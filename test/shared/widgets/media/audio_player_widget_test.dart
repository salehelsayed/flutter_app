import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/waveform_seek_bar.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

void main() {
  Widget buildApp(
    MediaAttachment attachment, {
    bool requireVerifiedContentHash = false,
    VoidCallback? onRetryUnavailableMedia,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: AudioPlayerWidget(
          attachment: attachment,
          requireVerifiedContentHash: requireVerifiedContentHash,
          onRetryUnavailableMedia: onRetryUnavailableMedia,
        ),
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
    testWidgets('renders WaveformSeekBar when attachment has waveform data', (
      tester,
    ) async {
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
      final attachment = baseAttachment.copyWith(waveform: [0.5, 0.5]);
      await tester.pumpWidget(buildApp(attachment));

      // Duration label should be visible (either formatted or '--:--')
      expect(find.byType(Text), findsWidgets);
    });

    testWidgets(
      'quarantined (integrity_failed) audio shows the couldn\'t-verify terminal '
      'label and NO retry (INV-DL-3)',
      (tester) async {
        var retried = false;
        final quarantined = baseAttachment.copyWith(
          localPath: '/tmp/quarantined.m4a',
          downloadStatus: kMediaDownloadStatusIntegrityFailed,
          contentHash:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          encryptionKeyBase64: 'key-audio',
          encryptionNonce: 'nonce-audio',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );

        await tester.pumpWidget(
          buildApp(
            quarantined,
            requireVerifiedContentHash: true,
            onRetryUnavailableMedia: () => retried = true,
          ),
        );

        // Tamper gets the distinct honest label and is NOT retryable — retrying
        // the same descriptor would just re-fail.
        expect(find.text("Couldn't verify this media"), findsOneWidget);
        expect(
          find.bySemanticsLabel('Retry unavailable media'),
          findsNothing,
        );
        expect(find.byType(WaveformSeekBar), findsNothing);
        expect(find.byType(Slider), findsNothing);
        expect(retried, isFalse);
      },
    );

    testWidgets(
      'transient failed audio under the ceiling still exposes a retry affordance',
      (tester) async {
        var retried = false;
        final failed = baseAttachment.copyWith(
          localPath: '/tmp/failed.m4a',
          downloadStatus: kMediaDownloadStatusFailed,
          downloadRetryCount: 1,
        );

        await tester.pumpWidget(
          buildApp(failed, onRetryUnavailableMedia: () => retried = true),
        );

        expect(find.text('Media unavailable'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Retry unavailable media'),
          findsOneWidget,
        );

        await tester.tap(find.byIcon(Icons.refresh_rounded));
        await tester.pump();
        expect(retried, isTrue);
      },
    );

    testWidgets(
      'terminal download_failed audio shows the unavailable label and NO retry',
      (tester) async {
        var retried = false;
        final terminal = baseAttachment.copyWith(
          localPath: '/tmp/terminal.m4a',
          downloadStatus: kMediaDownloadStatusDownloadFailed,
          downloadRetryCount: kMaxDownloadRetries,
        );

        await tester.pumpWidget(
          buildApp(terminal, onRetryUnavailableMedia: () => retried = true),
        );

        expect(find.text('Media unavailable'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Retry unavailable media'),
          findsNothing,
        );
        expect(find.byType(WaveformSeekBar), findsNothing);
        expect(retried, isFalse);
      },
    );
  });
}
