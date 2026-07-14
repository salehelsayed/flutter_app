import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_private_media_lifecycle.dart';
import 'package:flutter_app/features/groups/application/group_private_media_viewer_controller.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_private_media_viewer.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLifecycleEngine implements GroupPrivateMediaLifecycleEngine {
  _FakeLifecycleEngine({
    required this.data,
    required this.order,
    this.settleGate,
  });

  final GroupPrivateMediaOpenGrantData data;
  final List<String> order;
  final Completer<void>? settleGate;
  bool qualifies = true;
  bool consumeSucceeds = true;
  bool revalidateSucceeds = true;
  int qualifyCalls = 0;
  int consumeCalls = 0;
  int revalidateCalls = 0;
  int settleCalls = 0;

  @override
  Future<GroupPrivateMediaOpenGrantData?> qualifyOpen({
    required String groupId,
    required String messageId,
    required String attachmentId,
  }) async {
    qualifyCalls++;
    order.add('qualify:$groupId:$messageId:$attachmentId');
    if (!qualifies ||
        groupId != data.groupId ||
        messageId != data.messageId ||
        attachmentId != data.attachmentId) {
      return null;
    }
    return data;
  }

  @override
  Future<bool> consumeAtFirstFrame(GroupPrivateMediaOpenGrantData grant) async {
    consumeCalls++;
    order.add('consume');
    if (!consumeSucceeds) return false;
    if (grant.policy.lifecycle == GroupMediaLifecycle.viewOnce) {
      grant.consumedAtFirstFrame = true;
    }
    return true;
  }

  @override
  Future<bool> revalidateOpen(GroupPrivateMediaOpenGrantData grant) async {
    revalidateCalls++;
    return revalidateSucceeds;
  }

  @override
  Future<void> settle(GroupPrivateMediaOpenGrantData grant) async {
    settleCalls++;
    order.add('settle');
    await settleGate?.future;
  }

  @override
  Future<GroupPrivateMediaReconcileResult> sweepExpiries({
    int limit = 100,
    int? evaluationFloorMs,
  }) async => GroupPrivateMediaReconcileResult();

  @override
  Future<GroupPrivateMediaReconcileResult> reconcileLocalLifecycle({
    int limit = 100,
  }) async => GroupPrivateMediaReconcileResult();

  @override
  Future<int?> loadNextExpiryAtMs() async => data.expiresAtMs;

  @override
  Future<bool> cleanupTerminalMessage(String messageId) async => true;

  @override
  int Function() get nowMs =>
      () => 200;

  // The controller exercises only the lifecycle methods above. These concrete
  // engine collaborators remain deliberately unreachable in this presentation
  // fixture so an accidental lower-layer call fails the test immediately.
  @override
  Never get messageRepository => throw StateError('unexpected repository read');

  @override
  Never get mediaAttachmentRepository =>
      throw StateError('unexpected attachment read');

  @override
  Never get cleanupRepository => throw StateError('unexpected cleanup read');

  @override
  Never get mediaFileManager => throw StateError('unexpected file read');

  @override
  Never get lifecycleLock => throw StateError('unexpected lock read');
}

class _ViewerFixture {
  _ViewerFixture({
    required String path,
    GroupPrivateMediaPolicy policy = const GroupPrivateMediaPolicy.protected(),
    MediaViewerKind kind = MediaViewerKind.image,
    Completer<Object?>? enterGate,
    Completer<void>? settleGate,
  }) : events = StreamController<Object?>.broadcast(sync: true),
       order = <String>[],
       nativeCalls = <String>[] {
    engine = _FakeLifecycleEngine(
      data: GroupPrivateMediaOpenGrantData(
        groupId: 'group-private',
        messageId: 'message-private',
        attachmentId: 'attachment-private',
        policy: policy,
        kind: kind,
        localPath: path,
        expiresAtMs: null,
      ),
      order: order,
      settleGate: settleGate,
    );
    protection = PrivateMediaProtectionCoordinator(
      invokeMethod: (method, arguments) async {
        nativeCalls.add(method);
        order.add('native:$method');
        if (method == 'enter' && enterGate != null) {
          return enterGate.future;
        }
        return <String, Object?>{
          'ok': true,
          'protectionActive': method == 'enter',
        };
      },
      nativeEvents: events.stream,
    );
    controller = GroupPrivateMediaViewerController(
      lifecycleEngine: engine,
      protectionCoordinator: protection,
    );
  }

  final StreamController<Object?> events;
  final List<String> order;
  final List<String> nativeCalls;
  late final _FakeLifecycleEngine engine;
  late final PrivateMediaProtectionCoordinator protection;
  late final GroupPrivateMediaViewerController controller;

  Future<GroupPrivateMediaViewerGrant?> prepare() => controller.prepare(
    const GroupPrivateMediaViewerIdentity(
      groupId: 'group-private',
      messageId: 'message-private',
      attachmentId: 'attachment-private',
    ),
  );

  Future<void> close(
    GroupPrivateMediaViewerGrant? grant, {
    WidgetTester? tester,
  }) async {
    if (grant != null && !grant.protectionReleased) {
      await controller.settle(grant, GroupPrivateMediaExitReason.dispose);
    }
    await events.close();
    unawaited(controller.dispose());
  }
}

File _validImage() {
  final directory = Directory.systemTemp.createTempSync(
    'group-private-viewer-',
  );
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return File('${directory.path}/SECRET-private.png')..writeAsBytesSync(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
  );
}

MaterialApp _routedViewerApp({
  required GroupPrivateMediaViewerGrant grant,
  required GroupPrivateMediaViewerController controller,
  TargetPlatform? platform,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    initialRoute: '/private',
    routes: <String, WidgetBuilder>{
      '/': (_) => const SizedBox(key: ValueKey('ordinary-underlying-route')),
      '/private': (_) => GroupPrivateMediaViewer(
        grant: grant,
        controller: controller,
        capturePlatformOverride: platform,
      ),
    },
  );
}

Future<void> _pumpUntilReleased(
  WidgetTester tester,
  GroupPrivateMediaViewerGrant grant,
) async {
  for (var frame = 0; frame < 30; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (grant.protectionReleased) {
      // The grant flips this flag before the awaited native exit completes.
      // Give the release future a frame to remove the grant from the
      // controller's active-owner set before disposing the controller.
      await tester.pump();
      return;
    }
  }
}

void main() {
  test(
    'GPL-11 controller enters native protection before publishing the path and balances ownership',
    () async {
      final image = _validImage();
      final enterGate = Completer<Object?>();
      final fixture = _ViewerFixture(
        path: image.path,
        policy: const GroupPrivateMediaPolicy.viewOnce(),
        enterGate: enterGate,
      );
      GroupPrivateMediaViewerGrant? grant;
      addTearDown(() => fixture.close(grant));

      var completed = false;
      final preparing = fixture.prepare().whenComplete(() => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(fixture.order, <String>[
        'qualify:group-private:message-private:attachment-private',
        'native:enter',
      ]);
      expect(
        completed,
        isFalse,
        reason: 'no path-bearing grant may publish before native enter',
      );

      enterGate.complete(<String, Object?>{
        'ok': true,
        'protectionActive': true,
      });
      grant = await preparing;
      expect(grant, isNotNull);
      final liveGrant = grant!;
      expect(fixture.engine.qualifyCalls, 2);
      expect(fixture.order.take(3), <String>[
        'qualify:group-private:message-private:attachment-private',
        'native:enter',
        'qualify:group-private:message-private:attachment-private',
      ]);
      expect(await fixture.controller.markFirstFrame(liveGrant), isTrue);
      expect(await fixture.controller.markFirstFrame(liveGrant), isFalse);
      expect(fixture.engine.consumeCalls, 1);
      await fixture.controller.settle(
        liveGrant,
        GroupPrivateMediaExitReason.close,
      );
      expect(fixture.nativeCalls, <String>['enter', 'exit']);
      expect(liveGrant.protectionReleased, isTrue);
    },
  );

  testWidgets(
    'GPL-11 viewer is privacy minimized denies PiP and shows truthful platform copy',
    (tester) async {
      final image = _validImage();
      for (final platform in <TargetPlatform>[
        TargetPlatform.android,
        TargetPlatform.iOS,
      ]) {
        final fixture = _ViewerFixture(path: image.path);
        final grant = await fixture.prepare();
        expect(grant, isNotNull);
        final liveGrant = grant!;
        try {
          await tester.pumpWidget(
            _routedViewerApp(
              grant: liveGrant,
              controller: fixture.controller,
              platform: platform,
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump();

          expect(
            find.byKey(const ValueKey('group-private-media-viewer')),
            findsOneWidget,
          );
          final typed = tester.widget<FullScreenTypedMediaViewer>(
            find.byType(FullScreenTypedMediaViewer),
          );
          expect(typed.privacyMinimized, isTrue);
          expect(typed.onAction, isNull);
          expect(typed.resumeStore, isNull);
          expect(typed.onFirstRenderedFrame, isNotNull);
          expect(await typed.onFirstRenderedFrame!.call(), isTrue);
          expect(typed.items, hasLength(1));
          final item = typed.items.single;
          expect(item.owner, MediaOwnerLane.group);
          expect(item.capabilities.allowed, isEmpty);
          expect(item.protection.isProtected, isTrue);
          expect(item.canEnterPictureInPicture, isFalse);
          for (final action in MediaViewerAction.values) {
            expect(item.canDispatch(action), isFalse);
            expect(
              find.byKey(ValueKey('media_action_${action.name}')),
              findsNothing,
            );
          }
          expect(find.byKey(const ValueKey('media_meta_mime')), findsNothing);
          expect(
            find.byKey(const ValueKey('media_meta_caption')),
            findsNothing,
          );
          expect(find.textContaining('SECRET'), findsNothing);
          expect(fixture.engine.consumeCalls, 1);

          final context = tester.element(
            find.byKey(const ValueKey('group-private-media-viewer')),
          );
          final l10n = AppLocalizations.of(context)!;
          expect(
            find.text(
              platform == TargetPlatform.iOS
                  ? l10n.private_media_ios_capture_limit
                  : l10n.private_media_android_capture_limit,
            ),
            findsOneWidget,
          );
          expect(
            find.text(l10n.private_media_general_capture_limit),
            findsOneWidget,
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await _pumpUntilReleased(tester, liveGrant);
          expect(liveGrant.protectionReleased, isTrue);
          expect(fixture.nativeCalls, <String>['enter', 'exit']);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _pumpUntilReleased(tester, liveGrant);
          await fixture.close(grant, tester: tester);
        }
      }
    },
  );

  testWidgets(
    'GPL-11 pre-frame decode failure never consumes and closes protected route',
    (tester) async {
      final missingPath =
          '${Directory.systemTemp.path}/missing-group-private-${DateTime.now().microsecondsSinceEpoch}.png';
      final fixture = _ViewerFixture(
        path: missingPath,
        policy: const GroupPrivateMediaPolicy.viewOnce(),
      );
      final grant = await fixture.prepare();
      expect(grant, isNotNull);
      final liveGrant = grant!;
      addTearDown(() => fixture.close(grant, tester: tester));

      await tester.pumpWidget(
        _routedViewerApp(grant: liveGrant, controller: fixture.controller),
      );
      await tester.pump();
      final typed = tester.widget<FullScreenTypedMediaViewer>(
        find.byType(FullScreenTypedMediaViewer),
      );
      expect(typed.onPreFrameFailure, isNotNull);
      typed.onPreFrameFailure!.call();
      await _pumpUntilReleased(tester, liveGrant);

      expect(fixture.engine.consumeCalls, 0);
      expect(fixture.engine.settleCalls, 1);
      expect(liveGrant.firstFrameRecorded, isFalse);
      expect(liveGrant.protectionReleased, isTrue);
      expect(fixture.nativeCalls, <String>['enter', 'exit']);
      expect(
        find.byKey(const ValueKey('group-private-media-viewer')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('ordinary-underlying-route')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'GPL-11 capture and background cover immediately then close before native release',
    (tester) async {
      final image = _validImage();
      for (final scenario in <String>['capture', 'background']) {
        final settleGate = Completer<void>();
        final fixture = _ViewerFixture(
          path: image.path,
          settleGate: settleGate,
        );
        final grant = await fixture.prepare();
        expect(grant, isNotNull);
        final liveGrant = grant!;
        try {
          await tester.pumpWidget(
            _routedViewerApp(grant: liveGrant, controller: fixture.controller),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          if (scenario == 'capture') {
            fixture.events.add(<String, Object?>{'event': 'captureStarted'});
          } else {
            fixture.events.add(<String, Object?>{'event': 'background'});
          }
          await tester.pump();
          await tester.pump();

          expect(
            find.byKey(const ValueKey('group-private-media-cover')),
            findsOneWidget,
            reason: '$scenario must cover while durable settle is pending',
          );
          expect(liveGrant.protectionReleased, isFalse);
          expect(fixture.nativeCalls, <String>['enter']);

          settleGate.complete();
          await _pumpUntilReleased(tester, liveGrant);
          expect(liveGrant.protectionReleased, isTrue);
          expect(fixture.nativeCalls, <String>['enter', 'exit']);
          expect(
            find.byKey(const ValueKey('group-private-media-viewer')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('ordinary-underlying-route')),
            findsOneWidget,
          );
        } finally {
          if (!settleGate.isCompleted) settleGate.complete();
          await fixture.close(grant, tester: tester);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      }
    },
  );
}
