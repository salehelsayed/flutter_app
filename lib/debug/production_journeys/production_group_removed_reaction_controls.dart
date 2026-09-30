import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import 'production_group_catalog_controls.dart';
import 'production_group_reaction_capture.dart';
import 'production_journey_controller.dart';

/// PL-010's only mutation is the exact removed Charlie reaction attempt. Group
/// creation, invitation acceptance, target send and removal remain UI actions.
void bindProductionRemovedReactionControls({
  required ProductionJourneyController controller,
  required Bridge bridge,
  required GroupRepository groupRepository,
  required GroupMessageRepository messageRepository,
  required ReactionRepository reactionRepository,
  required GroupReactionReplayOutboxRepository replayOutboxRepository,
  required GroupInviteDeliveryAttemptRepository? inviteDeliveryRepository,
  required IdentityRepository identityRepository,
  required GroupMessageListener groupMessageListener,
}) {
  if (controller.invocation.scenarioId != groupCatalogRemovedReactionJourney) {
    return;
  }
  String? groupId, messageId, reactorPeerId, creatorPeerId;
  ProductionGroupReactionCapture? capture;
  var attempted = false;
  final role = controller.invocation.role;
  final run = controller.invocation.runId;
  final text = 'PL-010 Alice pre-removal reaction target $run';
  Map<String, Object?> binding() => {
    'runId': run,
    'role': role,
    'groupId': groupId,
    'messageId': messageId,
    'reactorPeerId': reactorPeerId,
  };
  controller.bindDisposer(() => capture?.dispose());
  controller.bindAction('catalog_arm_removed_reaction', (args) async {
    if (capture != null ||
        args.keys.any((k) => !{'messageId', 'reactorPeerId'}.contains(k))) {
      throw StateError('removed-reaction arm refused');
    }
    final targetId = args['messageId'];
    final reactorId = args['reactorPeerId'];
    if (targetId is! String || reactorId is! String) {
      throw StateError('target identity missing');
    }
    final groups = (await groupRepository.getAllGroups())
        .where((g) => g.name == productionCatalogGroupName(controller))
        .toList();
    if (groups.length != 1) throw StateError('exact run group missing');
    final group = groups.single;
    final target = await messageRepository.getMessage(targetId);
    final identity = await identityRepository.loadIdentity();
    final reactor = await groupRepository.getMember(group.id, reactorId);
    if (identity == null ||
        target == null ||
        target.groupId != group.id ||
        target.text != text ||
        target.senderPeerId != group.createdBy ||
        reactor?.username != 'Journeycharlie' ||
        (role == 'charlie') != (identity.peerId == reactorId) ||
        await groupRepository.getMember(group.id, identity.peerId) == null ||
        (await reactionRepository.getReactionsForMessage(
          targetId,
        )).isNotEmpty) {
      throw StateError('exact fresh target or actor rejected');
    }
    groupId = group.id;
    messageId = targetId;
    reactorPeerId = reactorId;
    creatorPeerId = group.createdBy;
    capture = ProductionGroupReactionCapture(
      groupId: group.id,
      messageId: targetId,
      senderPeerId: reactorId,
      changes: groupMessageListener.groupReactionChangeStream,
    );
    return {...binding(), 'armed': true, 'initialReactionCount': 0};
  });
  controller.bindAction('catalog_removed_reaction_snapshot', (args) async {
    if (args.isNotEmpty || capture == null) {
      throw StateError('removed-reaction snapshot refused');
    }
    final target = await messageRepository.getMessage(messageId!);
    final members = await groupRepository.getMembers(groupId!);
    final key = await groupRepository.getLatestKey(groupId!);
    final group = await groupRepository.getGroup(groupId!);
    return {
      ...binding(),
      ...capture!.snapshot(),
      'memberPeerIds': members.map((m) => m.peerId).toList(),
      'keyEpoch': key?.keyGeneration ?? 0,
      'groupConfigStateHash': group == null
          ? null
          : buildGroupConfigPayload(group, members)[groupConfigStateHashField],
      'target': target == null
          ? null
          : {
              'messageId': target.id,
              'groupId': target.groupId,
              'senderPeerId': target.senderPeerId,
              'text': target.text,
            },
      'reactions': [
        for (final r in await reactionRepository.getReactionsForMessage(
          messageId!,
        ))
          r.toMap(),
      ],
    };
  });
  if (role != 'charlie') return;
  controller.bindAction('catalog_attempt_removed_reaction', (args) async {
    if (args.isNotEmpty || capture == null || attempted) {
      throw StateError('removed reaction attempt refused');
    }
    capture!.snapshot();
    final identity = await identityRepository.loadIdentity();
    final target = await messageRepository.getMessage(messageId!);
    if (identity == null ||
        identity.peerId != reactorPeerId ||
        await groupRepository.getMember(groupId!, reactorPeerId!) != null ||
        target == null ||
        target.groupId != groupId ||
        target.senderPeerId != creatorPeerId ||
        target.text != text ||
        (await reactionRepository.getReactionsForMessage(
          messageId!,
        )).isNotEmpty) {
      throw StateError('removed identity and retained target required');
    }
    attempted = true;
    final (result, reaction) = await sendGroupReaction(
      bridge: bridge,
      groupRepo: groupRepository,
      msgRepo: messageRepository,
      reactionRepo: reactionRepository,
      reactionReplayOutboxRepo: replayOutboxRepository,
      inviteDeliveryAttemptRepo: inviteDeliveryRepository,
      groupId: groupId!,
      messageId: messageId!,
      emoji: '🔥',
      senderPeerId: identity.peerId,
      senderPublicKey: identity.publicKey,
      senderPrivateKey: identity.privateKey,
    );
    return {
      ...binding(),
      'outcome': result.name,
      'accepted': result == SendGroupReactionResult.success,
      'reactionId': reaction?.id,
      'localReactionCountAfterAttempt':
          (await reactionRepository.getReactionsForMessage(
            messageId!,
          )).where((r) => r.senderPeerId == reactorPeerId).length,
    };
  });
}
