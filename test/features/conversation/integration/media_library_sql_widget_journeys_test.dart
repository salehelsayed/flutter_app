import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_gateway.dart';
import 'package:flutter_app/core/media/received_media_egress_service.dart';
import 'package:flutter_app/features/conversation/application/direct_media_library_batch_actions.dart';
import 'package:flutter_app/features/conversation/application/build_direct_media_library_batch_forward.dart';
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/direct_media_library_batch_delete.dart';
import 'package:flutter_app/features/conversation/application/received_media_action_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_shared_media_library_screen.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/direct_received_media_action_sheet.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_shared_media_library_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

// Current production SQL, actual files, library widgets and batch coordinators.
// Only the native export destination is replaced; no device decode/export is
// claimed by this host journey.
class _Destination implements ReceivedMediaEgressGateway {
  final requests = <MediaEgressRequest>[];
  final failures = <String>{};
  final hashes = <List<String>>[];

  @override
  Future<MediaEgressResult> perform(MediaEgressRequest request) async {
    requests.add(request);
    hashes.add([
      for (final item in request.items)
        sha256.convert(File(item.sourcePath).readAsBytesSync()).toString(),
    ]);
    return MediaEgressResult(
      requestId: request.requestId,
      outcome: failures.isEmpty
          ? MediaEgressOutcome.saved
          : MediaEgressOutcome.partial,
      items: [
        for (final item in request.items)
          MediaEgressItemResult(
            attachmentId: item.attachmentId,
            outcome: failures.contains(item.attachmentId)
                ? MediaEgressItemOutcome.platformFailure
                : MediaEgressItemOutcome.saved,
          ),
      ],
    );
  }
}

void main() {
  late Directory root;
  late File image;
  late MediaRepositoryRealDbFixture fixture;
  late String digest;
  String? previousCache;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('library-sql-widget-');
    image = File('${root.path}/media/contact/image.png');
    image.parent.createSync(recursive: true);
    image.writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAEAAAAAgCAIAAAAt/+nTAAAATklEQVR4nO3PUQkAIBTAwNfAfmY3jCH8OITBAtxm7fN1wwUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjx2AV3NKJdv7voVAAAAAElFTkSuQmCC',
      ),
    );
    digest = sha256.convert(image.readAsBytesSync()).toString();
    previousCache = MediaFileManager.cachedDocumentsDir;
    MediaFileManager.cacheDocumentsDir(root.path);
    fixture = await MediaRepositoryRealDbFixture.create(
      databasePath: '${root.path}/identity.db',
      databaseFactoryOverride: databaseFactoryFfiNoIsolate,
    );
  });
  tearDown(() async {
    await fixture.dispose();
    MediaFileManager.debugResetDocumentsDirCache();
    if (previousCache != null) {
      MediaFileManager.cacheDocumentsDir(previousCache!);
    }
    root.deleteSync(recursive: true);
  });

  Future<void> seed(
    String id, {
    bool group = false,
    bool foreign = false,
    bool deleted = false,
    bool bookmarked = false,
  }) async {
    final parent = 'parent-$id';
    if (group) {
      await fixture.seedGroupParent(
        parent,
        groupId: foreign ? 'foreign-group' : 'group-1',
      );
    } else {
      await fixture.seedDirectParent(
        parent,
        contactPeerId: foreign ? 'foreign-contact' : 'contact-1',
        deletedAt: deleted ? '2026-07-02T00:00:00Z' : null,
      );
    }
    final groupFile = File(
      '${root.path}/media/${foreign ? 'foreign-group' : 'group-1'}/$id.png',
    );
    if (group) {
      groupFile.parent.createSync(recursive: true);
      groupFile.writeAsBytesSync(image.readAsBytesSync());
    }
    await fixture.repo.saveAttachment(
      MediaAttachment(
        id: id,
        messageId: parent,
        mime: 'image/png',
        size: image.lengthSync(),
        mediaType: 'image',
        localPath: group ? groupFile.path : image.path,
        downloadStatus: 'done',
        createdAt: '2026-07-01T00:00:00.000Z',
        contentHash: digest,
        encryptionKeyBase64: group ? 'c3ludGhldGljLWZpeHR1cmUta2V5' : null,
        encryptionNonce: group ? 'c3ludGhldGljLW5vbmNl' : null,
        encryptionScheme: group ? 'blob_aes_256_gcm_v1' : null,
        ownerLane: group ? MediaOwnerLane.group : MediaOwnerLane.direct,
        isBookmarked: bookmarked,
      ),
      owner: group ? MediaOwnerLane.group : MediaOwnerLane.direct,
    );
  }

  Widget app(Widget home) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  Future<void> settle(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 200 && !ready(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(
      ready(),
      isTrue,
      reason: 'SQL-backed widget must finish its actual query',
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final group in [false, true]) {
    testWidgets(
      'MEDIA-025 ${group ? 'group' : 'direct'} SQL reopen pages tied identities and opens the bookmarked file in the real library viewer',
      (tester) async {
        await tester.runAsync(() async {
          for (var i = 0; i < 52; i++) {
            await seed(
              'visible-${i.toString().padLeft(3, '0')}',
              group: group,
              bookmarked: i == 51,
            );
          }
          await seed('foreign', group: group, foreign: true);
          if (!group) await seed('deleted', deleted: true);
          // A sibling lane shares the same file but must never leak into scope.
          await seed('sibling-lane', group: !group);
          fixture = await fixture.reopen();
          final scope = group
              ? const MediaLibraryScope.group('group-1')
              : const MediaLibraryScope.direct('contact-1');
          final first = await fixture.repo.getMediaLibraryPage(
            scope: scope,
            filter: const MediaLibraryFilter(),
            limit: 50,
          );
          final next = await fixture.repo.getMediaLibraryPage(
            scope: scope,
            filter: const MediaLibraryFilter(),
            limit: 50,
            cursor: first.nextCursor,
          );
          expect(first.entries, hasLength(50));
          expect(next.entries, hasLength(2));
          expect(next.nextCursor, isNull);
          expect(
            [...first.entries, ...next.entries].map((e) => e.attachment.id),
            [
              for (var i = 51; i >= 0; i--)
                'visible-${i.toString().padLeft(3, '0')}',
            ],
          );
        });
        await tester.pumpWidget(app(const SizedBox.shrink()));
        final selectedFile = group
            ? File('${root.path}/media/group-1/visible-051.png')
            : image;
        await tester.runAsync(
          () => precacheImage(
            FileImage(selectedFile),
            tester.element(find.byType(SizedBox).first),
          ).timeout(const Duration(seconds: 10)),
        );
        await tester.pumpWidget(
          app(
            group
                ? GroupSharedMediaLibraryScreen(
                    groupId: 'group-1',
                    libraryRepository: fixture.repo,
                    stateRepository: fixture.repo,
                  )
                : DirectSharedMediaLibraryScreen(
                    contactPeerId: 'contact-1',
                    contactUsername: 'Alice',
                    libraryRepository: fixture.repo,
                    stateRepository: fixture.repo,
                    resolveStoredPath: (p) => p,
                  ),
          ),
        );
        final prefix = group ? 'group-shared-media' : 'shared-media';
        final tile = find.byKey(ValueKey('$prefix-tile-visible-051'));
        await settle(tester, () => tile.evaluate().isNotEmpty);
        await tester.tap(find.byKey(ValueKey('$prefix-filter-bookmarked')));
        await settle(
          tester,
          () =>
              tile.evaluate().isNotEmpty &&
              find
                  .byKey(ValueKey('$prefix-tile-visible-050'))
                  .evaluate()
                  .isEmpty,
        );
        expect(find.byKey(ValueKey('$prefix-tile-visible-050')), findsNothing);
        await tester.tap(tile);
        await settle(
          tester,
          () => find.byType(FullScreenTypedMediaViewer).evaluate().isNotEmpty,
        );
        final viewer = tester.widget<FullScreenTypedMediaViewer>(
          find.byType(FullScreenTypedMediaViewer),
        );
        final current = viewer.items[viewer.initialIndex];
        expect(
          (current.attachmentId, current.messageId, current.owner),
          (
            'visible-051',
            'parent-visible-051',
            group ? MediaOwnerLane.group : MediaOwnerLane.direct,
          ),
        );
        expect(current.localPath, selectedFile.path);
        expect(viewer.items, hasLength(1));
        expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
        await tester.pageBack();
        await settle(
          tester,
          () =>
              tile.evaluate().isNotEmpty &&
              find.byType(FullScreenTypedMediaViewer).evaluate().isEmpty,
        );
        expect(tile, findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  test(
    'MEDIA-026 SQL forward snapshots keep per-source captions tokens and bytes; bookmark and local delete affect exact parents',
    () async {
      for (final id in ['source-a', 'source-b', 'unrelated']) {
        await seed(id);
      }
      await seed('group-preserved', group: true);
      await fixture.db.update(
        'messages',
        {'text': 'First caption'},
        where: 'id = ?',
        whereArgs: ['parent-source-a'],
      );
      await fixture.db.update(
        'messages',
        {'text': 'Second caption'},
        where: 'id = ?',
        whereArgs: ['parent-source-b'],
      );
      final identities = [
        for (final id in ['source-a', 'source-b'])
          DirectReceivedMediaActionIdentity(
            messageId: 'parent-$id',
            attachmentId: id,
          ),
      ];
      var tokens = 0;
      BuildDirectMediaLibraryBatchForward builder() =>
          BuildDirectMediaLibraryBatchForward(
            loadParentMessage: fixture.messageRepo.getMessage,
            mediaAttachmentRepository: fixture.repo,
            resolveStoredPath: (p) => p,
            operationTokenFactory: () => 'fixture-operation-${++tokens}',
          );
      final initial = await builder().build(
        contactPeerId: 'contact-1',
        identities: identities,
      );
      expect(initial.isReady, isTrue);
      final originals = {
        for (final item in initial.draft!.items)
          item.identity.attachmentId: (
            item.caption,
            item.forwardProvenance.operationDedupKey,
          ),
      };
      expect(originals['source-a']!.$1, 'First caption');
      expect(originals['source-b']!.$1, 'Second caption');
      expect(originals.values.map((v) => v.$2).toSet(), hasLength(2));
      expect(
        await fixture.repo.setDirectBookmarkedIfOrdinary(
          messageId: 'parent-source-a',
          attachmentId: 'source-a',
          bookmarked: true,
        ),
        isTrue,
      );
      fixture = await fixture.reopen();
      final refreshed = await builder().revalidateForDispatch(
        contactPeerId: 'contact-1',
        draft: initial.draft!,
      );
      expect(refreshed.isReady, isTrue);
      expect(
        tokens,
        2,
        reason: 'revalidation must not remint operation tokens',
      );
      for (final item in refreshed.draft!.items) {
        expect((
          item.caption,
          item.forwardProvenance.operationDedupKey,
        ), originals[item.identity.attachmentId]);
        expect(
          sha256.convert(File(item.resolvedPath).readAsBytesSync()).toString(),
          digest,
        );
      }
      final bookmarked = await fixture.repo.getMediaLibraryPage(
        scope: const MediaLibraryScope.direct('contact-1'),
        filter: const MediaLibraryFilter(bookmarkedOnly: true),
        limit: 50,
      );
      expect(bookmarked.entries.map((e) => e.attachment.id), ['source-a']);
      final deleted = <String>[];
      final outcome = await deleteDirectMediaSelectionForMe(
        identities: [identities.first],
        messageRepo: fixture.messageRepo,
        deleteMessageForMe: (parent) {
          deleted.add(parent.id);
          return deleteMessageForMe(
            message: parent,
            messageRepo: fixture.messageRepo,
            mediaAttachmentRepo: fixture.repo,
          );
        },
      );
      expect(deleted, ['parent-source-a']);
      expect(outcome.deletedMessageIds, {'parent-source-a'});
      expect(outcome.deletedAttachmentIds, {'source-a'});
      expect(await fixture.messageRepo.getMessage('parent-source-a'), isNull);
      expect(
        await fixture.messageRepo.getMessage('parent-source-b'),
        isNotNull,
      );
      expect(
        await fixture.messageRepo.getMessage('parent-unrelated'),
        isNotNull,
      );
      expect(
        await fixture.repo.getAttachmentsForMessage(
          'parent-group-preserved',
          owner: MediaOwnerLane.group,
        ),
        hasLength(1),
      );
      final stale = await builder().revalidateForDispatch(
        contactPeerId: 'contact-1',
        draft: initial.draft!,
      );
      expect(stale.isReady, isFalse);
      expect(stale.draft, isNull);
      expect(
        image.existsSync(),
        isTrue,
        reason:
            'this local database-delete leg has no file-manager/export owner',
      );
    },
  );

  testWidgets(
    'MEDIA-026 real SQL selection requalifies a privacy race and retries only failed native-boundary items',
    (tester) async {
      await tester.runAsync(() async {
        for (final id in [
          'selected-a',
          'selected-b',
          'selected-stale',
          'unselected',
        ]) {
          await seed(id);
        }
        await seed('group-sibling', group: true);
      });
      final destination = _Destination()..failures.add('selected-b');
      final service = ReceivedMediaEgressService(
        gateway: destination,
        resolveStoredPath: (path) async => path,
        documentsDirectory: () async => root,
      );
      final coordinator = DirectMediaLibraryBatchActionsCoordinator(
        loadParentMessage: fixture.messageRepo.getMessage,
        mediaAttachmentRepo: fixture.repo,
        egressService: service,
        resolveStoredPath: (p) => p,
      );
      final dispatches = <List<DirectReceivedMediaActionIdentity>>[];
      await tester.pumpWidget(
        app(
          DirectSharedMediaLibraryScreen(
            contactPeerId: 'contact-1',
            contactUsername: 'Alice',
            libraryRepository: fixture.repo,
            stateRepository: fixture.repo,
            resolveStoredPath: (p) => p,
            dispatchEgress: (identities, target) async {
              dispatches.add(identities);
              return coordinator.performBatchEgress(
                identities: identities,
                destination: target,
              );
            },
          ),
        ),
      );
      final tile = find.byKey(const ValueKey('shared-media-tile-selected-a'));
      await settle(tester, () => tile.evaluate().isNotEmpty);
      for (final id in ['selected-a', 'selected-b', 'selected-stale']) {
        await tester.longPress(find.byKey(ValueKey('shared-media-tile-$id')));
        await tester.pump();
      }
      expect(find.text('3 selected'), findsOneWidget);
      await tester.runAsync(
        () => fixture.db.update(
          'messages',
          {
            'private_media_policy_version': 1,
            'private_media_mode': 'view_once',
            'private_media_state': 'available',
            'private_media_received_at_ms': 1000,
          },
          where: 'id = ?',
          whereArgs: ['parent-selected-stale'],
        ),
      );
      Future<void> save() async {
        await tester.tap(
          find.byKey(const ValueKey('shared-media-action-save')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(DirectMediaSaveDestinationSheet.filesActionKey),
        );
      }

      await save();
      await settle(tester, () => find.text('2 selected').evaluate().isNotEmpty);
      expect(destination.requests, hasLength(1));
      expect(destination.requests.single.items.map((i) => i.attachmentId), [
        'selected-a',
        'selected-b',
      ]);
      expect(destination.hashes.single, [digest, digest]);
      expect(dispatches.single.map((i) => (i.messageId, i.attachmentId)), [
        ('parent-selected-a', 'selected-a'),
        ('parent-selected-b', 'selected-b'),
        ('parent-selected-stale', 'selected-stale'),
      ]);
      // Let the truthful partial-result notice leave the action bar before
      // the next real tap; it otherwise overlays Save in the short viewport.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      destination.failures.clear();
      await save();
      await settle(tester, () => find.text('1 selected').evaluate().isNotEmpty);
      expect(destination.requests, hasLength(2));
      expect(destination.requests.last.items.map((i) => i.attachmentId), [
        'selected-b',
      ]);
      expect(dispatches.last.map((i) => i.attachmentId), [
        'selected-b',
        'selected-stale',
      ]);
      expect(image.existsSync(), isTrue);
      expect(sha256.convert(image.readAsBytesSync()).toString(), digest);
      await tester.runAsync(() async {
        expect(
          await fixture.repo.getAttachmentsForMessage(
            'parent-group-sibling',
            owner: MediaOwnerLane.group,
          ),
          hasLength(1),
        );
        expect(
          await fixture.repo.getAttachmentsForMessage(
            'parent-unselected',
            owner: MediaOwnerLane.direct,
          ),
          hasLength(1),
        );
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
