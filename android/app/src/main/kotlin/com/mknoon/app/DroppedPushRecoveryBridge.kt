package com.mknoon.app

import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Flutter bridge for authoritative polling and compare-and-acknowledgement. */
class DroppedPushRecoveryBridge internal constructor(
    context: Context,
    messenger: BinaryMessenger?,
    private val store: DroppedPushRecoveryStore = DroppedPushRecoveryStore(context),
    recoverySignal: ((Long) -> Unit)? = null,
    cancelRecoveryNotification: (() -> Unit)? = null,
    private val bindingScheduler: RecoveryBindingScheduler =
        DroppedPushRecoveryWorkScheduler(context),
) : MethodChannel.MethodCallHandler {
    companion object {
        internal const val CHANNEL_NAME = "mknoon/dropped_push_recovery"
        private const val RECOVERY_PENDING_CALLBACK = "recoveryPending"
    }

    private val applicationContext = context.applicationContext
    private val methodChannel = messenger?.let { MethodChannel(it, CHANNEL_NAME) }
    private val signalRecovery: (Long) -> Unit = recoverySignal ?: { generation ->
        methodChannel?.invokeMethod(RECOVERY_PENDING_CALLBACK, generation)
    }
    private val cancelRecoveryCard: () -> Unit = cancelRecoveryNotification ?: {
        MknoonFirebaseMessagingService.cancelRecoveryNotification(
            applicationContext,
        )
    }

    init {
        methodChannel?.setMethodCallHandler(this)
        reconcileStaleRecoveryNotification()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "currentBinding" -> result.success(store.currentBinding())
            "pendingGeneration" -> result.success(readPendingGeneration())
            "pendingRecovery" -> result.success(
                store.pendingRecovery()?.let { pending ->
                    mapOf(
                        "generation" to pending.generation,
                        "binding" to pending.binding,
                    )
                },
            )
            "setCurrentBinding" -> setCurrentBinding(call, result)
            "acknowledgeGeneration" -> {
                val arguments = call.arguments as? Map<*, *>
                val generation = positiveIntegralGeneration(arguments?.get("generation"))
                if (generation == null) {
                    result.error(
                        "bad_args",
                        "generation must be a positive integer",
                        null,
                    )
                } else {
                    result.success(acknowledgeGeneration(generation))
                }
            }
            "acknowledgeRecovery" -> {
                val arguments = call.arguments as? Map<*, *>
                val generation = positiveIntegralGeneration(arguments?.get("generation"))
                val binding = (arguments?.get("binding") as? String)
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                if (generation == null || binding == null) {
                    result.error(
                        "bad_args",
                        "generation and binding are required",
                        null,
                    )
                } else {
                    result.success(
                        store.acknowledgeRecovery(
                            generation,
                            binding,
                            cancelRecoveryCard,
                        ),
                    )
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun setCurrentBinding(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        if (arguments == null || !arguments.containsKey("binding")) {
            result.error("bad_args", "binding key is required", null)
            return
        }
        val rawBinding = arguments["binding"]
        if (rawBinding != null && rawBinding !is String) {
            result.error("bad_args", "binding must be a string or null", null)
            return
        }
        val activateRecoveryWork = arguments["activateRecoveryWork"] as? Boolean ?: false
        val rotation = store.setCurrentBinding(
            rawBinding as? String,
            recoveryWorkEnabled = activateRecoveryWork,
        )
        if (!rotation.committed) {
            result.error("persistence_failed", "binding rotation was not committed", null)
            return
        }
        bindingScheduler.onBindingRotated(rotation)
        if (rotation.retiredRecovery != null) {
            cancelRecoveryCard()
        }
        result.success(
            mapOf(
                "changed" to rotation.changed,
                "committed" to rotation.committed,
                "currentBinding" to rotation.currentBinding,
                "retiredGeneration" to rotation.retiredRecovery?.generation,
                "recoveryWorkEnabled" to rotation.recoveryWorkEnabled,
            ),
        )
    }

    fun acknowledgeGeneration(generation: Long): Boolean =
        store.acknowledgeGeneration(generation, cancelRecoveryCard)

    /** Warm-intent acceleration only; the committed marker remains authoritative. */
    fun onWarmIntent(intent: Intent): Boolean {
        if (intent.action != MknoonFirebaseMessagingService.RECOVERY_INTENT_ACTION) {
            return false
        }
        val generation = readPendingGeneration() ?: return false
        signalRecovery(generation)
        return true
    }

    private fun readPendingGeneration(): Long? {
        val generation = store.pendingGeneration()
        if (generation == null) reconcileStaleRecoveryNotification()
        return generation
    }

    private fun reconcileStaleRecoveryNotification() {
        store.reconcileNoPendingGeneration(cancelRecoveryCard)
    }

    private fun positiveIntegralGeneration(value: Any?): Long? {
        val generation = when (value) {
            is Byte -> value.toLong()
            is Short -> value.toLong()
            is Int -> value.toLong()
            is Long -> value
            else -> return null
        }
        return generation.takeIf { it > 0L }
    }

    fun dispose() {
        methodChannel?.setMethodCallHandler(null)
    }
}
