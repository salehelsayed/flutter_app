import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';

import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_image_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_grid_cell.dart';
import 'package:flutter_app/shared/widgets/media/video_thumbnail_overlay.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Report 89 group new-member media simulator proof', () {
    testWidgets(
      'new member video and voice rows render, play, and survive reopen on simulator',
      (tester) async {
        final tempDir = await Directory.systemTemp.createTemp(
          'group_new_member_media_sim_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final videoBytes = base64Decode(_tinyMp4Base64);
        final voiceBytes = base64Decode(_tinyMp3Base64);
        final videoContentHash = sha256.convert(videoBytes).toString();
        final voiceContentHash = sha256.convert(voiceBytes).toString();
        final videoFile = File('${tempDir.path}/report89-video.mp4')
          ..writeAsBytesSync(videoBytes);
        File(
          '${tempDir.path}/report89-video.thumb.jpg',
        ).writeAsBytesSync(base64Decode(_tinyPngBase64));
        final incomingVoiceFile = File('${tempDir.path}/report89-incoming.mp3')
          ..writeAsBytesSync(voiceBytes);
        final outgoingVoiceFile = File('${tempDir.path}/report89-outgoing.mp3')
          ..writeAsBytesSync(voiceBytes);
        debugPrint('report89-proof: fixture files ready');

        final group = GroupModel(
          id: 'report89-group',
          name: 'Report 89 Group',
          type: GroupType.chat,
          topicName: 'topic-report89',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'alice-peer',
          myRole: GroupRole.member,
        );
        final now = DateTime.now().toUtc();
        final incoming = _message(
          id: 'incoming-post-join-media',
          groupId: group.id,
          senderPeerId: 'alice-peer',
          senderUsername: 'Alice',
          text: 'post-join text plus video and voice',
          timestamp: now,
          isIncoming: true,
          videoPath: videoFile.path,
          voicePath: incomingVoiceFile.path,
          videoContentHash: videoContentHash,
          voiceContentHash: voiceContentHash,
        );
        final outgoing = _message(
          id: 'outgoing-new-member-media',
          groupId: group.id,
          senderPeerId: 'bob-peer',
          senderUsername: 'Bob',
          text: 'new member sent video and voice',
          timestamp: now.add(const Duration(seconds: 1)),
          isIncoming: false,
          videoPath: videoFile.path,
          voicePath: outgoingVoiceFile.path,
          videoContentHash: videoContentHash,
          voiceContentHash: voiceContentHash,
        );
        final messages = [incoming, outgoing];

        debugPrint('report89-proof: pumping initial screen');
        await tester.pumpWidget(_ProofApp(group: group, messages: messages));
        debugPrint('report89-proof: initial screen pumped');
        await _pumpFrames(tester);
        debugPrint('report89-proof: initial frames pumped');

        await _expectReport89RowsVisible(tester);
        debugPrint('report89-proof: initial rows visible');
        await _expectVoiceCanPlay(tester);
        debugPrint('report89-proof: initial voice playback verified');
        await _expectVideoViewerCanOpen(tester);
        debugPrint('report89-proof: initial video viewer verified');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        debugPrint('report89-proof: pumping reopened screen');
        await tester.pumpWidget(_ProofApp(group: group, messages: messages));
        debugPrint('report89-proof: reopened screen pumped');
        await _pumpFrames(tester);
        debugPrint('report89-proof: reopened frames pumped');

        await _expectReport89RowsVisible(tester);
        debugPrint('report89-proof: reopen rows visible');
        await _expectVoiceCanPlay(tester);
        debugPrint('report89-proof: reopen voice playback verified');
        await _expectVideoViewerCanOpen(tester);
        debugPrint('report89-proof: reopen video viewer verified');
      },
    );
  });
}

class _ProofApp extends StatelessWidget {
  const _ProofApp({required this.group, required this.messages});

  final GroupModel group;
  final List<GroupMessage> messages;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => GroupConversationScreen(
            group: group,
            messages: messages,
            ownPeerId: 'bob-peer',
            onSend: (_) {},
            onBack: () {},
            canWrite: true,
            initialLoadDone: true,
            onMediaTap: (messageId, index) {
              final media = messages
                  .firstWhere((message) => message.id == messageId)
                  .media;
              final visual = media
                  .where(
                    (attachment) =>
                        attachment.mediaType == 'image' ||
                        attachment.mediaType == 'video',
                  )
                  .toList(growable: false);
              if (index >= visual.length || visual[index].localPath == null) {
                return;
              }
              final paths = visual
                  .where(
                    (attachment) =>
                        attachment.localPath != null &&
                        attachment.downloadStatus == 'done',
                  )
                  .map((attachment) => attachment.localPath!)
                  .toList(growable: false);
              final selectedPath = visual[index].localPath!;
              final initialIndex = math.max(0, paths.indexOf(selectedPath));
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FullScreenImageViewer(
                    localPath: selectedPath,
                    allPaths: paths,
                    initialIndex: initialIndex,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

GroupMessage _message({
  required String id,
  required String groupId,
  required String senderPeerId,
  required String senderUsername,
  required String text,
  required DateTime timestamp,
  required bool isIncoming,
  required String videoPath,
  required String voicePath,
  required String videoContentHash,
  required String voiceContentHash,
}) {
  return GroupMessage(
    id: id,
    groupId: groupId,
    senderPeerId: senderPeerId,
    senderUsername: senderUsername,
    text: text,
    timestamp: timestamp,
    createdAt: timestamp,
    status: isIncoming ? 'received' : 'sent',
    isIncoming: isIncoming,
    media: [
      MediaAttachment(
        id: '$id-video',
        messageId: id,
        mime: 'video/mp4',
        size: File(videoPath).lengthSync(),
        mediaType: 'video',
        localPath: videoPath,
        downloadStatus: 'done',
        contentHash: videoContentHash,
        encryptionKeyBase64: _fixtureEncryptionKeyBase64,
        encryptionNonce: _fixtureEncryptionNonce,
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        createdAt: timestamp.toIso8601String(),
        width: 32,
        height: 32,
        durationMs: 600,
      ),
      MediaAttachment(
        id: '$id-voice',
        messageId: id,
        mime: 'audio/mpeg',
        size: File(voicePath).lengthSync(),
        mediaType: 'audio',
        localPath: voicePath,
        downloadStatus: 'done',
        contentHash: voiceContentHash,
        encryptionKeyBase64: _fixtureEncryptionKeyBase64,
        encryptionNonce: _fixtureEncryptionNonce,
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        createdAt: timestamp.toIso8601String(),
        durationMs: 1000,
        waveform: const [0.2, 0.55, 0.35, 0.8, 0.4, 0.7],
      ),
    ],
  );
}

Future<void> _expectReport89RowsVisible(WidgetTester tester) async {
  expect(find.text('post-join text plus video and voice'), findsOneWidget);
  expect(find.text('new member sent video and voice'), findsOneWidget);
  expect(find.byType(VideoThumbnailOverlay), findsNWidgets(2));
  expect(find.byType(AudioPlayerWidget), findsNWidgets(2));
}

Future<void> _expectVoiceCanPlay(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () =>
        find.text('0:01').evaluate().length >= 2 &&
        find
            .descendant(
              of: find.byType(AudioPlayerWidget).first,
              matching: find.byIcon(Icons.play_arrow_rounded),
            )
            .evaluate()
            .isNotEmpty,
    timeout: const Duration(seconds: 8),
  );
  await tester.tap(
    find.descendant(
      of: find.byType(AudioPlayerWidget).first,
      matching: find.byIcon(Icons.play_arrow_rounded),
    ),
  );
  await _pumpDeviceFrame(tester, delay: const Duration(milliseconds: 250));
  expect(
    find.descendant(
      of: find.byType(AudioPlayerWidget).first,
      matching: find.byIcon(Icons.pause_rounded),
    ),
    findsOneWidget,
  );
  await tester.tap(
    find.descendant(
      of: find.byType(AudioPlayerWidget).first,
      matching: find.byIcon(Icons.pause_rounded),
    ),
  );
  await _pumpDeviceFrame(tester);
}

Future<void> _expectVideoViewerCanOpen(WidgetTester tester) async {
  await tester.tap(find.byType(MediaGridCell).first);
  await _pumpUntil(
    tester,
    () =>
        find.byType(VideoPlayer).evaluate().isNotEmpty ||
        find.text('Could not load video').evaluate().isNotEmpty,
    timeout: const Duration(seconds: 8),
  );
  expect(find.text('Could not load video'), findsNothing);
  expect(find.byType(VideoPlayer), findsOneWidget);

  await tester.tap(find.byIcon(Icons.arrow_back));
  await _pumpFrames(tester);
}

Future<void> _pumpFrames(WidgetTester tester, {int count = 8}) async {
  for (var i = 0; i < count; i++) {
    await _pumpDeviceFrame(tester);
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final pumpCount = math.max(1, (timeout.inMilliseconds / 100).ceil());
  for (var i = 0; i < pumpCount; i++) {
    await _pumpDeviceFrame(tester);
    if (condition()) {
      return;
    }
  }
  fail('Timed out waiting for simulator condition');
}

Future<void> _pumpDeviceFrame(
  WidgetTester tester, {
  Duration delay = const Duration(milliseconds: 100),
}) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(delay);
  });
  await tester.pump();
}

const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

const _fixtureEncryptionKeyBase64 =
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
const _fixtureEncryptionNonce = 'AAAAAAAAAAAAAAAA';

const _tinyMp3Base64 =
    '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';

final _tinyMp4Base64 =
    '''
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
'''
        .replaceAll(RegExp(r'\s+'), '');
