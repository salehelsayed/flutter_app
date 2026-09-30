import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import 'production_group_fixture_controls.dart';
import 'production_journey_controller.dart';
import 'production_sound_descriptor.dart';

/// Uses production-owned dependencies for exact descriptor projection and
/// read-only persistence/visibility observations. No services are constructed.
void bindProductionSoundJourneyControls({
  required ProductionJourneyController controller,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepository,
  required ContactRepository contactRepository,
  required MessageRepository messageRepository,
  required MediaAttachmentRepository mediaAttachmentRepository,
  required GroupRepository groupRepository,
  required GroupMessageRepository groupMessageRepository,
  required GroupInviteDeliveryAttemptRepository inviteDeliveryRepository,
  required ActiveConversationTracker conversationTracker,
  required ActiveConversationTracker groupConversationTracker,
}) {
  if (controller.invocation.scenarioId != notificationSoundJourney) return;
  final claims = ProductionSoundDescriptorClaims();
  String value(Map<String, Object?> args, String name) {
    final result = args[name];
    if (result is! String || result.isEmpty) {
      throw FormatException('missing $name');
    }
    return result;
  }

  Future<GroupModel> ownedGroup(String id) async {
    final group = await groupRepository.getGroup(id);
    if (group == null ||
        !{GroupType.chat, GroupType.announcement}.contains(group.type) ||
        group.name != productionFixtureGroupName(controller, group.type)) {
      throw StateError('sound group is not owned by this invocation');
    }
    return group;
  }

  controller.bindAction('send_sound_descriptor', (args) async {
    final attachment = claims.claim(
      controller.invocation,
      value(args, 'caseId'),
    );
    final number = int.parse(value(args, 'caseId').substring(1));
    final identity = await identityRepository.loadIdentity();
    if (identity == null) throw StateError('production identity is absent');
    String outcome;
    String? firstOutcome;
    if (number <= 7) {
      final contact = await contactRepository.getContact(value(args, 'peerId'));
      if (contact == null ||
          contact.mlKemPublicKey?.isNotEmpty != true ||
          contact.rendezvous !=
              '/mknoon/production-journey/${controller.invocation.runId}') {
        throw StateError('prepared encrypted peer is absent');
      }
      if (await messageRepository.getMessage(attachment.messageId) != null) {
        throw StateError('descriptor message already exists');
      }
      final result = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepository,
        targetPeerId: contact.peerId,
        text: '',
        senderPeerId: identity.peerId,
        senderUsername: identity.username,
        messageId: attachment.messageId,
        preassignedMessageIdIsFresh: true,
        bridge: bridge,
        recipientMlKemPublicKey: contact.mlKemPublicKey,
        mediaAttachments: [attachment],
        mediaAttachmentRepo: mediaAttachmentRepository,
      );
      outcome = result.$1.name;
    } else {
      final group = await ownedGroup(value(args, 'groupId'));
      if (group.type !=
              (number <= 10 ? GroupType.chat : GroupType.announcement) ||
          await groupMessageRepository.getMessage(attachment.messageId) !=
              null) {
        throw StateError('sound descriptor lane or identity rejected');
      }
      var result = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepository,
        msgRepo: groupMessageRepository,
        groupId: group.id,
        text: '',
        senderPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
        senderUsername: identity.username,
        messageId: attachment.messageId,
        mediaAttachments: [attachment],
        mediaAttachmentRepo: mediaAttachmentRepository,
        inviteDeliveryAttemptRepo: inviteDeliveryRepository,
      );
      if (group.type == GroupType.announcement &&
          result.$1 == SendGroupMessageResult.error &&
          result.$2 == null &&
          await groupMessageRepository.getMessage(attachment.messageId) ==
              null) {
        firstOutcome = result.$1.name;
        // An in-place topic rejoin can begin between the runner's readiness
        // snapshot and the send. Keep the first failure visible and retry the
        // same production send once, only after the recovery gate clears.
        for (var attempt = 0;
            attempt < 20 && isGroupRecoveryInProgress();
            attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        if (!isGroupRecoveryInProgress()) {
          result = await sendGroupMessage(
            bridge: bridge,
            groupRepo: groupRepository,
            msgRepo: groupMessageRepository,
            groupId: group.id,
            text: '',
            senderPeerId: identity.peerId,
            senderPublicKey: identity.publicKey,
            senderPrivateKey: identity.privateKey,
            senderUsername: identity.username,
            messageId: attachment.messageId,
            mediaAttachments: [attachment],
            mediaAttachmentRepo: mediaAttachmentRepository,
            inviteDeliveryAttemptRepo: inviteDeliveryRepository,
          );
        }
      }
      outcome = result.$1.name;
    }
    return {
      'messageId': attachment.messageId,
      'outcome': outcome,
      'firstOutcome': firstOutcome,
    };
  });

  // S16 is the original paused-but-still-connected seam. Starting a new UI
  // driver after Home consumes the brief live-bridge window, so perform only
  // this send through the same production use case as the retained harness.
  controller.bindAction('send_sound_text', (args) async {
    if (value(args, 'caseId') != 'S16') {
      throw StateError('timed sound text action is limited to S16');
    }
    final peerId = value(args, 'peerId');
    final text = value(args, 'text');
    final contact = await contactRepository.getContact(peerId);
    if (contact == null ||
        contact.mlKemPublicKey?.isNotEmpty != true ||
        contact.rendezvous !=
            '/mknoon/production-journey/${controller.invocation.runId}') {
      throw StateError('prepared encrypted peer is absent');
    }
    final identity = await identityRepository.loadIdentity();
    if (identity == null) throw StateError('production identity is absent');
    if ((await messageRepository.getMessagesForContact(
      peerId,
    )).any((row) => !row.isIncoming && row.text == text)) {
      throw StateError('timed sound text was already sent');
    }
    final result = await sendChatMessage(
      p2pService: p2pService,
      messageRepo: messageRepository,
      targetPeerId: peerId,
      text: text,
      senderPeerId: identity.peerId,
      senderUsername: identity.username,
      bridge: bridge,
      recipientMlKemPublicKey: contact.mlKemPublicKey,
    );
    return {'outcome': result.$1.name};
  });

  controller.bindAction('sound_snapshot', (args) async {
    final peer = value(args, 'peerId');
    if (await contactRepository.getContact(peer) == null) {
      throw StateError('snapshot peer is not a prepared contact');
    }
    final rawGroups = args['groupIds'];
    if (rawGroups is! List || rawGroups.any((g) => g is! String)) {
      throw const FormatException('exact sound group identities required');
    }
    final rows = <Map<String, Object?>>[];
    Future<List<Map<String, Object?>>> attachments(
      String id,
      MediaOwnerLane owner,
    ) async =>
        (await mediaAttachmentRepository.getAttachmentsForMessage(
              id,
              owner: owner,
            ))
            .map(
              (a) => <String, Object?>{
                'id': a.id,
                'messageId': a.messageId,
                'mediaType': a.mediaType,
                'mime': a.mime,
                'size': a.size,
                'contentHash': a.contentHash,
                'encryptionScheme': a.encryptionScheme,
              },
            )
            .toList();
    for (final row in await messageRepository.getMessagesForContact(peer)) {
      rows.add({
        'id': row.id,
        'lane': 'direct',
        'conversationId': peer,
        'text': row.text,
        'transport': row.transport,
        'incoming': row.isIncoming,
        'readAt': row.readAt,
        'attachments': await attachments(row.id, MediaOwnerLane.direct),
      });
    }
    for (final id in rawGroups.cast<String>().toSet()) {
      final group = await ownedGroup(id);
      for (final row in await groupMessageRepository.getMessagesPage(
        id,
        limit: 500,
      )) {
        rows.add({
          'id': row.id,
          'lane': group.type.name,
          'conversationId': id,
          'text': row.text,
          'incoming': row.isIncoming,
          'attachments': await attachments(row.id, MediaOwnerLane.group),
        });
      }
    }
    return {
      'messages': rows,
      'activePeerId': conversationTracker.activePeerId,
      'activeGroupId': groupConversationTracker.activePeerId,
      'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
      'groupRecoveryActive': isGroupRecoveryInProgress(),
      'locales': WidgetsBinding.instance.platformDispatcher.locales
          .map((l) => l.languageCode)
          .toList(),
      'notifications': controller.foregroundPush.snapshotNotifications(),
    };
  });
}
