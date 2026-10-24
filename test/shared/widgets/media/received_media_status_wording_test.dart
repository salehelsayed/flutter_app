import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/document_attachment_tile.dart';
import 'package:flutter_app/shared/widgets/media/media_grid_cell.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_media_info_sheet.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import '../../fakes/fake_just_audio.dart';

void main() {
  setUp(installFakeJustAudioPlatform);
  const copy = {
    'en': [
      "Couldn't load yet. Tap to try again.",
      'No longer available',
      "Couldn't open this file",
    ],
    'de': [
      'Noch nicht geladen. Tippe, um es erneut zu versuchen.',
      'Nicht mehr verfügbar',
      'Datei konnte nicht geöffnet werden',
    ],
    'ar': [
      'لم يتم التحميل بعد. اضغط للمحاولة مرة أخرى.',
      'لم تعد متاحة',
      'تعذر فتح هذا الملف',
    ],
  };
  const statuses = {
    'loading': kMediaDownloadStatusDownloading,
    'retry-pending': kMediaDownloadStatusPending,
    'retryable-failed': kMediaDownloadStatusFailed,
    'deferred': kMediaDownloadStatusRetryWaiting,
    'notfound-wait-1': kMediaDownloadStatusNotFoundRetry1,
    'notfound-wait-2': kMediaDownloadStatusNotFoundRetry2,
    'notfound-wait-3': kMediaDownloadStatusNotFoundRetry3,
    'gone': kMediaDownloadStatusUnavailable,
    'cannot-open': kMediaDownloadStatusIntegrityFailed,
  };
  for (final language in copy.keys) {
    for (final tile in ['image', 'audio', 'file']) {
      for (final state in statuses.entries) {
        testWidgets(
          '$language $tile ${state.key} has exact truthful receiver copy',
          (tester) async {
            var retries = 0;
            final id = '$tile-${state.key}';
            final loading = [
              'loading',
              'retry-pending',
              'retryable-failed',
              'notfound-wait-1',
              'notfound-wait-2',
              'notfound-wait-3',
            ].contains(state.key);
            final attachment = MediaAttachment(
              id: id,
              messageId: 'message',
              mime: tile == 'file'
                  ? 'application/pdf'
                  : tile == 'audio'
                  ? 'audio/mp4'
                  : 'image/jpeg',
              mediaType: tile,
              size: 4096,
              fileName: 'photo.pdf',
              downloadStatus: state.value,
              downloadRetryCount:
                  state.key == 'retry-pending' ||
                      state.key == 'retryable-failed'
                  ? 1
                  : 0,
              ownerLane: MediaOwnerLane.direct,
              createdAt: '2026-10-20T00:00:00Z',
            );
            final Widget child;
            if (tile == 'audio') {
              child = AudioPlayerWidget(
                attachment: attachment,
                onRetryUnavailableMedia: () => retries++,
              );
            } else if (tile == 'file') {
              child = DocumentAttachmentTile(
                attachment: attachment,
                onRetryUnavailableMedia: () => retries++,
              );
            } else {
              child = MediaGridCell(
                attachment: attachment,
                onRetryUnavailableMedia: () => retries++,
              );
            }
            await tester.pumpWidget(
              MaterialApp(
                locale: Locale(language),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Scaffold(
                  body: SizedBox(width: 360, height: 220, child: child),
                ),
              ),
            );
            await tester.pump();
            if (loading) {
              for (final text in copy[language]!) {
                expect(find.text(text), findsNothing);
              }
              expect(find.byType(CircularProgressIndicator), findsOneWidget);
              expect(find.text('Media unavailable'), findsNothing);
              if (state.key.startsWith('notfound-wait')) {
                expect(
                  find.byKey(DocumentAttachmentTile.retryKey(id)),
                  findsNothing,
                );
                expect(
                  find.byKey(ValueKey('unavailable-media-retry-message-$id')),
                  findsNothing,
                );
                expect(retries, 0);
              }
            } else {
              final index = state.key == 'deferred'
                  ? 0
                  : state.key == 'gone'
                  ? 1
                  : 2;
              expect(find.text(copy[language]![index]), findsOneWidget);
              for (var other = 0; other < 3; other++) {
                if (other != index) {
                  expect(find.text(copy[language]![other]), findsNothing);
                }
              }
              expect(find.byType(CircularProgressIndicator), findsNothing);
              final retryKey = tile == 'file'
                  ? DocumentAttachmentTile.retryKey(id)
                  : ValueKey('unavailable-media-retry-message-$id');
              if (state.key == 'deferred') {
                expect(find.byKey(retryKey), findsOneWidget);
                await tester.tap(find.byKey(retryKey));
                expect(retries, 1);
              } else {
                expect(find.byKey(retryKey), findsNothing);
              }
            }
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
  for (final language in copy.keys) {
    for (final status in kMediaDownloadNotFoundRetryStatuses) {
      testWidgets(
        '$language absence window group info stays pending without internals',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: GroupMediaInfoSheet(
                  attachment: MediaAttachment(
                    id: 'absence-info',
                    messageId: 'message',
                    mime: 'image/jpeg',
                    mediaType: 'image',
                    size: 4096,
                    ownerLane: MediaOwnerLane.group,
                    downloadStatus: status,
                    createdAt: '2026-10-20T00:00:00Z',
                  ),
                  senderDisplayName: 'Sender',
                  sentAt: DateTime.utc(2026, 10, 20),
                ),
              ),
            ),
          );
          await tester.pump();
          final l10n = AppLocalizations.of(
            tester.element(find.byKey(GroupMediaInfoSheet.sheetKey)),
          )!;
          expect(
            find.text(l10n.group_media_info_state_pending),
            findsOneWidget,
          );
          expect(
            find.text(l10n.group_media_info_state_unavailable),
            findsNothing,
          );
          expect(find.text(status), findsNothing);
          expect(find.byTooltip(l10n.btn_retry), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('a real decoder failure says cannot open, not gone', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('receiver-decode-'),
    ))!;
    addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
    final file = File('${root.path}/broken.jpg');
    await tester.runAsync(() => file.writeAsBytes([0xff, 0xd8, 0xff, 0xe0]));
    var decoderRejected = false;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 200,
              child: MediaGridCell(
                attachment: MediaAttachment(
                  id: 'decode',
                  messageId: 'message',
                  mime: 'image/jpeg',
                  size: 4,
                  mediaType: 'image',
                  downloadStatus: kMediaDownloadStatusDone,
                  localPath: file.path,
                  ownerLane: MediaOwnerLane.direct,
                  createdAt: '2026-10-20T00:00:00Z',
                ),
              ),
            ),
          ),
        ),
      );
      final image = find.byType(Image).first;
      await precacheImage(
        tester.widget<Image>(image).image,
        tester.element(image),
        onError: (_, _) => decoderRejected = true,
      ).timeout(const Duration(seconds: 20));
    });
    await tester.pumpAndSettle();
    expect(decoderRejected, isTrue);
    expect(find.text("Couldn't open this file"), findsOneWidget);
    expect(find.text('No longer available'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'a voice source load failure replaces the dead player with cannot-open copy',
    (tester) async {
      final platform = JustAudioPlatform.instance as FakeJustAudioPlatform;
      platform.enqueueLoadFailure(
        PlatformException(code: '0', message: 'Source error'),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AudioPlayerWidget(
              attachment: MediaAttachment(
                id: 'audio-codec',
                messageId: 'message',
                mime: 'audio/mp4',
                size: 4,
                mediaType: 'audio',
                downloadStatus: kMediaDownloadStatusDone,
                localPath: '/test/received-but-unopenable.m4a',
                ownerLane: MediaOwnerLane.direct,
                createdAt: '2026-10-20T00:00:00Z',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(platform.loadedUris, hasLength(1));
      expect(find.text("Couldn't open this file"), findsOneWidget);
      expect(find.text('No longer available'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
