package com.motoristapro.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Notification
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

class ScreenCaptureService : Service() {
    companion object {
        @Volatile var isRunning = false
        @Volatile var lastError = ""
    }

    private val recognizer by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }
    private var projection: MediaProjection? = null
    private var reader: ImageReader? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var scanning = false
    private var lastScan = 0L
    private lateinit var worker: HandlerThread
    private lateinit var handler: Handler

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return try {
            startCapture(intent)
        } catch (error: Throwable) {
            isRunning = false
            lastError = "${error.javaClass.simpleName}: ${error.message ?: "falha ao iniciar a captura"}"
            stopSelf()
            START_NOT_STICKY
        }
    }

    private fun startCapture(intent: Intent?): Int {
        lastError = ""
        createChannel()
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, "ride_capture") else Notification.Builder(this)
        val notification = builder
            // Ícones adaptáveis de launcher não são aceitos como smallIcon em
            // alguns aparelhos Samsung com Android 10 e causam
            // RemoteServiceException: Bad notification for startForeground.
            .setSmallIcon(R.drawable.ic_stat_driver)
            .setContentTitle("Motorista Pro ativo")
            .setContentText("Lendo ofertas da 99 e Uber")
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(92, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else startForeground(92, notification)

        if (!::worker.isInitialized) {
            worker = HandlerThread("ride-screen-capture").also { it.start() }
            handler = Handler(worker.looper)
        }
        if (projection == null) {
            val code = intent?.getIntExtra("resultCode", 0) ?: 0
            @Suppress("DEPRECATION")
            val data = if (Build.VERSION.SDK_INT >= 33) intent?.getParcelableExtra("resultData", Intent::class.java)
                else intent?.getParcelableExtra("resultData")
            if (code == 0 || data == null) { stopSelf(); return START_NOT_STICKY }
            val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            projection = manager.getMediaProjection(code, data)
            projection?.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() { stopSelf() }
            }, handler)
            startReader()
        }
        isRunning = true
        return START_NOT_STICKY
    }

    private fun startReader() {
        val metrics = resources.displayMetrics
        // Telefones mais antigos podem encerrar o processo ao analisar capturas em
        // resolução total continuamente. Metade da resolução mantém os números
        // legíveis para o OCR e reduz o consumo de memória para cerca de 1/4.
        val captureWidth = (metrics.widthPixels / 2).coerceAtLeast(360)
        val captureHeight = (metrics.heightPixels.toLong() * captureWidth / metrics.widthPixels).toInt()
        val captureDensity = (metrics.densityDpi * captureWidth / metrics.widthPixels).coerceAtLeast(120)
        reader = ImageReader.newInstance(captureWidth, captureHeight, PixelFormat.RGBA_8888, 2)
        virtualDisplay?.release()
        virtualDisplay = projection?.createVirtualDisplay(
            "MotoristaProCapture", captureWidth, captureHeight, captureDensity,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, reader?.surface, null, handler
        )
        reader?.setOnImageAvailableListener({ source ->
            var captured: android.media.Image? = null
            try {
                val now = System.currentTimeMillis()
                val image = source.acquireLatestImage() ?: return@setOnImageAvailableListener
                captured = image
                if (scanning || now - lastScan < 2200) {
                    image.close()
                    return@setOnImageAvailableListener
                }
                lastScan = now
                val plane = image.planes.firstOrNull() ?: run {
                    image.close()
                    return@setOnImageAvailableListener
                }
                val width = image.width
                val height = image.height
                val pixelStride = plane.pixelStride.coerceAtLeast(1)
                val rowPadding = (plane.rowStride - pixelStride * width).coerceAtLeast(0)
                val bitmap = Bitmap.createBitmap(width + rowPadding / pixelStride, height, Bitmap.Config.ARGB_8888)
                bitmap.copyPixelsFromBuffer(plane.buffer)
                image.close()
                captured = null
                val cropped = Bitmap.createBitmap(bitmap, 0, 0, width, height)
                bitmap.recycle()
                scanning = true
                val framePlatform = RideAccessibilityService.instance?.foregroundPlatform()
                recognizer.process(InputImage.fromBitmap(cropped, 0))
                    .addOnSuccessListener { result ->
                        try {
                            val detectedPlatform = ScreenOfferParser.detectPlatform(result.text)
                            val accessibility = RideAccessibilityService.instance
                            val platform = if (accessibility != null) {
                                val foreground = accessibility.foregroundPlatform()
                                if (foreground == null || foreground != framePlatform || (detectedPlatform != null && foreground != detectedPlatform)) return@addOnSuccessListener
                                foreground
                            } else detectedPlatform ?: return@addOnSuccessListener
                            if (ScreenOfferParser.isActiveRide(result.text)) {
                                CompletedRideStore.confirmRideStarted(this, platform)
                            }
                            CompletedRideStore.observe(this, platform, result.text)
                            // Analise primeiro apenas a região onde a 99 desenha
                            // os cartões. Isso evita misturar saldo, promoções e
                            // informações do mapa com o valor real da oferta.
                            val cardText = result.textBlocks.filter { block ->
                                val box = block.boundingBox
                                box != null && box.centerY() > cropped.height * 0.20 && box.bottom < cropped.height * 0.98
                            }.joinToString("\n") { it.text }
                            val offer = ScreenOfferParser.parse(cardText) ?: ScreenOfferParser.parse(result.text)
                            // A captura é uma fonte auxiliar. Ela não deve
                            // fechar um cartão encontrado pela acessibilidade
                            // só porque um quadro do OCR ficou ilegível.
                            if (offer != null) {
                                if (accessibility != null) accessibility.showCapturedOffer(platform, offer)
                                else showOffer(platform, offer)
                            }
                        }
                        catch (error: Throwable) { lastError = "OCR: ${error.message ?: error.javaClass.simpleName}" }
                    }
                    .addOnFailureListener { error -> lastError = "OCR: ${error.message ?: error.javaClass.simpleName}" }
                    .addOnCompleteListener {
                        try { cropped.recycle() } catch (_: Throwable) { }
                        scanning = false
                    }
            } catch (error: Throwable) {
                try { captured?.close() } catch (_: Throwable) { }
                scanning = false
                lastError = "Captura: ${error.message ?: error.javaClass.simpleName}"
            }
        }, handler)
    }

    private fun showOffer(platform: String, offer: ScreenOffer) {
        CompletedRideStore.rememberOffer(this, platform, offer)
        val prefs = getSharedPreferences("ride_calculator", MODE_PRIVATE)
        RideOverlay.show(this, mapOf(
            "platform" to platform,
            "fare" to offer.fare, "distance" to offer.distance, "minutes" to offer.minutes,
            "perKm" to offer.fare / offer.distance, "perHour" to offer.fare * 60.0 / offer.minutes,
            "pickup" to offer.route.pickup, "destination" to offer.route.destination,
            "rating" to offer.rating,
            "yellow" to prefs.getFloat("yellow", 1.5f).toDouble(),
            "green" to prefs.getFloat("green", 2.0f).toDouble(),
            "ratingMinimum" to prefs.getFloat("ratingMinimum", 4.8f).toDouble(),
            "theme" to prefs.getInt("theme",0), "fontScale" to prefs.getFloat("fontScale",1f).toDouble(), "cardScale" to prefs.getFloat("cardScale",1f).toDouble()
        ))
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("ride_capture", "Calculadora automática", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        isRunning = false
        try { virtualDisplay?.release() } catch (_: Throwable) { }
        virtualDisplay = null
        try { reader?.close() } catch (_: Throwable) { }
        try { projection?.stop() } catch (_: Throwable) { }
        try { recognizer.close() } catch (_: Throwable) { }
        if (::worker.isInitialized) try { worker.quitSafely() } catch (_: Throwable) { }
        super.onDestroy()
    }
}
