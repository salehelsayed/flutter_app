import 'package:flutter_app/features/groups/domain/models/group_backlog_retention_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_history_gap_repair.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

enum GroupBacklogRetentionNoticeKind { fullyExpired, mixedWindow }

class GroupBacklogRetentionNotice {
  final GroupBacklogRetentionNoticeKind kind;
  final String listSummary;
  final String bannerText;
  final String emptyTitle;
  final String emptySubtitle;

  const GroupBacklogRetentionNotice({
    required this.kind,
    required this.listSummary,
    required this.bannerText,
    required this.emptyTitle,
    required this.emptySubtitle,
  });
}

GroupBacklogRetentionNotice? groupBacklogRetentionNoticeFor(GroupModel group) {
  if (group.lastBacklogExpiredAt == null) {
    return null;
  }

  final windowDays = groupBacklogRetentionWindowDays;
  if (group.lastBacklogRetainedAt != null) {
    return GroupBacklogRetentionNotice(
      kind: GroupBacklogRetentionNoticeKind.mixedWindow,
      listSummary: 'Older backlog expired after $windowDays days',
      bannerText:
          'Older missed messages expired after $windowDays days. Recent messages were recovered.',
      emptyTitle: 'Recent messages recovered',
      emptySubtitle:
          'Older missed messages expired after $windowDays days while you were away.',
    );
  }

  return GroupBacklogRetentionNotice(
    kind: GroupBacklogRetentionNoticeKind.fullyExpired,
    listSummary: 'Missed backlog expired after $windowDays days',
    bannerText:
        'Missed messages older than $windowDays days expired while you were away.',
    emptyTitle: 'Older backlog expired',
    emptySubtitle:
        'Missed messages older than $windowDays days expired while you were away.',
  );
}

enum GroupHistoryGapRepairNoticeKind { active, failed, repaired }

class GroupHistoryGapRepairNotice {
  final GroupHistoryGapRepairNoticeKind kind;
  final String bannerText;
  final String emptyTitle;
  final String emptySubtitle;

  const GroupHistoryGapRepairNotice({
    required this.kind,
    required this.bannerText,
    required this.emptyTitle,
    required this.emptySubtitle,
  });
}

GroupHistoryGapRepairNotice? groupHistoryGapRepairNoticeFor(
  GroupHistoryGapRepair? repair,
) {
  if (repair == null) return null;

  switch (repair.status) {
    case groupHistoryGapRepairStatusDetected:
    case groupHistoryGapRepairStatusRepairing:
      return const GroupHistoryGapRepairNotice(
        kind: GroupHistoryGapRepairNoticeKind.active,
        bannerText:
            'Some missed messages are being repaired from trusted group members.',
        emptyTitle: 'Repairing missed messages',
        emptySubtitle:
            'Some missed messages are being verified before they appear here.',
      );
    case groupHistoryGapRepairStatusFailed:
      return const GroupHistoryGapRepairNotice(
        kind: GroupHistoryGapRepairNoticeKind.failed,
        bannerText:
            'Some missed messages could not be repaired from trusted group members.',
        emptyTitle: 'History repair needed',
        emptySubtitle:
            'Some missed messages could not be verified from trusted members.',
      );
    case groupHistoryGapRepairStatusRepaired:
      return const GroupHistoryGapRepairNotice(
        kind: GroupHistoryGapRepairNoticeKind.repaired,
        bannerText: 'Missed messages were repaired and verified.',
        emptyTitle: 'Messages repaired',
        emptySubtitle: 'Missed messages were verified and restored.',
      );
    default:
      return null;
  }
}
