package com.motoristapro.app

import java.util.UUID

data class RideRecord(
    val id: String, val platform: String, val timestamp: Long,
    val value: Double?, val distance: Double?, val pickup: String?, val destination: String?,
    val routeSource: String, val reference: String?, val conflict: Boolean = false,
    val revision: Int = 1, val acknowledged: Int = 0
)
data class TripContext(val id: String, val platform: String, val route: RideRoute, val at: Long, val key: String)

/** Serializable, Android-free state machine shared by OCR and accessibility. */
class RideLedger(
    val records: MutableList<RideRecord> = mutableListOf(),
    val active: MutableMap<String, TripContext> = mutableMapOf(),
    val next: MutableMap<String, TripContext> = mutableMapOf(),
    val candidates: MutableMap<String, TripContext> = mutableMapOf(),
    val receiptOnScreen: MutableMap<String, String> = mutableMapOf(),
    val receiptSeenAt: MutableMap<String, Long> = mutableMapOf()
) {
    fun noReceipt(platform: String, now: Long) {
        val seen = receiptSeenAt[platform] ?: return
        if (now - seen > 5000) receiptOnScreen.remove(platform)
    }
    fun offer(platform: String, offer: ScreenOffer, now: Long) {
        val key = "${offer.fare}|${offer.distance}|${offer.minutes}|${offer.route}"
        val previous = candidates[platform]
        if (previous?.key == key && now - previous.at in 0..15_000L) return
        candidates[platform] = TripContext(previous?.takeIf { it.key == key }?.id ?: UUID.randomUUID().toString(), platform, offer.route, now, key)
    }

    fun accept(platform: String, now: Long): Boolean {
        val candidate = candidates[platform]?.takeIf { now - it.at in 0..120_000L } ?: return false
        val current = active[platform]?.takeIf { now - it.at in 0..21_600_000L }
        if (current?.id == candidate.id || next[platform]?.id == candidate.id) return true
        if (current == null) active[platform] = candidate else next[platform] = candidate
        return true
    }

    fun acceptUnknown(platform: String, now: Long) {
        val context = TripContext(UUID.randomUUID().toString(),platform,RideRoute(),now,"unread-accepted-offer")
        if (active[platform]?.let { now - it.at in 0..21_600_000L } == true) next[platform] = context
        else active[platform] = context
    }

    fun started(platform: String, now: Long) {
        if (active[platform]?.let { now - it.at in 0..21_600_000L } != true) {
            active.remove(platform)
            val queued = next.remove(platform)?.takeIf { now - it.at in 0..7_200_000L }
            if (queued != null) active[platform] = queued
            else {
                // An active screen proves a trip is underway, but does not prove which
                // unaccepted candidate it came from. Never borrow that candidate's route.
                active[platform] = TripContext(UUID.randomUUID().toString(),platform,RideRoute(),now,"observed-start")
            }
        }
        if (active.containsKey(platform)) receiptOnScreen.remove(platform)
    }

    fun receipt(platform: String, receipt: RideReceipt, now: Long): RideRecord {
        val context = active[platform]?.takeIf { now - it.at in 0..21_600_000L }
        val byReference = receipt.reference?.let { ref -> records.find { it.platform == platform && it.reference == ref } }
        val onScreen = records.find { it.id == receiptOnScreen[platform] }
            ?.takeIf { context == null && (receipt.reference == null || it.reference == null || it.reference == receipt.reference) }
        // Fallback without a trip ID must never create a stream of duplicate receipts.
        val duplicate = if (context == null && receipt.reference == null) records.lastOrNull {
            it.platform == platform && now - it.timestamp in 0..86_400_000L &&
                receipt.fare != null && it.value == receipt.fare && it.distance == receipt.distance &&
                it.pickup == receipt.route.pickup && it.destination == receipt.route.destination
        } else null
        val previous = byReference ?: onScreen ?: records.find { it.id == context?.id } ?: duplicate
        val valueConflict = previous?.conflict == true || (previous?.value != null && receipt.fare != null && previous.value != receipt.fare)
        val distanceConflict = previous?.distance != null && receipt.distance != null && previous.distance != receipt.distance
        val receiptRoute = receipt.route.pickup != null || receipt.route.destination != null
        val matchingContext = context?.takeIf { previous == null || previous.id == it.id }
        val record = RideRecord(
            id = previous?.id ?: context?.id ?: UUID.randomUUID().toString(),
            platform = platform, timestamp = previous?.timestamp ?: now,
            value = if (valueConflict) null else receipt.fare ?: previous?.value,
            distance = if (distanceConflict) null else receipt.distance ?: previous?.distance,
            pickup = receipt.route.pickup ?: previous?.pickup ?: matchingContext?.route?.pickup,
            destination = receipt.route.destination ?: previous?.destination ?: matchingContext?.route?.destination,
            routeSource = if (receipt.route.pickup != null && receipt.route.destination != null) "receipt"
                else previous?.routeSource ?: if (matchingContext != null) "accepted_offer" else if (receiptRoute) "receipt" else "unavailable",
            reference = receipt.reference ?: previous?.reference,
            conflict = valueConflict || distanceConflict,
            revision = previous?.revision ?: 1, acknowledged = previous?.acknowledged ?: 0
        )
        val updated = if (previous != null && record != previous) record.copy(revision = previous.revision + 1) else record
        if (previous != null) records[records.indexOf(previous)] = updated else records.add(updated)
        receiptOnScreen[platform] = updated.id
        if (now - (receiptSeenAt[platform] ?: 0L) >= 1000L) receiptSeenAt[platform] = now
        // A queued offer only becomes active after an observed start, never on another receipt frame.
        if (context != null && (previous == null || previous.id == context.id)) {
            active.remove(platform)
            candidates.remove(platform)
        }
        return updated
    }

    fun pending(): List<RideRecord> = records.filter { it.revision > it.acknowledged }
    fun acknowledge(id: String, revision: Int) {
        val index = records.indexOfFirst { it.id == id }
        if (index >= 0) {
            val record = records[index]
            // An acknowledgement of an older snapshot cannot delete a later OCR enrichment.
            records[index] = record.copy(acknowledged = maxOf(record.acknowledged, minOf(revision, record.revision)))
        }
    }
}
