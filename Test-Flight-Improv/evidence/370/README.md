# Plan 370 Final-Tree Authenticated Bounded Wake Outcome Coordinator Receipt

Date: 2026-08-15 (Europe/Berlin)

This receipt records the final host-tested source and test tree for Plan 370,
N03 slice 2 of 2. It closes the default-off N03-owned wake-outcome coordinator
foundation over Plans 368 and 369. It does not establish full N03, live, PRD,
deployment, activation, provider, device, or release acceptance.

## Verdict

- `N03_WAKE_OUTCOME_COORDINATOR_FOUNDATION_CODE_COMPLETE = true`
- `N03_COMPLETE = false`
- `N03_LIVE_ACCEPTANCE_PROVEN = false`
- One paired Dart admission seam gates both advertised relay capabilities, both
  completed-outcome producers, and the production drainer. Its production
  default is `false`.
- Redis is the only durable wake-obligation owner. The memory backend preserves
  incumbent immediate delivery and is a terminal non-owner for outcome action
  handling.
- Provider submission is honestly at-least-once under Plan 368's fixed collapse
  identity; this receipt makes no exact-once claim.

The exact completion marker is:

```text
N03_WAKE_OUTCOME_COORDINATOR_FOUNDATION_CODE_COMPLETE
```

The two N03-owned default-off mechanism slices are now code-complete. No third
N03 slice is warranted. Shared lifecycle, native final-effect, read/policy,
rollout, and release work remains with N04-N08/N11 and WP-07.

## Dependency provenance

Plans 369 and 368 were checksum- and marker-validated before Plan 370 execution:

| Dependency | Verified value |
|---|---|
| Plan 369 receipt | `Test-Flight-Improv/evidence/369/README.md` |
| Plan 369 receipt SHA-256 | `8d4229405b1b39ac26dd2304fa77455322be8b25c1b1f573a4903f0044d4873c` (`shasum -a 256 -c`: PASS) |
| Plan 369 frozen tested tree | `61e1b1935a022e7ad0f54d207549903a728e9b86` |
| Plan 369 Graphify fingerprint | `ec9a45bfd76c0f40` |
| Plan 369 marker | `N03_DURABLE_LOCAL_OUTCOME_FOUNDATION_CODE_COMPLETE` |
| Plan 368 receipt | `Test-Flight-Improv/evidence/368/README.md` |
| Plan 368 receipt SHA-256 | `0d6747b448a97103b750eaa275a37ded1cceeff096582b0fb05b15d1357ca5f1` (`shasum -a 256 -c`: PASS) |
| Plan 368 marker | `N02_OPAQUE_WAKE_MECHANISM_CODE_COMPLETE` |

Plan 368 transitively binds the opaque route/fixed provider boundary and Plan
369 binds DB-v116 local completed-outcome authority. Plan 370 extends those
owners without adding a third payload queue, provider service, scheduler,
Flutter migration, or native writer.

## Implemented contract

### Admission, storage, and fallback

- Delay is admitted only for an incumbent-authorized producer with stable
  Plan-369 correlation, a current encrypted route advertising both
  `opaque_wake_v1` and `wake_outcome_v1`, any required reaction capability,
  and Redis transaction support.
- Route handle, generation, canonical capability set, and directory source
  digest are validated at the event/obligation commit boundary. A changed
  preflight cannot leave a delayed obligation or cause a pre-persistence
  provider call.
- Direct, protected-direct, group, direct-reaction, and group-reaction owners
  converge on one Redis wake-state family and one due index. Event and pending
  obligation commit atomically; duplicates do not refanout or duplicate state.
- Delivery or custody ACK never removes wake state. An authenticated outcome
  that arrives before event storage creates a bounded completed tombstone, and
  the later event transaction consumes that authority without creating a wake
  obligation.
- Live records are bounded per authenticated recipient. Admission-cap overflow
  preserves the event and runs the incumbent immediate fixed wake. If an absent
  outcome tombstone cannot be retained, the result is retryable so DB-v116
  authority remains available; an unexpired record is never silently evicted.
- Redis composes the durable owner and coordinator. The memory backend remains
  immediate and does not pretend to own delayed recovery.

### Coordinator and provider boundary

- Pending, claimed, and completed states use revision/claim CAS, one fixed
  500 ms debounce, bounded retry/backoff/expiry, and a claim lease strictly
  beyond the provider timeout plus retry budget.
- The incumbent Plan-368 gateway returns only `accepted`, `permanent`, or
  `retryable`. Immediate callers retain their existing behavior; the coordinator
  alone consumes the typed result.
- Accepted delivery settles the obligation. A permanent provider rejection is
  terminal only when exact-generation revoke/CAS confirms the rejected route
  was still current. Revoke loss/error, token rotation, stale or ineligible
  route, provider unavailability, and deadline expiry requeue safely.
- Redis permits one live claim owner, not exactly-once provider submission. A
  crash after provider acceptance but before Redis completion can resubmit the
  same collapsed fixed wake. Recovery is therefore at-least-once by design.
- Expired and stale due entries cannot head-of-line block valid due work; a
  blocked provider call times out before another live claimant is admitted.

### Authenticated action and strict local drain

- The only action is strict JSON for authenticated `remotePeer`:
  `{"action":"wake_outcome_v1","correlation":"<64 lowercase hex>","wakeNotRequired":true}`.
  Missing/false booleans, uppercase/noncanonical correlation, duplicate or
  unknown keys, peer fields, malformed scalars, and boundary bytes are refused.
- State is namespaced exclusively by the authenticated peer. The wire body
  carries no sender, recipient, event kind, group, conversation, platform,
  provider, token, route, or private UI reason.
- Go and Dart share Plan 369's exact correlation vectors. Node fanout returns a
  result for every distinct configured relay instead of reusing any-success
  semantics. Exact old-relay unknown-action is terminal unsupported; partial,
  malformed, and network failures retain DB-v116 authority for retry.
- One bridge action and one in-flight-coalesced Dart drainer are shared by
  post-commit, startup/reopen, online/reconnect, network-restored, periodic, and
  `handleAppResumed` triggers. No second service, worker, or timer was added.
- The sole production seam is
  `kWakeOutcomeCoordinatorAdmissionEnabled`, backed by
  `MKNOON_ENABLE_WAKE_OUTCOME_COORDINATOR` with `defaultValue: false`. The same
  value gates both capability advertisements, both completed-outcome producers,
  and the one production drainer composition.

## TDD chronology

The historical first discovery-guarded semantic RED was not captured: the
initial tests and implementation landed concurrently. This receipt does not
rewrite that chronology or claim a raw first RED that did not occur.

Subsequent focused proof work did produce genuine causal REDs before their
repairs: wrong due-type partial-event acceptance, duplicated preflight
lookup/provider work, missing source-digest route CAS, stale-due head-of-line
blocking, malformed scalar delay admission, retryable memory ownership, a
boundary `FEFF` grammar case, and protected near-expiry suppression. Those raw
temporary logs were not retained; the final owner runs below supersede them.

### Serial semantic mutations

Each required mutation was applied alone, made the exact owner RED, was
reverted, and was followed by GREEN. All hashes identify non-retained `/tmp`
logs.

| Mutation | Causal owner and observed RED | Non-retained RED log SHA-256 |
|---|---|---|
| Accept outcome-only capability | TC-370-01 rejected delay without the paired opaque capability | `eb98f03165ebdb839a574db2c4b52a2ea5e6e44307868693a3db7766fc89ebd1` |
| Split event and obligation transaction | TC-370-02 rejected the partial atomic commit | `c9eb7773c37c117a059ab593e32aa6a58fae96bf13bac412b22787d3df9fb7ae` |
| Discard an absent-outcome tombstone | TC-370-02 rejected loss of the outcome-before-store race | `cbfce306d9bef9398a946121f8a510c7ad15b5cf2ef634ce14c3cc4aa1188f87` |
| Terminalize revoke-CAS loss | TC-370-04 rejected settlement after route-generation ownership was lost | `0cb3ec3909034e579375275bcdd5a2358ff0bcfe234b79e39ebece41af49eb91` |
| Reuse any-success node fanout | The node owner rejected DB-v116 retirement with a retryable participant | `b94205eb0403a1ed921e21e231d175127070ab3427c34441b20e224de5605ace` |

## Final gates

Every hash below is an attestation for a non-retained temporary artifact; no
execution log is presented as a repository-retained file.

| Gate | Final result | Non-retained artifact SHA-256 |
|---|---|---|
| Focused Dart TC-370-05/07 | exactly 5/5 PASS; 0 SKIP; no error events | log `24ea6ae2fb9f9f4fa74f11d76fd4a1992584657650952111f80fe79de5bd8747`; JSON `ec0752933481d4a7e5a42642d764ef08b334cc04d56f5ad7960bdecfe90820b2` |
| Focused relay TC-370-01..05 | exactly 5/5 PASS; 0 SKIP | `bd62defc668ece14fff8ee7c76ddc2a1a030b85a20e7d83b9e1ca8e9507b5160` |
| Race TC-370-04 | exactly 1 PASS; 0 SKIP; macOS linker warning only | `a05c0409e6a86a1f6585304665fbb569b95c08877932bc11161c1308ddb0910d` |
| Exact node owner | exactly 1 selected / 1 PASS | `10c599cf8791c9f46bcd1c212d4a16347608ace13cdeb8329e0ee0e9892a11b3` |
| Exact bridge owner | exactly 1 selected / 1 PASS | `ad18971f4b53d16a159c62d6d366c1df96e61ab76d48da21a88f74d901ca2f3a` |
| Tagged process handoff | PASS; pending-before-due and death-after-claim-before-provider-call both exercised | `64a50efc2ae55b460b90734d6fad30b77591f970f2e785877e3b43d44924981a` |
| Exact preservation bundle | exactly 12/12 PASS; 0 SKIP | `f44344a0509c71a9b26bb31d13553d1ab786c2e0270e46df2349a3cad1f23669` |
| Curated `groups` | 4,262 Dart tests PASS; registered bridge/node/relay tails PASS | `4c4beeaba76e64754b62ff1b6b6a86eca3cd43e45fef945de96bc0f1004a2694` |
| Relay family | all 309 script-owned tests PASS | `0dfea2e943e5c347e5dcb6c9dc481ce475806ee213cccf22356c4e4d03462c9e` |
| Host batch contract | PASS | `02bd1fce20bfdc96f6eb19133b590015169d7e0dc978db1a1555ae897be0bf50` |
| Shell syntax, Go vet, and Go format | PASS / no output | covered by terminal attestation |
| Changed-Dart format | 14 files; all canonical; list SHA-256 `8673faf813846ba76c954325cf5f49261f4a87c215f898fc96b1ab98fdd064d1` | non-retained terminal attestation |
| Full `flutter analyze` | exit 0; no issues | `9c0e913ec174857e18978c15ecd1714c7a25bf464859461e63036cd9b1eaa89e` |
| `git diff --check` | exit 0; no output | non-retained terminal attestation |

No phone, live provider, live Redis, `core-host-all`, `feature-host-all`, or full
`host-all` gate was run. That is the deliberate per-plan cadence, not a hidden
green claim. Full `host-all` remains due once after the N03-N06 dependency wave
and again at rollout/release closure.

## Current-source audit

| Guard | Final value |
|---|---:|
| Base-to-frozen changed paths | 36 |
| Added / modified paths | 8 / 28 |
| Graphify files within that surface | 2 |
| Changed scripts / runtime-root files | 3 / 1 |
| Production drainer compositions | 1 |
| Production producer uses of the paired admission flag | 2 |
| Paired capability constants | `opaque_wake_v1` and `wake_outcome_v1` |
| Production `bool.fromEnvironment` seams for the coordinator | 1, default `false` |
| Platform-native handlers for `inbox:wake_outcome` | 0 |

The Redis bootstrap is the durable owner. The memory backend remains immediate
and terminally non-owning. No native handler, live provider call campaign, live
Redis deployment, phone proof, activation, or release change is part of this
closure.

## Graph grounding

The settled incremental refresh followed all app-owned source, test, script,
and runtime-root repairs. The refined exact-anchor review query was current and
anchored at the same frozen source.

| Graph fact | Final value |
|---|---|
| Freshness / confidence | `current` / `anchored` |
| Fingerprint | `1cd2db6f3341312b` |
| Nodes / edges | 76,031 / 111,542 |
| TDD overlay | 1,584 files / 15,682 named tests / 1,247 production targets |
| `graphify-arch/graphify-out/graph.json` SHA-256 | `089a22389d4643a72340c7f7d7f1573f3453781a4c32527067e033368fbf504b` |
| `graphify-arch/graphify-out/manifest.json` SHA-256 | `6c41f13df6e1211c1b41c0eef58876471b0075475fada41f500b52e7a2da435a` |
| `graphify-arch/tdd-overlay.json` SHA-256 | `f04cf958c2d3a8ab265588c33e8957a7641eed49128ee1aa3987cae1f1c614de` |
| Settled refresh log SHA-256 | `12755d0129f418c5045edf5de8e0737d12b2ee4909a27c887b5f2ba4d729dfa9` (non-retained) |
| Refined review-query log SHA-256 | `4bdc188ad65e926dfa216a9eea0b0a309a7a48026858541e4b3677332ddba680` (non-retained) |

Graphify surfaced the Redis state/coordinator, the exact relay/process owners,
the strict node/bridge boundary, the Dart drainer, and production bootstrap as
the expected reverse-dependency surface. Graph evidence supplements but does
not replace the executed gates above.

## Frozen tested state

An alternate Git index captured every tracked file plus every untracked,
nonignored file without changing the shared index.

| Identity | Value |
|---|---|
| Capture time | `2026-08-15T21:03:34+0200` |
| Branch | `protected-view` |
| Base and unchanged `HEAD` | `ddf4b1459187b074128213e72b8456bd44e39cef` |
| `HEAD` tree | `e24ba92b8c6d65ec24cb40d7ee2b4297075c02f1` |
| Frozen tested tree | `79664ab276372316833a03de0c90c3423c6129f4` |
| Porcelain-v2 workspace snapshot SHA-256 | `26f862323fe4242296c9a626ab5e3b23e5c1d6911ebdf5a9e66f6bbfe2b756ed` |
| Porcelain-v2 records | 36 |
| Shared-index entries SHA-256 | `7b45a4b9d58e786792ca7330848e1964c91383d9aa259f00ee6eca44af34617d` |
| Shared-index entries | 6,403 |
| Shared-index byte SHA-256 | `c4dcc216bb2caa20e9da50a320dcada7fcd79dee1a5163a4d8fba1971ec6767a` |
| Alternate-index entries SHA-256 | `19e1409ce36c248f3624745f17ce61b9d706423bd1e120ec31a332e9c4222a07` |
| Alternate-index entries | 6,411 |
| Alternate-index byte SHA-256 | `68fc6f9427a22c3b86b09668bc41cb4af0dcfbb40b870f4f9460ea6a5a6866c8` |

The machine-readable identities are:

```text
Base HEAD: ddf4b1459187b074128213e72b8456bd44e39cef
Frozen tested tree: 79664ab276372316833a03de0c90c3423c6129f4
Dirty snapshot SHA-256: 26f862323fe4242296c9a626ab5e3b23e5c1d6911ebdf5a9e66f6bbfe2b756ed
Graphify fingerprint: 1cd2db6f3341312b
```

This README, its sibling checksum, and the final Plan 370/status/index/coverage
closure edits necessarily postdate and are absent from the self-describing
frozen tested tree. No product, test, script, runtime-root, or Graphify blob is
changed by those closure edits.

## Handoff

Preserve the paired admission default at `false` until the downstream
lifecycle/native/final-effect owners and WP-07 explicitly authorize and prove a
rollout. Native Android/iOS handling, live provider and Redis operations,
device evidence, dependency-wave full-host proof, A-control acceptance,
deployment, activation, and release eligibility remain open.

This receipt closes only the host-verified N03-owned coordinator foundation. It
does not authorize a third N03 slice or upgrade `N03_COMPLETE`.
