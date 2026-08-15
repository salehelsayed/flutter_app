# Plan 371 Final-Tree Durable App Visibility Authority Receipt

Date: 2026-08-16 (Europe/Berlin)

This receipt records the frozen source and test tree for Plan 371, the bounded
GAP-N04 lifecycle/visible-conversation authority and current-adopter slice. It
does not establish full GAP-N04, N03, live-provider, rollout, PRD, or release
acceptance.

## Verdict

- `N04_APP_VISIBILITY_AUTHORITY_FOUNDATION_CODE_COMPLETE = true`
- `N03_COMPLETE = false`
- `N04_LIVE_ACCEPTANCE_PROVEN = false`
- One root Dart authority now owns fresh lifecycle plus exact visible-chat
  suppression for current Flutter direct/group message and reaction paths.
- iOS and Android expose one shared versioned snapshot contract. Unknown,
  malformed, future-schema, stale, wrong-boot, wrong-lifecycle, or wrong-chat
  state always fails toward notification.
- The paired N03 capability/outcome admission remains default `false`.

The exact completion marker is:

```text
N04_APP_VISIBILITY_AUTHORITY_FOUNDATION_CODE_COMPLETE
```

This is a foundation marker only. Plans 372 and later retain the immediate
final-effect ledger/barrier and native consumer work; consolidated Apple-device
acceptance remains deferred by project policy.

## Dependency provenance

| Dependency | Verified value |
|---|---|
| Plan 371 reviewed planning baseline | `9be694a19e4f17973e447f8b98c8167b9881fd74`, tree `d31e890195b200444076cf14dfb664f54559cc06` |
| Plan 370 implementation/closure | `b90455347f64bd102056bc13d62d89fe5e379cb9`, tree `8d386473c747f1318945124f7c94b797843a46e0` |
| Plan 370 receipt SHA-256 | `14af6bddc18cda365b1bda36bc69d1c0d23b5f7106dc6f9f72e04641eada0b04` |
| Plan 370 marker | `N03_WAKE_OUTCOME_COORDINATOR_FOUNDATION_CODE_COMPLETE` |
| Plan 369 implementation/closure | `ddf4b1459187b074128213e72b8456bd44e39cef` |
| Plan 369 receipt SHA-256 | `8d4229405b1b39ac26dd2304fa77455322be8b25c1b1f573a4903f0044d4873c` |
| Plan 369 marker | `N03_DURABLE_LOCAL_OUTCOME_FOUNDATION_CODE_COMPLETE` |

The execution baseline differs from Plan 370 only by the five reviewed and
allowlisted planning documents recorded in Plan 371. All dependency receipt
checks, ancestry/tree pins, and the three default-off N03 sentinels passed
before RED.

## Implemented contract

### Shared snapshot and predicate

- Schema v1 is one whole record containing `revision`,
  `lifecycleGeneration`, `lifecycle`, nullable
  `visibleConversationDigest`, `updatedMonotonicMs`, and `bootSession`.
- The canonical digest is lowercase SHA-256 over the frozen domain, lane, and
  LP32BE-normalized conversation bytes. Direct and `group:<id>` grammar,
  whitespace, control/C1, embedded group-colon, invalid Unicode, and the
  `unavailable` boot sentinel agree across Dart, Swift, and Kotlin through the
  one repository fixture.
- Suppression requires schema v1, a valid current boot, exact
  `FOREGROUND_ACTIVE`, exact digest, nonnegative age, and age strictly below
  90,000 ms. Route refresh is bounded at 60,000 ms. Every unsafe state notifies.
- The Dart authority serializes bridge I/O, verifies native commit/readback,
  generation-fences delayed route writes, and latches a failed generation
  ineligible until a newer native lifecycle generation is observed.

### Root lifecycle, route, and account ownership

- Production creates one `AppVisibilityAuthority` and one
  `AppVisibilityRouteRegistry`, then threads both through `MyApp` and the
  incumbent root route-observer scope.
- The single existing route observer now tracks direct, ordinary-group, and
  linked-group top routes without adding a Navigator or observer. Notification
  open dedupe uses process-local top-route identity; notification suppression
  uses only the fresh native-backed authority.
- Lifecycle changes invalidate synchronously before asynchronous continuation.
  Resume synchronizes native state before route republish and presence relay
  work. Root disposal invalidates before other teardown.
- Post-review repair also invalidates synchronously before account-replacement
  cutover and before migrated-out account erase/native cleanup. The callback is
  forwarded through a restarted `StartupRouter`.

### Current notification adopters

- All ten production `maybeShowNotification` invocations receive the canonical
  suppression reader; raw tracker/lifecycle presentation bypasses are absent.
- Direct/group messages, reactions, unanchored fallback, and canonical display
  reconciliation evaluate the same authority. Chat B and non-chat routes remain
  notification-eligible.
- Protected group message/reaction custody stages independently of visibility;
  the later display projection owns the fresh decision. Suppression never mints
  a completed outcome, marks read, deletes state, or cancels a delivered card.
- Existing direct/group trackers remain only for route/read/keepalive
  compatibility consumers, not as a second notification authority.

### Native projections

- Channel `mknoon/app_visibility` exposes only `readSnapshot` and
  `publishVisibleConversation` with strict maps and fail-safe null/false
  results.
- iOS Runner and NSE share one App-Group file protected by stable BSD flock,
  whole-record temporary-file write, fsync, rename, directory sync, and
  readback. UIApplication/UIScene duplicates are semantically coalesced so an
  interleaved route CAS is not cleared. Both targets ship their required-reason
  privacy manifests.
- Android uses one process and one whole-record `AtomicFile`; `MainActivity`
  synchronously orders cold/start/resume/pause/stop transitions and the method
  channel. A manifest proof prevents an unreviewed multiprocess assumption.
- No NSE/FCM/WorkManager renderer, SQL/DB migration, ledger, worker, scheduler,
  notification style, or provider payload changed. DB remains v116.

## TDD chronology

The first named owner was captured as a genuine assertion RED before the
predicate implementation. The exact TC-371-01 name selected once, completed as
one non-skipped failure, and reported fresh active exact A as `false`; there was
no compile, load, tool, or teardown error. The non-retained JSON SHA-256 is
`68956f036463af2bdbc900117868fb9c867184afc8583660b943cf315a98c34c`.

Final counterexample review found the missing account-replacement invalidation.
The strengthened TC-371-05a then failed semantically because native recovery
mutation was the first statement instead of synchronous invalidation. Its RED
log/JSON hashes are `6a21dd6dcfc9236fb47e81242074c45f5cbabd66836e244695ca939502085817`
and `9ce09fb5fb922394a43f961ceeae8d1fc79f9123909308bff492ca338c2ea589`.
After repair, the exact AST plus runtime erase-order bundle passed 2/2 and the
complete startup-router owner passed 26/26.

### Serial semantic mutations

Each required mutation was applied alone, made its exact causal owner RED, was
reverted, and was followed by GREEN.

| Mutation | Causal observed RED | Non-retained artifact SHA-256 |
|---|---|---|
| Accept age exactly 90,000 ms | TC-371-01 rejected `stale_exact_90000ms` | log `7a6e867d26ae8eaf01a5bc5d28b66e3d6bfb7ba84022c1677d598b52feab22ac`; JSON `ac35d6182f9f1c97089ff909471e1d4a8c9ce5d4871133a01957fe8048fb80a1` |
| Treat failed native commit/readback as eligible | TC-371-02a rejected successful synchronization after failed verification | log `c11e5c2bdc0799d2ae15bb2c9cf47784d1ce5c3d254d93ec5e12003dabd14aca`; JSON `716383bc4a2f877784203a0bcb2c070e8ce314509bf0e7609cd7171fda353d9d` |
| Restore a raw tracker `isViewing` bypass | TC-371-05a production AST owner rejected the bypass | log `bad6f0174196838509f5786d75dd328360535517eba802d994f3c835364cd7d6`; JSON `9cc70d04d3261383912e25c912a157a86e6dfbff3105118d4a00ce216108aeef` |
| Remove iOS duplicate-active coalescing | Exact TC-371-06 XCTest failed four generation/route assertions with zero skips | log `42c6437ff4f1e9c5c89854c0fa248f5e599868b94754bf65eb9da145fb5247c3`; summary `0414c707578cadaca9d4680025a82909ec5d02daf9993193874719ee24f9ff8d` |
| Persist Android `INACTIVE` instead of `BACKGROUND` on stop | Exact TC-371-07 observed expected `BACKGROUND`, actual `INACTIVE` | `302cace8c98d055cdb1ceca12bf6554f98f94b77363449da182d6f80714d5945` |

## Final gates

All hashes identify non-retained temporary evidence; no build or test output is
committed.

| Gate | Final result | Non-retained artifact SHA-256 |
|---|---|---|
| Focused Dart TC-371 bundle | exactly 11/11 PASS; zero skips | log `abb46aad05a6f2e77897f434d2f97b27873e684faf64417cdf8895844af571cd`; JSON `4cfb76e521f18a7733b49cf8ef87c10359a21c3fb5d58834bd963787edeee11d` |
| Account replacement/erase repair | exact AST/runtime 2/2 PASS; whole StartupRouter 26/26 PASS | green JSON `ad4002616f73fa60fd2c0371117a36fc1d2cc8bca685700b8457027c7f42bf61`; owner log `8e964016345c2d352604842bdccaa5513fafc68ab491f243127ab5ba1b422d50` |
| Exact preservation bundle | exactly 8/8 PASS; zero skips | log `435820990480a4018241a8814f796bbe61e4d9f2e65bf8c08db304f4edcbef9c`; JSON `87036b9c953c74c00176a196dce81f08bb218789ae1428270e5b63837f17b115` |
| Native registered host item | Android exact JVM 2/2 and flagged Kotlin compiles PASS; generic Runner/NSE builds and privacy source/bundle checks PASS; exact TC-371-06 XCTest 2/2 PASS, zero skips; fixture source/bundle byte-equal | JVM log `6da225d68b494586be481a232bd1d146552463fd7083ce4ddca34f3892bf08c4`; XCTest log `4b04534dd889735fa6829cd97fd899ca51ef732bb0d059de548bab049adf4690`; fixture `7a489b6f800bebacf299ebc05d7e2e334dcd78b511f19079798a545f34564174` |
| Former group fixture failures | all eight owners together 501/501 PASS | `a87f6e876979b90f247a27c9cb1d991976a8786981f8c1b2f9ad4187b000b820` |
| Curated `1to1` | 3,302 Flutter PASS; 10 declared skips; all relay/toolchain/ACK/media tails PASS | `8e514312e8ae15b3ccf498969163c3b784034b26d415f04dbbe8d5aea9d8dfd5` |
| Curated `groups` | 4,303 Flutter PASS; bridge/node/relay tails PASS | `151d355d37c9760bbf082db5873a20b34c5acde5fa1d34369bf96bd2d13bc200` |
| Android build-once artifact | disposable app/test APK pair validated for exact package/runner/one-process manifest | build log `6078da555639299d5e2241b1d76cc7c3c9ae0da14d70bc7d1d498cd698a3ab1a`; app APK `903899b0c30da85b20db9c1f69d20c89fc3b9452bdde97f4a7aa30a33426394e`; test APK `977279d2d302b48e8b8afc85973217bd53b1bbadc36b6fc880d248fedeb78495` |
| Android TC-371-08 | Pixel 6 `21071FDF600CSC` and emulator `emulator-5554` independently passed phase A, exact host force-stop, disk reopen, and phase B with zero skips | physical `7f8bca1ac67f8c41b8d810372c0556bafb0a6bf030b9c2249db8f28d69d2ef30`; emulator `bb59d43a0be1a08c368a22e57c49337fa66545c4a395c750951fe936d69c3d1f` |
| Registration/discovery | shared/group/native owners occur exactly once; host dry-runs and both reliability categories PASS | terminal attestation |
| Full analyzer | no issues in 93.9 s | `1f3ac44fc9d15d44512bf4b91eb916b2e3b63e3ba4c43686bff48113ccbfd204` |
| Format/diff/shell/plist/Swift hygiene | all changed Dart canonical; `git diff --check`, five shell parses, two privacy plists, and Swift parse PASS | terminal attestation |

The available-device inventory contained one USB Android, one Android emulator,
two USB iPhones, and available iPhone simulators. Plan 371 required no physical
iPhone. No per-plan `core-host-all`, `feature-host-all`, or full `host-all` was
run; this is the deliberate project cadence, with the N03-N06 aggregate retained
for Plan 372.

## Current-source audit

| Guard | Final value |
|---|---:|
| Base-to-frozen changed paths | 80 |
| Added / modified / deleted | 24 / 56 / 0 |
| Dart / Kotlin / Swift / shell paths | 56 / 7 / 4 / 5 |
| Android / iOS paths | 8 / 7 |
| Production bootstrap authority creations | 1 |
| Classified production `maybeShowNotification` calls | 10 |
| Direct/group/linked route bindings | 3 |
| DB migration paths | 0 |
| Native renderer/worker paths | 0 |
| Paired N03 environment seams | 1, `defaultValue: false` |

The group gate initially exposed 64 deterministic stale-fixture failures: 63
missing suppression readers plus one stale constructor contract, with no
resource, overload, process, or unrelated semantic failure. Test-only
`FixedAppVisibility`/`TrackerBackedAppVisibility` injection repaired those
fixtures while preserving the one intentional null-dependency cancellation
case; production did not gain a second or fallback suppression authority.

## Graph grounding

One incremental refresh followed the final account-boundary repair. The exact
review query was current and anchored at the same source.

| Graph fact | Final value |
|---|---|
| Freshness / confidence | `current` / `anchored` |
| Fingerprint | `a1554310fab6234f` |
| Nodes / edges | 76,525 / 112,334 |
| TDD overlay | 1,590 files / 15,693 named tests / 1,251 production targets |
| `graph.json` SHA-256 | `98caf3da4edc28c46417e00f06134fd1e901ded4605651348969cec7b7d0ab62` |
| `manifest.json` SHA-256 | `1188457672d61d8fc637804d79aba80d0f7e254ad105a9ae68e2e244f322d98a` |
| `tdd-overlay.json` SHA-256 | `2ae289eb03142f3a5eb677eb08eda98607b41d7a12da7c8f416f5ddfc13529a0` |
| Refresh log SHA-256 | `22a97df9951dfa57827a2cc45b45b7a8924cbd98d2456cfba4b833774794f0d6` |
| Review query SHA-256 | `69807d89b9b28240c6951292da731f2b627f1d78eff7ec6738e7e0a009c34dbe` |

Graphify confirmed the one authority, route registry, startup invalidation seam,
current presentation adopters, and expected reverse dependencies. The graph is
supporting evidence; executable gates remain authoritative.

## Frozen tested state

An alternate Git index captured the Plan-371 implementation without changing
the shared index. Four concurrently authored successor plan files (372–375) and
their index rows were deliberately excluded from the frozen tree and from the
Plan-371 commit. The raw workspace snapshot records that planning dirt rather
than hiding it.

| Identity | Value |
|---|---|
| Capture date | `2026-08-16` (Europe/Berlin) |
| Branch | `protected-view` |
| Base and unchanged `HEAD` | `9be694a19e4f17973e447f8b98c8167b9881fd74` |
| `HEAD` tree | `d31e890195b200444076cf14dfb664f54559cc06` |
| Frozen tested tree | `75116f8b1c7cc0cec99f2a72d1410713868d0f23` |
| Porcelain-v2 workspace snapshot SHA-256 | `7f85fe07bd306706895b2a11d5d27431b2bba2405379bfd925db851f94f4fa9b` |
| Porcelain-v2 records | 85 |
| Frozen name-status SHA-256 | `98faea552ffb4abeabad1d8f763874736ba68d4cd2dc041bbe316465b8edb4cd` |
| Shared-index entries / list SHA-256 | 6,414 / `843a7f4979ea51753c2a89c5756372b9d95fb11f8a39a25cfb2f23624ba22fd5` |
| Shared-index byte SHA-256 | `44993fee8ea88bdbf79e5f252c0d8e2738a4db205adf8a8edc1906be9b6b15ea` |
| Alternate-index entries / list SHA-256 | 6,438 / `1e41fccf68817519ce82a744caef3e06c4cb8cbf560ef7fbcb537593e89c8ff5` |
| Alternate-index byte SHA-256 | `440e8bc65120fc4b2cc64af56fd84ae04783dfc6192152732ffdf975668424c1` |

Machine-readable identities:

```text
Base HEAD: 9be694a19e4f17973e447f8b98c8167b9881fd74
Frozen tested tree: 75116f8b1c7cc0cec99f2a72d1410713868d0f23
Dirty snapshot SHA-256: 7f85fe07bd306706895b2a11d5d27431b2bba2405379bfd925db851f94f4fa9b
Graphify fingerprint: a1554310fab6234f
```

This README, its checksum, and the final Plan/status/index/coverage closure edits
necessarily postdate and are absent from the frozen tested tree. No production,
test, native, fixture, script, or Graphify blob changes in those closure edits.

## Handoff

Plan 372 may consume the checksum-bound v1 snapshot and authority evaluation,
but must add the immediate final-effect ledger/barrier without weakening strict
freshness or fail-notify behavior. Plans 373–375 retain native consumers and
headless/fixed-wake adoption. Keep the paired N03 admission default-off until
its downstream owners and rollout evidence explicitly authorize activation.

This receipt closes only the Plan-371 N04-owned foundation. It makes no native
rendering, live provider, device-universal, full GAP-N04, N03, PRD, deployment,
activation, or release claim.
