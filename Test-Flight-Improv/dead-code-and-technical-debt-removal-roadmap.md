# Dead Code and Technical Debt Removal — Master Roadmap

Status: executing — Wave 0 was accepted on 2026-07-25, Wave 1 on 2026-07-26,
and Waves 2 and 3 on 2026-07-27. DTR-09 remains terminal `Retained`, DTR-10 is
terminally complete, and DTR-11 is `Wave-accepted` under Plan 287. Wave 4A
planning is unblocked; DTR-13 remains decision-blocked on DTR-12 and its
separate QA + release owner decision.

Snapshot date: 2026-07-27.

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
| Dormant future Posts UI island | 24 files / about 6,993 LOC | Intentionally retained off-navigation until Social Posts implementation resumes |
| Retired Group-list UI island | 3 files / about 2,035 LOC | Retire after current-navigation proof |
| Account-migration manifest/test island | 11 files / about 3,353 LOC | Retain unwired under `DTR09-AUTH-01` until Move Account completeness work resumes |
| Other legacy/test-only group code | 6 files / about 1,185 LOC | Split into bounded DTR-10 Plans 277–284; live compatibility boundaries remain retained |
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
| Plan-green | Focused, preservation, curated, and affected family gates passed; this retained plan-level state is separate from later registry-row and wave acceptance |
| Wave-accepted | The wave-level full gate passed and evidence is linked |
| Retained | Kept intentionally with owner, reason, and removal condition |
| Deferred | Explicitly out of the current rollout with a revisit condition |
| Dropped | Refuted as debt or superseded by another slice |

No code-bearing registry row is promoted to `Wave-accepted` until its plan has
reached `Plan-green`.

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

DTR-04 + product decision ────────────────> DTR-06 Posts UI (retained)
DTR-04 + product decision/navigation proof ─> DTR-07 Group-list UI

DTR-08 + owner decision ─┬─> DTR-09 account migration (retained)
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
| DTR-03 | P1 | Remove high-confidence dead core APIs/models | DTR-01, DTR-02 | Focused import/API tests; `core-host-all` | **Wave-accepted** — [Plan 274](274-dead-core-api-model-removal-tdd-plan.md) retired the duplicate core `ChatMessage`, hollow core contact listener and its SUT-only suite, plus only the deprecated topic-only wrapper and legacy test fragments (339 dead code/test lines). Live feature models/listener, DTR-10 islands, and full-config Dart/native/Go join behavior remain. Causal RED/GREEN and mutation re-red, bindings/eight Go tests, `runtime-roots`, `1to1`, `groups`, `core-host-all`, strict analysis, completeness, Graphify, scope, and diff gates passed on 2026-07-25; the Wave 1 aggregate acceptance evidence is recorded below. |
| DTR-04 | P1 | Remove high-confidence dead feature/UI leaves and obsolete SUT-only tests | DTR-01, DTR-02 | Replacement-preservation tests; affected curated gates; `feature-host-all` | **Wave-accepted** — [Plan 275](275-unused-visible-feature-leaves-removal-tdd-plan.md) retired eight visible/UI leaves and four obsolete SUT-only tests after the staged `DTR08-COMP-002` production-first recording-facade migration. Live replacement surfaces remain covered; the group cursor was separately retired under DTR-10 Plan 283, and the post helper is protected by DTR-06 accepted retention (`DTR06-AUTH-01`). Causal RED/GREEN and representative mutation re-red, `runtime-roots` 16/16, completeness 1,354/1,354, `1to1`, `feed`, `groups`, the 821-file `feature-host-all`, strict analysis, Graphify, scope, and diff gates passed on 2026-07-25; the Wave 1 aggregate acceptance evidence is recorded below. |
| DTR-05 | P1 | Remove the suppressed unused 1:1 relay-probe branch | DTR-01, DTR-08; transport/protocol owner decision | Causal structural and 1:1 preservation tests; `1to1`; `transport`; `feature-host-all`; the approved helper-only two-peer waiver below; conditional Go/native proof if a live protocol boundary changes | **Wave-accepted** — [Plan 276](276-dormant-chat-relay-probe-helper-removal-tdd-plan.md) atomically removed the zero-call-site private chat helper, its suppression/inventory identity, and stale serial-probe prose. Causal RED/GREEN and six mutation re-reds, TC-02 through TC-08, `1to1` (2,441 tests plus its relay tail), strict analysis at three reviewed suppressions/zero issues, four exact Go selectors, discovery, physical Pixel 6 `transport`, the 821-path `feature-host-all` sweep (`+8550 ~1`, one skip), Graphify, protected-scope, and diff gates passed on 2026-07-26. `DTR05-AUTH-01` and its helper-only waiver remain the authorization of record; the live shared relay protocol is unchanged. The Wave 1 aggregate acceptance evidence is recorded below. |
| DTR-06 | P2 | Preserve the standalone Posts UI island as an intentionally dormant future Social Posts surface while retaining live post backends and Feed/Orbit integration | DTR-04; product decision | Documentation/source verification; no application gate required while no code or navigation changes are made | **Retained** — `DTR06-AUTH-01` records accepted retention on 2026-07-26; keep the island unreachable, make no implementation/navigation change in this rollout, and revisit when Social Posts implementation is scheduled |
| DTR-07 | P2 | Retire the Group-list UI island after moving valuable coverage to Feed/Orbit | DTR-04; `DTR07-AUTH-01`; current-navigation proof | `groups`; `feed`; `feature-host-all` | **Wave-accepted** — [Plan 286](286-group-list-ui-island-retirement-tdd-plan.md) remains Plan-green after retiring the unreachable 2,035-line three-source island, its five SUT-only suites, three runtime-root declarations, one `GROUP_TESTS` entry, and exactly eight orphan keys from each locale. Orbit's separate in-place `allChats` list and every live group/navigation/backend boundary remain. Causal RED/GREEN, representative mutation re-red, all preservation selectors, `runtime-roots` (18/18; trustworthy/no drift), `groups` (3,238 Flutter tests plus all Go tails), `feed` (310), stabilized `feature-host-all` evidence (8,476 pass, 1 skip, 0 fail across 816 paths), completeness (1,349/1,349), source/diff bounds, and Graphify refresh passed. Strict analysis found no DTR-07 issue; the unrelated concurrent Plan-285 warning observed during that run was later cleared by Plan 285's clean host-tier closure. The Wave 2 aggregate acceptance evidence is recorded below. |
| DTR-08 | P3 | Compatibility ledger with owners, version floors, telemetry, and exact removal proof | DTR-01 | Ledger/schema contract test if automated; source verification | Wave-accepted (`Ledger-complete`) — documentation-only `DTR08-COMP-001` through `DTR08-COMP-011` source-verified and independently audited on 2026-07-25; both exact DTR-01 compatibility roots are covered, no implementation TDD plan was required, and no removal is authorized |
| DTR-09 | P3 | Preserve the account-migration group and pending-work manifest islands as separately retained future Move Account completeness work | DTR-08; Move Account owner decision | Documentation/source verification; preserve existing direct tests; no application gate required while no code, schema, bundle, or runtime wiring changes are made | **Retained** — `DTR09-AUTH-01` records accepted retention on 2026-07-26; neither island is authorized for deletion or production wiring during this rollout, and each must be revisited separately when Move Account completeness implementation resumes |
| DTR-10 | P3 | Retire seven bounded legacy/test-only group leaves while retaining live admission, recovery, exit, persistence, wire, crypto, and security boundaries | DTR-08; `DTR10-AUTH-01` through `DTR10-AUTH-08`; Plan 279 additionally depended on Plan 280 Plan-green | Per-plan causal/preservation contracts; `runtime-roots`; `groups`; justified `feature-host-all`; exact Go/native/device/SQLCipher proof only where named | **Terminally complete / accepted in Wave 3** — [Plans 277](277-old-join-group-removal-tdd-plan.md), [278](278-hydrate-groups-from-peers-disposition-tdd-plan.md), [279](279-dormant-group-leave-path-removal-tdd-plan.md), [280](280-superseded-leave-local-history-coordinator-removal-tdd-plan.md), [281](281-legacy-group-key-rotation-path-removal-tdd-plan.md), and [282](282-duplicate-dart-group-message-payload-removal-tdd-plan.md) are implementation-complete and Plan-green/closed; [Plan 283](283-unused-group-inbox-cursor-model-removal-tdd-plan.md) is also implementation-complete and Plan-green/closed after final strict-analysis and diff-hygiene closure; [Plan 284](284-legacy-group-secret-security-scrub-retention-evidence-tdd-plan.md) is acceptance-verified terminal `Retained`. The eight owner receipts disposition exact, separate boundaries rather than authorizing a legacy-group batch deletion. |
| DTR-11 | P3 | Map and disposition remaining test-only leaves | DTR-08; replacement mapping; `DTR11-AUTH-01` | Focused replacement tests and affected curated/family gates | **Wave-accepted** — [Plan 287](287-remaining-test-only-leaves-disposition-tdd-plan.md) re-derived and dispositioned the exact 11-file/1,065-LOC map: ten app sources and ten SUT-only suites retired, one 94-line telemetry calculator relocated byte-identically to tooling, all 11 runtime-root rows removed, live Feed/Orbit/QR/LetterCard owners preserved, only the dead backlog summary/two keys and inert S15 diagnostic retired, and `test/unit/**` registered under `core-host-all`. `_RaceResult.relayProbeEligible` remains behaviorally intact. Causal/focused/curated/family/analyzer/completeness/Graphify gates passed, followed by the accepted Wave-3 aggregate: 1,250 Flutter paths, 12,755 pass, one skip, all eight Go tails, exit 0. [Stable evidence](evidence/dtr-wave3/README.md). |
| DTR-12 | P4/P5 | Add enforceable architecture/layer boundary checks | DTR-01 | Exact boundary-tool tests; current exceptions pinned | **Candidate — planning unblocked after Wave 3 acceptance** |
| DTR-13 | P4 | Move debug/E2E wiring behind a separate composition root while preserving proof entrypoints | DTR-01, DTR-12 | `sims-contracts`; affected simulations; startup/lifecycle preservation; affected family gate | **Decision blocked — temporal Wave-3 dependency cleared; DTR-12 and the QA + release owner decision remain open** |
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

### Wave 2 — Dormant and retired UI architectures

Slices: retained DTR-06 and Wave-accepted DTR-07. Both constituents are
terminal, and Wave 2 was accepted on 2026-07-27 after its aggregate
`host-all`.

Posts is not a blanket feature deletion. The 24-file island rooted at
`lib/features/posts/presentation/screens/posts_wired.dart` is production
unreachable, while post repositories, listeners, notification routing, and
follow-on retry behavior remain live. Product has accepted this island as
intentionally dormant future Social Posts work under `DTR06-AUTH-01`. It is
neither retired nor restored during this rollout: its files remain present,
its production navigation remains disconnected, and its live Feed/Orbit and
backend integrations remain unchanged. Revisit it when Social Posts
implementation is scheduled.

Plan 286 retired the Group-list island:

- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/groups/presentation/screens/group_list_screen.dart`
- `lib/features/groups/presentation/widgets/group_card.dart`

Exit:

- DTR-06 remains preserved under its accepted-retention boundary; DTR-07's
  retirement was authorized by `DTR07-AUTH-01` (2026-07-26) and completed by
  Plan 286.
- Still-relevant coverage now lives on Feed/Orbit and current group navigation;
  the five obsolete SUT-only suites retired with the island.
- Plan 286's preservation evidence keeps live backend and notification behavior
  unchanged.
- DTR-06 remains `Retained`; Plan 286 remains Plan-green, and the DTR-07
  registry row is `Wave-accepted`.
- The aggregate full `host-all` passed all 1,267 planned items: Flutter
  `+12,827 ~1`, all eight Go tails passed, the final scope marker is present,
  and the process exited 0.

All five exit conditions are satisfied, so Wave 2 is accepted. Final-rollout
`host-all` remains a later, separate gate.

### Wave 3 — Disposition and bounded cleanup

Slices: retained DTR-09, terminally complete DTR-10, and Wave-accepted DTR-11.

No production deletion begins while a slice is `Decision blocked`. A decision
to wire code into production becomes a modification plan with new causal tests;
it is not disguised as cleanup.

Specific caution:

- The account-migration group and pending-work manifest islands are retained
  separately under `DTR09-AUTH-01` as unfinished future Move Account
  completeness work. They remain unwired during this rollout and must be
  source-verified independently before later integration.
- Plans 277 and 278 separately retired the test-only join and hydrate wrappers
  after preserving live invite/rejoin and cold-start/resume/retrier recovery.
  The hydrate wrapper cannot acquire missing fresh-device group/key state; any
  such future feature requires a separately authorized plan.
- Plan 280 migrated still-valuable UI proof to the durable exit boundary and
  retired only the superseded coordinator/fixture. Plan 279 then retired the
  old leave function/default-false branch, rehomed the last-admin message, and
  migrated the host/device proof callers onto the durable boundary.
- Plans 281 through 283 retired only the obsolete Dart rotation leaf, duplicate
  Dart payload, and orphan cursor model. Live native/Go rotation, v3 wire,
  migration 066, repository transactions, and inbox replay remain protected.
- Plan 284 acceptance-verifies terminal retention of the startup security scrub.
  No fleet-wide completion evidence exists, and marker/import/background
  alignment remains unresolved.
- Plan 287 dispositioned the exact residual 11-file/1,065-LOC test-only map,
  preserved every named live replacement and behavior boundary, retired only
  its approved sources/tests/fragments, relocated telemetry unchanged, and
  registered the missing `test/unit/**` core family.

Exit:

- Every candidate has an owner-approved wire, retire, retain, or defer decision.
- Compatibility ledger conditions are satisfied for every removal.
- DTR-09 through DTR-11 are `Plan-green` or terminally retained/deferred.
- Wave 3 full `host-all` passes.

All four exit conditions are satisfied. After Plan 287's focused, curated,
family, analyzer, completeness, runtime-root, l10n, and Graphify gates passed,
the Wave-3 aggregate passed all 1,258 planned items: 1,250 exact Flutter paths,
12,755 passing tests, one expected skip, all eight Go tails, final scope marker,
and exit 0. Wave 3 is accepted; the stable receipt is
[`evidence/dtr-wave3/README.md`](evidence/dtr-wave3/README.md).

### Wave 4A — Boundaries and composition roots

Plans: DTR-12 and DTR-13.

The goal is to make later refactors safer: enforce the desired layer direction,
then remove debug/E2E construction from the production bootstrap without
removing the workflows themselves.

Planning is unblocked by Wave 3 acceptance. DTR-12 is a planning candidate.
DTR-13 is no longer temporally deferred by Wave 3, but remains decision-blocked
until DTR-12 and the separate QA + release owner decision are resolved.

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
| Wave 1 | DTR-03, DTR-04, DTR-05 | **Wave-accepted** | Attempts 1 and 2: `./scripts/run_host_test_gates.sh host-all --continue-on-failure --batch-flutter --concurrency 1 --reporter failures-only`; each planned 1,265 exact Dart paths + 8 Go tails = 1,273 items | Attempt 1: `95d754e03fc67e21d5006efd1fbec2dddaada394`; Attempt 2: the same commit plus the uncommitted test-only TCP-port-assertion correction in `account_migration_local_transfer_runtime_test.dart`. Concurrent documentation and Graphify-output changes did not alter the executed tests. | Attempt 1 completed non-green at Flutter `+12,862 ~1 -1`; all 8 Go tails passed. Its only failure was an invalid assertion that consecutive requests must share the exact TCP source port. After the test-only correction, the selector passed 20/20 repetitions, its full file passed 40 tests, and `move-feature` passed `+442 ~1`. Attempt 2 exited 0: Flutter `+12,863 ~1`, all 8 Go tails passed, and the final scope PASS marker is present. Original-log SHA-256 values: Attempt 1 `2a8d20fca9d4c60cab49194f89071153b9f9108fae1d1d8245b002dfae397401`; Attempt 2 `781a669fbfbdebf0b50bb7abad824fac9166aef83f5ddce0ee34efc9805b22b5`. [Stable evidence archives](evidence/dtr-wave1/README.md). | 2026-07-26 / user-executed; Codex-verified and archived |
| Wave 2 | DTR-06, DTR-07 | **Wave-accepted** | Three completed attempts: `./scripts/run_host_test_gates.sh host-all --continue-on-failure --batch-flutter --concurrency 4 --reporter failures-only`; each planned 1,259 exact Dart paths + 8 Go tails = 1,267 items. Attempt 2 additionally used a temporary `GIT_INDEX_FILE` and was rejected as an invalid environment. | `95d754e03fc67e21d5006efd1fbec2dddaada394` plus the integrated uncommitted working-tree delta, including Plan 286 and later DTR-10/Plan-285 work. The accepted attempt includes the discovery/test-only closure corrections and exact staging of seven already-deleted terminal DTR-10 source paths. | Attempt 1: Flutter `+12,819 ~1 -5`, exit 1; all 8 Go tails passed. Its five failures reduce to a missing Android-harness discovery classification (three consumers), one fixed-sleep timing race, and unstaged terminal DTR-10 deletion drift. Attempt 2: Flutter `+12,822 ~1 -5`, all 8 Go tails passed, exit 1; repository guards correctly rejected the temporary redirected index, so it was not acceptance evidence. Attempt 3 exited 0: Flutter `+12,827 ~1`, all 8 Go tails passed, and the final scope marker is present. Original-log SHA-256 values: Attempt 1 `c838804bb2095d3841ee8116da6b0e38b510e0345cf7070c395ca8f81fd564c3`; Attempt 2 `6167749d53ce32954e44c0e2ee6d98a39dcfe823443cac623ebe0e7b788285ab`; Attempt 3 `869a75236f97e34f610b4053540f7e7b449ea76103f5d807d52c82aae5d4c135`. [Stable evidence archives](evidence/dtr-wave2/README.md). | 2026-07-27 / user-requested; Codex-executed, verified, and archived |
| Wave 3 | DTR-09, DTR-10, DTR-11 | **Wave-accepted** | `./scripts/run_host_test_gates.sh host-all --continue-on-failure --batch-flutter --concurrency 4 --reporter failures-only`; 1,250 exact Dart paths + 8 Go tails = 1,258 items | Repository-retained validation snapshot `ec268ce4a41d94450919170c9df2b1bf1a7ef987` (tag `dtr-wave3-tested-tree-20260727`); tree `897a285f68f1266dc6945f727f2425272151f068` frozen from the integrated workspace with a separate index | Exit 0: Flutter `+12,755 ~1`, all eight Go tails passed, and the final scope marker is present. Original-log SHA-256 `4b45449c2d064c8358fc895b580e249404faf995e95d12a7a6369600fab338d9`; archive SHA-256 `55ac78d1a0fd2a98b70884194e5cb6677ff0dba474ca24594f469165e97806f7`. [Stable Plan 287 and Wave 3 evidence](evidence/dtr-wave3/README.md). | 2026-07-27 / user-authorized; Codex-executed, verified, and archived |
| Wave 4A | DTR-12, DTR-13 | Planning unblocked; DTR-12 candidate, DTR-13 decision-blocked | `host-all` pending | — | Wave-3 temporal dependency cleared; DTR-12 plan and DTR-13 QA + release decision remain open | — |
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

Wave 1 also required two complete 1,273-item `host-all` attempts, both at
concurrency 1. Attempt 1 ran against `95d754e03fc67e21d5006efd1fbec2dddaada394`
and completed non-green only because the killed-connection account-migration
test required two consecutive requests to have the same TCP source port. That
is not an `HttpClient` contract: Dart may choose another pooled socket. All
eight Go tails passed, and the failure did not identify a production defect.

The correction changed only
`test/features/account_migration/application/account_migration_local_transfer_runtime_test.dart`.
It removed the invalid port-equality assertion while preserving the killed
connection, typed timeout classification, command order, forced client close,
cleanup, and telemetry checks. The corrected selector passed 20/20 repetitions,
the complete test file passed 40 tests, and `move-feature` passed `+442 ~1`.
No production source changed.

Attempt 2 reran the complete inventory against the same commit plus that
test-only correction. It exited 0 with 12,863 Flutter tests passed, 1 skipped,
all 8 Go tails passed, and the final scope-completion marker present. Both
attempts and both original-log hashes are preserved in the
[Wave 1 evidence archive](evidence/dtr-wave1/README.md). The failed attempt
remains part of the record; the complete green retry satisfies the Wave 1 exit
gate, so DTR-03 through DTR-05 and Wave 1 are accepted. Final-rollout
`host-all` remains a later, separate gate.

Wave 2 required three completed 1,267-item `host-all` attempts at concurrency
4. Attempt 1 ran against
`95d754e03fc67e21d5006efd1fbec2dddaada394` plus the integrated uncommitted
working-tree delta. It completed non-green at Flutter `+12,819 ~1 -5` while
all eight Go tails passed. Three failures shared one cause: the new
Android-only group multi-party harness lacked its fail-closed reliability
discovery classification. A profile-picture integration assertion used a
fixed 500 ms sleep and ran just before its successful asynchronous update
completed under batch load. The runtime-root guard also correctly reported
seven already-authorized terminal DTR-10 source deletions as unstaged drift.

The correction classified that harness as `support`, replaced the fixed sleep
with a bounded condition wait, and staged only the seven already-deleted
DTR-10 source paths. No production source changed. Discovery and all three of
its previously failing consumers plus the complete profile flow passed
together (37 tests), and the complete analyzer-ratchet/runtime-root pair passed
together (25 tests).

Attempt 2 evaluated a temporary copied-index alternative before changing the
real index. Four analyzer-guard cases correctly rejected `GIT_INDEX_FILE`, and
one runtime-root fixture inherited the redirected index. That invalid
execution environment completed at Flutter `+12,822 ~1 -5` with all eight Go
tails green, but it was not used for acceptance.

Attempt 3 used the normal repository environment and reran the complete
inventory. It exited 0 with 12,827 Flutter tests passed, 1 skipped, all 8 Go
tails passed, and the final scope-completion marker present. All three
completed attempts and original-log hashes are preserved in the
[Wave 2 evidence archive](evidence/dtr-wave2/README.md). DTR-06 remains
`Retained`; Plan 286 remains Plan-green; the DTR-07 registry row and Wave 2 are
now `Wave-accepted`. Final-rollout `host-all` remains a later, separate gate.

Wave 3 used one complete frozen-snapshot acceptance run after DTR-09 and DTR-10
were terminal and Plan 287 was Plan-green. The separate-index synthetic commit
isolated the integrated code/test tree without rewriting the shared dirty
workspace index. The 1,258-item gate exited 0 with 12,755 Flutter tests passed,
one skipped, all eight Go tails passed, and the final scope marker present.
The tested commit/tree, ignored-local-fixture disclosure, original/archive log
hashes, and Plan 287 family receipts are preserved in the
[Wave 3 evidence archive](evidence/dtr-wave3/README.md). DTR-11 and Wave 3 are
`Wave-accepted`; DTR-12/DTR-13's temporal Wave-3 dependency is cleared.
The tested snapshot is repository-reachable through
`dtr-wave3-tested-tree-20260727` and as the direct parent of the closure-record
commit. Final-rollout `host-all` remains a later, separate gate.

---

## Decision ledger

| Decision | Required before | Owner | State | Resolution / evidence |
|---|---|---|---|---|
| Rotate/revoke exposed signing material and coordinate history rewrite | SEC-00 closure | Release/security | Open | — |
| Supported Android, iOS, macOS, Windows, Linux, and web release/CI targets | Any platform cleanup or DEP-01 planning | Product + release | Open | — |
| Approve exact retirement of the duplicate core `ChatMessage`, hollow core `ContactRequestListener`, and its SUT-only suite/current-doc metadata | DTR-03 execution | Core services | Approved 2026-07-25 | `DTR03-AUTH-01`: the current authenticated project owner, acting as Core Services owner, approved the exact two sources, SUT-only test, two DTR-01 rows/expectations, and stale current-doc claims; the live feature P2P model, feature contact listener/lifecycle, and fake P2P service are retained. Rollback restores the exact retired sources/test/inventory/current-doc claims together. |
| Preserve, retire, or restore the standalone Posts UI | DTR-06 disposition | Product | Accepted retention 2026-07-26 | `DTR06-AUTH-01`: the current authenticated project owner, acting as Product owner, designates the 24-file island rooted at `lib/features/posts/presentation/screens/posts_wired.dart` as intentionally dormant future Social Posts work. It is not authorized for deletion and will not be restored to production navigation during this technical-debt rollout. The live Posts backend and Feed/Orbit integrations remain unchanged. Revisit when Social Posts implementation is scheduled; that future work must source-verify the island before reuse and may replace it rather than assuming it is implementation-ready. |
| Retire Group-list UI after Feed/Orbit test migration | DTR-07 planning | Product + groups | Approved 2026-07-26 | `DTR07-AUTH-01`: the current authenticated project owner, as the sole implementation authority and acting as Product + Groups owner, approved retirement of the Group-list UI island on the exact boundary in [Plan 286](286-group-list-ui-island-retirement-tdd-plan.md) *Scope Contract And Guard → In scope*. **Approved removal set:** the three production sources `group_list_wired.dart`, `group_list_screen.dart`, and `groups/presentation/widgets/group_card.dart`; the five SUT-only suites `group_list_wired_test.dart`, `group_list_screen_test.dart`, `group_list_screen_bidi_test.dart`, `group_card_test.dart`, `group_card_bidi_test.dart`; the three `explained-root` declarations at `tool/runtime_roots/runtime_roots.json:691-732` (whose own `condition` field already delegates to "the owning downstream DTR plan"); the single `GROUP_TESTS` entry at `scripts/run_test_gates.sh:368`; and exactly these eight l10n keys across all three locales — `group_card_no_messages`, `groups_title`, `groups_joined`, `groups_no_joined`, `groups_empty_title`, `groups_empty_desc`, `groups_pending_invites`, `groups_unknown_sender`. **Explicitly NOT authorized:** `SettingsGroupCard`, `lastAdminLeaveBlockedMessage` and its two live consumers (`group_info_wired.dart:560`, `:619`; `orbit_wired.dart:3131`, owned by DTR-10 Plan 279), `GroupBacklogRetentionNotice` (deferred to DTR-11), Orbit/Feed/`main.dart`/picker group-entry wiring, and every group backend, listener, repository, notification, bridge, native, Go, schema, migration, or relay boundary. **Approved product statement — coverage retirement, not migration:** the `de group-list row renders 24-hour time` device-proof leg is retired **with** its surface rather than migrated, because the replacement `GroupRow` (`group_row.dart:55`) deliberately renders relative time via `formatRelativeTime` and has no `DateFormat.jm` equivalent to carry the assertion. The real-iOS ICU claim retains live carriers in the three surviving conversation legs of the same proof file and in `feed_wired.dart:887`/`:906`; Plan 286 TC-286-11 test-locks the difference so it cannot be silently reverted. Rollback restores only the exact retired sources/tests/declarations/keys without erasing this historical owner decision |
| Disposition the dormant chat relay-probe helper while retaining the live shared relay protocol | DTR-05 planning | Transport + protocol | Approved 2026-07-26 | `DTR05-AUTH-01`: the current authenticated project owner, as the sole implementation authority and Transport + Protocol owner, approved Plan 276's exact chat-helper/suppression/inventory/comment/test-bookkeeping removal set and the `DTR05-AUTH-01 leaf-only two-peer waiver`. The approval explicitly excludes `relayProbeSendAttempts`, the live introduction twin, `P2PService.probeRelay`, Dart/native `relay:probe`, Go `RelayProbe`, and executable `relayProbeEligible` plumbing. The live shared relay protocol remains retained under its UNKNOWN compatibility floor; rollback reverts the DTR-05 implementation atomically without erasing this historical owner decision. |
| Preserve, wire, or retire the account-migration group and pending-work manifests | DTR-09 disposition | Move Account | Accepted retention 2026-07-26 | `DTR09-AUTH-01`: the current authenticated project owner, acting as Move Account owner, designates both manifest islands as separately retained unfinished future Move Account functionality. Neither island is authorized for deletion or production wiring during this technical-debt rollout; their existing source and direct tests remain preserved. Revisit `DTR08-COMP-005` when group-state transfer implementation resumes and revisit `DTR08-COMP-006` when pending-work transfer/resume implementation resumes. Before either is wired, source-verify its design against the then-current bundle schema, encryption and device-security contracts, ownership/cutover rules, backward parsing, and availability-bounded end-to-end proof requirements. |
| Remove the deprecated `callGroupJoin` refusal wrapper while retaining test-only join/hydrate and live rejoin/full-config behavior | DTR-03 execution | Groups | Approved 2026-07-25 | `DTR03-AUTH-02`: the current authenticated project owner, acting as Groups owner, approved only the wrapper and its legacy test fragments, confirmed no supported external users, and accepted `DTR03-CALLER-01` as the complete supported external/path/git/raw caller floor. Full-config/native/generated/Go behavior and both DTR-10 islands are retained; rollback restores only the wrapper/test fragments. |
| Retire the test-only `joinGroup` island while preserving live invite/rejoin/full-config behavior | DTR-10 Plan 277 | Groups | Plan-green / closed 2026-07-26 | `DTR10-AUTH-01`: removed the old source, SUT-only suite, direct-join-only `commitFreshDirectJoin` declaration/implementation/fake/test fragments, and exact bookkeeping. Live invite admission, lifecycle rejoin, accepted-reentry retry/rollback, full-config Dart/native/Go join, stored keys, and epochs remain excluded and preserved. |
| Evidence-led disposition of `hydrateGroupsFromPeers` | DTR-10 Plan 278 | Groups | Plan-green / closed 2026-07-26 | `DTR10-AUTH-02`: removed the duplicate wrapper after current source/tests proved cold-start, resume, and retrier paths already run richer rejoin/inbox recovery for stored keyed groups. It did not acquire missing fresh-device group/key state; any such feature needs new authorization and a new plan. |
| Retire the dormant `leaveGroup` function/default-false branch | DTR-10 Plan 279 | Groups + database + release | Plan-green / closed 2026-07-26 | `DTR10-AUTH-03`: removed the dormant source/function, dedicated test, and default-false branch; rehomed the byte-identical last-admin message; migrated valuable host/device proof onto the durable path; and retained strict dissolved-local deletion, native leave, v103/v104 state, diagnostics, and the durable exit graph. |
| Retire the superseded leave/local-history coordinator | DTR-10 Plan 280 | Groups + database + release | Plan-green / closed 2026-07-26 | `DTR10-AUTH-04`: migrated 11 live-surface proofs to a production-shaped durable coordinator/runner fixture, then deleted only the obsolete coordinator, legacy fixture, and SUT-only blocks. |
| Retire the obsolete Dart group-key rotation leaf | DTR-10 Plan 281 | Groups + crypto + release | Plan-green / closed 2026-07-27 | `DTR10-AUTH-05`: removed only the old use case, refusal helper, raw command mapping, SUT-only tests/fragments, and bookkeeping; retained live generate/distribute/promote/update rotation, native/Go compatibility, and every persisted key generation. |
| Retire the duplicate Dart group-message payload | DTR-10 Plan 282 | Groups + crypto + release | Implemented 2026-07-27 | `DTR10-AUTH-06`: under the recorded copy/paste interpretation, removed only the unused Dart model/test/bookkeeping and preserved the live Go v3 envelope/parser/publish/receive protocol. Focused Dart/Go preservation, completeness, `groups`, `feature-host-all`, strict analysis, and scoped runtime-root closure are green; the plan is Plan-green and closed. |
| Retire the orphan `GroupInboxCursor` model | DTR-10 Plan 283 | Groups + database + release | Plan-green / closed 2026-07-27 | `DTR10-AUTH-07`: removed only the unused model and exact runtime-root declaration while retaining migration 066, cursor/receipt tables, DB helpers, repository page transactions, production composition, and inbox replay. The final root strict-analysis run reported no issues and diff hygiene passed. |
| Retain the legacy group-secret security scrub | DTR-10 Plan 284 / DEP-01 | Groups + crypto + security + release | Acceptance-verified terminal `Retained` 2026-07-27 | `DTR10-AUTH-08`: keep the startup scrub. The marker is not profile-qualified or owned by Move Account reset/import, and the background isolate does not invoke the foreground scrub; these remain unresolved, not repaired. A new removal plan is allowed only after Security + Release prove supported-data/marker and declared-backup completion, zero legacy rows, recovery safety, and crypto/client rollout compatibility. |
| Ownership of remaining test-only leaves | DTR-11 planning | Feature owners | Accepted and executed / Wave-accepted 2026-07-27 | `DTR11-AUTH-01`: the current authenticated project owner explicitly identified themself as owner and approved [Plan 287](287-remaining-test-only-leaves-disposition-tdd-plan.md)'s exact 11-path/1,065-LOC boundary: retire ten app sources and their ten SUT-only suites; relocate the 94-line push preview release calculator unchanged to `tool/telemetry/` while retaining its test and `runtime-telemetry` gate; migrate the Feed parity suite to `FeedStore`, remove only stale `ReactionDisplay` type assertions, and add the missing live Orbit/QR assertions; remove all 11 matching runtime-root declarations; remove only `GroupBacklogRetentionNotice.listSummary` plus the two exact orphan l10n keys in every locale; remove only the inert S15 retired-event filter/derived signal/print output; and add `test/unit/**` to `core-host-all` with an exact shell contract. `_RaceResult.relayProbeEligible`, relay/failure semantics, automatic identity restore, live UI behavior, native/Go/wire/storage/schema boundaries, and DTR-13's QA + release decision are explicitly excluded. The boundary was implemented exactly; all Plan 287 gates and the Wave-3 aggregate passed. [Stable evidence](evidence/dtr-wave3/README.md). Rollback is the exact inverse of this boundary and does not erase the owner decision. |
| Supported build profiles and debug/E2E entrypoints | DTR-13 planning | QA + release | Open | Wave 3's temporal dependency is cleared by its accepted aggregate. DTR-12 predecessor planning and this explicit QA + release owner decision remain open; no DTR-13 execution is authorized. |

---

## DTR-08 compatibility ledger

This is a removal-safety ledger, not authorization to remove compatibility
code. Every exact DTR-01 manifest record tagged `compatibility` is present
below as `DTR08-COMP-001` or `DTR08-COMP-002`. The additional rows split the
known downstream compatibility islands by behavior contract. `UNKNOWN` means
that current source has no supported-client/fleet floor or aggregate usage
evidence; under the safety invariants above, that state requires retention or
deferral rather than deletion.

| ID | Exact surface / source anchors | Downstream plan | Owner | Supported-version floor | Telemetry / usage evidence | Exact removal proof floor | Rollback | DTR-08 audit disposition / revisit condition |
|---|---|---|---|---|---|---|---|---|
| DTR08-COMP-001 | `lib/core/database/production_migration_registry.dart`: `productionCreateMigrations`, `productionUpgradeMigrations`; `lib/core/database/app_database_version.dart`: `currentIdentityDatabaseVersion` | All schema-bearing DTR/DEP work | Database + release | DB schema is v104; v96+ is the one-way supported release floor. This does **not** make v1-v95 migration code removable because supported profiles still require exact create/upgrade ordering and there is no fleet population proof. | `lib/main.dart` opens `identity.db` through the registry; startup readiness exists, but no aggregate installed-schema/adoption telemetry proves old steps unused. | Run `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart`, `flutter test --no-pub test/core/database/migrations`, explicit-target `integration_test/migration_database_sqlcipher_capability_test.dart`, and `./scripts/run_host_test_gates.sh core-host-all`. Removal additionally requires release-owner population evidence, a named step-specific forward-upgrade test, and forward-only recovery proof. | Restore migration files and exact registry order. Never schema-downgrade a profile; ship a forward fix for a released migration. | **Retained.** Revisit only when every supported install/backup floor, population evidence, upgrade proof, and rollback plan permits an exact step to retire. |
| DTR08-COMP-002 | Former `lib/features/conversation/presentation/widgets/recording_overlay.dart` export facade, retired by Plan 275; `compose_area.dart` and both affected tests now import `lib/shared/widgets/media/recording_overlay.dart` directly | DTR-04 | Conversation | **Resolved.** Source/API compatibility only; no release or wire floor applies. The zero-supported-import floor was reached by atomically retargeting production and tests before deleting the facade. | Checkpoint B1 recorded zero old-path imports while the facade and both compatibility records were still present; all three consumers used the shared implementation and the full three-file parity command passed 180/180. Checkpoint B2 then removed only the facade and its two runtime-root records. Runtime telemetry is not applicable. | Plan 275 passed the fail-closed zero-import proof, exact shared-import proof, pre-delete B1 and post-delete B2 parity, `runtime-roots`, `1to1`, strict analysis, and the 821-path `feature-host-all`. The Wave 1 aggregate `host-all` subsequently passed and is recorded above. | Restore the one-line facade and both compatibility records first, then restore prior imports together; never restore an old import without its facade. | **Facade retired / Wave-accepted under DTR-04.** The shared recording overlay and its live consumers are retained. |
| DTR08-COMP-003 | Former dormant chat-only `_tryRelayProbeSend` in `send_chat_message_use_case.dart`, removed by Plan 276; live shared `relayProbeSendAttempts` consumed by introduction delivery and delete-message flows; live `P2PService.probeRelay` implementation, Dart/native `relay:probe` dispatch, and `go-mknoon/bridge/bridge.go` `RelayProbe` | DTR-05 | Transport + protocol | **UNKNOWN for protocol retirement; resolved for the private helper leaf.** No supported-client/protocol retirement floor or fleet adoption evidence exists. The former dormant chat helper is not equivalent to the live shared relay protocol. | The fail-closed pre-edit Plan 276 census proved one private helper declaration, zero executable references/tear-offs, no Dart part linkage, and no VM entrypoint. Post-edit source and ratchet proof confirms the helper is absent and exactly three generated l10n identities remain. `relayProbeSendAttempts` and the introduction/delete/global protocol paths remain live and outside the chat-leaf retirement. | `DTR05-AUTH-01 leaf-only two-peer waiver`: the sole project authority approved replacing an unobservable two-peer deletion leg with Plan 276's causal inventory/source-removal RED, M-1 through M-4, exact FDC-03 zero-probe/custody sentinels, live introduction/delete/Dart bridge preservation tests, `./scripts/run_test_gates.sh 1to1`, explicit-supported-Android `transport`, and `./scripts/run_host_test_gates.sh feature-host-all`. Preserve the four existing Go smoke selectors with exact commands: `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -v -run '^TestForegroundRelayProbeIsNotRequiredForActiveSendPath$' -count=1)`, `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -v -run '^TestDialPeerViaRelayTriesAllAddresses$' -count=1)`, `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -v -run '^TestDialPeerViaRelay_TriesSecondRelayWhenFirstFails$' -count=1)`, and `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -v -run '^TestDialPeerViaRelay_SingleRelayStillWorks$' -count=1)`; protected staged/unstaged no-diff guards are the causal Go/native preservation proof. Any future live protocol-boundary change still requires its own owner decision, supported-client floor, exact Go/native causal tests, and named availability-bounded two-peer proof. | Revert the entire atomic Plan 276 implementation change, including helper/suppression/inventory/test/status bookkeeping, while preserving `DTR05-AUTH-01` as historical owner evidence. Do not remove or restore the live shared attempt constant. Protocol rollback remains a separate Dart-interface/service/bridge/Go/live-consumer change. | **Private chat-helper removed / Plan-green under Plan 276; shared attempt constant and global relay protocol retained.** `DTR05-AUTH-01` remains historical authorization for only the helper leaf and does not authorize protocol retirement. |
| DTR08-COMP-004 | Retired local-refusal `callGroupJoin` wrapper from `bridge_group_helpers.dart`; retired test-only `joinGroup` island and direct-only `commitFreshDirectJoin` repository seam; retired duplicate `hydrateGroupsFromPeers` wrapper; live `callGroupJoinWithConfig` and `rejoinGroupTopics` used by startup/resume/UI/invite flows | DTR-03 / DTR-10 | Groups | **Resolved for the three isolated Dart leaves.** `DTR03-AUTH-02` authorized the refusal-wrapper retirement; `DTR10-AUTH-01` authorized the direct-join island retirement; `DTR10-AUTH-02` authorized the hydrate-wrapper retirement after replacement sufficiency was proven. The full-config `group:join` floor remains live. | Plans 277 and 278 used fail-closed owned-Dart censuses and causal removal contracts. Final censuses are zero for all retired identifiers and old source imports; `rejoinGroupTopics` and `callGroupJoinWithConfig` retain current production callers. | Plans 274, 277, and 278 preserve exact full-config invite/rejoin/bridge behavior, startup/resume/retrier recovery, protected native/generated/Go paths, binding verification, runtime-root inventory, curated groups coverage, and justified affected host sweeps. A command-mapping change still requires its own platform-dispatch plan. | Roll back each leaf independently: restore only its source/API/test/fake/inventory fragments. Never remove or change live full-config `group:join`, recovery orchestration, accepted-reentry coordination, stored keys, or epochs while restoring a retired leaf. | **All three isolated Dart leaves retired / Plan-green under Plans 274, 277, and 278.** Live invite/rejoin/recovery and the full-config bridge/native/Go path are retained. |
| DTR08-COMP-005 | `migration_group_manifest_builder.dart`, `migration_group_manifest_validator.dart`, and `domain/models/migration_group_manifest.dart` | DTR-09 | Move Account | **UNKNOWN / no manifest schema floor.** The exact group-manifest island has no proven production bundle caller; dead-call evidence is not a product decision. | Direct builder/validator tests are the only proven consumers; no production telemetry is possible while unwired. | Require `! rg -n -e 'migration_group_manifest_builder\.dart' -e 'migration_group_manifest_validator\.dart' -e 'migration_group_manifest\.dart' lib --glob '!lib/features/account_migration/application/migration_group_manifest_builder.dart' --glob '!lib/features/account_migration/application/migration_group_manifest_validator.dart' --glob '!lib/features/account_migration/domain/models/migration_group_manifest.dart'`; run `flutter test --no-pub test/features/account_migration/application/migration_group_manifest_builder_test.dart test/features/account_migration/application/migration_group_manifest_validator_test.dart`, full `account_migration_bundle_transfer_test.dart` and `account_migration_end_to_end_test.dart`, and `./scripts/run_test_gates.sh move-feature`; run `./scripts/run_test_gates.sh groups` only if group behavior is wired/transferred. Wiring must add exact schema/backward-parse and encryption/device proof; current tests cannot authorize a nonexistent bundle slot. | A retirement rollback restores model/builder/validator/tests. A wiring rollback must preserve backward parsing and not strand an emitted bundle. | **Retained under `DTR09-AUTH-01`.** Preserve the island and its direct tests without production wiring during this rollout. Revisit separately when group-state transfer implementation resumes; retention is not evidence that the current design is integration-ready. |
| DTR08-COMP-006 | `migration_pending_work_manifest_builder.dart`, `migration_pending_work_manifest_validator.dart`, and `domain/models/migration_pending_work_manifest.dart`, including queued group retry/inbox/key-repair/membership/reaction classifications | DTR-09 | Move Account | **UNKNOWN / no pending-work schema or bundle-slot floor.** Transfer protocol v2/min importer 2 does not prove this separate unwired manifest removable. | Direct tests and the Move gap audit show the island; no live caller or telemetry exists. | Require `! rg -n -e 'migration_pending_work_manifest_builder\.dart' -e 'migration_pending_work_manifest_validator\.dart' -e 'migration_pending_work_manifest\.dart' lib --glob '!lib/features/account_migration/application/migration_pending_work_manifest_builder.dart' --glob '!lib/features/account_migration/application/migration_pending_work_manifest_validator.dart' --glob '!lib/features/account_migration/domain/models/migration_pending_work_manifest.dart'`; run `flutter test --no-pub test/features/account_migration/application/migration_pending_work_manifest_builder_test.dart test/features/account_migration/application/migration_pending_work_manifest_validator_test.dart`, full `account_migration_bundle_transfer_test.dart` and `account_migration_end_to_end_test.dart`, `./scripts/run_test_gates.sh move-feature`, and `./scripts/run_test_gates.sh completeness-check`. If wiring changes queued behavior, additionally run the exact `1to1`, `groups`, `posts`, and `intro` gates plus new causal availability-bounded transfer/encryption proof; current device tests do not prove this unwired schema. | Retirement restores the isolated files/tests. Wiring rolls sender/receiver schema and parsing back atomically or keeps backward parsing. | **Retained under `DTR09-AUTH-01`.** Preserve the island and its direct tests without production wiring during this rollout. Revisit separately when pending-work transfer and new-phone resume implementation resumes; retention is not evidence that the current design is integration-ready. |
| DTR08-COMP-007 | Retired legacy `leaveGroup` source/function and default-false branch under Plan 279; live UI constant `lastAdminLeaveBlockedMessage` rehomed to `group_exit_policy.dart`; retired test-only `leave_group_and_delete_local_history_use_case.dart` under Plan 280; live v103/v104 exit coordinator/runner, native `group:leave`, and diagnostics | DTR-10 | Groups + database + release | **Resolved for the two isolated Dart retirement slices.** The global DB release floor is v96, but the retained native group-wire/client floor is **UNKNOWN**. v103/v104 durable state remains live and cannot be downgraded. | The Plan 279 fail-closed census proves the old source/function/imports, default-false flag, and direct manual proof route are absent; Plan 280's contract proves the superseded coordinator/fixture are absent. The rehomed constant remains live in Group-info and Orbit UI, the v103/v104 coordinator/runner remains wired, and the H-01/GM-015 Android closure preserved exact durable/native behavior. No fleet client-floor evidence authorizes broader native or persistence retirement. | Plans 279 and 280 passed their causal runtime-root removal contracts, exact delete/policy/actions/coordinator/runner and UI preservation suites, v103/v104 and SQLCipher sentinels, Dart/native/Go leave tests, `./scripts/run_test_gates.sh groups`, and justified `./scripts/run_host_test_gates.sh feature-host-all`; Plan 279 additionally passed `private_voluntary_leave_convergence` and `gm015` on one physical Android plus two emulators. A future native, schema, or durable-exit change still requires its own causal plan and availability-bounded proof. | Roll back each retired leaf independently: restore only Plan 279's old source/test/branch or Plan 280's coordinator/fixture/test fragments while preserving the rehomed compatibility constant and modern durable graph. Never drop or downgrade v103/v104; released persistence failures require a forward fix. | **Both bounded Dart leaves retired / Plan-green and closed under Plans 279 and 280.** The last-admin compatibility rule, durable v103/v104 state, diagnostics, native leave, and valuable host/device proof remain retained. |
| DTR08-COMP-008 | Former test-only `rotate_group_key_use_case.dart`, local-refusal `callGroupRotateKey`, and Dart `group:rotateKey` mapping, retired under Plan 281; retained Go `GroupRotateKey` export; live `rotate_and_distribute_group_key_use_case.dart` plus generate/distribute/promote/update bridge and Go crypto/key-epoch paths | DTR-10 | Groups + crypto + release | Key epoch is persisted protocol state, not a supported-client floor; the release/wire floor is **UNKNOWN**. | The Plan 281 removal contract now requires the old Dart source/helper/mapping/tests to remain absent and the raw command to return `UNKNOWN_COMMAND` before native invocation. Live rotation/bridge events remain, but no fleet version/adoption evidence authorizes native/Go protocol retirement. | Run `flutter test --no-pub test/features/groups/application/legacy_group_key_rotation_removal_contract_test.dart`; the exact `DTR10-ROT-02` and 67-command selectors in `go_bridge_client_test.dart`; the live restore/promotion, retention, generate/update bridge selectors; `./scripts/verify_gomobile_bindings.sh all`; the exact retained Go fail-closed/update/key-epoch tests; `./scripts/run_test_gates.sh groups`; and `./scripts/run_host_test_gates.sh feature-host-all`. | Restore only the retired Dart wrapper/helper/mapping/tests for leaf rollback. Live rotation rollback is atomic across Dart/Go and must never regress an already-promoted epoch. | **Dart legacy leaf retired under Plan 281; native/Go compatibility and live rotation retained.** |
| DTR08-COMP-009 | Retired test-only Dart `group_message_payload.dart`; live `go-mknoon/internal/group_envelope.go` v3 parser and `go-mknoon/node/pubsub.go` publish/receive wire path | DTR-10 / DTR-11 | Groups + crypto + release | Live wire schema is v3, but supported installed-client release floor is **UNKNOWN**; the literal version is not population evidence. | The retired Dart leaf has no production importer. Live Go parse/publish events exist, but no mixed-version/adoption counts prove v3 wire retirement safe. | For the Dart leaf, require `! rg -n "import .*group_message_payload\\.dart" lib` and `flutter test --no-pub test/features/groups/domain/models/group_message_payload_removal_contract_test.dart`. Preserve the live protocol with `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./internal -count=1)`, `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^TestGK029' -count=1)`, `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^TestGK030' -count=1)`, `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run '^TestGP023' -count=1)`, and `./scripts/run_test_gates.sh groups`; a wire change additionally requires `FLUTTER_DEVICE_ID=<explicit-discovered-id> ./scripts/run_test_gates.sh transport`, `./scripts/run_host_test_gates.sh feature-host-all`, a new named native/Go compatibility test, and a new named availability-bounded mixed-client/two-peer group compatibility proof. | Restore the Dart leaf/test independently. A wire rollback must preserve mixed clients and be atomic; leaf removal must never be described as protocol retirement. | **Dart duplicate retired under Plan 282; Go v3 wire/parser retained.** |
| DTR08-COMP-010 | Retired orphan `group_inbox_cursor.dart` model under Plan 283; live migration 066 `group_sync_receipts`, DB helpers, repository page transaction, account-migration metadata sibling, and `main.dart` wiring | DTR-04 / DTR-10 | Groups + database + release | **Resolved for the isolated model leaf.** Migration 066 predates the v96 release floor, but its live tables persist in supported profiles; no model-leaf result supplies a storage-removal or population floor. | Plan 283's causal contract proves the 31-line model and exact runtime-root declaration are absent while the migration, helpers, repository/drain transactions, account-migration metadata sibling, and production injection remain. No fleet cursor-population evidence authorizes storage removal. | Plan 283 passed the exact `DTR-10 retires orphan GroupInboxCursor model only` and DTR-04 ownership sentinels; migration/helper/repository/drain/full-chain preservation; isolated `runtime-roots`; `groups`; `feature-host-all`; final strict analysis; and diff hygiene. No current test authorizes table mutation: a persistence change still requires a new forward migration, explicit-target SQLCipher proof, and the justified core/feature family gates. | Restore only `group_inbox_cursor.dart` and its exact DTR-01 runtime-root declaration for leaf rollback; there is no dedicated model unit test. Never drop or mutate the live table without a new migration and forward recovery. | **Model leaf retired / Plan-green and closed under Plan 283.** Migration 066, the persisted cursor/receipt contract, DB helpers, repository/drain transactions, production composition, and account-migration metadata remain retained. |
| DTR08-COMP-011 | `legacy_group_secret_storage_scrub.dart`; foreground startup call in `main.dart`; background group-key hydration; Move Account database replacement and secure-storage registry/reset; secure-reference write/hydration in group and media-attachment repositories; `go-mknoon/crypto/group.go`, `crypto/sign.go`, `internal/group_envelope.go`, and retained node key epochs | DTR-10 / DEP-01 | Groups + crypto + security + release | Global DB floor is v96, but completion across current data/marker namespaces, database-replacement or release-declared backup flows, and the crypto-format negotiation floor are **UNKNOWN**. | Scrub start/success/skip events and moved-row count are debug/test diagnostics only, not release telemetry. Android system backup/device transfer is disabled and iOS secure values are device-only. The fixed marker is not owned by Move Account registry/reset, an active database can be replaced after foreground startup, and the background handler can hydrate a legacy plaintext row without invoking the scrub. No fleet aggregation/adoption evidence exists. | For retained-baseline acceptance, run [Plan 284](284-legacy-group-secret-security-scrub-retention-evidence-tdd-plan.md) TC-284-01 through TC-284-06 exactly: foreground order/declaration audits, 17 focused scrub/repository/secure-upload/migration tests, marker/import/background/backup-policy source audits, `./scripts/run_test_gates.sh groups`, strict analysis, and diff hygiene. A future removal or format change additionally requires Security + Release population/recovery evidence, a new causal plan, exact crypto/Go proof, a named availability-bounded mixed-client/device proof, and the affected family gates; the acceptance commands do not authorize it. | Restore the scrub before release; never roll back by writing plaintext. Format changes require dual-read/old-key retention or a forward migration and atomic Dart/Go rollout. | **Acceptance-verified retained under Plan 284 on 2026-07-27.** Focused and curated gates prove current local preservation only, not operational sufficiency. Marker/import/background alignment remains unresolved; retirement still requires the owner evidence package and new authorization. |

The table above retains each compatibility proof floor and is updated when a
downstream owner decision or implementation resolves an audited leaf. The
following overlay provides a compact current DTR-10 status without weakening
those proof floors:

| Compatibility row | Current DTR-10 disposition |
|---|---|
| `DTR08-COMP-004` | **Plans 277 and 278 are Plan-green and closed.** Plan 277 retired the test-only `joinGroup` island and its direct-only repository seam; Plan 278 retired only the separate hydrate wrapper. Live invite admission, cold-start/resume/retrier recovery, full-config join, native/Go handlers, keys, and epochs remain preserved. |
| `DTR08-COMP-007` | **Plans 279 and 280 are Plan-green and closed.** Plan 280 retired the superseded coordinator after migrating valuable UI proof to the durable fixture; Plan 279 retired the dormant `leaveGroup` source/default-false branch, rehomed the last-admin message, and migrated the remaining host/device proof callers. The last-admin rule, durable v103/v104 state, diagnostics, native leave, and valuable proof remain preserved. |
| `DTR08-COMP-008` | **Plan-green and closed under Plan 281.** The obsolete Dart rotation source/helper/mapping/tests are retired; native/Go compatibility, live generate/distribute/promote/update rotation, and persisted key generations remain retained. |
| `DTR08-COMP-009` | **Implementation-complete under Plan 282.** The scoped plan is Plan-green and closed after retiring only the duplicate Dart payload/test; the Go v3 wire/parser/publish/receive boundary remains retained. |
| `DTR08-COMP-010` | **Plan-green and closed under Plan 283.** The orphan model and exact runtime-root declaration are retired; migration 066, DB helpers, production injection, account-migration metadata, and the persisted cursor/receipt boundary remain retained. |
| `DTR08-COMP-011` | **Acceptance-verified retained under Plan 284 and `DTR10-AUTH-08`.** Local preservation is green, but the unowned fixed marker, post-startup database replacement, background-isolate bypass, and absent fleet completion evidence prevent an operational-sufficiency or removal claim. |

DTR-10 is terminally complete: its seven removal plans are Plan-green/closed
and Plan 284 is acceptance-verified terminal `Retained`. No broader
compatibility surface is deletion-ready. Plan 287 subsequently closed DTR-11,
and the separate aggregate accepted Wave 3 without changing any retained
compatibility boundary.

---

## Candidate reconciliation ledger

Update totals after each accepted wave. Never report only deleted LOC; retained
and newly wired code are part of the safety result.

| Outcome | Files | LOC | Evidence |
|---|---:|---:|---|
| Removed | 59 | 14,067 | Conservative accepted-wave tally. The prior Wave 0–2 baseline was 26 files / 9,308 LOC: DTR-02 retired 3 files / 1,179 LOC; DTR-03 retired 3 whole files plus deprecated wrapper/test fragments / 339 lines; DTR-04 retired 12 whole files / 1,079 LOC plus 57 orphan catalog/generated-l10n lines; DTR-05 removed the 135-line dormant helper/comment block plus its 22-line suppression record; and DTR-07 retired 8 whole files / 6,255 lines, plus 147 orphan ARB/generated-l10n lines and 95 indirect test/harness lines. Accepted Wave 3 adds only exact whole-file retirements to avoid overclaiming: DTR-10 retired 13 files / 1,940 LOC, and DTR-11 retired 20 files / 2,819 LOC (ten 971-line app sources plus ten 1,848-line SUT-only suites). DTR-11's byte-identical 94-line tooling relocation, field/l10n/routing/test-assertion fragments, rewrites, additions, runtime-root/gate/documentation bookkeeping, and preservation tests are excluded. Per-plan proof lives in Plans 273–287; Wave 0–3 acceptance evidence is linked above. |
| Wired into supported behavior | 0 | 0 | — |
| Retained with owner/removal condition | 32 | 10,503 | DTR-01 keeps `smoke_test_runner.dart` (225 LOC) as `retained-unresolved`; `DTR06-AUTH-01` retains the 24-file Posts UI island (6,993 LOC) plus `post_pass_follow_on_support.dart` (192 LOC); `DTR09-AUTH-01` separately retains the six group/pending-work manifest source files (3,093 LOC) for future Move Account completeness work |
| Deferred with revisit condition | 0 | 0 | — |
| Classified candidates awaiting downstream execution or disposition | 0 | 0 | DTR-10 and DTR-11 have terminal accepted dispositions. The advisory manifest still labels the retained 192-line post helper as a candidate, but `DTR06-AUTH-01` supplies its terminal roadmap disposition and it is counted in the retained row above. |
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
