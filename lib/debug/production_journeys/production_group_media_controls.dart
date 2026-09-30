import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/video_thumbnail_overlay.dart';
import 'package:video_player/video_player.dart';

import 'production_journey_controller.dart';

String productionMediaGroupId(String runId) => 'report89-$runId';
String productionMediaGroupName(String runId) => 'Report 89 Group $runId';
const productionMediaIncomingText = 'post-join text plus video and voice';
const productionMediaOutgoingText = 'new member sent video and voice';

/// NEW_MEMBER_MEDIA display proof on the production app. The original seeds a
/// new member's two media messages (incoming post-join text+video+voice and
/// the member's own video+voice) over local fixture files; this writes the
/// same rows and original fixture bytes through the production repositories
/// and trusted media paths. Maestro drives the UI; observations are read-only.
void bindProductionGroupMediaControls({
  required ProductionJourneyController controller,
  required IdentityRepository identityRepository,
  required GroupRepository groupRepository,
  required GroupMessageRepository groupMessageRepository,
  required MediaAttachmentRepository mediaAttachmentRepository,
  required MediaFileManager mediaFileManager,
}) {
  if (controller.invocation.scenarioId != groupNewMemberMediaJourney) return;
  final run = controller.invocation.runId;
  final groupId = productionMediaGroupId(run);
  var seeded = false;
  Timer? watcher;
  int? playingSeenAtMs;
  Stopwatch? watchClock;
  controller.bindDisposer(() => watcher?.cancel());

  String string(Map<String, Object?> values, String name) {
    final value = values[name];
    if (value is! String || value.isEmpty) {
      throw FormatException('missing $name');
    }
    return value;
  }

  Map<String, int> treeCounts() {
    var thumbnails = 0, players = 0, playing = 0, videoPlayers = 0;
    final texts = <String, int>{};
    void count(String text) => texts[text] = (texts[text] ?? 0) + 1;
    void visit(Element element, bool insidePlayer) {
      final widget = element.widget;
      var inPlayer = insidePlayer;
      if (widget is VideoThumbnailOverlay) thumbnails++;
      if (widget is AudioPlayerWidget) {
        players++;
        inPlayer = true;
      }
      if (widget is VideoPlayer) videoPlayers++;
      if (inPlayer && widget is Icon && widget.icon == Icons.pause_rounded) {
        playing++;
      }
      // Same matching as flutter_test's find.text (findRichText: false):
      // Text data or Text.rich span, and EditableText; raw RichText is ignored.
      if (widget is Text) {
        final text = widget.data ?? widget.textSpan?.toPlainText();
        if (text != null) count(text);
      }
      if (widget is EditableText) count(widget.controller.text);
      element.visitChildElements((child) => visit(child, inPlayer));
    }

    // The original pumps GroupConversationScreen alone; in the app the Orbit
    // route stays mounted underneath (its row previews the latest message),
    // so scope the finders to the open group conversation when there is one.
    Element? conversation;
    void locate(Element element) {
      if (conversation != null) return;
      if (element.widget is GroupConversationWired) {
        conversation = element;
        return;
      }
      element.visitChildElements(locate);
    }

    final root = WidgetsBinding.instance.rootElement;
    root?.visitChildElements(locate);
    (conversation ?? root)?.visitChildElements((child) => visit(child, false));
    final scoped = {
      'scopedToConversation': conversation != null ? 1 : 0,
      'videoThumbnailOverlays': thumbnails,
      'audioPlayerWidgets': players,
      'playingAudioPlayers': playing,
      'incomingText': texts[productionMediaIncomingText] ?? 0,
      'outgoingText': texts[productionMediaOutgoingText] ?? 0,
      'durationLabels': texts['0:01'] ?? 0,
    };
    // The video viewer is its own route above the conversation: observe it
    // across the whole tree.
    videoPlayers = 0;
    texts.clear();
    root?.visitChildElements((child) => visit(child, false));
    return {
      ...scoped,
      'videoPlayers': videoPlayers,
      'videoLoadErrors': texts['Could not load video'] ?? 0,
    };
  }

  controller.bindAction('prepare_new_member_media', (args) async {
    final alicePeerId = string(args, 'alicePeerId');
    final identity = await identityRepository.loadIdentity();
    if (seeded ||
        controller.invocation.role != 'bob' ||
        identity == null ||
        identity.peerId == alicePeerId ||
        await groupRepository.getGroup(groupId) != null) {
      throw StateError('new member media seed rejected');
    }
    seeded = true;
    final video = base64Decode(string(args, 'mp4Base64'));
    final voice = base64Decode(string(args, 'mp3Base64'));
    final thumb = base64Decode(string(args, 'pngBase64'));
    final key = string(args, 'encryptionKeyBase64');
    final nonce = string(args, 'encryptionNonce');
    const scheme = kMediaAttachmentEncryptionSchemeBlobAesGcmV1;
    final now = DateTime.now().toUtc();
    await groupRepository.saveGroup(
      GroupModel(
        id: groupId,
        name: productionMediaGroupName(run),
        type: GroupType.chat,
        topicName: 'topic-$groupId',
        createdAt: now.subtract(const Duration(minutes: 5)),
        createdBy: alicePeerId,
        myRole: GroupRole.member,
      ),
    );
    final random = Random.secure();
    await groupRepository.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: base64Encode(
          List<int>.generate(32, (_) => random.nextInt(256)),
        ),
        createdAt: now.subtract(const Duration(minutes: 5)),
      ),
    );
    for (final (peerId, username, role) in [
      (alicePeerId, 'Alice', MemberRole.admin),
      (identity.peerId, 'Bob', MemberRole.writer),
    ]) {
      await groupRepository.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: peerId,
          username: username,
          role: role,
          publicKey: 'pk-$peerId',
          mlKemPublicKey: 'mlkem-pk-$peerId',
          joinedAt: now.subtract(const Duration(minutes: 4)),
        ),
      );
    }
    final attachments = <Map<String, Object?>>[];
    for (final (id, sender, username, text, incoming, at) in [
      (
        'incoming-post-join-media-$run',
        alicePeerId,
        'Alice',
        productionMediaIncomingText,
        true,
        now,
      ),
      (
        'outgoing-new-member-media-$run',
        identity.peerId,
        'Bob',
        productionMediaOutgoingText,
        false,
        now.add(const Duration(seconds: 1)),
      ),
    ]) {
      await groupMessageRepository.saveMessage(
        GroupMessage(
          id: id,
          groupId: groupId,
          senderPeerId: sender,
          senderUsername: username,
          text: text,
          timestamp: at,
          createdAt: at,
          status: incoming ? 'received' : 'sent',
          isIncoming: incoming,
        ),
      );
      for (final (suffix, mime, type, bytes) in [
        ('video', 'video/mp4', 'video', video),
        ('voice', 'audio/mpeg', 'audio', voice),
      ]) {
        final attachmentId = '$id-$suffix';
        final path = await mediaFileManager.localPathForAttachment(
          contactPeerId: groupId,
          blobId: attachmentId,
          mime: mime,
        );
        await File(path).writeAsBytes(bytes, flush: true);
        if (type == 'video') {
          final base = path.substring(0, path.lastIndexOf('.'));
          await File('$base.thumb.jpg').writeAsBytes(thumb, flush: true);
        }
        final attachment = MediaAttachment(
          id: attachmentId,
          messageId: id,
          mime: mime,
          size: bytes.length,
          mediaType: type,
          localPath: mediaFileManager.relativePathForAttachment(
            contactPeerId: groupId,
            blobId: attachmentId,
            mime: mime,
          ),
          downloadStatus: 'done',
          contentHash: sha256.convert(bytes).toString(),
          encryptionKeyBase64: key,
          encryptionNonce: nonce,
          encryptionScheme: scheme,
          createdAt: at.toIso8601String(),
          width: type == 'video' ? 32 : null,
          height: type == 'video' ? 32 : null,
          durationMs: type == 'video' ? 600 : 1000,
          waveform: type == 'audio'
              ? const [0.2, 0.55, 0.35, 0.8, 0.4, 0.7]
              : null,
        );
        await mediaAttachmentRepository.saveAttachment(
          attachment,
          owner: MediaOwnerLane.group,
        );
        attachments.add({'id': attachmentId, 'size': bytes.length});
      }
    }
    return {'groupId': groupId, 'attachments': attachments};
  });

  // Read-only element-tree observation mirroring the original's finders.
  controller.bindAction('media_snapshot', (_) async {
    final group = await groupRepository.getGroup(groupId);
    final rows = <Map<String, Object?>>[];
    for (final id in [
      'incoming-post-join-media-$run',
      'outgoing-new-member-media-$run',
    ]) {
      for (final a in await mediaAttachmentRepository.getAttachmentsForMessage(
        id,
        owner: MediaOwnerLane.group,
      )) {
        final path = a.localPath == null
            ? null
            : MediaFileManager.resolveStoredPathSync(a.localPath!);
        rows.add({
          'id': a.id,
          'messageId': a.messageId,
          'mediaType': a.mediaType,
          'downloadStatus': a.downloadStatus,
          'contentHash': a.contentHash,
          'fileExists': path != null && File(path).existsSync(),
        });
      }
    }
    return {
      'runId': run,
      'role': controller.invocation.role,
      'groupId': groupId,
      'groupPresent': group?.name == productionMediaGroupName(run),
      'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
      'attachments': rows,
      'tree': treeCounts(),
    };
  });

  // The fixture voice clip is 1 s long, longer-latency host polling would miss
  // it: arm an in-app watcher before the tap, read the result after.
  controller.bindAction('media_watch_playing', (_) async {
    watcher?.cancel();
    playingSeenAtMs = null;
    watchClock = Stopwatch()..start();
    watcher = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      if (treeCounts()['playingAudioPlayers']! > 0) {
        playingSeenAtMs = watchClock!.elapsedMilliseconds;
        timer.cancel();
      } else if (watchClock!.elapsed > const Duration(seconds: 20)) {
        timer.cancel();
      }
    });
    return {'armed': true};
  });

  controller.bindAction('media_playing_result', (_) async {
    watcher?.cancel();
    return {'playingObserved': playingSeenAtMs != null, 'seenAtMs': playingSeenAtMs};
  });
}
