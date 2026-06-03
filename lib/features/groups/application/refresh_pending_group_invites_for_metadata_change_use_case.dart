import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/resend_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

class PendingGroupInviteMetadataRefreshResult {
  final int attemptCount;
  final int refreshedCount;

  const PendingGroupInviteMetadataRefreshResult({
    required this.attemptCount,
    required this.refreshedCount,
  });

  static const empty = PendingGroupInviteMetadataRefreshResult(
    attemptCount: 0,
    refreshedCount: 0,
  );

  bool get refreshedAny => refreshedCount > 0;
}

Future<PendingGroupInviteMetadataRefreshResult>
refreshPendingGroupInvitesForMetadataChange({
  required P2PService p2pService,
  required Bridge bridge,
  required GroupRepository groupRepo,
  required GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  required IdentityModel identity,
  required String groupId,
}) async {
  final repo = inviteDeliveryAttemptRepo;
  if (repo == null) {
    return PendingGroupInviteMetadataRefreshResult.empty;
  }

  try {
    final attempts = await repo.getAttemptsForGroup(groupId);
    final pendingAttempts = attempts
        .where((attempt) => attempt.status != GroupInviteDeliveryStatus.joined)
        .toList(growable: false);
    if (pendingAttempts.isEmpty) {
      return PendingGroupInviteMetadataRefreshResult.empty;
    }

    var refreshedCount = 0;
    for (final attempt in pendingAttempts) {
      final result = await resendGroupInvite(
        p2pService: p2pService,
        bridge: bridge,
        groupRepo: groupRepo,
        inviteDeliveryAttemptRepo: repo,
        identity: identity,
        groupId: groupId,
        memberPeerId: attempt.peerId,
      );
      if (result.wasQueuedOrSent) {
        refreshedCount++;
      }
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INFO_FL_PENDING_INVITE_METADATA_REFRESH_DONE',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'attemptCount': pendingAttempts.length,
        'refreshedCount': refreshedCount,
      },
    );
    return PendingGroupInviteMetadataRefreshResult(
      attemptCount: pendingAttempts.length,
      refreshedCount: refreshedCount,
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INFO_FL_PENDING_INVITE_METADATA_REFRESH_WARNING',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'error': e.toString(),
      },
    );
    return PendingGroupInviteMetadataRefreshResult.empty;
  }
}
