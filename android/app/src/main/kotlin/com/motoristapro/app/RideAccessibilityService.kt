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
            packageName.contains("indriver") || packageName.contains("indrive") -> "inDrive"
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
                        val offer = ScreenOfferParser.parse(recognized.text)
                        if (offer == null) RideOverlay.remove(this@RideAccessibilityService) else showOffer(platform, offer)
                    }
                    .addOnCompleteListener { bitmap.recycle(); scanning = false }
            }
            override fun onFailure(errorCode: Int) { scanning = false }
        })
    }

    private fun showOffer(platform: String, offer: ScreenOffer) {
        val signature = "$platform:${offer.fare}:${offer.distance}:${offer.minutes}"
        val now = System.currentTimeMillis()
        if (signature == lastSignature && now - lastShownAt < 30000) return
        lastSignature = signature
        lastShownAt = now
        val preferences = getSharedPreferences("ride_calculator", MODE_PRIVATE)
        RideOverlay.show(this, mapOf(
            "platform" to platform,
            "offerId" to signature,
            "fare" to offer.fare,
            "distance" to offer.distance,
            "minutes" to offer.minutes,
            "perKm" to offer.fare / offer.distance,
            "perHour" to offer.fare * 60.0 / offer.minutes,
            "yellow" to preferences.getFloat("yellow", 1.5f).toDouble(),
            "green" to preferences.getFloat("green", 2.0f).toDouble(),
            "theme" to preferences.getInt("theme", 0),
            "fontScale" to preferences.getFloat("fontScale", 1.0f).toDouble(),
            "cardScale" to preferences.getFloat("cardScale", 1.0f).toDouble()
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
        val fares = money.findAll(text).mapNotNull { decimal(it.groupValues[1]) }.filter { it in 3.0..999.0 }.distinct().toList()
        // Ambiguous screens are ignored: choosing the largest number would invent which value is the fare.
        if (fares.size != 1) return null
        val fare = fares.single()
        val distances = km.findAll(text).mapNotNull { decimal(it.groupValues[1]) }.filter { it in 0.1..500.0 }.toList()
        if (distances.isEmpty()) return null
        // Do not guess whether multiple distances mean pickup + trip. Only accept an unambiguous value.
        if (distances.distinct().size != 1) return null
        val distance = distances.single()
        val durationValues = min.findAll(text).mapNotNull { it.groupValues[1].toIntOrNull() }.filter { it in 1..600 }.toList()
        val hourValue = hourMinute.find(text)?.let {
            (it.groupValues[1].toIntOrNull() ?: 0) * 60 + (it.groupValues[2].toIntOrNull() ?: 0)
        }
        if (hourValue == null && durationValues.distinct().size != 1) return null
        val minutes = hourValue?.takeIf { it > 0 } ?: durationValues.singleOrNull() ?: return null
        return ScreenOffer(fare, distance, minutes)
    }

    private fun decimal(value: String): Double? {
        val normalized = if (value.contains(',')) value.replace(".", "").replace(',', '.') else value
        return normalized.toDoubleOrNull()
    }
}
