package com.motoristapro.app

import android.accessibilityservice.AccessibilityService
import android.graphics.Bitmap
import android.os.Build
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.util.Locale
import java.util.concurrent.Executors

class RideAccessibilityService : AccessibilityService() {
    companion object { @Volatile var isRunning = false }

    private var lastSignature = ""
    private var lastShownAt = 0L
    private var lastScanAt = 0L
    private var scanning = false
    private val screenshotExecutor = Executors.newSingleThreadExecutor()
    private val recognizer by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }

    override fun onServiceConnected() { isRunning = true }
    override fun onUnbind(intent: android.content.Intent?): Boolean { isRunning = false; return super.onUnbind(intent) }
    override fun onInterrupt() = Unit

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val packageName = event?.packageName?.toString()?.lowercase(Locale.ROOT) ?: return
        val platform = when {
            packageName.contains("uber") -> "Uber"
            packageName.contains("taxis99") || packageName.contains("99") || packageName.contains("didi") -> "99"
            else -> return
        }
        val root = rootInActiveWindow ?: event.source ?: return
        val chunks = mutableListOf<String>()
        collectText(root, chunks)
        val text = chunks.distinct().joinToString(" | ")
        val offer = ScreenOfferParser.parse(text)
        if (offer == null) {
            scanScreenshot(platform)
            return
        }
        showOffer(platform, offer)
    }

    private fun scanScreenshot(platform: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || scanning) return
        val now = System.currentTimeMillis()
        if (now - lastScanAt < 900) return
        lastScanAt = now
        scanning = true
        takeScreenshot(Display.DEFAULT_DISPLAY, screenshotExecutor, object : TakeScreenshotCallback {
            override fun onSuccess(result: ScreenshotResult) {
                val bitmap = Bitmap.wrapHardwareBuffer(result.hardwareBuffer, result.colorSpace)?.copy(Bitmap.Config.ARGB_8888, false)
                result.hardwareBuffer.close()
                if (bitmap == null) { scanning = false; return }
                recognizer.process(InputImage.fromBitmap(bitmap, 0))
                    .addOnSuccessListener { recognized ->
                        ScreenOfferParser.parse(recognized.text)?.let { showOffer(platform, it) }
                    }
                    .addOnCompleteListener { bitmap.recycle(); scanning = false }
            }
            override fun onFailure(errorCode: Int) { scanning = false }
        })
    }

    private fun showOffer(platform: String, offer: ScreenOffer) {
        val signature = "$platform:${offer.fare}:${offer.distance}:${offer.minutes}"
        val now = System.currentTimeMillis()
        if (signature == lastSignature && now - lastShownAt < 12000) return
        lastSignature = signature
        lastShownAt = now
        val preferences = getSharedPreferences("ride_calculator", MODE_PRIVATE)
        RideOverlay.show(this, mapOf(
            "platform" to platform,
            "fare" to offer.fare,
            "distance" to offer.distance,
            "minutes" to offer.minutes,
            "perKm" to offer.fare / offer.distance,
            "perHour" to offer.fare * 60.0 / offer.minutes,
            "yellow" to preferences.getFloat("yellow", 1.5f).toDouble(),
            "green" to preferences.getFloat("green", 2.0f).toDouble()
        ))
    }

    override fun onDestroy() {
        isRunning = false
        recognizer.close()
        screenshotExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun collectText(node: AccessibilityNodeInfo, out: MutableList<String>) {
        node.text?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let(out::add)
        node.contentDescription?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let(out::add)
        for (index in 0 until node.childCount) node.getChild(index)?.let { collectText(it, out) }
    }
}

private data class ScreenOffer(val fare: Double, val distance: Double, val minutes: Int)

private object ScreenOfferParser {
    private val money = Regex("R\\$\\s*([0-9]{1,3}(?:[.]?[0-9]{3})*(?:[,][0-9]{1,2})?|[0-9]+(?:[.][0-9]{1,2})?)", RegexOption.IGNORE_CASE)
    private val km = Regex("([0-9]+(?:[.,][0-9]+)?)\\s*km", RegexOption.IGNORE_CASE)
    private val min = Regex("([0-9]+)\\s*(?:min|minutos?|m)(?![a-z])", RegexOption.IGNORE_CASE)
    private val hourMinute = Regex("([0-9]+)\\s*h(?:ora)?s?\\s*([0-9]+)\\s*m", RegexOption.IGNORE_CASE)

    fun parse(text: String): ScreenOffer? {
        val fare = money.findAll(text).mapNotNull { decimal(it.groupValues[1]) }.filter { it in 3.0..999.0 }.maxOrNull() ?: return null
        val distances = km.findAll(text).mapNotNull { decimal(it.groupValues[1]) }.filter { it in 0.1..500.0 }.toList()
        if (distances.isEmpty()) return null
        // A oferta pode exibir distância até o passageiro e distância da viagem. Somamos ambas.
        val distance = distances.take(2).sum()
        val durationValues = min.findAll(text).mapNotNull { it.groupValues[1].toIntOrNull() }.filter { it in 1..600 }.toList()
        val hourValue = hourMinute.find(text)?.let {
            (it.groupValues[1].toIntOrNull() ?: 0) * 60 + (it.groupValues[2].toIntOrNull() ?: 0)
        }
        val minutes = hourValue?.takeIf { it > 0 } ?: durationValues.take(2).sum().takeIf { it > 0 } ?: return null
        return ScreenOffer(fare, distance, minutes)
    }

    private fun decimal(value: String): Double? {
        val normalized = if (value.contains(',')) value.replace(".", "").replace(',', '.') else value
        return normalized.toDoubleOrNull()
    }
}
