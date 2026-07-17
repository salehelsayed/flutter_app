import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:flutter_test/flutter_test.dart';

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
  Future<bool> claimOpening(String messageId, {required int nowMs}) async {
    if (target.state != PrivateMediaLifecycleState.available ||
        target.mode != PrivateMediaMode.viewOnce ||
        target.hidden) {
      return false;
    }
    claimCount++;
    target = target.copyWith(state: PrivateMediaLifecycleState.opening);
    return true;
  }

  @override
  Future<bool> markViewing(String messageId, {required int nowMs}) async {
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
  Future<bool> rollbackOpening(String messageId) async {
    if (target.state != PrivateMediaLifecycleState.opening || target.hidden) {
      return false;
    }
    rollbackCount++;
    target = target.copyWith(state: PrivateMediaLifecycleState.available);
    return true;
  }

  @override
  Future<bool> consume(String messageId, {required int nowMs}) async {
    if (target.mode != PrivateMediaMode.viewOnce || target.state.isTerminal) {
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
    isIncoming: true,
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
}) => MediaAttachment(
  id: id,
  messageId: 'message-1',
  mime: mime ?? (mediaType == 'video' ? 'video/SECRET' : 'image/SECRET'),
  size: size ?? (File(path).existsSync() ? File(path).lengthSync() : 99),
  mediaType: mediaType,
  localPath: path,
  downloadStatus: 'done',
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
}) => PrivateMediaLifecycleTarget(
  messageId: 'message-1',
  scopeId: 'contact-1',
  mode: mode,
  state: state,
  expiresAtMs: expiresAtMs,
  clockHighWaterMs: 100,
  attachments: [
    PrivateMediaLifecycleAttachment(
      id: attachmentId,
      messageId: 'message-1',
      storedLocalPath: path,
      localPath: path,
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
    _target(effectivePath, mode: mode, state: state, expiresAtMs: expiresAtMs),
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
        ),
        attachment: lane.target.attachments.isEmpty
            ? null
            : currentAttachmentForLoad?.call(loadCount, lane, effectivePath) ??
                  _attachment(effectivePath),
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
    'lease identity mismatch and thrown post-enter reload terminalize view once and release protection',
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
      expect(wrongLease.lane.consumeCount, 1);
      expect(wrongLease.lane.cleanupCount, 1);
      expect(wrongLease.lane.target.state, PrivateMediaLifecycleState.consumed);

      final reloadThrow = _fixture(throwCurrentRowsOnLoad: 2);
      expect(await reloadThrow.controller.prepare(identity), isNull);
      expect(reloadThrow.currentRowLoads, [1, 2]);
      expect(reloadThrow.lane.consumeCount, 1);
      expect(reloadThrow.lane.cleanupCount, 1);
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
    'post-enter terminal delete expiry or lease loss builds no route and view once terminalizes',
    () async {
      final fixture = _fixture(
        onNativeEnter: (lane) async {
          lane.target = lane.target.copyWith(hidden: true);
        },
      );
      expect(await fixture.controller.prepare(identity), isNull);
      expect(fixture.lane.consumeCount, 1);
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
      expect(replacedPath.lane.consumeCount, 1);
      expect(replacedPath.nativeCalls, ['enter', 'exit']);
    },
  );

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
                    DirectPrivateMediaOpenPlaceholder(onOpen: null),
                    DirectPrivateMediaOpenPlaceholder(
                      onOpen: null,
                      opening: true,
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
              ? viewerL10n.private_media_ios_capture_limit
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
