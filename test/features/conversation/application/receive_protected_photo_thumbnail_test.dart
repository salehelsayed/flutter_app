import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_message_deletion_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/message_deletion_payload.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

const _thumbnailKey = 'thumbnailInlineBase64';
const _senderPeerId = '12D3KooWThumbReceiveSender';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.docsPath);

  final String docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

void main() {
  late Directory tempDocs;
  late MediaRepositoryRealDbFixture fixture;
  late InMemoryContactRepository contactRepo;
  late MediaFileManager mediaFileManager;
  var timestampCounter = 0;

  setUp(() async {
    tempDocs = Directory.systemTemp.createTempSync('protected_thumb_receive_');
    PathProviderPlatform.instance = _FakePathProvider(tempDocs.path);
    fixture = await MediaRepositoryRealDbFixture.create();
    contactRepo = InMemoryContactRepository()
      ..addTestContact(_contact(_senderPeerId));
    mediaFileManager = MediaFileManager();
  });

  tearDown(() async {
    await fixture.dispose();
    if (tempDocs.existsSync()) {
      tempDocs.deleteSync(recursive: true);
    }
  });

  String nextTimestamp() =>
      '2026-07-29T10:00:${(timestampCounter++).toString().padLeft(2, '0')}.000Z';

  String validThumbnailBase64() =>
      base64Encode(img.encodeJpg(img.Image(width: 12, height: 12)));

  ChatMessage incomingProtectedPhoto({
    required String messageId,
    required String attachmentId,
    String senderPeerId = _senderPeerId,
    String mime = 'image/jpeg',
    String mediaType = 'image',
    String mode = 'protected',
    String? timestamp,
    String? thumbnailInlineBase64,
  }) {
    final resolvedTimestamp = timestamp ?? nextTimestamp();
    final inner = <String, Object?>{
      'id': messageId,
      'text': '',
      'senderPeerId': senderPeerId,
      'senderUsername': 'ThumbSender',
      'timestamp': resolvedTimestamp,
      'media': [
        <String, Object?>{
          'id': attachmentId,
          'mime': mime,
          'size': 42,
          'mediaType': mediaType,
          'contentHash':
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'encryptionKeyBase64': base64Encode(utf8.encode('thumb-recv-key')),
          'encryptionNonce': base64Encode(utf8.encode('thumb-recv-nonce')),
          'encryptionScheme': 'blob_aes_256_gcm_v1',
          _thumbnailKey: ?thumbnailInlineBase64,
        },
      ],
      if (mode != 'ordinary') 'privateMedia': {'version': 1, 'mode': mode},
    };
    final envelope = MessagePayload.buildEncryptedEnvelope(
      id: messageId,
      senderPeerId: senderPeerId,
      senderUsername: 'ThumbSender',
      kem: 'opaque-kem',
      ciphertext: 'opaque-ciphertext',
      nonce: 'opaque-nonce',
    );
    return ChatMessage(
      from: senderPeerId,
      to: 'me',
      content: envelope,
      timestamp: resolvedTimestamp,
      isIncoming: true,
      transport: 'direct',
      predecryptedText: jsonEncode(inner),
    );
  }

  Future<(HandleChatMessageResult, dynamic, dynamic)> receive(
    ChatMessage message,
  ) => handleIncomingChatMessage(
    message: message,
    messageRepo: fixture.messageRepo,
    contactRepo: contactRepo,
    predecryptedText: message.predecryptedText,
    mediaAttachmentRepo: fixture.repo,
    mediaFileManager: mediaFileManager,
    transport: 'direct',
  );

  Future<String> expectedThumbnailPath({
    required String contactPeerId,
    required String blobId,
  }) => mediaFileManager.resolveStoredPath(
    MediaFilePathConvention.relativeThumbnailPathForAttachment(
      contactPeerId: contactPeerId,
      blobId: blobId,
    ),
  );

  List<File> thumbnailFilesUnder(Directory root) => root
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.thumb.jpg'))
      .toList();

  test(
    'incoming inline thumbnail persists once to the guarded sibling path',
    () async {
      const messageId = 'thumb-receive-valid';
      const attachmentId = 'thumb-receive-valid-att';
      final inline = validThumbnailBase64();

      final (result, stored, _) = await receive(
        incomingProtectedPhoto(
          messageId: messageId,
          attachmentId: attachmentId,
          timestamp: '2026-07-29T09:59:00.000Z',
          thumbnailInlineBase64: inline,
        ),
      );

      expect(result, HandleChatMessageResult.chatMessage);
      // The file lands at the path derived from the SAME row identifiers the
      // attachment row persisted with.
      final path = await expectedThumbnailPath(
        contactPeerId: _senderPeerId,
        blobId: attachmentId,
      );
      final thumbFile = File(path);
      expect(
        thumbFile.existsSync(),
        isTrue,
        reason: 'the guarded sibling thumbnail file must exist after receive',
      );
      expect(base64Encode(thumbFile.readAsBytesSync()), inline);

      // Nothing thumbnail-shaped lands in the DB: scan every column of the
      // persisted message + attachment row maps for the exact inline value
      // (encryption key/nonce are legitimately base64 — scan for this value).
      final attachmentRow = await fixture.rawAttachmentRow(attachmentId);
      expect(attachmentRow, isNotNull);
      for (final entry in attachmentRow!.entries) {
        expect(
          '${entry.value}',
          isNot(contains(inline)),
          reason: 'attachment column ${entry.key}',
        );
      }
      final messageRows = await fixture.db.query(
        'messages',
        where: 'id = ?',
        whereArgs: [messageId],
      );
      expect(messageRows, hasLength(1));
      for (final entry in messageRows.single.entries) {
        expect(
          '${entry.value}',
          isNot(contains(inline)),
          reason: 'message column ${entry.key}',
        );
      }

      // Idempotent on replay: same payload again is a duplicate and the file is
      // written exactly once.
      final before = thumbFile.lastModifiedSync();
      final (replayResult, _, _) = await receive(
        incomingProtectedPhoto(
          messageId: messageId,
          attachmentId: attachmentId,
          timestamp: '2026-07-29T09:59:00.000Z',
          thumbnailInlineBase64: inline,
        ),
      );
      expect(replayResult, HandleChatMessageResult.duplicate);
      expect(thumbFile.existsSync(), isTrue);
      expect(
        thumbFile.lastModifiedSync(),
        before,
        reason: 'replay must not rewrite the thumbnail file',
      );
      expect(base64Encode(thumbFile.readAsBytesSync()), inline);
    },
  );

  test(
    'malformed oversized or non-protected inline thumbnails are discarded and the message still lands',
    () async {
      final cases = <String, ChatMessage>{
        'malformed base64': incomingProtectedPhoto(
          messageId: 'thumb-bad-base64',
          attachmentId: 'thumb-bad-base64-att',
          thumbnailInlineBase64: '!!!not-base64!!!',
        ),
        'oversized raw payload': incomingProtectedPhoto(
          messageId: 'thumb-oversized',
          attachmentId: 'thumb-oversized-att',
          thumbnailInlineBase64: base64Encode(List<int>.filled(49153, 7)),
        ),
        'ordinary mode': incomingProtectedPhoto(
          messageId: 'thumb-ordinary-mode',
          attachmentId: 'thumb-ordinary-mode-att',
          mode: 'ordinary',
          thumbnailInlineBase64: validThumbnailBase64(),
        ),
        'view-once mode': incomingProtectedPhoto(
          messageId: 'thumb-view-once-mode',
          attachmentId: 'thumb-view-once-mode-att',
          mode: 'view_once',
          thumbnailInlineBase64: validThumbnailBase64(),
        ),
        'protected gif (dual check)': incomingProtectedPhoto(
          messageId: 'thumb-protected-gif',
          attachmentId: 'thumb-protected-gif-att',
          mime: 'image/gif',
          mediaType: 'gif',
          thumbnailInlineBase64: base64Encode(
            img.encodeGif(img.Image(width: 6, height: 6)),
          ),
        ),
        'protected video': incomingProtectedPhoto(
          messageId: 'thumb-protected-video',
          attachmentId: 'thumb-protected-video-att',
          mime: 'video/mp4',
          mediaType: 'video',
          thumbnailInlineBase64: validThumbnailBase64(),
        ),
      };

      for (final entry in cases.entries) {
        final (result, _, _) = await receive(entry.value);
        expect(
          result,
          HandleChatMessageResult.chatMessage,
          reason: '${entry.key}: the message itself must still land',
        );
      }
      expect(
        thumbnailFilesUnder(tempDocs),
        isEmpty,
        reason: 'no discarded input may produce a thumbnail file',
      );
    },
  );

  test(
    'a traversal attachment or peer id writes no file anywhere and the message still lands',
    () async {
      final (attachmentResult, _, _) = await receive(
        incomingProtectedPhoto(
          messageId: 'thumb-traversal-attachment',
          attachmentId: '../../databases/evil',
          thumbnailInlineBase64: validThumbnailBase64(),
        ),
      );
      expect(attachmentResult, HandleChatMessageResult.chatMessage);

      const hostilePeer = '..';
      contactRepo.addTestContact(_contact(hostilePeer));
      final (peerResult, _, _) = await receive(
        incomingProtectedPhoto(
          messageId: 'thumb-traversal-peer',
          attachmentId: 'thumb-traversal-peer-att',
          senderPeerId: hostilePeer,
          thumbnailInlineBase64: validThumbnailBase64(),
        ),
      );
      expect(peerResult, HandleChatMessageResult.chatMessage);

      expect(thumbnailFilesUnder(tempDocs), isEmpty);
      // Nothing may escape or target the databases directory either.
      final evil = tempDocs
          .listSync(recursive: true, followLinks: false)
          .where((entity) => entity.path.contains('evil'));
      expect(evil, isEmpty);
      expect(
        tempDocs.parent.listSync().whereType<File>().where(
          (file) => file.path.endsWith('.thumb.jpg'),
        ),
        isEmpty,
      );
    },
  );

  test('replay after delete-for-me does not recreate the thumbnail', () async {
    const messageId = 'thumb-replay-after-delete';
    const attachmentId = 'thumb-replay-after-delete-att';
    const timestamp = '2026-07-29T09:58:00.000Z';
    final inline = validThumbnailBase64();

    final (result, _, _) = await receive(
      incomingProtectedPhoto(
        messageId: messageId,
        attachmentId: attachmentId,
        timestamp: timestamp,
        thumbnailInlineBase64: inline,
      ),
    );
    expect(result, HandleChatMessageResult.chatMessage);
    final path = await expectedThumbnailPath(
      contactPeerId: _senderPeerId,
      blobId: attachmentId,
    );
    expect(File(path).existsSync(), isTrue);

    // Seed the REAL hidden tombstone the delete-for-me flow writes, then wipe
    // the artifact the way the lifecycle cleanup does (the wipe path itself is
    // proven by the thumbnail wipe suite).
    final hidden = await fixture.messageRepo.hidePrivateMediaForMe(
      messageId,
      hiddenAt: '2026-07-29T10:30:00.000Z',
      nowMs: DateTime.parse('2026-07-29T10:30:00.000Z').millisecondsSinceEpoch,
    );
    expect(hidden, isTrue);
    File(path).deleteSync();

    final (replayResult, _, _) = await receive(
      incomingProtectedPhoto(
        messageId: messageId,
        attachmentId: attachmentId,
        timestamp: timestamp,
        thumbnailInlineBase64: inline,
      ),
    );
    expect(replayResult, HandleChatMessageResult.duplicate);
    expect(
      File(path).existsSync(),
      isFalse,
      reason: 'a replay of a deleted message must not resurrect the thumbnail',
    );
    expect(thumbnailFilesUnder(tempDocs), isEmpty);
  });

  group('Plan 354 strict protected thumbnail', () {
    test('TC-354-04d strict protected thumbnail follows custody and stays '
        'cleanup-owned', () {
      final receiver = File(
        'lib/features/conversation/application/'
        'handle_incoming_chat_message_use_case.dart',
      ).readAsStringSync();
      final lifecycle = File(
        'lib/features/conversation/application/'
        'direct_private_media_lifecycle.dart',
      ).readAsStringSync();

      // 1. On the strict lane the thumbnail write happens AFTER the atomic
      //    custody transaction and AFTER the post-stage terminal re-read, so
      //    terminal cleanup can never be followed by a stale sibling.
      final stage = receiver.indexOf(
        'stageIncomingDirectPrivateMediaBlobCustody(',
      );
      final terminalReread = receiver.indexOf(
        'final durableParent = await messageRepo.getMessage(strictMessageId);',
      );
      final strictThumbnail = receiver.indexOf(
        'if (mediaFileManager != null && (strictRawMedia?.length ?? 0) == 1)',
      );
      final markerStage = receiver.indexOf(
        'await stageNotificationDisplayCustody?.call(conversationMessage);',
      );
      expect(stage, greaterThan(-1));
      expect(terminalReread, greaterThan(stage));
      expect(
        strictThumbnail,
        greaterThan(terminalReread),
        reason: 'a terminal winner must never be followed by a thumbnail write',
      );
      expect(strictThumbnail, lessThan(markerStage));

      // 2. It is exactly one attachment and it is best-effort: the writer
      //    swallows its own failures and never blocks the receipt.
      final block = receiver.substring(strictThumbnail, markerStage);
      expect(block.contains('(strictRawMedia?.length ?? 0) == 1'), isTrue);
      expect(
        block.contains('_persistIncomingProtectedPhotoThumbnail('),
        isTrue,
      );
      final writer = receiver.indexOf(
        'Future<void> _persistIncomingProtectedPhotoThumbnail({',
      );
      final writerBody = receiver.substring(writer, writer + 3000);
      expect(
        writerBody.contains('// Best-effort: a failed thumbnail write never'),
        isTrue,
      );
      // It is never authority: the hash is dropped rather than persisted.
      expect(
        writerBody.contains('saveAttachment('),
        isFalse,
        reason: 'the inline thumbnail never becomes database authority',
      );
      // It is path-authorized per call site.
      expect(writerBody.contains('DirectPrivateMediaPathGuard'), isTrue);

      // 3. Existing private cleanup still owns its removal, unchanged.
      final wipe = lifecycle.indexOf(
        'Future<void> _deleteExactAppOwnedArtifacts({',
      );
      final wipeBody = lifecycle.substring(wipe, wipe + 3000);
      expect(
        wipeBody.contains('relativeThumbnailPathForAttachment('),
        isTrue,
        reason: 'terminal cleanup, delete-for-me and recovery all wipe it',
      );
      expect(
        wipeBody.contains('path: thumbnailPath, root: canonicalRoot'),
        isTrue,
      );
    });
  });

  group('Plan 355 private lifecycle authority', () {
    const expiresAtMs = 1_900_000_700_000;
    const contentHash =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    ChatMessage strictProtectedPhoto({
      required String messageId,
      required String attachmentId,
      required String thumbnail,
      String? timestamp,
    }) {
      final resolvedTimestamp = timestamp ?? nextTimestamp();
      final inner = <String, Object?>{
        'id': messageId,
        'text': '',
        'senderPeerId': _senderPeerId,
        'senderUsername': 'ThumbSender',
        'timestamp': resolvedTimestamp,
        'dedupKey': messageId,
        'media': <Map<String, Object?>>[
          <String, Object?>{
            'id': attachmentId,
            'mime': 'image/jpeg',
            'size': 42,
            'mediaType': 'image',
            'contentHash': contentHash,
            'encryptionKeyBase64': base64Encode(utf8.encode('thumb-key')),
            'encryptionNonce': base64Encode(utf8.encode('thumb-nonce')),
            'encryptionScheme': 'blob_aes_256_gcm_v1',
            'blobCustody': <String, Object?>{
              'kind': 'direct_media_blob_v1',
              'contract': 'ack_or_expiry_v1',
              'contentHash': contentHash,
              'ciphertextSize': 70,
              'transportMime': 'application/octet-stream',
              'expiresAtMs': expiresAtMs,
            },
            _thumbnailKey: thumbnail,
          },
        ],
        'privateMedia': const <String, Object?>{
          'version': 1,
          'mode': 'protected',
        },
      };
      return ChatMessage(
        from: _senderPeerId,
        to: 'me',
        content: MessagePayload.buildEncryptedEnvelope(
          id: messageId,
          senderPeerId: _senderPeerId,
          senderUsername: 'ThumbSender',
          kem: 'opaque-kem',
          ciphertext: 'opaque-ciphertext',
          nonce: 'opaque-nonce',
        ),
        timestamp: resolvedTimestamp,
        isIncoming: true,
        transport: 'direct',
        predecryptedText: jsonEncode(inner),
      );
    }

    test('TC-355-04a private terminal and strict presentation converge under '
        'one lifecycle authority', () async {
      // --- Lock order A: RECEIVE first. Every presentation effect runs
      // inside one exclusive lease, so a competing terminal owner cannot
      // interleave between the re-read, the thumbnail, the marker, the
      // publication and the ready promotion. ---
      const messageId = 'tc355-04a-receive-first';
      const attachmentId = '$messageId-a';
      final effects = <String>[];
      var terminalWonDuringLease = false;
      final startCompeting = Completer<void>();
      // Started OUTSIDE the receive's zone: an exclusive section requested
      // from inside the lease's own zone would be reentrant, not competing.
      final competingTerminal = Future<void>(() async {
        await startCompeting.future;
        await fixture.repo.lifecycleLock.synchronizedAll(() async {
          await fixture.db.update(
            'messages',
            <String, Object?>{
              'private_media_state': 'consumed',
              'private_media_terminal_at_ms': 1_800_000_800_000,
            },
            where: 'id = ?',
            whereArgs: <Object?>[messageId],
          );
          terminalWonDuringLease = true;
        });
      });

      Future<void> assertLeaseStillHeld() async {
        // Drain the event loop: a competing exclusive section must still be
        // queued behind our lease, not applied.
        for (var i = 0; i < 5; i += 1) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(
          terminalWonDuringLease,
          isFalse,
          reason: 'no terminal owner may interleave inside the lease',
        );
      }

      final receiveFirst = strictProtectedPhoto(
        messageId: messageId,
        attachmentId: attachmentId,
        thumbnail: validThumbnailBase64(),
      );
      final (result, _, _) = await handleIncomingChatMessage(
        message: receiveFirst,
        messageRepo: fixture.messageRepo,
        contactRepo: contactRepo,
        predecryptedText: receiveFirst.predecryptedText,
        mediaAttachmentRepo: fixture.repo,
        mediaFileManager: mediaFileManager,
        transport: 'direct',
        stageNotificationDisplayCustody: (_) async {
          effects.add('marker-stage');
          if (!startCompeting.isCompleted) startCompeting.complete();
          await assertLeaseStillHeld();
        },
        promoteNotificationDisplayCustody: (_) async {
          effects.add('marker-promote');
          // The later generic ready-promotion site must be inside the same
          // authority, not after it.
          await assertLeaseStillHeld();
        },
        sendDeliveryReceipt: (_) async => effects.add('receipt'),
      );

      expect(result, HandleChatMessageResult.chatMessage);
      expect(effects, <String>['marker-stage', 'marker-promote', 'receipt']);
      // Exactly ONE promotion: the private lane owns it and the generic
      // site must not repeat it.
      expect(
        effects.where((effect) => effect == 'marker-promote'),
        hasLength(1),
      );
      // No async work started under the lease was detached.
      await competingTerminal;
      expect(terminalWonDuringLease, isTrue);
      expect(
        File(
          await expectedThumbnailPath(
            contactPeerId: _senderPeerId,
            blobId: attachmentId,
          ),
        ).existsSync(),
        isTrue,
        reason: 'a receive-first winner still writes its guarded sibling',
      );

      // --- Lock order B: TERMINAL first. The terminal owner holds the
      // exclusive lease while the receive is already in flight; the receive
      // must wait for it and then produce durable zero-effect supersession.
      const secondId = 'tc355-04a-terminal-first';
      const secondAttachmentId = '$secondId-a';
      final firstDelivery = strictProtectedPhoto(
        messageId: secondId,
        attachmentId: secondAttachmentId,
        thumbnail: validThumbnailBase64(),
      );
      expect(
        (await handleIncomingChatMessage(
          message: firstDelivery,
          messageRepo: fixture.messageRepo,
          contactRepo: contactRepo,
          predecryptedText: firstDelivery.predecryptedText,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: mediaFileManager,
          transport: 'direct',
        )).$1,
        HandleChatMessageResult.chatMessage,
      );

      final release = Completer<void>();
      final terminalFirst = fixture.repo.lifecycleLock.synchronizedAll(
        () async {
          await fixture.db.update(
            'messages',
            <String, Object?>{
              'private_media_state': 'consumed',
              'private_media_terminal_at_ms': 1_800_000_800_000,
            },
            where: 'id = ?',
            whereArgs: <Object?>[secondId],
          );
          await release.future;
        },
      );
      final replayEffects = <String>[];
      // The exact same wire event: an immutable-field crossing would refuse
      // instead of settling, which TC-355-03a proves separately.
      final replay = strictProtectedPhoto(
        messageId: secondId,
        attachmentId: secondAttachmentId,
        thumbnail: validThumbnailBase64(),
        timestamp: firstDelivery.timestamp,
      );
      final pending = handleIncomingChatMessage(
        message: replay,
        messageRepo: fixture.messageRepo,
        contactRepo: contactRepo,
        predecryptedText: replay.predecryptedText,
        mediaAttachmentRepo: fixture.repo,
        mediaFileManager: mediaFileManager,
        transport: 'direct',
        stageNotificationDisplayCustody: (_) async =>
            replayEffects.add('marker-stage'),
        promoteNotificationDisplayCustody: (_) async =>
            replayEffects.add('marker-promote'),
        sendDeliveryReceipt: (_) async => replayEffects.add('receipt'),
      );
      for (var i = 0; i < 5; i += 1) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        replayEffects,
        isEmpty,
        reason:
            'the receive cannot publish while the terminal owner holds '
            'the exclusive lease',
      );
      release.complete();
      await terminalFirst;
      final (terminalResult, _, _) = await pending;
      await Future<void>.delayed(Duration.zero);

      expect(terminalResult, HandleChatMessageResult.durablySuperseded);
      expect(replayEffects, <String>['receipt']);
    });

    test('TC-356-04c current private deletion and strict presentation '
        'serialize in both lifecycle lock orders', () async {
      const author = _senderPeerId;

      /// Builds one authenticated current deletion event for [messageId].
      ChatMessage deletionEvent(String messageId, String eventId) {
        final inner = MessageDeletionPayload(
          messageId: messageId,
          senderPeerId: author,
          timestamp: '2026-07-29T11:00:00.000Z',
          eventId: eventId,
        );
        return ChatMessage(
          from: author,
          to: 'me',
          content: MessageDeletionPayload.buildEncryptedEnvelope(
            senderPeerId: author,
            eventId: eventId,
            kem: 'kem',
            ciphertext: inner.toInnerJson(),
            nonce: 'nonce',
          ),
          timestamp: '2026-07-29T11:00:00.000Z',
          isIncoming: true,
          transport: 'inbox',
        );
      }

      // --- Lock order A: the DELETION owns the exclusive lease first. ---
      const deletedId = 'tc356-04c-delete-first';
      const deletedAttachment = '$deletedId-a';
      final seeded = strictProtectedPhoto(
        messageId: deletedId,
        attachmentId: deletedAttachment,
        thumbnail: validThumbnailBase64(),
      );
      expect(
        (await handleIncomingChatMessage(
          message: seeded,
          messageRepo: fixture.messageRepo,
          contactRepo: contactRepo,
          predecryptedText: seeded.predecryptedText,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: mediaFileManager,
          transport: 'direct',
        )).$1,
        HandleChatMessageResult.chatMessage,
      );

      final deletionHoldsLease = Completer<void>();
      final releaseDeletion = Completer<void>();
      addTearDown(() {
        if (!releaseDeletion.isCompleted) releaseDeletion.complete();
      });
      final gatedFileManager = _GatedPrivateCleanupFileManager(
        onFirstDelete: () async {
          if (!deletionHoldsLease.isCompleted) deletionHoldsLease.complete();
          await releaseDeletion.future;
        },
      );
      final deletionReceipts = <String>[];
      final deletion = handleIncomingMessageDeletion(
        message: deletionEvent(deletedId, '35600000-0000-4000-8000-04c1'),
        messageRepo: fixture.messageRepo,
        contactRepo: contactRepo,
        mediaAttachmentRepo: fixture.repo,
        mediaFileManager: gatedFileManager,
        bridge: PassthroughCryptoBridge(),
        ownMlKemSecretKey: 'secret',
        stagedEntryId: 'relay-uuid-tc356-04c-a',
        sendMutationDeliveryReceipt: (id, {required mutationEventId}) async =>
            deletionReceipts.add(mutationEventId),
      );
      await Future.any(<Future<Object?>>[
        deletionHoldsLease.future,
        deletion,
      ]).timeout(const Duration(seconds: 10));
      expect(
        deletionHoldsLease.isCompleted,
        isTrue,
        reason:
            'the current private deletion must hold the same exclusive private '
            'lifecycle lease that strict presentation uses',
      );

      // A competing strict initial cannot make any presentation progress.
      const competingId = 'tc356-04c-competing-strict';
      final competingEffects = <String>[];
      final competing = strictProtectedPhoto(
        messageId: competingId,
        attachmentId: '$competingId-a',
        thumbnail: validThumbnailBase64(),
      );
      final competingReceive = handleIncomingChatMessage(
        message: competing,
        messageRepo: fixture.messageRepo,
        contactRepo: contactRepo,
        predecryptedText: competing.predecryptedText,
        mediaAttachmentRepo: fixture.repo,
        mediaFileManager: mediaFileManager,
        transport: 'direct',
        stageNotificationDisplayCustody: (_) async =>
            competingEffects.add('marker-stage'),
        promoteNotificationDisplayCustody: (_) async =>
            competingEffects.add('marker-promote'),
        sendDeliveryReceipt: (_) async => competingEffects.add('receipt'),
      );
      for (var i = 0; i < 5; i += 1) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        competingEffects,
        isEmpty,
        reason:
            'no strict presentation may start while the deletion holds the '
            'exclusive private lifecycle lease',
      );
      expect(
        await fixture.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: const <Object?>[competingId],
        ),
        isEmpty,
        reason: 'the competing strict DB stage has not run yet',
      );
      expect(deletionReceipts, isEmpty);

      releaseDeletion.complete();
      final (deletionResult, deletedRow) = await deletion.timeout(
        const Duration(seconds: 10),
      );
      expect(deletionResult, HandleMessageDeletionResult.success);
      expect(deletedRow?.isDeleted, isTrue);
      expect(deletionReceipts, hasLength(1));
      expect(
        (await competingReceive.timeout(const Duration(seconds: 10))).$1,
        HandleChatMessageResult.chatMessage,
      );
      expect(competingEffects, contains('marker-stage'));
      expect(
        File(
          await expectedThumbnailPath(
            contactPeerId: author,
            blobId: deletedAttachment,
          ),
        ).existsSync(),
        isFalse,
        reason: 'the deletion winner leaves no thumbnail behind',
      );

      // --- Lock order B: strict RECEIVE owns the lease first. ---
      const receiveFirstId = 'tc356-04c-receive-first';
      final receiveEffects = <String>[];
      var deletionProgressDuringLease = false;
      final startDeletion = Completer<void>();
      final laterReceipts = <String>[];
      // Started OUTSIDE the receive's zone so it genuinely competes.
      final laterDeletion = Future<void>(() async {
        await startDeletion.future;
        final (_, _) = await handleIncomingMessageDeletion(
          message: deletionEvent(
            receiveFirstId,
            '35600000-0000-4000-8000-04c2',
          ),
          messageRepo: fixture.messageRepo,
          contactRepo: contactRepo,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: mediaFileManager,
          bridge: PassthroughCryptoBridge(),
          ownMlKemSecretKey: 'secret',
          stagedEntryId: 'relay-uuid-tc356-04c-b',
          sendMutationDeliveryReceipt: (id, {required mutationEventId}) async =>
              laterReceipts.add(mutationEventId),
        );
        deletionProgressDuringLease = true;
      });

      Future<void> assertDeletionBlocked() async {
        for (var i = 0; i < 5; i += 1) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(
          deletionProgressDuringLease,
          isFalse,
          reason: 'no deletion may interleave inside the presentation lease',
        );
        expect(
          (await fixture.db.query(
            'messages',
            where: 'id = ?',
            whereArgs: const <Object?>[receiveFirstId],
          )).single['deleted_at'],
          isNull,
          reason: 'no tombstone may commit inside the presentation lease',
        );
        expect(laterReceipts, isEmpty);
      }

      final receiveFirstMessage = strictProtectedPhoto(
        messageId: receiveFirstId,
        attachmentId: '$receiveFirstId-a',
        thumbnail: validThumbnailBase64(),
      );
      final (receiveResult, _, _) = await handleIncomingChatMessage(
        message: receiveFirstMessage,
        messageRepo: fixture.messageRepo,
        contactRepo: contactRepo,
        predecryptedText: receiveFirstMessage.predecryptedText,
        mediaAttachmentRepo: fixture.repo,
        mediaFileManager: mediaFileManager,
        transport: 'direct',
        stageNotificationDisplayCustody: (_) async {
          receiveEffects.add('marker-stage');
          if (!startDeletion.isCompleted) startDeletion.complete();
          await assertDeletionBlocked();
        },
        promoteNotificationDisplayCustody: (_) async {
          receiveEffects.add('marker-promote');
          await assertDeletionBlocked();
        },
        sendDeliveryReceipt: (_) async => receiveEffects.add('receipt'),
      );

      expect(receiveResult, HandleChatMessageResult.chatMessage);
      expect(receiveEffects, <String>[
        'marker-stage',
        'marker-promote',
        'receipt',
      ]);
      await laterDeletion.timeout(const Duration(seconds: 10));
      expect(deletionProgressDuringLease, isTrue);
      expect(laterReceipts, hasLength(1));
      expect(
        (await fixture.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: const <Object?>[receiveFirstId],
        )).single['deleted_at'],
        isNotNull,
      );
      expect(
        File(
          await expectedThumbnailPath(
            contactPeerId: author,
            blobId: '$receiveFirstId-a',
          ),
        ).existsSync(),
        isFalse,
        reason: 'a receive-first winner leaves no marker or thumbnail behind',
      );
    });
  });
}

/// Pauses inside the deletion's private artifact cleanup, which the shared
/// handler runs under the same exclusive private lifecycle lease.
class _GatedPrivateCleanupFileManager extends MediaFileManager {
  _GatedPrivateCleanupFileManager({required this.onFirstDelete});

  final Future<void> Function() onFirstDelete;
  bool _observed = false;

  @override
  Future<void> deleteFile(
    String localPath, {
    String caller = 'MediaFileManager.deleteFile',
    String reason = 'media_file_delete',
    String? storedPath,
    Map<String, Object?> details = const {},
    bool redactTelemetry = false,
  }) async {
    if (!_observed) {
      _observed = true;
      await onFirstDelete();
    }
    return super.deleteFile(
      localPath,
      caller: caller,
      reason: reason,
      storedPath: storedPath,
      details: details,
      redactTelemetry: redactTelemetry,
    );
  }
}

ContactModel _contact(String peerId) => ContactModel(
  peerId: peerId,
  publicKey: 'public-key',
  rendezvous: 'rendezvous',
  username: 'ThumbSender',
  signature: 'signature',
  scannedAt: '2026-07-29T08:00:00.000Z',
  mlKemPublicKey: 'ml-kem-public-key',
);
