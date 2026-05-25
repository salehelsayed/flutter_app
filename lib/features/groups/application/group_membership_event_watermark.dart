import 'dart:async';

import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

final Map<String, Future<void>> _groupMembershipMutationLocks = {};

Future<T> runGroupMembershipMutationLocked<T>({
  required String groupId,
  required Future<T> Function() action,
}) async {
  final previous = _groupMembershipMutationLocks[groupId];
  final gate = Completer<void>();
  final current = (previous ?? Future<void>.value())
      .catchError((_) {})
      .then((_) => gate.future);
  _groupMembershipMutationLocks[groupId] = current;

  if (previous != null) {
    try {
      await previous;
    } catch (_) {
      // Prior mutations release the queue through [gate] even when they fail.
    }
  }

  try {
    return await action();
  } finally {
    if (!gate.isCompleted) {
      gate.complete();
    }
    if (identical(_groupMembershipMutationLocks[groupId], current)) {
      _groupMembershipMutationLocks.remove(groupId);
    }
  }
}

bool isStaleGroupMembershipEvent({
  required DateTime eventAt,
  DateTime? lastMembershipEventAt,
}) {
  final current = lastMembershipEventAt?.toUtc();
  return current != null && !eventAt.toUtc().isAfter(current);
}

Future<void> recordGroupMembershipEventWatermark({
  required GroupRepository groupRepo,
  required String groupId,
  DateTime? eventAt,
}) async {
  if (eventAt == null) {
    return;
  }

  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    return;
  }

  final normalizedEventAt = eventAt.toUtc();
  final current = group.lastMembershipEventAt?.toUtc();
  if (current != null && !normalizedEventAt.isAfter(current)) {
    return;
  }

  await groupRepo.updateGroup(
    group.copyWith(lastMembershipEventAt: normalizedEventAt),
  );
}
