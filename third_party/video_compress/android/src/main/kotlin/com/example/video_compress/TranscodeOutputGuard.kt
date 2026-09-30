package com.example.video_compress

import java.io.File
import java.util.concurrent.atomic.AtomicReference

/** Owns only the output of the current transcode, including a codec that never calls back. */
internal class TranscodeOutputGuard {
    private val activePath = AtomicReference<String?>(null)

    fun begin(path: String) {
        activePath.set(path)
    }

    fun cancel() {
        activePath.getAndSet(null)?.let { File(it).delete() }
    }

    fun complete(path: String): Boolean {
        if (activePath.compareAndSet(path, null)) return true
        File(path).delete()
        return false
    }

    fun failed(path: String) {
        File(path).delete()
        activePath.compareAndSet(path, null)
    }
}
