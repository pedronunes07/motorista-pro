package com.motoristapro.app

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
                    "isAccessibilityEnabled" -> result.success(RideAccessibilityService.isRunning)
                    "configureCalculator" -> {
                        @Suppress("UNCHECKED_CAST")
                        val data = call.arguments as? Map<String, Any?> ?: emptyMap()
                        getSharedPreferences("ride_calculator", MODE_PRIVATE).edit()
                            .putFloat("yellow", (data["yellow"] as? Number)?.toFloat() ?: 1.5f)
                            .putFloat("green", (data["green"] as? Number)?.toFloat() ?: 2.0f)
                            .apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
