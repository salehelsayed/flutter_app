import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../helpers/group_private_media_lifecycle_test_fixture.dart';

const _privateKey = 'cGxhbi0yMzgtc2VlZC1rZXk=';
const _privateNonce = 'cGxhbi0yMzgtbm9uY2U=';
const _jpegBytes = <int>[0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10];

List<int> _encryptedBytes(List<int> plaintext) => <int>[
  ...'cipher:$_privateKey:$_privateNonce:'.codeUnits,
  ...plaintext.reversed,
];

class _GroupPrivateDownloadBridge implements Bridge {
  _GroupPrivateDownloadBridge({
    required this.plaintext,
    Future<void> Function()? afterDecrypt,
  }) : encrypted = _encryptedBytes(plaintext),
       _afterDecrypt = afterDecrypt;

  final List<int> plaintext;
  final List<int> encrypted;
  final Future<void> Function()? _afterDecrypt;
  int sendCallCount = 0;

  @override
  Future<String> send(String message) async {
    sendCallCount++;
    final request = jsonDecode(message) as Map<String, dynamic>;
    final payload = request['payload'] as Map<String, dynamic>? ?? const {};
    switch (request['cmd']) {
      case 'media:download':
        final outputPath = payload['outputPath'] as String;
        final file = File(outputPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(encrypted, flush: true);
        return jsonEncode(<String, Object?>{
          'ok': true,
          'size': encrypted.length,
          'mime': 'image/jpeg',
        });
      case 'blob:decrypt':
        final encryptedPath = payload['filePath'] as String;
        final decryptedPath = '$encryptedPath.dec';
        await File(decryptedPath).writeAsBytes(plaintext, flush: true);
        await _afterDecrypt?.call();
        return jsonEncode(<String, Object?>{
          'ok': true,
          'decryptedPath': decryptedPath,
        });
      default:
        return jsonEncode(<String, Object?>{
          'ok': false,
          'errorMessage': 'unexpected command',
        });
    }
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  bool get isInitialized => true;

  @override
  void Function(ChatMessage)? onMessageReceived;

  @override
  void Function(ConnectionState)? onPeerConnected;

  @override
  void Function(ConnectionState)? onPeerDisconnected;

  @override
  void Function(List<String>, List<String>)? onAddressesUpdated;

  @override
  void Function(Map<String, dynamic>)? onRelayStateChanged;

  @override
  void Function(Map<String, dynamic>)? onGroupMessageReceived;

  @override
  void Function(Map<String, dynamic>)? onGroupReactionReceived;
}

void main() {
  test(
    'GPL-08 cleanup is scoped durable and replay cannot resurrect private media',
    () async {
      final fixture = await GroupPrivateMediaLifecycleTestFixture.create(
        nowMs: 3000,
      );
      addTearDown(fixture.dispose);

      const messageId = 'gpl08-terminal';
      const attachmentId = 'gpl08-terminal-att';
      await fixture.seedParent(
        messageId: messageId,
        policy: const GroupPrivateMediaPolicy.viewOnce(),
        receivedAt: 1000,
        lastCheckedAt: 2000,
        consumedAt: 2000,
        cleanupPending: true,
      );
      final target = await fixture.seedAttachment(
        messageId: messageId,
        attachmentId: attachmentId,
        isBookmarked: true,
        lastPlaybackPositionMs: 321,
      );

      final pendingBase = p.join(
        FakeMediaFileManager.testRootPath,
        MediaFilePathConvention.relativePathForPendingUpload(
          messageId: messageId,
          attachmentId: attachmentId,
          mime: 'image/jpeg',
        ),
      );
      final exactArtifacts = <String>{
        target.absolutePath,
        '${target.absolutePath}.part',
        '${target.absolutePath}.enc',
        '${target.absolutePath}.enc.part',
        pendingBase,
        '$pendingBase.part',
        '$pendingBase.enc',
        '$pendingBase.enc.part',
      };
      for (final path in exactArtifacts) {
        final file = File(path);
        file.createSync(recursive: true);
        file.writeAsBytesSync(const <int>[7, 8, 9]);
      }

      final sameDirectorySibling = File(
        p.join(p.dirname(target.absolutePath), 'gpl08-unrelated-sibling.jpg'),
      )..writeAsBytesSync(const <int>[5, 5, 5]);
      addTearDown(() {
        if (sameDirectorySibling.existsSync()) {
          sameDirectorySibling.deleteSync();
        }
      });
      final exportedRoot = Directory.systemTemp.createTempSync(
        'gpl08-exported-',
      );
      addTearDown(() {
        if (exportedRoot.existsSync()) {
          exportedRoot.deleteSync(recursive: true);
        }
      });
      final exportedCopy = File(p.join(exportedRoot.path, 'exported.jpg'))
        ..writeAsBytesSync(const <int>[4, 4, 4]);

      const ordinaryMessageId = 'gpl08-ordinary-sibling-parent';
      await fixture.seedParent(
        messageId: ordinaryMessageId,
        policy: const GroupPrivateMediaPolicy.ordinary(),
      );
      final ordinarySibling = await fixture.seedAttachment(
        messageId: ordinaryMessageId,
        attachmentId: 'gpl08-ordinary-sibling-att',
      );

      await fixture.mediaFixture.seedDirectParent(messageId);
      const directSiblingId = 'gpl08-direct-lane-sibling';
      await fixture.mediaFixture.repo.saveAttachment(
        const MediaAttachment(
          id: directSiblingId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 3,
          mediaType: 'image',
          localPath: 'media/contact-1/gpl08-direct-lane-sibling.jpg',
          downloadStatus: 'done',
          createdAt: '2026-07-12T00:00:00.000Z',
          encryptionKeyBase64: 'ZGlyZWN0LWtleQ==',
          encryptionNonce: 'ZGlyZWN0LW5vbmNl',
        ),
        owner: MediaOwnerLane.direct,
      );

      final cleanup = await fixture.engine.reconcileLocalLifecycle();
      expect(cleanup.cleanupCompleted, 1);
      expect(cleanup.retainedAfterError, 0);
      for (final path in exactArtifacts) {
        expect(File(path).existsSync(), isFalse, reason: path);
      }
      expect(sameDirectorySibling.existsSync(), isTrue);
      expect(exportedCopy.existsSync(), isTrue);
      expect(File(ordinarySibling.absolutePath).existsSync(), isTrue);
      expect(
        await fixture.mediaFixture.rawAttachmentRow(
          ordinarySibling.attachment.id,
        ),
        isNotNull,
      );
      expect(
        await fixture.mediaFixture.rawAttachmentRow(directSiblingId),
        isNotNull,
      );
      expect(await fixture.mediaFixture.rawAttachmentRow(attachmentId), isNull);
      expect(
        await fixture.mediaFixture.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
        isFalse,
      );

      final placeholder = await fixture.messageRepository
          .loadGroupPrivateMediaMessage(messageId);
      expect(placeholder, isNotNull);
      expect(placeholder!.mediaConsumedAt, 2000);
      expect(placeholder.mediaCleanupPending, isFalse);

      expect(
        await dbSaveGroupMediaAttachmentGuarded(
          fixture.db,
          target.attachment.copyWith(ownerLane: MediaOwnerLane.group).toMap(),
          groupId: 'group-1',
        ),
        isFalse,
        reason: 'offline/live replay cannot recreate a terminal attachment row',
      );
      expect(
        await dbBeginGroupPrivateMediaDownloadIfEligible(
          fixture.db,
          groupId: 'group-1',
          messageId: messageId,
          attachmentId: attachmentId,
          nowMs: 4000,
        ),
        0,
      );
      expect(
        await dbCommitGroupPrivateMediaDownloadIfEligible(
          fixture.db,
          groupId: 'group-1',
          messageId: messageId,
          attachmentId: attachmentId,
          localPath: target.relativePath,
          nowMs: 4000,
        ),
        0,
      );
      expect(
        await fixture.engine.qualifyOpen(
          groupId: 'group-1',
          messageId: messageId,
          attachmentId: attachmentId,
        ),
        isNull,
      );
      expect(await fixture.mediaFixture.rawAttachmentRow(attachmentId), isNull);
      expect(File(target.absolutePath).existsSync(), isFalse);
      expect(
        (await fixture.engine.reconcileLocalLifecycle()).cleanupCompleted,
        0,
      );
    },
  );

  test(
    'group private explicit download commits only through current-parent guarded CAS',
    () async {
      final fixture = await GroupPrivateMediaLifecycleTestFixture.create(
        nowMs: 1500,
      );
      addTearDown(fixture.dispose);
      final encrypted = _encryptedBytes(_jpegBytes);

      const messageId = 'gpl08-explicit-download';
      const attachmentId = 'gpl08-explicit-download-att';
      await fixture.seedParent(
        messageId: messageId,
        policy: const GroupPrivateMediaPolicy.viewOnce(),
        receivedAt: 1000,
        lastCheckedAt: 1000,
      );
      await fixture.seedAttachment(
        messageId: messageId,
        attachmentId: attachmentId,
        bytes: _jpegBytes,
        contentHash: sha256.convert(encrypted).toString(),
        downloadStatus: 'pending',
        includeLocalPath: false,
        createCanonicalFile: false,
      );
      final attachment =
          (await fixture.mediaFixture.repo.getAttachmentsForMessage(
            messageId,
            owner: MediaOwnerLane.group,
          )).single;
      final deniedBridge = _GroupPrivateDownloadBridge(plaintext: _jpegBytes);

      expect(
        await downloadMedia(
          bridge: deniedBridge,
          mediaAttachmentRepo: fixture.mediaFixture.repo,
          mediaFileManager: fixture.mediaFileManager,
          attachment: attachment,
          contactPeerId: 'group-1',
          owner: MediaOwnerLane.group,
          groupMessageRepo: fixture.messageRepository,
          intent: MediaDownloadIntent.automatic,
          enforceGroupMediaPolicy: true,
          nowMs: () => fixture.nowMs,
        ),
        isNull,
      );
      expect(
        await downloadMedia(
          bridge: deniedBridge,
          mediaAttachmentRepo: fixture.mediaFixture.repo,
          mediaFileManager: fixture.mediaFileManager,
          attachment: attachment,
          contactPeerId: 'group-1',
          owner: MediaOwnerLane.group,
          intent: MediaDownloadIntent.explicitUser,
          enforceGroupMediaPolicy: true,
          nowMs: () => fixture.nowMs,
        ),
        isNull,
      );
      expect(deniedBridge.sendCallCount, 0);
      var row = await fixture.mediaFixture.rawAttachmentRow(attachmentId);
      expect(row!['download_status'], 'pending');
      expect(row['local_path'], isNull);

      final successBridge = _GroupPrivateDownloadBridge(plaintext: _jpegBytes);
      final downloaded = await downloadMedia(
        bridge: successBridge,
        mediaAttachmentRepo: fixture.mediaFixture.repo,
        mediaFileManager: fixture.mediaFileManager,
        attachment: attachment,
        contactPeerId: 'group-1',
        owner: MediaOwnerLane.group,
        groupMessageRepo: fixture.messageRepository,
        intent: MediaDownloadIntent.explicitUser,
        enforceGroupMediaPolicy: true,
        nowMs: () => fixture.nowMs,
      );
      expect(downloaded, isNotNull);
      expect(successBridge.sendCallCount, 2);
      final successPath = fixture.mediaFileManager.relativePathForAttachment(
        contactPeerId: 'group-1',
        blobId: attachmentId,
        mime: 'image/jpeg',
      );
      row = await fixture.mediaFixture.rawAttachmentRow(attachmentId);
      expect(row!['download_status'], 'done');
      expect(row['local_path'], successPath);
      expect(await File(downloaded!.localPath!).readAsBytes(), _jpegBytes);

      expect(
        await fixture.messageRepository.consumeGroupPrivateMedia(
          messageId,
          nowMs: 2000,
        ),
        isTrue,
      );
      expect(
        (await fixture.engine.reconcileLocalLifecycle()).cleanupCompleted,
        1,
      );

      const expiringMessageId = 'gpl08-expiry-during-download';
      const expiringAttachmentId = 'gpl08-expiry-during-download-att';
      const deadline = 3601000;
      await fixture.seedParent(
        messageId: expiringMessageId,
        policy: GroupPrivateMediaPolicy.disappearing(3600),
        receivedAt: 1000,
        expiresAt: deadline,
        lastCheckedAt: 1000,
      );
      await fixture.seedAttachment(
        messageId: expiringMessageId,
        attachmentId: expiringAttachmentId,
        bytes: _jpegBytes,
        contentHash: sha256.convert(encrypted).toString(),
        downloadStatus: 'pending',
        includeLocalPath: false,
        createCanonicalFile: false,
      );
      final expiringAttachment =
          (await fixture.mediaFixture.repo.getAttachmentsForMessage(
            expiringMessageId,
            owner: MediaOwnerLane.group,
          )).single;
      final expiringBridge = _GroupPrivateDownloadBridge(
        plaintext: _jpegBytes,
        afterDecrypt: () async {
          fixture.nowMs = deadline;
          await fixture.messageRepository.advanceGroupPrivateMediaClock(
            expiringMessageId,
            nowMs: deadline,
          );
        },
      );
      expect(
        await downloadMedia(
          bridge: expiringBridge,
          mediaAttachmentRepo: fixture.mediaFixture.repo,
          mediaFileManager: fixture.mediaFileManager,
          attachment: expiringAttachment,
          contactPeerId: 'group-1',
          owner: MediaOwnerLane.group,
          groupMessageRepo: fixture.messageRepository,
          intent: MediaDownloadIntent.explicitUser,
          enforceGroupMediaPolicy: true,
          nowMs: () => fixture.nowMs,
        ),
        isNull,
      );
      final expiringRelative = fixture.mediaFileManager
          .relativePathForAttachment(
            contactPeerId: 'group-1',
            blobId: expiringAttachmentId,
            mime: 'image/jpeg',
          );
      final expiringCanonical = await fixture.mediaFileManager
          .resolveStoredPath(expiringRelative);
      expect(File(expiringCanonical).existsSync(), isFalse);
      expect(File('$expiringCanonical.enc').existsSync(), isFalse);
      expect(File('$expiringCanonical.enc.dec').existsSync(), isFalse);
      row = await fixture.mediaFixture.rawAttachmentRow(expiringAttachmentId);
      expect(row, isNotNull);
      expect(row!['local_path'], isNull);
      expect(row['download_status'], isNot('done'));
      final expiredParent = await fixture.messageRepository
          .loadGroupPrivateMediaMessage(expiringMessageId);
      expect(expiredParent!.mediaExpiredAt, deadline);
      expect(expiredParent.mediaCleanupPending, isTrue);
      expect(
        (await fixture.engine.reconcileLocalLifecycle()).cleanupCompleted,
        1,
      );
      expect(
        await fixture.mediaFixture.rawAttachmentRow(expiringAttachmentId),
        isNull,
      );
    },
  );
}
