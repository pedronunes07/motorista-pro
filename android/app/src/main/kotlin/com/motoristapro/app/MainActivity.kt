package com.motoristapro.app

import android.content.Intent
import android.app.Activity
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val captureRequestCode = 9917
    private var pendingCaptureResult: MethodChannel.Result? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == captureRequestCode && resultCode == Activity.RESULT_OK && data != null) {
            val intent = Intent(this, ScreenCaptureService::class.java).apply {
                putExtra("resultCode", resultCode)
                putExtra("resultData", data)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
            window.decorView.postDelayed({
                pendingCaptureResult?.success(ScreenCaptureService.isRunning)
                pendingCaptureResult = null
            }, 700)
        } else if (requestCode == captureRequestCode) {
            pendingCaptureResult?.success(false)
            pendingCaptureResult = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "motorista_pro/overlay")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showRideOverlay" -> {
                        @Suppress("UNCHECKED_CAST")
                        RideOverlay.show(this, call.arguments as? Map<String, Any?> ?: emptyMap())
                        result.success(null)
                    }
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(null)
                    }
                    "openNotificationAccessSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "isAccessibilityEnabled" -> result.success(RideAccessibilityService.isRunning)
                    "isScreenCaptureActive" -> result.success(ScreenCaptureService.isRunning)
                    "getScreenCaptureError" -> result.success(ScreenCaptureService.lastError)
                    "getRiskSettings" -> result.success(mapOf("configured" to RouteRiskClient.configured(this), "enabled" to RouteRiskClient.enabled(this)))
                    "setRiskEnabled" -> {
                        val enabled = call.arguments == true && RouteRiskClient.configured(this)
                        getSharedPreferences("ride_calculator",MODE_PRIVATE).edit().putBoolean("riskEnabled",enabled).apply()
                        RideOverlay.updateStyle(this,emptyMap())
                        result.success(enabled)
                    }
                    "peekCompletedRides" -> try {
                        result.success(CompletedRideStore.peek(this))
                    } catch (_: Exception) { result.error("ride_storage", "Não foi possível ler as corridas salvas.", null) }
                    "acknowledgeCompletedRides" -> {
                        @Suppress("UNCHECKED_CAST")
                        try {
                            CompletedRideStore.acknowledge(this, call.arguments as? List<Map<String, Any?>> ?: emptyList())
                            result.success(true)
                        } catch (_: Exception) { result.error("ride_storage", "Não foi possível confirmar o salvamento.", null) }
                    }
                    "stopScreenCapture" -> {
                        stopService(Intent(this, ScreenCaptureService::class.java))
                        RideOverlay.remove(this)
                        result.success(true)
                    }
                    "getLastCrash" -> result.success(
                        getSharedPreferences("motorista_pro_diagnostics", MODE_PRIVATE)
                            .getString("last_crash", "")
                    )
                    "clearLastCrash" -> {
                        getSharedPreferences("motorista_pro_diagnostics", MODE_PRIVATE)
                            .edit().remove("last_crash").apply()
                        result.success(null)
                    }
                    "requestScreenCapture" -> {
                        if (pendingCaptureResult != null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        pendingCaptureResult = result
                        // Android bloqueia botões sensíveis quando existe uma janela flutuante
                        // sobre a tela. Fechamos qualquer cartão antes de pedir a captura.
                        RideOverlay.remove(this)
                        window.decorView.postDelayed({
                            val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                            startActivityForResult(manager.createScreenCaptureIntent(), captureRequestCode)
                        }, 400)
                    }
                    "configureCalculator" -> {
                        @Suppress("UNCHECKED_CAST")
                        val data = call.arguments as? Map<String, Any?> ?: emptyMap()
                        getSharedPreferences("ride_calculator", MODE_PRIVATE).edit()
                            .putFloat("yellow", (data["yellow"] as? Number)?.toFloat() ?: 1.5f)
                            .putFloat("green", (data["green"] as? Number)?.toFloat() ?: 2.0f)
                            .putFloat("ratingMinimum", (data["ratingMinimum"] as? Number)?.toFloat() ?: 4.8f)
                            .putInt("theme", (data["theme"] as? Number)?.toInt() ?: 0)
                            .putFloat("fontScale", (data["fontScale"] as? Number)?.toFloat() ?: 1f)
                            .putFloat("cardScale", (data["cardScale"] as? Number)?.toFloat() ?: 1f)
                            .apply()
                        RideOverlay.updateStyle(this, data)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
