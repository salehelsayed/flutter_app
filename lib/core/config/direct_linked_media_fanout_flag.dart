/// Build-time authoring selector for Plan 362 direct linked-device MEDIA,
/// VOICE and BLOB fanout (GAP-N01 adopter; DB v114).
///
/// Default-OFF. Enable in a build with
/// `--dart-define=MKNOON_ENABLE_DIRECT_LINKED_MEDIA_FANOUT=true`.
///
/// This selector is deliberately SEPARATE from both
/// `MKNOON_ENABLE_DIRECT_LINKED_EVENT_FANOUT`
/// (`lib/core/config/direct_linked_event_fanout_flag.dart`, which expressly
/// owns BLOB-FREE v108/v109 event batches) and
/// `MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED`
/// (`lib/core/config/direct_media_blob_custody_client_flag.dart`, which may
/// already be ON for single-target strict custody cohorts). Neither incumbent
/// switch, nor their intersection, is a safe rollout boundary for the NEW
/// linked blob-bearing adopter: enabling it must be its own controlled-build
/// decision, so upgrading a pair can never silently activate linked media.
///
/// Scope of this selector — it gates ONLY the authoring of NEW v114
/// blob-bearing direct-media initial generations (ordinary/voice/protected/
/// view-once/disappearing producers, external share, received-media forward):
///   * primary role with an INITIALIZED contact roster requires it together
///     with both incumbent selectors before media crypto, file write, upload,
///     target-envelope crypto or message network; any required selector OFF
///     refuses and never demotes the attempt to one target;
///   * linked-origin blob authoring always requires it.
///
/// It deliberately does NOT gate:
///   * primary + UNINITIALIZED roster — the incumbent single-target path
///     (including its LAN acceleration) stays byte-for-byte regardless;
///   * ordinary caption EDIT and Delete-for-Everyone — those remain Plan-361
///     blob-free v109 authoring under the event selector, with zero blob
///     upload, and must continue after this media selector rolls back;
///   * receiving, downloading, ACKing or cleaning up already-committed
///     durable v114/v108 rows. Flag rollback stops new fanout but can never
///     strand or reinterpret durable rows.
///
/// Follows the repo's canonical pure-Dart build-time flag pattern. Omitting
/// `defaultValue` yields `false`.
const bool kDirectLinkedMediaFanoutEnabled = bool.fromEnvironment(
  'MKNOON_ENABLE_DIRECT_LINKED_MEDIA_FANOUT',
);

/// Injectable host seam over [kDirectLinkedMediaFanoutEnabled].
///
/// Host tests inject `false`/`true` per case rather than compiling the whole
/// host bundle with the define enabled. Production owners construct this with
/// no argument so they read the real build-time constant.
class DirectLinkedMediaFanoutSelector {
  const DirectLinkedMediaFanoutSelector({bool? enabled})
    : _enabled = enabled ?? kDirectLinkedMediaFanoutEnabled;

  /// Explicitly enabled seam for host proofs.
  const DirectLinkedMediaFanoutSelector.enabled() : _enabled = true;

  /// Explicitly disabled seam for host proofs.
  const DirectLinkedMediaFanoutSelector.disabled() : _enabled = false;

  final bool _enabled;

  /// True when NEW v114 blob-bearing direct linked-media initial generations
  /// may be authored.
  ///
  /// Callers that drain, retry, download, ACK or clean up already-durable
  /// rows must NOT consult this; see the flag-independence contract above.
  bool get allowsDirectLinkedMediaFanoutAuthoring => _enabled;
}
