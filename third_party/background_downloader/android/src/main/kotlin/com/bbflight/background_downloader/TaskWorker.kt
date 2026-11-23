package com.bbflight.background_downloader

import android.app.Notification
import android.content.Context
import android.content.SharedPreferences
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import androidx.preference.PreferenceManager
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.serialization.json.Json
import android.util.Log
import kotlinx.coroutines.sync.withLock

/**
 * The worker to execute one task
 *
 * Wraps [TaskRunner], delegating the actual work to it, and implements
 * [TaskJobContext] to provide the context for the [TaskRunner].
 */
@Suppress("ConstPropertyName")
open class TaskWorker(
    val context: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(context, workerParams), TaskJobContext {

    companion object {
        const val keyTask = "Task"
        const val keyNotificationConfig = "notificationConfig"
        const val keyResumeDataData = "tempFilename"
        const val keyStartByte = "startByte"
        const val keyETag = "eTag"
        const val bufferSize = 2 shl 12

        /** Converts [Task] to JSON string representation */
        fun taskToJsonString(task: Task): String {
            return TaskRunner.taskToJsonString(task)
        }

        /**
         * Processes a change in status for the task
         *
         * Delegates to [TaskRunner.processStatusUpdate]
         */
        suspend fun processStatusUpdate(
            task: Task,
            status: TaskStatus,
            prefs: SharedPreferences,
            taskException: TaskException? = null,
            responseBody: String? = null,
            responseHeaders: Map<String, String>? = null,
            responseStatusCode: Int? = null,
            mimeType: String? = null,
            charSet: String? = null,
            context: Context
        ) {
            TaskRunner.processStatusUpdate(
                task,
                status,
                prefs,
                taskException,
                responseBody,
                responseHeaders,
                responseStatusCode,
                mimeType,
                charSet,
                context
            )
        }
    }

    override val appContext: Context
        get() = applicationContext

    // TaskJobContext Mutable properties
    override lateinit var task: Task
    override var notificationConfig: NotificationConfig? = null
    override var notificationId: Int = 0
    override var notificationProgress: Double = 2.0 // indeterminate
    override var networkSpeed: Double = -1.0
    override var taskCanResume: Boolean = false
    override var notificationConfigJsonString: String? = null
    override var runInForeground: Boolean = false

    override val isTaskStopped: Boolean
        get() = isStopped



    override val isActive: Boolean
        get() = !isTaskStopped

    override fun getInputLong(key: String, defaultValue: Long): Long {
        return inputData.getLong(key, defaultValue)
    }

    override fun getInputString(key: String): String? {
        return inputData.getString(key)
    }

    override suspend fun setForegroundNotification(
        notificationId: Int,
        notification: Notification,
        notificationType: Int
    ) {
        try {
            setForeground(ForegroundInfo(notificationId, notification, notificationType))
        } catch (e: IllegalStateException) {
            Log.d("TaskWorker", "Ignoring setForeground: worker already completed. ${e.message}")
        }
    }

    override suspend fun updateNotification(
        task: Task,
        status: TaskStatus,
        progress: Double,
        timeRemaining: Long
    ) {
        NotificationService.updateNotification(this, status, progress, timeRemaining)
    }

    override fun updateEstimatedNetworkBytes(downloadBytes: Long, uploadBytes: Long) {
        // No-op for TaskWorker
    }

    internal fun managedNetwork(): Network? {
        val connectivity = applicationContext.getSystemService(ConnectivityManager::class.java) ?: return null
        val selected = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) network else null)
            ?: connectivity.activeNetwork ?: return null
        val capabilities = connectivity.getNetworkCapabilities(selected) ?: return null
        if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) return null
        return selected.takeIf {
            !BDPlugin.taskRequiresWifi(task) || capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
        }
    }

    internal fun managedNetworkStopped(): Boolean =
        (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && isStopped &&
            stopReason == WorkInfo.STOP_REASON_CONSTRAINT_CONNECTIVITY) || managedNetwork() == null

    internal fun hasLiveManagedWork(): Boolean =
        WorkManager.getInstance(appContext).getWorkInfoById(id).get()?.state?.isFinished == false

    override suspend fun doWork(): Result {
        try {
            // Initialize task and notificationConfig from inputData
            val taskJson = inputData.getString(keyTask)
            if (taskJson != null) {
                task = bdJson.decodeFromString(taskJson)
            } else {
                return Result.failure()
            }

            notificationConfigJsonString = inputData.getString(keyNotificationConfig)
            if (notificationConfigJsonString != null) {
                notificationConfig = bdJson.decodeFromString(notificationConfigJsonString!!)
            }
            
            runInForeground = false 

            val runner = createRunner()
            if (ManagedDownloadHold.appliesTo(task)) {
                ManagedDownloadHold.writerMutex.withLock { runner.run() }
            } else {
                runner.run()
            }

            return if (runner.retrySameWork) Result.retry() else Result.success()
        } catch (e: Exception) {
            return Result.failure()
        }
    }

    /**
     * Create the appropriate [TaskRunner] for this worker
     *
     * Must be overridden by subclasses
     */
    open fun createRunner(): TaskRunner {
        throw NotImplementedError("Subclasses must override createRunner")
    }
}
