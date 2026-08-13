import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// Why a bounded group lifecycle leaf did or did not run.
enum SelfRemovedGroupLifecycleDisposition {
  ran,
  skippedAbsent,
  skippedSelfRemoved,
}

/// Result of one per-group native/network lifecycle leaf.
class SelfRemovedGroupLifecycleResult<T> {
  const SelfRemovedGroupLifecycleResult._({
    required this.disposition,
    this.value,
  });

  final SelfRemovedGroupLifecycleDisposition disposition;
  final T? value;

  bool get didRun => disposition == SelfRemovedGroupLifecycleDisposition.ran;
}

/// Serializes one bounded native/network action with membership authority.
///
/// Callers may shortlist work outside this function, but the final group read
/// and the single external leaf stay in the same per-group membership phase.
/// Batch loops, page loops, listener callbacks, and follow-on drains must stay
/// outside. An absent or durably self-removed shell has no lifecycle authority.
/// [authorityPhaseHeld] is an explicit capability for a caller that already
/// owns this group's non-reentrant authority phase; ordinary callers acquire
/// the phase here as before.
Future<SelfRemovedGroupLifecycleResult<T>> runSelfRemovedGroupLifecycleLeaf<T>({
  required GroupRepository groupRepo,
  required String groupId,
  required Future<T> Function(GroupModel group) action,
  bool authorityPhaseHeld = false,
}) {
  return runGroupAuthorityPhaseIfNeeded(
    groupId: groupId,
    authorityPhaseHeld: authorityPhaseHeld,
    action: () async {
      final group = await groupRepo.getGroup(groupId);
      if (group == null) {
        return SelfRemovedGroupLifecycleResult<T>._(
          disposition: SelfRemovedGroupLifecycleDisposition.skippedAbsent,
        );
      }
      if (group.selfRemovedAt != null) {
        return SelfRemovedGroupLifecycleResult<T>._(
          disposition: SelfRemovedGroupLifecycleDisposition.skippedSelfRemoved,
        );
      }
      return SelfRemovedGroupLifecycleResult<T>._(
        disposition: SelfRemovedGroupLifecycleDisposition.ran,
        value: await action(group),
      );
    },
  );
}
