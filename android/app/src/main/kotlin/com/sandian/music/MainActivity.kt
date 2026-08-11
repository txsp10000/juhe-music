package com.sandian.music

import com.ryanheise.audioservice.AudioServiceActivity
import android.view.InputDevice
import android.view.MotionEvent

class MainActivity : AudioServiceActivity() {
    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        val isTvHoverMove = event.actionMasked == MotionEvent.ACTION_HOVER_MOVE &&
            event.isFromSource(InputDevice.SOURCE_MOUSE)
        if (isTvHoverMove) return true
        return super.dispatchGenericMotionEvent(event)
    }
}
