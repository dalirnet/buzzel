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

object FileLogger {
    private const val TAG = "FileLogger"
    private const val FILE_NAME = "buzzel.log"
    private const val MAXIMUM_FILE_SIZE_BYTES = 5 * 1024 * 1024 // 5 MB

    private val dateFormatter = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
    private val queue = LinkedBlockingQueue<String>()
    private val running = AtomicBoolean(false)
    private var logFile: File? = null

    fun init(context: Context) {
        val directory = context.getExternalFilesDir(null) ?: context.filesDir
        logFile = File(directory, FILE_NAME)
        if (!running.getAndSet(true)) {
            Thread({ drain() }, "FileLogger").apply {
                isDaemon = true
                start()
            }
        }
        enqueue("I", TAG, "=== Log started: ${logFile?.absolutePath} ===")
    }

    fun d(
        tag: String,
        message: String,
    ) {
        Log.d(tag, message)
        enqueue("D", tag, message)
    }

    fun i(
        tag: String,
        message: String,
    ) {
        Log.i(tag, message)
        enqueue("I", tag, message)
    }

    fun w(
        tag: String,
        message: String,
        error: Throwable? = null,
    ) {
        if (error != null) Log.w(tag, message, error) else Log.w(tag, message)
        enqueue("W", tag, if (error != null) "$message | ${error.javaClass.simpleName}: ${error.message}" else message)
    }

    fun e(
        tag: String,
        message: String,
        error: Throwable? = null,
    ) {
        if (error != null) Log.e(tag, message, error) else Log.e(tag, message)
        enqueue("E", tag, if (error != null) "$message | ${error.javaClass.simpleName}: ${error.message}" else message)
    }

    private fun enqueue(
        level: String,
        tag: String,
        message: String,
    ) {
        queue.offer("${dateFormatter.format(Date())} $level/$tag: $message")
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
            if (file.exists() && file.length() > MAXIMUM_FILE_SIZE_BYTES) {
                file.renameTo(File(file.parent, "buzzel.log.1"))
            }
            PrintWriter(FileWriter(file, true)).use { it.println(line) }
        } catch (exception: Exception) {
            Log.e(TAG, "Write failed: ${exception.message}")
        }
    }

    fun path(): String? = logFile?.absolutePath
}
