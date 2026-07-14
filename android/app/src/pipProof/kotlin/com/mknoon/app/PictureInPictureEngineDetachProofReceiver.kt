package com.mknoon.app

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log

/** Disposable debug-build control; this class is absent from ordinary APKs. */
class PictureInPictureEngineDetachProofReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!isOrderedBroadcast || !isExactControl(context, intent)) {
            if (isOrderedBroadcast) resultCode = Activity.RESULT_CANCELED
            return
        }
        val invoked =
            PictureInPictureEngineCleanupCoordinator.cleanUpFlutterEngine()
        if (!invoked) {
            resultCode = Activity.RESULT_CANCELED
            return
        }
        Log.i(LIFECYCLE_TAG, CONTROL_MARKER)
        resultCode = Activity.RESULT_OK
    }

    private fun isExactControl(context: Context, intent: Intent): Boolean {
        if (
            intent.action != ACTION ||
            intent.component != ComponentName(
                context,
                PictureInPictureEngineDetachProofReceiver::class.java,
            ) ||
            intent.data != null ||
            intent.type != null ||
            intent.clipData != null ||
            intent.extras != null ||
            !intent.categories.isNullOrEmpty()
        ) {
            return false
        }
        return true
    }

    companion object {
        const val ACTION =
            "com.mknoon.app.pipproof.action.PICTURE_IN_PICTURE_ENGINE_DETACH"
        const val REQUIRED_SENDER_PERMISSION = "android.permission.DUMP"
        const val CONTROL_MARKER =
            "[MKNOON_PIP] PROOF_ENGINE_CLEANUP_CONTROL invoked=true"
        private const val LIFECYCLE_TAG = "MknoonPiP"
    }
}
