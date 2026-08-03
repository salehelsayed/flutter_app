import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/debug/group_media_reliability_e2e_main_actions.dart';
import 'package:flutter_app/core/debug/group_media_reliability_e2e.dart';
import 'package:flutter_app/core/debug/group_notification_projection_e2e.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

Future<Map<String, Object?>> runGroupNotificationProjectionE2EAction({
  required Map<String, dynamic> config,
  required Directory fixtureDirectory,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepository,
  required GroupRepository groupRepository,
  required GroupMessageRepository groupMessageRepository,
  required MediaAttachmentRepository mediaAttachmentRepository,
  required AudioRecorderService audioRecorderService,
  required MediaFileManager mediaFileManager,
  required ReactionRepository reactionRepository,
  required GroupReactionReplayOutboxRepository
  groupReactionReplayOutboxRepository,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepository,
  String installedProfileId = const String.fromEnvironment(
    'SIMS_BUILD_PROFILE_ID',
  ),
}) async {
  final request = GroupNotificationProjectionE2ERequest.fromConfig(config);
  if (!Platform.isAndroid ||
      installedProfileId != groupNotificationProjectionBuildProfile) {
    throw StateError(
      'Plan 330 endpoint requires the Android production-FCM profile',
    );
  }
  final group = await _exactGroup(
    groupRepository: groupRepository,
    groupName: request.groupName,
  );
  final identity = await identityRepository.loadIdentity();
  if (identity == null) {
    throw StateError('Plan 330 endpoint identity is unavailable');
  }
  final base = <String, Object?>{
    'schema': groupNotificationProjectionE2EResultSchema,
    'transport_action': groupNotificationProjectionE2EAction,
    'scenario': groupNotificationProjectionScenario,
    'stepId': request.stepId,
    'phase': request.phase,
    'role': request.role,
    'runId': request.runId,
    'nonce': request.nonce,
    'status': 'complete',
    'success': true,
  };

  switch (request.phase) {
    case groupNotificationProjectionObserveGroupPhase:
      return <String, Object?>{
        ...base,
        'observation': <String, Object?>{
          'groupIdSha256': _sha256Text(group.id),
          'unreadCount': await groupMessageRepository.getUnreadCount(group.id),
        },
      };
    case groupNotificationProjectionSendMediaPhase:
      if (request.role != 'physical_author') {
        throw const FormatException('Plan 330 media author role rejected');
      }
      final otherMembers = (await groupRepository.getMembers(group.id))
          .where((member) => member.peerId != identity.peerId)
          .toList(growable: false);
      if (otherMembers.length != 1) {
        throw StateError('Plan 330 group must contain one remote member');
      }
      final remoteDevices = otherMembers.single
          .activeDevicesWithLegacyFallback();
      final remoteTransportPeerId = resolvePlan330AccountBoundRemoteTransport(
        remoteAccountPeerId: otherMembers.single.peerId,
        activeTransportPeerIds: remoteDevices.map(
          (device) => device.transportPeerId,
        ),
      );
      if (remoteTransportPeerId == null) {
        throw StateError('Plan 330 remote transport authority is ambiguous');
      }
      await sendGroupMediaReliabilityFixtures(
        runId: request.runId,
        groupId: group.id,
        messageIds: request.messageIds,
        attachmentIds: request.attachmentIds,
        receiverAccountPeerId: otherMembers.single.peerId,
        receiverTransportPeerId: remoteTransportPeerId,
        fixtureDirectory: fixtureDirectory,
        bridge: bridge,
        p2pService: p2pService,
        identityRepository: identityRepository,
        groupRepository: groupRepository,
        groupMessageRepository: groupMessageRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        mediaFileManager: mediaFileManager,
        audioRecorderService: audioRecorderService,
        authorityMode: GroupMediaReliabilityAuthorityMode.accountBoundLegacy,
        inviteDeliveryAttemptRepository: inviteDeliveryAttemptRepository,
      );
      final media = <Map<String, Object?>>[];
      for (final fixtureKind in const <String>['jpeg', 'mp4', 'voice']) {
        final messageId = request.messageIds[fixtureKind]!;
        final attachments = await mediaAttachmentRepository
            .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.group);
        final expectedType =
            groupNotificationProjectionMediaTypeByFixtureKind[fixtureKind]!;
        if (attachments.length != 1 ||
            attachments.single.id != request.attachmentIds[fixtureKind] ||
            attachments.single.mediaType != expectedType ||
            attachments.single.ownerLane != MediaOwnerLane.group) {
          throw StateError(
            'Plan 330 $fixtureKind author attachment did not settle',
          );
        }
        media.add(<String, Object?>{
          'kind':
              groupNotificationProjectionExternalKindByFixtureKind[fixtureKind],
          'mediaType': expectedType,
          'ownerLane': 'group',
          'attachmentCount': 1,
          'targetMessageIdSha256': _sha256Text(messageId),
        });
      }
      return <String, Object?>{
        ...base,
        'observation': <String, Object?>{
          'groupIdSha256': _sha256Text(group.id),
          'media': media,
        },
      };
    case groupNotificationProjectionReactMediaPhase:
      if (request.role != 'emulator_reactor') {
        throw const FormatException('Plan 330 reactor role rejected');
      }
      final messageId = request.messageIds[request.kind]!;
      final attachmentId = request.attachmentIds[request.kind]!;
      final expectedType =
          groupNotificationProjectionMediaTypeByFixtureKind[request.kind]!;
      final attachment = await _waitForTargetAttachment(
        groupId: group.id,
        messageId: messageId,
        attachmentId: attachmentId,
        mediaType: expectedType,
        groupMessageRepository: groupMessageRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
      );
      final (result, reaction) = await sendGroupReaction(
        bridge: bridge,
        groupRepo: groupRepository,
        msgRepo: groupMessageRepository,
        reactionRepo: reactionRepository,
        reactionReplayOutboxRepo: groupReactionReplayOutboxRepository,
        groupId: group.id,
        messageId: messageId,
        emoji: '👍',
        senderPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
      );
      if (reaction == null ||
          !const <SendGroupReactionResult>{
            SendGroupReactionResult.success,
            SendGroupReactionResult.queuedForRetry,
          }.contains(result)) {
        throw StateError('Plan 330 production reaction did not commit');
      }
      return <String, Object?>{
        ...base,
        'observation': <String, Object?>{
          'schema': groupNotificationProjectionTargetReceiptSchema,
          'kind':
              groupNotificationProjectionExternalKindByFixtureKind[request
                  .kind],
          'mediaType': attachment.mediaType,
          'ownerLane': 'group',
          'attachmentCount': 1,
          'targetMessageIdSha256': _sha256Text(messageId),
          'reactionCommitted': true,
        },
      };
  }
  throw StateError('unreachable Plan 330 phase');
}

Future<GroupModel> _exactGroup({
  required GroupRepository groupRepository,
  required String groupName,
}) async {
  final matches = (await groupRepository.getAllGroups())
      .where((group) => group.name == groupName && !group.isDissolved)
      .toList(growable: false);
  if (matches.length != 1) {
    throw StateError('Plan 330 exact group lookup did not settle');
  }
  return matches.single;
}

Future<MediaAttachment> _waitForTargetAttachment({
  required String groupId,
  required String messageId,
  required String attachmentId,
  required String mediaType,
  required GroupMessageRepository groupMessageRepository,
  required MediaAttachmentRepository mediaAttachmentRepository,
}) async {
  for (var attempt = 0; attempt < 120; attempt += 1) {
    final message = await groupMessageRepository.getMessage(messageId);
    final attachments = await mediaAttachmentRepository
        .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.group);
    if (message?.groupId == groupId &&
        attachments.length == 1 &&
        attachments.single.id == attachmentId &&
        attachments.single.mediaType == mediaType &&
        attachments.single.ownerLane == MediaOwnerLane.group) {
      return attachments.single;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw StateError('Plan 330 media target did not arrive');
}

String _sha256Text(String value) =>
    sha256.convert(utf8.encode(value)).toString();
