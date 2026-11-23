package com.bbflight.background_downloader

import android.content.SharedPreferences
import android.os.SystemClock
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import kotlin.concurrent.write
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.encodeToString

internal class ManagedVerificationWindow private constructor(
    private val taskId: String,
    val workId: UUID,
    val channel: MethodChannel,
) {
    private val finished = CompletableDeferred<Unit>()
    private val expiresAt = SystemClock.elapsedRealtime() + 30_000L

    suspend fun awaitAcknowledgement() {
        withTimeoutOrNull(expiresAt - SystemClock.elapsedRealtime()) { finished.await() }
    }

    fun persistCompletion(
        prefs: SharedPreferences,
        edit: SharedPreferences.Editor,
        update: TaskStatusUpdate,
    ): Boolean {
        // Dart may receive completion and then lose the engine before persisting its result.
        val statuses = storedStatuses(prefs)
        statuses[taskId] = bdJson.encodeToString(update)
        return edit.putString(completedWorkKey, workId.toString())
            .putString(BDPlugin.keyStatusUpdateMap, bdJson.encodeToString(statuses)).commit()
    }

    fun close() {
        synchronized(windows) {
            if (windows[taskId] === this) windows.remove(taskId)
            finished.complete(Unit)
        }
    }

    companion object {
        const val completedWorkKey = "com.bbflight.background_downloader.completedManagedWork"
        private val windows = mutableMapOf<String, ManagedVerificationWindow>()
        private val appChannels = mutableSetOf<MethodChannel>()

        fun attachAppChannel(channel: MethodChannel) {
            synchronized(windows) { appChannels.add(channel) }
        }

        fun detachAppChannel(channel: MethodChannel) {
            synchronized(windows) {
                appChannels.remove(channel)
                val affected = windows.values.filter { it.channel === channel }
                affected.forEach { it.close() }
            }
        }

        fun isLiveAppChannel(channel: MethodChannel): Boolean =
            synchronized(windows) { channel in appChannels }

        fun open(taskId: String, workId: UUID): ManagedVerificationWindow? = synchronized(windows) {
            val owner = BDPlugin.bgChannelByTaskId[taskId] ?: return@synchronized null
            if (owner !in appChannels || taskId in windows) return@synchronized null
            ManagedVerificationWindow(taskId, workId, owner).also { windows[taskId] = it }
        }

        fun acknowledge(prefs: SharedPreferences, taskId: String, channel: MethodChannel) {
            val window = synchronized(windows) { windows[taskId]?.takeIf { it.channel === channel } }
                ?: return
            try {
                discardCompletion(prefs, taskId, window.workId)
            } finally {
                window.close()
            }
        }

        fun cancel(prefs: SharedPreferences, taskId: String, workId: UUID) {
            val window = synchronized(windows) { windows[taskId]?.takeIf { it.workId == workId } }
            try {
                discardCompletion(prefs, taskId, workId)
            } finally {
                window?.close()
            }
        }

        private fun discardCompletion(prefs: SharedPreferences, taskId: String, workId: UUID) {
            BDPlugin.prefsLock.write {
                if (prefs.getString(completedWorkKey, null) != workId.toString()) return@write
                val statuses = storedStatuses(prefs)
                val status = statuses[taskId]?.let { bdJson.decodeFromString<TaskStatusUpdate>(it) }
                if (status?.taskStatus != TaskStatus.complete) return@write
                statuses.remove(taskId)
                prefs.edit().putString(BDPlugin.keyStatusUpdateMap, bdJson.encodeToString(statuses)).apply()
            }
        }

        private fun storedStatuses(prefs: SharedPreferences): MutableMap<String, String> =
            bdJson.decodeFromString(prefs.getString(BDPlugin.keyStatusUpdateMap, "{}") ?: "{}")
    }
}
