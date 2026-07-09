# 234 - 1:1 Private Media Lifecycle

Status: evidence-gated
Type: New Feature
Spec: free-text intent — direct-chat view-once, disappearing, and protected received image/video lifecycle with truthful local, notification, capture, restart, and multi-device behavior
Classification: evidence-gated
Closure tier: device/relay conditional

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | `graphify-arch` query; direct message/media models and v1/v2 codecs; send/receive/retry paths; viewer/actions; notification preview/listener; media cleanup; DB migration chain; relay media TTL/cleanup | HEAD has no lifecycle fields, consume state, secure-screen/PiP seam, or single-use relay operation. Several mutually incompatible product choices change schema, wire compatibility, Go/relay scope, and required device proof. | Resolve D-234-01..08, refresh exact schema/wire tests, then reclassify or split transport enforcement before authoring REDs. |

## Problem And Evidence

- Behavior to improve: direct-chat users need clearly defined private media modes such as View Once, time-limited disappearing media, or export-protected media, with truthful behavior when opened, expired, retried, screenshotted/recorded, notified, restarted, or viewed on another device.
- Impact: adding only hidden buttons or a local timer would create false privacy. A media file can currently persist locally, appear in notifications, be exported by plans 227/231/232, survive restart, and remain on the relay for its ordinary retention window.
- Confirmed current gap: `ConversationMessage`, `MediaAttachment`, and `MessagePayload` carry no private-media policy, open/consume timestamp, expiry, or protected-export state. The v1/v2 inner codecs therefore cannot preserve such policy.
- Confirmed current mechanism: direct receipt persists/decrypts a message and may auto-download media before displaying a caption/type notification (`lib/features/conversation/application/chat_message_listener.dart:588-635`). `notificationBodyForMessage` returns text/caption/media type at `lib/core/notifications/show_notification_use_case.dart:17-39`, while push preview derives text/media at `lib/core/notifications/push_decrypt_preview.dart:72-90`.
- Confirmed current gap: `FullScreenImageViewer` is path-backed and HEAD contains no app-wide secure-screen, screenshot/screen-recording observer, protected background snapshot, or native PiP policy seam.
- Confirmed current mechanism: deleting for me removes the direct message, attachments, and app-owned files locally; it does not revoke an exported copy or remote/relay copy (`delete_message_use_case.dart:17-47`, `:435-463`).
- Confirmed relay boundary: relay media has a fixed seven-day TTL and background cleanup in `go-relay-server/media.go:18-23`, `:94-110`; there is no source-grounded single-use fetch, consume receipt, or sender revocation API.
- Existing coverage: direct v2 codec/encryption round-trip, dedup/retry, notification preview, viewer lifecycle, local deletion, and migration chain tests cover ordinary media only.
- Missing coverage: policy codec/privacy, DB durability, compose eligibility, receive-before-preview ordering, atomic consumption, expiration clocks, duplicate/retry/restart convergence, export/forward/bookmark exclusion, platform capture truth, multi-device semantics, relay custody, and legacy fallback.
- Refuted finding: a local `opened=true` flag alone cannot honestly provide account-wide View Once or relay revocation. Those promises require a decided authority/receipt contract and, if server-enforced, a separately reviewed transport/Go slice.
- Unresolved findings (blocking): **D-234-01** exact modes, sender eligibility, combinations, and recipient copy; **D-234-02** clock origin, durations, grace/clock-skew/offline rules, and expiry display; **D-234-03** what counts as consumed plus local-versus-account/multi-device convergence, retry, duplicate, and receipt semantics; **D-234-04** Android/iOS screenshot, recording, app-switcher, and PiP guarantees versus best-effort disclosure; **D-234-05** relay fetch count, deletion/revocation, offline access, exported-copy truth, and whether Go enforcement is required; **D-234-06** foreground/background/push notification preview policy; **D-234-07** codec versioning, unknown-mode fail behavior, and legacy-client interoperability; **D-234-08** sender/recipient delete, block, bookmark, reply, save, share, forward, and library interactions before/after consume.
- Affected production/test/gate files are intentionally conditional: direct policy/model/codec/send/receive/retry/viewer/notification files; a DB vNEXT allocated only after approval and a fresh conflict check if durable fields are required; Android/iOS native privacy hooks if approved; dedicated host/SQLCipher/device tests; and possibly a separate Go/relay plan after D-234-03/05. Exact production scope must not be frozen before those decisions.

## Scope Contract And Guard

Conditionally in scope after D-234-01..08:
- Define one versioned, typed direct-only private-media policy and a state machine whose events, clocks, terminal states, and legacy behavior are approved before implementation.
- Carry only the approved policy/state receipt inside the encrypted direct-message inner payload; ordinary routing envelopes must not reveal private mode, expiry, caption, or consumption state.
- If the approved state machine requires durable schema, allocate DB vNEXT only during the plan refresh after checking the then-current version/migration ledger; define only the minimum approved lifecycle fields/constraints. This evidence-gated plan reserves no number.
- Persist receive policy before any notification or auto-download decision; use generic/redacted notification content when D-234-06 requires it.
- Fail closed across plan-227 Save/Share, plan-232 Forward, plan-228 bookmark/library, plan-229 download/eviction, and plan-230 viewer capabilities according to the approved state machine.
- Make consume/expiry cleanup atomic and restart-safe for app-owned message/attachment/file state, with idempotent duplicate/retry handling and no resurrection.
- Add only platform protections that can be demonstrated on real Android/iOS devices, and label unavoidable OS limitations rather than claiming impossible prevention.

Must preserve:
- Ordinary and legacy direct media continue to send, receive, notify, download, open, export, forward, bookmark, retry, and delete under their current contracts -> TC-234-01/13.
- Existing direct dedup, retry identity, encrypted v2 envelope, and media integrity behavior remain unchanged for non-private media -> existing exchange/encryption `GREEN sentinels`.
- Exported Photos/Files/third-party copies are never claimed to be revocable -> D-234-05 plus TC-234-06/12.
- Group/discussion/announcement payloads and permissions are untouched -> TC-234-14.

Hard `Do not`:
- Do not implement private behavior, schema, wire fields, UI copy, timers, platform flags, receipts, or cleanup until D-234-01..08 are approved and the plan is refreshed.
- Do not call a local-only View Once implementation account-wide, globally consumed, screenshot-proof, or relay-revoked.
- Do not place policy/expiry/consume state in an unencrypted outer envelope or diagnostics.
- Do not silently treat an unknown private policy as ordinary exportable media; D-234-07 must specify the interoperable fail behavior.
- Do not edit group/announcement payloads or Go/libp2p/relay code inside this plan. If D-234-03/05 require server enforcement, create an isolated transport plan with its own review and real-relay closure.
- Do not auto-download, cache, bookmark, save, share, forward, or PiP protected media merely because a legacy action path bypasses the viewer.

Deferred / accepted difference:
- Group and announcement private-media lifecycle -> plans 238 and 242 or later approved owners; direct policy must not leak into those lanes.
- Account-wide/single-use relay enforcement -> a new transport/relay plan only if D-234-03/05 select that promise.
- Preventing a user from photographing another screen/camera is outside software control and must be stated plainly in product copy.
- Ordinary media actions/library remain owned by plans 231–233 and are not blocked by this evidence-gated feature.

Dependencies:
- Plans 227–230 define egress, local media state/download policy, and typed viewer capability seams that private eligibility must fail closed through.
- `Test-Flight-Improv/232-1to1-received-media-forwarding-tdd-plan.md` owns direct Forward/action eligibility. It does not grant this evidence-gated plan a later DB number.
- D-234-01..08 are approval dependencies. Any choice requiring relay authority also depends on a new isolated Go/relay plan, not an implicit expansion here.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-234-01 | Missing private policy remains ordinary legacy media with no expiry/consume/export restriction. | `test/features/conversation/domain/models/private_media_policy_test.dart::missing policy preserves ordinary legacy media behavior` | host domain unit / v1/v2 legacy fixtures | HEAD is ordinary-only; after approved implementation this becomes a `GREEN sentinel` proving absence decodes to the D-234-07 legacy state | default a missing field to the strictest private mode or expire an ordinary fixture -> TC-234-01 red | Reserved AUTO (`feature-host-all`) + both 1:1 arrays after the plan refresh; do not author a guessed codec before D-234-07 |
| TC-234-02 | Every approved policy/state field round-trips only in encrypted inner v1/v2 payloads; unknown versions/modes follow the approved fail behavior and outer routing stays private. | `test/features/conversation/domain/models/private_media_policy_test.dart::approved policy codec is inner-only versioned and legacy-safe` | evidence-gated host domain / approved D-234-01/07 matrix | HEAD causal gap: fields absent -> GREEN expectations become exact only after modes/version/fallback are approved | leak policy into outer envelope, drop a state field, or change unknown-mode fallback -> TC-234-02 red after decisions | `flutter test test/features/conversation/domain/models/private_media_policy_test.dart --plain-name 'approved policy codec is inner-only versioned and legacy-safe'`; reserve AUTO + both 1:1 arrays; blocked by D-234-01/07 |
| TC-234-03 | A freshly conflict-checked DB vNEXT preserves all then-current rows, adds only approved constrained lifecycle state, supports fresh/full-chain/run-twice migration, and survives encrypted close/reopen. | `test/core/database/migrations/direct_private_media_lifecycle_migration_test.dart::approved vNEXT preserves prior schema and adds lifecycle state idempotently` plus `integration_test/direct_private_media_lifecycle_sqlcipher_proof_test.dart` | evidence-gated host structure + Android/iOS real `sqflite_sqlcipher` | HEAD evidence gap: no version/schema is allocated -> after D-234 approval/fresh ledger check, exact PRAGMA/default/check/index, before/after, registry arms, fresh/full chain, close/reopen, and second run pass | omit a default/guard/registry arm, lose a prior-version row on reopen, or make rerun fail -> TC-234-03 red after refresh | `flutter test test/core/database/migrations/direct_private_media_lifecycle_migration_test.dart` plus dedicated Android/iOS commands; reserve one exact `1to1` device discovery record only after D-234-01..03/07 and vNEXT allocation |
| TC-234-04 | Sender composer exposes exactly the approved modes for eligible image/video, rejects invalid combinations, and previews recipient-visible clock/copy truthfully. | `test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart::composer enforces approved private media modes and copy` | evidence-gated widget / approved mode-duration matrix | HEAD causal RED: no mode UI -> exact keys, invalid-state non-dispatch, and payload policy pass after D-234-01/02 | allow a disallowed type/mode combination or send stale prior selection -> TC-234-04 red | `flutter test test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart`; reserve AUTO + both 1:1 arrays; blocked by D-234-01/02 |
| TC-234-05 | Receive persists policy/state before notification and download decisions; duplicate/retry delivery cannot downgrade or restart a private lifecycle. | `test/features/conversation/application/chat_message_listener_private_media_test.dart::receive commits private policy before preview download and duplicate handling` | evidence-gated host application / ordered repository, notification, downloader fakes | HEAD causal RED: listener has no policy -> approved event order and call counts become exact after D-234-03/06 | notify/download before commit or overwrite stricter state with duplicate input -> TC-234-05 red | `flutter test test/features/conversation/application/chat_message_listener_private_media_test.dart`; reserve AUTO + both 1:1 arrays; blocked by D-234-03/06/07 |
| TC-234-06 | Save, Files, external Share, internal Forward, bookmark/library, and PiP capabilities fail closed in every approved protected/consumed/expired state, including non-viewer entry points. | `test/features/conversation/application/private_media_action_eligibility_test.dart::private lifecycle gates every egress forward library and pip path centrally` | evidence-gated host application / plans 227–232 spies + state table | HEAD gap: no policy -> central matrix and zero forbidden calls pass after D-234-01/08 | check only viewer buttons, allow forwarding from bubble/library, or claim exported-copy revocation -> TC-234-06 red | `flutter test test/features/conversation/application/private_media_action_eligibility_test.dart`; reserve AUTO + both 1:1 arrays; blocked by D-234-01/04/05/08 |
| TC-234-07 | Opening/consuming follows the approved atomic transition exactly once, closes/cleans approved local artifacts, and never reveals bytes after the terminal state. | `test/features/conversation/application/consume_private_media_use_case_test.dart::approved consume transition is atomic exactly-once and cleanup-safe` | evidence-gated host integration / real temp files + transactional repository fake | HEAD compile RED: use case/state absent -> exact transition, callback, cleanup, rollback, and sibling preservation follow D-234-02/03/08 | mark consumed before successful open, consume twice, delete a sibling/export, or leave bytes after terminal state -> TC-234-07 red | `flutter test test/features/conversation/application/consume_private_media_use_case_test.dart`; reserve AUTO + both 1:1 arrays; blocked by D-234-02/03/08 |
| TC-234-08 | Restart, crash between approved transition steps, duplicate delivery, and send retry converge without resurrecting consumed/expired media or reminting receipt identity. | `test/features/conversation/integration/private_media_restart_replay_test.dart::restart duplicate and retry converge on approved terminal lifecycle` | evidence-gated host integration / crash checkpoints + repository reopen | HEAD compile RED -> recovery results depend on D-234-03 but must be deterministic, idempotent, and non-resurrecting | omit persisted checkpoint, accept stale duplicate, or mint a new consume receipt on retry -> TC-234-08 red | `flutter test test/features/conversation/integration/private_media_restart_replay_test.dart`; reserve AUTO + both 1:1 arrays; blocked by D-234-03/07 |
| TC-234-09 | Expiry starts from the approved clock, handles offline/clock skew/background/resume exactly, sweeps once, and displays truthful remaining/expired state. | `test/features/conversation/application/private_media_expiry_scheduler_test.dart::approved clock expires once across restart skew and resume` | evidence-gated host application / fake monotonic+wall clocks, lifecycle, repository reopen | HEAD compile RED: policy/scheduler absent -> exact boundaries and no early/late resurrection pass after D-234-02 | use only device wall clock, reset timer on reopen, or run duplicate cleanup -> TC-234-09 red | `flutter test test/features/conversation/application/private_media_expiry_scheduler_test.dart`; reserve AUTO + both 1:1 arrays; blocked by D-234-02/03 |
| TC-234-10 | Foreground/local/push notifications expose only the approved generic metadata and never private caption, thumbnail, bytes, mode, expiry, or consume state. | `test/core/notifications/private_media_preview_policy_test.dart::private media preview is consistently redacted across local and push paths` | evidence-gated host unit/application / local and push fixtures | HEAD partial RED: current preview may use caption/type -> approved generic body and no forbidden fields after D-234-06 | reuse ordinary caption preview in one path or serialize policy into notification payload -> TC-234-10 red | `flutter test test/core/notifications/private_media_preview_policy_test.dart`; reserve `core-host-all` + both 1:1 arrays if cross-family registration requires it; blocked by D-234-06 |
| TC-234-11 | Android/iOS apply only approved screenshot, recording, app-switcher, and PiP controls while the private route is visible, restore ordinary routes afterward, and disclose platform limits. | `integration_test/direct_private_media_platform_protection_proof_test.dart` | evidence-gated physical Android+iOS proof / real lifecycle and operator capture checklist | HEAD device RED: no native seam -> exact prevent/detect/blank/disable outcomes and restoration are defined only after D-234-04/platform feasibility evidence | leave secure state enabled globally, permit PiP, fail to shield background snapshot, or claim an unproved prevention -> TC-234-11 fails | `flutter test integration_test/direct_private_media_platform_protection_proof_test.dart -d "$ANDROID_DEVICE_ID"` and `-d "$IOS_DEVICE_ID"`; dedicated `1to1` device-proof discovery; blocked by D-234-04 |
| TC-234-12 | If account-wide/single-use behavior is approved, two devices and the real relay converge on one consumption result, enforce approved offline/replay rules, and never reserve bytes; otherwise this row explicitly records local-only truth. | `integration_test/direct_private_media_multi_device_real_harness.dart::approved view lifecycle converges across two direct peers and relay` | conditional paired-device real-relay proof / two physical clients + relay media state | HEAD has no receipt/single-use API. GREEN is intentionally undefined until D-234-03/05 selects local-only versus relay-authoritative behavior | replay a fetch/receipt, consume on both devices, or continue serving after approved revocation -> TC-234-12 fails when global enforcement is selected | Register/run under `1to1` only if D-234-03/05 select global enforcement; otherwise mark N/A with approved local-only product copy and no Go claim |
| TC-234-13 | Ordinary direct images/videos retain current encrypted send/receive, notification, download, viewer, retry, save/share/forward, and deletion behavior. | `test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart` plus direct media/action sentinels | `GREEN sentinels` / existing host fixtures | GREEN on HEAD -> remain GREEN after the approved private branch lands | route all media through private cleanup/redaction or change ordinary defaults -> sentinel red | Run existing encryption/exchange/download/viewer/action tests and both 1:1 gates; exact additions finalized after D-234 decisions |
| TC-234-14 | The direct private slice changes no group/announcement payload or permissions and contains no Go/relay edits unless a separately accepted transport plan owns them. | `test/features/conversation/application/direct_private_media_boundary_test.dart::private media remains direct-scoped and transport-plan isolated` | evidence-gated host source-contract / forbidden imports and baseline path guard | HEAD compile RED: target sources absent -> approved direct files exclude group/announcement/Go/relay calls; baseline Go/relay state and ordinary sentinels remain unchanged | import group publisher, change a baseline Go/relay path under this plan, or reuse direct policy silently in announcements -> TC-234-14 red | `flutter test test/features/conversation/application/direct_private_media_boundary_test.dart`; reserve AUTO + both 1:1 arrays; refreshed plan must add baseline status+binary-diff commands |

### Test Notes

- TC-234-02..12 are obligations, not permission to guess expected values. Their exact fixtures/assertions must be refreshed after D-234-01..08; until then, writing production or theatrical RED tests is prohibited.
- TC-234-03 reserves no DB number. Refresh must first allocate a free vNEXT, then name every column/default/check/index, both registry arms, prior/full-chain fixture, and real SQLCipher before/after/run-twice assertions.
- TC-234-11 must distinguish prevention, detection, obscuring, and disclosure per platform. A test that only checks a Dart boolean cannot close screenshot/recording/PiP behavior.
- TC-234-12 is not optional if product copy promises cross-device or relay-authoritative single-use. Local-only copy makes the paired-relay row explicitly N/A instead.

## Implementation Steps

1. Do not implement. Obtain written decisions D-234-01..08, platform feasibility evidence for D-234-04, and a product statement choosing local-only versus account/relay-authoritative consumption.
2. Refresh this plan: enumerate the state machine/events, exact inner-wire fields/version fallback, action matrix, notification copy, and closure profile. If schema is required, check the then-current ledger, allocate a free DB vNEXT, and only then specify its exact migration.
3. If D-234-03/05 require Go/relay enforcement, create and independently review an isolated transport plan; keep its migrations/protocol/device tests out of this UI/local plan.
4. Run `$tdd-review` on the refreshed plan(s). Only after an execution-ready verdict, author the chosen causal REDs before production edits.
5. Implement domain/persistence/receive/notification/eligibility first, then atomic consume/expiry/UI, then native protection and any separately owned relay contract.
6. Register dedicated host/device proofs, run preservation gates and representative mutations, and accept only the approved platform/relay closure.

## Risks And Blind Spots

- False privacy claims are worse than a missing feature -> D-234-03..05 and TC-234-11/12 force local/platform/relay truth to match copy.
- Unknown/legacy clients can downgrade policy -> D-234-07 and TC-234-01/02.
- Notification or auto-download can leak before policy persistence -> TC-234-05/10.
- Lifecycle / derived-state durability: TC-234-03/08/09 require encrypted reopen, crash checkpoints, and clock/lifecycle reconstruction.
- Sibling-surface consistency: TC-234-06 checks viewer, bubble, library, bookmark, Forward, and native egress through one central eligibility matrix.
- Destructive-action side effects: TC-234-07 proves exact approved cleanup plus rollback, sibling, and exported-copy preservation.
- Invariant re-verification under new transitions: every open/resume/retry/duplicate/clock/device receipt rechecks terminal state before byte access in TC-234-07..12.

## Acceptance Gates

```bash
# Snapshot before any future execution; record unrelated changes
git status --short

# Structural blocker inventory only; this does not approve the decisions
test -f Test-Flight-Improv/232-1to1-received-media-forwarding-tdd-plan.md
rg -n 'D-234-01|D-234-02|D-234-03|D-234-04|D-234-05|D-234-06|D-234-07|D-234-08' Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan.md

# Approval evidence gate: no shell command can close it. Written D-234-01..08 decisions,
# platform feasibility evidence, refreshed exact contracts, and tdd-review are required.

# After refresh: first causal RED must be named from the approved state machine
# N/A while evidence-gated; do not manufacture a RED against unspecified behavior.

# Mandatory preservation baseline before/after any later implementation
flutter test test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh 1to1 --list

# Conditional DB/platform closure is not executable yet. The refresh must replace
# the vNEXT migration placeholder with its allocated number and add literal host,
# Android SQLCipher, iOS SQLCipher, and per-platform protection commands.

# Scope/hygiene after later implementation
# Refreshed plan must record and compare Go/relay status+binary diff against its
# execution-start baseline; a raw clean-tree assertion is invalid on current dirt.
flutter analyze
git diff --check
```

## Device/Relay Proof Profile

- Profile status: decision-blocked. No device/relay command currently closes the feature because D-234-01..08 do not define what must be observed.
- Always-required if the refreshed plan allocates DB vNEXT/native protection: one physical Android and one physical iOS run for real SQLCipher persistence and platform capture/background/PiP behavior. Use `$ANDROID_DEVICE_ID` and `$IOS_DEVICE_ID`; never hardcode transient IDs.
- Conditional real-relay branch: if D-234-03/05 promise account-wide or relay-authoritative single use, require two direct peers on separate physical devices, a real relay/media service, deterministic consume/replay coordination, and retained relay/server logs that expose no media/caption/key. A separate transport plan must own any Go/protocol edits.
- Local-only branch: if approved copy explicitly says consumption is device-local, paired-relay proof is N/A; host retry/restart plus Android/iOS local device proof closes only that narrower claim.
- Required setup after refresh: approved policy fixtures, clean/upgrade encrypted DBs, controllable foreground/background/clock states, capture/recording operator checklist, and explicit offline/replay scenario. Exact accounts/relay credentials remain undefined until D-234-03/05.
- Registration: dedicated files only — `direct_private_media_lifecycle_sqlcipher_proof_test.dart` and `direct_private_media_platform_protection_proof_test.dart` get exact `1to1` discovery records. Do not classify a broad unrelated capability file.
- Closure outputs: per-platform SQLCipher PRAGMA/before-after/reopen/run-twice evidence; per-platform screenshot/recording/app-switcher/PiP observation; and, only when selected, paired-device consume/replay/relay evidence.
- Current availability observation: physical Android and iOS devices were visible on 2026-07-09, but availability must be rechecked at execution; evidence decisions, not hardware, are the current blocker.

## Execution Interpretation And Done Criteria

- Expected RED: N/A while evidence-gated. The first causal RED is selected only after the approved state machine makes GREEN observable.
- Green sentinel: ordinary direct encrypted media round trip, dedup/retry, viewer, notification, and local-delete behavior.
- Pre-existing dirty tree / known failure: snapshot at any future execution start; preserve unrelated changes.
- Environment blocker: none currently determines status. Product/platform/authority evidence is the blocker.
- Scope drift: any guessed semantics, prematurely reserved migration number/columns, group/announcement changes, or Go/relay edit without a separate accepted plan blocks progress.

- [ ] D-234-01..08 are written, mutually consistent, and mapped to every affected action/surface.
- [ ] The refreshed plan names the state machine, codec, freshly allocated DB vNEXT schema/migration proof when required, and legacy fallback exactly.
- [ ] Platform claims distinguish prevention/detection/obscuring and have Android+iOS physical proof.
- [ ] Local-only versus multi-device/relay-authoritative consumption has one explicit closure profile.
- [ ] Every approved behavior has a causal test and representative mutation; ordinary media sentinels remain GREEN.
- [ ] New host/device tests are registered only in owning 1:1 inventories.
- [ ] `flutter analyze`, `git diff --check`, and the appropriate Go/relay scope guard pass.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: N/A — resolve D-234-01..08 and refresh/review this plan before authoring any behavior test.
- Preservation command: `flutter test test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart`.
- Manual registration: reserved dedicated direct host files in both 1:1 arrays; dedicated SQLCipher/platform proof files get exact `1to1` discovery records only after decisions. Never broaden-classify the existing mixed SQLCipher capability file.
- Migration: none reserved. If approved lifecycle durability requires schema, refresh against the then-current ledger and allocate vNEXT only then; required closure remains host structure/full chain plus physical Android/iOS real-SQLCipher PRAGMA/before-after/reopen/run-twice proof.
- Boundary closure: conditional Android+iOS native proof; paired-device real-relay proof only if approved product copy promises global/single-use enforcement.
- Unresolved evidence: D-234-01..08 and the resulting local-versus-transport plan boundary. Status remains `evidence-gated`.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | D-234-01..08 unresolved | obtain decisions and refresh plan |
