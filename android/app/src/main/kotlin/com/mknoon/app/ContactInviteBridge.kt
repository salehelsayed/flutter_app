package com.mknoon.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Owned by MainActivity. Activity callbacks and this channel run on the main thread. */
internal class ContactInviteBridge(private val activity: Activity) {
    private var channel: MethodChannel? = null
    private var pending: Map<String, String>? = null

    fun attach(messenger: BinaryMessenger) {
        channel?.setMethodCallHandler(null)
        val bridge = MethodChannel(messenger, CHANNEL_NAME)
        bridge.setMethodCallHandler { call, result ->
            when {
                call.method == "takePending" && call.arguments == null -> {
                    val entry = pending
                    pending = null
                    result.success(entry)
                }
                call.method == "shareLink" -> result.success(shareLink(call.arguments as? String))
                else -> result.notImplemented()
            }
        }
        channel = bridge
        if (pending != null) wake()
    }

    fun offer(intent: Intent?) {
        if (intent == null ||
            intent.action != Intent.ACTION_VIEW ||
            (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
        ) {
            return
        }
        val raw = intent.dataString ?: return
        pending = when {
            raw == PASTE_URL -> mapOf("kind" to "paste")
            inviteFrame.matches(raw) -> mapOf("kind" to "link", "url" to raw)
            else -> return
        }
        wake()
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        pending = null
    }

    private fun wake() {
        channel?.invokeMethod("inviteAvailable", null)
    }

    private fun shareLink(raw: String?): Boolean {
        if (raw == null || !inviteFrame.matches(raw) || activity.isFinishing || activity.isDestroyed) {
            return false
        }
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, raw)
        }
        return try {
            activity.startActivity(Intent.createChooser(send, null))
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    private companion object {
        const val CHANNEL_NAME = "mknoon/contact_invites"
        const val PASTE_URL = "mknoon://invite"
        val inviteFrame = Regex("""https://invite\.mknoon\.xyz/i/v1#[A-Za-z0-9_-]{1,2048}""")
    }
}
