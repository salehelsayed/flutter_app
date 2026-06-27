import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_history_gap_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/push/application/prepare_notification_open_use_case.dart';

Future<void> prepareNotificationRouteTarget({
  required NotificationRouteTarget routeTarget,
  required Future<void> Function() drainOfflineInbox,
  required Bridge bridge,
  required GroupRepository? groupRepository,
  required GroupMessageRepository? groupMessageRepository,
  GroupPendingKeyRepairRepository? pendingKeyRepairRepository,
  GroupHistoryGapRepairRepository? historyGapRepairRepository,
  GroupMessageListener? groupMessageListener,
  required MediaAttachmentRepository mediaAttachmentRepository,
  required ReactionRepository? reactionRepository,
  AccountMigrationNetworkGate accountMigrationNetworkGate =
      allowAccountMigrationNetworkSideEffects,
  String? selfPeerId,
  // FDC-04 (WIRE-1): eager-warm hook forwarded straight through to
  // prepareNotificationOpen. This wrapper carries no P2PService of its own, so
  // the real fn is supplied at main.dart (the only seam holding a p2p handle).
  // Optional/default-null — must be forwarded here or notif-tap warm silently
  // never fires (the dead-wire that TC-04-10b locks against).
  Future<void> Function(String peerId)? warmPeer,
}) async {
  final result = await prepareNotificationOpen(
    routeTarget: routeTarget,
    drainOfflineInbox: drainOfflineInbox,
    warmPeer: warmPeer,
    drainGroupOfflineInboxForGroup: (groupId) async {
      final allowed = await accountMigrationNetworkGate(
        peerId: selfPeerId,
        operation: 'push_notification_open_group_drain',
      );
      if (!allowed) {
        return;
      }
      final groupRepo = groupRepository;
      final groupMsgRepo = groupMessageRepository;
      if (groupRepo == null || groupMsgRepo == null) {
        throw StateError('group notification recovery is unavailable');
      }

      await drainGroupOfflineInboxForGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: groupMsgRepo,
        groupId: groupId,
        groupMessageListener: groupMessageListener,
        mediaAttachmentRepo: mediaAttachmentRepository,
        reactionRepo: reactionRepository,
        pendingKeyRepairRepo: pendingKeyRepairRepository,
        historyGapRepairRepo: historyGapRepairRepository,
        requestGroupKeyRepair: emitGroupKeyRepairRequest,
        selfPeerId: selfPeerId,
      );
    },
  );

  if (!result.ok) {
    throw StateError(result.error ?? 'notification open preparation failed');
  }
}
