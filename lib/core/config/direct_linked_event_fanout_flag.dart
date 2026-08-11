/// Build-time authoring selector for Plan 361 direct linked-device BLOB-FREE
/// event fanout (GAP-N01 adopter; DB v113).
///
/// Default-OFF. Enable in a build with
/// `--dart-define=MKNOON_ENABLE_DIRECT_LINKED_EVENT_FANOUT=true`.
///
/// This selector is deliberately SEPARATE from both
/// `MKNOON_ENABLE_DIRECT_LINKED_DEVICES`
/// (`lib/core/config/direct_linked_devices_flag.dart`, authority creation /
/// QR admission) and `MKNOON_ENABLE_MULTI_DEVICE_SYNC` (unfinished group
/// same-user convergence). Trusting a device (Plan 360) proves identity, not
/// that the remote installation runs the Plan 361 event grammar; authoring
/// fanout is therefore its own controlled-build decision and neither flag may
/// stand in for the other.
///
/// Scope of this selector — it gates ONLY the authoring of NEW v113 blob-free
/// direct-event fanout batches (fresh text, text EDIT, Delete-for-Everyone,
/// reaction ADD/REMOVE):
///   * primary role with an INITIALIZED contact roster requires it before any
///     target crypto or network; OFF refuses and never demotes the attempt to
///     the incumbent single legacy target;
///   * linked-origin blob-free authoring always requires it, even when the
///     resolver currently yields only the dynamic legacy target.
///
/// It deliberately does NOT gate:
///   * primary + UNINITIALIZED roster — the incumbent single-target path stays
///     byte-for-byte regardless of this selector;
///   * receiving or rejecting/quarantining linked input;
///   * draining/retrying already-committed durable v113 rows. Flag rollback
///     stops new fanout but can never strand or reinterpret durable rows.
///
/// Follows the repo's canonical pure-Dart build-time flag pattern. Omitting
/// `defaultValue` yields `false`.
const bool kDirectLinkedEventFanoutEnabled = bool.fromEnvironment(
  'MKNOON_ENABLE_DIRECT_LINKED_EVENT_FANOUT',
);

/// Injectable host seam over [kDirectLinkedEventFanoutEnabled].
///
/// Host tests inject `false`/`true` per case rather than compiling the whole
/// host bundle with the define enabled. Production owners construct this with
/// no argument so they read the real build-time constant.
class DirectLinkedEventFanoutSelector {
  const DirectLinkedEventFanoutSelector({bool? enabled})
    : _enabled = enabled ?? kDirectLinkedEventFanoutEnabled;

  /// Explicitly enabled seam for host proofs.
  const DirectLinkedEventFanoutSelector.enabled() : _enabled = true;

  /// Explicitly disabled seam for host proofs.
  const DirectLinkedEventFanoutSelector.disabled() : _enabled = false;

  final bool _enabled;

  /// True when NEW v113 blob-free direct-event fanout batches may be authored.
  ///
  /// Callers that drain, retry, or receive already-durable rows must NOT
  /// consult this; see the flag-independence contract documented above.
  bool get allowsDirectLinkedEventFanoutAuthoring => _enabled;
}
