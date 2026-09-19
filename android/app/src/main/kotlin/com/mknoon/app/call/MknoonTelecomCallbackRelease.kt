package com.mknoon.app.call

import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

internal enum class MknoonTelecomReleaseOutcome { RELEASED, FAILED, CANCELED, RETIRED }

internal class MknoonTelecomCallbackRelease<S : Any>(
    private val scope: CoroutineScope,
    private val current: (UUID) -> S?,
    private val disconnect: suspend (S) -> Boolean,
    private val markLocal: (UUID, S) -> Unit,
    private val clearLocal: (UUID, S) -> Unit,
    private val report: (MknoonTelecomReleaseOutcome) -> Unit = {},
) {
    private class Entry<S>(val session: S) {
        var job: Job? = null
        var outcome: MknoonTelecomReleaseOutcome? = null
        var retired = false
    }

    private val lock = Any()
    private val entries = mutableMapOf<UUID, Entry<S>>()

    // The supplied scope belongs to the platform, never to the provider callback.
    // Telecom cannot complete disconnect until that callback has returned.
    fun request(id: UUID, session: S?): Boolean = synchronized(lock) {
        if (session == null || current(id) !== session || !scope.isActive) {
            return@synchronized false
        }
        val previous = entries[id]
        if (previous?.session === session) {
            return@synchronized previous.outcome == null ||
                previous.outcome == MknoonTelecomReleaseOutcome.RELEASED
        }
        previous?.job?.cancel()
        val entry = Entry(session)
        entries[id] = entry
        markLocal(id, session)
        val job = scope.launch(start = CoroutineStart.LAZY) {
            val stillCurrent = current(id) === session
            val released = stillCurrent &&
                releaseTelecomCallbackSession { disconnect(session) }
            synchronized(lock) {
                entry.outcome = when {
                    entry.retired || !stillCurrent -> MknoonTelecomReleaseOutcome.RETIRED
                    released -> MknoonTelecomReleaseOutcome.RELEASED
                    !isActive -> MknoonTelecomReleaseOutcome.CANCELED
                    else -> MknoonTelecomReleaseOutcome.FAILED
                }
            }
        }
        entry.job = job
        job.invokeOnCompletion {
            val outcome = synchronized(lock) {
                val final = entry.outcome ?: if (entry.retired) {
                    MknoonTelecomReleaseOutcome.RETIRED
                } else {
                    MknoonTelecomReleaseOutcome.CANCELED
                }
                entry.outcome = final
                if (final != MknoonTelecomReleaseOutcome.RELEASED) clearLocal(id, session)
                final
            }
            // Diagnostics cannot change callback acceptance or cleanup ownership.
            runCatching { report(outcome) }
        }
        job.start()
        !job.isCancelled
    }

    fun retire(id: UUID, session: S) = synchronized(lock) {
        val entry = entries[id]?.takeIf { it.session === session }
        if (entry != null) {
            entries.remove(id)
            entry.retired = true
            entry.job?.cancel()
        }
        clearLocal(id, session)
    }
}
