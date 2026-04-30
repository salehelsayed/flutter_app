import 'package:flutter_app/features/groups/domain/models/group_invite_consumption.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_revocation.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository.dart';

class InMemoryPendingGroupInviteRepository
    implements PendingGroupInviteRepository {
  final Map<String, PendingGroupInvite> _invites = {};
  final Map<String, GroupInviteRevocation> _revocations = {};
  final Map<String, GroupInviteConsumption> _consumptions = {};

  @override
  Future<void> savePendingInvite(PendingGroupInvite invite) async {
    _invites[invite.groupId] = invite;
  }

  @override
  Future<void> saveRevokedInvite(GroupInviteRevocation revocation) async {
    _revocations[revocation.inviteId] = revocation;
  }

  @override
  Future<void> saveConsumedInvite(GroupInviteConsumption consumption) async {
    _consumptions[consumption.inviteId] = consumption;
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
  Future<GroupInviteRevocation?> getRevokedInvite(String inviteId) async {
    return _revocations[inviteId];
  }

  @override
  Future<GroupInviteConsumption?> getConsumedInvite(String inviteId) async {
    return _consumptions[inviteId];
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

  @override
  Future<int> deleteExpiredRevokedInvites(DateTime now) async {
    final expired = _revocations.values
        .where((revocation) => !revocation.isActiveAt(now))
        .map((revocation) => revocation.inviteId)
        .toList(growable: false);
    for (final inviteId in expired) {
      _revocations.remove(inviteId);
    }
    return expired.length;
  }

  @override
  Future<int> deleteExpiredConsumedInvites(DateTime now) async {
    final expired = _consumptions.values
        .where((consumption) => !consumption.isActiveAt(now))
        .map((consumption) => consumption.inviteId)
        .toList(growable: false);
    for (final inviteId in expired) {
      _consumptions.remove(inviteId);
    }
    return expired.length;
  }

  int get count => _invites.length;

  int get revokedCount => _revocations.length;

  int get consumedCount => _consumptions.length;
}
