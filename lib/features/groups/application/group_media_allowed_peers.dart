import 'package:flutter_app/features/groups/domain/models/group_member.dart';

/// Builds the relay media ACL from the current active member rows.
List<String> groupMediaAllowedPeersForMembers(Iterable<GroupMember> members) {
  final seen = <String>{};
  final allowedPeers = <String>[];
  for (final member in members) {
    final peerId = member.peerId.trim();
    if (peerId.isEmpty || !seen.add(peerId)) {
      continue;
    }
    allowedPeers.add(peerId);
  }
  return allowedPeers;
}
