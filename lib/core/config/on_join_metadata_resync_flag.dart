/// Build-time feature flag gating the on-join authoritative-metadata resync
/// pull (Review-08 finding D / L2).
///
/// Default-OFF. Enable in a build with
/// `--dart-define=MKNOON_ENABLE_ONJOIN_METADATA_RESYNC=true`.
///
/// When on, accepting a group invite fires a best-effort `config:request` to
/// the inviter; a reachable peer replies with its current authoritative,
/// admin-signed group config so a joiner whose invite carried stale
/// name/avatar converges. Ships dark until verified on a two-device matrix —
/// it is a metadata-mutation vector, so the applier always verifies the
/// admin-signed actorEvent and only applies strictly-newer metadata.
///
/// Follows the repo's canonical pure-Dart build-time flag pattern (see
/// `lib/core/config/multi_device_sync_flag.dart`). Omitting `defaultValue`
/// yields `false`.
const bool kOnJoinMetadataResyncEnabled = bool.fromEnvironment(
  'MKNOON_ENABLE_ONJOIN_METADATA_RESYNC',
);
