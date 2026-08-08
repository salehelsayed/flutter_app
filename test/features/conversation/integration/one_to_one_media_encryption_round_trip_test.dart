// 112 Phase 2.5 — 1:1 media end-to-end encryption round trip.
//
// Full upload → send → receive/hydrate → download → decrypt path over a
// fake in-memory relay with CONTENT-TRANSFORMING blob crypto: the shared
// FakeBridge's blob:encrypt copies bytes unchanged and cannot detect
// plaintext leaks, so this file overrides the blob handlers with a
// prefix-tagging transform (same scheme as download_media_use_case_test).
//
// Authored red→green inside Phase 2: against the Phase-1 tree the receiver
// could already decrypt, but the sender still uploaded plaintext, so the
// "uploaded bytes ≠ plaintext" assertion failed until the Phase-2.6 flip.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';

const _alicePeerId = '12D3KooWAliceRoundTrip0000001';
const _bobPeerId = '12D3KooWBobRoundTrip000000002';

/// Content-transforming crypto + shared in-memory relay store.
///
/// blob:encrypt prefixes `cipher:<key>:<nonce>:` and reverses the bytes;
/// blob:decrypt verifies the prefix and restores the original — a wrong
/// key/nonce fails exactly like a real AES-GCM auth-tag mismatch.
class _RelayBridge extends PassthroughCryptoBridge {
  _RelayBridge(this.relayStore);

  final Map<String, List<int>> relayStore;
  int _keygenCount = 0;
  final Map<String, String> _noncesByKey = {};

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    final payload = parsed['payload'] as Map<String, dynamic>?;

    if (cmd == 'blob:keygen') {
      commandLog.add(cmd!);
      _keygenCount++;
      return jsonEncode({'ok': true, 'keyBase64': 'rt-key-$_keygenCount'});
    }
    if (cmd == 'blob:encrypt') {
      commandLog.add(cmd!);
      final filePath = payload!['filePath'] as String;
      final key = payload['keyBase64'] as String;
      final nonce = 'rt-nonce-$_keygenCount';
      _noncesByKey[key] = nonce;
      final source = await File(filePath).readAsBytes();
      final encryptedPath = '$filePath.$_keygenCount.enc';
      await File(encryptedPath).writeAsBytes([
        ...'cipher:$key:$nonce:'.codeUnits,
        ...source.reversed,
      ], flush: true);
      return jsonEncode({
        'ok': true,
        'encryptedPath': encryptedPath,
        'nonce': nonce,
      });
    }
    if (cmd == 'blob:decrypt') {
      commandLog.add(cmd!);
      final filePath = payload!['filePath'] as String;
      final key = payload['keyBase64'] as String;
      final nonce = payload['nonce'] as String;
      final encrypted = await File(filePath).readAsBytes();
      final prefix = 'cipher:$key:$nonce:'.codeUnits;
      final hasPrefix =
          encrypted.length >= prefix.length &&
          List.generate(
            prefix.length,
            (index) => encrypted[index] == prefix[index],
          ).every((matches) => matches);
      if (!hasPrefix) {
        return jsonEncode({'ok': false, 'errorMessage': 'decrypt failed'});
      }
      final decryptedPath = '$filePath.dec';
      await File(decryptedPath).writeAsBytes(
        encrypted.skip(prefix.length).toList().reversed.toList(),
        flush: true,
      );
      return jsonEncode({'ok': true, 'decryptedPath': decryptedPath});
    }
    if (cmd == 'media:upload') {
      commandLog.add(cmd!);
      final filePath = payload!['filePath'] as String;
      relayStore[payload['id'] as String] = await File(filePath).readAsBytes();
      return jsonEncode({'ok': true});
    }
    if (cmd == 'media:download') {
      commandLog.add(cmd!);
      final stored = relayStore[payload!['id'] as String];
      if (stored == null) {
        return jsonEncode({'ok': false, 'errorMessage': 'not found'});
      }
      final outputPath = payload['outputPath'] as String;
      final outputFile = File(outputPath);
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsBytes(stored, flush: true);
      return jsonEncode({'ok': true, 'size': stored.length});
    }
    if (cmd == 'media:delete') {
      commandLog.add(cmd!);
      relayStore.remove(payload!['id'] as String);
      return jsonEncode({'ok': true});
    }
    return super.send(message);
  }
}

class _TempMediaFileManager extends MediaFileManager {
  _TempMediaFileManager(this.basePath);

  final String basePath;

  @override
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) async {
    final ext = mime == 'image/jpeg' ? '.jpg' : '';
    return '$basePath/$contactPeerId/$blobId$ext';
  }

  @override
  Future<String> resolveStoredPath(String storedPath) async {
    if (storedPath.startsWith('/')) {
      return storedPath;
    }
    return '$basePath/$storedPath';
  }

  @override
  Future<void> deleteMediaForContact(String contactPeerId) async {}

  @override
  Future<void> deleteFile(
    String localPath, {
    String caller = 'MediaFileManager.deleteFile',
    String reason = 'media_file_delete',
    String? storedPath,
    Map<String, Object?> details = const {},
    bool redactTelemetry = false,
  }) async {
    final file = File(localPath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

void main() {
  late Directory tempDir;
  late Map<String, List<int>> relayStore;
  late _RelayBridge aliceBridge;
  late _RelayBridge bobBridge;
  late InMemoryMediaAttachmentRepository aliceMediaRepo;
  late InMemoryMediaAttachmentRepository bobMediaRepo;
  late InMemoryMessageRepository aliceMessageRepo;
  late InMemoryMessageRepository bobMessageRepo;
  late InMemoryContactRepository bobContacts;
  late _TempMediaFileManager bobFileManager;

  final plaintextBytes = List<int>.generate(512, (index) => index % 251);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('one_to_one_rt_');
    relayStore = <String, List<int>>{};
    aliceBridge = _RelayBridge(relayStore);
    bobBridge = _RelayBridge(relayStore);
    aliceMediaRepo = InMemoryMediaAttachmentRepository();
    bobMediaRepo = InMemoryMediaAttachmentRepository();
    aliceMessageRepo = InMemoryMessageRepository();
    aliceMediaRepo.enableDirectMediaInboxCustodyForTest(aliceMessageRepo);
    bobMessageRepo = InMemoryMessageRepository();
    bobContacts = InMemoryContactRepository();
    bobContacts.addTestContact(
      ContactModel(
        peerId: _alicePeerId,
        publicKey: 'pk-alice',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'Alice',
        signature: 'sig-alice',
        scannedAt: '2026-06-12T08:00:00.000Z',
      ),
    );
    bobFileManager = _TempMediaFileManager(tempDir.path);
  });

  Future<void> seedOrdinaryIncomingParent(String messageId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await bobMessageRepo.saveMessage(
      ConversationMessage(
        id: messageId,
        contactPeerId: _alicePeerId,
        senderPeerId: _alicePeerId,
        text: '',
        timestamp: now,
        status: 'delivered',
        isIncoming: true,
        createdAt: now,
      ),
    );
  }

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('sender encrypts, key rides the v2 envelope, receiver decrypts to '
      'byte-identical media', () async {
    final photo = File('${tempDir.path}/photo.jpg');
    await photo.writeAsBytes(plaintextBytes, flush: true);

    // 1. Upload (sender).
    final uploaded = (await uploadMedia(
      bridge: aliceBridge,
      localFilePath: photo.path,
      mime: 'image/jpeg',
      recipientPeerId: _bobPeerId,
    )).attachmentOrNull;
    expect(uploaded, isNotNull);
    // THE flip assertion: what the relay stores is ciphertext.
    expect(relayStore[uploaded!.id], isNotNull);
    expect(relayStore[uploaded.id], isNot(equals(plaintextBytes)));

    // 2. Send (sender) — key/nonce/scheme/hash ride INSIDE the v2
    // envelope; the outer wire never carries them in cleartext fields.
    final aliceP2P = FakeP2PService(
      initialState: const NodeState(isStarted: true, peerId: _alicePeerId),
    );
    String? acceptedInboxEnvelope;
    final (sendResult, _) = await sendChatMessage(
      p2pService: aliceP2P,
      messageRepo: aliceMessageRepo,
      targetPeerId: _bobPeerId,
      text: 'photo for you',
      senderPeerId: _alicePeerId,
      senderUsername: 'Alice',
      bridge: aliceBridge,
      recipientMlKemPublicKey: 'mlkem-bob',
      mediaAttachments: [uploaded],
      mediaAttachmentRepo: aliceMediaRepo,
      storeInAckCustodyInboxDetailed:
          (peerId, envelope, {required custodyKind, timeoutMs}) async {
            expect(peerId, _bobPeerId);
            expect(custodyKind, AckCustodyKind.directTextV108);
            acceptedInboxEnvelope = envelope;
            return const InboxStoreOutcome(
              status: InboxStoreStatus.stored,
              storeStatus: 'stored',
              expiresAtMs: 1770000000000,
              custodyContract: ackOrExpiryInboxCustodyContract,
            );
          },
    );
    expect(sendResult, SendChatMessageResult.success);
    expect(
      aliceMessageRepo.directCustodyRows,
      isEmpty,
      reason: 'strict ACK-or-expiry acceptance settles exact local custody',
    );
    final wire =
        aliceP2P.lastSendMessageContent ??
        acceptedInboxEnvelope ??
        aliceP2P.lastStoreInInboxMessage;
    expect(wire, isNotNull);
    final outerEnvelope = jsonDecode(wire!) as Map<String, dynamic>;
    expect(outerEnvelope['version'], '2');
    expect(outerEnvelope.containsKey('media'), isFalse);

    // 3. Receive + hydrate (receiver).
    final (rxResult, rxMessage, _) = await handleIncomingChatMessage(
      message: ChatMessage(
        from: _alicePeerId,
        to: _bobPeerId,
        content: wire,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      ),
      messageRepo: bobMessageRepo,
      contactRepo: bobContacts,
      bridge: bobBridge,
      ownMlKemSecretKey: 'mlkem-bob-secret',
      mediaAttachmentRepo: bobMediaRepo,
    );
    expect(rxResult, HandleChatMessageResult.chatMessage);
    expect(rxMessage, isNotNull);
    final hydrated = rxMessage!.media.single;
    expect(hydrated.encryptionKeyBase64, uploaded.encryptionKeyBase64);
    expect(hydrated.encryptionNonce, uploaded.encryptionNonce);
    expect(hydrated.encryptionScheme, uploaded.encryptionScheme);
    expect(hydrated.contentHash, uploaded.contentHash);

    // 4. Download + decrypt (receiver).
    final persisted = (await bobMediaRepo.getPendingDownloads()).single;
    final downloaded = await downloadMedia(
      bridge: bobBridge,
      mediaAttachmentRepo: bobMediaRepo,
      mediaFileManager: bobFileManager,
      attachment: persisted,
      contactPeerId: _alicePeerId,
      owner: MediaOwnerLane.direct,
      messageRepo: bobMessageRepo,
    );
    expect(downloaded, isNotNull);
    expect(downloaded!.downloadStatus, kMediaDownloadStatusDone);
    expect(
      File(downloaded.localPath!).readAsBytesSync(),
      equals(plaintextBytes),
    );
    expect(bobBridge.commandLog, contains('blob:decrypt'));
  });

  test('legacy plaintext message from old sender still round-trips', () async {
    // Mixed-version matrix cell: an old-build sender shipped a v1 envelope
    // with a metadata-free attachment and a PLAINTEXT relay blob. The
    // receiver must keep working through the ≤7-day drain window.
    relayStore['legacy-blob-001'] = plaintextBytes;
    final envelope = jsonEncode({
      'type': 'chat_message',
      'version': '1',
      'payload': {
        'id': 'msg-legacy-001',
        'text': 'old sender photo',
        'senderPeerId': _alicePeerId,
        'senderUsername': 'Alice',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'media': [
          {
            'id': 'legacy-blob-001',
            'mime': 'image/jpeg',
            'size': plaintextBytes.length,
            'mediaType': 'image',
          },
        ],
      },
    });

    final (rxResult, rxMessage, _) = await handleIncomingChatMessage(
      message: ChatMessage(
        from: _alicePeerId,
        to: _bobPeerId,
        content: envelope,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      ),
      messageRepo: bobMessageRepo,
      contactRepo: bobContacts,
      bridge: bobBridge,
      ownMlKemSecretKey: 'mlkem-bob-secret',
      mediaAttachmentRepo: bobMediaRepo,
    );
    expect(rxResult, HandleChatMessageResult.chatMessage);
    expect(rxMessage, isNotNull);

    final persisted = (await bobMediaRepo.getPendingDownloads()).single;
    expect(persisted.hasEncryptionKeyMaterial, isFalse);

    final downloaded = await downloadMedia(
      bridge: bobBridge,
      mediaAttachmentRepo: bobMediaRepo,
      mediaFileManager: bobFileManager,
      attachment: persisted,
      contactPeerId: _alicePeerId,
      owner: MediaOwnerLane.direct,
      messageRepo: bobMessageRepo,
    );
    expect(downloaded, isNotNull);
    expect(downloaded!.downloadStatus, kMediaDownloadStatusDone);
    expect(
      File(downloaded.localPath!).readAsBytesSync(),
      equals(plaintextBytes),
    );
    // Legacy plaintext stays decrypt-free.
    expect(bobBridge.commandLog, isNot(contains('blob:decrypt')));
  });

  // --- 112 Phase 5.1: matrix completion (green-on-arrival pins) ---

  test('voice round trip: encrypted m4a decrypts byte-identical', () async {
    // Pin (Phases 2.3 + 1): the voice path inherits the same blob scheme.
    final voiceBytes = List<int>.generate(960, (index) => (index * 7) % 251);
    final recordingFile = File('${tempDir.path}/voice.m4a');
    await recordingFile.writeAsBytes(voiceBytes, flush: true);

    final uploaded = (await uploadMedia(
      bridge: aliceBridge,
      localFilePath: recordingFile.path,
      mime: 'audio/mp4',
      recipientPeerId: _bobPeerId,
      durationMs: 4200,
      waveform: const [0.2, 0.7, 0.4],
    )).attachmentOrNull;
    expect(uploaded, isNotNull);
    expect(relayStore[uploaded!.id], isNot(equals(voiceBytes)));

    await seedOrdinaryIncomingParent('msg-voice-rt');

    await bobMediaRepo.saveAttachment(
      uploaded.copyWith(
        messageId: 'msg-voice-rt',
        downloadStatus: 'pending',
        clearLocalPath: true,
      ),
      owner: MediaOwnerLane.direct,
    );
    final persisted = (await bobMediaRepo.getPendingDownloads()).single;
    final downloaded = await downloadMedia(
      bridge: bobBridge,
      mediaAttachmentRepo: bobMediaRepo,
      mediaFileManager: bobFileManager,
      attachment: persisted,
      contactPeerId: _alicePeerId,
      owner: MediaOwnerLane.direct,
      messageRepo: bobMessageRepo,
    );

    expect(downloaded, isNotNull);
    expect(downloaded!.downloadStatus, kMediaDownloadStatusDone);
    expect(File(downloaded.localPath!).readAsBytesSync(), equals(voiceBytes));
    // Voice metadata rides the attachment, never the transport.
    expect(downloaded.durationMs, 4200);
    expect(downloaded.waveform, const [0.2, 0.7, 0.4]);
  });

  test(
    'share-built attachment round-trips through the same decrypt path',
    () async {
      // Pin (Phase 2.4): the share coordinator's attachments come from the
      // same uploadMedia and decrypt through the same receiver path —
      // including arbitrary shared-file mimes.
      final sharedBytes = List<int>.generate(640, (index) => (index * 3) % 251);
      final sharedFile = File('${tempDir.path}/shared.pdf');
      await sharedFile.writeAsBytes(sharedBytes, flush: true);

      final uploaded = (await uploadMedia(
        bridge: aliceBridge,
        localFilePath: sharedFile.path,
        mime: 'application/pdf',
        recipientPeerId: _bobPeerId,
      )).attachmentOrNull;
      expect(uploaded, isNotNull);
      expect(uploaded!.mediaType, 'file');
      expect(relayStore[uploaded.id], isNot(equals(sharedBytes)));

      await seedOrdinaryIncomingParent('msg-share-rt');

      await bobMediaRepo.saveAttachment(
        uploaded.copyWith(
          messageId: 'msg-share-rt',
          downloadStatus: 'pending',
          clearLocalPath: true,
        ),
        owner: MediaOwnerLane.direct,
      );
      final persisted = (await bobMediaRepo.getPendingDownloads()).single;
      final downloaded = await downloadMedia(
        bridge: bobBridge,
        mediaAttachmentRepo: bobMediaRepo,
        mediaFileManager: bobFileManager,
        attachment: persisted,
        contactPeerId: _alicePeerId,
        owner: MediaOwnerLane.direct,
        messageRepo: bobMessageRepo,
      );

      expect(downloaded, isNotNull);
      expect(downloaded!.downloadStatus, kMediaDownloadStatusDone);
      expect(
        File(downloaded.localPath!).readAsBytesSync(),
        equals(sharedBytes),
      );
    },
  );
}
