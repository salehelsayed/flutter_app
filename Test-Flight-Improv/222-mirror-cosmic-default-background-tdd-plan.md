# 222 - Make "Mirror Cosmic" the Default Background (rename old default → "Aurora", migrate default users)  (Modification)

Status: **reviewed — execute-with-corrections** (8-agent /tdd-review 2026-07-08, verdict *yes-with-tightening*; fix-list `222-review-fixlist.md` **APPLIED into this plan**). Core bet VERIFIED SOUND; corrections are test-precision + execution structure, not architecture.
Spec: free-text intent (no formal spec) — grounded in Step 1 below

## Migration Contract (canonical — every stored token's fate)  (§E3)
Reading is via `loadBackgroundPreference → fromStorageString`; **stored tokens are NEVER normalized on read** (a `'cosmic_mirrored'`/`'default'` user keeps that byte in SecureKeyStore — it is only *re-interpreted* — which is exactly why INV-6 matters: nothing may branch on the raw token outside the codec).

| stored token | resolves to enum | rendered surface | Settings tile highlighted | rewritten on load? | Lock |
|---|---|---|---|---|---|
| `null` (never chose) | `defaultBackground` | **Mirror Cosmic** | Default | No | SC-6 (#4 render) |
| `'default'` | `defaultBackground` | **Mirror Cosmic** | Default | No | SC-4 (#4 render) |
| `'cosmic_mirrored'` (retired) | `defaultBackground` | **Mirror Cosmic** | Default | No | SC-5 (#1), SC-5b (#7 concrete) |
| `'aurora'` (new) | `aurora` | glow | Aurora | No | SC-2 (#5), SC-3 (#2 codec) |
| `'cosmic'` | `cosmic` | Cosmic | Cosmic | No | SC-7 (existing parse) |
| `'daylight_lagoon'` | `daylightLagoon` | Signal (light) | Signal | No | SC-7 (existing parse) |
| garbage/unknown | `defaultBackground` | **Mirror Cosmic** | Default | No | SC-4 (existing parse) |

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-08 | Evidence Collector | background_preference.dart, ambient_background.dart, background_readable_colors.dart, background_choice_control.dart, settings_screen.dart, settings_wired.dart, background_preference_use_cases.dart, migration_secure_storage_registry.dart, app_en.arb, + 5 test files | Single secure-store seam; 6 switch/branch sites; NOT SQLite | Ground via verify→refute workflow |
| 2026-07-08 | Verify→Refute Workflow (4 ground + refute + critic) | above + bundle_transfer.dart, staging.dart, startup_router.dart, cosmic_background_mirrored.dart | Design Option 1 SOUND; `_usesDefaultBackground` landmine CONFIRMED; account-move copies token verbatim (no whitelist) | Emit plan |
| 2026-07-08 | Planner | — | Enum: retire `cosmicMirrored`, add `aurora`, repoint default→Mirror Cosmic | This document |
| 2026-07-08 | Reviewer (8-agent /tdd-review) | + ambient_background_test.dart (6 default tests), conversation_screen_test.dart:348-365, feed_performance_test.dart FEED6, migration_secure_storage_registry_test.dart:63 | yes-with-tightening; core bet SOUND; test-precision fixes → `222-review-fixlist.md` | Apply fix-list |
| 2026-07-08 | Arbiter | fix-list §A–§E | All corrections VERIFIED against source & APPLIED (§A 6-test blast-radius, §B render-vs-glow rebase + FEED6 gate, §C1 INV-6 precision, §C2 drop #6(d), §C3–C5, §D two slices, §E1 5 switches) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-08 17:01 CEST | contract extracted | `Test-Flight-Improv/222-mirror-cosmic-default-background-tdd-plan.md`; graph query via `graphify-arch` | `git status --short` shows pre-existing dirty 221/graphify/orbit/feed/native files plus this untracked plan; no execution edits yet | scope confirmed: background pref/ambient/settings/l10n/tests only; required gates extracted from Acceptance Gates | spawn isolated Executor (`gpt-5.5`, xhigh) |
| 2026-07-08 17:05 CEST | Executor spawn no-progress; local fallback begins | no scoped background files touched by child | Spawned Executor `019f4240-2d93-7200-864a-93dd588edac6` waited 60s + progress request + 60s; `## Execution Progress` unchanged; scoped diff empty; child closed with previous status `running` | classify child attempt `spawn_or_tool_failure`; local sequential fallback is bounded to this plan contract | perform Executor locally, then local QA if required spawned QA also fails/materializes poorly |
| 2026-07-08 17:07 CEST | Slice A RED tests added | `background_preference_use_cases_test.dart`, `ambient_background_test.dart`, `background_choice_control_test.dart`, `background_readable_colors_test.dart` | `flutter test ...background_preference_use_cases_test.dart --plain-name 'aurora token round-trips'` FAIL missing `BackgroundPreference.aurora`; `flutter test ...ambient_background_test.dart --plain-name 'aurora preference renders the ambient glow'` FAIL missing `aurora`; `flutter test ...background_readable_colors_test.dart --plain-name 'aurora resolves to the dark tone'` FAIL missing `aurora`; `flutter test ...background_choice_control_test.dart --plain-name 'tapping options notifies selection'` FAIL missing `aurora` after serial rerun. One earlier parallel picker attempt hit a Flutter startup/native-asset lock and was replaced by the serial rerun. | RED for expected compile reason; no production code edited before this evidence | implement additive `aurora` support |
| 2026-07-08 17:08 CEST | Slice A additive support GREEN | `background_preference.dart`, `ambient_background.dart`, `background_readable_colors.dart`, `settings_screen.dart`, `background_choice_control.dart`, `app_*.arb`, generated l10n | `flutter gen-l10n` PASS; `flutter test ...background_preference_use_cases_test.dart --plain-name 'aurora token round-trips'` PASS; `flutter test ...ambient_background_test.dart --plain-name 'aurora preference renders the ambient glow'` PASS; `flutter test ...background_choice_control_test.dart --plain-name 'tapping options notifies selection'` PASS; `flutter test ...background_readable_colors_test.dart --plain-name 'aurora resolves to the dark tone'` PASS | additive checkpoint clean; `cosmicMirrored` still live and default still glow | add Slice B flip tests and capture assertion RED |
| 2026-07-08 17:09 CEST | Slice B assertion RED captured | `background_preference_use_cases_test.dart`, `ambient_background_test.dart`, `background_choice_control_test.dart` | `flutter test ...background_preference_use_cases_test.dart --plain-name 'parses cosmic_mirrored as the new default'` FAIL actual `cosmicMirrored`; `flutter test ...ambient_background_test.dart --plain-name 'default preference renders Mirror Cosmic'` FAIL no `CosmicBackgroundMirrored`; `flutter test ...ambient_background_test.dart --plain-name 'aurora glow animates, is chat-suppressed, and honors OS reduce-motion'` FAIL controller `isAnimating` false; `flutter test ...background_choice_control_test.dart --plain-name 'cosmic_mirrored user sees Default tile selected'` FAIL no default selected icon; `flutter test ...background_choice_control_test.dart --plain-name 'shows Default, Cosmic, Aurora, and Signal without mirrored cosmic'` FAIL old default desc/mirrored tile still present | RED for expected pre-flip behavior | implement flip/retire and update blast-radius tests |
| 2026-07-08 17:14 CEST | direct GREEN + preservation GREEN | scoped production/l10n/tests | Direct: `flutter test test/features/settings/application/background_preference_use_cases_test.dart` PASS (15); `flutter test test/features/identity/presentation/widgets/ambient_background_test.dart` PASS (24); `flutter test test/features/settings/presentation/widgets/background_choice_control_test.dart` PASS (14); `flutter test test/core/theme/background_readable_colors_test.dart` PASS (8). Preservation: `flutter test test/features/feed/presentation/screens/feed_reduced_motion_test.dart` PASS (3); `flutter test test/features/account_migration/presentation/account_migration_journey_screen_test.dart` PASS (31). | required direct/preservation checks green; no retired enum refs remain | run acceptance legs, named host gates, l10n/hygiene, graphify refresh |
| 2026-07-08 17:14 CEST | gate failure triage | `integration_test/settings_background_choice_smoke_test.dart` | Failing gate command: `flutter test integration_test/settings_background_choice_smoke_test.dart`; failing test: none loaded; log path: none; focused triage command: `flutter devices`; classification: `pending_triage` | exact command stopped on multiple connected devices before test execution | inspect devices, then rerun pinned to `macos` if available |
| 2026-07-08 17:17 CEST | gate failure triage | `integration_test/settings_background_choice_smoke_test.dart` | Failing focused command: `flutter test -d macos integration_test/settings_background_choice_smoke_test.dart`; failing test: `Settings background choice smoke over Feed`; log path: none; focused triage command: `sed -n '270,305p' integration_test/settings_background_choice_smoke_test.dart`; classification: `pending_triage` | test reached assertion and found `CosmicBackgroundMirrored` where the updated smoke expected Aurora/glow | inspect smoke flow and fix caused-by-session expectation or app behavior |
| 2026-07-08 17:18 CEST | gate failure triage | `integration_test/feed_performance_test.dart` | Failing gate command: `flutter test integration_test/feed_performance_test.dart`; failing test: none loaded; log path: none; focused triage command: `flutter test -d macos integration_test/feed_performance_test.dart`; classification: `pending_triage` | exact command stopped on multiple connected devices before test execution | rerun pinned to `macos` to exercise FEED6 |
| 2026-07-08 17:18 CEST | gate failure triage | `integration_test/feed_performance_test.dart` | Failing focused command: `flutter test -d macos integration_test/feed_performance_test.dart`; failing test: none loaded; log path: none; focused triage command: `sed -n '1,80p' integration_test/feed_performance_test.dart`; classification: `pending_triage` | pinned command reports missing `main` method | inspect file for skipped/harness shape and classify |
| 2026-07-08 17:20 CEST | acceptance legs resolved | `integration_test/settings_background_choice_smoke_test.dart`, `integration_test/feed_performance_test.dart` | `flutter test -d macos integration_test/settings_background_choice_smoke_test.dart` PASS; `flutter test -d macos integration_test/feed_performance_test.dart` PASS after adding the file-level `main()` wrapper. Exact unpinned commands remain blocked before test loading by multiple connected devices. | product evidence green on pinned host device; exact unpinned command limitation is environment/tooling, not a product assertion failure | continue named host gates |
| 2026-07-08 17:43 CEST | gate failure triage | `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart` | Failing gate command: `./scripts/run_host_test_gates.sh feature-host-all`; failing test file: `#357 test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart`; log path: none captured from script; focused triage command: pending | classification: `pending_triage`; failure is outside 222 background-preference scope and occurred after `#356` passed | inspect focused failure, decide unrelated/pre-existing vs caused-by-session before continuing gates |
| 2026-07-08 17:45 CEST | gate failure triage | `test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart` | Focused command: `flutter test test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart --plain-name 'ordinary media upload failure after unmount still persists failed parent status'`; failing assertion: expected status `sending`, actual `queued_offline`; temp log `/tmp/222-bg-task-media-fail.log`; classification: `unrelated_host_gate_blocker` | this group-send lifecycle path is outside 222 files and fails in isolation, so the 222 feature implementation is not allowed to claim `feature-host-all` green | keep 222-scoped evidence; decide final verdict after remaining hygiene/QA evidence |
| 2026-07-08 18:01 CEST | named core host gate GREEN | broad `test/core/**` host suite | `./scripts/run_host_test_gates.sh core-host-all` PASS through `#282 test/core/utils/url_parser_test.dart`; final line: `PASS: host tests completed for scope: core-host-all` | core host gate clean; only named host blocker remains the unrelated `feature-host-all` group background-task failure above | run l10n/hygiene and graphify refresh |
| 2026-07-08 18:04 CEST | l10n + hygiene | l10n generated files plus 222-scoped Dart files | `flutter gen-l10n && git diff --stat lib/l10n/app_localizations*.dart` PASS; generated diff limited to 4 l10n files (24 insertions, 28 deletions). Full `flutter analyze` FAILS with 1625 existing repo-wide issues; scoped `flutter analyze` over the 15 files changed for this plan PASS (`No issues found!`). `git diff --check` PASS. | no analyzer or whitespace issues attributable to this plan; global analyzer backlog is pre-existing/out-of-scope | run graphify refresh |
| 2026-07-08 18:09 CEST | graph refresh | `graphify-out/**`, `graphify-arch/**` generated graph outputs | `graphify update .` PASS (`109701` nodes, `185026` edges, `4663` communities); `./graphify-arch/refresh_arch_graph.sh` PASS (`43645` nodes, `68565` edges, `929` communities; refreshed `GRAPH_SELECTION.md`/`comparison.json`) | graph state refreshed after app-owned code changes | run QA review |
| 2026-07-08 18:22 CEST | QA review complete | no files modified by reviewer | Spawned isolated QA Reviewer `019f427e-d154-7073-b2fb-ee51fe7b925b` (`gpt-5.5`, xhigh, read-only); reviewer reported no blocking findings, scope satisfied, and `unrelated_host_gate_blocker` classification defensible. Evidence cited: default renders `CosmicBackgroundMirrored`, `aurora` owns glow/gate, retired token remaps to default, settings/l10n updated, source guard present. | final verdict recommendation: `accepted_with_explicit_follow_up` because 222 is complete but `feature-host-all` still has unrelated #357 group failure | record final verdict |

## Source Of Truth
- Intent: inline below (make Mirror Cosmic the Default; name the old default; migrate default users; preserve explicit non-default picks).
- Gate definitions: `scripts/run_host_test_gates.sh` (host) + `scripts/run_test_gates.sh` (curated families) — script wins over prose.
- l10n regen: `l10n.yaml` (arb-dir `lib/l10n`, template `app_en.arb`) + `generate: true` in pubspec → `flutter gen-l10n`.
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (next-free after 221 → **222**).

## Session Classification
**implementation-ready** — pure-Dart UI/preference/codec change. No OS boundary, no crypto, no relay, no SQLite. Host + widget tiers close it; the existing `integration_test/settings_background_choice_smoke_test.dart` is the top acceptance leg. **No device-proof required** (argued in *Device/Relay Proof Profile*).

## Exact Problem Statement
Today the app's **Default** background is the green/red ambient **glow** (`_DefaultAmbientBackground`, `AppColors.background` + two radial `AnimatedBuilder` blooms). "Mirror Cosmic" (UI label "Mirrored cosmic") is a *separate* fourth option (`BackgroundPreference.cosmicMirrored` → `CosmicBackgroundMirrored`, a dark radial gradient with color blooms + a starfield).

We want to **make Mirror Cosmic the Default** background: it becomes what new users get, what null/unstored resolves to, and what the "Default" tile shows. The **current default glow** must keep existing but under its **own name** ("Aurora"), still selectable. In the new build, **any user who currently has Default** (stored token `'default'`, OR no stored value / unknown — all resolve to `defaultBackground` today) must render **Mirror Cosmic**. Users who explicitly picked a non-default (`'cosmic'`, `'daylight_lagoon'`) keep it. Users who explicitly picked `'cosmic_mirrored'` keep seeing Mirror Cosmic (which is now == Default).

What must improve:
- `defaultBackground` (the "Default" tile, the null/unknown fallback) renders **Mirror Cosmic**.
- The old glow is reachable under a new named value **`aurora`** ("Aurora" tile).
- `'default'`, `null`, unknown, and the retired `'cosmic_mirrored'` token all resolve to **Mirror Cosmic**.

What must stay unchanged (→ preserved-green sentinels):
- `'cosmic'` → Cosmic; `'daylight_lagoon'` → Signal (label "Signal", light tone) — untouched.
- All 16+ ambient surfaces keep rendering through the single `AmbientBackground` switch (single source of truth).
- OS reduce-motion, chat-surface idle-glow suppression (158), feed reduce-motion (134) behaviors — **preserved, but the glow-specific gate must follow the glow to `aurora`** (see Root Cause landmine).
- Account **Move** (device transfer) still round-trips the background choice.

## Root Cause (verify → refute confirmed)
This is a modification, not a bug, but the "mechanism to change" survived adversarial refutation with these confirmed facts (all `file:line`):

1. **Enum + codec** — `lib/features/settings/domain/models/background_preference.dart`
   - `toStorageString` (12–23): **exhaustive switch**, no `default:` → adding `aurora` is compiler-forced here.
   - `fromStorageString` (26–40): if-chain of raw-string equality + catch-all `return defaultBackground` (39). Unknown/null → `defaultBackground`. **This is the single seam** for the `'cosmic_mirrored'` remap and the new `'aurora'` token. (Not compiler-forced — hand edit.)
2. **Render switch** — `lib/features/identity/presentation/widgets/ambient_background.dart:124–136`: **exhaustive switch-expression** → compiler forces the `aurora` arm. `defaultBackground => _DefaultAmbientBackground(animation: _controller)`; `cosmicMirrored => CosmicBackgroundMirrored`.
3. **CONFIRMED LANDMINE — `_usesDefaultBackground`** — `ambient_background.dart:157–159` is a **bare `== defaultBackground`**, NOT a switch, so the compiler will **not** flag it when default is repointed. It gates `_shouldAnimate` (169–175) which drives the shared `_controller` (repeat/stop at 103–111). `_DefaultAmbientBackground` binds `animation: _controller` (125–128); `CosmicBackgroundMirrored` uses its **own** internal controller (`cosmic_background_mirrored.dart:36,100`). After repointing `defaultBackground → CosmicBackgroundMirrored` and moving the glow to `aurora`, **if this line is left as `== defaultBackground`, the Aurora glow freezes at `value 0` (never `repeat()`s) while `_controller` pointlessly loops behind Mirror Cosmic.** Repointing `_usesDefaultBackground` to `== aurora` is **mandatory**.
4. **Tone switch** — `lib/core/theme/background_readable_colors.dart:245–256`: exhaustive → `aurora` joins the `dark` group.
5. **Settings label switch** — `lib/features/settings/presentation/screens/settings_screen.dart:86–94`: exhaustive → needs `aurora` label arm.
6. **Settings tiles + selectedLabel switch** — `lib/features/settings/presentation/widgets/background_choice_control.dart:26–34` (exhaustive selectedLabel switch) + manual `==` tiles (25/89 default, 105 cosmic, 123 cosmic-mirrored, 141 daylight). Adding the Aurora tile + retiring the cosmic-mirrored tile are **manual** edits.
7. **Persistence** — `lib/features/settings/application/background_preference_use_cases.dart:10–11,19–22`: the ONLY semantic read (`load → fromStorageString`) and write (`save → toStorageString`). **No SQLite row exists** (grep of `lib/**/data|infrastructure` for `background_preference` ∩ `sql|migrat|schema|table` = 0 hits) → **no DB version bump, no imperative migration**. Migration = read-time remap + render repoint.
8. **Account Move** — `migration_secure_storage_registry.dart:54–60`: key registered `policy: migrate, criticality: optional`. Donor reads the raw value and copies it **byte-for-byte** (`bundle_transfer.dart:341/350/2026/2033`); recipient promotes it verbatim (`staging.dart:66–76`) — **no whitelist / no `fromStorageString` validation**. So token strings survive any cross-build move and are re-interpreted by the recipient's own codec.

**No raw storage-token string comparison exists anywhere in `lib/` outside the codec** (switch-census, high confidence): every `'default'`/`'cosmic'`/`'cosmic_mirrored'`/`'daylight_lagoon'` literal in code lives only in `toStorageString`/`fromStorageString`; all other hits are `.arb` data + generated `app_localizations*.dart` label getters. There is **no** `switch` on `.toStorageString()`/`.name`/`.index`.

Refuted / do-NOT-re-introduce:
- ❌ "Needs a DB migration / `DB v##`." — **False.** SecureKeyStore only; no schema. Read-time remap suffices.
- ❌ "Account-move whitelists token values so `'aurora'` would be rejected." — **False.** Verbatim byte copy, no validation (`bundle_transfer.dart` / `staging.dart`).
- ❌ "Keep `cosmicMirrored` as a hidden parse-only alias." — **Rejected.** A hidden tile that no `== defaultBackground` check highlights leaves a `'cosmic_mirrored'` user with *no* selected tile. Remapping `'cosmic_mirrored' → defaultBackground` is required regardless, which makes `cosmicMirrored` unreachable dead code. **Retire it.**
- ❌ "Some other surface hard-assumes `defaultBackground` renders the glow." — **False.** `startup_router.dart:320`, `main.dart`, `app_shell_controller.dart:50` only forward the resolved enum. The only `default == glow` coupling is the `_usesDefaultBackground` gate (item 3).

## Real Scope
**In scope** (the swap + rename + migration + gate repoint + tests):
- `background_preference.dart`: retire `cosmicMirrored`, add `aurora('aurora')`; `fromStorageString`: `'cosmic_mirrored' → defaultBackground` (explicit branch for clarity), add `'aurora' → aurora`, keep `'default'/null/unknown → defaultBackground`.
- `ambient_background.dart`: render arm `defaultBackground => CosmicBackgroundMirrored`, add `aurora => _DefaultAmbientBackground(animation: _controller)`; repoint `_usesDefaultBackground` (rename → `_usesGlowBackground`) to `== aurora`.
- `background_readable_colors.dart`: `aurora` → `dark` tone.
- `settings_screen.dart` + `background_choice_control.dart`: `aurora` label arm; replace the cosmic-mirrored **tile** with an **Aurora tile** (key `background-choice-aurora`); repoint the Default tile's **description** to describe Mirror Cosmic.
- l10n (`app_en.arb`, `app_de.arb`, `app_ar.arb` + `flutter gen-l10n`): change `settings_background_default_desc`; add `settings_background_aurora` / `_desc` / `_selected`; retire `settings_background_cosmic_mirrored` / `_desc` / `_selected`.
- Update the **9 existing test files** that reference `cosmicMirrored`/`cosmic_mirrored` (compile-break + behavior flips) — these carry the RED→GREEN evidence.

**Out of scope** (owned elsewhere):
- Renaming `daylightLagoon`'s enum value to match its "Signal" label (221 reskin follow-up — memory `project_221_signal_light_background_reskin_planned`). Untouched here.
- Any visual retuning of the Mirror Cosmic / glow painters themselves.
- The pre-existing failing `onboarding_landing_surface_test` (221 WIP) — unrelated.
- Reworking the account-Move pipeline (only asserting its round-trip still holds).

## Files To Inspect Next
Production (edit): `background_preference.dart`, `ambient_background.dart`, `background_readable_colors.dart`, `background_choice_control.dart`, `settings_screen.dart`; `lib/l10n/app_en.arb`, `app_de.arb`, `app_ar.arb` (+ generated `app_localizations*.dart` via `flutter gen-l10n`).
Do-NOT-edit but verify compiles/round-trips: `background_preference_use_cases.dart`, `settings_wired.dart`, `app_shell_controller.dart`, `startup_router.dart`, `migration_secure_storage_registry.dart`, `cosmic_background_mirrored.dart`.
Tests to update (compile-break or flip — full blast radius): `test/features/settings/application/background_preference_use_cases_test.dart`, `test/features/settings/presentation/widgets/background_choice_control_test.dart`, `test/features/identity/presentation/widgets/ambient_background_test.dart`, `test/core/theme/background_readable_colors_test.dart`, `test/features/settings/presentation/screens/settings_screen_test.dart` + `settings_wired_test.dart`, `test/features/conversation/presentation/screens/conversation_screen_test.dart`, `test/features/posts/phase1/app_shell_controller_test.dart`, `test/features/theme/dark_preset_preservation_test.dart`, `integration_test/settings_background_choice_smoke_test.dart`, `integration_test/feed_performance_test.dart`.

## Existing Tests Covering This Area
- `background_preference_use_cases_test.dart` — **is** the codec test: `toStorageString`/`fromStorageString`/`load`/`save` (exists; asserts `cosmicMirrored`↔`'cosmic_mirrored'`). Will flip + compile-break.
- `ambient_background_test.dart` — render switch per preference + glow animation controller gating + chat suppression (exists; asserts `default → glow`, `cosmicMirrored → mirror`). Will flip + compile-break. **Already pinned in `run_test_gates.sh:206`.**
- `background_choice_control_test.dart` — tiles/labels/semantics/locales (exists; asserts "Mirrored cosmic" tile + taps `background-choice-cosmic-mirrored`). Will flip + compile-break.
- `background_readable_colors_test.dart` — tone per preference (exists). Needs `aurora → dark`.
- `settings_screen_test.dart` / `settings_wired_test.dart` — label switch + save flow (exist).
- `integration_test/settings_background_choice_smoke_test.dart` — end-to-end choose-a-background smoke (exists). **Pinned in `run_test_gates.sh:378`.**
- `migration_secure_storage_registry_test.dart:63-64` — asserts `background_preference → policy:migrate` (exists; **the real SC-11 round-trip lock** — gates the key's migrate-policy, which is what makes the token travel verbatim; auto-globs into `feature-host-all`).
- `account_migration_journey_screen_test.dart` — uses `backgroundPreference: daylightLagoon` as a **render prop only** (`:124,187`), never write→read (§C5: proves nothing about the round-trip; kept as a stays-green preservation sentinel, NOT the SC-11 lock).

Missing coverage gaps (new tests this plan adds): (a) `default → Mirror Cosmic`; (b) `aurora → glow`; (c) `'cosmic_mirrored' → defaultBackground` remap; (d) glow animation gate now keys off `aurora`; (e) `aurora` codec round-trip; (f) source-guard: no token string-branch outside the codec.

Already in curated family arrays?: `ambient_background_test.dart` and `settings_background_choice_smoke_test.dart` are individually pinned in `run_test_gates.sh` (206, 378). New host tests **auto-glob** into `feature-host-all` / `core-host-all`. No background family array exists.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

> Prefer assertions expressible via **storage strings + existing symbols** so they fail as *assertion* errors on HEAD, not compile errors. New-enum-value references (`aurora`) are unavoidably **compile-RED until the value is added** — documented as such.

1. `background_preference_use_cases_test.dart`::`'parses cosmic_mirrored as the new default (Mirror Cosmic)'` **(NEW)**
   - Tier: unit/application (host).
   - Shape: `expect(BackgroundPreference.fromStorageString('cosmic_mirrored'), BackgroundPreference.defaultBackground);`
   - RED on HEAD because: HEAD returns `cosmicMirrored` (line 34–37). Assertion fails. **Clean assertion-RED (both symbols exist on HEAD).**
   - GREEN after fix asserts: `'cosmic_mirrored' → defaultBackground` (retired token consolidates into Default).
   - Mutation that re-reds: re-add `if (value == 'cosmic_mirrored') return cosmicMirrored;` → RED.

2. `background_preference_use_cases_test.dart`::`'aurora token round-trips'` **(NEW)**
   - Tier: unit/application.
   - Shape: `expect(BackgroundPreference.aurora.toStorageString(), 'aurora'); expect(BackgroundPreference.fromStorageString('aurora'), BackgroundPreference.aurora);`
   - RED on HEAD because: `BackgroundPreference.aurora` does not exist → **compile-RED (documented; new enum value)**.
   - GREEN after fix asserts: `aurora ↔ 'aurora'`.
   - Mutation that re-reds: remove the `aurora` arm from `toStorageString` → compile/assert RED.

3. `background_preference_use_cases_test.dart`::`'default, null, unknown all resolve to Default'` **(update existing parse test)**
   - Tier: unit/application.
   - Shape: assert `fromStorageString('default') == defaultBackground`, `fromStorageString(null) == defaultBackground`, `fromStorageString('garbage') == defaultBackground` (unchanged) **AND** the load-tier test `'returns default when stored value is default'` now documents that Default == Mirror Cosmic.
   - RED on HEAD because: these specific parse rows stay green on HEAD (they already pass) — this row's RED lives in the *render* test (#4); here it is a **preserved-green invariant** guarding that the remap did not disturb the fallback. (No mutation needed beyond #1/#5.)

4. `ambient_background_test.dart`::`'default preference renders Mirror Cosmic'` **(NEW; replaces the glow assertions in `renders child over the default background treatment`)**
   - Tier: widget.
   - Shape: `wrapAmbient()` (default preference) → `expect(find.byType(CosmicBackgroundMirrored), findsOneWidget); expect(find.byKey(const ValueKey('cosmic-background-mirrored-root')), findsOneWidget); expect(find.byType(CosmicBackground), findsNothing);` and assert the `0xFF0A1124`/`0xFF02030A` gradient colors.
   - RED on HEAD because: HEAD renders `_DefaultAmbientBackground` (glow) for default → no `cosmic-background-mirrored-root`. **Clean widget-RED.**
   - GREEN after fix asserts: default → Mirror Cosmic.
   - Mutation that re-reds: revert the render arm `defaultBackground => _DefaultAmbientBackground` → RED.

5. `ambient_background_test.dart`::`'aurora preference renders the ambient glow'` **(NEW; repurposes the retired-`cosmicMirrored` glow assertions onto `aurora`)**
   - Tier: widget.
   - Shape: `wrapAmbient(preference: BackgroundPreference.aurora)` → assert `AppColors.background` container + green-glow(0.3)/red-glow(0.25) radial gradients present, `CosmicBackgroundMirrored` findsNothing.
   - RED on HEAD because: `BackgroundPreference.aurora` absent → compile-RED (new value).
   - GREEN after fix asserts: `aurora → glow`.
   - Mutation that re-reds: remove the `aurora => _DefaultAmbientBackground` arm → RED.

6. `ambient_background_test.dart`::`'aurora glow animates (motion on), is suppressed on chat surfaces, and honors OS reduce-motion'` **(NEW — locks the `_usesDefaultBackground` landmine, INV-5)**
   - Tier: widget.
   - Shape: (a) `wrapAmbient(preference: aurora, disableAnimations: false)` → `ambientControllers(tester).first.isAnimating == true`; (b) `wrapAmbient(preference: aurora, chatSurface: true, disableAnimations: false)` → `isAnimating == false` (158 suppression follows the glow); (c) `wrapAmbient(preference: aurora, disableAnimations: true)` → `isAnimating == false` (156 OS gate).
   - **(§C2) Part (d) DROPPED** — "default (Mirror Cosmic) leaves the shared controller idle" is **unobservable**: `ambientControllers` returns only `AnimatedBuilder`-bound controllers, and Mirror Cosmic renders through `CustomPaint`, so the helper is empty for default → the clause is vacuous (and with `.first` it would be the one place that throws). The landmine is **fully locked by (a) + its mutation-revert**; do not author (d).
   - RED on HEAD because: `aurora` absent → compile-RED; and logically, if `_usesDefaultBackground` is not repointed, (a) fails (glow frozen at value 0).
   - GREEN after fix asserts: the glow gate keys off `aurora`; mirror-cosmic default self-manages (via its own controller, not `_controller`).
   - Mutation that re-reds: revert `_usesDefaultBackground` back to `== defaultBackground` → (a) RED (aurora glow frozen).

7. `background_choice_control_test.dart`::`'shows Default/Cosmic/Aurora/Signal; no Mirrored-cosmic tile; Default describes Mirror Cosmic'` **(update existing `shows all background options…`)**
   - Tier: widget.
   - Shape: assert `find.text('Aurora')` findsOneWidget, the new Default description text findsOneWidget, `find.text('Mirrored cosmic')` **findsNothing**, `find.byKey(ValueKey('background-choice-aurora'))` present, `background-choice-cosmic-mirrored` **absent**; Default tile selected by default.
   - RED on HEAD because: HEAD shows the "Mirrored cosmic" tile and no "Aurora"/`background-choice-aurora`. **Clean widget-RED** (text/keys).
   - GREEN after fix asserts: tiles Default/Cosmic/Aurora/Signal.
   - Mutation that re-reds: revert the tile swap in `background_choice_control.dart` → RED.

8. `background_choice_control_test.dart`::`'tapping Aurora selects aurora; Mirror-cosmic-as-default recovery path'` **(update existing `tapping options notifies selection`)**
   - Tier: widget.
   - Shape: tap `background-choice-aurora` → `onChanged` receives `BackgroundPreference.aurora`; tap `background-choice-default` → `defaultBackground` (Mirror Cosmic). (Removes the `cosmic-mirrored` tap.)
   - RED on HEAD because: `aurora` + key absent → compile-RED.
   - GREEN: Aurora tile is the re-selection path for the old glow.
   - Mutation that re-reds: remove the Aurora tile `onTap` → RED.

9. `background_readable_colors_test.dart`::`'aurora resolves to the dark tone'` **(NEW/update)**
   - Tier: unit (test/core/**).
   - Shape: `expect(BackgroundReadableColors.toneForPreference(BackgroundPreference.aurora), BackgroundReadableTone.dark);` and `resolve(aurora) == BackgroundReadableColors.dark`.
   - RED on HEAD because: `aurora` absent → compile-RED.
   - Mutation that re-reds: move `aurora` to the `representativeLight` arm → RED.

10. `ambient_background_test.dart`::`'no background token string is branched on outside the codec'` **(NEW — INV-6 source-guard)**
    - Tier: unit (source-scan, like the existing `production code does not import…` test in the same file).
    - Shape **(§C1 — precision, load-bearing)**: for each `lib/**.dart` except `background_preference.dart`, assert absence of the **quote-adjacent token literals** — the exact byte sequences `'aurora'`, `"aurora"`, `'cosmic_mirrored'`, `"cosmic_mirrored"` (an opening quote immediately before the word and a closing quote immediately after). **Do NOT** use a bare `contains('aurora')` substring: that FALSE-REDs the whole `feature-host-all` gate on the first GREEN run, because the new l10n key `settings_background_aurora` and the `ValueKey('background-choice-aurora')` both embed the substring `aurora` in `settings_screen.dart` / `background_choice_control.dart` / generated `app_localizations*.dart`. The quote-adjacent form matches ONLY the codec's own token literals (which live solely in `background_preference.dart`) and excludes the l10n key names and the widget key.
    - RED on HEAD because: passes on HEAD (already true) — this is a **preserved-green guard** locking that the swap did not introduce a stray string branch. Mutation that re-reds: add a `if (v == 'cosmic_mirrored')` branch in any other `lib/` file → RED. (Guard, not a flip.)

## Test Coverage Matrix  (zero empty cells in tier / mutation / gate / registration)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| SC-1 default→Mirror Cosmic | UI render | widget | `ambient_background_test`::`default preference renders Mirror Cosmic` (#4) | HEAD default renders glow, no mirror-root key | revert `defaultBackground=>_DefaultAmbientBackground` | `run_host_test_gates.sh feature-host-all` | AUTO (glob); file also pinned `run_test_gates.sh:206` |
| SC-2 old glow → `aurora` | UI render | widget | `ambient_background_test`::`aurora preference renders the ambient glow` (#5) | `aurora` absent (compile-RED) | remove `aurora=>_DefaultAmbientBackground` arm | `run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| SC-3 aurora codec | serialization | unit | `background_preference_use_cases_test`::`aurora token round-trips` (#2) | `aurora` absent (compile-RED) | remove `aurora` arm in `toStorageString` | `run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| SC-4 `'default'`/null→Default(=Mirror Cosmic) | migration (auto) | unit+widget | `use_cases_test`::`default…resolve to Default` (#3) + `ambient…default renders Mirror Cosmic` (#4) | render row RED on HEAD | revert render arm | `run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| SC-5 `'cosmic_mirrored'`→Default | migration remap | unit | `use_cases_test`::`parses cosmic_mirrored as the new default` (#1) | HEAD returns `cosmicMirrored` | re-add `'cosmic_mirrored'=>cosmicMirrored` branch | `run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| SC-5b Default tile highlights for `'cosmic_mirrored'` user | settings UI (via codec) | widget | `background_choice_control_test`::`cosmic_mirrored user sees Default tile selected` — construct `BackgroundChoiceControl(value: BackgroundPreference.fromStorageString('cosmic_mirrored'))`, assert `background-choice-default-selected-icon` findsOneWidget (§C4: routes through the codec so the mutation truly re-reds — the widget takes `value` directly, so a plain `value:` assert would bypass `fromStorageString`) | HEAD: `fromStorageString('cosmic_mirrored')`==`cosmicMirrored` → cosmic-mirrored tile selected, Default NOT → assertion-RED | re-add `'cosmic_mirrored'=>cosmicMirrored` branch → RED | `run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| SC-6 null→Mirror Cosmic (new user) | migration/load | unit | `use_cases_test`::`returns default when key not set` (existing) + #4 render | render row RED on HEAD | revert render arm | `run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| SC-7 preserve `'cosmic'`/`'daylight_lagoon'` | preserve | unit | `use_cases_test`::`parses known…values` (existing, keep green) | n/a (preserved-green) | change either parse arm → RED | `run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| SC-8 glow gate keys off `aurora` (landmine) | animation gate | widget | `ambient_background_test`::`aurora glow animates, chat-suppressed, honors OS reduce-motion` (#6a) + the six §A2-repointed default tests | `aurora` absent + glow frozen if not repointed | revert `_usesGlowBackground`→`==defaultBackground` | `run_host_test_gates.sh feature-host-all` | AUTO (glob); pinned :206 |
| SC-9 settings tiles Default/Cosmic/Aurora/Signal + tap | settings UI | widget | `background_choice_control_test`::#7 + #8 | HEAD has Mirrored-cosmic tile, no Aurora | revert tile swap | `run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| SC-10 aurora→dark tone | pure logic | unit | `background_readable_colors_test`::`aurora resolves to the dark tone` (#9) | `aurora` absent (compile-RED) | move aurora to light arm | `run_host_test_gates.sh core-host-all` | AUTO (glob, test/core/**) |
| SC-11 account-Move round-trips | key-policy (not token value) | unit | `migration_secure_storage_registry_test`::asserts `byKey['background_preference'].policy == migrate` (`:63-64`) — §C5 re-cite: the OLD citation `account_migration_journey_screen_test` uses `backgroundPreference: daylightLagoon` as a **render prop only** (`:124,187`), never write→read, so it proves nothing about the round-trip; the registry test gates the KEY's migrate-policy (which is what makes the token travel verbatim) | n/a (verbatim copy, no code change; stays green) | change the key's `policy` in the registry → RED | `run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| SC-12 durability (reread reconstructs) | lifecycle | unit | `use_cases_test`::`returns default when stored value is default`/`…cosmic_mirrored` load-tier (#1 at load) | HEAD load returns cosmicMirrored | revert remap | `run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| SC-13 no stray token branch | invariant guard | unit | `ambient_background_test`::`no background token string branched outside codec` (#10) | preserved-green | add a `if(v=='cosmic_mirrored')` branch in another file → RED | `run_host_test_gates.sh feature-host-all` | AUTO (glob) |
| SC-ACC top acceptance leg | end-to-end pick | integration | `integration_test/settings_background_choice_smoke_test` (update cosmic-mirrored→aurora) | selects removed value (compile) | n/a | `flutter test integration_test/settings_background_choice_smoke_test.dart` | pinned `run_test_gates.sh:378` (no new reg) |

## Blind-Spot Sweep  (evergreen — row or justified N/A)
- **Lifecycle / derived-state durability:** **Covered — SC-12.** The choice persists in SecureKeyStore; on restart, `loadBackgroundPreference → fromStorageString` re-resolves. Load-tier tests assert a store holding `'cosmic_mirrored'` reconstructs `defaultBackground` (Mirror Cosmic), and `'default'`/null reconstruct Mirror Cosmic. No in-memory derived latch beyond the resolved enum forwarded to `appShellController`.
- **Sibling-surface consistency:** **Covered — SC-1 + existing `current shared-background screen surfaces use AmbientBackground` scan.** All 16+ surfaces render through the single `AmbientBackground` switch (single source of truth). Constructor default-params (`this.backgroundPreference = defaultBackground`) merely pass the enum; the real value flows from `appShellController` (`settings_wired`/`startup_router`/`feed_wired`). No per-surface default branching → the new default propagates uniformly; SC-1 proves it for the shared widget every surface uses.
- **Destructive-action side-effects:** **Covered — SC-2 + SC-9 (#8).** The "destructive" effect is intended: users on `'default'` (indistinguishable from never-chose) lose the glow and get Mirror Cosmic. The **recovery path** is the new Aurora tile; #8 asserts tapping Aurora → `aurora` → glow, and #5 asserts `aurora` renders the glow. This makes the loss reversible and test-locked (not merely asserted in prose).
- **Invariant re-verification under new transitions:** **Covered — SC-8 (#6a) + §A repoints.** The new transitions are "select Aurora" and "Default now means Mirror Cosmic." #6(a) re-verifies the full glow-animation invariant set (motion-on animates, chat suppression, OS reduce-motion) under `aurora` — the exact invariant the `_usesDefaultBackground` landmine would silently break — plus the six existing default-preference motion tests (§A2) are *repointed* to `aurora` so their 156/158 coverage rides the glow to its new home rather than being deleted. (The default-side "controller idle" check is dropped per §C2 as unobservable.)

## Invariants (locked by tests)
- INV-1: `defaultBackground` renders exactly `CosmicBackgroundMirrored` (Mirror Cosmic) → #4.
- INV-2: The ambient glow is reachable **only** via `aurora` → #5.
- INV-3: `'default'`, null, unknown, and `'cosmic_mirrored'` all resolve to `defaultBackground` → #1, #3.
- INV-4: `'cosmic'`, `'daylight_lagoon'` preserved → SC-7 (existing parse test).
- INV-5: The glow animation gate keys off `aurora`, not `defaultBackground` → #6.
- INV-6: No background storage-token is branched on outside the codec → #10.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan  (§D — TWO GATED SLICES)

> Adding `aurora` is **purely additive** — it compiles with `cosmicMirrored` still present. So split the work at a **bisectable, host-green waypoint**: Slice A introduces `aurora` alongside the intact old default; Slice B flips the behavior and retires `cosmicMirrored`. Release-risk is standard (B-1 CLEAR: cosmetic-only, no brick, no data loss).

**S0. Snapshot** `git status --short` (dirty tree has 221 WIP — do not revert). Confirm scope files only.

### Slice A — additive (`aurora` added, `cosmicMirrored` fully intact, reversible)  (§D1)
1. **RED first (Slice-A tests):** add the `aurora`-only tests (#2 codec round-trip, #5 aurora→glow **render**, #9 aurora→dark tone, #8 Aurora-tile tap). These are **compile-RED** until step 2 (documented; new enum value). **#6a is deliberately NOT a Slice-A test** — it asserts the aurora glow *animates*, which requires the `_usesGlowBackground` gate repoint that lives in **Slice B step 8**. In Slice A the gate is still `== defaultBackground`, so `_shouldAnimate` returns false for `aurora` at its first clause (`if (!_usesDefaultBackground) return false;`) → the glow is frozen → #6a would be RED at the step-6 checkpoint. It is authored in Slice B (step 7).
2. **Enum/codec** (`background_preference.dart`): add `aurora`; `toStorageString`: `aurora => 'aurora'`; `fromStorageString`: add `if (value == 'aurora') return aurora;`. **Leave `cosmicMirrored` and its `'cosmic_mirrored'` branch untouched.**
3. **Add `aurora` arms to all FIVE exhaustive switches** (compiler-forced): `toStorageString`; render → `aurora => _DefaultAmbientBackground(animation: _controller, child: …)`; `toneForPreference` → `dark`; `settings_screen._backgroundValueLabel` → `l10n.settings_background_aurora`; `background_choice_control` `selectedLabel`.
4. **Add the Aurora tile** (`background_choice_control.dart`): keys `background-choice-aurora`/`-semantics`/`-selected-icon`, `label: settings_background_aurora`, `description: settings_background_aurora_desc`, `selectedLabel: settings_background_aurora_selected`, **`isSelected: value == BackgroundPreference.aurora`** (§E2, mirrors `:123`), `onChanged(BackgroundPreference.aurora)`. Leave the Mirrored-cosmic tile in place for now.
5. **Add `settings_background_aurora*` l10n keys** (all 3 arb) + `flutter gen-l10n`. Do NOT yet touch `settings_background_default_desc` or the `cosmic_mirrored*` keys.
6. **✅ Checkpoint (Slice-A gate):** `./scripts/run_host_test_gates.sh feature-host-all` **and** `core-host-all` GREEN (Aurora is now a live 5th option; nothing removed yet).

### Slice B — behavior-flip + retire (`cosmicMirrored` removed, default → Mirror Cosmic)  (§D2)
7. **RED first (Slice-B flips):** add/repoint the flip tests — #1 (`'cosmic_mirrored' → defaultBackground`, assertion-RED), #4 (default → Mirror Cosmic, widget-RED), **#6a (aurora glow animates / chat-suppressed / OS-gate — the landmine lock; `aurora` already exists from Slice A so this is now *assertion-RED*, not compile-RED: with the gate still `== defaultBackground` the aurora glow is frozen → goes GREEN only at the step-8 repoint, and its mutation-revert re-reds it)**, #7 (tiles Default/Cosmic/Aurora/Signal, no Mirrored-cosmic), SC-5b (#7 concrete: `value: fromStorageString('cosmic_mirrored')` → Default selected). Run them and confirm assertion-RED for the documented reason before editing production.
8. **Render + gate flip** (`ambient_background.dart`): render arm `defaultBackground => CosmicBackgroundMirrored(child: …)`; rename `_usesDefaultBackground` → `_usesGlowBackground`, body `preference == BackgroundPreference.aurora`. **Stop-if:** if the compiler does NOT force an arm you expected, a switch went non-exhaustive — re-audit, do not add a `default:`.
9. **✅ Payoff-early checkpoint** (§D3, immediately after step 8, BEFORE the mechanical edits): `flutter test .../ambient_background_test.dart --plain-name 'default preference renders Mirror Cosmic'` (#4) **and** the #6(a) landmine test → both GREEN. This confirms the two load-bearing edits before touching tone/settings/l10n.
10. **Codec retire** (`background_preference.dart`): add `if (value == 'cosmic_mirrored') return defaultBackground;` (explicit, self-documenting), then **remove `cosmicMirrored`** from the enum + its arms in all five switches (compiler-forced sweep).
11. **l10n flip** (all 3 arb): set `settings_background_default_desc` → Mirror-Cosmic copy (en: "Mirrored cosmic drift with soft color blooms."); **remove** `settings_background_cosmic_mirrored`/`_desc`/`_selected`. Remove the Mirrored-cosmic **tile** from `background_choice_control.dart`. The Default tile's `:87` code stays **byte-identical** — the desc change is solely the `settings_background_default_desc` **arb value** (§E2), not a code edit.
12. **Run codec/render/tone/settings direct-GREEN legs BEFORE `flutter gen-l10n`** (§D4), so the committed generated-file diff lands on a known-green base and any post-regen failure isolates to l10n. Then `flutter gen-l10n`.
13. **Update the existing tests** to the new behavior. **Disposition rules (do NOT weaken):**
    - **§A2 — the six default-preference motion tests** in `ambient_background_test.dart` (**TC-04** `:121`, **TC-05** `:132`, **TC-158-01** `:198`, **TC-158-02** `:220`, **TC-158-03** `:234`, **'Feed surface with default preference stays default'** `:411`) go **assertion-RED** once default renders Mirror Cosmic (the `ambientControllers` helper is empty for `CustomPaint`). **CONVERT each to `preference: BackgroundPreference.aurora`** — the glow moved there, so these motion/chat/OS-gate assertions must follow it. **Do NOT weaken them to `isEmpty`/`findsNothing`** (that deletes the 156 OS-reduce-motion + 158 chat-suppression coverage on the live glow). #6 is their named landmine lock, not a substitute. **Rename any repointed test whose name references "default"** so the name matches the new assertion — e.g. `'Feed surface with default preference stays default'` → `'Feed surface with aurora preference animates the glow'`.
    - **§B1 — render-vs-glow rebase target:** when rebasing a `cosmicMirrored` reference, **split by intent** — a **render-assert** ("`CosmicBackgroundMirrored` is present") rebases to **`defaultBackground`** (now Mirror Cosmic); a **glow/animation-assert** rebases to **`aurora`**. Blindly swapping all → `aurora` inverts the render-asserts.
    - **§B2 — apply to the two known render-assert sites:** `conversation_screen_test.dart:349-365` (`'renders the selected mirrored cosmic background'`, `find.byType(CosmicBackgroundMirrored)`) → `defaultBackground`. `feed_performance_test.dart` FEED6: the **baseline** first pump (`:416`, feeding `:417 expect(CosmicBackgroundMirrored, findsNothing)`) → `BackgroundPreference.aurora` (keeps `findsNothing` valid — glow ≠ mirror); the **explicit mirrored** second pump (`:424/:427 findsOneWidget`) → `defaultBackground`. (Blindly sending both to `defaultBackground` makes `:417 findsNothing` fail.)
    - Also update `integration_test/settings_background_choice_smoke_test.dart` (cosmic-mirrored selection → `aurora` or default per intent), and the remaining flip files (`background_preference_use_cases_test`, `background_choice_control_test` locales/semantics, `background_readable_colors_test`, `settings_screen_test`/`settings_wired_test`, `posts/phase1/app_shell_controller_test`, `theme/dark_preset_preservation_test`).
14. Rerun direct → preservation → named gates (below), **incl. the FEED6 gate** `flutter test integration_test/feed_performance_test.dart` (§B3 — not globbed by host-all). **Stop-if:** any failure outside scope → replan.
15. `graphify update .` + `./graphify-arch/refresh_arch_graph.sh` (app-owned code changed).

## Risks And Edge Cases
- **`_usesDefaultBackground` silent breakage** (glow freezes on `aurora`) → pinned by #6; mutation-verified.
- **Non-exhaustive switch hiding a missed site** → switch-census confirmed **all 5** exhaustive switches are compiler-forced (`toStorageString`, render, `toneForPreference`, `settings_screen._backgroundValueLabel`, `background_choice_control.selectedLabel`) + the 2 non-switch `==` sites (`_usesGlowBackground`/formerly `_usesDefaultBackground`, tile list) are hand-edited and locked by #6/#7.
- **Test blast-radius under-count (§A)** → the six default-preference motion tests fail **assertion-RED** (not compile-RED, not a throw — the `expect(controllers, isNotEmpty)` guard fires before `.first`); §A2 mandates repoint-to-`aurora`, do not weaken. **Blast-radius bounded:** `grep -rln 'greenGlow\|redGlow' test/ integration_test/` returns only `ambient_background_test.dart` — no other surface test (feed/posts/orbit) asserts the default glow.
- **Silent semantic-inversion in a non-gated test (§B3)** → `feed_performance_test.dart` FEED6 runs in NO named host gate (`integration_test/` not globbed by `run_host_test_gates.sh:132-133`); `flutter analyze` catches only its `cosmicMirrored` compile-break, NOT the `:417 findsNothing → findsOneWidget` inversion. The added `flutter test integration_test/feed_performance_test.dart` gate is the only thing that catches a wrong rebase.
- **Account-Move new→old downgrade** (a NEW-build Default user, token `'default'`, moving to an OLD build sees the glow, since `'default'` == glow there): acceptable, forward-compat only; noted as Accepted Difference. Old→new and new→old for `aurora`/`cosmic_mirrored`/null all verified visually correct (round-trip matrix in Root Cause item 8).
- **Feed reduce-motion (134)**: `feed_reduced_motion_test` asserts only feed-*local* durations + bounded-pump settling; `CosmicBackgroundMirrored` self-gates its controller under `disableAnimations` (`cosmic_background_mirrored.dart:90–95`), so the mirror-cosmic default behaves like the glow did for that test → stays green (preservation sentinel). The app-level feed `reduceMotion` flag (134 §7) only ever gated the glow loop; with Mirror Cosmic as default it no longer applies, but OS reduce-motion IS still honored internally → accessibility preserved (animation-gating agent, high confidence).
- **Orphaned l10n**: retiring `settings_background_cosmic_mirrored*` must remove all 3 arb entries + regen, else the locale test still expects them. Locked by #7 locale assertions.

## Device/Relay Proof Profile
**host-only for closure.** This is a pure-Dart UI/preference/codec change: **no** OS callback, **no** crypto/ML-KEM convergence, **no** relay custody, **no** real SQLCipher (preference lives in SecureKeyStore; tests use `FakeSecureKeyStore`). Per the tier matrix, the lowest tier that fails for the real reason is host unit + widget; the boundary that would force a device-proof (OS/crypto/cross-device/real-relay) is absent. Closure gate = host `feature-host-all`/`core-host-all` GREEN **+** the existing `integration_test/settings_background_choice_smoke_test.dart` (top acceptance leg, pinned `run_test_gates.sh:378`). Account-Move round-trip is asserted at the existing fake-integration tier (verbatim byte copy, no code change). No feature flag to flip; no relay config needed.
Optional manual smoke (not a gate): fresh install → Orbit shows Mirror Cosmic; Settings → Background shows Default/Cosmic/Aurora/Signal; pick Aurora → glow; restart → persists.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before production edits) — assertion-RED ones must FAIL for the documented reason
flutter test test/features/settings/application/background_preference_use_cases_test.dart \
  --plain-name 'parses cosmic_mirrored as the new default'          # RED: HEAD returns cosmicMirrored
flutter test test/features/identity/presentation/widgets/ambient_background_test.dart \
  --plain-name 'default preference renders Mirror Cosmic'           # RED: HEAD renders glow
# (aurora-referencing tests are compile-RED until the enum value exists — documented)

# Direct GREEN (after fix)
flutter test test/features/settings/application/background_preference_use_cases_test.dart
flutter test test/features/identity/presentation/widgets/ambient_background_test.dart
flutter test test/features/settings/presentation/widgets/background_choice_control_test.dart
flutter test test/core/theme/background_readable_colors_test.dart

# Preservation sentinels (must stay green)
flutter test test/features/feed/presentation/screens/feed_reduced_motion_test.dart
flutter test test/features/account_migration/presentation/account_migration_journey_screen_test.dart

# Named host gates (auto-glob) — full feature + core host suites
./scripts/run_host_test_gates.sh feature-host-all      # expect: all green (no new failures vs baseline)
./scripts/run_host_test_gates.sh core-host-all         # expect: all green

# Top acceptance leg (curated, pinned run_test_gates.sh:378)
flutter test integration_test/settings_background_choice_smoke_test.dart

# FEED6 render-rebase gate (§B3) — integration_test/ is NOT globbed by host-all;
# without this line a wrong FEED6 rebase (:417 findsNothing → findsOneWidget) ships silently.
flutter test integration_test/feed_performance_test.dart

# l10n regen must be clean and committed
flutter gen-l10n && git diff --stat lib/l10n/app_localizations*.dart

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```
(No migration gate: `test/core/database/migrations/**` is **not** touched — no schema change.)

## Known-Failure Interpretation
- **Expected RED (new tests)**: #1, #4, #7, SC-5b assertion-RED on HEAD; **#2/#5/#6/#8/#9 compile-RED** until `aurora` exists (documented — new enum value). **#3 and #10 are preserved-GREEN guards** (§C3 — #3 uses only `fromStorageString('default'/null/'garbage')`, no `aurora` symbol, so it is neither compile-RED nor assertion-RED on HEAD; it guards that the remap did not disturb the fallback).
- **(§A1) Expected assertion-RED (existing default-preference tests, in `ambient_background_test.dart`)** once `defaultBackground` renders Mirror Cosmic — these are NOT scope-drift, do NOT misread as blocking, do NOT weaken; **repoint to `aurora`** (§A2, disposition in Step 13): **TC-04** (`:121-130`), **TC-05** (`:132-141`), **TC-158-01** (`:198-218`), **TC-158-02** (`:220-232`), **TC-158-03** (`:234-246`), **'Feed surface with default preference stays default'** (`:411-418`). They fail as a **clean `expect(controllers, isNotEmpty)` assertion-RED** (the `isNotEmpty` guard fires before `.first` — NOT a `Bad state` throw), because Mirror Cosmic renders via `CustomPaint`, so the `ambientControllers` helper returns empty.
- **Pre-existing dirty**: 221 "Paper White" reskin WIP + graphify regen in the tree (see initial `git status`). Do NOT revert. `onboarding_landing_surface_test` fails pre-existing (221) — unrelated.
- **Environment blocker (NOT product)**: none — host-only closure; no sim/device required.
- **Scope drift (BLOCKING)**: any failure outside the listed files/tests **and outside the §A1 six + §B2 two known rebases** (e.g. an untouched group/transport suite) → stop and replan.

## Done Criteria
- [ ] RED added first, failed for the expected reason (assertion-RED where possible; compile-RED documented).
- [ ] Mutation-verified (each fix has a re-red revert — see matrix).
- [ ] Direct GREEN + preservation sentinels + `feature-host-all`/`core-host-all` + integration smoke pass.
- [ ] No migration test needed (no schema change) — verified `test/core/database/migrations/**` untouched.
- [ ] No device/relay proof needed — argued; host+widget+integration close it.
- [ ] Every new test auto-globs (`test/features/**` / `test/core/**`); modified pinned files (206, 378) need no new registration.
- [ ] `flutter gen-l10n` run; generated files committed; `flutter analyze` 0 new; `git diff --check` clean.
- [ ] `graphify update .` + `./graphify-arch/refresh_arch_graph.sh` run (app-owned code changed).

## Scope Guard (hard "Do not")
- Do not add a `default:`/`_ =>` catch-all to any of the **5** exhaustive switches (`toStorageString`, render, `toneForPreference`, `settings_screen._backgroundValueLabel`, `background_choice_control.selectedLabel`) — defeats compiler completeness for the next background.
- Do not touch the account-Move pipeline code, the `daylightLagoon`→"Signal" naming, or the Mirror-Cosmic/glow painter internals.
- Do not introduce a DB migration or bump any `DB v##` (there is no DB row).
- Do not leave `'cosmic_mirrored'` mapping to a live tile (retire it; remap to Default).

## Accepted Differences / Intentionally Out Of Scope
- **(product-confirmable)** **Glow-lovers on `'default'` are migrated to Mirror Cosmic** and must re-pick "Aurora" — unavoidable: `'default'` (deliberate) is indistinguishable from null (never-chose) in storage, and the requirement explicitly moves current-Default users to Mirror Cosmic. Reversibility test-locked (#5/#8).
- **(product-confirmable)** **New→old Move downgrade**: a new-build Default user moving to an old build renders the glow (old `'default'` == glow). Forward-compat only; not fixable without emitting `'cosmic_mirrored'` for the new default (rejected — would keep the retired token alive).
- **`aurora` display label** ("Aurora") + de/ar strings are product-confirmable; the durable contract is the stored token `'aurora'` (label is pure l10n, changeable in one line without another migration).
- **`daylightLagoon` enum↔"Signal" label mismatch** left as-is (221 follow-up owns the rename).

## Dependency Impact
- 221 "Paper White" reskin shares `background_readable_colors.dart` (light tone) and the ambient surfaces — this plan adds only a dark-tone `aurora` arm and does not touch `representativeLight`; land order-independent, but coordinate the shared file edit if 221 is mid-flight.

## Reviewer Findings
8-agent /tdd-review (2 source-verifiers → 5 dimension assessors → completeness critic), 2026-07-08. Verdict **yes-with-tightening**. Dimension scores: Goal-clarity 83 (strong) · Compartmentalization 62 · Anti-drift 64 · Define-good 62 · Goal-verification 68 (all adequate). **Core bet VERIFIED SOUND** — read-time-only pref/codec swap, no OS/crypto/relay/SQLite; the `_usesDefaultBackground` animation landmine is correctly identified and test-locked by #6(a)+mutation; the account-Move round-trip is safe-by-construction (verbatim byte copy, no whitelist). Every cited `file:line` accurate. Corrections are **test-precision + execution structure, not architecture** — captured in `222-review-fixlist.md`.

## Arbiter Decision
All fix-list items **verified against real source and APPLIED into this plan** (2026-07-08):
- **§A** (BLOCKER 1) — named the six default-preference tests as assertion-RED + mandated repoint-to-`aurora` (Step 13 §A2; Known-Failure §A1) + blast-radius bound (Risks). ✅
- **§B** (BLOCKER 2) — render-vs-glow rebase rule (Step 13 §B1/§B2: render-assert→`defaultBackground`, glow-assert→`aurora`; FEED6 baseline→`aurora`) + the non-globbed FEED6 gate (Acceptance Gates §B3). ✅
- **§C** — C1 INV-6 #10 respecified to quote-adjacent token literals (was a whole-gate false-RED); C2 dropped #6(d) as unobservable; C3 relabeled #3/#10 as preserved-green; C4 SC-5b routed through `fromStorageString` so the mutation re-reds; C5 re-cited SC-11 → `migration_secure_storage_registry_test:63`. ✅
- **§D** — Step-By-Step split into two gated slices (A additive → host-green checkpoint → B flip+retire) + payoff-early checkpoint + pre-`gen-l10n` green base. ✅
- **§E** — "4 exhaustive switches" → "5" (Scope Guard, Risks, +migration-contract table); E2 Aurora-tile `isSelected` + Default-tile byte-identical; E3 canonical Migration Contract table (top); E4 `(product-confirmable)` tags. ✅

**Re-review (2026-07-08, applied-plan pass):** verified every applied line-target against real source — FEED6 baseline→`aurora`/explicit→`defaultBackground` split confirmed correct (`:416/:417`, `:424/:427`), conversation_screen_test `:349` render-assert→`defaultBackground` confirmed, SC-5b codec-routing confirmed (`background-choice-default-selected-icon` key exists). **Caught + fixed one revision-introduced slice-sequencing defect:** #6a (aurora glow *animates*) was mis-assigned to Slice A but cannot pass until the Slice-B step-8 gate repoint (`_shouldAnimate` returns false for `aurora` while the gate is still `== defaultBackground`) → **moved #6a to Slice B step 7** (Slice A keeps only the render/codec/logic tests #2/#5/#8/#9). Plus two nits: FEED6 baseline line `:414`→`:416`; repointed default-named tests get renamed.

Structural blockers: none remaining. **EXECUTION-READY** — proceed Slice A (host-green checkpoint) → Slice B (payoff-early checkpoint) → gates incl. the FEED6 leg.

## Final Execution Verdict
**accepted_with_explicit_follow_up** — Plan 222 implementation is complete and QA-reviewed with no blocking 222-scoped findings. All direct, preservation, pinned acceptance, `core-host-all`, scoped analyze, l10n, whitespace, and graph refresh checks passed.

The only unresolved required-gate item is `./scripts/run_host_test_gates.sh feature-host-all`, which stops at unrelated host test `#357 test/features/groups/presentation/screens/group_conversation_wired_bg_task_test.dart` (`ordinary media upload failure after unmount still persists failed parent status`: expected `sending`, actual `queued_offline`). Focused rerun reproduces the same failure outside the 222 background-preference files. Independent QA confirmed this `unrelated_host_gate_blocker` classification is defensible and should be tracked separately before claiming a fully green `feature-host-all`.

Retry focus: fix or baseline the group background-task status expectation, then rerun `./scripts/run_host_test_gates.sh feature-host-all`. No 222-specific follow-up is required unless that retry surfaces a background-preference failure.
