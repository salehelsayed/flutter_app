import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/group_media_allowed_peers.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart'
    as group_send;
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/group_test_user.dart';

const _downloadedBytesHash =
    '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a';

class _DownloadWritingBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'media:download') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);

      final payload = parsed['payload'] as Map<String, dynamic>;
      final outputPath = payload['outputPath'] as String;
      final file = File(outputPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(<int>[1, 2, 3, 4]);

      return jsonEncode({'ok': true, 'id': payload['id'], 'size': 4});
    }
    return super.send(message);
  }
}

class _FailingDownloadBridge extends _DownloadWritingBridge {
  _FailingDownloadBridge({required Set<String> failingBlobIds})
    : _failingBlobIds = failingBlobIds;

  final Set<String> _failingBlobIds;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'media:download') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      final blobId = payload['id'] as String;
      if (_failingBlobIds.contains(blobId)) {
        sendCallCount++;
        lastSentMessage = message;
        sentMessages.add(message);
        lastCommand = cmd;
        commandLog.add(cmd!);
        return jsonEncode({
          'ok': false,
          'id': blobId,
          'errorMessage': 'forced download failure for $blobId',
        });
      }
    }
    return super.send(message);
  }
}

class _ScopedMediaFileManager extends FakeMediaFileManager {
  _ScopedMediaFileManager(String scope)
    : _root = Directory(p.join(Directory.systemTemp.path, 'test_docs', scope));

  final Directory _root;

  @override
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) async {
    final relativePath = relativePathForAttachment(
      contactPeerId: contactPeerId,
      blobId: blobId,
      mime: mime,
    );
    final absolutePath = p.join(_root.path, relativePath);
    final file = File(absolutePath);
    await file.parent.create(recursive: true);
    return absolutePath;
  }

  @override
  Future<String> resolveStoredPath(String storedPath) async {
    if (storedPath.startsWith('pending_uploads/') ||
        storedPath.startsWith('pending_uploads\\') ||
        storedPath.startsWith('media/') ||
        storedPath.startsWith('media\\') ||
        storedPath.startsWith('post_media/') ||
        storedPath.startsWith('post_media\\')) {
      return p.join(_root.path, storedPath);
    }
    return storedPath;
  }
}

void main() {
  late FakeGroupPubSubNetwork network;

  setUp(() {
    network = FakeGroupPubSubNetwork();
  });

  Future<void> pump() => Future.delayed(const Duration(milliseconds: 50));

  MediaAttachment attachment({
    required String id,
    required String mime,
    required int size,
    int? width,
    int? height,
    int? durationMs,
    List<double>? waveform,
    String contentHash = _downloadedBytesHash,
  }) {
    return MediaAttachment(
      id: id,
      messageId: '',
      mime: mime,
      size: size,
      mediaType: MediaAttachment.mediaTypeFromMime(mime),
      width: width,
      height: height,
      durationMs: durationMs,
      localPath: 'pending_uploads/$id',
      downloadStatus: 'done',
      contentHash: contentHash,
      encryptionKeyBase64: 'key-$id',
      encryptionNonce: 'nonce-$id',
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      createdAt: '2026-04-29T00:00:00.000Z',
      waveform: waveform,
    );
  }

  Future<void> waitForDownloads({
    required GroupTestUser user,
    required int expectedCount,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      final downloadCount = user.bridge.commandLog
          .where((cmd) => cmd == 'media:download')
          .length;
      if (downloadCount >= expectedCount) return;
      await pump();
    }
    fail(
      'Expected $expectedCount media download attempts for ${user.username}',
    );
  }

  Future<void> waitForDownloadedAttachments({
    required GroupTestUser user,
    required String groupId,
    required List<String> messageTexts,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      final messages = await user.loadGroupMessages(groupId);
      var allDone = true;
      for (final messageText in messageTexts) {
        final matches = messages
            .where(
              (message) => message.isIncoming && message.text == messageText,
            )
            .toList();
        if (matches.length != 1) {
          allDone = false;
          break;
        }

        final attachments = await user.mediaAttachmentRepo
            .getAttachmentsForMessage(matches.single.id);
        if (attachments.length != 1 ||
            attachments.single.downloadStatus != 'done' ||
            attachments.single.localPath == null) {
          allDone = false;
          break;
        }
      }

      if (allDone) return;
      await pump();
    }

    fail('Expected downloaded media attachments for ${user.username}');
  }

  Future<void> waitForAttachmentStatus({
    required GroupTestUser user,
    required String messageId,
    required String expectedStatus,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      final attachments = await user.mediaAttachmentRepo
          .getAttachmentsForMessage(messageId);
      if (attachments.length == 1 &&
          attachments.single.downloadStatus == expectedStatus) {
        return;
      }
      await pump();
    }

    fail(
      'Expected attachment $messageId to reach $expectedStatus for '
      '${user.username}',
    );
  }

  Future<void> saveLatestKey({
    required GroupTestUser user,
    required String groupId,
    required int epoch,
  }) async {
    await user.groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: epoch,
        encryptedKey: 'group-key-epoch-$epoch',
        createdAt: DateTime.utc(2026, 4, 29).add(Duration(minutes: epoch)),
      ),
    );
  }

  Future<MediaAttachment> expectSingleAttachment({
    required GroupTestUser user,
    required String groupId,
    required String messageText,
    required MediaAttachment sent,
    required bool expectDownloaded,
  }) async {
    final received = (await user.loadGroupMessages(groupId))
        .where((message) => message.isIncoming && message.text == messageText)
        .single;
    final attachments = await user.mediaAttachmentRepo.getAttachmentsForMessage(
      received.id,
    );
    expect(attachments, hasLength(1), reason: '${user.username}: $messageText');

    final actual = attachments.single;
    expect(actual.id, sent.id, reason: user.username);
    expect(actual.mediaType, sent.mediaType, reason: user.username);
    expect(actual.mime, sent.mime, reason: user.username);
    expect(actual.width, sent.width, reason: user.username);
    expect(actual.height, sent.height, reason: user.username);
    expect(actual.durationMs, sent.durationMs, reason: user.username);
    expect(actual.waveform, sent.waveform, reason: user.username);
    expect(actual.contentHash, sent.contentHash, reason: user.username);
    expect(
      actual.encryptionKeyBase64,
      sent.encryptionKeyBase64,
      reason: user.username,
    );
    expect(actual.encryptionNonce, sent.encryptionNonce, reason: user.username);
    expect(
      actual.encryptionScheme,
      sent.encryptionScheme,
      reason: user.username,
    );
    if (expectDownloaded) {
      expect(actual.downloadStatus, 'done', reason: user.username);
      expect(actual.localPath, isNotNull, reason: user.username);
    }
    return actual;
  }

  Future<void> expectOutgoingAttachment({
    required GroupTestUser user,
    required String groupId,
    required String messageText,
    required MediaAttachment sent,
  }) async {
    final outgoing = (await user.loadGroupMessages(groupId))
        .where((message) => !message.isIncoming && message.text == messageText)
        .single;
    expect(outgoing.status, isNot('failed'));

    final attachments = await user.mediaAttachmentRepo.getAttachmentsForMessage(
      outgoing.id,
    );
    expect(attachments, hasLength(1), reason: '$messageText outgoing');

    final actual = attachments.single;
    expect(actual.id, sent.id);
    expect(actual.mediaType, sent.mediaType);
    expect(actual.mime, sent.mime);
    expect(actual.width, sent.width);
    expect(actual.height, sent.height);
    expect(actual.durationMs, sent.durationMs);
    expect(actual.waveform, sent.waveform);
    expect(actual.contentHash, sent.contentHash);
    expect(actual.encryptionKeyBase64, sent.encryptionKeyBase64);
    expect(actual.encryptionNonce, sent.encryptionNonce);
    expect(actual.encryptionScheme, sent.encryptionScheme);
  }

  group('Existing-member group media fan-out', () {
    test(
      'discussion members independently download image, video, and voice for every eligible recipient',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-media-fanout-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-media-fanout-peer',
          username: 'Bob',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: _ScopedMediaFileManager('bob-existing-fanout'),
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-media-fanout-peer',
          username: 'Charlie',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: _ScopedMediaFileManager('charlie-existing-fanout'),
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-existing-media-fanout';
        await alice.createGroup(
          groupId: groupId,
          name: 'Existing Media Fanout',
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);

        alice.start();
        bob.start();
        charlie.start();
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        final image = attachment(
          id: 'blob-existing-member-image',
          mime: 'image/jpeg',
          size: 4,
          width: 640,
          height: 480,
        );
        final (imageResult, imageMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'existing-member image',
              mediaAttachments: [image],
            );
        expect(imageResult, group_send.SendGroupMessageResult.success);
        expect(imageMessage, isNotNull);

        final video = attachment(
          id: 'blob-existing-member-video',
          mime: 'video/mp4',
          size: 4,
          width: 1280,
          height: 720,
          durationMs: 12_000,
        );
        final (videoResult, videoMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'existing-member video',
              mediaAttachments: [video],
            );
        expect(videoResult, group_send.SendGroupMessageResult.success);
        expect(videoMessage, isNotNull);

        final voice = attachment(
          id: 'blob-existing-member-voice',
          mime: 'audio/mp4',
          size: 4,
          durationMs: 3500,
          waveform: const <double>[0.1, 0.4, 0.2],
        );
        final (voiceResult, voiceMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'existing-member voice',
              mediaAttachments: [voice],
            );
        expect(voiceResult, group_send.SendGroupMessageResult.success);
        expect(voiceMessage, isNotNull);

        const mediaTexts = [
          'existing-member image',
          'existing-member video',
          'existing-member voice',
        ];
        for (final receiver in [bob, charlie]) {
          await waitForDownloads(user: receiver, expectedCount: 3);
          await waitForDownloadedAttachments(
            user: receiver,
            groupId: groupId,
            messageTexts: mediaTexts,
          );
        }

        for (final receiver in [bob, charlie]) {
          final incoming = (await receiver.loadGroupMessages(
            groupId,
          )).where((message) => message.isIncoming).toList();
          expect(
            incoming.map((message) => message.text),
            containsAllInOrder([
              'existing-member image',
              'existing-member video',
              'existing-member voice',
            ]),
            reason: receiver.username,
          );

          expect(
            incoming
                .where((message) => message.text == 'existing-member image')
                .single
                .id,
            imageMessage!.id,
            reason: receiver.username,
          );
          expect(
            incoming
                .where((message) => message.text == 'existing-member video')
                .single
                .id,
            videoMessage!.id,
            reason: receiver.username,
          );
          expect(
            incoming
                .where((message) => message.text == 'existing-member voice')
                .single
                .id,
            voiceMessage!.id,
            reason: receiver.username,
          );

          await expectSingleAttachment(
            user: receiver,
            groupId: groupId,
            messageText: 'existing-member image',
            sent: image,
            expectDownloaded: true,
          );
          await expectSingleAttachment(
            user: receiver,
            groupId: groupId,
            messageText: 'existing-member video',
            sent: video,
            expectDownloaded: true,
          );
          await expectSingleAttachment(
            user: receiver,
            groupId: groupId,
            messageText: 'existing-member voice',
            sent: voice,
            expectDownloaded: true,
          );
        }

        for (final receiver in [bob, charlie]) {
          expect(
            receiver.bridge.commandLog.where((cmd) => cmd == 'media:download'),
            hasLength(3),
            reason: receiver.username,
          );
        }
      },
    );

    test(
      'PL-002 fake-network media-only message reaches recipients with empty text',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-pl002-media-only-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-pl002-media-only-peer',
          username: 'Bob',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: _ScopedMediaFileManager('bob-pl002-media-only'),
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-pl002-media-only-peer',
          username: 'Charlie',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: _ScopedMediaFileManager('charlie-pl002-media-only'),
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-pl002-media-only';
        await alice.createGroup(groupId: groupId, name: 'PL002 Media Only');
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveLatestKey(user: alice, groupId: groupId, epoch: 1);
        await saveLatestKey(user: bob, groupId: groupId, epoch: 1);
        await saveLatestKey(user: charlie, groupId: groupId, epoch: 1);

        alice.start();
        bob.start();
        charlie.start();
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        final voice = attachment(
          id: 'blob-pl002-media-only-voice',
          mime: 'audio/mp4',
          size: 4,
          durationMs: 2200,
          waveform: const <double>[0.2, 0.6, 0.4],
        );
        final (result, sentMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: '',
          messageId: 'msg-pl002-media-only',
          mediaAttachments: [voice],
        );
        expect(result, group_send.SendGroupMessageResult.success);
        expect(sentMessage, isNotNull);
        expect(sentMessage!.text, '');

        for (final receiver in [bob, charlie]) {
          await waitForDownloads(user: receiver, expectedCount: 1);
          await waitForDownloadedAttachments(
            user: receiver,
            groupId: groupId,
            messageTexts: const [''],
          );

          final incoming = (await receiver.loadGroupMessages(groupId))
              .where((message) => message.isIncoming && message.text == '')
              .toList(growable: false);
          expect(incoming, hasLength(1), reason: receiver.username);
          expect(incoming.single.id, sentMessage.id, reason: receiver.username);

          await expectSingleAttachment(
            user: receiver,
            groupId: groupId,
            messageText: '',
            sent: voice,
            expectDownloaded: true,
          );
        }

        await expectOutgoingAttachment(
          user: alice,
          groupId: groupId,
          messageText: '',
          sent: voice,
        );
        final messageDeliveryRecords = network.deliveryRecords
            .where((record) => record['messageId'] == 'msg-pl002-media-only')
            .toList(growable: false);
        expect(messageDeliveryRecords, hasLength(2));
        expect(
          messageDeliveryRecords.map((record) => record['receiverPeerId']),
          containsAll([
            'bob-pl002-media-only-peer',
            'charlie-pl002-media-only-peer',
          ]),
        );
      },
    );

    test(
      'PL-012 fake-network media schema variants survive fanout and downloads',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-pl012-media-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-pl012-media-peer',
          username: 'Bob',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: _ScopedMediaFileManager('bob-pl012-media'),
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-pl012-media-peer',
          username: 'Charlie',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: _ScopedMediaFileManager('charlie-pl012-media'),
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-pl012-media-schema';
        const messageText = 'PL-012 schema variants';
        const messageId = 'msg-pl012-media-schema';
        await alice.createGroup(groupId: groupId, name: 'PL012 Media Schema');
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveLatestKey(user: alice, groupId: groupId, epoch: 1);
        await saveLatestKey(user: bob, groupId: groupId, epoch: 1);
        await saveLatestKey(user: charlie, groupId: groupId, epoch: 1);

        alice.start();
        bob.start();
        charlie.start();
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        final variants = <MediaAttachment>[
          attachment(
            id: 'blob-pl012-image',
            mime: 'image/jpeg',
            size: 4,
            width: 800,
            height: 600,
          ),
          attachment(
            id: 'blob-pl012-gif',
            mime: 'image/gif',
            size: 4,
            width: 320,
            height: 240,
          ),
          attachment(
            id: 'blob-pl012-file',
            mime: 'application/octet-stream',
            size: 4,
          ),
          attachment(
            id: 'blob-pl012-video',
            mime: 'video/mp4',
            size: 4,
            width: 1280,
            height: 720,
            durationMs: 12000,
          ),
          attachment(
            id: 'blob-pl012-voice',
            mime: 'audio/mp4',
            size: 4,
            durationMs: 3300,
            waveform: const <double>[0.1, 0.4, 0.2],
          ),
        ];

        final (result, sentMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: messageText,
          messageId: messageId,
          mediaAttachments: variants,
        );
        expect(result, group_send.SendGroupMessageResult.success);
        expect(sentMessage, isNotNull);

        Future<void> expectVariantSchema(GroupTestUser user) async {
          final incoming = (await user.loadGroupMessages(groupId))
              .where(
                (message) => message.isIncoming && message.text == messageText,
              )
              .single;
          expect(incoming.id, sentMessage!.id, reason: user.username);
          final attachments = await user.mediaAttachmentRepo
              .getAttachmentsForMessage(incoming.id);
          expect(
            attachments,
            hasLength(variants.length),
            reason: user.username,
          );
          final byId = {
            for (final attachment in attachments) attachment.id: attachment,
          };
          for (final expected in variants) {
            final actual = byId[expected.id];
            expect(
              actual,
              isNotNull,
              reason: '${user.username} ${expected.id}',
            );
            expect(actual!.mime, expected.mime, reason: user.username);
            expect(actual.mediaType, expected.mediaType, reason: user.username);
            expect(actual.width, expected.width, reason: user.username);
            expect(actual.height, expected.height, reason: user.username);
            expect(
              actual.durationMs,
              expected.durationMs,
              reason: user.username,
            );
            expect(actual.waveform, expected.waveform, reason: user.username);
            expect(
              actual.contentHash,
              expected.contentHash,
              reason: user.username,
            );
            expect(
              actual.encryptionKeyBase64,
              expected.encryptionKeyBase64,
              reason: user.username,
            );
            expect(
              actual.encryptionNonce,
              expected.encryptionNonce,
              reason: user.username,
            );
            expect(
              actual.encryptionScheme,
              expected.encryptionScheme,
              reason: user.username,
            );
            expect(actual.downloadStatus, 'done', reason: user.username);
            expect(actual.localPath, isNotNull, reason: user.username);
          }
        }

        for (final receiver in [bob, charlie]) {
          await waitForDownloads(
            user: receiver,
            expectedCount: variants.length,
          );
          await expectVariantSchema(receiver);
        }

        final outgoing = (await alice.loadGroupMessages(groupId))
            .where(
              (message) => !message.isIncoming && message.text == messageText,
            )
            .single;
        final outgoingAttachments = await alice.mediaAttachmentRepo
            .getAttachmentsForMessage(outgoing.id);
        expect(outgoingAttachments, hasLength(variants.length));

        final deliveryRecords = network.deliveryRecords
            .where((record) => record['messageId'] == messageId)
            .toList(growable: false);
        expect(deliveryRecords, hasLength(2));
      },
    );

    test(
      'one recipient media download failure remains observable per recipient',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-one-recipient-failure-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-one-recipient-failure-peer',
          username: 'Bob',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: _ScopedMediaFileManager(
            'bob-one-recipient-failure',
          ),
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-one-recipient-failure-peer',
          username: 'Charlie',
          network: network,
          bridge: _FailingDownloadBridge(
            failingBlobIds: {'blob-one-recipient-failure-image'},
          ),
          mediaFileManager: _ScopedMediaFileManager(
            'charlie-one-recipient-failure',
          ),
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-existing-media-one-recipient-failure';
        await alice.createGroup(
          groupId: groupId,
          name: 'One Recipient Media Failure',
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);

        alice.start();
        bob.start();
        charlie.start();
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        final image = attachment(
          id: 'blob-one-recipient-failure-image',
          mime: 'image/jpeg',
          size: 4,
          width: 640,
          height: 480,
        );
        final (imageResult, imageMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'one-recipient-failure image',
              mediaAttachments: [image],
            );
        expect(imageResult, group_send.SendGroupMessageResult.success);
        expect(imageMessage, isNotNull);

        final video = attachment(
          id: 'blob-one-recipient-failure-video',
          mime: 'video/mp4',
          size: 4,
          width: 1280,
          height: 720,
          durationMs: 12_000,
        );
        final (videoResult, videoMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'one-recipient-failure video',
              mediaAttachments: [video],
            );
        expect(videoResult, group_send.SendGroupMessageResult.success);
        expect(videoMessage, isNotNull);

        final voice = attachment(
          id: 'blob-one-recipient-failure-voice',
          mime: 'audio/mp4',
          size: 4,
          durationMs: 3500,
          waveform: const <double>[0.1, 0.4, 0.2],
        );
        final (voiceResult, voiceMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'one-recipient-failure voice',
              mediaAttachments: [voice],
            );
        expect(voiceResult, group_send.SendGroupMessageResult.success);
        expect(voiceMessage, isNotNull);

        for (final receiver in [bob, charlie]) {
          await waitForDownloads(user: receiver, expectedCount: 3);
        }
        await waitForDownloadedAttachments(
          user: bob,
          groupId: groupId,
          messageTexts: const [
            'one-recipient-failure image',
            'one-recipient-failure video',
            'one-recipient-failure voice',
          ],
        );
        await waitForDownloadedAttachments(
          user: charlie,
          groupId: groupId,
          messageTexts: const [
            'one-recipient-failure video',
            'one-recipient-failure voice',
          ],
        );

        for (final receiver in [bob, charlie]) {
          final incoming = (await receiver.loadGroupMessages(
            groupId,
          )).where((message) => message.isIncoming).toList();
          expect(
            incoming
                .where(
                  (message) => message.text == 'one-recipient-failure image',
                )
                .single
                .id,
            imageMessage!.id,
            reason: receiver.username,
          );
          expect(
            incoming
                .where(
                  (message) => message.text == 'one-recipient-failure video',
                )
                .single
                .id,
            videoMessage!.id,
            reason: receiver.username,
          );
          expect(
            incoming
                .where(
                  (message) => message.text == 'one-recipient-failure voice',
                )
                .single
                .id,
            voiceMessage!.id,
            reason: receiver.username,
          );
        }

        await expectSingleAttachment(
          user: bob,
          groupId: groupId,
          messageText: 'one-recipient-failure image',
          sent: image,
          expectDownloaded: true,
        );
        await expectSingleAttachment(
          user: bob,
          groupId: groupId,
          messageText: 'one-recipient-failure video',
          sent: video,
          expectDownloaded: true,
        );
        await expectSingleAttachment(
          user: bob,
          groupId: groupId,
          messageText: 'one-recipient-failure voice',
          sent: voice,
          expectDownloaded: true,
        );

        final charlieImage = await expectSingleAttachment(
          user: charlie,
          groupId: groupId,
          messageText: 'one-recipient-failure image',
          sent: image,
          expectDownloaded: false,
        );
        expect(charlieImage.downloadStatus, kMediaDownloadStatusFailed);
        expect(charlieImage.downloadStatus, isNot(kMediaDownloadStatusDone));
        expect(charlieImage.localPath, isNull);
        await expectSingleAttachment(
          user: charlie,
          groupId: groupId,
          messageText: 'one-recipient-failure video',
          sent: video,
          expectDownloaded: true,
        );
        await expectSingleAttachment(
          user: charlie,
          groupId: groupId,
          messageText: 'one-recipient-failure voice',
          sent: voice,
          expectDownloaded: true,
        );

        for (final receiver in [bob, charlie]) {
          expect(
            receiver.bridge.commandLog.where((cmd) => cmd == 'media:download'),
            hasLength(3),
            reason: receiver.username,
          );
        }
      },
    );

    test(
      'oversized fake-network media is not stored or downloaded by recipients',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-oversized-media-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-oversized-media-peer',
          username: 'Bob',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: FakeMediaFileManager(),
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
        });

        const groupId = 'group-oversized-media-fanout';
        await alice.createGroup(
          groupId: groupId,
          name: 'Oversized Media Fanout',
        );
        await alice.addMember(groupId: groupId, invitee: bob);

        alice.start();
        bob.start();
        await pump();

        await network.publish(groupId, alice.peerId, {
          'groupId': groupId,
          'senderId': alice.peerId,
          'senderUsername': alice.username,
          'keyEpoch': 0,
          'text': 'oversized fake-network media',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'messageId': 'msg-oversized-fake-network',
          'media': [
            attachment(
              id: 'blob-oversized-fake-network',
              mime: 'image/jpeg',
              size: kGroupMediaPerAttachmentLimitBytes + 1,
            ).toJson(),
          ],
        });
        await pump();

        final bobMessages = await bob.loadGroupMessages(groupId);
        expect(
          bobMessages.where(
            (message) => message.id == 'msg-oversized-fake-network',
          ),
          isEmpty,
        );
        expect(await bob.mediaAttachmentRepo.getPendingDownloads(), isEmpty);
        expect(bob.bridge.commandLog, isNot(contains('media:download')));
      },
    );

    test(
      'PL-005 fake-network media upload allowedPeers match active membership',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-pl005-media-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-pl005-media-peer',
          username: 'Bob',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: _ScopedMediaFileManager('bob-pl005-media'),
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-pl005-media-peer',
          username: 'Charlie',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: _ScopedMediaFileManager('charlie-pl005-media'),
        );
        final tempDir = await Directory.systemTemp.createTemp(
          'pl005_group_media_',
        );
        addTearDown(() async {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        const groupId = 'group-pl005-active-media';
        await alice.createGroup(groupId: groupId, name: 'PL005 Active Media');
        await saveLatestKey(user: alice, groupId: groupId, epoch: 1);
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveLatestKey(user: bob, groupId: groupId, epoch: 1);
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveLatestKey(user: charlie, groupId: groupId, epoch: 1);

        alice.start();
        bob.start();
        charlie.start();
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
        );
        await pump();

        final allowedPeers = groupMediaAllowedPeersForMembers(
          await alice.groupRepo.getMembers(groupId),
        );
        expect(allowedPeers, unorderedEquals([alice.peerId, bob.peerId]));
        expect(allowedPeers, isNot(contains(charlie.peerId)));
        expect(allowedPeers, isNot(contains('peer-dave-never-joined')));

        final localMedia = File(p.join(tempDir.path, 'pl005.bin'));
        await localMedia.writeAsBytes(<int>[1, 2, 3, 4]);
        final uploaded = await uploadMedia(
          bridge: alice.bridge,
          localFilePath: localMedia.path,
          mime: 'application/octet-stream',
          recipientPeerId: groupId,
          allowedPeers: allowedPeers,
          blobId: 'blob-pl005-active-media',
        );
        expect(uploaded, isNotNull);
        final uploadedAttachment = uploaded!;

        final uploadPayload = alice.bridge.sentMessages
            .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
            .where((message) => message['cmd'] == 'media:upload')
            .map((message) => message['payload'] as Map<String, dynamic>)
            .last;
        expect(uploadPayload['id'], 'blob-pl005-active-media');
        expect(uploadPayload['to'], groupId);
        expect(
          (uploadPayload['allowedPeers'] as List<dynamic>).cast<String>(),
          unorderedEquals([alice.peerId, bob.peerId]),
        );
        expect(
          (uploadPayload['allowedPeers'] as List<dynamic>).cast<String>(),
          isNot(contains(charlie.peerId)),
        );
        expect(
          (uploadPayload['allowedPeers'] as List<dynamic>).cast<String>(),
          isNot(contains('peer-dave-never-joined')),
        );

        network.resetCounters();
        final (result, sentMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'PL-005 active media',
          messageId: 'msg-pl005-active-media',
          mediaAttachments: [uploadedAttachment],
        );
        expect(result, group_send.SendGroupMessageResult.success);
        expect(sentMessage, isNotNull);
        expect(network.totalDeliveries, 1);

        await waitForDownloads(user: bob, expectedCount: 1);
        await waitForDownloadedAttachments(
          user: bob,
          groupId: groupId,
          messageTexts: const ['PL-005 active media'],
        );
        await expectSingleAttachment(
          user: bob,
          groupId: groupId,
          messageText: 'PL-005 active media',
          sent: uploadedAttachment,
          expectDownloaded: true,
        );

        final charlieMessages = await charlie.loadGroupMessages(groupId);
        expect(
          charlieMessages.where((message) => message.id == sentMessage!.id),
          isEmpty,
        );
        expect(
          await charlie.mediaAttachmentRepo.getPendingDownloads(),
          isEmpty,
        );
        expect(charlie.bridge.commandLog, isNot(contains('media:download')));

        final deliveryRecords = network.deliveryRecords
            .where((record) => record['messageId'] == 'msg-pl005-active-media')
            .toList(growable: false);
        expect(deliveryRecords, hasLength(1));
        expect(deliveryRecords.single['receiverPeerId'], bob.peerId);
      },
    );

    test(
      'PL-006 MD-011 removed member is excluded from future media descriptors and downloads',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-md011-media-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-md011-media-peer',
          username: 'Bob',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: FakeMediaFileManager(),
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-md011-media-peer',
          username: 'Charlie',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: FakeMediaFileManager(),
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-md011-removed-media-exclusion';
        await alice.createGroup(groupId: groupId, name: 'MD011 Media');
        await saveLatestKey(user: alice, groupId: groupId, epoch: 1);
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveLatestKey(user: bob, groupId: groupId, epoch: 1);
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveLatestKey(user: charlie, groupId: groupId, epoch: 1);

        alice.start();
        bob.start();
        charlie.start();
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
        );
        await pump();

        await saveLatestKey(user: alice, groupId: groupId, epoch: 2);
        await saveLatestKey(user: bob, groupId: groupId, epoch: 2);

        expect(
          (await alice.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId),
          unorderedEquals([alice.peerId, bob.peerId]),
        );
        expect(
          (await bob.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId),
          unorderedEquals([alice.peerId, bob.peerId]),
        );
        expect(await charlie.groupRepo.getGroup(groupId), isNull);
        expect(await charlie.groupRepo.getKeyByGeneration(groupId, 2), isNull);
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

        network.resetCounters();
        final image = attachment(
          id: 'blob-md011-future-image',
          mime: 'image/jpeg',
          size: 4,
          width: 640,
          height: 480,
        );
        final (result, sentMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'MD-011 future media',
          messageId: 'msg-md011-future-media',
          timestamp: DateTime.utc(2026, 4, 29, 12),
          mediaAttachments: [image],
        );

        expect(result, group_send.SendGroupMessageResult.success);
        expect(sentMessage, isNotNull);
        expect(sentMessage!.keyGeneration, 2);
        expect(network.totalDeliveries, 1);

        await waitForDownloads(user: bob, expectedCount: 1);
        await waitForDownloadedAttachments(
          user: bob,
          groupId: groupId,
          messageTexts: const ['MD-011 future media'],
        );

        final bobIncoming = (await bob.loadGroupMessages(
          groupId,
        )).where((message) => message.id == sentMessage.id).single;
        expect(bobIncoming.isIncoming, isTrue);
        expect(bobIncoming.keyGeneration, 2);
        final bobAttachments = await bob.mediaAttachmentRepo
            .getAttachmentsForMessage(bobIncoming.id);
        expect(bobAttachments, hasLength(1));
        expect(bobAttachments.single.id, image.id);
        expect(
          bobAttachments.single.encryptionKeyBase64,
          image.encryptionKeyBase64,
        );
        expect(bobAttachments.single.downloadStatus, 'done');

        final charlieMessages = await charlie.loadGroupMessages(groupId);
        expect(
          charlieMessages.where((message) => message.id == sentMessage.id),
          isEmpty,
        );
        expect(
          charlieMessages.where(
            (message) => message.text == 'MD-011 future media',
          ),
          isEmpty,
        );
        expect(
          await charlie.mediaAttachmentRepo.getAttachmentsForMessage(
            sentMessage.id,
          ),
          isEmpty,
        );
        expect(
          await charlie.mediaAttachmentRepo.getPendingDownloads(),
          isEmpty,
        );
        expect(charlie.bridge.commandLog, isNot(contains('media:download')));
        expect(charlie.bridge.commandLog, isNot(contains('blob:decrypt')));

        final publishPayload = alice.bridge.sentMessages
            .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
            .where((message) => message['cmd'] == 'group:publish')
            .map((message) => message['payload'] as Map<String, dynamic>)
            .last;
        final publishedMedia = (publishPayload['media'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(publishedMedia, hasLength(1));
        expect(publishedMedia.single['id'], image.id);
        expect(
          publishedMedia.single['encryptionKeyBase64'],
          image.encryptionKeyBase64,
        );

        final inboxPayload = alice.bridge.sentMessages
            .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
            .where((message) => message['cmd'] == 'group:inboxStore')
            .map((message) => message['payload'] as Map<String, dynamic>)
            .last;
        expect(
          (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
          unorderedEquals([bob.peerId]),
        );
        final replayEnvelope =
            jsonDecode(inboxPayload['message'] as String)
                as Map<String, dynamic>;
        expect(replayEnvelope['keyEpoch'], 2);
        final replayPlaintext =
            jsonDecode(replayEnvelope['ciphertext'] as String)
                as Map<String, dynamic>;
        expect(replayPlaintext['keyEpoch'], 2);
        final replayMedia = (replayPlaintext['media'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(replayMedia.single['id'], image.id);
      },
    );

    test('PL-007 re-added member downloads only post-readd media', () async {
      final alice = GroupTestUser.create(
        peerId: 'alice-pl007-media-peer',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'bob-pl007-media-peer',
        username: 'Bob',
        network: network,
        bridge: _DownloadWritingBridge(),
        mediaFileManager: _ScopedMediaFileManager('bob-pl007-media'),
      );
      final charlie = GroupTestUser.create(
        peerId: 'charlie-pl007-media-peer',
        username: 'Charlie',
        network: network,
        bridge: _DownloadWritingBridge(),
        mediaFileManager: _ScopedMediaFileManager('charlie-pl007-media'),
      );
      addTearDown(() {
        alice.dispose();
        bob.dispose();
        charlie.dispose();
      });

      const groupId = 'group-pl007-readd-media-window';
      await alice.createGroup(groupId: groupId, name: 'PL007 Readd Media');
      await saveLatestKey(user: alice, groupId: groupId, epoch: 1);
      await alice.addMember(groupId: groupId, invitee: bob);
      await saveLatestKey(user: bob, groupId: groupId, epoch: 1);
      await alice.addMember(groupId: groupId, invitee: charlie);
      await saveLatestKey(user: charlie, groupId: groupId, epoch: 1);

      alice.start();
      bob.start();
      charlie.start();
      await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
      await pump();

      await alice.removeMember(
        groupId: groupId,
        memberPeerId: charlie.peerId,
        memberUsername: charlie.username,
      );
      await pump();

      await saveLatestKey(user: alice, groupId: groupId, epoch: 2);
      await saveLatestKey(user: bob, groupId: groupId, epoch: 2);

      expect(await charlie.groupRepo.getGroup(groupId), isNull);
      expect(await charlie.groupRepo.getKeyByGeneration(groupId, 2), isNull);
      expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

      network.resetCounters();
      final removedWindowMedia = attachment(
        id: 'blob-pl007-removed-window-image',
        mime: 'image/jpeg',
        size: 4,
        width: 320,
        height: 240,
      );
      final (removedResult, removedSent) = await alice
          .sendGroupMessageViaBridge(
            groupId: groupId,
            text: 'PL-007 removed-window media',
            messageId: 'msg-pl007-removed-window-media',
            timestamp: DateTime.now().toUtc().add(const Duration(seconds: 1)),
            mediaAttachments: [removedWindowMedia],
          );
      expect(removedResult, group_send.SendGroupMessageResult.success);
      expect(removedSent, isNotNull);
      expect(removedSent!.keyGeneration, 2);
      expect(network.totalDeliveries, 1);

      await waitForDownloads(user: bob, expectedCount: 1);
      await waitForDownloadedAttachments(
        user: bob,
        groupId: groupId,
        messageTexts: const ['PL-007 removed-window media'],
      );
      await expectSingleAttachment(
        user: bob,
        groupId: groupId,
        messageText: 'PL-007 removed-window media',
        sent: removedWindowMedia,
        expectDownloaded: true,
      );

      final charlieDuringRemovalMessages = await charlie.loadGroupMessages(
        groupId,
      );
      expect(
        charlieDuringRemovalMessages.where(
          (message) => message.id == removedSent.id,
        ),
        isEmpty,
      );
      expect(
        charlieDuringRemovalMessages.where(
          (message) => message.text == 'PL-007 removed-window media',
        ),
        isEmpty,
      );
      expect(
        await charlie.mediaAttachmentRepo.getAttachmentsForMessage(
          removedSent.id,
        ),
        isEmpty,
      );
      expect(await charlie.mediaAttachmentRepo.getPendingDownloads(), isEmpty);
      expect(charlie.bridge.commandLog, isNot(contains('media:download')));
      expect(charlie.bridge.commandLog, isNot(contains('blob:decrypt')));

      final removedInboxPayload = alice.bridge.sentMessages
          .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
          .where((message) => message['cmd'] == 'group:inboxStore')
          .map((message) => message['payload'] as Map<String, dynamic>)
          .last;
      expect(
        (removedInboxPayload['recipientPeerIds'] as List<dynamic>)
            .cast<String>(),
        unorderedEquals([bob.peerId]),
      );

      await alice.addMember(groupId: groupId, invitee: charlie);
      await saveLatestKey(user: charlie, groupId: groupId, epoch: 2);
      await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
      await pump();

      expect(
        (await alice.groupRepo.getMembers(
          groupId,
        )).map((member) => member.peerId),
        unorderedEquals([alice.peerId, bob.peerId, charlie.peerId]),
      );
      expect(
        (await charlie.groupRepo.getMembers(
          groupId,
        )).map((member) => member.peerId),
        unorderedEquals([alice.peerId, bob.peerId, charlie.peerId]),
      );
      expect(await charlie.groupRepo.getKeyByGeneration(groupId, 2), isNotNull);
      expect(network.isSubscribed(groupId, charlie.peerId), isTrue);

      network.resetCounters();
      final postReaddMedia = attachment(
        id: 'blob-pl007-post-readd-image',
        mime: 'image/png',
        size: 4,
        width: 640,
        height: 480,
      );
      final (postResult, postSent) = await alice.sendGroupMessageViaBridge(
        groupId: groupId,
        text: 'PL-007 post-readd media',
        messageId: 'msg-pl007-post-readd-media',
        timestamp: DateTime.now().toUtc().add(const Duration(seconds: 2)),
        mediaAttachments: [postReaddMedia],
      );
      expect(postResult, group_send.SendGroupMessageResult.success);
      expect(postSent, isNotNull);
      expect(postSent!.keyGeneration, 2);
      expect(network.totalDeliveries, 2);

      await waitForDownloads(user: bob, expectedCount: 2);
      await waitForDownloadedAttachments(
        user: bob,
        groupId: groupId,
        messageTexts: const [
          'PL-007 removed-window media',
          'PL-007 post-readd media',
        ],
      );
      await waitForDownloads(user: charlie, expectedCount: 1);
      await waitForDownloadedAttachments(
        user: charlie,
        groupId: groupId,
        messageTexts: const ['PL-007 post-readd media'],
      );

      await expectSingleAttachment(
        user: bob,
        groupId: groupId,
        messageText: 'PL-007 post-readd media',
        sent: postReaddMedia,
        expectDownloaded: true,
      );
      final charliePostAttachment = await expectSingleAttachment(
        user: charlie,
        groupId: groupId,
        messageText: 'PL-007 post-readd media',
        sent: postReaddMedia,
        expectDownloaded: true,
      );
      expect(charliePostAttachment.localPath, isNotNull);
      expect(await charlie.mediaAttachmentRepo.getPendingDownloads(), isEmpty);

      final charlieAfterReaddMessages = await charlie.loadGroupMessages(
        groupId,
      );
      expect(
        charlieAfterReaddMessages.where(
          (message) => message.id == removedSent.id,
        ),
        isEmpty,
      );
      expect(
        charlieAfterReaddMessages.where(
          (message) => message.text == 'PL-007 removed-window media',
        ),
        isEmpty,
      );
      expect(
        await charlie.mediaAttachmentRepo.getAttachmentsForMessage(
          removedSent.id,
        ),
        isEmpty,
      );

      final charlieDownloads = charlie.bridge.sentMessages
          .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
          .where((message) => message['cmd'] == 'media:download')
          .map((message) => message['payload'] as Map<String, dynamic>)
          .toList(growable: false);
      expect(
        charlieDownloads.map((payload) => payload['id'] as String?),
        contains(postReaddMedia.id),
      );
      expect(
        charlieDownloads.map((payload) => payload['id'] as String?),
        isNot(contains(removedWindowMedia.id)),
      );
      expect(
        charlie.bridge.sentMessages.where(
          (raw) =>
              raw.contains('"cmd":"blob:decrypt"') &&
              raw.contains(removedWindowMedia.id),
        ),
        isEmpty,
      );

      final postInboxPayload = alice.bridge.sentMessages
          .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
          .where((message) => message['cmd'] == 'group:inboxStore')
          .map((message) => message['payload'] as Map<String, dynamic>)
          .last;
      expect(
        (postInboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
        unorderedEquals([bob.peerId, charlie.peerId]),
      );
    });

    test(
      'tampered fake-network media download fails integrity before done',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-tampered-media-peer',
          username: 'Alice',
          network: network,
        );
        final bobMediaFileManager = FakeMediaFileManager();
        final bob = GroupTestUser.create(
          peerId: 'bob-tampered-media-peer',
          username: 'Bob',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: bobMediaFileManager,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
        });

        const groupId = 'group-tampered-media-fanout';
        await alice.createGroup(
          groupId: groupId,
          name: 'Tampered Media Fanout',
        );
        await alice.addMember(groupId: groupId, invitee: bob);

        alice.start();
        bob.start();
        await pump();

        final tampered = attachment(
          id: 'blob-tampered-fake-network',
          mime: 'image/jpeg',
          size: 4,
          contentHash:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        );
        await network.publish(groupId, alice.peerId, {
          'groupId': groupId,
          'senderId': alice.peerId,
          'senderUsername': alice.username,
          'keyEpoch': 0,
          'text': 'tampered fake-network media',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'messageId': 'msg-tampered-fake-network',
          'media': [tampered.toJson()],
        });

        await waitForDownloads(user: bob, expectedCount: 1);
        await waitForAttachmentStatus(
          user: bob,
          messageId: 'msg-tampered-fake-network',
          expectedStatus: kMediaDownloadStatusIntegrityFailed,
        );

        final received = (await bob.loadGroupMessages(
          groupId,
        )).where((message) => message.id == 'msg-tampered-fake-network').single;
        final attachments = await bob.mediaAttachmentRepo
            .getAttachmentsForMessage(received.id);
        expect(attachments, hasLength(1));
        expect(
          attachments.single.downloadStatus,
          kMediaDownloadStatusIntegrityFailed,
        );
        expect(attachments.single.localPath, isNull);

        final downloadedPath = await bobMediaFileManager.localPathForAttachment(
          contactPeerId: groupId,
          blobId: tampered.id,
          mime: tampered.mime,
        );
        expect(File(downloadedPath).existsSync(), isFalse);
        expect(
          bob.bridge.commandLog.where((cmd) => cmd == 'media:download'),
          hasLength(1),
        );
      },
    );

    test(
      'newly-added discussion member media reaches every eligible recipient',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-new-member-media-send-peer',
          username: 'Alice',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: _ScopedMediaFileManager('alice-new-member-send'),
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-new-member-media-send-peer',
          username: 'Charlie',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: _ScopedMediaFileManager('charlie-new-member-send'),
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-new-member-media-send-peer',
          username: 'Bob',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          charlie.dispose();
          bob.dispose();
        });

        const groupId = 'group-new-member-media-send';
        const epoch = 4;
        await alice.createGroup(
          groupId: groupId,
          name: 'New Member Media Send',
        );
        await saveLatestKey(user: alice, groupId: groupId, epoch: epoch);
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveLatestKey(user: charlie, groupId: groupId, epoch: epoch);

        alice.start();
        charlie.start();
        bob.start();

        await alice.addMember(groupId: groupId, invitee: bob);
        await saveLatestKey(user: bob, groupId: groupId, epoch: epoch);
        await alice.broadcastMemberAdded(groupId: groupId, newMember: bob);
        await pump();

        final image = attachment(
          id: 'blob-new-member-sent-image',
          mime: 'image/jpeg',
          size: 4,
          width: 800,
          height: 600,
        );
        final (imageResult, imageMessage) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'new-member image',
          mediaAttachments: [image],
        );
        expect(imageResult, group_send.SendGroupMessageResult.success);
        expect(imageMessage, isNotNull);

        final video = attachment(
          id: 'blob-new-member-sent-video',
          mime: 'video/mp4',
          size: 4,
          width: 1920,
          height: 1080,
          durationMs: 18_000,
        );
        final (videoResult, videoMessage) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'new-member video',
          mediaAttachments: [video],
        );
        expect(videoResult, group_send.SendGroupMessageResult.success);
        expect(videoMessage, isNotNull);

        final voice = attachment(
          id: 'blob-new-member-sent-voice',
          mime: 'audio/mp4',
          size: 4,
          durationMs: 4200,
          waveform: const <double>[0.2, 0.5, 0.3, 0.6],
        );
        final (voiceResult, voiceMessage) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'new-member voice',
          mediaAttachments: [voice],
        );
        expect(voiceResult, group_send.SendGroupMessageResult.success);
        expect(voiceMessage, isNotNull);

        const mediaTexts = [
          'new-member image',
          'new-member video',
          'new-member voice',
        ];
        for (final receiver in [alice, charlie]) {
          await waitForDownloads(user: receiver, expectedCount: 3);
          await waitForDownloadedAttachments(
            user: receiver,
            groupId: groupId,
            messageTexts: mediaTexts,
          );
        }

        await expectOutgoingAttachment(
          user: bob,
          groupId: groupId,
          messageText: 'new-member image',
          sent: image,
        );
        await expectOutgoingAttachment(
          user: bob,
          groupId: groupId,
          messageText: 'new-member video',
          sent: video,
        );
        await expectOutgoingAttachment(
          user: bob,
          groupId: groupId,
          messageText: 'new-member voice',
          sent: voice,
        );

        for (final receiver in [alice, charlie]) {
          final incoming = (await receiver.loadGroupMessages(
            groupId,
          )).where((message) => message.isIncoming).toList();
          expect(
            incoming.map((message) => message.text),
            containsAllInOrder([
              'new-member image',
              'new-member video',
              'new-member voice',
            ]),
            reason: receiver.username,
          );

          expect(
            incoming
                .where((message) => message.text == 'new-member image')
                .single
                .id,
            imageMessage!.id,
            reason: receiver.username,
          );
          final receivedImage = incoming
              .where((message) => message.text == 'new-member image')
              .single;
          expect(
            receivedImage.senderPeerId,
            bob.peerId,
            reason: receiver.username,
          );
          expect(
            receivedImage.senderUsername,
            bob.username,
            reason: receiver.username,
          );
          expect(receivedImage.keyGeneration, epoch, reason: receiver.username);
          expect(
            incoming
                .where((message) => message.text == 'new-member video')
                .single
                .id,
            videoMessage!.id,
            reason: receiver.username,
          );
          final receivedVideo = incoming
              .where((message) => message.text == 'new-member video')
              .single;
          expect(
            receivedVideo.senderPeerId,
            bob.peerId,
            reason: receiver.username,
          );
          expect(
            receivedVideo.senderUsername,
            bob.username,
            reason: receiver.username,
          );
          expect(receivedVideo.keyGeneration, epoch, reason: receiver.username);
          expect(
            incoming
                .where((message) => message.text == 'new-member voice')
                .single
                .id,
            voiceMessage!.id,
            reason: receiver.username,
          );
          final receivedVoice = incoming
              .where((message) => message.text == 'new-member voice')
              .single;
          expect(
            receivedVoice.senderPeerId,
            bob.peerId,
            reason: receiver.username,
          );
          expect(
            receivedVoice.senderUsername,
            bob.username,
            reason: receiver.username,
          );
          expect(receivedVoice.keyGeneration, epoch, reason: receiver.username);

          await expectSingleAttachment(
            user: receiver,
            groupId: groupId,
            messageText: 'new-member image',
            sent: image,
            expectDownloaded: true,
          );
          await expectSingleAttachment(
            user: receiver,
            groupId: groupId,
            messageText: 'new-member video',
            sent: video,
            expectDownloaded: true,
          );
          await expectSingleAttachment(
            user: receiver,
            groupId: groupId,
            messageText: 'new-member voice',
            sent: voice,
            expectDownloaded: true,
          );
        }

        for (final receiver in [alice, charlie]) {
          expect(
            receiver.bridge.commandLog.where((cmd) => cmd == 'media:download'),
            hasLength(3),
            reason: receiver.username,
          );
        }
      },
    );

    test(
      'existing non-creator discussion member media reaches creator and every eligible recipient',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-existing-non-creator-media-peer',
          username: 'Alice',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: _ScopedMediaFileManager(
            'alice-existing-non-creator-send',
          ),
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-existing-non-creator-media-peer',
          username: 'Bob',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: _ScopedMediaFileManager(
            'bob-existing-non-creator-send',
          ),
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-existing-non-creator-media-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-existing-non-creator-media-send';
        const epoch = 6;
        await alice.createGroup(
          groupId: groupId,
          name: 'Existing Non Creator Media Send',
        );
        await saveLatestKey(user: alice, groupId: groupId, epoch: epoch);
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveLatestKey(user: bob, groupId: groupId, epoch: epoch);
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveLatestKey(user: charlie, groupId: groupId, epoch: epoch);

        alice.start();
        bob.start();
        charlie.start();
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        final image = attachment(
          id: 'blob-existing-non-creator-image',
          mime: 'image/jpeg',
          size: 4,
          width: 800,
          height: 600,
        );
        final (imageResult, imageMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'existing-non-creator image',
              mediaAttachments: [image],
            );
        expect(imageResult, group_send.SendGroupMessageResult.success);
        expect(imageMessage, isNotNull);

        final video = attachment(
          id: 'blob-existing-non-creator-video',
          mime: 'video/mp4',
          size: 4,
          width: 1920,
          height: 1080,
          durationMs: 18_000,
        );
        final (videoResult, videoMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'existing-non-creator video',
              mediaAttachments: [video],
            );
        expect(videoResult, group_send.SendGroupMessageResult.success);
        expect(videoMessage, isNotNull);

        final voice = attachment(
          id: 'blob-existing-non-creator-voice',
          mime: 'audio/mp4',
          size: 4,
          durationMs: 4200,
          waveform: const <double>[0.2, 0.5, 0.3, 0.6],
        );
        final (voiceResult, voiceMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'existing-non-creator voice',
              mediaAttachments: [voice],
            );
        expect(voiceResult, group_send.SendGroupMessageResult.success);
        expect(voiceMessage, isNotNull);

        const mediaTexts = [
          'existing-non-creator image',
          'existing-non-creator video',
          'existing-non-creator voice',
        ];
        for (final receiver in [alice, bob]) {
          await waitForDownloads(user: receiver, expectedCount: 3);
          await waitForDownloadedAttachments(
            user: receiver,
            groupId: groupId,
            messageTexts: mediaTexts,
          );
        }

        await expectOutgoingAttachment(
          user: charlie,
          groupId: groupId,
          messageText: 'existing-non-creator image',
          sent: image,
        );
        await expectOutgoingAttachment(
          user: charlie,
          groupId: groupId,
          messageText: 'existing-non-creator video',
          sent: video,
        );
        await expectOutgoingAttachment(
          user: charlie,
          groupId: groupId,
          messageText: 'existing-non-creator voice',
          sent: voice,
        );

        for (final receiver in [alice, bob]) {
          final incoming = (await receiver.loadGroupMessages(
            groupId,
          )).where((message) => message.isIncoming).toList();
          expect(
            incoming.map((message) => message.text),
            containsAllInOrder(mediaTexts),
            reason: receiver.username,
          );

          final receivedImage = incoming
              .where((message) => message.text == 'existing-non-creator image')
              .single;
          expect(receivedImage.id, imageMessage!.id, reason: receiver.username);
          expect(
            receivedImage.senderPeerId,
            charlie.peerId,
            reason: receiver.username,
          );
          expect(
            receivedImage.senderUsername,
            charlie.username,
            reason: receiver.username,
          );
          expect(receivedImage.keyGeneration, epoch, reason: receiver.username);

          final receivedVideo = incoming
              .where((message) => message.text == 'existing-non-creator video')
              .single;
          expect(receivedVideo.id, videoMessage!.id, reason: receiver.username);
          expect(
            receivedVideo.senderPeerId,
            charlie.peerId,
            reason: receiver.username,
          );
          expect(
            receivedVideo.senderUsername,
            charlie.username,
            reason: receiver.username,
          );
          expect(receivedVideo.keyGeneration, epoch, reason: receiver.username);

          final receivedVoice = incoming
              .where((message) => message.text == 'existing-non-creator voice')
              .single;
          expect(receivedVoice.id, voiceMessage!.id, reason: receiver.username);
          expect(
            receivedVoice.senderPeerId,
            charlie.peerId,
            reason: receiver.username,
          );
          expect(
            receivedVoice.senderUsername,
            charlie.username,
            reason: receiver.username,
          );
          expect(receivedVoice.keyGeneration, epoch, reason: receiver.username);

          await expectSingleAttachment(
            user: receiver,
            groupId: groupId,
            messageText: 'existing-non-creator image',
            sent: image,
            expectDownloaded: true,
          );
          await expectSingleAttachment(
            user: receiver,
            groupId: groupId,
            messageText: 'existing-non-creator video',
            sent: video,
            expectDownloaded: true,
          );
          await expectSingleAttachment(
            user: receiver,
            groupId: groupId,
            messageText: 'existing-non-creator voice',
            sent: voice,
            expectDownloaded: true,
          );
        }

        for (final receiver in [alice, bob]) {
          expect(
            receiver.bridge.commandLog.where((cmd) => cmd == 'media:download'),
            hasLength(3),
            reason: receiver.username,
          );
        }
      },
    );
  });
}
