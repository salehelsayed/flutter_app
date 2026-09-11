import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';
import 'package:flutter_app/shared/widgets/media/media_video_resume_controller.dart';

import 'fake_media_playback_adapter.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );

  MediaViewerItem videoItem(String id) => MediaViewerItem(
    attachmentId: id,
    messageId: 'm-$id',
    kind: MediaViewerKind.video,
    mime: 'video/mp4',
    owner: MediaOwnerLane.group,
    durationMs: 60000,
    localPath: '/tmp/$id.mp4',
  );

  testWidgets(
    'only current visible video may play across lifecycle transitions',
    (tester) async {
      final adapters = <String, FakeMediaPlaybackAdapter>{};
      FakeMediaPlaybackAdapter factory(MediaViewerItem item) =>
          adapters.putIfAbsent(
            item.attachmentId,
            () =>
                FakeMediaPlaybackAdapter(duration: const Duration(seconds: 60)),
          );

      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: [videoItem('V1'), videoItem('V2')],
            playbackAdapterFactory: factory,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Only the current page auto-plays; the off-screen page is not even
      // started (lazily unbuilt or built-but-idle).
      expect(adapters['V1']!.playCount, greaterThanOrEqualTo(1));
      expect(
        adapters['V2']?.playCount ?? 0,
        0,
        reason: 'non-current never starts',
      );

      // Background pauses exactly the owned (current) controller.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final v1PauseAfterBackground = adapters['V1']!.pauseCount;
      expect(v1PauseAfterBackground, greaterThanOrEqualTo(1));
      expect(adapters['V2']?.playCount ?? 0, 0);

      // Foreground alone does not auto-play.
      final v1PlayBeforeForeground = adapters['V1']!.playCount;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(adapters['V1']!.playCount, v1PlayBeforeForeground);

      // Page change: the leaving page stops (pause or dispose), the new
      // current page plays.
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
      await tester.pumpAndSettle();
      expect(adapters['V2']!.playCount, greaterThanOrEqualTo(1));
      expect(
        adapters['V1']!.pauseCount > v1PauseAfterBackground ||
            adapters['V1']!.disposeCount >= 1,
        isTrue,
        reason: 'leaving page pauses or disposes the owned controller',
      );

      // Route exit / disposal disposes the owned controllers.
      await tester.pumpWidget(wrap(const SizedBox.shrink()));
      await tester.pump();
      expect(adapters['V2']!.disposeCount, 1);
      expect(adapters['V1']!.disposeCount, greaterThanOrEqualTo(1));
    },
  );

  for (final resumeBeforeReady in [false, true]) {
    testWidgets('late initialization cannot autoplay after backgrounding '
        '(resumeBeforeReady=$resumeBeforeReady)', (tester) async {
      final gate = Completer<void>();
      final adapter = FakeMediaPlaybackAdapter(initializeGate: gate);
      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: [videoItem('V1')],
            playbackAdapterFactory: (_) => adapter,
          ),
        ),
      );
      await tester.pump();
      expect(adapter.initializeCount, 1);
      expect(adapter.playCount, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      if (resumeBeforeReady) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(adapter.playCount, 0);

      // Returning to the foreground stays paused; a new explicit play works.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(adapter.playCount, 0);
      await tester.tap(find.byKey(const ValueKey('media_controls_play_pause')));
      await tester.pump();
      expect(adapter.playCount, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final returnBeforeResume in [false, true]) {
    testWidgets('pending resume belongs to the current page '
        '(returnBeforeResume=$returnBeforeResume)', (tester) async {
      final adapters = <String, FakeMediaPlaybackAdapter>{};
      final store = _HeldResumeStore();
      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: [videoItem('V1'), videoItem('V2')],
            resumeStore: store,
            playbackAdapterFactory: (item) => adapters.putIfAbsent(
              item.attachmentId,
              () => FakeMediaPlaybackAdapter(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(store.heldReads, 1);
      expect(adapters['V1']!.playCount, 0);

      // Keep both pages mounted during a drag across the current-page boundary.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-460, 0));
      await tester.pump();
      await tester.pump();
      expect(find.text('2 / 2'), findsOneWidget);
      expect(adapters['V1']!.disposeCount, 0);
      expect(adapters['V2']!.isPlaying, isTrue);

      if (returnBeforeResume) {
        await gesture.moveBy(const Offset(460, 0));
        await tester.pump();
        await tester.pump();
        expect(find.text('1 / 2'), findsOneWidget);
        expect(
          adapters['V1']!.playCount,
          0,
          reason: 'the new activation must await the same pending seek',
        );
      }

      store.pending.complete(12000);
      await tester.pump();
      await tester.pump();
      expect(store.heldReads, 1);
      expect(adapters['V1']!.playCount, returnBeforeResume ? 1 : 0);
      expect(adapters['V1']!.isPlaying, returnBeforeResume);
      expect(adapters['V2']!.isPlaying, !returnBeforeResume);
      if (returnBeforeResume) {
        expect(adapters['V1']!.position, const Duration(seconds: 12));
      }
      await gesture.up();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('delayed reveal authorization cannot autoplay after app pause', (
    tester,
  ) async {
    final authorization = Completer<bool>();
    final adapter = FakeMediaPlaybackAdapter();
    var authorizationCalls = 0;
    await tester.pumpWidget(
      wrap(
        FullScreenTypedMediaViewer(
          items: [videoItem('V1')],
          playbackAdapterFactory: (_) => adapter,
          onFirstRenderedFrame: () {
            authorizationCalls++;
            return authorization.future;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(authorizationCalls, 1);
    expect(adapter.playCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    authorization.complete(true);
    await tester.pump();
    await tester.pump();
    expect(adapter.playCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _HeldResumeStore implements MediaViewerResumeStore {
  final pending = Completer<int?>();
  int heldReads = 0;

  @override
  Future<int?> readResumePosition(MediaViewerItem item) {
    if (item.attachmentId == 'V1') {
      heldReads++;
      return pending.future;
    }
    return Future.value(null);
  }

  @override
  Future<void> writeResumePosition(
    MediaViewerItem item,
    int positionMs,
  ) async {}
}
