import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLane
    implements
        PrivateMediaLifecycleLaneAdapter,
        PrivateMediaIndeterminateQuarantineAdapter {
  _FakeLane(
    this.target, {
    this.rollbackThrowsAfterCommit = false,
    this.rollbackLosesToTerminal = false,
    this.consumeThrowsRemaining = 0,
    this.firstConsumeThrowLeavesAvailable = false,
    this.quarantineLosesToChangedIdentity = false,
  });

  PrivateMediaLifecycleTarget target;
  final bool rollbackThrowsAfterCommit;
  final bool rollbackLosesToTerminal;
  int consumeThrowsRemaining;
  final bool firstConsumeThrowLeavesAvailable;
  final bool quarantineLosesToChangedIdentity;
  int cleanupCalls = 0;
  int rollbackCalls = 0;
  int consumeCalls = 0;
  int quarantineCalls = 0;
  PrivateMediaLifecycleState? stateObservedAtCleanup;

  bool get _isQualifiedLeaseTarget =>
      (target.direction == PrivateMediaDirection.incoming &&
          target.mode == PrivateMediaMode.viewOnce) ||
      (target.direction == PrivateMediaDirection.outgoing &&
          (target.mode == PrivateMediaMode.protected ||
              target.mode == PrivateMediaMode.viewOnce));

  @override
  Future<PrivateMediaLifecycleTarget?> loadTarget(String messageId) async =>
      target.messageId == messageId ? target : null;

  @override
  Future<bool> claimOpening(
    PrivateMediaOpeningLeaseIdentity identity, {
    required int nowMs,
  }) async {
    if (!_isQualifiedLeaseTarget ||
        target.state != PrivateMediaLifecycleState.available ||
        target.hidden) {
      return false;
    }
    target = target.copyWith(
      state: PrivateMediaLifecycleState.opening,
      clockHighWaterMs: nowMs,
    );
    return true;
  }

  @override
  Future<bool> markViewing(
    PrivateMediaOpeningLeaseIdentity identity, {
    required int nowMs,
  }) async {
    if (target.hidden ||
        target.terminalAtMs != null ||
        !_isQualifiedLeaseTarget ||
        target.state != PrivateMediaLifecycleState.opening) {
      return false;
    }
    target = target.copyWith(
      state: PrivateMediaLifecycleState.viewing,
      revealedAtMs: nowMs,
      clockHighWaterMs: nowMs,
    );
    return true;
  }

  @override
  Future<bool> rollbackOpening(
    PrivateMediaOpeningLeaseIdentity identity,
  ) async {
    if (target.hidden ||
        target.terminalAtMs != null ||
        !_isQualifiedLeaseTarget ||
        target.state != PrivateMediaLifecycleState.opening ||
        target.revealedAtMs != null) {
      return false;
    }
    rollbackCalls++;
    if (rollbackLosesToTerminal) {
      target = target.copyWith(
        state: PrivateMediaLifecycleState.consumed,
        terminalAtMs: 1099,
      );
      return false;
    }
    target = target.copyWith(state: PrivateMediaLifecycleState.available);
    if (rollbackThrowsAfterCommit) {
      throw StateError('rollback committed then response was lost');
    }
    return true;
  }

  @override
  Future<bool> consume(String messageId, {required int nowMs}) async {
    if (target.hidden ||
        target.terminalAtMs != null ||
        !_isQualifiedLeaseTarget ||
        (target.state != PrivateMediaLifecycleState.opening &&
            target.state != PrivateMediaLifecycleState.viewing)) {
      return false;
    }
    consumeCalls++;
    if (consumeThrowsRemaining > 0) {
      consumeThrowsRemaining--;
      if (firstConsumeThrowLeavesAvailable && consumeCalls == 1) {
        target = target.copyWith(state: PrivateMediaLifecycleState.available);
      }
      throw StateError('consume persistence response was lost');
    }
    target = target.copyWith(
      state: PrivateMediaLifecycleState.consumed,
      terminalAtMs: nowMs,
      clockHighWaterMs: nowMs,
    );
    return true;
  }

  @override
  Future<bool> consumeOpening(
    PrivateMediaOpeningLeaseIdentity identity, {
    required int nowMs,
  }) => consume(identity.messageId, nowMs: nowMs);

  @override
  Future<bool> quarantineIndeterminateAvailable(
    PrivateMediaOpeningLeaseIdentity identity, {
    required int nowMs,
  }) async {
    quarantineCalls++;
    if (quarantineLosesToChangedIdentity && target.attachments.length == 1) {
      final attachment = target.attachments.single;
      target = target.copyWith(
        attachments: [
          PrivateMediaLifecycleAttachment(
            id: attachment.id,
            messageId: attachment.messageId,
            storedLocalPath: 'media/contact-1/replaced.jpg',
            localPath: 'media/contact-1/replaced.jpg',
            mime: attachment.mime,
            size: attachment.size,
            isDownloadComplete: attachment.isDownloadComplete,
            isIntegrityEligible: attachment.isIntegrityEligible,
          ),
        ],
      );
      return false;
    }
    if (target.state != PrivateMediaLifecycleState.available ||
        target.messageId != identity.messageId ||
        target.direction != identity.direction ||
        target.mode != identity.mode ||
        target.attachments.length != 1) {
      return false;
    }
    final attachment = target.attachments.single;
    if (attachment.id != identity.attachmentId ||
        attachment.storedLocalPath != identity.storedLocalPath ||
        attachment.localPath != identity.localPath) {
      return false;
    }
    target = target.copyWith(
      state: PrivateMediaLifecycleState.opening,
      clockHighWaterMs: nowMs,
    );
    return true;
  }

  @override
  Future<bool> advanceClock(String messageId, {required int nowMs}) async {
    final high = target.clockHighWaterMs ?? 0;
    final effective = nowMs > high ? nowMs : high;
    if (target.mode != PrivateMediaMode.disappearing || target.hidden) {
      return false;
    }
    var state = target.state;
    int? terminal = target.terminalAtMs;
    if (target.expiresAtMs != null && effective >= target.expiresAtMs!) {
      state = PrivateMediaLifecycleState.expired;
      terminal ??= effective;
    }
    target = target.copyWith(
      state: state,
      terminalAtMs: terminal,
      clockHighWaterMs: effective,
    );
    return true;
  }

  @override
  Future<bool> failClosedCorruptState(
    String messageId, {
    required int nowMs,
  }) async {
    target = target.copyWith(
      state: PrivateMediaLifecycleState.unsupported,
      terminalAtMs: nowMs,
    );
    return true;
  }

  @override
  Future<List<PrivateMediaLifecycleTarget>> loadActiveDisappearing({
    int limit = 100,
  }) async =>
      target.mode == PrivateMediaMode.disappearing &&
          !target.state.isTerminal &&
          !target.hidden
      ? [target]
      : const [];

  @override
  Future<List<PrivateMediaLifecycleTarget>> loadRecoveryCandidates({
    int limit = 100,
  }) async => [target];

  @override
  Future<bool> rotateRecoveryCandidate(
    String messageId, {
    required int nowMs,
  }) async {
    target = target.copyWith(clockHighWaterMs: nowMs);
    return true;
  }

  @override
  Future<int?> loadNextExpiryAtMs() async => target.expiresAtMs;

  @override
  Future<void> cleanupTerminalWithinLock(
    PrivateMediaLifecycleTarget current,
  ) async {
    cleanupCalls++;
    stateObservedAtCleanup = target.state;
    target = target.copyWith(attachments: const []);
  }
}

PrivateMediaLifecycleTarget _target({
  PrivateMediaMode mode = PrivateMediaMode.viewOnce,
  PrivateMediaLifecycleState state = PrivateMediaLifecycleState.available,
  PrivateMediaDirection direction = PrivateMediaDirection.incoming,
  bool isDownloadComplete = true,
  bool isIntegrityEligible = true,
}) {
  return PrivateMediaLifecycleTarget(
    messageId: 'message-1',
    scopeId: 'contact-1',
    direction: direction,
    mode: mode,
    state: state,
    clockHighWaterMs: 1000,
    attachments: [
      PrivateMediaLifecycleAttachment(
        id: 'attachment-1',
        messageId: 'message-1',
        storedLocalPath: 'media/contact-1/attachment-1.jpg',
        localPath: 'media/contact-1/attachment-1.jpg',
        mime: 'image/jpeg',
        size: 3,
        isDownloadComplete: isDownloadComplete,
        isIntegrityEligible: isIntegrityEligible,
      ),
    ],
  );
}

void main() {
  test('two concurrent opens yield exactly one ephemeral lease', () async {
    final lane = _FakeLane(_target());
    final engine = PrivateMediaLifecycleEngine(
      adapter: lane,
      lifecycleLock: MediaAttachmentLifecycleLock(),
      nowMs: () => 1100,
    );

    final leases = await Future.wait([
      engine.openViewOnce('message-1'),
      engine.openViewOnce('message-1'),
    ]);

    expect(leases.whereType<PrivateMediaOpeningLease>(), hasLength(1));
    expect(lane.target.state, PrivateMediaLifecycleState.opening);
  });

  test('only the active pre-frame lease may roll opening back', () async {
    final lane = _FakeLane(_target());
    var now = 1100;
    final engine = PrivateMediaLifecycleEngine(
      adapter: lane,
      lifecycleLock: MediaAttachmentLifecycleLock(),
      nowMs: () => now,
    );
    final lease = (await engine.openViewOnce('message-1'))!;

    expect(await engine.markFirstFrame(lease), isTrue);
    now = 1200;
    expect(await engine.rollbackPreFirstFrame(lease), isFalse);
    expect(lane.target.state, PrivateMediaLifecycleState.viewing);

    expect(await engine.terminalizeViewOnce(lease), isTrue);
    expect(lane.stateObservedAtCleanup, PrivateMediaLifecycleState.consumed);
    expect(await engine.markFirstFrame(lease), isFalse);
    expect(await engine.rollbackPreFirstFrame(lease), isFalse);
  });

  test(
    'proven pre-frame failure rolls back only the same active lease',
    () async {
      final lane = _FakeLane(_target());
      final engine = PrivateMediaLifecycleEngine(
        adapter: lane,
        lifecycleLock: MediaAttachmentLifecycleLock(),
        nowMs: () => 1100,
      );
      final lease = (await engine.openViewOnce('message-1'))!;

      expect(await engine.rollbackPreFirstFrame(lease), isTrue);
      expect(lane.target.state, PrivateMediaLifecycleState.available);
      expect(await engine.rollbackPreFirstFrame(lease), isFalse);

      final replacement = (await engine.openViewOnce('message-1'))!;
      expect(await engine.markFirstFrame(lease), isFalse);
      expect(await engine.markFirstFrame(replacement), isTrue);
    },
  );

  test(
    'restart opening/viewing terminalizes fail closed before cleanup',
    () async {
      for (final interrupted in [
        PrivateMediaLifecycleState.opening,
        PrivateMediaLifecycleState.viewing,
      ]) {
        final lane = _FakeLane(_target(state: interrupted));
        final restarted = PrivateMediaLifecycleEngine(
          adapter: lane,
          lifecycleLock: MediaAttachmentLifecycleLock(),
          nowMs: () => 2000,
        );

        await restarted.reconcileLocalLifecycle();

        expect(lane.target.state, PrivateMediaLifecycleState.consumed);
        expect(
          lane.stateObservedAtCleanup,
          PrivateMediaLifecycleState.consumed,
        );
      }
    },
  );

  test('route exit before first frame consumes before cleanup', () async {
    final lane = _FakeLane(_target());
    final engine = PrivateMediaLifecycleEngine(
      adapter: lane,
      lifecycleLock: MediaAttachmentLifecycleLock(),
      nowMs: () => 1500,
    );
    final lease = (await engine.openViewOnce('message-1'))!;

    expect(await engine.terminalizeViewOnce(lease), isTrue);
    expect(lane.stateObservedAtCleanup, PrivateMediaLifecycleState.consumed);
    expect(await engine.markFirstFrame(lease), isFalse);
  });

  test('first-frame callback losing to external delete is rejected', () async {
    final lane = _FakeLane(_target());
    final engine = PrivateMediaLifecycleEngine(
      adapter: lane,
      lifecycleLock: MediaAttachmentLifecycleLock(),
      nowMs: () => 1500,
    );
    final lease = (await engine.openViewOnce('message-1'))!;
    lane.target = lane.target.copyWith(hidden: true, terminalAtMs: 1450);

    expect(await engine.markFirstFrame(lease), isFalse);
    expect(lane.target.state, PrivateMediaLifecycleState.opening);
    expect(lane.target.revealedAtMs, isNull);
  });

  test('protected and disappearing never acquire View Once leases', () async {
    for (final mode in [
      PrivateMediaMode.protected,
      PrivateMediaMode.disappearing,
    ]) {
      final lane = _FakeLane(_target(mode: mode));
      final engine = PrivateMediaLifecycleEngine(
        adapter: lane,
        lifecycleLock: MediaAttachmentLifecycleLock(),
        nowMs: () => 1100,
      );
      expect(await engine.openViewOnce('message-1'), isNull);
      expect(lane.target.state, PrivateMediaLifecycleState.available);
    }
  });

  test('stale nonempty local path cannot mint a View Once lease', () async {
    for (final target in [
      _target(isDownloadComplete: false),
      _target(isIntegrityEligible: false),
    ]) {
      final lane = _FakeLane(target);
      final engine = PrivateMediaLifecycleEngine(
        adapter: lane,
        lifecycleLock: MediaAttachmentLifecycleLock(),
        nowMs: () => 1100,
      );

      expect(await engine.openViewOnce('message-1'), isNull);
      expect(lane.target.state, PrivateMediaLifecycleState.available);
    }
  });

  test(
    'rollback exception rereads available and caches the exact result',
    () async {
      final lane = _FakeLane(_target(), rollbackThrowsAfterCommit: true);
      final engine = PrivateMediaLifecycleEngine(
        adapter: lane,
        lifecycleLock: MediaAttachmentLifecycleLock(),
        nowMs: () => 1100,
      );
      final lease = (await engine.openOneShot('message-1'))!;

      final first = await engine.settleOpeningLease(
        lease,
        intent: PrivateMediaLifecycleSettlementIntent.rollbackPreFrame,
      );
      final repeated = await engine.settleOpeningLease(
        lease,
        intent: PrivateMediaLifecycleSettlementIntent.terminalize,
      );

      expect(
        first,
        PrivateMediaLifecycleSettlementDisposition.rolledBackAvailable,
      );
      expect(repeated, first);
      expect(lane.rollbackCalls, 1);
      expect(lane.consumeCalls, 0);
      expect(lane.target.state, PrivateMediaLifecycleState.available);
    },
  );

  test('rollback lost race never reports safe availability', () async {
    final lane = _FakeLane(_target(), rollbackLosesToTerminal: true);
    final engine = PrivateMediaLifecycleEngine(
      adapter: lane,
      lifecycleLock: MediaAttachmentLifecycleLock(),
      nowMs: () => 1100,
    );
    final lease = (await engine.openOneShot('message-1'))!;

    final result = await engine.settleOpeningLease(
      lease,
      intent: PrivateMediaLifecycleSettlementIntent.rollbackPreFrame,
    );

    expect(result, PrivateMediaLifecycleSettlementDisposition.lostRollbackRace);
    expect(lane.target.state, PrivateMediaLifecycleState.consumed);
  });

  test(
    'terminalize exception never reclassifies available as rollback and quarantines before one retry',
    () async {
      final lane = _FakeLane(
        _target(direction: PrivateMediaDirection.outgoing),
        consumeThrowsRemaining: 1,
        firstConsumeThrowLeavesAvailable: true,
      );
      final engine = PrivateMediaLifecycleEngine(
        adapter: lane,
        lifecycleLock: MediaAttachmentLifecycleLock(),
        nowMs: () => 1100,
      );
      final lease = (await engine.openOneShot('message-1'))!;

      final result = await engine.settleOpeningLease(
        lease,
        intent: PrivateMediaLifecycleSettlementIntent.terminalize,
      );

      expect(result, PrivateMediaLifecycleSettlementDisposition.terminalized);
      expect(lane.quarantineCalls, 1);
      expect(lane.consumeCalls, 2);
      expect(lane.cleanupCalls, 1);
      expect(lane.target.state, PrivateMediaLifecycleState.consumed);
      expect(lane.target.attachments, isEmpty);
    },
  );

  test(
    'uncertain terminal retry retains opening quarantine for restart reconciliation',
    () async {
      final lane = _FakeLane(
        _target(
          direction: PrivateMediaDirection.outgoing,
          mode: PrivateMediaMode.protected,
        ),
        consumeThrowsRemaining: 2,
        firstConsumeThrowLeavesAvailable: true,
      );
      final firstEngine = PrivateMediaLifecycleEngine(
        adapter: lane,
        lifecycleLock: MediaAttachmentLifecycleLock(),
        nowMs: () => 1100,
      );
      final lease = (await firstEngine.openOneShot('message-1'))!;

      final result = await firstEngine.settleOpeningLease(
        lease,
        intent: PrivateMediaLifecycleSettlementIntent.terminalize,
      );

      expect(
        result,
        PrivateMediaLifecycleSettlementDisposition.indeterminateFailClosed,
      );
      expect(lane.quarantineCalls, 1);
      expect(lane.target.state, PrivateMediaLifecycleState.opening);
      expect(lane.cleanupCalls, 0);

      final restarted = PrivateMediaLifecycleEngine(
        adapter: lane,
        lifecycleLock: MediaAttachmentLifecycleLock(),
        nowMs: () => 1200,
      );
      await restarted.reconcileLocalLifecycle();

      expect(lane.target.state, PrivateMediaLifecycleState.consumed);
      expect(lane.cleanupCalls, 1);
      expect(lane.target.attachments, isEmpty);
    },
  );

  test(
    'failed quarantine CAS never claims a changed attachment identity',
    () async {
      final lane = _FakeLane(
        _target(direction: PrivateMediaDirection.outgoing),
        consumeThrowsRemaining: 1,
        firstConsumeThrowLeavesAvailable: true,
        quarantineLosesToChangedIdentity: true,
      );
      final engine = PrivateMediaLifecycleEngine(
        adapter: lane,
        lifecycleLock: MediaAttachmentLifecycleLock(),
        nowMs: () => 1100,
      );
      final lease = (await engine.openOneShot('message-1'))!;

      final result = await engine.settleOpeningLease(
        lease,
        intent: PrivateMediaLifecycleSettlementIntent.terminalize,
      );

      expect(
        result,
        PrivateMediaLifecycleSettlementDisposition.indeterminateFailClosed,
      );
      expect(lane.quarantineCalls, 1);
      expect(lane.consumeCalls, 1);
      expect(lane.target.attachments.single.localPath, contains('replaced'));
    },
  );
}
