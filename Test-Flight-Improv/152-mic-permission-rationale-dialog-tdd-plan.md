# 152 - Microphone-permission rationale dialog + Open Settings (replace the dead-end mic toast)  (Feature Improvement)

Status: awaiting-review
Spec: free-text intent (no formal spec) — chained from a UI/UX review of Group Messaging snackbars

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-23 | Evidence Collector | group_conversation_wired.dart (:3485-3524), conversation_wired.dart (:2800-2839, :641-666), record_audio_recorder_service.dart, audio_recorder_service.dart, fake_audio_recorder_service.dart, compose_post_sheet.dart (:230-254, :818-863), posts_wired.dart (:559), nearby_location_service.dart (:356-359), app_en/ar/de.arb, run_test_gates.sh (:62-63,:116-132,:529,:613), record_platform_interface-1.5.0, ios/Runner/Info.plist:56, AndroidManifest.xml:5 | verify→refute complete: byte-identical denied blocks in BOTH chat screens NOT shared; `record` pkg `hasPermission()` is bool-only (no tri-state) → a reliable permanentlyDenied→openAppSettings deep-link REQUIRES a new plugin (`permission_handler`). Native mic decls already present. ZERO existing denied-branch test. | Planner |
| 2026-06-23 | Planner | (as above) | Extract `lib/core/permissions/mic_permission_prompt.dart`, call from both screens; add `permission_handler` (Option A) for tri-state + `openAppSettings()`; tri-state the fake first (prerequisite); spy-seam openAppSettings | Reviewer |
| | Reviewer (sufficiency) | | | |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + counts) | gate green | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: inline below (UX review → user-locked design decisions)
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (no sim rows; one DEFERRED device-proof named)
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (this plan = 152)

## Session Classification
implementation-ready (host-only closure; **no migration**; ONE device-proof — the real `openAppSettings` round-trip — is a DEFERRED closure, host spy is the floor)

## Exact Problem Statement
When a user taps the voice-record mic but has **denied** the microphone permission, the app shows a transient red `SnackBar` — `perm_microphone_record` ("Microphone permission is required to record voice messages.") — and resets the composer to idle. This is a **dead end**: the message is informational only, gives the user no way to actually grant the permission (they must leave the app, find iOS/Android Settings, locate the app, find the Microphone toggle), and on iOS a permanently-denied permission can ONLY be re-granted from system Settings — there is no in-app re-prompt that will ever succeed. A user who taps "deny" once is effectively locked out of voice messages with no recoverable path.

The denied-handler is **duplicated byte-for-byte** in two screens and **not shared**:
- GROUP: `group_conversation_wired.dart:3498` `hasPermission = await recorder.requestPermission()`; `:3508 if (!hasPermission)` → `:3510-3516` `ScaffoldMessenger.showSnackBar(SnackBar(content: Text(perm_microphone_record), backgroundColor: Colors.red[700], behavior: floating))`; `:3517-3521` reset to idle.
- 1:1: `conversation_wired.dart:2800` `_onRecordStart`; `:2811` same `requestPermission()`; `:2823 if (!hasPermission)` → `:2825-2830` the **identical** snackbar; `:2832-2836` reset to idle.

Because the two blocks are independent copies, any fix applied to one silently leaves the other a dead-end toast — the duplication is itself a defect surface.

What must improve:
- On mic denial, replace the snackbar with an **`AlertDialog`** (rationale body explaining why mic access is needed) offering **"Not now"** (dismiss, reset to idle — same as today) and **"Open Settings"** which deep-links to the app's system settings via `openAppSettings()`.
- The denied-handler must live in **ONE shared helper** (`lib/core/permissions/mic_permission_prompt.dart`) called from BOTH chat screens, so neither screen can drift back to a dead-end toast.

What must stay unchanged (→ preserved-green sentinels):
- The **granted** path: `requestPermission()==true` proceeds to `recorder.start(...)` exactly as today (1:1 `conversation_wired.dart:2840+`, group `:3526+`).
- The **abort** path (`!mounted || _pendingRecorderAbort`) resets to idle without any prompt.
- The composer **reset-to-idle** on dismissal (the user is never left in `arming`/`recording`).
- The 5-min auto-stop review surface (117), voice send/stop/cancel, LetterCard render, all unrelated group/1:1 suites, `flutter analyze` 0-new.

## Root Cause (verify → refute confirmed)
**Confirmed on HEAD (tree dirty on `new-feed` but these lines are committed prior work, not session WIP):**
- The denied branch in both screens calls only `ScaffoldMessenger.showSnackBar(...)` + idle-reset; there is no settings deep-link and no shared helper. `group_conversation_wired.dart:3508-3523` and `conversation_wired.dart:2823-2838` are the two independent copies.
- The app cannot today distinguish *denied* from *permanentlyDenied*: it depends on the `record` package (`pubspec.yaml:55 record: ^5.1.0`); `RecordAudioRecorderService.hasPermission()`/`requestPermission()` both forward to `record`'s `AudioRecorder.hasPermission()` (`record_audio_recorder_service.dart:55-58`), which returns a **plain `bool`** — confirmed in the vendored interface `record_platform_interface-1.5.0/lib/src/record_platform_interface.dart:74 Future<bool> hasPermission(...)`. There is **no** `permission_handler` dependency (`grep permission_handler pubspec.yaml` = 0).
- The only existing `openAppSettings` precedent is **`Geolocator.openAppSettings()`** (`nearby_location_service.dart:358`), which is location-domain and not reusable for a mic deep-link; and the only "Open Settings" UX precedent is the posts nearby `TextButton.icon(Icons.settings_outlined, label: compose_open_settings)` → `posts_wired.dart:559 nearbyLocationService.openAppSettings()` (`compose_post_sheet.dart:847-863`).

Refuted / do-NOT-re-introduce:
- ❌ "native mic permission decls are missing / unknown" — **FALSE / present**: `ios/Runner/Info.plist:56 <key>NSMicrophoneUsageDescription</key>` AND `AndroidManifest.xml:5 <uses-permission android:name="android.permission.RECORD_AUDIO"/>` already exist. Do not re-flag as an open question; only the `openAppSettings` round-trip needs device proof (deferred).
- ❌ "we can detect permanentlyDenied from the `record` package" — **FALSE**: `record`'s `hasPermission()` is bool-only at the platform-interface layer; no status enum. A tri-state requires a new plugin (see OPEN DECISION).
- ❌ "the denied logic is already shared" — **FALSE**: two byte-identical copies, independently maintained.
- ❌ "there's an existing denied-branch test we can extend" — **FALSE**: `grep perm_microphone_record` / `permissionGranted = false` across both wired tests = **0 hits**. The denied branch is entirely uncovered today.
- ❌ "this needs a DB migration" — **FALSE**: pure presentation/permission flow; no schema, no persisted state. `migration = false` (DB stays at v92; next-free 093 untouched).

## OPEN DECISION (present to reviewer — pick before implementation)
A reliable "Open Settings" deep-link requires a plugin **either way**, because `record` exposes no `openAppSettings()` and no permanentlyDenied state. Two options:

- **Option A (recommended): add `permission_handler` (`^11.x`).** Gives `Permission.microphone.request()` → `PermissionStatus` (granted / denied / permanentlyDenied / restricted) AND a domain-correct `openAppSettings()`. The shared helper shows the dialog only when the user can no longer be re-prompted in-app (`permanentlyDenied`/`restricted` on iOS; permanentlyDenied on Android), and on first `denied` it can re-request silently. Cost: one new third-party dep + iOS/Android native plumbing (Podfile `PERMISSION_MICROPHONE=1` macro, no new manifest entries — decls already present per Root Cause). Blast radius is contained to a new `lib/core/permissions/` module behind an injected interface.
- **Option B: no tri-state — show the rationale dialog on ANY denial.** The dialog's "Open Settings" STILL needs a deep-link plugin (record has none), so a plugin is required regardless; Option B just over-shows the dialog (a user who could have been re-prompted is sent to Settings unnecessarily). Net: same dependency cost, worse UX.

→ **Plan body assumes Option A.** If the reviewer picks B, drop the tri-state cases (TC-04 collapses into TC-02/03) and keep the rest; the helper still injects a settings-opener seam.

The plugin's status call AND `openAppSettings()` are wrapped behind a thin injected interface `MicPermissionGateway` (prod impl wraps `permission_handler`; tests inject a spy) — mirroring the `NearbyLocationService.openAppSettings()` seam so host tests never hit the real plugin (plugins throw `MissingPluginException` under `flutter_test`).

## Real Scope
In scope:
- NEW `lib/core/permissions/mic_permission_prompt.dart`: a function `showMicPermissionDeniedPrompt(BuildContext, {required MicPermissionGateway gateway})` (or a small class) that renders the `AlertDialog` (title + rationale body + "Not now" `TextButton` `pop(false)` + "Open Settings" `FilledButton`/`TextButton.icon` `pop(true)` → on true calls `gateway.openAppSettings()`), mirroring the `_confirmLeaveWhileUploadActive` dialog shape (`conversation_wired.dart:641-666`) with **new button keys** (`mic-perm-not-now`, `mic-perm-open-settings`).
- NEW `lib/core/permissions/mic_permission_gateway.dart`: `abstract class MicPermissionGateway { Future<MicPermissionStatus> request(); Future<bool> openAppSettings(); }` + enum `MicPermissionStatus { granted, denied, permanentlyDenied }`; prod impl `PermissionHandlerMicGateway` wrapping `permission_handler`.
- `pubspec.yaml`: add `permission_handler: ^11.x` (Option A). iOS Podfile macro `PERMISSION_MICROPHONE=1`.
- GROUP denied branch `group_conversation_wired.dart:3508-3523`: replace the snackbar with a call to the shared helper (inject the gateway via the screen's widget so tests can spy); keep the idle-reset on dismissal.
- 1:1 denied branch `conversation_wired.dart:2823-2838`: identical replacement via the SAME shared helper.
- Tri-state the recorder/permission call: route the denied decision through `gateway.request()` (Option A) so the helper sees the status; granted → proceed to `start()` unchanged.
- l10n: NEW `mic_perm_dialog_title` + `mic_perm_dialog_body` × en/ar/de (append-by-key); REUSE `compose_open_settings` for the Settings button; NEW `mic_perm_not_now` (or reuse an existing dismiss key if one matches — verify; brief says "may need a key").
- `test/shared/fakes/fake_audio_recorder_service.dart`: **prerequisite** — extend from the single `bool permissionGranted` to a tri-state seam (`MicPermissionStatus permissionStatus` or a `FakeMicPermissionGateway`) so a `permanentlyDenied → dialog` RED can exist (today only granted/!granted exists). NEW `test/shared/fakes/fake_mic_permission_gateway.dart` spy (records `openAppSettings` calls, returns a scriptable status).
- Harness: NEW `test/core/permissions/mic_permission_prompt_test.dart` needs a **classify_path registration** — `permissions` is NOT in the `test/core/(bridge|constants|database|device|inbox|local_discovery|media|secure_storage|theme|utils)` regex (`run_test_gates.sh:529`) and the core-root fallback (`:613`) only matches files directly under `test/core/` (not a `permissions/` subdir). Add `permissions` to the `:529` regex.

Out of scope (owning work named):
- The THIRD record site `compose_post_sheet.dart:241/:249` resets **silently** (no UI today) — adding the dialog there is OPTIONAL parity; it widens blast radius into the posts composer (zero current coverage). Owner: a future "posts composer mic parity" pass. Flagged, not done here.
- Camera / photo-library permission prompts (different permission, different decls) — not touched.
- Any change to voice capture, the 117 auto-stop review, send/stop/cancel, relay/custody, or LetterCard render.

## Files To Inspect Next
Production:
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` — denied branch `:3508-3523`; `requestPermission` `:3498`; idle-reset `:3517-3521`; screen ctor (to inject the gateway) — find the `audioRecorderService` widget field for the parallel injection seam.
- `lib/features/conversation/presentation/screens/conversation_wired.dart` — denied branch `:2823-2838`; `requestPermission` `:2811`; dialog-shape model `_confirmLeaveWhileUploadActive` `:641-666` (keys `upload-leave-stay`/`upload-leave-confirm` — pick NEW keys, do not reuse).
- NEW `lib/core/permissions/mic_permission_prompt.dart`, `lib/core/permissions/mic_permission_gateway.dart`.
- `lib/core/media/audio_recorder_service.dart` (`:8-9` `hasPermission`/`requestPermission`) + `record_audio_recorder_service.dart:55-58` (bool-only forward — do NOT add a status method here; the gateway owns status).
- `lib/features/posts/presentation/widgets/compose_post_sheet.dart:847-863` (Open Settings UX) + `lib/features/posts/presentation/screens/posts_wired.dart:559` + `lib/features/posts/application/nearby_location_service.dart:356-359` (openAppSettings seam precedent).
- `lib/l10n/app_en.arb` / `app_ar.arb` / `app_de.arb` — append-by-key (`compose_open_settings` is at `:146` in all three; `perm_microphone_record` en `:869` / ar `:862` / de `:862`).
- `pubspec.yaml:55` (record), iOS Podfile.
Direct tests:
- `test/features/groups/presentation/group_conversation_wired_test.dart` — recorder fake injected via `audioRecorderService` (`:981 builder param`, `:1024 wiring`; `:1813`/`:2686`/`:5216`/`:5316` construct `FakeAudioRecorderService`). Drive `_onRecordStart` (group equivalent of `screen.onRecordStart!`). NO denied test today.
- `test/features/conversation/presentation/screens/conversation_wired_test.dart` — `audioRecorderService` builder param `:894`/`:935`; tests drive `screen.onRecordStart! as Future<void> Function()` (`:5950`, `:6037`). NO denied test today.
- NEW `test/core/permissions/mic_permission_prompt_test.dart` — pure widget pump of the helper (no full screen).
Fakes / context:
- `test/shared/fakes/fake_audio_recorder_service.dart` (`:15 permissionGranted` — extend to tri-state / or leave granted-only and add the gateway fake).
- NEW `test/shared/fakes/fake_mic_permission_gateway.dart`.

## Existing Tests Covering This Area
- Denied branch (both screens): **NO test** — `grep perm_microphone_record|permissionGranted = false` in both wired tests = 0. Entirely uncovered.
- Granted voice path: covered (e.g. conv wired `:5950` drives `onRecordStart`→`onRecordStop` happy path; group wired `:5216`/`:5316` voice cases). Sentinel — must stay green.
- `FakeAudioRecorderService.permissionGranted` (`:15`, default `true`) — only a bool; `requestPermission()` (`:42`) returns it. No tri-state, no permanentlyDenied → a `permanentlyDenied→dialog` RED cannot be written until the fake/gateway is extended (prerequisite step).
- Posts Open-Settings seam: `posts_wired_nearby_compose_test.dart` / `nearby_location_service_test.dart` exercise the `openAppSettings` injection — the precedent template for the mic spy seam (not edited).
Missing coverage gaps: denied→dialog (both screens); "Open Settings" tap → `openAppSettings()` invoked; "Not now" → idle-reset + NO settings call; shared-helper source-wiring (both screens call the one helper); tri-state (granted proceeds / denied vs permanentlyDenied) under Option A; NO snackbar from the denied path.
Already in curated family arrays?: `conversation_wired_test.dart` ✅ `ONE_TO_ONE_TESTS:63`. `group_conversation_wired_test.dart` ✅ `GROUP_TESTS:131`. `fake_audio_recorder_service.dart` is not a `_test.dart` (auto-included where imported). **NEW `test/core/permissions/mic_permission_prompt_test.dart` ❌ not classified** → registration step (add `permissions` to `run_test_gates.sh:529` regex).

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
   - RED on HEAD because: HEAD shows `SnackBar(perm_microphone_record)` (no gateway/dialog) → asserting an `AlertDialog` + `mic-perm-open-settings` key present FAILS; asserting `find.text(perm_microphone_record)` absent FAILS (it's shown).
   - GREEN asserts: `AlertDialog` present with `mic-perm-open-settings` key; **no** `find.text(l10n.perm_microphone_record)` snackbar; composer state reset to idle after dismiss.
   - Mutation that re-reds: restore the `:2823-2838` snackbar block (don't call the helper) → no dialog → red.

5. `group_conversation_wired_test.dart`::"group mic denial shows the rationale dialog instead of the snackbar (permanentlyDenied)"
   - Tier: integration/widget (full `GroupConversationScreen`; drive the group `_onRecordStart` via the screen's record-start callback; gateway spy injected)
   - RED on HEAD because: HEAD `:3508-3523` shows the snackbar; same asserts as TC-4 fail.
   - GREEN asserts: `AlertDialog` + `mic-perm-open-settings`; no `perm_microphone_record` snackbar; reset to idle.
   - Mutation that re-reds: restore the `:3508-3523` snackbar block → red.

6. `conversation_wired_test.dart`::"1:1 Open Settings tap deep-links via the injected gateway"  *(source-wiring + behavior lock)*
   - Tier: integration/widget
   - RED on HEAD because: no gateway is wired into the 1:1 denied path today → the injected spy is never called; asserting `gateway.openAppSettingsCallCount == 1` after tapping the dialog's Settings button fails (dialog doesn't even render on HEAD).
   - GREEN asserts: after `onRecordStart` (permanentlyDenied) → tap `mic-perm-open-settings` → `gateway.openAppSettingsCallCount == 1`.
   - Mutation that re-reds: have the screen pass its OWN inline dialog (not the shared helper) OR drop the gateway injection → spy uncalled → red. (Locks "both screens route through the one shared helper + injected gateway".)

7. `group_conversation_wired_test.dart`::"group Open Settings tap deep-links via the injected gateway"  *(source-wiring + behavior lock)*
   - Tier: integration/widget
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
| TC-01 dialog renders | helper render | widget | mic_permission_prompt_test::"permanentlyDenied shows the rationale dialog …" | helper file absent → compile red | swap dialog back to snackbar | `./scripts/run_test_gates.sh 1to1` (+ add `permissions` to :529 regex) | **add `permissions` to classify regex `run_test_gates.sh:529`** |
| TC-02 Open Settings deep-links | helper behavior | widget | mic_permission_prompt_test::"tapping Open Settings invokes gateway.openAppSettings …" | helper absent; no openAppSettings call exists | button only pop()s, no gateway call | `flutter test test/core/permissions/mic_permission_prompt_test.dart` | classify via :529 regex add |
| TC-03 Not now dismisses | helper behavior | widget | mic_permission_prompt_test::"tapping Not now dismisses without opening settings" | helper absent → compile red | wire Not-now to call openAppSettings | `flutter test test/core/permissions/mic_permission_prompt_test.dart` | classify via :529 regex add |
| TC-04 1:1 denial → dialog | screen wiring (1:1) | integration/widget | conversation_wired_test::"1:1 mic denial shows the rationale dialog …" | HEAD shows perm_microphone_record snackbar | restore `:2823-2838` snackbar block | `./scripts/run_test_gates.sh 1to1` | AUTO — `ONE_TO_ONE_TESTS:63` |
| TC-05 group denial → dialog | screen wiring (group) | integration/widget | group_conversation_wired_test::"group mic denial shows the rationale dialog …" | HEAD shows `:3508-3523` snackbar | restore `:3508-3523` snackbar block | `./scripts/run_test_gates.sh groups` | AUTO — `GROUP_TESTS:131` |
| TC-06 1:1 Settings deep-link | source-wiring lock (1:1) | integration/widget | conversation_wired_test::"1:1 Open Settings tap deep-links via the injected gateway" | no gateway wired in 1:1 → spy uncalled | inline a screen-local dialog / drop injection | `./scripts/run_test_gates.sh 1to1` | AUTO — `ONE_TO_ONE_TESTS:63` |
| TC-07 group Settings deep-link | source-wiring lock (group) | integration/widget | group_conversation_wired_test::"group Open Settings tap deep-links via the injected gateway" | no gateway wired in group → spy uncalled | inline a screen-local dialog / drop injection | `./scripts/run_test_gates.sh groups` | AUTO — `GROUP_TESTS:131` |
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
2. **DECIDE the OPEN DECISION** (Option A recommended). If A: add `permission_handler: ^11.x` to `pubspec.yaml`; `flutter pub get`; add the iOS Podfile `PERMISSION_MICROPHONE=1` macro. Stop-if: `pub get` resolution conflict with `record`/other deps → escalate (do not pin blindly).
3. NEW `lib/core/permissions/mic_permission_gateway.dart`: `enum MicPermissionStatus { granted, denied, permanentlyDenied }` + `abstract class MicPermissionGateway { Future<MicPermissionStatus> request(); Future<bool> openAppSettings(); }` + prod `PermissionHandlerMicGateway` wrapping `Permission.microphone.request()` (map `PermissionStatus`) and `openAppSettings()`.
4. NEW `lib/core/permissions/mic_permission_prompt.dart`: `Future<void> showMicPermissionDeniedPrompt(BuildContext, {required MicPermissionGateway gateway})` — `showDialog` modeled on `_confirmLeaveWhileUploadActive` (`conversation_wired.dart:641-666`): `AlertDialog(title: Text(l10n.mic_perm_dialog_title), content: Text(l10n.mic_perm_dialog_body), actions: [ TextButton(key: ValueKey('mic-perm-not-now'), …pop()), TextButton.icon(key: ValueKey('mic-perm-open-settings'), Icons.settings_outlined, label: l10n.compose_open_settings, onPressed: () { Navigator.pop(); gateway.openAppSettings(); }) ])`. NEW button keys — do NOT reuse `upload-leave-*`.
5. `conversation_wired.dart:2811-2838`: route through the gateway (Option A: `final status = await gateway.request()`; `granted` → continue to `start()`; `permanentlyDenied`/`denied`-final → `await showMicPermissionDeniedPrompt(context, gateway: gateway)` then reset idle). Replace the `:2823-2838` snackbar block. Inject the gateway via the `ConversationScreen`/wired widget field (parallel to `audioRecorderService`) so tests pass a `FakeMicPermissionGateway`; prod default = `PermissionHandlerMicGateway()`.
6. `group_conversation_wired.dart:3498-3523`: identical replacement via the SAME helper + injected gateway. Stop-if: the two screens cannot share one helper without duplicating the dialog → that means the helper is mis-scoped; fix the helper, do not copy the dialog.
7. `test/shared/fakes/fake_audio_recorder_service.dart` (prerequisite, from step 1): keep `permissionGranted` for the granted path; the denied decision now comes from the injected `FakeMicPermissionGateway`. NEW `test/shared/fakes/fake_mic_permission_gateway.dart`.
8. l10n: append-by-key `mic_perm_dialog_title`, `mic_perm_dialog_body` to en/ar/de (plain-string, no @-metadata). REUSE `compose_open_settings` (`:146` all locales) for the Settings button. For "Not now": verify whether an existing dismiss key fits (`grep -i '"cancel"\|"not_now\|"dismiss"' lib/l10n/app_en.arb`); if none, add `mic_perm_not_now`. Regenerate l10n (`flutter gen-l10n` via `flutter pub get`/build). Proposed en copy — title: "Microphone access needed"; body: "To record voice messages, allow microphone access in Settings."; not-now: "Not now".
9. `scripts/run_test_gates.sh:529`: add `permissions` to the alternation → `^test/core/(bridge|constants|database|device|inbox|local_discovery|media|permissions|secure_storage|theme|utils)/.*_test\.dart$` so `test/core/permissions/mic_permission_prompt_test.dart` classifies (completeness gate + core-host-all sweep). Confirm with `run_completeness_check`.
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

# Preservation + named gates (after adding `permissions` to the :529 regex)
./scripts/run_test_gates.sh 1to1       # ONE_TO_ONE_TESTS green + the new 1:1 cases
./scripts/run_test_gates.sh groups     # GROUP_TESTS green + new group cases; the 2 PRE-EXISTING wired fails (GMAR-004 reopen-hydration, incoming-group-image-refresh) are NOT mine
./scripts/run_test_gates.sh core-host-all   # mic_permission_prompt_test now classified + swept

# Completeness (the new core/permissions test must classify, not go unmatched)
./scripts/run_test_gates.sh completeness    # 0 unmatched (regex add at :529 covers it)

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
- [ ] OPEN DECISION resolved (Option A `permission_handler` added, or Option B documented) and reviewer-approved.
- [ ] Denied branch shared in ONE helper called from BOTH screens (INV-3 source-wiring lock green).
- [ ] `test/core/permissions/mic_permission_prompt_test.dart` classifies — `permissions` added to `run_test_gates.sh:529`; completeness = 0 unmatched.
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
- **Option B path** (no tri-state) — documented but not chosen; if reviewer flips to B, TC-04 collapses into denial-on-any and the tri-state cases drop.

## Dependency Impact
- None outbound. NEW `lib/core/permissions/` module + `MicPermissionGateway` seam are reusable for any future permission prompt (camera/photos) — a standalone hardening win. Adding `permission_handler` is a new shared dependency available to the whole app (Option A).

## Reviewer Findings
<to be filled by the sufficiency reviewer>

## Arbiter Decision
Structural blockers: … | Deferred details: real openAppSettings device round-trip | Accepted differences: posts-composer parity out; Option-A plugin add gated on reviewer approval | hand off to execution

## Final Execution Verdict
Verdict: (accepted/rejected) | Files changed: … | Tests run (+counts): … | Blocking: … | QA verdict: … | Non-blocking follow-ups (owner): posts mic parity; device round-trip proof
