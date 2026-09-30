package com.example.video_compress

import java.nio.file.Files
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TranscodeOutputGuardTest {
    @Test
    fun cancelUnlinksPartialMp4EvenWithoutNativeCallback() {
        val path = Files.createTempFile("partial-transcode-", ".mp4")
        try {
            val guard = TranscodeOutputGuard()
            guard.begin(path.toString())
            guard.cancel()
            assertFalse(Files.exists(path))
            assertFalse(guard.complete(path.toString()))
        } finally {
            Files.deleteIfExists(path)
        }
    }

    @Test
    fun completedOutputRemainsAvailableAndFailedOutputIsDeleted() {
        val complete = Files.createTempFile("complete-transcode-", ".mp4")
        val failed = Files.createTempFile("failed-transcode-", ".mp4")
        try {
            val guard = TranscodeOutputGuard()
            guard.begin(complete.toString())
            assertTrue(guard.complete(complete.toString()))
            assertTrue(Files.exists(complete))
            guard.begin(failed.toString())
            guard.failed(failed.toString())
            assertFalse(Files.exists(failed))
        } finally {
            Files.deleteIfExists(complete)
            Files.deleteIfExists(failed)
        }
    }
}
