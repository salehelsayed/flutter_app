import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository.dart';

class InMemoryPendingGroupInviteRepository
    implements PendingGroupInviteRepository {
  final Map<String, PendingGroupInvite> _invites = {};

  @override
  Future<void> savePendingInvite(PendingGroupInvite invite) async {
    _invites[invite.groupId] = invite;
  }

  @override
  Future<List<PendingGroupInvite>> getPendingInvites() async {
    final invites = _invites.values.toList(growable: false)
      ..sort((a, b) {
        final receivedAtCompare = b.receivedAt.compareTo(a.receivedAt);
        if (receivedAtCompare != 0) {
          return receivedAtCompare;
        }
        return a.groupId.compareTo(b.groupId);
      });
    return invites;
  }

  @override
  Future<PendingGroupInvite?> getPendingInvite(String groupId) async {
    return _invites[groupId];
  }

  @override
  Future<void> deletePendingInvite(String groupId) async {
    _invites.remove(groupId);
  }

  @override
  Future<int> deleteExpiredPendingInvites(DateTime now) async {
    final expired = _invites.values
        .where((invite) => invite.isExpiredAt(now))
        .map((invite) => invite.groupId)
        .toList(growable: false);
    for (final groupId in expired) {
      _invites.remove(groupId);
    }
    return expired.length;
  }

  int get count => _invites.length;
}
