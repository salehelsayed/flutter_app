import 'dart:convert';
import 'dart:math';

import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger_store.dart';

/// Final canonical disposition read only after the ledger has durably entered
/// `PUBLISHING`. Unknown facts never authorize suppression or a native effect.
enum DurableLocalNotificationCanonicalDisposition {
  eligible,
  read,
  suppressedPolicy,
  cancelled,
  retryableUnknown,
}

typedef ReadDurableLocalNotificationCanonicalDisposition =
    Future<DurableLocalNotificationCanonicalDisposition> Function();

typedef ResolveDurableLocalNotificationActiveIds =
    Future<Iterable<Object?>> Function();

typedef AuthorizeDurableLocalNotificationNativeEntry = Future<bool> Function();
typedef PublishDurableLocalNotificationAtFinalBarrier =
    Future<bool> Function(
      AuthorizeDurableLocalNotificationNativeEntry authorize,
    );

/// Cross-lane result of the exact SQL custody handoff that runs after an
/// effect-terminal receipt and before ledger settlement.
enum DurableLocalNotificationSqlHandoffResult {
  committed,
  alreadyCommitted,
  retryableMismatch,
}

/// Stable privacy-safe generation for one exact ledger event. Retrying a
/// retained SQL row must reuse the marker/payload generation rather than mint
/// a fresh value that can never match its READY record.
String? durableLocalNotificationContentGeneration(String eventCorrelation) =>
    _lowercaseDigest.hasMatch(eventCorrelation)
    ? 'ledger:$eventCorrelation'
    : null;

/// Immutable authority supplied by an authenticated message/reaction owner.
///
/// This type contains only opaque identifiers. Display copy, raw peer/group
/// identifiers, routes and provider payloads must not enter the durable ledger.
final class DurableLocalNotificationEffectContext {
  const DurableLocalNotificationEffectContext({
    required this.currentOpaqueBinding,
    required this.eventCorrelation,
    required this.conversationDigest,
    required this.producerKind,
    required this.sourceCustody,
    required this.presentationOwner,
    required this.readFinalCanonicalDisposition,
    this.expectedRecordRevision,
    this.onEffectTerminal,
    this.terminalObserverCompletesSqlHandoff = false,
  });

  final String currentOpaqueBinding;
  final String eventCorrelation;
  final String conversationDigest;
  final LocalNotificationProducerKind producerKind;
  final LocalNotificationSourceCustody sourceCustody;
  final LocalNotificationPresentationOwner presentationOwner;
  final ReadDurableLocalNotificationCanonicalDisposition
  readFinalCanonicalDisposition;
  final int? expectedRecordRevision;

  /// Runs after the registry lock is released. It may complete exact SQL/v116
  /// handoff and then call [settleSqlReadyEffect]; it is never proof by itself
  /// that source custody has been deleted or settled.
  final Future<void> Function(DurableLocalNotificationEffectReceipt receipt)?
  onEffectTerminal;

  /// True only when [onEffectTerminal] commits/verifies SQL custody and
  /// settles this exact ledger receipt before returning. Capture-only
  /// observers must leave this false so reconciliation cannot run between the
  /// file terminal and its SQL handoff.
  final bool terminalObserverCompletesSqlHandoff;

  bool get isValid =>
      isCanonicalRuntimeOpaqueBinding(currentOpaqueBinding) &&
      _lowercaseDigest.hasMatch(eventCorrelation) &&
      _lowercaseDigest.hasMatch(conversationDigest) &&
      (expectedRecordRevision == null ||
          _isPositiveLedgerInt64(expectedRecordRevision));
}

enum DurableLocalNotificationEffectDisposition {
  osPosted,
  inChat,
  suppressedPolicy,
  cancelled,
  retryable,
  ambiguous,
}

/// Exact durable terminal returned to the SQL custody owner.
final class DurableLocalNotificationEffectReceipt {
  const DurableLocalNotificationEffectReceipt({
    required this.eventCorrelation,
    required this.recordRevision,
    required this.presentationState,
  });

  final String eventCorrelation;
  final int recordRevision;
  final LocalNotificationPresentationState presentationState;
}

final class DurableLocalNotificationEffectResult {
  const DurableLocalNotificationEffectResult({
    required this.disposition,
    this.receipt,
    this.currentNativeEntryAttempted = false,
    this.currentNativeEntryWasSilentRepair = false,
  });

  const DurableLocalNotificationEffectResult.retryable()
    : disposition = DurableLocalNotificationEffectDisposition.retryable,
      receipt = null,
      currentNativeEntryAttempted = false,
      currentNativeEntryWasSilentRepair = false;

  const DurableLocalNotificationEffectResult.ambiguous({
    this.currentNativeEntryAttempted = false,
    this.currentNativeEntryWasSilentRepair = false,
  }) : disposition = DurableLocalNotificationEffectDisposition.ambiguous,
       receipt = null;

  final DurableLocalNotificationEffectDisposition disposition;
  final DurableLocalNotificationEffectReceipt? receipt;
  final bool currentNativeEntryAttempted;
  final bool currentNativeEntryWasSilentRepair;
}

/// Optional capability implemented by the incumbent stable-id/content owner.
/// Its public methods acquire the registry coordination lock exactly once.
abstract interface class DurableLocalNotificationEffectRegistry {
  Future<DurableLocalNotificationEffectResult> runFinalEffect({
    required DurableLocalNotificationEffectContext context,
    required AppVisibilitySuppressionReader appVisibility,
    required AppVisibilityConversationIdentity conversationIdentity,
    required String conversationKey,
    required int notificationId,
    required ConversationNotificationContentMetadata metadata,
    required Future<void> Function() retireCurrent,
    required Future<void> Function() publishNative,
    Future<void> Function()? publishNativeSilently,
    PublishDurableLocalNotificationAtFinalBarrier? publishNativeAtFinalBarrier,
    ResolveDurableLocalNotificationActiveIds? activeNotificationIds,
  });

  Future<LocalNotificationRecordV1?> settleSqlReadyEffect({
    required String currentOpaqueBinding,
    required String eventCorrelation,
    required int expectedRevision,
  });

  Future<LocalNotificationRecordV1?> lookupExactEffect({
    required String currentOpaqueBinding,
    required String eventCorrelation,
    required String conversationDigest,
    required int notificationId,
    required String contentGeneration,
  });

  /// Lists SQL-custody records whose native effect is immutable, including
  /// SETTLED records that can still have an exact SQL transaction-B READY row
  /// after a process cut.
  Future<List<LocalNotificationRecordV1>> listSqlReadyEffectTerminals({
    required String currentOpaqueBinding,
  });

  Future<LocalNotificationRecordV1?> upgradeRelayCustodyToSqlReady({
    required String currentOpaqueBinding,
    required String eventCorrelation,
    required int expectedRevision,
  });
}

/// Lock-held state machine used only by
/// [DurableLocalNotificationEffectRegistry]. The caller owns the incumbent
/// `.coordination.lock`; every ledger operation here is deliberately lock-held
/// so this class cannot recursively acquire that file.
final class DurableLocalNotificationEffectCoordinator {
  DurableLocalNotificationEffectCoordinator({
    required LocalNotificationLedgerStore ledgerStore,
    DateTime Function()? nowUtc,
    String Function()? effectTokenFactory,
  }) : _ledgerStore = ledgerStore,
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
       _effectTokenFactory = effectTokenFactory ?? _newEffectToken;

  final LocalNotificationLedgerStore _ledgerStore;
  final DateTime Function() _nowUtc;
  final String Function() _effectTokenFactory;

  Future<DurableLocalNotificationEffectResult> runLockHeld({
    required DurableLocalNotificationEffectContext context,
    required AppVisibilitySuppressionReader appVisibility,
    required AppVisibilityConversationIdentity conversationIdentity,
    required int notificationId,
    required ConversationNotificationContentMetadata metadata,
    required Future<void> Function() prepareContent,
    required Future<void> Function() retireCurrent,
    required Future<void> Function() retireAndActivateContent,
    required Future<bool> Function() ensureContentActivated,
    required Future<bool> Function() hasContentActivationIntent,
    required Future<void> Function() completeContentActivation,
    required Future<bool> Function() exactContentIsCurrent,
    required Future<void> Function() clearActivatedContent,
    required Future<void> Function() publishNative,
    Future<void> Function()? publishNativeSilently,
    PublishDurableLocalNotificationAtFinalBarrier? publishNativeAtFinalBarrier,
    ResolveDurableLocalNotificationActiveIds? activeNotificationIds,
  }) async {
    if (!context.isValid ||
        context.conversationDigest != conversationIdentity.digest ||
        metadata.generation == null ||
        metadata.generation!.trim().isEmpty ||
        metadata.eventIdentity?.trim() != context.eventCorrelation ||
        !_producerMatchesContentKind(context.producerKind, metadata.kind) ||
        notificationId < 0 ||
        notificationId > localNotificationLedgerMaxNotificationId) {
      return const DurableLocalNotificationEffectResult.retryable();
    }

    // Account/startup composition owns intentional initialization/rebinding.
    // An effect attempt may only read the current exact binding; treating a
    // mismatched context as a rebind would let stale work erase authority.
    final initialized = await _ledgerStore.readLockHeld(
      currentOpaqueBinding: context.currentOpaqueBinding,
    );
    if (initialized == null || initialized.claimsSuspended) {
      return const DurableLocalNotificationEffectResult.retryable();
    }

    var record = initialized.records[context.eventCorrelation];
    if (record == null) {
      record = await _seedReadyRecordLockHeld(
        context: context,
        notificationId: notificationId,
        contentGeneration: metadata.generation!,
      );
      if (record == null) {
        return const DurableLocalNotificationEffectResult.retryable();
      }
    }

    final expectedRevision = context.expectedRecordRevision;
    if (expectedRevision != null && record.revision != expectedRevision) {
      return const DurableLocalNotificationEffectResult.retryable();
    }

    final materializingRelay =
        context.sourceCustody == LocalNotificationSourceCustody.sqlReady &&
        record.sourceCustody ==
            LocalNotificationSourceCustody.relayVerifiedUnacked;
    if (materializingRelay) {
      if (!_recordMatchesBaseIdentity(record: record, context: context) ||
          !_recordMatchesContent(
            record: record,
            notificationId: notificationId,
            contentGeneration: metadata.generation!,
          )) {
        return const DurableLocalNotificationEffectResult.retryable();
      }
      final adopted = await _transitionLockHeld(
        currentOpaqueBinding: context.currentOpaqueBinding,
        current: record,
        next: record.copyWith(
          sourceCustody: LocalNotificationSourceCustody.sqlReady,
          revision: record.revision + 1,
          // Custody materialization must not restart CLAIMED/PUBLISHING
          // recovery horizons owned by the incumbent native adapter.
          updatedAtUtc: record.updatedAtUtc,
        ),
      );
      if (adopted == null) {
        return const DurableLocalNotificationEffectResult.retryable();
      }
      record = adopted;
      if (record.effectPhase == LocalNotificationEffectPhase.effectTerminal) {
        return _terminalResult(record);
      }
      if (record.effectPhase == LocalNotificationEffectPhase.publishing) {
        return _recoverPublishingLockHeld(
          context: context,
          record: record,
          notificationId: notificationId,
          appVisibility: appVisibility,
          conversationIdentity: conversationIdentity,
          retireCurrent: retireCurrent,
          ensureContentActivated: ensureContentActivated,
          hasContentActivationIntent: hasContentActivationIntent,
          completeContentActivation: completeContentActivation,
          exactContentIsCurrent: exactContentIsCurrent,
          clearActivatedContent: clearActivatedContent,
          publishNative: publishNative,
          publishNativeSilently: publishNativeSilently,
          activeNotificationIds: activeNotificationIds,
        );
      }
      // READY and an aged CLAIMED record continue through the ordinary state
      // machine below while retaining the incumbent native owner and token.
      // A fresh CLAIMED record still waits for its normal recovery horizon.
    }

    final materializedNativeOwner =
        context.sourceCustody == LocalNotificationSourceCustody.sqlReady &&
        record.sourceCustody == LocalNotificationSourceCustody.sqlReady &&
        record.presentationOwner != context.presentationOwner &&
        _isNativePresentationOwner(record.presentationOwner) &&
        _recordMatchesBaseIdentity(record: record, context: context) &&
        _recordMatchesContent(
          record: record,
          notificationId: notificationId,
          contentGeneration: metadata.generation!,
        );
    if (materializedNativeOwner) {
      if (record.effectPhase == LocalNotificationEffectPhase.effectTerminal ||
          record.effectPhase == LocalNotificationEffectPhase.settled) {
        return _terminalResult(record);
      }
      if (record.effectPhase == LocalNotificationEffectPhase.publishing) {
        return _recoverPublishingLockHeld(
          context: context,
          record: record,
          notificationId: notificationId,
          appVisibility: appVisibility,
          conversationIdentity: conversationIdentity,
          retireCurrent: retireCurrent,
          ensureContentActivated: ensureContentActivated,
          hasContentActivationIntent: hasContentActivationIntent,
          completeContentActivation: completeContentActivation,
          exactContentIsCurrent: exactContentIsCurrent,
          clearActivatedContent: clearActivatedContent,
          publishNative: publishNative,
          publishNativeSilently: publishNativeSilently,
          activeNotificationIds: activeNotificationIds,
        );
      }
      // READY and CLAIMED continue below under the incumbent native owner.
    }
    final preservesNativePresentationOwner =
        materializingRelay || materializedNativeOwner;
    if (!_recordMatchesBaseIdentity(record: record, context: context) ||
        record.sourceCustody != context.sourceCustody ||
        (!preservesNativePresentationOwner &&
            record.presentationOwner != context.presentationOwner)) {
      return const DurableLocalNotificationEffectResult.retryable();
    }
    if (!_recordMatchesContent(
      record: record,
      notificationId: notificationId,
      contentGeneration: metadata.generation!,
    )) {
      return const DurableLocalNotificationEffectResult.retryable();
    }
    if (record.effectPhase == LocalNotificationEffectPhase.effectTerminal ||
        record.effectPhase == LocalNotificationEffectPhase.settled) {
      return _terminalResult(record);
    }
    if (record.effectPhase == LocalNotificationEffectPhase.publishing) {
      if (!_recordMatchesContent(
        record: record,
        notificationId: notificationId,
        contentGeneration: metadata.generation!,
      )) {
        return const DurableLocalNotificationEffectResult.retryable();
      }
      return _recoverPublishingLockHeld(
        context: context,
        record: record,
        notificationId: notificationId,
        appVisibility: appVisibility,
        conversationIdentity: conversationIdentity,
        retireCurrent: retireCurrent,
        ensureContentActivated: ensureContentActivated,
        hasContentActivationIntent: hasContentActivationIntent,
        completeContentActivation: completeContentActivation,
        exactContentIsCurrent: exactContentIsCurrent,
        clearActivatedContent: clearActivatedContent,
        publishNative: publishNative,
        publishNativeSilently: publishNativeSilently,
        activeNotificationIds: activeNotificationIds,
      );
    }
    if (record.effectPhase == LocalNotificationEffectPhase.claimed) {
      if (!_claimedRecoveryHorizonReached(record)) {
        return const DurableLocalNotificationEffectResult.retryable();
      }
    } else if (record.effectPhase == LocalNotificationEffectPhase.ready) {
      final currentEnvelope = await _ledgerStore.readLockHeld(
        currentOpaqueBinding: context.currentOpaqueBinding,
      );
      final currentRecord = currentEnvelope?.records[context.eventCorrelation];
      if (currentEnvelope == null ||
          currentRecord == null ||
          currentRecord.revision != record.revision ||
          _hasUnsettledConversationOwner(
            envelope: currentEnvelope,
            candidate: currentRecord,
          )) {
        return const DurableLocalNotificationEffectResult.retryable();
      }
      record = currentRecord;
      final token = _effectTokenFactory();
      if (!_lowercaseDigest.hasMatch(token)) {
        return const DurableLocalNotificationEffectResult.retryable();
      }
      record = await _transitionLockHeld(
        currentOpaqueBinding: context.currentOpaqueBinding,
        current: record,
        next: record.copyWith(
          effectPhase: LocalNotificationEffectPhase.claimed,
          attemptKind: LocalNotificationAttemptKind.postOrUpdate,
          effectToken: token,
          revision: record.revision + 1,
          updatedAtUtc: _canonicalNow(),
        ),
      );
      if (record == null) {
        return const DurableLocalNotificationEffectResult.retryable();
      }
    } else {
      return const DurableLocalNotificationEffectResult.retryable();
    }

    await prepareContent();
    record = await _transitionLockHeld(
      currentOpaqueBinding: context.currentOpaqueBinding,
      current: record,
      next: record.copyWith(
        effectPhase: LocalNotificationEffectPhase.publishing,
        revision: record.revision + 1,
        updatedAtUtc: _canonicalNow(),
      ),
    );
    if (record == null) {
      return const DurableLocalNotificationEffectResult.retryable();
    }

    final activationCancel = await _armCancelAttemptLockHeld(
      context: context,
      record: record,
    );
    if (activationCancel == null) {
      return const DurableLocalNotificationEffectResult.retryable();
    }
    record = activationCancel;

    // The retired card and activated generation marker are both protected by
    // the same registry lock as PUBLISHING and the callback below.
    try {
      await retireAndActivateContent();
    } on Object {
      // The old-card cancellation may have reached the platform while marker
      // activation did not. The durable activation intent lets recovery
      // resume this exact generation without overwriting a later sibling.
      return const DurableLocalNotificationEffectResult.ambiguous(
        currentNativeEntryAttempted: true,
      );
    }
    final postAttempt = await _armPostAttemptLockHeld(
      context: context,
      record: record,
    );
    if (postAttempt == null) {
      return const DurableLocalNotificationEffectResult.retryable();
    }
    record = postAttempt;
    await completeContentActivation();

    DurableLocalNotificationCanonicalDisposition? canonical;
    AppVisibilityEvaluation? visibility;
    LocalNotificationPresentationState? terminalPresentation;
    Future<bool> authorizeNativeEntry() async {
      canonical = await context.readFinalCanonicalDisposition();
      final contentIsCurrent = await exactContentIsCurrent();
      // This is the final awaited authority read. Production wraps this
      // closure inside the already-armed event/tone owners and enters the
      // platform callback immediately after its boolean result.
      visibility = await appVisibility.evaluate(conversationIdentity);
      if (!contentIsCurrent ||
          canonical ==
              DurableLocalNotificationCanonicalDisposition.retryableUnknown) {
        return false;
      }
      if (canonical == DurableLocalNotificationCanonicalDisposition.cancelled ||
          canonical == DurableLocalNotificationCanonicalDisposition.read) {
        terminalPresentation = LocalNotificationPresentationState.cancelled;
      } else if (canonical ==
          DurableLocalNotificationCanonicalDisposition.suppressedPolicy) {
        terminalPresentation =
            LocalNotificationPresentationState.suppressedPolicy;
      } else if (visibility!.maySuppress &&
          visibility!.hasExactSnapshotMetadata &&
          visibility!.lifecycle == AppVisibilityLifecycle.foregroundActive) {
        terminalPresentation = LocalNotificationPresentationState.inChat;
      } else {
        terminalPresentation = LocalNotificationPresentationState.osPosted;
      }
      return terminalPresentation ==
          LocalNotificationPresentationState.osPosted;
    }

    var currentNativeEntryAttempted = false;
    final publishAtBarrier = publishNativeAtFinalBarrier;
    if (publishAtBarrier != null) {
      try {
        currentNativeEntryAttempted = await publishAtBarrier(
          authorizeNativeEntry,
        );
      } on Object {
        if (terminalPresentation ==
            LocalNotificationPresentationState.osPosted) {
          return const DurableLocalNotificationEffectResult.ambiguous(
            currentNativeEntryAttempted: true,
          );
        }
        return const DurableLocalNotificationEffectResult.retryable();
      }
      if (terminalPresentation == null ||
          canonical == null ||
          visibility == null) {
        return const DurableLocalNotificationEffectResult.retryable();
      }
      if (terminalPresentation == LocalNotificationPresentationState.osPosted &&
          !currentNativeEntryAttempted) {
        return const DurableLocalNotificationEffectResult.retryable();
      }
      if (terminalPresentation != LocalNotificationPresentationState.osPosted &&
          currentNativeEntryAttempted) {
        return const DurableLocalNotificationEffectResult.ambiguous(
          currentNativeEntryAttempted: true,
        );
      }
    } else {
      final authorized = await authorizeNativeEntry();
      if (terminalPresentation == null ||
          canonical == null ||
          visibility == null) {
        return const DurableLocalNotificationEffectResult.retryable();
      }
      if (!authorized) {
        // A known no-effect decision continues below; unknown left the
        // presentation null and returned above.
      } else {
        try {
          currentNativeEntryAttempted = true;
          await publishNative();
        } on Object {
          // Native acceptance is ambiguous. PUBLISHING, token, generation and
          // marker remain intact for exact-ID recovery; never lie as OS_POSTED.
          return const DurableLocalNotificationEffectResult.ambiguous(
            currentNativeEntryAttempted: true,
          );
        }
      }
    }

    final terminalAt = _canonicalNow();
    final terminal = await _transitionLockHeld(
      currentOpaqueBinding: context.currentOpaqueBinding,
      current: record,
      next: record.copyWith(
        readState:
            canonical == DurableLocalNotificationCanonicalDisposition.read
            ? LocalNotificationReadState.read
            : record.readState,
        presentationState: terminalPresentation!,
        lastEvaluatedLifecycle: _ledgerLifecycle(visibility!),
        visibilityRevision: visibility!.hasExactSnapshotMetadata
            ? visibility!.revision
            : null,
        lifecycleGeneration: visibility!.hasExactSnapshotMetadata
            ? visibility!.lifecycleGeneration
            : null,
        effectPhase: LocalNotificationEffectPhase.effectTerminal,
        attemptKind: null,
        effectToken: null,
        revision: record.revision + 1,
        updatedAtUtc: terminalAt,
        terminalAtUtc: terminalAt,
      ),
    );
    if (terminal == null) {
      // A successful callback without a durable terminal remains ambiguous.
      return DurableLocalNotificationEffectResult.ambiguous(
        currentNativeEntryAttempted: currentNativeEntryAttempted,
      );
    }
    if (terminalPresentation != LocalNotificationPresentationState.osPosted) {
      await clearActivatedContent();
    }
    return _terminalResult(
      terminal,
      currentNativeEntryAttempted: currentNativeEntryAttempted,
    );
  }

  Future<DurableLocalNotificationEffectResult> _recoverPublishingLockHeld({
    required DurableLocalNotificationEffectContext context,
    required LocalNotificationRecordV1 record,
    required int notificationId,
    required AppVisibilitySuppressionReader appVisibility,
    required AppVisibilityConversationIdentity conversationIdentity,
    required Future<void> Function() retireCurrent,
    required Future<bool> Function() ensureContentActivated,
    required Future<bool> Function() hasContentActivationIntent,
    required Future<void> Function() completeContentActivation,
    required Future<bool> Function() exactContentIsCurrent,
    required Future<void> Function() clearActivatedContent,
    required Future<void> Function() publishNative,
    required Future<void> Function()? publishNativeSilently,
    required ResolveDurableLocalNotificationActiveIds? activeNotificationIds,
  }) async {
    var currentRecord = record;
    final activationIntentPending = await hasContentActivationIntent();
    if (activationIntentPending &&
        currentRecord.attemptKind ==
            LocalNotificationAttemptKind.postOrUpdate) {
      final armed = await _armCancelAttemptLockHeld(
        context: context,
        record: currentRecord,
      );
      if (armed == null) {
        return const DurableLocalNotificationEffectResult.retryable();
      }
      currentRecord = armed;
    }
    try {
      if (!await ensureContentActivated()) {
        return const DurableLocalNotificationEffectResult.retryable();
      }
    } on Object {
      return const DurableLocalNotificationEffectResult.ambiguous(
        currentNativeEntryAttempted: true,
      );
    }
    if (activationIntentPending) {
      final postAttempt = await _armPostAttemptLockHeld(
        context: context,
        record: currentRecord,
      );
      if (postAttempt == null) {
        return const DurableLocalNotificationEffectResult.retryable();
      }
      currentRecord = postAttempt;
      await completeContentActivation();
    }
    final canonical = await context.readFinalCanonicalDisposition();
    final contentIsCurrent = await exactContentIsCurrent();

    var inventorySucceeded = false;
    var exactIdIsActive = false;
    if (contentIsCurrent &&
        currentRecord.attemptKind != LocalNotificationAttemptKind.cancel &&
        canonical == DurableLocalNotificationCanonicalDisposition.eligible) {
      final resolveActive = activeNotificationIds;
      if (resolveActive != null) {
        try {
          final activeIds = await resolveActive();
          inventorySucceeded = true;
          exactIdIsActive = activeIds.any(
            (candidate) => candidate is int && candidate == notificationId,
          );
        } on Object {
          inventorySucceeded = false;
        }
      }
    }

    // As on a first attempt, visibility is the final awaited authority read.
    // Any cancel or silent repair callback below is entered immediately after
    // synchronous branches over these captured facts.
    final visibility = await appVisibility.evaluate(conversationIdentity);
    if (!contentIsCurrent ||
        canonical ==
            DurableLocalNotificationCanonicalDisposition.retryableUnknown) {
      return const DurableLocalNotificationEffectResult.retryable();
    }

    // Once an exact cancellation has been armed, recovery must retry that
    // operation. Reinterpreting it as POST_OR_UPDATE could resurrect a card
    // after an ambiguous native cancel.
    if (currentRecord.attemptKind == LocalNotificationAttemptKind.cancel) {
      try {
        await retireCurrent();
      } on Object {
        return const DurableLocalNotificationEffectResult.ambiguous(
          currentNativeEntryAttempted: true,
        );
      }
      final pendingPresentation = switch (canonical) {
        DurableLocalNotificationCanonicalDisposition.suppressedPolicy =>
          LocalNotificationPresentationState.suppressedPolicy,
        _ => LocalNotificationPresentationState.cancelled,
      };
      return _finishRecoveredPublishingLockHeld(
        context: context,
        record: currentRecord,
        visibility: visibility,
        presentation: pendingPresentation,
        markRead:
            canonical == DurableLocalNotificationCanonicalDisposition.read,
        clearActivatedContent: clearActivatedContent,
        currentNativeEntryAttempted: true,
      );
    }

    final presentationFromCanonical = switch (canonical) {
      DurableLocalNotificationCanonicalDisposition.cancelled ||
      DurableLocalNotificationCanonicalDisposition.read =>
        LocalNotificationPresentationState.cancelled,
      DurableLocalNotificationCanonicalDisposition.suppressedPolicy =>
        LocalNotificationPresentationState.suppressedPolicy,
      DurableLocalNotificationCanonicalDisposition.eligible ||
      DurableLocalNotificationCanonicalDisposition.retryableUnknown => null,
    };
    if (presentationFromCanonical != null) {
      final armed = await _armCancelAttemptLockHeld(
        context: context,
        record: currentRecord,
      );
      if (armed == null) {
        return const DurableLocalNotificationEffectResult.retryable();
      }
      currentRecord = armed;
      try {
        await retireCurrent();
      } on Object {
        return const DurableLocalNotificationEffectResult.ambiguous(
          currentNativeEntryAttempted: true,
        );
      }
      return _finishRecoveredPublishingLockHeld(
        context: context,
        record: currentRecord,
        visibility: visibility,
        presentation: presentationFromCanonical,
        markRead:
            canonical == DurableLocalNotificationCanonicalDisposition.read,
        clearActivatedContent: clearActivatedContent,
        currentNativeEntryAttempted: true,
      );
    }

    if (inventorySucceeded && exactIdIsActive) {
      // Exact stable ID plus the exact on-disk generation proves the prior
      // native post/update. Never invoke the native callback a second time.
      return _finishRecoveredPublishingLockHeld(
        context: context,
        record: currentRecord,
        visibility: visibility,
        presentation: LocalNotificationPresentationState.osPosted,
        clearActivatedContent: clearActivatedContent,
        currentNativeEntryAttempted: false,
      );
    }

    final finalSameChat =
        visibility.maySuppress &&
        visibility.hasExactSnapshotMetadata &&
        visibility.lifecycle == AppVisibilityLifecycle.foregroundActive;
    final recoveryHorizonReached = _publishingRecoveryHorizonReached(record);
    if (finalSameChat) {
      if (!inventorySucceeded && !recoveryHorizonReached) {
        return const DurableLocalNotificationEffectResult.ambiguous();
      }
      if (!inventorySucceeded) {
        final armed = await _armCancelAttemptLockHeld(
          context: context,
          record: currentRecord,
        );
        if (armed == null) {
          return const DurableLocalNotificationEffectResult.retryable();
        }
        currentRecord = armed;
        try {
          await retireCurrent();
        } on Object {
          return const DurableLocalNotificationEffectResult.ambiguous(
            currentNativeEntryAttempted: true,
          );
        }
      }
      return _finishRecoveredPublishingLockHeld(
        context: context,
        record: currentRecord,
        visibility: visibility,
        presentation: LocalNotificationPresentationState.inChat,
        clearActivatedContent: clearActivatedContent,
        currentNativeEntryAttempted: !inventorySucceeded,
      );
    }

    if (!inventorySucceeded && !recoveryHorizonReached) {
      return const DurableLocalNotificationEffectResult.ambiguous();
    }
    final publishSilent = publishNativeSilently;
    if (publishSilent == null) {
      // A recovery caller that cannot force the same-ID repair silent has no
      // authority to reuse the ordinary publication callback. Its original
      // tone/event leases may already have expired.
      return const DurableLocalNotificationEffectResult.ambiguous();
    }
    try {
      await publishSilent();
    } on Object {
      return const DurableLocalNotificationEffectResult.ambiguous(
        currentNativeEntryAttempted: true,
        currentNativeEntryWasSilentRepair: true,
      );
    }
    return _finishRecoveredPublishingLockHeld(
      context: context,
      record: currentRecord,
      visibility: visibility,
      presentation: LocalNotificationPresentationState.osPosted,
      clearActivatedContent: clearActivatedContent,
      currentNativeEntryAttempted: true,
      currentNativeEntryWasSilentRepair: true,
    );
  }

  Future<LocalNotificationRecordV1?> _armCancelAttemptLockHeld({
    required DurableLocalNotificationEffectContext context,
    required LocalNotificationRecordV1 record,
  }) async {
    if (record.attemptKind == LocalNotificationAttemptKind.cancel) {
      return record;
    }
    if (record.effectPhase != LocalNotificationEffectPhase.publishing ||
        record.attemptKind != LocalNotificationAttemptKind.postOrUpdate) {
      return null;
    }
    return _transitionLockHeld(
      currentOpaqueBinding: context.currentOpaqueBinding,
      current: record,
      next: record.copyWith(
        attemptKind: LocalNotificationAttemptKind.cancel,
        // The token identifies the same ambiguous native attempt. Changing
        // only its operation makes crash recovery exact without minting a
        // second owner.
        effectToken: record.effectToken,
        revision: record.revision + 1,
        updatedAtUtc: _canonicalNow(),
      ),
    );
  }

  Future<LocalNotificationRecordV1?> _armPostAttemptLockHeld({
    required DurableLocalNotificationEffectContext context,
    required LocalNotificationRecordV1 record,
  }) async {
    if (record.effectPhase != LocalNotificationEffectPhase.publishing ||
        record.attemptKind != LocalNotificationAttemptKind.cancel) {
      return null;
    }
    return _transitionLockHeld(
      currentOpaqueBinding: context.currentOpaqueBinding,
      current: record,
      next: record.copyWith(
        attemptKind: LocalNotificationAttemptKind.postOrUpdate,
        effectToken: record.effectToken,
        revision: record.revision + 1,
        updatedAtUtc: _canonicalNow(),
      ),
    );
  }

  Future<DurableLocalNotificationEffectResult>
  _finishRecoveredPublishingLockHeld({
    required DurableLocalNotificationEffectContext context,
    required LocalNotificationRecordV1 record,
    required AppVisibilityEvaluation visibility,
    required LocalNotificationPresentationState presentation,
    bool markRead = false,
    required Future<void> Function() clearActivatedContent,
    required bool currentNativeEntryAttempted,
    bool currentNativeEntryWasSilentRepair = false,
  }) async {
    final terminalAt = _canonicalNow();
    final terminal = await _transitionLockHeld(
      currentOpaqueBinding: context.currentOpaqueBinding,
      current: record,
      next: record.copyWith(
        readState: markRead
            ? LocalNotificationReadState.read
            : record.readState,
        presentationState: presentation,
        lastEvaluatedLifecycle: _ledgerLifecycle(visibility),
        visibilityRevision: visibility.hasExactSnapshotMetadata
            ? visibility.revision
            : null,
        lifecycleGeneration: visibility.hasExactSnapshotMetadata
            ? visibility.lifecycleGeneration
            : null,
        effectPhase: LocalNotificationEffectPhase.effectTerminal,
        attemptKind: null,
        effectToken: null,
        revision: record.revision + 1,
        updatedAtUtc: terminalAt,
        terminalAtUtc: terminalAt,
      ),
    );
    if (terminal == null) {
      return DurableLocalNotificationEffectResult.ambiguous(
        currentNativeEntryAttempted: currentNativeEntryAttempted,
        currentNativeEntryWasSilentRepair: currentNativeEntryWasSilentRepair,
      );
    }
    if (presentation != LocalNotificationPresentationState.osPosted) {
      await clearActivatedContent();
    }
    return _terminalResult(
      terminal,
      currentNativeEntryAttempted: currentNativeEntryAttempted,
      currentNativeEntryWasSilentRepair: currentNativeEntryWasSilentRepair,
    );
  }

  bool _publishingRecoveryHorizonReached(LocalNotificationRecordV1 record) {
    final updatedAt = DateTime.tryParse(record.updatedAtUtc)?.toUtc();
    if (updatedAt == null) return false;
    return !_nowUtc().toUtc().isBefore(
      updatedAt.add(_publishingRecoveryHorizon),
    );
  }

  bool _hasUnsettledConversationOwner({
    required LocalNotificationLedgerEnvelopeV1 envelope,
    required LocalNotificationRecordV1 candidate,
  }) => envelope.records.values.any((other) {
    if (other.eventCorrelation == candidate.eventCorrelation ||
        other.conversationDigest != candidate.conversationDigest ||
        other.notificationId != candidate.notificationId) {
      return false;
    }
    return other.effectPhase == LocalNotificationEffectPhase.claimed ||
        other.effectPhase == LocalNotificationEffectPhase.publishing;
  });

  bool _claimedRecoveryHorizonReached(LocalNotificationRecordV1 record) {
    final updatedAt = DateTime.tryParse(record.updatedAtUtc)?.toUtc();
    if (updatedAt == null) return false;
    return !_nowUtc().toUtc().isBefore(updatedAt.add(_claimedRecoveryHorizon));
  }

  Future<LocalNotificationRecordV1?> settleSqlReadyEffectLockHeld({
    required String currentOpaqueBinding,
    required String eventCorrelation,
    required int expectedRevision,
  }) async {
    final envelope = await _ledgerStore.readLockHeld(
      currentOpaqueBinding: currentOpaqueBinding,
    );
    final current = envelope?.records[eventCorrelation];
    if (current == null ||
        current.sourceCustody != LocalNotificationSourceCustody.sqlReady) {
      return null;
    }
    if (current.effectPhase == LocalNotificationEffectPhase.settled &&
        expectedRevision < localNotificationLedgerMaxSignedInt64 &&
        current.revision == expectedRevision + 1) {
      return current;
    }
    if (current.effectPhase != LocalNotificationEffectPhase.effectTerminal ||
        current.revision != expectedRevision) {
      return null;
    }
    final settledAt = _canonicalNow();
    return _transitionLockHeld(
      currentOpaqueBinding: currentOpaqueBinding,
      current: current,
      next: current.copyWith(
        effectPhase: LocalNotificationEffectPhase.settled,
        revision: current.revision + 1,
        updatedAtUtc: settledAt,
        settledAtUtc: settledAt,
      ),
    );
  }

  Future<LocalNotificationRecordV1?> lookupExactEffectLockHeld({
    required String currentOpaqueBinding,
    required String eventCorrelation,
    required String conversationDigest,
    required int notificationId,
    required String contentGeneration,
  }) async {
    if (!_lowercaseDigest.hasMatch(eventCorrelation) ||
        !_lowercaseDigest.hasMatch(conversationDigest) ||
        notificationId < 0 ||
        notificationId > localNotificationLedgerMaxNotificationId ||
        contentGeneration.trim().isEmpty) {
      return null;
    }
    final envelope = await _ledgerStore.readLockHeld(
      currentOpaqueBinding: currentOpaqueBinding,
    );
    final record = envelope?.records[eventCorrelation];
    if (record == null ||
        record.conversationDigest != conversationDigest ||
        record.notificationId != notificationId ||
        record.contentGeneration != contentGeneration) {
      return null;
    }
    return record;
  }

  Future<List<LocalNotificationRecordV1>> listSqlReadyEffectTerminalsLockHeld({
    required String currentOpaqueBinding,
  }) async {
    final envelope = await _ledgerStore.readLockHeld(
      currentOpaqueBinding: currentOpaqueBinding,
    );
    if (envelope == null || envelope.claimsSuspended) {
      throw StateError('local notification ledger authority unavailable');
    }
    final terminals =
        envelope.records.values
            .where(
              (record) =>
                  record.sourceCustody ==
                      LocalNotificationSourceCustody.sqlReady &&
                  (record.effectPhase ==
                          LocalNotificationEffectPhase.effectTerminal ||
                      record.effectPhase ==
                          LocalNotificationEffectPhase.settled),
            )
            .toList(growable: false)
          ..sort(
            (left, right) =>
                left.eventCorrelation.compareTo(right.eventCorrelation),
          );
    return List<LocalNotificationRecordV1>.unmodifiable(terminals);
  }

  Future<LocalNotificationRecordV1?> upgradeRelayCustodyToSqlReadyLockHeld({
    required String currentOpaqueBinding,
    required String eventCorrelation,
    required int expectedRevision,
  }) async {
    final envelope = await _ledgerStore.readLockHeld(
      currentOpaqueBinding: currentOpaqueBinding,
    );
    final current = envelope?.records[eventCorrelation];
    if (current == null ||
        current.effectPhase == LocalNotificationEffectPhase.settled) {
      return null;
    }
    if (current.sourceCustody == LocalNotificationSourceCustody.sqlReady &&
        expectedRevision < localNotificationLedgerMaxSignedInt64 &&
        current.revision == expectedRevision + 1) {
      return current;
    }
    if (current.sourceCustody !=
            LocalNotificationSourceCustody.relayVerifiedUnacked ||
        current.revision != expectedRevision) {
      return null;
    }
    return _transitionLockHeld(
      currentOpaqueBinding: currentOpaqueBinding,
      current: current,
      next: current.copyWith(
        sourceCustody: LocalNotificationSourceCustody.sqlReady,
        revision: current.revision + 1,
        updatedAtUtc: current.updatedAtUtc,
      ),
    );
  }

  Future<LocalNotificationRecordV1?> _seedReadyRecordLockHeld({
    required DurableLocalNotificationEffectContext context,
    required int notificationId,
    required String contentGeneration,
  }) async {
    LocalNotificationRecordV1? seeded;
    final now = _canonicalNow();
    final envelope = await _ledgerStore.mutateLockHeld(
      currentOpaqueBinding: context.currentOpaqueBinding,
      mutation: (current) {
        if (current.claimsSuspended ||
            current.records.containsKey(context.eventCorrelation) ||
            current.storeRevision == localNotificationLedgerMaxSignedInt64) {
          return null;
        }
        final candidate = LocalNotificationRecordV1(
          eventCorrelation: context.eventCorrelation,
          conversationDigest: context.conversationDigest,
          producerKind: context.producerKind,
          sourceCustody: context.sourceCustody,
          readState: LocalNotificationReadState.unread,
          presentationState: LocalNotificationPresentationState.notEvaluated,
          presentationOwner: context.presentationOwner,
          notificationId: notificationId,
          contentGeneration: contentGeneration,
          lastEvaluatedLifecycle: LocalNotificationEvaluatedLifecycle.unknown,
          visibilityRevision: null,
          lifecycleGeneration: null,
          effectPhase: LocalNotificationEffectPhase.ready,
          attemptKind: null,
          effectToken: null,
          revision: 1,
          createdAtUtc: now,
          updatedAtUtc: now,
          terminalAtUtc: null,
          settledAtUtc: null,
        );
        if (!candidate.isValid) return null;
        seeded = candidate;
        return current.copyWith(
          storeRevision: current.storeRevision + 1,
          records: <String, LocalNotificationRecordV1>{
            ...current.records,
            candidate.eventCorrelation: candidate,
          },
        );
      },
    );
    return envelope == null ? null : seeded;
  }

  Future<LocalNotificationRecordV1?> _transitionLockHeld({
    required String currentOpaqueBinding,
    required LocalNotificationRecordV1 current,
    required LocalNotificationRecordV1 next,
  }) async {
    LocalNotificationRecordV1? accepted;
    final envelope = await _ledgerStore.mutateLockHeld(
      currentOpaqueBinding: currentOpaqueBinding,
      mutation: (store) {
        if (store.claimsSuspended ||
            store.storeRevision == localNotificationLedgerMaxSignedInt64 ||
            !_sameRecord(store.records[current.eventCorrelation], current)) {
          return null;
        }
        final transitioned =
            LocalNotificationLedgerStateMachineV1.tryTransition(
              current: current,
              expectedRevision: current.revision,
              next: next,
            );
        if (transitioned == null) return null;
        accepted = transitioned;
        return store.copyWith(
          storeRevision: store.storeRevision + 1,
          records: <String, LocalNotificationRecordV1>{
            ...store.records,
            transitioned.eventCorrelation: transitioned,
          },
        );
      },
    );
    return envelope == null ? null : accepted;
  }

  bool _recordMatchesBaseIdentity({
    required LocalNotificationRecordV1 record,
    required DurableLocalNotificationEffectContext context,
  }) =>
      record.eventCorrelation == context.eventCorrelation &&
      record.conversationDigest == context.conversationDigest &&
      record.producerKind == context.producerKind;

  bool _recordMatchesContent({
    required LocalNotificationRecordV1 record,
    required int notificationId,
    required String contentGeneration,
  }) =>
      record.notificationId == notificationId &&
      record.contentGeneration == contentGeneration;

  DurableLocalNotificationEffectResult _terminalResult(
    LocalNotificationRecordV1 record, {
    bool currentNativeEntryAttempted = false,
    bool currentNativeEntryWasSilentRepair = false,
  }) {
    final disposition = switch (record.presentationState) {
      LocalNotificationPresentationState.osPosted =>
        DurableLocalNotificationEffectDisposition.osPosted,
      LocalNotificationPresentationState.inChat =>
        DurableLocalNotificationEffectDisposition.inChat,
      LocalNotificationPresentationState.suppressedPolicy =>
        DurableLocalNotificationEffectDisposition.suppressedPolicy,
      LocalNotificationPresentationState.cancelled =>
        DurableLocalNotificationEffectDisposition.cancelled,
      LocalNotificationPresentationState.notEvaluated =>
        DurableLocalNotificationEffectDisposition.retryable,
    };
    return DurableLocalNotificationEffectResult(
      disposition: disposition,
      currentNativeEntryAttempted: currentNativeEntryAttempted,
      currentNativeEntryWasSilentRepair: currentNativeEntryWasSilentRepair,
      receipt:
          disposition == DurableLocalNotificationEffectDisposition.retryable
          ? null
          : DurableLocalNotificationEffectReceipt(
              eventCorrelation: record.eventCorrelation,
              // A SETTLED replay hands the SQL owner the preceding exact
              // EFFECT_TERMINAL revision so its idempotent settle CAS has the
              // same receipt semantics on both sides of the crash cut.
              recordRevision:
                  record.effectPhase == LocalNotificationEffectPhase.settled
                  ? record.revision - 1
                  : record.revision,
              presentationState: record.presentationState,
            ),
    );
  }

  String _canonicalNow() => _nowUtc().toUtc().toIso8601String();
}

LocalNotificationEvaluatedLifecycle _ledgerLifecycle(
  AppVisibilityEvaluation visibility,
) {
  if (!visibility.hasExactSnapshotMetadata) {
    return LocalNotificationEvaluatedLifecycle.unknown;
  }
  return switch (visibility.lifecycle!) {
    AppVisibilityLifecycle.foregroundActive =>
      LocalNotificationEvaluatedLifecycle.foregroundActive,
    AppVisibilityLifecycle.inactive =>
      LocalNotificationEvaluatedLifecycle.inactive,
    AppVisibilityLifecycle.background =>
      LocalNotificationEvaluatedLifecycle.background,
  };
}

final RegExp _lowercaseDigest = RegExp(r'^[0-9a-f]{64}$');
const Duration _publishingRecoveryHorizon = Duration(seconds: 65);
const Duration _claimedRecoveryHorizon = Duration(seconds: 60);

bool _isPositiveLedgerInt64(Object? value) =>
    value is int && value > 0 && value <= localNotificationLedgerMaxSignedInt64;

String _newEffectToken() {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var index = 0; index < 32; index++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

bool _producerMatchesContentKind(
  LocalNotificationProducerKind producer,
  ConversationNotificationContentKind contentKind,
) => switch (producer) {
  LocalNotificationProducerKind.directMessage ||
  LocalNotificationProducerKind.groupMessage =>
    contentKind == ConversationNotificationContentKind.message,
  LocalNotificationProducerKind.directReaction ||
  LocalNotificationProducerKind.groupReaction =>
    contentKind == ConversationNotificationContentKind.reaction,
};

bool _isNativePresentationOwner(LocalNotificationPresentationOwner owner) =>
    owner == LocalNotificationPresentationOwner.iosNse ||
    owner == LocalNotificationPresentationOwner.androidPushService;

bool _sameRecord(
  LocalNotificationRecordV1? left,
  LocalNotificationRecordV1 right,
) => left != null && jsonEncode(left.toJson()) == jsonEncode(right.toJson());
