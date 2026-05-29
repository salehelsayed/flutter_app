import 'package:flutter_app/features/groups/domain/models/group_backlog_retention_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_history_gap_repair.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

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

GroupBacklogRetentionNotice? groupBacklogRetentionNoticeFor(
  GroupModel group,
  AppLocalizations l10n,
) {
  if (group.lastBacklogExpiredAt == null) {
    return null;
  }

  final windowDays = groupBacklogRetentionWindowDays;
  if (group.lastBacklogRetainedAt != null) {
    return GroupBacklogRetentionNotice(
      kind: GroupBacklogRetentionNoticeKind.mixedWindow,
      listSummary: l10n.group_backlog_mixed_list_summary(windowDays),
      bannerText: l10n.group_backlog_mixed_banner(windowDays),
      emptyTitle: l10n.group_backlog_mixed_empty_title,
      emptySubtitle: l10n.group_backlog_mixed_empty_subtitle(windowDays),
    );
  }

  return GroupBacklogRetentionNotice(
    kind: GroupBacklogRetentionNoticeKind.fullyExpired,
    listSummary: l10n.group_backlog_expired_list_summary(windowDays),
    bannerText: l10n.group_backlog_expired_banner(windowDays),
    emptyTitle: l10n.group_backlog_expired_empty_title,
    emptySubtitle: l10n.group_backlog_expired_empty_subtitle(windowDays),
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
  AppLocalizations l10n,
) {
  if (repair == null) return null;

  switch (repair.status) {
    case groupHistoryGapRepairStatusDetected:
    case groupHistoryGapRepairStatusRepairing:
      return GroupHistoryGapRepairNotice(
        kind: GroupHistoryGapRepairNoticeKind.active,
        bannerText: l10n.group_history_repair_active_banner,
        emptyTitle: l10n.group_history_repair_active_empty_title,
        emptySubtitle: l10n.group_history_repair_active_empty_subtitle,
      );
    case groupHistoryGapRepairStatusFailed:
      return GroupHistoryGapRepairNotice(
        kind: GroupHistoryGapRepairNoticeKind.failed,
        bannerText: l10n.group_history_repair_failed_banner,
        emptyTitle: l10n.group_history_repair_failed_empty_title,
        emptySubtitle: l10n.group_history_repair_failed_empty_subtitle,
      );
    case groupHistoryGapRepairStatusRepaired:
      return GroupHistoryGapRepairNotice(
        kind: GroupHistoryGapRepairNoticeKind.repaired,
        bannerText: l10n.group_history_repair_done_banner,
        emptyTitle: l10n.group_history_repair_done_empty_title,
        emptySubtitle: l10n.group_history_repair_done_empty_subtitle,
      );
    default:
      return null;
  }
}
