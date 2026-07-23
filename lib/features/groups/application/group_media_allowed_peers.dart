import 'package:flutter_app/features/groups/domain/models/group_member.dart';

/// Builds the relay media ACL from the current active member rows.
List<String> groupMediaAllowedPeersForMembers(Iterable<GroupMember> members) {
  final seen = <String>{};
  final allowedPeers = <String>[];
  for (final member in members) {
    for (final device in member.activeDevicesWithLegacyFallback()) {
      final transportPeerId = device.transportPeerId.trim();
      if (transportPeerId.isEmpty || !seen.add(transportPeerId)) {
        continue;
      }
      allowedPeers.add(transportPeerId);
    }
  }
  return allowedPeers;
}
