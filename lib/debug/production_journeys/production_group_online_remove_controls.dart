import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_key_distribution_debug_gate.dart';
import 'package:flutter_app/features/groups/application/group_media_allowed_peers.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import 'production_group_catalog_controls.dart';
import 'production_journey_controller.dart';

/// Catalog `private_online_remove` (ML-005, KE-006, KE-007, ST-006, PL-006).
/// Creation, acceptance, Charlie's removal and the ordinary text sends are UI
/// actions. The narrow operations below are the original protocol's controlled
/// preconditions: hold Alice's rotated-key send to Bob (debug-only gate) so
/// Bob can publish during rotation, Alice's exact post-removal media message,
/// Bob's explicit media download, and Charlie's rejected send and direct
/// download attempts. Observations are read-only.
void bindProductionGroupOnlineRemoveControls({
  required ProductionJourneyController controller,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepository,
  required GroupRepository groupRepository,
  required GroupMessageRepository messageRepository,
  required MediaAttachmentRepository mediaAttachmentRepository,
  required MediaFileManager mediaFileManager,
  required GroupInviteDeliveryAttemptRepository inviteDeliveryRepository,
}) {
  if (controller.invocation.scenarioId != groupCatalogOnlineRemoveJourney) {
    return;
  }
  final run = controller.invocation.runId;
  final role = controller.invocation.role;
  const scenario = 'private_online_remove';

  Future<GroupModel> runGroup() async {
    final groups = (await groupRepository.getAllGroups())
        .where((g) => g.name == productionCatalogGroupName(controller))
        .toList();
    if (groups.length != 1) throw StateError('exact run group missing');
    return groups.single;
  }

  String string(Map<String, Object?> args, String name) {
    final value = args[name];
    if (value is! String || value.isEmpty) throw FormatException('missing $name');
    return value;
  }

  Future<int> keyEpoch(String groupId) async =>
      (await groupRepository.getLatestKey(groupId))?.keyGeneration ?? 0;

  Future<Map<String, Object?>> send({
    required GroupModel group,
    required String key,
    required String text,
    List<MediaAttachment>? media,
  }) async {
    final identity = await identityRepository.loadIdentity();
    if (identity == null) throw StateError('production identity absent');
    final transport = p2pService.currentState.peerId?.trim();
    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepository,
      msgRepo: messageRepository,
      groupId: group.id,
      text: text,
      senderPeerId: identity.peerId,
      senderPublicKey: identity.publicKey,
      senderPrivateKey: identity.privateKey,
      senderUsername: identity.username,
      messageId: 'gmp_${run}_${scenario}_${key}_$role',
      senderDeviceId: transport,
      senderTransportPeerId: transport,
      mediaAttachments: media,
      mediaAttachmentRepo: mediaAttachmentRepository,
      inviteDeliveryAttemptRepo: inviteDeliveryRepository,
    );
    return {
      'key': key,
      'messageId': message?.id ?? 'gmp_${run}_${scenario}_${key}_$role',
      'text': text,
      'outcome': result.name,
      'senderPeerId': identity.peerId,
      'keyEpoch': message?.keyGeneration ?? await keyEpoch(group.id),
      'accepted':
          result == SendGroupMessageResult.success ||
          result == SendGroupMessageResult.successNoPeers,
      if (media != null)
        'mediaAttachments': [
          for (final m in media) {'id': m.id, 'mime': m.mime, 'size': m.size},
        ],
    };
  }

  controller.bindAction('online_remove_snapshot', (args) async {
    final identity = await identityRepository.loadIdentity();
    if (identity == null) throw StateError('production identity absent');
    final named = (await groupRepository.getAllGroups())
        .where((g) => g.name == productionCatalogGroupName(controller))
        .toList();
    if (named.length > 1) throw StateError('ambiguous run group');
    if (named.isEmpty) {
      return {
        'runId': run,
        'role': role,
        'scenario': scenario,
        'peerId': identity.peerId,
        'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
        'groupPresent': false,
        'selfMember': false,
      };
    }
    final group = named.single;
    final members = await groupRepository.getMembers(group.id);
    final messages = await messageRepository.getMessagesPage(
      group.id,
      limit: 500,
    );
    final watched = (args['texts'] as Map?) ?? const {};
    final mediaMessageId = args['mediaMessageId'];
    return {
      'runId': run,
      'role': role,
      'scenario': scenario,
      'peerId': identity.peerId,
      'transportPeerId': p2pService.currentState.peerId,
      'relayReady': p2pService.currentState.relayReady,
      'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
      'groupId': group.id,
      'topicName': group.topicName,
      'keyEpoch': await keyEpoch(group.id),
      'groupConfigStateHash': buildGroupConfigPayload(
        group,
        members,
      )[groupConfigStateHashField],
      'memberPeerIds': [for (final m in members) m.peerId],
      'selfMember': members.any((m) => m.peerId == identity.peerId),
      'groupPresent': true,
      'watched': {
        for (final entry in watched.entries)
          '${entry.key}': [
            for (final m in messages)
              if (m.text == (entry.value as Map)['text'] &&
                  m.senderPeerId == (entry.value as Map)['senderPeerId'])
                {
                  'messageId': m.id,
                  'groupId': m.groupId,
                  'text': m.text,
                  'senderPeerId': m.senderPeerId,
                  'senderUsername': m.senderUsername,
                  'timestamp': m.timestamp.toUtc().toIso8601String(),
                  'keyEpoch': m.keyGeneration,
                  'isIncoming': m.isIncoming,
                  'status': m.status,
                },
          ],
      },
      if (mediaMessageId is String)
        'media': [
          for (final a
              in await mediaAttachmentRepository.getAttachmentsForMessage(
                mediaMessageId,
                owner: MediaOwnerLane.group,
              ))
            {'id': a.id, 'downloadStatus': a.downloadStatus},
        ],
      'pendingDownloads': (await mediaAttachmentRepository
              .getPendingDownloads())
          .length,
    };
  });

  if (role == 'alice') {
    Completer<void>? release;
    var held = false;
    controller.bindDisposer(() {
      if (release?.isCompleted == false) release!.complete();
      debugGroupKeyDistributionGate = null;
    });
    controller.bindAction('online_remove_arm_rotation_hold', (args) async {
      final bobPeerId = string(args, 'bobPeerId');
      final group = await runGroup();
      if (release != null) throw StateError('rotation hold already armed');
      release = Completer<void>();
      debugGroupKeyDistributionGate = (groupId, peerId) async {
        if (groupId != group.id || peerId != bobPeerId || held) return;
        held = true;
        await release!.future;
      };
      return {'armed': true, 'groupId': group.id};
    });
    controller.bindAction('online_remove_rotation_state', (_) async {
      final group = await runGroup();
      return {
        'held': held,
        'released': release?.isCompleted ?? false,
        'keyEpoch': await keyEpoch(group.id),
      };
    });
    controller.bindAction('online_remove_release_rotation', (_) async {
      if (!held || release == null || release!.isCompleted) {
        throw StateError('no held rotation to release');
      }
      release!.complete();
      debugGroupKeyDistributionGate = null;
      return {'released': true};
    });
    controller.bindAction('online_remove_send_media_message', (args) async {
      final group = await runGroup();
      final bob = string(args, 'bobPeerId');
      final charlie = string(args, 'charliePeerId');
      final identity = await identityRepository.loadIdentity();
      final members = await groupRepository.getMembers(group.id);
      final allowedPeers = groupMediaAllowedPeersForMembers(members);
      final dir = await Directory.systemTemp.createTemp('pl006_post_removal_');
      final file = File('${dir.path}/pl006-post-removal.png');
      await file.writeAsBytes(base64Decode(string(args, 'pngBase64')));
      final uploaded = (await uploadMedia(
        bridge: bridge,
        localFilePath: file.path,
        mime: 'image/png',
        recipientPeerId: group.id,
        allowedPeers: allowedPeers,
        blobId: 'pl006-post-removal-media-$run',
      )).attachmentOrNull;
      if (uploaded == null) throw StateError('PL-006 media upload failed');
      final sent = await send(
        group: group,
        key: 'aliceAfterCharlieRemove',
        text: string(args, 'text'),
        media: [uploaded],
      );
      return {
        ...sent,
        'upload': {
          'blobId': uploaded.id,
          'allowedPeers': allowedPeers,
          'uploadAllowedPeersExcludeRemoved': !allowedPeers.contains(charlie),
          'uploadAllowedPeersIncludeActive':
              allowedPeers.contains(identity?.peerId) &&
              allowedPeers.contains(bob),
          'uploadAllowedPeersCount': allowedPeers.length,
        },
      };
    });
  }

  if (role == 'bob') {
    controller.bindAction('online_remove_download_media', (args) async {
      final group = await runGroup();
      final messageId = string(args, 'messageId');
      var attachments = await mediaAttachmentRepository
          .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.group);
      for (final attachment in attachments) {
        if (attachment.downloadStatus == 'done') continue;
        await downloadMedia(
          bridge: bridge,
          mediaAttachmentRepo: mediaAttachmentRepository,
          mediaFileManager: mediaFileManager,
          attachment: attachment,
          contactPeerId: group.id,
          owner: MediaOwnerLane.group,
          groupMessageRepo: messageRepository,
          enforceGroupMediaPolicy: true,
        );
      }
      attachments = await mediaAttachmentRepository.getAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.group,
      );
      return {
        'media': [
          for (final a in attachments)
            {'id': a.id, 'downloadStatus': a.downloadStatus},
        ],
      };
    });
  }

  if (role == 'charlie') {
    var attempted = false;
    controller.bindAction('online_remove_attempt_send', (_) async {
      final group = await runGroup();
      final identity = await identityRepository.loadIdentity();
      if (attempted ||
          identity == null ||
          await groupRepository.getMember(group.id, identity.peerId) != null) {
        throw StateError('removed Charlie send attempt refused');
      }
      attempted = true;
      return send(
        group: group,
        key: 'charlieAfterCharlieRemove',
        text: 'GM-004 Charlie after removal $run',
      );
    });
    controller.bindAction('online_remove_direct_download', (args) async {
      final blobId = string(args, 'blobId');
      final dir = await Directory.systemTemp.createTemp('pl006_removed_');
      final output = '${dir.path}/$blobId.bin';
      Future<int> bytes() async =>
          await File(output).exists() ? await File(output).length() : 0;
      try {
        final result = await callP2PMediaDownload(
          bridge,
          id: blobId,
          outputPath: output,
        ).timeout(const Duration(seconds: 45));
        final size = await bytes();
        return {
          'ok': result['ok'] == true,
          'directDownloadDenied': result['ok'] != true,
          'outputBytes': size,
          'noDirectDownloadPlaintext': result['ok'] != true && size == 0,
          'errorMessage': result['errorMessage'],
        };
      } catch (error) {
        final size = await bytes();
        return {
          'ok': false,
          'directDownloadDenied': true,
          'outputBytes': size,
          'noDirectDownloadPlaintext': size == 0,
          'errorMessage': error.toString(),
        };
      }
    });
  }
}
