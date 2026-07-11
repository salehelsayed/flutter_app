# 238 - Group Private Media Lifecycle

Status: evidence-gated
Type: New Feature
Spec: free-text intent — add view-once, disappearing, and protected media to discussion groups only after product/security semantics are explicit
Classification: evidence-gated
Closure tier: device

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | group message/media models and DB mapping, send/listen/offline/replay paths, group integrity/viewer/action surfaces, notifications, Go bridge/node extra-field handling, migrations/gates, Android/iOS platform files | HEAD has no private-media policy, lifecycle fields, consumption/expiry state, capture protection, or relay revocation. Critical authoring, clock, consume, cross-device, moderation, platform, and notification semantics are unresolved. | Product/security accepts the decision ledger; then run a fresh migration conflict check, allocate vNEXT, refresh/review this plan, and select the real-boundary profile before RED. |
| 2026-07-10 | Dependency refresh | revised plan 228 owner-lane/backfill/replay/cursor contracts and shared production migration registry | Future group-private state and cleanup must use `owner_lane='group'`, exclude unresolved rows, preserve same-ID direct siblings, and extend the shared registry. The privacy evidence ledger remains unresolved. | Carry these fixed storage invariants into the post-decision refresh without expanding Go/libp2p implicitly. |

## Problem And Evidence

- Behavior to improve: discussion-group senders need an approved way to mark image/video media as view once, disappearing, or protected, and receivers need enforcement that remains correct across restart, offline replay, notification, viewer actions, and cleanup.
- Impact: ordinary media is indefinitely reusable inside the app and inherits Save/Share/Forward/Bookmark capabilities. Adding private labels without durable enforcement would create a false privacy promise.
- Confirmed model/schema gap: `lib/features/groups/domain/models/group_message.dart` and `media_attachments` mapping contain no lifecycle, expiry, consumption, or protected flags. No version is reserved while policy remains evidence-gated.
- Confirmed wire gap: `SendGroupMessageUseCase`, `bridge_group_helpers.dart`, `group_message_listener.dart`, and `DrainGroupOfflineInboxUseCase` carry text/quote/media but no private-media policy fields.
- Confirmed action gap: current viewer and group media surfaces have no lifecycle-aware capability restrictions. Plans 230/235/236/237 add actions that private media must be able to deny centrally.
- Confirmed notification gap: group incoming notification construction can use sender/caption and generic Photo/Video text. There is no policy-driven preview/thumbnail redaction for private media.
- Confirmed replay risk: a consumed/expired item cannot rely on deleting only its file. Offline/live replay can reintroduce attachment metadata unless durable local lifecycle state wins before download/render.
- Confirmed platform limitation: HEAD has no Android secure-window or iOS capture-state handling. iOS cannot guarantee prevention of every screenshot; Android `FLAG_SECURE` and iOS capture detection/obscuring require real-device proof and truthful product wording.
- Confirmed narrow payload opportunity: Go node encrypted payload extras are generic, as established in plan 236. Optional sender policy can use the existing encrypted group payload with narrow bridge whitelisting; local consumption must not be placed on wire unless product explicitly chooses a signed/convergent consumption protocol.
- Missing coverage: no legacy decoder, migration, eligibility, live/offline crypto roundtrip, atomic consume, expiry scheduler, cleanup/replay, notification redaction, action denial, screen-capture, multi-device, relay-revocation, or announcement-isolation proof exists.
- Refuted finding: deleting a local file is not equivalent to view-once/disappearing enforcement. Without durable consumed/expired state and ingest/download guards, restart or replay can restore access.
- Unresolved findings that block implementation:
  - Policy granularity for a message containing multiple attachments: whole-message lifecycle/consume/expiry or independent per-attachment state, and how mixed private/ordinary attachments are represented.
  - Who may author each policy in a discussion group: every writer, admins only, or a group-level setting; and how a revoked permission affects queued sends.
  - View-once consumption boundary: tap, successful decrypt, first decoded frame, video start, or playback completion; plus cancel/decode failure/crash behavior.
  - Disappearing clock: sender time, relay receipt, device receipt, first open, or group policy; allowed durations; clock authority/skew and offline-late-delivery behavior.
  - Whether consumed/expired state is device-local or converges across a user's devices; if convergent, authentication, conflict, retry, and offline event semantics.
  - Admin/moderator override, audit/evidence retention, report compatibility, and whether local Delete for me differs.
  - Meaning of “protected”: action denial only, Android secure-window/iOS best-effort capture response, or an impossible universal screenshot-prevention guarantee.
  - Relay/blob retention and late-download/replay behavior; whether policy promises actual remote access revocation or only local UI/file cleanup.
  - Notification title/body/thumbnail redaction and whether lock-screen previews differ from in-app notifications.
  - Unknown explicit lifecycle values: fail closed as unavailable or fall back to ordinary; legacy absence can safely default to ordinary, but unknown sender data needs an accepted disposition.
- Affected production, test, migration, platform, bridge, and gate files cannot be finalized until those decisions are accepted. No fixed DB version or migration filename is reserved; optional encrypted-inner policy fields, group local enforcement, and necessary device proofs remain provisional scope only.

## Evidence Decision Ledger

| Decision | Required accepted evidence | Current state | Consequence if unresolved |
|---|---|---|---|
| Policy granularity | message-vs-attachment model for multi-media sends, mixed modes and consume/expiry | unresolved | no schema/codec/state-machine allocation |
| Author/admin eligibility | role matrix for standard/view-once/disappearing/protected, send-time revalidation | unresolved | no composer/send policy implementation |
| View-once boundary | exact consume transition plus cancel/decode/crash matrix | unresolved | no viewer or consumed-state implementation |
| Expiry clock | anchor, duration set, UTC/skew authority, offline/late delivery | unresolved | no timestamp/scheduler implementation |
| Device convergence | local-only or authenticated multi-device state machine | unresolved | no consumed-event/wire decision |
| Moderation/report | override, audit retention, report access after consume/expiry | unresolved | no admin/safety semantics |
| Capture protection | truthful Android/iOS guarantees and user copy | unresolved | no platform flags/obscuring or device acceptance |
| Blob/replay | relay retention/revocation promise and replay/download guard | unresolved | no remote-revocation claim or relay work |
| Notification privacy | body/thumbnail/lock-screen matrix | unresolved | no private-media notification path |
| Unknown value | fail-closed or legacy fallback for explicit unknown policy | unresolved | no safe decoder contract |

## Scope Contract And Guard

Provisional in scope after every ledger row is accepted:
- Discussion groups (`GroupType.chat`) only. Announcement reuse belongs to plan 242 and must not acquire authoring or viewer semantics from this plan implicitly.
- Add `GroupMediaLifecycle { standard, viewOnce, disappearing }` and `GroupPrivateMediaPolicy` with an independent protected flag, subject to accepted naming/semantics.
- After TC-238-00 acceptance, run a fresh repo-wide migration-owner conflict check and allocate the then-next free version (`vNEXT`) through the shared production create/upgrade registry introduced by plan 228. If policy is message-scoped, provisional `group_messages` columns are `media_lifecycle TEXT NOT NULL DEFAULT 'standard'`, `media_expires_at TEXT`, `media_consumed_at TEXT`, and `media_protected INTEGER NOT NULL DEFAULT 0`; if attachment-scoped/mixed modes are accepted, refresh to the minimum approved `media_attachments` schema without duplicating or weakening `owner_lane`. Record exact table/columns/number/filename in a reviewed plan before any schema edit.
- All attachment-scoped policy, consume, expiry, cleanup and action checks require `owner_lane='group'` plus the exact live/tombstoned group parent contract. Plan-228 `unresolved` rows remain inaccessible, and a direct attachment sharing the same message ID is preserved.
- `mediaConsumedAt` is local-only unless the accepted convergence decision introduces a separately reviewed authenticated protocol. Legacy rows default to ordinary standard media.
- Carry optional `mediaLifecycle`, `mediaExpiresAt`, and `mediaProtected` inside the existing encrypted group-message payload. Do not put private policy, caption, or media metadata in outer routing fields.
- Enforce authoring permission at composer selection and again at send/retry; enforce receiver policy before download, decode, viewer display, egress, forward, bookmark, thumbnail, and notification preview.
- Make consume/expire transition durable before irreversible file/key/thumbnail cleanup. Preserve a non-playable message placeholder so local history is truthful and replay cannot restore access.
- Make cleanup idempotent and app-owned: media file, decrypted temp/thumbnail, attachment availability, playback position, and in-memory decoder/controller; never arbitrary external/exported copies.
- Reuse plan 230 capabilities and plans 235-237 actions so one central policy disables prohibited operations across bubble, viewer, gallery, and batch selection.
- Add only the device/relay mechanism required by the accepted product guarantee, with truthful unsupported/best-effort outcomes.

Must preserve:
- Ordinary/legacy group media remains behaviorally unchanged when fields are absent/default standard.
- Existing group media integrity/encryption validation and download ownership rules.
- Existing local Delete-for-me tombstone/replay behavior.
- Announcement writer/admin/read-only rules and announcement notification behavior until plan 242 explicitly opts in.
- Existing Go node topic, recipient, group-key, pubsub, retry, inbox, and relay semantics unless a separately accepted convergence/revocation decision explicitly expands scope.

Hard `Do not`:
- Do not infer group ownership from `message_id`, reclassify `unresolved` legacy rows, mutate a same-ID direct sibling, or serialize the local owner lane into the encrypted policy/provenance.
- Do not implement any private-media UI, schema, platform flag, or wire field while the ledger is unresolved; partial enforcement is a privacy defect.
- Do not assume one lifecycle applies to every attachment in a multi-media message or invent mixed-mode behavior before policy granularity is accepted.
- Do not claim universal screenshot/screen-recording prevention, remote deletion, exported-copy revocation, cryptographic erasure, or multi-device convergence without matching real-boundary proof.
- Do not send `mediaConsumedAt` as an unauthenticated optional bool/timestamp or infer account-wide consumption from local state.
- Do not trust sender/device wall clock without the accepted clock/skew policy.
- Do not delete arbitrary paths, externally saved/shared copies, sibling messages/attachments, or moderation evidence not authorized by policy.
- Do not expose Save, OS Share, Forward, Bookmark, thumbnail, playback resume, PiP, notification caption, or screen capture when accepted policy prohibits it.
- Do not alter `GroupType.announcement` or `GroupType.qa` surfaces in this plan.
- Do not edit Go node/libp2p production merely to transport optional sender policy; existing encrypted-extra behavior is the allowed path.

Deferred / accepted difference:
- Announcement private-media UX/eligibility is plan 242 and reuses the eventual group-private vNEXT migration/wire contract after this plan is accepted; it gets no competing migration.
- 1:1 private media is plan 234; policy parity is desirable but lane-specific group admin/replay behavior and migration allocation remain separate.
- Report access/evidence interaction is plan 245 plus the accepted moderation decision.
- External copies made before protection/expiry cannot be recalled.
- Any authenticated cross-device consumption event or relay blob revocation that changes transport is a follow-up implementation plan after explicit evidence; it is not silently implied by these optional fields.

Dependencies:
- Migration dependency: no version is reserved now. The landed spine is plan 228 `v96` shared media state, plan 232 `v97` direct forwarded marker, plan 235 `v98` group deletion journal, and plan 236 `v99` group forwarded marker. After TC-238-00, inspect the actually landed database version and all accepted claims, then allocate exactly the next free version; later landed work may still change this plan's actual predecessor before evidence acceptance.
- Storage dependency: plan 228 owns typed attachment ownership, replay-safe local state, owner-scoped deletion and the shared production migration registry. This plan must compose those seams rather than recreate untyped media helpers.
- Plans 229/230 for storage/viewer lifecycle and plans 235-237 for group action surfaces that must consume the central policy.
- Product/security/platform decisions in the Evidence Decision Ledger.
- Existing group integrity, send/listen/offline replay, notification, and real-Go bridge fixtures.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-238-00 | Every policy guarantee and boundary is accepted before executable work starts. | `Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan.md::Evidence Decision Ledger` | planning evidence / product-security-platform sign-off | HEAD evidence RED: all rows unresolved -> every row records one accepted choice, owner, date, user copy, and required test profile | N/A — this is the stop gate that makes later mutations meaningful | manual plan-review gate; blocks every following row |
| TC-238-01 | Allocated vNEXT extends the shared production registry, adds approved lifecycle fields, preserves complete predecessor owner/local-state rows, maps explicit state, and is run-twice idempotent under host SQLite. | `test/core/database/migrations/group_private_media_lifecycle_vnext_test.dart::GPL-01 allocated vNEXT preserves owner scoped legacy and private lifecycle state idempotently` | evidence-gated host migration / `sqflite_common_ffi` predecessor with same-ID direct/group and unresolved rows | HEAD evidence RED: no version/schema is allocated -> after TC-238-00 and plan refresh, exact schema/default/preservation/time roundtrips, collision rows, repeated call, allocated version and actual create/upgrade/full-chain registry paths pass | recreate callbacks, omit a default/registry branch, reclassify unresolved, mutate direct sibling, or serialize UTC incorrectly -> GPL-01 red | exact structural test command; AUTO core discovery, but no broad core gate at this plan boundary; does **not** claim SQLCipher closure |
| TC-238-01D | The allocated vNEXT migration and full chain preserve the same lifecycle state on production `sqflite_sqlcipher` across repeated migration and close/reopen. | `integration_test/group_private_media_lifecycle_db_proof_test.dart::GPL-01D real SQLCipher allocated vNEXT preserves legacy private state reopen and full chain` | device integration / password-protected `sqflite_sqlcipher`, freshly verified predecessor DB + fresh-chain DB | HEAD evidence/device RED: version/proof absent -> after refresh, `PRAGMA table_info`, legacy default, approved explicit rows, second invocation, close/reopen mapping, allocated `user_version`, and fresh/full-chain open pass | remove an approved default, corrupt mapping, skip upgrade/fresh-chain wiring, or fail repeat/reopen -> GPL-01D red | add exact `classify_path` group/test rule and group simulator entry after refresh; required closure |
| TC-238-02 | Legacy absence is ordinary and explicit unknown lifecycle follows the accepted fail-closed/fallback disposition without crashing. | `test/features/groups/domain/models/group_private_media_policy_test.dart::GPL-02 legacy and unknown lifecycle decode exactly as approved` | evidence-gated host unit / absent, known, unknown, malformed payload table | HEAD compile RED: types absent -> legacy default and accepted unknown result are exact | treat unknown inconsistently in live/offline paths -> GPL-02 red; exact mutation waits for ledger decision | add file to `GROUP_TESTS` after TC-238-00 |
| TC-238-03 | Only approved discussion roles/options can author policy, revalidated at send/retry; ordinary send remains unchanged. | `test/features/groups/domain/usecases/send_group_message_use_case_test.dart::GPL-03 private media authoring follows accepted role matrix at send time` | evidence-gated host application / role, membership, queued/revoked fixtures | HEAD RED: no policy -> every accepted/rejected combination and retry transition matches ledger | remove send-time revalidation or broaden one role -> GPL-03 red | existing use-case test; `GROUP_TESTS` |
| TC-238-04 | Optional sender policy stays in the encrypted inner payload and roundtrips through outgoing persist/retry, live listener, and offline drain; local consumption never leaks. | `test/features/groups/integration/group_private_media_payload_roundtrip_test.dart::GPL-04 private sender policy matches across send live offline and retry` | host integration / fake bridge + real repository, known/legacy payloads | HEAD compile RED -> exact accepted policy persists; absence standard; `mediaConsumedAt` absent from every outgoing map | drop one path, place fields in outer map, or serialize consumed state -> GPL-04 red | add file to `GROUP_TESTS` |
| TC-238-05 | View-once consumes at the exact accepted boundary and approved message/attachment granularity once, durably before cleanup; cancel/decode failure and sibling attachments follow the accepted matrix. | `test/features/groups/application/group_private_media_lifecycle_test.dart::GPL-05 view once transition is atomic idempotent granular and boundary exact` | evidence-gated host integration / production repository over host SQLite, multi-attachment temp files, fake decoder milestones | HEAD compile RED -> transition time/count and target/sibling file/row/placeholder state match each milestone/granularity | consume all attachments when one-item scope was approved, move consume boundary, or clean before durable state -> GPL-05 red after decisions | add file to `GROUP_TESTS`; blocked by TC-238-00 |
| TC-238-06 | Crash/restart at every consume cleanup seam cannot reopen consumed media or lose the truthful placeholder; cleanup resumes idempotently. | `test/features/groups/integration/group_private_media_crash_recovery_test.dart::GPL-06 consumed media stays unavailable across injected restart seams` | host integration / production repository over host SQLite + temp files + fresh controllers | HEAD compile RED -> fresh process sees consumed state first, never decodes, and converges cleanup | mark consumed only in memory or reconstruct from surviving attachment -> GPL-06 red | add file to `GROUP_TESTS` |
| TC-238-07 | Disappearing media expires according to the accepted anchor/duration/skew policy across foreground, background, restart, offline late arrival, and clock change. | `test/features/groups/application/group_private_media_expiry_test.dart::GPL-07 expiry state machine follows approved clock authority across lifecycle` | evidence-gated host/application + fake authoritative clock, lifecycle scheduler, host SQLite repository | HEAD compile RED -> boundary timestamps and late/offline cases are exact and monotonic under approved policy | use raw `DateTime.now`, reset timer on restart, or trust sender skew outside bound -> GPL-07 red after clock decision | add file to `GROUP_TESTS`; blocked by TC-238-00 |
| TC-238-08 | Consume/expiry cleanup removes only app-owned media/thumbnail/decode/playback state, preserves required placeholder/audit state, and blocks live/offline replay/redownload resurrection. | `test/features/groups/integration/group_private_media_cleanup_replay_test.dart::GPL-08 cleanup is scoped durable and replay cannot resurrect private media` | host integration / production repository over host SQLite, temp ownership tree, live+offline fixtures, download spy | HEAD compile RED -> target bytes/derived state removed; siblings/external copies survive; replay/download makes zero plaintext-availability transition | skip ingest guard, broad-delete paths, or delete state needed to block replay -> GPL-08 red | add file to `GROUP_TESTS` |
| TC-238-09 | Bubble/viewer/gallery/batch action capabilities centrally deny prohibited operations and expose only resolved group-owned rows. | `test/features/groups/presentation/group_private_media_capabilities_test.dart::GPL-09 every owner scoped group media surface shares fail closed private capabilities` | evidence-gated host widget / plans 230/235-237 harnesses, state table, same-ID direct/group/unresolved fixtures | HEAD compile RED -> Save/Share/Forward/Bookmark/resume/PiP/thumbnail actions match policy before/after consume/expiry; direct/unresolved fixtures never surface or mutate | guard viewer only, use capability union in batch, remove owner predicate, or accept unresolved -> GPL-09 red | add file to `GROUP_TESTS`; blocked on action matrix |
| TC-238-10 | Private-media notifications redact title/body/caption/thumbnail exactly per accepted lock-screen/foreground matrix and never trigger download/decode. | `test/features/groups/application/group_private_media_notification_test.dart::GPL-10 notifications apply approved redaction without plaintext fetch` | evidence-gated host application/widget / notification sink and download/decode spies | HEAD RED: no policy branch -> exact generic body/visibility and zero plaintext calls | reuse ordinary caption/thumbnail or hydrate attachment for preview -> GPL-10 red | add file to `GROUP_TESTS`; blocked on notification matrix |
| TC-238-11 | Android/iOS capture behavior and user copy match the accepted best-effort platform guarantee, including route transitions/background/app switch. | `integration_test/group_private_media_platform_proof_test.dart::GPL-11 protected viewer applies truthful platform capture safeguards` | external-fixture-blocked device proof / each applicable Android/iOS target available at execution, screenshot/record session | HEAD device RED: no platform mechanism -> only accepted observable behavior passes; unsupported limits are surfaced, not claimed away | omit secure flag/capture observer, leak app-switch snapshot, or leave protection after route exit -> GPL-11 red | add an exact `classify_path` rule recording this path as `ignored/ignored` manual-native proof; run directly on each applicable available target and record unavailable platform legs `N/A (target unavailable by project policy)` |
| TC-238-12 | Sender policy survives real Go bridge encryption/decryption through existing extras with no Go node production change. | `integration_test/group_real_crypto_onboarding_test.dart::GPL-12 private media policy survives real Go bridge encrypted group payload`; `go-mknoon/node/pubsub_delivery_test.go::TestGPL12PrivatePolicyUsesExistingEncryptedExtras` | single-device real bridge + host two-node Go test | HEAD RED: bridge whitelist drops fields -> known policy survives; absence standard; outer event has no leaked private fields beyond decrypted payload map | drop field, move it outside encrypted payload, or edit node protocol -> GPL-12 red | existing group reliability-sim path + exact Go command in `groups` gate |
| TC-238-13 | Device-local or multi-device consume/expiry behavior matches the accepted convergence promise; conflicts/offline replay are deterministic. | `integration_test/group_private_media_convergence_proof_test.dart::GPL-13 consumed and expired state follows approved device convergence policy` | external-fixture-blocked / one device if local-only; one USB physical Android + one Android emulator with automated interaction, plus relay, if convergent | HEAD evidence RED: no policy/protocol/harness -> selected profile proves no unintended sync or authenticated convergence/conflict semantics | N/A until ledger selects local-only vs convergent; then withhold/drop/reorder the state event as mutation | registration and closure command cannot be finalized before decision; row blocks closure if product promises convergence |
| TC-238-14 | Relay blob/late-download behavior matches the accepted retention/revocation wording and never overclaims deletion. | `integration_test/group_private_media_relay_retention_proof_test.dart::GPL-14 late relay access follows approved private media retention contract` | external-fixture-blocked / controlled relay clock/blob fixture only if remote revocation is promised | HEAD evidence RED: no relay contract -> selected fixture observes exact availability/revocation deadline or row is explicitly N/A for local-only wording | N/A until blob/revocation decision; then retain a blob past deadline as mutation | do not register transport work unless TC-238-00 explicitly selects it |
| TC-238-15 | Announcements remain on their current ordinary-media semantics and authoring rules; shared schema decoding alone adds no private UI/action there. | `test/features/groups/presentation/group_private_media_announcement_sentinel_test.dart::GPL-15 discussion private lifecycle does not alter announcements` | `GREEN sentinel` extension / announcement reader/admin fixtures | HEAD current behavior GREEN -> remains green and no plan-238 private controls/routes appear | remove `GroupType.chat` policy boundary -> GPL-15 red | add file to `GROUP_TESTS`; existing announcement sentinels |
| TC-238-16 | Approved optional-field plumbing changes no existing group transport semantics. | `test/features/groups/integration/group_private_media_transport_boundary_test.dart::GPL-16 private policy uses only approved encrypted extra and local state paths` | host source-contract / exact allowlist | HEAD compile RED: sources absent -> allows group policy/model/db/send/listen/drain and narrow Go bridge params; rejects node/topic/recipient/key/inbox/retry semantic edits | edit Go node production or add consume event without accepted convergence scope -> GPL-16 red | add file to `GROUP_TESTS`; node-production status/binary-diff baseline comparison below |

### Test Notes

- TC-238-00 is a genuine execution stop, not documentation theater. Until each decision is accepted, later HEAD-to-GREEN and mutation descriptions that depend on it are intentionally conditional.
- TC-238-05/06/08 require fresh database/repository/controller construction and injected failures between persistence and each cleanup side effect; a single happy-path widget test cannot close view-once.
- TC-238-11 must test observable platform behavior and app-switch snapshots on each applicable available target; unavailable platform legs are N/A and retain host/native proof. It must not assert “screenshots impossible” on a platform that cannot guarantee that claim.
- TC-238-13/14 become required only if the accepted user promise includes account-wide convergence or remote blob revocation. If wording is explicitly local-device cleanup, record those rows N/A with the accepted wording and prove no consume event/relay mutation exists.

## Implementation Steps

1. Resolve every Evidence Decision Ledger row with product/security/platform owners, user-facing wording, and selected proof profile. Keep status evidence-gated and make no production/test/schema edits until then.
2. After acceptance, snapshot `git status --short`, inspect the live database constant/migration files/full-chain plus all accepted plan claims, allocate the then-next free version, replace vNEXT with the actual owner/predecessor/filename in this plan, and run independent review. Stop on any conflict or lane-contract mismatch.
3. Verify plans 229/230/235-237 that the accepted implementation uses have landed; add structural TC-238-01 as the first executable RED only after the allocation refresh/review.
4. Add the allocated idempotent migration, app version/on-create/on-upgrade/full-chain wiring, typed local policy, legacy/unknown decoding, and local-only map/wire boundaries. Add production-engine device TC-238-01D; do not call host SQLite a SQLCipher proof.
5. Thread accepted sender policy through send/retry and existing encrypted extras, narrow Go bridge params/options, live listener, offline drain, repository, and notification preclassification. Keep Go node production unchanged unless a separately accepted follow-up owns transport.
6. Implement the accepted consume/expiry state machine durable-first with authoritative clock, restart scheduler, scoped idempotent cleanup, and ingest/download/replay guards.
7. Feed one central policy into plans 230/235-237 capabilities, thumbnails, playback, notifications, and any accepted platform capture mechanism.
8. Add the exact selected device/relay fixtures and explicit `classify_path` records: GPL-01D as `group/test`, existing GPL-12 path remains `group/test`, and GPL-11 as `ignored/ignored` manual-native proof. Never rely on a filename wildcard. Run records/discovery checks, host/device/relay mutations, sentinels, family gates, analyzer, and hygiene.

## Risks And Blind Spots

- False privacy promise is the highest risk -> TC-238-00 blocks partial implementation and TC-238-11/13/14 tie wording to real boundaries.
- Consume timing races with decoder/crash -> TC-238-05/06 inject every milestone and reconstruct fresh state.
- Expiry depends on untrusted clocks/offline delivery -> TC-238-07 requires accepted authority/skew behavior.
- Replay/redownload can restore deleted bytes -> TC-238-08 gates ingestion and download with durable state.
- Cross-device conflict can leak a second view -> TC-238-13 requires explicit local-only wording or authenticated convergence proof.
- Capture APIs differ fundamentally -> TC-238-11 proves platform-specific behavior and unsupported limits.
- Notification/app-switch thumbnails can leak before viewer -> TC-238-10/11.
- Migration/wire unknown values can weaken policy -> TC-238-01/01D/02/04.
- Lifecycle / derived-state durability: canonical consumed/expiry state is DB-backed; file/cache/viewer state is reconstructible and must fail closed -> TC-238-05..08.
- Sibling-surface consistency: one policy drives bubble/viewer/gallery/batch/notification -> TC-238-09/10.
- Destructive-action side effects: TC-238-08 proves only target app-owned derived state is removed and required placeholder/audit/siblings survive.
- Invariant re-verification under new transitions: send role, viewer action, download, decode, resume, and notification each re-evaluate current policy/state rather than trusting stale UI.
- Announcement regression -> TC-238-15 and plan-242 ownership boundary.

## Gate Cadence

- While evidence-gated, no implementation closure sweep is authorized. After refresh, per-plan closure is the selected focused host tests, the curated `groups` gate, and every approved SQLCipher, real-bridge, native-capture, multi-device, or relay proof.
- `feature-host-all`, `core-host-all`, and full `host-all` are not individual Plan-238 closure gates; migration/full-chain behavior is exercised by the exact commands below.
- Full `host-all` runs once after the complete private-lifecycle wave (`234`, `238`, and `242`) and once at final rollout closure.

## Acceptance Gates

```bash
# Evidence stop: do not continue while any decision remains unresolved
! rg -n '\| unresolved \|' Test-Flight-Improv/238-group-private-media-lifecycle-tdd-plan.md

# Accepted feature dependencies; database version is allocated only after a fresh conflict review
test -f Test-Flight-Improv/228-shared-media-library-bookmark-persistence-tdd-plan.md
test -f Test-Flight-Improv/232-1to1-received-media-forwarding-tdd-plan.md
test -f Test-Flight-Improv/236-group-received-media-forwarding-tdd-plan.md
git status --short
git status --short --untracked-files=all -- go-mknoon/node \
  ':(exclude,glob)go-mknoon/node/*_test.go' \
  ':(exclude,glob)go-mknoon/node/**/*_test.go' \
  > /tmp/plan-238-go-node-production-status.before
git diff --binary -- go-mknoon/node \
  ':(exclude,glob)go-mknoon/node/*_test.go' \
  ':(exclude,glob)go-mknoon/node/**/*_test.go' \
  > /tmp/plan-238-go-node-production-diff.before
rg -n '^const int currentIdentityDatabaseVersion = ' lib/core/database/app_database_version.dart
rg --files lib/core/database/migrations test/core/database/migrations | sort | tail -40
rg -n '^[-*] Migration:|exclusively (DB )?v[0-9]+|owns v[0-9]+' Test-Flight-Improv/*.md

# Stop here, allocate vNEXT, persist the actual version/filename/predecessor in this plan, and re-review.
# First executable causal RED after that refresh; expect non-zero because the allocated migration is absent.
flutter test test/core/database/migrations/group_private_media_lifecycle_vnext_test.dart --plain-name 'GPL-01 allocated vNEXT preserves owner scoped legacy and private lifecycle state idempotently'

# Focused host GREEN selected by accepted policy
flutter test test/core/database/migrations/group_private_media_lifecycle_vnext_test.dart
flutter test test/features/groups/domain/models/group_private_media_policy_test.dart
flutter test test/features/groups/domain/usecases/send_group_message_use_case_test.dart --plain-name 'GPL-03'
flutter test test/features/groups/integration/group_private_media_payload_roundtrip_test.dart
flutter test test/features/groups/application/group_private_media_lifecycle_test.dart
flutter test test/features/groups/integration/group_private_media_crash_recovery_test.dart
flutter test test/features/groups/application/group_private_media_expiry_test.dart
flutter test test/features/groups/integration/group_private_media_cleanup_replay_test.dart
flutter test test/features/groups/presentation/group_private_media_capabilities_test.dart
flutter test test/features/groups/application/group_private_media_notification_test.dart
flutter test test/features/groups/presentation/group_private_media_announcement_sentinel_test.dart
flutter test test/features/groups/integration/group_private_media_transport_boundary_test.dart

# Migration chain, Go extra boundary, and curated affected-lane gate
flutter test test/core/database/integration/full_migration_chain_test.dart
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge ./node -run 'GPL12|GK030' -count=1)
./scripts/run_test_gates.sh groups

# Discover real devices plus required SQLCipher/bridge fixtures; exact platform/convergence/relay commands are finalized by TC-238-00
flutter devices --machine
./scripts/check_reliability_simulation_discovery.sh --records-tsv | rg '^group\ttest\tintegration_test/group_private_media_lifecycle_db_proof_test\.dart\t'
./scripts/check_reliability_simulation_discovery.sh --records-tsv | rg '^group\ttest\tintegration_test/group_real_crypto_onboarding_test\.dart\t'
./scripts/check_reliability_simulation_discovery.sh --records-tsv | rg '^ignored\tignored\tintegration_test/group_private_media_platform_proof_test\.dart\t'
./scripts/run_reliability_simulations.sh group --list | rg 'group_(private_media_lifecycle_db_proof|real_crypto_onboarding)_test.dart'
flutter test -d "$FLUTTER_DEVICE_ID" integration_test/group_private_media_lifecycle_db_proof_test.dart --plain-name 'GPL-01D real SQLCipher allocated vNEXT preserves legacy private state reopen and full chain'
flutter test -d "$FLUTTER_DEVICE_ID" integration_test/group_real_crypto_onboarding_test.dart --plain-name 'GPL-12 private media policy survives real Go bridge encrypted group payload'

# Capture proof after accepted Android/iOS guarantee; repeat with an explicit discovered id for each applicable available platform
flutter test -d "$FLUTTER_DEVICE_ID" integration_test/group_private_media_platform_proof_test.dart --plain-name 'GPL-11 protected viewer applies truthful platform capture safeguards'

# Hygiene
git status --short --untracked-files=all -- go-mknoon/node \
  ':(exclude,glob)go-mknoon/node/*_test.go' \
  ':(exclude,glob)go-mknoon/node/**/*_test.go' \
  | cmp -s - /tmp/plan-238-go-node-production-status.before
git diff --binary -- go-mknoon/node \
  ':(exclude,glob)go-mknoon/node/*_test.go' \
  ':(exclude,glob)go-mknoon/node/**/*_test.go' \
  | cmp -s - /tmp/plan-238-go-node-production-diff.before
flutter analyze
git diff --check
```

## Device/Relay Proof Profile

- Profile: `external-fixture-blocked` until TC-238-00 selects the promise. Minimum known boundaries are single-device production SQLCipher and real-Go-bridge; protected capture runs on each applicable Android/iOS target available at execution, with unavailable platform legs recorded `N/A (target unavailable by project policy)`; non-iOS-specific convergence/revocation uses one pinned USB physical Android plus one pinned Android emulator and a controlled relay.
- Boundary being proven: freshly allocated group-private migration/full-chain/default/mapping/idempotence/reopen on password-protected `sqflite_sqlcipher`; optional policy encryption through the real bridge; consume/expire and capture behavior matching user wording; any account-wide convergence or remote blob revocation at the actual device/relay boundary.
- Live availability check: `flutter devices --machine` and group reliability-sim discovery. No device id, second-user fixture, controllable relay clock/blob store, or platform guarantee is assumed at planning time.
- Required setup: production `sqflite_sqlcipher` plugin for self-contained GPL-01D DB files and existing real-Go group crypto fixture for GPL-12. GPL-11 uses applicable platform target(s), a private image/video fixture, and screenshot/screen-record/app-switch observation. If selected, GPL-13 pins a USB physical Android plus Android emulator and automates all peer actions; GPL-14 setup remains decision-dependent.
- Closure role: GPL-01D, GPL-12, and every platform guarantee named to users are required closure. Host SQLite/mocks cannot close SQLCipher, native capture, native bridge, multi-device, or relay claims.
- `FLUTTER_DEVICE_ID`: sufficient only for GPL-12 and one platform capture run. It is insufficient for a two-device convergence promise or both-platform capture promise.
- Registration: edit `classify_path` in `scripts/check_reliability_simulation_discovery.sh` explicitly. Add `integration_test/group_private_media_lifecycle_db_proof_test.dart` to the exact group reliability-device case (`record "group" ... "test"`); keep existing exact `group_real_crypto_onboarding_test.dart` group record for GPL-12; add an exact `group_private_media_platform_proof_test.dart` case under ignored paths (`record "ignored" ... "ignored" "manual native private-media capture proof outside reliability-sim"`). GPL-13/14 require their own explicit rules after evidence selection.
- Discovery commands: the three literal `--records-tsv | rg` checks in Acceptance Gates, followed by `./scripts/run_reliability_simulations.sh group --list | rg 'group_(private_media_lifecycle_db_proof|real_crypto_onboarding)_test.dart'`. The capture proof must be ignored/manual and therefore must not appear in group `--list`.
- Closure commands: GPL-01D, GPL-12, and GPL-11 commands in Acceptance Gates. GPL-13/14 have no truthful exact command until TC-238-00 supplies fixture topology; if their promise is selected, this plan must be refreshed before implementation.
- Deferred device work: none for guarantees actually selected. A decision to keep behavior device-local/no remote revocation records GPL-13/14 N/A and forbids corresponding user claims/transport edits.

## Execution Interpretation And Done Criteria

- Expected evidence RED: TC-238-00 currently fails because every ledger row is unresolved. No production/test/schema action is authorized.
- Expected first executable RED after evidence/allocation refresh: TC-238-01 fails because the allocated migration and fields do not exist.
- Green sentinels: ordinary legacy group media, group integrity validation, IR-020 deletion replay, Go GK030 extra delivery, and announcement authorization/read-only behavior remain green.
- Pre-existing dirty tree / known failure: record from execution-time snapshot; do not absorb unrelated changes.
- Evidence blocker: any unresolved ledger row keeps the plan evidence-gated; do not substitute developer preference for product/security acceptance.
- Environment blocker: failures on selected available targets or a missing required relay/authority fixture block their corresponding guarantee; unavailable mobile target legs are `N/A (target unavailable by project policy)` and retain host/native proof.
- Scope drift: unauthenticated consume event, new transport/topic, Go node production edit, universal capture claim, remote revocation claim, or announcement UI without accepted evidence requires replanning.

- [ ] Evidence Decision Ledger has accepted owner/date/user wording/test profile for every row.
- [ ] Every selected behavior has a named causal test or real-boundary proof; unselected guarantees are explicitly N/A and absent from copy/code.
- [ ] First executable RED, focused GREEN, and representative mutation re-red are recorded.
- [ ] Fresh conflict check allocated exactly one next-free version and persisted the actual predecessor/number/filenames before implementation.
- [ ] The allocated migration passes structural host plus real-SQLCipher device idempotence, legacy-default, approved explicit-state, reopen, mapping, and full-chain tests.
- [ ] Send/live/offline/retry/real-bridge payload semantics agree and consumption remains local-only unless separately approved.
- [ ] Consume/expiry is durable-first, crash-safe, replay/download-safe, and scoped.
- [ ] Viewer/gallery/batch/notification/platform behavior shares one current policy.
- [ ] Required proofs pass on every selected available device/multi-device/relay boundary for each user-facing guarantee; unavailable mobile legs are recorded N/A.
- [ ] Announcement, ordinary-media, group/core/feature, analyzer, and hygiene sentinels pass; node-production status/binary diff matches its pre-execution baseline while allowed node tests may extend.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: none while TC-238-00 is unresolved or vNEXT is unallocated. After the required conflict-check refresh/review: `flutter test test/core/database/migrations/group_private_media_lifecycle_vnext_test.dart --plain-name 'GPL-01 allocated vNEXT preserves owner scoped legacy and private lifecycle state idempotently'`.
- Preservation command: `flutter test test/features/groups/domain/usecases/send_group_message_use_case_test.dart --plain-name 'returns unauthorized for non-admin in announcement group'` plus `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'GK030' -count=1)`.
- Harness registration: new host files into `GROUP_TESTS`; the structural migration remains AUTO-discovered and runs by exact command here; exact `classify_path` group records for SQLCipher DB/real bridge and exact ignored/manual-native record for capture; convergence/relay get explicit records only after accepted evidence.
- Migration: unallocated vNEXT. After TC-238-00, claim the freshly verified next free version and persist its exact predecessor/table/columns/filename; message-level lifecycle columns are provisional and must change if attachment-level/mixed policy is accepted. Plan 242 reuses that eventual migration without another claim.
- Boundary closure: selected combination of host crash/replay, real Go bridge, available-platform capture, multi-device, and relay proof; currently external-fixture/evidence blocked.
- Unresolved evidence: every row in the Evidence Decision Ledger; specifically policy granularity, role, consume boundary, expiry clock/skew, device convergence, moderation/report, capture guarantee, blob/replay, notification, and unknown-value disposition.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-09 | evidence gate | plan only | source/graph audit complete | all lifecycle/platform/transport gaps confirmed | Evidence Decision Ledger unresolved; no implementation authorized | product/security/platform decision review |
