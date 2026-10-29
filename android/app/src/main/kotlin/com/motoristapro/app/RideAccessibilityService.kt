package com.motoristapro.app

import android.accessibilityservice.AccessibilityService
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.util.Locale
import java.util.concurrent.Executors

class RideAccessibilityService : AccessibilityService() {
    companion object {
        @Volatile var isRunning = false
        @Volatile var currentPlatform: String? = null
        @Volatile var instance: RideAccessibilityService? = null
    }

    private var lastScanAt = 0L
    private var scanning = false
    private var activePlatform: String? = null
    private var activePlatformAt = 0L
    private var scanUntil = 0L
    private val mainHandler = Handler(Looper.getMainLooper())
    private val scanLoop = object : Runnable {
        override fun run() {
            val platform = activePlatform ?: return
            if (System.currentTimeMillis() > scanUntil) return
            scanCurrentWindow(platform)
            mainHandler.postDelayed(this, 1800)
        }
    }

    private fun scanCurrentWindow(platform: String) {
        val root = rootInActiveWindow
        if (ScreenOfferParser.platformForPackage(root?.packageName?.toString()) != platform) return
        if (root != null) {
            val chunks = mutableListOf<String>()
            collectText(root, chunks)
            val visibleText = chunks.joinToString("\n")
            if (ScreenOfferParser.isActiveRide(visibleText)) {
                CompletedRideStore.confirmRideStarted(this, platform)
            }
            CompletedRideStore.observe(this, platform, visibleText)
            // A lista de espera pode conter várias ofertas. Procure primeiro
            // dentro de cada cartão para não misturar valores de corridas
            // diferentes; use a tela inteira apenas como alternativa.
            val offer = findOfferInTree(root) ?: ScreenOfferParser.parse(visibleText)
            if (offer != null) {
                showOffer(platform, offer)
                return
            }
        }
        RideOverlay.reportOfferMissing(this)
        scanScreenshot(platform)
    }
    private val screenshotExecutor = Executors.newSingleThreadExecutor()
    private val recognizer by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }

    override fun onServiceConnected() { isRunning = true; instance = this }
    override fun onUnbind(intent: android.content.Intent?): Boolean { isRunning = false; if (instance === this) instance = null; return super.onUnbind(intent) }
    override fun onInterrupt() = Unit

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val packageName = (event?.packageName?.toString()
            ?: rootInActiveWindow?.packageName?.toString())?.lowercase(Locale.ROOT) ?: return
        val platform = ScreenOfferParser.platformForPackage(packageName) ?: run {
            val foreground = foregroundPlatform()
            if (foreground == null) {
                activePlatform = null
                currentPlatform = null
                mainHandler.removeCallbacks(scanLoop)
                RideOverlay.reportOfferMissing(this)
            }
            return
        }
        activePlatform = platform
        activePlatformAt = System.currentTimeMillis()
        currentPlatform = platform
        scanUntil = Long.MAX_VALUE
        mainHandler.removeCallbacks(scanLoop)
        mainHandler.post(scanLoop)
        if (event?.eventType == AccessibilityEvent.TYPE_VIEW_CLICKED) {
            // Primeiro tenta ler o conteúdo ainda presente no evento do toque;
            // depois relê a janela durante a animação da oferta da 99.
            event.source?.let { source ->
                val clickedChunks = mutableListOf<String>()
                collectText(source, clickedChunks)
                val clickedText = clickedChunks.joinToString(" | ").lowercase(Locale.ROOT)
                if ((clickedText.contains("aceitar") || clickedText.contains("aceite")) && !clickedText.contains("não aceitar") && !clickedText.contains("nao aceitar")) {
                    // Vincule a corrida aceita aos valores do cartão tocado,
                    // nunca a outra oferta que esteja visível na fila.
                    val accepted = findOfferAround(source)
                    if (accepted != null) {
                        CompletedRideStore.rememberOffer(this, platform, accepted)
                        showOffer(platform, accepted)
                        CompletedRideStore.acceptLatestOffer(this, platform)
                    } else {
                        CompletedRideStore.acceptUnknown(this,platform)
                    }
                    RideOverlay.dismissCurrent(this)
                } else if (listOf("recusar", "rejeitar", "não aceitar", "nao aceitar", "dispensar", "fechar").any(clickedText::contains)) {
                    CompletedRideStore.discardCandidate(this, platform)
                    RideOverlay.dismissCurrent(this)
                }
                if (!clickedText.contains("aceitar") && !clickedText.contains("aceite"))
                    ScreenOfferParser.parse(clickedChunks.joinToString("\n"))?.let { showOffer(platform, it) }
            }
            mainHandler.postDelayed({ scanCurrentWindow(platform) }, 250)
            mainHandler.postDelayed({ scanCurrentWindow(platform) }, 700)
            mainHandler.postDelayed({ scanCurrentWindow(platform) }, 1500)
        }
        val root = rootInActiveWindow ?: event?.source ?: return
        if (ScreenOfferParser.platformForPackage(root.packageName?.toString()) != platform) return
        val chunks = mutableListOf<String>()
        collectText(root, chunks)
        val text = chunks.joinToString("\n")
        if (ScreenOfferParser.isActiveRide(text)) {
            CompletedRideStore.confirmRideStarted(this, platform)
        }
        CompletedRideStore.observe(this, platform, text)
        val offer = findOfferInTree(root) ?: ScreenOfferParser.parse(text)
        if (offer == null) {
            RideOverlay.reportOfferMissing(this)
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
                        if (foregroundPlatform() != platform) return@addOnSuccessListener
                        if (ScreenOfferParser.isActiveRide(recognized.text)) {
                            CompletedRideStore.confirmRideStarted(this@RideAccessibilityService, platform)
                        }
                        CompletedRideStore.observe(this@RideAccessibilityService, platform, recognized.text)
                        val cardText = recognized.textBlocks.filter { block ->
                            val box = block.boundingBox
                            box != null && box.centerY() > bitmap.height * 0.20 && box.bottom < bitmap.height * 0.98
                        }.joinToString("\n") { it.text }
                        val recognizedOffer = ScreenOfferParser.parse(cardText) ?: ScreenOfferParser.parse(recognized.text)
                        if (recognizedOffer == null) RideOverlay.reportOfferMissing(this@RideAccessibilityService)
                        else showOffer(platform, recognizedOffer)
                    }
                    .addOnCompleteListener { bitmap.recycle(); scanning = false }
            }
            override fun onFailure(errorCode: Int) { scanning = false }
        })
    }

    private fun showOffer(platform: String, offer: ScreenOffer) {
        CompletedRideStore.rememberOffer(this, platform, offer)
        val preferences = getSharedPreferences("ride_calculator", MODE_PRIVATE)
        RideOverlay.show(this, mapOf(
            "platform" to platform,
            "fare" to offer.fare,
            "distance" to offer.distance,
            "minutes" to offer.minutes,
            "perKm" to offer.fare / offer.distance,
            "perHour" to offer.fare * 60.0 / offer.minutes,
            "yellow" to preferences.getFloat("yellow", 1.5f).toDouble(),
            "green" to preferences.getFloat("green", 2.0f).toDouble(),
            "pickup" to offer.route.pickup, "destination" to offer.route.destination,
            "rating" to offer.rating,
            "ratingMinimum" to preferences.getFloat("ratingMinimum", 4.8f).toDouble(),
            "theme" to preferences.getInt("theme",0), "fontScale" to preferences.getFloat("fontScale",1f).toDouble(), "cardScale" to preferences.getFloat("cardScale",1f).toDouble()
        ))
    }

    fun foregroundPlatform(): String? = ScreenOfferParser.platformForPackage(rootInActiveWindow?.packageName?.toString())

    fun showCapturedOffer(platform: String, offer: ScreenOffer) {
        currentPlatform = platform
        showOffer(platform, offer)
    }

    override fun onDestroy() {
        isRunning = false
        if (instance === this) instance = null
        mainHandler.removeCallbacks(scanLoop)
        recognizer.close()
        screenshotExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun collectText(node: AccessibilityNodeInfo, out: MutableList<String>) {
        node.text?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let(out::add)
        node.contentDescription?.toString()?.trim()?.takeIf { it.isNotEmpty() && it != node.text?.toString()?.trim() }?.let(out::add)
        for (index in 0 until node.childCount) node.getChild(index)?.let { collectText(it, out) }
    }

    private fun findOfferInTree(node: AccessibilityNodeInfo): ScreenOffer? {
        val chunks = mutableListOf<String>()
        collectText(node, chunks)
        for (index in 0 until node.childCount) {
            node.getChild(index)?.let { child ->
                findOfferInTree(child)?.let { return it }
            }
        }
        return ScreenOfferParser.parse(chunks.joinToString("\n"))
    }

    private fun findOfferAround(source: AccessibilityNodeInfo): ScreenOffer? {
        var node: AccessibilityNodeInfo? = source
        repeat(6) {
            val current = node ?: return null
            val chunks = mutableListOf<String>()
            collectText(current, chunks)
            ScreenOfferParser.parse(chunks.joinToString("\n"))?.let { return it }
            node = current.parent
        }
        return null
    }
}
