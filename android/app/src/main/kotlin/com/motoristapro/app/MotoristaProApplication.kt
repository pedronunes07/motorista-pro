package com.motoristapro.app

import android.app.Application
import android.os.Build
import java.io.PrintWriter
import java.io.StringWriter

class MotoristaProApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val previousHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                val trace = StringWriter().also { error.printStackTrace(PrintWriter(it)) }.toString()
                val report = buildString {
                    appendLine("Motorista Pro - diagnóstico do fechamento")
                    appendLine("Android: ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
                    appendLine("Aparelho: ${Build.MANUFACTURER} ${Build.MODEL}")
                    appendLine("Thread: ${thread.name}")
                    appendLine()
                    append(trace)
                }
                getSharedPreferences("motorista_pro_diagnostics", MODE_PRIVATE)
                    .edit()
                    .putString("last_crash", report)
                    .commit()
            } catch (_: Throwable) {
                // O relatório nunca deve impedir o tratamento normal do Android.
            }
            previousHandler?.uncaughtException(thread, error)
        }
    }
}
