import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/media_preview_descriptor.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_thread_summary.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_thread_summary_repository.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/orbit/application/load_latest_media_descriptors.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';

/// Loads groups with their latest message and unread count,
/// sorted by most recent activity first.
///
/// When [includeArchived] is true, returns only archived groups.
/// Otherwise returns only active (non-archived) groups.
///
/// This drives group rows in the Orbit screen alongside friend rows.
Future<List<OrbitGroup>> loadOrbitGroups({
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  MediaAttachmentRepository? mediaAttachmentRepo,
  bool includeArchived = false,
}) async {
  emitFlowEvent(
    layer: 'UC',
    event: 'LOAD_ORBIT_GROUPS_START',
    details: {'includeArchived': includeArchived},
  );

  try {
    final List<GroupModel> groups;
    if (includeArchived) {
      final all = await groupRepo.getAllGroups();
      groups = all.where((g) => g.isArchived).toList();
    } else {
      groups = await groupRepo.getActiveGroups();
    }
    final summaries = await _loadGroupThreadSummaries(
      msgRepo: msgRepo,
      groupIds: groups.map((group) => group.id),
    );
    final descriptors = await loadLatestMediaDescriptors(
      mediaAttachmentRepo: mediaAttachmentRepo,
      messageIds: _latestMessageIds(summaries.values),
      owner: MediaOwnerLane.group,
    );
    final orbitGroups = groups
        .map(
          (group) => _buildOrbitGroup(
            group: group,
            summary:
                summaries[group.id] ?? GroupThreadSummary(groupId: group.id),
            descriptors: descriptors,
          ),
        )
        .toList(growable: false);

    _sortOrbitGroups(orbitGroups);

    emitFlowEvent(
      layer: 'UC',
      event: 'LOAD_ORBIT_GROUPS_SUCCESS',
      details: {'count': orbitGroups.length},
    );

    return orbitGroups;
  } catch (e) {
    emitFlowEvent(
      layer: 'UC',
      event: 'LOAD_ORBIT_GROUPS_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

Future<OrbitGroup?> loadOrbitGroupSnapshot({
  required GroupRepository groupRepo,
  required GroupMessageRepository msgRepo,
  required String groupId,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  emitFlowEvent(
    layer: 'UC',
    event: 'LOAD_ORBIT_GROUP_SNAPSHOT_START',
    details: {'groupId': groupId},
  );

  try {
    final group = await groupRepo.getGroup(groupId);
    if (group == null) {
      emitFlowEvent(
        layer: 'UC',
        event: 'LOAD_ORBIT_GROUP_SNAPSHOT_SUCCESS',
        details: {'groupId': groupId, 'found': false},
      );
      return null;
    }

    final summary = await _loadGroupThreadSummary(
      msgRepo: msgRepo,
      groupId: groupId,
    );
    final descriptors = await loadLatestMediaDescriptors(
      mediaAttachmentRepo: mediaAttachmentRepo,
      messageIds: _latestMessageIds([summary]),
      owner: MediaOwnerLane.group,
    );
    final orbitGroup = _buildOrbitGroup(
      group: group,
      summary: summary,
      descriptors: descriptors,
    );

    emitFlowEvent(
      layer: 'UC',
      event: 'LOAD_ORBIT_GROUP_SNAPSHOT_SUCCESS',
      details: {'groupId': groupId, 'found': true},
    );
    return orbitGroup;
  } catch (e) {
    emitFlowEvent(
      layer: 'UC',
      event: 'LOAD_ORBIT_GROUP_SNAPSHOT_ERROR',
      details: {'groupId': groupId, 'error': e.toString()},
    );
    rethrow;
  }
}

OrbitGroup _buildOrbitGroup({
  required GroupModel group,
  required GroupThreadSummary summary,
  Map<String, MediaPreviewDescriptor> descriptors =
      const <String, MediaPreviewDescriptor>{},
}) {
  final latestMessage = summary.latestMessage;
  final mayExposeLatest =
      latestMessage != null &&
      !latestMessage.privateMediaPolicy.requiresRedaction;
  return OrbitGroup(
    group: group,
    latestMessageSenderUsername: latestMessage?.senderUsername,
    latestMessageText: mayExposeLatest ? latestMessage.text : null,
    latestMessage: mayExposeLatest ? latestMessage.text : null,
    unreadCount: summary.unreadCount,
    lastActivityTimestamp: latestMessage?.timestamp ?? group.createdAt,
    latestMedia: mayExposeLatest ? descriptors[latestMessage.id] : null,
  );
}

/// Latest-message ids for a media lookup. Group messages carry no soft-delete
/// state ([GroupMessage] has no deletedAt), so every present latest qualifies.
List<String> _latestMessageIds(Iterable<GroupThreadSummary> summaries) {
  final ids = <String>[];
  for (final summary in summaries) {
    final latest = summary.latestMessage;
    if (latest != null && !latest.privateMediaPolicy.requiresRedaction) {
      ids.add(latest.id);
    }
  }
  return ids;
}

Future<GroupThreadSummary> _loadGroupThreadSummary({
  required GroupMessageRepository msgRepo,
  required String groupId,
}) async {
  final summaryRepo = msgRepo is GroupThreadSummaryRepository
      ? msgRepo as GroupThreadSummaryRepository
      : null;
  if (summaryRepo != null) {
    return summaryRepo.getGroupThreadSummary(groupId);
  }

  return GroupThreadSummary(
    groupId: groupId,
    latestMessage: await msgRepo.getLatestMessage(groupId),
    unreadCount: await msgRepo.getUnreadCount(groupId),
  );
}

Future<Map<String, GroupThreadSummary>> _loadGroupThreadSummaries({
  required GroupMessageRepository msgRepo,
  required Iterable<String> groupIds,
}) async {
  final ids = groupIds.toList(growable: false);
  if (ids.isEmpty) return const <String, GroupThreadSummary>{};

  final summaryRepo = msgRepo is GroupThreadSummaryRepository
      ? msgRepo as GroupThreadSummaryRepository
      : null;
  if (summaryRepo != null) {
    return summaryRepo.getGroupThreadSummaries(ids);
  }

  final summaries = <String, GroupThreadSummary>{};
  for (final groupId in ids) {
    summaries[groupId] = await _loadGroupThreadSummary(
      msgRepo: msgRepo,
      groupId: groupId,
    );
  }
  return summaries;
}

void _sortOrbitGroups(List<OrbitGroup> groups) {
  groups.sort((a, b) {
    final aTime = a.lastActivityTimestamp?.toUtc().toIso8601String() ?? '';
    final bTime = b.lastActivityTimestamp?.toUtc().toIso8601String() ?? '';
    return bTime.compareTo(aTime);
  });
}
