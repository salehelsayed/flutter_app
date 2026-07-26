# Dead Code and Technical Debt Removal — Master Roadmap

Status: executing — Wave 0 accepted on 2026-07-25; Wave 1 constituent plans
DTR-03 through DTR-05 are Plan-green, and the Wave 1 aggregate `host-all`
remains pending.

Snapshot date: 2026-07-26.

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
| Ledger-complete | Documentation-only safety or decision artifact is source-verified and requires no application mutation |
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
| DTR-01 | P1/P4 | Advisory runtime-root inventory, allowlist, and CI reachability classifier; it never deletes or promotes candidates automatically | None | Exact tool tests; callback/native/generated fixtures; affected family gate | Wave-accepted — [Plan 272](272-runtime-root-inventory-advisory-reachability-guard-tdd-plan.md); 1,056 files reconciled, 17/17 restricted roots validated, deterministic/read-only real-tree proof and focused gates green on 2026-07-25; Wave 0 closure evidence is recorded below |
| DTR-02 | P4 | Retire stale analyzer baseline and enforce a production suppression ratchet | None | Analyzer-tool tests; strict `flutter analyze`; `git diff --check` | Wave-accepted — [Plan 273](273-analyzer-baseline-retirement-production-suppression-ratchet-tdd-plan.md); strict no-pub/fatal analysis, the originally landed exact four-identity production suppression ratchet, retired legacy baseline artifacts, migrated repo callers, and focused gates were green on 2026-07-25. After authorized Plan 276 removed the sole handwritten identity, the current ratchet is exactly the three generated l10n identities; Wave 0 closure evidence is recorded below. |
| DTR-03 | P1 | Remove high-confidence dead core APIs/models | DTR-01, DTR-02 | Focused import/API tests; `core-host-all` | **Plan-green** — [Plan 274](274-dead-core-api-model-removal-tdd-plan.md) retired the duplicate core `ChatMessage`, hollow core contact listener and its SUT-only suite, plus only the deprecated topic-only wrapper and legacy test fragments (339 dead code/test lines). Live feature models/listener, DTR-10 islands, and full-config Dart/native/Go join behavior remain. Causal RED/GREEN and mutation re-red, bindings/eight Go tests, `runtime-roots`, `1to1`, `groups`, `core-host-all`, strict analysis, completeness, Graphify, scope, and diff gates passed on 2026-07-25; Wave 1 `host-all` remains deferred. |
| DTR-04 | P1 | Remove high-confidence dead feature/UI leaves and obsolete SUT-only tests | DTR-01, DTR-02 | Replacement-preservation tests; affected curated gates; `feature-host-all` | **Plan-green** — [Plan 275](275-unused-visible-feature-leaves-removal-tdd-plan.md) retired eight visible/UI leaves and four obsolete SUT-only tests after the staged `DTR08-COMP-002` production-first recording-facade migration. Live replacement surfaces remain covered, and the group cursor and post helper remain under their DTR-10/DTR-06 owner conditions. Causal RED/GREEN and representative mutation re-red, `runtime-roots` 16/16, completeness 1,354/1,354, `1to1`, `feed`, `groups`, the 821-file `feature-host-all`, strict analysis, Graphify, scope, and diff gates passed on 2026-07-25; Wave 1 `host-all` remains deferred. |
| DTR-05 | P1 | Remove the suppressed unused 1:1 relay-probe branch | DTR-01, DTR-08; transport/protocol owner decision | Causal structural and 1:1 preservation tests; `1to1`; `transport`; `feature-host-all`; the approved helper-only two-peer waiver below; conditional Go/native proof if a live protocol boundary changes | **Plan-green** — [Plan 276](276-dormant-chat-relay-probe-helper-removal-tdd-plan.md) atomically removed the zero-call-site private chat helper, its suppression/inventory identity, and stale serial-probe prose. Causal RED/GREEN and six mutation re-reds, TC-02 through TC-08, `1to1` (2,441 tests plus its relay tail), strict analysis at three reviewed suppressions/zero issues, four exact Go selectors, discovery, physical Pixel 6 `transport`, the 821-path `feature-host-all` sweep (`+8550 ~1`, one skip), Graphify, protected-scope, and diff gates passed on 2026-07-26. `DTR05-AUTH-01` and its helper-only waiver remain the authorization of record; the live shared relay protocol is unchanged. Wave 1 aggregate `host-all` remains deferred. |
| DTR-06 | P2 | Retire or restore the Posts UI island while retaining live post backends | DTR-04; product decision | `posts`; `feed`; `feature-host-all`; navigation preservation | Decision blocked |
| DTR-07 | P2 | Retire the Group-list UI island after moving valuable coverage to Feed/Orbit | DTR-04; product decision; current-navigation proof | `groups`; `feed`; `feature-host-all` | Decision blocked |
| DTR-08 | P3 | Compatibility ledger with owners, version floors, telemetry, and exact removal proof | DTR-01 | Ledger/schema contract test if automated; source verification | Wave-accepted (`Ledger-complete`) — documentation-only `DTR08-COMP-001` through `DTR08-COMP-011` source-verified and independently audited on 2026-07-25; both exact DTR-01 compatibility roots are covered, no implementation TDD plan was required, and no removal is authorized |
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
- DTR-01 and DTR-02 are `Plan-green`; documentation-only DTR-08 is
  `Ledger-complete`.
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
behavior-preservation proof than deleting orphan files.
`DTR05-AUTH-01 leaf-only two-peer waiver` records the sole project authority's
2026-07-26 approval after a fail-closed current-source census proved one private
declaration, zero executable references/tear-offs, no Dart part linkage, and no
VM entrypoint. A two-peer run cannot observe deletion of that unreachable leaf,
so Plan 276's causal structural/host proof plus the explicitly pinned
single-target `transport` preservation gate replaces the otherwise categorical
two-peer leg for this helper only. The waiver does not authorize or weaken the
availability-bounded two-peer and exact Go/native proof required for any future
live `probeRelay` / `relay:probe` / Go `RelayProbe` boundary change.

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
are terminally `Ledger-complete`, retained, deferred, or dropped, run the
wave-level gate on the integrated commit:

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
| Wave 0 | DTR-01, DTR-02, DTR-08 | Wave-accepted | Attempt 1: `./scripts/run_host_test_gates.sh host-all --continue-on-failure --batch-flutter --concurrency 8 --reporter failures-only`; Attempt 2: `./scripts/run_host_test_gates.sh host-all --continue-on-failure --batch-flutter --concurrency 1 --reporter failures-only`; each planned 1,269 exact Dart paths + 8 Go tails = 1,277 items | `a68aacee7482` + uncommitted DTR working-tree delta | Attempt 1: Flutter `+12,885 ~1 -2`, exit 1; Go 8/8 PASS; four narrow diagnostics passed but did not replace the failed gate. Attempt 2: exit 0; Flutter 12,887 passed and 1 skipped; Go 8/8 PASS; final `PASS: host tests completed for scope: host-all`. Retained log: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/dtr-wave0-host-all.XXXXXX.log`; SHA-256 `33563aacaa60919508b6779061d1d2236de2c2c999b36f7b4ab29d00be537d1c`. | 2026-07-25 / user-executed; Codex-verified |
| Wave 1 | DTR-03, DTR-04, DTR-05 | In progress — DTR-03, DTR-04, and DTR-05 Plan-green; aggregate `host-all` pending | `host-all` pending until every Wave 1 plan is complete or terminal | — | All three per-plan proof sets are green; `DTR05-AUTH-01` resolved the helper-only disposition/waiver on 2026-07-26. Wave 1 aggregate acceptance is not yet claimed. | 2026-07-26 / DTR-03, DTR-04, DTR-05 |
| Wave 2 | DTR-06, DTR-07 | Blocked | Product decisions pending | — | — | — |
| Wave 3 | DTR-09, DTR-10, DTR-11 | Blocked | Ownership decisions pending | — | — | — |
| Wave 4A | DTR-12, DTR-13 | Deferred | `host-all` pending | — | — | — |
| Wave 4B | DTR-14, DTR-15 | Deferred | `host-all`; conditional `performance-host` | — | — | — |
| Wave 4C | DTR-16, DTR-17, DTR-18 | Deferred | `host-all`; conditional `performance-host` | — | — | — |
| Wave 5 child waves | DEP-01 children | Deferred | Per-child `host-all` plus platform gates | — | — | — |
| Final rollout | All accepted waves | Not started | Final `host-all` plus justified families | — | — | — |

Two Wave 0 full `host-all` closure attempts were executed. No full `host-all`
ran between DTR-01 and DTR-02. Attempt 1 ran the complete 1,277-item inventory
at concurrency 8 and completed non-green. The `failures-only` reporter's two
`[E]` blocks fell inside truncated PTY segments; its retained global counters
beside concurrently active tests are not exact failure attribution.

Two independent read-only source/order audits identified the known
`group_conversation_wired_test.dart` aggregate pair as the strongest
inference: `GMAR-004 reopen hydration preserves video voice pending and failed
media without duplicates` and `incoming group image refreshes on open recipient
route after background download without reopen`. Both occur before the retained
same-suite line where `-2` was visible, and both passed together in a narrow
exact-name rerun (`2/2`). The concurrently displayed GE-020 group soak and the
known group voice pre-persist timeout also passed together (`2/2`). These
diagnostics classify the residual as batch/load-sensitive and outside the
DTR-01/DTR-02/DTR-08 surfaces. They do not convert Attempt 1's nonzero
`host-all` result into a pass; that failed attempt remains part of the closure
record.

Attempt 2 was an authorized full retry of the same 1,269 exact Dart paths and
8 Go tails at concurrency 1. It exited 0 with 12,887 Flutter tests passed,
1 skipped, all 8 Go tails passed, and the final scope-completion marker present.
The retained log is
`/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/dtr-wave0-host-all.XXXXXX.log`
with SHA-256
`33563aacaa60919508b6779061d1d2236de2c2c999b36f7b4ab29d00be537d1c`.
This green complete-inventory retry satisfies the Wave 0 exit gate, so Wave 0
is accepted.

---

## Decision ledger

| Decision | Required before | Owner | State | Resolution / evidence |
|---|---|---|---|---|
| Rotate/revoke exposed signing material and coordinate history rewrite | SEC-00 closure | Release/security | Open | — |
| Supported Android, iOS, macOS, Windows, Linux, and web release/CI targets | Any platform cleanup or DEP-01 planning | Product + release | Open | — |
| Approve exact retirement of the duplicate core `ChatMessage`, hollow core `ContactRequestListener`, and its SUT-only suite/current-doc metadata | DTR-03 execution | Core services | Approved 2026-07-25 | `DTR03-AUTH-01`: the current authenticated project owner, acting as Core Services owner, approved the exact two sources, SUT-only test, two DTR-01 rows/expectations, and stale current-doc claims; the live feature P2P model, feature contact listener/lifecycle, and fake P2P service are retained. Rollback restores the exact retired sources/test/inventory/current-doc claims together. |
| Retire or restore the Posts UI | DTR-06 planning | Product | Open | — |
| Retire Group-list UI after Feed/Orbit test migration | DTR-07 planning | Product + groups | Open | — |
| Disposition the dormant chat relay-probe helper while retaining the live shared relay protocol | DTR-05 planning | Transport + protocol | Approved 2026-07-26 | `DTR05-AUTH-01`: the current authenticated project owner, as the sole implementation authority and Transport + Protocol owner, approved Plan 276's exact chat-helper/suppression/inventory/comment/test-bookkeeping removal set and the `DTR05-AUTH-01 leaf-only two-peer waiver`. The approval explicitly excludes `relayProbeSendAttempts`, the live introduction twin, `P2PService.probeRelay`, Dart/native `relay:probe`, Go `RelayProbe`, and executable `relayProbeEligible` plumbing. The live shared relay protocol remains retained under its UNKNOWN compatibility floor; rollback reverts the DTR-05 implementation atomically without erasing this historical owner decision. |
| Wire or retire account-migration group/pending-work manifests | DTR-09 planning | Move Account | Open | The two independently decision-blocked islands are recorded in `DTR08-COMP-005` and `DTR08-COMP-006`. |
| Remove the deprecated `callGroupJoin` refusal wrapper while retaining test-only join/hydrate and live rejoin/full-config behavior | DTR-03 execution | Groups | Approved 2026-07-25 | `DTR03-AUTH-02`: the current authenticated project owner, acting as Groups owner, approved only the wrapper and its legacy test fragments, confirmed no supported external users, and accepted `DTR03-CALLER-01` as the complete supported external/path/git/raw caller floor. Full-config/native/generated/Go behavior and both DTR-10 islands are retained; rollback restores only the wrapper/test fragments. |
| Disposition the test-only `joinGroup` and `hydrateGroupsFromPeers` islands | DTR-10 planning | Groups | Open | Not covered by `DTR03-AUTH-02`; their independent caller, proof, and rollback boundaries remain recorded in `DTR08-COMP-004`. |
| Compatibility floor for legacy group-leave paths and durable exit persistence | DTR-10 planning | Groups + database + release | Open | Test-only and default-false legacy paths are separated from the live `lastAdminLeaveBlockedMessage` UI constant and live v103/v104 state in `DTR08-COMP-007`. |
| Compatibility floor for legacy rotation and the Dart payload duplicate | DTR-10 / DTR-11 planning | Groups + crypto + release | Open | Leaf candidates are separated from live key-epoch and v3 wire contracts in `DTR08-COMP-008` and `DTR08-COMP-009`. |
| Compatibility floor for group cursor persistence and legacy secret scrub | DTR-10 / DEP-01 planning | Groups + database + crypto + security + release | Open | Live persistence and security rollback constraints are recorded independently in `DTR08-COMP-010` and `DTR08-COMP-011`. |
| Ownership of remaining test-only leaves | DTR-11 planning | Feature owners | Open | — |
| Supported build profiles and debug/E2E entrypoints | DTR-13 planning | QA + release | Open | — |

---

## DTR-08 compatibility ledger

This is a removal-safety ledger, not authorization to remove compatibility
code. Every exact DTR-01 manifest record tagged `compatibility` is present
below as `DTR08-COMP-001` or `DTR08-COMP-002`. The additional rows split the
known downstream compatibility islands by behavior contract. `UNKNOWN` means
that current source has no supported-client/fleet floor or aggregate usage
evidence; under the safety invariants above, that state requires retention or
deferral rather than deletion.

| ID | Exact surface / source anchors | Downstream plan | Owner | Supported-version floor | Telemetry / usage evidence | Exact removal proof floor | Rollback | Current disposition / revisit condition |
|---|---|---|---|---|---|---|---|---|
| DTR08-COMP-001 | `lib/core/database/production_migration_registry.dart`: `productionCreateMigrations`, `productionUpgradeMigrations`; `lib/core/database/app_database_version.dart`: `currentIdentityDatabaseVersion` | All schema-bearing DTR/DEP work | Database + release | DB schema is v104; v96+ is the one-way supported release floor. This does **not** make v1-v95 migration code removable because supported profiles still require exact create/upgrade ordering and there is no fleet population proof. | `lib/main.dart` opens `identity.db` through the registry; startup readiness exists, but no aggregate installed-schema/adoption telemetry proves old steps unused. | Run `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart`, `flutter test --no-pub test/core/database/migrations`, explicit-target `integration_test/migration_database_sqlcipher_capability_test.dart`, and `./scripts/run_host_test_gates.sh core-host-all`. Removal additionally requires release-owner population evidence, a named step-specific forward-upgrade test, and forward-only recovery proof. | Restore migration files and exact registry order. Never schema-downgrade a profile; ship a forward fix for a released migration. | **Retained.** Revisit only when every supported install/backup floor, population evidence, upgrade proof, and rollback plan permits an exact step to retire. |
| DTR08-COMP-002 | `lib/features/conversation/presentation/widgets/recording_overlay.dart` export facade; live import in `compose_area.dart` | DTR-04 | Conversation | Source/API compatibility only; no release or wire floor applies. The floor is zero supported imports of the facade after an atomic retarget. | Current production import is direct usage evidence; runtime import telemetry is not applicable. Posts already uses the shared implementation directly. | Atomically retarget production/tests; require `! rg -n "features/conversation/presentation/widgets/recording_overlay\\.dart" lib test`; run `flutter test --no-pub test/features/conversation/presentation/widgets/recording_overlay_test.dart test/features/conversation/presentation/widgets/compose_area_test.dart test/features/conversation/presentation/screens/conversation_wired_test.dart`, `./scripts/run_test_gates.sh 1to1`, `./scripts/check_flutter_analyze_strict.sh`, and `./scripts/run_host_test_gates.sh feature-host-all`. | Restore the one-line export and prior imports. | **Retained / removal deferred to DTR-04.** The live production importer currently blocks removal. |
| DTR08-COMP-003 | Former dormant chat-only `_tryRelayProbeSend` in `send_chat_message_use_case.dart`, removed by Plan 276; live shared `relayProbeSendAttempts` consumed by introduction delivery and delete-message flows; live `P2PService.probeRelay` implementation, Dart/native `relay:probe` dispatch, and `go-mknoon/bridge/bridge.go` `RelayProbe` | DTR-05 | Transport + protocol | **UNKNOWN for protocol retirement; resolved for the private helper leaf.** No supported-client/protocol retirement floor or fleet adoption evidence exists. The former dormant chat helper is not equivalent to the live shared relay protocol. | The fail-closed pre-edit Plan 276 census proved one private helper declaration, zero executable references/tear-offs, no Dart part linkage, and no VM entrypoint. Post-edit source and ratchet proof confirms the helper is absent and exactly three generated l10n identities remain. `relayProbeSendAttempts` and the introduction/delete/global protocol paths remain live and outside the chat-leaf retirement. | `DTR05-AUTH-01 leaf-only two-peer waiver`: the sole project authority approved replacing an unobservable two-peer deletion leg with Plan 276's causal inventory/source-removal RED, M-1 through M-4, exact FDC-03 zero-probe/custody sentinels, live introduction/delete/Dart bridge preservation tests, `./scripts/run_test_gates.sh 1to1`, explicit-supported-Android `transport`, and `./scripts/run_host_test_gates.sh feature-host-all`. Preserve the four existing Go smoke selectors with exact commands: `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -v -run '^TestForegroundRelayProbeIsNotRequiredForActiveSendPath$' -count=1)`, `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -v -run '^TestDialPeerViaRelayTriesAllAddresses$' -count=1)`, `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -v -run '^TestDialPeerViaRelay_TriesSecondRelayWhenFirstFails$' -count=1)`, and `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -v -run '^TestDialPeerViaRelay_SingleRelayStillWorks$' -count=1)`; protected staged/unstaged no-diff guards are the causal Go/native preservation proof. Any future live protocol-boundary change still requires its own owner decision, supported-client floor, exact Go/native causal tests, and named availability-bounded two-peer proof. | Revert the entire atomic Plan 276 implementation change, including helper/suppression/inventory/test/status bookkeeping, while preserving `DTR05-AUTH-01` as historical owner evidence. Do not remove or restore the live shared attempt constant. Protocol rollback remains a separate Dart-interface/service/bridge/Go/live-consumer change. | **Private chat-helper removed / Plan-green under Plan 276; shared attempt constant and global relay protocol retained.** `DTR05-AUTH-01` remains historical authorization for only the helper leaf and does not authorize protocol retirement. |
| DTR08-COMP-004 | Retired local-refusal `callGroupJoin` wrapper from `bridge_group_helpers.dart`; test-only `joinGroup` in `join_group_use_case.dart` and `hydrateGroupsFromPeers` in `hydrate_groups_from_peers_use_case.dart`; live `callGroupJoinWithConfig` and `rejoinGroupTopics` used by startup/resume/UI/invite flows | DTR-03 / DTR-10 | Groups | **Resolved for the DTR-03 wrapper only.** On 2026-07-25, `DTR03-AUTH-02` accepted Plan 274's `DTR03-CALLER-01` execution source set as the complete supported external/path/git/raw caller floor and confirmed no supported external users of `callGroupJoin`. The floor remains **UNKNOWN** for DTR-10 disposition; full-config `group:join` remains live. | `DTR03-CALLER-01` found one wrapper declaration, four SUT-only calls/six test tokens, zero other owned/current Dart or native/Go/platform tokens, zero export facades, and `publish_to: none`. `joinGroup` and `hydrateGroupsFromPeers` still have test-only callers. `rejoinGroupTopics` and `callGroupJoinWithConfig` have current production callers; no fleet join-version telemetry exists. | Wrapper-only removal passed Plan 274's fail-closed caller/source contract, exact full-config and live invite/rejoin/startup sentinels, protected native/generated/Go no-diff and binding checks, eight exact Go tests, `runtime-roots`, `1to1`, `groups`, and justified `core-host-all`. DTR-10 must separately prove and authorize `joinGroup`/`hydrateGroupsFromPeers`; a command-mapping change still requires a new platform-dispatch test and separate plan. | Wrapper rollback restores only `callGroupJoin` and its legacy test fragments; no storage/wire/native/Go rollback applies. DTR-10 leaf rollback remains independent. Never remove or change live full-config `group:join` in either leaf cleanup. | **Wrapper retired / Plan-green under DTR-03.** Test-only `joinGroup` and `hydrateGroupsFromPeers` remain decision-blocked for DTR-10; live `rejoinGroupTopics` and the full-config bridge/native/Go path are retained. |
| DTR08-COMP-005 | `migration_group_manifest_builder.dart`, `migration_group_manifest_validator.dart`, and `domain/models/migration_group_manifest.dart` | DTR-09 | Move Account | **UNKNOWN / no manifest schema floor.** The exact group-manifest island has no proven production bundle caller; dead-call evidence is not a product decision. | Direct builder/validator tests are the only proven consumers; no production telemetry is possible while unwired. | Require `! rg -n -e 'migration_group_manifest_builder\.dart' -e 'migration_group_manifest_validator\.dart' -e 'migration_group_manifest\.dart' lib --glob '!lib/features/account_migration/application/migration_group_manifest_builder.dart' --glob '!lib/features/account_migration/application/migration_group_manifest_validator.dart' --glob '!lib/features/account_migration/domain/models/migration_group_manifest.dart'`; run `flutter test --no-pub test/features/account_migration/application/migration_group_manifest_builder_test.dart test/features/account_migration/application/migration_group_manifest_validator_test.dart`, full `account_migration_bundle_transfer_test.dart` and `account_migration_end_to_end_test.dart`, and `./scripts/run_test_gates.sh move-feature`; run `./scripts/run_test_gates.sh groups` only if group behavior is wired/transferred. Wiring must add exact schema/backward-parse and encryption/device proof; current tests cannot authorize a nonexistent bundle slot. | A retirement rollback restores model/builder/validator/tests. A wiring rollback must preserve backward parsing and not strand an emitted bundle. | **Decision-blocked / deferred.** Move Account must choose wire, retire, or retain before DTR-09. |
| DTR08-COMP-006 | `migration_pending_work_manifest_builder.dart`, `migration_pending_work_manifest_validator.dart`, and `domain/models/migration_pending_work_manifest.dart`, including queued group retry/inbox/key-repair/membership/reaction classifications | DTR-09 | Move Account | **UNKNOWN / no pending-work schema or bundle-slot floor.** Transfer protocol v2/min importer 2 does not prove this separate unwired manifest removable. | Direct tests and the Move gap audit show the island; no live caller or telemetry exists. | Require `! rg -n -e 'migration_pending_work_manifest_builder\.dart' -e 'migration_pending_work_manifest_validator\.dart' -e 'migration_pending_work_manifest\.dart' lib --glob '!lib/features/account_migration/application/migration_pending_work_manifest_builder.dart' --glob '!lib/features/account_migration/application/migration_pending_work_manifest_validator.dart' --glob '!lib/features/account_migration/domain/models/migration_pending_work_manifest.dart'`; run `flutter test --no-pub test/features/account_migration/application/migration_pending_work_manifest_builder_test.dart test/features/account_migration/application/migration_pending_work_manifest_validator_test.dart`, full `account_migration_bundle_transfer_test.dart` and `account_migration_end_to_end_test.dart`, `./scripts/run_test_gates.sh move-feature`, and `./scripts/run_test_gates.sh completeness-check`. If wiring changes queued behavior, additionally run the exact `1to1`, `groups`, `posts`, and `intro` gates plus new causal availability-bounded transfer/encryption proof; current device tests do not prove this unwired schema. | Retirement restores the isolated files/tests. Wiring rolls sender/receiver schema and parsing back atomically or keeps backward parsing. | **Decision-blocked / deferred.** Move Account must decide defense-in-depth wiring versus explicit retirement. |
| DTR08-COMP-007 | Dormant legacy `leaveGroup` symbol and live UI constant `lastAdminLeaveBlockedMessage` in `leave_group_use_case.dart`; superseded, test-only `leave_group_and_delete_local_history_use_case.dart`; the default-false native-leave branch in `delete_group_and_messages_use_case.dart`; live v103/v104 exit coordinator/runner, native `group:leave`, and diagnostics | DTR-10 | Groups + database + release | Global DB release floor is v96, but the group-wire/client floor is **UNKNOWN**. v103/v104 durable state is live and cannot be downgraded. | Every current production `deleteGroupAndMessages` caller passes `deleteLocallyIfDissolved: true`; the superseded coordinator has test-only consumers. The constant is live in Group-list, Group-info, and Orbit UI, while the v103/v104 coordinator/runner is wired in `main.dart`. No fleet client-floor evidence exists. | Run `flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart test/features/groups/application/delete_group_and_messages_use_case_test.dart test/features/groups/application/group_exit_actions_test.dart test/features/groups/application/group_exit_intent_coordinator_test.dart test/features/groups/application/group_exit_intent_runner_test.dart`; preserve the live constant with full `group_list_wired_test.dart`, `group_info_wired_test.dart`, and `orbit_wired_test.dart`; run `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'callGroupLeave'`; run `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'group:leave calls groupLeaveTopic with payload JSON'`; run `flutter test --no-pub test/core/database/migrations/103_group_exit_intents_test.dart test/core/database/migrations/104_group_exit_diagnostics_test.dart`; run `flutter test --no-pub -d <explicit-discovered-id> integration_test/group_exit_intents_sqlcipher_proof_test.dart` and `flutter test --no-pub -d <explicit-discovered-id> integration_test/group_exit_release_diagnostics_sqlcipher_proof_test.dart`; `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run '^TestGroupLeaveTopic_' -count=1)`; `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^TestGL009LeaveGroupTopic' -count=1)`; and `./scripts/run_test_gates.sh groups`. When behavior changes, also run the explicit-discovered-target `private_voluntary_leave_convergence` scenario and `./scripts/run_host_test_gates.sh feature-host-all`. | Restore only the removed legacy symbol/branch/coordinator plus its exact tests/inventory record. `leave_group_use_case.dart` cannot be removed until the live UI constant is atomically rehomed and all three imports retargeted. Never drop or downgrade v103/v104; released persistence failures require a forward fix. | **Dormant `leaveGroup`, the superseded coordinator, and the default-false branch are deferred; the UI compatibility constant and durable/native leave are retained.** Revisit after harness migration and owner approval. |
| DTR08-COMP-008 | Test-only legacy `rotate_group_key_use_case.dart`; local-refusal `callGroupRotateKey` in `bridge_group_helpers.dart`; `group:rotateKey` mapping in `go_bridge_client.dart`; Go `GroupRotateKey` export; live `rotate_and_distribute_group_key_use_case.dart` plus generate/distribute/promote/update bridge and Go crypto/key-epoch paths | DTR-10 | Groups + crypto + release | Key epoch is persisted protocol state, not a supported-client floor; the release/wire floor is **UNKNOWN**. | The legacy file is imported only by its unit test and `group_edge_cases_smoke_test.dart`; `callGroupRotateKey` has no other `lib` caller. Live rotation/bridge events exist, but no fleet version/adoption evidence authorizes protocol retirement. | Run `flutter test --no-pub test/features/groups/application/rotate_group_key_use_case_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`; `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'callGroupRotateKey legacy helper'`; `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'group:rotateKey calls groupRotateKey with payload JSON'`; `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run '^TestGroupRotateKey_' -count=1)`; `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge -run '^TestGroupGenerateNextKey_' -count=1)`; `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^TestGK01[6-9]' -count=1)`; `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^TestGK02[01]' -count=1)`; `./scripts/run_test_gates.sh groups`; explicit-target `group_removal_rotation_keyless_proof_test.dart` and `group_removal_rotation_keyless_converge_proof_test.dart`; and `./scripts/run_host_test_gates.sh feature-host-all`. External/raw/native command census remains an owner prerequisite. | Restore legacy wrapper/mapping/tests for leaf rollback. Live rotation rollback is atomic across Dart/Go and must never regress an already-promoted epoch. | **Legacy wrapper/mapping deferred candidate; live rotation retained.** |
| DTR08-COMP-009 | Test-only Dart `group_message_payload.dart`; live `go-mknoon/internal/group_envelope.go` v3 parser and `go-mknoon/node/pubsub.go` publish/receive wire path | DTR-10 / DTR-11 | Groups + crypto + release | Live wire schema is v3, but supported installed-client release floor is **UNKNOWN**; the literal version is not population evidence. | The Dart leaf has no production importer. Live Go parse/publish events exist, but no mixed-version/adoption counts prove v3 wire retirement safe. | For the Dart leaf, require `! rg -n "import .*group_message_payload\\.dart" lib` and `flutter test --no-pub test/features/groups/domain/models/group_message_payload_test.dart`. Preserve the live protocol with `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./internal -count=1)`, `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^TestGK029' -count=1)`, `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^TestGK030' -count=1)`, `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^TestGP023' -count=1)`, and `./scripts/run_test_gates.sh groups`; a wire change additionally requires `FLUTTER_DEVICE_ID=<explicit-discovered-id> ./scripts/run_test_gates.sh transport`, `./scripts/run_host_test_gates.sh feature-host-all`, a new named native/Go compatibility test, and a new named availability-bounded mixed-client/two-peer group compatibility proof. | Restore the Dart leaf/test independently. A wire rollback must preserve mixed clients and be atomic; leaf removal must never be described as protocol retirement. | **Dart duplicate deferred candidate; Go v3 wire/parser retained.** |
| DTR08-COMP-010 | Orphan `group_inbox_cursor.dart`; live migration 066 `group_sync_receipts`, DB helpers, repository page transaction, and `main.dart` wiring | DTR-04 / DTR-10 | Groups + database + release | Migration 066 predates the v96 release floor, but the live table persists in supported profiles; there is no safe-removal inference or population proof. | Page-transaction/migration events and live repository wiring exist; no fleet cursor-population evidence authorizes storage removal. | For model-leaf removal require `! rg -n "import .*group_inbox_cursor\\.dart" lib`; run `flutter test --no-pub test/core/database/migrations/066_group_sync_receipts_test.dart test/core/database/helpers/group_sync_receipts_db_helpers_test.dart`; the `PREREQ-GROUP-SYNC-RECEIPTS` selector in both `test/features/groups/domain/repositories/group_message_repository_impl_test.dart` and `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart`; `./scripts/run_test_gates.sh groups`; `./scripts/run_host_test_gates.sh core-host-all`; and `./scripts/run_host_test_gates.sh feature-host-all`. No current test authorizes table mutation: a persistence change requires a new forward migration and new explicit-target SQLCipher proof. | Restore `group_inbox_cursor.dart` and its DTR-01 inventory candidate assertion; there is no dedicated model unit test. Never drop or mutate the live table without a new migration and forward recovery. | **Model leaf deferred candidate; persisted cursor contract retained.** |
| DTR08-COMP-011 | `legacy_group_secret_storage_scrub.dart`; startup call in `main.dart`; secure-reference write/hydration in group and media-attachment repositories; `go-mknoon/crypto/group.go`, `crypto/sign.go`, `internal/group_envelope.go`, and retained node key epochs | DTR-10 / DEP-01 | Groups + crypto + security + release | Global DB floor is v96, but completion of the legacy scrub across every supported profile and the crypto-format negotiation floor are **UNKNOWN**. | Local scrub start/success/skip events and moved-row count exist; there is no fleet aggregation/adoption evidence. | Run `flutter test --no-pub test/core/secure_storage/legacy_group_secret_storage_scrub_test.dart`; `flutter test --no-pub test/features/groups/domain/repositories/group_repository_impl_test.dart --plain-name 'PREREQ-SECRET-STORAGE-WRAPPING'`; `flutter test --no-pub test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart --plain-name 'PREREQ-SECRET-STORAGE-WRAPPING'`; `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart`; `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./crypto -count=1)`; `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^TestUDME_' -count=1)`; `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^TestGK01[6-9]' -count=1)`; `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^TestGK02[01]' -count=1)`; `./scripts/run_test_gates.sh groups`; `flutter test --no-pub -d <explicit-discovered-id> integration_test/group_real_crypto_onboarding_test.dart`; `./scripts/run_host_test_gates.sh core-host-all`; and `./scripts/run_host_test_gates.sh feature-host-all`. Any format change additionally needs a new named mixed-client atomic-rollout proof; these current commands do not authorize it. | Restore the scrub before release; never roll back by writing plaintext. Format changes require dual-read/old-key retention or a forward migration and atomic Dart/Go rollout. | **Retained.** Security/release owners must prove floor, zero legacy rows, recovery, and rollout compatibility before retirement. |

Except for the DTR-03 wrapper now recorded as retired in `DTR08-COMP-004`, no
unresolved row above is deletion-ready. A downstream plan must copy the
relevant row ID into its scope, re-verify the anchors, resolve every `UNKNOWN`,
and record the owner-approved floor and proof before changing another
compatibility surface.

---

## Candidate reconciliation ledger

Update totals after each accepted wave. Never report only deleted LOC; retained
and newly wired code are part of the safety result.

| Outcome | Files | LOC | Evidence |
|---|---:|---:|---|
| Removed | 6 | 1,518 | DTR-02 retired 3 files / 1,179 LOC. DTR-03 retired 3 whole files plus the deprecated wrapper/test fragments for 339 dead code/test lines; per-plan evidence is in Plans 273 and 274. Wave 0 acceptance evidence remains preserved above; DTR-03 is Plan-green but Wave 1 aggregate acceptance is still pending. |
| Wired into supported behavior | 0 | 0 | — |
| Retained with owner/removal condition | 1 | 225 | DTR-01 keeps `smoke_test_runner.dart` as `retained-unresolved`; no caller or safe removal condition is proven |
| Deferred with revisit condition | 0 | 0 | — |
| Classified candidates awaiting downstream disposition | 5 | 516 | The five exact DTR-01 `candidate` rows remain advisory and map to DTR-04/DTR-10 or their named owner conditions; DTR-04 authorization does not make the classifier itself a deletion verdict. |
| Remaining unclassified audit candidates | 0 | 0 | DTR-01 accounts for every current non-main-reachable Dart path; uncertainty is retained or classified rather than hidden |

## Maintenance protocol

1. Add or split a `DTR-*` registry row before creating implementation work.
2. Record decisions in the decision ledger; do not bury them in plan prose.
3. For behavior-changing or non-trivial removal work, link the source-verified
   TDD plan and change the row to `Planned`. A documentation-only safety or
   decision artifact may instead become `Ledger-complete` after source
   verification is recorded.
4. Record focused, curated, family, analyzer, and boundary evidence in the
   implementation plan; record documentation-only source-audit evidence in this
   roadmap or a linked artifact.
5. Change a code-bearing row to `Plan-green` only after all per-plan proof
   passes.
6. When every code-bearing plan in a wave is `Plan-green` and every other slice
   is terminal, run the wave gate from the exact commit/range under acceptance
   and fill the wave ledger.
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
