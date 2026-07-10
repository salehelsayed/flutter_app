import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';

import 'fake_media_playback_adapter.dart';

void main() {
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
            () => FakeMediaPlaybackAdapter(
              duration: const Duration(seconds: 60),
            ),
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
      expect(adapters['V2']?.playCount ?? 0, 0, reason: 'non-current never starts');

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
}
