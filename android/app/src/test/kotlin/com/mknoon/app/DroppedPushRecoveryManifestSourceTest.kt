package com.mknoon.app

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

class DroppedPushRecoveryManifestSourceTest {
    @Test
    fun `source manifest removes FlutterFire owner and registers higher priority custom owner`() {
        val manifest = sequenceOf(
            File("src/main/AndroidManifest.xml"),
            File("android/app/src/main/AndroidManifest.xml"),
        ).firstOrNull(File::isFile) ?: error("Cannot locate app source manifest")
        val xml = manifest.readText()

        assertTrue(xml.contains("xmlns:tools=\"http://schemas.android.com/tools\""))
        assertTrue(xml.contains("io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService"))
        assertTrue(xml.contains("tools:node=\"remove\""))
        val customOwner = Regex(
            """<service\s+[^>]*android:name="\.MknoonFirebaseMessagingService"[^>]*>.*?<intent-filter\s+[^>]*android:priority="[1-9][0-9]*"[^>]*>.*?<action\s+android:name="com\.google\.firebase\.MESSAGING_EVENT"\s*/>.*?</intent-filter>.*?</service>""",
            RegexOption.DOT_MATCHES_ALL,
        )
        assertTrue(customOwner.containsMatchIn(xml))
    }
}
