import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/media_video_controls.dart';

import 'fake_media_playback_adapter.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  testWidgets(
    'seek speed mute and time controls drive one active adapter safely',
    (tester) async {
      final adapter = FakeMediaPlaybackAdapter(
        duration: const Duration(seconds: 60),
        position: const Duration(seconds: 30),
      );

      await tester.pumpWidget(wrap(MediaVideoControls(adapter: adapter)));
      await tester.pump();

      // Elapsed / duration readout for the current position.
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('media_controls_time')))
            .data,
        '0:30 / 1:00',
      );

      // Four playback speeds cycle in order and the label stays fresh.
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const ValueKey('media_controls_speed')));
        await tester.pump();
      }
      expect(adapter.setSpeedCalls, <double>[1.5, 2.0, 0.5, 1.0]);
      expect(find.text('1x'), findsOneWidget);

      // Mute toggles.
      await tester.tap(find.byKey(const ValueKey('media_controls_mute')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('media_controls_mute')));
      await tester.pump();
      expect(adapter.setMutedCalls, <bool>[true, false]);

      // Play / pause drives exactly this adapter.
      await tester.tap(
        find.byKey(const ValueKey('media_controls_play_pause')),
      );
      await tester.pump();
      expect(adapter.playCount, 1);
      await tester.tap(
        find.byKey(const ValueKey('media_controls_play_pause')),
      );
      await tester.pump();
      expect(adapter.pauseCount, 1);

      // Seek forward from mid-clip clamps to nothing (target well inside).
      await tester.tap(
        find.byKey(const ValueKey('media_controls_skip_forward')),
      );
      await tester.pump();
      expect(adapter.seekTargets.last, const Duration(seconds: 40));

      // Seek forward near the end clamps to the upper bound (duration).
      adapter.position = const Duration(seconds: 55);
      adapter.notify();
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('media_controls_skip_forward')),
      );
      await tester.pump();
      expect(adapter.seekTargets.last, const Duration(seconds: 60));

      // Seek back past the start clamps to the lower bound (zero).
      adapter.position = const Duration(seconds: 5);
      adapter.notify();
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('media_controls_skip_back')),
      );
      await tester.pump();
      expect(adapter.seekTargets.last, Duration.zero);
    },
  );
}
