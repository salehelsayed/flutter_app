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
DateTime nextMembershipEventAt(DateTime? lastMembershipEventAt, {DateTime? now}) {
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
