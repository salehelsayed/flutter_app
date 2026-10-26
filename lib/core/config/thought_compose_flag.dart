/// Build-time switch for SHARING thoughts from Orbit (plan 407).
///
/// Default-OFF. Enable with `--dart-define=MKNOON_ENABLE_THOUGHT_COMPOSE=true`.
///
/// Off hides the "+" on the user's own avatar, the only way into the thought
/// composer. Thoughts friends share still show and can be answered.
const bool kThoughtComposeEnabled = bool.fromEnvironment(
  'MKNOON_ENABLE_THOUGHT_COMPOSE',
);
