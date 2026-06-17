/// Build-time feature flag gating the on-join authoritative-metadata resync
/// pull (Review-08 finding D / L2).
///
/// Default-ON (enabled 2026-06-17 after the two-device relay matrix passed).
/// Disable in a build with
/// `--dart-define=MKNOON_ENABLE_ONJOIN_METADATA_RESYNC=false`.
///
/// When on, accepting a group invite fires a best-effort `config:request` to
/// the inviter; a reachable peer replies with its current authoritative,
/// admin-signed group config so a joiner whose invite carried stale
/// name/avatar converges. It is a metadata-mutation vector, so the applier
/// always verifies the admin-signed actorEvent and only applies strictly-newer
/// metadata. Verified single-sim real-crypto + two-device over the prod relay
/// before being defaulted on.
///
/// Follows the repo's canonical pure-Dart build-time flag pattern (see
/// `lib/core/config/multi_device_sync_flag.dart`). `defaultValue: true` makes
/// stock builds enable it; an explicit `=false` define overrides.
const bool kOnJoinMetadataResyncEnabled = bool.fromEnvironment(
  'MKNOON_ENABLE_ONJOIN_METADATA_RESYNC',
  defaultValue: true,
);
