package com.buzzel.debug

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileWriter
import java.io.PrintWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Writes log output to a file alongside the normal Android logcat.
 *
 * Usage: replace `Log.d(TAG, msg)` with `FileLogger.d(TAG, msg)`.
 * Log file location: <external-files-dir>/buzzel.log
 * Rotates at 5 MB (keeps one backup: buzzel.log.1).
 */
object FileLogger {
    private const val FTAG = "FileLogger"
    private const val FILE_NAME = "buzzel.log"
    private const val MAX_SIZE_BYTES = 5 * 1024 * 1024 // 5 MB

    private val fmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
    private val queue = LinkedBlockingQueue<String>()
    private val running = AtomicBoolean(false)
    private var logFile: File? = null

    fun init(context: Context) {
        val dir = context.getExternalFilesDir(null) ?: context.filesDir
        logFile = File(dir, FILE_NAME)
        if (!running.getAndSet(true)) {
            Thread({ drain() }, "FileLogger").apply {
                isDaemon = true
                start()
            }
        }
        enqueue("I", FTAG, "=== Log started: ${logFile?.absolutePath} ===")
    }

    fun d(
        tag: String,
        msg: String,
    ) {
        Log.d(tag, msg)
        enqueue("D", tag, msg)
    }

    fun i(
        tag: String,
        msg: String,
    ) {
        Log.i(tag, msg)
        enqueue("I", tag, msg)
    }

    fun w(
        tag: String,
        msg: String,
        e: Throwable? = null,
    ) {
        if (e != null) Log.w(tag, msg, e) else Log.w(tag, msg)
        enqueue("W", tag, if (e != null) "$msg | ${e.javaClass.simpleName}: ${e.message}" else msg)
    }

    fun e(
        tag: String,
        msg: String,
        e: Throwable? = null,
    ) {
        if (e != null) Log.e(tag, msg, e) else Log.e(tag, msg)
        enqueue("E", tag, if (e != null) "$msg | ${e.javaClass.simpleName}: ${e.message}" else msg)
    }

    private fun enqueue(
        level: String,
        tag: String,
        msg: String,
    ) {
        queue.offer("${fmt.format(Date())} $level/$tag: $msg")
    }

    private fun drain() {
        while (running.get()) {
            val line =
                try {
                    queue.take()
                } catch (_: InterruptedException) {
                    break
                }
            appendToFile(line)
        }
    }

    private fun appendToFile(line: String) {
        val file = logFile ?: return
        try {
            if (file.exists() && file.length() > MAX_SIZE_BYTES) {
                file.renameTo(File(file.parent, "buzzel.log.1"))
            }
            PrintWriter(FileWriter(file, true)).use { it.println(line) }
        } catch (ex: Exception) {
            Log.e(FTAG, "Write failed: ${ex.message}")
        }
    }

    fun path(): String? = logFile?.absolutePath
}
