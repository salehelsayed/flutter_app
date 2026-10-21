import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/document_attachment_tile.dart';
import 'package:flutter_app/shared/widgets/media/media_grid_cell.dart';

import '../../fakes/fake_just_audio.dart';

void main() {
  setUp(installFakeJustAudioPlatform);
  for (final language in ['en', 'de', 'ar']) {
    for (final kind in ['image', 'video', 'audio', 'file']) {
      for (final exhausted in [false, true]) {
        testWidgets(
          '$language retained $kind upload failure exhausted=$exhausted stays truthful through rearm',
          (tester) async {
            final root = (await tester.runAsync(
              () => Directory.systemTemp.createTemp('sender-upload-'),
            ))!;
            addTearDown(
              () => tester.runAsync(() => root.delete(recursive: true)),
            );
            final source = File('${root.path}/source');
            await tester.runAsync(() => source.writeAsBytes([1, 2, 3, 4]));
            final attachment = MediaAttachment(
              id: 'retained',
              messageId: 'sender',
              mediaType: kind,
              mime: kind == 'audio'
                  ? 'audio/mp4'
                  : kind == 'file'
                  ? 'application/pdf'
                  : kind == 'video'
                  ? 'video/mp4'
                  : 'image/jpeg',
              size: 4,
              localPath: source.path,
              downloadStatus: 'upload_failed',
              uploadRetryCount: exhausted ? kMaxUploadRetries : 0,
              createdAt: '2026-10-21T00:00:00Z',
            );
            Future<void> show(MediaAttachment value) async {
              final Widget child = kind == 'audio'
                  ? AudioPlayerWidget(attachment: value)
                  : kind == 'file'
                  ? DocumentAttachmentTile(attachment: value)
                  : MediaGridCell(attachment: value);
              await tester.pumpWidget(
                MaterialApp(
                  locale: Locale(language),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: Scaffold(
                    body: SizedBox(width: 360, height: 220, child: child),
                  ),
                ),
              );
              await tester.pump();
            }

            await show(attachment);
            final l10n = AppLocalizations.of(
              tester.element(find.byType(Scaffold)),
            )!;
            expect(find.text(l10n.message_status_failed), findsOneWidget);
            expect(find.text(l10n.media_unavailable), findsNothing);
            expect(find.text(l10n.media_no_longer_available), findsNothing);
            expect(find.byType(CircularProgressIndicator), findsNothing);
            // Existing retry ownership rearms this same retained source.
            await show(
              attachment.copyWith(
                downloadStatus: 'upload_pending',
                uploadRetryCount: 0,
              ),
            );
            expect(find.text(l10n.post_media_pending_upload), findsOneWidget);
            expect(find.text(l10n.message_status_failed), findsNothing);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}
