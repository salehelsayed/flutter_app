/// Shared contracts for Plan 361 blob-free direct linked-device event fanout
/// (DB v113).
///
/// One logical blob-free event (fresh text / text EDIT / Delete-for-Everyone /
/// reaction ADD/REMOVE) is encrypted independently for every currently
/// authorized target and staged as one atomic all-target batch of v108/v109
/// sibling rows. Surviving rows ARE the pending set: replay drains survivors
/// and never re-resolves the roster; exact per-row accepted handoff retires
/// exactly one sibling.
library;

/// The immutable facts of one addressing target captured BEFORE bridge crypto
/// and re-read/re-compared inside the atomic stage transaction.
class DirectContactFanoutTargetFact {
  const DirectContactFanoutTargetFact({
    required this.peerId,
    required this.mlKemPublicKey,
    required this.isLegacyAccountTarget,
    required this.fingerprint,
    this.deviceId,
    this.transportPublicKey,
  });

  /// The physical transport peer to address.
  final String peerId;

  /// The ML-KEM public key that peer decrypts with.
  final String mlKemPublicKey;

  /// True for the contact's own dynamic account target.
  final bool isLegacyAccountTarget;

  /// The immutable binding fingerprint for a linked device, or the dynamic
  /// legacy-target fingerprint for the account target. Any drift between
  /// capture and stage commit fails the whole batch all-zero.
  final String fingerprint;

  /// Null for the legacy account target.
  final String? deviceId;

  /// The device transport public key for a linked binding; null for legacy.
  final String? transportPublicKey;

  bool sameFactAs(DirectContactFanoutTargetFact other) =>
      peerId == other.peerId &&
      mlKemPublicKey == other.mlKemPublicKey &&
      isLegacyAccountTarget == other.isLegacyAccountTarget &&
      fingerprint == other.fingerprint &&
      deviceId == other.deviceId &&
      transportPublicKey == other.transportPublicKey;
}

/// The complete persisted-contact addressing snapshot one fanout stage is
/// authorized against.
///
/// Built ONLY from the persisted nonblocked contact row plus the complete
/// active v112 binding facts — never from a caller-provided legacy ML-KEM
/// value. Target order is deterministic: the dynamic legacy target first when
/// authorized, then active linked bindings in stable `device_id` order. The
/// first target is the representative generation witness.
class DirectContactFanoutSnapshot {
  const DirectContactFanoutSnapshot({
    required this.contactAccountPeerId,
    required this.contactAccountSigningPublicKey,
    required this.rosterInitialized,
    required this.targets,
  });

  final String contactAccountPeerId;
  final String contactAccountSigningPublicKey;
  final bool rosterInitialized;
  final List<DirectContactFanoutTargetFact> targets;

  DirectContactFanoutTargetFact? get representativeTarget =>
      targets.isEmpty ? null : targets.first;

  bool sameSnapshotAs(DirectContactFanoutSnapshot other) {
    if (contactAccountPeerId != other.contactAccountPeerId ||
        contactAccountSigningPublicKey !=
            other.contactAccountSigningPublicKey ||
        rosterInitialized != other.rosterInitialized ||
        targets.length != other.targets.length) {
      return false;
    }
    for (var index = 0; index < targets.length; index++) {
      if (!targets[index].sameFactAs(other.targets[index])) return false;
    }
    return true;
  }
}

/// One per-target encrypted candidate produced by bridge crypto between the
/// snapshot capture and the atomic stage transaction.
class DirectEventFanoutTargetCandidate {
  const DirectEventFanoutTargetCandidate({
    required this.recipientPeerId,
    required this.wireEnvelope,
  });

  /// The physical transport peer this exact ciphertext was encrypted for.
  final String recipientPeerId;

  /// The exact outer envelope to replay byte-for-byte for this target.
  final String wireEnvelope;
}

/// Authority carried into the private-media v114/v108 fanout transactions.
///
/// Fresh authoring must requalify the exact roster snapshot captured before
/// encryption. Restart/retry deliberately treats the complete persisted v114
/// survivor set as the sole authority and therefore performs no roster read.
enum DirectPrivateMediaFanoutStageAuthority {
  currentRosterSnapshot,
  persistedV114Survivors,
}

/// One exact private-media target at Barrier B.
///
/// These neutral fields live outside either SQL helper so the message helper
/// can bind v108 siblings without importing the media-attachment helper (which
/// already depends on the message helper).
final class DirectPrivateMediaFanoutTargetBinding {
  const DirectPrivateMediaFanoutTargetBinding({
    required this.recipientPeerId,
    required this.recipientMlKemPublicKey,
    required this.wireEnvelope,
    required this.wireMediaBlobManifestHash,
    required this.wireMediaBlobExpiresAtMs,
  });

  final String recipientPeerId;
  final String recipientMlKemPublicKey;
  final String wireEnvelope;
  final String wireMediaBlobManifestHash;
  final int wireMediaBlobExpiresAtMs;
}

/// Outcome of one atomic all-target fanout stage.
enum DirectEventFanoutStageOutcome {
  /// The canonical transition plus EVERY sibling row committed atomically.
  applied,

  /// At least one sibling row for the same logical event already existed.
  /// The surviving rows are the complete pending set; nothing was staged,
  /// no roster/capacity was consulted, and no target was appended/recreated.
  survivorReplay,

  /// Zero siblings survive and the canonical generation already records this
  /// exact event. Terminal and idempotent — never authority to resolve a new
  /// roster and remint the event.
  terminal,

  /// Refused all-zero: canonical rows, every sibling and network counters are
  /// byte-identical to before the call.
  refused,
}

/// Result of one atomic all-target fanout stage.
class DbDirectEventFanoutStageResult {
  const DbDirectEventFanoutStageResult({required this.outcome, this.rows});

  const DbDirectEventFanoutStageResult.refused()
    : outcome = DirectEventFanoutStageOutcome.refused,
      rows = null;

  final DirectEventFanoutStageOutcome outcome;

  /// The staged sibling rows on [DirectEventFanoutStageOutcome.applied], or
  /// the exact surviving rows on
  /// [DirectEventFanoutStageOutcome.survivorReplay]. Null otherwise.
  final List<Map<String, Object?>>? rows;

  /// Network may begin only after every row exists durably.
  bool get authorizesTransport =>
      outcome == DirectEventFanoutStageOutcome.applied ||
      outcome == DirectEventFanoutStageOutcome.survivorReplay;
}
