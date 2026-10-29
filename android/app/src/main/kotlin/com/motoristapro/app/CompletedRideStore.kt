package com.motoristapro.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object CompletedRideStore {
    private const val PREFS = "completed_rides_native"
    private const val STATE = "ledger_v27"
    private var lastCommitted: String? = null
    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun nullableText(item: JSONObject, key: String): String? = item.optString(key).takeIf { it.isNotBlank() && it != "null" }
    private fun nullableNumber(item: JSONObject, key: String): Double? =
        if (item.isNull(key)) null else item.optDouble(key).takeIf { it.isFinite() && it >= 0 }

    private fun load(context: Context): RideLedger {
        // Parse errors must not silently erase the durable queue.
        val json = JSONObject(prefs(context).getString(STATE, "{}") ?: "{}")
        val ledger = RideLedger()
        val records = json.optJSONArray("records") ?: JSONArray()
        for (index in 0 until records.length()) {
            val r = records.getJSONObject(index)
            ledger.records.add(RideRecord(r.getString("id"), r.getString("platform"), r.getLong("timestamp"),
                nullableNumber(r,"value"), nullableNumber(r,"distance"), nullableText(r,"pickup"), nullableText(r,"destination"),
                r.optString("routeSource","unavailable"), nullableText(r,"reference"), r.optBoolean("conflict"),
                r.optInt("revision",1), r.optInt("acknowledged",0)))
        }
        fun contexts(key: String, target: MutableMap<String, TripContext>) {
            val array = json.optJSONArray(key) ?: JSONArray()
            for (i in 0 until array.length()) {
                val c = array.getJSONObject(i)
                val platform = c.getString("platform")
                target[platform] = TripContext(c.getString("id"), platform,
                    RideRoute(nullableText(c,"pickup"),nullableText(c,"destination")),c.getLong("at"),c.getString("key"))
            }
        }
        contexts("active",ledger.active); contexts("next",ledger.next); contexts("candidates",ledger.candidates)
        val screen = json.optJSONObject("screen") ?: JSONObject()
        screen.keys().forEach { ledger.receiptOnScreen[it] = screen.getString(it) }
        val seen = json.optJSONObject("seen") ?: JSONObject()
        seen.keys().forEach { ledger.receiptSeenAt[it] = seen.getLong(it) }
        return ledger
    }

    private fun recordJson(r: RideRecord) = JSONObject().put("id",r.id).put("platform",r.platform).put("timestamp",r.timestamp)
        .put("value",r.value ?: JSONObject.NULL).put("distance",r.distance ?: JSONObject.NULL)
        .put("pickup",r.pickup ?: JSONObject.NULL).put("destination",r.destination ?: JSONObject.NULL)
        .put("routeSource",r.routeSource).put("reference",r.reference ?: JSONObject.NULL)
        .put("conflict",r.conflict).put("revision",r.revision).put("acknowledged",r.acknowledged).put("verified",true)

    private fun save(context: Context, ledger: RideLedger) {
        fun contexts(items: Map<String,TripContext>) = JSONArray().apply { items.values.forEach { c ->
            put(JSONObject().put("id",c.id).put("platform",c.platform).put("at",c.at).put("key",c.key)
                .put("pickup",c.route.pickup ?: JSONObject.NULL).put("destination",c.route.destination ?: JSONObject.NULL))
        } }
        val json = JSONObject().put("records",JSONArray().apply { ledger.records.forEach { put(recordJson(it)) } })
            .put("active",contexts(ledger.active)).put("next",contexts(ledger.next)).put("candidates",contexts(ledger.candidates))
            .put("screen",JSONObject(ledger.receiptOnScreen.toMap()))
            .put("seen",JSONObject(ledger.receiptSeenAt.toMap()))
        val encoded = json.toString()
        // Accessibility can fire dozens of events a second. Avoid synchronous disk
        // writes when the trip/queue has not changed, which could stall detection.
        if (lastCommitted == encoded) return
        check(prefs(context).edit().putString(STATE,encoded).commit()) { "Não foi possível gravar a corrida." }
        lastCommitted = encoded
    }

    private inline fun update(context: Context, change: (RideLedger) -> Unit): Boolean = try {
        val ledger = load(context)
        change(ledger)
        save(context,ledger)
        true
    } catch (_: Exception) {
        // Keep the stored queue intact; never replace unreadable data with an empty history.
        ScreenCaptureService.lastError = "Não foi possível salvar a corrida. Abra o Motorista Pro e tente sincronizar novamente."
        false
    }

    @Synchronized fun rememberOffer(context: Context, platform: String, offer: ScreenOffer) =
        update(context) { it.offer(platform,offer,System.currentTimeMillis()) }

    @Synchronized fun acceptLatestOffer(context: Context, platform: String): Boolean {
        var accepted = false
        val saved = update(context) { accepted = it.accept(platform,System.currentTimeMillis()) }
        return saved && accepted
    }
    @Synchronized fun confirmRideStarted(context: Context, platform: String) =
        update(context) { it.started(platform,System.currentTimeMillis()) }

    @Synchronized fun acceptUnknown(context: Context, platform: String) =
        update(context) { it.acceptUnknown(platform,System.currentTimeMillis()) }

    @Synchronized fun discardCandidate(context: Context, platform: String) =
        update(context) { it.candidates.remove(platform) }

    @Synchronized fun observe(context: Context, platform: String, text: String) {
        val receipt = RideReceiptParser.parse(text)
        val saved = update(context) { ledger ->
            if (receipt == null) ledger.noReceipt(platform,System.currentTimeMillis())
            else ledger.receipt(platform,receipt,System.currentTimeMillis())
        }
        if (saved && receipt != null) RideOverlay.dismissCurrent(context)
    }
    @Synchronized fun peek(context: Context): List<Map<String, Any?>> {
        val result = load(context).pending().map { r ->
            val json = recordJson(r)
            json.keys().asSequence().associateWith { key -> json.get(key).takeUnless { it == JSONObject.NULL } }
        }.toMutableList()
        // Keep v26 pending items visible for review, without declaring their old values verified.
        val old = JSONArray(prefs(context).getString("pending","[]") ?: "[]")
        for (i in 0 until old.length()) {
            val item = old.getJSONObject(i)
            result.add(mapOf("id" to item.getString("id"), "platform" to item.getString("platform"),
                "timestamp" to item.getLong("timestamp"), "value" to nullableNumber(item,"value"),
                "distance" to nullableNumber(item,"distance"), "verified" to false, "revision" to 1))
        }
        return result
    }
    @Synchronized fun acknowledge(context: Context, acknowledgements: List<Map<String, Any?>>) {
        val ledger = load(context)
        acknowledgements.forEach { ack ->
            ledger.acknowledge(ack["id"].toString(),(ack["revision"] as? Number)?.toInt() ?: 0)
        }
        save(context,ledger)
        val old = JSONArray(prefs(context).getString("pending","[]") ?: "[]")
        val kept = JSONArray()
        for (i in 0 until old.length()) {
            val item = old.getJSONObject(i)
            if (acknowledgements.none { it["id"] == item.getString("id") }) kept.put(item)
        }
        check(prefs(context).edit().putString("pending",kept.toString()).commit())
    }
}
