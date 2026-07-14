package com.mknoon.app

import java.lang.ref.WeakReference

/** One weak playback-handler binding consumed by the first engine cleanup. */
internal class PictureInPictureEngineCleanupBinding<T : Any>(
    private val cleanup: (T) -> Unit,
) {
    private val lock = Any()
    private var owner = WeakReference<T>(null)

    fun bind(next: T) {
        synchronized(lock) { owner = WeakReference(next) }
    }

    fun unbind(expected: T) {
        synchronized(lock) {
            if (owner.get() === expected) owner.clear()
        }
    }

    fun cleanUpFlutterEngine(): Boolean {
        val bound = synchronized(lock) {
            val current = owner.get() ?: return false
            owner.clear()
            current
        }
        cleanup(bound)
        return true
    }
}

/**
 * Shared engine-cleanup entry used by the real Flutter callback and the
 * disposable proof-only receiver. It owns no Activity, engine, or media path.
 */
internal object PictureInPictureEngineCleanupCoordinator {
    private val binding = PictureInPictureEngineCleanupBinding<PictureInPictureHandler> {
        handler -> handler.dispose("flutter_engine_detached")
    }

    fun bind(handler: PictureInPictureHandler) = binding.bind(handler)

    fun unbind(handler: PictureInPictureHandler) = binding.unbind(handler)

    fun cleanUpFlutterEngine(): Boolean = binding.cleanUpFlutterEngine()
}
