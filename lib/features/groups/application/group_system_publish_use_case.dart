import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
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
}) async {
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
