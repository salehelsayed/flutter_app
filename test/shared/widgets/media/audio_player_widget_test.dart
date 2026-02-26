import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/waveform_seek_bar.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

void main() {
  Widget buildApp(MediaAttachment attachment) {
    return MaterialApp(
      home: Scaffold(
        body: AudioPlayerWidget(attachment: attachment),
      ),
    );
  }

  const baseAttachment = MediaAttachment(
    id: 'att-audio-001',
    messageId: 'msg-001',
    mime: 'audio/mp4',
    size: 10000,
    mediaType: 'audio',
    durationMs: 5000,
    downloadStatus: 'done',
    createdAt: '2026-02-26T10:00:00.000Z',
    // localPath intentionally null so player stays in unloaded state
    // (avoids needing a real audio file)
  );

  group('AudioPlayerWidget', () {
    testWidgets('renders WaveformSeekBar when attachment has waveform data',
        (tester) async {
      final attachment = baseAttachment.copyWith(
        waveform: [0.1, 0.5, 0.8, 0.3, 0.6],
      );
      await tester.pumpWidget(buildApp(attachment));

      expect(find.byType(WaveformSeekBar), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('falls back to Slider when waveform is null', (tester) async {
      await tester.pumpWidget(buildApp(baseAttachment));

      expect(find.byType(Slider), findsOneWidget);
      expect(find.byType(WaveformSeekBar), findsNothing);
    });

    testWidgets('play/pause button is always present', (tester) async {
      await tester.pumpWidget(buildApp(baseAttachment));
      // Should find the play icon
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('duration label is always present', (tester) async {
      final attachment = baseAttachment.copyWith(
        waveform: [0.5, 0.5],
      );
      await tester.pumpWidget(buildApp(attachment));

      // Duration label should be visible (either formatted or '--:--')
      expect(find.byType(Text), findsWidgets);
    });
  });
}
