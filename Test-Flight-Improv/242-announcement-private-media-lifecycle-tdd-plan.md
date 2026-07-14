# 242 - Announcement Private-Media Lifecycle

Status: accepted
Type: New Feature
Spec: free-text intent — adapt approved group view-once, disappearing, and protected image/video policy to announcements without weakening publisher authorization or inventing another lifecycle protocol
Classification: implemented and directly accepted
Closure tier: device

## Accepted Decision Contract

Accepted for direct execution on 2026-07-12 after Plan 238 closed. This
section supersedes every historical statement below that describes Plan 242 or
its upstream lifecycle contract as unresolved or evidence-gated.

| Decision | Accepted contract |
|---|---|
| Base lifecycle | Reuse Plan 238's message-scoped v101 policy, durable device/install-local consume/expiry state, cleanup engine, download/replay guards, viewer, notification, and platform protection without another migration, owner lane, enum, clock, or wire protocol. |
| Author eligibility | Any currently active announcement admin may author private image/video. Both the local `GroupRole.admin` row and current roster `MemberRole.admin` must agree at selection, send, pre-upload, final dispatch, and every retry/re-drive. Receive persistence independently requires the resolved current sender roster row to remain `MemberRole.admin`; reader/writer, removed, demoted, missing, or mismatched authority fails before event-log, parent, attachment, or notification work. Readers never gain compose or publish. |
| Broadcast consumption | Each recipient installation enforces its own consume/expiry state. No account-wide/global-once event, sibling-device convergence, relay revocation, uninstall recovery, or remote reset is claimed. |
| Admin/terminal state | Published lifecycle policy and terminal consume/expiry state are immutable. A later admin cannot reset, revoke, recover, export, or reclassify private bytes. The durable placeholder retains only the normal message identity plus policy/terminal/integrity metadata required for truthful local history and lifecycle auditability. |
| Notification | Foreground/background/lock-screen copy is app title plus localized `New private media`; no announcement, publisher, caption, subtype, lifecycle, duration, thumbnail, path, key, or bytes are visible or fetched. Explicit partial, malformed, or future policy markers fail closed to the same generic copy in both Dart and the iOS Notification Service Extension. |
| Reporting disposition | Report is an accepted product non-goal. Retained identity/policy/terminal/integrity metadata exists only for truthful local history and lifecycle proof; there is no reporting consumer, gateway, consent/result flow, byte access, recovery override, or lifecycle-reset authority. |
| Platform promise | Reuse the exact Plan-238 protected viewer: Android route-scoped `FLAG_SECURE`; iOS detection/obscuring with truthful best-effort wording; private PiP/resume denied. No universal screenshot-prevention claim. |
| Proof topology | Announcement-specific host tests prove role, encrypted-inner live/offline/retry, terminal lifecycle, capability, notification, and metadata boundaries. Existing ordinary announcement tests plus Go authorization preserve read-only broadcast semantics. The inherited Plan-238 SQLCipher/native proof and announcement-specific real-Go payload plus wired Android route/native-protection proof run on explicit available targets; the iOS Notification Service resolver suite covers the platform notification boundary. No three-party scenario is required because this plan adds no schema, transport, convergence, or relay behavior. Unavailable mobile legs are N/A by project policy. |

## Current Direct Execution Contract

- Plan 238 remains the exclusive owner of DB v101, group-owned storage,
  encrypted-inner policy fields, lifecycle engine, cleanup, viewer, and native
  protection. Plan 242 allocates no migration and adds no Go/node protocol.
- Production availability now admits `GroupType.announcement`, while the same
  current-state qualification requires matching local and roster admin roles.
  Initial send, pre-upload, failed-message retry, incomplete-upload retry, and
  final dispatch all reuse the exact durable-parent requalification seam. Key
  lookup is followed by a fresh group read and a final live-roster read, so an
  async demotion cannot cross into reliable-send, publish, or inbox work.
- Announcement readers remain read-only. All private message rendering,
  actions, Forward, library/batch eligibility, notifications, download/open,
  consume/expiry, and terminal cleanup reuse the central Plan-238 policy.
- Live and offline receive paths share a final current-sender admin check
  before persistence. The iOS Notification Service Extension recognizes any
  explicit group-private policy marker and returns localized generic copy,
  including partial, malformed, and future policy input.
- A dedicated three-party device runner is intentionally N/A: the accepted
  behavior is per-install and changes no broadcast transport. Device closure
  passed on physical Android `21071FDF600CSC` through v101 SQLCipher, the real
  Go announcement payload, inherited native protection, and the actual
  announcement wired route; the iOS NSE regression passed on available
  simulator `DBE8C32E-9F19-4593-860A-B41113791D79`.

## Current Change Manifest

Production seams:

- `lib/features/groups/application/group_private_media_availability.dart` —
  announcement availability and exact local/roster role predicate.
- `lib/features/groups/application/send_group_message_use_case.dart` —
  announcement private send support, durable-parent/key/current-author
  qualification, final roster read after async gaps, and shared initial/retry/
  fallback dispatch enforcement.
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
  — current announcement-admin receive authorization before any persistence.
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
  and `retry_incomplete_group_uploads_use_case.dart` — every retry/pre-upload/
  final-send branch consumes the shared fresh qualification.
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` —
  composer selection and send recheck use the current admin predicate. This
  shared file is serialized with the forwarding lane after the narrow privacy
  hunk; Plan 242 owns no Forward/library implementation there.
- `lib/features/push/application/push_decrypt_preview.dart` and
  `ios/NotificationService/NotificationPreviewResolver.swift` — generic
  private-announcement notification copy with explicit-policy fail-closed
  handling across Dart and the iOS NSE.

Dedicated proof files:

- `test/features/groups/domain/models/announcement_private_media_policy_test.dart`
- `test/features/groups/application/announcement_private_media_authorization_test.dart`
- `test/features/groups/application/announcement_incoming_message_authorization_test.dart`
- `test/features/groups/application/announcement_private_media_notification_test.dart`
- `test/features/groups/application/announcement_private_media_moderation_test.dart`
- `test/features/groups/integration/announcement_private_media_payload_roundtrip_test.dart`
- `test/features/groups/integration/announcement_private_media_lifecycle_test.dart`
- `test/features/groups/presentation/announcement_private_media_capabilities_test.dart`
- `integration_test/announcement_private_media_platform_proof_test.dart`

Existing preservation/adapter files extended by exact APL cases:

- `test/features/groups/application/group_private_media_notification_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`

Deliberately unchanged: database version/migrations, `GroupMessage` lifecycle
columns, core lifecycle/viewer/native protection, Go node/relay production,
report submission (intentionally absent), and forwarding/library production. Plan 242 adds only a
thin wired-route device proof around the shared viewer/native mechanism.

## Historical Planning Record (Superseded)

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
- Missing coverage at the historical planning point: announcement author eligibility, announcement live/offline mapping, reader action denial, multi-reader consume/expiry behavior, notification redaction, admin/terminal-state interaction, and an announcement-specific real-device scenario.
- Refuted findings: local file deletion alone is not view once/disappearing; replay can restore access unless DB lifecycle state wins before download/decode. `FLAG_SECURE` alone is not a universal cross-platform screenshot guarantee.
- Unresolved findings at the historical planning point: all plan-238 ledger choices remained unresolved, plus whether any announcement admin or only the original publisher could apply/change policy; whether a later admin could revoke/override a published policy; how per-reader consumption applied to broadcast recipients; reader/admin notification wording; whether any reporting consumer existed after consume/expiry; and the exact real-device role topology. The accepted contract above and Plan 246's intentional non-goal supersede these questions.
- Affected production, test, migration, platform, bridge, and gate files cannot be finalized until those decisions are approved. This plan owns only the announcement adapter/tests; the eventual lifecycle migration, base policy/platform bridge, and optional encrypted fields remain plan 238.

## Evidence Decision Ledger

| Decision | Required accepted evidence | Current state | Consequence if unresolved |
|---|---|---|---|
| Base lifecycle semantics | plan-238 ledger accepted for consume boundary, expiry authority/skew, unknown values, capture wording, replay/blob and device convergence | accepted 2026-07-12 — exact Plan-238 device/install-local contract | implemented through the shared v101 policy/engine |
| Announcement author eligibility | any current admin vs original publisher/owner; composer/send/retry/receive revalidation matrix | accepted 2026-07-12 — any current admin with matching local+roster admin send authority and current roster-admin receive authority | APL-02/APL-02W plus the live/offline incoming authorization suite cover selection, send, demotion, retries, and persistence |
| Broadcast consumption scope | per recipient-device, per account, or another authenticated scope; offline/multi-device conflict behavior | accepted 2026-07-12 — independent recipient installation; no convergence claim | no new consume event or transport exists |
| Admin/terminal-state override | whether another admin can revoke/change policy and how truthful lifecycle metadata survives | accepted 2026-07-12 — no override/reset/recovery; immutable terminal placeholder metadata only | APL-09 covers retained metadata without bytes |
| Announcement notification privacy | foreground/background/lock-screen title/body/caption/thumbnail matrix for each policy | accepted 2026-07-12 — app title plus localized generic private-media body; explicit malformed/partial/future policy fails closed | APL-07 covers Dart paths and `NotificationPreviewResolverTests` covers the iOS NSE |
| Reporting disposition | whether any downstream reporting consumer exists and what metadata remains without retaining or exporting prohibited media bytes | accepted 2026-07-13 — no reporting consumer; identity/policy/terminal/integrity metadata remains only for truthful local history and lifecycle proof | Plan 246 closes Report as an intentional non-goal with no lifecycle authority or byte access |
| Platform promise | Android/iOS best-effort capture behavior and exact user copy inherited/extended from GPL-11 | accepted 2026-07-12 — exact Plan-238 viewer/platform promise, no extension | no second native implementation |
| Device proof topology | roles/accounts/devices, offline interval, relay fixture, process restart, accepted semantic oracle, and exact scenario/platform discovery rules | accepted 2026-07-12 — availability-bounded GPL-01D/GPL-11 plus announcement-specific APL-03D/APL-08 on Android `21071FDF600CSC`; iOS NSE regression on the available simulator | no three-party scenario or unavailable target gate |

## Scope Contract And Guard

Provisional in scope after every ledger row is accepted:
- Reuse plan 238's `GroupMediaLifecycle { standard, viewOnce, disappearing }`, `GroupPrivateMediaPolicy`, and independent `isMediaProtected`; add no announcement-specific enum, timestamp, or storage field.
- Reuse the local lifecycle fields and migration version accepted/allocated by plan 238. Local consumption state stays local-only unless the accepted upstream decision introduces a separately reviewed authenticated convergence contract.
- Reuse optional encrypted-inner `mediaLifecycle`, `mediaExpiresAt`, and `mediaProtected` fields across admin send/retry, live receive, offline inbox/history replay, and legacy absence. Do not add outer-envelope fields or a new Go/libp2p command.
- Offer policy controls only to the accepted eligible announcement publisher role, revalidated immediately before send/retry. Every reader remains unable to compose, attach, quote, record, or publish.
- Apply plan 238's durable-first consume/expire engine before file/key/thumbnail/controller cleanup. Preserve the accepted non-playable placeholder so history remains truthful and replay/download cannot resurrect plaintext.
- Drive plan 230 and plans 239-241 from one current policy/capability result. View-once/protected media must deny Save, external Share, Forward, Bookmark, batch selection, PiP/resume and thumbnails whenever the accepted policy says so; Delete for me and retained lifecycle metadata follow their own accepted matrix.
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
- Do not implement Report or make retained lifecycle metadata an egress path. Plan 246 closes Report as an intentional product non-goal and owns no reporting gateway, consent flow, result behavior, or metadata consumer.

Deferred / accepted difference:
- 1:1 private media is plan 234 and discussion-group private media is plan 238; this plan does not force identical author/admin semantics across lanes.
- General announcement expiration/text-message expiry and admin Delete for everyone are separate product work.
- External copies created before a policy applies cannot be recalled.
- Authenticated multi-device consumption convergence or relay blob revocation is not implied. If selected, it requires the upstream plan-238 follow-up transport contract and its proof before this adapter can close.

Dependencies:
- Plan 228 supplies group owner isolation, unresolved exclusion, replay-safe local state, scope/filter-bound cursor semantics and the shared production migration registry; announcement policy consumes these through plans 238/241.
- `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan.md` must have an accepted Evidence Decision Ledger, a freshly conflict-checked eventual migration, and supplies `GroupMediaLifecycle`, `GroupPrivateMediaPolicy`, encrypted-inner fields, durable lifecycle engine, notification/capture base policy, and boundary proofs.
- Plans 227-230 and 239-241 supply egress/storage/viewer/action/library capabilities that must consume the central policy. Plan 246 is a closed intentional non-goal, has no lifecycle-metadata consumer, and is not a prerequisite.
- Existing announcement authorization tests, group real-crypto fixture, multi-party device runner, and test discovery are preservation/harness dependencies.
- This plan reserves no migration and no new Go/libp2p contract.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-242-00 | Both evidence ledgers have accepted owner/date/user wording and a proof profile before executable work starts | `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan.md::Evidence Decision Ledger` plus this plan's `Evidence Decision Ledger` | planning evidence / product-security-platform sign-off | HEAD evidence RED: rows unresolved -> every row records an accepted choice and announcement delta | N/A — this stop gate makes later mutations meaningful | manual plan-review gate; blocks every following row |
| TC-242-01 | Announcement mapping reuses plan 238's eventual shared-registry lifecycle migration/state with legacy standard defaults, group ownership and no competing migration. | plan-238 migration + real-SQLCipher proof rows plus `test/features/groups/domain/models/announcement_private_media_policy_test.dart::announcement rows reuse owner scoped lifecycle state without another schema` | prerequisite migration sentinels + host model/repository same-ID direct/group/unresolved fixture | HEAD lifecycle model RED -> after plan 238 acceptance, known/legacy announcement rows map as `group`, unresolved/direct collision rows remain excluded/preserved, and this plan leaves DB version unchanged | add an announcement column/lane/version, drop owner filtering, or reclassify unresolved -> TC-242-01 red | `flutter test test/features/groups/domain/models/announcement_private_media_policy_test.dart`; AUTO plus `GROUP_TESTS`; require exact migration/SQLCipher commands recorded by accepted plan 238 |
| TC-242-02 | Only a current announcement admin can choose/publish policy, and receive persistence independently requires a current roster admin | `test/features/groups/application/announcement_private_media_authorization_test.dart` (`APL-02`, `APL-02K`), `announcement_incoming_message_authorization_test.dart`, plus `group_conversation_wired_test.dart::APL-02W` | host application/widget / admin/member/demotion/removal/key-await/live/offline fixtures | exact role matrix succeeds/rejects before bridge or persistence; final-key demotion and non-admin live/offline replay deny | trust composer state, return a stale roster snapshot, or persist reader/writer/revoked announcement traffic -> TC-242-02 red | focused APL aggregate plus exact `--plain-name 'APL-'`; `GROUP_TESTS` |
| TC-242-03 | Sender policy roundtrips through announcement persist/retry, real encrypted live receive, offline replay, and legacy absence with no local consume leakage | `test/features/groups/integration/announcement_private_media_payload_roundtrip_test.dart` plus `integration_test/group_real_crypto_onboarding_test.dart::APL-03D` | host integration + real-Go bridge sentinel / fake inbox and encrypted bridge fixture | all paths produce one exact encrypted-inner policy; legacy stays standard; local consume state remains absent from wire | drop policy from retry/drain, leak consumed state, or add outer field -> TC-242-03 red | focused payload suite plus explicit physical-Android `APL-03D`; `GROUP_TESTS` + device proof |
| TC-242-04 | Reader bubble/viewer/library/batch surfaces derive one current capability matrix, accept only resolved group-owned media, and deny every prohibited egress/forward/bookmark/resume action. | `test/features/groups/presentation/announcement_private_media_capabilities_test.dart::reader owner scoped media surfaces fail closed without gaining compose` | evidence-gated host widget / plans 230/239-241 harnesses, state table, same-ID direct/group/unresolved rows | HEAD policy/capabilities absent -> every surface agrees before/after consume/expiry; direct/unresolved entries never render or call gateways | guard viewer only, use stale capabilities, union batch permissions, omit owner scope, or accept unresolved -> TC-242-04 red | `flutter test test/features/groups/presentation/announcement_private_media_capabilities_test.dart`; AUTO plus `GROUP_TESTS`; blocked on accepted action matrix |
| TC-242-05 | View-once consumes once at the accepted decoder boundary, commits Plan-238 local state before cleanup, and cannot reopen | `test/features/groups/integration/announcement_private_media_lifecycle_test.dart::APL-05` plus Plan-238 GPL-05/06/08 | host integration / production repository over host SQLite and exact app-owned file | durable consume precedes cleanup; placeholder remains and later open is denied | consume at tap, clean before commit, or reopen terminal media -> TC-242-05 red | focused APL aggregate; `GROUP_TESTS`; inherits Plan-238 crash/replay matrix |
| TC-242-06 | Disappearing media expires under the accepted high-water clock and cannot reopen/redownload | `test/features/groups/integration/announcement_private_media_lifecycle_test.dart::APL-06` plus Plan-238 GPL-07/08 | host integration / production repository over host SQLite, exact deadline and file | exact boundary terminalizes, cleans, retains placeholder, and denies open | use a competing clock, reset duration, or accept terminal replay -> TC-242-06 red | focused APL aggregate; `GROUP_TESTS` |
| TC-242-07 | Private announcement notifications and thumbnails follow the generic foreground/background/lock-screen matrix without media hydration | `announcement_private_media_notification_test.dart`, `push_decrypt_preview_test.dart`, and `ios/RunnerTests/NotificationPreviewResolverTests.swift::testGroupPrivateMediaPreviewIsGenericForAnnouncementsAndMalformedPolicy` | host Dart + iOS NSE native suite / trusted and malformed policy fixtures | localized app title/generic body, no group/sender/caption/subtype, zero plaintext media fetch; malformed/partial/future policy fails closed | reuse ordinary preview or trust incomplete policy -> TC-242-07 red | `GROUP_TESTS` plus focused `xcodebuild test` on an available iOS simulator |
| TC-242-08 | Protected announcement viewer applies the accepted best-effort capture behavior and truthful copy, including background and route exit | `integration_test/announcement_private_media_platform_proof_test.dart::APL-08` plus inherited GPL-11 | actual wired-route device proof / explicit physical Android target | reader taps the production announcement route into the shared viewer; `FLAG_SECURE` acquires/releases on normal exit and injected background | omit protection, keep flag after exit, bypass the shared viewer, or fork a second mechanism -> TC-242-08 red | explicit Android `21071FDF600CSC` APL-08; `ignored/ignored` discovery record |
| TC-242-09 | Admin override/revoke and retained lifecycle metadata after consume/expiry follow the accepted terminal-state matrix without restoring/exporting media | `test/features/groups/application/announcement_private_media_moderation_test.dart::admin lifecycle and retained safety metadata match approved audit matrix without media resurrection` | application host / admin transitions, repository snapshot and egress spies | Historical HEAD contracts absent -> exact allowed/denied transitions and required placeholder/lifecycle metadata survive while every media egress call stays zero | let a later admin reset consume/expiry, discard required lifecycle identity, or retain/export prohibited bytes -> TC-242-09 red | `flutter test test/features/groups/application/announcement_private_media_moderation_test.dart`; AUTO plus `GROUP_TESTS`; decision closed |
| TC-242-10 | Ordinary/legacy announcement image/video delivery, viewing and reactions remain unchanged when policy is absent/standard | `test/features/groups/integration/announcement_happy_path_test.dart::announcement happy path: create, admin send, reader read-only receive, member react` plus `test/features/groups/presentation/group_conversation_wired_test.dart::announcement readers stay read-only for compose but still keep reaction entry` | GREEN sentinel / existing host integration/widget fixtures | GREEN on HEAD -> remains GREEN after lifecycle adapter | default absence to private/expired or gate reaction on private capability -> sentinel red | `flutter test test/features/groups/integration/announcement_happy_path_test.dart --plain-name 'announcement happy path: create, admin send, reader read-only receive, member react' && flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'announcement readers stay read-only for compose but still keep reaction entry'`; existing `GROUP_TESTS` |
| TC-242-11 | Reader cannot publish lifecycle-tagged or ordinary media and optional policy plumbing changes no Go node authorization/topic/recipient/retry behavior | `test/features/groups/integration/announcement_new_reader_onboarding_test.dart::new reader receives only post-join admin media with descriptors` plus `go-mknoon/node/pubsub_test.go::TestGroupTopicValidator_AnnouncementNonAdminRejected` plus plan-238 GPL-16 | GREEN sentinel / Flutter integration, Go validator, source boundary | GREEN on HEAD -> remains GREEN; no Go node production diff and all reader bridge send counts remain zero | trust lifecycle flag as permission or weaken validator -> sentinel red | `flutter test test/features/groups/integration/announcement_new_reader_onboarding_test.dart --plain-name 'new reader receives only post-join admin media with descriptors' && (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run TestGroupTopicValidator_AnnouncementNonAdminRejected -count=1) && git diff --exit-code -- go-mknoon/node`; existing `GROUP_TESTS` / Go preservation |
| TC-242-12 | Dedicated three-party/convergence/relay scenario | N/A under accepted per-install/no-new-transport contract | N/A — host APL-03, device APL-03D, and Go authorization prove the selected boundary | no global-once, convergence, or relay-revocation user claim exists | adding such a claim or protocol makes TC-242-12 required after replanning | no runner or discovery registration |

### Test Notes

- TC-242-00 is an execution stop. Announcement authoring cannot be inferred merely from current admin publish permission; consume/expiry/capture and retained-metadata privacy guarantees require explicit product/security wording.
- TC-242-04 must open a menu before a lifecycle transition and invoke afterward; the coordinator must re-load policy and fail closed. Widget-only hidden buttons do not prove egress gateways are unreachable.
- TC-242-05/06 reconstruct database, repository, scheduler, viewer and download policy after injected failures. Reusing one in-memory controller would make restart/replay assertions vacuous.
- TC-242-08 records observable platform behavior and cleanup, not an assertion that screenshots are impossible. Repeat on each applicable available platform target; record unavailable legs N/A and retain native host coverage.
- TC-242-12 is N/A under the accepted device/install-local contract. Any future
  account-wide, global-once, or relay-revocation promise requires a separately
  authenticated protocol and a freshly reviewed multi-peer fixture.

## Implementation Steps

1. Resolve every plan-238 and announcement Evidence Decision Ledger row with product/security/platform owners, exact user wording, and selected test topology. Make no production/test/schema edits until then.
2. Verify ordered predecessor migrations and shared action/viewer contracts have landed; after plan 238 accepts its ledger, require its fresh vNEXT collision check and complete migration/lifecycle gates. Stop-if plan 238 remains evidence-gated or its accepted semantics differ.
3. Snapshot `git status --short`; add announcement mapping/role/payload/capability causal tests without changing schema or Go node production.
4. Add the `GroupType.announcement` adapter around plan 238's policy/engine, revalidating eligible admin role on send/retry and preserving reader no-write callbacks.
5. Thread the same optional encrypted-inner fields through announcement live/offline/retry paths and apply the central policy before download/decode/notification/action dispatch.
6. Reuse durable consume/expiry/cleanup and native capture mechanisms; add only announcement route, notification, admin/retained-metadata, and multi-reader tests. Stop-if an implementation needs a competing timestamp, consumption event, bridge command, or platform mechanism.
7. Register the eight dedicated host suites in `GROUP_TESTS`; classify the
   thin announcement platform proof as an explicit manual Android proof.
8. Run selected host GREEN, inherited DB/real-crypto/platform proof,
   ordinary/read-only/Go sentinels, the curated `groups` lane gate, analyzer,
   and diff hygiene.

## Risks And Blind Spots

- Broadcast scale amplifies a false privacy promise -> TC-242-00 blocks partial implementation and TC-242-08/12 tie copy to real boundaries.
- A stale menu or batch selection can bypass protection -> TC-242-04 re-evaluates policy at invocation and spies every gateway.
- Crash/offline replay can reopen consumed/expired content -> TC-242-05/06 commit state first and reconstruct fresh runtime state.
- Admin role changes can authorize a queued private send incorrectly -> TC-242-02 revalidates membership/role at send and retry.
- Async key lookup can stale an earlier role snapshot -> APL-02K demotes both
  local and roster authority during the final key read; current group and roster
  are reloaded afterward with the roster read last.
- Notifications/app-switch snapshots can leak before viewer -> TC-242-07/08.
- Retained lifecycle metadata can accidentally become a retention/egress override -> TC-242-09 fixes the boundary; Plan 246 intentionally has no consumer and cannot restore or export media.
- Lifecycle / derived-state durability: plan 238's eventual accepted DB state is canonical; cleanup/cache/controller state reconstructs fail-closed -> TC-242-01/05/06 plus its real-SQLCipher proof.
- Sibling-surface consistency: TC-242-04 covers bubble/viewer/library/batch and uses one central capability result; TC-242-07 covers notification.
- Destructive-action side effects: TC-242-05/06/09 preserve truthful placeholder/audit and siblings/external paths while removing only app-owned target state.
- Invariant re-verification under new transitions: role, policy, clock, consume state, file eligibility, and reporting absence are rechecked at each send/open/action/retry boundary.

## Gate Cadence

- Individual plan closure runs the accepted TC-242 focused tests, exact ordinary-announcement and Go sentinels, the curated `groups` lane gate, and every selected available-device/relay proof below.
- Do not run `host-all`, `feature-host-all`, or `core-host-all` for Plan 242 closure; broad host coverage is deferred without weakening its required native or multi-party boundary proof.
- Run full `host-all` once after the private-lifecycle wave is complete, and once again at final media-rollout closure.

## Acceptance Gates

```bash
# Evidence stop: Plan 238's authoritative top-level accepted status supersedes
# its retained historical unresolved ledger; Plan 242's current ledger is exact.
rg -n '^Status: accepted$' Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan.md
! rg -n '\| unresolved( upstream)? \|' Test-Flight-Improv/242-announcement-private-media-lifecycle-tdd-plan.md

# Ordered prerequisite and migration ownership; plan 238 allocates vNEXT only after its evidence/collision gate
test -f Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan.md
git status --short

# Focused announcement host GREEN selected by the accepted policy
flutter test --no-pub --concurrency=1 --reporter failures-only \
  test/features/groups/domain/models/announcement_private_media_policy_test.dart \
  test/features/groups/application/announcement_private_media_authorization_test.dart \
  test/features/groups/application/announcement_incoming_message_authorization_test.dart \
  test/features/groups/integration/announcement_private_media_payload_roundtrip_test.dart \
  test/features/groups/integration/announcement_private_media_lifecycle_test.dart \
  test/features/groups/presentation/announcement_private_media_capabilities_test.dart \
  test/features/groups/application/announcement_private_media_notification_test.dart \
  test/features/groups/application/announcement_private_media_moderation_test.dart
flutter test --no-pub --concurrency=1 --reporter failures-only \
  test/features/groups/presentation/group_conversation_wired_test.dart \
  test/features/groups/application/group_private_media_notification_test.dart \
  --plain-name 'APL-'

# Ordinary announcement and native authorization preservation
flutter test test/features/groups/integration/announcement_happy_path_test.dart test/features/groups/integration/announcement_new_reader_onboarding_test.dart
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestIsAllowedWriter_AnnouncementMemberBlocked|TestGroupTopicValidator_AnnouncementNonAdminRejected' -count=1)
# Compare Go production status/diff with the execution-start baseline; test-only
# pre-existing changes make a raw clean-tree assertion invalid.

# Affected curated lane gate; expect new announcement files selected and zero failures
./scripts/run_test_gates.sh groups

# Availability-bounded device closure. Plan 242 adds no schema/bridge protocol
# and therefore no three-peer run; APL-08 wraps the shared native mechanism.
flutter devices --machine
./scripts/check_reliability_simulation_discovery.sh
flutter test --no-pub -d 21071FDF600CSC integration_test/group_private_media_lifecycle_db_proof_test.dart --plain-name 'GPL-01D real SQLCipher allocated vNEXT preserves legacy private state reopen and full chain'
flutter test --no-pub -d 21071FDF600CSC integration_test/group_real_crypto_onboarding_test.dart --plain-name 'APL-03D private announcement policy survives the real Go bridge encrypted payload'
flutter test --no-pub -d 21071FDF600CSC integration_test/group_private_media_platform_proof_test.dart --plain-name 'GPL-11 protected viewer applies truthful platform capture safeguards'
flutter test --no-pub -d 21071FDF600CSC integration_test/announcement_private_media_platform_proof_test.dart
xcodebuild test -quiet -workspace ios/Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,id=DBE8C32E-9F19-4593-860A-B41113791D79' \
  CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -only-testing:RunnerTests/NotificationPreviewResolverTests

# Hygiene; expect no new analyzer issues and no whitespace errors
flutter analyze
git diff --check
```

## Device/Relay Proof Profile

- Profile: `available-target inherited-plus-wired-boundary`. The live matrix on 2026-07-12
  contains USB Android `21071FDF600CSC` and no attached Android emulator.
- Boundary being proven: production SQLCipher v101 state, real-Go encrypted
  announcement extras, actual announcement wired-route entry, and shared
  protected-viewer native ownership/restoration. Host APL-02 plus receive and
  Go authorization sentinels prove announcement-admin/read-only policy;
  APL-03/05/06 prove the adapter and per-install lifecycle.
- Required setup: run GPL-01D, APL-03D, inherited GPL-11, and APL-08 on explicit
  Android `21071FDF600CSC`. No relay authority, account-wide convergence, or
  three-peer runner is selected because none is part of the accepted promise.
- Native proof limit: GPL-11/APL-08 observe Android `FLAG_SECURE` ownership and
  wired-route/event cleanup; their debug-injected events do not observe or prove
  physical screenshot or screen-record prevention. iOS capture behavior remains
  the inherited best-effort mechanism with the same injected-event limitation.
- iOS notification closure runs the native `NotificationPreviewResolverTests`
  on available simulator `DBE8C32E-9F19-4593-860A-B41113791D79`; capture/viewer
  semantics remain inherited from accepted Plan 238.
- Registration: APL-08 is an explicit `ignored/ignored` manual Android proof in
  reliability discovery; the eight host suites are registered in `GROUP_TESTS`.
- Result on 2026-07-12: GPL-01D, APL-03D, GPL-11, and APL-08 each passed `1/1`
  with exit 0 on physical Android `21071FDF600CSC`; the iOS resolver class
  passed with exit 0. The harness required no manual taps or prompts.
- Deferred device work: none.

## Execution Interpretation And Done Criteria

- Decision stops are closed. Historical RED recreation is neither required nor safe in this dirty integrated Wave-2 tree; the retained causal APL tests and review mutations are authoritative.
- Focused Plan-242 host tests, receive authorization, metadata-only terminal-state preservation,
  Dart/iOS notification adapters, ordinary/read-only sentinels, Plan-238
  preservation, Go publisher authorization, all selected device proofs, test
  discovery, and the integrated curated `groups` lane are green.
- Pre-existing dirty tree / known failure: record unrelated changes; do not edit the already-dirty `Test-Flight-Improv/00-INDEX.md` in this plan.
- Environment blocker: failures on selected available targets remain blockers; unavailable mobile target legs are N/A by project policy and retain host/native proof. No relay or reporting-authority fixture is required.
- Scope drift: any announcement-owned migration/version, competing wire/engine, unauthenticated consumption event, Go node behavior edit, reader write path, universal capture/remote revocation claim, or retained-metadata egress bypass requires replanning.

- [x] Plan 238's authoritative Accepted Decision Contract and this plan's
  accepted Evidence Decision Ledger record every selected base and announcement
  outcome; the plan-level Test Contract and Device/Relay Proof Profile record
  the proof topology.
- [x] Every selected announcement behavior has a named causal test or inherited real-boundary proof; convergence/relay/three-party guarantees are explicitly N/A and absent from UI/copy.
- [x] Retained causal tests, focused GREEN, and representative denial/terminal counterexamples are recorded.
- [x] Plan-238 migration passes the current inherited real-SQLCipher rerun; this plan allocates no new migration.
- [x] Announcement send/live/offline/retry/real-bridge policy agrees on the current inherited device rerun; local consumption never leaks.
- [x] Consume/expiry is durable-first, terminal, cleanup-safe, and scoped to the accepted recipient/install model.
- [x] Viewer/action/Forward/notification/retained-metadata/platform adapters consume one current policy and expose no private-byte egress bypass.
- [x] Ordinary/read-only/Go sentinels and the curated `groups` lane gate pass.
- [x] Every selected available Android inherited proof passes; multi-party/convergence/relay and unavailable emulator legs are N/A.
- [x] Scoped analyzers have no issues; `git diff --check` is clean.
- [x] Scope Contract And Guard is respected.

## Handoff

- Focused command: the eight-file Plan-242 host aggregate in Acceptance Gates.
- Preservation command: `flutter test test/features/groups/integration/announcement_new_reader_onboarding_test.dart && (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run TestGroupTopicValidator_AnnouncementNonAdminRejected -count=1)`.
- Registration: all eight Plan-242 host files are in `GROUP_TESTS`; APL-08 is
  explicitly classified as a manual Android proof and discovery passes.
- Migration: none; reuse accepted DB v101 and its structural plus real-SQLCipher proof.
- Boundary closure: GPL-01D/APL-03D/GPL-11/APL-08 passed on Android
  `21071FDF600CSC`; the iOS NSE resolver class passed on the available simulator.
- Unresolved evidence: none. Plan 242 is accepted.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-12 | Host implementation and preservation | availability/send/receive/retry/composer adapters; eight dedicated host files; Dart/iOS notification adapters | dedicated aggregate `19/19`; Plan-238 preservation `63/63`; ordinary/new-reader `3/3`; receive/offline sentinels green; Go auth passed; iOS resolver class passed | v101 reuse, final current-admin send/receive authority, live/offline/retry, terminal lifecycle, capability, notification, and metadata contracts are closed | none | accepted |
| 2026-07-12 | Availability-bounded device closure | inherited SQLCipher/native harnesses plus announcement real-Go and actual wired-route proofs | `GPL-01D`, `APL-03D`, `GPL-11`, and `APL-08` each `1/1`, exit 0 on physical Android `21071FDF600CSC` | v101 reopen/full-chain, exact encrypted-inner announcement policy, and actual shared-viewer `FLAG_SECURE` acquire/release/background cleanup pass without manual interaction | unavailable emulator legs N/A; no multi-party/convergence/relay promise | accepted |
| 2026-07-12 | Integrated closure | eight host registrations, APL-08 discovery classification, corrected iOS smoke scenario expansion, forwarding preservation reconciliation | `GROUP_TESTS` `2139/2139` plus bridge/node Go legs passed; completeness `1226/1226`; reliability discovery PASS; scoped analyzers/diff hygiene clean | Plan 242 and the integrated Track-2 group/forwarding surfaces are mutually coherent | none | accepted |
