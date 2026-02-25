import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/shared/widgets/media/video_thumbnail_overlay.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(width: 200, height: 200, child: child)),
  );

  group('VideoThumbnailOverlay', () {
    testWidgets('renders play arrow icon', (tester) async {
      await tester.pumpWidget(wrap(const VideoThumbnailOverlay()));
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('shows duration pill when durationMs is provided', (tester) async {
      await tester.pumpWidget(wrap(const VideoThumbnailOverlay(durationMs: 65000)));
      expect(find.text('1:05'), findsOneWidget);
    });

    testWidgets('hides duration pill when durationMs is null', (tester) async {
      await tester.pumpWidget(wrap(const VideoThumbnailOverlay()));
      // Only the play icon, no duration text
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      // No text widgets for duration
      expect(find.text('0:00'), findsNothing);
    });

    testWidgets('formats duration correctly', (tester) async {
      await tester.pumpWidget(wrap(const VideoThumbnailOverlay(durationMs: 125000)));
      expect(find.text('2:05'), findsOneWidget);
    });
  });
}
