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
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

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
        'if (strictMediaProjection.isPrivate) {\n      final durableParent =',
      );
      final strictThumbnail = receiver.indexOf(
        'if (strictMediaProjection.isPrivate &&\n        mediaFileManager != null &&',
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
      expect(block.contains("(payload.media?.length ?? 0) == 1"), isTrue);
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
