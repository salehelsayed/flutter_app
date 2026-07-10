import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';

/// Fresh route qualification. Callers invoke the media-library builder only
/// when this returns an exact active discussion group, so stale/deep sibling
/// routes perform zero media queries.
Future<GroupModel?> resolveGroupSharedMediaRoute({
  required String groupId,
  required Future<GroupModel?> Function(String groupId) loadGroup,
  bool includeAnnouncements = false,
}) async {
  final live = await loadGroup(groupId);
  final supportedType =
      live?.type == GroupType.chat ||
      (includeAnnouncements && live?.type == GroupType.announcement);
  if (live == null ||
      live.id != groupId ||
      !supportedType ||
      live.isDissolved) {
    return null;
  }
  return live;
}

/// Loads the one bounded exact-group window used by Library -> Info -> the
/// already-mounted Conversation. Wrong-group, missing, oversized, or
/// anchorless answers fail closed.
Future<List<GroupMessage>> loadGroupSharedMediaAnchorWindow({
  required GroupMessageRepository repository,
  required String currentGroupId,
  required String requestedGroupId,
  required String messageId,
}) async {
  if (requestedGroupId != currentGroupId) return const [];
  final window = await repository.getMessagesAround(
    currentGroupId,
    messageId,
    before: 25,
    after: 25,
  );
  if (window.length > 51 ||
      window.any((message) => message.groupId != currentGroupId) ||
      !window.any((message) => message.id == messageId)) {
    return const [];
  }
  return window;
}

/// Latest-request-wins fence for repeated Go-to-message results in one mounted
/// conversation. A late older repository response is discarded.
class GroupSharedMediaAnchorRequestCoordinator {
  int _generation = 0;

  Future<List<GroupMessage>?> load({
    required GroupMessageRepository repository,
    required String currentGroupId,
    required String requestedGroupId,
    required String messageId,
  }) async {
    final generation = ++_generation;
    final window = await loadGroupSharedMediaAnchorWindow(
      repository: repository,
      currentGroupId: currentGroupId,
      requestedGroupId: requestedGroupId,
      messageId: messageId,
    );
    if (generation != _generation) return null;
    return window;
  }
}
