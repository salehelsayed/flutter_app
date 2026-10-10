package com.mknoon.app

import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import java.io.File

/**
 * 414 (F2): drops shared files this app cannot read before the share plugin
 * sees the intent.
 *
 * `receive_sharing_intent` opens every shared `content://` stream on the main
 * thread and does not catch [SecurityException]. A share whose URI carries no
 * read grant therefore killed the whole app. Readable files pass through
 * unchanged; an intent left with nothing to share becomes a plain launch.
 */
internal object ShareIntentReadabilityGuard {
    fun sanitize(intent: Intent?, canRead: (Uri) -> Boolean): Intent? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_SEND -> sanitizeSingle(intent, canRead)
            Intent.ACTION_SEND_MULTIPLE -> sanitizeMultiple(intent, canRead)
            else -> intent
        }
    }

    fun canRead(resolver: ContentResolver, uri: Uri): Boolean = try {
        when (uri.scheme) {
            ContentResolver.SCHEME_CONTENT ->
                resolver.openAssetFileDescriptor(uri, "r")?.use { true } ?: false
            ContentResolver.SCHEME_FILE -> uri.path?.let { File(it).canRead() } ?: false
            else -> false
        }
    } catch (_: Exception) {
        false
    }

    @Suppress("DEPRECATION")
    private fun sanitizeSingle(intent: Intent, canRead: (Uri) -> Boolean): Intent {
        val stream = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: return intent
        if (canRead(stream)) return intent
        intent.removeExtra(Intent.EXTRA_STREAM)
        intent.clipData = null
        return if (hasText(intent)) asTextShare(intent) else asPlainLaunch(intent)
    }

    @Suppress("DEPRECATION")
    private fun sanitizeMultiple(intent: Intent, canRead: (Uri) -> Boolean): Intent {
        val streams = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: return intent
        val readable = streams.filter(canRead)
        if (readable.size == streams.size) return intent
        if (readable.isNotEmpty()) {
            intent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(readable))
            return intent
        }
        intent.clipData = null
        intent.removeExtra(Intent.EXTRA_STREAM)
        return if (hasText(intent)) asTextShare(intent) else asPlainLaunch(intent)
    }

    private fun hasText(intent: Intent): Boolean =
        !intent.getStringExtra(Intent.EXTRA_TEXT).isNullOrBlank()

    private fun asTextShare(intent: Intent): Intent {
        intent.action = Intent.ACTION_SEND
        intent.type = "text/plain"
        return intent
    }

    private fun asPlainLaunch(intent: Intent): Intent {
        intent.action = Intent.ACTION_MAIN
        intent.type = null
        return intent
    }
}
