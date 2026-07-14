# 234 - 1:1 Private Media Lifecycle

Status: accepted
Type: New Feature
Spec: free-text intent — direct-chat view-once, disappearing, and protected received image/video lifecycle with truthful local, notification, capture, restart, and multi-device behavior
Classification: implemented and accepted (device/install-local contract)
Closure tier: host + availability-bounded platform proof; relay-authoritative proof N/A

## Accepted Decision Contract

Accepted on 2026-07-11 for implementation-committed gap closure. This section resolves D-234-01..08 and supersedes every older statement below that calls these decisions unresolved, evidence-gated, conditional, or an implementation prohibition. The six-session breakdown remains the execution authority.

| Decision | Accepted contract |
|---|---|
| D-234-01 | Version 1 has mutually exclusive `ordinary`, `protected`, `view_once`, and `disappearing` modes. A private mode is available only for a new ordinary send with exactly one image/GIF or video, no audio/file, second attachment, text/caption, edit, or Forward origin. All private modes are egress-protected. Disappearing durations are exactly 1 hour, 1 day, or 7 days. |
| D-234-02 | Disappearing starts when the recipient durably commits the message on that device. Persist `receivedAt`, `expiresAt`, and a clock high-water mark; expire at `now >= expiresAt`; evaluate with `max(now, persistedHighWater)` so backward clock movement never resurrects or extends. Resume/cold-start sweeps are idempotent. |
| D-234-03 | Consumption is device/install-local. View Once is `available -> opening -> viewing -> consumed`; CAS to `opening` precedes byte exposure. Only a proven pre-first-frame decode failure in the same process may restore `available`. First frame records `viewing/revealedAt`; exit, background, capture handling, or close terminalizes. Restart from `opening`/`viewing` terminalizes fail closed. Duplicate/retry never reopens terminal state. No consume receipt is sent. |
| D-234-04 | Private routes use route-scoped Android `FLAG_SECURE`, restored on every exit/error. iOS makes no screenshot-prevention claim: observe screenshot/capture signals, cover app-switcher snapshots, cover/pause private bytes during capture, and warn/dismiss truthfully. Every private mode is PiP-ineligible. Plan 243 owns actual PiP implementation; this plan owns denial input. |
| D-234-05 | There is no Go/libp2p/relay change or relay-revocation promise. Existing encrypted transport and post-commit relay-delete behavior remain. Local terminal state blocks re-download. Cross-device consumption, recovery after uninstall, sender revocation, and revocation of external copies are not promised. |
| D-234-06 | Foreground local and decrypted push previews use the localized meaning `Private media`; sender/conversation identity may remain. Caption, thumbnail, kind, mode, duration, expiry, keys, paths, and lifecycle state never enter preview text, payloads, or diagnostics. Policy commits before preview/download decisions. |
| D-234-07 | A versioned `privateMedia` object (version, mode, and disappearing duration) exists only in encrypted v2 inner JSON. It never enters the clear envelope, v1 plaintext writer, owner lane, relay metadata, or logs. Missing means ordinary. Unknown/malformed/ineligible private policy persists as local `unsupported`, remains redacted and non-downloadable/non-openable/non-egressable/non-forwardable/non-bookmarkable/non-PiP, but deletable. Unknown additive fields in valid v1 are ignored. |
| D-234-08 | Private media is excluded from Shared Media and bookmarks. Photos/Files Save, external Share, internal Forward, bookmark, batch actions, and PiP are always denied across viewer, bubble, library, deep-link/notification, and direct-call seams. Auto-download is off; manual in-app download is allowed only before terminal state into canonical app storage. Reply quotes only `Private media`; Delete-for-me remains. Terminalization removes app-owned bytes, staged parts, key material, bookmark/resume state, and local path while retaining a minimal idempotency tombstone. |

Product truth is deliberately device-local. It does not claim account-wide consumption, relay revocation, screenshot-proof iOS behavior, protection against photographing another screen, or recovery after uninstall. Plan 234 exclusively owns DB v100; Plan 238 is reserved v101.

## Session Execution Ledger

| Session | Status | Closed scope | Evidence | Reopen rule |
|---|---|---|---|---|
| 01 — Typed policy, encrypted codec, and v100 durability | accepted | Shared typed policy/unsupported vocabulary; encrypted-v2 inner codec; direct-parent model/helper persistence; idempotent v100 in both registries; v1..v99 preservation | Causal REDs; focused host suites; Android `21071FDF600CSC` and iOS simulator `674DFFF6-5F38-4235-93F6-AF7FBF86AE65` SQLCipher proofs; curated `1to1` 1,793 tests; independent QA accepted after two scope-hygiene fixes | Reopen only for a concrete regression in the closed Session-01 scope. |
| 02 — Compose, send/receive ordering, redacted previews, and private download entry | accepted | Eligible one-item private composer and pre-dispatch validation; encrypted-inner-only send/retry policy retention; receive-before-preview/download durability with replay-monotonic state; localized local/Dart-push/iOS-NSE redaction; automatic/visible download suppression; durable-parent-qualified explicit download entry | Original causal/focused/curated evidence remains accepted. A later concrete iOS NSE leak was repaired by causal compile RED, exact GREEN 1/1, full resolver 30/30, Dart preview preservation 55/55, independent QA accepted at `post_closure_fix_passes=1`, Graphify affected, and exactly one additional post-QA incremental refresh | Reopen only for a concrete regression in the closed Session-02 scope. |
| 03 — Atomic reveal, expiry, cleanup, and restart convergence | accepted | Transactional parent lifecycle CAS; single-opener lease and monotonic callbacks; persisted high-water/immutable-deadline expiry; retryable exact-direct cleanup; guarded download/eviction/delete races; hidden-tombstone replay suppression; bounded cold-start/resume recovery and foreground expiry scheduling | `B1` resolved by causal RED/GREEN; SQL 14/14, scheduler 11/11, download 66/66, restart 2/2, remaining direct/preservation commands green; curated `1to1` 1,875/1,875; host inventory 78; completeness 1,164/1,164; static/scope guards green; final QA accepted after `fix_passes=1`; exactly one post-QA Graphify refresh; no owned source/test newer than refresh | Reopen only for a concrete regression in the closed Session-03 lifecycle scope. |
| 04 — Central action, library, egress, Forward, bookmark, and PiP eligibility | accepted | One exact-current direct capability matrix across Save/Files/Share, Forward, bookmark, Shared Media/batch, explicit download, quote/Info, ordinary viewer entry, and typed PiP denial; SQL-before-`LIMIT`; guarded exact bookmark; same-ID group/unresolved preservation | Initial-QA version-1-ordinary `B1` resolved by causal RED/GREEN; focused policy 8, boundary 8, action 4, Forward 3, batch/library 8, SQL/repository 41, download 68, presentation/Forward 13, Shared Media/viewer 12, typed viewer 4; curated `1to1` 1,901/1,901; host inventory 80; completeness 1,166/1,166; static/scope guards green; final QA accepted after `fix_passes=1`; exactly one post-QA Graphify refresh | Reopen only for a concrete regression in the closed Session-04 direct capability/action/library scope. |
| 05 — Private-route UX and native Android/iOS protection truth | accepted | Dedicated direct private route; exact post-enter revalidation; real first-raster lifecycle; privacy-minimized state/actions; serialized Dart/native ownership; Android route-scoped `FLAG_SECURE`; truthful iOS detection/obscuring; debug-only proof seams | Final direct viewer 16, coordinator 9, typed/boundary 8, native Android 5 and iOS 4, device Android/iOS 1 each, download 68, curated `1to1` 1,935/1,935, host inventory 83, completeness 1,170/1,170; static/scope green; final QA accepted after honest `fix_passes=3`; Graphify impact over 21 attributable deltas plus one unchanged preservation dependency; one post-QA refresh; separate closure review accepted | Reopen only for a concrete Session-05 route/native protection regression; the third pass remains the recorded bounded exception. |
| 06 — Cross-session acceptance, device-local proof, and closure | accepted | Acceptance-only proof harness; whole-contract focused/native/device evidence; bounded physical-Android plus emulator artifact; registration/static/scope audit; durable closure synchronization | Criteria 84/84; focused batches 167/167, 332/332, 72/72, complete download 68/68, and 31/31 + 68/68 + 33/33; Android/iOS native and explicit SQLCipher/protection device proofs green; host inventory 90; final artifact `854235…6233`; protected manifests byte-identical at `9fa736…8a13`; QA accepted after `fix_passes=2`. External `1to1` success is user-attested with no available count/log and was not rerun here. | Reopen only for a concrete regression in the accepted device/install-local contract or proof/registration integrity. |

## Final Plan Verdict

Plan 234 is accepted and closed for the deliberately bounded device/install-
local direct private-media contract. Sessions 01–06 are accepted; no
Plan-234-owned residual, blocker, or hidden follow-up remains. The accepted
scope includes DB v100, encrypted-inner policy, local lifecycle and cleanup,
generic previews, centralized egress/library/viewer/PiP denial, guarded manual
download, and truthful Android/iOS protection behavior. It does not claim real
relay transport, account-wide consume, remote revocation, screenshot-proof
iOS behavior, cross-install convergence, or actual PiP.

Plan 238 landed sequential DB v101. The included-Wave-1 `host-all` and final
Graphify refresh completed on 2026-07-12; they remain aggregate evidence rather
than Plan-234 closure gates. Plans 242, 243, 248, 254, 241, and 253 remain
excluded from this rollout.

## Historical Pre-Decision Record (Superseded)

Everything from this heading through the old planning/gate profile below is a
retained audit trail from before D-234-01..08 were accepted. It is not current
status, implementation advice, or a blocker; the accepted decision contract,
session ledger, final verdict, and final execution criteria control.

### Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | `graphify-arch` query; direct message/media models and v1/v2 codecs; send/receive/retry paths; viewer/actions; notification preview/listener; media cleanup; DB migration chain; relay media TTL/cleanup | HEAD has no lifecycle fields, consume state, secure-screen/PiP seam, or single-use relay operation. Several mutually incompatible product choices change schema, wire compatibility, Go/relay scope, and required device proof. | Resolve D-234-01..08, refresh exact schema/wire tests, then reclassify or split transport enforcement before authoring REDs. |
| 2026-07-10 | Dependency refresh | revised plan 228 owner-lane/backfill/replay/cursor contracts and shared production migration registry | Any future direct lifecycle state must be owner-scoped, exclude unresolved legacy attachments, preserve same-ID group siblings, and extend the shared registry rather than recreating migration callbacks. These constraints do not resolve D-234-01..08. | Apply these invariants when the evidence ledger is accepted and vNEXT is allocated. |

### Historical Problem And Evidence

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

### Historical Scope Contract And Guard

Conditionally in scope after D-234-01..08:
- Define one versioned, typed direct-only private-media policy and a state machine whose events, clocks, terminal states, and legacy behavior are approved before implementation.
- Carry only the approved policy/state receipt inside the encrypted direct-message inner payload; ordinary routing envelopes must not reveal private mode, expiry, caption, or consumption state.
- If the approved state machine requires durable schema, allocate DB vNEXT only during the plan refresh after checking the then-current version/migration ledger; define only the minimum approved lifecycle fields/constraints and append it to plan 228's shared production create/upgrade migration registry. This evidence-gated plan reserves no number.
- Persist receive policy before any notification or auto-download decision; use generic/redacted notification content when D-234-06 requires it.
- Fail closed across plan-227 Save/Share, plan-232 Forward, plan-228 bookmark/library, plan-229 download/eviction, and plan-230 viewer capabilities according to the approved state machine.
- Apply direct lifecycle reads, writes, cleanup and action eligibility only to `owner_lane='direct'` attachments with a live direct parent. Plan-228 `unresolved` rows remain unavailable, and a same-message-ID group attachment is never mutated by a direct lifecycle transition.
- Make consume/expiry cleanup atomic and restart-safe for app-owned message/attachment/file state, with idempotent duplicate/retry handling and no resurrection.
- Add only platform protections that can be demonstrated on applicable Android/iOS targets available at execution, and label unavailable legs N/A plus unavoidable OS limitations rather than claiming impossible prevention.

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
- Do not infer direct ownership from `message_id`, reclassify plan-228 `unresolved` rows, or serialize the local owner lane into private-media wire policy/provenance.

Deferred / accepted difference:
- Group and announcement private-media lifecycle -> plans 238 and 242 or later approved owners; direct policy must not leak into those lanes.
- Account-wide/single-use relay enforcement -> a new transport/relay plan only if D-234-03/05 select that promise.
- Preventing a user from photographing another screen/camera is outside software control and must be stated plainly in product copy.
- Ordinary media actions/library remain owned by plans 231–233 and are not blocked by this evidence-gated feature.

Dependencies:
- Plans 227–230 define egress, local media state/download policy, and typed viewer capability seams that private eligibility must fail closed through.
- Plan 228 supplies the mandatory owner-aware repository contract, fail-closed legacy classification, scope/filter-bound cursor, `1..100` page limit, and shared production migration registry; the refreshed private-media plan must use rather than duplicate them.
- `Test-Flight-Improv/232-1to1-received-media-forwarding-tdd-plan.md` owns direct Forward/action eligibility. It does not grant this evidence-gated plan a later DB number.
- D-234-01..08 are approval dependencies. Any choice requiring relay authority also depends on a new isolated Go/relay plan, not an implicit expansion here.

### Historical Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-234-01 | Missing private policy remains ordinary legacy media with no expiry/consume/export restriction. | `test/features/conversation/domain/models/private_media_policy_test.dart::missing policy preserves ordinary legacy media behavior` | host domain unit / v1/v2 legacy fixtures | HEAD is ordinary-only; after approved implementation this becomes a `GREEN sentinel` proving absence decodes to the D-234-07 legacy state | default a missing field to the strictest private mode or expire an ordinary fixture -> TC-234-01 red | Reserved AUTO discovery + both 1:1 arrays after the plan refresh; close with the focused test and curated `1to1` gate, not a broad feature sweep; do not author a guessed codec before D-234-07 |
| TC-234-02 | Every approved policy/state field round-trips only in encrypted inner v1/v2 payloads; unknown versions/modes follow the approved fail behavior and outer routing stays private. | `test/features/conversation/domain/models/private_media_policy_test.dart::approved policy codec is inner-only versioned and legacy-safe` | evidence-gated host domain / approved D-234-01/07 matrix | HEAD causal gap: fields absent -> GREEN expectations become exact only after modes/version/fallback are approved | leak policy into outer envelope, drop a state field, or change unknown-mode fallback -> TC-234-02 red after decisions | `flutter test test/features/conversation/domain/models/private_media_policy_test.dart --plain-name 'approved policy codec is inner-only versioned and legacy-safe'`; reserve AUTO + both 1:1 arrays; blocked by D-234-01/07 |
| TC-234-03 | A freshly conflict-checked DB vNEXT extends the shared production registry, preserves the complete then-current chain including plan-228 owner/local-state artifacts, adds only approved constrained lifecycle state, and survives fresh/upgrade/run-twice encrypted reopen. | `test/core/database/migrations/direct_private_media_lifecycle_migration_test.dart::approved vNEXT preserves owner scoped predecessor and adds lifecycle state idempotently` plus `integration_test/direct_private_media_lifecycle_sqlcipher_proof_test.dart` | evidence-gated host structure + Android/iOS real `sqflite_sqlcipher`, predecessor collision/unresolved fixture | HEAD evidence gap: no version/schema is allocated -> after D-234 approval/fresh ledger check, exact PRAGMA/default/check/index, same-ID direct/group and unresolved preservation, actual registry arms, fresh/full chain, close/reopen, and second run pass | recreate callbacks outside the shared registry, omit a guard/arm, reclassify an unresolved row, lose a sibling row, or fail rerun -> TC-234-03 red after refresh | `flutter test test/core/database/migrations/direct_private_media_lifecycle_migration_test.dart` plus dedicated Android/iOS commands; reserve one exact `1to1` device discovery record only after D-234-01..03/07 and vNEXT allocation |
| TC-234-04 | Sender composer exposes exactly the approved modes for eligible image/video, rejects invalid combinations, and previews recipient-visible clock/copy truthfully. | `test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart::composer enforces approved private media modes and copy` | evidence-gated widget / approved mode-duration matrix | HEAD causal RED: no mode UI -> exact keys, invalid-state non-dispatch, and payload policy pass after D-234-01/02 | allow a disallowed type/mode combination or send stale prior selection -> TC-234-04 red | `flutter test test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart`; reserve AUTO + both 1:1 arrays; blocked by D-234-01/02 |
| TC-234-05 | Receive persists policy/state before notification and download decisions; duplicate/retry delivery cannot downgrade or restart a private lifecycle. | `test/features/conversation/application/chat_message_listener_private_media_test.dart::receive commits private policy before preview download and duplicate handling` | evidence-gated host application / ordered repository, notification, downloader fakes | HEAD causal RED: listener has no policy -> approved event order and call counts become exact after D-234-03/06 | notify/download before commit or overwrite stricter state with duplicate input -> TC-234-05 red | `flutter test test/features/conversation/application/chat_message_listener_private_media_test.dart`; reserve AUTO + both 1:1 arrays; blocked by D-234-03/06/07 |
| TC-234-06 | Save, Files, external Share, internal Forward, bookmark/library, and PiP capabilities fail closed in every approved protected/consumed/expired state, including non-viewer entry points and owner-collision fixtures. | `test/features/conversation/application/private_media_action_eligibility_test.dart::private lifecycle gates owner scoped egress forward library and pip paths centrally` | Session-04 accepted host application / central matrix, direct-call spies, SQL fixtures, same-message-ID direct/group/unresolved rows | Causal missing-API RED plus initial-QA version-1-ordinary RED -> final policy 8/8, boundary 8/8, zero forbidden calls, SQL-before-`LIMIT`, guarded bookmark, viewer denial, and typed PiP denial; only canonical exact direct ordinary rows qualify | check only viewer buttons, accept unresolved/group ownership, mutate the same-ID group sibling, or claim exported-copy revocation -> TC-234-06 red | Both causal suites are in both 1:1 arrays and gate docs; final curated `1to1` 1,901/1,901; Session-04 final QA accepted after `fix_passes=1` |
| TC-234-07 | Opening/consuming follows the approved atomic transition exactly once, closes/cleans approved local artifacts, and never reveals bytes after the terminal state. | `test/features/conversation/application/consume_private_media_use_case_test.dart::approved consume transition is atomic exactly-once and cleanup-safe` | evidence-gated host integration / real temp files + transactional repository fake | HEAD compile RED: use case/state absent -> exact transition, callback, cleanup, rollback, and sibling preservation follow D-234-02/03/08 | mark consumed before successful open, consume twice, delete a sibling/export, or leave bytes after terminal state -> TC-234-07 red | `flutter test test/features/conversation/application/consume_private_media_use_case_test.dart`; reserve AUTO + both 1:1 arrays; blocked by D-234-02/03/08 |
| TC-234-08 | Restart, crash between approved transition steps, duplicate delivery, and send retry converge without resurrecting consumed/expired media or reminting receipt identity. | `test/features/conversation/integration/private_media_restart_replay_test.dart::restart duplicate and retry converge on approved terminal lifecycle` | Session-03 accepted host integration / real repository reopen and crash checkpoints; Session-04 preservation through the curated direct gate | Causal lifecycle RED/GREEN and restart 2/2 prove deterministic non-resurrection; Session-04 retained the same parent authority and guarded private download path, with full download 68/68 and curated `1to1` 1,901/1,901 | omit persisted checkpoint, accept stale duplicate, mint a receipt, or bypass terminal state through action/download authority -> TC-234-08 red | Registered in both 1:1 arrays; Session-03 closure remains accepted and Session-04 introduced no lifecycle/schema rewrite |
| TC-234-09 | Expiry starts from the approved clock, handles offline/clock skew/background/resume exactly, sweeps once, and displays truthful remaining/expired state. | `test/features/conversation/application/private_media_expiry_scheduler_test.dart::approved clock expires once across restart skew and resume` | evidence-gated host application / fake monotonic+wall clocks, lifecycle, repository reopen | HEAD compile RED: policy/scheduler absent -> exact boundaries and no early/late resurrection pass after D-234-02 | use only device wall clock, reset timer on reopen, or run duplicate cleanup -> TC-234-09 red | `flutter test test/features/conversation/application/private_media_expiry_scheduler_test.dart`; reserve AUTO + both 1:1 arrays; blocked by D-234-02/03 |
| TC-234-10 | Foreground/local/push notifications expose only the approved generic metadata and never private caption, thumbnail, bytes, mode, expiry, or consume state. | `test/core/notifications/private_media_preview_policy_test.dart::private media preview is consistently redacted across local and push paths` | evidence-gated host unit/application / local and push fixtures | HEAD partial RED: current preview may use caption/type -> approved generic body and no forbidden fields after D-234-06 | reuse ordinary caption preview in one path or serialize policy into notification payload -> TC-234-10 red | `flutter test test/core/notifications/private_media_preview_policy_test.dart`; reserve the focused command + both 1:1 arrays after refresh; blocked by D-234-06 |
| TC-234-11 | Android/iOS apply only approved screenshot, recording, app-switcher, and PiP controls while the private route is visible, restore ordinary routes afterward, and disclose platform limits. | `integration_test/direct_private_media_platform_protection_proof_test.dart` | availability-bounded automated route/native proof plus exact Kotlin/XCTest ownership suites on each applicable discovered platform | Causal missing-native-seam RED -> Android route-scoped prevention and restoration, iOS detection/cover/dismissal/restoration, View Once/protected/disappearing/unsupported route truth, and typed PiP denial | leave secure state enabled globally, permit PiP, fail to cover/dismiss, publish before protection, or claim iOS prevention -> TC-234-11 red | accepted in Session 05: Android native 5/5, iOS native 4/4, Android Pixel 6 `21071FDF600CSC` proof 1/1, iOS simulator `DBE8C32E-9F19-4593-860A-B41113791D79` proof 1/1; final QA accepted after `fix_passes=3`; separate closure review accepted |
| TC-234-12 | If account-wide/single-use behavior is approved, two devices and the real relay converge on one consumption result, enforce approved offline/replay rules, and never reserve bytes; otherwise this row explicitly records local-only truth. | `integration_test/direct_private_media_multi_device_real_harness.dart::approved view lifecycle converges across two direct peers and relay` | conditional paired-device real-relay proof / one USB physical Android + one Android emulator, fully automated, plus relay media state | HEAD has no receipt/single-use API. GREEN is intentionally undefined until D-234-03/05 selects local-only versus relay-authoritative behavior | replay a fetch/receipt, consume on both devices, or continue serving after approved revocation -> TC-234-12 fails when global enforcement is selected | Register/run under `1to1` only if D-234-03/05 select global enforcement; otherwise mark N/A with approved local-only product copy and no Go claim |
| TC-234-13 | Ordinary direct images/videos retain current encrypted send/receive, notification, download, viewer, retry, save/share/forward, and deletion behavior. | `test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart` plus direct media/action sentinels | Accepted `GREEN sentinels` / existing host fixtures and exact canonical direct viewer fixtures | Ordinary direct/group preservation remained green across action 4/4, Forward 3/3, batch/library 8/8, SQL/repository 41/41, download 68/68, presentation/Forward 13/13, Shared Media/viewer 12/12, typed viewer 4/4, and curated `1to1` 1,901/1,901 | route all media through private cleanup/redaction or change ordinary defaults -> sentinel red | Retain the focused Session-04 command set plus curated `1to1`; no per-session full `host-all` was run or required |
| TC-234-14 | The direct private slice changes no group/announcement payload or permissions and contains no Go/relay edits unless a separately accepted transport plan owns them. | `test/features/conversation/application/direct_private_media_boundary_test.dart::private media remains direct-scoped and transport-plan isolated` | Session-04 accepted host source-contract / forbidden imports, ownership collisions, and literal path guard | Missing-API boundary RED -> final boundary 8/8 and transport sentinels green; scope output remained only the authorized pre-existing version/registry and two group-repository paths, with no attributable Go/relay/native/group/announcement/Plan-243 change | import group publisher, change a baseline Go/relay path under this plan, or reuse direct policy silently in announcements -> TC-234-14 red | Both causal suites are in both 1:1 arrays/docs; final scope/diff/static gates and independent QA accepted |

### Test Notes

- TC-234-02..12 are obligations, not permission to guess expected values. Their exact fixtures/assertions must be refreshed after D-234-01..08; until then, writing production or theatrical RED tests is prohibited.
- TC-234-03 reserves no DB number. Refresh must first allocate a free vNEXT, then name every column/default/check/index, both registry arms, prior/full-chain fixture, and real SQLCipher before/after/run-twice assertions.
- TC-234-11 must distinguish prevention, detection, obscuring, and disclosure per platform. A test that only checks a Dart boolean cannot close screenshot/recording/PiP behavior.
- TC-234-12 is not optional if product copy promises cross-device or relay-authoritative single-use. Local-only copy makes the paired-relay row explicitly N/A instead.

### Historical Implementation Steps

1. Do not implement. Obtain written decisions D-234-01..08, platform feasibility evidence for D-234-04, and a product statement choosing local-only versus account/relay-authoritative consumption.
2. Refresh this plan: enumerate the state machine/events, exact inner-wire fields/version fallback, action matrix, notification copy, and closure profile. If schema is required, check the then-current ledger, allocate a free DB vNEXT, and only then specify its exact migration.
3. If D-234-03/05 require Go/relay enforcement, create and independently review an isolated transport plan; keep its migrations/protocol/device tests out of this UI/local plan.
4. Run `$tdd-review` on the refreshed plan(s). Only after an execution-ready verdict, author the chosen causal REDs before production edits.
5. Implement domain/persistence/receive/notification/eligibility first, then atomic consume/expiry/UI, then native protection and any separately owned relay contract.
6. Register dedicated host/device proofs, run preservation gates and representative mutations, and accept only the approved platform/relay closure.

### Historical Risks And Blind Spots

- False privacy claims are worse than a missing feature -> D-234-03..05 and TC-234-11/12 force local/platform/relay truth to match copy.
- Unknown/legacy clients can downgrade policy -> D-234-07 and TC-234-01/02.
- Notification or auto-download can leak before policy persistence -> TC-234-05/10.
- Lifecycle / derived-state durability: TC-234-03/08/09 require encrypted reopen, crash checkpoints, and clock/lifecycle reconstruction.
- Sibling-surface consistency: TC-234-06 checks viewer, bubble, library, bookmark, Forward, and native egress through one central eligibility matrix.
- Destructive-action side effects: TC-234-07 proves exact approved cleanup plus rollback, sibling, and exported-copy preservation.
- Invariant re-verification under new transitions: every open/resume/retry/duplicate/clock/device receipt rechecks terminal state before byte access in TC-234-07..12.

### Historical Gate Cadence

- This evidence-gated draft does not authorize broad host sweeps. After the decision refresh, per-plan closure is the approved focused lifecycle tests, exact direct-media sentinels, the curated `1to1` gate, and every selected device/SQLCipher/relay proof.
- `feature-host-all`, `core-host-all`, and full `host-all` are not individual Plan-234 closure gates; any new core notification or migration test runs by exact command here.
- Full `host-all` is not a Plan-234 gate. Under the current rollout exclusions,
  it runs at final included-Wave-1 closure after Plan 238.

### Historical Acceptance Gates

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

### Historical Device/Relay Proof Profile

- Profile status: decision-blocked. No device/relay command currently closes the feature because D-234-01..08 do not define what must be observed.
- Required if the refreshed plan allocates DB vNEXT/native protection: run real SQLCipher persistence and platform capture/background/PiP proof on each applicable Android/iOS target available at execution. Pin explicit discovered target IDs; unavailable platform legs are `N/A (target unavailable by project policy)` and retain host/native proof.
- Conditional real-relay branch: if D-234-03/05 promise account-wide or relay-authoritative single use, require two direct peers on one pinned USB physical Android plus one pinned Android emulator, a fully automated no-user-taps harness, a real relay/media service, deterministic consume/replay coordination, and retained relay/server logs that expose no media/caption/key. A separate transport plan must own any Go/protocol edits; do not use an iPhone merely as the second peer.
- Local-only branch: if approved copy explicitly says consumption is device-local, paired-relay proof is N/A; host retry/restart plus local proof on each applicable available platform closes only that narrower claim.
- Required setup after refresh: approved policy fixtures, clean/upgrade encrypted DBs, controllable foreground/background/clock states, capture/recording operator checklist, and explicit offline/replay scenario. Exact accounts/relay credentials remain undefined until D-234-03/05.
- Registration: dedicated files only — `direct_private_media_lifecycle_sqlcipher_proof_test.dart` and `direct_private_media_platform_protection_proof_test.dart` get exact `1to1` discovery records. Do not classify a broad unrelated capability file.
- Closure outputs: per-platform SQLCipher PRAGMA/before-after/reopen/run-twice evidence; per-platform screenshot/recording/app-switcher/PiP observation; and, only when selected, paired-device consume/replay/relay evidence.
- Current availability observation: the 2026-07-09 device snapshot is historical only. Re-resolve the live matrix at execution; unavailable mobile targets are N/A, and evidence decisions—not a missing model/OS version—are the current blocker.

## Final Accepted Execution And Done Criteria

- Expected RED: every owned implementation/proof slice retained its recorded
  causal RED before GREEN; Session 06's evaluator ends at `84/84`.
- Green sentinel: ordinary direct encrypted media round trip, dedup/retry,
  viewer, notification, download, Forward/library, and local-delete behavior
  remained green through the accepted sessions.
- Dirty tree: every session used scoped hashes/manifests and preserved unrelated
  edits; no clean-tree claim is made.
- Environment blocker: none. Availability-bounded Android/iOS evidence passed
  on the explicit accepted targets.
- Scope drift: none attributable to Plan 234. DB v100 remains exclusive to this
  plan; Plan 238 retains v101; no Go/relay, group/announcement, or actual-PiP
  production change is attributed to Session 06.

- [x] D-234-01..08 are written, mutually consistent, and mapped to every affected action/surface.
- [x] The state machine, encrypted-inner codec, DB v100 schema/migration, and legacy/unsupported fallbacks are exact and proven.
- [x] Platform claims distinguish prevention, detection, and obscuring and pass on every applicable available target.
- [x] Device/install-local consumption is the one explicit closure profile; relay/account-wide claims remain N/A.
- [x] Every approved behavior has causal proof and ordinary media sentinels remain GREEN.
- [x] New host/device proof is registered only in the owning 1:1 inventories and exact discovery records.
- [x] Scoped analysis/format, script syntax, `git diff --check`, and protected-scope comparison pass. The external `1to1` success is user-attested without an available count/log; no `run_test_gates.sh` command was rerun under the user's explicit direction.
- [x] Scope Contract And Guard is respected.

### Session 03 Accepted Checkpoint

- Session 03 is `closed` for its host-only lifecycle scope: transactional CAS/lease transitions, monotonic high-water expiry, retryable exact-direct cleanup, download/eviction/delete race authority, replay suppression, restart recovery, and foreground expiry scheduling.
- `B1` was replaced with causal RED/GREEN proof. Final evidence includes SQL 14/14, scheduler 11/11, download 66/66, restart 2/2, all remaining direct/preservation commands, curated `1to1` 1,875/1,875, host inventory 78, completeness 1,164/1,164, green scoped formatter/analyzer/diff/scope guards, and accepted final QA after `fix_passes=1`.
- Exactly one post-QA incremental Graphify refresh passed, and no Session-03-owned source or test is newer than that refresh. Session-03 residuals, blockers, and follow-ups are none.
- The accepted boundary is device/install-local and host-only for this session. No schema/v101, native protection, Go/relay authority, action/library/egress/PiP enforcement, or device/program-closure claim landed here.
- At that historical checkpoint the source-wide boxes remained open; the final
  accepted criteria above now supersede that interim status.

#### Session 03 Post-Closure Proof Repair

- A repeatedly reproduced timeout-fixture race during Plan-247 Session-04
  acceptance concretely reopened only Session 03's download/late-scrub proof.
  The first polling candidate was independently rejected; the final optional
  `latePrivateTransferScrubDelay` seam preserves the exact production default
  while making the fake's post-write timeout causal.
- Final repair evidence is exact `10/10`, download+cleanup `83/83`, curated
  `1to1` `1,963/1,963`, groups `1,951/1,951` plus Go, inventory `88`,
  completeness `1,179/1,179`, and clean formatter/analyzer/diff checks.
  Independent QA accepted at `post_closure_fix_passes=2`, followed by exactly
  one additional post-QA incremental Graphify refresh (`48,201` nodes,
  `74,809` edges; overlay `1,272` / `12,419` / `959`).
- Historical `fix_passes=1` and the original Session-03 closure evidence remain
  unchanged. Session 03 is again accepted/closed; no default product behavior,
  schema, transport, native/device, or later-session ownership changed. A
  separate read-only Closure Reviewer accepted the synchronized repair record
  with no documentation blocker.

### Session 04 Accepted Checkpoint

- Session 04 is `closed` for its host-only direct capability scope: one exact-current parent/attachment decision now governs Save/Files/Share, Forward, bookmark, Shared Media/batch, explicit download, generic quote/Info/Delete capability, ordinary viewer entry, and typed PiP denial.
- Initial independent QA found `B1`: version-1 ordinary could bypass the central matrix while SQL/bookmark correctly required canonical version 0. Fix pass 1 added two causal REDs, aligned the central predicate to version 0/null duration, and passed the combined causal suites 16/16. Final QA accepted with no `B`/`N` finding.
- Final evidence includes policy 8, boundary 8, action 4, Forward 3, batch/library 8, SQL/repository 41, download 68, presentation/Forward 13, Shared Media/viewer 12, typed viewer 4, curated `1to1` 1,901/1,901, host inventory 80, completeness 1,166/1,166, and green formatter/analyzer/diff/scope gates.
- Exactly one post-QA incremental Graphify refresh passed; no Session-04 code/test is newer than the refresh. Session-04 residuals, blockers, and follow-ups are none.
- No actual PiP, schema/v101, native/device, Go/relay, group/announcement, or
  Session-05/06 work was claimed at that checkpoint; the later accepted
  Session-05/06 rows now supersede its interim dependency status.

### Session 05 Accepted Checkpoint

- Session 05 has final independent-QA acceptance for the dedicated direct private route, exact retained lifecycle/lease authority, native-before-render protection, first-raster truth, privacy-minimized UI, serialized native ownership, Android `FLAG_SECURE`, and truthful iOS capture/app-switcher behavior.
- QA chronology is explicit: initial B1-B10 rejection and fix pass 1; remaining B3/B7 rejection and fix pass 2; deeper overlapping-unpublished-owner B7 and causal fix pass 3; final verdict `ACCEPTED`. `fix_passes=3` exceeds the original two-pass forecast/limit through one recorded causally bounded controller exception.
- Final evidence is direct viewer `16/16`, coordinator `9/9`, typed viewer/boundary `8/8`, preservation `23/23` + `16/16` + `16/16`, fresh download `68/68`, received actions `11/11`, l10n `2/2`, Android native `5/5`, iOS native `4/4`, Android/iOS device proof `1/1` each, curated `1to1` `1,935/1,935`, host inventory `83`, completeness `1,170/1,170`, and green static/scope gates.
- Final Graphify impact reconciles 22 exact inputs: 21 Session-05-attributable production deltas, including EN/DE/AR and `android/app/build.gradle.kts`, plus unchanged Session-04 preservation dependency `media_viewer_item.dart`. Exactly one post-QA incremental refresh passed; no production or test file is newer than the refreshed TDD overlay.
- The root `info.plist` record is truthfully reconstructed to the last-known pre-Session-05 hash because no exact execution-start hash exists. No migration/v101, actual PiP, Go/relay, group/announcement, Plan-247 implementation, or Session-06 work is claimed.
- Separate read-only Closure Reviewer accepted all 21 criteria with no unresolved finding. That checkpoint released the later work recorded in Session 06; its old interim controller status is historical.

### Session 06 Accepted Checkpoint

- Session 06 is accepted for whole-contract, acceptance-only proof. Its final
  artifact SHA-256 is
  `85423546027053fe3d44da0f2cb46660ef997fc02ceda76fa3f9fd6a8dfb6233`;
  the final protected manifests are byte-identical at
  `9fa73691afcc5772d083423a46a7def50d1742cf097cce11877f1c7641208a13`
  (`2,069,571` bytes; `cmp=0`).
- Focused/native/device/registration/static evidence is green with the exact
  counts in the Session-06 ledger row. Independent QA accepted after honest
  `fix_passes=2`; the theatrical artifact and invalid one-second fixture are
  superseded with no closure credit.
- The Android pair is device/install-local app-layer proof only. It does not
  prove live relay transport, global consume, remote revocation, actual PiP,
  or two rendered protected sessions.
- The `1to1` gate is user-attested external success; this QA did not observe
  it and its exact count/log is unavailable. No `run_test_gates.sh` command was
  rerun here. Session 06 added no production delta and correctly performed no
  Graphify refresh.

## Handoff

- Plan 234 is closed; reopen only for a concrete regression in D-234-01..08,
  the accepted session boundaries, registration integrity, or truthful
  platform/device-local behavior.
- Plan 238 is next and exclusively takes sequential DB v101 while preserving
  all v100 values, checks, indexes, migration ordering, and direct-lane
  behavior byte-for-byte.
- Plans 242, 243, 248, 254, 241, and 253 remain excluded. No excluded plan is a
  dependency of this closure or of final included-Wave-1 acceptance.
- Wave-level `host-all`, availability-bounded required device proof,
  documentation synchronization, and the final Graphify refresh completed on
  2026-07-12. The aggregate runner exercised all `1,130` commands (`1,125`
  initial passes); the exact five-file post-fix rerun passed `53/53`.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-12 | Session 06 / Plan-234 closure accepted | Session-06 proof/plan; source; breakdown; index; stable closure reference | Independent QA and separate Closure Review `ACCEPTED` with zero findings; current protected manifests `907c422…36562`, 2,072,461 bytes, `cmp=0` | Criteria 84/84; final artifact `854235…6233`; focused/native/device/static evidence green; external `1to1` success user-attested without an available count/log; `fix_passes=2`; no attributable production delta or Session-06 Graphify refresh | No Plan-234-owned blocker, residual, or follow-up; stable Closure Audit persisted. | Begin Plan 238 at sequential DB v101. |
| 2026-07-12 04:58 CEST | Session 03 post-closure proof repair accepted | `download_media_use_case.dart`; its direct download test; Session-03/source/breakdown ledgers; Graphify overlay | Fresh independent QA `ACCEPTED`; exactly one additional post-QA incremental refresh passed | Repeated timeout-proof race resolved causally; exact 10/10, download+cleanup 83/83, 1to1 1,963/1,963, groups 1,951/1,951 plus Go, host 88, completeness 1,179/1,179, static checks green; `post_closure_fix_passes=2` | Production defaults and lifecycle semantics unchanged. Session 03 remains accepted/closed; Plan 247 Session 04 must restart from a fresh baseline. | Recapture Plan-247 Session-04 immutable baseline and rerun every literal acceptance gate. |
| 2026-07-11 | Session 05 closure accepted | Session-05 plan; source/breakdown; current code/tests/gates/native artifacts; graph timestamps | Separate read-only Closure Reviewer `ACCEPTED` all 21 criteria | No unresolved finding; honest `fix_passes=3`; one refresh; 21 attributable deltas plus one unchanged impact dependency; Sessions 01-04 remain closed | Session 05 is closed. Overall Plan 234 remains `implementation-in-progress`; only Plan 247 Session 03 is released. | Execute Plan 247 Sessions 03-04 before planning Plan 234 Session 06. |
| 2026-07-11 21:22 CEST | Session 05 QA acceptance / closure writing | Session-05 plan; Graphify impact over 21 attributable deltas plus one unchanged preservation dependency; post-QA architecture refresh; this source ledger; breakdown | Final independent QA `ACCEPTED` after honest `fix_passes=3`; exactly one post-QA incremental refresh passed | Focused/native/device/named/static/scope evidence green; curated `1to1` 1,935/1,935; host inventory 83; completeness 1,170/1,170; no owned code/test newer than refresh; reconstructed `info.plist` uncertainty recorded | No behavioral blocker. Stable closure and dependency release await separate read-only Closure Reviewer acceptance. Overall Plan 234 remains `implementation-in-progress`. | Review synchronized Session-05 plan/source/breakdown; if accepted, close Session 05 and release only Plan 247 Session 03. |
| 2026-07-11 17:55 CEST | Session 04 closure accepted | Session-04 plan; session breakdown; this source execution ledger/checkpoint | Final QA `accepted` after `fix_passes=1`; exactly one post-QA incremental Graphify refresh passed | B1 causal RED/GREEN resolved; all focused commands green; curated `1to1` 1,901/1,901; host inventory 80; completeness 1,166/1,166; static/scope guards green; no owned code/test newer than refresh | No Session-04 blocker, residual, or follow-up. Overall Plan 234 remains `implementation-in-progress` for Sessions 05-06. | Refresh and execute Session 05 as the sole next runnable session; do not reopen Sessions 01-04 absent a real regression. |
| 2026-07-11 16:19 CEST | Session 03 closure accepted | Session-03 plan; session breakdown; this source execution ledger/checkpoint | Persisted final QA `accepted` after `fix_passes=1`; exactly one post-QA incremental Graphify refresh passed | Session-03 causal/direct/preservation evidence green; curated `1to1` 1,875/1,875; host inventory 78; completeness 1,164/1,164; static/scope guards green; no owned source/test newer than refresh | No Session-03 blocker, residual, or follow-up. Overall Plan 234 remains `implementation-in-progress` for Sessions 04-06. | Plan and execute Session 04 as the sole next runnable session; do not reopen Sessions 01-03 absent a real regression. |
