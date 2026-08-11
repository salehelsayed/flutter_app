/// Build-time authoring selector for the Plan 360 direct linked-device
/// addressing foundation (GAP-N01 / WP-01).
///
/// Default-OFF. Enable in a build with
/// `--dart-define=MKNOON_ENABLE_DIRECT_LINKED_DEVICES=true`.
///
/// This selector is deliberately SEPARATE from
/// `MKNOON_ENABLE_MULTI_DEVICE_SYNC` (`lib/core/config/multi_device_sync_flag.dart`).
/// That flag gates the *group* same-user convergence build; widening it to
/// cover direct linked devices would activate sibling-device admission, group
/// key continuity, and peer hydration that Plan 360 does not implement and has
/// not proven. Never conflate the two.
///
/// Scope of this selector — it gates ONLY:
///   * creation of a new linked-secondary installation authority,
///   * authoring and scanning the dual-signed direct linked-device QR,
///   * the restricted linked setup/status UI route.
///
/// It deliberately does NOT gate persisted authority. A build that flips this
/// define back to false must still start the exact transport an already-active
/// linked credential names (see [DirectLinkedDeviceSelector] docs and
/// `linked_installation_authority.dart`): authoring rollback is not a
/// mechanism for invalidating durable device identity.
///
/// Follows the repo's canonical pure-Dart build-time flag pattern (see
/// `lib/core/config/multi_device_sync_flag.dart`). Omitting `defaultValue`
/// yields `false`.
const bool kDirectLinkedDevicesEnabled = bool.fromEnvironment(
  'MKNOON_ENABLE_DIRECT_LINKED_DEVICES',
);

/// Injectable host seam over [kDirectLinkedDevicesEnabled].
///
/// Host tests inject `false`/`true` per case rather than compiling the whole
/// host bundle with the define enabled. Production owners construct this with
/// no argument so they read the real build-time constant.
class DirectLinkedDeviceSelector {
  const DirectLinkedDeviceSelector({bool? enabled})
    : _enabled = enabled ?? kDirectLinkedDevicesEnabled;

  /// Explicitly enabled seam for host proofs.
  const DirectLinkedDeviceSelector.enabled() : _enabled = true;

  /// Explicitly disabled seam for host proofs.
  const DirectLinkedDeviceSelector.disabled() : _enabled = false;

  final bool _enabled;

  /// True when NEW linked authority may be created and the dual-signed QR may
  /// be authored or scanned.
  ///
  /// Callers that decide whether to *start* an already-persisted linked
  /// transport must NOT consult this; see the flag-off preservation contract
  /// documented above.
  bool get allowsLinkedDeviceAuthoring => _enabled;
}
