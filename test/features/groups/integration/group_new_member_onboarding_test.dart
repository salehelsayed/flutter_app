import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart'
    as group_send;
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart'
    as group_react;
import 'package:flutter_app/features/groups/application/update_group_metadata_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../conversation/domain/repositories/fake_reaction_repository.dart';
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
    required String groupId,
    required int expectedCount,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      final downloadCount = user.bridge.commandLog
          .where((cmd) => cmd == 'media:download')
          .length;
      final messages = await user.loadGroupMessages(groupId);
      var doneCount = 0;
      for (final message in messages) {
        final attachments = await user.mediaAttachmentRepo
            .getAttachmentsForMessage(message.id);
        doneCount += attachments
            .where((attachment) => attachment.downloadStatus == 'done')
            .length;
      }
      if (downloadCount >= expectedCount && doneCount >= expectedCount) {
        return;
      }
      await pump();
    }
    fail('Expected $expectedCount completed media downloads');
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

  List<String> downloadBlobIds(GroupTestUser user) {
    return user.bridge.sentMessages
        .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
        .where((message) => message['cmd'] == 'media:download')
        .map((message) {
          final payload = message['payload'] as Map<String, dynamic>;
          return payload['id'] as String;
        })
        .toList();
  }

  Future<MediaAttachment> expectDownloadedIncomingAttachment({
    required GroupTestUser user,
    required String groupId,
    required String messageText,
    required GroupMessage sentMessage,
    required String senderPeerId,
    required String senderUsername,
    required int keyGeneration,
    required MediaAttachment sent,
  }) async {
    final matches = (await user.loadGroupMessages(groupId))
        .where((message) => message.isIncoming && message.text == messageText)
        .toList();
    expect(matches, hasLength(1), reason: '${user.username}: $messageText');

    final received = matches.single;
    expect(received.id, sentMessage.id, reason: user.username);
    expect(received.senderPeerId, senderPeerId, reason: user.username);
    expect(received.senderUsername, senderUsername, reason: user.username);
    expect(received.keyGeneration, keyGeneration, reason: user.username);

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
    expect(actual.downloadStatus, 'done', reason: user.username);
    expect(actual.localPath, isNotNull, reason: user.username);
    return actual;
  }

  Widget buildConversation({
    required GroupModel group,
    required List<GroupMessage> messages,
    required String ownPeerId,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: GroupConversationScreen(
          group: group,
          messages: messages,
          ownPeerId: ownPeerId,
          onSend: (_) {},
          onBack: () {},
          canWrite: true,
          initialLoadDone: true,
        ),
      ),
    );
  }

  group('Group new-member onboarding', () {
    test(
      'new member receives only post-join text and media with descriptors',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-onboarding-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-onboarding-peer',
          username: 'Bob',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: FakeMediaFileManager(),
        );

        const groupId = 'group-new-member-media';
        await alice.createGroup(groupId: groupId, name: 'New Member Media');

        alice.start();
        bob.start();

        await alice.sendGroupMessage(
          groupId: groupId,
          text: 'pre-join history',
        );
        await pump();

        await alice.addMember(groupId: groupId, invitee: bob);

        final (textResult, _) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'post-join text',
        );
        expect(textResult, group_send.SendGroupMessageResult.success);

        final image = attachment(
          id: 'blob-new-member-image',
          mime: 'image/jpeg',
          size: 4,
          width: 640,
          height: 480,
        );
        final (imageResult, _) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'post-join image',
          mediaAttachments: [image],
        );
        expect(imageResult, group_send.SendGroupMessageResult.success);

        final video = attachment(
          id: 'blob-new-member-video',
          mime: 'video/mp4',
          size: 4,
          width: 1280,
          height: 720,
          durationMs: 12_000,
        );
        final (videoResult, _) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'post-join video',
          mediaAttachments: [video],
        );
        expect(videoResult, group_send.SendGroupMessageResult.success);

        final voice = attachment(
          id: 'blob-new-member-voice',
          mime: 'audio/mp4',
          size: 4,
          durationMs: 3500,
          waveform: const <double>[0.1, 0.4, 0.2],
        );
        final (voiceResult, _) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'post-join voice',
          mediaAttachments: [voice],
        );
        expect(voiceResult, group_send.SendGroupMessageResult.success);

        await waitForDownloads(user: bob, groupId: groupId, expectedCount: 3);

        final bobIncoming = (await bob.loadGroupMessages(
          groupId,
        )).where((message) => message.isIncoming).toList();
        expect(
          bobIncoming.map((message) => message.text),
          containsAllInOrder([
            'post-join text',
            'post-join image',
            'post-join video',
            'post-join voice',
          ]),
        );
        expect(
          bobIncoming.map((message) => message.text),
          isNot(contains('pre-join history')),
        );

        Future<MediaAttachment> receivedAttachmentFor(String text) async {
          final message = bobIncoming.singleWhere(
            (message) => message.text == text,
          );
          final attachments = await bob.mediaAttachmentRepo
              .getAttachmentsForMessage(message.id);
          expect(attachments, hasLength(1), reason: text);
          return attachments.single;
        }

        final receivedImage = await receivedAttachmentFor('post-join image');
        expect(receivedImage.id, image.id);
        expect(receivedImage.mediaType, 'image');
        expect(receivedImage.mime, 'image/jpeg');
        expect(receivedImage.width, 640);
        expect(receivedImage.height, 480);
        expect(receivedImage.downloadStatus, 'done');
        expect(receivedImage.localPath, isNotNull);

        final receivedVideo = await receivedAttachmentFor('post-join video');
        expect(receivedVideo.id, video.id);
        expect(receivedVideo.mediaType, 'video');
        expect(receivedVideo.mime, 'video/mp4');
        expect(receivedVideo.width, 1280);
        expect(receivedVideo.height, 720);
        expect(receivedVideo.durationMs, 12_000);
        expect(receivedVideo.downloadStatus, 'done');

        final receivedVoice = await receivedAttachmentFor('post-join voice');
        expect(receivedVoice.id, voice.id);
        expect(receivedVoice.mediaType, 'audio');
        expect(receivedVoice.mime, 'audio/mp4');
        expect(receivedVoice.durationMs, 3500);
        expect(receivedVoice.waveform, const <double>[0.1, 0.4, 0.2]);
        expect(receivedVoice.downloadStatus, 'done');

        expect(
          bob.bridge.commandLog.where((cmd) => cmd == 'media:download'),
          hasLength(3),
        );

        alice.dispose();
        bob.dispose();
      },
    );

    test(
      'multiple newly-added members converge on latest epoch and receive the same post-add message',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-multi-add-onboarding-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-multi-add-onboarding-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-multi-add-onboarding-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-new-member-multi-add';
        const epoch = 7;
        await alice.createGroup(groupId: groupId, name: 'New Member Multi Add');
        await saveLatestKey(user: alice, groupId: groupId, epoch: epoch);

        await alice.addMember(groupId: groupId, invitee: bob);
        await saveLatestKey(user: bob, groupId: groupId, epoch: epoch);

        alice.start();
        bob.start();
        charlie.start();

        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveLatestKey(user: charlie, groupId: groupId, epoch: epoch);
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        final (sendResult, sentMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'post-add epoch message',
        );
        expect(sendResult, group_send.SendGroupMessageResult.success);
        expect(sentMessage, isNotNull);
        expect(sentMessage!.keyGeneration, epoch);
        await pump();

        for (final recipient in [bob, charlie]) {
          final receivedMessages = await recipient.loadGroupMessages(groupId);
          final received = receivedMessages
              .where(
                (message) =>
                    message.isIncoming &&
                    message.text == 'post-add epoch message',
              )
              .single;
          expect(received.id, sentMessage.id, reason: recipient.username);
          expect(received.keyGeneration, epoch, reason: recipient.username);

          final latestKey = await recipient.groupRepo.getLatestKey(groupId);
          expect(latestKey, isNotNull, reason: recipient.username);
          expect(latestKey!.keyGeneration, epoch, reason: recipient.username);

          final members = await recipient.groupRepo.getMembers(groupId);
          expect(
            members.map((member) => member.peerId).toSet(),
            {alice.peerId, bob.peerId, charlie.peerId},
            reason: recipient.username,
          );
        }
      },
    );

    test(
      'multiple newly-added members independently download the same post-join image, video, and voice without pre-join history',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-multi-new-media-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-multi-new-media-peer',
          username: 'Bob',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: _ScopedMediaFileManager('bob-multi-new-media'),
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-multi-new-media-peer',
          username: 'Charlie',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: _ScopedMediaFileManager('charlie-multi-new-media'),
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-multi-new-member-media';
        const epoch = 9;
        await alice.createGroup(
          groupId: groupId,
          name: 'Multi New Member Media',
        );
        await saveLatestKey(user: alice, groupId: groupId, epoch: epoch);

        alice.start();
        bob.start();
        charlie.start();

        final (preTextResult, preTextMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'pre-join text history',
              messageId: 'msg-gmar003-pre-text',
            );
        expect(preTextResult, group_send.SendGroupMessageResult.successNoPeers);
        expect(preTextMessage, isNotNull);

        final preImage = attachment(
          id: 'blob-gmar003-pre-image',
          mime: 'image/jpeg',
          size: 4,
          width: 320,
          height: 240,
        );
        final (preImageResult, preImageMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'pre-join image history',
              messageId: 'msg-gmar003-pre-image',
              mediaAttachments: [preImage],
            );
        expect(
          preImageResult,
          group_send.SendGroupMessageResult.successNoPeers,
        );
        expect(preImageMessage, isNotNull);

        final preVideo = attachment(
          id: 'blob-gmar003-pre-video',
          mime: 'video/mp4',
          size: 4,
          width: 640,
          height: 360,
          durationMs: 7000,
        );
        final (preVideoResult, preVideoMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'pre-join video history',
              messageId: 'msg-gmar003-pre-video',
              mediaAttachments: [preVideo],
            );
        expect(
          preVideoResult,
          group_send.SendGroupMessageResult.successNoPeers,
        );
        expect(preVideoMessage, isNotNull);

        final preVoice = attachment(
          id: 'blob-gmar003-pre-voice',
          mime: 'audio/mp4',
          size: 4,
          durationMs: 2100,
          waveform: const <double>[0.3, 0.2, 0.5],
        );
        final (preVoiceResult, preVoiceMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'pre-join voice history',
              messageId: 'msg-gmar003-pre-voice',
              mediaAttachments: [preVoice],
            );
        expect(
          preVoiceResult,
          group_send.SendGroupMessageResult.successNoPeers,
        );
        expect(preVoiceMessage, isNotNull);
        await pump();

        await alice.addMember(groupId: groupId, invitee: bob);
        await saveLatestKey(user: bob, groupId: groupId, epoch: epoch);
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveLatestKey(user: charlie, groupId: groupId, epoch: epoch);
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        final postImage = attachment(
          id: 'blob-gmar003-post-image',
          mime: 'image/jpeg',
          size: 4,
          width: 800,
          height: 600,
        );
        final (postImageResult, postImageMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'post-join image for all new members',
              messageId: 'msg-gmar003-post-image',
              mediaAttachments: [postImage],
            );
        expect(postImageResult, group_send.SendGroupMessageResult.success);
        expect(postImageMessage, isNotNull);

        final postVideo = attachment(
          id: 'blob-gmar003-post-video',
          mime: 'video/mp4',
          size: 4,
          width: 1920,
          height: 1080,
          durationMs: 18_000,
        );
        final (postVideoResult, postVideoMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'post-join video for all new members',
              messageId: 'msg-gmar003-post-video',
              mediaAttachments: [postVideo],
            );
        expect(postVideoResult, group_send.SendGroupMessageResult.success);
        expect(postVideoMessage, isNotNull);

        final postVoice = attachment(
          id: 'blob-gmar003-post-voice',
          mime: 'audio/mp4',
          size: 4,
          durationMs: 4200,
          waveform: const <double>[0.2, 0.5, 0.3, 0.6],
        );
        final (postVoiceResult, postVoiceMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'post-join voice for all new members',
              messageId: 'msg-gmar003-post-voice',
              mediaAttachments: [postVoice],
            );
        expect(postVoiceResult, group_send.SendGroupMessageResult.success);
        expect(postVoiceMessage, isNotNull);

        for (final recipient in [bob, charlie]) {
          await waitForDownloads(
            user: recipient,
            groupId: groupId,
            expectedCount: 3,
          );

          final messages = await recipient.loadGroupMessages(groupId);
          final messageTexts = messages.map((message) => message.text).toList();
          final messageIds = messages.map((message) => message.id).toSet();
          expect(
            messageTexts,
            containsAll([
              'post-join image for all new members',
              'post-join video for all new members',
              'post-join voice for all new members',
            ]),
            reason: recipient.username,
          );
          for (final preJoinText in [
            'pre-join text history',
            'pre-join image history',
            'pre-join video history',
            'pre-join voice history',
          ]) {
            expect(
              messageTexts,
              isNot(contains(preJoinText)),
              reason: recipient.username,
            );
          }
          for (final preJoinMessage in [
            preTextMessage,
            preImageMessage,
            preVideoMessage,
            preVoiceMessage,
          ]) {
            expect(
              messageIds,
              isNot(contains(preJoinMessage!.id)),
              reason: recipient.username,
            );
          }

          for (final preJoinMessage in [
            preTextMessage,
            preImageMessage,
            preVideoMessage,
            preVoiceMessage,
          ]) {
            expect(
              await recipient.mediaAttachmentRepo.getAttachmentsForMessage(
                preJoinMessage!.id,
              ),
              isEmpty,
              reason: recipient.username,
            );
          }

          await expectDownloadedIncomingAttachment(
            user: recipient,
            groupId: groupId,
            messageText: 'post-join image for all new members',
            sentMessage: postImageMessage!,
            senderPeerId: alice.peerId,
            senderUsername: alice.username,
            keyGeneration: epoch,
            sent: postImage,
          );
          await expectDownloadedIncomingAttachment(
            user: recipient,
            groupId: groupId,
            messageText: 'post-join video for all new members',
            sentMessage: postVideoMessage!,
            senderPeerId: alice.peerId,
            senderUsername: alice.username,
            keyGeneration: epoch,
            sent: postVideo,
          );
          await expectDownloadedIncomingAttachment(
            user: recipient,
            groupId: groupId,
            messageText: 'post-join voice for all new members',
            sentMessage: postVoiceMessage!,
            senderPeerId: alice.peerId,
            senderUsername: alice.username,
            keyGeneration: epoch,
            sent: postVoice,
          );

          expect(
            await recipient.mediaAttachmentRepo.getPendingDownloads(),
            isEmpty,
          );
          expect(
            recipient.bridge.commandLog.where((cmd) => cmd == 'media:download'),
            hasLength(3),
            reason: recipient.username,
          );
          expect(
            downloadBlobIds(recipient),
            unorderedEquals([postImage.id, postVideo.id, postVoice.id]),
            reason: recipient.username,
          );

          final latestKey = await recipient.groupRepo.getLatestKey(groupId);
          expect(latestKey, isNotNull, reason: recipient.username);
          expect(latestKey!.keyGeneration, epoch, reason: recipient.username);

          final members = await recipient.groupRepo.getMembers(groupId);
          expect(
            members.map((member) => member.peerId).toSet(),
            {alice.peerId, bob.peerId, charlie.peerId},
            reason: recipient.username,
          );
        }
      },
    );

    test(
      'new member receives current metadata and roles without pre-join history',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-current-state-onboarding-peer',
          username: 'Alice',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-current-state-onboarding-peer',
          username: 'Charlie',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-current-state-onboarding-peer',
          username: 'Bob',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          charlie.dispose();
          bob.dispose();
        });

        const groupId = 'group-new-member-current-state';
        final createdAt = DateTime.utc(2026, 4, 29, 9);
        await alice.createGroup(
          groupId: groupId,
          name: 'Original Charter',
          description: 'Draft state',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: DateTime.utc(2026, 4, 29, 9, 1),
        );

        alice.start();
        charlie.start();
        bob.start();

        final preJoin = await alice.sendGroupMessage(
          groupId: groupId,
          text: 'pre-join state history',
        );
        expect(preJoin, isNotNull);
        await pump();

        final metadataAt = DateTime.utc(2026, 4, 29, 9, 2);
        await updateGroupMetadata(
          groupRepo: alice.groupRepo,
          groupId: groupId,
          name: 'Final Charter',
          description: 'Current authorized state',
          eventAt: metadataAt,
        );
        await alice.updateMemberRole(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          role: MemberRole.reader,
          changedAt: DateTime.utc(2026, 4, 29, 9, 3),
        );
        final updatedCharlie = await alice.groupRepo.getMember(
          groupId,
          charlie.peerId,
        );
        expect(updatedCharlie, isNotNull);
        await alice.groupRepo.saveMember(
          GroupMember(
            groupId: updatedCharlie!.groupId,
            peerId: updatedCharlie.peerId,
            username: updatedCharlie.username,
            role: updatedCharlie.role,
            permissions: const GroupMemberPermissions(
              inviteMembers: false,
              editMetadata: false,
              pinMessages: true,
            ),
            publicKey: updatedCharlie.publicKey,
            mlKemPublicKey: updatedCharlie.mlKemPublicKey,
            joinedAt: updatedCharlie.joinedAt,
          ),
        );

        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: DateTime.utc(2026, 4, 29, 9, 4),
        );

        final bobGroup = await bob.groupRepo.getGroup(groupId);
        expect(bobGroup, isNotNull);
        expect(bobGroup!.name, 'Final Charter');
        expect(bobGroup.description, 'Current authorized state');
        expect(bobGroup.createdBy, alice.peerId);
        expect(bobGroup.createdAt, createdAt);
        expect(bobGroup.type, GroupType.chat);
        expect(bobGroup.myRole, GroupRole.member);
        expect(bobGroup.lastMetadataEventAt, metadataAt);

        final bobMembersByPeerId = {
          for (final member in await bob.groupRepo.getMembers(groupId))
            member.peerId: member,
        };
        expect(bobMembersByPeerId.keys.toSet(), {
          alice.peerId,
          charlie.peerId,
          bob.peerId,
        });
        expect(bobMembersByPeerId[alice.peerId]!.role, MemberRole.admin);
        expect(bobMembersByPeerId[charlie.peerId]!.role, MemberRole.reader);
        expect(bobMembersByPeerId[charlie.peerId]!.permissions.toJson(), {
          'inviteMembers': false,
          'editMetadata': false,
          'pinMessages': true,
        });
        expect(
          bobMembersByPeerId[charlie.peerId]!.permissions.allows(
            GroupMemberPermission.inviteMembers,
            MemberRole.reader,
          ),
          isFalse,
        );
        expect(
          bobMembersByPeerId[charlie.peerId]!.permissions.allows(
            GroupMemberPermission.pinMessages,
            MemberRole.reader,
          ),
          isTrue,
        );
        expect(bobMembersByPeerId[bob.peerId]!.role, MemberRole.writer);
        expect(
          bobMembersByPeerId[bob.peerId]!.permissions.hasOverrides,
          isFalse,
        );

        final bobMessagesBeforePostJoin = await bob.loadGroupMessages(groupId);
        expect(bobMessagesBeforePostJoin, isEmpty);
        expect(
          bobMessagesBeforePostJoin.map((message) => message.text),
          isNot(contains('pre-join state history')),
        );

        final (sendResult, postJoin) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'post-join current-state message',
        );
        expect(sendResult, group_send.SendGroupMessageResult.success);
        expect(postJoin, isNotNull);
        await pump();

        final bobIncomingTexts = (await bob.loadGroupMessages(groupId))
            .where((message) => message.isIncoming)
            .map((message) => message.text)
            .toList();
        expect(bobIncomingTexts, contains('post-join current-state message'));
        expect(bobIncomingTexts, isNot(contains('pre-join state history')));
      },
    );

    test(
      'add-send boundary delivers only after the new member is subscribed',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-add-send-boundary-peer',
          username: 'Alice',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-add-send-boundary-peer',
          username: 'Charlie',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-add-send-boundary-peer',
          username: 'Bob',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          charlie.dispose();
          bob.dispose();
        });

        const groupId = 'group-add-send-boundary';
        const epoch = 3;
        await alice.createGroup(groupId: groupId, name: 'Add Send Boundary');
        await saveLatestKey(user: alice, groupId: groupId, epoch: epoch);
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveLatestKey(user: charlie, groupId: groupId, epoch: epoch);

        alice.start();
        charlie.start();
        bob.start();

        final stagedAt = DateTime.utc(2026, 4, 29, 12);
        await alice.groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: bob.peerId,
            username: bob.username,
            role: MemberRole.writer,
            publicKey: bob.publicKey,
            joinedAt: stagedAt,
          ),
        );
        final group = await alice.groupRepo.getGroup(groupId);
        expect(group, isNotNull);
        await bob.groupRepo.saveGroup(
          group!.copyWith(myRole: GroupRole.member),
        );
        for (final member in await alice.groupRepo.getMembers(groupId)) {
          await bob.groupRepo.saveMember(member);
        }
        await saveLatestKey(user: bob, groupId: groupId, epoch: epoch);
        expect(network.isSubscribed(groupId, bob.peerId), isFalse);

        final duringAdd = await charlie.sendGroupMessage(
          groupId: groupId,
          text: 'sent while add is staged',
        );
        expect(duringAdd, isNotNull);
        await pump();

        bob.subscribeToGroup(groupId);
        await alice.broadcastMemberAdded(groupId: groupId, newMember: bob);
        await pump();

        final afterAdd = await charlie.sendGroupMessage(
          groupId: groupId,
          text: 'sent after add is effective',
        );
        expect(afterAdd, isNotNull);
        await pump();

        final bobIncomingTexts = (await bob.loadGroupMessages(groupId))
            .where((message) => message.isIncoming)
            .map((message) => message.text)
            .toList();
        expect(bobIncomingTexts, contains('sent after add is effective'));
        expect(bobIncomingTexts, isNot(contains('sent while add is staged')));
        expect(
          bobIncomingTexts.where(
            (text) => text == 'sent after add is effective',
          ),
          hasLength(1),
        );

        final charlieMembers = await charlie.groupRepo.getMembers(groupId);
        expect(charlieMembers.map((member) => member.peerId).toSet(), {
          alice.peerId,
          charlie.peerId,
          bob.peerId,
        });

        final charlieOutgoing = (await charlie.loadGroupMessages(groupId))
            .where(
              (message) =>
                  !message.isIncoming &&
                  (message.text == 'sent while add is staged' ||
                      message.text == 'sent after add is effective'),
            )
            .toList();
        expect(charlieOutgoing, hasLength(2));
        expect(charlieOutgoing.map((message) => message.status).toSet(), {
          'sent',
        });
      },
    );

    test(
      'new member receives post-join reactions without pre-join reaction state',
      () async {
        const flameEmoji = '\u{1F525}';
        final alice = GroupTestUser.create(
          peerId: 'alice-reaction-onboarding-peer',
          username: 'Alice',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-reaction-onboarding-peer',
          username: 'Charlie',
          network: network,
          reactionRepo: FakeReactionRepository(),
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-reaction-onboarding-peer',
          username: 'Bob',
          network: network,
          reactionRepo: FakeReactionRepository(),
        );
        addTearDown(() {
          alice.dispose();
          charlie.dispose();
          bob.dispose();
        });

        const groupId = 'group-new-member-reactions';
        await alice.createGroup(groupId: groupId, name: 'New Member Reactions');
        await alice.addMember(groupId: groupId, invitee: charlie);

        alice.start();
        charlie.start();
        bob.start();

        final preJoin = await alice.sendGroupMessage(
          groupId: groupId,
          text: 'pre-join reaction parent',
        );
        expect(preJoin, isNotNull);
        await pump();

        await alice.addMember(groupId: groupId, invitee: bob);

        final (postJoinResult, postJoin) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'post-join reaction target',
            );
        expect(postJoinResult, group_send.SendGroupMessageResult.success);
        expect(postJoin, isNotNull);
        await pump();

        final charlieMessages = await charlie.loadGroupMessages(groupId);
        final charlieTarget = charlieMessages.singleWhere(
          (message) => message.id == postJoin!.id,
        );
        final bobReactionFuture = bob
            .groupMessageListener
            .groupReactionChangeStream
            .first
            .timeout(const Duration(seconds: 2));

        final (reactionResult, reaction) = await charlie
            .sendGroupReactionViaBridge(
              groupId: groupId,
              messageId: charlieTarget.id,
              emoji: flameEmoji,
            );
        expect(reactionResult, group_react.SendGroupReactionResult.success);
        expect(reaction, isNotNull);

        final change = await bobReactionFuture;
        expect(change.messageId, postJoin!.id);
        expect(change.senderPeerId, charlie.peerId);
        expect(change.reaction, isNotNull);
        expect(change.reaction!.emoji, flameEmoji);

        final bobPostJoinReactions = await bob.reactionRepo!
            .getReactionsForMessage(postJoin.id);
        expect(bobPostJoinReactions, hasLength(1));
        expect(bobPostJoinReactions.single.emoji, flameEmoji);
        expect(bobPostJoinReactions.single.senderPeerId, charlie.peerId);
        expect(
          await bob.reactionRepo!.getReactionsForMessage(preJoin!.id),
          isEmpty,
        );
        expect(network.reactionPublishCallCount, 1);
      },
    );

    testWidgets(
      'quoted reply to pre-join parent keeps missing-parent fallback for new member',
      (tester) async {
        final alice = GroupTestUser.create(
          peerId: 'alice-quote-onboarding-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-quote-onboarding-peer',
          username: 'Bob',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
        });

        const groupId = 'group-new-member-quoted-reply';
        await alice.createGroup(groupId: groupId, name: 'New Member Quotes');

        alice.start();
        bob.start();

        final parent = await alice.sendGroupMessage(
          groupId: groupId,
          text: 'pre-join quoted parent',
        );
        expect(parent, isNotNull);
        await tester.pump(const Duration(milliseconds: 50));

        await alice.addMember(groupId: groupId, invitee: bob);

        final (replyResult, reply) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'post-join quoted reply',
          quotedMessageId: parent!.id,
        );
        expect(replyResult, group_send.SendGroupMessageResult.success);
        expect(reply, isNotNull);
        await tester.pump(const Duration(milliseconds: 50));

        final bobMessages = await bob.loadGroupMessages(groupId);
        expect(
          bobMessages.map((message) => message.text),
          isNot(contains('pre-join quoted parent')),
        );
        final bobReply = bobMessages.singleWhere(
          (message) => message.text == 'post-join quoted reply',
        );
        expect(bobReply.quotedMessageId, parent.id);

        final bobGroup = await bob.groupRepo.getGroup(groupId);
        expect(bobGroup, isNotNull);
        await tester.pumpWidget(
          buildConversation(
            group: bobGroup!,
            messages: bobMessages,
            ownPeerId: bob.peerId,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('post-join quoted reply'), findsWidgets);
        expect(find.text('Message unavailable'), findsOneWidget);
      },
    );
  });
}
