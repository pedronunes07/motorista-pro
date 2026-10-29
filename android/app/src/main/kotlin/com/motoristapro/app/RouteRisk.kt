package com.motoristapro.app

import java.net.URI

data class RiskEvidence(val address: String, val country: String, val source: String, val url: String, val updatedAt: Long, val expiresAt: Long, val alert: Boolean)

object RouteRisk {
    const val MAX_AGE = 30L * 24 * 60 * 60 * 1000
    fun accepts(query: String, evidence: RiskEvidence, now: Long): Boolean {
        val uri = try { URI(evidence.url) } catch (_: Exception) { return false }
        return query.isNotBlank() && RideReceiptParser.normalized(query) == RideReceiptParser.normalized(evidence.address) &&
            evidence.country == "BR" && evidence.source.isNotBlank() && evidence.source.length <= 120 &&
            uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo == null &&
            evidence.updatedAt <= now && now - evidence.updatedAt <= MAX_AGE &&
            evidence.expiresAt > now && evidence.expiresAt - evidence.updatedAt <= MAX_AGE
    }
}
