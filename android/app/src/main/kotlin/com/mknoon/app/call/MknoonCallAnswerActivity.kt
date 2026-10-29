package com.mknoon.app.call

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.FrameLayout
import com.mknoon.app.MainActivity

/** Notification-owned Answer entry; the manifest keeps external callers out. */
class MknoonCallAnswerActivity : Activity() {
    private var presentation: MknoonIncomingCallPresentation? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(FrameLayout(this))
        presentation = MknoonIncomingCallPresentation(this).also {
            // Reuse the exact-call, expiry and duplicate checks before answering.
            // Activity restoration is display-only, just as for MainActivity.
            it.onIntent(intent, answerFromIntent = savedInstanceState == null)
        }
        val callId = intent.getStringExtra(MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID)
        startActivity(
            Intent(this, MainActivity::class.java)
                .setAction(AndroidMknoonCallPendingIntentFactory.ACTION_OPEN_INCOMING_CALL)
                .setData(Uri.parse("mknoon-call://local/$callId"))
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra(MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID, callId),
        )
        finish()
    }

    override fun onDestroy() {
        presentation?.dispose()
        presentation = null
        super.onDestroy()
    }
}
