import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_viewer_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_private_media_viewer.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';
import 'package:flutter_test/flutter_test.dart';

class _MutableContinuityGuard implements DirectPrivateMediaContinuityGuard {
  _MutableContinuityGuard([
    this.state = DirectPrivateMediaContinuityState.valid,
  ]);

  @override
  DirectPrivateMediaContinuityState state;
}

class _Lane implements PrivateMediaLifecycleLaneAdapter {
  _Lane(this.target, {this.beforeLoadTarget, this.throwCleanup = false});

  PrivateMediaLifecycleTarget target;
  final void Function(_Lane lane, int loadCount)? beforeLoadTarget;
  final bool throwCleanup;
  int loadCount = 0;
  int claimCount = 0;
  int markCount = 0;
  int rollbackCount = 0;
  int consumeCount = 0;
  int cleanupCount = 0;

  @override
  Future<PrivateMediaLifecycleTarget?> loadTarget(String messageId) async {
    loadCount++;
    beforeLoadTarget?.call(this, loadCount);
    return target.messageId == messageId ? target : null;
  }

  @override
  Future<bool> claimOpening(
    PrivateMediaOpeningLeaseIdentity identity, {
    required int nowMs,
  }) async {
    if (target.state != PrivateMediaLifecycleState.available ||
        !((target.direction == PrivateMediaDirection.incoming &&
                target.mode == PrivateMediaMode.viewOnce) ||
            (target.direction == PrivateMediaDirection.outgoing &&
                (target.mode == PrivateMediaMode.protected ||
                    target.mode == PrivateMediaMode.viewOnce))) ||
        target.hidden) {
      return false;
    }
    claimCount++;
    target = target.copyWith(state: PrivateMediaLifecycleState.opening);
    return true;
  }

  @override
  Future<bool> markViewing(
    PrivateMediaOpeningLeaseIdentity identity, {
    required int nowMs,
  }) async {
    if (target.state != PrivateMediaLifecycleState.opening || target.hidden) {
      return false;
    }
    markCount++;
    target = target.copyWith(
      state: PrivateMediaLifecycleState.viewing,
      revealedAtMs: nowMs,
    );
    return true;
  }

  @override
  Future<bool> rollbackOpening(
    PrivateMediaOpeningLeaseIdentity identity,
  ) async {
    if (target.state != PrivateMediaLifecycleState.opening || target.hidden) {
      return false;
    }
    rollbackCount++;
    target = target.copyWith(state: PrivateMediaLifecycleState.available);
    return true;
  }

  @override
  Future<bool> consume(String messageId, {required int nowMs}) async {
    final qualified =
        (target.direction == PrivateMediaDirection.incoming &&
            target.mode == PrivateMediaMode.viewOnce) ||
        (target.direction == PrivateMediaDirection.outgoing &&
            (target.mode == PrivateMediaMode.protected ||
                target.mode == PrivateMediaMode.viewOnce));
    if (!qualified || target.state.isTerminal) {
      return false;
    }
    consumeCount++;
    target = target.copyWith(
      state: PrivateMediaLifecycleState.consumed,
      terminalAtMs: nowMs,
    );
    return true;
  }

  @override
  Future<bool> consumeOpening(
    PrivateMediaOpeningLeaseIdentity identity, {
    required int nowMs,
  }) => consume(identity.messageId, nowMs: nowMs);

  @override
  Future<bool> advanceClock(String messageId, {required int nowMs}) async {
    final highWater = target.clockHighWaterMs ?? 0;
    final effectiveNow = nowMs > highWater ? nowMs : highWater;
    final expired =
        target.expiresAtMs != null && effectiveNow >= target.expiresAtMs!;
    target = target.copyWith(
      state: expired ? PrivateMediaLifecycleState.expired : target.state,
      terminalAtMs: expired ? effectiveNow : target.terminalAtMs,
      clockHighWaterMs: effectiveNow,
    );
    return true;
  }

  @override
  Future<bool> failClosedCorruptState(
    String messageId, {
    required int nowMs,
  }) async => false;

  @override
  Future<List<PrivateMediaLifecycleTarget>> loadActiveDisappearing({
    int limit = 100,
  }) async => [target];

  @override
  Future<List<PrivateMediaLifecycleTarget>> loadRecoveryCandidates({
    int limit = 100,
  }) async => [target];

  @override
  Future<bool> rotateRecoveryCandidate(
    String messageId, {
    required int nowMs,
  }) async => true;

  @override
  Future<int?> loadNextExpiryAtMs() async => target.expiresAtMs;

  @override
  Future<void> cleanupTerminalWithinLock(
    PrivateMediaLifecycleTarget current,
  ) async {
    cleanupCount++;
    if (throwCleanup) throw StateError('cleanup failed');
    target = target.copyWith(attachments: const []);
  }
}

ConversationMessage _parent({
  PrivateMediaMode mode = PrivateMediaMode.viewOnce,
  PrivateMediaLifecycleState state = PrivateMediaLifecycleState.available,
  int? expiresAtMs,
  PrivateMediaDirection direction = PrivateMediaDirection.incoming,
}) {
  final policy = switch (mode) {
    PrivateMediaMode.protected => const PrivateMediaPolicy.protected(),
    PrivateMediaMode.viewOnce => const PrivateMediaPolicy.viewOnce(),
    PrivateMediaMode.disappearing => PrivateMediaPolicy.disappearing(3600),
    PrivateMediaMode.unsupported => const PrivateMediaPolicy.unsupported(
      sourceVersion: 99,
    ),
    PrivateMediaMode.ordinary => const PrivateMediaPolicy.ordinary(),
  };
  return ConversationMessage(
    id: 'message-1',
    contactPeerId: 'contact-1',
    senderPeerId: 'contact-1',
    text: 'SECRET caption and file name',
    timestamp: '2026-07-11T10:00:00.000Z',
    status: 'delivered',
    isIncoming: direction == PrivateMediaDirection.incoming,
    createdAt: '2026-07-11T10:00:00.000Z',
    privateMediaPolicy: policy,
    privateMediaState: state,
    privateMediaReceivedAtMs: mode == PrivateMediaMode.ordinary ? null : 100,
    privateMediaExpiresAtMs: expiresAtMs,
    privateMediaTerminalAtMs: state.isTerminal ? 900 : null,
    privateMediaClockHighWaterMs: mode == PrivateMediaMode.ordinary
        ? null
        : 100,
  );
}

MediaAttachment _attachment(
  String path, {
  String id = 'attachment-1',
  String mediaType = 'image',
  String? mime,
  int? size,
  String downloadStatus = 'done',
  int? downloadRetryCount,
}) => MediaAttachment(
  id: id,
  messageId: 'message-1',
  mime: mime ?? (mediaType == 'video' ? 'video/SECRET' : 'image/SECRET'),
  size: size ?? (File(path).existsSync() ? File(path).lengthSync() : 99),
  mediaType: mediaType,
  localPath: path,
  downloadStatus: downloadStatus,
  downloadRetryCount: downloadRetryCount,
  createdAt: '2026-07-11T10:00:00.000Z',
  encryptionKeyBase64: 'SECRET-key',
  encryptionNonce: 'SECRET-nonce',
  ownerLane: MediaOwnerLane.direct,
);

PrivateMediaLifecycleTarget _target(
  String path, {
  PrivateMediaMode mode = PrivateMediaMode.viewOnce,
  PrivateMediaLifecycleState state = PrivateMediaLifecycleState.available,
  int? expiresAtMs,
  String attachmentId = 'attachment-1',
  String mime = 'image/SECRET',
  PrivateMediaDirection direction = PrivateMediaDirection.incoming,
  bool openablePath = true,
}) => PrivateMediaLifecycleTarget(
  messageId: 'message-1',
  scopeId: 'contact-1',
  direction: direction,
  mode: mode,
  state: state,
  expiresAtMs: expiresAtMs,
  clockHighWaterMs: 100,
  attachments: [
    PrivateMediaLifecycleAttachment(
      id: attachmentId,
      messageId: 'message-1',
      storedLocalPath: path,
      localPath: openablePath ? path : null,
      mime: mime,
      size: File(path).existsSync() ? File(path).lengthSync() : 99,
      isDownloadComplete: true,
      isIntegrityEligible: true,
    ),
  ],
);

({
  DirectPrivateMediaViewerController controller,
  _Lane lane,
  List<String> nativeCalls,
  StreamController<Object?> nativeEvents,
  List<int> currentRowLoads,
})
_fixture({
  PrivateMediaMode mode = PrivateMediaMode.viewOnce,
  PrivateMediaLifecycleState state = PrivateMediaLifecycleState.available,
  PrivateMediaDirection direction = PrivateMediaDirection.incoming,
  int nowMs = 200,
  int? expiresAtMs,
  Future<void> Function(_Lane lane)? onNativeEnter,
  Future<void> Function()? onNativeExit,
  Completer<Object?>? nativeEnterGate,
  String? path,
  int Function()? nowMsProvider,
  int? throwCurrentRowsOnLoad,
  MediaAttachment Function(int loadCount, _Lane lane, String path)?
  currentAttachmentForLoad,
  void Function(_Lane lane, int loadCount)? beforeLifecycleLoad,
  bool throwCleanup = false,
  String mediaType = 'image',
  String? mime,
  bool openablePath = true,
  String downloadStatus = 'done',
  int? downloadRetryCount,
}) {
  final effectivePath =
      path ??
      '${Directory.systemTemp.path}/private-viewer-${DateTime.now().microsecondsSinceEpoch}.png';
  if (!File(effectivePath).existsSync()) {
    File(effectivePath).writeAsBytesSync(const <int>[1, 2, 3]);
    addTearDown(() {
      try {
        File(effectivePath).deleteSync();
      } catch (_) {}
    });
  }
  final lane = _Lane(
    _target(
      effectivePath,
      mode: mode,
      state: state,
      expiresAtMs: expiresAtMs,
      direction: direction,
      mime: mime ?? (mediaType == 'video' ? 'video/SECRET' : 'image/SECRET'),
      openablePath: openablePath,
    ),
    beforeLoadTarget: beforeLifecycleLoad,
    throwCleanup: throwCleanup,
  );
  final nativeCalls = <String>[];
  final events = StreamController<Object?>();
  final currentRowLoads = <int>[];
  final protection = PrivateMediaProtectionCoordinator(
    invokeMethod: (method, arguments) async {
      nativeCalls.add(method);
      if (method == 'enter') {
        await onNativeEnter?.call(lane);
        if (nativeEnterGate != null) return nativeEnterGate.future;
      } else if (method == 'exit') {
        await onNativeExit?.call();
      }
      return <String, Object?>{
        'ok': true,
        'protectionActive': method == 'enter',
      };
    },
    nativeEvents: events.stream,
  );
  final engine = PrivateMediaLifecycleEngine(
    adapter: lane,
    lifecycleLock: MediaAttachmentLifecycleLock(),
    nowMs: nowMsProvider ?? () => nowMs,
  );
  final controller = DirectPrivateMediaViewerController(
    loadCurrentRows: (_) async {
      final loadCount = currentRowLoads.length + 1;
      currentRowLoads.add(loadCount);
      if (throwCurrentRowsOnLoad == loadCount) {
        throw StateError('current row reload failed');
      }
      return DirectPrivateMediaCurrentRows(
        parent: _parent(
          mode: mode,
          state: lane.target.state,
          expiresAtMs: expiresAtMs,
          direction: direction,
        ),
        attachment: lane.target.attachments.isEmpty
            ? null
            : currentAttachmentForLoad?.call(loadCount, lane, effectivePath) ??
                  _attachment(
                    effectivePath,
                    mediaType: mediaType,
                    mime: mime,
                    downloadStatus: downloadStatus,
                    downloadRetryCount: downloadRetryCount,
                  ),
      );
    },
    lifecycleEngine: engine,
    protectionCoordinator: protection,
  );
  addTearDown(() async {
    await controller.dispose();
    await events.close();
  });
  return (
    controller: controller,
    lane: lane,
    nativeCalls: nativeCalls,
    nativeEvents: events,
    currentRowLoads: currentRowLoads,
  );
}

void main() {
  const identity = DirectPrivateMediaViewerIdentity(
    messageId: 'message-1',
    attachmentId: 'attachment-1',
  );

  test(
    'typed prepare and settle distinguish success from lifecycle disposition',
    () async {
      final guard = _MutableContinuityGuard();
      final protected = _fixture(mode: PrivateMediaMode.protected);
      final prepared = await protected.controller.prepareResult(
        identity,
        guard,
      );
      expect(prepared.isGranted, isTrue);
      expect(prepared.failureReason, isNull);
      final grant = prepared.grant!;
      expect(await protected.controller.markFirstFrame(grant), isTrue);

      final first = await protected.controller.settle(
        grant,
        DirectPrivateMediaExitReason.close,
        releaseProtection: false,
      );
      expect(first.disposition, DirectPrivateMediaSettleDisposition.noLease);
      expect(first.exitReason, DirectPrivateMediaExitReason.close);
      expect(first.firstFrameRecorded, isTrue);
      expect(protected.nativeCalls, <String>['enter']);

      final repeated = await protected.controller.settle(
        grant,
        DirectPrivateMediaExitReason.dispose,
      );
      expect(identical(repeated, first), isTrue);
      expect(protected.nativeCalls, <String>['enter', 'exit']);
      await protected.controller.releaseProtectionOwner(grant);
      expect(protected.nativeCalls, <String>['enter', 'exit']);

      final displayed = DirectPrivateMediaOpenResult.displayed(first);
      expect(displayed.wasDisplayed, isTrue);
      expect(displayed.settleResult, first);
      expect(displayed.canRetry, isFalse);
    },
  );

  test(
    'retry qualification re-reads status budget path and authority',
    () async {
      const rolledBack = DirectPrivateMediaSettleResult(
        disposition: DirectPrivateMediaSettleDisposition.rolledBackAvailable,
        exitReason: DirectPrivateMediaExitReason.routePushFailure,
        firstFrameRecorded: false,
      );
      const noLease = DirectPrivateMediaSettleResult(
        disposition: DirectPrivateMediaSettleDisposition.noLease,
        exitReason: DirectPrivateMediaExitReason.protectionEnterFailure,
        firstFrameRecorded: false,
      );

      final transient = _fixture(
        downloadStatus: 'failed',
        downloadRetryCount: kMaxDownloadRetries - 1,
      );
      expect(
        await transient.controller.canRetryAfterOpenFailure(
          identity,
          DirectPrivateMediaOpenFailureReason.authorityLost,
        ),
        isTrue,
      );

      final exhausted = _fixture(
        downloadStatus: 'failed',
        downloadRetryCount: kMaxDownloadRetries,
      );
      expect(
        await exhausted.controller.canRetryAfterOpenFailure(
          identity,
          DirectPrivateMediaOpenFailureReason.preFrameFailure,
          settleResult: rolledBack,
        ),
        isFalse,
      );

      for (final terminalStatus in <String>[
        'download_failed',
        'integrity_failed',
      ]) {
        final fixture = _fixture(downloadStatus: terminalStatus);
        expect(
          await fixture.controller.canRetryAfterPrepareFailure(
            identity,
            DirectPrivateMediaPrepareFailureReason.revalidationFailed,
            settleResult: rolledBack,
          ),
          isFalse,
          reason: terminalStatus,
        );
      }

      final exactDone = _fixture();
      expect(
        await exactDone.controller.canRetryAfterOpenFailure(
          identity,
          DirectPrivateMediaOpenFailureReason.routePushFailure,
          settleResult: rolledBack,
        ),
        isTrue,
      );
      final protected = _fixture(mode: PrivateMediaMode.protected);
      expect(
        await protected.controller.canRetryAfterPrepareFailure(
          identity,
          DirectPrivateMediaPrepareFailureReason.protectionEnterFailed,
          settleResult: noLease,
        ),
        isTrue,
      );

      for (final disposition in <DirectPrivateMediaSettleDisposition>[
        DirectPrivateMediaSettleDisposition.terminalized,
        DirectPrivateMediaSettleDisposition.lostRollbackRace,
        DirectPrivateMediaSettleDisposition.indeterminateFailClosed,
      ]) {
        final result = DirectPrivateMediaSettleResult(
          disposition: disposition,
          exitReason: DirectPrivateMediaExitReason.routePushFailure,
          firstFrameRecorded: false,
        );
        expect(
          await exactDone.controller.canRetryAfterOpenFailure(
            identity,
            DirectPrivateMediaOpenFailureReason.routePushFailure,
            settleResult: result,
          ),
          isFalse,
          reason: disposition.name,
        );
      }
      expect(
        await exactDone.controller.canRetryAfterOpenFailure(
          identity,
          DirectPrivateMediaOpenFailureReason.lifecycleInterrupted,
          settleResult: rolledBack,
        ),
        isFalse,
      );

      final missingPath = _fixture(openablePath: false);
      expect(
        await missingPath.controller.canRetryAfterOpenFailure(
          identity,
          DirectPrivateMediaOpenFailureReason.preFrameFailure,
          settleResult: rolledBack,
        ),
        isFalse,
      );
      final mismatched = _fixture(
        currentAttachmentForLoad: (loadCount, lane, path) =>
            _attachment(path, id: 'replacement-attachment'),
      );
      expect(
        await mismatched.controller.canRetryAfterOpenFailure(
          identity,
          DirectPrivateMediaOpenFailureReason.preFrameFailure,
          settleResult: rolledBack,
        ),
        isFalse,
      );
      final senderExpiry = _fixture(
        direction: PrivateMediaDirection.outgoing,
        mode: PrivateMediaMode.disappearing,
        downloadStatus: 'failed',
        downloadRetryCount: 0,
      );
      expect(
        await senderExpiry.controller.canRetryAfterPrepareFailure(
          identity,
          DirectPrivateMediaPrepareFailureReason.revalidationFailed,
        ),
        isFalse,
      );
    },
  );

  test(
    'prepare continuity rolls route-only races back and app lifecycle races fail closed',
    () async {
      for (final scenario
          in <
            ({
              DirectPrivateMediaContinuityState state,
              DirectPrivateMediaPrepareFailureReason reason,
              DirectPrivateMediaSettleDisposition disposition,
            })
          >[
            (
              state: DirectPrivateMediaContinuityState.routeInvalidated,
              reason:
                  DirectPrivateMediaPrepareFailureReason.routeContinuityLost,
              disposition:
                  DirectPrivateMediaSettleDisposition.rolledBackAvailable,
            ),
            (
              state: DirectPrivateMediaContinuityState.appLifecycleInvalidated,
              reason: DirectPrivateMediaPrepareFailureReason
                  .appLifecycleContinuityLost,
              disposition: DirectPrivateMediaSettleDisposition.terminalized,
            ),
          ]) {
        final gate = Completer<Object?>();
        final guard = _MutableContinuityGuard();
        final fixture = _fixture(nativeEnterGate: gate);
        final preparing = fixture.controller.prepareResult(identity, guard);
        for (
          var spin = 0;
          spin < 20 && !fixture.nativeCalls.contains('enter');
          spin++
        ) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(fixture.lane.claimCount, 1);
        guard.state = scenario.state;
        gate.complete(<String, Object?>{'ok': true, 'protectionActive': true});

        final result = await preparing;
        expect(result.isGranted, isFalse);
        expect(result.failureReason, scenario.reason);
        expect(result.settleResult?.disposition, scenario.disposition);
        expect(
          fixture.lane.target.state,
          scenario.disposition ==
                  DirectPrivateMediaSettleDisposition.rolledBackAvailable
              ? PrivateMediaLifecycleState.available
              : PrivateMediaLifecycleState.consumed,
        );
        expect(fixture.nativeCalls, <String>['enter', 'exit']);
      }

      final invalidBeforeAcquire = _fixture();
      final denied = await invalidBeforeAcquire.controller.prepareResult(
        identity,
        _MutableContinuityGuard(
          DirectPrivateMediaContinuityState.appLifecycleInvalidated,
        ),
      );
      expect(denied.isGranted, isFalse);
      expect(invalidBeforeAcquire.lane.claimCount, 0);
      expect(invalidBeforeAcquire.nativeCalls, isEmpty);
    },
  );

  test(
    'direction mode and GIF qualification are exact before path publication',
    () async {
      for (final mode in <PrivateMediaMode>[
        PrivateMediaMode.protected,
        PrivateMediaMode.viewOnce,
      ]) {
        final outgoing = _fixture(
          direction: PrivateMediaDirection.outgoing,
          mode: mode,
        );
        final prepared = await outgoing.controller.prepareResult(
          identity,
          _MutableContinuityGuard(),
        );
        expect(prepared.isGranted, isTrue, reason: mode.name);
        expect(outgoing.lane.claimCount, 1, reason: mode.name);
        expect(
          await outgoing.controller.markFirstFrame(prepared.grant!),
          isTrue,
        );
        final settled = await outgoing.controller.settle(
          prepared.grant!,
          DirectPrivateMediaExitReason.close,
        );
        expect(
          settled.disposition,
          DirectPrivateMediaSettleDisposition.terminalized,
        );
      }

      for (final direction in PrivateMediaDirection.values) {
        final gif = _fixture(
          direction: direction,
          mode: direction == PrivateMediaDirection.incoming
              ? PrivateMediaMode.protected
              : PrivateMediaMode.viewOnce,
          mediaType: 'gif',
          mime: 'image/gif',
        );
        final result = await gif.controller.prepareResult(
          identity,
          _MutableContinuityGuard(),
        );
        expect(result.grant?.kind, MediaViewerKind.gif, reason: direction.name);
        await gif.controller.settle(
          result.grant!,
          DirectPrivateMediaExitReason.close,
        );
      }

      final mismatchedGif = _fixture(mediaType: 'gif', mime: 'image/png');
      final gifFailure = await mismatchedGif.controller.prepareResult(
        identity,
        _MutableContinuityGuard(),
      );
      expect(gifFailure.isGranted, isFalse);
      expect(
        gifFailure.failureReason,
        DirectPrivateMediaPrepareFailureReason.unsupportedMediaKind,
      );

      final danglingSender = _fixture(
        direction: PrivateMediaDirection.outgoing,
        mode: PrivateMediaMode.protected,
        openablePath: false,
      );
      final missing = await danglingSender.controller.prepareResult(
        identity,
        _MutableContinuityGuard(),
      );
      expect(missing.isGranted, isFalse);
      expect(
        missing.failureReason,
        DirectPrivateMediaPrepareFailureReason.localAuthorityMissing,
      );
      expect(danglingSender.lane.claimCount, 0);
      expect(danglingSender.nativeCalls, isEmpty);
    },
  );

  test(
    'pre-frame route and decode exits roll back while background fails closed',
    () async {
      for (final reason in <DirectPrivateMediaExitReason>[
        DirectPrivateMediaExitReason.routePushFailure,
        DirectPrivateMediaExitReason.preFrameDecodeFailure,
        DirectPrivateMediaExitReason.routeContinuityLoss,
        DirectPrivateMediaExitReason.protectionEnterFailure,
        DirectPrivateMediaExitReason.revalidationFailure,
      ]) {
        final fixture = _fixture();
        final prepared = await fixture.controller.prepareResult(
          identity,
          _MutableContinuityGuard(),
        );
        final settled = await fixture.controller.settle(
          prepared.grant!,
          reason,
        );
        expect(
          settled.disposition,
          DirectPrivateMediaSettleDisposition.rolledBackAvailable,
          reason: reason.name,
        );
      }

      for (final reason in <DirectPrivateMediaExitReason>[
        DirectPrivateMediaExitReason.background,
        DirectPrivateMediaExitReason.capture,
        DirectPrivateMediaExitReason.dispose,
        DirectPrivateMediaExitReason.appLifecycleLoss,
      ]) {
        final fixture = _fixture();
        final prepared = await fixture.controller.prepareResult(
          identity,
          _MutableContinuityGuard(),
        );
        final settled = await fixture.controller.settle(
          prepared.grant!,
          reason,
        );
        expect(
          settled.disposition,
          DirectPrivateMediaSettleDisposition.terminalized,
          reason: reason.name,
        );
      }
    },
  );

  test(
    'view once protects before bytes records one first frame and terminalizes on every non-decode exit',
    () async {
      final nativeEnterGate = Completer<Object?>();
      final fixture = _fixture(nativeEnterGate: nativeEnterGate);
      var preparationCompleted = false;
      final preparing = fixture.controller
          .prepare(identity)
          .whenComplete(() => preparationCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(fixture.nativeCalls, ['enter']);
      expect(
        preparationCompleted,
        isFalse,
        reason: 'no byte-bearing grant exists before native enter succeeds',
      );
      nativeEnterGate.complete(<String, Object?>{
        'ok': true,
        'protectionActive': true,
      });
      final grant = await preparing;
      expect(grant, isNotNull);
      expect(fixture.lane.claimCount, 1);
      expect(fixture.nativeCalls, ['enter']);
      expect(await fixture.controller.markFirstFrame(grant!), isTrue);
      expect(await fixture.controller.markFirstFrame(grant), isFalse);
      await fixture.controller.settle(
        grant,
        DirectPrivateMediaExitReason.close,
      );
      expect(fixture.lane.consumeCount, 1);
      expect(fixture.lane.cleanupCount, 1);
      expect(fixture.nativeCalls, ['enter', 'exit']);

      final preFrameExit = _fixture();
      final preFrameGrant = (await preFrameExit.controller.prepare(identity))!;
      await preFrameExit.controller.settle(
        preFrameGrant,
        DirectPrivateMediaExitReason.close,
      );
      expect(preFrameExit.lane.rollbackCount, 0);
      expect(preFrameExit.lane.consumeCount, 1);
    },
  );

  test(
    'only proven pre-first-frame decode failure rolls view once back to available',
    () async {
      final fixture = _fixture();
      final grant = (await fixture.controller.prepare(identity))!;
      await fixture.controller.settle(
        grant,
        DirectPrivateMediaExitReason.preFrameDecodeFailure,
      );
      expect(fixture.lane.rollbackCount, 1);
      expect(fixture.lane.consumeCount, 0);
      expect(fixture.lane.target.state, PrivateMediaLifecycleState.available);
    },
  );

  test(
    'protected and disappearing private routes revalidate without consume and expiry dismisses fail closed',
    () async {
      final protected = _fixture(mode: PrivateMediaMode.protected);
      final grant = await protected.controller.prepare(identity);
      expect(grant, isNotNull);
      expect(
        await protected.controller.revalidateForLifecycleEvent(grant!),
        isTrue,
      );
      await protected.controller.settle(
        grant,
        DirectPrivateMediaExitReason.close,
      );
      expect(protected.lane.consumeCount, 0);
      expect(protected.lane.target.state, PrivateMediaLifecycleState.available);

      final expired = _fixture(
        mode: PrivateMediaMode.disappearing,
        nowMs: 1000,
        expiresAtMs: 500,
      );
      expect(await expired.controller.prepare(identity), isNull);
      expect(expired.lane.target.state, PrivateMediaLifecycleState.expired);
      expect(expired.nativeCalls, ['enter', 'exit']);
    },
  );

  testWidgets(
    'foreground disappearing route expires at its live deadline and dismisses fail closed',
    (tester) async {
      var nowMs = 200;
      final directory = Directory.systemTemp.createTempSync(
        'private_disappearing_deadline_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final image = File('${directory.path}/private.png')
        ..writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        );
      final fixture = _fixture(
        mode: PrivateMediaMode.disappearing,
        expiresAtMs: 500,
        nowMsProvider: () => nowMs,
        path: image.path,
        onNativeExit: () async {
          expect(
            find.byKey(const ValueKey('direct-private-media-viewer')),
            findsNothing,
            reason: 'native protection remains until the route is removed',
          );
        },
      );
      final grant = (await fixture.controller.prepare(identity))!;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          initialRoute: '/private',
          routes: <String, WidgetBuilder>{
            '/': (_) =>
                const SizedBox(key: ValueKey('ordinary-underlying-route')),
            '/private': (_) => DirectPrivateMediaViewer(
              grant: grant,
              controller: fixture.controller,
            ),
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 299));
      expect(grant.settled, isFalse);
      expect(fixture.lane.target.state, PrivateMediaLifecycleState.available);

      nowMs = 501;
      await tester.pump(const Duration(milliseconds: 2));
      for (var frame = 0; frame < 20 && !grant.protectionReleased; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(grant.settled, isTrue);
      expect(fixture.lane.target.state, PrivateMediaLifecycleState.expired);
      expect(fixture.nativeCalls, ['enter', 'exit']);
      expect(
        find.byKey(const ValueKey('direct-private-media-viewer')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('ordinary-underlying-route')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'disappearing deadline re-arms after a backward clock and fails closed on reload error',
    (tester) async {
      var nowMs = 200;
      final backwardClock = _fixture(
        mode: PrivateMediaMode.disappearing,
        expiresAtMs: 500,
        nowMsProvider: () => nowMs,
      );
      final backwardGrant = (await backwardClock.controller.prepare(identity))!;
      var backwardClosures = 0;
      backwardClock.controller.armDisappearingDeadline(backwardGrant, () async {
        backwardClosures++;
        await backwardClock.controller.settle(
          backwardGrant,
          DirectPrivateMediaExitReason.expiry,
        );
      });

      nowMs = 100;
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(backwardClosures, 0);
      expect(backwardGrant.settled, isFalse);
      expect(backwardClock.nativeCalls, ['enter']);

      nowMs = 501;
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(backwardClosures, 1);
      expect(backwardGrant.settled, isTrue);
      expect(backwardClock.nativeCalls, ['enter', 'exit']);

      final reloadFailure = _fixture(
        mode: PrivateMediaMode.disappearing,
        expiresAtMs: 500,
        nowMs: 200,
        throwCurrentRowsOnLoad: 3,
      );
      final failedGrant = (await reloadFailure.controller.prepare(identity))!;
      var failureClosures = 0;
      reloadFailure.controller.armDisappearingDeadline(failedGrant, () async {
        failureClosures++;
        await reloadFailure.controller.settle(
          failedGrant,
          DirectPrivateMediaExitReason.expiry,
        );
      });
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(failureClosures, 1);
      expect(failedGrant.settled, isTrue);
      expect(reloadFailure.nativeCalls, ['enter', 'exit']);
    },
  );

  testWidgets(
    'pre-route capture and channel failure stay sticky until the grant is covered and settled',
    (tester) async {
      final triggers = <void Function(StreamController<Object?>)>[
        (events) => events.add(<String, Object?>{'event': 'captureStarted'}),
        (events) => events.addError(StateError('native event channel failed')),
      ];
      for (var index = 0; index < triggers.length; index++) {
        final fixture = _fixture(mode: PrivateMediaMode.protected);
        final grant = (await fixture.controller.prepare(identity))!;
        final navigatorKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey('pre-route-incident-$index'),
            navigatorKey: navigatorKey,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SizedBox(key: ValueKey('ordinary-underlying-route')),
          ),
        );
        triggers[index](fixture.nativeEvents);
        await tester.pump();

        unawaited(
          navigatorKey.currentState!.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => DirectPrivateMediaViewer(
                grant: grant,
                controller: fixture.controller,
              ),
            ),
          ),
        );
        for (var frame = 0; frame < 20 && !grant.protectionReleased; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(
          grant.settled,
          isTrue,
          reason: 'a protection incident before route subscription cannot drop',
        );
        expect(fixture.nativeCalls, ['enter', 'exit']);
        expect(
          find.byKey(const ValueKey('direct-private-media-viewer')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('ordinary-underlying-route')),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets(
    'latched pre-route incident builds zero byte viewer frames before dismissal',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'private_pre_route_latch_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final image = File('${directory.path}/private.png')
        ..writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        );
      final fixture = _fixture(path: image.path);
      final grant = (await fixture.controller.prepare(identity))!;
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SizedBox(key: ValueKey('ordinary-underlying-route')),
        ),
      );

      fixture.nativeEvents.add(<String, Object?>{'event': 'captureStarted'});
      await tester.pump();
      expect(fixture.controller.latchedProtectionEvent, isNotNull);

      unawaited(
        navigatorKey.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => DirectPrivateMediaViewer(
              grant: grant,
              controller: fixture.controller,
            ),
          ),
        ),
      );
      var byteViewerFramesBeforeDismissal = 0;
      for (var frame = 0; frame < 20 && !grant.protectionReleased; frame++) {
        tester.binding.addPostFrameCallback((_) {
          if (find.byType(FullScreenTypedMediaViewer).evaluate().isNotEmpty) {
            byteViewerFramesBeforeDismissal++;
          }
        });
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(grant.protectionReleased, isTrue);
      expect(
        byteViewerFramesBeforeDismissal,
        0,
        reason:
            'a pre-route incident must prevent every byte viewer build/frame '
            'before dismissal',
      );
      expect(fixture.lane.markCount, 0);
      expect(fixture.nativeCalls, ['enter', 'exit']);
      expect(
        find.byKey(const ValueKey('ordinary-underlying-route')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'capture removes the exact route and overlays before release despite persistence failures',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'private_route_completion_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final image = File('${directory.path}/private.png')
        ..writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        );

      for (var scenario = 0; scenario < 3; scenario++) {
        final fixture = _fixture(
          mode: scenario == 1
              ? PrivateMediaMode.viewOnce
              : PrivateMediaMode.protected,
          path: image.path,
          throwCurrentRowsOnLoad: scenario == 0 ? 3 : null,
          throwCleanup: scenario == 1,
          onNativeExit: () async {
            expect(
              find.byKey(const ValueKey('direct-private-media-viewer')),
              findsNothing,
              reason: 'the exact private route is removed before native exit',
            );
            expect(
              find.byKey(const ValueKey('private-info-overlay')),
              findsNothing,
              reason: 'a route above private media is dismissed first',
            );
          },
        );
        final grant = (await fixture.controller.prepare(identity))!;
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey('private-route-app-$scenario'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            initialRoute: '/private',
            routes: <String, WidgetBuilder>{
              '/': (_) =>
                  const SizedBox(key: ValueKey('ordinary-underlying-route')),
              '/private': (_) => DirectPrivateMediaViewer(
                grant: grant,
                controller: fixture.controller,
              ),
            },
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        Future<void>? dialogClosed;
        if (scenario == 2) {
          final privateContext = tester.element(
            find.byKey(const ValueKey('direct-private-media-viewer')),
          );
          dialogClosed = showDialog<void>(
            context: privateContext,
            builder: (_) => const AlertDialog(
              key: ValueKey('private-info-overlay'),
              content: Text('Private media'),
            ),
          );
          await tester.pumpAndSettle();
        }

        fixture.nativeEvents.add(<String, Object?>{'event': 'captureStarted'});
        for (var frame = 0; frame < 30 && !grant.protectionReleased; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        if (dialogClosed != null) await dialogClosed;

        expect(
          grant.protectionReleased,
          isTrue,
          reason:
              'scenario=$scenario settled=${grant.settled} calls=${fixture.nativeCalls}',
        );
        expect(fixture.nativeCalls, ['enter', 'exit']);
        expect(
          find.byKey(const ValueKey('direct-private-media-viewer')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('ordinary-underlying-route')),
          findsOneWidget,
        );
      }
    },
  );

  test(
    'post-enter current path mime kind and size must exactly match lifecycle authority',
    () async {
      final mismatches = <MediaAttachment Function(int, _Lane, String)>[
        (load, lane, path) => _attachment(load == 1 ? path : '$path.replaced'),
        (load, lane, path) =>
            _attachment(path, mime: load == 1 ? 'image/SECRET' : 'image/other'),
        (load, lane, path) => _attachment(
          path,
          mediaType: load == 1 ? 'image' : 'video',
          mime: 'image/SECRET',
        ),
        (load, lane, path) => _attachment(
          path,
          size: File(path).lengthSync() + (load == 1 ? 0 : 1),
        ),
      ];

      for (final mismatch in mismatches) {
        final fixture = _fixture(
          mode: PrivateMediaMode.protected,
          currentAttachmentForLoad: mismatch,
        );
        expect(await fixture.controller.prepare(identity), isNull);
        expect(fixture.nativeCalls, ['enter', 'exit']);
      }
    },
  );

  test(
    'pre-frame lease mismatch and thrown post-enter reload roll back and release protection',
    () async {
      final wrongLease = _fixture(
        beforeLifecycleLoad: (lane, loadCount) {
          if (loadCount != 2) return;
          final current = lane.target.attachments.single;
          lane.target = lane.target.copyWith(
            attachments: <PrivateMediaLifecycleAttachment>[
              PrivateMediaLifecycleAttachment(
                id: 'other-attachment',
                messageId: current.messageId,
                storedLocalPath: current.storedLocalPath,
                localPath: current.localPath,
                mime: current.mime,
                size: current.size,
                isDownloadComplete: true,
                isIntegrityEligible: true,
              ),
            ],
          );
        },
      );
      expect(await wrongLease.controller.prepare(identity), isNull);
      expect(wrongLease.lane.rollbackCount, 1);
      expect(wrongLease.lane.consumeCount, 0);
      expect(wrongLease.lane.cleanupCount, 0);
      expect(
        wrongLease.lane.target.state,
        PrivateMediaLifecycleState.available,
      );

      final reloadThrow = _fixture(throwCurrentRowsOnLoad: 2);
      expect(await reloadThrow.controller.prepare(identity), isNull);
      expect(reloadThrow.currentRowLoads, [1, 2]);
      expect(reloadThrow.lane.rollbackCount, 1);
      expect(reloadThrow.lane.consumeCount, 0);
      expect(reloadThrow.lane.cleanupCount, 0);
      expect(reloadThrow.nativeCalls, ['enter', 'exit']);
    },
  );

  testWidgets(
    'private route states copy safe actions metadata and typed PiP remain privacy minimized',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('private_viewer_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final image = File('${directory.path}/SECRET-private.png');
      image.writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
      final fixture = _fixture(path: image.path);
      final grant = (await fixture.controller.prepare(identity))!;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DirectPrivateMediaViewer(
            grant: grant,
            controller: fixture.controller,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(const ValueKey('direct-private-media-viewer')),
        findsOneWidget,
      );
      expect(find.textContaining('SECRET'), findsNothing);
      expect(find.byKey(const ValueKey('media_meta_mime')), findsNothing);
      expect(find.byKey(const ValueKey('media_meta_size')), findsNothing);
      expect(find.byKey(const ValueKey('media_action_save')), findsNothing);
      expect(grant.canEnterPictureInPicture, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  test(
    'ordinary direct and group viewers remain unchanged when private callbacks are absent',
    () {
      final source = File(
        'lib/shared/widgets/media/full_screen_typed_media_viewer.dart',
      ).readAsStringSync();
      expect(source, contains('this.onFirstRenderedFrame'));
      expect(source, contains('this.onPreFrameFailure'));
      expect(source, contains('this.privacyMinimized = false'));
    },
  );

  test(
    'post-enter authority loss builds no route and never claims safe rollback',
    () async {
      final fixture = _fixture(
        onNativeEnter: (lane) async {
          lane.target = lane.target.copyWith(hidden: true);
        },
      );
      expect(await fixture.controller.prepare(identity), isNull);
      expect(fixture.lane.rollbackCount, 0);
      expect(fixture.lane.consumeCount, 0);
      expect(fixture.lane.target.state, PrivateMediaLifecycleState.opening);
      expect(fixture.nativeCalls, ['enter', 'exit']);

      final replacedPath = _fixture(
        onNativeEnter: (lane) async {
          final attachment = lane.target.attachments.single;
          lane.target = lane.target.copyWith(
            attachments: [
              PrivateMediaLifecycleAttachment(
                id: attachment.id,
                messageId: attachment.messageId,
                storedLocalPath: '/tmp/replaced-after-enter.png',
                localPath: '/tmp/replaced-after-enter.png',
                mime: attachment.mime,
                size: attachment.size,
                isDownloadComplete: true,
                isIntegrityEligible: true,
              ),
            ],
          );
        },
      );
      expect(await replacedPath.controller.prepare(identity), isNull);
      expect(replacedPath.lane.rollbackCount, 0);
      expect(
        replacedPath.lane.consumeCount,
        1,
        reason: 'an indeterminate path-identity race is reconciled fail-closed',
      );
      expect(
        replacedPath.lane.target.state,
        PrivateMediaLifecycleState.consumed,
      );
      expect(replacedPath.lane.cleanupCount, 1);
      expect(replacedPath.lane.target.attachments, isEmpty);
      expect(replacedPath.nativeCalls, ['enter', 'exit']);
    },
  );

  testWidgets('view-once placeholder states single view', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DirectPrivateMediaOpenPlaceholder(
            onOpen: null,
            policy: PrivateMediaPolicy.viewOnce(),
            contactDisplayName: 'Layla',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('You can only view this once.'), findsOneWidget);
    expect(
      find.textContaining("doesn't allow saving or sharing"),
      findsNothing,
    );
  });

  testWidgets('private card title renders the protected media kind', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DirectPrivateMediaOpenPlaceholder(
            onOpen: null,
            policy: PrivateMediaPolicy.protected(),
            contactDisplayName: 'Layla',
          ),
        ),
      ),
    );
    await tester.pump();

    final modeLabel = find.byKey(const ValueKey('private-media-mode-label'));
    expect(modeLabel, findsOneWidget);
    expect(tester.widget<Text>(modeLabel).data, 'Protected photo');
  });

  testWidgets(
    'sender protected and view-once expose one-more-look while disappearing and missing local media do not',
    (tester) async {
      var opens = 0;
      Future<void> pump(
        PrivateMediaPolicy policy, {
        bool localMediaAvailable = true,
      }) => tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DirectPrivateMediaOutgoingPlaceholder(
              policy: policy,
              contactDisplayName: 'Layla',
              localMediaAvailable: localMediaAvailable,
              onOpen: () => opens++,
            ),
          ),
        ),
      );

      for (final policy in <PrivateMediaPolicy>[
        const PrivateMediaPolicy.protected(),
        const PrivateMediaPolicy.viewOnce(),
      ]) {
        await pump(policy);
        expect(
          find.byKey(const ValueKey('private-media-open')),
          findsOneWidget,
        );
        expect(
          find.textContaining('You can reopen it once here after sending.'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('private-media-open')));
        expect(opens, greaterThan(0));
      }

      await pump(PrivateMediaPolicy.disappearing(3600));
      expect(find.byKey(const ValueKey('private-media-open')), findsNothing);

      await pump(
        const PrivateMediaPolicy.protected(),
        localMediaAvailable: false,
      );
      expect(find.byKey(const ValueKey('private-media-open')), findsNothing);
      expect(
        find.text("Your sent media can't be reopened on this phone."),
        findsOneWidget,
      );
      expect(find.textContaining('Choose'), findsNothing);
    },
  );

  testWidgets('typed open failure copy claims safety only for exact rollback', (
    tester,
  ) async {
    const rolledBack = DirectPrivateMediaSettleResult(
      disposition: DirectPrivateMediaSettleDisposition.rolledBackAvailable,
      exitReason: DirectPrivateMediaExitReason.routePushFailure,
      firstFrameRecorded: false,
    );
    const terminalized = DirectPrivateMediaSettleResult(
      disposition: DirectPrivateMediaSettleDisposition.terminalized,
      exitReason: DirectPrivateMediaExitReason.background,
      firstFrameRecorded: false,
    );
    var retries = 0;
    Future<void> pump({
      required PrivateMediaDirection direction,
      required DirectPrivateMediaSettleResult settleResult,
      bool canRetry = true,
      bool localMediaMissing = false,
      PrivateMediaAttachmentKind kind = PrivateMediaAttachmentKind.image,
    }) => tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DirectPrivateMediaOpenFailurePlaceholder(
            direction: direction,
            kind: kind,
            settleResult: settleResult,
            canRetry: canRetry,
            localMediaMissing: localMediaMissing,
            onRetry: () => retries++,
          ),
        ),
      ),
    );

    await pump(
      direction: PrivateMediaDirection.incoming,
      settleResult: rolledBack,
    );
    expect(find.text('Your one view is still available.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('private-media-try-again')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('private-media-try-again')));
    expect(retries, 1);

    await pump(
      direction: PrivateMediaDirection.outgoing,
      settleResult: rolledBack,
    );
    expect(find.text('Your one more look is still available.'), findsOneWidget);

    await pump(
      direction: PrivateMediaDirection.outgoing,
      settleResult: terminalized,
      canRetry: false,
      kind: PrivateMediaAttachmentKind.video,
    );
    expect(find.text("Couldn't open this video"), findsOneWidget);
    expect(find.textContaining('still available'), findsNothing);
    expect(find.byKey(const ValueKey('private-media-try-again')), findsNothing);

    await pump(
      direction: PrivateMediaDirection.outgoing,
      settleResult: rolledBack,
      localMediaMissing: true,
    );
    expect(
      find.text("Your sent media can't be reopened on this phone."),
      findsOneWidget,
    );
    expect(find.textContaining('still available'), findsNothing);
    expect(find.byKey(const ValueKey('private-media-try-again')), findsNothing);
  });

  testWidgets('sender-consumed terminal is generic after attachment cleanup', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DirectPrivateMediaTerminalPlaceholder(
            state: PrivateMediaLifecycleState.consumed,
            direction: PrivateMediaDirection.outgoing,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Private media'), findsOneWidget);
    expect(find.text("You've used your one more look"), findsOneWidget);
    expect(find.textContaining('photo'), findsNothing);
    expect(find.textContaining('video'), findsNothing);
    expect(find.textContaining('GIF'), findsNothing);
    expect(find.byKey(const ValueKey('private-media-open')), findsNothing);
  });

  testWidgets(
    'attachmentless consumed and expired parents render generic terminal actions without synthetic media',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final state in <PrivateMediaLifecycleState>[
        PrivateMediaLifecycleState.consumed,
        PrivateMediaLifecycleState.expired,
      ]) {
        for (final locale in const <Locale>[
          Locale('en'),
          Locale('de'),
          Locale('ar'),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: DirectPrivateMediaTerminalPlaceholder(state: state),
              ),
            ),
          );
          await tester.pump();
          expect(
            find.byKey(ValueKey('private-terminal-${state.name}')),
            findsOneWidget,
          );
          expect(find.byType(Image), findsNothing);
          expect(
            find.byKey(const ValueKey('private-media-open')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('private-action-info')),
            findsOneWidget,
          );
          expect(find.textContaining('SECRET'), findsNothing);
          expect(tester.takeException(), isNull);
          final direction = Directionality.of(
            tester.element(
              find.byKey(ValueKey('private-terminal-${state.name}')),
            ),
          );
          expect(
            direction,
            locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          );
        }
      }
    },
  );

  testWidgets(
    'private open opening viewing terminal unsupported and capture copy are localized small and RTL safe',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Widget app(Locale locale, Widget home) => MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: home,
      );

      for (final locale in const <Locale>[
        Locale('en'),
        Locale('de'),
        Locale('ar'),
      ]) {
        await tester.pumpWidget(
          app(
            locale,
            Scaffold(
              body: SingleChildScrollView(
                key: const ValueKey('private-state-copy-scroll'),
                child: Column(
                  children: const <Widget>[
                    DirectPrivateMediaOpenPlaceholder(
                      onOpen: null,
                      contactDisplayName: 'Layla',
                    ),
                    DirectPrivateMediaOpenPlaceholder(
                      onOpen: null,
                      opening: true,
                      contactDisplayName: 'Layla',
                    ),
                    DirectPrivateMediaTerminalPlaceholder(
                      state: PrivateMediaLifecycleState.consumed,
                    ),
                    DirectPrivateMediaTerminalPlaceholder(
                      state: PrivateMediaLifecycleState.expired,
                    ),
                    DirectPrivateMediaUnsupportedPlaceholder(),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final stateContext = tester.element(
          find.byKey(const ValueKey('private-state-copy-scroll')),
        );
        final l10n = AppLocalizations.of(stateContext)!;
        expect(find.text(l10n.private_media_open), findsOneWidget);
        expect(find.text(l10n.private_media_opening), findsOneWidget);
        expect(find.text(l10n.private_media_consumed), findsOneWidget);
        expect(find.text(l10n.private_media_expired), findsOneWidget);
        expect(find.text(l10n.private_media_unsupported), findsOneWidget);
        expect(find.textContaining('SECRET'), findsNothing);
        expect(
          Directionality.of(stateContext),
          locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(tester.takeException(), isNull);

        final directory = Directory.systemTemp.createTempSync(
          'private_copy_${locale.languageCode}_',
        );
        final image = File('${directory.path}/private.png')
          ..writeAsBytesSync(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            ),
          );
        addTearDown(() => directory.deleteSync(recursive: true));

        for (final platform in <TargetPlatform>[
          TargetPlatform.android,
          TargetPlatform.iOS,
        ]) {
          final fixture = _fixture(
            mode: PrivateMediaMode.protected,
            path: image.path,
          );
          final grant = (await fixture.controller.prepare(identity))!;
          await tester.pumpWidget(
            app(
              locale,
              DirectPrivateMediaViewer(
                grant: grant,
                controller: fixture.controller,
                capturePlatformOverride: platform,
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          final viewerContext = tester.element(
            find.byKey(const ValueKey('direct-private-media-viewer')),
          );
          final viewerL10n = AppLocalizations.of(viewerContext)!;
          final expectedCapture = platform == TargetPlatform.iOS
              ? viewerL10n.private_media_ios_image_capture_limit
              : viewerL10n.private_media_android_capture_limit;
          expect(find.text(expectedCapture), findsOneWidget);
          // The generic "another camera can still photograph the screen"
          // disclaimer was removed from the viewer (user decision 2026-07-16);
          // only the platform-specific capture note renders.
          expect(
            find.text(viewerL10n.private_media_general_capture_limit),
            findsNothing,
          );
          expect(find.textContaining('SECRET'), findsNothing);
          expect(
            Directionality.of(viewerContext),
            locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      }
    },
  );

  test(
    'wired route reuses one lifecycle lock and engine and denies missing runtime capabilities',
    () {
      final source = File(
        'lib/features/conversation/presentation/screens/conversation_wired.dart',
      ).readAsStringSync();
      expect(source, contains('DirectPrivateMediaLifecycleRepository'));
      expect(source, contains('DirectPrivateMediaCleanupRepository'));
      expect(source, contains('DirectPrivateMediaCleanupRuntime'));
      expect(source, contains('directPrivateMediaLifecycleLock'));
      expect(source, contains('_privateMediaViewerController'));
      expect(
        source,
        contains(
          'attachmentRepository is! DirectPrivateMediaCleanupRepository',
        ),
      );
      expect(
        source,
        contains('attachmentRepository is! DirectPrivateMediaCleanupRuntime'),
      );
      expect(
        source,
        contains(
          'lifecycleLock: cleanupRuntime.directPrivateMediaLifecycleLock',
        ),
      );
      expect(
        RegExp('PrivateMediaLifecycleEngine\\(').allMatches(source),
        hasLength(1),
      );
    },
  );
}
