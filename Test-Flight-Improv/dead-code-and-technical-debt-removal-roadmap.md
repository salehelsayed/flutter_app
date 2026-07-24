# Dead Code and Technical Debt Removal — Master Roadmap

Status: umbrella roadmap — proposed, not yet executing.

Snapshot date: 2026-07-24.

This document is the sequencing, dependency, decision, and wave-gate ledger for
the dead-code and technical-debt program. It is deliberately not an
implementation plan. Every behavior-changing or non-trivial removal gets its
own source-verified TDD plan and links back here.

The `DTR-*` identifiers below are stable roadmap identifiers, not allocated TDD
plan numbers.

---

## Objective

Remove code proven to be unreachable, retired, or duplicated while preserving
every supported application, background, native, migration, protocol, test,
and release workflow.

The program is successful when:

1. every candidate has a terminal disposition: removed, wired, retained with an
   owner and reason, or explicitly deferred;
2. deletion candidates are proven against all runtime roots, not only Dart
   imports;
3. every implementation slice passes focused proof and its affected curated and
   family gates;
4. full `host-all` passes once after each dependency wave and once again at
   final rollout closure; and
5. the repository prevents newly unclassified production-unreachable files and
   unjustified production `unused_*` suppressions.

## What this roadmap owns

- The candidate and disposition registry.
- Dependencies and safe execution order.
- Product, compatibility, and ownership decisions.
- Per-plan proof-family expectations.
- Wave-level and final `host-all` evidence.
- Aggregate removal, retention, and wiring outcomes.

Individual TDD plans own mutation targets, causal tests, preservation
sentinels, implementation steps, exact rollback instructions, and their
per-plan gate commands.

## Safety invariants

- A missing Dart importer is a shortlist signal, not sufficient deletion proof.
- Absence of an owner never constitutes deletion proof. Unresolved ownership or
  uncertainty defaults to retained or deferred.
- Backends do not become dead merely because their current UI is unreachable.
- Deletion and behavior refactoring are not combined in the same plan.
- Existing public facades remain stable while large implementations are split.
- Historical migrations, persisted identifiers, wire values, and crypto
  compatibility paths remain until an explicit supported-version floor makes
  removal safe.
- Full `host-all` is not a per-plan gate.
- Device proof uses only targets available at execution time. Resolve the live
  matrix with `flutter devices --machine`, `adb devices`, and
  `xcrun simctl list devices available`, then pin every command to an explicit
  discovered target ID.
- Generic two-peer proof defaults to one connected physical Android device plus
  one available Android emulator. iOS is used only for an iOS-specific boundary
  or an explicit parity claim. An unavailable model, API, or OS-version leg is
  recorded as `N/A (target unavailable by project policy)`, never as a blocker
  or failed gate.

## Restricted runtime roots

The following are retained by default. A general runtime root requires a
dedicated plan proving the whole owning capability is retired. Migrations,
persisted values, crypto formats, and wire protocols additionally require an
explicit compatibility/version floor, named-owner approval, upgrade/protocol
proof, and a rollback plan:

- Dart entrypoints and `@pragma('vm:entry-point')` callbacks, including the FCM
  background handler.
- `lib/smoke_test_main.dart`, `lib/smoke_test_messages.dart`, and
  `lib/smoke_test_restore.dart`, which are explicit manual `flutter run -t`
  targets.
- Android manifest classes, services, providers, reflected names, Gradle
  variants, and generated plugin registration.
- iOS/macOS plist principal classes, AppDelegate callbacks, extensions,
  selectors, entitlements, and app-group identifiers.
- Windows, Linux, and web entrypoints and every generated registrant.
- Method-channel names, Go exports, wire strings, notification route values,
  persisted enums, and storage keys.
- Deep-link and URL schemes, platform-view IDs, notification categories,
  JNI/Objective-C selectors, FFI exports, and reflection/string registries.
- Ordered database migrations and upgrade compatibility behavior.
- Assets, fonts, shaders, asset catalogs, fixtures, goldens, and resources
  owned through pubspec, Xcode, Gradle, or platform manifests.
- Generated localization/plugin output, CI hooks, test configuration, native
  test modules, convention-discovered tests, shell entrypoints, and manually
  invoked tooling.
- `lib/core/debug/smoke_test_runner.dart` until its workflow ownership is
  explicitly resolved.

`packages/background_push_crypto` is a known graph-blind runtime boundary. Its
generated/headless registration must not be classified from normal Dart
reachability, and its existing native plugin unit-test task must be registered
before a plan changes that boundary.

---

## Grounding snapshot

The initial audit found 1,056 app-owned Dart files under `lib/`:

| Classification | Files | Meaning |
|---|---:|---|
| Reachable from `lib/main.dart` | 986 | Dart import closure only; not runtime-root proof |
| Manual entrypoint only | 3 | Intentional smoke roots |
| Test/integration-test only | 60 | Review or disposition required |
| No Dart importer | 7 | High-value shortlist; still verify external roots |

The architecture graph was marked stale for one unrelated conversation media
file during the audit. Graph results were therefore used as a shortlist and
load-bearing findings were checked in current source. Every TDD plan must
re-verify its own anchors before implementation.

### Confirmed debt groups

| Group | Audit size | Initial disposition |
|---|---:|---|
| Apparent Dart-import orphans | 6 files / about 564 LOC | High-confidence shortlist; deletion still requires DTR-01 proof |
| Superseded test-only files | 5 files / about 417 LOC | Remove with obsolete SUT-only tests |
| Retired Posts UI island | 24 files / about 6,993 LOC | Retire only after behavior/test migration decision |
| Retired Group-list UI island | 3 files / about 2,035 LOC | Retire after current-navigation proof |
| Account-migration test island | 11 files / about 3,353 LOC | Wire or retire; ownership decision required |
| Other legacy/test-only group code | 6 files / about 1,185 LOC | Split explicit legacy removal from integrate/delete decisions |
| Remaining test-only leaves | 11 files / about 1,065 LOC | Map replacements before disposition |
| `lib/core/debug` | 31 files / about 10,219 LOC | Preserve proof capability; move behind E2E composition root |
| `lib/smoke_test_*` | about 677 LOC | Preserve explicit entrypoints |
| Five largest architecture hotspots | 34,617 LOC | Refactor behind stable facades; never bulk-delete |

The five hotspots are `lib/main.dart`,
`lib/features/groups/presentation/screens/group_conversation_wired.dart`,
`lib/features/conversation/presentation/screens/conversation_wired.dart`,
`lib/features/groups/application/group_message_listener.dart`, and
`lib/core/services/p2p_service_impl.dart`.

Other measured debt includes 175 resolved `core -> feature` imports, 24
concrete `*_repository_impl.dart` files under feature domain folders, a stale
1,609-finding analyzer baseline despite a currently clean analyzer, and an
outdated dependency inventory that must be refreshed before upgrade planning.

---

## Status vocabulary

| State | Meaning |
|---|---|
| Candidate | Audited and recorded; no execution-ready TDD plan yet |
| Decision blocked | Product, compatibility, security, or ownership decision is missing |
| Planned | Source-verified TDD plan exists and is linked |
| In progress | Implementation has started |
| Plan-green | Focused, preservation, curated, and affected family gates passed; awaiting wave closure |
| Wave-accepted | The wave-level full gate passed and evidence is linked |
| Retained | Kept intentionally with owner, reason, and removal condition |
| Deferred | Explicitly out of the current rollout with a revisit condition |
| Dropped | Refuted as debt or superseded by another slice |

No plan is promoted directly from `In progress` to `Wave-accepted`.

---

## Dependency map

```text
SEC-00 reversible guard work and runbook preparation may begin in parallel;
all credential, artifact, history, force-push, and clone actions remain
authorization-gated

DTR-01 advisory runtime-root classifier ─┬─> DTR-03 core leaves
                                        ├─> DTR-04 feature leaves
                                        └─> DTR-08 compatibility ledger

DTR-02 strict analyzer/suppression rail ───> DTR-03 / DTR-04
DTR-08 + transport/protocol decision ─────> DTR-05 relay-probe branch

DTR-04 + product decision ────────────────> DTR-06 Posts UI
DTR-04 + product decision/navigation proof ─> DTR-07 Group-list UI

DTR-08 + owner decision ─┬─> DTR-09 account migration
                         ├─> DTR-10 legacy group operations
                         └─> DTR-11 remaining test-only leaves

DTR-12 architecture boundary guard ─┬─> DTR-13 E2E/debug composition
                                    └─> DTR-15 conversation controllers

DTR-13 ─> DTR-14 main bootstrap extraction ─> DTR-17 P2P service split
DTR-15 ─> DTR-16 GroupMessageListener split
DTR-14 / DTR-16 / DTR-17 ────────────────> DTR-18 layering relocation

DEP-01 dependency upgrades run as separate platform-specific child waves;
they must not share a batch with DTR-14 through DTR-18.
```

---

## Plan registry

| ID | Priority | Slice | Depends on | Per-plan proof floor | State / plan link |
|---|---:|---|---|---|---|
| SEC-00 | P0 | Rotate exposed signing material, remove binary signing artifacts from HEAD/history, add ignore/CI guards | Reversible preparation is independent; destructive actions require explicit authorization | Security runbook evidence; repository guard tests where added | Decision blocked — coordinated destructive history rewrite required |
| DTR-01 | P1/P4 | Advisory runtime-root inventory, allowlist, and CI reachability classifier; it never deletes or promotes candidates automatically | None | Exact tool tests; callback/native/generated fixtures; affected family gate | Planned — [Plan 272](272-runtime-root-inventory-advisory-reachability-guard-tdd-plan.md) |
| DTR-02 | P4 | Retire stale analyzer baseline and enforce a production suppression ratchet | None | Analyzer-tool tests; strict `flutter analyze`; `git diff --check` | Planned — [Plan 273](273-analyzer-baseline-retirement-production-suppression-ratchet-tdd-plan.md) |
| DTR-03 | P1 | Remove high-confidence dead core APIs/models | DTR-01, DTR-02 | Focused import/API tests; `core-host-all` | Candidate |
| DTR-04 | P1 | Remove high-confidence dead feature/UI leaves and obsolete SUT-only tests | DTR-01, DTR-02 | Replacement-preservation tests; affected curated gates; `feature-host-all` | Candidate |
| DTR-05 | P1 | Remove the suppressed unused 1:1 relay-probe branch | DTR-01, DTR-08; transport/protocol owner decision | Causal 1:1 preservation tests; `1to1`; `transport`; `feature-host-all`; availability-bounded two-peer proof; conditional Go/native proof | Decision blocked |
| DTR-06 | P2 | Retire or restore the Posts UI island while retaining live post backends | DTR-04; product decision | `posts`; `feed`; `feature-host-all`; navigation preservation | Decision blocked |
| DTR-07 | P2 | Retire the Group-list UI island after moving valuable coverage to Feed/Orbit | DTR-04; product decision; current-navigation proof | `groups`; `feed`; `feature-host-all` | Decision blocked |
| DTR-08 | P3 | Compatibility ledger with owners, version floors, telemetry, and exact removal proof | DTR-01 | Ledger/schema contract test if automated; source verification | Candidate |
| DTR-09 | P3 | Wire or retire the account-migration group/pending-work island | DTR-08; Move Account owner decision | `move-feature`; migration/encryption compatibility proof | Decision blocked |
| DTR-10 | P3 | Split explicit legacy group removal from join/hydrate/leave/rotation disposition | DTR-08; group/crypto owner decision | `groups`; `feature-host-all`; crypto/native proof where affected | Decision blocked |
| DTR-11 | P3 | Map and disposition remaining test-only leaves | DTR-08; replacement mapping | Focused replacement tests and affected curated/family gates | Candidate |
| DTR-12 | P4/P5 | Add enforceable architecture/layer boundary checks | DTR-01 | Exact boundary-tool tests; current exceptions pinned | Candidate |
| DTR-13 | P4 | Move debug/E2E wiring behind a separate composition root while preserving proof entrypoints | DTR-01, DTR-12 | `sims-contracts`; affected simulations; startup/lifecycle preservation; affected family gate | Deferred until Wave 3 |
| DTR-14 | P5 | Extract `main.dart` bootstrap phases behind stable application interfaces | DTR-13 | Startup, lifecycle, push, Move Account, and affected core/feature gates | Deferred until DTR-13 |
| DTR-15 | P5 | Extract shared direct/group conversation controllers without a shared base `State` | DTR-12 | `1to1`; `groups`; `feature-host-all`; justified `performance-host` | Deferred until Wave 4A |
| DTR-16 | P5 | Decompose `GroupMessageListener` behind its existing facade | DTR-15 | `groups`; `feature-host-all`; crypto/background preservation | Deferred until DTR-15 |
| DTR-17 | P5 | Decompose `P2PServiceImpl` behind stable interfaces | DTR-14 | `1to1`; `transport`; `core-host-all`; justified `performance-host` | Deferred until DTR-14 |
| DTR-18 | P5 | Move orchestration out of `core` and relocate misplaced repository implementations incrementally | DTR-12, DTR-14, DTR-16, DTR-17 | Boundary tests; affected `core-host-all` and `feature-host-all` | Deferred until predecessor facades stabilize |
| DEP-01 | P4/P5 | Dependency modernization split by pure Dart, persistence/crypto, Android, and iOS boundaries | A green preceding wave; no concurrent architecture rewrite | Per-package causal proof, affected family/native gates, then child-wave closure | Split into child plans before execution |

### SEC-00 evidence already requiring action

The audit found a tracked Android upload keystore and tracked IPA artifacts,
with an additional IPA present in Git history. SEC-00 must be an operational
security runbook, not an ordinary application TDD plan. Credential
rotation/revocation, artifact removal, history rewriting, coordinated force
pushes, and downstream clone invalidation require explicit owner authorization.
Repository ignore and secret/artifact guards can be a separate, reversible
code-plan child of SEC-00.

Reversible guard work and runbook preparation may begin immediately.
Credential rotation/revocation, artifact deletion, history rewriting,
force-pushes, and clone invalidation require explicit release/security
authorization and exact target resolution. Confirm secure custody of replacement
signing material before deleting repository copies, rotate or revoke before
history cleanup, and keep all evidence sanitized: never record credentials,
keystore contents, passwords, private keys, or signing material in this roadmap.

---

## Wave charters

### Wave 0 — Safety rails

Plans: DTR-01, DTR-02, and DTR-08.

Entry:

- Runtime roots and supported compatibility floors have named owners.
- Current analyzer output is captured.
- CI/test discovery conventions are enumerated before writing reachability
  rules.
- DTR-02 accounts for `scripts/check_flutter_analyze_baseline.sh`,
  `tool/analyzer_baseline/`, and its registration in
  `tool/sims/critical_features.json`; it does not delete only the TSV while
  leaving a broken gate.

Exit:

- The reachability guard has explicit exceptions for manual, generated,
  callback, native, migration, protocol, and test roots.
- The reachability guard is advisory and classifying only: it never mutates
  files and cannot promote a candidate based solely on Graphify, analyzer
  output, or missing imports.
- Strict analysis replaces historical-baseline acceptance.
- Compatibility removals cannot proceed without owner, floor, and proof data.
- All three slices are `Plan-green`.
- Wave 0 full `host-all` and any exact tool tests pass.

### Wave 1 — Proven dependency leaves

Plans: DTR-03, DTR-04, and DTR-05.

Initial DTR-03 anchors:

- `lib/core/services/chat_message.dart`
- `lib/core/services/contact_request_listener.dart`
- deprecated `callGroupJoin` in
  `lib/core/bridge/bridge_group_helpers.dart`

Initial DTR-04 anchors:

- `lib/features/feed/presentation/widgets/feed_ring_avatar.dart`
- `lib/features/groups/domain/models/group_inbox_cursor.dart`
- `lib/features/groups/presentation/widgets/group_compose_area.dart`
- `lib/features/posts/application/post_pass_follow_on_support.dart`
- `lib/features/settings/presentation/widgets/settings_move_account_card.dart`
- `lib/features/conversation/presentation/widgets/amplitude_bars.dart`
- `lib/features/settings/presentation/widgets/settings_peer_id_card.dart`
- `lib/features/settings/presentation/widgets/posts_nearby_settings_card.dart`
- `lib/features/identity/presentation/widgets/identity_loading_card.dart`
- the compatibility export at
  `lib/features/conversation/presentation/widgets/recording_overlay.dart`

DTR-05 owns only the suppressed unused relay-probe implementation in
`lib/features/conversation/application/send_chat_message_use_case.dart`; it is
kept separate because deleting a branch in the live send path needs stronger
behavior-preservation proof than deleting orphan files. It cannot proceed
without named transport/protocol ownership, documented flag/protocol retirement
evidence, the `transport` gate, and availability-bounded automated two-peer
proof. Add exact Go/native proof if relay protocol behavior participates in the
branch.

Exit:

- Every deleted file/symbol has an active replacement or proof of no runtime,
  compatibility, tooling, or product dependency plus named-owner approval.
- SUT-only obsolete tests are removed only with their retired SUT.
- Replacement behavior remains covered.
- DTR-03 through DTR-05 are `Plan-green`.
- Wave 1 full `host-all` passes.

### Wave 2 — Retired UI architectures

Plans: DTR-06 and DTR-07.

Posts is not a blanket feature deletion. The 24-file island rooted at
`lib/features/posts/presentation/screens/posts_wired.dart` is production
unreachable, while post repositories, listeners, notification routing, and
follow-on retry behavior remain live.

The Group-list island consists of:

- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/groups/presentation/screens/group_list_screen.dart`
- `lib/features/groups/presentation/widgets/group_card.dart`

Exit:

- Product has recorded retire-versus-restore decisions.
- Still-relevant tests have moved to Feed/Orbit and current group navigation
  before retired UI tests are deleted.
- Live backend and notification behavior is preserved.
- DTR-06 and DTR-07 are `Plan-green`.
- Wave 2 full `host-all` passes.

### Wave 3 — Wire or retire

Plans: DTR-09, DTR-10, and DTR-11.

No production deletion begins while a slice is `Decision blocked`. A decision
to wire code into production becomes a modification plan with new causal tests;
it is not disguised as cleanup.

Specific caution:

- The account-migration group/pending-work manifest island may be an abandoned
  specification or missing integration.
- Group join/hydrate code claims production behavior despite having no live
  wiring.
- Leave, rotation, payload, persistence, and crypto compatibility must be split
  by behavior contract rather than deleted as one “legacy” batch.

Exit:

- Every candidate has an owner-approved wire, retire, retain, or defer decision.
- Compatibility ledger conditions are satisfied for every removal.
- DTR-09 through DTR-11 are `Plan-green` or terminally retained/deferred.
- Wave 3 full `host-all` passes.

### Wave 4A — Boundaries and composition roots

Plans: DTR-12 and DTR-13.

The goal is to make later refactors safer: enforce the desired layer direction,
then remove debug/E2E construction from the production bootstrap without
removing the workflows themselves.

Exit:

- Boundary checks fail on newly introduced forbidden dependencies.
- Production bootstrap no longer owns E2E polling/controller construction.
- Manual smoke, simulation, and headless proof entrypoints remain discoverable.
- DTR-12 and DTR-13 are `Plan-green`.
- Wave 4A full `host-all` passes.

### Wave 4B — Bootstrap and conversation seams

Plans: DTR-14 and DTR-15.

These are extraction plans, not deletion-by-LOC plans. Preserve current facade
and widget APIs. Shared conversation behavior should move into compositional
controllers; do not introduce a shared base `State` or perform a big-bang
screen rewrite.

Exit:

- Bootstrap lifecycle ordering and failure behavior remain causally covered.
- Direct and group conversation controllers have explicit ownership and stable
  adapters.
- DTR-14 and DTR-15 are `Plan-green`.
- Wave 4B full `host-all` passes.
- `performance-host` also passes if performance surfaces or contracts changed.

### Wave 4C — Listener, transport, and layering decomposition

Plans: DTR-16 and DTR-17, followed by DTR-18.

DTR-16 and DTR-17 may be developed independently but must settle stable
facades before DTR-18 moves orchestration or repository implementations.
DTR-18 is not a repository-wide folder shuffle; each relocation is tied to an
enforced boundary and an affected proof family.

Exit:

- Listener and P2P responsibilities have explicit component ownership.
- Public behavior remains behind stable facades.
- Layering exceptions decrease and no new exception is added silently.
- DTR-16 through DTR-18 are `Plan-green`.
- Wave 4C full `host-all` passes.
- `performance-host` also passes where justified.

### Wave 5 — Dependency modernization

DEP-01 must be decomposed before execution. At minimum, keep these child waves
separate:

1. pure-Dart packages;
2. persistence and crypto packages;
3. Android plugins/build tooling; and
4. iOS plugins/build tooling.

Refresh `flutter pub outdated --no-dev-dependencies` at plan time. Vendored
Bonsoir follows its documented rebase/upstream-verification process. Package
upgrades must not be mixed with DTR-14 through DTR-18, because that would make
regression attribution and rollback ambiguous.

Each dependency child wave gets one full `host-all` after its constituent plans
are plan-green, plus its required native/platform gates.

---

## Gate policy

### Per-plan cadence

Every implementation plan runs:

1. focused causal tests for the exact removed or moved behavior;
2. exact preservation sentinels;
3. the affected curated lane, such as:
   - `./scripts/run_test_gates.sh 1to1`
   - `./scripts/run_test_gates.sh feed`
   - `./scripts/run_test_gates.sh groups`
   - `./scripts/run_test_gates.sh posts`
   - `./scripts/run_test_gates.sh transport`
4. only the justified family sweep:
   - `./scripts/run_host_test_gates.sh core-host-all`
   - `./scripts/run_host_test_gates.sh feature-host-all`
   - `./scripts/run_host_test_gates.sh move-feature`
   - `./scripts/run_host_test_gates.sh performance-host`
5. exact shared tests outside those globs;
6. `flutter analyze` after DTR-02, and the current analyzer gate until DTR-02
   lands; and
7. `git diff --check`.

Native, Go, migration, crypto, background, and device proof is added whenever
the affected behavior participates in that boundary, even if the edited files
are Dart-only. A Dart edit to a headless callback still requires its
headless/native proof. Graph relationships do not replace those proof legs.

### Wave-level full gate

After every code-bearing plan is `Plan-green` and all other constituent rows
are terminally retained, deferred, or dropped, run the wave-level gate on the
integrated commit:

```bash
./scripts/run_host_test_gates.sh host-all --continue-on-failure
```

The canonical script currently discovers all non-performance
`test/**/*_test.dart` paths and the registered Go bridge/node tails. Do not
hard-code an inventory count in this roadmap; record the planned count emitted
by the run.

Batching, concurrency, or exact resume options are allowed when required by the
execution environment, but the evidence row must record the exact commands and
covered item ranges. A segmented run must be labelled segmented and may be
accepted only when the combined evidence covers the exact original inventory
with no gaps. A dry run or `--list` is never passing evidence.

After each coherent app-owned code plan or batch, refresh the architecture
graph once:

```bash
./graphify-arch/refresh_arch_graph.sh --incremental
```

Documentation-only updates do not require a graph refresh.

### Final closure

Run full `host-all` again after all accepted waves, even if the last wave
already ran it. Also run the justified final platform, migration, and
performance families for surfaces changed across the program.

---

## Wave gate ledger

Update this table in the same change that records a wave verdict.

| Closure | Plans | State | Exact command / inventory | Commit or range | Result and evidence | Date / owner |
|---|---|---|---|---|---|---|
| SEC-00 operational closure | SEC-00 | Not started | Runbook pending | — | Rotation, HEAD/history cleanup, clone invalidation, and guard evidence pending | — |
| Wave 0 | DTR-01, DTR-02, DTR-08 | Not started | `host-all` pending | — | — | — |
| Wave 1 | DTR-03, DTR-04, DTR-05 | Not started | `host-all` pending | — | — | — |
| Wave 2 | DTR-06, DTR-07 | Blocked | Product decisions pending | — | — | — |
| Wave 3 | DTR-09, DTR-10, DTR-11 | Blocked | Ownership decisions pending | — | — | — |
| Wave 4A | DTR-12, DTR-13 | Deferred | `host-all` pending | — | — | — |
| Wave 4B | DTR-14, DTR-15 | Deferred | `host-all`; conditional `performance-host` | — | — | — |
| Wave 4C | DTR-16, DTR-17, DTR-18 | Deferred | `host-all`; conditional `performance-host` | — | — | — |
| Wave 5 child waves | DEP-01 children | Deferred | Per-child `host-all` plus platform gates | — | — | — |
| Final rollout | All accepted waves | Not started | Final `host-all` plus justified families | — | — | — |

---

## Decision ledger

| Decision | Required before | Owner | State | Resolution / evidence |
|---|---|---|---|---|
| Rotate/revoke exposed signing material and coordinate history rewrite | SEC-00 closure | Release/security | Open | — |
| Supported Android, iOS, macOS, Windows, Linux, and web release/CI targets | Any platform cleanup or DEP-01 planning | Product + release | Open | — |
| Retire or restore the Posts UI | DTR-06 planning | Product | Open | — |
| Retire Group-list UI after Feed/Orbit test migration | DTR-07 planning | Product + groups | Open | — |
| Retire the unused relay-probe flag/protocol behavior | DTR-05 planning | Transport + protocol | Open | — |
| Wire or retire account-migration group/pending-work manifests | DTR-09 planning | Move Account | Open | — |
| Wire or retire group join/hydrate paths | DTR-10 planning | Groups | Open | — |
| Compatibility floor for legacy group leave/rotation/payload paths | DTR-10 planning | Groups + crypto | Open | — |
| Ownership of remaining test-only leaves | DTR-11 planning | Feature owners | Open | — |
| Supported build profiles and debug/E2E entrypoints | DTR-13 planning | QA + release | Open | — |

---

## Candidate reconciliation ledger

Update totals after each accepted wave. Never report only deleted LOC; retained
and newly wired code are part of the safety result.

| Outcome | Files | LOC | Evidence |
|---|---:|---:|---|
| Removed | 0 | 0 | — |
| Wired into supported behavior | 0 | 0 | — |
| Retained with owner/removal condition | 0 | 0 | — |
| Deferred with revisit condition | 0 | 0 | — |
| Remaining unclassified audit candidates | Pending | Pending | Initial audit groups above |

## Maintenance protocol

1. Add or split a `DTR-*` registry row before creating implementation work.
2. Record decisions in the decision ledger; do not bury them in plan prose.
3. Link the source-verified TDD plan and change the row to `Planned`.
4. Record its focused, curated, family, analyzer, and boundary evidence in that
   plan.
5. Change the row to `Plan-green` only after all per-plan proof passes.
6. When every plan in a wave is terminal, run the wave gate from the exact
   commit/range under acceptance and fill the wave ledger.
7. Promote eligible rows to `Wave-accepted` in the same roadmap update.
8. Update reconciliation totals and retained conditions.
9. Re-run and record final rollout closure after the last wave.

## Final rollout checklist

- [ ] SEC-00 is closed with sanitized authorization, replacement-key custody,
      rotation/revocation, artifact-target, history, and clone-coordination
      evidence.
- [ ] Every registry row is wave-accepted, retained, deferred, or dropped.
- [ ] Every reachability candidate has an evidence-backed disposition;
      unresolved uncertainty is retained or deferred, never removed.
- [ ] Strict analyzer and suppression rules pass.
- [ ] Every required wave-level `host-all` has evidence.
- [ ] Final full `host-all` passes.
- [ ] Required performance, native, Go, migration, crypto, background, and
      availability-bounded device proofs pass.
- [ ] Architecture graph is refreshed after the final app-owned change.
- [ ] Removal/wiring/retention totals are recorded.
- [ ] Remaining debt has an owner and a new explicit revisit condition.
