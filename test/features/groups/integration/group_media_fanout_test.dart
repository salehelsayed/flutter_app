import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart'
    as group_send;
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/group_test_user.dart';

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

  Future<void> expectSingleAttachment({
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
    if (expectDownloaded) {
      expect(actual.downloadStatus, 'done', reason: user.username);
      expect(actual.localPath, isNotNull, reason: user.username);
    }
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
  }

  group('Existing-member group media fan-out', () {
    test(
      'discussion members receive image, video, and voice descriptors',
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
          mediaFileManager: FakeMediaFileManager(),
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-media-fanout-peer',
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
          size: 2048,
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
          size: 4096,
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
          size: 1024,
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

        await waitForDownloads(user: bob, expectedCount: 3);

        for (final receiver in [bob, charlie]) {
          final expectDownloaded = receiver == bob;
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
            expectDownloaded: expectDownloaded,
          );
          await expectSingleAttachment(
            user: receiver,
            groupId: groupId,
            messageText: 'existing-member video',
            sent: video,
            expectDownloaded: expectDownloaded,
          );
          await expectSingleAttachment(
            user: receiver,
            groupId: groupId,
            messageText: 'existing-member voice',
            sent: voice,
            expectDownloaded: expectDownloaded,
          );
        }

        expect(
          bob.bridge.commandLog.where((cmd) => cmd == 'media:download'),
          hasLength(3),
        );
      },
    );

    test(
      'newly-added discussion member sends image, video, and voice to existing members',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-new-member-media-send-peer',
          username: 'Alice',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: FakeMediaFileManager(),
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-new-member-media-send-peer',
          username: 'Charlie',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: FakeMediaFileManager(),
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
          size: 3072,
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
          size: 8192,
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
          size: 2048,
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

        await waitForDownloads(user: alice, expectedCount: 3);

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
          final expectDownloaded = receiver == alice;
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
          expect(
            incoming
                .where((message) => message.text == 'new-member video')
                .single
                .id,
            videoMessage!.id,
            reason: receiver.username,
          );
          expect(
            incoming
                .where((message) => message.text == 'new-member voice')
                .single
                .id,
            voiceMessage!.id,
            reason: receiver.username,
          );

          await expectSingleAttachment(
            user: receiver,
            groupId: groupId,
            messageText: 'new-member image',
            sent: image,
            expectDownloaded: expectDownloaded,
          );
          await expectSingleAttachment(
            user: receiver,
            groupId: groupId,
            messageText: 'new-member video',
            sent: video,
            expectDownloaded: expectDownloaded,
          );
          await expectSingleAttachment(
            user: receiver,
            groupId: groupId,
            messageText: 'new-member voice',
            sent: voice,
            expectDownloaded: expectDownloaded,
          );
        }

        expect(
          alice.bridge.commandLog.where((cmd) => cmd == 'media:download'),
          hasLength(3),
        );
      },
    );
  });
}
