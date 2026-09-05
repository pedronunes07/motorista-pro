package com.motoristapro.app

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
    private var generation = 0L
    private val handler = Handler(Looper.getMainLooper())

    fun show(context: Context, data: Map<String, Any?>) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(context)) return
        handler.post {
            remove(context)
            val currentGeneration = ++generation
            val perKm = number(data["perKm"])
            val yellow = number(data["yellow"], 1.5)
            val green = number(data["green"], 2.0)
            val theme = number(data["theme"]).toInt()
            val fontScale = number(data["fontScale"], 1.0).toFloat().coerceIn(.8f, 1.5f)
            val cardScale = number(data["cardScale"], 1.0).coerceIn(.8, 1.3)
            val metricColor = when {
                perKm >= green -> Color.rgb(22, 128, 60)
                perKm >= yellow -> Color.rgb(244, 180, 0)
                else -> Color.rgb(198, 40, 40)
            }
            val background = when (theme) { 1 -> Color.WHITE; 2 -> Color.rgb(28, 28, 30); else -> metricColor }
            val foreground = if (theme == 1) Color.BLACK else Color.WHITE
            val status = when {
                perKm >= green -> "ACIMA DA META"
                perKm >= yellow -> "FAIXA INTERMEDIÁRIA"
                else -> "ABAIXO DA META"
            }
            val box = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(context, (18 * cardScale).toInt()), dp(context, (12 * cardScale).toInt()), dp(context, (18 * cardScale).toInt()), dp(context, (12 * cardScale).toInt()))
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
            box.addView(label(context, "$platform · $status", 14f * fontScale, true, foreground))
            box.addView(label(context, "${money(number(data["fare"]))}  •  ${money(perKm)}/km", 24f * fontScale, true, foreground))
            box.addView(label(context, "$minutes min  •  ${format(distance)} km  •  ${money(perHour)}/h", 15f * fontScale, true, foreground))
            box.setOnClickListener { remove(context) }

            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE
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
                handler.postDelayed({ if (generation == currentGeneration) remove(context) }, 14000)
            } catch (_: Exception) { }
        }
    }

    fun remove(context: Context) {
        overlayView?.let {
            try { (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(it) } catch (_: Exception) { }
        }
        overlayView = null
        generation++
    }

    private fun label(context: Context, value: String, size: Float, bold: Boolean, color: Int) = TextView(context).apply {
        text = value
        textSize = size
        setTextColor(color)
        if (bold) setTypeface(typeface, Typeface.BOLD)
        setPadding(0, dp(context, 2), 0, dp(context, 2))
    }
    private fun number(value: Any?, fallback: Double = 0.0) = (value as? Number)?.toDouble() ?: fallback
    private fun money(value: Double) = NumberFormat.getCurrencyInstance(Locale("pt", "BR")).format(value)
    private fun format(value: Double) = String.format(Locale("pt", "BR"), "%.1f", value)
    private fun dp(context: Context, value: Int) = (value * context.resources.displayMetrics.density).toInt()
}
