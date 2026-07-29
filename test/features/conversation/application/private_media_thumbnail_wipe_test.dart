import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

const _senderPeerId = '12D3KooWThumbWipeSender';
const _tileKey = ValueKey('private-media-thumbnail-tile');

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
    tempDocs = Directory.systemTemp.createTempSync('protected_thumb_wipe_');
    PathProviderPlatform.instance = _FakePathProvider(tempDocs.path);
    MediaFileManager.cacheDocumentsDir(tempDocs.path);
    fixture = await MediaRepositoryRealDbFixture.create();
    contactRepo = InMemoryContactRepository()
      ..addTestContact(
        ContactModel(
          peerId: _senderPeerId,
          publicKey: 'public-key',
          rendezvous: 'rendezvous',
          username: 'WipeSender',
          signature: 'signature',
          scannedAt: '2026-07-29T08:00:00.000Z',
          mlKemPublicKey: 'ml-kem-public-key',
        ),
      );
    mediaFileManager = MediaFileManager();
  });

  tearDown(() async {
    await fixture.dispose();
    MediaFileManager.debugResetDocumentsDirCache();
    if (tempDocs.existsSync()) {
      tempDocs.deleteSync(recursive: true);
    }
  });

  /// Lands one incoming protected photo WITH its inline thumbnail through the
  /// real receive path, so the wipe cases operate on production-written rows,
  /// key custody, and the real sibling file.
  Future<({ConversationMessage message, String thumbPath})> landProtectedPhoto({
    required String messageId,
    required String attachmentId,
  }) async {
    final timestamp =
        '2026-07-29T10:0${timestampCounter ~/ 10}:${(timestampCounter % 10)}0.000Z';
    timestampCounter++;
    final inner = <String, Object?>{
      'id': messageId,
      'text': '',
      'senderPeerId': _senderPeerId,
      'senderUsername': 'WipeSender',
      'timestamp': timestamp,
      'media': [
        <String, Object?>{
          'id': attachmentId,
          'mime': 'image/jpeg',
          'size': 42,
          'mediaType': 'image',
          'contentHash':
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'encryptionKeyBase64': base64Encode(utf8.encode('wipe-key')),
          'encryptionNonce': base64Encode(utf8.encode('wipe-nonce')),
          'encryptionScheme': 'blob_aes_256_gcm_v1',
          'thumbnailInlineBase64': base64Encode(
            img.encodeJpg(img.Image(width: 10, height: 10)),
          ),
        },
      ],
      'privateMedia': {'version': 1, 'mode': 'protected'},
    };
    final (result, _, _) = await handleIncomingChatMessage(
      message: ChatMessage(
        from: _senderPeerId,
        to: 'me',
        content: MessagePayload.buildEncryptedEnvelope(
          id: messageId,
          senderPeerId: _senderPeerId,
          senderUsername: 'WipeSender',
          kem: 'opaque-kem',
          ciphertext: 'opaque-ciphertext',
          nonce: 'opaque-nonce',
        ),
        timestamp: timestamp,
        isIncoming: true,
        transport: 'direct',
        predecryptedText: jsonEncode(inner),
      ),
      messageRepo: fixture.messageRepo,
      contactRepo: contactRepo,
      predecryptedText: jsonEncode(inner),
      mediaAttachmentRepo: fixture.repo,
      mediaFileManager: mediaFileManager,
      transport: 'direct',
    );
    expect(result, HandleChatMessageResult.chatMessage);
    final thumbPath = await mediaFileManager.resolveStoredPath(
      MediaFilePathConvention.relativeThumbnailPathForAttachment(
        contactPeerId: _senderPeerId,
        blobId: attachmentId,
      ),
    );
    expect(
      File(thumbPath).existsSync(),
      isTrue,
      reason: 'fixture precondition: the receive path wrote the thumbnail',
    );
    final message = await fixture.messageRepo.getMessage(messageId);
    expect(message, isNotNull);
    return (message: message!, thumbPath: thumbPath);
  }

  test('delete for me removes the protected thumbnail file', () async {
    final landed = await landProtectedPhoto(
      messageId: 'wipe-delete-for-me',
      attachmentId: 'wipe-delete-for-me-att',
    );

    final deleted = await deleteMessageForMe(
      message: landed.message,
      messageRepo: fixture.messageRepo,
      mediaAttachmentRepo: fixture.repo,
      mediaFileManager: mediaFileManager,
    );

    expect(deleted, 1);
    expect(
      File(landed.thumbPath).existsSync(),
      isFalse,
      reason: 'delete-for-me must remove the thumbnail sibling',
    );
  });

  testWidgets(
    'terminalization leaves no thumbnail file and the bubble shows the terminal placeholder',
    (tester) async {
      final landed = await tester.runAsync(() async {
        final landed = await landProtectedPhoto(
          messageId: 'wipe-terminalized',
          attachmentId: 'wipe-terminalized-att',
        );

        // Incoming protected rows cannot reach a terminal state through
        // today's CAS surface (consume covers incoming view-once and outgoing
        // VIEW-ONCE only — since plan 302 the outgoing protected sender opens
        // lease-free and never consumes) — their real destructive paths are
        // the delete legs. The terminal-cleanup path must still wipe the
        // sibling for ANY terminal row, so seed the terminal columns directly
        // on the real schema and drive the production cleanup through it.
        await fixture.db.rawUpdate(
          "UPDATE messages SET private_media_state = 'consumed', "
          'private_media_terminal_at_ms = ? WHERE id = ?',
          [
            DateTime.parse('2026-07-29T11:00:00.000Z').millisecondsSinceEpoch,
            landed.message.id,
          ],
        );
        final consumed = (await fixture.messageRepo.getMessage(
          landed.message.id,
        ))!;
        expect(consumed.privateMediaState, PrivateMediaLifecycleState.consumed);

        final engine = PrivateMediaLifecycleEngine(
          adapter: DirectPrivateMediaLifecycle(
            messageRepository: fixture.messageRepo,
            mediaAttachmentRepository: fixture.repo,
            mediaFileManager: mediaFileManager,
          ),
          lifecycleLock: (fixture.repo as DirectPrivateMediaCleanupRuntime)
              .directPrivateMediaLifecycleLock,
          nowMs: () => DateTime.now().toUtc().millisecondsSinceEpoch,
        );
        await engine.cleanupTerminalMessage(consumed.id);

        expect(
          File(landed.thumbPath).existsSync(),
          isFalse,
          reason: 'terminal cleanup must remove the thumbnail sibling',
        );
        return (message: consumed, thumbPath: landed.thumbPath);
      });

      // Post-transition rebuild: the bubble shows the terminal placeholder,
      // never a stale thumbnail.
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ConversationScreen(
              contactPeerId: _senderPeerId,
              contactUsername: 'WipeSender',
              connectionDate: 'July 29, 2026',
              ownPeerId: 'own-peer',
              messages: [landed!.message],
              onSend: (_) {},
              onBack: () {},
              initialLoadDone: true,
              hasMoreOlderMessages: false,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byKey(const ValueKey('private-terminal-consumed')),
        findsOneWidget,
      );
      expect(find.byKey(_tileKey), findsNothing);
    },
  );

  test('incoming delete-for-everyone removes the thumbnail file', () async {
    final landed = await landProtectedPhoto(
      messageId: 'wipe-delete-for-everyone',
      attachmentId: 'wipe-delete-for-everyone-att',
    );

    // The incoming deletion handler persists the tombstone and then runs
    // cleanupDeletedMessageArtifacts — the DISTINCT third destructive path.
    final tombstone = landed.message.copyWith(
      deletedAt: '2026-07-29T12:00:00.000Z',
      deletedByPeerId: _senderPeerId,
    );
    await fixture.messageRepo.saveMessage(tombstone);
    await cleanupDeletedMessageArtifacts(
      message: tombstone,
      mediaAttachmentRepo: fixture.repo,
      mediaFileManager: mediaFileManager,
    );

    expect(
      File(landed.thumbPath).existsSync(),
      isFalse,
      reason: 'incoming delete-for-everyone must remove the thumbnail sibling',
    );
  });
}
