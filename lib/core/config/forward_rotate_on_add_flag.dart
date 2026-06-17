/// Build-time flag (default-OFF) for B5: rotate the group key after adding a
/// member, so a joiner cannot read prior-epoch live traffic. This is an optional
/// forward-secrecy improvement INDEPENDENT of multi-device sync; it adds a full
/// key rotation + per-device distribution to every add (latency/cost), so it is
/// opt-in via `--dart-define=MKNOON_ENABLE_FORWARD_ROTATE_ON_ADD=true`.
const bool kForwardRotateOnAddEnabled = bool.fromEnvironment(
  'MKNOON_ENABLE_FORWARD_ROTATE_ON_ADD',
);
