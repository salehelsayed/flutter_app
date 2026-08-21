package com.mknoon.app

import android.app.Activity
import android.app.Notification
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import com.davidmartos96.sqflite_sqlcipher.SqfliteSqlCipherPlugin
import com.dexterous.flutterlocalnotifications.FlutterLocalNotificationsPlugin
import com.it_nomads.fluttersecurestorage.FlutterSecureStoragePlugin
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugins.firebase.core.FlutterFirebaseCorePlugin
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingPlugin
import io.flutter.plugins.pathprovider.PathProviderPlugin
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONArray
import org.json.JSONObject

/** Debug-only no-Activity proof of the Plan 331A canonical runtime boundary. */
class CanonicalRuntimeH0ProbeReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION = "com.mknoon.app.debug.CANONICAL_RUNTIME_H0_PROBE"
        const val EXTRA_HANDOFF = "handoff"
        const val EXTRA_QUEUE_INVERSION = "queueInversion"
        const val EXTRA_RUN_NONCE = "runNonce"
        const val EXTRA_PLAN374_PHASE = "plan374Phase"
        private const val RESULT_CHANNEL = "mknoon/canonical_runtime_h0_probe"
        private const val PLAN374_RESULT_CHANNEL =
            "mknoon/headless_recovery_374_fixture"
        private const val RESULT_DIRECTORY = "h0-probe"
        private const val PLAN374_RESULT_DIRECTORY = "plan374-headless-recovery"
        private const val RESULT_FILE = "latest.json"
        private const val PHASE_TIMEOUT_MS = 40_000L
        private const val QUEUE_INVERSION_HARD_TIMEOUT_MS = 8_000L
        private const val QUEUE_INVERSION_WATCHDOG_MS = 4_000L

        // Hidden platform Notification flag with a stable AOSP/CTS value. The
        // system sets it on autogroup summaries it creates itself, including
        // the API 36+ silent-section aggregate summary.
        private const val FLAG_AUTOGROUP_SUMMARY = 0x00000400
        private val running = AtomicBoolean(false)

        private val pluginAllowlist = listOf(
            "flutter_secure_storage",
            "sqflite_sqlcipher",
            "flutter_local_notifications",
            "firebase_core",
            "firebase_messaging",
            "app_canonical_runtime_lease",
            "app_dropped_push_binding",
            "app_go_bridge",
            "app_probe_result",
        )
    }

    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        val applicationContext = context.applicationContext
        val mainHandler = Handler(Looper.getMainLooper())
        if (intent.action != ACTION) {
            pending.resultCode = Activity.RESULT_CANCELED
            pending.resultData = "wrong_action"
            pending.finish()
            return
        }
        if (!running.compareAndSet(false, true)) {
            pending.resultCode = Activity.RESULT_CANCELED
            pending.resultData = "probe_already_running"
            pending.finish()
            return
        }

        val finishProbe = { artifact: JSONObject, passed: Boolean ->
            val rendered = artifact.toString()
            val directory = File(applicationContext.filesDir, RESULT_DIRECTORY)
            directory.mkdirs()
            File(directory, RESULT_FILE).writeText(rendered)
            pending.resultCode = if (passed) {
                Activity.RESULT_OK
            } else {
                Activity.RESULT_CANCELED
            }
            pending.resultData = rendered
            running.set(false)
            pending.finish()
        }
        val plan374Phase = intent.getStringExtra(EXTRA_PLAN374_PHASE)?.trim()
        if (!plan374Phase.isNullOrEmpty()) {
            val runNonce = intent.getStringExtra(EXTRA_RUN_NONCE).orEmpty()
            val finishPlan374 = { artifact: JSONObject, passed: Boolean ->
                val directory = File(
                    applicationContext.filesDir,
                    PLAN374_RESULT_DIRECTORY,
                )
                directory.mkdirs()
                File(directory, "$plan374Phase-latest.json")
                    .writeText(artifact.toString())
                pending.resultCode = if (passed) {
                    Activity.RESULT_OK
                } else {
                    Activity.RESULT_CANCELED
                }
                pending.resultData = artifact.toString()
                running.set(false)
                pending.finish()
            }
            if (runNonce.isBlank()) {
                finishPlan374(
                    JSONObject()
                        .put("status", "FAIL")
                        .put("phase", plan374Phase)
                        .put("failure", "missing runNonce broadcast extra"),
                    false,
                )
                return
            }
            if (plan374Phase == "arm-fixed-wake") {
                val store = DroppedPushRecoveryStore(applicationContext)
                val before = store.recoveryAuthority()
                val armed = before.currentBinding != null &&
                    before.recoveryWorkEnabled &&
                    before.pendingRecovery == null &&
                    Plan374ProcessDeathBarrier.arm(
                        applicationContext,
                        runNonce,
                    )
                val after = store.recoveryAuthority()
                val passed = armed &&
                    after.currentBinding == before.currentBinding &&
                    after.recoveryWorkEnabled &&
                    after.pendingRecovery == null
                finishPlan374(
                    JSONObject()
                        .put("status", if (passed) "PASS" else "FAIL")
                        .put("phase", plan374Phase)
                        .put("runNonce", runNonce)
                        .put("processDeathBarrierArmed", armed)
                        .put("productionIngressInvoked", false)
                        .put("bindingBefore", before.currentBinding)
                        .put("bindingAfter", after.currentBinding)
                        .put("recoveryWorkEnabled", after.recoveryWorkEnabled)
                        .put("pendingGenerationBefore", before.pendingRecovery?.generation)
                        .put("pendingGenerationAfter", after.pendingRecovery?.generation)
                        .put("mainActivityLaunchCount", 0)
                        .put("pid", Process.myPid()),
                    passed,
                )
                return
            }
            if (plan374Phase == "fixed-wake") {
                val store = DroppedPushRecoveryStore(applicationContext)
                val before = store.recoveryAuthority()
                val processDeathBarrierArmed = Plan374ProcessDeathBarrier.arm(
                    applicationContext,
                    runNonce,
                )
                // Drive the REAL production service ingress: classifier, seam,
                // silent generic card and WorkManager scheduling. Direct
                // preference writes or direct enqueue would not prove ingress.
                val ingressService = DebugFixedWakeIngressService(applicationContext)
                val richCanary = com.google.firebase.messaging.debugRemoteMessageFromBundle(
                    android.os.Bundle().apply {
                        putString("v", "1")
                        putString("w", "1")
                        putString("x", "1")
                    },
                )
                ingressService.onMessageReceived(richCanary)
                val delegatedBeforeFixed = ingressService.delegatedCount
                val exactFixed = com.google.firebase.messaging.debugRemoteMessageFromBundle(
                    android.os.Bundle().apply {
                        putString("v", "1")
                        putString("w", "1")
                    },
                )
                ingressService.onMessageReceived(exactFixed)
                if (store.pendingRecovery() == null) {
                    Plan374ProcessDeathBarrier.disarm(applicationContext)
                }
                val after = store.recoveryAuthority()
                val committed = after.pendingRecovery
                val postedCard = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    applicationContext.getSystemService(NotificationManager::class.java)
                        .activeNotifications.firstOrNull { posted ->
                            posted.tag ==
                                MknoonFirebaseMessagingService.RECOVERY_NOTIFICATION_TAG &&
                                posted.id ==
                                MknoonFirebaseMessagingService.RECOVERY_NOTIFICATION_ID
                        }
                } else {
                    null
                }
                // Requested-silence facts that survive the OS post: no sound
                // URI, no sound/vibrate defaults, no vibrate pattern, and the
                // summary-only alert behavior. The app-requested "silent"
                // group itself is NOT stable evidence on API 36+: forced
                // auto-grouping may strip a sparse app group at post time and
                // regroup the card under the system silent-section aggregate,
                // so the group and override-group facts are recorded verbatim
                // instead of asserted. Robolectric TC-375-01 owns the exact
                // pre-post builder request including the group key.
                @Suppress("DEPRECATION")
                val cardRequestedSilent = postedCard != null &&
                    postedCard.notification.sound == null &&
                    postedCard.notification.defaults == 0 &&
                    postedCard.notification.vibrate == null &&
                    postedCard.notification.groupAlertBehavior ==
                    Notification.GROUP_ALERT_SUMMARY
                val passed = before.currentBinding != null &&
                    before.recoveryWorkEnabled &&
                    processDeathBarrierArmed &&
                    delegatedBeforeFixed == 1 &&
                    ingressService.delegatedCount == 1 &&
                    committed != null &&
                    committed.triggerKind ==
                    DroppedPushRecoveryStore.TriggerKind.FIXED_WAKE &&
                    postedCard != null &&
                    cardRequestedSilent
                finishPlan374(
                    JSONObject()
                        .put("status", if (passed) "PASS" else "FAIL")
                        .put("phase", plan374Phase)
                        .put("runNonce", runNonce)
                        .put("productionFixedIngressSeam", true)
                        .put("processDeathBarrierArmed", processDeathBarrierArmed)
                        .put("recoveryWorkEnabledBefore", before.recoveryWorkEnabled)
                        .put("bindingBefore", before.currentBinding)
                        .put("richCanaryDelegatedOnce", delegatedBeforeFixed == 1)
                        .put("fixedDelegated", ingressService.delegatedCount != 1)
                        .put("committedGeneration", committed?.generation)
                        .put("committedBinding", committed?.binding)
                        .put("committedTriggerKind", committed?.triggerKind?.name)
                        .put(
                            "committedGenericMayHaveAlerted",
                            committed?.genericMayHaveAlerted,
                        )
                        .put("genericCardPresent", postedCard != null)
                        .put("genericCardRequestedSilent", cardRequestedSilent)
                        .put("genericCardSoundUri", postedCard?.notification?.sound?.toString())
                        .put("genericCardDefaults", postedCard?.notification?.defaults)
                        .put(
                            "genericCardVibratePattern",
                            @Suppress("DEPRECATION")
                            postedCard?.notification?.vibrate?.joinToString(","),
                        )
                        .put("genericCardGroup", postedCard?.notification?.group)
                        .put("genericCardOverrideGroupKey", postedCard?.overrideGroupKey)
                        .put("genericCardSystemGroupKey", postedCard?.groupKey)
                        .put(
                            "genericCardGroupAlertBehavior",
                            postedCard?.notification?.groupAlertBehavior,
                        )
                        .put(
                            "genericCardOnlyAlertOnce",
                            postedCard?.notification?.flags?.let { flags ->
                                flags and Notification.FLAG_ONLY_ALERT_ONCE != 0
                            },
                        )
                        .put(
                            "immediateUniqueWorkName",
                            committed?.binding?.let(
                                DroppedPushRecoveryWorkScheduler::immediateUniqueName,
                            ),
                        )
                        .put("mainActivityLaunchCount", 0)
                        .put("pid", Process.myPid()),
                    passed,
                )
                return
            }
            if (plan374Phase == "deleted-batch") {
                val store = DroppedPushRecoveryStore(applicationContext)
                val before = store.recoveryAuthority()
                val processDeathBarrierArmed = Plan374ProcessDeathBarrier.arm(
                    applicationContext,
                    runNonce,
                )
                val committed = ProductionDeletedBatchRecovery(
                    applicationContext,
                ).commitAndSchedule()
                if (committed == null) {
                    Plan374ProcessDeathBarrier.disarm(applicationContext)
                }
                val after = store.recoveryAuthority()
                val passed = before.currentBinding != null &&
                    before.recoveryWorkEnabled &&
                    processDeathBarrierArmed &&
                    committed != null &&
                    committed == after.pendingRecovery
                finishPlan374(
                    JSONObject()
                        .put("status", if (passed) "PASS" else "FAIL")
                        .put("phase", plan374Phase)
                        .put("runNonce", runNonce)
                        .put("productionDeletedBatchSeam", true)
                        .put("processDeathBarrierArmed", processDeathBarrierArmed)
                        .put("recoveryWorkEnabledBefore", before.recoveryWorkEnabled)
                        .put("bindingBefore", before.currentBinding)
                        .put("committedGeneration", committed?.generation)
                        .put("committedBinding", committed?.binding)
                        .put("pendingGenerationAfter", after.pendingRecovery?.generation)
                        .put("pendingBindingAfter", after.pendingRecovery?.binding)
                        .put(
                            "immediateUniqueWorkName",
                            committed?.binding?.let(
                                DroppedPushRecoveryWorkScheduler::immediateUniqueName,
                            ),
                        )
                        .put("mainActivityLaunchCount", 0)
                        .put("pid", Process.myPid()),
                    passed,
                )
                return
            }
            val runner = Plan374FixtureRunner(
                applicationContext = applicationContext,
                mainHandler = mainHandler,
                phase = plan374Phase,
                runNonce = runNonce,
                finish = finishPlan374,
            )
            mainHandler.post(runner::start)
            return
        }
        if (intent.getBooleanExtra(EXTRA_QUEUE_INVERSION, false)) {
            val runner = QueueInversionRunner(
                applicationContext = applicationContext,
                mainHandler = mainHandler,
                runNonce = intent.getStringExtra(EXTRA_RUN_NONCE).orEmpty(),
                finish = finishProbe,
            )
            mainHandler.post(runner::start)
            return
        }

        val phases = if (intent.getBooleanExtra(EXTRA_HANDOFF, false)) {
            listOf("recovery-handoff", "foreground")
        } else {
            listOf("recovery")
        }
        val runner = ProbeRunner(
            applicationContext = applicationContext,
            mainHandler = mainHandler,
            phases = phases,
            finish = finishProbe,
        )
        mainHandler.post(runner::start)
    }

    /** Seed/inspect only; the recovery phase itself is owned by WorkManager. */
    private class Plan374FixtureRunner(
        private val applicationContext: Context,
        private val mainHandler: Handler,
        private val phase: String,
        private val runNonce: String,
        private val finish: (JSONObject, Boolean) -> Unit,
    ) {
        private var completed = false
        private var engine: FlutterEngine? = null
        private var resultChannel: MethodChannel? = null
        private var leaseBridge: CanonicalRuntimeLeaseBridge? = null
        private var droppedPushBridge: DroppedPushRecoveryBridge? = null
        private var goBridge: GoBridge? = null

        fun start() {
            check(Looper.myLooper() == Looper.getMainLooper())
            if (phase != "seed" && phase != "inspect") {
                finishTerminal(emptyMap<Any?, Any?>(), false, "unsupported phase")
                return
            }
            val created = FlutterEngine(applicationContext, null, false)
            engine = created
            created.plugins.add(FlutterSecureStoragePlugin())
            created.plugins.add(SqfliteSqlCipherPlugin())
            created.plugins.add(FlutterLocalNotificationsPlugin())
            created.plugins.add(PathProviderPlugin())
            leaseBridge = CanonicalRuntimeLeaseBridge(
                messenger = created.dartExecutor.binaryMessenger,
                ownerId = "plan374-$phase-${System.identityHashCode(created)}",
                role = CanonicalRuntimeLeaseBroker.Role.FOREGROUND,
                attachRuntimeOwner = {
                    if (goBridge == null) {
                        goBridge = runCatching {
                            GoBridge(created, applicationContext)
                        }.getOrNull()
                    }
                    goBridge != null
                },
                beginRuntimeDrain = { goBridge?.requestRuntimeDrain() ?: true },
                isRuntimeReleased = { goBridge?.isRuntimeReleased() ?: true },
            )
            droppedPushBridge = DroppedPushRecoveryBridge(
                applicationContext,
                created.dartExecutor.binaryMessenger,
            )
            resultChannel = MethodChannel(
                created.dartExecutor.binaryMessenger,
                PLAN374_RESULT_CHANNEL,
            ).also { channel ->
                channel.setMethodCallHandler { call, result ->
                    val payload = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
                    when (call.method) {
                        "complete" -> {
                            result.success(null)
                            finishTerminal(payload, true, null)
                        }
                        "failed" -> {
                            result.success(null)
                            finishTerminal(payload, false, "Dart fixture failed")
                        }
                        else -> result.notImplemented()
                    }
                }
            }
            val loader = FlutterInjector.instance().flutterLoader()
            created.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    loader.findAppBundlePath(),
                    "androidHeadlessRecovery374FixtureMain",
                ),
                listOf(phase, runNonce),
            )
            mainHandler.postDelayed({
                if (!completed) {
                    finishTerminal(
                        emptyMap<Any?, Any?>(),
                        false,
                        "fixture phase exceeded $PHASE_TIMEOUT_MS ms",
                    )
                }
            }, PHASE_TIMEOUT_MS)
        }

        private fun finishTerminal(
            payload: Map<*, *>,
            dartSucceeded: Boolean,
            failure: String?,
        ) {
            if (completed) return
            completed = true
            check(Looper.myLooper() == Looper.getMainLooper())
            resultChannel?.setMethodCallHandler(null)
            resultChannel = null
            droppedPushBridge?.dispose()
            droppedPushBridge = null
            leaseBridge?.dispose()
            leaseBridge = null
            goBridge?.dispose()
            goBridge = null
            engine?.destroy()
            engine = null

            val store = DroppedPushRecoveryStore(applicationContext)
            val authority = store.recoveryAuthority()
            val lease = ProcessCanonicalRuntimeLease.broker.snapshot()
            val go = ProcessGoRuntimeHost.instance.snapshot()
            val active = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                applicationContext.getSystemService(NotificationManager::class.java)
                    .activeNotifications
            } else {
                emptyArray()
            }
            val activeCards = JSONArray().also { cards ->
                active.forEach { notification ->
                    cards.put(
                        JSONObject()
                            .put("id", notification.id)
                            .put("tag", notification.tag)
                            .put("category", notification.notification.category)
                            .put("visibility", notification.notification.visibility)
                            .put("flags", notification.notification.flags)
                            .put(
                                "systemAutogroupSummary",
                                (notification.notification.flags and FLAG_AUTOGROUP_SUMMARY) != 0,
                            )
                            .put(
                                "channelId",
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                    notification.notification.channelId
                                } else {
                                    null
                                },
                            ),
                    )
                }
            }
            val expectedCardIds = mutableSetOf<Int>()
            val ledgerRecords = (payload["ledgerRecords"] as? Iterable<*>)
                ?.mapNotNull { it as? Map<*, *> }
                ?: emptyList()
            ledgerRecords.forEach { record ->
                if (
                    record["presentationState"] == "OS_POSTED" &&
                    (
                        record["producerKind"] == "direct_message" ||
                            record["producerKind"] == "group_message"
                    )
                ) {
                    (record["notificationId"] as? Number)?.toInt()?.let(expectedCardIds::add)
                }
            }
            val exactSettledLedger = ledgerRecords.size == 2 &&
                ledgerRecords.map { it["producerKind"] }.toSet() ==
                setOf("direct_message", "group_message") &&
                ledgerRecords.all {
                    it["sourceCustody"] == "SQL_READY" &&
                        it["presentationOwner"] == "INBOX_RECONCILER" &&
                        it["presentationState"] == "OS_POSTED" &&
                        it["effectPhase"] == "SETTLED"
                }
            // Newer Android images bundle silent app cards under a
            // system-created autogroup summary (FLAG_AUTOGROUP_SUMMARY, e.g.
            // the API 36+ Aggregate_SilentSection row). That summary is
            // system-owned presentation, not an app-posted card, so the exact
            // invariant is: both expected app cards present and zero
            // unexpected app-posted extras.
            val systemAutogroupSummaries = active.filter {
                (it.notification.flags and FLAG_AUTOGROUP_SUMMARY) != 0
            }
            val appPostedCards = active.filterNot {
                (it.notification.flags and FLAG_AUTOGROUP_SUMMARY) != 0
            }
            val unexpectedAppPostedCards =
                appPostedCards.filter { it.id !in expectedCardIds }
            val matchingCards = appPostedCards.filter { it.id in expectedCardIds }
            val privateMessageCards = matchingCards.count {
                it.notification.visibility == Notification.VISIBILITY_PRIVATE &&
                    it.notification.category == Notification.CATEGORY_MESSAGE
            }
            val custody = payload[if (phase == "seed") "custodyBefore" else "custodyAfter"]
                as? Map<*, *>
            val custodyValues = custody?.values?.mapNotNull { (it as? Number)?.toInt() }
                ?: emptyList()
            val basePassed = dartSucceeded &&
                payload["runNonce"] == runNonce &&
                payload["phase"] == phase &&
                payload["databaseUserVersion"] == 116 &&
                payload["cipherVersion"]?.toString()?.isNotBlank() == true &&
                lease.state == CanonicalRuntimeLeaseBroker.State.RELEASED &&
                go.state == GoRuntimeHost.State.RELEASED &&
                !isHeadlessCanonicalRecoveryEngineRetained()
            val phasePassed = when (phase) {
                "seed" -> basePassed &&
                    payload["databaseClosed"] == true &&
                    custodyValues.size == 4 && custodyValues.all { it > 0 } &&
                    authority.currentBinding == payload["binding"] &&
                    authority.recoveryWorkEnabled &&
                    authority.pendingRecovery == null
                "inspect" -> basePassed &&
                    payload["databaseClosed"] == true &&
                    payload["quickCheck"]?.toString()?.equals("ok", true) == true &&
                    payload["identityPresent"] == true &&
                    custodyValues.size == 4 && custodyValues.all { it == 0 } &&
                    (payload["settledSqlReadyInboxReconcilerCount"] as? Number)
                        ?.toInt() == 2 &&
                    exactSettledLedger &&
                    expectedCardIds.size == 2 &&
                    matchingCards.size == 2 &&
                    privateMessageCards == 2 &&
                    appPostedCards.size == 2 &&
                    unexpectedAppPostedCards.isEmpty() &&
                    authority.pendingRecovery == null
                else -> false
            }
            val artifact = JSONObject()
                .put("status", if (phasePassed) "PASS" else "FAIL")
                .put("phase", phase)
                .put("runNonce", runNonce)
                .put("entrypoint", "androidHeadlessRecovery374FixtureMain")
                .put("dartSucceeded", dartSucceeded)
                .put("dart", jsonValue(payload))
                .put("failure", failure)
                .put("pid", Process.myPid())
                .put("sdkInt", Build.VERSION.SDK_INT)
                .put("device", "${Build.MANUFACTURER} ${Build.MODEL}".trim())
                .put("mainActivityLaunchCount", 0)
                .put("applicationRootConstructed", false)
                .put("fixtureEngineDestroyed", engine == null)
                .put("finalLeaseState", lease.state.name)
                .put("finalGoState", go.state.name)
                .put("headlessRecoveryEngineRetained", isHeadlessCanonicalRecoveryEngineRetained())
                .put("recoveryWorkEnabled", authority.recoveryWorkEnabled)
                .put("currentBinding", authority.currentBinding)
                .put("pendingGeneration", authority.pendingRecovery?.generation)
                .put("pendingBinding", authority.pendingRecovery?.binding)
                .put("expectedCardIds", JSONArray(expectedCardIds.toList().sorted()))
                .put("matchingCardCount", matchingCards.size)
                .put("privateMessageCardCount", privateMessageCards)
                .put("appPostedCardCount", appPostedCards.size)
                .put("unexpectedAppPostedCardCount", unexpectedAppPostedCards.size)
                .put("systemAutogroupSummaryCount", systemAutogroupSummaries.size)
                .put("exactSettledLedger", exactSettledLedger)
                .put("activeNotifications", activeCards)
            finish(artifact, phasePassed)
        }

        private fun jsonValue(value: Any?): Any? = when (value) {
            null -> JSONObject.NULL
            is Map<*, *> -> JSONObject().also { target ->
                value.forEach { (key, nested) ->
                    target.put(key.toString(), jsonValue(nested))
                }
            }
            is Iterable<*> -> JSONArray().also { target ->
                value.forEach { nested -> target.put(jsonValue(nested)) }
            }
            else -> value
        }
    }

    /**
     * Deterministic device fixture for the upstream sqflite_sqlcipher process-wide
     * worker inversion. The two database engines are deliberately independent;
     * native acknowledgements establish the exact queue order before the writer
     * is resumed.
     */
    private class QueueInversionRunner(
        private val applicationContext: Context,
        private val mainHandler: Handler,
        private val runNonce: String,
        private val finish: (JSONObject, Boolean) -> Unit,
    ) {
        private val startedAtNanos = System.nanoTime()
        private val orderedPhases = JSONArray()
        private var completed = false
        private var causalWatchdogArmed = false
        private var greenTeardownStarted = false
        private var workerCensusWaitStartedAtNanos = 0L
        private var liveEngineCount = 0
        private var peakLiveEngineCount = 0
        private var peakLivePluginWorkerCount = 0
        private var peakLivePluginHandleCount = 0

        private var writerCipherVersion: String? = null
        private var readerCipherVersion: String? = null
        private var writerJournalMode: String? = null

        private var writerEngine: FlutterEngine? = null
        private var readerEngine: FlutterEngine? = null
        private var sentinelEngine: FlutterEngine? = null
        private var writerChannel: MethodChannel? = null
        private var readerChannel: MethodChannel? = null
        private var sentinelChannel: MethodChannel? = null

        private var writerOpenReply: MethodChannel.Result? = null
        private var readerReadyReply: MethodChannel.Result? = null
        private var readerOpenReply: MethodChannel.Result? = null
        private var writerBeginReply: MethodChannel.Result? = null

        private var writerDatabaseOpened = false
        private var readerDatabaseOpened = false
        private var writerBeginExclusive = false
        private var readerQueryPosted = false
        private var writerResumeRequested = false
        private var writerCommit = false
        private var readerQueryResult = false
        private var writerClosed = false
        private var readerClosed = false
        private var sentinelOpened = false
        private var sentinelVerified = false
        private var sentinelClosed = false
        private var writerEngineDestroyed = false
        private var readerEngineDestroyed = false
        private var sentinelEngineDestroyed = false

        fun start() {
            check(Looper.myLooper() == Looper.getMainLooper())
            if (runNonce.isBlank()) {
                finishTerminal(
                    status = "FAIL",
                    watchdogFired = false,
                    failure = "missing runNonce broadcast extra",
                )
                return
            }
            // Start both isolates together so cold Flutter startup is outside
            // the causal four-second observation. The reader reports ready and
            // remains fenced from the database until the writer creates it.
            startWriter()
            startReader()
            mainHandler.postDelayed({
                if (!completed) {
                    finishTerminal(
                        status = "FAIL",
                        watchdogFired = false,
                        failure =
                            "queue inversion terminal artifact exceeded " +
                                "$QUEUE_INVERSION_HARD_TIMEOUT_MS ms",
                    )
                }
            }, QUEUE_INVERSION_HARD_TIMEOUT_MS)
        }

        private fun startWriter() {
            check(Looper.myLooper() == Looper.getMainLooper())
            val engine = newSqlCipherEngine()
            writerEngine = engine
            val channel = MethodChannel(
                engine.dartExecutor.binaryMessenger,
                RESULT_CHANNEL,
            )
            writerChannel = channel
            channel.setMethodCallHandler { call, result ->
                val payload = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
                if (completed) {
                    result.error("probe_completed", "queue inversion probe completed", null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "queueWriterDatabaseOpened" -> {
                        if (writerDatabaseOpened || writerOpenReply != null) {
                            result.error(
                                "duplicate_writer_open",
                                "writer database was already reported open",
                                null,
                            )
                        } else {
                            writerCipherVersion = payloadText(payload, "cipherVersion")
                            writerJournalMode = payloadText(payload, "journalMode")
                            writerDatabaseOpened = true
                            recordPhase("writer.database_opened")
                            writerOpenReply = result
                            readerReadyReply?.success(null)
                            readerReadyReply = null
                        }
                    }
                    "queueWriterBeginExclusive" -> {
                        if (!readerDatabaseOpened || writerBeginExclusive) {
                            result.error(
                                "invalid_writer_begin",
                                "reader must be open exactly once before writer BEGIN",
                                null,
                            )
                        } else {
                            writerBeginExclusive = true
                            recordPhase("writer.begin_exclusive")
                            writerBeginReply = result
                            val pendingReaderOpen = readerOpenReply
                            readerOpenReply = null
                            if (pendingReaderOpen == null) {
                                failProtocol("reader open acknowledgement was not pending")
                            } else {
                                pendingReaderOpen.success(null)
                            }
                        }
                    }
                    "queueWriterCommit" -> {
                        writerCommit = true
                        recordPhase("writer.commit")
                        result.success(null)
                        maybeFinishGreenDatabaseLegs()
                    }
                    "queueWriterClosed" -> {
                        writerClosed = true
                        recordPhase("writer.closed")
                        result.success(null)
                        maybeFinishGreenDatabaseLegs()
                    }
                    "queueWriterFailed" -> {
                        result.success(null)
                        finishTerminal(
                            status = "FAIL",
                            watchdogFired = false,
                            failure = "writer failed: ${jsonValue(payload)}",
                        )
                    }
                    else -> result.notImplemented()
                }
            }
            executeQueueEntrypoint(engine, "queue-inversion-writer")
        }

        private fun startReader() {
            check(Looper.myLooper() == Looper.getMainLooper())
            if (readerEngine != null) {
                failProtocol("reader engine was started more than once")
                return
            }
            val engine = newSqlCipherEngine()
            readerEngine = engine
            val channel = MethodChannel(
                engine.dartExecutor.binaryMessenger,
                RESULT_CHANNEL,
            )
            readerChannel = channel
            channel.setMethodCallHandler { call, result ->
                val payload = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
                if (completed) {
                    result.error("probe_completed", "queue inversion probe completed", null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "queueReaderReady" -> {
                        if (readerReadyReply != null) {
                            result.error(
                                "duplicate_reader_ready",
                                "reader isolate was already reported ready",
                                null,
                            )
                        } else if (writerDatabaseOpened) {
                            result.success(null)
                        } else {
                            readerReadyReply = result
                        }
                    }
                    "queueReaderDatabaseOpened" -> {
                        if (readerDatabaseOpened || readerOpenReply != null) {
                            result.error(
                                "duplicate_reader_open",
                                "reader database was already reported open",
                                null,
                            )
                        } else {
                            readerCipherVersion = payloadText(payload, "cipherVersion")
                            readerDatabaseOpened = true
                            recordPhase("reader.database_opened")
                            readerOpenReply = result
                            val pendingWriterOpen = writerOpenReply
                            writerOpenReply = null
                            if (pendingWriterOpen == null) {
                                failProtocol("writer open acknowledgement was not pending")
                            } else {
                                pendingWriterOpen.success(null)
                            }
                        }
                    }
                    "queueReaderQueryPosted" -> {
                        if (
                            !writerBeginExclusive ||
                            readerQueryPosted ||
                            writerBeginReply == null
                        ) {
                            result.error(
                                "invalid_reader_query",
                                "writer BEGIN must be pending before the reader query",
                                null,
                            )
                        } else {
                            readerQueryPosted = true
                            recordPhase("reader.query_posted")
                            writerResumeRequested = true
                            recordPhase("writer.resume_requested")
                            val pendingWriterBegin = writerBeginReply
                            writerBeginReply = null
                            pendingWriterBegin?.success(null)
                            result.success(null)
                            armCausalWatchdog()
                        }
                    }
                    "queueReaderQueryResult" -> {
                        readerQueryResult = true
                        recordPhase("reader.query_result")
                        result.success(null)
                        maybeFinishGreenDatabaseLegs()
                    }
                    "queueReaderClosed" -> {
                        readerClosed = true
                        recordPhase("reader.closed")
                        result.success(null)
                        maybeFinishGreenDatabaseLegs()
                    }
                    "queueReaderFailed" -> {
                        result.success(null)
                        finishTerminal(
                            status = "FAIL",
                            watchdogFired = false,
                            failure = "reader failed: ${jsonValue(payload)}",
                        )
                    }
                    else -> result.notImplemented()
                }
            }
            executeQueueEntrypoint(engine, "queue-inversion-reader")
        }

        private fun armCausalWatchdog() {
            if (causalWatchdogArmed) return
            causalWatchdogArmed = true
            mainHandler.postDelayed({
                if (completed) return@postDelayed
                val exactUpstreamInversion =
                    hasRequiredCausalPrefix() &&
                        readerQueryPosted &&
                        writerResumeRequested &&
                        !writerCommit &&
                        !readerQueryResult
                val acceptedUpstreamInversion =
                    exactUpstreamInversion && sqlCipherRuntimeIdentityVerified()
                finishTerminal(
                    status = if (acceptedUpstreamInversion) "EXPECTED_RED" else "FAIL",
                    watchdogFired = true,
                    failure = if (acceptedUpstreamInversion) {
                        "upstream process-wide FIFO deadlocked writer behind reader"
                    } else if (exactUpstreamInversion) {
                        "queue inversion reached the stall without verified SQLCipher identity"
                    } else {
                        "queue inversion did not reach either accepted terminal state"
                    },
                )
            }, QUEUE_INVERSION_WATCHDOG_MS)
        }

        private fun maybeFinishGreenDatabaseLegs() {
            if (
                completed ||
                greenTeardownStarted ||
                !writerCommit ||
                !readerQueryResult ||
                !writerClosed ||
                !readerClosed
            ) {
                return
            }
            greenTeardownStarted = true
            mainHandler.post {
                if (completed) return@post
                destroyWriterAndReader()
                startSentinel()
            }
        }

        private fun destroyWriterAndReader() {
            check(Looper.myLooper() == Looper.getMainLooper())
            writerChannel?.setMethodCallHandler(null)
            writerChannel = null
            writerEngine?.destroy()
            writerEngine = null
            writerEngineDestroyed = true
            liveEngineCount -= 1
            recordPhase("writer.engine_destroyed")

            readerChannel?.setMethodCallHandler(null)
            readerChannel = null
            readerEngine?.destroy()
            readerEngine = null
            readerEngineDestroyed = true
            liveEngineCount -= 1
            recordPhase("reader.engine_destroyed")
        }

        private fun startSentinel() {
            check(Looper.myLooper() == Looper.getMainLooper())
            val engine = newSqlCipherEngine()
            sentinelEngine = engine
            val channel = MethodChannel(
                engine.dartExecutor.binaryMessenger,
                RESULT_CHANNEL,
            )
            sentinelChannel = channel
            channel.setMethodCallHandler { call, result ->
                val payload = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
                if (completed) {
                    result.error("probe_completed", "queue inversion probe completed", null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "queueSentinelDatabaseOpened" -> {
                        sentinelOpened = true
                        recordPhase("sentinel.database_opened")
                        result.success(null)
                    }
                    "queueSentinelVerified" -> {
                        if (!sentinelOpened) {
                            result.error(
                                "sentinel_not_open",
                                "fresh sentinel verified before its database opened",
                                null,
                            )
                        } else {
                            sentinelVerified = true
                            recordPhase("sentinel.verified")
                            result.success(null)
                        }
                    }
                    "queueSentinelClosed" -> {
                        sentinelClosed = true
                        recordPhase("sentinel.closed")
                        result.success(null)
                        mainHandler.post(::finishGreenAfterSentinel)
                    }
                    "queueSentinelFailed" -> {
                        result.success(null)
                        finishTerminal(
                            status = "FAIL",
                            watchdogFired = false,
                            failure = "fresh sentinel failed: ${jsonValue(payload)}",
                        )
                    }
                    else -> result.notImplemented()
                }
            }
            executeQueueEntrypoint(engine, "queue-inversion-sentinel")
        }

        private fun finishGreenAfterSentinel() {
            if (completed) return
            if (!sentinelOpened || !sentinelVerified || !sentinelClosed) {
                failProtocol("fresh sentinel closed without complete verification")
                return
            }
            sentinelChannel?.setMethodCallHandler(null)
            sentinelChannel = null
            sentinelEngine?.destroy()
            sentinelEngine = null
            sentinelEngineDestroyed = true
            liveEngineCount -= 1
            recordPhase("sentinel.engine_destroyed")

            val enginesDestroyed =
                writerEngineDestroyed && readerEngineDestroyed && sentinelEngineDestroyed
            if (liveEngineCount != 0 || !enginesDestroyed) {
                finishTerminal(
                    status = "FAIL",
                    watchdogFired = false,
                    failure = "engine census was not zero after green teardown",
                )
                return
            }
            workerCensusWaitStartedAtNanos = System.nanoTime()
            finishGreenWhenWorkerCensusSettles()
        }

        private fun finishGreenWhenWorkerCensusSettles() {
            if (completed) return
            val census = sqfliteDebugCensus()
            fun value(name: String): Int = (census?.get(name) as? Number)?.toInt() ?: -1
            val settled =
                value("liveInstances") == 0 &&
                    value("liveWorkers") == 0 &&
                    value("liveHandles") == 0 &&
                    value("queuedTasks") == 0 &&
                    value("runningTasks") == 0 &&
                    value("terminatedInstances") >= 3
            if (settled) {
                finishTerminal(status = "PASS", watchdogFired = false, failure = null)
                return
            }
            val waitedMs =
                (System.nanoTime() - workerCensusWaitStartedAtNanos) / 1_000_000L
            if (waitedMs >= 1_000L) {
                finishTerminal(
                    status = "FAIL",
                    watchdogFired = false,
                    failure = "plugin worker census did not settle after engine teardown",
                )
                return
            }
            mainHandler.postDelayed(::finishGreenWhenWorkerCensusSettles, 10L)
        }

        private fun newSqlCipherEngine(): FlutterEngine {
            val engine = FlutterEngine(applicationContext, null, false)
            engine.plugins.add(SqfliteSqlCipherPlugin())
            liveEngineCount += 1
            peakLiveEngineCount = maxOf(peakLiveEngineCount, liveEngineCount)
            observePluginCensus()
            return engine
        }

        private fun executeQueueEntrypoint(engine: FlutterEngine, phase: String) {
            val loader = FlutterInjector.instance().flutterLoader()
            val entrypoint = DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                "androidCanonicalRuntimeH0ProbeMain",
            )
            engine.dartExecutor.executeDartEntrypoint(entrypoint, listOf(phase))
        }

        private fun failProtocol(failure: String) {
            finishTerminal(status = "FAIL", watchdogFired = false, failure = failure)
        }

        private fun payloadText(payload: Map<*, *>, name: String): String? =
            payload[name]?.toString()?.trim()?.takeIf(String::isNotEmpty)

        private fun sqlCipherRuntimeIdentityVerified(): Boolean {
            val writerCipher = writerCipherVersion
            val readerCipher = readerCipherVersion
            return !writerCipher.isNullOrEmpty() &&
                writerCipher == readerCipher &&
                writerJournalMode.equals("delete", ignoreCase = true)
        }

        private fun recordPhase(phase: String) {
            orderedPhases.put(phase)
            observePluginCensus()
        }

        private fun observePluginCensus() {
            val census = sqfliteDebugCensus() ?: return
            peakLivePluginWorkerCount = maxOf(
                peakLivePluginWorkerCount,
                (census["liveWorkers"] as? Number)?.toInt() ?: 0,
            )
            peakLivePluginHandleCount = maxOf(
                peakLivePluginHandleCount,
                (census["liveHandles"] as? Number)?.toInt() ?: 0,
            )
        }

        /** Lifecycle-only projection of [orderedPhases], preserving exact order. */
        private fun orderedLifecycleTransitions(): JSONArray = JSONArray().also { lifecycle ->
            for (index in 0 until orderedPhases.length()) {
                val phase = orderedPhases.optString(index)
                if (
                    phase.endsWith(".database_opened") ||
                    phase.endsWith(".closed") ||
                    phase.endsWith(".engine_destroyed")
                ) {
                    lifecycle.put(phase)
                }
            }
        }

        private fun hasRequiredCausalPrefix(): Boolean {
            val required = listOf(
                "writer.database_opened",
                "reader.database_opened",
                "writer.begin_exclusive",
                "reader.query_posted",
                "writer.resume_requested",
            )
            if (orderedPhases.length() < required.size) return false
            return required.indices.all { index ->
                orderedPhases.optString(index) == required[index]
            }
        }

        /**
         * The census exists only in the vendored fork. Reflection keeps the
         * disposable debug source set compilable during the hosted rollback
         * drill while queue evidence still fails closed when it is absent.
         */
        private fun sqfliteDebugCensus(): Map<String, Any?>? = runCatching {
            val method = SqfliteSqlCipherPlugin::class.java.getMethod("getDebugCensus")
            val raw = method.invoke(null) as? Map<*, *> ?: return@runCatching null
            raw.entries.associate { entry -> entry.key.toString() to entry.value }
        }.getOrNull()

        private fun finishTerminal(
            status: String,
            watchdogFired: Boolean,
            failure: String?,
        ) {
            if (completed) return
            completed = true
            observePluginCensus()
            val enginesDestroyed =
                writerEngineDestroyed && readerEngineDestroyed && sentinelEngineDestroyed
            val workerCensus = sqfliteDebugCensus()
            fun censusValue(name: String): Int =
                (workerCensus?.get(name) as? Number)?.toInt() ?: -1
            val workerCensusSettled =
                censusValue("liveInstances") == 0 &&
                    censusValue("liveWorkers") == 0 &&
                    censusValue("liveHandles") == 0 &&
                    censusValue("queuedTasks") == 0 &&
                    censusValue("runningTasks") == 0 &&
                    censusValue("terminatedInstances") >= 3
            val passed =
                status == "PASS" &&
                    writerCommit &&
                    readerQueryResult &&
                    sentinelVerified &&
                    enginesDestroyed &&
                    liveEngineCount == 0 &&
                    workerCensusSettled &&
                    sqlCipherRuntimeIdentityVerified()
            val expectedRedValid =
                status == "EXPECTED_RED" &&
                    hasRequiredCausalPrefix() &&
                    readerQueryPosted &&
                    writerResumeRequested &&
                    !writerCommit &&
                    !readerQueryResult &&
                    sqlCipherRuntimeIdentityVerified()
            val terminalStatus = when (status) {
                "PASS" -> if (passed) "PASS" else "FAIL"
                "EXPECTED_RED" -> if (expectedRedValid) "EXPECTED_RED" else "FAIL"
                else -> status
            }
            val terminalFailure = failure ?: if (terminalStatus != status) {
                "$status terminal invariants were not satisfied"
            } else {
                null
            }
            val artifact = JSONObject()
                .put("schema", "mknoon.android.sqlcipher-queue-inversion-h0.v1")
                .put("status", terminalStatus)
                .put("runNonce", runNonce)
                .put("pid", Process.myPid())
                .put("elapsedMs", (System.nanoTime() - startedAtNanos) / 1_000_000L)
                .put("sdkInt", Build.VERSION.SDK_INT)
                .put("device", "${Build.MANUFACTURER} ${Build.MODEL}".trim())
                .put("watchdogMs", QUEUE_INVERSION_WATCHDOG_MS)
                .put("watchdogFired", watchdogFired)
                .put("storageAggregateDeadlineMs", 8_000)
                .put("storagePhaseDeadlineMs", 2_000)
                .put("encryptedReadOnlyOpenDeadlineMs", 2_000)
                .put("encryptedReadOnlyBusyTimeoutMs", 1_000)
                .put("androidFlockAcquisitionMs", 1_000)
                .put("journalMaxCallerImpactMs", 200)
                .put("phases", orderedPhases)
                .put("orderedPhases", orderedPhases)
                .put("orderedLifecycleTransitions", orderedLifecycleTransitions())
                .put("causalPrefixVerified", hasRequiredCausalPrefix())
                .put("writerCipherVersion", writerCipherVersion ?: JSONObject.NULL)
                .put("readerCipherVersion", readerCipherVersion ?: JSONObject.NULL)
                .put("writerJournalMode", writerJournalMode ?: JSONObject.NULL)
                .put("sqlCipherRuntimeIdentityVerified", sqlCipherRuntimeIdentityVerified())
                .put("writerDatabaseOpened", writerDatabaseOpened)
                .put("readerDatabaseOpened", readerDatabaseOpened)
                .put("writerBeginExclusive", writerBeginExclusive)
                .put("readerQueryPosted", readerQueryPosted)
                .put("writerResumeRequested", writerResumeRequested)
                .put("writerCommit", writerCommit)
                .put("readerQueryResult", readerQueryResult)
                .put("writerClosed", writerClosed)
                .put("readerClosed", readerClosed)
                .put("sentinelOpened", sentinelOpened)
                .put("sentinelVerified", sentinelVerified)
                .put("sentinelClosed", sentinelClosed)
                .put("writerEngineDestroyed", writerEngineDestroyed)
                .put("readerEngineDestroyed", readerEngineDestroyed)
                .put("sentinelEngineDestroyed", sentinelEngineDestroyed)
                .put("enginesDestroyed", enginesDestroyed)
                .put("liveEngineCount", liveEngineCount)
                .put("peakLiveEngineCount", peakLiveEngineCount)
                .put("pluginWorkerCountAvailable", workerCensus != null)
                .put("livePluginWorkerCount", censusValue("liveWorkers"))
                .put("peakLivePluginWorkerCount", peakLivePluginWorkerCount)
                .put("peakLivePluginHandleCount", peakLivePluginHandleCount)
                .put("pluginWorkerCensusSettled", workerCensusSettled)
                .put("pluginWorkerCensus", JSONObject(workerCensus ?: emptyMap<String, Any?>()))
                .put("applicationRootConstructed", false)
                .put("applicationRootConstructionCount", 0)
                .put(
                    "applicationRootObservationBasis",
                    "direct_debug_entrypoint_plus_source_locked_no_runApp",
                )
                .put("failure", terminalFailure ?: JSONObject.NULL)
            finish(artifact, passed || expectedRedValid)
        }

        private fun jsonValue(value: Any?): Any? = when (value) {
            null -> JSONObject.NULL
            is Map<*, *> -> JSONObject().also { target ->
                value.forEach { (key, nested) ->
                    target.put(key.toString(), jsonValue(nested))
                }
            }
            is Iterable<*> -> JSONArray().also { target ->
                value.forEach { nested -> target.put(jsonValue(nested)) }
            }
            else -> value
        }
    }

    private class ProbeRunner(
        private val applicationContext: Context,
        private val mainHandler: Handler,
        private val phases: List<String>,
        private val finish: (JSONObject, Boolean) -> Unit,
    ) {
        private val phaseResults = JSONArray()
        private val contentionResults = JSONArray()
        private val observedWritableGenerations = mutableListOf<Long>()
        private var nextPhaseIndex = 0
        private var completed = false
        private var observedWritableDatabaseHandles = 0
        private var maximumObservedWritableDatabaseHandles = 0
        private var activeContentionPassed = false
        private var closeFailureRetentionPassed = false
        private var admittedGoJniWorkHeld = false
        private var admittedGoJniWorkSettled = false
        private var activeContentionStarted = false
        private var closeFailureContentionStarted = false
        private var readOnlyPeerPassed = false
        private var readOnlyDatabaseHandles = 0
        private var maximumObservedReadOnlyDatabaseHandles = 0
        private var threeEngineConcurrencyObserved = false
        private var readOnlyPeerResult: JSONObject? = null

        fun start() {
            check(Looper.myLooper() == Looper.getMainLooper())
            runNextPhase()
        }

        private fun runNextPhase() {
            if (nextPhaseIndex >= phases.size) {
                finishRun()
                return
            }
            val phase = phases[nextPhaseIndex++]
            executePhase(phase)
        }

        private fun executePhase(phase: String) {
            check(Looper.myLooper() == Looper.getMainLooper())
            var goBridge: GoBridge? = null
            val engine = FlutterEngine(applicationContext, null, false)
            registerAllowlistedPlugins(engine)
            val leaseBridge = CanonicalRuntimeLeaseBridge(
                messenger = engine.dartExecutor.binaryMessenger,
                ownerId = "$phase-${System.identityHashCode(engine)}",
                role = if (phase.startsWith("recovery")) {
                    CanonicalRuntimeLeaseBroker.Role.RECOVERY
                } else {
                    CanonicalRuntimeLeaseBroker.Role.FOREGROUND
                },
                attachRuntimeOwner = {
                    if (goBridge == null) {
                        goBridge = runCatching {
                            GoBridge(engine, applicationContext)
                        }.getOrNull()
                    }
                    goBridge != null
                },
                beginRuntimeDrain = {
                    goBridge?.requestRuntimeDrain() ?: true
                },
                isRuntimeReleased = {
                    goBridge?.isRuntimeReleased() ?: true
                },
            )
            val droppedPushBridge = DroppedPushRecoveryBridge(
                applicationContext,
                engine.dartExecutor.binaryMessenger,
            )
            val resultChannel = MethodChannel(
                engine.dartExecutor.binaryMessenger,
                RESULT_CHANNEL,
            )
            var phaseCompleted = false
            var databaseOpen = false

            fun destroyEngine() {
                check(Looper.myLooper() == Looper.getMainLooper())
                resultChannel.setMethodCallHandler(null)
                droppedPushBridge.dispose()
                leaseBridge.dispose()
                goBridge?.dispose()
                engine.destroy()
            }

            fun finishPhase(payload: Map<*, *>, succeeded: Boolean) {
                if (phaseCompleted || completed) return
                phaseCompleted = true
                mainHandler.post {
                    val go = ProcessGoRuntimeHost.instance.snapshot()
                    val lease = ProcessCanonicalRuntimeLease.broker.snapshot()
                    val result = JSONObject()
                        .put("phase", phase)
                        .put("dartSucceeded", succeeded)
                        .put("dart", jsonValue(payload))
                        .put("goStateBeforeDestroy", go.state.name)
                        .put("leaseStateBeforeDestroy", lease.state.name)
                        .put("databaseOpenBeforeDestroy", databaseOpen)
                        .put("engineDestroyedOnMainLooper", true)
                    destroyEngine()
                    result.put("engineDestroyed", true)
                    phaseResults.put(result)
                    if (!succeeded || databaseOpen) {
                        finishRun()
                    } else {
                        runNextPhase()
                    }
                }
            }

            resultChannel.setMethodCallHandler { call, result ->
                val payload = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
                when (call.method) {
                    "databaseOpened" -> {
                        if (databaseOpen) {
                            result.error(
                                "duplicate_database_open",
                                "engine already reported an open writable database",
                                null,
                            )
                        } else {
                            databaseOpen = true
                            observedWritableDatabaseHandles += 1
                            maximumObservedWritableDatabaseHandles = maxOf(
                                maximumObservedWritableDatabaseHandles,
                                observedWritableDatabaseHandles,
                            )
                            ProcessCanonicalRuntimeLease.broker.snapshot().generation?.let {
                                observedWritableGenerations += it
                            }
                            result.success(null)
                        }
                    }
                    "databaseClosed" -> {
                        if (!databaseOpen) {
                            result.error(
                                "database_not_open",
                                "engine reported a close without an observed open",
                                null,
                            )
                        } else {
                            databaseOpen = false
                            observedWritableDatabaseHandles -= 1
                            result.success(null)
                        }
                    }
                    "readyForActiveContention" -> {
                        val bridge = goBridge
                        if (phase != "recovery-handoff" || bridge == null) {
                            result.error(
                                "invalid_active_contention",
                                "recovery Go owner is not attached",
                                null,
                            )
                        } else {
                            startActiveContention(bridge, result)
                        }
                    }
                    "readyForCloseFailureContention" -> {
                        if (phase != "recovery-handoff") {
                            result.error(
                                "invalid_close_failure_contention",
                                "close-failure contention is recovery-only",
                                null,
                            )
                        } else {
                            startCloseFailureContention(result)
                        }
                    }
                    "complete" -> {
                        result.success(null)
                        finishPhase(payload, succeeded = true)
                    }
                    "failed" -> {
                        result.success(null)
                        finishPhase(payload, succeeded = false)
                    }
                    else -> result.notImplemented()
                }
            }

            mainHandler.postDelayed({
                if (!phaseCompleted && !completed) {
                    finishPhase(
                        mapOf(
                            "phase" to phase,
                            "errorType" to "ProbeTimeout",
                            "error" to "Dart phase exceeded $PHASE_TIMEOUT_MS ms",
                        ),
                        succeeded = false,
                    )
                }
            }, PHASE_TIMEOUT_MS)

            val loader = FlutterInjector.instance().flutterLoader()
            val entrypoint = DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                "androidCanonicalRuntimeH0ProbeMain",
            )
            engine.dartExecutor.executeDartEntrypoint(entrypoint, listOf(phase))
        }

        private fun startActiveContention(
            goBridge: GoBridge,
            channelResult: MethodChannel.Result,
        ) {
            if (activeContentionStarted) {
                channelResult.error(
                    "active_contention_already_started",
                    "active contention may run only once",
                    null,
                )
                return
            }
            activeContentionStarted = true
            val initialLease = ProcessCanonicalRuntimeLease.broker.snapshot()
            if (
                initialLease.state != CanonicalRuntimeLeaseBroker.State.ACTIVE ||
                observedWritableDatabaseHandles != 1
            ) {
                channelResult.error(
                    "active_owner_not_observed",
                    "recovery must own one open database before contention",
                    null,
                )
                return
            }

            val releaseHold = CountDownLatch(1)
            var holdSettled = false
            var holdSucceeded = false
            var contenderSettled = false
            var contenderSucceeded = false
            var readOnlySettled = false
            var readOnlySucceeded = false
            var closeReadOnly: (() -> Unit)? = null
            var readOnlyCloseRequested = false
            var replied = false

            fun maybeCloseReadOnly() {
                if (
                    !readOnlyCloseRequested &&
                    holdSettled &&
                    contenderSettled
                ) {
                    readOnlyCloseRequested = true
                    closeReadOnly?.invoke()
                }
            }

            fun maybeReply() {
                check(Looper.myLooper() == Looper.getMainLooper())
                if (
                    replied ||
                    !holdSettled ||
                    !contenderSettled ||
                    !readOnlySettled
                ) {
                    return
                }
                replied = true
                val finalLease = ProcessCanonicalRuntimeLease.broker.snapshot()
                activeContentionPassed = holdSucceeded &&
                    contenderSucceeded &&
                    readOnlySucceeded &&
                    readOnlyPeerPassed &&
                    threeEngineConcurrencyObserved &&
                    admittedGoJniWorkHeld &&
                    admittedGoJniWorkSettled &&
                    finalLease.state == CanonicalRuntimeLeaseBroker.State.ACTIVE &&
                    observedWritableDatabaseHandles == 1 &&
                    readOnlyDatabaseHandles == 0
                channelResult.success(
                    mapOf(
                        "passed" to activeContentionPassed,
                        "heldAdmittedGoJniWork" to admittedGoJniWorkHeld,
                        "settledAdmittedGoJniWork" to admittedGoJniWorkSettled,
                        "leaseState" to finalLease.state.name,
                        "observedWritableDatabaseHandles" to
                            observedWritableDatabaseHandles,
                        "flutterFireReadOnlyPeerPassed" to readOnlyPeerPassed,
                        "threeEngineConcurrencyObserved" to
                            threeEngineConcurrencyObserved,
                    ),
                )
            }

            runFlutterFireReadOnlyPeer(
                onOpened = { close ->
                    closeReadOnly = close
                    threeEngineConcurrencyObserved =
                        readOnlyDatabaseHandles == 1 &&
                            observedWritableDatabaseHandles == 1 &&
                            ProcessCanonicalRuntimeLease.broker.snapshot().state ==
                            CanonicalRuntimeLeaseBroker.State.ACTIVE
                    val admitted = goBridge.admitH0ProbeJniHold(
                        release = releaseHold,
                        onHeld = {
                            mainHandler.post {
                                if (completed || replied) {
                                    releaseHold.countDown()
                                    return@post
                                }
                                admittedGoJniWorkHeld = true
                                runContender(
                                    kind = "active",
                                    expectedLeaseState =
                                        CanonicalRuntimeLeaseBroker.State.ACTIVE,
                                    requireReadOnlyPeer = true,
                                ) { succeeded ->
                                    contenderSucceeded = succeeded
                                    contenderSettled = true
                                    releaseHold.countDown()
                                    maybeCloseReadOnly()
                                    maybeReply()
                                }
                            }
                        },
                        onSettled = { succeeded ->
                            mainHandler.post {
                                admittedGoJniWorkSettled = succeeded
                                holdSucceeded = succeeded
                                holdSettled = true
                                if (!admittedGoJniWorkHeld) {
                                    contenderSettled = true
                                    contenderSucceeded = false
                                }
                                maybeCloseReadOnly()
                                maybeReply()
                            }
                        },
                    )
                    if (!admitted) {
                        holdSettled = true
                        contenderSettled = true
                        maybeCloseReadOnly()
                    }
                },
                onFinished = { succeeded ->
                    readOnlySucceeded = succeeded
                    readOnlySettled = true
                    if (!threeEngineConcurrencyObserved) {
                        holdSettled = true
                        contenderSettled = true
                    }
                    maybeReply()
                },
            )
            mainHandler.postDelayed({
                if (!replied && !completed) {
                    releaseHold.countDown()
                    closeReadOnly?.invoke()
                    replied = true
                    channelResult.error(
                        "active_contention_timeout",
                        "active three-engine contention did not settle",
                        null,
                    )
                }
            }, 12_000L)
        }

        private fun startCloseFailureContention(
            channelResult: MethodChannel.Result,
        ) {
            if (closeFailureContentionStarted) {
                channelResult.error(
                    "close_failure_contention_already_started",
                    "close-failure contention may run only once",
                    null,
                )
                return
            }
            closeFailureContentionStarted = true
            val retainedLease = ProcessCanonicalRuntimeLease.broker.snapshot()
            if (
                retainedLease.state != CanonicalRuntimeLeaseBroker.State.DRAINING ||
                observedWritableDatabaseHandles != 1
            ) {
                channelResult.error(
                    "close_failure_not_retained",
                    "close failure must retain one DRAINING database owner",
                    null,
                )
                return
            }
            runContender(
                kind = "close-failure",
                expectedLeaseState = CanonicalRuntimeLeaseBroker.State.DRAINING,
            ) { succeeded ->
                val after = ProcessCanonicalRuntimeLease.broker.snapshot()
                closeFailureRetentionPassed = succeeded &&
                    after.state == CanonicalRuntimeLeaseBroker.State.DRAINING &&
                    observedWritableDatabaseHandles == 1
                channelResult.success(
                    mapOf(
                        "passed" to closeFailureRetentionPassed,
                        "leaseState" to after.state.name,
                        "observedWritableDatabaseHandles" to
                            observedWritableDatabaseHandles,
                    ),
                )
            }
        }

        private fun runContender(
            kind: String,
            expectedLeaseState: CanonicalRuntimeLeaseBroker.State,
            requireReadOnlyPeer: Boolean = false,
            onFinished: (Boolean) -> Unit,
        ) {
            check(Looper.myLooper() == Looper.getMainLooper())
            val phase = "contender-$kind"
            val engine = FlutterEngine(applicationContext, null, false)
            registerAllowlistedPlugins(engine)
            var databaseOpen = false
            val leaseBridge = CanonicalRuntimeLeaseBridge(
                messenger = engine.dartExecutor.binaryMessenger,
                ownerId = "$phase-${System.identityHashCode(engine)}",
                role = CanonicalRuntimeLeaseBroker.Role.FOREGROUND,
                attachRuntimeOwner = { false },
            )
            val droppedPushBridge = DroppedPushRecoveryBridge(
                applicationContext,
                engine.dartExecutor.binaryMessenger,
            )
            val resultChannel = MethodChannel(
                engine.dartExecutor.binaryMessenger,
                RESULT_CHANNEL,
            )
            var settled = false

            fun finishContender(payload: Map<*, *>, dartSucceeded: Boolean) {
                if (settled || completed) return
                settled = true
                mainHandler.post {
                    val nativeLease = ProcessCanonicalRuntimeLease.broker.snapshot()
                    val verified = dartSucceeded &&
                        payload["leaseRejected"] == true &&
                        payload["databaseOpened"] == false &&
                        !databaseOpen &&
                        nativeLease.state == expectedLeaseState &&
                        observedWritableDatabaseHandles == 1 &&
                        (!requireReadOnlyPeer || readOnlyDatabaseHandles == 1)
                    val record = JSONObject()
                        .put("kind", kind)
                        .put("dartSucceeded", dartSucceeded)
                        .put("verified", verified)
                        .put("dart", jsonValue(payload))
                        .put("nativeLeaseState", nativeLease.state.name)
                        .put("databaseOpenBeforeDestroy", databaseOpen)
                        .put("engineDestroyedOnMainLooper", true)
                    resultChannel.setMethodCallHandler(null)
                    droppedPushBridge.dispose()
                    leaseBridge.dispose()
                    engine.destroy()
                    record.put("engineDestroyed", true)
                    contentionResults.put(record)
                    onFinished(verified)
                }
            }

            resultChannel.setMethodCallHandler { call, result ->
                val payload = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
                when (call.method) {
                    "databaseOpened" -> {
                        databaseOpen = true
                        observedWritableDatabaseHandles += 1
                        maximumObservedWritableDatabaseHandles = maxOf(
                            maximumObservedWritableDatabaseHandles,
                            observedWritableDatabaseHandles,
                        )
                        result.success(null)
                    }
                    "databaseClosed" -> {
                        if (databaseOpen) {
                            databaseOpen = false
                            observedWritableDatabaseHandles -= 1
                        }
                        result.success(null)
                    }
                    "complete" -> {
                        result.success(null)
                        finishContender(payload, dartSucceeded = true)
                    }
                    "failed" -> {
                        result.success(null)
                        finishContender(payload, dartSucceeded = false)
                    }
                    else -> result.notImplemented()
                }
            }
            mainHandler.postDelayed({
                if (!settled && !completed) {
                    finishContender(
                        mapOf(
                            "phase" to phase,
                            "errorType" to "ContenderTimeout",
                        ),
                        dartSucceeded = false,
                    )
                }
            }, 8_000L)
            val loader = FlutterInjector.instance().flutterLoader()
            val entrypoint = DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                "androidCanonicalRuntimeH0ProbeMain",
            )
            engine.dartExecutor.executeDartEntrypoint(entrypoint, listOf(phase))
        }

        private fun runFlutterFireReadOnlyPeer(
            onOpened: (() -> Unit) -> Unit,
            onFinished: (Boolean) -> Unit,
        ) {
            check(Looper.myLooper() == Looper.getMainLooper())
            val phase = "firebase-read-only"
            val engine = FlutterEngine(applicationContext, null, false)
            registerAllowlistedPlugins(engine)
            val resultChannel = MethodChannel(
                engine.dartExecutor.binaryMessenger,
                RESULT_CHANNEL,
            )
            var databaseOpen = false
            var settled = false
            var closeReply: MethodChannel.Result? = null

            fun finishReadOnly(payload: Map<*, *>, dartSucceeded: Boolean) {
                if (settled || completed) return
                settled = true
                mainHandler.post {
                    val nativeLease = ProcessCanonicalRuntimeLease.broker.snapshot()
                    val verified = dartSucceeded &&
                        payload["entrypoint"] ==
                        "androidCanonicalRuntimeH0ProbeMain" &&
                        payload["readOnlyDatabaseOpened"] == true &&
                        payload["databaseClosedBeforeCompletion"] == true &&
                        payload["writableLeaseAcquired"] == false &&
                        payload["goBridgeAttached"] == false &&
                        !databaseOpen &&
                        readOnlyDatabaseHandles == 0 &&
                        observedWritableDatabaseHandles == 1 &&
                        nativeLease.state == CanonicalRuntimeLeaseBroker.State.ACTIVE
                    readOnlyPeerPassed = verified
                    val record = JSONObject()
                        .put("phase", phase)
                        .put("dartSucceeded", dartSucceeded)
                        .put("verified", verified)
                        .put("dart", jsonValue(payload))
                        .put("nativeLeaseState", nativeLease.state.name)
                        .put("databaseOpenBeforeDestroy", databaseOpen)
                        .put("registeredWritableLeaseBridge", false)
                        .put("registeredGoBridge", false)
                        .put("engineDestroyedOnMainLooper", true)
                    resultChannel.setMethodCallHandler(null)
                    engine.destroy()
                    record.put("engineDestroyed", true)
                    readOnlyPeerResult = record
                    onFinished(verified)
                }
            }

            resultChannel.setMethodCallHandler { call, result ->
                val payload = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
                when (call.method) {
                    "readOnlyDatabaseOpened" -> {
                        if (databaseOpen || closeReply != null) {
                            result.error(
                                "duplicate_read_only_open",
                                "read-only peer already reported an open handle",
                                null,
                            )
                        } else {
                            databaseOpen = true
                            readOnlyDatabaseHandles += 1
                            maximumObservedReadOnlyDatabaseHandles = maxOf(
                                maximumObservedReadOnlyDatabaseHandles,
                                readOnlyDatabaseHandles,
                            )
                            closeReply = result
                            onOpened {
                                val pending = closeReply
                                closeReply = null
                                pending?.success(null)
                            }
                        }
                    }
                    "readOnlyDatabaseClosed" -> {
                        if (!databaseOpen) {
                            result.error(
                                "read_only_database_not_open",
                                "read-only peer reported close without open",
                                null,
                            )
                        } else {
                            databaseOpen = false
                            readOnlyDatabaseHandles -= 1
                            result.success(null)
                        }
                    }
                    "complete" -> {
                        result.success(null)
                        finishReadOnly(payload, dartSucceeded = true)
                    }
                    "failed" -> {
                        result.success(null)
                        finishReadOnly(payload, dartSucceeded = false)
                    }
                    else -> result.notImplemented()
                }
            }
            mainHandler.postDelayed({
                if (!settled && !completed) {
                    closeReply?.success(null)
                    closeReply = null
                }
            }, 8_000L)
            mainHandler.postDelayed({
                if (!settled && !completed) {
                    finishReadOnly(
                        mapOf(
                            "phase" to phase,
                            "errorType" to "ReadOnlyPeerTimeout",
                            "databaseClosedBeforeCompletion" to !databaseOpen,
                        ),
                        dartSucceeded = false,
                    )
                }
            }, 10_000L)
            val loader = FlutterInjector.instance().flutterLoader()
            val entrypoint = DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                "androidCanonicalRuntimeH0ProbeMain",
            )
            engine.dartExecutor.executeDartEntrypoint(entrypoint, listOf(phase))
        }

        private fun registerAllowlistedPlugins(engine: FlutterEngine) {
            // Deliberately explicit: automatic broad registration stays disabled.
            engine.plugins.add(FlutterSecureStoragePlugin())
            engine.plugins.add(SqfliteSqlCipherPlugin())
            engine.plugins.add(FlutterLocalNotificationsPlugin())
            engine.plugins.add(FlutterFirebaseCorePlugin())
            engine.plugins.add(FlutterFirebaseMessagingPlugin())
        }

        private fun finishRun() {
            if (completed) return
            completed = true
            val go = ProcessGoRuntimeHost.instance.snapshot()
            val lease = ProcessCanonicalRuntimeLease.broker.snapshot()
            val allDartSucceeded = (0 until phaseResults.length()).all { index ->
                val phase = phaseResults.getJSONObject(index)
                phase.optBoolean("dartSucceeded", false) &&
                    !phase.optBoolean("databaseOpenBeforeDestroy", true) &&
                    phase.optJSONObject("dart")
                        ?.optBoolean("databaseClosedBeforeCompletion", false) == true
            }
            val handoff = phases.contains("recovery-handoff")
            val directProbeEntrypointObserved =
                phaseResults.length() == phases.size &&
                    (0 until phaseResults.length()).all { index ->
                        phaseResults.getJSONObject(index)
                            .optJSONObject("dart")
                            ?.optString("entrypoint") ==
                            "androidCanonicalRuntimeH0ProbeMain"
                    }
            val generationsStrictlyIncrease =
                observedWritableGenerations.size == phases.size &&
                    observedWritableGenerations.zipWithNext().all { (before, after) ->
                        after > before
                    }
            val contentionsPassed = if (handoff) {
                contentionResults.length() == 2 &&
                    (0 until contentionResults.length()).all { index ->
                        contentionResults.getJSONObject(index)
                            .optBoolean("verified", false)
                    } &&
                    activeContentionPassed &&
                    closeFailureRetentionPassed &&
                    readOnlyPeerPassed &&
                    readOnlyPeerResult != null &&
                    threeEngineConcurrencyObserved &&
                    readOnlyDatabaseHandles == 0 &&
                    maximumObservedReadOnlyDatabaseHandles == 1 &&
                    admittedGoJniWorkHeld &&
                    admittedGoJniWorkSettled
            } else {
                contentionResults.length() == 0
            }
            val passed = allDartSucceeded &&
                phaseResults.length() == phases.size &&
                directProbeEntrypointObserved &&
                contentionsPassed &&
                generationsStrictlyIncrease &&
                observedWritableDatabaseHandles == 0 &&
                maximumObservedWritableDatabaseHandles == 1 &&
                CanonicalRuntimeProbeDiagnostics.mainActivityLaunchCount() == 0 &&
                go.initializeCount == 1 &&
                go.state == GoRuntimeHost.State.RELEASED &&
                go.outstandingDeliveries == 0 &&
                go.staleCallbackDeliveries == 0 &&
                go.staleResultDeliveries == 0 &&
                lease.state == CanonicalRuntimeLeaseBroker.State.RELEASED &&
                lease.maximumConcurrentWritableOwners == 1 &&
                !DroppedPushRecoveryStore(applicationContext).recoveryWorkEnabled()
            val artifact = JSONObject()
                .put("schema", "mknoon.android.canonical-runtime-h0.v1")
                .put("status", if (passed) "PASS" else "FAIL")
                .put("pid", Process.myPid())
                .put("sdkInt", Build.VERSION.SDK_INT)
                .put("device", "${Build.MANUFACTURER} ${Build.MODEL}".trim())
                .put(
                    "mainActivityLaunchCount",
                    CanonicalRuntimeProbeDiagnostics.mainActivityLaunchCount(),
                )
                .put(
                    "applicationRootConstructed",
                    !directProbeEntrypointObserved,
                )
                .put(
                    "applicationRootObservationBasis",
                    "observed_debug_entrypoint_plus_source_locked_no_runApp",
                )
                .put("goInitializeCount", go.initializeCount)
                .put("goFinalState", go.state.name)
                .put("goOutstandingDeliveries", go.outstandingDeliveries)
                .put("staleCallbackDeliveries", go.staleCallbackDeliveries)
                .put("staleResultDeliveries", go.staleResultDeliveries)
                .put(
                    "maxWritableDatabaseOwners",
                    lease.maximumConcurrentWritableOwners,
                )
                .put(
                    "maxObservedWritableDatabaseHandles",
                    maximumObservedWritableDatabaseHandles,
                )
                .put(
                    "finalObservedWritableDatabaseHandles",
                    observedWritableDatabaseHandles,
                )
                .put(
                    "observedWritableGenerations",
                    JSONArray(observedWritableGenerations),
                )
                .put("activeContentionPassed", activeContentionPassed)
                .put(
                    "closeFailureRetentionPassed",
                    closeFailureRetentionPassed,
                )
                .put("admittedGoJniWorkHeld", admittedGoJniWorkHeld)
                .put("admittedGoJniWorkSettled", admittedGoJniWorkSettled)
                .put("flutterFireReadOnlyPeerPassed", readOnlyPeerPassed)
                .put(
                    "threeEngineConcurrencyObserved",
                    threeEngineConcurrencyObserved,
                )
                .put(
                    "maxObservedReadOnlyDatabaseHandles",
                    maximumObservedReadOnlyDatabaseHandles,
                )
                .put("finalReadOnlyDatabaseHandles", readOnlyDatabaseHandles)
                .put(
                    "flutterFireReadOnlyPeer",
                    readOnlyPeerResult ?: JSONObject.NULL,
                )
                .put("finalLeaseState", lease.state.name)
                .put("recoveryWorkActivated", false)
                .put("engineLifecycleMainLooper", true)
                .put("pluginAllowlist", JSONArray(pluginAllowlist))
                .put("contentions", contentionResults)
                .put("phases", phaseResults)
            finish(artifact, passed)
        }

        private fun jsonValue(value: Any?): Any? = when (value) {
            null -> JSONObject.NULL
            is Map<*, *> -> JSONObject().also { target ->
                value.forEach { (key, nested) ->
                    target.put(key.toString(), jsonValue(nested))
                }
            }
            is Iterable<*> -> JSONArray().also { target ->
                value.forEach { nested -> target.put(jsonValue(nested)) }
            }
            else -> value
        }
    }
}

/**
 * Debug-proof host for the real production service ingress. The base context
 * is attached manually because the proof runs inside a broadcast, but every
 * classifier/seam/card/scheduler call is the production implementation; only
 * FlutterFire delegation is recorded so a rich canary cannot start incumbent
 * background staging mid-proof.
 */
private class DebugFixedWakeIngressService(
    base: android.content.Context,
) : MknoonFirebaseMessagingService() {
    var delegatedCount = 0
        private set

    init {
        attachBaseContext(base)
    }

    override fun delegateRichMessageToFlutterFire(
        message: com.google.firebase.messaging.RemoteMessage,
    ) {
        delegatedCount += 1
    }
}
