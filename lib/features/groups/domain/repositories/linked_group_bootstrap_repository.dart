import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/models/pending_sibling_device.dart';

enum LinkedGroupBootstrapAuthorCommitOutcome {
  committed,
  duplicate,
  refusedStateChanged,
  refusedPendingConflict,
}

enum LinkedGroupBootstrapMaterializationOutcome {
  committed,
  duplicate,
  refusedConflict,
}

/// Narrow optional capability for Plan-363 same-account group bootstrap.
///
/// It intentionally does not expand [GroupRepository]: the application has a
/// large population of test fakes, and ordinary invite/group writes must not
/// acquire this exceptional authority path accidentally.
abstract interface class LinkedGroupBootstrapRepository {
  /// Requalifies the group/self/key snapshot under the repository's per-group
  /// mutation lock and commits pending intent + legacy-preserving roster + the
  /// exact protected outbox in one SQL transaction.
  Future<LinkedGroupBootstrapAuthorCommitOutcome>
  commitLinkedGroupBootstrapAuthoring({
    required GroupModel expectedGroup,
    required List<GroupMember> expectedMembers,
    required GroupMember expectedSelfMember,
    required GroupKeyInfo expectedLatestKey,
    required GroupMember updatedSelfMember,
    required PendingSiblingDevice pendingDevice,
    required GroupPendingBroadcast pendingBroadcast,
  });

  /// Exact all-or-nothing completion after strict stored/duplicate custody.
  Future<bool> completeLinkedGroupBootstrapCustody({
    required PendingSiblingDevice expectedDevice,
    required GroupPendingBroadcast expectedBroadcast,
  });

  /// Stages key material at a deterministic bootstrap-qualified secure-store
  /// address, atomically commits group+roster+key SQL authority, and hydrates
  /// exact read-back before reporting success/duplicate.
  Future<LinkedGroupBootstrapMaterializationOutcome>
  commitLinkedGroupBootstrapMaterialization({
    required String bootstrapId,
    required GroupModel group,
    required List<GroupMember> members,
    required GroupKeyInfo key,
  });
}

/// Read-only guard used by the incumbent sibling Verify path. Protected
/// bootstrap intent remains durable until strict relay custody; it must never
/// be deleted or routed through generic current-key redistribution.
abstract interface class LinkedGroupBootstrapIntentGuard {
  Future<bool> isLinkedGroupBootstrapIntent(PendingSiblingDevice device);
}
