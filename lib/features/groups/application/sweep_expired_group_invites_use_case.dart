import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository.dart';

/// Per-table counts of rows reaped by [sweepExpiredGroupInvites].
class GroupInviteSweepResult {
  final int pendingInvites;
  final int revokedInvites;
  final int consumedInvites;
  final int welcomeKeyPackageTombstones;

  const GroupInviteSweepResult(
    this.pendingInvites,
    this.revokedInvites,
    this.consumedInvites,
    this.welcomeKeyPackageTombstones,
  );

  static const GroupInviteSweepResult empty = GroupInviteSweepResult(
    0,
    0,
    0,
    0,
  );

  int get total =>
      pendingInvites +
      revokedInvites +
      consumedInvites +
      welcomeKeyPackageTombstones;
}

/// Garbage-collects the four expiry-bounded group-invite side tables
/// (pending invites, revocations, consumptions, welcome key-package
/// tombstones). The revoked/consumed/tombstone tables have no other reaper, so
/// this is their only bounded-growth defense; expired pending invites are
/// removed here so dead cards disappear on the next list reload.
Future<GroupInviteSweepResult> sweepExpiredGroupInvites({
  required PendingGroupInviteRepository repo,
  DateTime Function()? now,
}) async {
  final cutoff = (now ?? () => DateTime.now().toUtc())().toUtc();
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_INVITE_SWEEP_START',
    details: {'cutoff': cutoff.toIso8601String()},
  );
  try {
    final pending = await repo.deleteExpiredPendingInvites(cutoff);
    final revoked = await repo.deleteExpiredRevokedInvites(cutoff);
    final consumed = await repo.deleteExpiredConsumedInvites(cutoff);
    final tombstones = await repo.deleteExpiredWelcomeKeyPackageTombstones(
      cutoff,
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SWEEP_SUCCESS',
      details: {
        'pending': pending,
        'revoked': revoked,
        'consumed': consumed,
        'tombstones': tombstones,
      },
    );
    return GroupInviteSweepResult(pending, revoked, consumed, tombstones);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_SWEEP_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
