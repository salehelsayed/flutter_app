import 'package:flutter_app/features/groups/domain/models/group_backlog_retention_policy.dart';
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
