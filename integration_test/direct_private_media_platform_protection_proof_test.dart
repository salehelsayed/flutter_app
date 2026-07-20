import 'dart:convert';
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
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

class _ProofLane implements PrivateMediaLifecycleLaneAdapter {
  _ProofLane(this.target);

  PrivateMediaLifecycleTarget target;
  int firstFrames = 0;
  int consumes = 0;
  int rollbacks = 0;

  @override
  Future<PrivateMediaLifecycleTarget?> loadTarget(String messageId) async =>
      target.messageId == messageId ? target : null;

  @override
  Future<bool> claimOpening(
    PrivateMediaOpeningLeaseIdentity identity, {
    required int nowMs,
  }) async {
    if (target.mode != PrivateMediaMode.viewOnce ||
        target.state != PrivateMediaLifecycleState.available) {
      return false;
    }
    target = target.copyWith(state: PrivateMediaLifecycleState.opening);
    return true;
  }

  @override
  Future<bool> markViewing(
    PrivateMediaOpeningLeaseIdentity identity, {
    required int nowMs,
  }) async {
    if (target.state != PrivateMediaLifecycleState.opening) return false;
    firstFrames++;
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
    if (target.state != PrivateMediaLifecycleState.opening) return false;
    rollbacks++;
    target = target.copyWith(state: PrivateMediaLifecycleState.available);
    return true;
  }

  @override
  Future<bool> consume(String messageId, {required int nowMs}) async {
    if (target.state.isTerminal) return false;
    consumes++;
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
    if (target.expiresAtMs != null && effectiveNow >= target.expiresAtMs!) {
      target = target.copyWith(
        state: PrivateMediaLifecycleState.expired,
        terminalAtMs: effectiveNow,
        clockHighWaterMs: effectiveNow,
      );
    } else {
      target = target.copyWith(clockHighWaterMs: effectiveNow);
    }
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
  }) async => <PrivateMediaLifecycleTarget>[target];

  @override
  Future<List<PrivateMediaLifecycleTarget>> loadRecoveryCandidates({
    int limit = 100,
  }) async => <PrivateMediaLifecycleTarget>[target];

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
    target = target.copyWith(attachments: const []);
  }
}

const _identity = DirectPrivateMediaViewerIdentity(
  messageId: 'platform-private-message',
  attachmentId: 'platform-private-attachment',
);

PrivateMediaPolicy _policy(PrivateMediaMode mode) => switch (mode) {
  PrivateMediaMode.protected => const PrivateMediaPolicy.protected(),
  PrivateMediaMode.viewOnce => const PrivateMediaPolicy.viewOnce(),
  PrivateMediaMode.disappearing => PrivateMediaPolicy.disappearing(3600),
  PrivateMediaMode.unsupported => const PrivateMediaPolicy.unsupported(
    sourceVersion: 99,
  ),
  PrivateMediaMode.ordinary => const PrivateMediaPolicy.ordinary(),
};

({DirectPrivateMediaViewerController controller, _ProofLane lane}) _controller({
  required PrivateMediaProtectionCoordinator protection,
  required String path,
  required PrivateMediaMode mode,
  PrivateMediaLifecycleState state = PrivateMediaLifecycleState.available,
  int nowMs = 100,
  int? expiresAtMs,
}) {
  final lane = _ProofLane(
    PrivateMediaLifecycleTarget(
      messageId: _identity.messageId,
      scopeId: 'platform-contact',
      mode: mode,
      state: state,
      expiresAtMs: expiresAtMs,
      clockHighWaterMs: 100,
      attachments: <PrivateMediaLifecycleAttachment>[
        PrivateMediaLifecycleAttachment(
          id: _identity.attachmentId,
          messageId: _identity.messageId,
          storedLocalPath: path,
          localPath: path,
          mime: 'image/png',
          size: File(path).lengthSync(),
          isDownloadComplete: true,
          isIntegrityEligible: true,
        ),
      ],
    ),
  );
  final engine = PrivateMediaLifecycleEngine(
    adapter: lane,
    lifecycleLock: MediaAttachmentLifecycleLock(),
    nowMs: () => nowMs,
  );
  final controller = DirectPrivateMediaViewerController(
    loadCurrentRows: (_) async => DirectPrivateMediaCurrentRows(
      parent: ConversationMessage(
        id: _identity.messageId,
        contactPeerId: 'platform-contact',
        senderPeerId: 'platform-contact',
        text: 'SECRET platform caption',
        timestamp: '2026-07-11T10:00:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-07-11T10:00:00.000Z',
        privateMediaPolicy: _policy(mode),
        privateMediaState: lane.target.state,
        privateMediaReceivedAtMs: 100,
        privateMediaExpiresAtMs: expiresAtMs,
      ),
      attachment: MediaAttachment(
        id: _identity.attachmentId,
        messageId: _identity.messageId,
        mime: 'image/png',
        size: File(path).lengthSync(),
        mediaType: 'image',
        localPath: path,
        downloadStatus: 'done',
        createdAt: '2026-07-11T10:00:00.000Z',
        ownerLane: MediaOwnerLane.direct,
      ),
    ),
    lifecycleEngine: engine,
    protectionCoordinator: protection,
  );
  return (controller: controller, lane: lane);
}

Widget _app(Widget home, {GlobalKey<NavigatorState>? navigatorKey}) =>
    MaterialApp(
      navigatorKey: navigatorKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

Future<void> _pumpUntilPrivateImageRevealed(WidgetTester tester) async {
  const coverKeys = <ValueKey<String>>[
    ValueKey<String>('typed-image-prereveal-cover'),
    ValueKey<String>('ios-capture-protected-image-prereveal-cover'),
  ];
  bool hasCover() =>
      coverKeys.any((key) => find.byKey(key).evaluate().isNotEmpty);

  for (var frame = 0; frame < 200 && hasCover(); frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  for (final key in coverKeys) {
    expect(
      find.byKey(key),
      findsNothing,
      reason: 'capture proof must run only after the private image is revealed',
    );
  }
  if (Platform.isIOS) {
    expect(
      find.byKey(
        const ValueKey<String>('ios-capture-protected-image-revealed'),
      ),
      findsOneWidget,
      reason: 'iOS proof requires the native reveal acknowledgement',
    );
  }
}

Future<void> _holdForSystemCaptureProof(
  WidgetTester tester,
  PrivateMediaProtectionCoordinator coordinator,
  String phase,
) async {
  const holdMs = int.fromEnvironment(
    'MKNOON_PRIVATE_MEDIA_CAPTURE_HOLD_MS',
    defaultValue: 0,
  );
  if (holdMs <= 0) return;
  final state = await coordinator.debugGetState();
  debugPrint(
    '[PRIVATE_MEDIA_CAPTURE_PROOF] phase=$phase '
    'activeOwnerCount=${state['activeOwnerCount']} '
    'holdMs=$holdMs',
  );
  await Future<void>.delayed(Duration(milliseconds: holdMs));
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'platform proof drives private route lifecycle denial capture and restoration',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'direct_private_platform_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final image = File('${directory.path}/private.png')
        ..writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAEAAAABAAQMAAACQp+OdAAAAA1BMVEX/AP804Oa6AAAAD0lEQVQoz2NgGAWjgHwAAAJAAAGMxat3AAAAAElFTkSuQmCC',
          ),
        );
      final brokenImage = File('${directory.path}/broken.png')
        ..writeAsBytesSync(const <int>[1, 2, 3]);

      final coordinator = PrivateMediaProtectionCoordinator.platform();
      addTearDown(coordinator.dispose);
      final events = <PrivateMediaProtectionEvent>[];
      final subscription = coordinator.events.listen(events.add);
      addTearDown(subscription.cancel);

      final before = await coordinator.debugGetState();
      expect(before['activeOwnerCount'], 0);

      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        _app(
          const Scaffold(body: SizedBox.expand()),
          navigatorKey: navigatorKey,
        ),
      );

      final viewOnce = _controller(
        protection: coordinator,
        path: image.path,
        mode: PrivateMediaMode.viewOnce,
      );
      final viewOnceGrant = await viewOnce.controller.prepare(_identity);
      expect(viewOnceGrant, isNotNull);
      expect(viewOnceGrant!.canEnterPictureInPicture, isFalse);
      final active = await coordinator.debugGetState();
      expect(active['activeOwnerCount'], 1);
      if (Platform.isAndroid) {
        expect(active['secureApplied'], isTrue);
      }

      final viewOnceRoute = navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => DirectPrivateMediaViewer(
            grant: viewOnceGrant,
            controller: viewOnce.controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('direct-private-media-viewer')),
        findsOneWidget,
      );
      await _pumpUntilPrivateImageRevealed(tester);
      expect(
        find.byKey(const ValueKey('direct-private-media-viewer')),
        findsOneWidget,
      );
      expect(viewOnceGrant.protectionReleased, isFalse);
      expect(viewOnce.lane.firstFrames, 1);
      await _holdForSystemCaptureProof(tester, coordinator, 'view_once_open');
      await tester.tap(find.byIcon(Icons.arrow_back).first);
      await tester.pumpAndSettle();
      await viewOnceRoute;
      expect(viewOnce.lane.consumes, 1);
      expect(viewOnce.lane.target.state, PrivateMediaLifecycleState.consumed);

      final protected = _controller(
        protection: coordinator,
        path: image.path,
        mode: PrivateMediaMode.protected,
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        final grant = await protected.controller.prepare(_identity);
        expect(grant, isNotNull);
        expect(grant!.canEnterPictureInPicture, isFalse);
        if (attempt == 0) {
          final route = navigatorKey.currentState!.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => DirectPrivateMediaViewer(
                grant: grant,
                controller: protected.controller,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await _pumpUntilPrivateImageRevealed(tester);
          expect(
            find.byKey(const ValueKey('direct-private-media-viewer')),
            findsOneWidget,
          );
          expect(grant.protectionReleased, isFalse);
          await _holdForSystemCaptureProof(
            tester,
            coordinator,
            'protected_open',
          );
          await tester.tap(find.byIcon(Icons.arrow_back).first);
          await tester.pumpAndSettle();
          await route;
        } else {
          await protected.controller.settle(
            grant,
            DirectPrivateMediaExitReason.close,
          );
        }
        expect(
          protected.lane.target.state,
          PrivateMediaLifecycleState.available,
        );
      }

      final ordinaryControlRoute = navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: SizedBox.expand(child: Image.file(image, fit: BoxFit.fill)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _holdForSystemCaptureProof(tester, coordinator, 'ordinary_control');
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await ordinaryControlRoute;

      final disappearing = _controller(
        protection: coordinator,
        path: image.path,
        mode: PrivateMediaMode.disappearing,
        nowMs: 1000,
        expiresAtMs: 500,
      );
      expect(await disappearing.controller.prepare(_identity), isNull);
      expect(
        disappearing.lane.target.state,
        PrivateMediaLifecycleState.expired,
      );

      final unsupported = _controller(
        protection: coordinator,
        path: image.path,
        mode: PrivateMediaMode.unsupported,
        state: PrivateMediaLifecycleState.unsupported,
      );
      expect(await unsupported.controller.prepare(_identity), isNull);

      final eventProtected = _controller(
        protection: coordinator,
        path: image.path,
        mode: PrivateMediaMode.protected,
      );
      final eventGrant = (await eventProtected.controller.prepare(_identity))!;
      final eventRoute = navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => DirectPrivateMediaViewer(
            grant: eventGrant,
            controller: eventProtected.controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final eventRouteActive = await coordinator.debugGetState();
      expect(eventRouteActive['activeOwnerCount'], 1);
      if (Platform.isAndroid) {
        expect(eventRouteActive['secureApplied'], isTrue);
      }
      expect(
        await coordinator.debugInjectEvent(
          Platform.isIOS
              ? PrivateMediaProtectionDebugEvent.captureStarted
              : PrivateMediaProtectionDebugEvent.background,
        ),
        isTrue,
      );

      // Native protection must remain observable while the covered route is
      // still mounted. The event-triggered close is intentionally waiting for
      // the next frame, so this samples the transient state before dismissal.
      final eventRouteCovered = await coordinator.debugGetState();
      expect(eventRouteCovered['activeOwnerCount'], 1);
      expect(
        find.byKey(const ValueKey('direct-private-media-viewer')),
        findsOneWidget,
      );
      if (Platform.isAndroid) {
        expect(eventRouteCovered['secureApplied'], isTrue);
      } else if (Platform.isIOS) {
        expect(eventRouteCovered['coverVisible'], isTrue);
        expect(eventRouteCovered['captureActive'], isTrue);
      }

      for (
        var frame = 0;
        frame < 40 && !eventGrant.protectionReleased;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        eventGrant.protectionReleased,
        isTrue,
        reason: 'event dismissal must settle within the bounded route window',
      );
      await eventRoute.timeout(const Duration(seconds: 5));
      final eventRouteRestored = await coordinator.debugGetState();
      expect(eventRouteRestored['activeOwnerCount'], 0);
      if (Platform.isAndroid) {
        expect(eventRouteRestored['secureApplied'], isFalse);
      } else if (Platform.isIOS) {
        expect(eventRouteRestored['coverVisible'], isFalse);
        expect(eventRouteRestored['captureActive'], isFalse);
      }

      final rendererFailure = _controller(
        protection: coordinator,
        path: brokenImage.path,
        mode: PrivateMediaMode.protected,
      );
      final failureGrant = (await rendererFailure.controller.prepare(
        _identity,
      ))!;
      final failureRoute = navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => DirectPrivateMediaViewer(
            grant: failureGrant,
            controller: rendererFailure.controller,
          ),
        ),
      );
      for (
        var frame = 0;
        frame < 40 && !failureGrant.protectionReleased;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        failureGrant.protectionReleased,
        isTrue,
        reason: 'renderer failure must settle within the bounded route window',
      );
      await failureRoute.timeout(const Duration(seconds: 5));

      final restored = await coordinator.debugGetState();
      expect(restored['activeOwnerCount'], 0);
      if (Platform.isAndroid) {
        expect(restored['secureApplied'], isFalse);
      } else if (Platform.isIOS) {
        expect(restored['coverVisible'], isFalse);
        expect(restored['captureActive'], isFalse);
      } else {
        fail('Session-05 proof supports only Android and iOS targets');
      }
      expect(events, isNotEmpty);
      expect(events, everyElement(isA<PrivateMediaProtectionEvent>()));
      expect(
        <Object?>[
          coordinator,
          viewOnceGrant,
          protected.lane.target,
          disappearing.lane.target,
        ].join(' '),
        isNot(contains('SECRET')),
      );
    },
  );
}
