import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/direct_media_library_batch_delete.dart';
import 'package:flutter_app/features/conversation/application/received_media_action_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_shared_media_library_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/in_memory_message_repository.dart';
import '../domain/repositories/fake_media_attachment_repository.dart';
import '../domain/repositories/strict_direct_media_library_repository.dart';

const String kContactPeerId = '12D3KooWDeleteContactPeer';

/// Records every [MessageRepository.getMessage] materialization so the test
/// can distinguish the batch's one lookup per unique parent from the delete
/// use case's mandatory current-authority re-read.
class _RecordingMessageRepository extends InMemoryMessageRepository {
  final List<String> getMessageCalls = [];

  @override
  Future<ConversationMessage?> getMessage(String id) {
    getMessageCalls.add(id);
    return super.getMessage(id);
  }
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('direct_media_batch_del_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  String writeFile(String name) {
    final path = '${tempDir.path}/$name';
    File(path).writeAsBytesSync(const [1, 2, 3]);
    return path;
  }

  ConversationMessage makeParent(String id) {
    return ConversationMessage(
      id: id,
      contactPeerId: kContactPeerId,
      senderPeerId: kContactPeerId,
      text: 'parent $id',
      timestamp: '2026-07-09T10:00:00.000Z',
      status: 'delivered',
      isIncoming: true,
      createdAt: '2026-07-09T10:00:01.000Z',
    );
  }

  MediaAttachment makeRow({
    required String id,
    required String messageId,
    required String localPath,
    MediaOwnerLane? ownerLane = MediaOwnerLane.direct,
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: 'image/jpeg',
      size: 3,
      mediaType: 'image',
      localPath: localPath,
      downloadStatus: 'done',
      createdAt: '2026-07-09T10:00:02.000Z',
      ownerLane: ownerLane,
    );
  }

  DirectReceivedMediaActionIdentity identity(String messageId, String id) =>
      DirectReceivedMediaActionIdentity(messageId: messageId, attachmentId: id);

  testWidgets(
    'confirmed batch delete materializes unique direct parents and preserves partial failures',
    (tester) async {
      // ── Application tier: dedup, materialization, once-per-parent delete,
      // typed partial failures, sibling/export preservation.
      final messageRepo = _RecordingMessageRepository();
      final mediaRepo = FakeMediaAttachmentRepository();

      await messageRepo.saveMessage(makeParent('msg-a'));
      await messageRepo.saveMessage(makeParent('msg-unrelated'));
      // msg-b is deliberately ABSENT (deleted underneath the library page).

      final pathA1 = writeFile('a1.jpg');
      final pathA2 = writeFile('a2.jpg');
      final pathB1 = writeFile('b1.jpg');
      final pathGroupTwin = writeFile('a1-group-twin.jpg');
      final pathUnresolvedTwin = writeFile('a1-unresolved-twin.jpg');
      final exportedCopy = writeFile('a1-exported-to-photos.jpg');

      mediaRepo.seed([
        makeRow(id: 'att-a1', messageId: 'msg-a', localPath: pathA1),
        makeRow(id: 'att-a2', messageId: 'msg-a', localPath: pathA2),
        makeRow(id: 'att-b1', messageId: 'msg-b', localPath: pathB1),
        // Same-ID controls in sibling lanes: a group twin (group message ids
        // are table-local, so 'att-a1'/'msg-a' can legitimately collide) and
        // an unresolved legacy row. Both must survive untouched.
        makeRow(
          id: 'att-a1',
          messageId: 'msg-a',
          localPath: pathGroupTwin,
          ownerLane: MediaOwnerLane.group,
        ),
        makeRow(
          id: 'att-a1',
          messageId: 'msg-a',
          localPath: pathUnresolvedTwin,
          ownerLane: null,
        ),
      ]);

      // Real direct delete seam behind a recording wrapper: the production
      // whole-message deleteMessageForMe over the same fakes.
      final deleteCalls = <String>[];
      Future<int> recordingDelete(ConversationMessage message) {
        deleteCalls.add(message.id);
        return deleteMessageForMe(
          message: message,
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaRepo,
        );
      }

      final outcome = await deleteDirectMediaSelectionForMe(
        identities: [
          // TWO attachments of message A plus one of the now-missing B.
          identity('msg-a', 'att-a1'),
          identity('msg-a', 'att-a2'),
          identity('msg-b', 'att-b1'),
        ],
        messageRepo: messageRepo,
        deleteMessageForMe: recordingDelete,
      );

      // The batch materializes each UNIQUE parent once (A's two attachments do
      // not add lookups). The resolved parent is then re-read exactly once by
      // deleteMessageForMe so a stale ordinary snapshot cannot physically
      // delete a row that became private before the deletion claim.
      expect(messageRepo.getMessageCalls, ['msg-a', 'msg-a', 'msg-b']);
      expect(deleteCalls, ['msg-a']);

      // Typed outcome: B is a per-message failure whose attachment stays
      // selected; A's two attachments are reported deleted.
      expect(outcome.deletedMessageIds, {'msg-a'});
      expect(outcome.failedMessageIds, {'msg-b'});
      expect(outcome.deletedAttachmentIds, {'att-a1', 'att-a2'});
      expect(outcome.failedAttachmentIds, {'att-b1'});

      // The direct parent and its direct-owned rows are gone...
      expect(await messageRepo.getMessage('msg-a'), isNull);
      expect(
        await mediaRepo.getAttachmentsForMessage(
          'msg-a',
          owner: MediaOwnerLane.direct,
        ),
        isEmpty,
      );
      // ...while the same-ID group/unresolved rows and their files, the
      // unrelated message, and the exported copy all survive.
      final groupTwins = await mediaRepo.getAttachmentsForMessage(
        'msg-a',
        owner: MediaOwnerLane.group,
      );
      expect(groupTwins.map((r) => r.id).toList(), ['att-a1']);
      expect(File(pathGroupTwin).existsSync(), isTrue);
      expect(File(pathUnresolvedTwin).existsSync(), isTrue);
      expect(await messageRepo.getMessage('msg-unrelated'), isNotNull);
      expect(File(exportedCopy).existsSync(), isTrue);
      // No delete-for-everyone/network seam even exists on this function:
      // it takes only the message repository and the local delete seam.

      // ── Widget tier: the explicit confirmation surface. Cancel = zero
      // dispatches; confirm dispatches ONCE and failed attachments stay
      // selected while deleted parents leave the grid.
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final libraryRepo = StrictDirectMediaLibraryRepository(
        expectedContactPeerId: kContactPeerId,
      );
      libraryRepo.seedPage(
        entries: [
          makeDirectLibraryEntry(
            'att-a1',
            contactPeerId: kContactPeerId,
            messageId: 'msg-a',
            localPath: 'media/a1.jpg',
          ),
          makeDirectLibraryEntry(
            'att-a2',
            contactPeerId: kContactPeerId,
            messageId: 'msg-a',
            localPath: 'media/a2.jpg',
          ),
          makeDirectLibraryEntry(
            'att-b1',
            contactPeerId: kContactPeerId,
            messageId: 'msg-b',
            localPath: 'media/b1.jpg',
          ),
        ],
        nextCursor: null,
      );

      final dispatches = <List<DirectReceivedMediaActionIdentity>>[];
      final deletedNotifications = <Set<String>>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DirectSharedMediaLibraryScreen(
            contactPeerId: kContactPeerId,
            contactUsername: 'Alice',
            libraryRepository: libraryRepo,
            stateRepository: libraryRepo,
            fileExists: (_) => true,
            resolveStoredPath: (storedPath) => storedPath,
            dispatchDelete: (identities) async {
              dispatches.add(identities);
              return const DirectMediaLibraryBatchDeleteOutcome(
                deletedMessageIds: {'msg-a'},
                failedMessageIds: {'msg-b'},
                deletedAttachmentIds: {'att-a1', 'att-a2'},
                failedAttachmentIds: {'att-b1'},
              );
            },
            onMessagesDeleted: deletedNotifications.add,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      for (final id in const ['att-a1', 'att-a2', 'att-b1']) {
        await tester.longPress(find.byKey(ValueKey('shared-media-tile-$id')));
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.text('3 selected'), findsOneWidget);

      // Cancel: the explicit confirmation names the UNIQUE parent count and
      // cancelling performs zero lookups/deletes.
      await tester.tap(
        find.byKey(const ValueKey('shared-media-action-delete')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Delete 2 messages?'), findsOneWidget);
      expect(
        find.textContaining('entire message'),
        findsOneWidget,
        reason:
            'the copy must state whole messages and all attachments are '
            'removed locally',
      );
      await tester.tap(
        find.byKey(const ValueKey('shared-media-delete-cancel')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(dispatches, isEmpty);
      expect(find.text('3 selected'), findsOneWidget);

      // Confirm: exactly one dispatch with the full selection; deleted
      // parents leave the grid, the failed attachment stays selected.
      await tester.tap(
        find.byKey(const ValueKey('shared-media-action-delete')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.byKey(const ValueKey('shared-media-delete-confirm')),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(dispatches, hasLength(1));
      expect(dispatches.single.map((i) => i.attachmentId).toSet(), {
        'att-a1',
        'att-a2',
        'att-b1',
      });
      expect(deletedNotifications, [
        {'msg-a'},
      ]);
      expect(
        find.byKey(const ValueKey('shared-media-tile-att-a1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('shared-media-tile-att-a2')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('shared-media-tile-att-b1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('shared-media-selected-att-b1')),
        findsOneWidget,
        reason: 'the failed attachment stays selected for truthful retry',
      );
      expect(find.text('1 selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
