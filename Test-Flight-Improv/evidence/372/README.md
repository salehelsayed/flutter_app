# Plan 372 Final-Tree Final-Effect Ledger Receipt

Date: 2026-08-16 (Europe/Berlin)

This receipt records the frozen source and test tree for Plan 372: the combined
GAP-N05 immediate final-effect gate and GAP-N06 installation-local notification
ledger mechanism. It closes the current Dart/shared-mechanism slice and the one
N03-N06 host wave. It does not claim an iOS NSE or Android native adopter, live
provider acceptance, activation, full GAP-N06/A-27, PRD, or release closure.

## Verdict

- `N05_N06_FINAL_EFFECT_LEDGER_MECHANISM_CODE_COMPLETE = true`
- `N04_APP_VISIBILITY_AUTHORITY_FOUNDATION_CODE_COMPLETE = inherited`
- `N05_N06_CROSS_NATIVE_ADOPTION_COMPLETE = false`
- `N03_N06_HOST_WAVE_GREEN = true`
- One strict identifier-only v1 ledger and one incumbent effect lock now own
  every adopted current Dart exact-correlation notification transition.
- The paired opaque-wake/outcome admission remains default `false`.
- Plan 372 is Dart-only at the effect adopter boundary. `IOS_NSE` is reserved
  in the shared state vocabulary for Plan 373; no Swift or Kotlin native
  renderer/adopter is claimed here.

The following values are standalone successor contracts:

N05_N06_FINAL_EFFECT_LEDGER_MECHANISM_CODE_COMPLETE
N04_APP_VISIBILITY_AUTHORITY_FOUNDATION_CODE_COMPLETE
local_notification_ledger_v1.json
NotificationConversationIds/.coordination.lock
IOS_NSE
RELAY_VERIFIED_UNACKED
phase-preserving
DB v116
default-off

## Dependency provenance

| Dependency | Verified value |
|---|---|
| Plan 372 reviewed planning baseline / Base HEAD | `434d31d16efc506b3a57b1cdec4ebb2f15fcf66a`, tree `d47d6cb840d9431c8ad41c1e1c576f768d561b9b` |
| Plan 371 implementation/closure | `3c7e704e77f9240d62332750db4a6ecd26894b1d` |
| Plan 371 receipt SHA-256 | `dad09eb0e708629d64c0ddd3b82cb3a051509b0ff2f8750a3a46cc4b1441a11f` |
| Plan 371 frozen tested tree | `75116f8b1c7cc0cec99f2a72d1410713868d0f23` |
| Plan 371 Graphify fingerprint | `a1554310fab6234f` |
| Plan 371 marker | `N04_APP_VISIBILITY_AUTHORITY_FOUNDATION_CODE_COMPLETE` |

TC-372-00 revalidated the checksum, committed receipt blobs, ancestry, frozen
tree, allowlisted planning drift, and the three exact Plan-370 default-off
sentinels before causal RED. Plan 371 transitively binds Plans 370/369 and the
earlier N02/N01 mechanism chain; no dependency evidence was replaced by a
moving worktree.

## Implemented contract

### Identifier-only v1 ledger and one effect lock

- `LocalNotificationRecordV1`, its strict codec/state machine, and the bounded
  envelope are defined in
  `lib/core/notifications/local_notification_ledger.dart`.
- The exact Dart production ledger source containing the durable basename is
  `lib/core/notifications/local_notification_ledger_store.dart`. It owns
  `local_notification_ledger_v1.json` and explicitly binds the existing
  `NotificationConversationIds/.coordination.lock` boundary.
- `lib/core/notifications/durable_local_notification_effect_coordinator.dart`
  implements the lock-held transition/recovery machinery. Public composition
  remains on `DurableConversationNotificationIdRegistry`; its successor-pinned
  transition API names are `runFinalEffect`, `settleSqlReadyEffect`,
  `listSqlReadyEffectTerminals`, and `upgradeRelayCustodyToSqlReady`.
- The file contains only opaque binding, canonical physical/event/conversation
  identifiers, stable key/generation, lifecycle/read/policy result, owner,
  custody, effect phase, revisions, bounded attempt metadata, and strict crash
  state. It contains no message, sender, group title, preview, media, route, or
  account plaintext.
- Whole-file update is fail-closed and atomic: bounded exact BSD flock, strict
  reload/revision comparison, temporary write, file flush, rename, directory
  sync, and exact readback. Binding mismatch/rebind/logout makes copied or stale
  bytes inert. Future-schema bytes remain immutable; unresolved/current rows
  never prune merely to satisfy the bound.

### Immediate final-effect gate

- After claim/tone/preparation arming, `runFinalEffect` reloads the exact READY
  record and obtains fresh Plan-371 visibility plus current canonical facts at
  the last serialized boundary. Expected and next revisions fence stale
  contenders. There is no asynchronous gap between final authorization and the
  selected native/in-chat/cancel effect entry.
- Direct and group messages and reactions in main, background, projection, and
  reconciler paths share the same gateway/correlation semantics. All 14 current
  production `maybeShowNotification` call sites were classified; unanchored
  generic/social, activation/tap, and global-clear paths remain explicitly
  outcome-ineligible instead of receiving synthetic identities.
- `PUBLISHING` is deliberately ambiguous, never success. A known active exact
  stable ID plus disk marker proves the already-attempted card; absence permits
  only silent same-ID repair. Ambiguous cancel retains the prior `OS_POSTED`
  state until the exact cancel succeeds. Recovery cannot replay a second
  audible effect.
- Read/delete/expiry/policy and card-replacement races require the exact event,
  generation, current canonical facts, and revision. They cannot resurrect a
  retired event or cancel a newer sibling card.

### SQL A -> SETTLED -> SQL B exception

Cross-store settlement intentionally uses this order rather than pretending the
ledger file and SQLCipher are one transaction:

1. The native result reaches durable `EFFECT_TERMINAL` while the SQL outbox
   still retains exact READY custody.
2. SQL transaction A verifies/records the terminal result and conditionally
   stages the approved v116 outcome while retaining READY.
3. The file ledger advances durably to `SETTLED`.
4. Idempotent SQL transaction B retires the exact READY row and reconciles
   without another native effect or ledger revision drift.

Restart recovery at every cut replays only the missing bookkeeping. An
`EFFECT_TERMINAL` or `SETTLED` record therefore completes SQL custody with zero
second native effect. DB v116 remains the current database version; Plan 372
adds no v117 migration.

`RELAY_VERIFIED_UNACKED` may reach effect terminal, but it cannot ACK, emit a
v116 completed outcome, or settle. Exact same-correlation SQL materialization
upgrades only custody/revisions to `SQL_READY`; the transition is
phase-preserving for READY, CLAIMED, PUBLISHING, and EFFECT_TERMINAL. In
particular, a materialized PUBLISHING row remains ambiguous. Only the upgraded
EFFECT_TERMINAL replay may execute SQL A, ledger SETTLED, and SQL B.

### Compatibility and rollback

- Stable notification IDs/content generations, tone/event claims, Plan-371
  visibility, v106/v107 display/read custody, v116 outcomes, iOS recovery, and
  Android dropped-wake projections retain their existing stores and semantics.
  The v107 direct delete trigger is repaired idempotently on database open while
  the declared database version remains 116.
- Legacy rows adopt lazily from evidence-exact identifiers; there is no global
  backfill. Claims can be suspended and binding can be rebound without
  weakening strict decode or future-schema rollback.
- Account migration now promotes only keys whose destination staging backend
  supports the key scope. This preserves Android/no-shared-store migration when
  Plan 372 adds the iOS shared canonical-binding key.
- No second lock, database ledger, scheduler, native renderer, platform worker,
  activation switch, or provider payload was added.

## TDD chronology

The first exact TC-372-01 owner selected once and failed one semantic assertion
because the compile-valid inert state machine refused the valid
`SQL_READY -> CLAIMED` transition.
There was no missing symbol, load, tool, or teardown failure. The non-retained
RED JSON SHA-256 is
`06baef9305459af29a41e5177c023f144873f734f5f260a58709868fab8fe9a9`;
stderr was empty at SHA-256
`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.

### Serial semantic mutations

Each mutation was applied alone, made the named owner fail semantically, was
reverted, and was followed by exact GREEN on restored production source.

| Mutation | Causal observed RED | RED SHA-256 | Restored GREEN SHA-256 |
|---|---|---|---|
| Remove expected/next revision CAS guards | TC-372-01 observed a record instead of exact `stale-record-revision` refusal | `9fa611fcf0f692d8007e6cdfade36315224075fc380c8b353a78b89dafbe454d` | `54c895a2d22fc7052d6dd702d80a890e9891d6f82b1150209b2394d63d16dc98` |
| Recover PUBLISHING with ordinary audible publish instead of silent same-ID repair | TC-372-05 expected zero audible recovery effects and observed one | `2d26a5f61f4346e00a6f9382467407d47c51662c8f044882a8b0d0ddfda836db` | `59a116e119153671d1bde6cc353554dc743e7442bf98f38f2db1175faaea0f32` |
| Exclude SETTLED from terminal enumeration | strengthened TC-372-06 could not find the exact SETTLED record retaining READY custody | `23b04365fa8f4fc20ff268ac508227d1ec8bf5c11947aeb253c560e251e96734` | `71c4f625e6505fbe75e19b13266d7b4e02292990e756bd1860325673d1bffba7` |

All mutation stderr artifacts were empty at the same SHA-256 recorded for the
first RED stderr.

### Aggregate-wave diagnostic and bounded repairs

The first full host sweep was not accepted. It reported 19 deterministic
failures: 13 exposed a real Android/no-shared-store account-migration promotion
regression from the new iOS shared key; two counted ignored `.DS_Store` vendor
junk; two were expected DTR-18 composition fingerprints; one asserted the
superseded tracker expression instead of the route registry; and one overloaded
a 4-second hang-only flock watchdog under 1,362-path concurrency. Its
non-retained log SHA-256 is
`f1ee80b2a2917c736c34295aeedb6e78d4e1988b93cb5a42ec4f6af245295df7`.

The production migration filter was repaired at the destination capability
boundary and passed 41/41 (SHA-256
`88d5ae787e5c2133b89a55a7c8a0b3e16546debede9f458a4c9aea6d2efcfefa`).
The ignored junk file was removed, exact composition fingerprints were
re-pinned, the route assertion was updated to the actual registry expression,
and the flock outer watchdog became 15 seconds while its semantic 1.4-second
owner floor and 1-second bounded-contender limit remained unchanged. The
combined preservation repair passed 58/58 (SHA-256
`5712be82be9d469e0814cb57d8f751ad9750782912d229c73e6b3bebb2773540`),
and the final route/flock owner bundle passed 42/42.

A later full attempt found two group widget tests whose fake-time waits did not
interleave real durable file copy/hash work under aggregate load. Both waits
were replaced with the incumbent bounded async-settling pump and completion
assertion, preserving the existing approximately 60-second hang ceiling. The
non-accepted full-run log has SHA-256
`bc6d1db5ac9bcf2f9b0cc09df84bcf98ddde853d3d562f44b02642124b305eba`.
The exact harness repair passed 2/2 at SHA-256
`3ab5c2de335617b2fb799dfcc02d6251d0802f867366b4e6e627268d79a3aa83`.
No production behavior changed for those two harness repairs. Only the final
complete rerun below is accepted as the N03-N06 wave gate.

## Final gates

All hashes below identify non-retained temporary evidence. No test/build log is
committed; the receipt commits only provenance inputs needed by successors.

| Gate | Final result | Non-retained artifact SHA-256 |
|---|---|---|
| Dependency preflight TC-372-00 | Plan-371 checksum/ancestry/tree/drift and three default-off sentinels PASS | terminal attestation |
| Focused TC-372 bundle | exactly 6/6 PASS; zero skips | `6726cd7dfd0d2fdb3e8c93bb3c2ec4dfd6ad29705db0a49fcd6f26e00b5373e9` |
| Serial convergence bundle | exactly 5/5 PASS; zero skips | `85d9f5562e298cd943dc1fd62a9fa791a393d2f18944c39b42214b6ef5f735be` |
| Exact preservation bundle | exactly 12/12 PASS; zero skips | `c976d4c49bb584df30cf911fb0f927b975c8bf53640801bf2ab6b75f291f0e24` |
| Registration | four new shared tests occur exactly once in `ONE_TO_ONE_TESTS`, `GROUP_TESTS`, and `ONE_TO_ONE_HOST_TESTS` | terminal attestation |
| Curated `1to1` | 3,330 Flutter PASS; 10 declared skips; relay/ACK/media tails PASS | `7366aad9a82a192894189f3457b458b753997e7915536555f20671726cdf5677` |
| Curated `groups` | 4,334 Flutter PASS; zero failures/skips; group bridge/node/relay tails PASS | `4f53c19d3ab438c71ef147aa70dad52969b7288638b56e6db18656aee1ab9e2c` |
| N03-N06 aggregate `host-all` | 1,362 Flutter paths; 14,288 PASS / 11 declared skips / 0 failures; host items 1363-1376, including native, all PASS; final scope PASS | `3c453e6d6cddce70ba787475e52fe0f0568944a975299ff5c000635f15df1895` |
| Post-format complete show owner | 56/56 PASS | `618620d3e090f117d6d6c39bfc9d6055931229d894c56e5d501387c6e9cce4a4` |
| Changed-Dart format | 72 files checked; zero changes required | `249033e5e44399de5e1a805e3b248a0da97cc61d6b5fab62510edb1971cb9a58` |
| Full analyzer | no issues | `e8faae38aa6ad4e3364d21b9ff004bb5e5f0f69a72d4c66293f1d95315a45d4c` |
| Static/diff/shell/source hygiene | all PASS | `b9a9725019131cf93ef3daadebf3cf30cd7b52f7624f4d3fc3b2c93849b31181` |

The first analyzer attempt encountered an ignored Gradle `java_res` copy left
by native host work. It was quarantined to `/tmp`; the clean rerun above found
no source issue. No `core-host-all` or `feature-host-all` was added: the one
aggregate `host-all` is the project-approved Plan-372 wave exception and
subsumes those families.

## Current-source audit

| Guard | Final value |
|---|---:|
| Base-to-frozen changed paths | 78 |
| Added / modified / deleted | 8 / 70 / 0 |
| Production / test paths | 38 / 35 |
| Dart / shell paths | 72 / 2 |
| Gate-script / Graphify / plan paths | 2 / 2 / 1 |
| Classified production `maybeShowNotification` calls | 14 |
| New shared causal test files | 4 |
| New Swift / Kotlin native effect adopters | 0 / 0 |
| Database version | 116; no v117 migration |
| Production files containing `local_notification_ledger_v1.json` | 1, `lib/core/notifications/local_notification_ledger_store.dart` |
| Paired opaque wake/outcome admission | one shared seam, default `false` |

The 38 production paths include the v107 on-open trigger repair and the bounded
account-migration compatibility repair found by the aggregate gate. Neither is
a new database version, platform adapter, or activation surface.

## Graph grounding

One incremental architecture refresh followed the final source and harness
repairs. The exact review query was current and anchored at the frozen source.

| Graph fact | Final value |
|---|---|
| Freshness / confidence | `current` / `anchored` |
| Graphify fingerprint | `8c428eb87b960e70` |
| Nodes / edges | 77,289 / 113,295 |
| TDD overlay | 1,594 files / 15,735 named cases / 1,255 production targets / 1,514 registered tests |
| `graph.json` SHA-256 | `90cfbe3a9a18c2b6cec32e59c30d468fb782e33d72ea78308a0b392d99b836c1` |
| `manifest.json` SHA-256 | `e76f50c22a68d7904c14b3dd0dcf182c542800dd9ab1088f5e650bf72ea2d860` |
| `tdd-overlay.json` SHA-256 | `dd62e5844d09c59c93332367d8b6d4a30ee2bd2137cb06796302be5a3a0d24c4` |
| Refresh log SHA-256 | `3c5cf83086e2faf0a50db9b8dd72e705ae3a58b61519ae7259077f28b0eb98fa` |
| Review query SHA-256 | `00dbf5d1fd6d3e22cf2564a72bf52565b08750ad71de5df0a1a0dc666c1f38ab` |

Graphify anchored the ledger/store/coordinator, registry/public transition
surface, direct/group projection owners, final visibility gate, background
adopter, and SQL convergence tests. Executable gates remain authoritative.

## Frozen tested state

An alternate Git index captured the tested Plan-372 transaction without
changing the shared index. The Plan-373/375 successor edits, their current index
hunk, and the coverage update were deliberately excluded from the frozen tree.
The raw workspace snapshot preserves that state rather than hiding it.

| Identity | Value |
|---|---|
| Capture date | `2026-08-16` (Europe/Berlin) |
| Branch | `protected-view` |
| Base HEAD | `434d31d16efc506b3a57b1cdec4ebb2f15fcf66a` |
| Base/HEAD tree | `d47d6cb840d9431c8ad41c1e1c576f768d561b9b` |
| Frozen tested tree | `71ab5f0ddcfa5e682f50f1bc36ebb891567b78b2` |
| Porcelain-v2 workspace snapshot SHA-256 | `45e68aab0c0a79750102ccbccd1e010f663dea20a50ea5221cffa1e9278357ed` |
| Porcelain-v2 status records / bytes | `82` plus 4 branch headers / `14,180` |
| Compressed snapshot SHA-256 | `e6311ee51cefca9a66201478ab07b0bc1ae1b5a4ff833cc6903117f2a08f027c` |
| Frozen paths SHA-256 | `63e85278fbc2f52773050b5046796895f6c35903f394b0db41c8b226d09e6195` |
| Frozen name-status SHA-256 | `11aba738774953eb9cf35a4f3dce0bfeec4620ad36ac5edb9d656d318cde5e5c` |
| Frozen numstat SHA-256 | `0f19e97d071fbcd6897d5d2c268dcea1c6d9ed171b134789f3f3de78e4fca268` |
| Shared-index entries / list SHA-256 | `6,444` / `84280f8e254b8e6f13c76e93c6c1d38e93dc8662c1f877be667319601f4c7ec6` |
| Shared-index byte SHA-256 | `33ca8488d1d25457e599063a86ecbf83446459165e24bd27ee0ecc1865620bf3` |
| Alternate-index entries / list SHA-256 | `6,452` / `43525c16bbf1bf90a972ee4177474763070865e6c58e4bf8d9ebdde9997a69bf` |
| Alternate-index bytes / SHA-256 | `916,561` / `50fb6b8ee2b437f807f539156f622eba58829f7fe915523ea95aaa888787bf7b` |

Machine-readable identities:

```text
Base HEAD: 434d31d16efc506b3a57b1cdec4ebb2f15fcf66a
Frozen tested tree: 71ab5f0ddcfa5e682f50f1bc36ebb891567b78b2
Dirty snapshot SHA-256: 45e68aab0c0a79750102ccbccd1e010f663dea20a50ea5221cffa1e9278357ed
Graphify fingerprint: 8c428eb87b960e70
```

`workspace-porcelain-v2.txt.gz` decompresses byte-exactly to the normalized
snapshot whose SHA-256 is recorded above. `graphify-fingerprint.txt` contains
the exact 16-hex graph identity. Both files, this README, and its sibling
checksum are successor-verifiable committed evidence.

This README, checksum, archive, fingerprint file, and the final
plan/status/index/coverage closure necessarily postdate and are absent from the
frozen tested tree. They add no production, test, native, fixture, script, or
Graphify transaction after the accepted gates.

## Independent audit and residual boundaries

Independent final review found no release-blocking defect. Three bounded
non-blocking residuals remain explicit: the state machine accepts a few
preterminal combinations the coordinator never emits; seven-day settled-row
pruning does not inspect a pathological indefinitely failing SQL-B row; and
directory-sync failure is fail-closed but lacks a dedicated injected-fault
test. Current unresolved/current rows remain non-evictable, restart paths retain
custody, and these residuals do not authorize cross-native or live claims.

## Handoff

Plan 373 may consume the checksum-bound v1 ledger/state vocabulary and add the
iOS NSE adapter against the same App-Group file, exact lock, strict codec, and
phase contract. It must not infer a Swift implementation from this Dart-only
receipt. Plans 374/375 retain production headless and fixed Android adoption;
the adapter wave owns its later aggregate host gate.

This receipt closes only the Plan-372 current-Dart/shared-mechanism boundary and
the one N03-N06 host wave. It makes no native-adapter-complete, device, live
provider, activation, full GAP-N06/A-27, N11, PRD, deployment, or release claim.
