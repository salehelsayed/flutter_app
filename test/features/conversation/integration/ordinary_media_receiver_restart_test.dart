import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/encrypted_media_test_bridge.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../contact_request/presentation/support/contact_request_sql_fixture.dart';

// Default legacy media lane, current SQL repositories/files and host image
// decoder. The controlled native transport error and recreated receiver graph
// model a persisted interruption checkpoint; no OS process was killed. Native
// crypto, real relay, camera/video/audio and actual platform viewers are faked
// or outside this test. A surviving partial ciphertext is not a done original.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('MEDIA-018 interrupted ordinary download survives receiver SQL/runtime '
      'reopen and commits one fully decodable image plus caption', () async {
    final root = await Directory.systemTemp.createTemp(
      'ordinary_media_restart_',
    );
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Documents(root.path);
    MediaFileManager.cacheDocumentsDir(root.path);
    final files = MediaFileManager();
    final a = TestEd25519Identity.fromSeedByte(93);
    final b = TestEd25519Identity.fromSeedByte(94);
    final store = RelayMediaStore();
    final sender = EncryptedMediaTestBridge(store, seedSalt: 40);
    var receiver = _PartialReceiver(store)..failDownloads = true;
    final alice = await MediaRepositoryRealDbFixture.create(
      databasePath: '${root.path}/alice.db',
      databaseFactoryOverride: databaseFactoryFfiNoIsolate,
    );
    var bob = await MediaRepositoryRealDbFixture.create(
      databasePath: '${root.path}/bob.db',
      databaseFactoryOverride: databaseFactoryFfiNoIsolate,
    );
    final persistedKeys = bob.secureKeyStore;
    await buildWidgetContactRepository(bob.db).addContact(
      ContactModel(
        peerId: a.peerId,
        publicKey: a.publicKey,
        username: 'Sender',
        rendezvous: 'synthetic-relay',
        signature: 'synthetic-signature',
        scannedAt: '2026-10-22T09:00:00.000Z',
        mlKemPublicKey: 'synthetic-kem-a',
      ),
    );
    ChatMessageListener wireReceiver(
      MediaRepositoryRealDbFixture fixture,
      _PartialReceiver native,
    ) => ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: fixture.messageRepo,
      contactRepo: buildWidgetContactRepository(fixture.db),
      bridge: native,
      getOwnMlKemSecretKey: () async => 'synthetic-kem-b-secret',
      mediaAttachmentRepo: fixture.repo,
      mediaFileManager: files,
      loadRetryableMediaMessageIds: ({afterMessageId, limit = 25}) =>
          dbLoadRetryableDirectMediaMessageIds(
            fixture.db,
            afterMessageId: afterMessageId,
            limit: limit,
          ),
    );
    var listener = wireReceiver(bob, receiver);
    final p2p = FakeP2PService(
      initialState: NodeState(isStarted: true, peerId: a.peerId),
    );
    addTearDown(() async {
      listener.dispose();
      p2p.dispose();
      if (bob.db.isOpen) await bob.dispose();
      if (alice.db.isOpen) await alice.dispose();
      MediaFileManager.debugResetDocumentsDirCache();
      PathProviderPlatform.instance = previousPaths;
      await root.delete(recursive: true);
    });
    final image = img.Image(width: 128, height: 96);
    for (final pixel in image) {
      pixel.setRgb(pixel.x < 64 ? 220 : 20, pixel.y < 48 ? 180 : 40, 30);
    }
    final bytes = img.encodeJpg(image, quality: 95);
    final source = File('${root.path}/source.jpg');
    await source.writeAsBytes(bytes, flush: true);
    final uploaded = (await uploadMedia(
      bridge: sender,
      localFilePath: source.path,
      mime: 'image/jpeg',
      recipientPeerId: b.peerId,
      mediaFileManager: files,
    )).attachmentOrNull!;
    expect(
      uploaded.blobCustody,
      isNull,
      reason: 'this exercises the default legacy lane, not the strict cohort',
    );
    String? wire;
    const caption = 'Restarted full photo 👋';
    final (sent, outbound) = await sendChatMessage(
      p2pService: p2p,
      messageRepo: alice.messageRepo,
      targetPeerId: b.peerId,
      text: caption,
      senderPeerId: a.peerId,
      senderUsername: 'Sender',
      bridge: sender,
      recipientMlKemPublicKey: 'synthetic-kem-b',
      mediaAttachments: [uploaded],
      mediaAttachmentRepo: alice.repo,
      storeInAckCustodyInboxDetailed:
          (peer, envelope, {required custodyKind, timeoutMs}) async {
            wire = envelope;
            return InboxStoreOutcome(
              status: InboxStoreStatus.stored,
              storeStatus: 'stored',
              expiresAtMs: DateTime.now()
                  .add(const Duration(days: 1))
                  .millisecondsSinceEpoch,
              custodyContract: ackOrExpiryInboxCustodyContract,
            );
          },
    );
    expect(sent, SendChatMessageResult.success);
    wire ??= p2p.lastSendMessageContent;
    final arrival = ChatMessage(
      from: a.peerId,
      to: b.peerId,
      content: wire!,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      isIncoming: true,
      transport: 'relay',
    );
    final interrupted = listener.incomingMessageStream.firstWhere(
      (m) =>
          m.id == outbound!.id &&
          m.media.isNotEmpty &&
          m.media.single.downloadStatus == kMediaDownloadStatusRetryWaiting,
    );
    await listener.processIncomingMessage(arrival);
    final pending = await interrupted.timeout(const Duration(seconds: 15));
    expect(pending.media.single.downloadRetryCount ?? 0, 0);
    expect(
      pending.media.single.downloadStatus,
      isNot(kMediaDownloadStatusDone),
    );
    final ciphertext = store.uploadedBytesByBlobId[uploaded.id]!;
    final prefix = ciphertext.take(ciphertext.length ~/ 2).toList();
    // Reconstruct the prefix that an abruptly stopped native writer can leave,
    // after the graceful error path has had its chance to clean its own file.
    final partial = File(receiver.partialPath!);
    await partial.parent.create(recursive: true);
    await partial.writeAsBytes(prefix, flush: true);
    expect(partial.lengthSync(), lessThan(ciphertext.length));

    listener.dispose();
    await bob.dispose();
    MediaFileManager.debugResetDocumentsDirCache();
    MediaFileManager.cacheDocumentsDir(root.path);
    bob = await MediaRepositoryRealDbFixture.create(
      databasePath: '${root.path}/bob.db',
      secureKeyStore: persistedKeys,
      databaseFactoryOverride: databaseFactoryFfiNoIsolate,
    );
    receiver = _PartialReceiver(store);
    listener = wireReceiver(bob, receiver);
    final before = (await bob.repo.getAttachmentsForMessage(
      outbound!.id,
      owner: MediaOwnerLane.direct,
    )).single;
    expect(before.downloadStatus, kMediaDownloadStatusRetryWaiting);
    expect(before.downloadStatus, isNot(kMediaDownloadStatusDone));
    expect(await listener.retryIncompleteMediaDownloads(), 1);
    final complete = (await bob.repo.getAttachmentsForMessage(
      outbound.id,
      owner: MediaOwnerLane.direct,
    )).single;
    expect(complete.downloadStatus, kMediaDownloadStatusDone);
    final path = await files.resolveStoredPath(complete.localPath!);
    final received = await File(path).readAsBytes();
    expect(sha256.convert(received), sha256.convert(bytes));
    final codec = await ui.instantiateImageCodec(received);
    try {
      final frame = await codec.getNextFrame();
      expect((frame.image.width, frame.image.height), (128, 96));
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
    expect((await bob.messageRepo.getMessage(outbound.id))!.text, caption);
    final attempts = receiver.attempts;
    await listener.processIncomingMessage(arrival);
    expect(
      receiver.attempts,
      attempts,
      reason:
          'replay must retain the complete original without another download',
    );
    expect(await bob.messageRepo.getMessagesForContact(a.peerId), hasLength(1));
    expect(
      await bob.repo.getAttachmentsForMessage(
        outbound.id,
        owner: MediaOwnerLane.direct,
      ),
      hasLength(1),
    );
  }, timeout: const Timeout(Duration(seconds: 45)));
}

class _PartialReceiver extends EncryptedMediaTestBridge {
  _PartialReceiver(super.relayStore) : super(seedSalt: 80);
  bool failDownloads = false;
  int attempts = 0;
  String? partialPath;
  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    if (request['cmd'] == 'media:download') {
      attempts++;
      if (failDownloads) {
        final payload = request['payload'] as Map<String, dynamic>;
        partialPath = payload['outputPath'] as String;
        final bytes = relayStore.uploadedBytesByBlobId[payload['id']]!;
        final written = bytes.length ~/ 2;
        final file = File(partialPath!);
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes.take(written).toList(), flush: true);
        return jsonEncode({
          'ok': false,
          'errorMessage':
              'all 1 relays failed, last error: download incomplete: '
              'wrote $written/${bytes.length}, err=EOF',
        });
      }
    }
    return super.send(message);
  }
}

class _Documents extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _Documents(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}
