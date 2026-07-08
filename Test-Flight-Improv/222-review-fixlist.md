# 222 Review — Fix-List (apply against `222-mirror-cosmic-default-background-tdd-plan.md`)

Source: 8-agent audit (2 source-verifiers → 5 dimension assessors → completeness critic) + orchestrator source-verification, 2026-07-08.
Plan is **execute-with-corrections, not execute-as-written**. **Core bet VERIFIED SOUND**: read-time-only pref/codec swap, no OS/crypto/relay/SQLite; the `_usesDefaultBackground` animation landmine is correctly identified and test-locked by #6(a)+mutation; the account-Move round-trip is safe-by-construction. What follows is **test-precision + structure**, not architecture.

Critic verdict: **yes-with-tightening**. Dimension scores: Goal-clarity 83 (strong) · Compartmentalization 62 · Anti-drift 64 · Define-good 62 · Goal-verification 68 (all adequate).

Decisions locked with the user:
- **Next action = fix-list** (this file). Do NOT edit the plan; apply these against it at execution time.
- **Slice strategy = two gated slices** (see §D). Slice A additive (`aurora` added, `cosmicMirrored` intact) → intermediate host-gate GREEN → Slice B behavior-flip + retire.
- Release-risk: **no special strategy needed** — B-1 is CLEAR (cosmetic-only reversion, no brick, no data loss). Standard ship.

Verified facts this list relies on (checked against real source by the orchestrator):
- Every cited `file:line` in the plan's Root Cause is accurate — `background_preference.dart:12-40`, `ambient_background.dart:124-136 / 157-159 / 169-175 / 103-111`, `cosmic_background_mirrored.dart:28,36,83-103,121`, `background_readable_colors.dart:248-256`, `settings_screen.dart:86-94`, `background_choice_control.dart:26-34 + 78-143`, `background_preference_use_cases.dart:10-11,19-22`. ✅ (B-3 clear)
- Landmine real: `_usesDefaultBackground` (`ambient_background.dart:157-159`) is a bare `== defaultBackground` gating the shared `_controller`; `CosmicBackgroundMirrored` self-animates via its OWN controller + self-gates OS reduce-motion (`cosmic_background_mirrored.dart:83-103`, `CustomPaint repaint:` — NOT an `AnimatedBuilder`). Repoint to `== aurora` is mandatory. ✅
- Test helper `ambientControllers(tester)` (`ambient_background_test.dart:113-119`) returns ONLY `AnimatedBuilder`-bound `AnimationController`s → returns **empty** for a Mirror-Cosmic default. ✅
- The six default-preference tests fail as **clean `expect(controllers, isNotEmpty)` assertion-RED** (guards at `:128/139/207/229/243` fire before any `.first`) — NOT a `Bad state` throw. ✅
- Account-Move copies the token **verbatim**, no whitelist (`migration_secure_storage_registry.dart:56` registers `BackgroundPreference.storageKey`, `policy:migrate/optional`; donor/recipient never validate the value). ✅
- Five (not four) compiler-forced exhaustive switches on `BackgroundPreference`. ✅
- `feed_reduced_motion_test.dart` stays green unchanged (asserts only feed-LOCAL `AnimatedOpacity`/`AnimatedSize`/`FeedSwipeCard` durations; never assumes default==glow; bounded pumps). ✅
- `conversation_screen_test.dart:349-365` asserts `CosmicBackgroundMirrored` renders and IS host-gated; `feed_performance_test.dart` FEED6 (`:417/:424/:427`) is NOT run by any named gate (`integration_test/` isn't globbed by `run_host_test_gates.sh:132-133`). ✅

---

## §A — Test blast-radius: the 6 default-preference tests (BLOCKER 1 · B-2 HIT)

The plan's RED catalog (106-174) and Known-Failure Interpretation (269-273) name only ONE of the existing ambient tests that break when `defaultBackground` renders Mirror Cosmic (#4 = "renders child over the default background treatment"). A `grep cosmic_mirrored` does not surface the others because they key off `default` implicitly. All live in ONE already-listed file (`test/features/identity/presentation/widgets/ambient_background_test.dart`), so running that file surfaces every break — but the plan must pre-declare them and mandate the disposition, or the executor will weaken them (silently deleting 156/158 coverage) instead of repointing them.

- **A1.** In **Known-Failure Interpretation**, add a subsection: *"Existing default-preference tests that go **assertion-RED** (clean `expect(controllers, isNotEmpty)` failure, NOT compile-RED, NOT a throw — the `isNotEmpty` guard fires before `.first`) once `defaultBackground` renders Mirror Cosmic: **TC-04** (`:121-130`), **TC-05** (`:132-141`), **TC-158-01** (`:198-218`), **TC-158-02** (`:220-232`), **TC-158-03** (`:234-246`), and **'Feed surface with default preference stays default'** (`:411-418`). These surface via the `ambientControllers` helper because Mirror Cosmic renders through `CustomPaint`, not an `AnimatedBuilder`."* — so the executor expects them and does not misread them as scope-drift (plan line 273 makes an unexpected failure BLOCKING).
- **A2.** In **Step 8**, add an explicit disposition rule: *"CONVERT each of the six default-preference tests above to `preference: BackgroundPreference.aurora` — the glow moved to `aurora`, so these motion/chat/OS-gate assertions must follow it. Do **NOT** weaken them to `isEmpty`/`findsNothing` (that deletes the 156 OS-reduce-motion + 158 chat-suppression coverage on the live glow)."* Position new test #6 as the **replacement/superset** of the TC-04/TC-05/TC-158-01/02/03 gate coverage, not an additive test.
- **A3.** *(containment note, reassuring)* Add: *"Blast-radius bounded — `grep -rln greenGlow\|redGlow test/ integration_test/` returns only `ambient_background_test.dart`; no other surface test (feed/posts/orbit) asserts the default glow."*

## §B — Gate coverage + render-vs-glow rebase target (BLOCKER 2 · B-4/B-10 HIT)

The plan's blanket "aurora replaces Mirrored-cosmic" (line 219) is wrong for tests that assert **Mirror Cosmic renders** — those must rebase to `defaultBackground`, not `aurora` (which now renders the glow). One such site runs in no gate and can ship semantically inverted.

- **B1.** Add a **Step-8 disambiguation rule**: *"When rebasing a `cosmicMirrored` reference, split by intent — a **render-assert** ('`CosmicBackgroundMirrored` is present') rebases to **`BackgroundPreference.defaultBackground`** (now Mirror Cosmic); a **glow/animation-assert** rebases to **`BackgroundPreference.aurora`**. Blindly swapping all to `aurora` inverts the render-asserts."*
- **B2.** Apply B1 to the two known render-assert sites: `conversation_screen_test.dart:349-365` (`find.byType(CosmicBackgroundMirrored)`) → `defaultBackground`; `feed_performance_test.dart` FEED6 `:417` (`findsNothing`, will invert) + `:427` (render-assert) → `defaultBackground`. *(conversation_screen_test is host-gated so a wrong swap self-reveals; FEED6 is not — see B3.)*
- **B3.** Add to **Acceptance Gates** (after line 258): `flutter test integration_test/feed_performance_test.dart` — *"`integration_test/` is NOT globbed by `feature-host-all`/`core-host-all` (`run_host_test_gates.sh:132-133`) and `flutter analyze` catches only the `:424` compile-break, not the `:417 findsNothing → findsOneWidget` inversion. Without this line the FEED6 rebase can ship wrong."*

## §C — Test-precision corrections (BLOCKER 3 + moderates)

- **C1. (BLOCKER 3 · B-4)** **INV-6 source-guard #10** (RED catalog `:171-174`, "Simplest durable form" `:173`): the bare-substring form false-REDs the whole `feature-host-all` gate on the first GREEN run, because the new l10n key `settings_background_aurora` puts the substring `aurora` into `settings_screen.dart`, `background_choice_control.dart`, and generated `app_localizations*`. **Respecify** the guard to match the **quote-adjacent token literal** only — for each `lib/**.dart` except `background_preference.dart`, assert absence of the exact byte sequences `'aurora'` / `"aurora"` and `'cosmic_mirrored'` / `"cosmic_mirrored"` (quotes adjacent to the word). That matches ONLY the codec and excludes the l10n key names and `ValueKey('background-choice-aurora')`.
- **C2. (moderate · D5)** **Drop test #6 part (d)** (`:145` clause "and (d) `wrapAmbient()` … no `AnimatedBuilder`-bound `AnimationController` is left animating" + the `:149` "distinct-flow discriminator" default-side clause). It is unobservable: `ambientControllers` returns empty for a Mirror-Cosmic default, so the clause is vacuous, and if authored with `.first` it would be the one place that actually throws. The landmine is fully locked by **#6(a)** (aurora glow animates) + its mutation-revert — keep those.
- **C3. (moderate · D4)** **Re-label RED #3**: remove it from the compile-RED list in **Known-Failure Interpretation line 270** — #3's own entry (`:124-127`) uses only `fromStorageString('default'/null/'garbage')` (no `aurora` symbol), so it is a **preserved-green guard**, neither compile-RED nor assertion-RED on HEAD. Keep the compile-RED list to #2/#5/#6/#8/#9.
- **C4. (moderate · D4)** **Fix SC-5b's mutation** (matrix row `:185`): `background_choice_control` takes a `selected`/`value` prop directly and does NOT call `fromStorageString`, so #7 (default-tile-selected-by-default) bypasses the codec and "revert remap" would not re-red it. Either specify the concrete extension — construct the control with `value: BackgroundPreference.fromStorageString('cosmic_mirrored')` and assert `background-choice-default` shows its selected icon (so "revert remap" truly re-reds) — OR **drop SC-5b** as redundant with SC-5 (#1 already locks `'cosmic_mirrored' → defaultBackground`).
- **C5. (moderate · B-10)** **Re-cite SC-11** (matrix `:191`, tests list `:100`, proof profile `:231`): `account_migration_journey_screen_test` uses `backgroundPreference: daylightLagoon` as a **render prop only** (`:124,187`) — it never writes-then-reads the token, so it proves nothing about the Move round-trip. Re-point SC-11 at **`migration_secure_storage_registry_test.dart:63-64`** (asserts `background_preference → policy:migrate`; stays green with no code change because it gates the KEY's policy, not the token VALUE). Keep the new→old downgrade as a prose Accepted Difference (no brick).

## §D — Execution structure: two gated slices (D2 material · locked decision)

Steps 3-8 are one monolithic block (enum retire + default flip + gate repoint + tone + tiles + l10n regen + 9 test rewrites) with the first GREEN at Step 9 — no bisectable waypoint. Because adding `aurora` is purely additive (it compiles with `cosmicMirrored` still present), split the Step-By-Step:

- **D1.** **Slice A (additive, reversible):** add `aurora('aurora')` to the enum; add its arms to all FIVE exhaustive switches (`toStorageString`, render→`_DefaultAmbientBackground(glow)`, `toneForPreference`→dark, `settings_screen` label, `background_choice_control` `selectedLabel`); add the Aurora tile (keys `background-choice-aurora`, `isSelected: value == BackgroundPreference.aurora`, `onChanged(aurora)`); add `fromStorageString('aurora') → aurora`; add the `settings_background_aurora*` l10n keys; add the new `aurora`-only tests. **Leave `cosmicMirrored` fully intact.** → **Checkpoint: `feature-host-all` + `core-host-all` GREEN.**
- **D2.** **Slice B (behavior-flip + retire):** repoint render `defaultBackground => CosmicBackgroundMirrored`; repoint `_usesDefaultBackground` (rename `_usesGlowBackground`) → `== aurora`; `fromStorageString('cosmic_mirrored') → defaultBackground`; retire `cosmicMirrored` (removes it from the enum + all switches); change `settings_background_default_desc`; remove `settings_background_cosmic_mirrored*`; rewrite the 9 existing tests (incl. §A repoints + §B render-target rule). → re-run all gates.
- **D3.** Insert the **payoff-early** checkpoint inside Slice B, immediately after the render + gate repoint: `flutter test .../ambient_background_test.dart --plain-name 'default preference renders Mirror Cosmic'` (#4) and the #6(a) landmine test — confirm GREEN before the tone/settings/l10n mechanical edits.
- **D4.** Run the codec/render/tone/settings **direct-GREEN legs BEFORE `flutter gen-l10n`** (Step 7), so the committed generated-file diff lands on a known-green base and any post-regen failure is isolable to l10n.

## §E — Accuracy / clarity (nits)

- **E1.** Change **"4 exhaustive switches" → "5"** at lines **225** and **286**, listing them: `toStorageString`, render, `toneForPreference`, settings-label (`_backgroundValueLabel`), `selectedLabel`. (No execution impact — all compiler-forced — but the Scope-Guard count should match the body.)
- **E2.** In **Step 6**, append `isSelected: value == BackgroundPreference.aurora` to the Aurora-tile field list (mirrors `background_choice_control.dart:123`), and clarify that the Default tile's `:87` code stays **byte-identical** — the description change is solely the `settings_background_default_desc` **arb value** edit in Step 7 (not a code edit).
- **E3.** *(optional, D1)* Add ONE canonical table near the top consolidating the migration contract — columns: `stored token | resolves to enum | rendered surface | Settings tile highlighted | rewritten on load? (N) | SC/INV lock` — rows: `null`, `'default'`, `'cosmic'`, `'cosmic_mirrored'`, `'daylight_lagoon'`, `'aurora'`, garbage. Cite it from Done Criteria. Include the benign note that migrated users' stored token is **never normalized on read** (persists as `'cosmic_mirrored'`/`'default'`), which is exactly why INV-6 matters.
- **E4.** *(optional, D1)* Tag the two product tradeoffs in **Accepted Differences** (`:291-296`) with the same `(product-confirmable)` marker already on the Aurora label: (a) deliberate-`'default'` pickers are indistinguishable from never-chose and are migrated to Mirror Cosmic (re-pick "Aurora" to restore — reversibility test-locked by #5/#8); (b) new→old Move renders the glow.

---

## Priority order to apply
1. **Correctness gates first** — §C1 (INV-6 #10 false-RED would fail the whole gate on green), §B3 (add the FEED6 run gate — it's the only site that ships wrong silently), §B1/§B2 (render-vs-glow rebase target).
2. **Coverage integrity** — §A1/§A2/§A3 (name the 6 default tests + mandate repoint-to-`aurora`, don't weaken).
3. **Structure** — §D1-§D4 (two gated slices + early payoff + pre-l10n green base).
4. **Test-precision cleanup** — §C2 (drop #6(d)), §C3 (#3 label), §C4 (SC-5b mutation), §C5 (SC-11 re-cite).
5. **Accuracy/nits** — §E1-§E4.
