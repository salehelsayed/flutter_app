# 244 - 1:1 Received Media Reporting

Status: evidence-gated
Type: New Feature
Spec: free-text intent — a truthful, privacy-minimized Report action for incoming direct-chat image/video, isolated from ordinary media actions and message transport
Classification: evidence-gated
Closure tier: external-authority conditional

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | `graphify-arch` direct-media query; conversation viewer/overlay/wired files; block-contact flow; media/message models; notification/diagnostic privacy patterns; repository/service/localization search; plans 227/230/231 | HEAD has a local contact Block flow but no moderation/report authority, gateway, payload, consent/retention contract, queue, receipt, or Report localization. Faking Report as telemetry/Block/Delete would be misleading. | Resolve D-244-01..07, choose an authority and proof environment, then refresh tests/scope before authoring REDs. |

## Problem And Evidence

- Behavior to improve: while viewing or long-pressing an incoming direct-chat image/video, a user should be able to report abusive or unsafe content and receive a truthful outcome.
- Impact: Report is a common safety expectation, but its presence creates a strong promise that evidence reaches an authorized moderation destination. A no-op, analytics event, or local Block operation would falsely imply review.
- Confirmed current gap: the message overlay exposes Reply/Edit/Copy/Delete only at `lib/features/conversation/presentation/widgets/message_context_overlay.dart:16-39`, `:286-316`; the current viewer has no media actions at `lib/shared/widgets/media/full_screen_image_viewer.dart:62-79`.
- Confirmed current mechanism: `ConversationWired` supports local contact blocking at `lib/features/conversation/presentation/screens/conversation_wired.dart:4196-4337`, but no report repository/service/authority is called.
- Confirmed absence: repository-wide source/localization searches found no direct abuse-report gateway, queue, receipt, moderation API, or report-specific message type under `lib/`. Existing uses of "report" concern diagnostics/test reports, not user safety submissions.
- Confirmed privacy boundary: direct media contains caption, sender/contact identifiers, local path, encryption metadata, and bytes. None may leave the device merely because a menu item was tapped; an approved payload/consent/retention contract is required.
- Existing coverage: conversation action tests cover Reply/Delete/Block and plan 231 will cover Save/Share/Info/action parity. No existing test can prove report eligibility, evidence minimization, submission, idempotency, offline retry, receipt, or optional side effects.
- Missing coverage: authority authentication, report category/reason, payload allowlist, byte consent/limits, identifier pseudonymization, queue durability, retries/idempotency, outcome copy, Block/Delete ordering, cancellation, expired/deleted source handling, accessibility, and transport boundary.
- Refuted finding: Block is not a substitute for Report. It changes only the local contact relationship and provides no evidence delivery or moderation receipt.
- Refuted finding: reusing normal 1:1 send, Forward, relay inbox, or go-libp2p to send abuse evidence is not source-grounded and could expose the reporter to the reported peer.
- Unresolved findings (blocking): **D-244-01** report authority, jurisdiction/availability, authentication, and whether moderation exists; **D-244-02** report categories, free text, subject identity, and minimal identifiers; **D-244-03** whether caption/thumbnail/original bytes may be attached, explicit consent, size/redaction/encryption, retention/deletion/access policy; **D-244-04** whether Block and Delete for Me are optional/default/required side effects and their ordering/rollback independence; **D-244-05** online/offline queue, retry/idempotency, cancellation, restart, status, and user receipt semantics; **D-244-06** handling of missing/expired/deleted/protected media plus reporter/reportee notification and appeal expectations; **D-244-07** rate limits, abuse/spam protection, diagnostics, support escalation, and real-authority test environment.
- Affected production/test/gate files are conditional: plan-230/231 action capability wiring, a new report domain/gateway/UI, l10n, possibly secure durable queue state, and dedicated host/external-service tests. No migration or transport file is reserved until decisions define the mechanism.

## Scope Contract And Guard

Conditionally in scope after D-244-01..07:
- Add Report as a direct incoming-media action in both bubble and current viewer item only when an approved authority is available and policy says the item is eligible.
- Define immutable report draft/request/result/receipt types with an explicit allowlist; default to metadata-only and require separate informed consent before any media bytes or caption are included.
- Add an injected report gateway authenticated to the approved authority. The gateway must not be a normal direct-message, Forward, relay inbox, analytics, or local Block call.
- Provide exactly-once UI submission semantics, idempotent server/client identity if approved, truthful online/offline/pending/sent/failed/cancelled copy, and durable restart behavior only if D-244-05 selects queueing.
- Keep optional Block and Delete for Me as separately observable actions/results; failure of one must not be presented as report failure/success unless D-244-04 explicitly defines that coupling.
- Redact diagnostics and enforce payload byte/type/size/retention rules in one application boundary, not only in UI.

Must preserve:
- Plan-231 Save/Share/Delete-for-Me/Info/Reply action set remains execution-ready and cannot depend on reporting decisions -> TC-244-01/12.
- Incoming Delete for Me remains local; outgoing Delete for Everyone remains sender-authorized; Block remains its current local relationship operation -> existing `GREEN sentinels` plus TC-244-07.
- Media source files, rows, encryption keys/nonces, raw local paths, and exported copies remain unchanged unless the user separately confirms an approved Delete-for-Me side effect -> TC-244-03/04/07.
- Group/discussion/announcement report behavior is not inferred from direct chat -> TC-244-11.

Hard `Do not`:
- Do not implement or display Report until D-244-01..07 are approved and this plan is refreshed to execution-ready.
- Do not claim a report was sent/reviewed when only telemetry, Block, Delete, OS Share, direct messaging, relay inbox, or local persistence occurred.
- Do not send raw filesystem paths, encryption keys/nonces, unapproved peer identifiers, contact profile data, caption, thumbnail, or media bytes.
- Do not notify the reported peer or reuse their encrypted direct channel unless an approved safety architecture explicitly requires it and a separately reviewed threat model/protocol plan owns it.
- Do not edit go-libp2p, relay, group/announcement payloads, or message dedup/delivery in this plan.
- Do not reserve a DB version speculatively. If durable queueing is selected, refresh against the then-current migration ledger and prove the exact schema separately.

Deferred / accepted difference:
- Until this plan becomes execution-ready, plan 231 intentionally keeps Report absent while shipping the other core actions.
- Reporting text messages, profiles, groups, discussions, announcements, or whole conversations -> separate safety product owners after the direct authority is established.
- Moderation operations, appeals, evidence access, and retention tooling outside the app -> authority/backend program, not inferred Flutter work.
- Camera capture of a displayed image and revocation of already-exported copies remain outside report submission control.

Dependencies:
- `Test-Flight-Improv/230-shared-typed-media-viewer-tdd-plan.md` supplies caller-owned action capability/current-item identity.
- `Test-Flight-Improv/231-1to1-received-media-core-actions-tdd-plan.md` supplies direct bubble/viewer action parity and remains independent; this plan later adds the Report capability through that seam.
- D-244-01..07 and an accessible test authority are mandatory. A durable queue, schema migration, or backend/relay protocol requires a refreshed or separate plan after those choices.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-244-01 | Report remains absent while no approved authority/configuration exists, while all plan-231 core actions remain available. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::incoming visual media long press exposes the eligible core action set` | `GREEN sentinel` after plan 231 / unavailable report capability + plan-231 action fixture | HEAD/plan-231 causal test establishes exact core keys and Report absence -> remains GREEN until this plan has approved authority/configuration | default missing authority to enabled or hide another core action with it -> TC-244-01 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'incoming visual media long press exposes the eligible core action set'`; plan-231 file in both 1:1 arrays |
| TC-244-02 | With an approved authority, Report appears only for eligible incoming direct media and targets the exact current attachment/message after viewer swipe. | `test/features/conversation/presentation/screens/conversation_received_media_report_test.dart::eligible bubble and viewer report exact current direct media identity` | evidence-gated widget / authority capability + cross-message typed items | HEAD causal RED: action absent -> eligibility/current identity become exact after D-244-01/06 | enable outgoing/text/group/missing items or retain the initial viewer item -> TC-244-02 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_report_test.dart --plain-name 'eligible bubble and viewer report exact current direct media identity'`; reserve AUTO + both 1:1 arrays; blocked by D-244-01/06 |
| TC-244-03 | Report request contains only approved category/reason/identifiers, excludes all denied fields, and diagnostics expose only redacted request prefix/outcome. | `test/features/conversation/application/build_received_media_report_test.dart::report payload is explicit allowlist and diagnostics are redacted` | evidence-gated host unit / maximal source fixture + recording gateway/event sink | HEAD compile RED: draft/request absent -> exact allowlist and negative field assertions follow D-244-02/03/07 | serialize message/media maps wholesale, include path/key/contact profile, or log request body -> TC-244-03 red | `flutter test test/features/conversation/application/build_received_media_report_test.dart`; reserve AUTO + both 1:1 arrays; blocked by D-244-02/03/07 |
| TC-244-04 | Media bytes/caption/thumbnail cross the gateway only if approved and explicitly consented, within exact type/size/redaction limits; cancel preserves all source state. | `test/features/conversation/application/build_received_media_report_test.dart::evidence inclusion requires informed consent and enforces approved limits` | evidence-gated host application / temp media + consent/limit matrix | HEAD compile RED -> metadata-only default, explicit evidence branch, rejection/cancel cleanup, and source byte equality become exact after D-244-03 | attach bytes by default, bypass size/type limit, or delete source on cancel -> TC-244-04 red | Same focused file; reserve both 1:1 arrays; blocked by D-244-03 |
| TC-244-05 | One user submit produces one authenticated/idempotent authority request and one truthful receipt/result; double taps and late completions cannot duplicate or lie. | `test/features/conversation/application/received_media_report_controller_test.dart::submit is authenticated idempotent and settles exactly once` | evidence-gated host application / approved gateway fake + gated completers | HEAD compile RED: controller/gateway absent -> auth/idempotency/result assertions follow D-244-01/05/07 | omit idempotency key, allow double submit, accept unauthenticated success, or settle twice -> TC-244-05 red | `flutter test test/features/conversation/application/received_media_report_controller_test.dart --plain-name 'submit is authenticated idempotent and settles exactly once'`; reserve AUTO + both 1:1 arrays; blocked by D-244-01/05/07 |
| TC-244-06 | Approved offline/retry/cancel/restart behavior preserves exact draft/receipt state, retries safely, and never displays Sent before authority acknowledgement. | `test/features/conversation/integration/received_media_report_retry_test.dart::offline report follows approved durable retry and receipt semantics across reopen` | evidence-gated host integration / failure-recovery gateway + repository recreation | HEAD compile RED -> exact queued-versus-failed policy, retry identity, cancellation, and reopen behavior follow D-244-05 | turn enqueue into success, remint request on retry, lose cancellation, or retry forever -> TC-244-06 red | `flutter test test/features/conversation/integration/received_media_report_retry_test.dart`; reserve both 1:1 arrays; blocked by D-244-05 and any queue schema decision |
| TC-244-07 | Approved optional Block/Delete side effects are separately confirmed, ordered, and reported; report success/failure does not silently imply either action, and siblings/exports survive. | `test/features/conversation/application/received_media_report_side_effects_test.dart::report block and delete outcomes remain independent and preserve siblings` | evidence-gated host application/widget / report, block, delete spies + file snapshots | HEAD partial: Block/Delete exist separately but no report composition -> exact matrix follows D-244-04 | auto-block/delete without consent, couple unrelated failure, call delete-for-everyone, or delete export/sibling -> TC-244-07 red | `flutter test test/features/conversation/application/received_media_report_side_effects_test.dart`; reserve AUTO + both 1:1 arrays; blocked by D-244-04 |
| TC-244-08 | Missing, expired, protected, or locally deleted evidence follows approved metadata-only/unavailable behavior without re-download, resurrection, or false receipt. | `test/features/conversation/application/build_received_media_report_test.dart::unavailable source follows approved report evidence policy without recovery side effects` | evidence-gated host application / status matrix + throwing downloader | HEAD compile RED -> exact eligibility/result, zero implicit downloads, and source absence remain after D-244-03/06 | auto-download expired bytes, recreate a deleted row, or claim attached evidence -> TC-244-08 red | Same focused file; reserve both 1:1 arrays; blocked by D-244-03/06 |
| TC-244-09 | Categories, evidence consent, status/receipt, Block/Delete choices, and failures are localized, accessible, RTL-safe, and reachable on small screens. | `test/features/conversation/presentation/screens/conversation_received_media_report_test.dart::report flow is localized accessible and RTL-safe in small viewports` | evidence-gated widget / en/de/ar, semantics tester, 320x568 viewport | HEAD causal RED: UI/copy absent -> exact approved strings/actions become assertable after D-244-02..06 | hardcode English, truncate retention/consent copy, or omit status semantics -> TC-244-09 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_report_test.dart --plain-name 'report flow is localized accessible and RTL-safe in small viewports'`; reserve both 1:1 arrays + existing ARB parity gate; blocked by copy decisions |
| TC-244-10 | A configured staging/real authority accepts one minimized request, enforces auth/idempotency/rate-limit behavior, returns a traceable receipt, and retains/deletes evidence per approved policy. | `integration_test/received_media_report_authority_proof_test.dart::approved authority accepts minimized direct media report exactly once` | conditional external-authority proof / test account, staging endpoint, audit receipt | HEAD has no gateway/authority. GREEN is undefined until D-244-01/03/05/07 supplies an environment and observable contract | replay idempotency key, omit auth, exceed limit, or retain evidence beyond approved window -> TC-244-10 fails | Dedicated `1to1` external-proof registration and command finalized after authority selection; host fake cannot substitute for an authority-delivery claim |
| TC-244-11 | Direct reporting imports no normal messaging/Forward/group/announcement/Bridge/relay/Go implementation and does not notify the reported peer. | `test/features/conversation/application/received_media_report_boundary_test.dart::report path is authority-isolated from messaging transports and sibling lanes` | evidence-gated host source-contract + throwing messaging spies + baseline path guard | HEAD compile RED: report sources absent -> forbidden imports/channel names/calls stay absent and Go/relay paths remain equal to the execution-start baseline after authority design | call `sendChatMessage`, `ShareBatchDeliveryCoordinator`, group publish, relay inbox, Bridge, or change a baseline Go/relay path -> TC-244-11 red | `flutter test test/features/conversation/application/received_media_report_boundary_test.dart`; reserve AUTO + both 1:1 arrays; refreshed plan must add baseline status+binary-diff commands |
| TC-244-12 | Save/Share/Delete-for-Me/Info/Reply, direct encryption/dedup/retry, and existing Block behavior remain unchanged when Report is disabled, cancelled, failed, or completed. | Plan-231 tests plus `conversation_wired_test.dart` Block/Delete sentinels and direct exchange/encryption tests | `GREEN sentinels` / existing host fixtures | GREEN on HEAD/plan 231 -> remain GREEN through every approved report outcome | make core actions depend on report gateway, mutate source message, or reuse delivery retry state -> sentinel red | Run plan-231 focused files, direct exchange/encryption, existing Block/Delete tests, and both 1:1 gates after implementation |

### Test Notes

- TC-244-02..11 are conditional obligations. Do not author success-path production or a fake GREEN until the authority, payload, retention, side effects, retry, and receipt semantics are approved.
- TC-244-03/04 require negative assertions for every sensitive field and byte source, not only a snapshot of allowed fields.
- TC-244-05/06 distinguish local queue acceptance from authority acknowledgement. Product copy may say Pending when queued; it must not say Sent/Reported until the approved authority confirms.
- TC-244-10 is mandatory for any claim that moderation receives reports. A mocked HTTP success or analytics event is not boundary proof.

## Implementation Steps

1. Do not implement. Resolve D-244-01..07 with product/safety/privacy/legal/backend owners and identify a staging/real authority capable of returning observable receipts.
2. Refresh this plan with the exact authority protocol, authentication, allowlisted request schema, evidence consent/retention, side-effect matrix, retry state machine, and any durable persistence. Recheck the migration ledger instead of assuming a DB number.
3. If the authority requires a new backend, relay, or protocol, create a separate narrow service/transport plan with independent threat-model/review/proof; keep direct messaging and Go/libp2p untouched here.
4. Run `$tdd-review` on the refreshed plan(s). Only after an execution-ready verdict, add TC-244 causal REDs before production edits.
5. Implement request/policy/gateway/controller first, then UI/action wiring and optional side effects, then durable retry if selected, then real-authority proof.
6. Register only direct-owned tests, run plan-231 and direct-delivery preservation gates, exercise payload/idempotency/side-effect mutations, and enforce scope/hygiene guards.

## Risks And Blind Spots

- A decorative Report action can create dangerous false confidence -> D-244-01 and TC-244-05/10 require an authenticated observable authority.
- Evidence can leak more harm than needed -> TC-244-03/04/08 enforce an allowlist, explicit consent, limits, and negative fields.
- Pending/offline UI can be mistaken for submitted -> TC-244-05/06 separate queue state from authority acknowledgement.
- Lifecycle / derived-state durability: conditional TC-244-06 recreates queue/repository and preserves idempotent receipt state when queueing is approved.
- Sibling-surface consistency: TC-244-02 compares bubble and current viewer item; TC-244-01/12 keep plan-231 actions independent.
- Destructive-action side effects: TC-244-07 proves confirmation, independent outcomes, whole-message local deletion, and sibling/export preservation.
- Invariant re-verification under new transitions: eligibility/source existence/consent/auth/idempotency are rechecked at submit/retry, not trusted from menu-open time, in TC-244-03..08.

## Acceptance Gates

```bash
# Snapshot before any future execution; record unrelated changes
git status --short

# Structural blocker inventory only; this does not approve the decisions
rg -n 'D-244-01|D-244-02|D-244-03|D-244-04|D-244-05|D-244-06|D-244-07' Test-Flight-Improv/244-1to1-received-media-reporting-tdd-plan.md
test -f Test-Flight-Improv/231-1to1-received-media-core-actions-tdd-plan.md

# Approval evidence gate: no shell command can close it. Written D-244-01..07 decisions,
# an observable authority fixture, refreshed exact contracts, and tdd-review are required.

# First causal RED after refresh: N/A while authority/payload/outcome are unspecified
# Do not use an analytics, Block, Delete, or no-op implementation to force GREEN.

# Preservation baseline after execution-ready plan 231 lands
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'incoming visual media long press exposes the eligible core action set'
flutter test test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh 1to1 --list

# Conditional focused and authority gates are added only after refresh
flutter test test/features/conversation/application/build_received_media_report_test.dart
flutter test test/features/conversation/application/received_media_report_controller_test.dart
flutter test test/features/conversation/application/received_media_report_side_effects_test.dart
flutter test test/features/conversation/integration/received_media_report_retry_test.dart
flutter test test/features/conversation/presentation/screens/conversation_received_media_report_test.dart
flutter test test/features/conversation/application/received_media_report_boundary_test.dart

# Scope/hygiene after later implementation
# Refreshed plan must record and compare Go/relay status+binary diff against its
# execution-start baseline; a raw clean-tree assertion is invalid on current dirt.
flutter analyze
git diff --check
```

## Device/Relay Proof Profile

- Profile status: authority-blocked. There is no current moderation endpoint/test account/protocol in the repo, so host tests cannot close a user-visible "reported" claim.
- Required boundary if remote moderation is approved: a dedicated staging/real authority test proves authenticated minimized upload, idempotent replay, rate limiting, typed failure, observable receipt, and approved retention/deletion. The final runner depends on the chosen protocol and must be written into the refreshed plan.
- Device requirement: not inherently required for a pure Dart authority gateway; add Android/iOS runs only if evidence selection uses native pickers, background transfer, OS credentials, or platform storage. Do not add device ceremony without a native boundary.
- Relay requirement: none by default. Reporting must not reuse the messaging relay. If an approved architecture intentionally adds a separate relay/backend component, a separate service/transport plan owns its implementation and real-service proof.
- Offline branch: if D-244-05 chooses durable background queueing, prove kill/restart/network-loss/recovery on the actual supported runtime and distinguish queued from authority-acknowledged. If it chooses fail-and-retry, TC-244-06 asserts no hidden queue.
- Registration: use a dedicated `received_media_report_authority_proof_test.dart` exact `1to1` record; do not classify broad messaging/relay suites merely to imply coverage.
- Current blocker: authority/product/privacy evidence, not device availability.

## Execution Interpretation And Done Criteria

- Expected RED: N/A while evidence-gated; an observable GREEN cannot be defined before the authority and request/result contract.
- Green sentinel: Report absent without authority; plan-231 core actions and ordinary direct encryption/dedup/retry/Block/Delete remain unchanged.
- Pre-existing dirty tree / known failure: snapshot at any future execution start and preserve unrelated changes.
- Environment blocker: a missing approved/staging authority blocks any claim that reports are delivered, even if host UI/controller tests pass.
- Scope drift: guessed payload/retention/side effects, speculative migration, normal messaging/relay reuse, or Go/group/announcement edits block progress.

- [ ] D-244-01..07 are approved by relevant product/safety/privacy/authority owners.
- [ ] The refreshed plan names the exact allowlist, negative fields, consent, retention, auth, idempotency, offline, receipt, and side-effect behavior.
- [ ] Every approved behavior has a causal test and representative mutation; TC-244-10 closes real authority delivery.
- [ ] Core actions remain independent and Report remains absent when authority/configuration is unavailable.
- [ ] New tests are registered only in owning 1:1 inventories; any migration uses a freshly verified free version.
- [ ] Direct messaging, group/announcement, Bridge/relay/Go paths remain unchanged unless a separate accepted plan owns them.
- [ ] `flutter analyze`, `git diff --check`, and scope guards pass.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: N/A — resolve D-244-01..07, identify the authority fixture, refresh the plan, and run `$tdd-review` first.
- Preservation command: `flutter test test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart`.
- Manual registration: after refresh, add dedicated direct report host files to both 1:1 arrays and the dedicated authority proof to an exact `1to1` external-proof inventory. Do not broaden unrelated suites.
- Migration: none reserved. Durable queue selection may require a later version only after rechecking the then-current ledger, with its own structural/full-chain/real-storage proof.
- Boundary closure: real/staging report authority when the product claims delivery; device/relay proof only if the approved architecture actually introduces those boundaries.
- Unresolved evidence: D-244-01..07 and an observable authority/test environment. Status remains `evidence-gated`.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | D-244-01..07 and authority fixture unresolved | obtain decisions and refresh plan |
