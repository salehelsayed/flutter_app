package com.bbflight.background_downloader

import android.app.ActivityManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.system.Os
import android.system.OsConstants
import android.system.StructStat
import android.system.StructTimespec
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import java.util.UUID
import kotlin.concurrent.read
import kotlin.concurrent.write
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.Serializable
import org.json.JSONObject

internal class ManagedModelVerification private constructor(
    private val workId: UUID,
    private val task: Task,
    private val file: File,
    private val expectedSha256: String,
    private val sizeBytes: Long,
    private val readyTitle: String,
    private val readyBody: String,
) {
    @Serializable
    private data class StagedFile(
        val workId: String,
        val device: Long,
        val inode: Long,
    ) {
        fun matches(stat: StructStat) = device == stat.st_dev && inode == stat.st_ino
    }

    private var verified: StructStat? = null
    private val stagedKey = stagePrefix + task.taskId

    // Write the source inode before the rename. On retry it identifies the
    // completed destination even if the process died immediately after moving it.
    fun stage(prefs: SharedPreferences, partial: File): Boolean = try {
        val source = Os.lstat(partial.path)
        OsConstants.S_ISREG(source.st_mode) && source.st_size == sizeBytes &&
            prefs.edit().putString(
                stagedKey, bdJson.encodeToString(StagedFile(workId.toString(), source.st_dev, source.st_ino))
            ).commit()
    } catch (_: Exception) {
        false
    }

    fun hasStagedFile(prefs: SharedPreferences): Boolean = try {
        val staged = prefs.getString(stagedKey, null)?.let { bdJson.decodeFromString<StagedFile>(it) }
        val stat = Os.lstat(file.path)
        staged?.workId == workId.toString() && staged.matches(stat) &&
            OsConstants.S_ISREG(stat.st_mode) && stat.st_size == sizeBytes
    } catch (_: Exception) {
        false
    }

    suspend fun verify() {
        verified = try {
            if (file.canonicalPath != file.path) return
            val pathBefore = Os.lstat(file.path)
            if (!OsConstants.S_ISREG(pathBefore.st_mode) || pathBefore.st_size != sizeBytes) return
            val descriptor = Os.open(file.path, OsConstants.O_RDONLY or OsConstants.O_CLOEXEC or OsConstants.O_NOFOLLOW, 0)
            FileInputStream(descriptor).use { input ->
                val opened = Os.fstat(input.fd)
                if (!sameFile(pathBefore, opened)) return
                val digest = MessageDigest.getInstance("SHA-256")
                val bytes = ByteArray(256 * 1024)
                while (true) {
                    currentCoroutineContext().ensureActive()
                    val count = input.read(bytes)
                    if (count < 0) break
                    digest.update(bytes, 0, count)
                }
                opened.takeIf {
                    sameFile(it, Os.fstat(input.fd)) && sameFile(it, Os.lstat(file.path)) &&
                        digest.digest().joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) } ==
                        expectedSha256
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            null
        }
    }

    // Called under the queue policy lock immediately before publishing transfer completion.
    fun complete(context: Context, prefs: SharedPreferences) {
        val stat = verified ?: return
        try {
            if (!sameFile(stat, Os.lstat(file.path))) return
            val identity = JSONObject()
                .put("canonicalPath", file.path)
                .put("sizeBytes", stat.st_size)
                .put("modifiedMicros", micros(stat.st_mtim))
                .put("changedMicros", micros(stat.st_ctim))
            val verification = JSONObject().put("expectedSha256", expectedSha256).put("identity", identity)
            val receipt = JSONObject().put("version", 1).put("taskId", task.taskId)
                .put("workId", workId.toString()).put("verification", verification).put("noticePosted", false)
            BDPlugin.prefsLock.write {
                if (!prefs.edit().putString(receiptKey, receipt.toString()).commit()) return
                if (postReady(context)) {
                    prefs.edit().putString(receiptKey, receipt.put("noticePosted", true).toString()).commit()
                }
            }
        } catch (e: Exception) {
            Log.w(BDPlugin.TAG, "Could not finish managed model verification", e)
        }
    }

    private fun postReady(context: Context): Boolean {
        val process = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(process)
        if (process.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND) return false
        val notifications = NotificationManagerCompat.from(context)
        if (!notifications.areNotificationsEnabled()) return false
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = manager.getNotificationChannel(channelId)
        if (channel?.importance == NotificationManager.IMPORTANCE_NONE) return false
        if (channel == null) {
            manager.createNotificationChannel(NotificationChannel(
                channelId,
                context.getString(R.string.bg_downloader_notification_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            ))
        }
        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.outline_download_done_24)
            .setContentTitle(readyTitle)
            .setContentText(readyBody)
            .setStyle(NotificationCompat.BigTextStyle().bigText(readyBody))
            .setAutoCancel(true).setOnlyAlertOnce(true).setSilent(true)
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.let { launch ->
            builder.setContentIntent(PendingIntent.getActivity(
                context, readyId, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            ))
        }
        notifications.notify(notificationTag, readyId, builder.build())
        return true
    }

    companion object {
        private const val channelId = "background_downloader"
        private const val notificationTag = "mknoon_translator_download"
        private const val readyId = -41004
        private const val stagePrefix = "com.bbflight.background_downloader.modelStage."
        private const val receiptKey = "com.bbflight.background_downloader.modelReceipt"

        fun create(context: Context, task: Task, workId: UUID): ManagedModelVerification? {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1 ||
                !ManagedDownloadHold.appliesTo(task) || task.metaData.isEmpty()
            ) return null
            return try {
                val request = JSONObject(task.metaData).getJSONObject("translatorVerification")
                val sha = request.getString("expectedSha256")
                val size = request.getLong("sizeBytes")
                val title = request.getString("readyTitle")
                val body = request.getString("readyBody")
                if (request.getInt("version") != 1 || !sha.matches(Regex("[a-f0-9]{64}")) ||
                    size <= 0 || title.isBlank() || body.isBlank()
                ) return null
                val base = File(baseDirPath(context, BaseDirectory.applicationSupport) ?: return null)
                    .canonicalFile
                val file = File(File(base, task.directory), task.filename)
                ManagedModelVerification(workId, task, file, sha, size, title, body)
            } catch (_: Exception) {
                null
            }
        }

        fun readReceipt(prefs: SharedPreferences, taskId: String): String? = try {
            BDPlugin.prefsLock.read {
                prefs.getString(receiptKey, null)?.takeIf { JSONObject(it).optString("taskId") == taskId }
            }
        } catch (_: Exception) {
            null
        }

        fun forgetStage(prefs: SharedPreferences, taskId: String, workId: UUID) {
            val key = stagePrefix + taskId
            val staged = prefs.getString(key, null)?.let { bdJson.decodeFromString<StagedFile>(it) }
            if (staged?.workId == workId.toString()) prefs.edit().remove(key).apply()
        }

        fun cancel(context: Context, prefs: SharedPreferences, taskId: String, workId: UUID) {
            forgetStage(prefs, taskId, workId)
            val receipt = readReceipt(prefs, taskId) ?: return
            if (JSONObject(receipt).optString("workId") != workId.toString()) return
            prefs.edit().remove(receiptKey).apply()
            NotificationManagerCompat.from(context).cancel(notificationTag, readyId)
        }

        private fun micros(time: StructTimespec) = time.tv_sec * 1_000_000 + time.tv_nsec / 1_000

        private fun sameFile(left: StructStat, right: StructStat) =
            left.st_dev == right.st_dev && left.st_ino == right.st_ino &&
                left.st_mode == right.st_mode && left.st_size == right.st_size &&
                left.st_mtim == right.st_mtim && left.st_ctim == right.st_ctim
    }
}
