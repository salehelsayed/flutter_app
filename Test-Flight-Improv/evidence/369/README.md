# Plan 369 Final-Tree Durable Local Notification Outcome Foundation Receipt

Date: 2026-08-15 (Europe/Berlin)

This receipt records the final host-tested source and test tree for Plan 369.
It closes only the default-off, installation-local persistence and projection
foundation. It does not add or activate a relay outcome action, relay drainer,
native outcome writer, provider proof, deployment, live acceptance, full N03
acceptance, or release eligibility.

## Verdict

- `N03_DURABLE_LOCAL_OUTCOME_FOUNDATION_CODE_COMPLETE = true`
- `N03_COMPLETE = false`
- `N03_LIVE_ACCEPTANCE_PROVEN = false`
- Both production completed-outcome producer switches remain explicitly
  `false`.
- `osPosted` is the only production-eligible outcome in this slice.
  `inChat` and `suppressedPolicy` remain reserved for N04/N05/N11 owners.
- No production `wake_outcome_v1` action or capability exists in this tree.

The exact completion marker is:

```text
N03_DURABLE_LOCAL_OUTCOME_FOUNDATION_CODE_COMPLETE
```

## Dependency provenance

Plan 368 was checksum, marker, immutable-tree, and pinned-receipt validated
before Plan 369 execution and again at closure:

| Identity | Verified value |
|---|---|
| Receipt | `Test-Flight-Improv/evidence/368/README.md` |
| Receipt SHA-256 | `0d6747b448a97103b750eaa275a37ded1cceeff096582b0fb05b15d1357ca5f1` (`shasum -a 256 -c`: `README.md: OK`) |
| Frozen tested tree | `924e8f64ebc7c9dca2de83890ecad144fefbdaf2` (`git cat-file -e`: PASS) |
| Graphify fingerprint | `27ea9a664ebf98d9` |
| Marker | `N02_OPAQUE_WAKE_MECHANISM_CODE_COMPLETE` |

The Plan 369 base is the clean dependency-wave checkpoint
`8d86501e46f1a06e724daf8009cd3bf0f807578c`. It transitively retains the
checksum-bound Plan 367 and Plan 366/N01 foundations without requiring N01 or
N02 live activation.

## Implemented contract

- DB v116 adds exactly one installation-local
  `notification_completed_outcome_outbox` table. It has no historical
  backfill, accepts only lowercase 64-hex correlation keys and the three
  reserved categories, retains immutable completion/creation facts for seven
  days, uses revision-exact retry/delete operations, prunes expired rows, and
  enforces a hard 512-row capacity without evicting a live row.
- The shared correlation frame is byte-exact LP32BE domain, physical peer,
  producer-kind byte, and event-key framing followed by lowercase SHA-256.
  Four JSON vectors pin direct message, direct reaction, aliased group
  message, and authenticated group-reaction identities. Input is never
  trimmed, folded, bounded into a display identity, or replaced with a logical
  sibling-account identity.
- Typed presentation distinguishes `osPosted`, `inChat`,
  `suppressedPolicy`, terminal-without-outcome, and retryable contention.
  Successful native posting remains `osPosted` even if later recent-remote
  bookkeeping fails; callback-entered ambiguity remains retryable/no-outcome.
- Direct and group retry coordinators carry a typed outcome candidate through
  one required outcome-aware completion callback. Stale or missing canonical
  state routes through revision-exact retirement instead of silently dropping
  a candidate or retrying an impossible exact-one terminal write.
- Direct/group message and reaction completion reselects exact READY custody,
  optionally appends the immutable outcome, performs an exact-one canonical
  terminal write, and deletes custody in one exclusive SQLite transaction.
  A fault or zero-row mutation rolls the whole transaction back. A category
  replay preserves the first valid row; full live capacity completes safely
  without manufacturing an outcome.
- Outcome eligibility is reconstructed from current canonical state. Direct
  reactions use the raw reaction transition; group messages use the exact
  authenticated logical-delivery ID or exact authenticated legacy message ID;
  group reactions require the raw authenticated transition ID. Missing,
  synthetic, normalized, mismatched, deleted, hidden, consumed-private,
  history-repair, policy, delivery-ACK, and reconciliation authorities cannot
  mint an outcome.
- The physical installation resolver validates ordinary-primary peer/key
  derivation and active-linked transport credentials. It rejects missing,
  malformed, cross-account, key-mismatched, and transport-equal-to-account
  credentials, preventing sibling installations from sharing outcome
  authority.
- Account snapshot export deletes v116 rows only from the exported copy;
  schema inventory retains the empty table as installation-local; active
  import clears destination residue and never transfers source v116 rows.
  Source databases are never mutated.
- Production bootstrap exposes the canonical direct/group seams but passes
  both producer switches as `false`. The repository remains deliberately
  host-rooted until Plan 370 composes the single production drainer.

## TDD evidence

The first selected semantic RED was
`TC-369-01 v116 outcome outbox is additive bounded and empty`; it failed before
production migration/table code existed. The raw RED output was not retained,
so this is explicitly a non-retained attestation.

The final named proof contract was:

| Proof | Final result | Non-retained temporary artifact SHA-256 |
|---|---|---|
| Focused TC-369 discovery/execution | Exactly 9 owners; 9 PASS; 0 SKIP; 0 error events | log `29b8bfbc687bef229b9bd055e0c247a183f6b2a8ab8c1b2c3ac93a46409d58c8`; JSON `d88b8977cd0d89abf2f0f908f74e1ce337e0efc8dc554ce9c1126272400c39fa` |
| Exact preservation bundle | Exactly 5 owners; 5 PASS; 0 SKIP; 0 error events | log `5af37b2c6ad702ec50d460a5fd6189fa44d4e5d6a7d81d38fdc48fc49610300d`; JSON `02fb4e6e5e0c31837accc583462c129f565f03f070e587c6eab4336854b60701` |
| Exact account-transfer policy | Exactly 3 owners; 3 PASS; 0 SKIP; 0 error events | log `220a8987ef99123a89e7f3e2328962b141f9d37b95611dba99beba63a3ab7fa4`; JSON `d9ec01e40356ec3ef550a0c271accbba4ceb1f77495f3b935d71f63a6dcfe680` |

### Serial semantic mutations

Each mutation was applied alone, required its named causal owner to fail,
reverted without retaining unrelated changes, and followed by GREEN. Raw
mutation logs were not retained; no synthetic hashes are claimed.

| Mutation | Required RED observed |
|---|---|
| Move outcome insertion outside the direct display-completion transaction | Direct `TC-369-02` rejected the split commit |
| Treat a zero-row group canonical terminal update as success | Group `TC-369-02` retained custody and rejected the false outcome |
| Promote recent-remote terminal suppression to `osPosted` | `TC-369-03` rejected the false completed effect |
| Remove physical-peer/producer-kind correlation framing | `TC-369-04` rejected the collision-prone digest |

No `PLAN369 MUTATION` marker remains in final source.

## Final gates

All temporary log hashes below are non-retained attestations; the files lived
under `/tmp/plan369-gates-final.qr86WM` during execution and are not part of
this repository receipt.

| Gate | Final result |
|---|---|
| Plan 368 prerequisite | sibling checksum PASS; exact marker PASS; pinned SHA PASS; frozen tree object PASS |
| Focused TC-369 bundle | exactly 9/9 PASS; 0 SKIP; log SHA-256 `29b8bfbc687bef229b9bd055e0c247a183f6b2a8ab8c1b2c3ac93a46409d58c8` |
| Five preservation sentinels | 5/5 PASS; 0 SKIP; log SHA-256 `5af37b2c6ad702ec50d460a5fd6189fa44d4e5d6a7d81d38fdc48fc49610300d` |
| Curated `1to1` | Flutter `+3261 ~10: All tests passed!`; all relay/toolchain tails PASS; log SHA-256 `77a423c630a250540937c929e4969fc3a5083a85057950e6186de3a7cbce576a` |
| Curated `groups` | Flutter `+4201: All tests passed!`; Go bridge/node/relay tails PASS; log SHA-256 `c2c638d2aa865064414385bde80b0f7acb98393efde699906db83eb2163a66ae` |
| Exact account-transfer tests | exactly 3/3 PASS; 0 SKIP; log SHA-256 `220a8987ef99123a89e7f3e2328962b141f9d37b95611dba99beba63a3ab7fa4` |
| Dart-only `core-host-all` | 412/412 paths; 3,324 PASS; 0 SKIP; 0 failed rows; log SHA-256 `3edfa495089edba216cfecf6ec223690b8589067e64b88f4efdb3021433be547` |
| Changed-Dart format check | 68 files; all canonical; file-list SHA-256 `15dd9df10adb66df25e503e20b4686616ffeead69a57aad4e640ef5b56f53b89` |
| `flutter analyze` | exit 0; `No issues found!` (non-retained terminal attestation) |
| `git diff --check` | exit 0; no output |

The first groups diagnostic found two stale preservation assertions. Their
exact owners passed after recording raw reaction identity and the new
default-off constructor seams; the authoritative full rerun above supersedes
that diagnostic. The first core diagnostic found only two composition digest
assertions and one runtime-root declaration; exact owners and the full
412-path rerun above passed after those hygiene records were corrected.

A provisional analyzer wrapper returned before its child output was complete.
The completed analyzer correctly exposed one missing `completedAt` argument in
an unrun group SQLCipher proof. That exact compile fanout and all stale
current-schema SQLCipher assertions were repaired to v116. A subsequent full
analyzer produced `No issues found!`. Project policy requires no Plan 369 phone
leg, so no unavailable device is treated as a gap. The provisional graph
refresh/tree capture are excluded; the settled refresh and tree below are the
only authoritative closure identities.

No feature/full-host sweep or device test was run for this per-plan slice.

## Current-source audit

| Guard | Final value |
|---|---:|
| `currentIdentityDatabaseVersion` | 116 |
| Production files containing `wake_outcome_v1` | 0 |
| Production `completedOutcomeProducerEnabled: true` sites | 0 |
| Production explicit `completedOutcomeProducerEnabled: false` sites | 2 |
| v116 production registry import/create/upgrade references | 3 |
| New tables introduced by Plan 369 | 1 |
| Tracked modified app-owned production files | 21 |
| New app-owned production files | 5 |
| Tracked modified test/integration files | 39 |
| New test/fixture files | 4 |

The source audit also found no remaining mutation marker and no stale exact
`currentIdentityDatabaseVersion` assertion below v116. Historical explicit
version create/upgrade/downgrade assertions remain deliberately unchanged.

## Graph grounding

The final settled-tree incremental refresh ran after every product, test,
runtime-root, and SQLCipher hygiene repair. A refined exact-anchor review query
was current and anchored.

| Graph fact | Final value |
|---|---|
| Freshness / confidence | `current` / `anchored` |
| Fingerprint | `ec9a45bfd76c0f40` |
| Nodes / edges | 75,796 / 110,752 |
| TDD overlay | 1,578 files / 15,669 named tests / 1,246 production targets |
| `graphify-arch/graphify-out/graph.json` SHA-256 | `ff02eb98f2f280f20aa3bfc299e0d876ad1d6237d5dc70308182190a601f51e8` |
| `graphify-arch/graphify-out/manifest.json` SHA-256 | `97515533762131c339e8b44c7dd72b988f799b1111775ba2c96c6731999df4f7` |
| `graphify-arch/tdd-overlay.json` SHA-256 | `3792fb69025fe3aa209ab93757b4a5a4fc62f3cb2940dead5abaed1de9b7828b` |
| Settled refresh log SHA-256 | `29c12e0fa4fc644af36a359253f52c05e4ad4c661c1761ec0fd8935d6e9413ee` (non-retained) |
| Refined review-query log SHA-256 | `8dbdddf4172ea226de6d45bdc7800eaa75d5f49e53236dc51df1910af45ac8c3` (non-retained) |

The graph surfaced the intended v116 repository, exact direct/group completion
helpers, and physical-installation selector. Its reverse-dependency shortlist
is covered by the focused, preservation, curated, account, and core gates
above.

## Frozen tested state

An alternate Git index captured every tracked file plus every untracked,
nonignored file without changing the shared index.

| Identity | Value |
|---|---|
| Capture time | `2026-08-15T18:31:56+0200` |
| Branch | `protected-view` |
| Base and unchanged `HEAD` | `8d86501e46f1a06e724daf8009cd3bf0f807578c` |
| `HEAD` tree | `c4de6777af17f13822fa17a11014b2f165105053` |
| Frozen tested tree | `61e1b1935a022e7ad0f54d207549903a728e9b86` |
| Porcelain-v2 workspace snapshot SHA-256 | `ff0c29a6e3ea5ed013aeb147b589c34de74b9131fce0d700e8c1f4d4b360f96b` |
| Porcelain-v2 records | 74 |
| Shared-index entries SHA-256 | `92180a075cb10e0a7a4ccd4f8fae66d9cf9b162a186e755f2383f383794f879d` |
| Shared-index entries | 6,392 |
| Shared-index byte SHA-256 | `ec58af3878f18f9f6362c477a9556e90fff3c41e57001ba031a7721ed99c1f4a` |
| Alternate-index entries SHA-256 | `08aa362cdea1b45735a1603aa92ff3069e122c05e4078c7fa37ebada1b968a73` |
| Alternate-index entries | 6,401 |
| Alternate-index byte SHA-256 | `b9ebbf615acb59695d58ad85014dafcb523ed3cd88b06d19f7cbe78f6807b33e` |

The machine-readable identities are:

```text
Base HEAD: 8d86501e46f1a06e724daf8009cd3bf0f807578c
Frozen tested tree: 61e1b1935a022e7ad0f54d207549903a728e9b86
Dirty snapshot SHA-256: ff0c29a6e3ea5ed013aeb147b589c34de74b9131fce0d700e8c1f4d4b360f96b
Graphify fingerprint: ec9a45bfd76c0f40
```

This README, its sibling checksum, the final Plan 369 checklist/progress edits,
and the status/index/coverage/Plan-370 prerequisite handoff necessarily
postdate and are absent from the self-describing frozen tested tree. No
product, test, script, runtime-root, or Graphify blob may change between this
freeze and the Plan 369 commit.

## Handoff

Plan 370 must validate this README's sibling checksum, exact marker, base HEAD,
frozen tree, dirty snapshot, and Graphify fingerprint together with the Plan
368 receipt. It then owns the only authenticated relay outcome action, durable
wake-obligation state/coordinator, strict all-relay drain, and combined
default-off capability seam.

This receipt authorizes none of those actions by itself. Native final-effect
ownership, `inChat`/policy production, capability activation, live provider or
device evidence, full N03/PRD acceptance, deployment, and release remain open.
