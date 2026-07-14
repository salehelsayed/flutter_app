# Plan 238 — Group Private Media Lifecycle Session Breakdown

Status: execution-ready

## Decomposition Progress

| Time | Phase | Evidence inspected | Current result | Next action |
|---|---|---|---|---|
| 2026-07-11 | Evidence Collector | Anchored Graphify TDD query; `GroupMessage`, `GroupMessagePayload`, group send/listen/offline paths, owner-scoped media helpers, group received-media policies/viewers/library, DB version/registry, group gate/discovery scripts, regression/gate docs, Plan 234 parity boundary, group closure reference and stable matrix | HEAD is DB v99 and has no lifecycle state. Current media actions are centralized enough to extend, encrypted `extra` is the narrow wire seam, and `owner_lane='group'` is already mandatory. No relay/node protocol work is required for a truthful device-local policy. The architecture graph was anchored but stale, so load-bearing conclusions were verified in source. | Map a privacy-safe local-only closure contract and reserve v101 without crossing Plan 234 v100. |
| 2026-07-11 | Closure Mapper | Plan 238 evidence ledger, Plan 234 lane-parity boundary, current group role/action/replay/notification/platform seams | Every ledger row can be resolved without external authority by choosing a narrow device-local contract and truthful wording. No relay revocation, cross-device consume event, moderator bypass, or universal screenshot claim is accepted. | Split schema/wire, lifecycle engine, surfaces/native safeguards, and independent acceptance into the minimum verified sessions. |
| 2026-07-11 | Session Splitter | Accepted decision contract, v101 ownership, TC-238-00..16, current group gate and real-boundary registrations | Four sessions are the minimum safe split: foundation/wire, durable lifecycle engine, user/privacy surfaces, then cross-session device acceptance and closure. | Run a strict sufficiency review for hidden coupling, missing tests/gates, and plan-path hygiene. |
| 2026-07-11 | Reviewer | Complete four-session ledger, code/test/gate ownership, accepted privacy decisions, migration/device contracts | Count is sufficient and paths are doc-scoped. One structural gap was found: Session 238-01 could otherwise expose authoring before lifecycle/surface enforcement. Required fix: central availability remains off through 238-02, receipt is fail-closed, and 238-03 enables only after all adapters are GREEN. Sender staging/no-auto-download tests were also made explicit. | Patch once, then run final arbiter check. |
| 2026-07-11 | Arbiter | Patched breakdown and reviewer questions | No structural blocker remains. No merge or further split has independent verification value. The four-session sequence, v101 prerequisite, accepted local-only policy, selected gates, and closure ownership are safe for the downstream rolling pipeline. | Wait for accepted Plan 234 v100, then plan Session 238-01 only. |

- Source doc: `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan.md`
- Intended breakdown: `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan-session-breakdown.md`
- Current role: Arbiter complete; reusable downstream breakdown
- Device policy: generic two-peer proof uses physical Android `21071FDF600CSC` plus Android emulator `emulator-5554`; unavailable targets are `N/A (target unavailable by project policy)`.
- Production-code status: untouched by this decomposition.

## Evidence Digest

- `lib/core/database/app_database_version.dart` and both production registries
  now end at landed DB v100. Plan 234 is accepted/closed and owns v100; this
  plan exclusively reserves sequential v101 as
  `101_group_private_media_lifecycle.dart`. No competing v101 exists.
- `lib/features/groups/domain/models/group_message.dart:1-188` persists group metadata but no private policy/state; media remains a separately loaded `media_attachments` relation.
- The live encrypted-extra path is map-based:
  `send_group_message_use_case.dart` -> `bridge_group_helpers.dart` -> narrow Go
  bridge parameters -> generic node encrypted extras -> live listener/offline
  drain/handler. `GroupMessagePayload` is test-only and is not load-bearing.
- `lib/features/groups/application/group_received_media_action_policy.dart:6-56`, `lib/features/groups/presentation/screens/group_conversation_wired.dart:4990-5121`, and `lib/features/groups/presentation/screens/group_shared_media_library_screen.dart:402-667` are existing centralized action/viewer/library seams that can fail closed before dispatch.
- `lib/core/database/helpers/media_attachments_db_helpers.dart` already enforces owner-lane guarded group writes/download transitions. Private cleanup and replay guards must preserve same-ID direct siblings and reject `unresolved` rows.
- `scripts/run_test_gates.sh` owns the curated `GROUP_TESTS` inventory and exact Go encrypted-extra sentinel; `scripts/check_reliability_simulation_discovery.sh` owns device classification.
- `Test-Flight-Improv/14-regression-test-strategy.md` requires focused causal regressions plus the affected named subsystem gate. `Test-Flight-Improv/test-gate-definitions.md` makes the script authoritative and bounds device proof to currently available targets.
- Stable closure records already exist at `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md` and `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`; no new matrix is needed.

## Overall Closure Bar

After all Plan 238 sessions finish, an eligible discussion-group writer can send one private image or video as protected-only, view-once, or disappearing media. Every receiver durably learns the policy before notification, download, decode, or render; view-once and expiry become terminal before cleanup; restart/replay cannot restore access; all non-permitted action, thumbnail, library, notification, and PiP entry points fail closed; ordinary/legacy group and announcement media remain unchanged. Product copy states that enforcement is per device, does not revoke relay or exported copies, and cannot universally prevent iOS screenshots. The v101 migration follows Plan 234 v100, exact focused/Go/native/device/static evidence passes, the user-directed curated-gate exception is recorded without invented evidence, final included-Wave-1 `host-all` passes, and the selected SQLCipher/real-bridge/Android-pair/Android+iOS native proofs are persisted on currently available explicit targets.

## Accepted Decision Contract

These choices are the implementation authority for the first downstream session. That session must replace every `unresolved` row in the source plan with these decisions, names, wording, proof profile, date, and owner before authoring production behavior.

| Evidence-ledger row | Accepted Plan 238 decision |
|---|---|
| Policy granularity | Private policy is message-scoped and permitted only when a message has exactly one image or video attachment, no mixed ordinary/private attachments, no caption/text, no quote, and no Forward provenance. Ordinary messages retain existing multi-attachment behavior. Wire policy v1 has `lifecycle = standard | viewOnce | disappearing` plus `protected`; `viewOnce` and `disappearing` normalize `protected=true`; `standard+protected` is protected-only. |
| Author/admin eligibility | Every active discussion-group member whose current role/membership grants ordinary write permission may select any approved private mode. Eligibility is revalidated at selection, dispatch, automatic retry, and manual retry. Revocation makes a queued private send fail `unauthorized` without publish/inbox fanout. Announcement/QA authoring is unchanged. |
| View-once boundary | Decode/decrypt must succeed first. The app then durably commits `consumed_at` immediately before the first image frame is exposed or video playback begins; a failed commit exposes no frame. Cancel-before-decode and decode failure do not consume. Because private messages contain one attachment, consumption is unambiguous. The current viewer may continue only until route exit, app background, capture response, or process loss; crash after commit stays consumed and cleanup resumes. |
| Expiry clock | Allowed disappearing durations are 1 hour, 24 hours, and 7 days. Incoming expiry is anchored to the receiver's durable local receipt; an offline late delivery receives the full chosen duration. Outgoing local state anchors when send/custody succeeds. UTC timestamps use an injected clock plus a persisted high-water `last_checked_at`; rollback beyond five minutes fails closed as unavailable until trusted time catches up, while forward jumps expire immediately. Expiry is durable before cleanup. User copy is “Expires on each device after it arrives.” |
| Device convergence | Consumption and expiry are deliberately device-local. No consumption receipt, sibling-device event, global “once,” or relay authority is added. Copy is “View once on this device”; each receiving device can have one local view. The Android physical+emulator proof must demonstrate this narrow behavior and same-device replay non-resurrection. |
| Moderation/report | Admins/moderators cannot reopen, bypass, or recover private bytes. Delete-for-me may remove the local placeholder. Reporting (Plan 245) may retain/send only existing message identity, sender/group metadata, timestamps, policy label, and integrity metadata; it must not recover or attach private bytes/captions. No special audit copy or moderation escrow is created. |
| Capture protection | Protected-only, view-once, and disappearing routes disable PiP. Android applies `FLAG_SECURE` only while the protected viewer is visible and shields task snapshots. iOS detects active capture/recording and blanks/pauses the viewer, shields app-switcher snapshots, and restores ordinary routes on exit; copy explicitly says iOS screenshots cannot always be prevented. A camera photographing another screen is outside the promise. |
| Blob/replay | Relay/blob retention and Go node protocol remain unchanged; no remote deletion/revocation is claimed. Private media never auto-downloads or produces a shared-library thumbnail. Explicit open may download/decrypt only after a fresh policy check into app-owned private storage. Durable consumed/expired/unsupported state blocks future ingest, download, decode, replay, and cache re-linking. Existing exported/external copies cannot be recalled. |
| Notification privacy | Foreground, background, and lock-screen notifications use the app title plus the generic body `New private media`; they expose no group, sender, caption, media subtype, mode, duration, thumbnail, path, or bytes and do not trigger download/decode. Opaque route identifiers may remain in the tap payload. |
| Unknown value | Absence of all policy fields is legacy ordinary media. An explicit unknown version/mode, malformed private combination, or invalid duration becomes durable `unsupportedPrivate`, shows only a generic unavailable placeholder, and cannot download, decode, notify content, enter Shared Media, or offer egress/forward/bookmark/PiP. It never falls back to ordinary. |

### Central capability matrix

| State | Open/download | Save/Share/Forward/Bookmark | Shared Media/thumbnail | Reply/Info/Delete for me | PiP |
|---|---|---|---|---|---|
| Ordinary legacy | Existing behavior | Existing behavior | Existing behavior | Existing behavior | Plan 243 ordinary policy |
| Protected-only, available | Explicit open only; app-private local copy | denied | excluded/no thumbnail | generic Info and Delete for me only | denied |
| View-once, unconsumed | Explicit open once; commit-before-first-frame | denied | excluded/no thumbnail | generic Info and Delete for me only | denied |
| Disappearing, unexpired | Explicit open while eligible | denied | excluded/no thumbnail | generic Info and Delete for me only | denied |
| Consumed/expired/unsupported/clock-invalid | denied; generic terminal placeholder | denied | excluded/no thumbnail | generic Info and Delete for me only | denied |

### Migration reservation

- Exclusive owner: Plan 238.
- Prerequisite: Plan 234 must land DB v100 first; the Plan 238 pipeline must verify the live registry still ends at v100 and stop on any competing v101 claim.
- Reserved migration: DB v101, `lib/core/database/migrations/101_group_private_media_lifecycle.dart`, structural test `test/core/database/migrations/101_group_private_media_lifecycle_test.dart`.
- Minimum message-scoped columns on `group_messages`: `media_policy_version`, `media_lifecycle`, `media_duration_seconds`, `media_protected`, `media_received_at`, `media_expires_at`, `media_last_checked_at`, `media_consumed_at`, `media_expired_at`, and `media_cleanup_pending`. Legacy defaults are policy version `0`, lifecycle `standard`, protected `0`, cleanup pending `0`, and nullable times/duration.
- Wiring: append v101 to `app_database_version.dart`, production create/upgrade
  registries, full-chain fixtures, and SQLCipher proof. Do not recreate Plan
  234 v100 or alter `owner_lane`. Excluded Plan 242 is not a dependency and
  receives no competing migration.

## Recommended Plan Count

Create **4** doc-scoped session plans.

## Decomposition Artifact

- Artifact: `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan-session-breakdown.md`
- Source: `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan.md`
- Downstream workflow rule: plan, execute/QA, and close one session at a time. Before planning any later session, refresh it against the code, schema, tests, device inventory, and closure evidence actually landed by all predecessors.
- Program ordering rule: no Plan 238 implementation starts before Plan 234 has accepted v100. Sessions 238-02 through 238-04 run strictly after the preceding Plan 238 session is accepted.

## Source Of Truth

- Product/privacy intent and original test inventory: `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan.md`.
- Binding conservative decisions for execution: `## Accepted Decision Contract` in this artifact until Session 238-01 writes them into the source plan.
- Dependency/migration order: user-requested Track A order; `lib/core/database/app_database_version.dart`; `lib/core/database/production_migration_registry.dart`; Plan 234 v100 ownership.
- Regression cadence: `Test-Flight-Improv/14-regression-test-strategy.md` and `Test-Flight-Improv/test-gate-definitions.md`; scripts win on disagreement.
- Stable closure/matrix docs: `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`, `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`, and `Test-Flight-Improv/00-INDEX.md`.
- Current architecture seams: the evidence-digest files plus direct tests named below. Graphify confidence was anchored but topology freshness was stale; current source verification governs.

## Session Ledger

| Session | Title | Classification | Intended plan file | Depends on | Initial status | Expected downstream run mode |
|---|---|---|---|---|---|---|
| 238-01 | Accepted policy, v101 persistence, encrypted wire, and safe-disabled authoring | implementation-ready | `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan-session-238-01-plan.md` | Accepted Plan 234 and landed DB v100 | execution-ready | `missing_implementation` |
| 238-02 | Durable consume, expiry, cleanup, and replay/download guards | prerequisite-blocked | `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan-session-238-02-plan.md` | 238-01 accepted | prerequisite-blocked | `missing_implementation` |
| 238-03 | Central capabilities, UI/notification privacy, and native safeguards | prerequisite-blocked | `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan-session-238-03-plan.md` | 238-02 accepted | prerequisite-blocked | `missing_implementation` |
| 238-04 | SQLCipher, real bridge, Android-pair/platform acceptance, and closure | prerequisite-blocked; acceptance-only | `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan-session-238-04-plan.md` | 238-03 accepted | prerequisite-blocked | `missing_evidence` |

## Ordered Session Breakdown

### Session 238-01 — Accepted policy, v101 persistence, encrypted wire, and authoring

- Classification: `implementation-ready`; Plan 234 is accepted/closed, the
  live DB head is exactly v100, and no competing v101 exists.
- Intended plan file: `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan-session-238-01-plan.md`.
- Exact scope:
  - Write the accepted decision table into Plan 238, remove every unresolved ledger state, replace `vNEXT`/conditional language with v101, and refresh test names/commands before RED.
  - Reserve and implement `101_group_private_media_lifecycle.dart` with the exact defaults/columns above, production create/upgrade/full-chain registration, run-twice behavior, and same-ID direct/group/unresolved preservation.
  - Add typed `GroupMediaLifecycle`, policy v1, local terminal-state decoding, legacy ordinary default, explicit unknown fail-closed state, and `GroupMessage` mapping/copy/equality coverage.
  - Add one central feature-availability seam. Until Session 238-03 has landed every enforcement surface, authoring stays disabled and received private/unknown policy stays a generic unavailable placeholder with zero download/decode/action calls. Do not expose a partially enforced private send.
  - Carry only `mediaPolicyVersion`, `mediaLifecycle`, `mediaDurationSeconds`, and `mediaProtected` in the existing encrypted group payload `extra`. A valid v1 tuple contains all four keys; non-disappearing duration is explicit JSON null, distinct from absence. Keep receipt/last-check/consume/expire/owner state local. Preserve absent fields and existing forwarded/media extras.
  - Add composer/presentation selection for one visual private attachment; reject caption, quote, Forward, mixed/multiple attachment, unsupported type, and invalid duration combinations.
  - Revalidate current discussion write permission before durable policy-bearing parent upload, dispatch, and every retry/re-drive; missing/empty/failed roster reads fail closed and revoked queued private sends become unauthorized without upload, publish, or inbox-store calls.
  - Own the minimum availability-off privacy shields now: suppress private notification derivatives/auto-download/ordinary viewer/actions, render a generic unavailable placeholder, exclude nonordinary parents in Shared Media SQL before `LIMIT`, and requalify stale cached bookmark/batch mutations atomically. Enabled/final notification/action/viewer UX remains Session 238-03.
  - Do not add consumer cleanup, final notification UX, native code, announcement UI, Go node changes, relay changes, or enabled Shared Media private representation.
- Why its own session: schema/model/wire/authoring form one compatibility boundary and must be stable before lifecycle transitions can safely persist. Its host structural REDs and Go no-leak sentinels differ from state-machine and UI/native proof.
- Likely code-entry files:
  - `lib/core/database/app_database_version.dart`
  - `lib/core/database/production_migration_registry.dart`
  - `lib/core/database/migrations/101_group_private_media_lifecycle.dart`
  - `lib/features/groups/domain/models/group_message.dart`
  - new `lib/features/groups/domain/models/group_private_media_policy.dart`
  - new `lib/features/groups/application/group_private_media_availability.dart`
  - `lib/features/groups/application/send_group_message_use_case.dart`
  - `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
  - `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
  - `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - `lib/core/bridge/bridge_group_helpers.dart`
  - `lib/core/database/helpers/media_library_db_helpers.dart` and the exact
    attachment bookmark mutation seam
  - `lib/features/groups/application/group_shared_media_library_controller.dart`
    plus its batch coordinator
  - live `group_conversation_screen.dart` / `group_conversation_wired.dart`
    shared-`ComposeArea` adapter; the dead `group_compose_area.dart` is excluded.
- Likely direct tests/regressions:
  - `test/core/database/migrations/101_group_private_media_lifecycle_test.dart` (TC-238-01 host structure/idempotence/owner collision)
  - `test/core/database/integration/full_migration_chain_test.dart`
  - `test/features/groups/domain/models/group_private_media_policy_test.dart` (TC-238-02)
  - existing `group_message_test.dart`; `group_message_payload_test.dart` is not
    accepted as live wire proof
  - existing `send_group_message_use_case_test.dart`, `retry_failed_group_messages_use_case_test.dart`, `retry_incomplete_group_uploads_use_case_test.dart`, and `retry_failed_group_inbox_stores_use_case_test.dart` with GPL-03 selectors
  - `test/features/groups/integration/group_private_media_payload_roundtrip_test.dart` (TC-238-04)
  - new composer widget test for private selection constraints
  - `test/features/groups/presentation/group_private_media_announcement_sentinel_test.dart` (TC-238-15)
  - `test/features/groups/integration/group_private_media_transport_boundary_test.dart` (TC-238-16)
  - a feature-availability regression proving disabled authoring plus fail-closed receipt until the enforcement stack is complete
  - exact pre-upload durability/strict-roster and stale-library bookmark/batch
    causal regressions named in the Session-238-01 plan
  - exact existing ordinary send/retry/live/offline/forward sentinels.
- Likely named gates:
  - causal RED/GREEN focused files above;
  - exact full-migration-chain host test;
  - `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge ./node -run 'GPL12|GK030' -count=1)` after adding only the narrow bridge mapping/test;
  - `run_test_gates.sh` is not invoked in this continuation under the user's
    explicit instruction; any external pre-change `groups` result is baseline-
    only and cannot be presented as post-change evidence;
  - scoped analyzer plus `git diff --check`; no `core-host-all`, `feature-host-all`, or full `host-all`.
- Docs/matrix update: source Plan 238 decision ledger, exact migration/test contract and execution progress; add new host tests to `GROUP_TESTS` and gate definitions as needed. Do not claim feature acceptance yet.
- Dependency: accepted Plan 234 v100. Stop if the current DB head is not v100 or another owner claims v101.
- Meaningful verified end state: policy v1 can be durably mapped/retried/live-offline decoded, but incomplete builds cannot author it and can only display an unavailable placeholder. The branch is compatibility-safe without making a partial privacy promise.

### Session 238-02 — Durable consume, expiry, cleanup, and replay/download guards

- Classification: `prerequisite-blocked` until 238-01 is accepted, then `implementation-ready`.
- Intended plan file: `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan-session-238-02-plan.md`.
- Exact scope:
  - Implement one owner-scoped lifecycle service/repository API for eligibility, receipt anchoring, high-water clock checks, commit-before-first-frame consume, expiry, and durable cleanup-pending convergence.
  - Make explicit-open download use an app-private path and fresh state/owner/integrity checks. Disable automatic download, thumbnails, and cache linking for all private policies.
  - On consume/expire, durably mark terminal first, dispose decoder/playback state, delete only app-owned private media/key/temp/thumbnail/progress artifacts, clear group attachment availability with guarded CAS, preserve the generic parent placeholder, and resume cleanup after crash/restart.
  - Clean sender-side app-owned staged plaintext after successful custody for every private mode while preserving retryability until success; never delete the external picker source. Terminal failed sends retain only the minimum app-private retry copy until Retry or Delete for me.
  - Reject or discard late live/offline/replay/local-media/download completion for consumed, expired, unsupported, clock-invalid, tombstoned, wrong-owner, or missing-parent state. A duplicate may never downgrade/reset a stricter local state.
  - Add lifecycle scheduling on app start/resume and relevant group screen/viewer refresh without broad polling.
  - No action-bar redesign, notification copy, native capture code, PiP implementation, relay protocol, or cross-device consume event.
- Why its own session: terminal-state atomicity and destructive cleanup have a different causal test family and rollback risk from codecs/UI. It must be independently restart-safe before surfaces can promise privacy.
- Likely code-entry files:
  - new group-private lifecycle policy/service/repository/helper files under `lib/features/groups/application/` and `lib/core/database/helpers/`
  - `lib/core/database/helpers/media_attachments_db_helpers.dart`
  - `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
  - group media download/link/retry seams and `lib/main.dart` startup/resume wiring
  - `lib/core/media/media_attachment_lifecycle_lock.dart`, `media_file_manager.dart`, and video thumbnail/playback cache seams only as needed.
- Likely direct tests/regressions:
  - `test/features/groups/application/group_private_media_lifecycle_test.dart` (TC-238-05)
  - `test/features/groups/integration/group_private_media_crash_recovery_test.dart` (TC-238-06)
  - `test/features/groups/application/group_private_media_expiry_test.dart` (TC-238-07)
  - `test/features/groups/integration/group_private_media_cleanup_replay_test.dart` (TC-238-08)
  - focused download/local-media completion tests for no resurrection
  - sender success/failure/retry staging cleanup tests and a receive-before-auto-download prohibition test
  - existing group media deletion journal/reconciler tests, `group_shared_media_eviction_test.dart`, incoming handler, listener, offline drain, and ordinary media download/integrity sentinels.
- Likely named gates:
  - focused causal lifecycle/restart/replay tests and exact existing cleanup/download sentinels;
  - focused causal and preservation commands; the current user-directed
    `run_test_gates.sh` skip is recorded without inventing a result;
  - scoped analyzer and `git diff --check`; no broad host family sweep/full host-all.
- Docs/matrix update: source Plan 238 TC-238-05..08 progress and actual lifecycle state-machine names; gate inventory for new group tests.
- Dependency: 238-01 accepted and schema/wire frozen.
- Meaningful verified end state: private bytes can be explicitly opened only while eligible; consume/expiry survives crash/replay and converges app-owned cleanup without touching ordinary/direct siblings.

### Session 238-03 — Central capabilities, UI/notification privacy, and native safeguards

- Classification: `prerequisite-blocked` until 238-02 is accepted, then `implementation-ready`.
- Intended plan file: `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan-session-238-03-plan.md`.
- Exact scope:
  - Feed current private state into one central capability projection used by bubble, viewer, info sheet, group received-media actions, Forward, bookmark, Shared Media query/cursor/selection/batch actions, egress requalification, thumbnails, playback resume, and the future Plan 243 PiP eligibility seam.
  - Exclude every private row from Shared Media at the repository query boundary, not just by hiding buttons. Keep generic placeholders in conversation history.
  - Implement protected/view-once/disappearing viewer transitions, commit-before-first-frame coordination, generic terminal/unsupported/clock-invalid copy, and current-route teardown on background/capture.
  - Enable the central feature-availability seam only in this session, after the action/library/notification/native guards and ordinary/announcement sentinels are GREEN.
  - Redact foreground/background/lock-screen notifications to the accepted app-title/generic body before any download/decode. Preserve opaque routing and ordinary notification behavior.
  - Add a scoped native privacy gateway: Android route-scoped `FLAG_SECURE` and task-snapshot protection; iOS capture observation with blank/pause plus app-switcher shielding. Restore ordinary routes and document truthful platform limits. Keep PiP disabled for private media; actual ordinary-video PiP belongs to Plan 243.
  - No relay revocation, screenshot-success claim, moderation escrow, announcement authoring/UI, or global app-wide secure flag.
- Why its own session: this is the cross-surface privacy and OS-boundary slice. Host capability/notification/widget regressions and native platform tests are materially different from destructive lifecycle persistence.
- Likely code-entry files:
  - `lib/features/groups/application/group_received_media_action_policy.dart`
  - `lib/features/groups/application/group_received_media_actions.dart`
  - `lib/features/groups/application/group_media_forward_policy.dart`
  - `lib/features/groups/application/group_shared_media_library_controller.dart`
  - media-library DB helper/query and bookmark/egress requalification seams
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
  - `lib/features/groups/presentation/screens/group_shared_media_library_screen.dart`
  - shared typed viewer protection/capability files
  - group notification construction plus core notification policy seam
  - new native privacy MethodChannel/gateway Dart files, Android activity/plugin files, iOS runner/channel files, and app lifecycle wiring
  - l10n ARB/generated files.
- Likely direct tests/regressions:
  - `test/features/groups/presentation/group_private_media_capabilities_test.dart` (TC-238-09) covering bubble/viewer/library/batch/dispatch owner collision and requalification
  - repository query test proving private rows never enter Shared Media
  - `test/features/groups/application/group_private_media_notification_test.dart` (TC-238-10)
  - viewer first-frame/background/route-restore widget tests
  - an enablement-order regression proving authoring cannot turn on before every registered enforcement adapter reports supported
  - native unit/channel tests for Android secure-window state machine and iOS capture/snapshot response
  - `integration_test/group_private_media_platform_proof_test.dart` implementation/harness (TC-238-11; real observations close in 238-04)
  - ordinary group/announcement action, library, notification, viewer, and batch sentinels.
- Likely named gates:
  - focused host/native tests and exact preservation sentinels;
  - exact discovery classification checks for the manual platform proof;
  - focused causal and preservation commands; the current user-directed
    `run_test_gates.sh` skip is recorded without inventing a result;
  - scoped analyzer and `git diff --check`; no per-session host-all.
- Docs/matrix update: source Plan 238 TC-238-09..11 progress; `test-gate-definitions.md` and discovery records for new exact paths. No final accepted verdict yet.
- Dependency: 238-02 accepted so surfaces cannot outpace terminal enforcement.
- Meaningful verified end state: every app/native entry point reflects current durable state and protects private routes without weakening ordinary or announcement behavior.

### Session 238-04 — SQLCipher, real bridge, Android-pair/platform acceptance, and closure

- Classification: `acceptance-only`, initially `prerequisite-blocked` until 238-03 is accepted.
- Intended plan file: `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan-session-238-04-plan.md`.
- Exact scope:
  - Resolve the live device matrix first and pin every command. Required known generic pair is USB Android `21071FDF600CSC` plus emulator `emulator-5554` if both remain available; re-resolve rather than assume. Use available Android and iOS target(s) separately for native protection/PiP-denial parity. Unavailable targets are N/A, never a blocker.
  - Run production-SQLCipher v100→v101 and fresh-chain close/reopen/run-twice proof on an available concrete target.
  - Run real Go bridge encrypted-extra proof and assert outer events/logs contain no policy/caption/media secret and Go node production remains unchanged.
  - Run fully automated physical-Android+emulator lifecycle proof: private send, generic notification, no auto-download, each device's independent one-time view, consume-before-frame evidence, same-device restart/replay non-resurrection, disappearing expiry, and no unintended cross-device consume event. This proves the accepted device-local wording, not global once.
  - Run route-scoped Android secure-window/task snapshot and available iOS capture-obscure/app-switcher restoration proof. Record screenshots/recording observations and platform limitations; do not claim universal prevention.
  - Rerun all Plan 238 focused tests, ordinary sentinels, exact Go leg,
    analyzer, discovery/list checks, and hygiene; record the user-directed
    curated-gate exception without claiming a run. Independent QA must
    counterexample unknown policy, stale UI capability, owner collision,
    replay/download race, clock rollback, capture route leakage, and ordinary/
    announcement preservation.
  - Persist final evidence and accepted/blocked verdict in Plan 238; update stable group closure/matrix docs, gate definitions, and `00-INDEX.md`.
- Why its own session: SQLCipher, real bridge, paired devices, and native platform observations validate interactions across all three implementation slices and require a clean acceptance role rather than more production scope.
- Likely code-entry files: no planned production changes; only bounded fixes for causal failures may return to owning prior seams. Test harness/discovery/docs are expected.
- Likely direct tests/proofs:
  - `integration_test/group_private_media_lifecycle_db_proof_test.dart` (TC-238-01D)
  - existing `integration_test/group_real_crypto_onboarding_test.dart` extended for GPL-12
  - `integration_test/group_private_media_convergence_proof_test.dart` renamed/worded as device-local boundary proof (TC-238-13)
  - `integration_test/group_private_media_platform_proof_test.dart` (TC-238-11)
  - TC-238-14 is explicitly N/A under local-only/no-revocation wording and is closed by Go/relay production-diff proof, not a relay mutation.
- Likely named gates/commands:
  - exact focused host tests from Sessions 238-01..03;
  - exact SQLCipher, bridge, Android-pair, Android platform, and iOS platform commands with discovered IDs;
  - `./scripts/check_reliability_simulation_discovery.sh --records-tsv` exact-path assertions and owning simulator `--list` checks;
  - `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge ./node -run 'GPL12|GK030' -count=1)`;
  - all exact focused/device/Go/static commands and `git diff --check`; the
    current user-directed `run_test_gates.sh` skip is recorded explicitly;
  - no Plan 238 `core-host-all`, `feature-host-all`, or full `host-all`. Full
    `host-all` waits until final included-Wave-1 closure after Plan 238; excluded
    Plan 242 is not a dependency.
- Docs/matrix update: final Plan 238 verdict/evidence; `20-group-discussion-reliability-closure-reference.md`; stable private-group matrix; `test-gate-definitions.md`; `00-INDEX.md`; breakdown program ledger.
- Dependency: 238-03 accepted and live device inventory available. A failed selected target is a causal blocker; an unavailable platform target is N/A.
- Meaningful verified end state: independent real-boundary evidence matches every accepted user promise, documentation and gate inventories agree, and Plan 238 is accepted without overclaiming relay/capture/global-once behavior.

## Why This Is Not Fewer Sessions

- Combining 238-01 and 238-02 would mix migration/codec compatibility with destructive consume/cleanup rollback. A codec GREEN would not prove crash-safe cleanup, and a cleanup failure could obscure schema/wire causality.
- Combining 238-02 and 238-03 would let UI/native work race ahead of terminal-state durability and would span different rollback boundaries: DB/file recovery versus capabilities/notifications/platform route state.
- Folding 238-04 into implementation would make the same role both author and accept cross-session SQLCipher, bridge, paired-device, and capture evidence. These proofs validate interactions that do not exist until all implementation slices land.
- The central disabled-until-complete availability seam prevents the four-session sequence from creating an externally usable half-feature.

## Why This Is Not More Sessions

- Policy types, v101 mapping, encrypted extras, composer selection, and send-time authorization share one compatibility contract and the same group gate; splitting them would leave either unpersistable policy or unauthorised/untransmittable UI state.
- Consume, expiry, cleanup, replay, and download guards are one terminal-state engine. Separate “timer,” “file cleanup,” or “replay” sessions would duplicate fixtures and invite inconsistent state machines.
- Capabilities, Shared Media exclusion, notification redaction, viewer coordination, and native route protection must agree before availability can turn on. Separate surface sessions would create bypass windows and mostly bookkeeping.
- Android/iOS/SQLCipher/bridge/device-local observations belong to one acceptance session because they all validate the same already-landed user promise and do not own independent product code.

## Regression And Gate Contract

- Follow RED-first causal work per session. A missing-file compile RED is acceptable only when the session plan first names the exact observable behavior and representative mutation.
- Every new group host test is added explicitly to `GROUP_TESTS` in `scripts/run_test_gates.sh`; device files receive exact records in `scripts/check_reliability_simulation_discovery.sh`. No wildcard classification or unrelated capability test may stand in for the new boundary.
- Session-focused tests run first. Exact ordinary/legacy send, retry, live/offline replay, media integrity/download, deletion journal, received actions, Forward, Shared Media, announcement, notification, and viewer sentinels then prove preservation.
- Under normal cadence each implementation session would close with the
  affected curated `groups` lane. In this continuation the user's explicit
  instruction not to invoke `run_test_gates.sh` controls: focused causal/
  preservation/Go/native/static evidence is still mandatory, no pre-change
  external run is credited as post-change, and the deviation is recorded
  without an invented count. Final included-Wave-1 `host-all` remains required.
- Migration proof is two-layered: host SQLite structure/full-chain/run-twice in 238-01, then production `sqflite_sqlcipher` close/reopen/upgrade/fresh-chain in 238-04. Host SQLite must never be reported as SQLCipher closure.
- `feature-host-all`, `core-host-all`, and full `host-all` are not Plan 238
  per-session or per-plan gates. Full `host-all` runs once at final included-
  Wave-1 closure after Plan 238.
- Snapshot the dirty worktree before each executor pass and preserve unrelated changes. Compare Go node/relay production status and binary diff against the session-start baseline; a raw clean-tree assertion is invalid.
- A selected, available target failure is a causal blocker. An absent target/version is `N/A (target unavailable by project policy)`, with host/native unit and compile/availability coverage retained.

## Matrix Update Contract

- Session 238-01 owns the source Plan 238 decision-ledger conversion, exact v101 allocation, revised test commands, and initial gate registration.
- Sessions 238-02 and 238-03 append only their actual implementation/test evidence and keep the source verdict open.
- Session 238-04 owns the final accepted/blocked verdict and synchronizes:
  - `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
  - `Test-Flight-Improv/00-INDEX.md`
  - this breakdown's session/program ledger.
- Do not create a replacement private-media matrix. Plan 242 remains excluded;
  no announcement-specific future record is a current Plan-238 dependency.

## Downstream Execution Path

For each session, in ledger order:

1. Invoke `$implementation-plan-orchestrator` against the exact doc-scoped intended plan path and refresh all assumptions against landed predecessors.
2. Invoke `$implementation-execution-qa-orchestrator` for RED/GREEN, proportional gates, independent QA, and bounded causal fix passes.
3. Invoke `$implementation-closure-audit-orchestrator` to persist evidence, reconcile docs/gates/matrices, and produce an accepted or exact blocker verdict.
4. Update this program ledger before planning the next session. Never pre-plan later sessions against unlanded schema/API names.

## Reviewer Answers

- Recommended count: sufficient; neither too coarse nor fragmented.
- Merge candidates: none.
- Required splits: none after preserving a separate acceptance session.
- Missing regressions found and fixed during review: disabled-until-complete availability, sender staged-copy cleanup, private no-auto-download, and enablement-order proof.
- Missing named gates: the normal curated `groups` command is intentionally not
  invoked under the user's explicit direction. Exact new-file registration,
  focused/full-chain/SQLCipher/Go/discovery/platform/Android-pair proof plus
  final Wave-1 `host-all` provide the recorded execution profile; no result is
  invented for the skipped command.
- Meaningful verified state: yes; 238-01 is compatibility-safe and disabled, 238-02 is terminal/replay safe, 238-03 turns on a fully guarded feature, and 238-04 independently accepts it.
- Matrix responsibility: explicit in 238-04.
- Minimum safe session set: four.

## Structural Blockers Remaining

- The Plan-234 prerequisite is satisfied: Plan 234 is accepted/closed with DB
  v100 landed and no competing v101 claim. Session 238-01 is execution-ready;
  later Plan-238 sessions remain sequentially blocked.
- No external product/security/relay authority blocker remains; the conservative device-local policy resolves all Plan 238 evidence rows.

## Accepted Differences Intentionally Left Unchanged

- No account-wide/global view-once convergence, sibling-device consume event, server single-use fetch, relay/blob revocation, sender recall, or exported-copy revocation.
- No universal screenshot or screen-recording prevention claim; iOS remains best-effort obscure/detect with truthful warning.
- No moderator recovery/escrow of private bytes. Plan 245 reporting is metadata-only for these rows.
- No announcement authoring or private UI in Plan 238. Plan 242 remains excluded
  from this rollout; any future reuse of v101 creates no current dependency or
  competing migration.
- No ordinary received-video PiP implementation. Plan 238 supplies only a fail-
  closed private eligibility seam. Excluded Plan 243 retains any future actual
  PiP ownership but does not run after or depend on excluded Plan 242 in this
  rollout.
- Ordinary/legacy group media, current Go node/relay semantics, and external picker originals remain unchanged.

## Exact Docs And Files Used As Evidence

- `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan.md`
- `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md`
- `Test-Flight-Improv/00-INDEX.md`
- `lib/core/database/app_database_version.dart`
- `lib/core/database/production_migration_registry.dart`
- `lib/core/database/helpers/media_attachments_db_helpers.dart`
- `lib/core/media/media_owner_lane.dart`
- `lib/features/groups/domain/models/group_message.dart`
- `lib/features/groups/domain/models/group_private_media_policy.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_received_media_action_policy.dart`
- `lib/features/groups/application/group_received_media_actions.dart`
- `lib/features/groups/application/group_media_forward_policy.dart`
- `lib/features/groups/application/group_shared_media_library_controller.dart`
- `lib/features/groups/application/group_shared_media_batch_actions.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_shared_media_library_screen.dart`
- `scripts/run_test_gates.sh`
- `scripts/check_reliability_simulation_discovery.sh`
- Direct current tests and proposed exact TC-238 test paths listed under Sessions 238-01..04.

## Why This Decomposition Is Safe For Downstream Execution

It resolves every privacy decision into one narrow, testable device-local contract; reserves v101 without colliding with Plan 234 v100; prevents partial rollout with a central availability gate; separates compatibility, destructive lifecycle state, cross-surface/native enforcement, and independent real-boundary acceptance; names exact doc-scoped plan paths and stable closure owners; and preserves the repo's availability-bounded device and wave-level gate cadence. The remaining prerequisite is concrete and discoverable rather than a vague authority gap.
