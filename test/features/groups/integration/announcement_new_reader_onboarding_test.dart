import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart'
    as group_send;
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
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
      await file.writeAsBytes(<int>[5, 6, 7, 8]);

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
    fail('Expected $expectedCount media download attempts');
  }

  group('Announcement new-reader onboarding', () {
    test(
      'new reader receives only post-join admin media with descriptors',
      () async {
        final admin = GroupTestUser.create(
          peerId: 'announcement-admin-peer',
          username: 'Admin',
          network: network,
        );
        final reader = GroupTestUser.create(
          peerId: 'announcement-reader-peer',
          username: 'Reader',
          network: network,
          bridge: _DownloadWritingBridge(),
          mediaFileManager: FakeMediaFileManager(),
        );

        const groupId = 'announcement-new-reader-media';
        await admin.createGroup(
          groupId: groupId,
          name: 'Announcement Onboarding',
          type: GroupType.announcement,
        );

        admin.start();
        reader.start();

        await admin.sendGroupMessage(
          groupId: groupId,
          text: 'pre-join admin post',
        );
        await pump();

        await admin.addMember(groupId: groupId, invitee: reader);

        final image = attachment(
          id: 'blob-announcement-image',
          mime: 'image/jpeg',
          size: 2048,
          width: 640,
          height: 480,
        );
        final (imageResult, _) = await admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'post-join announcement image',
          mediaAttachments: [image],
        );
        expect(imageResult, group_send.SendGroupMessageResult.success);

        final video = attachment(
          id: 'blob-announcement-video',
          mime: 'video/mp4',
          size: 4096,
          width: 1280,
          height: 720,
          durationMs: 12_000,
        );
        final (videoResult, _) = await admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'post-join announcement video',
          mediaAttachments: [video],
        );
        expect(videoResult, group_send.SendGroupMessageResult.success);

        final voice = attachment(
          id: 'blob-announcement-voice',
          mime: 'audio/mp4',
          size: 1024,
          durationMs: 3500,
          waveform: const <double>[0.2, 0.6, 0.3],
        );
        final (voiceResult, _) = await admin.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'post-join announcement voice',
          mediaAttachments: [voice],
        );
        expect(voiceResult, group_send.SendGroupMessageResult.success);

        await waitForDownloads(user: reader, expectedCount: 3);

        final readerIncoming = (await reader.loadGroupMessages(
          groupId,
        )).where((message) => message.isIncoming).toList();
        expect(
          readerIncoming.map((message) => message.text),
          containsAllInOrder([
            'post-join announcement image',
            'post-join announcement video',
            'post-join announcement voice',
          ]),
        );
        expect(
          readerIncoming.map((message) => message.text),
          isNot(contains('pre-join admin post')),
        );

        final readerGroup = await reader.groupRepo.getGroup(groupId);
        expect(readerGroup, isNotNull);
        expect(readerGroup!.type, GroupType.announcement);
        expect(readerGroup.myRole, GroupRole.member);

        final publishCountBeforeReaderAttempts = reader.bridge.commandLog
            .where((cmd) => cmd == 'group:publish')
            .length;
        final readerSendAttempts = [
          ('reader attempted announcement text', <MediaAttachment>[]),
          ('reader attempted announcement image', [image]),
          ('reader attempted announcement video', [video]),
          ('reader attempted announcement voice', [voice]),
        ];
        for (final attempt in readerSendAttempts) {
          final (result, message) = await reader.sendGroupMessageViaBridge(
            groupId: groupId,
            text: attempt.$1,
            mediaAttachments: attempt.$2,
          );
          expect(result, group_send.SendGroupMessageResult.unauthorized);
          expect(message, isNull);
        }
        expect(
          reader.bridge.commandLog.where((cmd) => cmd == 'group:publish'),
          hasLength(publishCountBeforeReaderAttempts),
        );

        Future<MediaAttachment> receivedAttachmentFor(String text) async {
          final message = readerIncoming.singleWhere(
            (message) => message.text == text,
          );
          final attachments = await reader.mediaAttachmentRepo
              .getAttachmentsForMessage(message.id);
          expect(attachments, hasLength(1), reason: text);
          return attachments.single;
        }

        final receivedImage = await receivedAttachmentFor(
          'post-join announcement image',
        );
        expect(receivedImage.id, image.id);
        expect(receivedImage.mediaType, 'image');
        expect(receivedImage.mime, 'image/jpeg');
        expect(receivedImage.width, 640);
        expect(receivedImage.height, 480);
        expect(receivedImage.downloadStatus, 'done');

        final receivedVideo = await receivedAttachmentFor(
          'post-join announcement video',
        );
        expect(receivedVideo.id, video.id);
        expect(receivedVideo.mediaType, 'video');
        expect(receivedVideo.mime, 'video/mp4');
        expect(receivedVideo.width, 1280);
        expect(receivedVideo.height, 720);
        expect(receivedVideo.durationMs, 12_000);
        expect(receivedVideo.downloadStatus, 'done');

        final receivedVoice = await receivedAttachmentFor(
          'post-join announcement voice',
        );
        expect(receivedVoice.id, voice.id);
        expect(receivedVoice.mediaType, 'audio');
        expect(receivedVoice.mime, 'audio/mp4');
        expect(receivedVoice.durationMs, 3500);
        expect(receivedVoice.waveform, const <double>[0.2, 0.6, 0.3]);
        expect(receivedVoice.downloadStatus, 'done');

        expect(
          reader.bridge.commandLog.where((cmd) => cmd == 'media:download'),
          hasLength(3),
        );
        final readerMessagesAfterSendAttempts = await reader.loadGroupMessages(
          groupId,
        );
        expect(
          readerMessagesAfterSendAttempts
              .where((message) => !message.isIncoming)
              .map((message) => message.text),
          isNot(contains(startsWith('reader attempted announcement'))),
        );

        admin.dispose();
        reader.dispose();
      },
    );
  });
}
