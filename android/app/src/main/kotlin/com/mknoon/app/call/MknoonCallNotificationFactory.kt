package com.mknoon.app.call

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.annotation.RequiresApi
import com.mknoon.app.MainActivity
import com.mknoon.app.R
import java.util.UUID

internal interface MknoonCallPendingIntentFactory {
    fun action(nativeCallId: UUID, action: String): PendingIntent

    fun fullScreen(nativeCallId: UUID): PendingIntent

    /**
     * Answer must bring the app forward: the activity answers through the
     * runtime, so the call surface and the microphone foreground service both
     * start from a user-interaction context. A plain broadcast cannot start an
     * activity from the background on Android 10+.
     */
    fun answerActivity(nativeCallId: UUID): PendingIntent =
        action(nativeCallId, MknoonCallActionReceiver.ACTION_ANSWER)
}

internal class AndroidMknoonCallPendingIntentFactory(
    context: Context,
) : MknoonCallPendingIntentFactory {
    private val applicationContext = context.applicationContext

    override fun action(nativeCallId: UUID, action: String): PendingIntent {
        val intent = Intent(applicationContext, MknoonCallActionReceiver::class.java)
            .setAction(action)
            .setData(Uri.parse("mknoon-call-action://local/${action.substringAfterLast('.')}/$nativeCallId"))
            .putExtra(MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID, nativeCallId.toString())
        return PendingIntent.getBroadcast(
            applicationContext,
            requestCode(nativeCallId, action),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    override fun answerActivity(nativeCallId: UUID): PendingIntent {
        val intent = Intent(applicationContext, MainActivity::class.java)
            .setAction(MknoonCallActionReceiver.ACTION_ANSWER)
            .setData(Uri.parse("mknoon-call-answer://local/$nativeCallId"))
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID, nativeCallId.toString())
        return PendingIntent.getActivity(
            applicationContext,
            requestCode(nativeCallId, ACTION_ANSWER_ACTIVITY),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    override fun fullScreen(nativeCallId: UUID): PendingIntent {
        val intent = Intent(applicationContext, MainActivity::class.java)
            .setAction(ACTION_OPEN_INCOMING_CALL)
            .setData(Uri.parse("mknoon-call://local/$nativeCallId"))
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID, nativeCallId.toString())
        return PendingIntent.getActivity(
            applicationContext,
            requestCode(nativeCallId, ACTION_OPEN_INCOMING_CALL),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun requestCode(nativeCallId: UUID, discriminator: String): Int =
        (nativeCallId.hashCode() xor discriminator.hashCode()) and Int.MAX_VALUE

    private companion object {
        const val ACTION_OPEN_INCOMING_CALL = "com.mknoon.app.call.action.OPEN_INCOMING"
        const val ACTION_ANSWER_ACTIVITY = "com.mknoon.app.call.action.ANSWER_ACTIVITY"
    }
}

/** Builds privacy-minimal call notifications for every supported Android API. */
internal class MknoonCallNotificationFactory(
    context: Context,
    private val pendingIntents: MknoonCallPendingIntentFactory =
        AndroidMknoonCallPendingIntentFactory(context),
) {
    companion object {
        // Versioned because notification-channel sound is immutable after creation.
        const val CHANNEL_ID = "mknoon_calls_ringtone_v2"
        const val ADMISSION_CHANNEL_ID = "mknoon_calls_admission_v1"
        const val NOTIFICATION_ID = 504
    }

    private val applicationContext = context.applicationContext

    fun createIncoming(
        nativeCallId: UUID,
        fullScreenAllowed: Boolean,
    ): Notification {
        ensureChannel()
        val decline = pendingIntents.action(
            nativeCallId,
            MknoonCallActionReceiver.ACTION_DECLINE,
        )
        val answer = pendingIntents.answerActivity(nativeCallId)
        val builder = builder()
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(applicationContext.getString(R.string.call_notification_title))
            .setContentText(applicationContext.getString(R.string.call_notification_incoming))
            .setCategory(Notification.CATEGORY_CALL)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Api31.applyIncoming(builder, applicationContext, decline, answer)
        } else {
            @Suppress("DEPRECATION")
            builder
                .addAction(
                    Notification.Action.Builder(
                        0,
                        applicationContext.getString(R.string.call_notification_decline),
                        decline,
                    ).build(),
                )
                .addAction(
                    Notification.Action.Builder(
                        0,
                        applicationContext.getString(R.string.call_notification_answer),
                        answer,
                    ).build(),
                )
        }
        if (fullScreenAllowed) {
            val fullScreen = pendingIntents.fullScreen(nativeCallId)
            builder.setFullScreenIntent(fullScreen, true).setContentIntent(fullScreen)
        }
        return builder.build()
    }

    fun createOngoing(nativeCallId: UUID): Notification {
        ensureChannel()
        val end = pendingIntents.action(nativeCallId, MknoonCallActionReceiver.ACTION_END)
        val builder = builder()
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(applicationContext.getString(R.string.call_notification_title))
            .setContentText(applicationContext.getString(R.string.call_notification_ongoing))
            .setCategory(Notification.CATEGORY_CALL)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Api31.applyOngoing(builder, applicationContext, end)
        } else {
            @Suppress("DEPRECATION")
            builder.addAction(
                Notification.Action.Builder(
                    0,
                    applicationContext.getString(R.string.call_notification_end),
                    end,
                ).build(),
            )
        }
        return builder.build()
    }

    private fun builder(): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(applicationContext, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(applicationContext)
        }

    /** Silent placeholder held while a pushed call is still being authenticated. */
    @Suppress("UNUSED_PARAMETER")
    fun createAdmission(nativeCallId: UUID): Notification {
        ensureAdmissionChannel()
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(applicationContext, ADMISSION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(applicationContext)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(applicationContext.getString(R.string.call_notification_title))
            .setContentText(applicationContext.getString(R.string.call_notification_admission))
            .setCategory(Notification.CATEGORY_CALL)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun ensureAdmissionChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        applicationContext.getSystemService(NotificationManager::class.java)
            .createNotificationChannel(
                NotificationChannel(
                    ADMISSION_CHANNEL_ID,
                    applicationContext.getString(R.string.call_admission_channel_name),
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                    setSound(null, null)
                    enableVibration(false)
                },
            )
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        applicationContext.getSystemService(NotificationManager::class.java)
            .createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    applicationContext.getString(R.string.call_notification_channel_name),
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = applicationContext.getString(
                        R.string.call_notification_channel_description,
                    )
                    lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                    setSound(null, null)
                    enableVibration(false)
                },
            )
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private object Api31 {
        fun applyIncoming(
            builder: Notification.Builder,
            context: Context,
            decline: PendingIntent,
            answer: PendingIntent,
        ) {
            builder.setStyle(
                Notification.CallStyle.forIncomingCall(person(context), decline, answer),
            )
        }

        fun applyOngoing(
            builder: Notification.Builder,
            context: Context,
            end: PendingIntent,
        ) {
            builder.setStyle(Notification.CallStyle.forOngoingCall(person(context), end))
        }

        private fun person(context: Context): Person = Person.Builder()
            .setName(context.getString(R.string.call_notification_person))
            .setImportant(true)
            .build()
    }
}
