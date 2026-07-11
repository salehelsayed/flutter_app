# 246 - Announcement Received-Media Reporting

Status: evidence-gated
Type: New Feature
Spec: free-text intent — let an announcement recipient report incoming image/video safely and truthfully without reusing group-message publication
Classification: evidence-gated
Closure tier: external-authority/device conditional

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector | plan-specific `graphify-arch` query; `lib/`, `go-mknoon/`, and `go-relay-server/` report/moderation searches; group send/validator paths; announcement action tests | HEAD contains no trust-and-safety report gateway, endpoint, durable queue, result model, or ownership boundary; unrelated diagnostic uses of “report” are not moderation | require an approved production destination and privacy/retry contract before coding |
| 2026-07-09 | Planner | plan 239 core action boundary; plans 230/242 typed capability and protected-media contracts; group pubsub/inbox authorization | Reporting must be a separately authenticated moderation operation, not a reader `group_message`, and its UI cannot claim success from a test-only/no-op gateway | define evidence gates, non-negotiable privacy invariants, causal tests, and real-boundary closure |

## Problem And Evidence

- Behavior to improve: a recipient who encounters harmful or abusive image/video content in an announcement needs a Report action, explicit reason/consent flow, and a truthful accepted/queued/rejected outcome.
- Impact: without a real reporting path, users cannot escalate content from the media surface; a cosmetic action would be worse because it could imply safety review that never occurs.
- Confirmed root cause/current gap: repository-wide searches under `lib/`, `go-mknoon/`, and `go-relay-server/` find no moderation/trust-and-safety repository, report endpoint/command, durable report queue, or receipt model. Hits such as telemetry “report” and Go report-card dependencies are unrelated.
- Confirmed transport constraint: announcement member publication is rejected in Flutter at `lib/features/groups/application/send_group_message_use_case.dart:809` and in Go at `go-mknoon/node/pubsub.go:1605`/`isAllowedWriter`; a report must not masquerade as a `group_message`, `group:publish`, or `group:inboxStore` event.
- Confirmed surface dependency: plan 239 intentionally owns only Save, Share, Delete for me, and Info; plan 230 supplies optional typed viewer capabilities. Reporting can extend those surfaces after its gateway exists without reopening local-core ownership.
- Existing coverage: `group_conversation_wired_test.dart::non-admin in announcement group cannot write` and Go `TestIsAllowedWriter_AnnouncementMemberBlocked` protect the no-publish invariant. No existing test proves moderation submission.
- Missing coverage: request minimization, reason/consent mapping, authorization, deduplication, offline/restart retry, server receipt/result truthfulness, protected-media handling, UI parity, and no-side-effect behavior.
- Refuted findings: diagnostic telemetry, a copied debug report, message reactions, blocking a contact, and deleting a local message are not a production content report and cannot close this feature.
- Unresolved findings: production service/owner; reporter authentication and anti-abuse/rate limiting; target identity and reason taxonomy; whether media bytes may ever be attached and under what explicit consent; encryption/access/retention/deletion policy; durable outbox owner; retry/idempotency/receipt states; moderation SLA/user copy; and whether Report offers separate follow-up Block/Mute/Delete actions.
- Affected production, test, and gate files: an eventual moderation gateway/client and durable queue, announcement message/viewer action adapters, reporting reason/result UI, host contract tests, a real service fixture proof, and test-gate registration. Exact persistence/native/Go files remain decision-dependent and cannot be invented now.

## Evidence Decision Ledger

| Decision | Required accepted evidence | Current state | Consequence if unresolved |
|---|---|---|---|
| Production owner/destination | named service/repository owner, escalation path and non-production fixture | unresolved | no gateway or user-visible Report action |
| Authenticated transport | client/server authentication, authorization boundary, forged-request handling and threat review | unresolved | no network request implementation |
| Request/consent schema | versioned field allowlist, reason taxonomy, optional comment, byte-upload consent and disclosure copy | unresolved | no request model or privacy test oracle |
| Retention/deletion/access | data classes, encryption, reviewer access, deletion deadline and audit policy | unresolved | no payload or fixture provisioning |
| Durable outbox/migration | owning persistence seam, exact state machine and migration allocation if required | unresolved | no Queued claim or restart retry |
| Result/retry/idempotency | accepted/queued/rejected/retryable receipt semantics, operation-key scope and retry limits | unresolved | no truthful result UI or dedupe proof |
| Anti-abuse | rate limits, duplicate/forged submission behavior and reporter safety controls | unresolved | no production acceptance proof |
| Follow-up actions | whether Block/Mute/Delete are offered separately and exact no-side-effect default | unresolved | no post-submit UI |
| Boundary fixture | device/account, service URL, short-lived auth authority and approved secure test-channel/keychain injection, sanitized audit oracle, retention cleanup owner and exact discovery category/rule | unresolved | no real closure command or registration can be finalized |

## Scope Contract And Guard

In scope after the evidence gate is approved:
- Define typed `AnnouncementMediaReportRequest`, reason/optional-comment policy, attachment-consent policy, idempotency key, and `accepted/queued/rejected/retryable` result semantics against a named production `AnnouncementMediaReportGateway`.
- Expose Report on both announcement message and typed viewer surfaces for a persisted incoming non-system media message. Reporting metadata must remain possible when the local media file is missing/evicted, because local download availability is not the moderation identity.
- Present explicit privacy copy listing the data to be sent. Default request contains only the approved identifiers/metadata; attaching decrypted bytes requires a separate, affirmative user choice and an approved encrypted upload/retention contract.
- Persist an offline submission only if the approved architecture supplies a durable outbox with retry count, next attempt, idempotency key, terminal receipt, and restart recovery. Display Queued only after durable commit and Accepted only after an authoritative service receipt.
- Keep optional Block sender, Mute announcement, and Delete for me as separate, explicit follow-up actions delegated to their existing owners. Reporting alone mutates none of those states.
- Add server/relay-side authentication, authorization, rate-limit, deduplication and receipt proof in the owning service if the approved architecture requires it.

Must preserve:
- Announcement readers remain unable to send into the source announcement -> Flutter/Go sentinels TC-246-09.
- Plan-239 Save/Share/Delete/Info remain independently available and do not depend on reporting service health -> TC-246-01/07.
- Protected/view-once media never bypasses plan-242 egress rules; a metadata-only report does not imply permission to export or retain media bytes -> TC-246-08.
- Missing gateway/network/receipt never renders Accepted -> TC-246-05/06.

Hard `Do not`:
- Do not implement Report as `sendGroupMessage`, `group:publish`, `group:inboxStore`, reaction, reply, local delete, contact block, diagnostic telemetry, email composer, or an unowned URL.
- Do not send encryption keys/nonces, raw local paths, address-book data, unrelated messages, full media bytes, or captions/comments beyond the approved request and explicit disclosure.
- Do not use a random retry ID per attempt, acknowledge before durable server acceptance, silently retry forever, or collapse rejected/retryable/queued/accepted into one success state.
- Do not allocate a DB version, Go command, relay route, HTTP endpoint, retention promise, or screenshot of evidence until its production owner and privacy/security review approve it.
- Do not weaken announcement writer validation or expose original group content to report recipients through the ordinary group transport.

Deferred / accepted difference:
- Reply privately is root plan 247; blocking/muting/deleting are separate user choices and are not implied by Report.
- General text/profile/group reporting and an admin moderation dashboard are separate product scopes. This plan covers received announcement image/video only.
- If durable submission needs new schema, its exact version and real-SQLCipher migration proof must be assigned after the current migration ledger and outbox owner are approved; this evidence-gated plan reserves no version.

Dependencies:
- `Test-Flight-Improv/239-announcement-received-media-core-actions-tdd-plan.md` supplies the local action surface; `Test-Flight-Improv/230-shared-typed-media-viewer-tdd-plan.md` supplies optional viewer action capabilities.
- `Test-Flight-Improv/242-announcement-private-media-lifecycle-tdd-plan.md` supplies protected/view-once action policy.
- A named production moderation service, privacy/security decision record, authenticated client contract, and durable retry owner are blocking dependencies not present on HEAD.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-246-00 | Every reporting owner, privacy, transport, persistence, result and fixture decision is accepted before executable work starts | `Test-Flight-Improv/246-announcement-received-media-reporting-tdd-plan.md::Evidence Decision Ledger` | planning evidence / product-trust-security-backend sign-off | HEAD evidence RED: all ledger rows unresolved -> each row records accepted choice, owner, date, user copy and proof profile | N/A — this stop gate makes later mutations meaningful | manual plan-review gate; blocks every following row |
| TC-246-01 | Once configured, the same Report capability appears on eligible incoming announcement media in message and viewer without changing the four plan-239 core actions or compose state | `test/features/groups/presentation/announcement_media_reporting_test.dart::configured report action has message viewer parity without announcement write controls` | widget / typed capability fixtures, gateway-present flag | HEAD has no Report capability -> both surfaces open one reason flow, core actions remain, compose/quote callbacks remain absent | expose only one surface, gate Report on `canWrite`, or remove a core action -> TC-246-01 red | `flutter test test/features/groups/presentation/announcement_media_reporting_test.dart --plain-name 'configured report action has message viewer parity without announcement write controls'`; AUTO plus add to `GROUP_TESTS`; **blocked until gateway contract approval** |
| TC-246-02 | Reason, optional comment, and media-attachment consent map exactly to the approved versioned request and disclosure | `test/features/groups/application/report_announcement_media_use_case_test.dart::report request maps approved reason consent and disclosed fields exactly` | application host / approved contract fixture, fake gateway | HEAD request/gateway absent -> exact version/reason/fields match disclosure and omitted consent means no media bytes | add a field not named in disclosure or attach bytes by default -> TC-246-02 red | `flutter test test/features/groups/application/report_announcement_media_use_case_test.dart --plain-name 'report request maps approved reason consent and disclosed fields exactly'`; AUTO plus `GROUP_TESTS`; evidence-gated schema |
| TC-246-03 | Request validation rejects keys/nonces/raw paths/unapproved metadata and logs only redacted identifiers | `test/features/groups/application/report_announcement_media_use_case_test.dart::report privacy boundary rejects secrets paths and undisclosed payload fields` | application host / adversarial request fixtures, log sink spy | HEAD contract absent -> prohibited values never reach gateway/logs and return typed local rejection | serialize `MediaAttachment.toMap()` or log full request -> TC-246-03 red | `flutter test test/features/groups/application/report_announcement_media_use_case_test.dart --plain-name 'report privacy boundary rejects secrets paths and undisclosed payload fields'`; AUTO plus `GROUP_TESTS` |
| TC-246-04 | Offline submit commits one durable operation before showing Queued; restart retry reuses the same idempotency key and settles one terminal receipt | `test/features/groups/integration/announcement_media_report_retry_test.dart::offline report survives restart and retry settles once with stable idempotency` | host integration / real approved outbox persistence, scripted gateway | HEAD outbox absent -> one durable row survives reopen; attempts share key; accepted receipt removes/settles once without duplicate user state | generate key per retry, show queued before commit, or retry a terminal rejection -> TC-246-04 red | `flutter test test/features/groups/integration/announcement_media_report_retry_test.dart`; AUTO plus `GROUP_TESTS`; **schema/persistence owner evidence gate** |
| TC-246-05 | Accepted, queued, retryable, rejected, rate-limited, and unauthenticated outcomes render distinct truthful states and preserve retry policy | `test/features/groups/presentation/announcement_media_reporting_test.dart::report results never promote queue failure or rejection to accepted` | widget/application host / table-driven gateway results | HEAD result model absent -> every service/local outcome maps to exact UI and only permitted retry states retry | map every completed future to success or hide auth/rate-limit result -> TC-246-05 red | `flutter test test/features/groups/presentation/announcement_media_reporting_test.dart --plain-name 'report results never promote queue failure or rejection to accepted'`; AUTO plus `GROUP_TESTS` |
| TC-246-06 | Missing/unconfigured gateway is unavailable and never displays a submission success or mutates data | `test/features/groups/presentation/announcement_media_reporting_test.dart::missing report gateway is truthfully unavailable with zero side effects` | widget / null gateway, repo/bridge spies | HEAD has no action -> explicit unavailable state, no accepted/queued copy and zero mutations/commands | install no-op gateway returning accepted or hide failure -> TC-246-06 red | `flutter test test/features/groups/presentation/announcement_media_reporting_test.dart --plain-name 'missing report gateway is truthfully unavailable with zero side effects'`; AUTO plus `GROUP_TESTS` |
| TC-246-07 | Reporting alone leaves message/media/contact/block/mute/membership state unchanged and emits no source group command | `test/features/groups/application/report_announcement_media_use_case_test.dart::report submission has no local moderation or source announcement side effects` | application host / full repository and bridge command spies | HEAD use case absent -> only report gateway/outbox calls occur; all named state snapshots stay equal | auto-delete, auto-block, auto-mute, or call source publish/inbox -> TC-246-07 red | `flutter test test/features/groups/application/report_announcement_media_use_case_test.dart --plain-name 'report submission has no local moderation or source announcement side effects'`; AUTO plus `GROUP_TESTS` |
| TC-246-08 | Protected/view-once media can submit approved metadata while Save/Share/Forward and unconsented media-byte upload remain blocked | `test/features/groups/application/report_announcement_media_use_case_test.dart::protected media report cannot become an egress bypass` | application host / plan-242 lifecycle fixtures, report and egress gateway spies | HEAD lifecycle/report contracts absent -> metadata request allowed by decision, egress calls zero, bytes absent unless policy explicitly permits and consent true | reuse external Share temp file or ignore protection during evidence upload -> TC-246-08 red | `flutter test test/features/groups/application/report_announcement_media_use_case_test.dart --plain-name 'protected media report cannot become an egress bypass'`; AUTO plus `GROUP_TESTS`; depends on 242 |
| TC-246-09 | Reporting never grants announcement publication and native Go authorization still rejects a reader message | `test/features/groups/presentation/group_conversation_wired_test.dart::non-admin in announcement group cannot write` plus `go-mknoon/node/pubsub_test.go::TestIsAllowedWriter_AnnouncementMemberBlocked` | GREEN sentinel / Flutter widget and Go validator | GREEN on HEAD -> remains GREEN; reporting uses no group send path | route report as group payload or weaken writer role -> sentinel red | `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'non-admin in announcement group cannot write' && (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run TestIsAllowedWriter_AnnouncementMemberBlocked -count=1)`; existing `GROUP_TESTS` / Go preservation |
| TC-246-10 | Real authenticated service accepts one report, deduplicates the same operation, rejects a forged reporter, and exposes an authoritative receipt without payload leakage | `integration_test/announcement_media_reporting_boundary_proof_test.dart::real reporting fixture authenticates deduplicates and receipts one sanitized report` | device/external fixture / real approved client and service/relay audit fixture | HEAD fixture/transport absent -> accepted receipt correlated to one idempotency key; duplicate count one; forged request rejected; captured request omits prohibited fields | disable auth/dedupe or acknowledge at local enqueue -> boundary proof red | client command may pass only non-secret fixture URL; short-lived auth must be provisioned through the approved secure test channel/keychain, never CLI/build constants; exact command and exact discovery rule remain blocked by TC-246-00 |

### Test Notes

- TC-246-02/03 cannot use a test-authored “approved” payload as evidence. The production owner/privacy decision must enumerate every transmitted field, retention class, and optional byte-upload consent before the fixture is frozen.
- TC-246-04 requires a real persistence owner. An in-memory fake proves orchestration only and cannot justify Queued or restart-safe copy.
- TC-246-07 uses source group ID as an event discriminator: report-gateway event present, `group:publish`/`group:inboxStore` for that ID absent. A generic “one call succeeded” assertion is insufficient.
- TC-246-10's fixture must expose sanitized audit facts (operation key hash, auth verdict, dedupe count, receipt), never raw media or secrets in test artifacts.

## Implementation Steps

1. Stop before production edits and obtain a signed decision record naming the service owner, authenticated transport, request/consent schema, retention/deletion policy, reason taxonomy, result/SLA copy, durable outbox, idempotency, retry, and abuse controls.
2. Re-query source and the migration ledger after approval; update this plan with exact owned endpoint/client/persistence files and, if needed, a separately reserved DB migration with real-SQLCipher run-twice/full-chain proof. Stop-if: any required owner remains “TBD”.
3. Add TC-246-02/03/05/07/09 causal host tests against the approved contract before production code; add persistence tests only against the real outbox implementation.
4. Implement the typed gateway/use case and durable result state without importing group-send APIs; then extend plan-239/230 capability surfaces with the reason/disclosure flow.
5. Add authenticated server-side authorization, rate limiting, idempotency/deduplication, receipt and retention behavior in the approved owning service; do not place it in go-libp2p group-message framing.
6. Register new announcement host suites in `GROUP_TESTS`. After the fixture authority is selected, record and implement one exact path/category/runner rule for the real boundary test; generic “manual proof” classification is insufficient.
7. Run focused GREEN, no-side-effect/authorization sentinels, named gates, real fixture proof, analyzer, and diff hygiene. Status becomes execution-ready only after Steps 1-2 produce concrete evidence.

## Risks And Blind Spots

- Cosmetic/no-op reporting creates false safety confidence -> TC-246-05/06/10 require authoritative outcomes.
- Reporting can leak decrypted content, keys, paths, identity, or unrelated metadata -> TC-246-02/03/08 plus explicit disclosure and fixture audit.
- Retries can duplicate moderation cases or lose offline submissions -> TC-246-04/10 require durable commit and stable idempotency.
- Reusing group publication could weaken announcement authorization or reveal the report to members -> TC-246-07/09 prohibit source group commands and preserve Go validation.
- Lifecycle / derived-state durability: TC-246-04 reopens the approved outbox and settles terminal state exactly once; no claim is made before an owner exists.
- Sibling-surface consistency: TC-246-01 derives message/viewer visibility from one configured capability while preserving plan-239 core actions.
- Destructive-action side effects: TC-246-07 snapshots message/media/contact/block/mute/membership state; any follow-up action remains explicit.
- Invariant re-verification under new transitions: gateway validates current auth, schema version, consent and idempotency on every attempt; TC-246-03/04/10 cover stale/forged/retried transitions.

## Acceptance Gates

```bash
# Snapshot before execution; record unrelated changes
git status --short

# Evidence checkpoint; do not continue while any owner/contract row is unresolved
! rg -n '\| unresolved \|' Test-Flight-Improv/246-announcement-received-media-reporting-tdd-plan.md

# First causal RED after evidence approval; expect non-zero because typed gateway/use case is absent
flutter test test/features/groups/application/report_announcement_media_use_case_test.dart --plain-name 'report request maps approved reason consent and disclosed fields exactly'

# Focused GREEN; expect exit 0 and zero failed tests
flutter test test/features/groups/application/report_announcement_media_use_case_test.dart test/features/groups/presentation/announcement_media_reporting_test.dart test/features/groups/integration/announcement_media_report_retry_test.dart

# Announcement authorization preservation; expect Flutter pass and Go package ok
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'non-admin in announcement group cannot write'
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestIsAllowedWriter_AnnouncementMemberBlocked|TestGroupTopicValidator_AnnouncementNonAdminRejected' -count=1)

# Named gates; expect reporting host files selected and zero failures
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all

# Boundary discovery and client run after TC-246-00 records an exact inventory rule and secure auth provisioning
rg -n 'integration_test/announcement_media_reporting_boundary_proof_test\.dart' scripts/run_test_gates.sh scripts/check_reliability_simulation_discovery.sh
./scripts/check_reliability_simulation_discovery.sh
flutter test integration_test/announcement_media_reporting_boundary_proof_test.dart -d "$FLUTTER_DEVICE_ID" --dart-define=REPORTING_FIXTURE_URL="$REPORTING_FIXTURE_URL"

# Hygiene; expect no new analyzer issues and no whitespace errors
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected evidence RED: TC-246-00 currently fails because every ledger row is unresolved. No production/test/schema action is authorized.
- Expected executable RED: only after the evidence checkpoint, TC-246-02 compile-fails because no request/gateway exists; TC-246-04/10 fail because no approved durable outbox/service fixture exists.
- Green sentinel: plan-239 core actions, announcement reader read-only behavior, and Go publisher authorization remain green.
- Pre-existing dirty tree / known failure: record unrelated changes; do not edit the already-dirty `Test-Flight-Improv/00-INDEX.md` in this plan.
- Environment blocker: the approved authenticated reporting fixture, short-lived credential authority/secure provisioning channel, retention-safe audit access, exact discovery rule, and device are absent; host fakes cannot close production reporting.
- Scope drift: invented endpoint/schema, ordinary group-message transport, unconsented media upload, unauthoritative success, automatic block/mute/delete, or an unassigned migration blocks completion.

- [ ] Evidence Decision Ledger records accepted owner/date/user wording/proof profile for every row.
- [ ] Every behavior has a named test or justified proof after the decision record is concrete.
- [ ] Causal RED, focused GREEN, and representative mutation re-red are recorded.
- [ ] Queued and Accepted are proven at durable-commit and authoritative-receipt boundaries respectively.
- [ ] Request/log/fixture audit contains no prohibited data and optional bytes require explicit approved consent.
- [ ] Announcement publisher sentinels and plan-239 core actions pass.
- [ ] New host/device tests are registered and discovered.
- [ ] Real authenticated dedupe/receipt boundary proof passes; a fake does not substitute.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: none while TC-246-00 is unresolved; after acceptance, `flutter test test/features/groups/application/report_announcement_media_use_case_test.dart --plain-name 'report request maps approved reason consent and disclosed fields exactly'`.
- Preservation command: `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestIsAllowedWriter_AnnouncementMemberBlocked|TestGroupTopicValidator_AnnouncementNonAdminRejected' -count=1)`.
- Manual registration: after approval, add three host reporting files to `GROUP_TESTS`; TC-246-00 must name an exact inventory category/runner rule for `integration_test/announcement_media_reporting_boundary_proof_test.dart`, then register that literal path. A generic manual-proof bucket is not acceptance.
- Migration: none reserved. If the approved durable outbox needs schema, allocate the then-next free version and add PRAGMA/before-after/run-twice/full-chain real-SQLCipher proof before execution-ready status.
- Boundary closure: external-fixture-blocked device proof against the real authenticated moderation service; host fake is supporting evidence only.
- Unresolved evidence: production service/owner, transport/auth, exact payload and consent, retention/deletion, reason/SLA copy, durable outbox/migration, retry/idempotency/receipts, anti-abuse, and separate follow-up action behavior.

## Device/Relay Proof Profile

- Profile: external-fixture-blocked.
- Boundary being proven: real reporter authentication, sanitized request receipt, stable-id deduplication, forged-request rejection, and an authoritative service receipt that host fakes cannot establish.
- Live availability check: `flutter devices --machine` plus a health/auth probe defined by the approved reporting service -> no service fixture, authority, secure credential-injection channel or credentials exist on HEAD.
- Required setup: one real supported device, a non-production test reporter, seeded reportable announcement media, approved fixture URL, a short-lived credential provisioned through an approved secure test channel/keychain, sanitized audit access, and retention cleanup owned by the service team. No secret may appear in `--dart-define`, command arguments, build constants or logs.
- Closure role: required closure evidence.
- `FLUTTER_DEVICE_ID`: sufficient for device selection only; external service URL, secure short-lived auth provisioning, audit fixture and exact discovery rule are still required.
- Registration: evidence-blocked. Before execution-ready status, TC-246-00 must name one exact `classify_path` category and runner/array entry, and the literal `integration_test/announcement_media_reporting_boundary_proof_test.dart` path must be added there; a generic manual-proof rule is not sufficient.
- Discovery command: evidence-blocked until that exact rule is selected. The refreshed command must both run discovery and assert this literal path/category, not merely pass the global script.
- Closure command: auth injection is evidence-blocked. After authority selection, refresh this plan with the exact secure-channel/keychain provisioning command followed by `flutter test integration_test/announcement_media_reporting_boundary_proof_test.dart -d "$FLUTTER_DEVICE_ID" --dart-define=REPORTING_FIXTURE_URL="$REPORTING_FIXTURE_URL"`; no credential may be passed by CLI or build constant.
- Deferred device work: all boundary work remains blocked until the production service/privacy/security owners approve and provision the fixture.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | source proves no reporting production seam | external owner/contract/fixture absent | evidence decision record |
