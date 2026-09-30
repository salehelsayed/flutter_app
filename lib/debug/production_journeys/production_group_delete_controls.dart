import 'package:flutter/widgets.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import 'production_journey_controller.dart';

String productionDeleteGroupName(String runId) => 'Game Night $runId';

/// Read-only observations for the delete-preserves-friends journey. The group
/// fixture, 1:1 sends, group sends and the swipe Leave & Delete are ordinary
/// fixture/UI operations; this only reports what the production repositories
/// hold before and after them.
void bindProductionGroupDeleteControls({
  required ProductionJourneyController controller,
  required IdentityRepository identityRepository,
  required ContactRepository contactRepository,
  required MessageRepository messageRepository,
  required GroupRepository groupRepository,
  required GroupMessageRepository groupMessageRepository,
}) {
  if (controller.invocation.scenarioId != groupDeletePreservesFriendsJourney) {
    return;
  }
  final run = controller.invocation.runId;

  controller.bindAction('delete_snapshot', (args) async {
    final groupId = args['groupId'];
    final friends = args['friendPeerIds'];
    if (groupId is! String ||
        groupId.isEmpty ||
        friends is! List ||
        friends.isEmpty ||
        friends.any((peer) => peer is! String || peer.isEmpty)) {
      throw const FormatException('groupId and friendPeerIds required');
    }
    final group = await groupRepository.getGroup(groupId);
    if (group != null && group.name != productionDeleteGroupName(run)) {
      throw StateError('delete journey group is not run-owned');
    }
    final identity = await identityRepository.loadIdentity();
    final contacts = await contactRepository.getAllContacts();
    final members = group == null
        ? null
        : await groupRepository.getMembers(groupId);
    final groupMessages = await groupMessageRepository.getMessagesPage(
      groupId,
      limit: 500,
    );
    return {
      'runId': run,
      'role': controller.invocation.role,
      'selfPeerId': identity?.peerId,
      'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
      'groupId': groupId,
      'group': group == null
          ? null
          : {
              'id': group.id,
              'name': group.name,
              'createdBy': group.createdBy,
              'role': group.myRole.name,
              'members': [for (final m in members!) m.peerId],
            },
      'groupMessages': [
        for (final m in groupMessages)
          {'id': m.id, 'text': m.text, 'incoming': m.isIncoming},
      ],
      'contacts': [for (final c in contacts) c.peerId],
      'direct': {
        for (final peer in friends.cast<String>())
          peer: [
            for (final m in await messageRepository.getMessagesForContact(peer))
              {'id': m.id, 'text': m.text, 'incoming': m.isIncoming},
          ],
      },
    };
  });
}
