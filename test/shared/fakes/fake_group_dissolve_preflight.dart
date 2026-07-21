import 'package:flutter_app/features/groups/application/group_exit_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_intent_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';

/// Explicit clear-state fixture for callers whose test scope predates durable
/// exit work. Production has no implicit allow authority.
GroupDissolvePreflightAuthority fakeClearGroupDissolvePreflightAuthority() =>
    GroupDissolvePreflightAuthority(
      intentRepository: _ClearGroupExitIntentRepository(),
      pendingRepository: _ClearGroupPendingBroadcastRepository(),
    );

class _ClearGroupExitIntentRepository implements GroupExitIntentRepository {
  @override
  Future<GroupExitIntent?> forGroup(String groupId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ClearGroupPendingBroadcastRepository
    implements GroupPendingBroadcastRepository {
  @override
  Future<List<GroupPendingBroadcast>> forGroup(String groupId) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
