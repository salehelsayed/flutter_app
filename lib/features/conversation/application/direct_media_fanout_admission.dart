/// Plan 362 GAP-N01 admission boundary for NEW send-owned direct media, voice
/// and blob generations.
///
/// Every fresh blob-bearing producer (composer, voice, external OS share,
/// received-media forward, group->contact forward) resolves exactly ONE route
/// here, after read-only MIME/size/modality validation and BEFORE any upload
/// lease, composer clearing, message/attachment persistence, durable copy,
/// crypto, custody staging or network. Survivor replay never calls this: a
/// persisted v108/v114 generation drains from its stored authority and must
/// never re-resolve the roster.
///
/// The three routes are deliberately distinct because a null snapshot is NOT
/// evidence of an uninitialized legacy contact — see
/// [OutgoingDirectLinkedMediaBlobFanoutRepository.readDirectContactFanoutSnapshotForMedia],
/// whose contract requires callers to fail closed instead of reinterpreting it.
library;

import 'package:flutter_app/core/database/direct_event_fanout_contract.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

/// The one route a fresh direct blob generation is admitted to.
enum DirectMediaFanoutAdmissionRoute {
  /// Uninitialized primary roster: the incumbent single-target path is
  /// authorized and stays byte-identical, LAN acceleration included.
  incumbentSingleTarget,

  /// Initialized roster and a caller that can serve every persisted target.
  linkedFanout,

  /// Initialized roster the caller cannot serve, or a roster state that cannot
  /// be established. Refuse before any send-owned durable write; never demote.
  refusedUnavailable,
}

/// The resolved route plus the exact snapshot a [linkedFanout] stage must be
/// authorized against.
final class DirectMediaFanoutAdmission {
  const DirectMediaFanoutAdmission._(this.route, this.snapshot, this.reason);

  const DirectMediaFanoutAdmission.incumbentSingleTarget(String reason)
    : this._(
        DirectMediaFanoutAdmissionRoute.incumbentSingleTarget,
        null,
        reason,
      );

  const DirectMediaFanoutAdmission.linkedFanout(
    DirectContactFanoutSnapshot snapshot,
  ) : this._(
        DirectMediaFanoutAdmissionRoute.linkedFanout,
        snapshot,
        'roster_initialized',
      );

  const DirectMediaFanoutAdmission.refusedUnavailable(String reason)
    : this._(DirectMediaFanoutAdmissionRoute.refusedUnavailable, null, reason);

  final DirectMediaFanoutAdmissionRoute route;

  /// Non-null ONLY on [DirectMediaFanoutAdmissionRoute.linkedFanout]. This is
  /// the exact snapshot the atomic stage re-compares in-transaction; callers
  /// must not resolve a second one.
  final DirectContactFanoutSnapshot? snapshot;

  /// Stable telemetry discriminator; never user-facing.
  final String reason;

  bool get allowsIncumbentSingleTarget =>
      route == DirectMediaFanoutAdmissionRoute.incumbentSingleTarget;

  bool get requiresLinkedFanout =>
      route == DirectMediaFanoutAdmissionRoute.linkedFanout;

  bool get refuses =>
      route == DirectMediaFanoutAdmissionRoute.refusedUnavailable;
}

/// Resolves the single admission route for one fresh direct blob generation.
///
/// [canServeLinkedFanout] is the caller's honest declaration that it can
/// publish every persisted target through the all-target owner — the required
/// authoring selectors AND a plural coordinator. A producer without plural
/// routing passes `false` and an initialized roster then refuses rather than
/// silently reaching one target.
///
/// This function is selector-independent by construction: the underlying
/// capability is wired unconditionally in production, so roster state is
/// readable whether or not the authoring selectors are compiled on. That is
/// what lets a default build refuse instead of demoting.
Future<DirectMediaFanoutAdmission> resolveDirectMediaFanoutAdmission({
  required Object? mediaAttachmentRepository,
  required String contactAccountPeerId,
  required bool canServeLinkedFanout,
}) async {
  final repository = mediaAttachmentRepository;
  if (repository is! OutgoingDirectLinkedMediaBlobFanoutRepository ||
      !repository.supportsDirectLinkedMediaBlobFanout) {
    // The capability is absent ENTIRELY, not merely switched off:
    // supportsDirectLinkedMediaBlobFanout depends only on injected db
    // functions and never on an authoring selector, and production wires all
    // of them unconditionally. So this is a composition with no linked roster
    // to read at all, and refusing would break the incumbent single-target
    // contract for a roster that is provably uninitialized.
    return const DirectMediaFanoutAdmission.incumbentSingleTarget(
      'fanout_capability_absent',
    );
  }
  if (contactAccountPeerId.isEmpty ||
      contactAccountPeerId != contactAccountPeerId.trim()) {
    return const DirectMediaFanoutAdmission.refusedUnavailable(
      'contact_peer_id_invalid',
    );
  }
  DirectContactFanoutSnapshot? snapshot;
  try {
    snapshot = await repository.readDirectContactFanoutSnapshotForMedia(
      contactAccountPeerId,
    );
  } catch (_) {
    return const DirectMediaFanoutAdmission.refusedUnavailable(
      'snapshot_read_error',
    );
  }
  if (snapshot == null) {
    // Repository contract: null means the persisted contact snapshot cannot
    // authorize ANY route (missing, blocked, or keyless). It is never evidence
    // of an uninitialized roster and therefore must not demote to the caller's
    // stale single-target contact value.
    return const DirectMediaFanoutAdmission.refusedUnavailable(
      'contact_snapshot_absent',
    );
  }
  if (!snapshot.rosterInitialized) {
    return const DirectMediaFanoutAdmission.incumbentSingleTarget(
      'roster_uninitialized',
    );
  }
  if (snapshot.targets.isEmpty) {
    return const DirectMediaFanoutAdmission.refusedUnavailable(
      'zero_authorized_targets',
    );
  }
  if (!canServeLinkedFanout) {
    return const DirectMediaFanoutAdmission.refusedUnavailable(
      'linked_fanout_unavailable',
    );
  }
  return DirectMediaFanoutAdmission.linkedFanout(snapshot);
}
