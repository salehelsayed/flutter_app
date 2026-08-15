import 'dart:async';

import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

typedef _GroupLockAddress = ({Object processScope, String groupId});

final Object _defaultGroupMembershipProcessScope = Object();
final Object _groupMembershipProcessScopeZoneKey = Object();
final Map<_GroupLockAddress, Future<void>> _groupAuthorityPhaseLocks = {};
final Object _groupAuthorityPhaseZoneKey = Object();
final Map<_GroupLockAddress, Future<void>> _groupMembershipActionLocks = {};
final Object _groupMembershipActionZoneKey = Object();

Object _currentGroupMembershipProcessScope() =>
    Zone.current[_groupMembershipProcessScopeZoneKey] ??
    _defaultGroupMembershipProcessScope;

_GroupLockAddress _groupLockAddress(String normalizedGroupId) => (
  processScope: _currentGroupMembershipProcessScope(),
  groupId: normalizedGroupId,
);

/// Creates a distinct simulated process scope for multi-device host tests.
///
/// Production never calls this seam: every ordinary caller shares the private
/// default scope and therefore retains one process-wide lock per group. Tests
/// that model independent app processes may run each process's listeners and
/// mutations in its own returned Zone without disabling non-reentrancy within
/// either simulated process.
Zone forkIndependentGroupMembershipProcessZoneForTest() => Zone.current.fork(
  zoneValues: <Object, Object>{
    _groupMembershipProcessScopeZoneKey: Object(),
    _groupAuthorityPhaseZoneKey: <String>{},
    _groupMembershipActionZoneKey: <String>{},
  },
);

bool isGroupAuthorityPhaseHeld(String groupId) {
  final normalizedGroupId = groupId.trim();
  if (normalizedGroupId.isEmpty) return false;
  final held = Zone.current[_groupAuthorityPhaseZoneKey] as Set<String>?;
  return held?.contains(normalizedGroupId) ?? false;
}

/// Whether the incumbent membership-action dispatch guard is held.
///
/// This guard is intentionally narrower than [runGroupAuthorityPhase]. It
/// keeps a legacy send's complete network action ordered against membership
/// B3 commits without forcing it to wait behind long-running key distribution
/// that owns the protected authority phase. Code holding only this guard must
/// never acquire the authority phase; dual-phase mutations use the global
/// authority-then-action order in [runGroupMembershipMutationLocked].
bool isGroupMembershipActionPhaseHeld(String groupId) {
  final normalizedGroupId = groupId.trim();
  if (normalizedGroupId.isEmpty) return false;
  final held = Zone.current[_groupMembershipActionZoneKey] as Set<String>?;
  return held?.contains(normalizedGroupId) ?? false;
}

/// Runs one mutation in the process-wide, per-group authority phase.
///
/// Membership, bootstrap receive, protected authority replay, and protected
/// key application share this queue. Re-entering the same group is rejected
/// explicitly instead of waiting on itself forever.
Future<T> runGroupAuthorityPhase<T>({
  required String groupId,
  required Future<T> Function() action,
}) async {
  final normalizedGroupId = groupId.trim();
  if (normalizedGroupId.isEmpty) {
    throw ArgumentError.value(groupId, 'groupId', 'must not be empty');
  }
  final held = Zone.current[_groupAuthorityPhaseZoneKey] as Set<String>?;
  if (held?.contains(normalizedGroupId) ?? false) {
    throw StateError(
      'group authority phase is non-reentrant for $normalizedGroupId',
    );
  }

  final lockAddress = _groupLockAddress(normalizedGroupId);
  final previous = _groupAuthorityPhaseLocks[lockAddress];
  final gate = Completer<void>();
  final current = (previous ?? Future<void>.value())
      .catchError((_) {})
      .then((_) => gate.future);
  _groupAuthorityPhaseLocks[lockAddress] = current;

  if (previous != null) {
    try {
      await previous;
    } catch (_) {
      // Prior mutations release the queue through [gate] even when they fail.
    }
  }

  try {
    return await runZoned(
      action,
      zoneValues: <Object, Object>{
        _groupAuthorityPhaseZoneKey: <String>{...?held, normalizedGroupId},
      },
    );
  } finally {
    if (!gate.isCompleted) {
      gate.complete();
    }
    if (identical(_groupAuthorityPhaseLocks[lockAddress], current)) {
      _groupAuthorityPhaseLocks.remove(lockAddress);
    }
  }
}

Future<T> runGroupMembershipActionLocked<T>({
  required String groupId,
  required Future<T> Function() action,
}) async {
  final normalizedGroupId = groupId.trim();
  if (normalizedGroupId.isEmpty) {
    throw ArgumentError.value(groupId, 'groupId', 'must not be empty');
  }
  final held = Zone.current[_groupMembershipActionZoneKey] as Set<String>?;
  if (held?.contains(normalizedGroupId) ?? false) {
    throw StateError(
      'group membership action phase is non-reentrant for $normalizedGroupId',
    );
  }

  final lockAddress = _groupLockAddress(normalizedGroupId);
  final previous = _groupMembershipActionLocks[lockAddress];
  final gate = Completer<void>();
  final current = (previous ?? Future<void>.value())
      .catchError((_) {})
      .then((_) => gate.future);
  _groupMembershipActionLocks[lockAddress] = current;

  if (previous != null) {
    try {
      await previous;
    } catch (_) {
      // Prior actions release the queue through [gate] even when they fail.
    }
  }

  try {
    return await runZoned(
      action,
      zoneValues: <Object, Object>{
        _groupMembershipActionZoneKey: <String>{...?held, normalizedGroupId},
      },
    );
  } finally {
    if (!gate.isCompleted) gate.complete();
    if (identical(_groupMembershipActionLocks[lockAddress], current)) {
      _groupMembershipActionLocks.remove(lockAddress);
    }
  }
}

Future<T> runGroupMembershipActionIfNeeded<T>({
  required String groupId,
  required bool membershipActionPhaseHeld,
  required Future<T> Function() action,
}) {
  if (membershipActionPhaseHeld) return action();
  return runGroupMembershipActionLocked(groupId: groupId, action: action);
}

/// Membership B3 work owns both the incumbent action guard and the protected
/// authority phase. Legacy sends own only the former; strict content owns
/// short authority phases instead.
Future<T> runGroupMembershipMutationLocked<T>({
  required String groupId,
  required Future<T> Function() action,
}) => runGroupAuthorityPhase(
  groupId: groupId,
  action: () =>
      runGroupMembershipActionLocked(groupId: groupId, action: action),
);

/// Enters the dual membership mutation phase without reacquiring a phase the
/// caller already owns.
///
/// The only valid order is authority then action. Protected replay commonly
/// arrives with authority already held and therefore acquires only the action
/// guard here. A caller holding action without authority is rejected because
/// acquiring authority from that state would create the inverse lock edge.
Future<T> runGroupMembershipMutationIfNeeded<T>({
  required String groupId,
  required bool authorityPhaseHeld,
  required bool membershipActionPhaseHeld,
  required Future<T> Function() action,
}) {
  final authorityHeldHere = isGroupAuthorityPhaseHeld(groupId);
  final actionHeldHere = isGroupMembershipActionPhaseHeld(groupId);
  if (authorityPhaseHeld && !authorityHeldHere) {
    throw StateError(
      'group authority phase capability is not held for $groupId',
    );
  }
  if (membershipActionPhaseHeld && !actionHeldHere) {
    throw StateError(
      'group membership action capability is not held for $groupId',
    );
  }
  if (authorityPhaseHeld) {
    return runGroupMembershipActionIfNeeded(
      groupId: groupId,
      membershipActionPhaseHeld: membershipActionPhaseHeld,
      action: action,
    );
  }
  if (membershipActionPhaseHeld || actionHeldHere) {
    throw StateError(
      'group membership action phase cannot acquire authority for $groupId',
    );
  }
  return runGroupMembershipMutationLocked(groupId: groupId, action: action);
}

Future<T> runGroupAuthorityPhaseIfNeeded<T>({
  required String groupId,
  required bool authorityPhaseHeld,
  required Future<T> Function() action,
}) {
  if (authorityPhaseHeld) return action();
  return runGroupAuthorityPhase(groupId: groupId, action: action);
}

/// Whether an incoming membership event is stale relative to the recorded
/// watermark.
///
/// Strictly-newer `eventAt` is fresh; strictly-older is stale. On an **equal
/// instant**, a deterministic tie-break by [eventId] applies *only when both
/// [eventId] and [lastEventId] are present*: the lexicographically higher id
/// wins (incoming higher ⇒ fresh; lower-or-equal ⇒ stale). When either id is
/// absent the comparator degrades to the strict rule (equal ⇒ stale), so
/// mixed-version cohorts keep today's behavior. The tie-break is symmetric:
/// the winner on one device is the loser on the other.
bool isStaleGroupMembershipEvent({
  required DateTime eventAt,
  DateTime? lastMembershipEventAt,
  String? eventId,
  String? lastEventId,
}) {
  final current = lastMembershipEventAt?.toUtc();
  if (current == null) {
    return false;
  }
  final normalized = eventAt.toUtc();
  if (normalized.isAfter(current)) {
    return false;
  }
  if (normalized.isBefore(current)) {
    return true;
  }
  // Equal instant: tie-break by event id only when both are present.
  if (eventId != null && lastEventId != null) {
    return eventId.compareTo(lastEventId) <= 0;
  }
  return true;
}

/// Returns the membership event timestamp to use for a locally-initiated
/// mutation so it never self-blocks against a watermark that a clock-skewed
/// remote event advanced past the local clock.
///
/// When [now] (defaulting to the wall clock) is strictly after the recorded
/// [lastMembershipEventAt], it is returned unchanged — the common case keeps
/// the caller's own timestamp. When [now] is equal to or before the watermark
/// (clock skew), the result is lifted to `lastMembershipEventAt + 1µs` so the
/// minted event is always strictly newer than the watermark.
/// The canonical, deterministic source event id for a locally-minted
/// membership transition: `<type>:<groupId>:<actorPeerId>:<eventAt-µs>`.
///
/// Deriving the id from the *minted* [eventAt] (not the caller's wall clock)
/// lets the sender record the same `(eventAt, eventId)` pair in its local
/// watermark that it publishes in the signed audit, so a concurrent remote
/// event with an equal instant tie-breaks against the same id on every device.
String canonicalMembershipEventId({
  required String transitionType,
  required String groupId,
  required String actorPeerId,
  required DateTime eventAt,
}) =>
    '$transitionType:$groupId:$actorPeerId:'
    '${eventAt.toUtc().microsecondsSinceEpoch}';

DateTime nextMembershipEventAt(
  DateTime? lastMembershipEventAt, {
  DateTime? now,
}) {
  final candidate = (now ?? DateTime.now()).toUtc();
  final last = lastMembershipEventAt?.toUtc();
  if (last != null && !candidate.isAfter(last)) {
    return last.add(const Duration(microseconds: 1));
  }
  return candidate;
}

Future<void> recordGroupMembershipEventWatermark({
  required GroupRepository groupRepo,
  required String groupId,
  DateTime? eventAt,
  String? eventId,
}) async {
  if (eventAt == null) {
    return;
  }

  final protectedRepository = groupRepo is GroupMembershipWatermarkRepository
      ? groupRepo as GroupMembershipWatermarkRepository
      : null;
  if (protectedRepository != null) {
    await protectedRepository.advanceGroupMembershipWatermark(
      groupId: groupId,
      eventAt: eventAt,
      eventId: eventId,
    );
    return;
  }

  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    return;
  }

  final normalizedEventAt = eventAt.toUtc();
  final current = group.lastMembershipEventAt?.toUtc();
  if (current != null) {
    if (normalizedEventAt.isBefore(current)) {
      return;
    }
    if (normalizedEventAt.isAtSameMomentAs(current)) {
      // Equal instant: only advance when the new id strictly out-tiebreaks the
      // stored one (higher id wins). When either id is absent, keep the stored
      // value so mixed-version cohorts preserve the strict (equal = no-op) rule.
      final storedId = group.lastMembershipEventId;
      if (eventId == null ||
          storedId == null ||
          eventId.compareTo(storedId) <= 0) {
        return;
      }
    }
  }

  await groupRepo.updateGroup(
    group.copyWith(
      lastMembershipEventAt: normalizedEventAt,
      lastMembershipEventId: eventId,
    ),
  );
}
