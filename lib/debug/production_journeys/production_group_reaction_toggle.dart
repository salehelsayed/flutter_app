import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/remove_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_reaction_replay_outbox_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// The RT-001 protocol interval is measured from each real use-case return.
/// Existing production owners perform all admission, publication and storage.
/// The caller enforces the once-only role and already-armed, run-owned target.
Future<Map<String, Object?>> executeProductionReactionToggle({
  required Bridge bridge,
  required GroupRepository groupRepository,
  required GroupMessageRepository messageRepository,
  required ReactionRepository reactionRepository,
  required GroupReactionReplayOutboxRepository replayOutboxRepository,
  required GroupInviteDeliveryAttemptRepository? inviteDeliveryRepository,
  required IdentityRepository identityRepository,
  required String groupId,
  required String messageId,
  required String reactorPeerId,
}) async {
  final identity = await identityRepository.loadIdentity();
  if (identity == null || identity.peerId != reactorPeerId) {
    throw StateError('toggle identity changed');
  }
  final outcomes = <Map<String, Object?>>[];
  final gaps = <int>[];
  Future<void> gap() async {
    final watch = Stopwatch()..start();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    gaps.add(watch.elapsedMilliseconds);
  }

  Future<bool> add(String operation, String emoji) async {
    final (result, reaction) = await sendGroupReaction(
      bridge: bridge,
      groupRepo: groupRepository,
      msgRepo: messageRepository,
      reactionRepo: reactionRepository,
      reactionReplayOutboxRepo: replayOutboxRepository,
      inviteDeliveryAttemptRepo: inviteDeliveryRepository,
      groupId: groupId,
      messageId: messageId,
      emoji: emoji,
      senderPeerId: identity.peerId,
      senderPublicKey: identity.publicKey,
      senderPrivateKey: identity.privateKey,
    );
    outcomes.add({
      'operation': operation,
      'outcome': result.name,
      'reactionId': reaction?.id,
    });
    return result == SendGroupReactionResult.success;
  }

  Map<String, Object?> receipt() => {
    'outcomes': outcomes,
    'returnToNextCallMs': gaps,
  };
  if (!await add('add', '🔥')) return receipt();
  await gap();
  final removed = await removeGroupReaction(
    bridge: bridge,
    groupRepo: groupRepository,
    msgRepo: messageRepository,
    reactionRepo: reactionRepository,
    reactionReplayOutboxRepo: replayOutboxRepository,
    inviteDeliveryAttemptRepo: inviteDeliveryRepository,
    groupId: groupId,
    messageId: messageId,
    emoji: '🔥',
    senderPeerId: identity.peerId,
    senderPublicKey: identity.publicKey,
    senderPrivateKey: identity.privateKey,
  );
  outcomes.add({'operation': 'remove', 'outcome': removed.name});
  if (removed != RemoveGroupReactionResult.success) return receipt();
  await gap();
  await add('readd', '✅');
  return receipt();
}
