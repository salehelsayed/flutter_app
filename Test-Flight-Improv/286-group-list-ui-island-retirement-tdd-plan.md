# 286 - Group-List UI Island Retirement (DTR-07)

Status: Plan-green
Type: Modification
Spec: free-text DTR-07 item (roadmap DTR-07 registry row, Wave 2)
Classification: implementation-complete — the reviewed exact retirement
boundary is implemented and its causal, preservation, curated, and affected
family evidence is recorded below. `DTR07-AUTH-01` remains the authorization
of record.
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-26 CEST | Evidence Collector | `group_list_wired.dart`, `group_list_screen.dart`, `group_card.dart`, `orbit_screen.dart`, `orbit_wired.dart`, `orbit_view_toggle_button.dart`, `orbit_view_mode.dart`, `group_row.dart`, `main.dart`, `lib/core/debug/**`, `lib/smoke_test_*.dart` | Island is production-unreachable; the shipped "classic list" is Orbit's `allChats` view mode built in-place, not this island | Enumerate deletion fallout |
| 2026-07-26 CEST | Evidence Collector | `runtime_roots.json`, `runtime_root_inventory.dart`, `check_runtime_root_inventory.sh`, `run_test_gates.sh`, 8 indirect guard tests, 3 ARB locales, `l10n_integrity_test.dart` | Fallout is entirely bookkeeping: 1 manifest, 1 curated array, 8 guard/harness test files, 24 ARB entries. No production behavior edge | Decide coverage-migration versus coverage-retirement per harness |
| 2026-07-26 CEST | Planner | `format_message_time.dart`, `group_row.dart:55`, `group_list_screen.dart:476`, `group_conversation_polish_proof_test.dart`, plans 275/276/283 | Orbit's replacement row renders **relative** time (`formatRelativeTime`), not locale-aware `DateFormat.jm` — so the device proof's group-list ICU leg retires with its surface rather than migrating. Test-lock that difference | Emit contract; block on `DTR07-AUTH-01` |
| 2026-07-26 CEST | TDD Reviewer | Full plan; runtime-root tool/test; ARB/generated l10n; Plans 279/280; roadmap/index/current C4 and inventory docs | `plan-fixes-required` before execution: isolate inventory proof from unrelated deletions, bound staged and unstaged over-deletion, make TC-286-12 positive as well as negative, preserve the Orbit relative-time contract and surviving ICU names, enumerate all current docs, and invoke `flutter gen-l10n` literally. Those necessary fixes were applied; all five review lenses then cleared | Execute the corrected contract |

## Problem And Evidence

- Behavior to improve: retire the three-file Group-list UI island that the Orbit
  redesign superseded, without touching any surface a user can reach.
- Impact: 2,035 production lines are compiled, analyzed, and kept in sync with
  live surfaces by five source-scanning guard tests, while no navigation reaches
  them. Every future group change pays maintenance on a dead second
  implementation, and the roadmap's own `DTR08-COMP-007` row already mislabels
  one of its dead call sites as live (corrected by TC-286-12).
- Confirmed current gap: the island is unreachable from every runtime root.
  - `GroupListWired` is declared at
    `lib/features/groups/presentation/screens/group_list_wired.dart:55` with
    **zero** construction sites anywhere in `lib/`.
  - `GroupListScreen` (`group_list_screen.dart:19`) has exactly one `lib/`
    consumer, `group_list_wired.dart:1198` — island-internal.
  - `GroupCard` (`group_card.dart:13`) has exactly one `lib/` consumer,
    `group_list_screen.dart:350` — island-internal. (`SettingsGroupCard` in
    `lib/features/settings/presentation/widgets/settings_group.dart:11` is an
    unrelated class and is **not** in scope.)
  - `lib/main.dart` contains no reference to any island symbol or path.
  - `lib/core/debug/**` (31 files) and all three `lib/smoke_test_*.dart`
    entrypoints contain no reference.
  - Dynamic reachability is categorically closed, not merely grep-closed: `lib/`
    has **zero** hits for `routes:`, `onGenerateRoute`, `pushNamed`,
    `deferred as`, and `dart:mirrors`. The app has no named-route table, so no
    string-keyed path to the island can exist, and no barrel re-exports it.
  - A recomputed transitive import closure from `lib/main.dart` plus the three
    `lib/smoke_test_*.dart` roots resolves to 988 files; none of the three
    island files appears.
- Live replacement surface (the "classic list view" users actually reach): the
  physical top-left `OrbitViewToggleButton`
  (`lib/features/orbit/presentation/widgets/orbit_view_toggle_button.dart:43`
  builds the `Positioned`; its `ValueKey('orbit-view-toggle')` is at `:50`) calls `_onToggleView`
  (`lib/features/orbit/presentation/screens/orbit_wired.dart:2413`), a pure
  `setState` flipping `OrbitViewMode` (`lib/features/orbit/domain/models/orbit_view_mode.dart:10`). The list is
  built **in place** by `_buildAllChatsListSurface`
  (`lib/features/orbit/presentation/screens/orbit_screen.dart:997`); group rows
  render through `_buildGroupRow` (`:1519`) → `SwipeableFriendRow` (`:1526`) →
  `GroupRow` (`lib/features/orbit/presentation/widgets/group_row.dart:15`). No
  navigation and no island symbol participates.
- Existing coverage of the replacement:
  `test/features/orbit/presentation/screens/orbit_view_split_test.dart::top-left toggle switches to the all-chats view`
  and the Orbit group-row suites already prove the live surface.
- Missing coverage: HEAD has no causal contract requiring the island's absence,
  no l10n contract for its eight orphan keys, and no source census bounding the
  removal.
- Refuted (do NOT re-introduce):
  - "The Group-list island is the classic list view behind Orbit's top-left
    button" — **refuted**. That button toggles `OrbitViewMode` in place
    (`orbit_wired.dart:2413`, `orbit_screen.dart:700`); it performs no
    navigation and reaches no island file.
  - "`lastAdminLeaveBlockedMessage` is live in Group-list" (asserted by the
    roadmap `DTR08-COMP-007` row) — **refuted**. `group_list_wired.dart:953`
    and `:999` are dead code. The genuine live consumers are
    `group_info_wired.dart:560`, `:619` and `orbit_wired.dart:3131`; the
    constant is declared at `leave_group_use_case.dart:8` and is untouched by
    this plan.
  - "`kDeclineUndoWindow` couples the island to Orbit" — **refuted**.
    `group_list_wired.dart:128` is a `static const` on the **private**
    `_GroupListWiredState` (`:120`), not externally addressable;
    `orbit_wired.dart:372` is an independent duplicate declaration.
- Pre-authorization finding: no evidence gaps remained; the only open item was
  the product decision, resolved by `DTR07-AUTH-01` on 2026-07-26.
- Affected production, test, gate, and documentation files:
  the three island sources; `tool/runtime_roots/runtime_roots.json`;
  `scripts/run_test_gates.sh` (`GROUP_TESTS`); five direct island test files;
  eight indirect guard/harness test files; three ARB locales plus the generated
  l10n API (`app_localizations.dart` plus its three locale subclasses);
  `test/l10n/l10n_integrity_test.dart`;
  `test/unit/runtime_root_inventory_test.dart`;
  `test/features/orbit/presentation/screens/orbit_wired_test.dart`;
  `Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md`;
  `Test-Flight-Improv/279-dormant-group-leave-path-removal-tdd-plan.md`;
  `Test-Flight-Improv/280-superseded-leave-local-history-coordinator-removal-tdd-plan.md`;
  `Test-Flight-Improv/codebase-test-inventory.md`;
  `Test-Flight-Improv/06-dead-code-lib.md`; `C4/file-structure.md`;
  `C4/components.md`;
  `lib/features/groups/presentation/widgets/contact_picker_row.dart`;
  `Test-Flight-Improv/00-INDEX.md`.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `b04644b8f017826a`; current
  (`confidence=anchored`). The `graphify-arch/.needs_incremental_refresh`
  backstop marker was present at planning start and
  `./graphify-arch/refresh_arch_graph.sh --incremental` was run before the query.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "GroupListWired group_list_wired.dart group_list_screen.dart GroupCard retirement reachability and Orbit allChats replacement surface" --profile tdd --budget 700`.
- Anchors:
  `GroupListWired` → `lib/features/groups/presentation/screens/group_list_wired.dart:55`;
  `_buildGroupCard` → `lib/features/groups/presentation/screens/group_list_screen.dart:331`;
  `GroupCard` → `lib/features/groups/presentation/widgets/group_card.dart:13`
  (community `Group & Friend Row Widgets`).
- Surfaced proof/gate files:
  `test/features/groups/presentation/group_list_wired_test.dart` with its
  `GROUP_TESTS` and `AUTO_FEATURE_HOST` gate mapping.
- Graph gaps that required raw source search: the compact result surfaced
  neither the Orbit `allChats` replacement topology, the runtime-root manifest
  bookkeeping, the five source-scanning guard tests, nor the ARB/l10n fallout.
  All were derived from current source.
- Reuse rule: anchors may be handed to review/execution as search starting
  points; every conclusion still requires current-source or command evidence.

## Authorization Recorded (`DTR07-AUTH-01`)

The roadmap `DTR07-AUTH-01` decision-ledger row is **Approved 2026-07-26**.
The current authenticated project owner, as the sole implementation authority
and acting as Product + Groups owner, approved this plan's exact boundary.

`DTR07-AUTH-01` records, in the `DTR03-AUTH-01/02` and `DTR05-AUTH-01` style:

1. Approval of the **exact** removal set in *Scope Contract And Guard → In
   scope* — three sources, five SUT-only tests, three manifest declarations,
   one curated-array entry, and these **eight** ARB keys across all three
   locales (`app_en.arb`, `app_ar.arb`, `app_de.arb` — 24 entries total), each
   verified to have exactly one non-generated `lib/` call site, all inside the
   island: `group_card_no_messages`, `groups_title`, `groups_joined`,
   `groups_no_joined`, `groups_empty_title`, `groups_empty_desc`,
   `groups_pending_invites`, `groups_unknown_sender`. A receipt that does not
   name these keys does not authorize their removal.
2. Explicit **non**-authorization of: `SettingsGroupCard`, the live
   `lastAdminLeaveBlockedMessage` constant and its two live consumers,
   `GroupBacklogRetentionNotice` (deferred below), Orbit/Feed/`main.dart`
   group-entry wiring, and every group backend, listener, notification, and
   persistence boundary.
3. The disposition of the **retired device-proof leg** described under
   *Coverage migration versus coverage retirement* — the `de group-list row`
   ICU assertion is retired with its surface rather than migrated, because the
   replacement surface deliberately renders relative time. This is an
   authorization-visible product statement, not a silent test deletion.

Execution must still re-verify the receipt against this plan's In-scope set
before the first edit (the two prerequisite commands in *Acceptance Gates*). A
receipt that does not name all eight l10n keys does not authorize their removal.

## Coverage Migration Versus Coverage Retirement

The roadmap Wave 2 exit contract requires: *"Still-relevant tests have moved
to Feed/Orbit and current group navigation before any DTR-07 retired UI tests
are deleted."*
Each island-dependent assertion is dispositioned exactly once:

| Island assertion | Disposition | Basis |
|---|---|---|
| `group list loading renders without overflow` — `ValueKey('group-loading-row-0')` (`group_list_screen.dart:492`) | **Retire — already covered on the live surface.** Do NOT retarget | `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart:219` already asserts `orbit-loading-row-0/-1/-2` render via its local `buildOrbitScreen(showLoadingPlaceholders: true)` harness (`:88`, `:146`). Retargeting is also mechanically wrong: `_OrbitLoadingRow` (`orbit_screen.dart:1573`) is **private**, so it can only be reached by pumping a whole `OrbitScreen`, and `integration_test/` cannot import the `test/`-side Orbit pump harness |
| `de group-list row renders 24-hour time, no AM/PM` (`group_conversation_polish_proof_test.dart:151`) | **Retire with the surface**, and test-lock the difference (TC-286-11) | `GroupListScreen._formatTime` (`:476`) uses `intl.DateFormat.jm(locale)`; the replacement `GroupRow` (`group_row.dart:55`) deliberately uses `formatRelativeTime` ("2m ago"). There is no equivalent behavior to migrate |
| The real-iOS ICU / locale claim itself | **Already carried elsewhere** — no coverage loss | The same proof file retains three conversation legs (`:105`, `:121`, `:135`); `formatMessageTime`'s live `DateFormat.jm` carriers remain `feed_wired.dart:887`, `:906`, and both thread groupers |
| 72 `testWidgets` across the five direct island suites | **Retire with the SUT** | Every behavior has a dedicated live owner: invite accept/decline outcomes in `accept_pending_group_invite_use_case_test.dart` and `decline_pending_group_invite_use_case_test.dart`, exit/recovery in the Orbit sole-admin suites, stuck-rejoin and self-removed-delete in the Orbit and use-case suites |

## Scope Contract And Guard

In scope:

- Delete exactly three production sources:
  `lib/features/groups/presentation/screens/group_list_wired.dart`,
  `lib/features/groups/presentation/screens/group_list_screen.dart`,
  `lib/features/groups/presentation/widgets/group_card.dart`.
- Delete exactly five SUT-only test files:
  `test/features/groups/presentation/group_list_wired_test.dart`,
  `group_list_screen_test.dart`, `group_list_screen_bidi_test.dart`,
  `group_card_test.dart`, `group_card_bidi_test.dart`.
- Remove exactly three `explained-root` declarations from
  `tool/runtime_roots/runtime_roots.json` (whose own `condition` field reads
  *"Revisit only in the owning downstream DTR plan with replacement or removal
  proof"* — this plan is that owner).
- Remove exactly one `GROUP_TESTS` entry at `scripts/run_test_gates.sh:368`.
- Edit exactly eight indirect guard/harness test files (enumerated in
  *Implementation Steps* step 4).
- Remove exactly eight orphan l10n keys from all three ARB locales and
  regenerate `app_localizations.dart`, `app_localizations_en.dart`,
  `app_localizations_de.dart`, and `app_localizations_ar.dart`.
- Add the causal absence contract to `test/unit/runtime_root_inventory_test.dart`
  and the causal l10n contract to `test/l10n/l10n_integrity_test.dart`.
- Add the TC-286-11 relative-time preservation sentinel to
  `test/features/orbit/presentation/screens/orbit_wired_test.dart`.
- Correct the `DTR08-COMP-007` "live in Group-list" claim and update the DTR-07
  roadmap rows. Remove the retired surface/test from the still-executable
  contracts in Plans 279 and 280; retain their Group Info and Orbit proof.
- Remove the island from the current C4 component catalog and dead-code report,
  and update the existing Plan-286 index row in place.

Must preserve:

- Orbit's `allChats` classic list toggles both ways and survives re-entry reset →
  `orbit_view_split_test.dart::top-left toggle switches to the all-chats view`,
  `::toggle returns to the Inner-Circle view`,
  `::non-null initialFilterTab forces the all-chats view`.
- Orbit's classic list renders group rows with structured previews and ordering →
  `orbit_wired_test.dart::displays group rows when groups exist`,
  `::displays structured group rows with latest message preview`,
  `::interleaves groups and friends sorted by last activity`.
- Group chat opens from the live entry surfaces →
  `orbit_wired_test.dart::orbit entry keeps group long-press actions aligned with the shared conversation surface`,
  `::orbit entry keeps group reaction inspection aligned with the shared conversation surface`,
  `::accepting a pending group invite from Intros joins the group`.
- The live sole-admin exit guidance that consumes
  `lastAdminLeaveBlockedMessage` →
  `orbit_wired_test.dart::first sole-admin Leave opens recovery without destructive work`,
  `::sole admin dissolve preserves history before optional local delete`.
- The group-media coordinator wiring baseline still enumerates every remaining
  live path →
  `group_media_reliability_wiring_test.dart` (5 → 4 paths, TC-286-07).
- The group-exit diagnostic application boundary on its remaining live surfaces →
  `group_exit_diagnostic_wiring_test.dart` (3 → 2 paths, TC-286-08).
- Flow-event privacy scrubbing on every remaining event row →
  `flow_event_emitter_test.dart` (TC-286-09).
- Ambient-background chat-suppression leakage guard, including the live
  `orbit_screen.dart` entry → `ambient_background_test.dart` (TC-286-10).

Hard `Do not`:

- Do not touch `SettingsGroupCard`
  (`lib/features/settings/presentation/widgets/settings_group.dart:11`) or its
  three call sites; the name collision is not a relationship.
- Do not touch `lib/features/groups/application/leave_group_use_case.dart`, the
  `lastAdminLeaveBlockedMessage` constant, or either live consumer. DTR-10 Plan
  279 owns that symbol.
- Do not touch `orbit_screen.dart`, `orbit_wired.dart`, `group_row.dart`,
  `feed_wired.dart`, `main.dart`, `create_group_picker_wired.dart`,
  `group_conversation_wired.dart`, or `group_info_wired.dart`.
- Do not change `GroupRow`'s relative-time rendering to restore `DateFormat.jm`
  parity with the retired surface; TC-286-11 locks the accepted difference.
- Do not delete `integration_test/group_conversation_polish_proof_test.dart` or
  either `loading_states_smoke_test.dart`; they are **edited**, and each retains
  its non-island obligations.
- Do not touch any group backend, listener, repository, notification, bridge,
  native, Go, schema, migration, or relay boundary. This plan changes none.
- Do not run a full `host-all` sweep for this plan.
- Do not rewrite the historical `DTR07-AUTH-01` receipt or historical completed
  plans/session evidence merely because they name an artifact that existed when
  that evidence was recorded. Only current structure/inventory documentation
  and the still-executable Plans 279/280 are swept.

Deferred / accepted difference:

- `GroupBacklogRetentionNotice.listSummary` (field declared at
  `lib/features/groups/presentation/group_backlog_retention_notice.dart:10`;
  written at `:36` and `:45`)
  becomes **write-only** once `group_list_screen.dart:354` — its only reader —
  is deleted. It is **deferred to DTR-11** (owner: Groups) rather than removed
  here, because removing the field also orphans
  `group_backlog_mixed_list_summary` and `group_backlog_expired_list_summary`,
  and its enclosing factory `groupBacklogRetentionNoticeFor` is live-called from
  `group_conversation_wired.dart:7721`. The accepted difference is **not** an
  untested assumption: TC-286-13 asserts the live caller's own fields still
  render, so the deferred field cannot silently take live behavior with it.
- The retired `de group-list row` ICU leg is an accepted, authorization-visible
  coverage reduction, test-locked by TC-286-11 and backed by the surviving
  conversation and Feed carriers listed above.

Dependencies:

- `DTR07-AUTH-01` (Product + groups) — **Approved 2026-07-26** in the roadmap
  decision ledger.
- DTR-01 runtime-root bookkeeping must change atomically with deletion, or
  `check_runtime_root_inventory.sh check` emits `stale-declaration` drift and
  exits non-zero (`runtime_root_inventory.dart:946`).
- The `DTR08-COMP-007` correction is a prerequisite input to DTR-10 Plans 279
  and 280. Both still inherit the false three-surface assumption and literal
  `group_list_wired_test.dart` commands, so both contracts must be corrected
  atomically with this retirement.
- Wave 2 exit also requires DTR-06, which is terminally `Retained` and unchanged.

## Test Contract

Zero empty cells. `HEAD state` is one of `causal RED` · `GREEN sentinel` ·
`manual/device-only proof`.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-286-01 | The three island sources, five SUT-only tests, and three manifest declarations are absent, while the exact live replacement anchors remain present | `test/unit/runtime_root_inventory_test.dart::DTR-07 retires the Group-list UI island and preserves the Orbit all-chats replacement` | Host source/policy test over the real tree and runtime-root manifest | causal RED (all three sources and all three declarations exist on HEAD) → GREEN: sources/tests/declarations absent and `orbit_screen.dart`, `orbit_view_toggle_button.dart`, `group_row.dart` still present | Restore any one island source, test, or manifest declaration → TC-286-01 red | `flutter test --no-pub test/unit/runtime_root_inventory_test.dart --plain-name 'DTR-07 retires the Group-list UI island and preserves the Orbit all-chats replacement'`; registered by the existing `runtime-roots` gate |
| TC-286-02 | The runtime-root inventory carries no stale declaration and the candidate set stays reconciled after deletion | `test/unit/runtime_root_inventory_test.dart::repository manifest accounts for current non-main sources and keeps known candidates advisory` (existing, `:1221`) plus the CLI check | Host inventory tool against the real tree | **GREEN sentinel on committed HEAD**, but the shared working tree is already red from the unrelated unstaged Plan-277/278 source deletions. After this plan's atomic edit, GREEN is evaluated with the literal temporary-index isolation in *Acceptance Gates*, which stages all current `lib/` deletions only in a copied index and leaves the user's real index untouched. Its Plan-286 causal power remains transitional, not HEAD-relative. Do NOT list it under INV-RED-FIRST | Delete a source but keep its declaration, or vice versa in the isolated index → TC-286-02 red | Run the full runtime test, CLI check, and `runtime-roots` gate with `GIT_INDEX_FILE="$DTR07_INDEX_PATH"` as shown in *Acceptance Gates* (exit 0, zero drift) |
| TC-286-03 | The eight orphan group-list copy keys are absent from every locale and the generated API, while live replacement copy remains | `test/l10n/l10n_integrity_test.dart::DTR-07 retired group-list keys are absent from every locale and generated API` | Host l10n policy test / real ARB files (`app_en.arb`, `app_ar.arb`, `app_de.arb`) + generated `app_localizations*.dart` | causal RED (all eight keys exist in all three locales and the generated API on HEAD) → GREEN: eight keys absent everywhere; retained `orbit_view_toggle_to_list` / `orbit_view_toggle_to_circle` still present in every locale and the generated API | Restore any one retired key in any one locale, or drop a retained key → TC-286-03 red | `flutter test --no-pub test/l10n/l10n_integrity_test.dart --plain-name 'DTR-07 retired group-list keys are absent from every locale and generated API'`; `test/l10n` is host-all-only, so this direct path command is the per-plan gate |
| TC-286-04 | No production or test file references any island path or symbol after removal — the census is computed, never a fixed list | Source proof: three `rg` censuses over `lib` and `test`/`integration_test` with explicit exit-status handling (literal commands in *Acceptance Gates*) | Host source proof / ripgrep over the real tree | causal RED (every census matches on HEAD) → GREEN: status 1 (no matches) for each census | Restore any island file, import, or symbol reference anywhere → the corresponding census re-reds | The three literal census commands in *Acceptance Gates*; N/A — source proof runs directly and needs no harness registration |
| TC-286-05 | The shipped classic list — Orbit's `allChats` view mode — still toggles both ways, survives re-entry reset, and renders group rows | `orbit_view_split_test.dart::top-left toggle switches to the all-chats view`; `::toggle returns to the Inner-Circle view`; `::non-null initialFilterTab forces the all-chats view`; `orbit_wired_test.dart::displays group rows when groups exist`; `::displays structured group rows with latest message preview`; `::interleaves groups and friends sorted by last activity` | Widget host / `WidgetTester` + Orbit pump harness and fakes | GREEN sentinel (passes today) → GREEN unchanged after deletion | Remove the `allChats` arm of the surface ternary at `orbit_screen.dart:700`, or unmount `OrbitViewToggleButton` at `:711` → the corresponding toggle sentinel re-reds | `flutter test --no-pub test/features/orbit/presentation/screens/orbit_view_split_test.dart`; `flutter test --no-pub test/features/orbit/presentation/screens/orbit_wired_test.dart` (run the file **unfiltered** — `--plain-name 'group rows'` would silently skip `interleaves groups and friends sorted by last activity`, which contains no such substring); AUTO (glob) into `feature-host-all` |
| TC-286-06 | Group chat still opens from the live entry surfaces, and the live sole-admin exit guidance is unaffected | `orbit_wired_test.dart::orbit entry keeps group long-press actions aligned with the shared conversation surface`; `::orbit entry keeps group reaction inspection aligned with the shared conversation surface`; `::accepting a pending group invite from Intros joins the group`; `::first sole-admin Leave opens recovery without destructive work`; `::sole admin dissolve preserves history before optional local delete` | Widget host / `WidgetTester`, fake bridge, in-memory repositories | GREEN sentinel → GREEN unchanged | Drop the `GroupConversationWired` push at `orbit_wired.dart:3691`, or remove the `lastAdminLeaveBlockedMessage` snackbar at `:3131` → the corresponding sentinel re-reds | `flutter test --no-pub test/features/orbit/presentation/screens/orbit_wired_test.dart`; `./scripts/run_test_gates.sh groups`; already in `GROUP_TESTS` |
| TC-286-07 | The group-media coordinator wiring baseline decrements from five paths to four and still requires every remaining live path to pass exactly one shared coordinator | `test/features/groups/integration/group_media_reliability_wiring_test.dart` (edited: drop the `group_list_wired.dart` key and update the "exactly five" reason string) | Host source-scanning integration guard / AST-shaped invocation extraction over real `lib` sources | causal RED (with the expectation decremented to four, HEAD still discovers `group_list_wired.dart` and the exact-set assertion at `:293` fails) → GREEN after deletion: discovered set equals the four live paths | Restore `group_list_wired.dart` → the set assertion re-reds; drop `groupMediaDownloadCoordinator` from `orbit_wired.dart` or `feed_wired.dart` → the per-path arity assertion re-reds | `flutter test --no-pub test/features/groups/integration/group_media_reliability_wiring_test.dart`; AUTO (glob) into `feature-host-all` |
| TC-286-08 | The group-exit application boundary and the announcement private-reply entry census still hold on their remaining live surfaces | `test/features/groups/application/group_exit_diagnostic_wiring_test.dart` (edited: drop `group_list_wired.dart` from the 3-path loop at `:274-276`); `test/features/groups/presentation/announcement_private_reply_entry_surface_test.dart` (edited: **four** coupled edits — rename the test at `:17` from `'five group entry sites …'` to `'four group entry sites …'`, drop the `listPath` const and its `sites` entry at `:27-33`, decrement the hardcoded `expect(constructors, hasLength(5))` at **`:78` to 4**, and delete the whole `expect(constructors[listPath], contains('openAnnouncementSenderConversation: null'))` block at **`:101-104`**) | Host source-scanning guards / `File(path).readAsStringSync()` over real `lib` sources | GREEN sentinel after edit (both currently pass, and both would throw `FileSystemException` on deletion if left unedited) → GREEN unchanged | Remove `resolveGroupExitActionSnapshot(` from `group_info_wired.dart` or `orbit_wired.dart` → exit-diagnostic sentinel re-reds; give any remaining site a second non-probe `GroupConversationWired` constructor → entry-surface `hasLength(4)` re-reds | `flutter test --no-pub test/features/groups/application/group_exit_diagnostic_wiring_test.dart test/features/groups/presentation/announcement_private_reply_entry_surface_test.dart`; AUTO (glob); the deletion-coupling itself is proven causally by TC-286-04 |
| TC-286-09 | Flow-event privacy scrubbing still holds for every remaining fixed event row after the three `GROUP_LIST_FL_*` rows leave with their only emitter | `test/core/utils/flow_event_emitter_test.dart` (edited: drop the three `GROUP_LIST_FL_*` rows at `:349`, `:356`, `:363`) | Host source-scanning guard / fixed-block extraction over real `lib` sources | GREEN sentinel after edit (would throw on deletion if left unedited) → GREEN unchanged | Add `'groupId'` or `'error'` to any remaining live event block, e.g. an `ORBIT_FL_*` row → TC-286-09 red | `flutter test --no-pub test/core/utils/flow_event_emitter_test.dart` — direct path command only; `core-host-all` is deliberately not a per-plan gate here (no `lib/core/**` production source changes) |
| TC-286-10 | The ambient-background chat-suppression leakage guard still covers every remaining non-chat surface, including the live Orbit screen | `test/features/identity/presentation/widgets/ambient_background_test.dart` (edited: drop `group_list_screen.dart` from `nonChatAmbientSurfaceFiles` at `:269` **and** from `expectedSurfaceFiles` at `:668`, and decrement the hardcoded "other 14" comment at `:261` to 13) | Host source-scanning guard / `File(path).readAsStringSync()` over real `lib` sources | GREEN sentinel after edit (would throw on deletion if left unedited) → GREEN unchanged | Make `orbit_screen.dart` opt into chat-surface ambient suppression → TC-286-10 red | `flutter test --no-pub test/features/identity/presentation/widgets/ambient_background_test.dart`; AUTO (glob) into `feature-host-all` |
| TC-286-11 | The three island-dependent harnesses keep every non-island obligation; the two island-only cases are retired against a named live owner; and the retired ICU leg's accepted difference is test-locked | Edits: `test/features/loading_states_smoke_test.dart` and `integration_test/loading_states_smoke_test.dart` (delete only the `group list loading renders without overflow` case and the now-unused `group_list_screen.dart` import); `integration_test/group_conversation_polish_proof_test.dart` (delete only the `de group-list row` leg at `:151` and its doc claim at `:13`). Live owners that must stay green: `test/features/orbit/presentation/screens/orbit_screen_loading_test.dart::renders loading placeholders while all tab is still hydrating`; the three surviving conversation legs at `:105`, `:121`, `:135`. New lock: `test/features/orbit/presentation/screens/orbit_wired_test.dart::DTR-07 the all-chats group row renders relative activity time, not clock time` | Widget host / `WidgetTester` + the existing Orbit pump harness; the device leg stays on the existing proof file | **GREEN sentinel** — labeled honestly: the relative-time lock passes the moment it is written, because `group_row.dart:55` already calls `formatRelativeTime`, and the live loading owner is already green at `orbit_screen_loading_test.dart:230-241`. An absent test is not a RED. The two deletions are proven causally by TC-286-04's `test`/`integration_test` census, which is the row that actually reds on HEAD | Restore `DateFormat.jm` formatting to `GroupRow` → the relative-time lock re-reds; remove `_OrbitLoadingRow` (`orbit_screen.dart:1573`) → the live loading owner re-reds | `flutter test --no-pub test/features/loading_states_smoke_test.dart`; `flutter test --no-pub test/features/orbit/presentation/screens/orbit_screen_loading_test.dart`; `flutter test --no-pub test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name 'DTR-07 the all-chats group row renders relative activity time, not clock time'`; `test/features/loading_states_smoke_test.dart` stays in `OUT_OF_GATE_TESTS` (`run_test_gates.sh:737`) and `integration_test/loading_states_smoke_test.dart` stays in `BASELINE_TESTS` (`:12`) — **both entries are retained, not removed** |
| TC-286-12 | The roadmap's DTR-07 rows are updated; the false `DTR08-COMP-007` three-surface claim is corrected without rewriting `DTR07-AUTH-01`; and still-executable Plans 279/280 no longer call the retired suite | Positive and negative source proofs over the exact `DTR08-COMP-007` row, the DTR-07/Wave-2 status rows, and Plans 279/280. Historical authorization and completed evidence remain untouched | Host source proof / ripgrep over exact current execution contracts | causal RED (the compatibility row and both downstream plans still require Group List / `group_list_wired_test.dart`) → GREEN: only Group Info and Orbit remain in the executable preservation contract; at per-plan closure DTR-07 was Plan-green; the post-wave maintenance state requires the DTR-07 registry row and Wave 2 to be `Wave-accepted` with linked aggregate `host-all` evidence | Restore a Group-list executable command/claim, erase the positive two-surface contract, or rewrite the historical receipt → TC-286-12 red | The targeted positive/negative commands in *Acceptance Gates*; N/A — documentation source proof needs no harness registration |
| TC-286-13 | The deferred `GroupBacklogRetentionNotice` field does not take live behavior with it: the live caller's own retention fields still render in group conversation | `test/features/groups/presentation/group_conversation_screen_test.dart::IR-016 shows expired backlog banner and empty-state override after retention expiry`; `::IR-016 shows mixed-window retention banner while retained messages stay visible`; `::PREREQ-HISTORY-GAP-REPAIR shows active failed and repaired gap state separately from retention expiry` | Widget host / `WidgetTester` over the real `groupBacklogRetentionNoticeFor` factory (invoked at `:1620`, `:1656`, `:1702`) | GREEN sentinel → GREEN unchanged after the island's `listSummary` reader is deleted | Stop populating the banner/empty-state fields that `groupBacklogRetentionNoticeFor` returns to the live caller at `group_conversation_wired.dart:7721` → the corresponding IR-016 sentinel re-reds | `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'IR-016'`; `./scripts/run_test_gates.sh groups`; already in `GROUP_TESTS` |

| TC-286-15 | Relative to the pre-edit dirty-tree baseline and any explicitly source-attributed concurrent plan, this change deletes **exactly** its intended set and nothing else — staged or unstaged over-deletion is caught | Baseline-relative working-tree proof: capture tracked deletions and ARB keys before edits; require every post-edit deletion/addition to be either one of this plan's exact removals or an exact path/key independently authorized by a concurrently executing plan; and require the real cached deletion set to equal this plan's eight paths. TC-286-03 separately requires the retired localization-key set to equal exactly eight in every locale | Host source/diff proof / `git`, exact HEAD-versus-worktree ARB key sets, concurrent plans' scope contracts, and the real ARB files | GREEN sentinel evaluated after the edit → GREEN: the eight staged paths and eight retired keys belong only to Plan 286; Plan 280's two new deletions and Plan 285's two new keys are explicitly attributed; every pre-existing deletion remains preserved | Delete any unclassified tracked file whether staged or unstaged, restore a pre-existing user deletion, misattribute a concurrent deletion/key, or remove a ninth ARB key → TC-286-15 red | The baseline capture and literal working-tree/cached/ARB-set comparisons in *Acceptance Gates*; N/A — diff/source proof needs no harness registration |
| TC-286-14 | Current structure/inventory documentation no longer presents the retired island as present or "not dead", while historical completion evidence remains untouched | Negative source proofs over `codebase-test-inventory.md`, `C4/file-structure.md`, `C4/components.md`, `06-dead-code-lib.md`, and the dangling `contact_picker_row.dart` comment; one positive/count proof updates the existing Plan-286 index row rather than duplicating it | Host source proof / ripgrep over the exact current documentation and comment files | causal RED (all named current files still present the island) → GREEN: exact current references are absent and the index contains exactly one Plan-286 row labeled Wave-accepted DTR-07 while retaining Plan 286's Plan-green status/date | Restore a retired current-structure reference, leave the "Verified NOT Dead" claim, or duplicate/delete the index row → TC-286-14 red | The literal targeted commands in *Acceptance Gates*; N/A — documentation/comment source proof needs no harness registration. Historical plans/session records are explicitly out of sweep |

### Test Notes

- TC-286-04 census is deliberately computed rather than a fixed list, per the
  construction/call-site blind-spot rule: counts drift, and a hardcoded site
  list would pass while a new reference existed. Status 1 means no matches;
  status 0 (a match) or status > 1 (an operational error) fails closed.
- TC-286-07 is the plan's strongest causal row because its assertion is a
  **relationship** (path → the exact coordinator expressions passed at that
  path), not a presence check; the set equality at `:293` cannot pass while the
  island file exists.
- TC-286-08/09/10 are labeled `GREEN sentinel` and not `causal RED` on purpose.
  Their edits remove a path from a hardcoded list, which passes both before and
  after deletion; the coupling that makes the edit mandatory is the
  `File(path).readAsStringSync()` throw, and the proof that the edit actually
  landed is TC-286-04's `test`-scope census.
- TC-286-11's relative-time lock is new coverage, not a migration: it exists so
  the accepted ICU difference cannot be silently reverted by a future change to
  `GroupRow`. Its Acceptance Gate also positively requires the three surviving
  `de`/`en`/`ar` conversation ICU test names to remain in the device-proof
  source; deleting those blocks is not an allowed way to retire the list leg.

## Implementation Steps

1. Run both prerequisite commands and confirm `DTR07-AUTH-01` is recorded AND
   matches this plan's exact removal set. If the ledger row reverts to `Open`,
   the receipt prose is absent, or the approved set is scope-mismatched,
   **stop** — a bare marker grep is not sufficient evidence of approval.
2. Snapshot `git status --short` and record every pre-existing unrelated change
   so nothing user-owned is reverted. Capture the executable TC-286-15
   baselines before any edit: all three locale message-key counts (currently
   988 each) and `git diff HEAD --name-only --diff-filter=D`. Re-run the compact
   Graphify query with `--ensure-fresh` and re-verify the TC-286-01 anchors in
   current source.
3. INV-RED-FIRST — before any production edit, add TC-286-01 and TC-286-03,
   and decrement TC-286-07's expectation to the four live paths. Run those three
   selectors and record causal RED with the exact documented mechanism for each.
   Add and run TC-286-11's group-row-specific relative-time sentinel as an
   honest GREEN baseline; it is explicitly in scope even though it is not a RED.
   Do **not** expect a HEAD red from TC-286-02 (transitional only) or from
   TC-286-11's relative-time lock (green the moment it is written) — claiming
   one would be a fabricated RED.
4. Edit the eight indirect guard/harness files, in one commit-atomic set. Three
   of them carry a **hardcoded count** that must be decremented, not just a list
   entry — those are the landmines:
   - `test/core/utils/flow_event_emitter_test.dart` — drop the three
     `GROUP_LIST_FL_*` rows at `:349`, `:356`, `:363`. No count.
   - `test/features/groups/integration/group_media_reliability_wiring_test.dart` —
     drop the `group_list_wired.dart` key from
     `expectedCoordinatorExpressionsByPath` **and** update the
     `'exactly five direct group-conversation paths'` reason string at `:296-297`.
   - `test/features/groups/application/group_exit_diagnostic_wiring_test.dart` —
     drop `group_list_wired.dart` from the path loop at `:274-276`. The
     `hasLength(greaterThanOrEqualTo(3))` at `:262` counts
     `groupExitIntentProcessor.processGroup(groupId)` matches in `main.dart`
     **only** and must NOT be decremented.
   - `test/features/groups/presentation/announcement_private_reply_entry_surface_test.dart` —
     **four coupled edits**: rename the test itself at `:17` —
     `'five group entry sites wire one complete or explicit null opener contract'`
     → `'four group entry sites …'`; drop the `listPath` const and its `sites`
     entry at `:27-33`; decrement `expect(constructors, hasLength(5))` at
     **`:78` to 4**; delete the whole
     `expect(constructors[listPath], contains('openAnnouncementSenderConversation: null'))`
     block at **`:101-104`**.
   - `test/features/identity/presentation/widgets/ambient_background_test.dart` —
     drop `group_list_screen.dart` from `nonChatAmbientSurfaceFiles` (`:269`)
     **and** `expectedSurfaceFiles` (`:668`), and decrement the
     `'None of the other 14 AmbientBackground call sites'` comment at `:261` to 13.
   - `test/features/loading_states_smoke_test.dart` and
     `integration_test/loading_states_smoke_test.dart` — delete **only** the
     `group list loading renders without overflow` case and the now-unused
     `group_list_screen.dart` import (`:5` and `:8` respectively). Do **not**
     retarget onto `orbit-loading-row-0`: `_OrbitLoadingRow` is private
     (`orbit_screen.dart:1573`), so it needs a full `OrbitScreen` pump, and
     `orbit_screen_loading_test.dart:219` already covers it on the live surface.
   - `integration_test/group_conversation_polish_proof_test.dart` — drop the
     group-list leg at `:151` and its doc claim at `:13` only; keep the three
     conversation legs.
   **Match every edit below by CONTENT, not by line number** — these files are
   actively edited by other work and the offsets drift.
   **Three `import` directives die with the island and must be deleted in the
   same edits, or strict analysis fails before any test runs:**
   `test/features/loading_states_smoke_test.dart:5`,
   `integration_test/loading_states_smoke_test.dart:8`, and
   `integration_test/group_conversation_polish_proof_test.dart:34` — all three
   are `import 'package:flutter_app/features/groups/presentation/screens/group_list_screen.dart';`.
   The other five affected guard tests reference the island only as **string
   literals** inside real-tree source scans, so they compile either way and fail
   at *runtime* instead — a different and easier-to-miss failure signature.
   Stop-if: any of these files turns out to assert something about the island
   that has **no** live owner — that is coverage loss, not bookkeeping, and
   requires replanning rather than deleting the assertion.
5. Delete the three sources and five SUT-only tests, then stage exactly those
   eight approved deletions. Remove the three `runtime_roots.json` declarations
   (currently at `:678-718`; the current shared-worktree count is 60 → 57,
   robustly `N → N-3`; every `rootKinds` is `[]`, so no
   `requiredRestrictedRoots`/`restrictedRoots` companion record exists to
   touch) and the one `GROUP_TESTS` entry; remove the eight keys from all three
   ARB locales and run literal `flutter gen-l10n` to regenerate the four l10n
   API files before focused GREEN. Retain the `BASELINE_TESTS` and
   `OUT_OF_GATE_TESTS` entries and both
   `check_reliability_simulation_discovery.sh` case arms (`:614`, `:617`) —
   those files are edited, not deleted.
5b. Sweep the stale documentation the deletion orphans:
   `Test-Flight-Improv/codebase-test-inventory.md:393` and `:400` (the five
   retired suites), `C4/file-structure.md:246`, `:247`, `:259`,
   `C4/components.md:147`, `:152`, `:939-951`,
   `Test-Flight-Improv/06-dead-code-lib.md:37`, `:54-56`, and the dangling
   `// and group_card.dart.` comment at
   `lib/features/groups/presentation/widgets/contact_picker_row.dart:37`.
   Correct only the executable two-surface contracts/commands in Plans 279 and
   280; historical completed-plan/session references remain historical.
6. Run focused GREEN, then every preservation sentinel, then the named gates.
7. Perform a representative mutation: restore `group_card.dart` and its manifest
   declaration temporarily, prove TC-286-01 and TC-286-04 re-red, then return to
   the intended deletion.
8. Run `./graphify-arch/refresh_arch_graph.sh --incremental` once from the repo
   root — required by `AGENTS.md:25` after a coherent app-owned code change, and
   run by both accepted sibling plans 275 and 276.
9. Update the roadmap DTR-07 registry row, the Wave-2 exit/status rows, the
   `Retired Group-list UI island` row in the grounding snapshot table, the
   `DTR08-COMP-007` correction (TC-286-12), and update the existing
   `00-INDEX.md` Plan-286 row under `## 4. Dead Code`. Preserve the historical
   authorization receipt in the roadmap decision ledger byte-for-byte.

## Risks And Blind Spots

- A guard test throws `FileSystemException` instead of failing an assertion, so
  the failure reads as an environment error rather than a missed edit →
  guarded by TC-286-08/09/10 and by running each edited file directly before the
  family gates.
- The `GroupCard` / `SettingsGroupCard` name collision invites an over-broad
  deletion → guarded by TC-286-04's path-scoped census and the hard `Do not`.
- The roadmap `DTR08-COMP-007` row and executable Plans 279/280 initially
  preserved a dead third surface and commanded a suite this plan deletes →
  guarded by TC-286-12's targeted negative and positive two-surface assertions.
- The shared worktree already contains two unrelated unstaged production
  deletions, so the raw runtime-root gate is red before this plan and a cached
  diff cannot bound this plan → guarded by TC-286-02's copied-index isolation
  and TC-286-15's baseline-relative working-tree delta.
- Lifecycle / derived-state durability: the replacement surface's view mode is
  **deliberately** non-persisted (`orbit_view_mode.dart:3-9`) and resets on
  re-entry (`orbit_wired.dart:673`) → asserted by TC-286-05's
  `non-null initialFilterTab forces the all-chats view` and the re-entry reset
  sentinel. No new derived state is introduced by a deletion.
- Sibling-surface consistency / **B-15 moving census**: as of planning,
  `grep -rn 'GroupConversationWired(' lib --include=*.dart` returns **7
  occurrences across 6 files** — six real invocations plus the constructor
  declaration at `group_conversation_wired.dart:362`, which
  `group_media_reliability_wiring_test.dart` filters out by `startsWith`. Those
  six resolve to **five paths** because `lib/main.dart` holds two — and they are
  NOT interchangeable: `:5344` is the **compile-gated P269 receiver render
  probe** (it passes `mediaRenderedSemanticsLabels:` at `:5374`), while `:6636`
  is the real notification-open entry surface. `group_media_reliability_wiring_test.dart`
  distinguishes them by that named argument. The others are `orbit_wired.dart:3691`,
  `create_group_picker_wired.dart:228`, `feed_wired.dart:1894`, and the island's
  unreachable `group_list_wired.dart:337`. **Treat that enumeration as
  illustrative, not authoritative** — these line numbers have already drifted
  once (a prior record had `orbit_wired:3686` / `feed_wired:1891`), and a fixed
  list is exactly the defect B-15 describes. The binding guarantee is that
  TC-286-07's assertion is **computed**: `discovered` is built by walking
  `Directory('lib').listSync(recursive: true)`, so the set equality at `:293`
  fails if any site is added, missed, or left behind. Execution must re-run the
  census rather than trust this bullet.
- Destructive-action side effects: TC-286-01 is a **whitelist, not a bound** —
  it asserts the eight intended paths are absent, so deleting a ninth file
  by accident is invisible to it, to the three censuses (which only match
  island paths/symbols), and to a deleted test's own gate. The bound is
  supplied separately by TC-286-15's baseline-relative staged-or-unstaged
  diff assertion and by TC-286-03's exact three-locale retired-key set.
  TC-286-04 proves nothing else references the
  island; TC-286-05/06 prove no live surface changed.
- Invariant re-verification under new transitions: N/A — this plan adds no
  transition, flag, latch, or self-heal path. Every edit is a deletion or a
  list decrement.
- Construction / call-site census: computed by TC-286-04
  (`rg -n 'GroupListWired\(|GroupListScreen\(|GroupCard\(' lib`), never a fixed
  list. Note that `GroupCard(` must be matched with a word boundary so
  `SettingsGroupCard(` is excluded.
- Build-artifact provenance: N/A — no native, plugin, Podfile, or binary
  artifact participates in this plan.
- Permission / ACL verb symmetry: N/A — no permission or ACL check changes.
- Fake side-effect fidelity: N/A — no fake is added or modified; the deleted
  suites take their own fakes with them.
- Composite-node / relationship assertions: TC-286-07 asserts the
  path → coordinator-expression relationship rather than two independent
  presence checks.

## Gate Cadence

- Per-plan closure: the causal contracts (TC-286-01/03/04/07/12/14), the
  exact preservation sentinels (TC-286-02/05/06/08/09/10/11/13), and the
  TC-286-15 over-deletion bound, `runtime-roots`,
  `groups`, `feed`, and a justified `feature-host-all` sweep because app-owned
  feature sources are deleted. `feed` is required for two independent reasons:
  the roadmap's DTR-07 registry row names it, and
  `ambient_background_test.dart` — which this plan edits — is registered in
  `FEED_TESTS` at `scripts/run_test_gates.sh:319`, so `feed` is the curated
  owner of that edit, not an optional extra.
- `core-host-all` is deliberately **not** run. The only `test/core/**` file this
  plan touches is `flow_event_emitter_test.dart`, and no `lib/core/**`
  production source changes at all; the proportionate gate is the direct
  `flutter test --no-pub test/core/utils/flow_event_emitter_test.dart` command
  below. Running a core sweep here would be broad-gate theater.
- `flutter analyze` is repo-wide: `scripts/check_flutter_analyze_strict.sh:26`
  runs `flutter analyze --no-pub --fatal-infos --fatal-warnings` and
  `analysis_options.yaml` declares **no `exclude:` key**, so `integration_test/`
  is analyzed. Both `integration_test/` edits in step 4 are therefore
  analyze-blocking, not merely test-blocking — an unedited import of a deleted
  file fails strict analysis before any test runs.
- Full `host-all` is **not** a per-plan gate. The Wave 2 DTR-06/DTR-07 run
  completed on 2026-07-27; the next full run is the separate final
  rollout/release closure gate.
- Any justified broad sweep runs batch-parallel:
  `--batch-flutter --concurrency 4 --reporter failures-only`.
- Shared tests outside the feature/core globs:
  `test/unit/runtime_root_inventory_test.dart` (also covered by `runtime-roots`)
  and `test/l10n/l10n_integrity_test.dart` each get a direct
  `flutter test --no-pub <exact path>` command below. They were included in the
  completed Wave 2 `host-all`; that registration was not a per-plan execution
  obligation.

## Acceptance Gates  (literal — copy/paste)

```bash
# Prerequisite. A bare `rg -n 'DTR07-AUTH-01' <roadmap>` is insufficient:
# it can match registry, historical, or compatibility prose without proving an
# approved decision-ledger row. Two complementary checks are required.
#
# (a) The decision-ledger row must no longer be Open; expect status 1.
DTR07_LEDGER_OPEN_STATUS=0
rg -n '^\| Retire Group-list UI after Feed/Orbit test migration \|.*\| Open \|' \
  Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md \
  || DTR07_LEDGER_OPEN_STATUS=$?
test "$DTR07_LEDGER_OPEN_STATUS" -eq 1

# (b) The recorded-receipt prose must exist, in the same shape DTR03-AUTH-01,
#     DTR05-AUTH-01, DTR06-AUTH-01, and DTR09-AUTH-01 use in the roadmap
#     decision ledger; expect status 0.
rg -n 'DTR07-AUTH-01`: the current authenticated project owner' \
  Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md

# Then confirm the receipt names this plan's exact removal set, including the
# eight l10n keys enumerated in "Authorization Required". Mismatched => STOP.

# Dirty-tree snapshot and executable baselines before any edit.
git status --short
DTR07_KEYS_EN_BEFORE=$(python3 -c "import json;print(len([k for k in json.load(open('lib/l10n/app_en.arb')) if not k.startswith('@')]))")
DTR07_KEYS_DE_BEFORE=$(python3 -c "import json;print(len([k for k in json.load(open('lib/l10n/app_de.arb')) if not k.startswith('@')]))")
DTR07_KEYS_AR_BEFORE=$(python3 -c "import json;print(len([k for k in json.load(open('lib/l10n/app_ar.arb')) if not k.startswith('@')]))")
test "$DTR07_KEYS_EN_BEFORE" -eq 988
test "$DTR07_KEYS_DE_BEFORE" -eq "$DTR07_KEYS_EN_BEFORE"
test "$DTR07_KEYS_AR_BEFORE" -eq "$DTR07_KEYS_EN_BEFORE"
DTR07_DELETED_BEFORE=$(git diff HEAD --name-only --diff-filter=D | LC_ALL=C sort)

# Causal RED before production edits; expect non-zero for the documented reason.
flutter test --no-pub test/unit/runtime_root_inventory_test.dart \
  --plain-name 'DTR-07 retires the Group-list UI island and preserves the Orbit all-chats replacement'
flutter test --no-pub test/l10n/l10n_integrity_test.dart \
  --plain-name 'DTR-07 retired group-list keys are absent from every locale and generated API'
flutter test --no-pub test/features/groups/integration/group_media_reliability_wiring_test.dart

# Honest GREEN baseline added before production edits.
flutter test --no-pub \
  test/features/orbit/presentation/screens/orbit_wired_test.dart \
  --plain-name 'DTR-07 the all-chats group row renders relative activity time, not clock time'

# After the ARB edits, regenerate the tracked API before focused GREEN.
flutter gen-l10n

# Stage exactly the eight approved deletions. The inventory has TWO
# independent drift channels: `stale-declaration` (manifest keeps a path the
# scan no longer sees) AND `tracked-path-deleted`, which fires purely from
# `git ls-files --deleted` for any `lib/**.dart` and is INDEPENDENT of the
# manifest. Use `git add -u` only for this approved set.
git add -u -- \
  lib/features/groups/presentation/screens/group_list_wired.dart \
  lib/features/groups/presentation/screens/group_list_screen.dart \
  lib/features/groups/presentation/widgets/group_card.dart \
  test/features/groups/presentation/group_list_wired_test.dart \
  test/features/groups/presentation/group_list_screen_test.dart \
  test/features/groups/presentation/group_list_screen_bidi_test.dart \
  test/features/groups/presentation/group_card_test.dart \
  test/features/groups/presentation/group_card_bidi_test.dart

# The shared tree also has unrelated unstaged Plan-277/278 lib deletions. Copy
# the real index, stage all current lib deletions only in that copy, and use it
# for inventory proof. This does not change the user's real index.
DTR07_INDEX_DIR=$(mktemp -d)
DTR07_INDEX_PATH="$DTR07_INDEX_DIR/index"
cp "$(git rev-parse --git-path index)" "$DTR07_INDEX_PATH"
GIT_INDEX_FILE="$DTR07_INDEX_PATH" git add -u -- lib

# Focused GREEN after deletion/bookkeeping; expect exit 0, zero failures.
GIT_INDEX_FILE="$DTR07_INDEX_PATH" \
  flutter test --no-pub test/unit/runtime_root_inventory_test.dart
flutter test --no-pub test/l10n/l10n_integrity_test.dart
flutter test --no-pub test/features/groups/integration/group_media_reliability_wiring_test.dart
GIT_INDEX_FILE="$DTR07_INDEX_PATH" \
  ./scripts/check_runtime_root_inventory.sh check --format text

# Source censuses. Status 1 means no matches; status 0 (a match) or status >1
# (an operational error) fails closed.
DTR07_PATH_STATUS=0
rg -n -e 'group_list_wired\.dart' -e 'group_list_screen\.dart' \
      -e 'groups/presentation/widgets/group_card\.dart' \
  --glob '!test/unit/runtime_root_inventory_test.dart' \
  lib test integration_test scripts tool || DTR07_PATH_STATUS=$?
test "$DTR07_PATH_STATUS" -eq 1

DTR07_SYMBOL_STATUS=0
rg -n -e '\bGroupListWired\b' -e '\bGroupListScreen\b' \
  lib test integration_test || DTR07_SYMBOL_STATUS=$?
test "$DTR07_SYMBOL_STATUS" -eq 1

# GroupCard census. `\b` alone already excludes SettingsGroupCard: in
# "SettingsGroupCard" the `s`/`G` junction is not a word boundary, so
# `\bGroupCard\b` cannot match it. Verified against the real tree.
# Do NOT use a look-behind here — ripgrep's Rust regex engine rejects
# look-around outright ("error: look-around ... is not supported") and exits 2,
# which fails this gate for a reason unrelated to the removal.
DTR07_CARD_STATUS=0
rg -n '\bGroupCard\b' lib test integration_test || DTR07_CARD_STATUS=$?
test "$DTR07_CARD_STATUS" -eq 1

# Preservation sentinels; expect exit 0 and zero failures.
flutter test --no-pub \
  test/features/orbit/presentation/screens/orbit_view_split_test.dart \
  test/features/orbit/presentation/screens/orbit_wired_test.dart
flutter test --no-pub \
  test/features/groups/application/group_exit_diagnostic_wiring_test.dart \
  test/features/groups/presentation/announcement_private_reply_entry_surface_test.dart
flutter test --no-pub test/core/utils/flow_event_emitter_test.dart
flutter test --no-pub \
  test/features/identity/presentation/widgets/ambient_background_test.dart
flutter test --no-pub test/features/loading_states_smoke_test.dart
flutter test --no-pub \
  test/features/orbit/presentation/screens/orbit_screen_loading_test.dart
# TC-286-13 needs BOTH selectors: the three tests are top-level (the file's
# first `group(` is at :2667), so their full names are bare, and the third
# name at :1679 contains no 'IR-016' substring.
flutter test --no-pub \
  test/features/groups/presentation/group_conversation_screen_test.dart \
  --plain-name 'IR-016'
flutter test --no-pub \
  test/features/groups/presentation/group_conversation_screen_test.dart \
  --plain-name 'PREREQ-HISTORY-GAP-REPAIR shows active failed and repaired gap state separately from retention expiry'

# New replacement-surface lock; expect exit 0.
flutter test --no-pub \
  test/features/orbit/presentation/screens/orbit_wired_test.dart \
  --plain-name 'DTR-07 the all-chats group row renders relative activity time, not clock time'

# The three real-iOS conversation ICU legs must remain in the proof source.
DTR07_ICU_NAME_COUNT=$(rg -c \
  -e 'de conversation row renders 24-hour time, no AM/PM' \
  -e 'en conversation row keeps 12-hour AM/PM' \
  -e 'ar conversation row renders Eastern-Arabic digits' \
  integration_test/group_conversation_polish_proof_test.dart)
test "$DTR07_ICU_NAME_COUNT" -eq 3

# TC-286-12 post-wave maintenance proof. The Wave 2 acceptance addendum
# supersedes the earlier Plan-green/awaiting-host-all registry state. A global
# grep for `group_list_wired_test.dart` is invalid because the immutable
# DTR07-AUTH-01 receipt deliberately names the approved deleted suite.
rg -n '^\| DTR-07 \|.*\*\*Wave-accepted\*\*.*Plan 286.*remains Plan-green' \
  Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md
rg -n '^\| Wave 2 \| DTR-06, DTR-07 \| \*\*Wave-accepted\*\*.*evidence/dtr-wave2/README\.md' \
  Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md
rg -n '^\| Retire Group-list UI after Feed/Orbit test migration \|.*Approved 2026-07-26.*DTR07-AUTH-01' \
  Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md
rg -n '^\| DTR08-COMP-007 \|.*live in Group-info and Orbit UI.*group_info_wired_test\.dart.*orbit_wired_test\.dart' \
  Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md

# Plan 280 may truthfully retain a land-order note naming its two former
# Group-list consumers. Reject executable use of the deleted suite, not that
# retrospective dependency evidence.
DTR07_EXECUTABLE_DOC_STATUS=0
rg -n -e 'flutter test[^`]*group_list_wired_test\.dart' \
      -e 'group_list_wired_test\.dart[^`]*flutter test' \
  Test-Flight-Improv/279-dormant-group-leave-path-removal-tdd-plan.md \
  Test-Flight-Improv/280-superseded-leave-local-history-coordinator-removal-tdd-plan.md \
  || DTR07_EXECUTABLE_DOC_STATUS=$?
test "$DTR07_EXECUTABLE_DOC_STATUS" -eq 1
rg -n 'Plan 286 has already retired that unreachable' \
  Test-Flight-Improv/280-superseded-leave-local-history-coordinator-removal-tdd-plan.md
rg -n 'Group Info and Orbit' \
  Test-Flight-Improv/279-dormant-group-leave-path-removal-tdd-plan.md \
  Test-Flight-Improv/280-superseded-leave-local-history-coordinator-removal-tdd-plan.md

# TC-286-14 stale-documentation sweep; each expects status 1 (references gone).
DTR07_INVENTORY_STATUS=0
rg -n -e 'group_list_screen_test\.dart' -e 'group_list_wired_test\.dart' \
      -e 'group_list_screen_bidi_test\.dart' -e 'group_card_test\.dart' \
      -e 'group_card_bidi_test\.dart' \
  Test-Flight-Improv/codebase-test-inventory.md || DTR07_INVENTORY_STATUS=$?
test "$DTR07_INVENTORY_STATUS" -eq 1

DTR07_C4_STATUS=0
rg -n -e 'group_list_screen\.dart' -e 'group_list_wired\.dart' \
      -e 'group_card\.dart' \
  C4/file-structure.md || DTR07_C4_STATUS=$?
test "$DTR07_C4_STATUS" -eq 1

DTR07_C4_COMPONENT_STATUS=0
rg -n -e '\bGroupListScreen\b' -e '\bGroupListWired\b' -e '\bGroupCard\b' \
  C4/components.md || DTR07_C4_COMPONENT_STATUS=$?
test "$DTR07_C4_COMPONENT_STATUS" -eq 1

DTR07_DEAD_CODE_DOC_STATUS=0
rg -n 'group_list_wired\.dart' \
  Test-Flight-Improv/06-dead-code-lib.md || DTR07_DEAD_CODE_DOC_STATUS=$?
test "$DTR07_DEAD_CODE_DOC_STATUS" -eq 1

DTR07_COMMENT_STATUS=0
rg -n 'group_card\.dart' \
  lib/features/groups/presentation/widgets/contact_picker_row.dart \
  || DTR07_COMMENT_STATUS=$?
test "$DTR07_COMMENT_STATUS" -eq 1

test "$(rg -c '286-group-list-ui-island-retirement-tdd-plan\.md' \
  Test-Flight-Improv/00-INDEX.md)" -eq 1
rg -n '286-group-list-ui-island-retirement-tdd-plan\.md.*\*\*Wave-accepted DTR-07.*Plan-green' \
  Test-Flight-Improv/00-INDEX.md

# TC-286-15 bounding proofs. TC-286-01 is a whitelist and cannot catch
# over-deletion; these can.

# (a) Plan 286 must remove exactly its eight keys in every locale. Plan 285
# concurrently added its exact new title/message pair after the 988-key
# baseline, so the net total is 988 - 8 + 2 = 982. Prove the key sets, not only
# the arithmetic, so an unrelated add/remove pair cannot cancel out.
rg -n 'Add only the new title/message' \
  Test-Flight-Improv/285-move-account-cutover-window-recovery-tdd-plan.md
rg -n 'keys in en/ar/de and regenerate' \
  Test-Flight-Improv/285-move-account-cutover-window-recovery-tdd-plan.md
rg -n -e 'account_migration_unfinished_move_title' \
      -e 'account_migration_unfinished_move_message' \
  lib/features/account_migration/presentation/screens/account_migration_blocked_screen.dart
python3 - <<'PY'
import json
import subprocess

expected_removed = {
    'group_card_no_messages',
    'groups_title',
    'groups_joined',
    'groups_no_joined',
    'groups_empty_title',
    'groups_empty_desc',
    'groups_pending_invites',
    'groups_unknown_sender',
}
expected_concurrent_additions = {
    'account_migration_unfinished_move_title',
    'account_migration_unfinished_move_message',
}
for locale in ('en', 'de', 'ar'):
    path = f'lib/l10n/app_{locale}.arb'
    before = json.loads(subprocess.check_output(['git', 'show', f'HEAD:{path}']))
    after = json.load(open(path))
    before_keys = {key for key in before if not key.startswith('@')}
    after_keys = {key for key in after if not key.startswith('@')}
    assert before_keys - after_keys == expected_removed, locale
    assert after_keys - before_keys == expected_concurrent_additions, locale
PY
DTR07_KEYS_EN_AFTER=$(python3 -c "import json;print(len([k for k in json.load(open('lib/l10n/app_en.arb')) if not k.startswith('@')]))")
DTR07_KEYS_DE_AFTER=$(python3 -c "import json;print(len([k for k in json.load(open('lib/l10n/app_de.arb')) if not k.startswith('@')]))")
DTR07_KEYS_AR_AFTER=$(python3 -c "import json;print(len([k for k in json.load(open('lib/l10n/app_ar.arb')) if not k.startswith('@')]))")
test "$((DTR07_KEYS_EN_BEFORE + 2 - DTR07_KEYS_EN_AFTER))" -eq 8
test "$((DTR07_KEYS_DE_BEFORE + 2 - DTR07_KEYS_DE_AFTER))" -eq 8
test "$((DTR07_KEYS_AR_BEFORE + 2 - DTR07_KEYS_AR_AFTER))" -eq 8
test "$DTR07_KEYS_EN_AFTER" -eq 982
test "$DTR07_KEYS_DE_AFTER" -eq "$DTR07_KEYS_EN_AFTER"
test "$DTR07_KEYS_AR_AFTER" -eq "$DTR07_KEYS_EN_AFTER"

# (b) Compare all tracked working-tree deletions (staged and unstaged) with the
# pre-edit dirty-tree baseline. During this shared-tree execution, Plan 280
# concurrently deleted its two exact in-scope paths after the baseline was
# captured. Source-verify that attribution, then require the newly deleted
# delta to be exactly Plan 286's eight paths plus those two Plan-280 paths.
rg -n 'lib/features/groups/application/leave_group_and_delete_local_history_use_case\.dart' \
  Test-Flight-Improv/280-superseded-leave-local-history-coordinator-removal-tdd-plan.md
rg -n 'test/shared/helpers/legacy_group_exit_coordinator_fixture\.dart' \
  Test-Flight-Improv/280-superseded-leave-local-history-coordinator-removal-tdd-plan.md
DTR07_DELETED_AFTER=$(git diff HEAD --name-only --diff-filter=D | LC_ALL=C sort)
test -z "$(comm -23 \
  <(printf '%s\n' "$DTR07_DELETED_BEFORE" | sed '/^$/d') \
  <(printf '%s\n' "$DTR07_DELETED_AFTER" | sed '/^$/d'))"
diff -u \
  <(printf '%s\n' \
    lib/features/groups/presentation/screens/group_list_screen.dart \
    lib/features/groups/presentation/screens/group_list_wired.dart \
    lib/features/groups/presentation/widgets/group_card.dart \
    test/features/groups/presentation/group_card_bidi_test.dart \
    test/features/groups/presentation/group_card_test.dart \
    test/features/groups/presentation/group_list_screen_bidi_test.dart \
    test/features/groups/presentation/group_list_screen_test.dart \
    test/features/groups/presentation/group_list_wired_test.dart \
    lib/features/groups/application/leave_group_and_delete_local_history_use_case.dart \
    test/shared/helpers/legacy_group_exit_coordinator_fixture.dart \
    | LC_ALL=C sort) \
  <(comm -13 \
    <(printf '%s\n' "$DTR07_DELETED_BEFORE" | sed '/^$/d') \
    <(printf '%s\n' "$DTR07_DELETED_AFTER" | sed '/^$/d'))

# Attribute Plan 286 itself from the real index: exactly its eight approved
# paths are staged, while the concurrent Plan-280 paths remain unstaged.
diff -u \
  <(printf '%s\n' \
    lib/features/groups/presentation/screens/group_list_screen.dart \
    lib/features/groups/presentation/screens/group_list_wired.dart \
    lib/features/groups/presentation/widgets/group_card.dart \
    test/features/groups/presentation/group_card_bidi_test.dart \
    test/features/groups/presentation/group_card_test.dart \
    test/features/groups/presentation/group_list_screen_bidi_test.dart \
    test/features/groups/presentation/group_list_screen_test.dart \
    test/features/groups/presentation/group_list_wired_test.dart \
    | LC_ALL=C sort) \
  <(git diff --cached --name-only --diff-filter=D | LC_ALL=C sort)
# Any unclassified tracked deletion still fails whether or not it was staged.

# Registration is grep-verified, never run-verified (family gates swallow --list).
grep -c 'group_list_wired_test\.dart' scripts/run_test_gates.sh    # expect: 0
grep -c 'integration_test/loading_states_smoke_test\.dart' scripts/run_test_gates.sh  # expect: 1
grep -c 'test/features/loading_states_smoke_test\.dart' scripts/run_test_gates.sh     # expect: 1
./scripts/run_test_gates.sh completeness-check                     # expect: PASS, 0 unmatched

# Curated and affected family gates; expect exit 0 and target selection.
GIT_INDEX_FILE="$DTR07_INDEX_PATH" ./scripts/run_test_gates.sh runtime-roots
test -d "$DTR07_INDEX_DIR" && rm -r -- "$DTR07_INDEX_DIR"
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh feed
./scripts/run_host_test_gates.sh feature-host-all \
  --batch-flutter --concurrency 4 --reporter failures-only

# Hygiene; expect zero analyzer issues and no whitespace errors.
./scripts/check_flutter_analyze_strict.sh
git diff --check

# Mandatory closure refresh for a coherent app-owned code change
# (AGENTS.md:25 and CLAUDE.md; plans 275 and 276 both run it). Expect exit 0.
# Run from the repo ROOT — never with cwd inside graphify-arch/, which would
# clobber the arch graph with a graph of its own meta files.
./graphify-arch/refresh_arch_graph.sh --incremental
```

## Rollback

- Reversible by: `git revert` of the single atomic commit. Every change is
  source, test, manifest, ARB, or documentation text.
- Restore order matters only in one direction: restore the three sources and
  their three `runtime_roots.json` declarations **together**, or
  `check_runtime_root_inventory.sh check` reports `stale-declaration` drift in
  one direction and an unexplained root in the other.
- A partial rollback that restores the sources without re-adding the eight ARB
  keys will fail `flutter analyze` on undefined l10n getters; restore ARB keys
  and regenerate l10n in the same step.
- What a PRIOR shipped build does with post-change data: **N/A** — this plan
  changes no schema, wire format, key material, persisted state, native
  boundary, or Go boundary. No released client can observe the difference.
- NOT recoverable once landed: nothing. The deleted code has no runtime,
  persistence, or protocol footprint; the retired `de group-list row` ICU
  assertion is recoverable from git history but has no surface to run against
  once the island is gone.
- Staging: none required. This is a host-only, behavior-neutral deletion behind
  an owner receipt; no kill switch or staged rollout applies.

## Execution Interpretation And Done Criteria

- Expected RED: after the test-only scaffold, TC-286-01, TC-286-03, and
  TC-286-07 fail **only** because the three island sources, their three manifest
  declarations, and the eight ARB keys still exist.
- GREEN sentinel: the Orbit toggle/list/entry suites, the exit-diagnostic and
  entry-surface guards, flow-event scrubbing, ambient leakage, and the group
  conversation backlog selector all remain green throughout.
- Pre-existing dirty tree / known failure: the working tree carries unrelated
  in-flight DTR and Move-Feature changes at planning time. Execution must record
  and preserve them; do not stash or revert `/workspace`.
- Environment blocker (NOT a product blocker): none. This plan is host-only —
  no device, simulator, relay, emulator, or SQLCipher target participates, so no
  hardware is `N/A (target unavailable by project policy)` either.
- Scope drift (BLOCKING): any need to edit `orbit_screen.dart`,
  `orbit_wired.dart`, `group_row.dart`, `feed_wired.dart`, `main.dart`,
  `leave_group_use_case.dart`, `group_backlog_retention_notice.dart`, or any
  backend, schema, native, Go, or relay surface stops execution and requires a
  new plan.

- [x] `DTR07-AUTH-01` is recorded (2026-07-26); execution re-verifies it
      matches the exact removal set before the first edit.
- [x] Every behavior has a named test or a justified proof.
- [x] Causal RED, focused GREEN, and representative mutation re-red are recorded.
- [x] Preservation sentinels and named gates pass with semantic outcomes.
- [x] Harness registration is implemented AND grep-verified, and
      `completeness-check` reports zero unmatched paths.
- [x] Every island-dependent assertion is dispositioned migrate/retire with a
      named live owner — none silently deleted.
- [x] No schema, migration, native, Go, relay, or device surface changed.
- [x] Strict analysis has no new DTR-07 issue and `git diff --check` is clean.
      The repository-wide strict command's sole remaining warning is in the
      concurrently edited Plan-285 account-migration test and is recorded
      below; it is not attributed to or hidden by this plan.
- [x] The Scope Contract And Guard is respected.

## Handoff

- **Complete / Plan-green.** `DTR07-AUTH-01` is recorded in the roadmap
  decision ledger (Approved 2026-07-26), and the reviewed boundary is
  implemented.
- First causal RED command:
  `flutter test --no-pub test/unit/runtime_root_inventory_test.dart --plain-name 'DTR-07 retires the Group-list UI island and preserves the Orbit all-chats replacement'`.
- Contract size: 15 rows — TC-286-01/03/04/07/12/14 are causal REDs;
  TC-286-02/05/06/08/09/10/11/13/15 are GREEN sentinels. TC-286-02 is a
  *transitional* red (intermediate state only), not a HEAD red.
- Preservation command:
  `flutter test --no-pub test/features/orbit/presentation/screens/orbit_view_split_test.dart test/features/orbit/presentation/screens/orbit_wired_test.dart`.
- Manual registration: `classify_path` needs **no** edit — the five deleted
  suites match the generic feature-local pattern rather than an explicit
  `record` line, and `completeness-check` enumerates *existing* files, so a
  deleted path cannot fail it. One **removal** (`GROUP_TESTS`,
  `run_test_gates.sh:368`);
  two entries deliberately **retained** (`BASELINE_TESTS:12`,
  `OUT_OF_GATE_TESTS:737`) because those files are edited, not deleted. Both new
  tests live in existing files and inherit their registration.
- Migration: none. No `DB v##`; no schema, table, or `user_version` change.
- Boundary closure: host-only.
- Unresolved DTR-07 evidence: none.

## Wave 2 Acceptance Addendum

Plan 286 remains Plan-green. Its DTR-07 registry row and Wave 2 were promoted
separately to `Wave-accepted` on 2026-07-27 after the complete aggregate
`host-all` retry passed.

Three completed attempts each covered 1,259 exact Dart paths plus eight Go
tails (1,267 planned items) at concurrency 4. The first completed non-green
attempt exposed one missing Android-harness discovery classification, one
fixed-sleep test timing race, and seven already-authorized terminal DTR-10
deletions that were still unstaged. The closure correction changed only the
discovery script and a test, then staged exactly those seven already-deleted
later-wave paths; no production source changed. A temporary copied-index
alternative was rejected because repository guards correctly prohibit
`GIT_INDEX_FILE`.

The normal-environment acceptance attempt exited 0 with Flutter `+12,827 ~1`,
all eight Go tails passed, and
`PASS: host tests completed for scope: host-all`. The tested state was Git
`95d754e03fc67e21d5006efd1fbec2dddaada394` plus the integrated uncommitted
working-tree delta, including Plan 286 and later DTR-10/Plan-285 work. The
accepted original-log SHA-256 is
`869a75236f97e34f610b4053540f7e7b449ea76103f5d807d52c82aae5d4c135`;
all completed attempts are preserved in the
[Wave 2 evidence archive](evidence/dtr-wave2/README.md). Final-rollout
`host-all` remains a later, separate gate.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-26 CEST | Review + RED | Plan contract; new absence/l10n/wiring tests; Orbit relative-time sentinel | Causal selectors failed on 11 runtime remnants, all eight retired keys in every locale/generated API, and the fifth obsolete media-wiring path; the Orbit sentinel passed before production edits | Initial review verdict was `plan-fixes-required`; only the necessary audit fixes were applied, then all five lenses cleared | none | Implement the exact authorized boundary |
| 2026-07-26 CEST | Implementation | Three production sources; five SUT-only suites; runtime manifest; `GROUP_TESTS`; eight guard/harness files; three ARBs + generated API; current docs and Plans 279/280 | `flutter gen-l10n`; exact eight approved deletions staged; every locale removed exactly the eight DTR-07 keys while concurrent Plan 285 added its two authorized keys (net 988 → 982) | Orbit/Feed/current navigation remained untouched; the retired ICU and loading legs were dispositioned against named live owners | none | Focused GREEN and mutation proof |
| 2026-07-26 CEST | Focused + mutation | TC-286-01 through TC-286-15 surfaces | Focused contracts and preservation selectors passed; restoring `group_card.dart` plus its manifest declaration re-red both the causal contract and census, then GREEN returned | 146 Orbit preservation tests passed across the full view/wiring and loading suites; all remaining diagnostic, privacy, loading, ICU, and retention selectors passed | none | Curated/family gates |
| 2026-07-26 CEST | Gates + closure | Runtime roots, groups, feed, feature family, registration, graph | `runtime-roots`: 18/18 and `trustworthy:true`, `drift:false`; `groups`: 3,238 Flutter tests plus every Go tail; `feed`: 310; stabilized feature replay: 8,476 pass, 1 skip, 0 fail across 816 paths; completeness 1,349/1,349; Graphify incremental refresh exit 0 | The first feature run observed 11 moving-tree failures while its inventory changed 788 → 816; the stabilized JSON replay is the authoritative result. TC-286-15 explicitly attributes the two concurrent Plan-280 deletions and proves Plan 286 owns exactly eight cached deletions | none | Wave-2 aggregate `host-all` remains a wave-level obligation |
| 2026-07-26 CEST | Hygiene | Repository analyzer/diff | DTR-07 runtime contract fatal-warning analysis: no issues; `git diff --check`: pass; repository strict ratchet: pass with one unrelated `unused_element_parameter` warning in concurrently edited `account_migration_bundle_transfer_test.dart:2725` | No DTR-07 analyzer issue; the shared Plan-285 warning remains visible for its owner and is not a per-plan code defect | none for DTR-07 | Hand off the aggregate wave gate |
| 2026-07-27 CEST | Wave 2 acceptance | Complete integrated `host-all`; closure-only discovery/test correction; exact terminal DTR-10 deletion staging | Accepted attempt: 1,267/1,267 planned items; Flutter `+12,827 ~1`; Go 8/8; final scope PASS marker; exit 0 | Plan 286 remains Plan-green; the DTR-07 registry row and Wave 2 are Wave-accepted. All completed logs and hashes are archived under `evidence/dtr-wave2/` | none | Final-rollout `host-all` remains separate |
