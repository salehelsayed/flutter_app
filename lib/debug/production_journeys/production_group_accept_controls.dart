import 'package:flutter/material.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import 'production_journey_controller.dart';

String productionAcceptGroupName(String runId) => 'Writers Room $runId';

/// Read-only observations for INVITE_ACCEPT_SPINNER. Alice creates the group
/// and Bob accepts through ordinary UI; this reports the run-owned pending
/// invite, the persisted group and, like the original's widget finders, how
/// many SnackBar and GroupConversationWired widgets are mounted.
void bindProductionGroupAcceptControls({
  required ProductionJourneyController controller,
  required P2PService p2pService,
  required IdentityRepository identityRepository,
  required GroupRepository groupRepository,
  required PendingGroupInviteRepository pendingInviteRepository,
}) {
  if (controller.invocation.scenarioId != groupInviteAcceptSpinnerJourney) {
    return;
  }
  final name = productionAcceptGroupName(controller.invocation.runId);

  controller.bindAction('accept_drain_inbox', (_) async {
    await p2pService.drainOfflineInbox();
    return {'drainReturned': true};
  });

  controller.bindAction('accept_snapshot', (_) async {
    final identity = await identityRepository.loadIdentity();
    final pending = (await pendingInviteRepository.getPendingInvites())
        .where((invite) => invite.groupName == name)
        .toList();
    final groups = (await groupRepository.getAllGroups())
        .where((group) => group.name == name)
        .toList();
    var snackBars = 0;
    var groupConversations = 0;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is SnackBar) snackBars++;
      if (widget is GroupConversationWired) groupConversations++;
      element.visitChildElements(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildElements(visit);
    return {
      'runId': controller.invocation.runId,
      'role': controller.invocation.role,
      'selfPeerId': identity?.peerId,
      'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
      'pending': [
        for (final invite in pending)
          {
            'groupId': invite.groupId,
            'inviteId': invite.inviteId,
            'senderPeerId': invite.senderPeerId,
          },
      ],
      'groups': [
        for (final group in groups)
          {
            'id': group.id,
            'createdBy': group.createdBy,
            'role': group.myRole.name,
          },
      ],
      'mountedSnackBars': snackBars,
      'mountedGroupConversations': groupConversations,
    };
  });
}
