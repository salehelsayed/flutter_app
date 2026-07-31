# 311 - Remove the `GroupType.qa` (Q&A) Group Type

Status: execution-ready (v2 — `$tdd-review` applied 2026-07-31)
Type: Modification (dead-feature removal)
Spec: free-text intent (no formal spec) — derived from the group-notification review that identified `qa` as an unreachable type
Classification: implementation-ready
Closure tier: host

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-31 | Evidence Collector | `group_model.dart`, `orbit_screen.dart`, `handle_incoming_group_invite_use_case.dart`, `group_type_badge.dart`, the three policy switches, both CHECK-constraint migrations, `l10n_integrity_test.dart` | Removal is safe *only* if the persisted-read path stops throwing on an unknown type | Full census + read-path hazard analysis |
| 2026-07-31 | Planner | `pending_group_invite.dart`, `group_message_listener_system_transition_processor.dart`, `background_message_handler.dart`, `l10n.yaml` | Blanket-defaulting `fromValue` would silently change system-transition behaviour → use an explicit `tryFromValue` + per-call-site fallback instead | Emit plan |
| 2026-07-31 | `$tdd-review` (3-worker adversarial audit) | `group_reaction_notification_projection.dart`, `NotificationPreviewResolver.swift`, `group_repository_impl.dart`, `go-mknoon/{node/group.go,bridge/bridge.go,bridge/bridge_test.go}`, `run_test_gates.sh`, `017_018_group_original_tables_test.dart`, `051_pending_group_invites_test.dart`, `group_message_listener_test.dart` | **v1 returned `not-ready`.** Two guards against the plan's own forbidden implementation were phantom (TC-06 had no test and was not in Step 1's write list; TC-07's named file cannot exist — the source is `part of` and its class is private), TC-09 named a nonexistent file, the "closes an Android/iOS divergence" premise was refuted, and the named `groups` gate has two Go legs the plan claimed it did not have | v2: all deltas applied below |

## Problem And Evidence

- **Behavior to improve:** `GroupType.qa` is a third group type that no shipped build can create, yet it costs live code in **five** production files (8 symbol references), a localized badge in three locales, a permissive schema CHECK in two migrations, a string in the Android push allow-list, and 21 references across 16 test files.
- **Impact:** carrying an unreachable enum value forces every future `switch (GroupType)` to handle a case that cannot occur, and leaves three independent allow-lists (Dart enum, Android push string set, Go bridge) free to drift from one another.
- **NOT the justification (refuted in review — do not re-introduce):** "removing `qa` closes a latent Android/iOS notification divergence." It does not. `lib/core/notifications/group_reaction_notification_projection.dart:1045-1046` already excludes `qa` from the iOS projection, so iOS suppresses today while Android's raw-string set at `background_message_handler.dart:1294-1296` accepts. Removing `'qa'` from the Android set *plus* the Step-3 fallback (which launders a persisted `'qa'` row into `chat` before the projection sees it) would **invert** that polarity, not close it. **Because no user has a qa group** — the only ingress needs a modified peer, see below — neither polarity is user-visible, and Step 6 is retained purely as dead-string tidy-up. Do not describe it as a divergence fix.

### Confirmed current state (re-verified in source, counts re-derived — do not trust the intake numbers)

**The type is unreachable in any shipped build.**
- The only group-creation entry points are the Orbit FAB's two items: "New group" → `GroupType.chat` and "New announce" → `GroupType.announcement` (`lib/features/orbit/presentation/screens/orbit_screen.dart:946,951`). No production code constructs `GroupType.qa`.
- The only ingress is an inbound invite carrying the literal wire string `"qa"`: `handle_incoming_group_invite_use_case.dart:967` reads `config['groupType']` from the peer-supplied payload, `:992` parses it via `_parseGroupType` (`:1417-1428`, which maps `'qa'` → `GroupType.qa` today), and `:1081` persists the `GroupModel` — and both CHECK constraints admit `'qa'`, so the row lands. **This path requires a modified/non-shipped peer**, because every Dart emitter serialises through `group.type.toValue()` and the shipped UI can only produce `chat`/`announcement`. **Accepted as the product reality: no user has a working qa group.** The parser already defaults anything unrecognized to `chat` (`:1426-1427`), so the ingress is closed by deleting the `case 'qa':` arm.

**Exact census — `GroupType.qa` symbol references: 8 in `lib/`, 21 across 16 test files.**

| # | Site | What it does | Post-removal |
|---|---|---|---|
| 1 | `lib/features/groups/domain/models/group_model.dart:17-18` | `fromValue` maps `'qa'` → `GroupType.qa` | delete the case |
| 2 | `lib/features/groups/application/handle_incoming_group_invite_use_case.dart:1423-1424` | `_parseGroupType` maps `'qa'` → `GroupType.qa` | delete the case; `default: return GroupType.chat` (`:1425-1426`) already absorbs it |
| 3 | `lib/features/groups/application/group_media_forward_policy.dart:71` | `group.type == GroupType.qa` → not a forward target | delete the clause (**compile error until edited**) |
| 4 | `lib/features/groups/application/group_private_media_availability.dart:56` | `GroupType.qa => false` in an exhaustive `switch` (`:52`) | delete the arm (**compile error until edited**) |
| 5 | `lib/features/groups/application/group_media_batch_forward.dart:515` | `GroupType.qa => null` in an exhaustive `switch` | delete the arm (**compile error until edited**) |
| 6-8 | `lib/features/groups/presentation/widgets/group_type_badge.dart:48,58,69` | three `case GroupType.qa:` arms (colour ×2, label ×1) | delete all three (**compile error until edited**) |

**Literal `'qa'` strings in `lib/` (5), which the enum census does not catch:**
- `lib/core/database/migrations/017_groups_tables.dart:11` — `type TEXT NOT NULL CHECK(type IN ('chat','announcement','qa'))`
- `lib/core/database/migrations/051_pending_group_invites.dart:12` — `group_type TEXT NOT NULL CHECK(group_type IN ('chat','announcement','qa'))`
- `handle_incoming_group_invite_use_case.dart:1423` and `group_model.dart:17` (the two `case 'qa':` arms above)
- `lib/features/push/application/background_message_handler.dart:1294-1296` — `(groupType != 'chat' && groupType != 'announcement' && groupType != 'qa')`, a **string** comparison against the raw `groups.type` column read at `:1282` (row from `dbLoadGroup`), so it does not break at compile time. It never constructs a `GroupModel`, so the Step-3 enum fallback is structurally unreachable from it.

**Third census class the symbol grep and the literal grep BOTH miss — positive allow-lists that exist only because a third type exists.** None of these produce a compile error (`flutter analyze` does not flag a tautological enum comparison, and `analysis_options.yaml` adds no lint that would), and none contain the string `'qa'`, so neither TC-13 grep nor Step 5's `flutter analyze` can surface them. **This plan does not edit any of them** (see Hard `Do not`), but they are recorded so the executor does not mistake them for undiscovered sites and so the tautology is a known landmine:

| Site | Shape today | After removal |
|---|---|---|
| `lib/core/notifications/group_reaction_notification_projection.dart:1045-1046` | `_supportedGroupType(t) => t == chat \|\| t == announcement`, called at `:153`, `:311`, `:421` | **tautology** — three guards stop guarding. This is the file that actually decides iOS notification eligibility (the Swift guards at `NotificationPreviewResolver.swift:776`/`:998` never see a `qa` group). Add a third type later and all three sites silently admit it. |
| `lib/features/groups/application/group_private_media_availability.dart:24` | `groupType == chat \|\| groupType == announcement` | tautology |
| `group_media_forward_policy.dart:52`, `:110`, `:476-477` | `!= chat && != announcement` | dead branches (same file the plan edits at `:71`) |
| `send_group_message_use_case.dart:1012-1013`, `:1029-1030`, `:1400` | `!= chat && != announcement` | dead branches |
| `group_received_media_action_policy.dart:40` (+ stale doc comment `:17` "QA surfaces") | `!= chat && != announcement` | dead branch |
| `group_info_screen.dart:262-263`, `group_info_wired.dart:2601-2602`, `group_conversation_wired.dart:6432-6433` | `== chat \|\| == announcement` | tautologies |

**Native (Go) layer — out of scope, recorded as a deferred difference.** `go-mknoon` owns a parallel enum: `node/group.go:11` `GroupTypeQA GroupType = "qa"`; `bridge/bridge.go:1815` `isSupportedBridgeGroupType` accepts it; `:1709` documents the wire contract as `"chat"|"announcement"|"qa"`; `bridge/bridge_test.go:1965` is a **live green test** iterating `[]string{"chat","announcement","qa"}`; `node/pubsub_test.go:858` uses `GroupTypeQA`; the doc string is baked into the checked-in `ios/Runner/GoMknoon.xcframework/*/Headers/Bridge.objc.h:133`. No runtime hazard — the Go acceptance is reachable only from local `GroupCreate` (`bridge.go:1751`), which Dart always calls with `type.toValue()`.

**Localization (3 locales + generated API) — 9 `group_type_qa` lines, not 8:** `lib/l10n/app_en.arb:981` ("Q&A"), `app_ar.arb:932`, `app_de.arb:932`, the generated `app_localizations.dart:3325`+`:3329`, `app_localizations_en.dart:1948`, `app_localizations_ar.dart:1976`, `app_localizations_de.dart:1994`, **and the consumer `group_type_badge.dart:70`** (`return l10n.group_type_qa;`, inside the `case` arm at `:69` that Step 5 already deletes). Generation is configured in `l10n.yaml` (`arb-dir: lib/l10n`, template `app_en.arb`), so the generated files are rewritten by `flutter gen-l10n`, not hand-edited.

### The one real hazard: `GroupType.fromValue` throws on an unknown value

`fromValue` (`group_model.dart:11-23`) ends in `default: throw ArgumentError('Unknown GroupType: $value')`. It has **four** production call sites; only **two** are genuinely unguarded (v1 said three — corrected in review):

| Call site | Reads | Guarded today? | Post-removal risk |
|---|---|---|---|
| `group_model.dart:154` (`GroupModel.fromMap`) | the `groups.type` **column** | **no** | a persisted `'qa'` row throws on every read → the group becomes unloadable |
| `pending_group_invite.dart:54` (`fromMap`) | the `pending_group_invites.group_type` **column** | **no** | same |
| `pending_group_invite.dart:156` | a wire value, `fromValue(value ?? 'chat')` | **yes** — `:154-160` wraps it in `try { … } catch (_) { return GroupType.chat; }` | already safe; **needs no edit** |
| `group_message_listener_system_transition_processor.dart:3711-3719` | a wire `groupConfig['groupType']` | **yes** — `try { … } on ArgumentError { resolvedType = group.type; }` | already safe. Note it does not merely *read*: `:3776-3781` writes `resolvedType` back, so this is also a normalization path |

Both CHECK constraints still *permit* `'qa'` (`017:11`, `051:12`), so the schema will not stop such a row existing. **Removing the enum value without fixing the read path converts a harmless dead type into a crash-on-read.**

**Why a blanket default is the wrong fix.** Making `fromValue` return `chat` for unknown values would silently change the fourth call site: today an unparseable wire type leaves the group's existing type intact (`resolvedType = group.type`); with a blanket default it would reclassify an **announcement** group as **chat**. The fallback must therefore be chosen *per call site*, not hidden in the parser.

### Existing coverage
- `test/features/groups/domain/models/group_model_test.dart:87-94` (`GroupType enum converts correctly`) round-trips all three enum values (this is the test that must change).
- `test/l10n/l10n_integrity_test.dart` already enforces ARB key-set parity across locales (`:10-44`) **and** carries an established "retired keys are absent from every locale and the generated API" pattern — `DTR-04` (`:45`) and `DTR-07` (`:93`). This plan reuses that exact pattern for `group_type_qa`.
- `test/features/groups/presentation/group_type_badge_test.dart` has **two** tests: the label test at `:19-26` (which asserts `find.text('Q&A')` for `GroupType.qa` and is the only colour/label proof) and a `GroupType.values` loop at `:29-35` that only asserts `find.byType(GroupTypeBadge)` renders. `test/features/feed/domain/models/feed_item_test.dart:852-863` also iterates `GroupType.values`. None break at compile time; all silently cover one fewer case after removal.
- `test/core/database/migrations/017_018_group_original_tables_test.dart` (**this is the real 017 test file — there is no `017_groups_tables_test.dart`**) already proves the `groups.type` CHECK on `sqflite_common_ffi`: `enforces original constraints and remains idempotent` (`:200-221`) inserts `type: 'broadcast'` and expects `throwsA(isA<DatabaseException>())`, using the parameterized `baselineGroupRow({id, name, type, topicName, myRole})` builder at `:46-62`.
- `test/core/database/migrations/051_pending_group_invites_test.dart` exists (`:23` group; tests at `:24`, `:33`, `:64`) but has **zero** CHECK-constraint coverage.

### Missing coverage
- **Nothing asserts what happens when a persisted or wire group type is unrecognized.** No test feeds an unknown string to `GroupModel.fromMap` or `PendingGroupInvite.fromMap`. This is the gap that makes the removal risky, and closing it is the substance of this plan.
- **Nothing asserts that `GroupType.fromValue` throws.** Verified: `grep -rn 'Unknown GroupType\|throwsArgumentError' test/features/groups/domain/models/group_model_test.dart` returns nothing, and the only hit for `Unknown GroupType` across `lib test integration_test` is `group_model.dart:20` itself. **TC-06 is therefore a NEW test, not an existing one** — it must be authored in Step 1 or the plan's headline "Do not make `fromValue` non-throwing" guard does not exist.
- **Nothing tests the system-transition retain-existing-type guard directly.** There is no `*_system_transition_processor_test.dart` and there cannot be: `group_message_listener_system_transition_processor.dart:1` is `part of 'group_message_listener.dart';` and its only declaration is the private `_SignedTransitionAuditActorBinding` (`:3`). The reachable harness is `test/features/groups/application/group_message_listener_test.dart`, which already drives system transitions with `groupConfig['groupType']` at `:1682-1684`, `:1714-1716`, `:1772-1774`, `:1825-1827` (all `'chat'`).
- **Nothing calls `GroupMediaForwardPolicy.canTargetGroup` from a test.** Verified: every caller is in `lib/` (`share_batch_delivery_coordinator.dart:1052`/`:1133`, `share_target_picker_wired.dart:297`, `group_media_batch_forward_picker_wired.dart:107`/`:119`). Its archived/dissolved clause is unguarded at the unit level — and it is the clause Step 5 edits.
- No test asserts the Android push handler's accepted group-type set.

### Refuted findings (do NOT re-introduce)
| Finding | Why refuted |
|---|---|
| "A DB migration is needed to rewrite `type='qa'` rows" | Unnecessary and higher-risk than the read-path fallback. SQLite cannot alter a CHECK constraint without a full table rebuild, and the constraints are *permissive* — they never reject a valid value. With the fallback in place, a legacy `'qa'` row reads as `chat`, and the first read-modify-write persists `'chat'` via `toValue()`. A migration would add a `DB v##`, a rebuild, and a rollback hazard to buy nothing the fallback does not already give. **Do not add one.** |
| "Removing the value is a compile-safe no-op because nothing creates it" | False. **Five** production files reference the symbol in exhaustive switches or `==` comparisons and will fail to compile — which is useful, but it means "delete the enum value" is not a one-line change. |
| "`group_type_qa` can be deleted from `app_en.arb` alone" | False. `l10n_integrity_test.dart:10-44` asserts identical key sets across `en`/`ar`/`de`; deleting from one locale reds it. All three plus a `flutter gen-l10n` regeneration are required. |
| "The system-transition call site needs no attention" | It is already guarded (`:3711-3719`), but its `on ArgumentError` catch becomes **dead code** if `fromValue` ever stops throwing. This plan keeps `fromValue`'s throwing contract precisely so that guard stays live and its behaviour (keep the existing type) is preserved. |
| "`flutter analyze` is a sufficient exhaustiveness proof for this removal" | False, in two directions. It **over**-reports (it analyzes `test/` too, so 16 test files error) and it **under**-reports (it cannot see the ~12 positive allow-lists in the third census class, nor the Go layer). Use it for the five lib files only; the other two classes are covered by the census table above, not by a tool. |
| "Removing `'qa'` from the Android push set closes the Android/iOS notification divergence" | False and backwards. See the Problem statement. iOS already suppresses `qa` via the Dart projection writer; the change inverts the polarity rather than closing it. Moot in practice (no qa groups exist), retained only as dead-string tidy-up. |
| "The persisted-`'qa'` population is empty, so the read fallback is optional" | The *user* population is empty (accepted, and it is why Step 6 is harmless), but the code path is live: `handle_incoming_group_invite_use_case.dart:967→992→1081` persists a peer-supplied `groupType`. The fallback is what keeps a deleted enum value from becoming a crash-on-read, and it stays. |

### Unresolved findings
None. Two review-surfaced decisions are closed: convergence direction (moot — no qa groups exist; keep Step 6 as tidy-up, drop the divergence framing) and Go scope (deferred with a recorded difference).

### Affected production / test / gate files
- `lib/features/groups/domain/models/group_model.dart` (enum + `fromValue` + new `tryFromValue` + `fromMap`)
- `lib/features/groups/domain/models/pending_group_invite.dart` (**one** read site — `:54`; `:156` is already guarded)
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `group_media_forward_policy.dart`, `group_private_media_availability.dart`, `group_media_batch_forward.dart`
- `lib/features/groups/presentation/widgets/group_type_badge.dart`
- `lib/features/push/application/background_message_handler.dart` (string set)
- `lib/l10n/app_en.arb`, `app_ar.arb`, `app_de.arb` + regenerated `app_localizations*.dart`
- **Read-only, NOT edited (census-recorded so the executor does not "fix" them):** `lib/core/notifications/group_reaction_notification_projection.dart` and the other ~11 allow-list guards; the whole `go-mknoon/` layer.
- Tests: `group_model_test.dart`, `pending_group_invite_test.dart`, `group_type_badge_test.dart`, `l10n_integrity_test.dart`, `background_message_handler_test.dart`, `group_message_listener_test.dart`, `handle_incoming_group_invite_use_case_test.dart`, `017_018_group_original_tables_test.dart`, `051_pending_group_invites_test.dart`, `group_media_forward_policy_test.dart`, plus the 16 test files carrying `GroupType.qa` references
- Gate: `scripts/run_test_gates.sh` (`GROUP_TESTS`, 375-688) — `background_message_handler_test.dart` is in **zero** curated arrays today (`grep -c` = 0, re-verified)

## Graph Grounding Snapshot
- Graph fingerprint / freshness: `6f47d12c12806538`, current after `/claude-host-bin/host-run bash ./graphify-arch/refresh_arch_graph.sh --incremental` (0 changed code, 2917 unchanged). **The `graphify` CLI is absent inside the container — refreshes go through the host bridge.**
- Query / profile: `python3 graphify-arch/tdd_context.py query "GroupType qa group_model fromValue group_type_badge" --profile tdd --budget 700`.
- Anchors: `GroupType` → `lib/features/groups/domain/models/group_model.dart:2`.
- Surfaced proof/gate files: `group_model_test.dart`, `group_type_badge_test.dart`.
- Graph gaps that required raw source search — **three classes, all invisible to a symbol graph:**
  1. **The literal-string census.** None of the five `'qa'` string sites surfaced — including the two migration CHECK constraints and the Android push handler's comparison, the ones a symbol-only removal leaves behind. The l10n key set and the generated-localization files were likewise invisible.
  2. **The positive allow-lists** (`_supportedGroupType` and the ~11 `== chat || == announcement` / `!= chat && != announcement` guards). These reference `GroupType` but never `GroupType.qa`, so neither the graph nor `grep 'GroupType\.qa'` nor `flutter analyze` finds them. Found only by grepping the *comparison shape*: `grep -rn 'type != GroupType\.\|type == GroupType\.' lib`.
  3. **The Go layer.** `go-mknoon/node/group.go:11` `GroupTypeQA` is a separate language's parallel enum; no Dart-symbol graph can reach it. Found by `grep -rn 'GroupTypeQA\|"qa"' go-mknoon --include=*.go`.
- The review pass that found (2) and (3) started from `python3 graphify-arch/tdd_context.py query "GroupType qa group_model fromValue group_type_badge pending_group_invite background_message_handler" --profile review --budget 800`, whose caller/bypass candidates surfaced `lib/core/notifications/group_reaction_notification_projection.dart` — the file v1's census missed entirely.
- Reuse rule: anchors are search starting points; every conclusion here came from direct source reads.

## Scope Contract And Guard

**In scope:**
- Delete `GroupType.qa` and every symbol reference (**5** production files, 16 test files).
- Add `GroupType.tryFromValue` returning `GroupType?`, and convert the **two** genuinely unguarded read sites (`group_model.dart:154`, `pending_group_invite.dart:54`) to explicit per-site fallbacks.
- Remove `group_type_qa` from all three ARB files and regenerate the localizations.
- Remove `'qa'` from the Android push handler's accepted string set (dead-string tidy-up, **not** a divergence fix).

**Must preserve:**
- `GroupType.fromValue` keeps throwing `ArgumentError` on an unknown value → `TC-06`. **This test does not exist today and must be authored in Step 1** — it is the primary guard against the blanket-default regression.
- The system-transition guard (`:3711-3719`) stays live and keeps the group's existing type → `TC-07` (retargeted to a harness that exists).
- `chat` and `announcement` round-trip unchanged → `TC-05` (GREEN sentinel).
- The badge renders the right colour and label for both surviving types → `TC-08` (GREEN sentinel).
- Both migration CHECK constraints stay exactly as they are → `TC-09` (groups) + `TC-14` (pending invites).
- `canTargetGroup` still rejects archived and dissolved groups → `TC-15` (GREEN sentinel). This is what makes the `:71` edit safe.

**Hard `Do not`:**
- Do not add a DB migration or alter either CHECK constraint (see Refuted findings).
- Do not make `fromValue` non-throwing — that silently changes the system-transition call site.
- Do not "simplify" `group_message_listener_system_transition_processor.dart:3711-3719` into `tryFromValue(v) ?? GroupType.chat`. That keeps `fromValue` throwing (so TC-06 stays green) while reclassifying an **announcement** group as **chat** on a garbled wire type, and `:3776-3781` then persists it. `TC-07` is the only thing that catches this.
- Do not hand-edit `lib/l10n/app_localizations*.dart`; they are generated.
- Do not change forwarding, private-media, or notification behaviour for `chat` or `announcement`. At `group_media_forward_policy.dart:71`, delete **only** the `|| group.type == GroupType.qa` clause — deleting the whole `if` would make archived and dissolved groups valid forward targets (`TC-15`).
- **Do not touch the ~12 positive allow-list guards** in the third census class, and do not touch `go-mknoon/`. Both are recorded deferred differences, not undiscovered sites. Widening into them turns a bounded removal into a 9-file behavioural refactor with no sentinels.

**Deferred / accepted difference:**
- The two CHECK constraints keep listing `'qa'` as an allowed value. Accepted: they are permissive, altering them needs a table rebuild, and `TC-09`/`TC-14` lock them so the difference is deliberate and visible rather than forgotten.
- A row persisted as `'qa'` reads as `chat` rather than being rewritten in place. Accepted, with two corrections to v1's wording: (a) **only a `groups`-row write normalizes it** (`group_repository_impl.dart:371-373` → `toMap()` → `dbUpdateGroup`, a full-row replace) — a group that merely *receives messages* is never rewritten, so such a row can persist indefinitely; (b) the Step-3 fallback **promotes** such a row to full `chat` privileges — it becomes a valid forward target (`forward_policy:71`), a private-media author surface (`private_media_availability:52-57`), and a batch-forward source (`batch_forward:511-515`). Both are accepted because no user has a qa group.
- **The ~12 positive allow-lists become tautologies or dead branches** and are left in place. Accepted: each already returns the identical answer for `chat`/`announcement`, so nothing changes behaviourally today. Recorded risk: `_supportedGroupType` (`group_reaction_notification_projection.dart:1045-1046`) *looks* like a filter and will not be one — whoever adds a third `GroupType` must re-audit all ~12 sites, because the compiler will not.
- **`go-mknoon` keeps `GroupTypeQA`.** Accepted: no runtime hazard (Dart can only send `type.toValue()`), and `bridge_test.go:1965` is a live green contract test pinning it. The consequence is that after this plan the Dart client can no longer *represent* a type the Go bridge still *accepts* — a documented cross-layer difference, not a closed one. Owner: whoever next touches `go-mknoon/bridge`.

**Dependencies:**
- Independent of plan 309 — confirmed by 309's own guard: `309-group-notification-reliability-tdd-plan.md:123` ("Do not touch `GroupType.qa` behaviour in either direction — owned by the separate removal plan") and `:298` (Scope drift BLOCKING).
- **But 309 edits the same function.** 309 changes `background_message_handler.dart` in `groupMessageLocalStateFromRows` (309 cites `:1284`, `:1298`) and also touches `group_reaction_notification_projection.dart`. If 309 lands first, `:1294-1296` will have moved: **locate Step 6's edit by the symbol `groupMessageLocalStateFromRows` and the literal `groupType != 'qa'`, never by line number.** 309 also registers `background_message_handler_test.dart` in `GROUP_TESTS`; verify `grep -c` is exactly 1, not 2.

## Test Contract

Zero empty cells. `HEAD state` is one of `causal RED` · `GREEN sentinel` · `manual/device-only proof`.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-01 | `GroupType` has exactly two values, and `'qa'` no longer parses to a distinct type | `test/features/groups/domain/models/group_model_test.dart::GroupType exposes only chat and announcement` | unit host / pure enum | causal RED — **author it in two stages** (see Test Notes): stage 1 asserts only `GroupType.values == [chat, announcement]` (fails today, 3 values, compiles fine); stage 2 adds `tryFromValue('qa') == null` **after Step 2**, because referencing `tryFromValue` before it exists is a compile error, not a causal RED | re-add the enum value → TC-01 red | `flutter test <path>`; AUTO (glob) + `GROUP_TESTS` (curated, `grep -c` = 1) |
| TC-02 | A persisted group row with an unrecognized `type` reads as `chat` instead of throwing | `group_model_test.dart::fromMap falls back to chat for an unrecognized persisted type` | unit host / plain map fixture | causal RED (`GroupModel.fromMap({'type': 'qa', …})` throws `ArgumentError` once the enum case is gone; today it returns `GroupType.qa`, so the assertion fails either way — for the *documented* reason in each direction) → returns `GroupType.chat`, no throw | revert `fromMap:154` to bare `fromValue` → TC-02 red | same as TC-01 |
| TC-03 | A persisted pending-invite row with an unrecognized `group_type` reads as `chat` instead of throwing | `test/features/groups/domain/models/pending_group_invite_test.dart::fromMap falls back to chat for an unrecognized persisted group type` | unit host / plain map fixture | causal RED (`PendingGroupInvite.fromMap` at `:54` throws on unknown) → returns `GroupType.chat` | revert `:54` to bare `fromValue` → TC-03 red | `flutter test <path>`; AUTO (glob). **File exists** (`test/features/groups/domain/models/pending_group_invite_test.dart`) — extend it |
| TC-04 | A wire invite carrying `groupType: "qa"` is materialized as a `chat` group, not rejected | `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart::materializes an unknown wire group type as chat` | unit host / existing invite fixtures + fake bridge. Drives the public use case (the parser at `:1417-1428` is a private top-level function); assert the persisted `GroupModel` at `:1081` | causal RED (today it materializes as `GroupType.qa`) → materializes as `GroupType.chat` and does not throw | delete the `default: return GroupType.chat` arm at `:1426-1427` → TC-04 red | `flutter test <path>`; `GROUP_TESTS` (curated — grep-verify by path, never by line: these line numbers drifted mid-review) |
| TC-05 | `chat` and `announcement` round-trip unchanged | `group_model_test.dart:87-94` (existing `GroupType enum converts correctly`, minus the `qa` lines at `:90`/`:93`) | unit host | GREEN sentinel → still passes | change `toValue()` to emit a different string → TC-05 red | same as TC-01 |
| TC-06 | `fromValue` still throws `ArgumentError` on an unknown value | `group_model_test.dart::fromValue still throws for an unrecognized value` | unit host / `expect(() => GroupType.fromValue('nope'), throwsArgumentError)` | **NEW test that passes on HEAD** — verified absent today (`grep -rn 'Unknown GroupType\|throwsArgumentError'` over `group_model_test.dart` returns nothing). Author it in **Step 1**; it is green immediately and stays green | make `fromValue` return `chat` on unknown → TC-06 red. **This is the primary guard against the blanket-default regression, and it does not exist until it is written** | same as TC-01 |
| TC-07 | A system transition with an unparseable wire `groupType` keeps an **announcement** group's existing type (does **not** become `chat`) | `test/features/groups/application/group_message_listener_test.dart::retains the existing group type for an unparseable wire group type` | unit host / the existing group-message-listener harness — it already drives system transitions with `groupConfig['groupType']` at `:1682-1684`, `:1714-1716`, `:1772-1774`, `:1825-1827`. **v1 named `group_message_listener_system_transition_processor_test.dart`; that file does not exist and cannot** — the source is `part of 'group_message_listener.dart';` (`:1`) and its only class is private (`:3`) | **NEW test that passes on HEAD** (the `on ArgumentError` guard at `:3711-3719` already does this) → still passes. Use an announcement group so the assertion discriminates: a blanket default would yield `chat` | (a) make `fromValue` non-throwing, **or** (b) replace the guard with `tryFromValue(v) ?? GroupType.chat` — either kills it and `:3776-3781` persists the wrong type → TC-07 red. **(b) is invisible to TC-06, so TC-07 is not redundant** | `flutter test <path>`; `GROUP_TESTS` (curated — grep-verify by path, never by line: these line numbers drifted mid-review) |
| TC-08 | The badge renders the correct colour and label for both surviving types | `test/features/groups/presentation/group_type_badge_test.dart:19-26` (the **label** test — `find.text('Discussion')` / `find.text('Announce')`, minus its `GroupType.qa`→`'Q&A'` lines at `:24-25`) | widget / `WidgetTester` | GREEN sentinel → still passes for the two surviving types | change `_labelForType`'s `chat` arm to return `group_type_announce` → TC-08 red. **The `GroupType.values` loop at `:29-35` is NOT this proof** — it only asserts `find.byType(GroupTypeBadge)` renders, which no colour or label change can re-red | `flutter test <path>`; AUTO (glob) — **not** in `GROUP_TESTS` (`grep -c` = 0), so it is reached by the `feature-host-all` sweep and the direct command |
| TC-09 | The `groups.type` CHECK still admits `'qa'` (the accepted difference, locked) | `test/core/database/migrations/017_018_group_original_tables_test.dart::groups type CHECK still admits the retired qa value` | migration host / `sqflite_common_ffi`; extend the existing file — add one `db.insert('groups', baselineGroupRow(id: 'group-qa', topicName: '/mknoon/group/group-qa', type: 'qa'))` **expected to succeed**, alongside the existing `type: 'broadcast'` rejection at `:200-221`. **v1 named `017_groups_tables_test.dart` (does not exist) and `PRAGMA table_info` (which returns only name/type/notnull/dflt/pk and cannot observe a CHECK at all)** — if a shape assertion is wanted, use `SELECT sql FROM sqlite_master WHERE name = 'groups'` | **NEW assertion that passes on HEAD** → still passes | rewrite the CHECK to drop `'qa'` → TC-09 red. Guards against a "tidy the schema too" edit that would need a table rebuild | `flutter test <path>` (direct — `test/core/**` is outside `feature-host-all`); `completeness-check` already classifies it (`classify_path`'s `test/core/**` component rule) |
| TC-10 | `group_type_qa` is absent from every locale ARB **and** the generated API | `test/l10n/l10n_integrity_test.dart::retired Q&A group-type key is absent from every locale and generated API` | unit host / reads the ARB files and the generated Dart sources, reusing the `DTR-04`/`DTR-07` pattern at `:45`/`:93` | causal RED (the key is present in all three ARBs and all four generated files today) → absent everywhere; `group_type_discussion`/`group_type_announce` still present | re-add the key to any one ARB and regenerate → TC-10 red | **`flutter test test/l10n/l10n_integrity_test.dart` (direct — `test/l10n` is host-all-only, outside the feature/core globs)** |
| TC-11 | ARB key sets stay identical across locales | `l10n_integrity_test.dart:10-44` (existing) | unit host | GREEN sentinel → still passes | delete `group_type_qa` from `app_en.arb` only → TC-11 red. This is what forces all three locales to be edited together | same as TC-10 |
| TC-12 | `groupMessageLocalStateFromRows` accepts exactly the `chat` and `announcement` column strings | `test/features/push/application/background_message_handler_test.dart::group message local state accepts only chat and announcement group types` | unit host / plain maps | causal RED (`'qa'` is accepted today at `:1294-1296`) → a `'qa'` row is ineligible; `chat` and `announcement` stay eligible | re-add `groupType != 'qa'` → TC-12 red | `flutter test <path>`; **add path to `GROUP_TESTS` (grep-verify)** — currently in zero arrays. Note `completeness-check` does **not** enforce this: `classify_path`'s feature-local rule matches `test/features/push/application/*_test.dart` whether or not it is curated. The `grep -c` is the only registration proof |
| TC-13 | No **Dart** `GroupType.qa` or `group_type_qa` reference survives in `lib`/`test`/`integration_test` | `grep -rn 'GroupType\.qa' lib test integration_test` → 0; `grep -rn 'group_type_qa' lib test` → 0; **plus** `grep -rn "'qa'" test integration_test --include=*.dart` → only the allowlisted survivors below | static / repo-wide grep | causal RED (returns 29, 9, and the literal set respectively today) → all three match their expected results | leave any single reference → the gate fails | run as explicit Acceptance Gate commands |
| TC-14 | The `pending_group_invites.group_type` CHECK still admits `'qa'` (the second half of the accepted difference, which v1 claimed to lock but never named a file for) | `test/core/database/migrations/051_pending_group_invites_test.dart::group_type CHECK still admits the retired qa value` | migration host / `sqflite_common_ffi`; extend the existing file (group `:23`, tests `:24`/`:33`/`:64`, currently **zero** CHECK coverage) with an insert-`'qa'`-succeeds probe | **NEW assertion that passes on HEAD** → still passes | rewrite `051:12`'s CHECK to drop `'qa'` → TC-14 red | `flutter test <path>` (direct — same reason as TC-09) |
| TC-15 | `canTargetGroup` still rejects archived and dissolved groups after the `:71` clause deletion | `test/features/groups/application/group_media_forward_policy_test.dart::canTargetGroup rejects archived and dissolved groups` | unit host / plain `GroupModel` fixtures, calling `GroupMediaForwardPolicy.canTargetGroup` **directly** — verified today that no test does | **NEW test that passes on HEAD** → still passes | delete the whole `if` at `group_media_forward_policy.dart:71-73` instead of just the `\|\| group.type == GroupType.qa` clause → TC-15 red. Without this row that mis-edit is silent: every caller re-checks archived/dissolved locally, so the existing suites stay green | `flutter test <path>`; `GROUP_TESTS` (curated — grep-verify) |

### Test Notes
- **Three rows are NEW tests that pass on HEAD (TC-06, TC-07, TC-15) and two are new assertions on existing files (TC-09, TC-14).** "Passes on HEAD" is not the same as "already exists" — v1 labelled TC-06/TC-07/TC-09 `GREEN sentinel (passes today)` and left them out of the write list, which meant the plan's own headline `Do not` had **no** enforcement. All five are now explicit Step-1 deliverables.
- **TC-01's honest RED shape:** the `tryFromValue` assertion cannot be part of the recorded RED — the symbol does not exist at HEAD, so the test file would not compile and the failure would be a compile error, not the documented mechanism. Record the `GroupType.values` RED first; add the `tryFromValue` assertion after Step 2.
- **TC-02's honest RED shape:** on HEAD the assertion "`fromMap` with `type:'qa'` yields `GroupType.chat`" fails because it yields `GroupType.qa`; after the enum is deleted but *before* the fallback is added it fails because it throws. Both are the documented mechanism at their respective stages — write the test once and expect it to move from one failure to the other to green. Record both.
- **`group_model_test.dart` will not compile between Step 4 and Step 8.** Its existing `GroupType enum converts correctly` test references `GroupType.qa` at `:90` and `:93`. Every row hosted in that file (TC-01, TC-02, TC-05, TC-06) is unrunnable in that window — delete those two lines as part of Step 4, not Step 8, so the file stays compilable and the REDs stay legible.
- **File existence (all re-verified, none need creating):** `pending_group_invite_test.dart` ✅, `handle_incoming_group_invite_use_case_test.dart` ✅, `group_message_listener_test.dart` ✅, `017_018_group_original_tables_test.dart` ✅, `051_pending_group_invites_test.dart` ✅, `group_media_forward_policy_test.dart` ✅. There is **no** `017_groups_tables_test.dart` and **no** `*_system_transition_processor_test.dart`.
- **TC-09/TC-14 fixture honesty:** `sqflite_common_ffi` is **plain SQLite**, not SQLCipher. It proves that an insert of `'qa'` succeeds against the real CHECK; it proves nothing about encryption, and nothing here claims otherwise. `PRAGMA table_info` cannot see a CHECK constraint — do not use it for this.
- **TC-10 must assert the generated API too, not just the ARBs** — the `DTR-04` precedent (`:45-91`) reads the generated Dart sources directly, because deleting an ARB key without regenerating leaves a live `String get group_type_qa` in `app_localizations*.dart`.
- **Compile-RED is expected — in FIVE lib files, plus `test/`.** Deleting the enum value breaks `handle_incoming_group_invite_use_case.dart:1424`, `group_media_forward_policy.dart:71`, `group_private_media_availability.dart:56`, `group_media_batch_forward.dart:515`, and `group_type_badge.dart:48,58,69`. `flutter analyze` also covers `test/`, so the 16 `GroupType.qa` test files error too until Step 8. Both are expected; neither is a stop-if. What `flutter analyze` **cannot** see is the third census class (positive allow-lists) and the Go layer — those are covered by the census table, not by the tool.

## Implementation Steps

1. Snapshot `git status --short`. **The tree is already dirty from unrelated in-flight work (plans 301-303, 309)** — record the baseline so nothing is reverted. Re-derive the census (Acceptance Gates block). Then author, in this order:
   - the causal-RED rows **TC-01 (stage 1 only)**, TC-02, TC-03, TC-04, TC-10, TC-12 — record each RED;
   - the pass-on-HEAD rows **TC-06, TC-07, TC-15** and the new assertions **TC-09, TC-14** — record each as green-before. These are the sentinels; if they are not written now, nothing in this plan enforces its own `Do not`s.
2. Add `static GroupType? tryFromValue(String value)` to `group_model.dart` beside `fromValue` (`:11-23`), returning `null` instead of throwing. Leave `fromValue`'s throwing contract **unchanged** (TC-06 locks this). Add TC-01's stage-2 `tryFromValue('qa') == null` assertion now.
3. Convert the **two** genuinely unguarded read sites to explicit fallbacks:
   - `group_model.dart:154` → `type: GroupType.tryFromValue(map['type'] as String) ?? GroupType.chat`
   - `pending_group_invite.dart:54` → same shape
   Leave `pending_group_invite.dart:154-160` alone — its `try/catch (_)` already returns `chat` (v1 wrongly listed it as unguarded; converting it is a behaviour-preserving no-op with no covering row, so skip it). Leave `group_message_listener_system_transition_processor.dart:3711-3719` alone — its `on ArgumentError` guard stays live and keeps its "retain the existing type" fallback (TC-07), and `:3776-3781` writes that type back.
4. Delete `case 'qa': return GroupType.qa;` from `group_model.dart:17-18` and the `qa` value from the enum (`:2-6`). **In the same step**, delete `group_model_test.dart:90` and `:93` so that file still compiles and TC-01/TC-02/TC-05/TC-06 stay runnable.
5. Run `flutter analyze` and fix every resulting compile error. Expected in **five** lib files: `handle_incoming_group_invite_use_case.dart:1424` (delete the `case 'qa':` arm — its `default` already returns `chat`), `group_media_forward_policy.dart:71` (**drop ONLY the `|| group.type == GroupType.qa` clause; keep the `isArchived || isDissolved` guard** — TC-15), `group_private_media_availability.dart:56`, `group_media_batch_forward.dart:515`, `group_type_badge.dart:48,58,69`. Errors in the 16 `GroupType.qa` **test** files are also expected here and are cleared by Step 8.
   Stop-if: a compile error appears in a **`lib/`** file not on this list — that is an undiscovered site; add it to the census rather than patching past it. Do **not** treat `test/` errors or the third-census-class allow-lists as stop-ifs: `flutter analyze` cannot see the latter at all, which is why they are enumerated in Problem And Evidence instead.
6. Remove `'qa'` from the push handler's accepted set — **locate it by the symbol `groupMessageLocalStateFromRows` and the literal `groupType != 'qa'`, not by line number** (plan 309 edits the same function and will shift `:1294-1296`). This is dead-string tidy-up; do not describe it as a divergence fix.
7. Delete `group_type_qa` from `app_en.arb:981`, `app_ar.arb:932`, `app_de.arb:932`, then regenerate: `flutter gen-l10n`. Do not hand-edit `app_localizations*.dart`.
8. Update the 16 test files carrying `GroupType.qa`: delete rows that exist *only* to cover `qa`; for parametrized tables that include `qa` as one case among several, drop that case and keep the rest. Three need care:
   - `background_message_handler_test.dart:1845-1850` — a `'qa'` group with a `'reader'` actor expected `isNull`. It passes today because the **role** is unauthorized; after Step 6 it would pass because the **type** is rejected, silently losing its discriminating power. Split it: keep the role assertion on a `'chat'` group.
   - `retry_incomplete_group_downloads_use_case_test.dart:805` — `if (candidate.attachment.id == '09-direct-drain') return GroupType.qa;` is a harness fake selecting the "not announcement" branch. Replace `GroupType.qa` with `GroupType.chat`; do **not** delete the `if`, or that case changes branch.
   - `group_conversation_wired_test.dart:19696` and `group_media_batch_forward_authorization_test.dart:202`/`:224-225` mix the symbol with literal `'qa'` strings — fix both halves.
   Also delete the now-stale prose referring to a type that no longer exists: `group_received_media_action_policy.dart:17` ("QA surfaces"), `group_conversation_screen.dart:961` and `:1288`, `group_conversation_wired.dart:2121` ("Q&A"). Comments only — no behaviour.
9. Register `test/features/push/application/background_message_handler_test.dart` in `GROUP_TESTS` (`scripts/run_test_gates.sh:375-688`), then `grep -c` it. If plan 309 landed first the path may already be present — verify the count is exactly 1, never 2.
10. Run focused GREEN → sentinels → graph-affected dependents → the `groups` lane → the two direct migration commands → the direct `test/l10n` command → `flutter analyze` → TC-13's greps.

## Risks And Blind Spots

- **The removal turning a dead type into a crash-on-read** → guarded by TC-02/TC-03; this is the plan's central risk.
- **A blanket `fromValue` default silently reclassifying announcement groups** → guarded by TC-06 **and** TC-07, both of which are new tests this plan must author. In v1 both were phantom (no test existed and neither was in the write list), which meant the exact implementation the plan forbids passed all thirteen rows, `flutter analyze`, every gate, and every grep. That hole is the single most important thing v2 closes.
- **Replacing the system-transition guard with `tryFromValue(v) ?? chat`** → a *second*, subtler form of the same regression that leaves `fromValue` throwing (TC-06 green) while still reclassifying announcements. Only TC-07 catches it; this is why TC-07 is not redundant with TC-06.
- **Deleting the whole `if` at `group_media_forward_policy.dart:71-73` instead of the `qa` clause** → archived and dissolved groups become valid forward targets. No test called `canTargetGroup` directly before this plan, and every caller re-checks archived/dissolved locally, so the existing suites would stay green → TC-15 exists solely to catch this.
- **The Step-3 fallback silently promoting a legacy `'qa'` row** → the three deleted arms each returned the restrictive answer *for the symbol*, but the fallback re-routes such a row into the `chat` arm of all three policies, so it gains forward-target, private-media-author, and batch-forward-source privileges. Recorded as an accepted difference (no user has a qa group), **not** as "deletion can only affect qa itself" — that v1 phrasing was self-reassuring and hid the promotion.
- **Lifecycle / derived-state durability:** N/A — nothing derived is added; the change removes an enum value and adds a pure parse fallback. The one persisted artifact (`groups.type`) is covered by TC-02.
- **Sibling-surface consistency:** three distinct classes, each needing a different instrument. (a) The *enum* seam — four `fromValue` call sites, two change and two deliberately do not (TC-02, TC-03, TC-04, TC-07); the compiler finds the rest. (b) The *literal-string* sites the symbol census misses — TC-12 covers the push handler, TC-09/TC-14 lock the two migrations. (c) The *positive allow-lists* that neither grep nor the compiler can see — enumerated by hand in Problem And Evidence, left untouched by design, and owned by whoever next adds a `GroupType`.
- **Destructive-action side effects:** this plan *is* a deletion. TC-13's greps assert what is removed; TC-05/TC-08/TC-09/TC-11/TC-14/TC-15 assert what is preserved. No disk file, DB row, or directory is deleted at runtime.
- **Invariant re-verification under new transitions:** the new transition is "unknown type → chat". TC-02/TC-03 assert the resulting model is fully valid (not merely that no throw occurred) — assert the whole `GroupModel`, not just `.type`, so a fallback that produces a half-built object fails.
- **Construction/call-site census (re-derive at execution; counts drift):** `grep -rn 'GroupType\.qa' lib test integration_test` (8 lib + 21 across 16 test files at review time), `grep -rn "'qa'" lib --include=*.dart` (5), `grep -rn 'GroupType.fromValue' lib` (4), `grep -rn 'group_type_qa' lib test` (**9**, not 8 — v1 omitted the `group_type_badge.dart:70` consumer). Concurrent sessions took plans 310 and 312 mid-flight, so re-run every one of these rather than trusting the numbers here.
- **Build-artifact provenance:** N/A — no native artifact, no relay deploy, no binary containment claim. The generated localization files are the only build output, and TC-10 asserts their content directly.
- **Permission / ACL verb symmetry:** N/A — no permission or ACL check changes. The deleted `qa` arms gate forwarding and private-media authoring, and both keep their behaviour for the surviving types unchanged.
- **Fake side-effect fidelity:** N/A — TC-02/TC-03 use plain map fixtures against pure factory constructors; there is no dependency to fake.
- **Composite-node / relationship assertions:** TC-10 binds two facts that must hold together (key absent from the ARB **and** from the generated API) — assert both, since deleting the ARB key without regenerating leaves a live getter, and that is precisely the half-done state a single assertion would pass.

## Gate Cadence

- **Per-plan closure:** the focused causal rows, the sentinels, `./scripts/run_test_gates.sh groups`, the two direct migration commands, the direct `test/l10n` command, and `flutter analyze` (load-bearing but **partial** — it proves exhaustiveness for `lib/` enum switches only; it cannot see the positive allow-lists or the Go layer).
- **`./scripts/run_test_gates.sh groups` has two Go legs.** `scripts/run_test_gates.sh:1502-1506` dispatches `run_gate_command "Group Messaging Gate"` **plus** `run_group_forwarding_go_bridge_gate` (`:1021-1025`) and `run_relay_notification_go_gate` (`:1035-1039`), both of which shell out to `go test`. There is no `go` toolchain inside the container (`command -v go` → empty), so the lane must be run through the host bridge: `/claude-host-bin/host-run bash ./scripts/run_test_gates.sh groups`. If the Go legs still cannot execute, record them as **not run** with the reason — do not report the lane as "exit 0". This plan changes no Go source, so a Go-leg skip is an environment note, not a product blocker; the Dart portion is the part that must be green.
- **Migration tests need direct commands.** `017_018_group_original_tables_test.dart` and `051_pending_group_invites_test.dart` live under `test/core/**`, which `feature-host-all` does not glob and no curated array in this plan's path includes.
- **Graph-affected first:** after the production edits and before the curated lane, run `python3 graphify-arch/tdd_context.py affected lib/features/groups/domain/models/group_model.dart lib/features/groups/domain/models/pending_group_invite.dart lib/features/push/application/background_message_handler.dart --budget 600` and `flutter test` the files it names. Note the graph's documented blind spot applies with unusual force here: **the literal-string and l10n sites have no import edge**, so TC-09/TC-10/TC-12/TC-13 will never be surfaced by `affected` — they are covered by the explicit commands.
- **Full `host-all` is not a per-plan gate.** Because this removes an enum value that 16 test files reference, it does warrant one `feature-host-all` sweep — the surface this plan actually changes is broad within `test/features`. Run it batch-parallel: `./scripts/run_host_test_gates.sh feature-host-all --batch-flutter --concurrency 4 --reporter failures-only`. Aggregate `host-all` still belongs to the group-notification dependency wave and final release closure.
- **Shared tests outside the feature/core globs:** `test/l10n/l10n_integrity_test.dart` is host-all-only (`feature-host-all` globs `test/features`; `core-host-all` globs `test/core`). It gets a direct `flutter test` command in this plan, not a sweep.

## Acceptance Gates  (literal — copy/paste)

```bash
# Dirty-tree snapshot before execution (tree is ALREADY dirty from plans 301-303/309 — record, do not revert)
git status --short

# --- Re-derive the census BEFORE editing (counts drift; concurrent sessions took plans 310 and 312) ---
grep -rn 'GroupType\.qa' lib test integration_test --include=*.dart | wc -l   # review-time: 29 (8 lib + 21 test)
grep -rn "'qa'" lib --include=*.dart                                          # review-time: 5 sites
grep -rn 'GroupType.fromValue' lib --include=*.dart                           # review-time: 4 call sites
grep -rn 'group_type_qa' lib test                                             # review-time: 9 (incl. group_type_badge.dart:70)
grep -rn "'qa'" test integration_test --include=*.dart                        # review-time: the literal set Step 8 must also clear
grep -rn 'GroupTypeQA\|"qa"' go-mknoon --include=*.go                         # review-time: 5 — DEFERRED, must stay non-zero

# --- Sentinels that must be AUTHORED and green BEFORE any production edit (v1 had none of these) ---
flutter test test/features/groups/domain/models/group_model_test.dart \
  --plain-name 'fromValue still throws for an unrecognized value'                 # TC-06
flutter test test/features/groups/application/group_message_listener_test.dart \
  --plain-name 'retains the existing group type for an unparseable wire group type'  # TC-07
flutter test test/features/groups/application/group_media_forward_policy_test.dart \
  --plain-name 'canTargetGroup rejects archived and dissolved groups'             # TC-15
flutter test test/core/database/migrations/017_018_group_original_tables_test.dart  # TC-09
flutter test test/core/database/migrations/051_pending_group_invites_test.dart      # TC-14

# --- Causal REDs (before production edits) — each must FAIL for its documented reason ---
flutter test test/features/groups/domain/models/group_model_test.dart \
  --plain-name 'GroupType exposes only chat and announcement'
flutter test test/features/groups/domain/models/group_model_test.dart \
  --plain-name 'fromMap falls back to chat for an unrecognized persisted type'
flutter test test/l10n/l10n_integrity_test.dart \
  --plain-name 'retired Q&A group-type key is absent from every locale and generated API'
flutter test test/features/push/application/background_message_handler_test.dart \
  --plain-name 'group message local state accepts only chat and announcement group types'

# --- Partial exhaustiveness proof: enum switches in lib/ only ---
flutter analyze     # expect: errors in the FIVE lib files named in Step 5, PLUS the 16 GroupType.qa
                    # test files (analyze covers test/). Neither is a stop-if. A sixth lib/ file IS.

# --- Regenerate localizations after the ARB edits (never hand-edit app_localizations*.dart) ---
flutter gen-l10n
git diff --stat lib/l10n/app_localizations*.dart    # expect: the four generated files changed

# --- Focused GREEN (after the fix) — exit 0, zero failures ---
flutter test test/features/groups/domain/models/group_model_test.dart
flutter test test/features/groups/domain/models/pending_group_invite_test.dart
flutter test test/features/groups/presentation/group_type_badge_test.dart
flutter test test/features/groups/application/group_media_forward_policy_test.dart
flutter test test/features/groups/application/group_message_listener_test.dart
flutter test test/features/groups/application/handle_incoming_group_invite_use_case_test.dart
flutter test test/features/push/application/background_message_handler_test.dart

# --- test/core/** is outside every lane this plan runs — direct commands ---
flutter test test/core/database/migrations/017_018_group_original_tables_test.dart
flutter test test/core/database/migrations/051_pending_group_invites_test.dart

# --- Shared test outside the feature/core globs — direct command, never a sweep ---
flutter test test/l10n/l10n_integrity_test.dart

# --- Graph-affected dependents BEFORE the lane ---
python3 graphify-arch/tdd_context.py affected \
  lib/features/groups/domain/models/group_model.dart \
  lib/features/groups/domain/models/pending_group_invite.dart \
  lib/features/push/application/background_message_handler.dart --budget 600
flutter test <exact test files named by the command above>

# --- Preservation sentinels + the affected curated lane. NOTE: this lane has two Go legs
#     (run_test_gates.sh:1502-1506 -> :1021-1025, :1035-1039). Run via the host bridge. ---
/claude-host-bin/host-run bash ./scripts/run_test_gates.sh groups

# --- One justified broad sweep: 16 test files reference the deleted value ---
./scripts/run_host_test_gates.sh feature-host-all --batch-flutter --concurrency 4 --reporter failures-only

# --- TC-13: nothing survives in Dart ---
grep -rn 'GroupType\.qa' lib test integration_test --include=*.dart | wc -l   # expect: 0
grep -rn 'group_type_qa' lib test                                             # expect: no output
grep -rn "'qa'" lib --include=*.dart                                          # expect: ONLY the two migration CHECK lines (017:11, 051:12)
grep -rn "'qa'" test integration_test --include=*.dart                        # expect: ONLY the migration-fixture copies of the
                                                                              # CHECK text (050/052/053_*_test.dart) — no policy
                                                                              # or push fixture may still say 'qa'
grep -rc 'GroupTypeQA' go-mknoon/node/group.go                                # expect: 1 — the DEFERRED Go difference is intact,
                                                                              # not silently widened into by this plan

# --- Registration is grep-verified, never run-verified (family gates swallow --list) ---
grep -c 'test/features/push/application/background_message_handler_test.dart' scripts/run_test_gates.sh  # expect: exactly 1 (309 may have added it)
./scripts/run_test_gates.sh completeness-check    # expect: PASS, 0 unmatched. NOT a registration check —
                                                  # classify_path matches this path either way.

# --- Hygiene ---
flutter analyze     # 0 issues after steps 5 and 8
git diff --check
```

**Semantic outcomes.** Each causal RED fails with its documented mechanism, and each of TC-06/TC-07/TC-09/TC-14/TC-15 is recorded green **before** any production edit. `flutter analyze` after the enum deletion lists errors in the five Step-5 lib files plus the 16 test files; a **sixth `lib/` file** is the stop-if. `flutter gen-l10n` changes exactly the four generated localization files. Every focused GREEN and the `feature-host-all` sweep exit 0 with zero failures; the `groups` lane's Dart portion exits 0, and any Go leg that could not run is reported as **not run, with the reason** — never folded into an "exit 0" claim. The final `grep` for `'qa'` in `lib` returns exactly the two migration CHECK lines; the `test` grep returns only the three migration-fixture copies; the `go-mknoon` grep still returns 1. `completeness-check` reports zero unmatched paths.

**Environment note (not a product blocker):** `flutter` resolves to the host shim at `/claude-host-bin/flutter` (3.41.4) and runs against `/workspace` on the Mac. The container has **no `go` toolchain**, and — contrary to v1 — the `groups` lane named above *does* have Go legs (`run_group_forwarding_go_bridge_gate`, `run_relay_notification_go_gate`). This plan changes no Go source, so those legs are expected to be unaffected; run them through `/claude-host-bin/host-run` where possible and record honestly if they are skipped.

## Execution Interpretation And Done Criteria

- **Expected RED:** TC-01 (stage 1) fails because the enum has three values; TC-02/TC-03 fail because the read path returns `GroupType.qa` (and, mid-edit, because it throws); TC-04 fails because the wire value materializes as `qa`; TC-10 fails because the key is present in all three ARBs and all four generated files; TC-12 fails because `'qa'` is accepted.
- **Expected compile failure:** after Step 4, in exactly **five** `lib/` files *and* the 16 `GroupType.qa` test files (`flutter analyze` covers `test/`). This is the exhaustiveness check working, not a defect. A **sixth `lib/` file** is a stop-if.
- **Green-before-and-after (must be AUTHORED, not assumed):** TC-06, TC-07, TC-09, TC-14, TC-15 are new and pass on HEAD. TC-05, TC-08, TC-11 are pre-existing. Record all eight green *before* Step 2 — a sentinel first observed after the fix proves nothing.
- **Pre-existing dirty tree:** unrelated uncommitted changes from plans 301-303 and 309. Baseline them in step 1; failures there are not this plan's REDs.
- **Environment blocker (NOT a product blocker):** the `groups` lane's two Go legs need a `go` toolchain the container lacks. Run via `/claude-host-bin/host-run`; if still unavailable, report them as not run with the reason. No device, relay, or simulator leg exists.
- **Scope drift (BLOCKING):** any DB migration, any CHECK-constraint edit, any change to `fromValue`'s throwing contract, any rewrite of the system-transition guard at `:3711-3719`, deleting the `isArchived || isDissolved` guard at `forward_policy:71`, editing any of the ~12 positive allow-lists, editing `go-mknoon/`, any hand-edit of a generated localization file, or any behaviour change for `chat`/`announcement`.

- [ ] Every behavior has a named test, and every named test file was confirmed to exist before being cited.
- [ ] Causal RED, focused GREEN, and representative mutation re-red are recorded.
- [ ] TC-06, TC-07, TC-09, TC-14, TC-15 were **written and observed green before Step 2**, and each was mutation-checked (TC-07 specifically against the `tryFromValue(v) ?? chat` rewrite, not only against a non-throwing `fromValue`).
- [ ] `flutter analyze` listed `lib/` compile errors only in the five expected files, and all were resolved by deletion (not by re-adding a branch).
- [ ] Preservation sentinels and named gates pass with semantic outcomes; any Go leg that did not run is reported as not run, with the reason.
- [ ] `flutter gen-l10n` ran and the generated files are in the diff.
- [ ] Harness registration implemented AND grep-verified at exactly 1; `completeness-check` passes (and was not treated as the registration proof).
- [ ] TC-13's five greps return their expected results, including the deferred `go-mknoon` count still being 1.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.
- [ ] The Scope Contract And Guard is respected — in particular, no allow-list guard and no Go file was touched.

## Rollback

- **Reversible by:** `git revert` of the single commit. There is no migration, no schema change, no key material, and no wire-format change to unwind. Verified in review: every wire emitter serialises through `group.type.toValue()` (`lib/features/groups/application/group_config_payload.dart:43`, `create_group_use_case.dart:204`), all three inbound seams absorb an unknown value, and the group-config state hash is computed over the **received** payload (`group_config_payload.dart:410`/`:421`, verified at `group_invite_auth.dart:206-216`) — so a local `qa`→`chat` flip cannot desynchronize hash verification across a mixed-version cohort.
- **What a PRIOR shipped build does with post-change data:** nothing is written differently. The only data-shape consequence is that a group previously stored as `'qa'` is read as `chat` and, **on its next `groups`-row write**, persisted as `'chat'`. A prior build reading `'chat'` handles it natively. The reverse direction is also safe: a prior build could still write `'qa'`, and the post-change build reads it as `chat` rather than throwing (TC-02). **Both CHECK constraints keep admitting `'qa'`, so neither direction hits a schema rejection** — this is exactly why the plan refuses to tighten them.
- **Normalization is not automatic.** "Next write" means a **`groups`-row** write — `group_repository_impl.dart:371-373` → `GroupModel.toMap()` (`:193-197`) → `dbUpdateGroup` (a documented full-row replace, `groups_db_helpers.dart:126`), triggered by a membership event, metadata sync, mute, dissolve, or retention drain. Receiving ordinary messages writes `group_messages`, not `groups`. A quiet group therefore keeps `type='qa'` **indefinitely**, and after Step 6 such a row is permanently dark to the Android background notification path while remaining live in the foreground and on iOS. Accepted: no user has a qa group.
- **NOT recoverable once landed:** the distinction between a group that *was* `qa` and one that was always `chat`. No shipped build can create a `qa` group and the only ingress needs a modified peer, so the affected population is empty in practice; if such a row exists, its type label is lost on the next `groups`-row write while all other group data (id, name, members, keys, messages) is untouched.
- **Staging:** land as a single client release. No forward-compat release is needed — the read fallback (Step 3) is what makes the change safe in both directions, and it ships in the same commit as the deletion. Ordering *within* the commit matters: the fallback must be added (Step 3) **before** the enum value is deleted (Step 4), or an intermediate build throws on legacy rows.

## Handoff

- **First action is NOT a RED.** Author the five sentinels (TC-06, TC-07, TC-15, TC-09, TC-14) and record them green on HEAD. Without them the plan cannot detect the implementation it forbids.
- **First causal RED command:** `flutter test test/features/groups/domain/models/group_model_test.dart --plain-name 'GroupType exposes only chat and announcement'`
- **Preservation command:** `/claude-host-bin/host-run bash ./scripts/run_test_gates.sh groups` (two Go legs — see Gate Cadence).
- **Manual registration:** one — add `test/features/push/application/background_message_handler_test.dart` to `GROUP_TESTS`, then `grep -c` for exactly 1. Plan 309 adds the same path; if 309 lands first, do not add a duplicate. `completeness-check` will pass either way and is not the proof.
- **Migration:** none — deliberately. See Refuted findings.
- **Boundary closure:** host-only for everything this plan **edits**. Two boundaries are explicitly *not* closed and are recorded as deferred differences rather than claimed: the Go bridge keeps `GroupTypeQA` (`go-mknoon/node/group.go:11`, pinned by the green `bridge_test.go:1965`), and the ~12 positive allow-lists become tautologies or dead branches. Neither is proven by any gate here, and neither is asserted to be.
- **Unresolved evidence:** none. Both review-surfaced decisions are closed: convergence direction (moot — no user has a qa group; Step 6 stays as tidy-up and the divergence framing is removed) and Go scope (deferred with the difference recorded and grep-locked).

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plan | contract extraction |
