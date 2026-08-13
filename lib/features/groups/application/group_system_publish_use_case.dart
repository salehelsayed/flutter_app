import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

class GroupSystemPublishResult {
  const GroupSystemPublishResult({
    required this.publishResult,
    required this.inboxStored,
    required this.inboxRetryPayload,
    this.timelineMessage,
    this.replayStorageError,
  });

  final Map<String, dynamic> publishResult;
  final bool inboxStored;
  final String? inboxRetryPayload;
  final GroupMessage? timelineMessage;
  final Object? replayStorageError;
}

Future<GroupSystemPublishResult> publishGroupSystemMessage({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String text,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  required String messageId,
  required String replayPlaintext,
  String senderUsername = '',
  String? senderDeviceId,
  String? senderTransportPeerId,
  String? senderDevicePublicKey,
  String? senderKeyPackageId,
  List<String> recipientPeerIds = const [],
  GroupMessageRepository? msgRepo,
  GroupMessage? timelineMessage,
}) {
  return runGroupMembershipMutationLocked(
    groupId: groupId,
    action: () => publishGroupSystemMessageAssumingMembershipPhaseHeld(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      text: text,
      senderPeerId: senderPeerId,
      senderPublicKey: senderPublicKey,
      senderPrivateKey: senderPrivateKey,
      messageId: messageId,
      replayPlaintext: replayPlaintext,
      senderUsername: senderUsername,
      senderDeviceId: senderDeviceId,
      senderTransportPeerId: senderTransportPeerId,
      senderDevicePublicKey: senderDevicePublicKey,
      senderKeyPackageId: senderKeyPackageId,
      recipientPeerIds: recipientPeerIds,
      msgRepo: msgRepo,
      timelineMessage: timelineMessage,
    ),
  );
}

/// Publishes while the caller already owns the per-group membership phase.
///
/// Most callers must use [publishGroupSystemMessage]. This entry point exists
/// for compound membership transitions that must perform a final authority
/// check and their first externally visible effect in one uninterrupted phase.
Future<GroupSystemPublishResult>
publishGroupSystemMessageAssumingMembershipPhaseHeld({
  required Bridge bridge,
  required GroupRepository groupRepo,
  required String groupId,
  required String text,
  required String senderPeerId,
  required String senderPublicKey,
  required String senderPrivateKey,
  required String messageId,
  required String replayPlaintext,
  String senderUsername = '',
  String? senderDeviceId,
  String? senderTransportPeerId,
  String? senderDevicePublicKey,
  String? senderKeyPackageId,
  List<String> recipientPeerIds = const [],
  GroupMessageRepository? msgRepo,
  GroupMessage? timelineMessage,
}) async {
  final currentGroup = await groupRepo.getGroup(groupId);
  if (currentGroup == null || currentGroup.selfRemovedAt != null) {
    throw StateError(
      'group system publish has no current membership authority',
    );
  }

  final protectedControl = _protectedControlFromSignedSystemText(text);
  ProtectedGroupAuthorityPreparation? protectedPreparation;
  if (protectedControl != null && hasProtectedGroupAuthorityAdapter) {
    final members = await groupRepo.getMembers(groupId);
    if (hasProtectedGroupPhysicalAuthority(members)) {
      final actorMatches = members
          .where((member) => member.peerId == senderPeerId)
          .toList(growable: false);
      if (actorMatches.length == 1) {
        final senderDevice = resolveProtectedGroupSenderDevice(
          actor: actorMatches.single,
          senderPublicKey: senderDevicePublicKey ?? senderPublicKey,
          senderDeviceId: senderDeviceId,
          senderTransportPeerId: senderTransportPeerId ?? senderPeerId,
        );
        if (senderDevice != null) {
          protectedPreparation = await prepareProtectedGroupAuthority(
            ProtectedGroupAuthorityPrepareRequest(
              groupId: groupId,
              transitionId: messageId,
              control: protectedControl,
              replayData: _protectedReplayData(
                replayPlaintext: replayPlaintext,
                text: text,
                groupId: groupId,
                senderPeerId: senderPeerId,
                senderUsername: senderUsername,
                senderDeviceId: senderDeviceId,
                senderTransportPeerId: senderTransportPeerId,
                messageId: messageId,
                timelineMessage: timelineMessage,
              ),
              actorAccountPeerId: senderPeerId,
              actorAccountPublicKey: senderPublicKey,
              actorAccountPrivateKey: senderPrivateKey,
              senderDevice: senderDevice,
              frozenRecipients: freezeProtectedGroupPhysicalRecipients(members),
            ),
          );
          if (protectedPreparation == null &&
              protectedControl ==
                  ProtectedGroupAuthorityControl.groupDissolve) {
            throw StateError('protected dissolve preparation failed');
          }
        }
      }
    }
  }

  final publishResult = await callGroupPublish(
    bridge,
    groupId: groupId,
    text: text,
    senderPeerId: senderPeerId,
    senderPublicKey: senderPublicKey,
    senderPrivateKey: senderPrivateKey,
    senderUsername: senderUsername,
    senderDeviceId: senderDeviceId,
    senderTransportPeerId: senderTransportPeerId,
    senderDevicePublicKey: senderDevicePublicKey,
    senderKeyPackageId: senderKeyPackageId,
    messageId: messageId,
  );

  final protectedAccepted = await activateProtectedGroupAuthority(
    protectedPreparation,
    requireAllCustody:
        protectedControl == ProtectedGroupAuthorityControl.groupDissolve,
  );
  if (!protectedAccepted &&
      protectedControl == ProtectedGroupAuthorityControl.groupDissolve) {
    throw StateError('protected dissolve custody not accepted');
  }

  if (recipientPeerIds.isEmpty) {
    return GroupSystemPublishResult(
      publishResult: publishResult,
      inboxStored: true,
      inboxRetryPayload: null,
      timelineMessage: timelineMessage?.copyWith(
        inboxStored: true,
        inboxRetryPayload: null,
      ),
    );
  }

  late final String inboxRetryPayload;
  try {
    inboxRetryPayload = await buildGroupOfflineReplayInboxRetryPayload(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      payloadType: groupOfflineReplayPayloadTypeMessage,
      plaintext: replayPlaintext,
      senderPeerId: senderPeerId,
      senderPublicKey: senderPublicKey,
      senderPrivateKey: senderPrivateKey,
      messageId: messageId,
      senderDeviceId: senderDeviceId,
      senderTransportPeerId: senderTransportPeerId,
      senderKeyPackageId: senderKeyPackageId,
      recipientPeerIds: recipientPeerIds,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SYSTEM_PUBLISH_REPLAY_ENVELOPE_ERROR',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'messageId': messageId.length > 8
            ? messageId.substring(0, 8)
            : messageId,
        'error': e.toString(),
      },
    );
    return GroupSystemPublishResult(
      publishResult: publishResult,
      inboxStored: false,
      inboxRetryPayload: null,
      timelineMessage: timelineMessage,
      replayStorageError: e,
    );
  }

  try {
    await storeGroupOfflineReplayFromRetryPayload(
      bridge: bridge,
      inboxRetryPayload: inboxRetryPayload,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_SYSTEM_PUBLISH_INBOX_STORE_ERROR',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'messageId': messageId.length > 8
            ? messageId.substring(0, 8)
            : messageId,
        'error': e.toString(),
      },
    );
    final retryableTimelineMessage = timelineMessage?.copyWith(
      status: 'sent',
      isIncoming: false,
      inboxStored: false,
      inboxRetryPayload: inboxRetryPayload,
    );
    if (msgRepo != null && retryableTimelineMessage != null) {
      await msgRepo.saveMessage(retryableTimelineMessage);
    }
    return GroupSystemPublishResult(
      publishResult: publishResult,
      inboxStored: false,
      inboxRetryPayload: inboxRetryPayload,
      timelineMessage: retryableTimelineMessage ?? timelineMessage,
      replayStorageError: e,
    );
  }

  return GroupSystemPublishResult(
    publishResult: publishResult,
    inboxStored: true,
    inboxRetryPayload: null,
    timelineMessage: timelineMessage?.copyWith(
      inboxStored: true,
      inboxRetryPayload: null,
    ),
  );
}

ProtectedGroupAuthorityControl? _protectedControlFromSignedSystemText(
  String text,
) {
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) return null;
    final kind = decoded['__sys'];
    if (kind is! String) return null;
    return ProtectedGroupAuthorityControl.fromWire(kind);
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> _protectedReplayData({
  required String replayPlaintext,
  required String text,
  required String groupId,
  required String senderPeerId,
  required String senderUsername,
  required String? senderDeviceId,
  required String? senderTransportPeerId,
  required String messageId,
  required GroupMessage? timelineMessage,
}) {
  try {
    final decoded = jsonDecode(replayPlaintext);
    if (decoded is Map<String, dynamic> &&
        decoded['groupId'] is String &&
        decoded['text'] is String) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {}
  String? signedEventAt;
  try {
    final decodedText = jsonDecode(text);
    if (decodedText is Map<String, dynamic>) {
      final audit = decodedText['signedTransitionAudit'];
      if (audit is Map<String, dynamic> && audit['eventAt'] is String) {
        signedEventAt = audit['eventAt'] as String;
      }
    }
  } catch (_) {}
  return <String, dynamic>{
    'groupId': groupId,
    'senderId': senderPeerId,
    'senderUsername': senderUsername,
    if (senderDeviceId != null && senderDeviceId.isNotEmpty)
      'senderDeviceId': senderDeviceId,
    if (senderTransportPeerId != null && senderTransportPeerId.isNotEmpty)
      'transportPeerId': senderTransportPeerId,
    'text': text,
    'timestamp':
        signedEventAt ??
        timelineMessage?.timestamp.toUtc().toIso8601String() ??
        DateTime.now().toUtc().toIso8601String(),
    'messageId': messageId,
  };
}
