# 169 - Orbit3 dimension persistence + reset-to-default  (New Feature)

Status: awaiting-review
Spec: free-text intent (no formal spec) — "default dimension for the orbit + arches, let the user change it and persist it"

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| t0 | Evidence Collector | orbit3_screen.dart, feed_wired.dart, secure_key_store.dart, background_preference_use_cases.dart, settings_wired.dart, test/features/orbit3/*, scripts/run_host_test_gates.sh, pubspec | grounded via 3-agent verify→refute workflow (wf_2ad5022a) | build matrix |
| t1 | Planner | references/tier-matrix.md, plan-template.md | host-only closure; mirror SecureKeyStore pref pattern; inject optional nullable store | emit plan |
| t2 | Reviewer (sufficiency) | references/sufficiency-checklist.md | blind-spot sweep run (4/4 addressed) | self-check below |
| t3 | Arbiter | — | structural verdict: implementation-ready | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | | reds now green | |
| | preservation GREEN | | | sentinels green | |
| | named gates | | | gate green | |
| | QA (independent) | | | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: inline below (free-text; user's "report-only" recommendation accepted)
- Gate definitions: scripts/run_host_test_gates.sh (orbit3 tests auto-glob under `feature-host-all` / `host-all`; NOT in any curated `*_TESTS` array in scripts/run_test_gates.sh — grep orbit3 → exit 1)
- Numbering / index: Test-Flight-Improv/00-INDEX.md (next-free = 169)

## Session Classification
implementation-ready

## Exact Problem Statement
The Orbit3 prototype tab exposes four "dimension" knobs via the +/- steppers — avatar size (`_avatarScale`), inter-orbit/arch spacing (`_spacingScale`), arch curve (`_curveScale`), and avatars-per-arch (`_perRow`) — but they are plain in-memory `State` fields on `_Orbit3ScreenState` (orbit3_screen.dart:79/82/84/86). They reset to the hardcoded defaults (1.0 / 1.0 / 1.0 / 7) on every app relaunch and on tab dispose. A user who tunes a combination they like cannot keep it, and there is no one-tap way back to the defaults.

What must improve: (1) keep the current defaults as the baseline; (2) persist each knob so a tuned value survives relaunch; (3) add a "Reset to default" control that restores all four AND clears the saved value.

What must stay unchanged (→ preserved-green sentinels): the entire existing orbit3 behaviour (the 77 `orbit3_screen_test.dart` cases + smoke + layout/wiring suites). The shared geometry constants in `orbit3_one_circle_layout.dart` and every other tab/feature are out of scope. Orbit and arch sizing stay UNIFIED — no new scales, only persistence of the existing four.

## Root Cause (verify → refute confirmed)
Not a bug — a missing capability. The knobs are `State` fields with no storage seam (orbit3_screen.dart:79–86), `initState` (115–132) is fully synchronous with no load step, and the screen has no persistence dependency injected. The app's established simple-preference pattern is **SecureKeyStore** (string K/V; secure_key_store.dart:6–11) + a domain model owning `storageKey`/`toStorageString`/`fromStorageString` (background_preference.dart:9/11/25) + top-level `load*/save*` use-cases (background_preference_use_cases.dart:7–23), wired into a screen exactly as settings_wired.dart does (field:47, load+setState in initState:191, save-on-change:201).

Refuted / do-NOT-re-introduce:
- **`shared_preferences`** — NOT a dependency (grep pubspec.yaml + pubspec.lock → exit 1; the only string hits are docstrings about Android's `EncryptedSharedPreferences`, the flutter_secure_storage backend). Do NOT add it; use SecureKeyStore.
- **"any new Orbit3Screen param is harmless because all params are optional"** — FALSE. The 3 widget mounts use `const Orbit3Screen(...)` (orbit3_screen_test.dart:26, orbit3_prototype_smoke_test.dart:26, orbit3_arch_preview_capture.dart:49). A param is safe ONLY if it stays optional AND null/const-default. A required param, or a non-const default, breaks those `const` sites (and a required one also forces feed_wired.dart:2645).
- **awaiting the load in initState** — impossible; `SecureKeyStore.read` is a `Future`. Must be fire-and-forget + `mounted`-guarded `setState`.

## Real Scope
In scope:
- NEW `lib/features/orbit3/domain/orbit3_dimension_preferences.dart` — immutable model holding the 4 values + `defaults` + `storageKey` + `toStorageString()` + `fromStorageString(String?)` (encode 3 doubles + 1 int into one delimited string; default on null/malformed; **clamp each field to its valid range** on decode).
- NEW `lib/features/orbit3/application/orbit3_dimension_preferences_use_cases.dart` — top-level `loadOrbit3DimensionPreferences({required SecureKeyStore})` + `saveOrbit3DimensionPreferences({required SecureKeyStore, required prefs})` + `clearOrbit3DimensionPreferences({required SecureKeyStore})` (mirrors background_preference_use_cases.dart).
- EDIT `lib/features/orbit3/presentation/screens/orbit3_screen.dart` — add optional nullable `final SecureKeyStore? secureKeyStore;` (null default, const-safe); `_restoreDimensions()` (fire-and-forget load in initState → mounted setState); save (fire-and-forget) appended to each of the 8 inc/dec handlers; `_resetDimensions()` (set 4 fields to defaults + `clear` storage + setState); a Reset pill keyed `orbit3-reset-dimensions` in `_buildSteppers`.
- EDIT `lib/features/feed/presentation/screens/feed_wired.dart:2645` — pass `secureKeyStore: widget.secureKeyStore` (already in scope; field at :157/201).
- NEW tests (below).

Out of scope (owning work): decoupling orbit-vs-arch sizing into separate scales (future session); migrating to a typed multi-pref store; settings-screen surface for these knobs. Not touched: `orbit3_one_circle_layout.dart` constants, other tabs.

## Files To Inspect Next
Production: orbit3_screen.dart (79–86 fields, 115–132 initState, 135–141 dispose, 292–330 stepper mutators, `_buildSteppers`/`_SizeStepper`), feed_wired.dart:2645 (mount) + :157/201 (store field), secure_key_store.dart, background_preference{,_use_cases}.dart (pattern to mirror).
Tests: test/features/orbit3/orbit3_screen_test.dart (`wrap()` :22–27), test/core/secure_storage/fake_secure_key_store.dart (`FakeSecureKeyStore` + `_FailingWriteSecureKeyStore`), test/features/settings/presentation/screens/settings_wired_test.dart (optional-ctor fake pattern :303).
Dependency-only context: image_quality_preference_use_cases.dart (sibling pref), settings_wired.dart (load/save wiring).

## Existing Tests Covering This Area
- `orbit3_screen_test.dart` — covers all current orbit3 UI incl. the 4 steppers' value readouts (`orbit3-*-value`) and inc/dec (`orbit3-*-inc/-dec`); does NOT cover persistence (MISSING) or reset (MISSING).
- `orbit3_prototype_smoke_test.dart`, `orbit3_wiring_test.dart`, `orbit3_one_circle_layout_test.dart`, `orbit3_arch_layout_test.dart`, `orbit3_mock_data_test.dart` — adjacent, must stay green.
- `fake_secure_key_store.dart` — the fixture to reuse (in-memory; same instance across two mounts models a relaunch; empty = fresh install).
Missing coverage gaps: codec round-trip/clamp, use-case load/save/clear, screen load-on-mount, screen save-on-change durability across re-mount, reset restores+clears.
Already in curated family arrays?: NO — orbit3 is auto-glob-only (`feature-host-all`/`host-all`); zero script edits needed.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. `test/features/orbit3/orbit3_dimension_preferences_test.dart`::`toStorageString/fromStorageString round-trips all four knobs`
   - Tier: unit (domain)
   - Shape/setup: build `Orbit3DimensionPreferences(avatarScale: 1.2, spacingScale: 0.8, curveScale: 2.0, perRow: 5)`; `fromStorageString(p.toStorageString())` equals `p`.
   - RED on HEAD: the model file/class does not exist → compile error.
   - GREEN asserts: equality of all four fields after round-trip.
   - Mutation that re-reds: drop `curveScale` from `toStorageString` → round-trip loses curve → RED.

2. same file::`fromStorageString returns defaults for null and malformed input`
   - Tier: unit (domain)
   - Shape/setup: `fromStorageString(null)`, `fromStorageString('')`, `fromStorageString('garbage|x')` each == `Orbit3DimensionPreferences.defaults` (1.0/1.0/1.0/7).
   - RED on HEAD: class absent.
   - GREEN asserts: all three decode to defaults.
   - Mutation: make `fromStorageString` throw instead of defaulting on parse failure → RED.

3. same file::`fromStorageString clamps out-of-range fields to valid bounds`
   - Tier: unit (domain) — invariant re-verification
   - Shape/setup: encode a string with avatar=5.0, spacing=0.1, perRow=99 → decode → avatar==1.4 (max), spacing==0.7 (min), perRow==9 (max).
   - RED on HEAD: class absent.
   - GREEN asserts: each field clamped to its documented range.
   - Mutation: remove the per-field `.clamp(...)` in `fromStorageString` → returns 5.0/0.1/99 → RED.

4. `test/features/orbit3/orbit3_dimension_preferences_use_cases_test.dart`::`save then load over a SecureKeyStore round-trips; empty store loads defaults`
   - Tier: application (host) — fake store
   - Shape/setup: `final store = FakeSecureKeyStore();` `await saveOrbit3DimensionPreferences(secureKeyStore: store, prefs: p);` `await loadOrbit3DimensionPreferences(secureKeyStore: store)` == p. Separately, a fresh empty `FakeSecureKeyStore()` → load == defaults.
   - RED on HEAD: use-case functions absent.
   - GREEN asserts: saved prefs reload; empty → defaults.
   - Mutation: make `saveOrbit3DimensionPreferences` a no-op → load returns defaults not `p` → RED.

5. same file::`clear removes the stored key (load reverts to defaults)`
   - Tier: application (host) — destructive side-effect
   - Shape/setup: save `p`; `await clearOrbit3DimensionPreferences(secureKeyStore: store);` then `store.read(Orbit3DimensionPreferences.storageKey)` is null AND `load` == defaults.
   - RED on HEAD: `clear*` absent.
   - GREEN asserts: key is gone; load defaults.
   - Mutation: make `clear*` call `write(defaults)` instead of `delete` → `store.read(key)` non-null → RED.

6. `test/features/orbit3/orbit3_screen_test.dart`::`mounts with a seeded store → all four steppers show the persisted values (load)`
   - Tier: widget
   - Shape/setup: `TestWidgetsFlutterBinding.ensureInitialized()`; `final store = FakeSecureKeyStore(); await saveOrbit3DimensionPreferences(secureKeyStore: store, prefs: Orbit3DimensionPreferences(avatarScale:1.2, spacingScale:1.2, curveScale:1.5, perRow:5));` pump `Orbit3Screen(userPeerId:'me-peer', secureKeyStore: store)`; `await tester.pump()` (flush the fire-and-forget load); read `orbit3-avatar-size-value` == '1.2×', `orbit3-spacing-value` == '1.2×', `orbit3-curve-value` == '1.5×', `orbit3-perrow-value` == '5'.
   - RED on HEAD: `Orbit3Screen` has no `secureKeyStore` param (compile error) — and no load path.
   - GREEN asserts: stored values applied to all four readouts (sibling-surface consistency: all four).
   - Mutation: remove the `setState` apply in `_restoreDimensions` → readouts show defaults (1.0×/…/7) → RED.

7. same file::`a changed knob persists across a fresh re-mount with the same store (save + durability)`
   - Tier: widget — lifecycle/derived-state durability
   - Shape/setup: empty `store`; pump `Orbit3Screen(secureKeyStore: store)`; tap `orbit3-avatar-size-inc` (→ 1.2×); `await tester.pump()`; pump a SECOND fresh `Orbit3Screen(secureKeyStore: store)` (same instance = relaunch); `await tester.pump()`; `orbit3-avatar-size-value` == '1.2×' (not '1.0×').
   - RED on HEAD: no save-on-change → re-mount shows default.
   - GREEN asserts: persisted value reconstructs on a fresh mount (derived UI rebuilt from storage).
   - Mutation: remove the save call appended to `_incAvatarSize` → re-mount shows '1.0×' → RED.

8. same file::`Reset restores all four defaults AND clears storage`
   - Tier: widget — destructive-action side-effect + invariant re-verification
   - Shape/setup: empty `store`; pump screen; tap several inc buttons (avatar/spacing/curve/perrow off-default); `await tester.pump()`; tap `orbit3-reset-dimensions`; `await tester.pump()`; the four readouts == '1.0×'/'1.0×'/'1.0×'/'7' AND `store.read(Orbit3DimensionPreferences.storageKey)` is null; re-mount with same store → still defaults.
   - RED on HEAD: no `orbit3-reset-dimensions` widget (finder fails).
   - GREEN asserts: defaults restored, key cleared, durable.
   - Mutation: (a) revert the field-reset in `_resetDimensions` → readouts not default → RED; (b) swap `clear` for nothing → `store.read(key)` non-null → RED.

## Test Coverage Matrix  (ZERO empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 codec round-trip | pure serialization | unit (domain) | orbit3_dimension_preferences_test.dart::round-trips all four | model class absent | drop curve from toStorageString | `flutter test test/features/orbit3` | AUTO (glob `test/features/**`) |
| TC-02 default-on-bad-input | pure logic | unit (domain) | …::defaults for null & malformed | class absent | throw instead of default | `flutter test test/features/orbit3` | AUTO (glob) |
| TC-03 clamp-on-decode | invariant | unit (domain) | …::clamps out-of-range | class absent | remove per-field clamp | `flutter test test/features/orbit3` | AUTO (glob) |
| TC-04 save/load round-trip | pref over store | application host | orbit3_dimension_preferences_use_cases_test.dart::save then load; empty→defaults | use-case fns absent | save→no-op | `flutter test test/features/orbit3` | AUTO (glob) |
| TC-05 clear key | destructive side-effect | application host | …::clear removes key | clear absent | clear writes defaults vs delete | `flutter test test/features/orbit3` | AUTO (glob) |
| TC-06 screen load-on-mount | widget load path / sibling-all-4 | widget | orbit3_screen_test.dart::seeded store shows persisted values | no `secureKeyStore` param + no load | drop setState in _restoreDimensions | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |
| TC-07 persist across re-mount | lifecycle durability | widget | orbit3_screen_test.dart::changed knob persists across re-mount | no save-on-change | remove save in _incAvatarSize | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |
| TC-08 reset+clear | destructive + invariant | widget | orbit3_screen_test.dart::Reset restores defaults AND clears storage | no reset widget | revert field-reset / drop clear | `flutter test test/features/orbit3/orbit3_screen_test.dart` | AUTO (glob) |

## Blind-Spot Sweep  (evergreen classes)
- **Lifecycle / derived-state durability**: TC-07 — a changed knob (in-memory derived state) is reconstructed on a FRESH `Orbit3Screen` mount from the store, not merely "saved". (TC-06 proves the load-apply path itself.)
- **Sibling-surface consistency**: TC-06 asserts ALL FOUR knobs load (not just avatar); the save calls are appended to ALL EIGHT inc/dec handlers (plan step 4) — the persistence "gate" applies uniformly to every knob, matched in TC-08's reset of all four.
- **Destructive-action side-effects**: TC-05 + TC-08 assert Reset/clear **removes the stored key** (`store.read(key)` null), not just that the values flip — and verify defaults reload (nothing else clobbered). Reuses the use-case `clear` rather than a divergent inline delete.
- **Invariant re-verification under new transitions**: TC-03 (clamp on the new load transition keeps values in range) + TC-08 (after the new Reset transition, defaults hold AND a subsequent re-mount stays default — the reset's full post-state is asserted, key + four fields).

## Invariants (locked by tests)
- INV-1: a persisted dimension survives relaunch → TC-07.
- INV-2: corrupt/missing/out-of-range storage never yields an out-of-bounds or crashed UI → TC-02/TC-03.
- INV-3: Reset returns to exactly the documented defaults AND erases storage → TC-08/TC-05.
- INV-4: existing orbit3 behaviour with NO store injected is byte-unchanged (null store → no-op load/save) → preservation gate (all current orbit3 tests stay green, mounts pass no store).
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot (dirty-tree baseline — this branch already has uncommitted orbit3 work; do not revert it).
2. Add RED tests 1–8; run the focused gates; confirm each fails for its documented reason (model/use-case/param/reset absent).
3. NEW `orbit3_dimension_preferences.dart`: immutable class (`avatarScale`,`spacingScale`,`curveScale`,`perRow`), `==`/`hashCode`, `static const defaults` (1.0/1.0/1.0/7), `static const storageKey = 'orbit3_dimension_preferences_v1'`, `toStorageString()` = `'$avatarScale|$spacingScale|$curveScale|$perRow'`, `static fromStorageString(String?)` = split on `|`; if not 4 parts or any unparseable → `defaults`; else clamp each (avatar 0.6–1.4, spacing 0.7–1.5, curve 0.5–2.5, perRow 4–9). Bounds live as named consts reused by the screen clamps.
4. NEW `orbit3_dimension_preferences_use_cases.dart`: `load` (read key → `fromStorageString`), `save` (write `toStorageString`), `clear` (`delete` key) — each `{required SecureKeyStore secureKeyStore}`.
5. EDIT `orbit3_screen.dart`: import the store + model + use-cases; add `final SecureKeyStore? secureKeyStore;` (null default in the const ctor); append `_restoreDimensions();` to `initState`; implement it async (`if (secureKeyStore==null) return; final p = await loadOrbit3DimensionPreferences(...); if (!mounted) return; setState(() {_avatarScale=p.avatarScale; _spacingScale=p.spacingScale; _curveScale=p.curveScale; _perRow=p.perRow;});`); add `_persistDimensions()` (fire-and-forget `save` when store non-null) and call it at the END of each of the 8 inc/dec handlers (after their setState); add `_resetDimensions()` (setState the 4 fields to defaults + fire-and-forget `clear`); add a Reset pill (`ValueKey('orbit3-reset-dimensions')`) in `_buildSteppers` wired to `_resetDimensions`. Stop-if: the const test mounts fail to compile → the param default isn't null/const; fix, do not make tests non-const.
6. EDIT `feed_wired.dart:2645`: add `secureKeyStore: widget.secureKeyStore,` to the `Orbit3Screen(...)` call.
7. Rerun direct REDs → GREEN; then preservation (`flutter test test/features/orbit3`) → all prior + new green; `flutter analyze` 0 new. Mutation-verify each lock (revert per the matrix → RED → restore).
8. `graphify update .` + `./graphify-arch/refresh_arch_graph.sh` (AST-only) after green.

## Risks And Edge Cases
- **Float formatting drift** (1.2000000000000002 from step arithmetic): `toStorageString` uses `toString()` (Dart `double.toString()`↔`double.parse` round-trips exactly); the display `toStringAsFixed(1)` is unchanged → pinned by TC-01 + TC-06 (asserts the '1.2×' readout). If accumulation produces ugly values, snap with `double.parse(x.toStringAsFixed(2))` in the codec — covered by TC-01.
- **Async setState after unmount** (tab switch during read): `mounted` guard in `_restoreDimensions` → no test needed beyond the guard; noted.
- **Null store in existing tests**: load/save/clear all early-return when `secureKeyStore == null` → INV-4 preservation.
- **`const` breakage**: pinned implicitly — the 3 const mounts are in the preservation gate; they only compile if the new param stays null/const-default.
- **Save spam** (rapid +/-): fire-and-forget overwrite of one key is idempotent and cheap; no debounce needed for a prototype (note: if added later, cancel the Timer in dispose:135–141).

## PROD-CRITICAL leg
The wire that ACTIVATES persistence in the real app is `feed_wired.dart:2645` passing `secureKeyStore: widget.secureKeyStore` into `Orbit3Screen`. TC-06/07/08 prove the screen+store path end-to-end **when a store is injected**, and TC-04/05 prove the store round-trip — but no host test mounts the full `FeedWired` to prove the injection line itself (FeedWired is a heavy wired screen with many real deps; mounting it for this is disproportionate). This is **accepted** because: (a) the Orbit3 tab is **debug-only** (`kOrbit3PrototypeEnabled == kDebugMode`, locked by orbit3_wiring_test.dart) so the leg is a developer-tool wire, not a shipped path; (b) it is a single named line; (c) dropping it degrades gracefully to the current in-memory behaviour (no crash). Marked PROD-CRITICAL-but-host-accepted; do NOT treat the screen-level tests as proof the prod mount injects the store — verify that line by reading the diff at execution close.

## Device/Relay Proof Profile
host-only for closure. Persistence is faked with `FakeSecureKeyStore` exactly as the existing `BackgroundPreference`/`ImageQualityPreference` prefs (no device-proof exists or is required for those). The real `FlutterSecureKeyStore` round-trip is the plugin's contract, already exercised by the shipped prefs. No simulator/device row. No DB migration (SecureKeyStore, not SQLCipher).

## Acceptance Gates  (literal — copy/paste, expected counts)
```bash
# RED (before production edits) — must FAIL for the documented reason (model/use-case/param/reset absent)
flutter test test/features/orbit3/orbit3_dimension_preferences_test.dart
flutter test test/features/orbit3/orbit3_dimension_preferences_use_cases_test.dart
flutter test test/features/orbit3/orbit3_screen_test.dart --plain-name 'persisted'

# Direct GREEN (after fix)
flutter test test/features/orbit3/orbit3_dimension_preferences_test.dart        # expect: all pass
flutter test test/features/orbit3/orbit3_dimension_preferences_use_cases_test.dart  # expect: all pass

# Preservation + new widget tests (must stay/much go green) — was 77, +3 widget = 80
flutter test test/features/orbit3                                                # expect: 0 failures

# Hygiene
flutter analyze lib/features/orbit3 test/features/orbit3                          # expect: No issues found
git diff --check
```
(No `run_test_gates.sh <family>` row — orbit3 is not in any curated array; `run_host_test_gates.sh feature-host-all` is the umbrella that auto-globs these. No `/sims`, no migration test.)

## Known-Failure Interpretation
- Expected RED: tests 1–8 before the fix (missing model/use-cases/param/reset).
- Pre-existing dirty: this `new-orbit` branch carries uncommitted orbit3 work from prior turns — snapshot with `git status --short` first; do not revert it.
- Environment blocker (NOT product): none (host-only).
- Scope drift (BLOCKING): any failure outside test/features/orbit3 + the single feed_wired.dart line.

## Done Criteria
- [ ] RED added first, failed for the expected reason.
- [ ] Mutation-verified (each fix has a re-red revert per the matrix).
- [ ] Direct GREEN + preservation (`flutter test test/features/orbit3`) pass.
- [ ] No migration (N/A — SecureKeyStore).
- [ ] No OS-boundary/device path (N/A — host-only, matches existing pref pattern).
- [ ] Every new test auto-globbed under feature-host-all (verified: names end `_test.dart`, live in test/features/orbit3/).
- [ ] flutter analyze 0 new; git diff --check clean; no Scope Guard violations.

## Scope Guard (hard "Do not")
- Do not add `shared_preferences` (absent; use SecureKeyStore).
- Do not touch `orbit3_one_circle_layout.dart` constants or any non-orbit3 feature (except the one `feed_wired.dart:2645` injection line).
- Do not make any Orbit3Screen constructor param required, or give it a non-const default (breaks the 3 const mounts).
- Do not decouple orbit vs arch sizing (future session).

## Accepted Differences / Intentionally Out Of Scope
- Decoupled orbit-vs-arch scales — could-do, not here; a follow-up if the unified scale proves limiting.
- A settings-screen surface for these knobs — the steppers + reset on the tab are sufficient for the prototype.
- Debounced/coalesced saves — single-key overwrite is cheap; revisit only if profiling shows churn.

## Dependency Impact
- None depends on this; it is additive to a prototype tab. The new `Orbit3DimensionPreferences` model/use-cases are self-contained under `lib/features/orbit3/`.

## Reviewer Findings
Sufficiency self-check (below) passes all gates: every TC has a tier + named test + RED reason + re-red mutation + literal gate + AUTO registration; blind-spot sweep 4/4 addressed with rows; no migration/device obligations (host-only matches the shipped-pref precedent); preservation sentinel named with command.

## Arbiter Decision
Structural blockers: none. Deferred details: exact Reset pill styling/placement (execution-time visual choice; key is fixed). Accepted differences: as listed. Hand off to execution.

## Final Execution Verdict
Verdict: **ACCEPTED** (executed 2026-06-25, same session).
Files changed:
- NEW `lib/features/orbit3/domain/orbit3_dimension_preferences.dart` (model + codec, clamp-on-decode)
- NEW `lib/features/orbit3/application/orbit3_dimension_preferences_use_cases.dart` (load/save/clear)
- EDIT `lib/features/orbit3/presentation/screens/orbit3_screen.dart` (optional null-default `secureKeyStore`; `_restoreDimensions`/`_persistDimensions`/`_resetDimensions`; `_persistDimensions()` in all 8 inc/dec handlers; `_Orbit3ResetPill` keyed `orbit3-reset-dimensions` above the grid)
- EDIT `lib/features/feed/presentation/screens/feed_wired.dart:2652` (inject `secureKeyStore: widget.secureKeyStore`)
- NEW `test/features/orbit3/orbit3_dimension_preferences_test.dart` (TC-01/02/03)
- NEW `test/features/orbit3/orbit3_dimension_preferences_use_cases_test.dart` (TC-04/05)
- EDIT `test/features/orbit3/orbit3_screen_test.dart` (TC-06/07/08 + imports + `wrapWithStore` helper)

Tests run (+counts): `flutter test test/features/orbit3` → **85/85 pass** (was 77 + 8 new). RED-first confirmed (compile errors for absent model/use-cases/param/reset). **All 8 TCs mutation-verified RED** (codec drop-curve, parse-guard return-non-default, avatar-clamp removal, save no-op, clear write-vs-delete, load-apply disabled, save-on-change removed, reset clear removed) and reverted. `flutter analyze lib/features/orbit3 lib/features/feed/.../feed_wired.dart test/features/orbit3` → No issues. `git diff --check` clean.

Blocking: none. QA verdict: pass (host-only closure per the shipped-pref precedent). Non-blocking follow-ups (owner: future session): decoupled orbit-vs-arch scales; the feed_wired injection line is host-verified only by reading the diff (PROD-CRITICAL-but-accepted, debug-only tab).
