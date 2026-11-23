package com.bbflight.background_downloader

import android.content.Context
import android.content.SharedPreferences
import androidx.work.WorkInfo
import java.io.File
import java.io.IOException
import java.util.UUID
import kotlin.concurrent.read
import kotlin.concurrent.write
import kotlinx.coroutines.sync.Mutex
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString

@Serializable
internal data class ManagedDownloadHold(
    val workId: String,
    val taskIdentity: String,
    val checkpoint: ResumeData?,
    val partialPath: String?,
    val notification: String?,
    val held: Boolean,
) {
    fun owns(task: Task, id: UUID): Boolean =
        workId == id.toString() && taskIdentity == identity(task)

    fun retainedBytes(context: Context): Long? {
        val path = partialPath ?: return 0L.takeIf { checkpoint == null }
        val file = ownedPartial(context, path) ?: return null
        if (checkpoint == null) return 0L.takeIf { !file.exists() || file.length() == 0L }
        return checkpoint.requiredStartByte.takeIf {
            identity(checkpoint.task) == taskIdentity && checkpoint.data == path &&
                it > 0 && strongValidator(checkpoint.eTag) &&
                file.isFile && file.length() == it
        }
    }

    companion object {
        private const val keyPrefix = "com.bbflight.background_downloader.managedDownload."
        val writerMutex = Mutex()

        fun appliesTo(task: Task): Boolean =
            task.options?.appManagedRecovery == true && task.group == "mknoon_gemma_translation" &&
                task.taskType == "DownloadTask" && task.allowPause && task.priority >= 5 &&
                task.baseDirectory == BaseDirectory.applicationSupport &&
                task.directory == "gemma_translation" && task.filename == "gemma-4-E2B-it.litertlm" &&
                task.post == null

        fun identity(task: Task): String = TaskRunner.taskToJsonString(task.copyWith(requiresWiFi = false))

        fun strongValidator(value: String?): Boolean =
            value != null && value.length >= 2 && value.first() == '"' && value.last() == '"'

        fun ownedPartial(context: Context, path: String): File? = try {
            val base = baseDirPath(context, BaseDirectory.applicationSupport)?.let(::File)?.canonicalFile
            val file = File(path).canonicalFile
            file.takeIf {
                base != null && it.parentFile == base &&
                    it.name.startsWith("com.bbflight.background_downloader")
            }
        } catch (_: IOException) {
            null
        }

        fun load(prefs: SharedPreferences, taskId: String): ManagedDownloadHold? = BDPlugin.prefsLock.read {
            prefs.getString(keyPrefix + taskId, null)?.let { bdJson.decodeFromString<ManagedDownloadHold>(it) }
        }

        fun live(prefs: SharedPreferences, task: Task, work: WorkInfo): ManagedDownloadHold? =
            load(prefs, task.taskId)?.takeIf {
                it.held && it.owns(task, work.id) && !work.state.isFinished &&
                    BDPlugin.TAG in work.tags && "group=${task.group}" in work.tags
            }

        fun save(
            prefs: SharedPreferences,
            task: Task,
            workId: UUID,
            checkpoint: ResumeData?,
            partialPath: String?,
            notification: String?,
            held: Boolean,
        ): Boolean = BDPlugin.prefsLock.write {
            if (task.taskId in BDPlugin.canceledTaskIds) return@write false
            val existing = load(prefs, task.taskId)
            if (existing != null && !existing.owns(task, workId)) return@write false
            val value = ManagedDownloadHold(workId.toString(), identity(task), checkpoint, partialPath, notification, held)
            prefs.edit().putString(keyPrefix + task.taskId, bdJson.encodeToString(value)).commit()
        }

        fun forget(prefs: SharedPreferences, taskId: String, workId: UUID): ManagedDownloadHold? =
            BDPlugin.prefsLock.write {
                val hold = load(prefs, taskId)?.takeIf { it.workId == workId.toString() } ?: return@write null
                if (prefs.edit().remove(keyPrefix + taskId).commit()) hold else null
            }
    }
}
