# TODO: 50 Two-Simulator User Journey Coverage Gaps

Source audit: [50-two-simulator-user-journey-tests-coverage-audit.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md)

## Closure Verdict

`closed`

## Closure State

The Report `50` rollout is closed through Sessions `1` through `10` in
[50-two-simulator-user-journey-tests-todo-session-breakdown.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md).

The old P0/P1/P2 backlog is no longer active:

- Sessions `1` through `7` closed the contact, 1:1 text/media/lifecycle,
  group-reaction, and posts journey gaps.
- Sessions `8` and `9` closed the intro core replay/offline matrix plus the
  remaining intro notification, conversation-surface, migration, and boundary
  rows.
- Session `10` refreshed the audit/journey/index docs and recorded the
  accepted current notification-open contract.
- The final closure audit then widened validation beyond the original
  doc-only Session `10` plan and passed:
  - `flutter test --no-pub test`
  - the full `integration_test/` tree on macOS via isolated per-file
    `flutter test -d macos --no-pub <file>` runs
  - `./scripts/run_test_gates.sh baseline`
  - `./scripts/run_test_gates.sh feed`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport`
  - `./scripts/run_test_gates.sh completeness-check`
- `integration_test/background_reconnect_test.dart` still exits `0` while the
  current macOS runner skips its cases; that is now an explicit accepted
  runner nuance, not an open product blocker for Report `50`.

## Accepted Differences

- Message notification taps are conversation-targeted, not Feed-expanded-card
  targeted. That accepted product contract applies to `2.1`, `6.5`,
  `7.1`-`7.10`, and `8.6`.
- Group notification taps are group-targeted, and intro notification taps are
  Orbit-intros-targeted.
- Report `50` does not require simulator camera automation or the unlanded
  command-executor infrastructure proposed in
  `51-e2e-test-infrastructure-plan.md`.
- The macOS `transport` gate now intentionally runs one integration file at a
  time in `scripts/run_test_gates.sh`; that is accepted maintenance hardening
  for a runner flake, not reopened transport product work.

## Maintenance-Time Safety

- Use
  [50-two-simulator-user-journey-tests-todo-session-breakdown.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/50-two-simulator-user-journey-tests-todo-session-breakdown.md)
  plus
  [50-two-simulator-user-journey-tests-coverage-audit.md](/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/50-two-simulator-user-journey-tests-coverage-audit.md)
  as the closure-time references for what is closed versus residual-only.
- Default maintenance-time safety for broad manual-journey confidence is:
  - `flutter test --no-pub test`
  - isolated macOS `integration_test/` runs when repo-wide simulator-backed
    confidence is needed
  - the relevant named gates for the touched seam:
    `baseline`, `1to1`, `feed`, `groups`, `posts`, and `transport`
- Rerun `./scripts/run_test_gates.sh completeness-check` whenever frozen gate
  definitions change.

## Residual-Only Items

These are no longer active rollout blockers. They are only
stronger-evidence-only follow-ups if future work wants even tighter direct
proof:

- Feed unread UX niceties such as exact badge decrement walkthroughs in `8.4`
  and some notification-open/readback combinations in `7.2`, `7.3`, `7.7`,
  `7.9`, and `7.10`.
- Voice/media/device-specific confidence beyond the current viewer/delivery
  proof, especially `3.1`.
- Long-tail transport/lifecycle/device-path scripts where the repo already has
  honest chaos, smoke, or split direct evidence, such as `5.4`, `15.4`,
  `16.3`, and `16.4`.
- Long-tail intro product edges that remain narrower than the closed Session
  `8` and `9` matrix, such as `I-10.3`, `I-11.6`, `I-12.7`, and `I-12.8`.

## Still-Open Items

- None for Report `50`. Future work should reopen only on real regression or
  on an intentional product-contract change.

## Reopen Rule

Reopen this report only if one of the following happens:

1. A currently accepted Session `1` through `9` proof regresses.
2. The product contract changes again, especially notification-open routing.
3. A residual-only item becomes a real escaped bug instead of a
   stronger-evidence nicety.

## Why This TODO Is Now Safe As The Closure Reference

- The old P0/P1/P2 backlog wording is retired; this doc now records only the
  closed state, accepted differences, residual-only watchlist, and reopen bar.
- The maintenance-time gate story now matches the landed repo state, including
  the hardened macOS `transport` gate and the `605/605` completeness check.
