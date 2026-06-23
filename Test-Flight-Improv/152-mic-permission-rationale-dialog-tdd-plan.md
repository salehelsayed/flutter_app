# 152 - Microphone-permission rationale dialog + Open Settings (replace the dead-end mic toast)  (Feature Improvement)

Status: awaiting-review
Spec: free-text intent (no formal spec) — chained from a UI/UX review of Group Messaging snackbars

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-23 | Evidence Collector | group_conversation_wired.dart (:3485-3524), conversation_wired.dart (:2800-2839, :641-666), record_audio_recorder_service.dart, audio_recorder_service.dart, fake_audio_recorder_service.dart, compose_post_sheet.dart (:230-254, :818-863), posts_wired.dart (:559), nearby_location_service.dart (:356-359), app_en/ar/de.arb, run_test_gates.sh (:62-63,:116-132,:529,:613), record_platform_interface-1.5.0, ios/Runner/Info.plist:56, AndroidManifest.xml:5 | verify→refute complete: byte-identical denied blocks in BOTH chat screens NOT shared; `record` pkg `hasPermission()` is bool-only (no tri-state) → a reliable permanentlyDenied→openAppSettings deep-link REQUIRES a new plugin (`permission_handler`). Native mic decls already present. ZERO existing denied-branch test. | Planner |
| 2026-06-23 | Planner | (as above) | Extract `lib/core/permissions/mic_permission_prompt.dart`, call from both screens; add `permission_handler` (Option A) for tri-state + `openAppSettings()`; tri-state the fake first (prerequisite); spy-seam openAppSettings | Reviewer |
| 2026-06-23 | Plan-Refresh (re-grounded vs HEAD) | conversation_wired.dart (:2784/:2795/:2807-2823), group_conversation_wired.dart (:3516/:3532/:3542-3558), run_test_gates.sh:531, app_en/ar/de.arb, conversation_wired_test.dart (:895/:936/:6282/:6369/:6607), group_conversation_wired_test.dart (:981/:1024/:6008/:6043), fake_audio_recorder_service.dart:15/:42, compose_post_sheet.dart:241/:249/:861, posts_wired.dart:559, nearby_location_service.dart:357 | **All findings RE-CONFIRMED valid; only line numbers were stale** — concurrent 149/155 work shifted 1:1 denied branch UP ~16 lines and group denied branch DOWN ~+34. Corrected all refs below. NEW: (a) group `_onRecordStart` has pre-permission guards (`_canWrite`/`_refreshSendCapabilityAndCanWrite`/`_isSending`, :3517-3519) → group RED tests MUST use a writable group else `onRecordStart` is null (proven `group..test:6008/:6043`); (b) no "Not now" l10n key exists (`btn_cancel`/`pinned_dismiss`/`pending_invite_dismiss` are the only dismiss candidates) → `mic_perm_not_now` IS needed (or reuse `btn_cancel`). | Reviewer |
| | Reviewer (sufficiency) | | | |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-23 | contract extraction | `git status --short` (tree already dirty on `new-feed`) | line numbers re-confirmed on HEAD: 1:1 `_onRecordStart`:2784/req:2795/snackbar:2807-2823; group `_onRecordStart`:3516/pre-guards:3517-3519/req:3532/snackbar:3542-3558; `audioRecorderService` fields conv:210/group:138 | scope confirmed; `permission_handler` absent; `permissionGranted=false` 0 hits (denial uncovered) | RED |
| 2026-06-23 | RED tests added | NEW `mic_permission_prompt_test.dart` (TC-01/02/03); +TC-04/06/08 conv_wired_test; +TC-05/07 group_wired_test; NEW `fake_mic_permission_gateway.dart` | conv `--plain-name 'mic permission denied prompt (152)'` → **+1 -2** (TC-08 green sentinel; TC-04/06 RED: AlertDialog absent, snackbar shown); group → **+0 -2** (TC-05/07 RED, AlertDialog absent) | RED for documented reason (HEAD snackbar). Group setup gotcha FIXED: `_supportsDurableGroupMediaUploads` needs `mediaRepo`+`mediaFileManager` else onRecordStart==null | implementation |
| 2026-06-23 | implementation | NEW `lib/core/permissions/mic_permission_gateway.dart`+`mic_permission_prompt.dart`; conv_wired+group_wired `_onRecordStart` (gateway.request() gate, dialog on permanentlyDenied); +field+const default both screens; pubspec `permission_handler ^11.3.1`; Podfile `PERMISSION_MICROPHONE=1`; l10n en/ar/de ×3 keys; gate regex `:533` +`permissions` | `flutter pub get` clean (6 deps, no conflict; resolved 11.x); `flutter gen-l10n` ok; module analyze 0 | scoped files + 6 collateral test-builder edits (see Accepted Differences) | direct GREEN |
| 2026-06-23 | direct GREEN | (as above) | conv mic group **+3 All pass**; group mic group **+2 All pass**; helper test **+3 All pass** | reds now green | preservation |
| 2026-06-23 | preservation GREEN | 4 collateral builders (bg_task ×2, send_then_lock, group_resume) | helper + 4 collateral suites together → **+134 All tests passed!**; mutations TC-02 (drop openAppSettings)→re-red, TC-03 (Not-now calls it)→re-red, TC-08 (invert granted gate)→re-red; TC-04/05/06/07 mutation = the pre-impl RED run | sentinels green; all mutation-verified | named gates |
| 2026-06-23 | named gates (pre-review) | — | `completeness-check` **944/944 PASS**; `1to1` **+1193** (1190+3); `groups` **+160/-2** (the -2 = PRE-EXISTING `GMAR-004 reopen-hydration` + `incoming-group-image-refresh`, NOT mic); `core-host-all` only fail = PRE-EXISTING time-bomb `intro_db_helpers` (`pending`→`expired`); `flutter analyze` **0-new**; `git diff --check` clean | gates green | adversarial review |
| 2026-06-23 | adversarial review (4-lens workflow) | tests only | 2 confirmed findings, both MINOR (prod correct, test-quality): (F1) TC-04/05 idle assertion read the never-populated `screen.isRecording` widget field → tautological; (F2) plain `denied` silent-reset (core of Option A) untested — guard mutation survives. **INCIDENT: a review verify-agent ran `git checkout`/`git stash` on the 2 screen files, reverting them to HEAD — wiped my 152 + concurrent-session uncommitted deltas.** | recover + fix findings | recovery |
| 2026-06-23 | recovery + review-fixes | conv restored from stash blob `6ceaece` (session-start incl. 149 reject-chip work) + re-applied 152; group kept at HEAD (its ~19-line session-start delta was never stashed → unrecoverable, verified not test-load-bearing via gate parity) + re-applied 152 | Fix-1: switched idle assertions to LIVE rendered composer icon (`mic_rounded` present / `stop_rounded` absent) — the `recordingState` prop is only refreshed on parent rebuild, the live state lives in `_composerState` via `composerStateListenable`. Fix-2: added 1:1 + group `denied → no dialog` tests. | re-verify | QA |
| 2026-06-23 | QA (post-recovery) | — | conv mic group **+4 All pass** (TC-04/06/08 + denied); group mic group **+3 All pass** (TC-05/07 + denied); helper **+3**; analyze 0-new. MUTATIONS re-verified on live assertions: F1 reset idle→arming → TC-04 re-reds (stuck `stop_rounded`); F2 guard `==permanentlyDenied`→`!=granted` → denied test re-reds (dialog over-shows → hang/timeout). `1to1`/`groups` gates re-running post-recovery | blocking: none (pending final gate parity) | final verdict |

## Source Of Truth
- Spec / intent: inline below (UX review → user-locked design decisions)
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (no sim rows; one DEFERRED device-proof named)
- Numbering / index: filename sequence under `Test-Flight-Improv/` (this plan = 152). NOTE (verified 2026-06-23): `00-INDEX.md` only narrates the older session-breakdown reports (24–76); the recent NN-*-tdd-plan family (149/150/151/152/155) is NOT registered there, so no index entry is added — consistent with siblings.

## Session Classification
implementation-ready (host-only closure; **no migration**; ONE device-proof — the real `openAppSettings` round-trip — is a DEFERRED closure, host spy is the floor)

## Exact Problem Statement
When a user taps the voice-record mic but has **denied** the microphone permission, the app shows a transient red `SnackBar` — `perm_microphone_record` ("Microphone permission is required to record voice messages.") — and resets the composer to idle. This is a **dead end**: the message is informational only, gives the user no way to actually grant the permission (they must leave the app, find iOS/Android Settings, locate the app, find the Microphone toggle), and on iOS a permanently-denied permission can ONLY be re-granted from system Settings — there is no in-app re-prompt that will ever succeed. A user who taps "deny" once is effectively locked out of voice messages with no recoverable path.

The denied-handler is **duplicated byte-for-byte** in two screens and **not shared** (line numbers RE-VERIFIED on HEAD 2026-06-23 after concurrent 149/155 drift):
- GROUP: `group_conversation_wired.dart:3516` `_onRecordStart` (pre-guards `_canWrite`/`_refreshSendCapabilityAndCanWrite`/`_isSending` at `:3517-3519`); `:3532` `hasPermission = await recorder.requestPermission()`; `:3542 if (!hasPermission)` → `:3544-3550` `ScaffoldMessenger.showSnackBar(SnackBar(content: Text(perm_microphone_record), backgroundColor: Colors.red[700], behavior: floating))`; `:3551-3555` reset to idle; `return` `:3557`.
- 1:1: `conversation_wired.dart:2784` `_onRecordStart`; `:2795` same `requestPermission()`; `:2807 if (!hasPermission)` → `:2809-2815` the **identical** snackbar; `:2816-2820` reset to idle; `return` `:2822`.

Because the two blocks are independent copies, any fix applied to one silently leaves the other a dead-end toast — the duplication is itself a defect surface.

What must improve:
- On mic denial, replace the snackbar with an **`AlertDialog`** (rationale body explaining why mic access is needed) offering **"Not now"** (dismiss, reset to idle — same as today) and **"Open Settings"** which deep-links to the app's system settings via `openAppSettings()`.
- The denied-handler must live in **ONE shared helper** (`lib/core/permissions/mic_permission_prompt.dart`) called from BOTH chat screens, so neither screen can drift back to a dead-end toast.

What must stay unchanged (→ preserved-green sentinels):
- The **granted** path: `requestPermission()==true` proceeds to `recorder.start(...)` exactly as today (1:1 `conversation_wired.dart:2835+` (`recorder.start` `:2837`), group `:3570+` (`recorder.start` `:3571`)).
- The **abort** path (`!mounted || _pendingRecorderAbort`) resets to idle without any prompt.
- The composer **reset-to-idle** on dismissal (the user is never left in `arming`/`recording`).
- The 5-min auto-stop review surface (117), voice send/stop/cancel, LetterCard render, all unrelated group/1:1 suites, `flutter analyze` 0-new.

## Root Cause (verify → refute confirmed)
**Confirmed on HEAD (tree dirty on `new-feed` but these lines are committed prior work, not session WIP):**
- The denied branch in both screens calls only `ScaffoldMessenger.showSnackBar(...)` + idle-reset; there is no settings deep-link and no shared helper. `group_conversation_wired.dart:3542-3558` and `conversation_wired.dart:2807-2823` are the two independent copies (re-verified on HEAD 2026-06-23; the blocks are still byte-identical aside from the group's pre-permission guards above the `requestPermission()` call).
- The app cannot today distinguish *denied* from *permanentlyDenied*: it depends on the `record` package (`pubspec.yaml:55 record: ^5.1.0`); `RecordAudioRecorderService.hasPermission()`/`requestPermission()` both forward to `record`'s `AudioRecorder.hasPermission()` (`record_audio_recorder_service.dart:55-58`), which returns a **plain `bool`** — confirmed in the vendored interface `record_platform_interface-1.5.0/lib/src/record_platform_interface.dart:74 Future<bool> hasPermission(...)`. There is **no** `permission_handler` dependency (`grep permission_handler pubspec.yaml` = 0).
- The only existing `openAppSettings` precedent is **`Geolocator.openAppSettings()`** (`nearby_location_service.dart:357-358`; interface decls `:67`/`:85`/`:157`), which is location-domain and not reusable for a mic deep-link; and the only "Open Settings" UX precedent is the posts nearby `TextButton.icon(Icons.settings_outlined, label: compose_open_settings)` → `posts_wired.dart:559 nearbyLocationService.openAppSettings()` (`compose_post_sheet.dart:861-862`).

Refuted / do-NOT-re-introduce:
- ❌ "native mic permission decls are missing / unknown" — **FALSE / present**: `ios/Runner/Info.plist:56 <key>NSMicrophoneUsageDescription</key>` AND `AndroidManifest.xml:5 <uses-permission android:name="android.permission.RECORD_AUDIO"/>` already exist. Do not re-flag as an open question; only the `openAppSettings` round-trip needs device proof (deferred).
- ❌ "we can detect permanentlyDenied from the `record` package" — **FALSE**: `record`'s `hasPermission()` is bool-only at the platform-interface layer; no status enum. A tri-state requires a new plugin (see RESOLVED DECISION — Option A locked).
- ❌ "the denied logic is already shared" — **FALSE**: two byte-identical copies, independently maintained.
- ❌ "there's an existing denied-branch test we can extend" — **FALSE**: `grep perm_microphone_record` / `permissionGranted = false` across both wired tests = **0 hits**. The denied branch is entirely uncovered today.
- ❌ "this needs a DB migration" — **FALSE**: pure presentation/permission flow; no schema, no persisted state. `migration = false` (DB stays at v92; next-free 093 untouched).

## RESOLVED DECISION (LOCKED 2026-06-23 by owner: **Option A**)
A reliable "Open Settings" deep-link requires a plugin **either way**, because `record` exposes no `openAppSettings()` and no permanentlyDenied state. The owner has **locked Option A** — implement the tri-state path. Option B is recorded below only as the rejected alternative; do not implement it.

- **✅ Option A (CHOSEN): add `permission_handler` (`^11.x`).** Gives `Permission.microphone.request()` → `PermissionStatus` (granted / denied / permanentlyDenied / restricted) AND a domain-correct `openAppSettings()`. The shared helper shows the dialog only when the user can no longer be re-prompted in-app (`permanentlyDenied`/`restricted` on iOS; permanentlyDenied on Android); on a first `denied` the OS prompt has already been shown by `request()`, so the dialog is not forced there. Cost: one new third-party dep + iOS/Android native plumbing (Podfile `PERMISSION_MICROPHONE=1` macro, no new manifest entries — decls already present per Root Cause). Blast radius is contained to a new `lib/core/permissions/` module behind an injected interface.
- **❌ Option B (REJECTED): no tri-state — show the rationale dialog on ANY denial.** The dialog's "Open Settings" STILL needs a deep-link plugin (record has none), so a plugin is required regardless; Option B just over-shows the dialog (a user who could have been re-prompted is sent to Settings unnecessarily). Net: same dependency cost, worse UX. Not implemented.

→ The full plan body (tri-state cases incl. TC-04, the `MicPermissionStatus` enum, the `gateway.request()` routing) is the Option-A path and stands as written.

The plugin's status call AND `openAppSettings()` are wrapped behind a thin injected interface `MicPermissionGateway` (prod impl wraps `permission_handler`; tests inject a spy) — mirroring the `NearbyLocationService.openAppSettings()` seam so host tests never hit the real plugin (plugins throw `MissingPluginException` under `flutter_test`).

## Real Scope
In scope:
- NEW `lib/core/permissions/mic_permission_prompt.dart`: a function `showMicPermissionDeniedPrompt(BuildContext, {required MicPermissionGateway gateway})` (or a small class) that renders the `AlertDialog` (title + rationale body + "Not now" `TextButton` `pop(false)` + "Open Settings" `FilledButton`/`TextButton.icon` `pop(true)` → on true calls `gateway.openAppSettings()`), mirroring the `_confirmLeaveWhileUploadActive` dialog shape (`conversation_wired.dart:641-666`) with **new button keys** (`mic-perm-not-now`, `mic-perm-open-settings`).
- NEW `lib/core/permissions/mic_permission_gateway.dart`: `abstract class MicPermissionGateway { Future<MicPermissionStatus> request(); Future<bool> openAppSettings(); }` + enum `MicPermissionStatus { granted, denied, permanentlyDenied }`; prod impl `PermissionHandlerMicGateway` wrapping `permission_handler`.
- `pubspec.yaml`: add `permission_handler: ^11.x` (Option A). iOS Podfile macro `PERMISSION_MICROPHONE=1`.
- GROUP denied branch `group_conversation_wired.dart:3542-3558`: replace the snackbar with a call to the shared helper (inject the gateway via the screen's widget so tests can spy); keep the idle-reset on dismissal. **Preserve the pre-permission guards at `:3517-3519`** (`_canWrite`/`_refreshSendCapabilityAndCanWrite`/`_isSending`) — these gate whether `_onRecordStart` runs at all and have no 1:1 equivalent.
- 1:1 denied branch `conversation_wired.dart:2807-2823`: identical replacement via the SAME shared helper.
- Tri-state the recorder/permission call: route the denied decision through `gateway.request()` (Option A) so the helper sees the status; granted → proceed to `start()` unchanged.
- l10n: NEW `mic_perm_dialog_title` + `mic_perm_dialog_body` × en/ar/de (append-by-key); REUSE `compose_open_settings` (`:146` all three locales) for the Settings button; **`mic_perm_not_now` IS needed** — verified on HEAD: no "Not now" key exists (only dismiss candidates are `btn_cancel`/`conversation_cancel_edit`/`account_migration_cancel` = "Cancel" and `pinned_dismiss`/`pending_invite_dismiss` = "Dismiss"). Either add `mic_perm_not_now` ("Not now") or, if the reviewer prefers reuse, `btn_cancel` ("Cancel") — but the locked copy is "Not now", so the plan adds the new key.
- `test/shared/fakes/fake_audio_recorder_service.dart`: **prerequisite** — extend from the single `bool permissionGranted` to a tri-state seam (`MicPermissionStatus permissionStatus` or a `FakeMicPermissionGateway`) so a `permanentlyDenied → dialog` RED can exist (today only granted/!granted exists). NEW `test/shared/fakes/fake_mic_permission_gateway.dart` spy (records `openAppSettings` calls, returns a scriptable status).
- Harness: NEW `test/core/permissions/mic_permission_prompt_test.dart` needs a **classify_path registration** — `permissions` is NOT in the `test/core/(bridge|constants|database|device|inbox|local_discovery|media|secure_storage|theme|utils)` regex (`run_test_gates.sh:531`) and the core-root fallback (`:615`, regex `^test/core/[^/]+_test\.dart$`) only matches files directly under `test/core/` (not a `permissions/` subdir). Add `permissions` to the `:531` regex.

Out of scope (owning work named):
- The THIRD record site `compose_post_sheet.dart:241/:249` resets **silently** (no UI today) — adding the dialog there is OPTIONAL parity; it widens blast radius into the posts composer (zero current coverage). Owner: a future "posts composer mic parity" pass. Flagged, not done here.
- Camera / photo-library permission prompts (different permission, different decls) — not touched.
- Any change to voice capture, the 117 auto-stop review, send/stop/cancel, relay/custody, or LetterCard render.

## Files To Inspect Next
Production (line numbers re-verified on HEAD 2026-06-23):
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` — `_onRecordStart` `:3516` (pre-guards `:3517-3519`); `requestPermission` `:3532`; denied branch `:3542-3558`; idle-reset `:3551-3555`; screen ctor (to inject the gateway) — find the `audioRecorderService` widget field for the parallel injection seam.
- `lib/features/conversation/presentation/screens/conversation_wired.dart` — `_onRecordStart` `:2784`; `requestPermission` `:2795`; denied branch `:2807-2823`; idle-reset `:2816-2820`; dialog-shape model `_confirmLeaveWhileUploadActive` `:641-666` (keys `upload-leave-stay` `:652`/`upload-leave-confirm` `:657` — pick NEW keys, do not reuse).
- NEW `lib/core/permissions/mic_permission_prompt.dart`, `lib/core/permissions/mic_permission_gateway.dart`.
- `lib/core/media/audio_recorder_service.dart` (`:8-9` `hasPermission`/`requestPermission`) + `record_audio_recorder_service.dart:55-58` (bool-only forward — do NOT add a status method here; the gateway owns status).
- `lib/features/posts/presentation/widgets/compose_post_sheet.dart:861-862` (Open Settings UX) + `lib/features/posts/presentation/screens/posts_wired.dart:559` + `lib/features/posts/application/nearby_location_service.dart:357-358` (openAppSettings seam precedent).
- `lib/l10n/app_en.arb` / `app_ar.arb` / `app_de.arb` — append-by-key (`compose_open_settings` is at `:146` in all three; `perm_microphone_record` en `:881` / ar `:874` / de `:874`).
- `pubspec.yaml:55` (record), iOS Podfile.
Direct tests (line numbers re-verified on HEAD 2026-06-23):
- `test/features/groups/presentation/group_conversation_wired_test.dart` — recorder fake injected via `audioRecorderService` (`:981 builder param`, `:1024 wiring`; existing voice cases construct `FakeAudioRecorderService` at `:2059`/`:2932`/`:5753`/`:5853`/`:5903`, drive `.onRecordStart!` at `:2109`/`:2955`/`:5806`/`:5919`). **The group `_onRecordStart` exposes `onRecordStart` only for a WRITABLE group — read-only groups make it `null` (`:6008`/`:6043`); the new denied RED tests MUST build a writable group or the permission path is never reached.** NO denied test today.
- `test/features/conversation/presentation/screens/conversation_wired_test.dart` — `audioRecorderService` builder param `:895`/`:936`; existing voice cases inject the recorder at `:6270`/`:6362`/`:6600`/`:6736` and drive `screen.onRecordStart! as Future<void> Function()` (`:6282`, `:6369`, `:6607`). NO denied test today.
- NEW `test/core/permissions/mic_permission_prompt_test.dart` — pure widget pump of the helper (no full screen).
Fakes / context:
- `test/shared/fakes/fake_audio_recorder_service.dart` (`:15 permissionGranted` — extend to tri-state / or leave granted-only and add the gateway fake).
- NEW `test/shared/fakes/fake_mic_permission_gateway.dart`.

## Existing Tests Covering This Area
- Denied branch (both screens): **NO test** — `grep perm_microphone_record|permissionGranted = false` in both wired tests = 0. Entirely uncovered.
- Granted voice path: covered (e.g. conv wired `:6282`/`:6369`/`:6607` drive `onRecordStart`→`onRecordStop` happy path; group wired `:5753`/`:5853`/`:5903` voice cases). Sentinel — must stay green.
- `FakeAudioRecorderService.permissionGranted` (`:15`, default `true`) — only a bool; `requestPermission()` (`:42`) returns it. No tri-state, no permanentlyDenied → a `permanentlyDenied→dialog` RED cannot be written until the fake/gateway is extended (prerequisite step).
- Posts Open-Settings seam: `posts_wired_nearby_compose_test.dart` / `nearby_location_service_test.dart` exercise the `openAppSettings` injection — the precedent template for the mic spy seam (not edited).
Missing coverage gaps: denied→dialog (both screens); "Open Settings" tap → `openAppSettings()` invoked; "Not now" → idle-reset + NO settings call; shared-helper source-wiring (both screens call the one helper); tri-state (granted proceeds / denied vs permanentlyDenied) under Option A; NO snackbar from the denied path.
Already in curated family arrays?: `conversation_wired_test.dart` ✅ `ONE_TO_ONE_TESTS:63`. `group_conversation_wired_test.dart` ✅ `GROUP_TESTS:133`. `fake_audio_recorder_service.dart` is not a `_test.dart` (auto-included where imported). **NEW `test/core/permissions/mic_permission_prompt_test.dart` ❌ not classified** → registration step (add `permissions` to `run_test_gates.sh:531` regex).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

0. **PREREQUISITE (not a behavior test): tri-state the fake / add the gateway fake.** Extend `FakeAudioRecorderService` or add `FakeMicPermissionGateway` (`test/shared/fakes/fake_mic_permission_gateway.dart`) exposing `MicPermissionStatus statusToReturn` + `int openAppSettingsCallCount` + `bool openAppSettingsReturn`. This is a harness change with no production behavior; its correctness is proven by the RED tests below compiling and running. (Without it, TC-04 cannot exist.)

1. `mic_permission_prompt_test.dart`::"permanentlyDenied shows the rationale dialog with an Open Settings action"
   - Tier: widget (pump the helper inside a minimal `MaterialApp` with localizations + a `Builder` to get a real `BuildContext`)
   - Shape/setup: `gateway = FakeMicPermissionGateway()..statusToReturn = permanentlyDenied`; call `showMicPermissionDeniedPrompt(context, gateway: gateway)`; `pump`.
   - RED on HEAD because: `lib/core/permissions/mic_permission_prompt.dart` does not exist → compile-time red (import missing).
   - GREEN after fix asserts: an `AlertDialog` is present; `find.text(l10n.mic_perm_dialog_title)` / `mic_perm_dialog_body` visible; `find.byKey(ValueKey('mic-perm-open-settings'))` findsOne; `find.byKey(ValueKey('mic-perm-not-now'))` findsOne; **no** `SnackBar`.
   - Mutation that re-reds: replace the dialog body with the old `ScaffoldMessenger.showSnackBar(perm_microphone_record)` → no AlertDialog → red.

2. `mic_permission_prompt_test.dart`::"tapping Open Settings invokes gateway.openAppSettings exactly once and dismisses"
   - Tier: widget
   - RED on HEAD because: helper absent → compile red; AND no production path calls `openAppSettings()` today (`grep openAppSettings lib/core/permissions` = nothing; only the geolocator one exists).
   - GREEN after fix asserts: tap `mic-perm-open-settings` → `gateway.openAppSettingsCallCount == 1`; dialog dismissed (`find.byType(AlertDialog) findsNothing`).
   - Mutation that re-reds: make the Open-Settings button only `pop()` without calling `gateway.openAppSettings()` → callCount 0 → red.
   - Discriminator: assert `gateway.openAppSettingsCallCount == 1` AND `find.byKey(ValueKey('mic-perm-not-now'))` was NOT the tapped key (guards against wiring the call to the wrong button).

3. `mic_permission_prompt_test.dart`::"tapping Not now dismisses without opening settings"
   - Tier: widget
   - RED on HEAD because: helper absent → compile red.
   - GREEN asserts: tap `mic-perm-not-now` → dialog dismissed; `gateway.openAppSettingsCallCount == 0`.
   - Mutation that re-reds: wire "Not now" to also call `openAppSettings()` → callCount 1 → red.

4. `conversation_wired_test.dart`::"1:1 mic denial shows the rationale dialog instead of the snackbar (permanentlyDenied)"
   - Tier: integration/widget (full `ConversationScreen` via the test builder, gateway spy injected; drive `screen.onRecordStart!`)
   - Shape/setup: inject `FakeMicPermissionGateway()..statusToReturn = permanentlyDenied`; `await (screen.onRecordStart! as Future<void> Function())()`; pump.
   - RED on HEAD because: HEAD shows `SnackBar(perm_microphone_record)` (`conversation_wired.dart:2807-2823`, no gateway/dialog) → asserting an `AlertDialog` + `mic-perm-open-settings` key present FAILS; asserting `find.text(perm_microphone_record)` absent FAILS (it's shown).
   - GREEN asserts: `AlertDialog` present with `mic-perm-open-settings` key; **no** `find.text(l10n.perm_microphone_record)` snackbar; composer state reset to idle after dismiss.
   - Mutation that re-reds: restore the `:2807-2823` snackbar block (don't call the helper) → no dialog → red.

5. `group_conversation_wired_test.dart`::"group mic denial shows the rationale dialog instead of the snackbar (permanentlyDenied)"
   - Tier: integration/widget (full `GroupConversationScreen`; drive the group `_onRecordStart` via the screen's record-start callback; gateway spy injected)
   - **Setup gotcha: build a WRITABLE group** — the group `_onRecordStart` (`:3516`) is gated by `_canWrite`/`_refreshSendCapabilityAndCanWrite`/`_isSending` (`:3517-3519`) and `screen.onRecordStart` is `null` for a read-only group (`group..test:6008`/`:6043`). A read-only fixture never reaches `requestPermission()`, so the RED would be a false-negative. Mirror the writable-group setup used by the existing voice cases (`:5753`/`:5853`).
   - RED on HEAD because: HEAD `:3542-3558` shows the snackbar; same asserts as TC-4 fail.
   - GREEN asserts: `AlertDialog` + `mic-perm-open-settings`; no `perm_microphone_record` snackbar; reset to idle.
   - Mutation that re-reds: restore the `:3542-3558` snackbar block → red.

6. `conversation_wired_test.dart`::"1:1 Open Settings tap deep-links via the injected gateway"  *(source-wiring + behavior lock)*
   - Tier: integration/widget
   - RED on HEAD because: no gateway is wired into the 1:1 denied path today → the injected spy is never called; asserting `gateway.openAppSettingsCallCount == 1` after tapping the dialog's Settings button fails (dialog doesn't even render on HEAD).
   - GREEN asserts: after `onRecordStart` (permanentlyDenied) → tap `mic-perm-open-settings` → `gateway.openAppSettingsCallCount == 1`.
   - Mutation that re-reds: have the screen pass its OWN inline dialog (not the shared helper) OR drop the gateway injection → spy uncalled → red. (Locks "both screens route through the one shared helper + injected gateway".)

7. `group_conversation_wired_test.dart`::"group Open Settings tap deep-links via the injected gateway"  *(source-wiring + behavior lock)*
   - Tier: integration/widget (same writable-group setup as TC-05 — read-only groups expose `onRecordStart == null`)
   - RED on HEAD because: as TC-6, group side.
   - GREEN asserts: `gateway.openAppSettingsCallCount == 1` after the Settings tap.
   - Mutation that re-reds: drop the group gateway injection / inline a screen-local dialog → red.

8. `conversation_wired_test.dart`::"granted mic permission still starts recording (preservation)"  *(sentinel)*
   - Tier: integration/widget
   - Shape/setup: `FakeMicPermissionGateway()..statusToReturn = granted` (and/or `recorder.permissionGranted = true`); `onRecordStart`; pump.
   - Asserts: no dialog, no snackbar; recorder transitions to recording (existing `find.byIcon(Icons.stop_rounded)` / `recorder.startCallCount == 1` style). Guards the happy path against the denied-branch refactor.
   - Mutation that re-reds: make the helper fire on `granted` too → unexpected dialog blocks `start()` → red.

## Test Coverage Matrix  (zero empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 dialog renders | helper render | widget | mic_permission_prompt_test::"permanentlyDenied shows the rationale dialog …" | helper file absent → compile red | swap dialog back to snackbar | `./scripts/run_test_gates.sh 1to1` (+ add `permissions` to :531 regex) | **add `permissions` to classify regex `run_test_gates.sh:531`** |
| TC-02 Open Settings deep-links | helper behavior | widget | mic_permission_prompt_test::"tapping Open Settings invokes gateway.openAppSettings …" | helper absent; no openAppSettings call exists | button only pop()s, no gateway call | `flutter test test/core/permissions/mic_permission_prompt_test.dart` | classify via :531 regex add |
| TC-03 Not now dismisses | helper behavior | widget | mic_permission_prompt_test::"tapping Not now dismisses without opening settings" | helper absent → compile red | wire Not-now to call openAppSettings | `flutter test test/core/permissions/mic_permission_prompt_test.dart` | classify via :531 regex add |
| TC-04 1:1 denial → dialog | screen wiring (1:1) | integration/widget | conversation_wired_test::"1:1 mic denial shows the rationale dialog …" | HEAD shows perm_microphone_record snackbar (`:2807-2823`) | restore `:2807-2823` snackbar block | `./scripts/run_test_gates.sh 1to1` | AUTO — `ONE_TO_ONE_TESTS:63` |
| TC-05 group denial → dialog (writable group) | screen wiring (group) | integration/widget | group_conversation_wired_test::"group mic denial shows the rationale dialog …" | HEAD shows `:3542-3558` snackbar | restore `:3542-3558` snackbar block | `./scripts/run_test_gates.sh groups` | AUTO — `GROUP_TESTS:133` |
| TC-06 1:1 Settings deep-link | source-wiring lock (1:1) | integration/widget | conversation_wired_test::"1:1 Open Settings tap deep-links via the injected gateway" | no gateway wired in 1:1 → spy uncalled | inline a screen-local dialog / drop injection | `./scripts/run_test_gates.sh 1to1` | AUTO — `ONE_TO_ONE_TESTS:63` |
| TC-07 group Settings deep-link (writable group) | source-wiring lock (group) | integration/widget | group_conversation_wired_test::"group Open Settings tap deep-links via the injected gateway" | no gateway wired in group → spy uncalled | inline a screen-local dialog / drop injection | `./scripts/run_test_gates.sh groups` | AUTO — `GROUP_TESTS:133` |
| TC-08 granted still records | preservation | integration/widget | conversation_wired_test::"granted mic permission still starts recording" | n/a (sentinel) | fire helper on granted too → blocks start() | `./scripts/run_test_gates.sh 1to1` | AUTO — `ONE_TO_ONE_TESTS:63` |

## Invariants (locked by tests)
- INV-1: on mic denial, the chat screen shows an `AlertDialog` (rationale + Open Settings + Not now) and **never** the `perm_microphone_record` snackbar → TC-01/04/05.
- INV-2: tapping "Open Settings" calls `gateway.openAppSettings()` exactly once and dismisses; "Not now" dismisses with zero settings calls → TC-02/03/06/07.
- INV-3: BOTH chat screens route the denied branch through the ONE shared helper + injected gateway (no screen-local inline dialog) → TC-06/07 (drop-injection mutation re-reds).
- INV-4: a granted permission still starts recording unchanged (no dialog) → TC-08.
- INV-5: the denied path resets the composer to idle on dismiss (never stuck in arming/recording) → TC-04/05.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. Snapshot `git status --short`. Add RED tests (catalog 1-8) + the prerequisite fake/gateway (catalog 0). Run focused cmds; confirm each fails for its documented reason (helper-absent compile red for TC-01/02/03; snackbar-shown for TC-04/05; spy-uncalled for TC-06/07).
2. **Option A is LOCKED** (decided 2026-06-23). Add `permission_handler: ^11.x` to `pubspec.yaml`; `flutter pub get`; add the iOS Podfile `PERMISSION_MICROPHONE=1` macro. Stop-if: `pub get` resolution conflict with `record`/other deps → escalate (do not pin blindly).
3. NEW `lib/core/permissions/mic_permission_gateway.dart`: `enum MicPermissionStatus { granted, denied, permanentlyDenied }` + `abstract class MicPermissionGateway { Future<MicPermissionStatus> request(); Future<bool> openAppSettings(); }` + prod `PermissionHandlerMicGateway` wrapping `Permission.microphone.request()` (map `PermissionStatus`) and `openAppSettings()`.
4. NEW `lib/core/permissions/mic_permission_prompt.dart`: `Future<void> showMicPermissionDeniedPrompt(BuildContext, {required MicPermissionGateway gateway})` — `showDialog` modeled on `_confirmLeaveWhileUploadActive` (`conversation_wired.dart:641-666`): `AlertDialog(title: Text(l10n.mic_perm_dialog_title), content: Text(l10n.mic_perm_dialog_body), actions: [ TextButton(key: ValueKey('mic-perm-not-now'), …pop()), TextButton.icon(key: ValueKey('mic-perm-open-settings'), Icons.settings_outlined, label: l10n.compose_open_settings, onPressed: () { Navigator.pop(); gateway.openAppSettings(); }) ])`. NEW button keys — do NOT reuse `upload-leave-*`.
5. `conversation_wired.dart:2795-2823`: route through the gateway (Option A: `final status = await gateway.request()`; `granted` → continue to `start()`; `permanentlyDenied`/`denied`-final → `await showMicPermissionDeniedPrompt(context, gateway: gateway)` then reset idle). Replace the `:2807-2823` snackbar block; keep the abort guard (`:2796-2805`) and the `stopping`/abort guard (`:2825-2833`) intact. Inject the gateway via the `ConversationScreen`/wired widget field (parallel to `audioRecorderService`) so tests pass a `FakeMicPermissionGateway`; prod default = `PermissionHandlerMicGateway()`.
6. `group_conversation_wired.dart:3532-3558`: identical replacement via the SAME helper + injected gateway. **Preserve the `:3517-3519` pre-permission guards** (`_canWrite`/`_refreshSendCapabilityAndCanWrite`/`_isSending`) and the abort guard (`:3533-3540`) — only the `:3542-3558` snackbar block changes. Stop-if: the two screens cannot share one helper without duplicating the dialog → that means the helper is mis-scoped; fix the helper, do not copy the dialog.
7. `test/shared/fakes/fake_audio_recorder_service.dart` (prerequisite, from step 1): keep `permissionGranted` for the granted path; the denied decision now comes from the injected `FakeMicPermissionGateway`. NEW `test/shared/fakes/fake_mic_permission_gateway.dart`.
8. l10n: append-by-key `mic_perm_dialog_title`, `mic_perm_dialog_body` to en/ar/de (plain-string, no @-metadata). REUSE `compose_open_settings` (`:146` all locales) for the Settings button. For "Not now": **verified on HEAD — no "Not now" key exists** (only "Cancel"/"Dismiss" keys: `btn_cancel:337`, `pinned_dismiss:173`, `pending_invite_dismiss:801`); add `mic_perm_not_now` ("Not now") unless the reviewer chooses to reuse `btn_cancel`. Regenerate l10n (`flutter gen-l10n` via `flutter pub get`/build). Proposed en copy — title: "Microphone access needed"; body: "To record voice messages, allow microphone access in Settings."; not-now: "Not now".
9. `scripts/run_test_gates.sh:531`: add `permissions` to the alternation → `^test/core/(bridge|constants|database|device|inbox|local_discovery|media|permissions|secure_storage|theme|utils)/.*_test\.dart$` so `test/core/permissions/mic_permission_prompt_test.dart` classifies (completeness gate + core-host-all sweep). Confirm with `run_completeness_check`.
10. Rerun direct → preservation → named gates; `flutter analyze`; `git diff --check`.

## Risks And Edge Cases
- **Plugin resolution / native plumbing** (`permission_handler`): host tests never touch it (gateway injected), but a host run could still trip if the prod default gateway is constructed in `flutter_test`. Mitigation: tests ALWAYS inject `FakeMicPermissionGateway`; the prod `PermissionHandlerMicGateway` is only the production default. Pinned by TC-04/05 (which inject the fake).
- **Plugins throw `MissingPluginException` under `flutter_test`** → the spy seam (`MicPermissionGateway`) is mandatory; mirrors `NearbyLocationService.openAppSettings()`. Pinned by TC-02/06/07 asserting the spy, never the real plugin.
- **Dialog uses `showDialog` (root overlay)** → after dismiss, the composer must reset to idle; if the screen `await`s the dialog before resetting, a backgrounded screen (`!mounted`) must guard the `setState`. Pinned by TC-05 (reset asserted) + existing `!mounted` guards.
- **Tri-state mapping** (Option A): first-`denied` vs `permanentlyDenied` — over-showing the dialog on first denied is acceptable (it still offers re-request via Settings); under-showing (never showing on permanentlyDenied) is the real failure. TC-01 fixes on `permanentlyDenied`.
- **Third record site** (`compose_post_sheet.dart:241/:249`) remains silent — explicitly OUT of scope; do not let the refactor accidentally import the helper there.
- **`find.text` on dialog body** — plain `Text`, no WidgetSpan, so `find.text` is safe here (unlike LetterCard bubbles).

## Device/Relay Proof Profile
host-only for closure of the dialog + wiring + Not-now + shared-helper behavior (all local screen-state + render, no migration, no OS-boundary in the asserted path — the gateway is faked).

**Deferred device-proof (ONE genuine host↔device gap): the real `openAppSettings()` round-trip.** `permission_handler.openAppSettings()` actually leaves the app to system Settings — un-fakeable on host. Defer to a manual device pass (iPhone + Android): deny mic → tap record → dialog → "Open Settings" → confirm the OS Settings page opens to the app, grant, return, record succeeds. NOT a `/sims` scenario (no relay/ML-KEM/multi-device leg); record as a closure checkbox, not a host blocker. No feature flag to flip.
Relay defaults: n/a (no transport leg).

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before production edits) — must FAIL for the documented reason
flutter test test/core/permissions/mic_permission_prompt_test.dart \
  --plain-name 'permanentlyDenied shows the rationale dialog'      # compile red: helper absent
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name '1:1 mic denial shows the rationale dialog'          # red: HEAD shows snackbar
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'group mic denial shows the rationale dialog'        # red: HEAD shows snackbar

# Direct GREEN (after fix)
flutter test test/core/permissions/mic_permission_prompt_test.dart                          # 3 new pass
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart    # prior count + TC-04/06/08
flutter test test/features/groups/presentation/group_conversation_wired_test.dart            # prior count + TC-05/07

# Preservation + named gates (after adding `permissions` to the :531 regex)
./scripts/run_test_gates.sh 1to1       # ONE_TO_ONE_TESTS green + the new 1:1 cases
./scripts/run_test_gates.sh groups     # GROUP_TESTS green + new group cases; the 2 PRE-EXISTING wired fails (GMAR-004 reopen-hydration, incoming-group-image-refresh) are NOT mine
./scripts/run_test_gates.sh core-host-all   # mic_permission_prompt_test now classified + swept

# Completeness (the new core/permissions test must classify, not go unmatched)
./scripts/run_test_gates.sh completeness    # 0 unmatched (regex add at :531 covers it)

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED: catalog 1-7 before the fix (helper-absent compile red; snackbar-shown; spy-uncalled). TC-08 is a sentinel, green throughout.
- Pre-existing dirty (NOT mine): the Groups suite has **2 pre-existing failing wired tests** — `GMAR-004 reopen-hydration` and `incoming-group-image-refresh` (media reopen/hydration, unrelated to mic). Record before execution; do not "fix" by reverting. The whole tree is already dirty on `new-feed` (uncommitted Feed/Orbit work) — snapshot `git status --short` first; touch only Real-Scope files.
- Environment blocker (NOT product): the real `openAppSettings` round-trip cannot run on host → deferred device-proof, not a host failure.
- Scope drift (BLOCKING): any failure outside the listed files/tests; any change to `compose_post_sheet.dart`, voice capture, or LetterCard.

## Done Criteria
- [ ] RED added first (catalog 1-7), failed for the expected reason; TC-08 sentinel green.
- [ ] Each fix mutation-verified (re-red revert named per matrix row).
- [ ] Direct GREEN + 1to1/groups preservation gates pass; the 2 pre-existing group wired fails unchanged.
- [ ] **No migration** introduced; DB stays v92; next-free 093 untouched.
- [x] OPEN DECISION resolved — **Option A LOCKED 2026-06-23 by owner** (`permission_handler` tri-state path); Option B rejected. Remaining: `permission_handler` actually added + `flutter pub get` clean.
- [ ] Denied branch shared in ONE helper called from BOTH screens (INV-3 source-wiring lock green).
- [ ] `test/core/permissions/mic_permission_prompt_test.dart` classifies — `permissions` added to `run_test_gates.sh:531`; completeness = 0 unmatched.
- [ ] New l10n keys (`mic_perm_dialog_title`, `mic_perm_dialog_body`, `mic_perm_not_now` if needed) present in en/ar/de; `compose_open_settings` reused; l10n regenerated; `flutter analyze` 0-new; `git diff --check` clean.
- [ ] Deferred device-proof (`openAppSettings` round-trip) recorded as a follow-up closure checkbox (not a host blocker).

## Scope Guard (hard "Do not")
- Do not add a DB migration or bump `currentIdentityDatabaseVersion` (no schema change).
- Do not add the dialog to the THIRD record site `compose_post_sheet.dart:241/:249` (out-of-scope posts parity, widens blast radius).
- Do not reuse the `upload-leave-stay`/`upload-leave-confirm` button keys (pick new `mic-perm-*` keys).
- Do not duplicate the dialog across the two screens — one shared helper only (INV-3).
- Do not hit the real `permission_handler` plugin from host tests — always inject `FakeMicPermissionGateway`.
- Do not alter voice capture, the 117 auto-stop review, send/stop/cancel, or LetterCard render.

## Accepted Differences / Intentionally Out Of Scope
- **Posts composer mic parity** (`compose_post_sheet.dart` silent reset) — could-do, not-here; owner = future posts mic-parity pass; widens coverage surface with zero current tests.
- **Real settings deep-link verification** — host-faked via the gateway spy; the un-fakeable OS round-trip is a deferred manual device-proof, accepted because it has no relay/ML-KEM/multi-device leg to warrant a `/sims` scenario.
- **Option B path** (no tri-state) — **rejected** (owner locked Option A 2026-06-23); kept on record only as the alternative that was weighed. Not implemented.

## Dependency Impact
- None outbound. NEW `lib/core/permissions/` module + `MicPermissionGateway` seam are reusable for any future permission prompt (camera/photos) — a standalone hardening win. Adding `permission_handler` is a new shared dependency available to the whole app (Option A).

## Reviewer Findings
<to be filled by the sufficiency reviewer>

## Arbiter Decision
Structural blockers: … | Deferred details: real openAppSettings device round-trip | Accepted differences: posts-composer parity out; **Option A LOCKED (owner, 2026-06-23) — `permission_handler` tri-state, Option B rejected** | hand off to execution

## Final Execution Verdict
Verdict: **ACCEPTED (152 complete + host-green)** | Files changed: NEW `lib/core/permissions/mic_permission_gateway.dart`+`mic_permission_prompt.dart`, `conversation_wired.dart`+`group_conversation_wired.dart` (`_onRecordStart` gateway gate + field), `pubspec.yaml` (`permission_handler ^11.3.1`), `ios/Podfile` (PERMISSION_MICROPHONE), `run_test_gates.sh:533`, l10n en/ar/de (+generated), NEW `fake_mic_permission_gateway.dart`, NEW `mic_permission_prompt_test.dart`, conv+group `_wired_test` (mic group: TC-01..08 + `denied`), 4 collateral builders | Tests run: helper **+3**; 1:1 mic **+4**; group mic **+3**; `conversation_wired_test` **+100 all-pass**; `1to1` gate **+1194 all-pass** (the one transient -1 was flaky, gone on re-run); `completeness-check` **944/944**; `flutter analyze` **0-new**; mutations TC-02/03/08 + review-fix F1(reset)/F2(denied-guard) all re-red | Blocking: **none for 152** | QA verdict: 152 mic-permission feature fully green; the **only** non-green items are NOT 152: (a) 2 genuinely-pre-existing group fails `GMAR-004 reopen-hydration` + `incoming-group-image-refresh`; (b) ~3 concurrent-session-150 `orbit_wired_test` invite-accept fails (appeared mid-session, +733→+869 count jump = concurrent churn); (c) **2 review-incident collateral fails** `group total-size overflow (149 attachment-total-overflow strip-note)` + `retained self-removal NO removed snackbar (151)` — a review verify-agent `git checkout`-reverted both screen files, wiping 149/151's FINAL uncommitted refinements (added after the last stash, never committed → unrecoverable from git; conv fully recovered from stash blob `6ceaece`, group recovered from `4ac7729` = 7/9). | Non-blocking follow-ups (owner): **OWNER DECISION 2026-06-23 — LEAVE the 2 collateral 149/151 group reds for now** (`group total-size overflow` / `retained self-removal NO removed snackbar`); restore from IDE local-history/Time Machine (authoritative @3532 version) when the 149/151 owners pick it up — NOT 152's scope; posts mic parity; real `openAppSettings` device round-trip; iOS Podfile macro device build. See [[feedback_review_subagents_must_not_mutate_worktree]].
