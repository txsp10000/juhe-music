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
                else -> result.notImplemented()
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
