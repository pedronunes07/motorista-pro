package com.motoristapro.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import java.net.URL
import java.util.concurrent.Executors
import javax.net.ssl.HttpsURLConnection

/** No keys in the APK; a configured backend must supply dated, address-matched evidence. */
object RouteRiskClient {
    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val cache = linkedMapOf<String, Pair<Long,String>>()
    fun configured(context: Context) = context.getString(com.motoristapro.app.R.string.route_risk_endpoint).startsWith("https://")
    fun enabled(context: Context) = context.getSharedPreferences("ride_calculator",Context.MODE_PRIVATE).getBoolean("riskEnabled",false)

    fun check(context: Context, pickup: String?, destination: String?, callback: (String) -> Unit) {
        if (!enabled(context)) return
        val app = context.applicationContext
        if (!configured(app)) { callback("Áreas de atenção: fonte ainda não conectada"); return }
        if (pickup.isNullOrBlank() && destination.isNullOrBlank()) { callback("Áreas de atenção: endereços não identificados"); return }
        val key = "$pickup|$destination"
        executor.execute {
            val now = System.currentTimeMillis()
            val cached = cache[key]?.takeIf { now - it.first < 60_000 }
            val message = cached?.second ?: lookup(app,pickup,destination,now)
            cache[key] = now to message
            while(cache.size > 30) cache.remove(cache.keys.first())
            handler.post { if (enabled(app)) callback(message) }
        }
    }

    private fun lookup(context: Context, pickup: String?, destination: String?, now: Long): String {
        var connection: HttpsURLConnection? = null
        return try {
            connection = URL(context.getString(com.motoristapro.app.R.string.route_risk_endpoint)).openConnection() as HttpsURLConnection
            connection.connectTimeout = 2500; connection.readTimeout = 3500; connection.instanceFollowRedirects = false
            connection.requestMethod = "POST"; connection.doOutput = true
            connection.setRequestProperty("Content-Type","application/json")
            val request = JSONObject().put("country","BR").put("pickup",pickup ?: JSONObject.NULL).put("destination",destination ?: JSONObject.NULL)
            connection.outputStream.use { it.write(request.toString().toByteArray(Charsets.UTF_8)) }
            if(connection.responseCode != 200) return "Áreas de atenção: consulta indisponível"
            val response = connection.inputStream.use { stream ->
                val bytes = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(2048)
                while(true) { val size = stream.read(buffer); if(size < 0) break; bytes.write(buffer,0,size); if(bytes.size() > 16384) error("Resposta excedeu o limite") }
                JSONObject(bytes.toString("UTF-8"))
            }
            val messages = listOf("pickup" to pickup,"destination" to destination).map { (field,address) ->
                val title = if(field=="pickup") "Embarque" else "Desembarque"
                val item = response.optJSONObject(field)
                if (address == null || item == null || item.optString("status") != "alert") "$title: sem dados de risco confirmados"
                else {
                    val evidence = RiskEvidence(item.optString("matchedAddress"),item.optString("country"),item.optString("sourceName"),item.optString("sourceUrl"),item.optLong("updatedAt"),item.optLong("expiresAt"),true)
                    if(!RouteRisk.accepts(address,evidence,now)) "$title: sem dados de risco confirmados"
                    else {
                        val date = java.text.SimpleDateFormat("dd/MM/yyyy",java.util.Locale("pt","BR")).format(java.util.Date(evidence.updatedAt))
                        "⚠ $title: alerta na fonte ${evidence.source} ($date)"
                    }
                }
            }
            messages.joinToString("\n") + "\nAusência de alerta não indica local seguro."
        } catch (_: Exception) { "Áreas de atenção: consulta indisponível" }
        finally { connection?.disconnect() }
    }
}
