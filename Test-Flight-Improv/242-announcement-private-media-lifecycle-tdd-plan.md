# 242 - Announcement Private-Media Lifecycle

Status: evidence-gated
Type: New Feature
Spec: free-text intent — adapt approved group view-once, disappearing, and protected image/video policy to announcements without weakening publisher authorization or inventing another lifecycle protocol
Classification: evidence-gated
Closure tier: device

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector | plan-specific `graphify-arch` query; `group_model.dart`; `group_message.dart`; send/listen/offline/replay paths; viewer/action surfaces; Go group payload/validator; announcement host/device tests | Announcements share group persistence/encrypted payloads but have distinct admin-only publish and reader-only receive semantics. HEAD has no lifecycle state or enforcement. | reuse plan 238 contracts only after its evidence ledger is accepted |
| 2026-07-09 | Planner | plan 238 evidence-gated migration/policy ownership; plans 227-230/239-241/246 action boundaries; group multi-party device runner/discovery | A second migration/wire field would create divergent privacy behavior. Announcement adaptation needs its own author/read-only/notification/multi-reader tests and inherits real platform/relay limits. | record announcement-specific decisions and conditional proof topology before implementation |
| 2026-07-10 | Dependency refresh | revised plan 228 ownership/library contract and refreshed group/announcement dependencies | Announcement media remains locally `group`-owned; no third owner lane exists. Private capability checks must exclude unresolved rows, preserve same-ID direct siblings, and reuse plan 238's future shared-registry migration. | Keep the evidence gate; apply these storage invariants after both decision ledgers are accepted. |

## Problem And Evidence

- Behavior to improve: an approved announcement publisher needs to mark image/video as view once, disappearing, or protected, while readers need truthful enforcement across open, restart, offline replay, notifications, media actions, and cleanup.
- Impact: ordinary announcement media is currently reusable and will gain Save/Share/Forward/Bookmark/library capabilities through plans 239-241. Merely displaying a private label without durable enforcement would create a false privacy promise at broadcast scale.
- Confirmed model/schema gap: `GroupMessage` at `lib/features/groups/domain/models/group_message.dart` and `MediaAttachment` at `lib/features/conversation/domain/models/media_attachment.dart` contain no lifecycle, expiration, consumption, or protected fields on HEAD.
- Confirmed announcement discriminator: `GroupType.announcement` and `GroupRole.admin/member` are durable fields at `lib/features/groups/domain/models/group_model.dart:2` and `:25`; `_canWriteForGroup` at `lib/features/groups/presentation/screens/group_conversation_wired.dart:4553` keeps members read-only.
- Confirmed native authorization: Flutter rejects a non-admin announcement send at `lib/features/groups/application/send_group_message_use_case.dart:809`; Go rejects unauthorized `group_message` publication at `go-mknoon/node/pubsub.go:1605` and `isAllowedWriter` at `:1963`.
- Confirmed shared payload opportunity: Go `GroupMessagePayload.Extra` in `go-mknoon/internal/group_envelope.go:40` and current send/listen extra handling allow optional policy fields inside the existing encrypted inner group payload. Plan 238 owns the narrow whitelist and proves no new Go node protocol.
- Confirmed persistence owner: plan 238 owns one eventual group-private lifecycle migration, allocated as the then-next free version only after its decision ledger and a fresh collision check. This plan must reuse its accepted fields and reserves no version.
- Confirmed action risk: plans 239-241 add egress, forwarding, bookmark/library, batch, viewer and storage actions. An announcement lifecycle policy must feed one shared capability decision before any of those paths resolves or exports a file.
- Existing coverage: `announcement_happy_path_test.dart` and `announcement_new_reader_onboarding_test.dart` prove ordinary image/video delivery and reader send rejection; plan-238 lifecycle rows will own the base engine, eventual migration, encrypted-inner, capture and replay contracts.
- Missing coverage: announcement author eligibility, announcement live/offline mapping, reader action denial, multi-reader consume/expiry behavior, notification redaction, admin/moderation interaction, and an announcement-specific real-device scenario.
- Refuted findings: local file deletion alone is not view once/disappearing; replay can restore access unless DB lifecycle state wins before download/decode. `FLAG_SECURE` alone is not a universal cross-platform screenshot guarantee.
- Unresolved findings: all plan-238 ledger choices remain unresolved, plus whether any announcement admin or only the original publisher may apply/change policy; whether a later admin can revoke/override a published policy; how per-reader consumption applies to broadcast recipients; reader/admin notification wording; report access after consume/expiry under plan 246; and the exact real-device role topology.
- Affected production, test, migration, platform, bridge, and gate files cannot be finalized until those decisions are approved. This plan owns only the announcement adapter/tests; the eventual lifecycle migration, base policy/platform bridge, and optional encrypted fields remain plan 238.

## Evidence Decision Ledger

| Decision | Required accepted evidence | Current state | Consequence if unresolved |
|---|---|---|---|
| Base lifecycle semantics | plan-238 ledger accepted for consume boundary, expiry authority/skew, unknown values, capture wording, replay/blob and device convergence | unresolved upstream | no announcement lifecycle implementation |
| Announcement author eligibility | any current admin vs original publisher/owner; composer/send/retry revalidation matrix | unresolved | no author controls or send policy |
| Broadcast consumption scope | per recipient-device, per account, or another authenticated scope; offline/multi-device conflict behavior | unresolved | no view-once acceptance or device topology |
| Admin/moderation override | whether another admin can revoke/change policy and how audit/report evidence survives | unresolved | no update/revoke behavior |
| Announcement notification privacy | foreground/background/lock-screen title/body/caption/thumbnail matrix for each policy | unresolved | no notification implementation |
| Reporting compatibility | minimum metadata/audit state retained for downstream plan 246 without retaining or exporting prohibited media bytes | unresolved | no stable downstream safety contract |
| Platform promise | Android/iOS best-effort capture behavior and exact user copy inherited/extended from GPL-11 | unresolved upstream | no protected UI/platform acceptance |
| Device proof topology | roles/accounts/devices, offline interval, relay fixture, process restart, accepted semantic oracle, and exact scenario/platform discovery rules | unresolved | no final simulator/device command or registration |

## Scope Contract And Guard

Provisional in scope after every ledger row is accepted:
- Reuse plan 238's `GroupMediaLifecycle { standard, viewOnce, disappearing }`, `GroupPrivateMediaPolicy`, and independent `isMediaProtected`; add no announcement-specific enum, timestamp, or storage field.
- Reuse the local lifecycle fields and migration version accepted/allocated by plan 238. Local consumption state stays local-only unless the accepted upstream decision introduces a separately reviewed authenticated convergence contract.
- Reuse optional encrypted-inner `mediaLifecycle`, `mediaExpiresAt`, and `mediaProtected` fields across admin send/retry, live receive, offline inbox/history replay, and legacy absence. Do not add outer-envelope fields or a new Go/libp2p command.
- Offer policy controls only to the accepted eligible announcement publisher role, revalidated immediately before send/retry. Every reader remains unable to compose, attach, quote, record, or publish.
- Apply plan 238's durable-first consume/expire engine before file/key/thumbnail/controller cleanup. Preserve the accepted non-playable placeholder so history remains truthful and replay/download cannot resurrect plaintext.
- Drive plan 230 and plans 239-241 from one current policy/capability result. View-once/protected media must deny Save, external Share, Forward, Bookmark, batch selection, PiP/resume and thumbnails whenever the accepted policy says so; Delete for me and retained safety metadata follow their own accepted matrix.
- Redact announcement notifications and app-switch snapshots according to the accepted matrix before any media download/decode.
- Reuse plan 238's Android/iOS best-effort capture mechanism and truthful copy. Add announcement route coverage, not a second native implementation.

Must preserve:
- Ordinary/legacy announcement media and reader reactions remain unchanged -> TC-242-10 plus existing announcement tests.
- Reader compose/send remains absent and Go independently rejects publication -> TC-242-11.
- Migration mapping, legacy standard default, real SQLCipher, encrypted-inner privacy, cleanup/replay and platform wording remain plan-238 contracts -> TC-242-01/03/05/06/08.
- Discussion-group private lifecycle stays owned by plan 238; announcement-specific role/UI conditions must not broaden `GroupType.chat` behavior.

Hard `Do not`:
- Do not create an announcement owner lane, infer ownership from `message_id`, reclassify plan-228 unresolved rows, or put local owner identity into announcement payloads/provenance.
- Do not implement any announcement lifecycle UI/schema/wire/platform behavior while either Evidence Decision Ledger has unresolved rows.
- Do not allocate any announcement migration/version, duplicate plan-238 fields, add an announcement payload schema, or edit Go node topics/recipient/auth/retry/inbox/relay behavior merely to carry policy.
- Do not grant a reader write permission, send `mediaConsumedAt` as an unauthenticated field, or infer account-wide consumption from a local timestamp.
- Do not allow Save/Share/Forward/Bookmark/library batch/PiP/resume/notification preview to bypass current policy through a sibling surface or stale menu.
- Do not claim universal screenshot/screen-record prevention, remote deletion, exported-copy revocation, cryptographic erasure, multi-device convergence, or relay revocation without matching real-boundary proof.
- Do not trust raw sender/device wall clock, silently treat explicit unknown lifecycle as ordinary, or delete state required to block replay.
- Do not implement Report or make retained safety metadata an egress path; downstream plan 246 owns the reporting gateway, consent and result behavior.

Deferred / accepted difference:
- 1:1 private media is plan 234 and discussion-group private media is plan 238; this plan does not force identical author/admin semantics across lanes.
- General announcement expiration/text-message expiry and admin Delete for everyone are separate product work.
- External copies created before a policy applies cannot be recalled.
- Authenticated multi-device consumption convergence or relay blob revocation is not implied. If selected, it requires the upstream plan-238 follow-up transport contract and its proof before this adapter can close.

Dependencies:
- Plan 228 supplies group owner isolation, unresolved exclusion, replay-safe local state, scope/filter-bound cursor semantics and the shared production migration registry; announcement policy consumes these through plans 238/241.
- `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan.md` must have an accepted Evidence Decision Ledger, a freshly conflict-checked eventual migration, and supplies `GroupMediaLifecycle`, `GroupPrivateMediaPolicy`, encrypted-inner fields, durable lifecycle engine, notification/capture base policy, and boundary proofs.
- Plans 227-230 and 239-241 supply egress/storage/viewer/action/library capabilities that must consume the central policy; plan 246 is a downstream consumer of accepted lifecycle/safety metadata and is not a prerequisite.
- Existing announcement authorization tests, group real-crypto fixture, multi-party device runner, and test discovery are preservation/harness dependencies.
- This plan reserves no migration and no new Go/libp2p contract.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-242-00 | Both evidence ledgers have accepted owner/date/user wording and a proof profile before executable work starts | `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan.md::Evidence Decision Ledger` plus this plan's `Evidence Decision Ledger` | planning evidence / product-security-platform sign-off | HEAD evidence RED: rows unresolved -> every row records an accepted choice and announcement delta | N/A — this stop gate makes later mutations meaningful | manual plan-review gate; blocks every following row |
| TC-242-01 | Announcement mapping reuses plan 238's eventual shared-registry lifecycle migration/state with legacy standard defaults, group ownership and no competing migration. | plan-238 migration + real-SQLCipher proof rows plus `test/features/groups/domain/models/announcement_private_media_policy_test.dart::announcement rows reuse owner scoped lifecycle state without another schema` | prerequisite migration sentinels + host model/repository same-ID direct/group/unresolved fixture | HEAD lifecycle model RED -> after plan 238 acceptance, known/legacy announcement rows map as `group`, unresolved/direct collision rows remain excluded/preserved, and this plan leaves DB version unchanged | add an announcement column/lane/version, drop owner filtering, or reclassify unresolved -> TC-242-01 red | `flutter test test/features/groups/domain/models/announcement_private_media_policy_test.dart`; AUTO plus `GROUP_TESTS`; require exact migration/SQLCipher commands recorded by accepted plan 238 |
| TC-242-02 | Only the approved announcement publisher role can choose policy, and role/membership is revalidated on send and queued retry | `test/features/groups/domain/usecases/send_group_message_use_case_test.dart::announcement private media authoring follows approved admin policy at send and retry` | evidence-gated host application / admin/member/demotion/removal fixtures | HEAD has no policy -> exact accepted role matrix succeeds/rejects before bridge calls; reader remains unauthorized | trust composer state or allow demoted/member retry -> TC-242-02 red after decision | `flutter test test/features/groups/domain/usecases/send_group_message_use_case_test.dart --plain-name 'announcement private media authoring follows approved admin policy at send and retry'`; existing `GROUP_TESTS`; blocked by TC-242-00 |
| TC-242-03 | Sender policy roundtrips through announcement persist/retry, real encrypted live receive, offline replay, and legacy absence with no local consume leakage | `test/features/groups/integration/announcement_private_media_payload_roundtrip_test.dart::announcement policy matches send live offline retry and legacy paths` plus plan-238 GPL-12 | host integration + real-Go bridge sentinel / fake inbox and encrypted bridge fixture | HEAD fields absent -> all paths produce one exact policy; legacy standard; `mediaConsumedAt` and private fields absent from outer routing data | drop policy from retry/drain, leak consumed state, or add outer field -> TC-242-03 red | `flutter test test/features/groups/integration/announcement_private_media_payload_roundtrip_test.dart && flutter test -d "$FLUTTER_DEVICE_ID" integration_test/group_real_crypto_onboarding_test.dart --plain-name 'GPL-12 private media policy survives real Go bridge encrypted group payload'`; `GROUP_TESTS` + inherited device proof |
| TC-242-04 | Reader bubble/viewer/library/batch surfaces derive one current capability matrix, accept only resolved group-owned media, and deny every prohibited egress/forward/bookmark/resume action. | `test/features/groups/presentation/announcement_private_media_capabilities_test.dart::reader owner scoped media surfaces fail closed without gaining compose` | evidence-gated host widget / plans 230/239-241 harnesses, state table, same-ID direct/group/unresolved rows | HEAD policy/capabilities absent -> every surface agrees before/after consume/expiry; direct/unresolved entries never render or call gateways | guard viewer only, use stale capabilities, union batch permissions, omit owner scope, or accept unresolved -> TC-242-04 red | `flutter test test/features/groups/presentation/announcement_private_media_capabilities_test.dart`; AUTO plus `GROUP_TESTS`; blocked on accepted action matrix |
| TC-242-05 | View-once consumes once at the accepted decoder boundary, commits plan-238 local state before cleanup, and cannot reopen after cancel/crash/restart/replay | `test/features/groups/integration/announcement_view_once_media_lifecycle_test.dart::announcement view once is boundary exact crash safe and replay proof` | evidence-gated host integration / production repository over host SQLite, temp file, decoder milestones, fresh controller, offline replay | HEAD lifecycle absent -> consume/cancel/crash matrix matches decision; placeholder remains; decode/download after consumed is zero | consume at tap regardless of decode, clean before commit, or reconstruct from replay -> TC-242-05 red | `flutter test test/features/groups/integration/announcement_view_once_media_lifecycle_test.dart`; AUTO plus `GROUP_TESTS`; inherits plan-238 engine |
| TC-242-06 | Disappearing media expires under the accepted authority/skew policy across foreground/background/restart/offline-late replay and cannot redownload | `test/features/groups/integration/announcement_disappearing_media_lifecycle_test.dart::announcement expiry follows approved clock and blocks late replay download` | evidence-gated host integration / fake authoritative clock, scheduler, repository reopen, download spy | HEAD expiry absent -> exact boundary/placeholder/cleanup and zero late decode/download | use `DateTime.now`, restart duration on receipt/open, or accept skewed replay -> TC-242-06 red | `flutter test test/features/groups/integration/announcement_disappearing_media_lifecycle_test.dart`; AUTO plus `GROUP_TESTS`; blocked on clock decision |
| TC-242-07 | Private announcement notifications and thumbnails follow the accepted foreground/background/lock-screen matrix without downloading/decrypting media | `test/features/groups/application/announcement_private_media_notification_test.dart::private announcement notification redacts approved fields without plaintext fetch` | evidence-gated host application/widget / notification sink, lifecycle table, download/decode spies | HEAD no policy branch -> exact generic title/body/visibility and zero plaintext calls | reuse caption/thumbnail from ordinary announcement or hydrate before policy -> TC-242-07 red | `flutter test test/features/groups/application/announcement_private_media_notification_test.dart`; AUTO plus `GROUP_TESTS`; blocked on notification decision |
| TC-242-08 | Protected announcement viewer applies the accepted Android/iOS best-effort capture behavior and truthful copy, including app switch and route exit | `integration_test/announcement_private_media_platform_proof_test.dart::protected announcement viewer applies truthful platform capture safeguards` | external-fixture-blocked device proof / every applicable Android/iOS target available for the accepted promise | HEAD platform mechanism absent -> observable secure/obscure/capture response and cleanup match exact wording; unsupported limits are disclosed | omit protection, leak switcher snapshot, keep flag after exit, or claim universal prevention -> TC-242-08 red | `flutter test -d "$FLUTTER_DEVICE_ID" integration_test/announcement_private_media_platform_proof_test.dart` per available target; unavailable legs are N/A; before execution-ready status refresh this row with the exact `classify_path` category/runner entry selected by TC-242-00; base mechanism inherited GPL-11 |
| TC-242-09 | Admin override/revoke and retained safety metadata after consume/expiry follow the accepted moderation matrix without restoring/exporting media | `test/features/groups/application/announcement_private_media_moderation_test.dart::admin lifecycle and retained safety metadata match approved audit matrix without media resurrection` | evidence-gated application host / admin transitions, repository snapshot and egress spies | HEAD contracts absent -> exact allowed/denied transitions and required placeholder/audit metadata survive while every media egress call stays zero | let a later admin reset consume/expiry, discard required safety identity, or retain/export prohibited bytes -> TC-242-09 red | `flutter test test/features/groups/application/announcement_private_media_moderation_test.dart`; AUTO plus `GROUP_TESTS`; blocked on moderation decision |
| TC-242-10 | Ordinary/legacy announcement image/video delivery, viewing and reactions remain unchanged when policy is absent/standard | `test/features/groups/integration/announcement_happy_path_test.dart::announcement happy path: create, admin send, reader read-only receive, member react` plus `test/features/groups/presentation/group_conversation_wired_test.dart::announcement readers stay read-only for compose but still keep reaction entry` | GREEN sentinel / existing host integration/widget fixtures | GREEN on HEAD -> remains GREEN after lifecycle adapter | default absence to private/expired or gate reaction on private capability -> sentinel red | `flutter test test/features/groups/integration/announcement_happy_path_test.dart --plain-name 'announcement happy path: create, admin send, reader read-only receive, member react' && flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'announcement readers stay read-only for compose but still keep reaction entry'`; existing `GROUP_TESTS` |
| TC-242-11 | Reader cannot publish lifecycle-tagged or ordinary media and optional policy plumbing changes no Go node authorization/topic/recipient/retry behavior | `test/features/groups/integration/announcement_new_reader_onboarding_test.dart::new reader receives only post-join admin media with descriptors` plus `go-mknoon/node/pubsub_test.go::TestGroupTopicValidator_AnnouncementNonAdminRejected` plus plan-238 GPL-16 | GREEN sentinel / Flutter integration, Go validator, source boundary | GREEN on HEAD -> remains GREEN; no Go node production diff and all reader bridge send counts remain zero | trust lifecycle flag as permission or weaken validator -> sentinel red | `flutter test test/features/groups/integration/announcement_new_reader_onboarding_test.dart --plain-name 'new reader receives only post-join admin media with descriptors' && (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run TestGroupTopicValidator_AnnouncementNonAdminRejected -count=1) && git diff --exit-code -- go-mknoon/node`; existing `GROUP_TESTS` / Go preservation |
| TC-242-12 | Real admin, online reader, and offline/restarting reader observe the accepted independent/convergent consume/expiry and replay semantics with no reader publish | `integration_test/scripts/run_group_multi_party_device_real.dart::announcement_private_media_lifecycle` | external-fixture-blocked three-party/device-lab / real Go bridge and relay with one USB physical Android plus two Android emulators, all harness-controlled | HEAD scenario/policy absent -> role-specific verdicts prove encrypted receipt, accepted consume/expiry oracle, offline late replay denial, restart durability and unauthorized reader send | omit offline guard, reorder expiry/receive, drop local consume, or allow reader publish -> scenario red | `MKNOON_RELAY_ADDRESSES="$MKNOON_RELAY_ADDRESSES" dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario announcement_private_media_lifecycle -d "$DEVICE_A,$DEVICE_B,$DEVICE_C"`; register only after TC-242-00 fixes topology |

### Test Notes

- TC-242-00 is an execution stop. Announcement authoring cannot be inferred merely from current admin publish permission; consume/expiry/capture/report guarantees require explicit product/security wording.
- TC-242-04 must open a menu before a lifecycle transition and invoke afterward; the coordinator must re-load policy and fail closed. Widget-only hidden buttons do not prove egress gateways are unreachable.
- TC-242-05/06 reconstruct database, repository, scheduler, viewer and download policy after injected failures. Reusing one in-memory controller would make restart/replay assertions vacuous.
- TC-242-08 records observable platform behavior and cleanup, not an assertion that screenshots are impossible. Repeat on each applicable available platform target; record unavailable legs N/A and retain native host coverage.
- TC-242-12's three distinct accounts prove broadcast recipient behavior, not same-account multi-device convergence. If the accepted promise includes account-wide consumption, plan-238 GPL-13 and an additional same-account device fixture remain required.

## Implementation Steps

1. Resolve every plan-238 and announcement Evidence Decision Ledger row with product/security/platform owners, exact user wording, and selected test topology. Make no production/test/schema edits until then.
2. Verify ordered predecessor migrations and shared action/viewer contracts have landed; after plan 238 accepts its ledger, require its fresh vNEXT collision check and complete migration/lifecycle gates. Stop-if plan 238 remains evidence-gated or its accepted semantics differ.
3. Snapshot `git status --short`; add announcement mapping/role/payload/capability causal tests without changing schema or Go node production.
4. Add the `GroupType.announcement` adapter around plan 238's policy/engine, revalidating eligible admin role on send/retry and preserving reader no-write callbacks.
5. Thread the same optional encrypted-inner fields through announcement live/offline/retry paths and apply the central policy before download/decode/notification/action dispatch.
6. Reuse durable consume/expiry/cleanup and native capture mechanisms; add only announcement route, notification, moderation, and multi-reader tests. Stop-if an implementation needs a competing timestamp, consumption event, bridge command, or platform mechanism.
7. Register new host suites in `GROUP_TESTS`; after topology approval, add scenario requirement/list/usage/dispatch/harness/verdict/discovery coverage for `announcement_private_media_lifecycle` and the platform proof.
8. Run selected host GREEN, DB/real-crypto/platform/multi-party proof, ordinary/read-only/Go sentinels, the curated `groups` lane gate, analyzer, and diff hygiene.

## Risks And Blind Spots

- Broadcast scale amplifies a false privacy promise -> TC-242-00 blocks partial implementation and TC-242-08/12 tie copy to real boundaries.
- A stale menu or batch selection can bypass protection -> TC-242-04 re-evaluates policy at invocation and spies every gateway.
- Crash/offline replay can reopen consumed/expired content -> TC-242-05/06 commit state first and reconstruct fresh runtime state.
- Admin role changes can authorize a queued private send incorrectly -> TC-242-02 revalidates membership/role at send and retry.
- Notifications/app-switch snapshots can leak before viewer -> TC-242-07/08.
- Moderation compatibility can accidentally become retention/egress override -> TC-242-09 fixes the retained-metadata boundary; downstream plan 246 must consume it without restoring media.
- Lifecycle / derived-state durability: plan 238's eventual accepted DB state is canonical; cleanup/cache/controller state reconstructs fail-closed -> TC-242-01/05/06 plus its real-SQLCipher proof.
- Sibling-surface consistency: TC-242-04 covers bubble/viewer/library/batch and uses one central capability result; TC-242-07 covers notification.
- Destructive-action side effects: TC-242-05/06/09 preserve truthful placeholder/audit and siblings/external paths while removing only app-owned target state.
- Invariant re-verification under new transitions: role, policy, clock, consume state, file eligibility and report consent are rechecked at each send/open/action/retry boundary.

## Gate Cadence

- Individual plan closure runs the accepted TC-242 focused tests, exact ordinary-announcement and Go sentinels, the curated `groups` lane gate, and every selected available-device/relay proof below.
- Do not run `host-all`, `feature-host-all`, or `core-host-all` for Plan 242 closure; broad host coverage is deferred without weakening its required native or multi-party boundary proof.
- Run full `host-all` once after the private-lifecycle wave is complete, and once again at final media-rollout closure.

## Acceptance Gates

```bash
# Evidence stop: do not continue while either ledger contains unresolved rows
! rg -n '\| unresolved( upstream)? \|' Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan.md Test-Flight-Improv/242-announcement-private-media-lifecycle-tdd-plan.md

# Ordered prerequisite and migration ownership; plan 238 allocates vNEXT only after its evidence/collision gate
test -f Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan.md
git status --short

# First announcement causal RED after evidence acceptance; expect non-zero because adapter/policy test is absent
flutter test test/features/groups/domain/models/announcement_private_media_policy_test.dart

# Focused announcement host GREEN selected by accepted policy
flutter test test/features/groups/domain/models/announcement_private_media_policy_test.dart
flutter test test/features/groups/domain/usecases/send_group_message_use_case_test.dart --plain-name 'announcement private media authoring follows approved admin policy at send and retry'
flutter test test/features/groups/integration/announcement_private_media_payload_roundtrip_test.dart
flutter test test/features/groups/presentation/announcement_private_media_capabilities_test.dart
flutter test test/features/groups/integration/announcement_view_once_media_lifecycle_test.dart
flutter test test/features/groups/integration/announcement_disappearing_media_lifecycle_test.dart
flutter test test/features/groups/application/announcement_private_media_notification_test.dart
flutter test test/features/groups/application/announcement_private_media_moderation_test.dart

# Ordinary announcement and native authorization preservation
flutter test test/features/groups/integration/announcement_happy_path_test.dart test/features/groups/integration/announcement_new_reader_onboarding_test.dart
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestIsAllowedWriter_AnnouncementMemberBlocked|TestGroupTopicValidator_AnnouncementNonAdminRejected' -count=1)
git diff --exit-code -- go-mknoon/node

# Affected curated lane gate; expect new announcement files selected and zero failures
./scripts/run_test_gates.sh groups

# Device discovery/closure only after TC-242-00 fixes topology and platform promise
flutter devices --machine
rg -n 'announcement_private_media_(lifecycle|platform_proof)' integration_test/scripts/run_group_multi_party_device_real.dart scripts/run_test_gates.sh scripts/check_reliability_simulation_discovery.sh
./scripts/check_reliability_simulation_discovery.sh
dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios --scenario announcement_private_media_lifecycle
MKNOON_RELAY_ADDRESSES="$MKNOON_RELAY_ADDRESSES" dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario announcement_private_media_lifecycle -d "$DEVICE_A,$DEVICE_B,$DEVICE_C"
flutter test -d "$FLUTTER_DEVICE_ID" integration_test/announcement_private_media_platform_proof_test.dart

# Hygiene; expect no new analyzer issues and no whitespace errors
flutter analyze
git diff --check
```

## Device/Relay Proof Profile

- Profile: external-fixture-blocked until TC-242-00 fixes the promise; expected minimum is the available three-party/device-lab topology plus platform capture runs on every applicable available target inherited from plan 238.
- Boundary being proven: real encrypted admin publication, online/offline reader receipt, accepted per-recipient consume/expiry behavior, restart/replay denial, no reader publish, and platform capture/app-switch behavior matching exact user wording.
- Live availability check: `flutter devices --machine` and `dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios --scenario announcement_private_media_lifecycle` -> no approved topology/scenario/device IDs exist at planning time.
- Required setup: Alice as eligible announcement publisher, Bob as online reader, and Charlie as offline/restarting reader on one pinned USB physical Android plus two pinned Android emulators; the harness drives setup, permissions, lifecycle, and assertions without user taps. Configure real relay addresses and policy fixtures separately. Android/iOS platform-capture proof remains its own platform-specific leg. Any same-account two-peer convergence fixture uses the physical Android + one emulator pair.
- Closure role: required closure evidence for announcement broadcast semantics; plan-238 accepted migration/SQLCipher, GPL-11/12/13/14 remain required for each selected DB/platform/convergence/relay guarantee.
- `FLUTTER_DEVICE_ID`: sufficient for one SQLCipher/real-bridge/platform row only; it is not sufficient for the three-party scenario, both promised platforms, or same-account convergence.
- Registration: add `announcement_private_media_lifecycle` to `group_multi_party_device_criteria.dart`, runner scenario list/usage/dispatch, harness role verdicts, criteria tests and reliability discovery only after topology approval. TC-242-00 must also select an exact `classify_path` category plus runner/array entry for `integration_test/announcement_private_media_platform_proof_test.dart`, and this plan must be refreshed with that literal rule before implementation; a generic manual-proof bucket is insufficient.
- Discovery command: `dart run integration_test/scripts/run_group_multi_party_device_real.dart --list-scenarios --scenario announcement_private_media_lifecycle` -> exactly that scenario must be listed; `scripts/check_reliability_simulation_discovery.sh` must classify its proof files.
- Closure command: `MKNOON_RELAY_ADDRESSES="$MKNOON_RELAY_ADDRESSES" dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario announcement_private_media_lifecycle -d "$DEVICE_A,$DEVICE_B,$DEVICE_C"` -> all three role verdicts prove the accepted state oracle and reader publish rejection.
- Deferred device work: scenario registration/command is provisional and must be refreshed if the accepted scope is not three distinct accounts; no chosen user-facing guarantee may ship without its exact real-boundary run.

## Execution Interpretation And Done Criteria

- Expected evidence RED: TC-242-00 currently fails because upstream and announcement ledgers are unresolved. No production/test/schema action is authorized.
- Expected first executable RED after evidence: TC-242-01's announcement model test fails because the adapter does not exist; the DB migration itself belongs to plan 238 and must already be green.
- Green sentinels: ordinary announcement media/reactions/read-only behavior, plan-238 migration/lifecycle tests, group real-crypto extras, and Go publisher authorization remain green.
- Pre-existing dirty tree / known failure: record unrelated changes; do not edit the already-dirty `Test-Flight-Improv/00-INDEX.md` in this plan.
- Environment blocker: failures on selected available targets or an unavailable required relay/authority fixture remain blockers; unavailable mobile target legs are N/A by project policy and retain host/native proof.
- Scope drift: any announcement-owned migration/version, competing wire/engine, unauthenticated consumption event, Go node behavior edit, reader write path, universal capture/remote revocation claim, or safety egress bypass requires replanning.

- [ ] Both Evidence Decision Ledgers have accepted owner/date/user wording/test profile for every row.
- [ ] Every selected announcement behavior has a named causal test or real-boundary proof; rejected guarantees are explicitly N/A and absent from UI/copy.
- [ ] First executable RED, focused GREEN, and representative mutation re-red are recorded.
- [ ] Plan-238 eventual migration passes its exact structural and real-SQLCipher default/state/reopen/idempotency/full-chain proof; this plan allocates no new migration.
- [ ] Announcement send/live/offline/retry/real-bridge policy agrees; local consumption never leaks unless a separate authenticated protocol is approved.
- [ ] Consume/expiry is durable-first, crash/restart/replay/download safe, and scoped to the accepted recipient/device model.
- [ ] Viewer/library/batch/notification/report/platform surfaces consume one current policy and have no egress bypass.
- [ ] Ordinary/read-only/Go sentinels and the curated `groups` lane gate pass.
- [ ] Every selected available-platform/multi-party/convergence/relay proof passes; unavailable mobile legs are recorded N/A.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: none while TC-242-00 is unresolved. After acceptance: `flutter test test/features/groups/domain/models/announcement_private_media_policy_test.dart`.
- Preservation command: `flutter test test/features/groups/integration/announcement_new_reader_onboarding_test.dart && (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run TestGroupTopicValidator_AnnouncementNonAdminRejected -count=1)`.
- Manual registration: after evidence approval, add seven announcement host files to `GROUP_TESTS`; register provisional three-party scenario/harness/criteria/discovery and available-platform proof only for selected guarantees.
- Migration: none; reuse the exact version/fields plan 238 allocates only after its evidence gate and fresh conflict check, and require that plan's structural plus real-SQLCipher proof. Do not allocate an announcement version.
- Boundary closure: evidence/external-fixture blocked; reuse GPL-12 real encrypted extras and selected GPL-11/13/14 proofs, plus announcement-specific three-party role verdicts.
- Unresolved evidence: all upstream lifecycle decisions plus announcement author/admin scope, broadcast consumption, override/moderation/report, notification copy, platform wording, and device topology.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | evidence gate | plan only | source/graph audit complete | shared eventual-migration/encrypted-extra path identified | both decision ledgers unresolved; no implementation authorized | product/security/platform review |
