import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_storage_manager.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/settings/presentation/widgets/media_storage_usage_section.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../shared/fixtures/media_repository_real_db_fixture.dart';

void main() {
  testWidgets(
    'SETTINGS-009 measure clear and refresh use actual local bytes per conversation',
    (tester) async {
      final docs = Directory.systemTemp.createTempSync('astra-storage-widget-');
      final fixture = await tester.runAsync(
        () => MediaRepositoryRealDbFixture.create(
          databaseFactoryOverride: databaseFactoryFfiNoIsolate,
        ),
      );
      final db = fixture!;
      addTearDown(() async {
        await db.dispose();
        docs.deleteSync(recursive: true);
      });
      final files = <String, File>{};
      await tester.runAsync(() async {
        await db.seedDirectParent('message-a', contactPeerId: 'contact-a');
        await db.seedDirectParent('message-b', contactPeerId: 'contact-b');
        for (final sample in const [
          ('photo-a', 'contact-a', 'image', 'image/jpeg', 'jpg', 1024),
          ('photo-b', 'contact-a', 'image', 'image/jpeg', 'jpg', 2048),
          ('audio-a', 'contact-a', 'audio', 'audio/mp4', 'm4a', 512),
          ('photo-sibling', 'contact-b', 'image', 'image/jpeg', 'jpg', 4096),
        ]) {
          final relative = 'media/${sample.$2}/${sample.$1}.${sample.$5}';
          final file = File('${docs.path}/$relative');
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(List.filled(sample.$6, 7));
          files[sample.$1] = file;
          await db.repo.saveAttachment(
            MediaAttachment(
              id: sample.$1,
              messageId: sample.$2 == 'contact-a' ? 'message-a' : 'message-b',
              mime: sample.$4,
              size:
                  999999, // Descriptor size must not substitute for actual bytes.
              mediaType: sample.$3,
              localPath: relative,
              downloadStatus: 'done',
              createdAt: '2026-10-01T00:00:00.000Z',
            ),
            owner: MediaOwnerLane.direct,
          );
        }
        await db.repo.saveAttachment(
          const MediaAttachment(
            id: 'missing-file',
            messageId: 'message-a',
            mime: 'image/jpeg',
            size: 888888,
            mediaType: 'image',
            localPath: 'media/contact-a/missing-file.jpg',
            downloadStatus: 'done',
            createdAt: '2026-10-01T00:00:00.000Z',
          ),
          owner: MediaOwnerLane.direct,
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MediaStorageUsageSection(
                manager: MediaStorageManager(
                  repository: db.repo,
                  documentsDirectoryProvider: () async => docs.path,
                ),
                loadScopes: () async => const [
                  MediaStorageScopeOption(
                    scope: MediaLibraryScope.direct('contact-a'),
                    label: 'Chat A',
                  ),
                  MediaStorageScopeOption(
                    scope: MediaLibraryScope.direct('contact-b'),
                    label: 'Chat B',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Show usage'), findsNWidgets(2));
      expect(find.textContaining('KB'), findsNothing);

      Future<void> activate(String key, bool Function() ready) async {
        await tester.tap(find.byKey(ValueKey(key)));
        for (var i = 0; i < 200; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 10));
          if (ready()) return;
        }
        fail('Storage action did not reach its visible completion: $key');
      }

      await activate(
        'media-storage-measure-direct/contact-a',
        () => find.text('Photos · 2 · 3.0 KB').evaluate().isNotEmpty,
      );
      expect(find.text('Photos · 2 · 3.0 KB'), findsOneWidget);
      expect(find.text('Audio · 1 · 512 B'), findsOneWidget);
      expect(find.text('Show usage'), findsOneWidget);
      await activate(
        'media-storage-clear-direct/contact-a-image',
        () =>
            !files['photo-a']!.existsSync() &&
            !files['photo-b']!.existsSync() &&
            find.text('Photos · 2 · 3.0 KB').evaluate().isEmpty,
      );
      expect(find.text('Photos · 2 · 3.0 KB'), findsNothing);
      expect(find.text('Audio · 1 · 512 B'), findsOneWidget);
      expect(files['photo-a']!.existsSync(), isFalse);
      expect(files['photo-b']!.existsSync(), isFalse);
      expect(files['audio-a']!.existsSync(), isTrue);
      expect(files['photo-sibling']!.lengthSync(), 4096);
      await tester.runAsync(() async {
        for (final id in ['photo-a', 'photo-b']) {
          final attachment = await db.repo.getAttachmentById(id);
          expect(attachment!.downloadStatus, 'evicted');
          expect(attachment.localPath, isNull);
        }
        expect(await db.db.query('messages'), hasLength(2));
      });
      await activate(
        'media-storage-clear-direct/contact-a-audio',
        () => find.text('No downloaded media copies').evaluate().isNotEmpty,
      );
      expect(find.text('No downloaded media copies'), findsOneWidget);
      expect(files['audio-a']!.existsSync(), isFalse);
      expect(files['photo-sibling']!.lengthSync(), 4096);
      await activate(
        'media-storage-measure-direct/contact-b',
        () => find.text('Photos · 1 · 4.0 KB').evaluate().isNotEmpty,
      );
      expect(find.text('Photos · 1 · 4.0 KB'), findsOneWidget);
      expect(find.text('No downloaded media copies'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
