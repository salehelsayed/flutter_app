# 245 - Group Received Media Reporting

Status: evidence-gated
Type: New Feature
Spec: free-text intent — add truthful, privacy-minimized reporting for incoming discussion-group image/video media after moderation authority and delivery semantics are approved
Classification: evidence-gated
Closure tier: external-authority/device conditional

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | group conversation/viewer/action surfaces, group repositories/send/listen/offline paths, notification/integrity/local-deletion code, search for report/moderation repositories and gates | HEAD has no report authority, destination, schema, durable queue, receipt, retention, or moderation backend. Treating a local tap/toast as “reported” would be false. Reporting was removed from implementation-ready plan 235 so ordinary actions can ship independently. | Product/trust/safety/security accept the reporting ledger, then refresh transport/storage proof and begin the policy RED. |

## Problem And Evidence

- Behavior to improve: a user viewing an incoming image/video in a `GroupType.chat` discussion should eventually be able to initiate an understandable safety report, confirm exactly what will be shared, and receive truthful queued/submitted/failed/acknowledged state.
- Impact: without a reporting path, users cannot escalate abusive group media. Without an approved authority and evidence contract, a Report button would either do nothing or leak private group content.
- Confirmed source action gap: the group bubble overlay and viewer expose no Report action. Plan 235 intentionally limits ordinary core actions to Save, Share, Delete for me, Info, and Reply; plan 245 is the sole owner of adding Report after evidence acceptance.
- Confirmed backend gap: repository-wide source search found no report repository, moderation use case, safety service client, report inbox/message type, durable report outbox, or report receipt model.
- Confirmed transport ambiguity: groups use encrypted P2P/pubsub/inbox delivery. There is no established trusted “platform moderator” endpoint or proof that group admins should receive private reports. Reusing ordinary group publish would disclose the report to the group and is not acceptable by assumption.
- Confirmed evidence sensitivity: locally available attachment state includes paths, hashes, encryption metadata, peer identifiers, captions, and decrypted bytes. Plan 235's Info contract deliberately redacts most of those; a report payload needs a separately approved minimization/encryption/access policy.
- Confirmed lifecycle interaction: plan 235 Delete for me can remove local message/media state, and plan 238 may consume/expire private media. Report evidence capture/retention must explicitly define ordering and whether safety evidence can outlive local visibility.
- Confirmed integrity boundary: `GroupMediaIntegrityPolicy` distinguishes verified displayable media from pending/failed/quarantined state. Reporting a message reference may be valid when plaintext is unavailable, but attaching media bytes must never silently bypass integrity/consent.
- Missing coverage: no eligibility, consent/category, minimized payload, authorization, encryption, queue/idempotency/retry, receipt, retention/deletion, rate-limit, lifecycle race, UI status, announcement isolation, or real destination proof exists.
- Refuted finding: “Report can be implemented as another share/send action” is false. Existing send/share recipients, encryption policy, receipts, retries, and user visibility are message-delivery contracts, not a confidential moderation channel.
- Unresolved findings that block implementation:
  - Report authority/destination: group owner/admins, an Mknoon trust service, a relay-operated queue, device-local export, or another explicitly governed actor.
  - Who may report and what objects are eligible: current member vs former member, incoming only, already-deleted/expired media, duplicate reports, and blocked senders.
  - Categories, optional text, confirmation wording, reporter anonymity/pseudonymity, and whether the reported sender/admin is notified.
  - Minimal evidence: ids/timestamps/sender/group membership proof, caption, content hash, thumbnail, encrypted blob, decrypted bytes, surrounding messages, and explicit per-field consent.
  - Encryption/access/key custody for evidence and whether destination can decrypt without broadening ordinary group access.
  - Retention/deletion/legal basis, reporter withdrawal, moderation audit, breach/log redaction, and exported-copy handling.
  - Offline behavior: no queue, durable outbox, cancel-before-send, retry schedule, idempotency key, deduplication, and app-restart semantics.
  - User-visible receipt: locally queued, transport accepted, authority acknowledged, actioned/rejected, timeout, and whether any of those states are actually available.
  - Abuse/rate limits and whether throttling occurs locally, at the destination, or both without exposing report existence.
  - Interaction with Delete for me, view-once/disappearing/protected media, and evidence preservation after consume/expiry.
- Affected production/test/migration/transport files cannot be named truthfully beyond the presentation/policy seam until those decisions are accepted. No DB version or Go/libp2p change is reserved by this evidence-gated draft.

## Evidence Decision Ledger

| Decision | Required accepted evidence | Current state | Consequence if unresolved |
|---|---|---|---|
| Authority/destination | named responsible actor, trust boundary, availability and moderation process | unresolved | no gateway or success state |
| Reporter/object eligibility | role/history/media-state matrix and send-time revalidation | unresolved | no Report capability policy |
| UX/consent | categories, optional text, confirmation copy, anonymity/disclosure | unresolved | no sheet/action wiring |
| Payload minimization | field-by-field required/optional/forbidden list and surrounding-content rule | unresolved | no report request model |
| Evidence crypto/access | encryption, key custody, authorized readers, integrity proof | unresolved | no media/evidence upload |
| Retention/deletion | duration, deletion/withdrawal, audit/legal owner, logs/backups | unresolved | no persistence/upload cleanup |
| Offline/idempotency | queue/cancel/retry/dedup/restart contract | unresolved | no storage schema or scheduler |
| Receipt/status | exact observable queued/submitted/acknowledged/failed meanings | unresolved | no truthful success UI |
| Abuse controls | rate/size limits and privacy-preserving rejection behavior | unresolved | no production enablement |
| Lifecycle interaction | order and evidence rights across delete/consume/expire/protected state | unresolved | no integration with plans 235/238 |

## Scope Contract And Guard

Provisional in scope after every ledger row is accepted:
- Incoming image/video messages in `GroupType.chat` only, subject to the accepted reporter/object eligibility matrix.
- Extend the central group media capability policy from plan 235 with a distinct `report` capability; add the same selected-item action to plan 230's typed viewer and the bubble overlay.
- Present category/details/consent confirmation that lists the approved evidence classes before any durable capture or network call. Cancel changes nothing.
- Construct a typed, versioned, privacy-minimized request from approved fields only. Use opaque report/idempotency ids; redact secrets/paths/keys/nonces and avoid raw media by default.
- Revalidate membership/eligibility, message identity, media integrity/availability, private lifecycle state, and rate limit at submission time.
- Use a dedicated `GroupMediaReportGateway` only after its authority, encryption, and receipt contract is approved. Do not route through ordinary `SendGroupMessageUseCase` or OS Share.
- If offline queueing is approved, make it durable, encrypted at rest, bounded, idempotent, restart-safe, and cancellable exactly as decided. At evidence refresh, inspect what has actually landed and all accepted claims, then allocate the freshly verified next free DB version; assume no fixed predecessor now and add real SQLCipher proof then.
- Display only states the gateway can prove. “Queued locally” is not “submitted”; “transport accepted” is not “moderator acknowledged” or “action taken.”
- Apply approved retention/deletion to payload, media copy, thumbnail, temp files, encryption material, logs, and queue rows; preserve only the authorized audit record.
- Define deterministic interaction with plan 235 Delete for me and plan 238 consume/expiry so a race cannot capture forbidden bytes, lose an already-authorized report, or resurrect private media.

Must preserve:
- Plan 235 ordinary Save/Share/Delete-for-me/Info/Reply remains implemented/device-proven and independent; absence/failure of reporting cannot disable it.
- Group media integrity and path ownership; no report path may weaken viewer/egress/forward gates.
- Announcement reader/admin behavior and announcement action surface; this plan is discussion-only.
- Existing group message delivery, group membership/key distribution, relay inbox, retries, and Go node/libp2p unless the accepted destination explicitly requires a separately reviewed transport expansion.
- Local message deletion and private-media lifecycle invariants.

Hard `Do not`:
- Do not add a visible Report action, fake/no-op gateway, optimistic success toast, or analytics-only “report” while the ledger is unresolved.
- Do not send the report as an ordinary group/contact message, publish it to the reported group, or silently notify the reported sender/admin.
- Do not upload decrypted media, surrounding messages, captions, keys/nonces, raw filesystem paths, address book data, or unrelated group membership without explicit approved necessity/consent.
- Do not call a new endpoint/relay/topic, edit Go bridge/node, add a DB migration, or create a durable queue before destination/offline contracts and proof topology are accepted.
- Do not call local queueing “submitted,” network acceptance “reviewed,” or timeout “rejected.”
- Do not let Delete for me, expiry, or app restart duplicate a report or restore consumed/expired media.
- Do not alter `GroupType.announcement` or `GroupType.qa`; their reporting policy requires its own lane decision.

Deferred / accepted difference:
- Reporting is not part of plan 235 completion and may ship later.
- Block/mute/leave group, Delete for everyone, moderator removal, appeals, and case-management UI are separate features unless the accepted authority explicitly adds them to a refreshed scope.
- Announcement reporting is deferred; plan 245 does not grant announcement admins or readers a report path.
- No schema version is reserved. If durable queue/audit state is approved, perform a fresh migration-ledger/source conflict check at evidence refresh and allocate the next free version after whatever has actually landed, with host structural plus device SQLCipher proof.
- No transport implementation is reserved. A service API, P2P moderator inbox, or relay queue has materially different security/proof needs and must be selected before code.

Dependencies:
- Plan 230 typed selected-item viewer and implemented/device-proven plan 235 group media action policy/surfaces.
- Plan 238 accepted lifecycle policy if reports may include or outlive private media; otherwise the ledger must explicitly prohibit that behavior.
- Product/trust/safety/security/legal approval for every Evidence Decision Ledger row.
- A controlled destination/receipt fixture and any required device/relay topology selected by that approval.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-245-00 | Reporting work cannot begin until every governance/security/delivery decision is accepted with owner/date/user copy/proof profile. | `Test-Flight-Improv/245-group-received-media-reporting-tdd-plan.md::Evidence Decision Ledger` | planning evidence / trust-safety-security-product review | HEAD evidence RED: every row unresolved -> all rows record one accepted decision and linked authority evidence | N/A — this stop gate makes later causal mutations possible | manual plan-review gate; blocks all following rows |
| TC-245-01 | Report capability appears only for objects/reporters approved by the accepted discussion eligibility matrix and is revalidated at submit time. | `test/features/groups/application/group_media_report_policy_test.dart::GMR-01 report eligibility follows approved discussion matrix at action and submit time` | evidence-gated host unit / role, membership, direction, integrity, lifecycle table | HEAD compile RED: policy/report capability absent -> every approved/denied transition is exact | remove group-type/direction/role/state or submit-time guard -> GMR-01 red after ledger acceptance | add file to `GROUP_TESTS` only after TC-245-00 |
| TC-245-02 | Bubble/viewer Report opens the same confirmation flow; category/details/consent and cancel behavior match approved UX. | `test/features/groups/presentation/group_media_report_flow_test.dart::GMR-02 report confirmation is explicit consistent and cancel safe` | evidence-gated host widget / plan-230/235 harnesses | HEAD RED: action/flow absent -> approved evidence disclosure/categories render and cancel causes zero persistence/gateway calls | submit on first tap, hide an evidence class, or diverge bubble/viewer flow -> GMR-02 red | add file to `GROUP_TESTS` |
| TC-245-03 | Typed request contains exactly approved fields and forbids sentinel paths/keys/nonces/unrelated identities/surrounding content/raw bytes by default. | `test/features/groups/application/group_media_report_payload_test.dart::GMR-03 report payload is versioned minimized consent bound and secret free` | evidence-gated host unit / fully populated source with sentinel secrets | HEAD compile RED: request type absent -> exact key allowlist/version/consent record passes and every forbidden sentinel is absent | serialize a raw model/map, add one forbidden field, or omit consent version -> GMR-03 red | add file to `GROUP_TESTS` |
| TC-245-04 | Approved media evidence is integrity-checked, encrypted for only the approved authority, size-bounded, and cleaned according to retention; no unauthorized plaintext temp remains. | `test/features/groups/application/group_media_report_evidence_test.dart::GMR-04 evidence capture encryption access and cleanup match approved contract` | evidence-gated host integration / temp ownership tree, crypto/gateway fixture | HEAD compile RED -> exact hash/access/key recipient/size/temp lifecycle pass; ineligible media yields reference-only or denial as approved | reuse group media key, broaden recipients, skip integrity, or retain temp past policy -> GMR-04 red | add file to `GROUP_TESTS`; real authority crypto still needs boundary proof |
| TC-245-05 | Authority and reporter eligibility are checked against current/history rules without exposing report existence to unauthorized group actors. | `test/features/groups/application/group_media_report_authorization_test.dart::GMR-05 report authorization and disclosure follow approved authority model` | evidence-gated host integration / reporter/member/former-member/admin/sender fixtures | HEAD compile RED -> accepted actors/results exact; unauthorized observers receive no event/notification | trust stale UI membership or emit ordinary group event -> GMR-05 red | add file to `GROUP_TESTS` |
| TC-245-06 | Approved offline queue is encrypted/bounded/durable/idempotent/cancellable across restart, or submission fails truthfully when queueing is not offered. | `test/features/groups/integration/group_media_report_outbox_test.dart::GMR-06 offline submission follows approved queue cancel retry and restart contract` | evidence-gated persistence integration / fresh repository, fake clock/gateway; device SQLCipher if durable | HEAD evidence RED: no queue/contract -> chosen behavior and exact state transitions pass | drop idempotency, duplicate after restart, retry canceled row, or call local queue submitted -> GMR-06 red | DB/harness registration and migration number assigned only after ledger decision |
| TC-245-07 | Retry/backoff/dedup and partial transport failures produce one authority case per idempotency key and never duplicate evidence upload. | `test/features/groups/application/group_media_report_delivery_test.dart::GMR-07 report delivery is idempotent and status truthful across failures` | evidence-gated host application / deterministic timeout, accepted, duplicate, permanent failure gateway | HEAD compile RED -> call count/state/receipt transitions exactly match approved protocol | mint id on retry, reupload accepted bytes, or conflate timeout with rejection -> GMR-07 red | add file to `GROUP_TESTS`; boundary proof required |
| TC-245-08 | UI distinguishes draft, queued, submitting, transport accepted, authority acknowledged, failed, canceled, and actioned only when the selected authority exposes them. | `test/features/groups/presentation/group_media_report_status_test.dart::GMR-08 report status labels never exceed available receipt evidence` | evidence-gated host widget / approved receipt-state fixture | HEAD compile RED -> only supported states/copy render and terminal transitions persist as approved | render “reported” for local queue or “reviewed” for HTTP/relay acceptance -> GMR-08 red | add file to `GROUP_TESTS` |
| TC-245-09 | Rate/size limits and duplicate-report handling are predictable, privacy preserving, and do not weaken ordinary media actions. | `test/features/groups/application/group_media_report_abuse_controls_test.dart::GMR-09 abuse controls are scoped truthful and ordinary actions independent` | evidence-gated host application / fake clock/counters, duplicate source ids | HEAD compile RED -> accepted thresholds/results exact; Save/Share/Delete/Info/Reply capabilities unaffected | global-disable media actions or reveal another reporter/case count -> GMR-09 red | add file to `GROUP_TESTS` |
| TC-245-10 | Delete for me and private consume/expiry races follow the approved evidence order without duplicate capture, forbidden retention, or media resurrection. | `test/features/groups/integration/group_media_report_lifecycle_race_test.dart::GMR-10 report delete consume and expiry races converge to approved state` | evidence-gated host integration / SQL structural repository, temp files, injected interleavings | HEAD compile RED -> each ordering preserves exact authorized report/evidence and local lifecycle invariants | capture after consent/state revocation, delete authorized outbox unexpectedly, or restore source media -> GMR-10 red | add file to `GROUP_TESTS`; depends plan 238 decision |
| TC-245-11 | Diagnostics, analytics, crash output, and UI never contain forbidden report evidence or reveal existence to unrelated actors. | `test/features/groups/integration/group_media_report_privacy_contract_test.dart::GMR-11 report telemetry and errors redact payload evidence and destination secrets` | evidence-gated host source/runtime contract / sentinel logger/crash/gateway errors | HEAD compile RED -> approved opaque ids/status only; every sentinel absent | interpolate request/error body or local path -> GMR-11 red | add file to `GROUP_TESTS` |
| TC-245-12 | Announcement/QA group surfaces and their authoring/read-only semantics remain unchanged. | `test/features/groups/presentation/group_media_report_flow_test.dart::GMR-12 report remains discussion only and announcements unchanged` | `GREEN sentinel` extension / discussion, announcement reader/admin, QA fixtures | HEAD announcement behavior GREEN/no report -> discussion follows policy; other types expose/call nothing | remove `GroupType.chat` guard -> GMR-12 red | `GROUP_TESTS`; existing announcement sentinels |
| TC-245-13 | Report delivery reaches the approved real authority with the approved encryption/idempotency/receipt behavior. | `integration_test/group_media_report_destination_proof_test.dart::GMR-13 approved authority receives one minimized encrypted report and returns truthful receipt` | external-fixture-blocked / topology selected by ledger: staging service, controlled relay, or moderator device(s) | HEAD evidence/device RED: no authority/fixture -> one real report is decryptable only by authority, deduped on retry, and exposes only approved receipt states | N/A until authority selected; then withhold/reorder/duplicate/corrupt receipt or use wrong key as mutation | registration/closure command cannot be finalized before TC-245-00; row required for any network-delivery claim |
| TC-245-14 | Reporting adds no unapproved ordinary group transport or Go/libp2p change. | `test/features/groups/integration/group_media_report_transport_boundary_test.dart::GMR-14 report code touches only approved authority gateway and never group publish` | host source-contract / exact allowlist after authority decision | HEAD compile RED: files absent -> forbids group send/publish/ordinary inbox and any unapproved bridge/node path | route through `SendGroupMessageUseCase` or edit topic/auth/fanout/retry outside approved transport plan -> GMR-14 red | add file to `GROUP_TESTS`; `git diff` allowlist selected after ledger |

### Test Notes

- TC-245-00 is the first and current RED. Creating a gateway interface with no governed destination does not satisfy it.
- TC-245-03 uses an exact serialized-key allowlist plus sentinel secret values; “does not show on screen” is insufficient payload minimization proof.
- TC-245-06 requires a new migration only if durable queue/audit state is approved. Host SQLite proves structure; a dedicated password-protected `sqflite_sqlcipher` device proof must cover upgrade/fresh chain, default/data preservation, repeat, close/reopen, and cleanup.
- TC-245-13 must run against the selected actual trust boundary. A fake gateway cannot close delivery, encryption-key custody, idempotency, or receipt claims.

## Implementation Steps

1. Keep implementation stopped. Resolve every Evidence Decision Ledger row with accountable product/trust/safety/security/legal owners, user-facing wording, and destination proof topology.
2. Refresh this plan after the decision: name the authority gateway/protocol and exact production/test files; if persistence is approved, inspect live source/accepted claims and allocate the freshly verified next free DB version with its actual predecessor and migration/device proof. Add exact destination discovery/closure commands and run independent TDD review before execution.
3. Verify plans 230/235 and any required accepted plan-238 lifecycle contract. Snapshot `git status --short`; add TC-245-01 as the first executable RED.
4. Add pure capability/authorization/payload policies and confirmation UI before gateway/storage implementation. Prove exact field allowlist/redaction and ordinary-action independence.
5. Implement only the approved dedicated gateway, evidence crypto/access, retention, abuse control, outbox/idempotency, and receipt states. Stop on any need to reuse ordinary group publish or expand unapproved Go/libp2p scope.
6. Integrate accepted lifecycle/delete ordering, add real authority/device/relay proof and discovery, then run focused/mutation/preservation tests, the curated `groups` lane gate, analyzer, and hygiene.

## Risks And Blind Spots

- Misidentified authority makes the feature meaningless or dangerous -> TC-245-00/05/13.
- Private group content can leak through raw models, errors, logs, or broad evidence -> TC-245-03/04/11.
- UI can overstate delivery/moderation -> TC-245-06/07/08/13.
- Retry can create duplicate cases/uploads -> TC-245-06/07 and real-boundary idempotency mutation.
- Delete/expiry races can either destroy authorized evidence or retain forbidden plaintext -> TC-245-10.
- A group publish shortcut can reveal reporter/report to the offender -> TC-245-05/14.
- Lifecycle / derived-state durability: queue/receipt state is durable only if approved; otherwise failure is immediate/truthful. Fresh-repository and destination proofs follow the selected contract.
- Sibling-surface consistency: bubble/viewer share plan-235 capability and one flow -> TC-245-01/02.
- Destructive-action side effects: approved report cleanup must not delete source/sibling/exported data; plan-235 Delete for me remains independently scoped -> TC-245-04/10.
- Invariant re-verification under new transitions: membership, rate, media integrity/lifecycle, consent, and authority availability revalidate at submit/retry rather than action-render time.
- Announcement regression -> TC-245-12 hard lane sentinel.

## Gate Cadence

- After evidence refresh, individual plan closure runs TC-245 focused tests, exact ordinary-action/announcement sentinels, the curated `groups` lane gate, and the selected real authority plus available-device/relay proof.
- Do not run `host-all`, `feature-host-all`, or `core-host-all` for Plan 245 closure; broad host coverage cannot substitute for the approved authority boundary.
- Run full `host-all` once after the 243-245 extension/reporting wave is complete, and once again at final media-rollout closure.

## Acceptance Gates

```bash
# Evidence stop: no executable work while any decision is unresolved
! rg -n '\| unresolved \|' Test-Flight-Improv/245-group-received-media-reporting-tdd-plan.md

# Accepted dependencies after the ledger and refreshed transport/storage contract
test -f Test-Flight-Improv/230-shared-typed-media-viewer-tdd-plan.md
test -f Test-Flight-Improv/235-group-received-media-core-actions-tdd-plan.md
git status --short

# First executable causal RED after TC-245-00; expect non-zero because report policy is absent
flutter test test/features/groups/application/group_media_report_policy_test.dart --plain-name 'GMR-01 report eligibility follows approved discussion matrix at action and submit time'

# Focused host contract after evidence acceptance
flutter test test/features/groups/application/group_media_report_policy_test.dart
flutter test test/features/groups/presentation/group_media_report_flow_test.dart
flutter test test/features/groups/application/group_media_report_payload_test.dart
flutter test test/features/groups/application/group_media_report_evidence_test.dart
flutter test test/features/groups/application/group_media_report_authorization_test.dart
flutter test test/features/groups/integration/group_media_report_outbox_test.dart
flutter test test/features/groups/application/group_media_report_delivery_test.dart
flutter test test/features/groups/presentation/group_media_report_status_test.dart
flutter test test/features/groups/application/group_media_report_abuse_controls_test.dart
flutter test test/features/groups/integration/group_media_report_lifecycle_race_test.dart
flutter test test/features/groups/integration/group_media_report_privacy_contract_test.dart
flutter test test/features/groups/integration/group_media_report_transport_boundary_test.dart

# Preserve ordinary actions and announcement behavior
flutter test test/features/groups/application/group_received_media_action_policy_test.dart
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'announcement'
./scripts/run_test_gates.sh groups

# Destination/migration/device commands are intentionally absent until TC-245-00 selects them;
# refresh this section before implementation and require that real boundary for closure.

# Hygiene
flutter analyze
git diff --check
```

## Device/Relay Proof Profile

- Profile: `external-fixture-blocked`; authority/destination is unresolved, so service-vs-relay-vs-moderator-device topology cannot be guessed.
- Boundary being proven: the actual approved authority alone receives/decrypts the minimized report once, retries deduplicate, retention/cleanup occurs as promised, and returned status supports the UI wording.
- Live availability check: N/A until authority is named. The refreshed plan must provide an availability command for the controlled staging service/relay/devices and must not reuse a generic group message simulation as substitute.
- Required setup: approved reporter/source fixture, authority credentials/keys, controllable offline/retry/duplicate/receipt behavior, evidence retention cleanup observation, and any device ids/relay endpoint selected by the ledger.
- Closure role: required for every delivery/encryption/receipt/retention claim. Host fakes close pure policy only.
- `FLUTTER_DEVICE_ID`: unknown/sufficient only if the selected topology is single-device; not enough for moderator-device or multi-peer delivery.
- Registration: unassigned. After evidence acceptance, add the exact integration path to the correct reliability/manual suite and discovery contract; do not leave TC-245-13 as an unclassified direct command.
- Discovery command: unassigned until the authority fixture exists; this is an evidence blocker that requires plan refresh, not an executor choice.
- Closure command: unassigned until authority/protocol/credentials are approved; this is why status remains evidence-gated.
- Deferred device work: none once a user-facing network report claim is selected. If the accepted feature is device-local export only, update closure tier/rows and do not use “submitted to moderation” wording.

## Execution Interpretation And Done Criteria

- Expected evidence RED: TC-245-00 currently fails because every ledger row is unresolved. No Report UI, gateway, queue, migration, or transport work is authorized.
- Expected first executable RED after evidence: TC-245-01 fails because the group media report policy/capability does not exist.
- Green sentinels: plan-235 ordinary action capability, group integrity, local deletion, and announcement read/write behavior remain green.
- Pre-existing dirty tree / known failure: record from execution-time snapshot; do not absorb unrelated changes.
- Evidence blocker: any unresolved ledger/destination/proof row keeps the plan evidence-gated; no fake gateway or developer-selected authority can clear it.
- Environment blocker: an unavailable selected authority/relay/SQLCipher fixture blocks its corresponding proof; unavailable mobile target legs are N/A by project policy, while failures on selected available targets remain blockers.
- Scope drift: ordinary group publish, raw evidence, new migration/version, Go/libp2p, announcement reporting, moderation case UI, or receipt wording outside accepted evidence requires replanning.

- [ ] Evidence Decision Ledger has accepted owner/date/user wording/proof profile for every row.
- [ ] Refreshed plan names exact authority protocol, files, optional migration version, harness registration, discovery, and closure commands.
- [ ] Every selected behavior has a named causal test or real-boundary proof.
- [ ] First executable RED, focused GREEN, and representative mutation re-red are recorded.
- [ ] Exact minimized payload/consent/crypto/access/retention and redacted telemetry tests pass.
- [ ] Queue/retry/idempotency/status behavior is durable and truthful if selected.
- [ ] Delete/private lifecycle races preserve only authorized state and never resurrect media.
- [ ] Real authority proof closes encryption, deduplication, receipt, and retention claims.
- [ ] Ordinary actions, announcements, the curated `groups` gate, analyzer, and hygiene pass.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: none while TC-245-00 is unresolved. After accepted/refreshed evidence: `flutter test test/features/groups/application/group_media_report_policy_test.dart --plain-name 'GMR-01 report eligibility follows approved discussion matrix at action and submit time'`.
- Preservation command: `flutter test test/features/groups/application/group_received_media_action_policy_test.dart` and the existing announcement wired/send sentinels.
- Harness registration: unassigned until authority and any persistence boundary are selected; host group files will join `GROUP_TESTS`, and real destination proof must join a discoverable device/relay suite.
- Migration: none reserved. If durable outbox/audit is approved, allocate the freshly verified next free version at evidence refresh after inspecting whatever has actually landed; require structural host plus production-SQLCipher device upgrade/fresh/reopen/run-twice proof.
- Boundary closure: actual approved report authority/destination; currently external-fixture blocked.
- Unresolved evidence: authority, eligibility, consent UX, minimized payload, evidence crypto/access, retention/deletion, offline/idempotency, receipt/status, abuse controls, and delete/private-lifecycle interaction.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-09 | evidence gate | plan only | graph/source audit complete | no reporting subsystem or governed authority exists | all Evidence Decision Ledger rows unresolved | trust/safety/security/product decision review |
