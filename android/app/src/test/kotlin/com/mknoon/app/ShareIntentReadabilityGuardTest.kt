package com.mknoon.app

import android.content.Intent
import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ShareIntentReadabilityGuardTest {
    private val ok = Uri.parse("content://media/external/downloads/1")
    private val denied = Uri.parse("content://media/external/downloads/2")
    private val canRead: (Uri) -> Boolean = { it == ok }

    @Suppress("DEPRECATION")
    @Test
    fun `414 readable shares pass through unchanged`() {
        val single = Intent(Intent.ACTION_SEND).setType("application/pdf").putExtra(Intent.EXTRA_STREAM, ok)
        assertSame(single, ShareIntentReadabilityGuard.sanitize(single, canRead))
        assertEquals(ok, single.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
        val other = Intent(Intent.ACTION_VIEW)
        assertSame(other, ShareIntentReadabilityGuard.sanitize(other) { false })
        assertNull(ShareIntentReadabilityGuard.sanitize(null, canRead))
    }

    @Suppress("DEPRECATION")
    @Test
    fun `414 an unreadable single share becomes a plain launch`() {
        val intent = Intent(Intent.ACTION_SEND).setType("application/pdf").putExtra(Intent.EXTRA_STREAM, denied)
        ShareIntentReadabilityGuard.sanitize(intent, canRead)
        assertEquals(Intent.ACTION_MAIN, intent.action)
        assertNull(intent.type)
        assertFalse(intent.hasExtra(Intent.EXTRA_STREAM))
    }

    @Suppress("DEPRECATION")
    @Test
    fun `414 an unreadable share with text keeps only the text`() {
        val intent = Intent(Intent.ACTION_SEND).setType("application/pdf")
            .putExtra(Intent.EXTRA_STREAM, denied).putExtra(Intent.EXTRA_TEXT, "caption")
        ShareIntentReadabilityGuard.sanitize(intent, canRead)
        assertEquals(Intent.ACTION_SEND, intent.action)
        assertEquals("text/plain", intent.type)
        assertEquals("caption", intent.getStringExtra(Intent.EXTRA_TEXT))
        assertFalse(intent.hasExtra(Intent.EXTRA_STREAM))
    }

    @Suppress("DEPRECATION")
    @Test
    fun `414 a multiple share keeps only readable files`() {
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).setType("*/*")
            .putParcelableArrayListExtra(Intent.EXTRA_STREAM, arrayListOf(ok, denied))
        ShareIntentReadabilityGuard.sanitize(intent, canRead)
        assertEquals(Intent.ACTION_SEND_MULTIPLE, intent.action)
        assertEquals(listOf(ok), intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM))

        val none = Intent(Intent.ACTION_SEND_MULTIPLE).setType("*/*")
            .putParcelableArrayListExtra(Intent.EXTRA_STREAM, arrayListOf(denied))
        ShareIntentReadabilityGuard.sanitize(none, canRead)
        assertEquals(Intent.ACTION_MAIN, none.action)
    }

    @Test
    fun `414 canRead is false for a provider that refuses access`() {
        val resolver = RuntimeEnvironment.getApplication().contentResolver
        assertFalse(ShareIntentReadabilityGuard.canRead(resolver, Uri.parse("content://no.such.provider/x.pdf")))
        assertFalse(ShareIntentReadabilityGuard.canRead(resolver, Uri.parse("file:///no/such/file.pdf")))
        assertFalse(ShareIntentReadabilityGuard.canRead(resolver, Uri.parse("https://example.com/x.pdf")))
    }
}
