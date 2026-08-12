package com.music

import android.os.Build
import android.os.Bundle
import android.content.pm.PackageManager
import android.util.Log
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

class MainActivity : AudioServiceActivity() {
    private val diagnosticsChannelName = "com.music/diagnostics"

    private val isTv: Boolean
        get() = packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            diagnosticsChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "log" -> {
                    val message = call.argument<String>("message") ?: ""
                    if (call.argument<String>("level") == "info") {
                        Log.i("AudioCacheService", message)
                    } else {
                        Log.e("AudioCacheService", message)
                    }
                    result.success(null)
                }
                "decryptAudioFile" -> {
                    val path = call.argument<String>("path")
                    val keyHex = call.argument<String>("keyHex")
                    val sampleTable = call.argument<ByteArray>("sampleTable")
                    if (path == null || keyHex == null || sampleTable == null) {
                        result.error("invalid_arguments", "Missing native decrypt arguments", null)
                        return@setMethodCallHandler
                    }
                    Thread({
                        try {
                            val startedAt = System.nanoTime()
                            decryptAudioFile(path, keyHex, sampleTable)
                            val elapsedMs = (System.nanoTime() - startedAt) / 1_000_000
                            runOnUiThread { result.success(elapsedMs) }
                        } catch (error: Throwable) {
                            Log.e("AudioCacheService", "Native audio decrypt failed", error)
                            runOnUiThread {
                                result.error(
                                    "native_decrypt_failed",
                                    error.message ?: error.javaClass.simpleName,
                                    null,
                                )
                            }
                        }
                    }, "AudioDecrypt").start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun decryptAudioFile(path: String, keyHex: String, sampleTable: ByteArray) {
        require(keyHex.length == 32) { "AES-128 key must contain 32 hex characters" }
        require(sampleTable.size % 24 == 0) { "Invalid CENC sample table" }
        val key = ByteArray(16) { index ->
            keyHex.substring(index * 2, index * 2 + 2).toInt(16).toByte()
        }
        val table = ByteBuffer.wrap(sampleTable).order(ByteOrder.BIG_ENDIAN)
        var maximumSampleLength = 0
        for (index in 0 until sampleTable.size / 24) {
            val length = table.getInt(index * 24 + 4)
            require(length >= 0) { "Invalid CENC sample length" }
            if (length > maximumSampleLength) maximumSampleLength = length
        }

        RandomAccessFile(path, "rw").use { file ->
            val channel = file.channel
            val mapped = channel.map(
                java.nio.channels.FileChannel.MapMode.READ_WRITE,
                0,
                channel.size(),
            )
            val input = ByteArray(maximumSampleLength)
            val output = ByteArray(maximumSampleLength)
            val iv = ByteArray(16)
            val cipher = Cipher.getInstance("AES/CTR/NoPadding")
            val keySpec = SecretKeySpec(key, "AES")
            table.position(0)
            repeat(sampleTable.size / 24) {
                val offset = table.int.toLong() and 0xffffffffL
                val length = table.int
                table.get(iv)
                require(offset + length <= channel.size()) { "Invalid CENC sample offset" }
                mapped.position(offset.toInt())
                mapped.get(input, 0, length)
                cipher.init(Cipher.DECRYPT_MODE, keySpec, IvParameterSpec(iv))
                val outputLength = cipher.doFinal(input, 0, length, output, 0)
                require(outputLength == length) { "Unexpected AES-CTR output length" }
                mapped.position(offset.toInt())
                mapped.put(output, 0, outputLength)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Some Android 6 TV ROMs expose PointerIcon but do not implement the
        // ViewParent method used by Flutter, causing an AbstractMethodError.
        if (isTv && Build.VERSION.SDK_INT == Build.VERSION_CODES.M) {
            flutterEngine?.mouseCursorChannel?.setMethodHandler { _ -> }
        }
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (isTv && event.isFromSource(InputDevice.SOURCE_MOUSE)) return true
        return super.dispatchGenericMotionEvent(event)
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (isTv && event.isFromSource(InputDevice.SOURCE_MOUSE)) return true
        return super.dispatchTouchEvent(event)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (isTv && event.isFromSource(InputDevice.SOURCE_MOUSE)) return true
        return super.dispatchKeyEvent(event)
    }
}
