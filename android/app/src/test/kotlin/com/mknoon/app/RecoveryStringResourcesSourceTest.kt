package com.mknoon.app

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class RecoveryStringResourcesSourceTest {
    @Test
    fun `default German and Arabic recovery resources have exact key parity`() {
        val expected = setOf(
            "dropped_push_recovery_channel_name",
            "dropped_push_recovery_channel_description",
            "dropped_push_recovery_notification_title",
            "dropped_push_recovery_notification_body",
            "dropped_push_recovery_worker_body",
        )

        listOf("values", "values-de", "values-ar").forEach { directory ->
            val xml = resourceFile(directory).readText()
            val keys = Regex("""<string\s+name="([^"]+)"""")
                .findAll(xml)
                .map { match -> match.groupValues[1] }
                .toSet()
            assertEquals("resource keys for $directory", expected, keys)
            expected.forEach { key ->
                val value = Regex("""<string\s+name="$key">([^<]*)</string>""")
                    .find(xml)
                    ?.groupValues
                    ?.get(1)
                    .orEmpty()
                    .trim()
                assertFalse("$directory/$key must not be blank", value.isBlank())
            }
        }
    }

    private fun resourceFile(directory: String): File = sequenceOf(
        File("src/main/res/$directory/strings.xml"),
        File("android/app/src/main/res/$directory/strings.xml"),
    ).firstOrNull(File::isFile) ?: error("Cannot locate $directory/strings.xml")
}
