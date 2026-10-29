package com.motoristapro.app

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import java.text.NumberFormat
import java.util.Locale

object RideOverlay {
    private var overlayView: View? = null
    private var lastOfferId: String? = null
    private var lastShownAt = 0L
    private var generation = 0L
    private var activeData: Map<String, Any?>? = null
    private var lastSeenAt = 0L
    private var dismissedOfferId: String? = null
    private var dismissedUntil = 0L
    private val handler = Handler(Looper.getMainLooper())

    fun show(context: Context, data: Map<String, Any?>) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(context)) return
        handler.post {
            val offerId = "${data["platform"]}:${data["fare"]}:${data["distance"]}:${data["minutes"]}:${data["pickup"]}:${data["destination"]}"
            val now = System.currentTimeMillis()
            if (offerId == dismissedOfferId && now < dismissedUntil) return@post
            if (offerId != dismissedOfferId) dismissedUntil = 0L
            lastSeenAt = now
            if (offerId == lastOfferId && now - lastShownAt < 30000 && overlayView != null) return@post
            remove(context)
            activeData = HashMap(data)
            lastOfferId = offerId
            lastShownAt = now
            ++generation
            val perKm = number(data["perKm"])
            val yellow = number(data["yellow"], 1.5)
            val green = number(data["green"], 2.0)
            val theme=number(data["theme"]).toInt(); val fontScale=number(data["fontScale"],1.0).toFloat(); val cardScale=number(data["cardScale"],1.0)
            val metricColor = when {
                perKm >= green -> Color.rgb(22, 128, 60)
                perKm >= yellow -> Color.rgb(244, 180, 0)
                else -> Color.rgb(198, 40, 40)
            }
            val background=when(theme){1->Color.WHITE;2->Color.rgb(28,28,30);else->metricColor}; val foreground=if(theme==1)Color.BLACK else Color.WHITE
            val status = when {
                perKm >= green -> "ACIMA DA META"
                perKm >= yellow -> "FAIXA INTERMEDIÁRIA"
                else -> "ABAIXO DA META"
            }
            val box = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(context,(18*cardScale).toInt()),dp(context,(12*cardScale).toInt()),dp(context,(18*cardScale).toInt()),dp(context,(12*cardScale).toInt()))
                this.background = GradientDrawable().apply {
                    setColor(background)
                    cornerRadius = dp(context, 18).toFloat()
                    setStroke(dp(context, 3), metricColor)
                }
                elevation = dp(context, 10).toFloat()
            }
            val platform = data["platform"]?.toString() ?: "Corrida"
            val distance = number(data["distance"])
            val minutes = number(data["minutes"]).toInt()
            val perHour = number(data["perHour"])
            val rating = (data["rating"] as? Number)?.toDouble()
            val ratingMinimum = number(data["ratingMinimum"], 4.8)
            box.addView(label(context,"$platform · $status",14f*fontScale,true,foreground)); box.addView(label(context,"${money(number(data["fare"]))}  •  ${money(perKm)}/km",24f*fontScale,true,foreground)); box.addView(label(context,"$minutes min  •  ${format(distance)} km  •  ${money(perHour)}/h",15f*fontScale,true,foreground))
            if (rating != null && rating in 1.0..5.0) {
                box.addView(ratingLabel(context, rating, ratingMinimum))
            }
            if (RouteRiskClient.enabled(context)) {
                val risk = label(context,"Áreas de atenção: consultando…",12f*fontScale,false,foreground)
                box.addView(risk)
                val requestGeneration = generation
                RouteRiskClient.check(context,data["pickup"] as? String,data["destination"] as? String) { message ->
                    if (generation == requestGeneration && lastOfferId == offerId && overlayView === box) risk.text = message
                }
            }
            box.setOnClickListener { remove(context) }

            // A 99 pode ocultar sobreposições comuns. Quando o cartão é criado
            // pelo serviço de acessibilidade, use o tipo próprio do serviço,
            // que também é o tipo correto para acompanhar a oferta na tela.
            val type = when {
                context is AccessibilityService -> WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else -> WindowManager.LayoutParams.TYPE_PHONE
            }
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                y = dp(context, 58)
                horizontalMargin = 0.025f
            }
            try {
                (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).addView(box, params)
                overlayView = box
            } catch (_: Exception) { }
        }
    }

    fun remove(context: Context) {
        overlayView?.let {
            try { (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(it) } catch (_: Exception) { }
        }
        overlayView = null
        activeData = null
        generation++
    }

    /** Fecha a oferta atual e impede que um último quadro antigo do OCR a reabra. */
    fun dismissCurrent(context: Context) {
        handler.post {
            dismissedOfferId = lastOfferId
            // Bloqueia apenas os últimos quadros do cartão antigo. Uma nova
            // oferta legítima, inclusive com o mesmo valor, não pode ficar
            // dez segundos sem aparecer.
            dismissedUntil = System.currentTimeMillis() + 2500L
            remove(context)
        }
    }

    /**
     * A 99 anima o cartão e pode deixá-lo ilegível por alguns quadros. Espere
     * três leituras aproximadamente antes de fechar, mas nunca mantenha uma
     * oferta que realmente saiu da tela.
     */
    fun reportOfferMissing(context: Context) {
        val observedAt = lastSeenAt
        handler.postDelayed({
            if (overlayView != null && lastSeenAt == observedAt &&
                System.currentTimeMillis() - lastSeenAt >= 3200L) {
                dismissCurrent(context)
            }
        }, 3300L)
    }

    fun updateStyle(context: Context, style: Map<String, Any?>) {
        handler.post {
            val current = activeData?.toMutableMap() ?: return@post
            current.putAll(style)
            lastOfferId = null
            show(context, current)
        }
    }

    private fun label(context: Context, value: String, size: Float, bold: Boolean, color:Int) = TextView(context).apply {
        text = value
        textSize = size
        setTextColor(color)
        if (bold) setTypeface(typeface, Typeface.BOLD)
        setPadding(0, dp(context, 2), 0, dp(context, 2))
    }
    private fun ratingLabel(context: Context, rating: Double, minimum: Double) = TextView(context).apply {
        text = "★ Nota do passageiro: ${String.format(Locale("pt", "BR"), "%.2f", rating)}"
        textSize = 15f
        setTextColor(if (rating >= minimum) Color.rgb(22, 128, 60) else Color.rgb(198, 40, 40))
        setTypeface(typeface, Typeface.BOLD)
        setPadding(dp(context, 9), dp(context, 5), dp(context, 9), dp(context, 5))
        background = GradientDrawable().apply { setColor(Color.WHITE); cornerRadius = dp(context, 8).toFloat() }
    }
    private fun number(value: Any?, fallback: Double = 0.0) = (value as? Number)?.toDouble() ?: fallback
    private fun money(value: Double) = NumberFormat.getCurrencyInstance(Locale("pt", "BR")).format(value)
    private fun format(value: Double) = String.format(Locale("pt", "BR"), "%.1f", value)
    private fun dp(context: Context, value: Int) = (value * context.resources.displayMetrics.density).toInt()
}
