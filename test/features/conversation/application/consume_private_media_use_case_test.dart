import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLane implements PrivateMediaLifecycleLaneAdapter {
  _FakeLane(this.target);

  PrivateMediaLifecycleTarget target;
  int cleanupCalls = 0;
  PrivateMediaLifecycleState? stateObservedAtCleanup;

  @override
  Future<PrivateMediaLifecycleTarget?> loadTarget(String messageId) async =>
      target.messageId == messageId ? target : null;

  @override
  Future<bool> claimOpening(String messageId, {required int nowMs}) async {
    if (target.mode != PrivateMediaMode.viewOnce ||
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
  Future<bool> markViewing(String messageId, {required int nowMs}) async {
    if (target.hidden ||
        target.terminalAtMs != null ||
        target.mode != PrivateMediaMode.viewOnce ||
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
  Future<bool> rollbackOpening(String messageId) async {
    if (target.hidden ||
        target.terminalAtMs != null ||
        target.mode != PrivateMediaMode.viewOnce ||
        target.state != PrivateMediaLifecycleState.opening ||
        target.revealedAtMs != null) {
      return false;
    }
    target = target.copyWith(state: PrivateMediaLifecycleState.available);
    return true;
  }

  @override
  Future<bool> consume(String messageId, {required int nowMs}) async {
    if (target.hidden ||
        target.terminalAtMs != null ||
        target.mode != PrivateMediaMode.viewOnce ||
        (target.state != PrivateMediaLifecycleState.opening &&
            target.state != PrivateMediaLifecycleState.viewing)) {
      return false;
    }
    target = target.copyWith(
      state: PrivateMediaLifecycleState.consumed,
      terminalAtMs: nowMs,
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
  bool isDownloadComplete = true,
  bool isIntegrityEligible = true,
}) {
  return PrivateMediaLifecycleTarget(
    messageId: 'message-1',
    scopeId: 'contact-1',
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
}
