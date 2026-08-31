package com.motoristapro.motorista_pro

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
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.text.NumberFormat
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val channelName = "motorista_pro/overlay"
    private var overlayView: View? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "showRideOverlay" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                        result.error("permission", "Autorize o Motorista Pro a aparecer sobre outros aplicativos.", null)
                    } else {
                        @Suppress("UNCHECKED_CAST")
                        showRideOverlay(call.arguments as? Map<String, Any?> ?: emptyMap())
                        result.success(null)
                    }
                }
                "closeRideOverlay" -> { removeOverlay(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    private fun showRideOverlay(data: Map<String, Any?>) {
        removeOverlay()
        val perKm = (data["perKm"] as? Number)?.toDouble() ?: 0.0
        val yellow = (data["yellow"] as? Number)?.toDouble() ?: 1.5
        val green = (data["green"] as? Number)?.toDouble() ?: 2.0
        val background = when {
            perKm >= green -> Color.rgb(22, 128, 60)
            perKm >= yellow -> Color.rgb(244, 180, 0)
            else -> Color.rgb(198, 40, 40)
        }
        val status = when {
            perKm >= green -> "ACIMA DA META"
            perKm >= yellow -> "FAIXA INTERMEDIÁRIA"
            else -> "ABAIXO DA META"
        }
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(14), dp(18), dp(14))
            this.background = GradientDrawable().apply { setColor(background); cornerRadius = dp(18).toFloat() }
            elevation = dp(10).toFloat()
        }
        val platform = data["platform"]?.toString() ?: "Corrida"
        box.addView(label("$platform · $status", 15f, true))
        box.addView(label(money((data["fare"] as? Number)?.toDouble() ?: 0.0), 30f, true))
        val distance = (data["distance"] as? Number)?.toDouble() ?: 0.0
        val minutes = (data["minutes"] as? Number)?.toInt() ?: 0
        val perHour = (data["perHour"] as? Number)?.toDouble() ?: 0.0
        box.addView(label(String.format(Locale("pt", "BR"), "%.1f km  •  %d min", distance, minutes), 15f, false))
        box.addView(label("${money(perKm)}/km  •  ${money(perHour)}/h", 16f, true))
        box.setOnClickListener { removeOverlay() }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply { gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL; y = dp(52); horizontalMargin = 0.03f }
        getSystemService(WINDOW_SERVICE).let { it as WindowManager }.addView(box, params)
        overlayView = box
        handler.postDelayed({ removeOverlay() }, 15000)
    }

    private fun label(text: String, size: Float, bold: Boolean) = TextView(this).apply {
        this.text = text
        textSize = size
        setTextColor(Color.WHITE)
        if (bold) setTypeface(typeface, Typeface.BOLD)
        setPadding(0, dp(2), 0, dp(2))
    }

    private fun money(value: Double): String = NumberFormat.getCurrencyInstance(Locale("pt", "BR")).format(value)
    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun removeOverlay() {
        handler.removeCallbacksAndMessages(null)
        overlayView?.let {
            try { (getSystemService(WINDOW_SERVICE) as WindowManager).removeView(it) } catch (_: Exception) {}
        }
        overlayView = null
    }

    override fun onDestroy() { removeOverlay(); super.onDestroy() }
}
