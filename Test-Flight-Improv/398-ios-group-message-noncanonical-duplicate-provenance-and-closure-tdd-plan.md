# 398 - iOS Group-Message Noncanonical Duplicate Provenance And Closure

Status: closed-unresolved
Type: Bug
Spec: free-text intent — explain and close Plan 397 run 21's second
noncanonical remote group-message card without weakening exactly-one delivery
Classification: retired-by-user
Closure tier: none (administrative closure; bug unresolved)

## Closure Notice

Closed at the user's direction on 2026-08-25. This is an administrative
retirement of Plan 398, not evidence that the notification bug was fixed or
that device closure passed.

- Do not resume this plan or execute any command, retry, amendment, or live
  authority recorded below.
- Preserve existing code changes and retained evidence as-is; this closure
  authorizes no cleanup, deletion, rollback, build, install, deployment,
  device action, marker, or message send.
- Any future work on the bug must begin from a brand-new session and prompt.
  It does not inherit execution authority from this document.
- Everything below this notice is historical context only.

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-23 15:11 CEST | Evidence Collector | `397-physical-iphone-group-chat-notification-verification-tdd-plan.md`; retained run-21 result/log artifacts; staging `relay-server` journal; relay, iOS inventory/handoff/NSE, harness, criteria, gates, and focused tests | Run 21 is a real duplicate: one event-bound remote request used the exact planned collapse identity, a second event-bound remote request used a different identifier, and the candidate relay recorded one provider acceptance on attempt 1. Flutter-local presentation, the Plan-397 retry, and absence of the canonical collapse header are refuted for that run. The second request's producer remains unresolved. | Plan bounded provenance capture before authorizing a repair. |
| 2026-08-23 15:17 CEST | Planner | Apple APNs/request-identifier/filtering documentation; Firebase collapse documentation; Graphify branches `6a5d09f723cd4c3c` and `90a04f9cb0f246fe` plus native fallback `974b59a2429544d4` | A sanitizer cannot honestly be planned as card suppression because the extension lacks the filtering entitlement. One diagnostic-only message window may classify provenance; a nonreproduction or opaque duplicate is not closure. | Author TC-398-01 through TC-398-08, keep status evidence-gated, then offer independent review. |
| 2026-08-23 15:43 CEST | Planner | completed Plan 398 and `00-INDEX.md` entry; TDD-plan sufficiency checklist | Diagnostic behavior, causal tests, mutations, registrations, literal gates, preservation, and real-device proof are total. The production root and root-repair mutation remain unknown, so the plan cannot honestly be execution-ready. | Keep `evidence-gated`; offer `$tdd-review`, then authorize TC-398-01 through TC-398-06 only if accepted. |
| 2026-08-23 17:26 CEST | Critical TDD-plan audit | current iOS inventory/sampler/handoff, installed Android observer, runner/criteria, relay gateway/metrics/projection, gate registration, retained run-21 files, and Apple/Firebase primary contracts; independent native, relay, and gate counterexample audits | The platform inference is sound, but the handoff was not: it capped before event matching, could lose transient-card provenance, had no run-owned expected-collapse-hash producer, cited ephemeral/raw evidence, over-specified relay outcomes, hard-pinned historical devices, used invalid validation syntax, omitted changed owners/registration, and placed unauthorized closure commands after a comment-only STOP. | Keep one plan and one scenario. Seal the baseline, implement only bounded diagnostics and terminal source attribution, run one diagnostic, restore staging, then amend this same plan once or remain gated. |
| 2026-08-23 pre-execution audit | Planner + three independent counterexample audits | revised native provenance schema, relay attribution/dispositions, runner attempt/receipt binding, focused gates, and literal staging state machine | The diagnostic model remained sound, but a later source-level review refuted the claim that proof registration and resume/rollback were already sufficient. Superseded by the correction row below. | Do not execute until the correction is incorporated. |
| 2026-08-23 review correction | Planner + three source-verification branches | exact proof selection, marker/artifact resume states, Sims input binding, deadline sampler, and group provider-size fallback | All six substantive review claims are confirmed. Keep one plan and one scenario; replace inline staging shell with one plan-specific host-tested helper, add the missing proof registration, close the deadline edge, and extend the existing provider-boundary test. | Execute only focused RED/GREEN and the transaction contract, then one diagnostic. |
| 2026-08-23 final coherence audit | Planner + three focused re-reviews | revised RED tokens, runtime provider-fallback owner, campaign claim/lock/lease, resume and signal restoration ordering, exact proof binding, focused gates | Corrections are coherent: one helper and one existing shell contract own transaction safety; runtime and build-time provider boundaries are separated; every row has one mutation; no extra scenario, framework, plan, broad gate, or device run was added. Production root remains intentionally evidence-gated. | Execute the written focused gates, then the single diagnostic only. |

## Problem And Evidence

- Behavior to improve: one Android-sent ordinary group text received while the
  physical iPhone app is backgrounded must create exactly one useful
  provider-owned iOS notification request. The later reaction and exact tap
  route may run only after that message boundary is clean.
- Impact: two cards for one group message violate user-visible exactly-one
  presentation, make source inventory fail closed, and prevent Plan 397 from
  reaching its reaction/tap closure leg.
- Confirmed current gap; root producer unresolved: the protected run-21 result
  currently survives at
  `/tmp/plan397-observation-state.cJVEuS/group-observation-result.json` with
  source-file SHA-256
  `fa9e984658a86d2151c9b6dc00abfa2cde953958afb15632b9cd81b603c8dfaf`.
  Before implementation, the evidence preflight must project its secret-free fields into a
  sealed run-21 baseline under the retained Plan-398 evidence directory; the
  `/tmp` file is input, never durable provenance. It completed at
  `2026-08-23T11:14:43.125Z` with
  `matchingRemoteCount=2`, `matchingUsefulProviderCount=1`,
  `matchingUnknownCount=1`, `matchingTotalCount=2`,
  `badSourceSeen=true`, and `duplicateSeen=true` across the full stable
  horizon. Its two SHA-256 request identifiers were distinct.
- Confirmed canonical request: the Android sender emitted one exact message.
  Independently applying Plan 397's `boundedGroupMessageIdentity` to the
  run-owned message identity yields request-identifier SHA-256
  `90e5a93461c990db01fe76b7d7b3527bd865a22c6e6520262720f55d8c9d7962`,
  exactly one delivered request hash. The other request hash,
  `405fb9584219e5eef8e2b48457dd7f7e910eba0306453404ddde6356a32c18fc`,
  is noncanonical for that event.
- Confirmed relay disposition: the staging journal from `11:14:20Z` through
  `11:14:50Z` contains exactly one
  `[PUSH] outcome=success attempt=1 total_attempts=3` and no
  retry/fallback/second success. The Android artifact records one
  live-and-inbox publish, one expected recipient, and one stored inbox row.
  Plan 397's retry did not create run 21's second request.
- Confirmed platform semantics: Apple documents that repeated APNs requests
  with the same `apns-collapse-id` are merged, and that a remote
  `UNNotificationRequest.identifier` equals the collapse identifier when one
  was supplied; otherwise the system assigns one.
  [APNs request headers](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)
  and
  [`UNNotificationRequest.identifier`](https://developer.apple.com/documentation/usernotifications/unnotificationrequest/identifier)
  are the external contract. Firebase supports `apns-collapse-id` for
  collapsible messages.
  [Firebase collapsible messages](https://firebase.google.com/docs/cloud-messaging/customize-messages/collapsible-message-types)
- Existing coverage:
  `TestRelayNotificationClosure_GroupMessageRetryCollapse` proves one stable
  collapse identity through retry and ordinary/strict projection. Plan 396's
  payload campaign proves final request-identifier hash equals expected
  collapse-identity hash.
  `testTC397GroupDeliveredInventoryClassifiesExactSources` and
  `testTC397GroupInventoryRequiresFullHorizonAndRejectsTransientLateLocalSibling`
  prove trigger-derived classification and sticky duplicate/bad-source
  detection.
- Missing coverage:
  `IosGroupNotificationInventory` returns aggregate counts and a sorted hash
  list, not a per-hash binding to trigger origin, source class, closed reason,
  expected-collapse equality, or relay dispatch claim. It also applies
  `prefix(8)` before exact-event matching, so unrelated cards can hide the
  event and ninth-match overflow cannot be represented. The full-horizon
  sampler latches only booleans; a transient duplicate can disappear from its
  final inventory and take its provenance with it. Finally, the protected
  request has an event hash but no independently derived expected-collapse
  hash, and the host bootstrap can discard a completed native FAIL as an
  environment timeout when the final CoreDevice pull races its deadline.
- Review-confirmed closure holes:
  the sampler labels an earlier inventory as sampled through the deadline
  without a final fetch; the iOS chat scenario has no exact proof test; the
  runner can purge and resend when an artifact exists without its marker;
  retained Sims reports do not serialize preparation input digests; the strict
  provider-size fallback drops collapse/provenance fields; and the original
  RED block could succeed without proving any named failure. These are folded
  into existing rows and one transaction helper, not split into more plans.
- Refuted findings:
  Flutter-local sibling (`matchingFlutterLocalCount=0`), sanitized provider
  copy (`matchingSanitizedProviderCount=0`), Plan-397 retry (one accepted
  attempt), omission of the collapse header from the one canonical candidate
  request (its hash equals the independently computed identity), and two
  Android send actions (one exact publish marker). The noncanonical request
  necessarily used a different or absent collapse identifier; its producer is
  not refuted.
- Unresolved findings:
  which request is useful versus unknown; why the noncanonical request carried
  the exact event; whether it traversed the candidate projection, a second
  repo-owned dispatch path, or downstream FCM/APNs; and whether it reproduces
  on a fresh product. Those facts must precede a repair choice.
- The NSE cannot be treated as a suppression repair:
  `ios/NotificationService/NotificationService.entitlements` lacks
  `com.apple.developer.usernotifications.filtering`, while current
  `NotificationService.swift` calls ordinary different-request sanitization
  privacy clearing rather than OS-card suppression. Apple requires the
  filtering entitlement for an NSE to silence a remote notification with empty
  content.
  [Notification filtering entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.usernotifications.filtering)
- Affected evidence-phase owners:
  `ios/NotificationService/IosNotificationRecovery.swift`,
  `ios/Runner/IosNotificationRecoveryCoordinator.swift`,
  `ios/Runner/AppDelegate.swift`,
  `ios/Runner/IosReceiverBootstrapHandoff.swift` and their Runner tests;
  `lib/core/debug/group_reaction_e2e_probe.dart` and its focused test;
  `integration_test/scripts/ios_receiver_bootstrap.py` and its Python test;
  `integration_test/scripts/run_group_reaction_notification_device.dart`,
  `integration_test/group_announcement_reaction_notification_proof_test.dart`,
  `integration_test/scripts/ios_group_message_diagnostic_staging.py`,
  `integration_test/scripts/group_reaction_notification_device_criteria.dart`,
  `integration_test/scripts/capture_group_reaction_notification_device.dart`,
  `integration_test/support/android_notification_payload_campaign.dart`,
  and their focused Dart tests, including
  `test/integration/android_notification_payload_campaign_support_test.dart`;
  `scripts/test/group_reaction_notification_device_contract_test.sh`;
  `go-relay-server/inbox.go`, `group_content_push.go`, `metrics.go`,
  `ordinary_push_projection_test.go`, `push_payload_closure_test.go`; and
  `scripts/test/run_ios_nse_native_373.sh`. A root-specific production file is
  deliberately not guessed; an evidence-backed amendment must add it.

## Graph Grounding Snapshot

- Graph fingerprint / freshness:
  `4d72d9b23f3c7e72`;
  `stale:ios/Flutter/flutter_export_environment.sh`, an unrelated generated
  environment file. The app-owned anchors were source-verified.
- Primary query / profile:
  `python3 graphify-arch/tdd_context.py query "buildGroupPushMessage sendWithRetry NotificationService IosNotificationRecovery IosGroupNotificationInventory matchingUsefulProviderCount matchingUnknownCount ios_chat_group_message_and_reaction_recipient" --profile tdd --budget 700`.
  Result: `query_id=6a5d09f723cd4c3c`,
  `evidence_digest=9fc2b310250144bb`.
- Selector query / profile:
  `python3 graphify-arch/tdd_context.py query "IosNotificationRecoveryTests.swift IosReceiverBootstrapHandoffTests.swift group_reaction_notification_device_criteria_test.dart IosReceiverBootstrapTest TestRelayNotificationClosure_GroupMessage" --profile tdd --budget 700`.
  Result: `query_id=90a04f9cb0f246fe`,
  `evidence_digest=dd057be9ab9075a8`; native fallback
  `query_id=974b59a2429544d4`,
  `evidence_digest=4956bda5e00b8dd1`.
- Consolidated evidence-owner query:
  `python3 graphify-arch/tdd_context.py query "IosNotificationRecovery.swift IosNotificationRecoveryCoordinator.swift IosReceiverBootstrapHandoff.swift ios_receiver_bootstrap.py group_reaction_notification_device_criteria.dart capture_group_reaction_notification_device.dart inbox.go group_content_push.go ordinary_push_projection_test.go run_ios_nse_native_373.sh" --profile tdd --budget 700`.
  Result: `query_id=0c6532cb0c134f47`,
  `evidence_digest=74df47e1ac8fa1d1`; native fallback
  `query_id=f9c669f8f85448bc`,
  `evidence_digest=a20168daa9cbd3c3`.
- Critical-review branches:
  native inventory fallback `query_id=dc45dc8bae28435d`,
  `evidence_digest=fee7517098793642`; relay review
  `query_id=244bd21edd614deb`,
  `evidence_digest=fa7532cf2312f914`; harness/gate review
  `query_id=be3c06d09dcb4c75`,
  `evidence_digest=327a968fe9494d86`; installed observer review
  `query_id=5ab404e7b2d449b8`,
  `evidence_digest=6ca33e835c4deea2`.
- External-review verification branches:
  proof registration `query_id=48b47801f5554dc4`,
  `evidence_digest=fd56a19889315616`; staging/build/RED
  `query_id=caa9f40104c248ac`,
  `evidence_digest=173373b0adcf129e`; sampler/provider boundary
  `query_id=7e14dfc019654bbb`,
  `evidence_digest=6eb38eeaae0f3331`; existing helper seam
  `query_id=b647a88b338046ed`,
  `evidence_digest=0c4c55dc37183c4d`.
- Anchors:
  `buildGroupPushMessage` -> `go-relay-server/inbox.go:940`;
  `sendWithRetry` -> `go-relay-server/inbox.go:666`;
  group classifier ->
  `ios/NotificationService/IosNotificationRecovery.swift:258`;
  coordinator -> `ios/Runner/IosNotificationRecoveryCoordinator.swift:86`;
  `IosReceiverBootstrapHandoff` ->
  `ios/Runner/IosReceiverBootstrapHandoff.swift:11`;
  `IosReceiverBootstrapTest` ->
  `scripts/test/ios_receiver_bootstrap_test.py:21`.
- Surfaced proof/gate files:
  `ordinary_push_projection_test.go`,
  `IosNotificationRecoveryTests.swift`,
  `IosReceiverBootstrapHandoffTests.swift`,
  `group_reaction_notification_device_criteria_test.dart`,
  `ios_receiver_bootstrap_test.py`,
  `scripts/run_test_gates.sh`, and
  `scripts/test/run_ios_nse_native_373.sh`.
- Graph gaps requiring source search:
  Runner-native targets required the recorded full-graph fallback; staging
  journal and runtime evidence are outside the graph.
- Reuse rule:
  preserve these query IDs, digests, source/test anchors, and the open question
  “what produced the noncanonical event-bound remote request?” through
  review/execution. Conclusions still require current-source or command proof.

## Scope Contract And Guard

In scope:

- Filter and exact-event-bind delivered requests before any cardinality cap.
  Retain a deterministic, hash-keyed union of at most eight matching requests
  across the full horizon: request-identifier SHA-256, remote/local trigger
  origin, closed `sourceClass`, closed reason, expected-collapse-hash equality,
  and an allow-listed dispatch claim if present. Latch ninth-match overflow and
  transient offending rows. If one hash later has different diagnostic values,
  retain one row, latch `diagnosticConflict`, and fail completeness rather than
  choosing first- or last-wins. Retain no raw identifier, payload, title, body,
  group, message, event, token, or peer.
- At the eight-second horizon, perform one final inventory fetch and merge it
  before publishing the outcome. Bound that fetch with one existing stable
  sample interval: callback success sets `sampledThroughDeadline=true`; the
  watchdog winning sets it false and makes the diagnostic incomplete. A card
  first visible in that final fetch must still latch provenance/duplicate
  state; an earlier inventory must never be relabeled as deadline-complete.
- Extend the existing installed Android observer—not add a new probe—to compute
  `expectedCollapseIdentifierSha256` from its run-owned raw message ID using the
  exact production `boundedGroupMessageIdentity` formula, then discard the raw
  ID. Pass that independent hash through the nonce-bound protected request; do
  not derive it from a delivered request or payload claim. Extend the protected
  result/host receipt with a versioned diagnostic array,
  `diagnosticRecordCount`, sticky `diagnosticOverflow`, exact
  `diagnosticConflict`, exact `diagnosticComplete`, the expected hash, and the existing final aggregates on
  PASS and FAIL. Keep the native result within its existing 4096-byte ceiling.
- After the normal polling deadline and exact observer PID termination, make
  one final bounded CoreDevice pull. A valid native FAIL receipt is capture
  evidence, never an environment timeout.
- Add one terminal
  `relay_group_message_dispatch_total{source,result}` counter with closed
  `source=group_inbox|group_content` and `result=accepted|failed`. One logical
  invocation that reaches `sendSelectedPushThroughGateway` records exactly one
  terminal result after all provider retries; permanent and retryable results
  both map to `failed`. A pre-gateway route lookup failure keeps its existing
  metric and yields no new terminal result.
  Keep the existing strict wake-decision metric unchanged. Project the constant
  data key `mknoon_group_message_dispatch_source` with only
  `group_inbox_v1|group_content_v1` so each delivered request can record
  `groupInbox`, `groupContent`, `absent`, or `invalid`. The claim correlates a
  candidate path but cannot replace `UNPushNotificationTrigger` origin or the
  independent terminal counter. Project the claim only in iOS APNs
  `CustomData`; top-level FCM `Data` is not authoritative after iOS projection,
  and Android output must remain byte-for-byte unchanged. When provider size
  rejection selects the strict minimal fallback, retain the same bounded iOS
  collapse identity and source claim for both ordinary and strict group
  sources while recording one terminal logical result across two provider
  attempts.
- Reuse `ios_chat_group_message_and_reaction_recipient` with one explicit
  `--diagnostic-only-message-window` mode. It stops after stable message
  inventory, writes a non-closure artifact, and performs no reaction or tap.
  In this mode, require the exported Plan-398 deployment receipt and
  single-owner declaration; persist only the receipt SHA-256 and the closed
  boolean, never the target, path, or credentials. Add its missing exact
  proof-test registration to the existing group/announcement proof file:
  `test(iosChatGroupMessageAndReactionScenarioId, ...)` must call
  `_validateScenario(iosChatGroupMessageAndReactionScenarioId)`. Do not add a
  scenario or proof file.
- Move only Plan-398 deployment/resume/attempt/restoration mechanics from this
  document into one checked-in, idempotent
  `integration_test/scripts/ios_group_message_diagnostic_staging.py` helper.
  It wraps the existing runner; it is not a notification harness or generic
  deployment framework. Extend the existing device-contract shell test with
  fake remote/process fixtures instead of adding a test framework.
- Before any markerless send, the helper reruns content-addressed Android/iOS
  preparation and a fresh deterministic relay build, then compares retained
  report/artifact/candidate/receipt outputs or fails closed. One Plan-398-wide
  claim prevents a new run ID from bypassing the diagnostic limit, and one
  transaction lock serializes state resolution through verified restoration.
  Claim-present state restores first if needed, then is validation-only.
  Recheck the final-tree and deployed identities at the exact claim/send
  boundary. Deploy only to Plan-257 staging, restore before standalone
  validation, and retain the closed single-owner declaration and terminal
  counter deltas. If ownership or activity is unjoinable, disposition is
  `incomplete_evidence`.
- Amend this plan with exactly one diagnostic disposition:
  repo-owned duplicate dispatch, candidate-single/unattributed duplicate,
  claim-absent/noncandidate path, local contender, clean nonreproduction, or incomplete
  evidence. Only a confirmed repo-owned seam may make it `execution-ready`.
- After an amended, reviewed repair, perform at most one final-tree report-bound
  message-plus-reaction/tap campaign. Closure requires one canonical message
  request before reaction/tap.

Must preserve:

- Ordinary/strict retry collapse ->
  `TestRelayNotificationClosure_GroupMessageRetryCollapse`.
- Ordinary Android and iOS projection plus provider-size behavior ->
  `TestRelayNotificationClosure_OrdinaryPushAndroidProjectionStripsApns`,
  `TestRelayNotificationClosure_OrdinaryPushIosProjectionDropsDuplicateData`,
  and `TestRelayNotificationClosure_ProviderBoundaryUsesCompleteSerializedPayloads`.
- Direct inventory/hard-deadline behavior -> existing TC-396 selectors in
  `run_ios_nse_native_373.sh`.
- Plan-397 full-horizon sticky bad-source/duplicate behavior ->
  `testTC397GroupInventoryRequiresFullHorizonAndRejectsTransientLateLocalSibling`.
- Trigger-derived source authority ->
  `testTC397GroupDeliveredInventoryClassifiesExactSources`.
- Payload-campaign equality between expected collapse and request identifier ->
  existing `ios_notification_payload_campaign.dart` checks.
- Existing scenario/build provenance, zero child builds, exact tap container,
  cleanup, and rollback ->
  the expanded `group_reaction_notification_device_contract_test.sh` and
  Plan-397 criteria.
- No content, raw identifiers, tokens, peers, groups, messages, or events in
  diagnostics -> sealed evidence preflight and TC-398-01/02/05/06.

Hard `Do not`:

- Do not change `boundedGroupMessageIdentity`, remove
  `apns-collapse-id`, or weaken exact-collapse equality unless new evidence
  directly disproves it.
- Do not infer source from payload; remote/local origin comes only from
  `UNPushNotificationTrigger`. The dispatch claim is candidate-path
  correlation only.
- Do not claim sanitizer/NSE card suppression without filtering entitlement and
  provisioning evidence; do not add that entitlement or alter signing here.
- Do not add a scenario, Sims profile/capability, generic controller/framework,
  second staging helper, DB probe, DB/Redis migration, raw logging path,
  production deployment, or manual tap.
- Do not rerun Plan 396 or broaden into direct/announcement/media/mute/sound/
  killed behavior.
- Do not spend more than one diagnostic run or one post-fix closure run. A
  Plan-398-wide exclusive, durably flushed diagnostic claim bound to the fixed
  owner run ID prevents a new shell/run ID from sending again. An interrupted
  resume first restores staging and may only validate the claimed artifact or
  remain incomplete. The later amended closure uses a separate claim
  namespace. A clean/nonreproducing diagnostic cannot trigger an automatic
  rerun.
- Do not call a diagnostic artifact PASS. A valid native FAIL is capture
  evidence; an absent/invalid receipt is environmental.
- Do not leave the active staging relay or manifest mutated. The two
  namespaced, hash-bound recovery sidecars may remain inert as retained
  evidence until final closure cleanup.

Deferred / accepted difference:

- Apple filtering entitlement/provisioning -> Apple capability/release owner;
  it is absent and externally controlled.
- `candidate_single_unattributed_duplicate` -> first audit every
  uninstrumented repository bypass; only if those are excluded may a
  separately authorized provider/Apple escalation follow. No repo repair or
  downstream owner can be inferred from one candidate dispatch alone.
- Full Apple OS/TestFlight matrix, sound, killed, media, mute, announcement,
  and release activation -> final Apple notification rollout.
- Full `host-all` -> Apple-notification dependency wave and final rollout.

Dependencies:

- Plan 397's inventory, protected handoff, classified scenario, central build
  contract, reversible staging CAS, and the sealed secret-free run-21 baseline.
- At execution, rediscover and pin one available USB Android sender, one
  available physical iPhone receiver, and one available iOS XCTest target
  (prefer a simulator). No
  historical UDID, model, or OS version is a closure requirement. APNs/FCM
  credentials, Plan-257 staging inputs, and service account remain required.
- A filtering-entitlement or downstream-provider finding makes this plan
  `prerequisite-blocked`, not permission to invent another repair.

## Test Contract

Phase-A rows TC-398-01 through TC-398-06 authorize diagnostics only.
TC-398-08 reserves one non-closure diagnostic run now and one full run only
after an evidence-backed amendment names the root repair and causal row.
TC-398-06's existing named criteria selector also owns deployment-receipt SHA,
closed single-owner, and exclusive Plan-398 diagnostic-claim binding; these
are one runner/artifact contract, not extra cases or a new harness.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-398-01 | Exact-event binding happens before the cap. Each matching request yields one bounded hash-only record with trigger origin, `sourceClass`, closed reason, expected-collapse equality, and allow-listed dispatch claim; the sampler retains a max-eight union across the horizon, latches transient rows/overflow/same-hash conflicts, and performs one final fetch at the deadline before declaring the horizon complete. | `ios/RunnerTests/IosNotificationRecoveryTests.swift::testTC398GroupInventoryFiltersBeforeBoundAndMapsClosedDiagnostics`; `...::testTC398GroupFullHorizonLatchesTransientDiagnosticUnion` | Host-native XCTest / unrelated-prefix, canonical useful, noncanonical unknown, sanitized, exact local, transient-disappearing sibling, same-hash changed-row, eighth/ninth matching-card, final-fetch-only duplicate, and never-returning final-fetch fixtures | HEAD has latest aggregates/hash list, caps before filtering, and publishes the preceding inventory as sampled through the deadline; authored tests RED -> GREEN filters/binds first, excludes unbound cards, sorts/dedupes by hash, retains the transient union, merges one bounded final fetch, and reports exact count/completeness/overflow/conflict. A final-fetch timeout reports an incomplete horizon. | Representative mutation only: bypass the final fetch -> the full-horizon selector reds. Other inventory permutations remain assertions, not separate mutation runs. | Run both exact XCTest selectors; register both in `run_ios_nse_native_373.sh` |
| TC-398-02 | Protected request/result persists independently derived `expectedCollapseIdentifierSha256`, versioned diagnostics, exact record count/completeness/overflow/conflict, and final aggregates on PASS/FAIL while bounded, <=4096 bytes, and secret-free. | `ios/RunnerTests/IosReceiverBootstrapHandoffTests.swift::testTC398GroupObservationReceiptPersistsBoundedPerCardDiagnostics` | Host-native XCTest / protected temporary request/result container | HEAD schema lacks the expected hash and per-card contract; authored test REDs -> GREEN round-trips the new exact schema, rejects open enums, contradictory source/reason/origin pairs, excess rows, and inconsistent counts/flags, retains FAIL, and exposes hashes only | Representative mutation only: omit diagnostic rows from a retained FAIL receipt -> the TC-398-02 XCTest selector reds. | Run the exact XCTest selector; register it in `run_ios_nse_native_373.sh` |
| TC-398-03 | A result pullable only after successful exact-PID termination gets exactly one final bounded pull; valid PASS/FAIL is retained with ordered command evidence and no relaunch, while absent/invalid evidence remains environmental. | `scripts/test/ios_receiver_bootstrap_test.py::IosReceiverBootstrapTest.test_group_observation_recovers_terminal_native_failure_after_final_termination_pull` | Host Python unittest / fake `devicectl` and fake process | HEAD times out, terminates, and rethrows without another copy -> GREEN performs one post-termination copy, exact-validates it, writes the host receipt, then returns/raises by native status | Representative mutation only: remove the one post-termination result pull -> the exact TC-398-03 Python selector reds. | Exact unittest; also invoke it from existing `run_ios_nse_native_373.sh`, the already registered native host-all tail—no new wrapper |
| TC-398-04 | Runner reads a valid retained native FAIL despite subprocess nonzero, classifies capture evidence, and reserves environment for absent/invalid receipt. | `test/integration/group_reaction_notification_device_criteria_test.dart::Plan 398 retains a native FAIL receipt as capture evidence, never environment evidence` | Host Flutter / temporary receipts plus fake exits | HEAD aborts before reading receipt -> GREEN pure disposition logic distinguishes valid FAIL, invalid/missing, and PASS | Representative mutation only: return on subprocess nonzero before reading a valid native FAIL -> the exact TC-398-04 Flutter selector reds. | `flutter test test/integration/group_reaction_notification_device_criteria_test.dart --plain-name 'Plan 398 retains a native FAIL receipt as capture evidence, never environment evidence'`; AUTO in `GROUP_TESTS` |
| TC-398-05 | One ordinary or strict group-message invocation that reaches the selected gateway emits one terminal `accepted`/`failed` result after retries and an iOS-only closed source claim; retry is not a second logical dispatch, pre-gateway route failure emits no terminal result, Android is unchanged, and ordinary/strict provider-size fallback preserves the same collapse identity and source claim. | `go-relay-server/ordinary_push_projection_test.go::TestRelayNotificationClosure_GroupMessageDispatchAttribution`; extend `go-relay-server/push_payload_closure_test.go::TestRelayNotificationClosure_ProviderTooLargeGetsOneStrictFallback` with the missing strict-source and attribution assertions | Host Go / ordinary/strict accepted, terminal-failed, transient-retry, pre-gateway route failure, iOS CustomData, ordinary/strict provider-size rejection, one representative Android no-Plan398-leakage case, and routing-only fixtures | HEAD has only global/strict-decision counters and no claim; strict minimal fallback also drops collapse/claim -> GREEN proves exact source/result, sibling zero, retry-one terminal count, failed-one terminal count, no early-route terminal, and two provider attempts but one terminal logical result with identical collapse/claim across fallback. Android remains unchanged in the representative fallback case. | Representative mutation only: drop collapse/claim from the strict fallback -> `TestRelayNotificationClosure_ProviderTooLargeGetsOneStrictFallback` reds. Other outcome permutations remain assertions, not separate mutation runs. | Run both exact Go selectors; AUTO via `TestRelayNotificationClosure_` in `groups` |
| TC-398-06 | The existing installed sender observer derives the expected collapse-request hash from the run-owned raw message ID and returns only that hash. The existing provider-journal support derives a strict `providerSingleFirstAttempt` boolean before redaction. The scenario's diagnostic flag is accepted/forwarded only for this scenario, stops after one message window, retains valid native FAIL provenance plus that boolean, forces `closurePassed=false`, and performs no reaction/tap/retry. Before any purge or send, the staging helper resolves the closed claim/artifact state table; only the fresh state may claim a Plan-398-wide durable claim at the capture driver's exact send boundary. | `test/core/debug/group_reaction_e2e_probe_test.dart::combined iOS group journey returns the canonical collapse-request hash only`; `test/integration/android_notification_payload_campaign_support_test.dart::Plan 398 provider evidence requires one first-attempt acceptance without retry or fallback`; `test/integration/group_reaction_notification_device_criteria_test.dart::Plan 398 diagnostic mode binds per-card provenance without claiming closure`; exact `ios_chat_group_message_and_reaction_recipient` test in `integration_test/group_announcement_reaction_notification_proof_test.dart` | Host Flutter / real SQLCipher-shaped observer fixture, raw-journal fixtures, synthetic artifact/command contract, and existing proof file with the missing exact registration added | HEAD exposes only message-ID SHA, has only a permissive accepted-send predicate, lacks the flag/disposition and exact proof registration, and can purge/resend after interruption -> GREEN proves the fixed production vector, hash-only boundary, strict attempt predicate, runner-to-capture forwarding, exact proof selection, immediate/standalone validation, one window, non-closure, and no resend from every claim/artifact or alternate-run state | Representative mutation only: allow an alternate/unleased run to reach send -> the existing transaction shell contract reds. | Run all three exact Flutter selectors plus the existing `group_reaction_notification_device_contract_test.sh`; criteria test is in `GROUP_TESTS`, support test is exact now and host-all later; add only the missing exact proof-test registration, not a new scenario/capability |
| TC-398-07 | Canonical collapse, Android/iOS payload projection and budgets, trigger-derived classification, sticky duplicate latch, protected handoff, and request-ID equality remain unchanged. | `TestRelayNotificationClosure_GroupMessageRetryCollapse`; ordinary Android/iOS projection plus `TestRelayNotificationClosure_ProviderBoundaryUsesCompleteSerializedPayloads`; TC-397 native inventory/horizon/handoff selectors; existing payload-campaign collapse-equality check | Host Go + native simulator + focused payload sentinels | GREEN sentinels on HEAD -> remain GREEN after diagnostics and later repair | Remove collapse, lose APNs CustomData/Android projection, trust payload origin, return early, drop latch/raw protection, or stop final hash equality -> one listed sentinel red | Exact commands below; existing registration; `groups` remains the affected curated lane for final amended closure |
| TC-398-08 | The currently authorized device run is diagnostic only: one controlled ordinary group-message window must bind native per-card provenance to a declared single-owner staging window and its terminal relay-source deltas, seal exactly one disposition, restore staging, and only then validate independently. One plan-specific helper owns the idempotent deploy/resume/claim/restore transaction. A later full message/reaction/tap run is an amendment obligation, not a current command. | Diagnostic-only `ios_chat_group_message_and_reaction_recipient` artifact plus independent `--validate-artifacts <dir>` | OS-notification device lab / live-pinned USB Android + physical iPhone + real staging relay/FCM/APNs/NSE; fake remote/process fixtures in the existing shell contract | Run 21 is retained device RED; the one report-bound diagnostic can select provenance but cannot pass notification closure. Every unclaimed send first regenerates content-addressed mobile preparation and a fresh deterministic relay candidate, verifies exact outputs, proves installed and running relay identity, and restores prior state in `finally`; claim-present resume restores first if needed and is validation-only. | Treat diagnostic as closure, claim counters prove exclusivity, accept ambiguous/unjoinable counters or provider attempts, treat noncanonical/second/local source as clean, reuse an unclaimed stale candidate/report, skip installed/running identity, send from a non-fresh state, skip validation, or fail rollback -> TC-398-08 red | Exact helper command below; existing scenario discovery/classification; no new Sims registration or general deployment framework. The amendment must add the later full command after it names the root repair |

### Test Notes

- TC-398-01:
  `UNPushNotificationTrigger` alone decides remote origin. First prove exact
  event identity; exclude a mismatched event or a row with no bindable event.
  `sourceClass` is exactly `usefulProviderRich`, `sanitizedProviderRich`,
  `flutterLocal`, or `unknown`. `reason` is exactly `exactUseful`,
  `exactSanitized`, `exactFlutterLocal`, `missingOrInvalidType`,
  `groupHashMismatch`, `partialContent`, `unclassifiedRemote`, or
  `unclassifiedLocal`. Do not retain `messageHashMismatch`: it is evidence that
  the card is outside this event, not a diagnostic row for it.
- TC-398-01/02:
  `diagnosticRecordCount` equals the retained array length.
  `diagnosticOverflow` latches on the ninth distinct event-bound request.
  A later nonidentical row for an already-retained request hash latches
  `diagnosticConflict`; neither first-wins nor last-wins is authoritative.
  Valid origin/class/reason triples are exactly: remote +
  `usefulProviderRich` + `exactUseful`; remote + `sanitizedProviderRich` +
  `exactSanitized`; local + `flutterLocal` + `exactFlutterLocal`; or `unknown`
  with remote + one of `missingOrInvalidType`, `groupHashMismatch`,
  `partialContent`, or `unclassifiedRemote`; or local + one of
  `groupHashMismatch` or `unclassifiedLocal`. Every other triple is an invalid
  receipt.
  Native `diagnosticComplete` requires a full sampled horizon, a valid expected
  hash, no overflow/conflict, and only closed consistent rows; it never means
  behavior PASS and need not equal the final-sample `matchingTotalCount` when a
  transient row disappeared. At the deadline, perform one final inventory
  fetch and merge it before publishing completion. Bound that fetch by one
  existing stable-sample interval: success may set
  `sampledThroughDeadline=true`; timeout or no callback sets it false and
  classifies the diagnostic incomplete.
- TC-398-03/04:
  valid `nativeStatus=FAIL` after exact PID termination is capture evidence;
  no valid receipt is environmental.
- TC-398-05:
  record one terminal result from `sendSelectedPushThroughGateway`, not every
  `sendWithRetry` attempt. The diagnostic artifact records closed
  `relayGroupMessageDispatchSource`, accepted/failed deltas for both allow-listed
  sources, a zero sibling-source delta, and the declared single-owner-window
  precondition.
  The counter reports terminal logical outcomes, not provider-attempt count.
  Ordinary and strict provider-size rejection fixtures must observe two
  provider attempts but one terminal logical result, with the same
  `apns-collapse-id` and closed source claim on both attempts. One
  representative Android case preserves its existing fallback projection;
  do not expand this into a platform-by-payload matrix.
  Reuse retained same-window relay journal evidence for attempt/retry/fallback;
  any unjoinable activity or absent single-owner staging attestation makes the
  evidence incomplete.
- TC-398-06:
  `diagnostic_complete` means evidence captured, never behavior passed. Both
  capture and standalone validation require the file exported as
  `PLAN398_DEPLOYMENT_RECEIPT`, recompute its SHA-256, require its closed
  `singleOwnerDeclared=true`, and match the artifact's
  `stagingDeploymentReceiptSha256` plus `singleOwnerDeclared=true`. The
  artifact stores only that hash and boolean, not target/path/credentials.
  Immediately before the diagnostic send, the capture driver calls the
  plan-specific staging helper's Plan-398-wide exclusive claim after final
  source/input/deployment revalidation. The helper creates the file exported
  as `PLAN398_DIAGNOSTIC_ATTEMPT_MARKER`, binds the fixed owner run ID,
  durably flushes the file and parent directory, and the artifact retains only
  `diagnosticAttemptClaimed=true` plus its SHA-256 in the artifact. The same
  existing shell contract proves a new run ID or interruption after claim
  flush and before network send cannot resend. Standalone validation
  recomputes the claim SHA after verified staging restoration.
  The helper resolves the marker/artifact table below before the runner may
  purge old artifacts. A complete matching artifact may be validation-only,
  never a second send. Missing/mismatched marker evidence is
  `incomplete_evidence`.
  Its representative mutation allows an alternate/unleased run to reach send;
  the existing transaction shell contract must re-red before the inverse patch
  restores GREEN.
- TC-398-08 disposition:

  | Observation | Disposition | Authorization |
  |---|---|---|
  | Two remote requests; two accepted terminal dispatches in the declared single-owner window whose closed claim/source matches the cards | `repo_owned_duplicate_dispatch` | Amend exact caller/repair/causal test, review, then execution-ready. |
  | Two remote requests; exactly one accepted candidate dispatch; retained journal proves exactly one provider attempt with no retry/fallback; both carry that candidate claim and one hash is canonical | `candidate_single_unattributed_duplicate` | Audit any uninstrumented repo bypass, then provider/Apple ownership; no repair until one is proven. |
  | Two remote requests; exactly one accepted candidate dispatch; the noncanonical card lacks the candidate claim | `claim_absent_or_noncandidate` | Keep evidence-gated; distinguish projection/OS loss from another source with one new Graphify branch, then amend. |
  | One remote plus exact local | `local_contender` | Amend exact app owner/test before repair. |
  | Exactly one canonical remote | `clean_nonreproduction` | Evidence gap; not PASS and do not spend post-fix run. |
  | Zero records; same-hash conflict; missing/overflow/open/inconsistent diagnostics; invalid claim; uncovered cardinality; no single-owner staging attestation; missing/mismatched attempt marker; ambiguous counter/provider attempts; stale build; or invalid receipt | `incomplete_evidence` | Typed capture/environment blocker; no root claim or automatic retry. |
- TC-398-08 rollback proof requires both the installed relay SHA and the
  running systemd `MainPID` executable SHA to equal the prior relay after
  restore. Extend the existing device-contract shell test with fake
  remote/process fixtures that reject a file-only check and a
  prior-file/candidate-process interruption; no new test owner is added.

## Implementation Steps

1. Snapshot `git status --short`, seal the secret-free run-21 baseline and its
   SHA-256 outside `/tmp`, and rediscover/pin only live targets. Preserve
   unrelated worktree changes and verified prior staging SHAs.
2. Author TC-398-01 through TC-398-06 first; record causal REDs, never missing
   or zero-test results.
3. Extend the existing sender observer with the fixed-vector expected-collapse
   hash only. Pass it through the protected request, filter/exact-event-bind
   before bounding, retain the bounded diagnostic union across the horizon,
   and merge one bounded final inventory fetch at the deadline.
4. Version and exact-validate protected native/host receipts. After a polling
   deadline, terminate the exact PID, make exactly one final pull, retain valid
   PASS/FAIL, and distinguish capture from environment.
5. Extract the closed Dart disposition and add/forward
   `--diagnostic-only-message-window` on the existing runner/capture path. Stop
   before reaction/tap and force non-closure. Extend the existing provider
   journal support—not a second parser—to compute
   `providerSingleFirstAttempt` from the raw window before redaction. Make the
   capture driver call the staging helper's durable exclusive marker claim at
   the exact send boundary only after final-tree/deployment revalidation, bind
   its SHA-256 into the artifact, and reject any new-run, concurrent,
   non-fresh, or interrupted state before another send. Register the exact
   `ios_chat_group_message_and_reaction_recipient` proof in the existing
   proof file; do not add a scenario or capability.
6. Add `relay_group_message_dispatch_total{source,result}` at the ordinary and
   strict adapters, project the closed claim only through APNs CustomData, and
   preserve collapse identity and the claim through ordinary/strict
   provider-size fallback. Keep provider attempts inside one terminal logical
   result and existing wake metrics intact. Preserve Android with one
   representative fallback case.
7. Run focused GREEN, representative mutation re-red, TC-398-07 sentinels,
   exact registrations, scoped hygiene, and Graphify impact. Do not run broad
   discovery or full `host-all`.
8. Implement one checked-in, plan-specific staging transaction helper and
   host-test it through the existing shell contract. Hold one transaction lock
   through restoration. On every markerless send, rerun content-addressed
   mobile preparation and a fresh deterministic relay build, compare exact
   retained outputs, prove installed and running candidate identity, and
   retain Plan 397's prior-authority SHA-CAS. Do not change the Sims report
   schema or create a generic deploy framework.
9. Through that helper, run exactly one declared single-owner diagnostic-only
   message window, restore prior relay/manifest and running process in
   `finally`, then independently validate and record one disposition.
   Claim-present resume restores first if needed and is validation-only.
10. Stop and amend this plan once. Without one proven repo root, remain
    evidence-gated or prerequisite-blocked and make no behavior repair. Only
    the reviewed amendment may add the root RED/GREEN/mutation, smallest repair,
    report-bound products (rebuilt only when inputs change), one full
    message/reaction/tap run, and final `groups` gate.

Stop if diagnostics are raw/open/incomplete; live staging matches neither
prior nor candidate; builds are stale/unbound or child-built; no unique
disposition exists; repair needs entitlement/production/new framework; or the
full run sees any second/noncanonical/local/sanitized/unknown message request.

## Risks And Blind Spots

- `candidate_single_unattributed_duplicate` may yield no repo repair ->
  TC-398-05/08 require an audit of uninstrumented repository bypasses before
  any provider/Apple ownership claim.
- Payload claim may be mistaken for origin -> TC-398-01 keeps trigger authority
  and TC-398-05 uses the claim only beside expected terminal deltas in the
  declared single-owner window.
- Diagnostics may leak/grow or lose a transient card -> filter/bind first,
  max-eight union, sticky overflow, closed enums, hash-only TC-398-01/02, and
  one bounded deadline fetch whose timeout cannot claim a complete horizon.
- Recovery pull may hide transport failure/loop -> one post-termination pull
  and strict validation in TC-398-03.
- Clean diagnostic may be mislabeled closure -> TC-398-06/08 force non-closure.
- Instrumentation may alter timing -> diagnostic cannot close; one post-repair
  final-tree full run remains mandatory.
- A process-global relay count can include unrelated traffic -> require the
  externally scheduled single-owner window, validate only expected deltas,
  classify ambiguity as incomplete, and combine it with native request
  inventory rather than treating the counter as exclusivity proof.
- Lifecycle / derived-state durability:
  protected files survive until pull; TC-398-02/03/04 cover FAIL, timeout, PID
  termination, and retention.
- Sibling-surface consistency:
  ordinary/strict share collapse but distinct attribution; TC-398-05/07 cover
  both. Direct/reaction are preservation-only.
- Destructive-action side effects:
  exact active relay/manifest rollback is a TC-398-08 prerequisite; the two
  hash-bound recovery sidecars are retained evidence, not live configuration.
- Invariant re-verification:
  after diagnostic and post-fix rebuild, recheck digests, relay health/SHA,
  manifest, device IDs, zero child builds, horizon, and collapse equality.

## Gate Cadence

- Evidence phase:
  exact TC-398-01 through TC-398-06, representative mutation re-red,
  TC-398-07, `run_ios_nse_native_373.sh` because native surfaces change, and
  one diagnostic device run. The exact scenario list, missing proof
  registration check, and expanded existing transaction contract are
  sufficient; do not run broad reliability discovery because no scenario or
  Sims capability is added.
- Root repair:
  amendment names its exact test/family; run it, affected sentinels, one full
  device campaign, and one final `./scripts/run_test_gates.sh groups`.
- Do not run full `host-all` per plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the
  Apple-notification dependency wave and once at final rollout/release.
- Shared tests outside globs:
  exact Python unittest, provider/payload-support selectors, and `xcodebuild` selectors
  below; later aggregate registration creates no per-plan `host-all` duty.
- Do not run `groups` between diagnostic disposition and plan amendment.

## Acceptance Gates

Only the evidence phase below is authorized. A root-repair RED/GREEN or full
message/reaction/tap command is intentionally absent until the diagnostic names
a source seam; the amendment must add it before `execution-ready`. Run the
evidence blocks sequentially in one shell. A resumed shell must revalidate and
re-export the retained target, build-report, and deployment-receipt values.

### Evidence Preflight And Live Target Pinning

This block is executable. It seals the only surviving run-21 native result into
a secret-free durable baseline and resolves current targets; historical device
IDs are preferences, not prerequisites. Until that retained baseline and its
checksum exist, loss of the exact `/tmp` source is an evidence prerequisite
blocker; never reconstruct the baseline from prose or remembered values.

```bash
set -euo pipefail
git status --short
mkdir -p build/plan398/run21-baseline build/plan398/live-matrix
export PLAN398_BASELINE_SOURCE=/tmp/plan397-observation-state.cJVEuS/group-observation-result.json
export PLAN398_BASELINE=build/plan398/run21-baseline/group-observation-result.redacted.json
export PLAN398_BASELINE_CHECKSUM=build/plan398/run21-baseline/baseline.sha256
if [ -e "$PLAN398_BASELINE" ]; then
  test -f "$PLAN398_BASELINE_CHECKSUM"
  (cd "$(dirname "$PLAN398_BASELINE")" && \
    shasum -a 256 -c "$(basename "$PLAN398_BASELINE_CHECKSUM")")
else
  test -f "$PLAN398_BASELINE_SOURCE"
  test "$(shasum -a 256 "$PLAN398_BASELINE_SOURCE" | awk '{print $1}')" = \
    fa9e984658a86d2151c9b6dc00abfa2cde953958afb15632b9cd81b603c8dfaf
  jq '{
    schema: "mknoon.plan398.run21-baseline.v1",
    sourceResultSha256: "fa9e984658a86d2151c9b6dc00abfa2cde953958afb15632b9cd81b603c8dfaf",
    expectedCollapseIdentifierSha256: "90e5a93461c990db01fe76b7d7b3527bd865a22c6e6520262720f55d8c9d7962",
    completedAt, status, resultCode,
    matchingRemoteCount, matchingLocalCount, matchingUsefulProviderCount,
    matchingSanitizedProviderCount, matchingFlutterLocalCount,
    matchingUnknownCount, matchingTotalCount, stableSampleCount,
    sampledThroughDeadline, badSourceSeen, duplicateSeen,
    requestIdentifierSha256, childBuildCount, manualActionCount
  }' "$PLAN398_BASELINE_SOURCE" > "$PLAN398_BASELINE"
  (cd "$(dirname "$PLAN398_BASELINE")" && \
    shasum -a 256 "$(basename "$PLAN398_BASELINE")" > \
      "$(basename "$PLAN398_BASELINE_CHECKSUM")")
fi
chmod 600 "$PLAN398_BASELINE"
jq -e --arg expected \
  '90e5a93461c990db01fe76b7d7b3527bd865a22c6e6520262720f55d8c9d7962' '
  .schema == "mknoon.plan398.run21-baseline.v1" and
  .matchingRemoteCount == 2 and .matchingTotalCount == 2 and
  .duplicateSeen == true and .badSourceSeen == true and
  .expectedCollapseIdentifierSha256 == $expected and
  ([.requestIdentifierSha256[] | select(. == $expected)] | length) == 1 and
  (.requestIdentifierSha256 | length) == 2
' "$PLAN398_BASELINE" >/dev/null

flutter devices --machine > build/plan398/live-matrix/flutter-devices.json
adb devices -l
xcrun simctl list devices available -j > build/plan398/live-matrix/ios-simulators.json
export PLAN398_ANDROID_ID="${PLAN398_ANDROID_ID:-$(jq -er '
  first(.[] | select(.emulator == false) |
    select(.targetPlatform | startswith("android"))) | .id
' build/plan398/live-matrix/flutter-devices.json)}"
export PLAN398_IPHONE_ID="${PLAN398_IPHONE_ID:-$(jq -er '
  first(.[] | select(.emulator == false) |
    select(.targetPlatform | startswith("ios"))) | .id
' build/plan398/live-matrix/flutter-devices.json)}"
export PLAN398_IOS_SIM_ID="${PLAN398_IOS_SIM_ID:-$(jq -r '
  [.devices[][] | select(.isAvailable == true) |
    select(.name | startswith("iPhone"))][0].udid // empty
' build/plan398/live-matrix/ios-simulators.json)}"
jq -e --arg id "$PLAN398_ANDROID_ID" \
  'any(.[]; .id == $id and .emulator == false and
    (.targetPlatform | startswith("android")))' \
  build/plan398/live-matrix/flutter-devices.json >/dev/null
adb devices | awk '$2 == "device" {print $1}' | \
  rg -F -x -- "$PLAN398_ANDROID_ID" >/dev/null
jq -e --arg id "$PLAN398_IPHONE_ID" \
  'any(.[]; .id == $id and .emulator == false and
    (.targetPlatform | startswith("ios")))' \
  build/plan398/live-matrix/flutter-devices.json >/dev/null
if [ -n "$PLAN398_IOS_SIM_ID" ]; then
  jq -e --arg id "$PLAN398_IOS_SIM_ID" \
    'any(.devices[][]; .udid == $id and .isAvailable == true and
      (.name | startswith("iPhone")))' \
    build/plan398/live-matrix/ios-simulators.json >/dev/null
  export PLAN398_IOS_TEST_DESTINATION="platform=iOS Simulator,id=$PLAN398_IOS_SIM_ID"
else
  export PLAN398_IOS_TEST_DESTINATION="platform=iOS,id=$PLAN398_IPHONE_ID"
fi
if plutil -extract com.apple.developer.usernotifications.filtering raw \
  ios/NotificationService/NotificationService.entitlements >/dev/null 2>&1; then
  echo 'unexpected filtering entitlement; replan provisioning assumptions' >&2
  exit 1
fi
```

When no simulator is available, the preflight selects the already-discovered
physical iPhone as the XCTest destination. The absent simulator/version is
`N/A (target unavailable by project policy)`, not a reason to wait for
hardware. A physical iPhone remains required for TC-398-08.

### Causal RED Commands

Author each test first and give its intended missing-behavior assertion the
stable token shown below. Every RED must have a nonzero exit, named execution
evidence, and that causal failure token; a selected crash/environment failure
is not RED. Keep this function inline—do not add a second helper file. The shell
contract prints `RUN: Plan 398 staging transaction contract` before its
authored assertions and uses `TC-398-08 staging transaction` in the intended
failure.

```bash
set -euo pipefail
export PLAN398_RED_DIR=build/plan398/red
mkdir -p "$PLAN398_RED_DIR"

expect_named_red() {
  local label="$1"
  local run_regex="$2"
  local failure_regex="$3"
  shift 3
  local log="$PLAN398_RED_DIR/$label.log"
  local status

  set +e
  "$@" >"$log" 2>&1
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    printf 'FAIL: %s unexpectedly passed\n' "$label" >&2
    return 1
  fi
  if rg -i 'no tests (ran|were found)|0 tests|no matching tests|test not found' \
      "$log" >/dev/null; then
    printf 'FAIL: %s did not select a test\n' "$label" >&2
    return 1
  fi
  if ! rg -e "$run_regex" "$log" >/dev/null; then
    printf 'FAIL: %s lacks named execution evidence\n' "$label" >&2
    return 1
  fi
  if ! rg -e "$failure_regex" "$log" >/dev/null; then
    printf 'FAIL: %s lacks its causal assertion token\n' "$label" >&2
    return 1
  fi
  printf 'EXPECTED RED: %s (exit %s)\n' "$label" "$status"
}

expect_named_red tc398_inventory \
  'Test Case.*testTC398GroupInventoryFiltersBeforeBoundAndMapsClosedDiagnostics.*started' \
  'TC-398-01 inventory binding' \
  xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -destination "$PLAN398_IOS_TEST_DESTINATION" \
  -only-testing:RunnerTests/IosNotificationRecoveryTests/testTC398GroupInventoryFiltersBeforeBoundAndMapsClosedDiagnostics
expect_named_red tc398_horizon \
  'Test Case.*testTC398GroupFullHorizonLatchesTransientDiagnosticUnion.*started' \
  'TC-398-01 deadline horizon' \
  xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -destination "$PLAN398_IOS_TEST_DESTINATION" \
  -only-testing:RunnerTests/IosNotificationRecoveryTests/testTC398GroupFullHorizonLatchesTransientDiagnosticUnion
expect_named_red tc398_handoff \
  'Test Case.*testTC398GroupObservationReceiptPersistsBoundedPerCardDiagnostics.*started' \
  'TC-398-02 protected receipt' \
  xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -destination "$PLAN398_IOS_TEST_DESTINATION" \
  -only-testing:RunnerTests/IosReceiverBootstrapHandoffTests/testTC398GroupObservationReceiptPersistsBoundedPerCardDiagnostics
expect_named_red tc398_final_pull \
  '^test_group_observation_recovers_terminal_native_failure_after_final_termination_pull' \
  'TC-398-03 terminal pull' \
  python3 -m unittest -v \
  scripts.test.ios_receiver_bootstrap_test.IosReceiverBootstrapTest.test_group_observation_recovers_terminal_native_failure_after_final_termination_pull
expect_named_red tc398_native_fail \
  'Plan 398 retains a native FAIL receipt as capture evidence, never environment evidence' \
  'TC-398-04 retained native FAIL' \
  flutter test test/integration/group_reaction_notification_device_criteria_test.dart \
  --plain-name 'Plan 398 retains a native FAIL receipt as capture evidence, never environment evidence'
expect_named_red tc398_diagnostic \
  'Plan 398 diagnostic mode binds per-card provenance without claiming closure' \
  'TC-398-06 diagnostic mode' \
  flutter test test/integration/group_reaction_notification_device_criteria_test.dart \
  --plain-name 'Plan 398 diagnostic mode binds per-card provenance without claiming closure'
expect_named_red tc398_provider \
  'Plan 398 provider evidence requires one first-attempt acceptance without retry or fallback' \
  'TC-398-06 provider attempt' \
  flutter test test/integration/android_notification_payload_campaign_support_test.dart \
  --plain-name 'Plan 398 provider evidence requires one first-attempt acceptance without retry or fallback'
expect_named_red tc398_relay \
  '=== RUN[[:space:]]+TestRelayNotificationClosure_GroupMessageDispatchAttribution' \
  'TC-398-05 dispatch attribution' \
  bash -lc "cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . -run '^TestRelayNotificationClosure_GroupMessageDispatchAttribution$' -v -count=1"
expect_named_red tc398_provider_fallback \
  '=== RUN[[:space:]]+TestRelayNotificationClosure_ProviderTooLargeGetsOneStrictFallback' \
  'TC-398-05 provider fallback' \
  bash -lc "cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . -run '^TestRelayNotificationClosure_ProviderTooLargeGetsOneStrictFallback$' -v -count=1"
expect_named_red tc398_probe \
  'combined iOS group journey returns the canonical collapse-request hash only' \
  'TC-398-06 expected collapse' \
  flutter test test/core/debug/group_reaction_e2e_probe_test.dart \
  --plain-name 'combined iOS group journey returns the canonical collapse-request hash only'
expect_named_red tc398_transaction \
  '^RUN: Plan 398 staging transaction contract$' \
  'TC-398-08 staging transaction' \
  bash scripts/test/group_reaction_notification_device_contract_test.sh
```

### Evidence-Phase GREEN, Preservation, Registration, And Hygiene

Run only the causal selectors, their exact preservation sentinels, and the
already-registered native family whose membership changes. Do not run
`groups`, a broad discovery gate, or `host-all` in this phase.

Mutation evidence is exact, not another gate: after all causal selectors for
each TC-398-01 through TC-398-06 row turn GREEN, apply that row's one named
representative mutation with `apply_patch`, rerun only its bound selector,
restore with the inverse patch, and rerun that selector GREEN. Record the
mutated seam, semantic failure, restoration, and final GREEN in Execution
Progress. Do not use `git checkout`/`reset`, mutate staging/device state, or
rerun a family for this proof. Complete these mutations before the
hygiene/Graphify commands below.

```bash
set -euo pipefail

xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -destination "$PLAN398_IOS_TEST_DESTINATION" \
  -only-testing:RunnerTests/IosNotificationRecoveryTests/testTC398GroupInventoryFiltersBeforeBoundAndMapsClosedDiagnostics \
  -only-testing:RunnerTests/IosNotificationRecoveryTests/testTC398GroupFullHorizonLatchesTransientDiagnosticUnion \
  -only-testing:RunnerTests/IosReceiverBootstrapHandoffTests/testTC398GroupObservationReceiptPersistsBoundedPerCardDiagnostics \
  -only-testing:RunnerTests/IosNotificationRecoveryTests/testTC397GroupDeliveredInventoryClassifiesExactSources \
  -only-testing:RunnerTests/IosNotificationRecoveryTests/testTC397GroupInventoryRequiresFullHorizonAndRejectsTransientLateLocalSibling \
  -only-testing:RunnerTests/IosReceiverBootstrapHandoffTests/testTC397GroupObservationReceiptIsProtectedAndRedacted
python3 -m unittest \
  scripts.test.ios_receiver_bootstrap_test.IosReceiverBootstrapTest.test_group_observation_recovers_terminal_native_failure_after_final_termination_pull \
  scripts.test.ios_receiver_bootstrap_test.IosReceiverBootstrapTest.test_group_observation_is_exact_source_bound_redacted_and_cleaned \
  scripts.test.ios_receiver_bootstrap_test.IosReceiverBootstrapTest.test_group_observation_holds_fence_until_pull_and_terminates_without_pretap_relaunch
flutter test test/core/debug/group_reaction_e2e_probe_test.dart \
  --plain-name 'combined iOS group journey returns the canonical collapse-request hash only'
flutter test test/integration/group_reaction_notification_device_criteria_test.dart \
  --plain-name 'Plan 398 retains a native FAIL receipt as capture evidence, never environment evidence'
flutter test test/integration/group_reaction_notification_device_criteria_test.dart \
  --plain-name 'Plan 398 diagnostic mode binds per-card provenance without claiming closure'
flutter test test/integration/android_notification_payload_campaign_support_test.dart \
  --plain-name 'Plan 398 provider evidence requires one first-attempt acceptance without retry or fallback'
flutter test test/integration/ios_notification_payload_campaign_support_test.dart \
  --plain-name 'TC-396 retry receipt requires two bound accepts and one card'
export PLAN398_GO_TESTS='^(TestRelayNotificationClosure_GroupMessageDispatchAttribution|TestRelayNotificationClosure_ProviderTooLargeGetsOneStrictFallback|TestRelayNotificationClosure_GroupMessageRetryCollapse|TestRelayNotificationClosure_OrdinaryPushAndroidProjectionStripsApns|TestRelayNotificationClosure_OrdinaryPushIosProjectionDropsDuplicateData|TestRelayNotificationClosure_ProviderBoundaryUsesCompleteSerializedPayloads)$'
PLAN398_GO_LIST="$(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . -list "$PLAN398_GO_TESTS")"
test "$(printf '%s\n' "$PLAN398_GO_LIST" | rg -c '^Test')" -eq 6
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . \
  -run "$PLAN398_GO_TESTS" -v -count=1)
bash scripts/test/run_ios_nse_native_373.sh
bash scripts/test/group_reaction_notification_device_contract_test.sh
dart run integration_test/scripts/run_group_reaction_notification_device.dart \
  --scenario ios_chat_group_message_and_reaction_recipient --list-scenarios

test -z "$(gofmt -l \
  go-relay-server/inbox.go \
  go-relay-server/group_content_push.go \
  go-relay-server/metrics.go \
  go-relay-server/ordinary_push_projection_test.go \
  go-relay-server/push_payload_closure_test.go)"
dart format --output=none --set-exit-if-changed \
  lib/core/debug/group_reaction_e2e_probe.dart \
  test/core/debug/group_reaction_e2e_probe_test.dart \
  integration_test/group_announcement_reaction_notification_proof_test.dart \
  integration_test/scripts/run_group_reaction_notification_device.dart \
  integration_test/scripts/group_reaction_notification_device_criteria.dart \
  integration_test/scripts/capture_group_reaction_notification_device.dart \
  integration_test/support/android_notification_payload_campaign.dart \
  test/integration/android_notification_payload_campaign_support_test.dart \
  test/integration/group_reaction_notification_device_criteria_test.dart
for PLAN398_DART_FILE in \
  lib/core/debug/group_reaction_e2e_probe.dart \
  test/core/debug/group_reaction_e2e_probe_test.dart \
  integration_test/group_announcement_reaction_notification_proof_test.dart \
  integration_test/scripts/run_group_reaction_notification_device.dart \
  integration_test/scripts/group_reaction_notification_device_criteria.dart \
  integration_test/scripts/capture_group_reaction_notification_device.dart \
  integration_test/support/android_notification_payload_campaign.dart \
  test/integration/android_notification_payload_campaign_support_test.dart \
  test/integration/group_reaction_notification_device_criteria_test.dart; do
  dart analyze "$PLAN398_DART_FILE"
done
python3 -m py_compile \
  integration_test/scripts/ios_group_message_diagnostic_staging.py \
  integration_test/scripts/ios_receiver_bootstrap.py \
  scripts/test/ios_receiver_bootstrap_test.py
bash -n \
  scripts/test/group_reaction_notification_device_contract_test.sh \
  scripts/test/run_ios_nse_native_373.sh
git diff --check
python3 graphify-arch/tdd_context.py affected \
  ios/NotificationService/IosNotificationRecovery.swift \
  ios/Runner/IosNotificationRecoveryCoordinator.swift \
  ios/Runner/AppDelegate.swift \
  ios/Runner/IosReceiverBootstrapHandoff.swift \
  ios/RunnerTests/IosNotificationRecoveryTests.swift \
  ios/RunnerTests/IosReceiverBootstrapHandoffTests.swift \
  lib/core/debug/group_reaction_e2e_probe.dart \
  test/core/debug/group_reaction_e2e_probe_test.dart \
  integration_test/group_announcement_reaction_notification_proof_test.dart \
  integration_test/scripts/ios_group_message_diagnostic_staging.py \
  integration_test/scripts/ios_receiver_bootstrap.py \
  scripts/test/ios_receiver_bootstrap_test.py \
  integration_test/scripts/run_group_reaction_notification_device.dart \
  integration_test/scripts/group_reaction_notification_device_criteria.dart \
  integration_test/scripts/capture_group_reaction_notification_device.dart \
  integration_test/support/android_notification_payload_campaign.dart \
  test/integration/android_notification_payload_campaign_support_test.dart \
  test/integration/group_reaction_notification_device_criteria_test.dart \
  go-relay-server/inbox.go \
  go-relay-server/group_content_push.go \
  go-relay-server/metrics.go \
  go-relay-server/ordinary_push_projection_test.go \
  go-relay-server/push_payload_closure_test.go \
  scripts/test/group_reaction_notification_device_contract_test.sh \
  scripts/test/run_ios_nse_native_373.sh \
  --budget 600
./graphify-arch/refresh_arch_graph.sh --incremental
```

`run_ios_nse_native_373.sh` must register all three new XCTest selectors,
change every exact native cardinality from 17 to 20, and invoke the exact
TC-398-03 Python unittest. That existing native tail is the aggregate
registration; do not add another wrapper. The existing shell contract must
also assert that the exact iOS chat proof is registered in
`group_announcement_reaction_notification_proof_test.dart`.

### Authorized Current-Source Pre-Claim Restart Amendment

The user explicitly authorized one evidence-preserving restart after the
idempotent Release-bound iPhone readiness repair changed the suite source
while the diagnostic claim, active lease, and authoritative scenario artifact
were still absent. This amendment does not authorize another diagnostic send,
an artifact purge, or overwriting retained preparation.

Extend the existing Plan-398 staging helper, not a second script, with one
literal-authorized `restart-current-source` subcommand. It must:

- acquire the existing nonblocking Plan-398 transaction lock before examining
  or moving state and hold it through the archive receipt fsync;
- require the literal authorization ID
  `plan398-reviewed-current-source-restart-v1`, the exact retained source
  digest, and the exact freshly computed current source digest;
- require the plan-wide claim, active lease, and authoritative scenario
  artifact to be absent; require the retained deployment receipt and prepared
  snapshot to agree on the expected old digest; and require the retained
  restoration receipt to prove the prior manifest, installed relay, and
  running `MainPID` executable were restored before archiving;
- recompute the same suite-source digest used at `claim-send`, require it to
  equal the command's expected current digest and differ from the retained
  digest, and execute no Sims build, relay build/deploy, runner, validator,
  claim, or send;
- hash the complete retained campaign entity, atomically move it to the
  deterministic sibling
  `preclaim-campaign-archives/current-source-restart-<old12>-<new12>`, fsync the
  parent, and atomically write a mode-0600 sibling receipt using schema
  `mknoon.plan398.preclaim-current-source-restart.v1`; the receipt binds the
  authorization ID, full old/current source digests, archive relative path,
  full entity digest, restored state, and explicit absent claim/artifact/lease
  booleans, never credentials or device/account content;
- recover idempotently if interruption occurs after the atomic move but before
  receipt creation: an absent live campaign plus the exact deterministic
  archive may be rehashed and sealed, while every other absent/collision or
  mixed live/archive state fails closed; and
- leave the fixed live campaign root absent so the ordinary `run --run-id
  diagnostic` path creates one fresh current-source campaign. The durable
  plan-wide claim remains in its original parent namespace, so this restart
  cannot reset or bypass a claimed attempt.

Extend only the existing Plan-398 shell transaction contract. It must prove
one restored pre-claim failure archives without any preparation, mutation,
runner, claim, or send during the restart; seals the exact entity digest and
private receipt; is idempotent across the move-before-receipt crash state; and
then permits one fresh current-source run. It must also prove wrong
authorization, old/current digest mismatch, claim present, artifact present,
active lease, unrestored receipt, archive collision, and concurrent lock
ownership all fail before moving the campaign. Representative mutation: omit
the claim-present guard; the existing contract must RED, then the inverse
patch must restore GREEN. This remains TC-398-08 transaction coverage, not a
new case or framework.

After focused GREEN and mutation restoration, compute the final current source
digest, invoke the subcommand once with retained digest
`d5995a332e351817047451a2d5e358e0bfa84fff43b62107ff68409404cec925`,
validate the archive receipt/entity independently, and only then invoke the
already-written single diagnostic command on the Release-ready iPhone 13. No
manual move, deletion, or second diagnostic root is authorized.

### Authorized Release Setup-Readiness Amendment

The first current-source campaign above stopped before claim or send after its
exact Release setup app remained foreground but emitted neither
`intro_e2e_identity.json` nor a result file. The retained campaign is restored,
its source digest is
`ef4afcfbf5232a0f641fc8c16a57cbdc3598dc8f12a4025bc4e7adb1d9accee0`,
and the plan-wide claim, active lease, and authoritative diagnostic artifact
remain absent. This amendment authorizes only a causal setup-readiness repair,
one evidence-preserving current-source restart, and one setup-only physical
attempt. It does not authorize a provider send, relay deployment, group
fixture mutation, diagnostic claim, artifact purge, or second diagnostic
campaign.

Keep the exact signed setup profile and existing owners. Do not add another
profile, scenario, proof file, capture framework, or generic bootstrap
receipt. The exact iOS setup app writes one app-container file,
`intro_e2e_setup_readiness.json`, with schema
`mknoon.plan398.ios-setup-readiness.v1`. The existing campaign readiness
selector forwards a fresh bounded launch-attempt value under the exact setup
profile; the app and host retain only its SHA-256. Ordinary builds, other E2E
profiles, other platforms, and launches without the exact setup gate remain
unable to emit or accept this receipt.

Every persisted receipt is closed: `status` is `PASS` or `FAIL`, never
`pending`, and `stage` is exactly one of `profile_launch`,
`identity_generation`, `identity_reload`, `qr_generation`,
`identity_export`, or `ready`. Before each fallible setup operation, atomically
replace the receipt with the corresponding closed FAIL state; successful work
may advance it but may never erase or skip a stage. A process interruption
therefore leaves the last armed stage rather than an ambiguous foreground
process. The exact outcomes are:

| Observation bound to the current launch-attempt SHA | Closed disposition |
|---|---|
| Exact profile/Release product or required launch input is rejected | `profile_launch_failed` |
| Identity generation returns non-success or throws | `identity_generation_failed` |
| The post-generation identity reload is absent or throws; username persistence is not durable | `identity_reload_failed` |
| Signed QR construction is non-success, null, or throws | `qr_generation_failed` |
| Atomic identity-file write/flush/verification fails or its SHA cannot be bound | `identity_export_failed` |
| Exact identity file exists, its SHA-256 equals the receipt binding, and all prior stages are consistent | `ready` / `PASS` |
| No current-attempt receipt appears within the bounded poll after the exact Release app was launched | host-only `pre_entry_failure`; never infer readiness from process foreground state |

The receipt has an exact allow-listed shape: schema, status, stage, reason,
exact profile ID, launch-attempt SHA-256, booleans for launch input,
identity-present/generation-attempted/generation-succeeded/reload-succeeded,
QR-built, and identity-exported, an identity-export SHA-256 only for `ready`,
and `containsSecrets=false`. It must not contain the raw launch attempt,
username, peer ID, QR payload, public or private keys, ML-KEM material, relay
addresses, exception text, stack traces, credentials, or message/account
content. Write both readiness and identity files with flush plus atomic replace;
publish `ready` only after independently hashing the final identity file.

Extend one existing causal owner,
`test/core/debug/group_reaction_notification_ios_setup_profile_test.dart`,
with the exact test
`Plan 398 setup readiness receipt closes every stage and binds the exported identity`.
Deterministic fakes must select profile/launch rejection, generation failure,
generation-success/reload-missing, QR failure, export failure, ready, stale or
mismatched launch-attempt receipt, contradictory fields, and absent receipt as
`pre_entry_failure`. The same test must prove the exact closed schema and that
no supplied raw username, attempt, QR, identity, or exception marker appears
in serialized output. Wire the production path through
`group_reaction_notification_ios_setup_profile.dart`,
`intro_e2e_runner.dart`, and `debug_e2e_composition_root.dart`; extend the
existing composition/source preservation assertions only as needed to prove
the exact profile gate, stage order, XCTest attempt forwarding, and host
receipt-before-identity validation. Representative mutation: skip the
post-generation `identity_reload` FAIL arm; the named existing-owner test must
RED, and restoring the inverse patch must return it to GREEN.

After the focused RED/GREEN/mutation cycle and app-owned impact refresh, reuse
the already-proven `restart-current-source` transaction exactly once. Its
retained digest is the `ef4afc...` value above, its current digest is freshly
computed by the helper after the final source restoration, and its existing
literal authorization remains
`plan398-reviewed-current-source-restart-v1`. All original lock, restored-state,
claim/artifact/lease absence, atomic archive, receipt fsync, collision, and
idempotent recovery rules still apply. This is a second source-digest pair,
not a reset of the diagnostic allowance; the plan-wide claim remains outside
the archived entity.

Then perform one logical setup-only readiness attempt on the live-discovered
physical iPhone with a fresh attempt value and current signed Release product:

1. Build the exact setup profile with `E2E_TEST_MODE=true`,
   `SIMS_BUILD_PROFILE_ID=ios.device.group_reaction_notification_397`, and the
   already-authorized relay-address define; retain the secret-free build and
   product digests. Do not prepare Android, build/deploy a relay candidate, or
   create a deployment receipt or lease.
2. Patch the current `.xctestrun` through the existing relocation path with
   the setup username and launch-attempt value, prove it contains no Debug
   product path, install that exact Release app, and run only
   `RunnerUITests/NotificationTapUITests/testSettleLocalNetworkPermissionForCampaign`.
   The existing single automation warm retry, if needed, reuses the same
   product and attempt value and remains one logical setup attempt.
3. Poll only `intro_e2e_setup_readiness.json` and
   `intro_e2e_identity.json` through the existing AFC reader. Exact-validate
   the current-attempt receipt and identity-file SHA. Retain only the
   secret-free readiness receipt and hashes; any temporary raw identity export
   is mode 0600 and deleted immediately after hashing.
4. Stop. A matching `ready` receipt clears only identity readiness. Any closed
   FAIL, contradictory/mismatched receipt, absent current-attempt receipt, UI
   automation failure, or identity hash mismatch is one typed pre-claim
   blocker with no automatic second setup launch. Do not invoke `run`,
   `claim-send`, the sender, or standalone diagnostic validation in this
   setup-only leg.

The single diagnostic transaction may be reconsidered only after the
setup-only receipt is independently `ready` and Plan 398 records that evidence.
Its existing claim/send contract remains otherwise unchanged.

### Authorized Pre-Entry Bootstrap Causal-Audit Amendment

The current-source setup-only attempt above is closed as
`pre_entry_failure`, not as readiness: its exact Release XCTest selector proved
only that the native app process reached `runningForeground`, while the
current-attempt setup-readiness and identity files remained absent. Static
source audit now identifies the unobserved interval. The first setup receipt is
written only inside `runSimulatorAutoSetupIfConfigured`, but production
bootstrap reaches that call after the share-launch/documents join, durable
notification setup, database open and repair, post-open migrations,
`identity_store_ready`, bridge construction, and other composition work. The
existing `StartupTiming` marks are in-memory and print only in debug mode, so
their presence in source cannot classify a stalled or failed Release bootstrap.
An alive foreground PID, absence of a crash report, and a passing permission
selector therefore remain non-evidence for Dart setup entry.

This amendment authorizes only an earlier exact-profile receipt boundary, its
causal host tests, one fresh Release build, and at most one additional
setup-only physical attempt. It does not authorize the Plan-398 staging helper,
diagnostic claim, provider send, relay build/deploy, fixture mutation,
authoritative diagnostic artifact, or deletion/restart of the already sealed
pre-claim archives. The diagnostic allowance remains wholly unspent even if
the additional setup-only attempt reaches `ready`.

Keep the one existing file
`intro_e2e_setup_readiness.json`, the exact signed setup profile, the raw
launch-attempt-to-SHA binding, and the existing atomic writer. The next attempt
uses schema `mknoon.plan398.ios-setup-readiness.v2`; the retained v1
host disposition and its SHA-256 remain immutable historical evidence, not an
input accepted for the new attempt. Do not add a second receipt, native mirror,
generic bootstrap logger, `StartupTiming` persistence hook, profile, scenario,
or capture framework.

For the exact iOS + `E2E_TEST_MODE=true` +
`ios.device.group_reaction_notification_397` + valid current launch-attempt
gate only, advance the same closed FAIL receipt at these existing bootstrap
boundaries:

| Durable observation for the current launch-attempt SHA | Exact retained state and disposition |
|---|---|
| The application-documents future has resolved but the concurrently started share-launch probe has not completed | `stage=bootstrap_share_launch`, `reason=bootstrap_share_launch_incomplete`, disposition `bootstrapShareLaunchFailure` |
| `share_launch_probe_complete` and `documents_dir_ready` have both been marked, before database work | `stage=bootstrap_database`, `reason=bootstrap_database_incomplete`, disposition `bootstrapDatabaseFailure` |
| `database_ready` has been marked, before post-open identity-store migrations | `stage=bootstrap_identity_store`, `reason=bootstrap_identity_store_incomplete`, disposition `bootstrapIdentityStoreFailure` |
| `identity_store_ready` has been marked, before the later call to `runSimulatorAutoSetupIfConfigured` | `stage=bootstrap_auto_setup`, `reason=bootstrap_auto_setup_not_reached`, disposition `bootstrapAutoSetupFailure` |
| `runSimulatorAutoSetupIfConfigured` has entered | the existing `profile_launch` arm takes ownership, followed by the existing generation/reload/QR/export/ready states |
| No valid current-attempt v2 receipt appears | host-only `pre_entry_failure`; this bounds the failure before the earliest durable documents-path arm and never infers progress from foreground state |

Start the documents-directory and share-intent probes concurrently as today.
Attach the first receipt write to the documents-directory future and await that
armed future in the existing join, so a stalled share probe cannot erase the
earliest durable evidence. After each named milestone, atomically replace the
receipt with the next FAIL arm before beginning the next fallible interval.
Failure to flush, replace, or read back any exact-profile arm aborts bootstrap;
it must not continue into setup with ambiguous evidence. Every bootstrap arm
uses the same exact allow-listed v2 shape, keeps
`launchInputPresent=false`, all identity-progress booleans false,
`identityInitiallyPresent=null`, `identityExportSha256=null`, and
`containsSecrets=false`. No raw attempt, username, identity, QR/key material,
exception, stack, relay value, credential, or account/message content may be
serialized.

Author the first RED in the existing owner
`test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart`
with the exact name
`TC-398-08 exact-profile receipt arms before the share join and advances through bootstrap milestones`.
It must prove the documents-path arm precedes the share/documents join, each
later arm follows its named existing milestone and precedes the next interval,
the auto-setup call follows the final bootstrap arm, ordinary paths remain
closed, and there is exactly one call for each boundary. Extend the existing
`Plan 398 setup readiness receipt closes every stage and binds the exported identity`
test in
`test/core/debug/group_reaction_notification_ios_setup_profile_test.dart` to
prove all four new closed dispositions, exact v2 allow-listing, stale/mismatched
rejection, and secret absence. Extend existing composition/criteria/source
preservation assertions only as required; do not add a new test file or host
wrapper.

Representative mutation: move the first documents-path receipt arm to after
the share/documents `Future.wait`. The named phase-contract selector must RED
because a stalled share probe would again leave no durable evidence; restoring
the inverse patch must return the focused selectors to GREEN. Run the named
phase selector, the exact setup-profile selector, the existing debug
composition and device-criteria selectors, the existing Plan-398
transaction/source contract, targeted analysis, scoped hygiene, Graphify
affected analysis, and the incremental architecture refresh before any device
launch.

Only after those gates and mutation restoration, rediscover the live device
matrix and build one fresh exact Release setup product from the final source.
Use a fresh launch attempt, run only
`testSettleLocalNetworkPermissionForCampaign`, and poll the same readiness and
identity files. Retain the current v2 receipt or typed absence in a new
mode-0600 host receipt, hash then delete raw XCTest/identity material, and
stop. There is no automatic retry. A closed bootstrap/setup failure or
`pre_entry_failure` remains pre-claim `incomplete_evidence`; `ready` clears
only setup readiness and still does not invoke the diagnostic helper, claim,
or send under this amendment.

### Authorized Native-to-Dart Entry-Boundary v3 Amendment

The one v2 setup-only attempt above is closed as `pre_entry_failure`. The
XCTest runner received the bounded launch attempt, forwarded it to the exact
Release application, observed that application in `runningForeground`, and
retained AFC access for the whole poll. Neither fact proves that the launched
application received the environment, that `AppDelegate` reached its launch
callback, that Flutter entered Dart `main`, or that the pre-documents bootstrap
interval completed. The v2 receipt cannot separate those intervals because its
earliest writer waits for `getApplicationDocumentsDirectory()`, and its Dart
resolver returns `null` for a missing or malformed attempt.

This amendment authorizes only one earlier native-to-Dart boundary, causal
tests in existing owners, the corresponding host classifier update, and at
most one fresh Release setup-only attempt. It does not authorize the
Plan-398 diagnostic helper, a claim, provider send, relay build or deployment,
fixture or staging mutation, authoritative diagnostic artifact, generic
logger, second receipt, native mirror, source-archive restart, evidence purge,
or an automatic physical retry. The one-shot diagnostic allowance remains
wholly unspent regardless of the v3 result.

Keep the one application-container file
`intro_e2e_setup_readiness.json`. The fresh attempt uses schema
`mknoon.plan398.ios-setup-readiness.v3`; retained v1 and v2 evidence remains
immutable historical evidence and is never accepted for the fresh attempt.
The exact Release product remains bound to `E2E_TEST_MODE=true` and
`SIMS_BUILD_PROFILE_ID=ios.device.group_reaction_notification_397`. The
existing XCTest selector additionally forwards that exact profile ID to the
application under the Plan-398-only launch key
`MKNOON_398_SETUP_ENTRY_PROFILE_ID`, alongside the existing raw
`MKNOON_398_SETUP_READINESS_ATTEMPT`. The native gate requires both a
canonical fresh attempt and that exact runtime profile binding. Dart promotion
requires the same two launch values plus the compile-time E2E/profile gate;
the host accepts any native-only receipt only when it is also bound to the
independently hashed exact Release product. Ordinary launches, another build
profile, another platform, a missing key, a partial gate, or a malformed value
must neither create nor advance a receipt.

Add no production file. One testable, Plan-398-specific coordinator in
`ios/Runner/AppDelegate.swift` owns the native stages and the one method
channel `mknoon/plan398_ios_setup_entry`. At the start of
`application(_:didFinishLaunchingWithOptions:)`, before `super.application`,
it hashes the valid raw attempt in memory and atomically publishes the native
arm to the application Documents directory. The raw attempt must not be
logged, returned, or persisted. Install the channel idempotently from the
existing implicit-engine messenger path, with the same root-controller
fallback convention as the current native channels. Its only method is
`acknowledgeDartMain`; it accepts exactly `schema`, `profileId`, and
`launchAttemptSha256`, advances only the coordinator's current native arm for
the same attempt, and returns an exact acknowledgement of the retained Dart
arm. Unknown methods, extra or missing arguments, a stale hash, a wrong
profile/schema, an unarmed coordinator, or any write/read-back failure is a
closed channel error and cannot advance bootstrap.

Use the established native durability semantics: a unique mode-0600 temporary
file in the same Documents directory, complete file protection, encoded-size
bound, file flush/fsync, atomic POSIX rename over the one destination,
directory fsync, exact read-back, and temporary cleanup on every failure. A
native commit failure permanently rejects Dart advancement for that process.
Do not reuse the SIMS receiver-bootstrap directory, application-group state,
or notification log; only reuse their tested atomic-write pattern.

After the exact gate succeeds, `lib/main.dart` initializes the Flutter binding
and invokes one existing-owner entry helper before
`runApplicationBootstrap`. That helper belongs to
`group_reaction_notification_ios_setup_profile.dart` with the platform/channel
adapter in `debug_e2e_composition_root.dart`. It computes the same attempt
SHA-256, sends no raw launch value, exact-validates the native response, and
returns only after the Dart arm is durably retained. An ordinary build is a
zero-channel-call no-op. In the exact iOS setup profile, however, a missing or
invalid attempt/profile binding, native channel error, mismatched response, or
unretained arm throws before `runApplicationBootstrap`; the old silent return
is forbidden. The later bootstrap and setup writers may advance only from the
same current-attempt v3 receipt and may never skip, replay, or roll back an
entry stage.

The v3 allow-list is the v2 shape plus exactly
`nativeEntryAcknowledged` and `dartEntryAcknowledged`. Every receipt retains
the exact schema, `status`, `stage`, `reason`, exact profile ID,
`launchAttemptSha256`, the existing launch/identity progress fields, and
`containsSecrets=false`. The native and Dart-entry arms set all identity
progress booleans false, `identityInitiallyPresent=null`,
`identityExportSha256=null`, and `launchInputPresent=false`. They contain no
raw attempt, username, PID, timestamp, path, environment dump, channel error,
exception or stack text, identity/QR/key material, relay or credential value,
or account/message content. All later v3 bootstrap/setup arms set both entry
acknowledgements true and otherwise preserve the v2 field meanings and exact
stage order.

| Durable current-attempt observation | Exact retained v3 state and closed disposition |
|---|---|
| No valid current-attempt v3 receipt appears after the exact product launch | host-only `native_entry_failure`; this does not infer whether UIKit omitted the callback, the app rejected the launch environment, or the first native atomic commit failed |
| `AppDelegate` accepted the exact runtime gate and durably committed before `super.application` | `status=FAIL`, `stage=native_app_delegate`, `reason=dart_main_not_reached`, `nativeEntryAcknowledged=true`, `dartEntryAcknowledged=false`; disposition `dartEntryFailure` |
| Dart `main` passed the compile-time and runtime gates and the native channel durably advanced before production bootstrap | `status=FAIL`, `stage=dart_main`, `reason=application_documents_not_ready`, both entry acknowledgements true; disposition `bootstrapDocumentsFailure` |
| The application-documents future resolves | advance to the existing `bootstrap_share_launch` arm with both entry acknowledgements true, then preserve the exact v2 bootstrap/setup stages and dispositions through `ready` |
| A receipt is stale, malformed, wrong-schema/profile/product, contradictory, non-monotonic, or not bound to the expected attempt SHA | `invalid`; never downgrade it to one of the three causal entry dispositions |

Author RED first in the existing native owner
`ios/RunnerTests/IosReceiverBootstrapHandoffTests.swift` with the exact selector
`testTC398SetupEntryReceiptAdvancesNativeToDartAndRejectsGateBypass`. With an
injected Documents root and environment it must prove the native-before-Dart
states, exact keys and channel arguments, current-attempt binding, owner-only
file mode, bounded secret-free JSON, atomic replacement/read-back, stale or
replayed advancement rejection, failure cleanup, and zero file/channel
eligibility for ordinary, partial, malformed, or wrong-profile gates. Keep the
type in `AppDelegate.swift`; do not add a native file, target, scheme, or test
bundle.

Extend the existing Dart test
`Plan 398 setup readiness receipt closes every stage and binds the exported identity`
to prove the two new dispositions, exact v3 allow-list, monotonic transition
into every existing bootstrap/setup state, v1/v2/stale/mismatched rejection,
and secret absence. Add the exact existing-owner selector
`Plan 398 v3 entry gate fails closed before production bootstrap` in
`test/core/debug/group_reaction_notification_ios_setup_profile_test.dart` for
ordinary zero-call behavior and every partial/invalid exact-profile gate,
native error, wrong response, and the one valid acknowledgement. Extend the
existing composition/phase assertions to prove native publication precedes
`super.application`, the channel uses the implicit-engine messenger, Dart
acknowledgement precedes `runApplicationBootstrap`, and the first Documents
arm follows the Dart arm exactly once. Extend the existing device-criteria and
Plan-398 shell contract only as needed to prove the XCTest runtime-profile
forwarding, v3 host allow-list/classification, exact product binding, and
single-attempt stop rule; add no wrapper or scenario.

Representative mutation: change the exact-profile Dart entry resolver back to
returning `null` for a missing readiness attempt. The named v3 entry-gate
selector must RED because the exact setup product could again enter production
bootstrap without a current-attempt receipt. Restore the inverse patch and
require that selector, the exact setup-receipt selector, native selector,
composition/phase selectors, device-criteria selector, Plan-398 shell
contract, targeted analysis, scoped hygiene, Graphify affected analysis, and
the incremental architecture refresh to return GREEN before any device
launch. Preserve the previously observed v2-focused gates; do not rerun full
`host-all` for this amendment.

Only after those gates and mutation restoration may the execution rediscover
the availability-bounded device matrix, re-prove the diagnostic root, claim,
lease, authoritative artifact, helper/send process, provider send, and staging
mutation absent, and build one fresh exact Release setup product from the
final tree. Verify the product contains the v3 schema/stages/channel and the
compile-time profile gate; patch a private relocated `.xctestrun` with one
fresh attempt, username, and exact runtime profile binding; prove every app
path is Release and no Debug path exists; install that exact product; and
invoke only
`RunnerUITests/NotificationTapUITests/testSettleLocalNetworkPermissionForCampaign`.
The existing automation warm retry, if the already-defined XCTest launch
boundary needs it, reuses the identical product and attempt and still counts
as the one logical attempt; there is no application relaunch after a valid
selector result.

Poll only the same readiness and identity paths through AFC. Retain one
mode-0600, secret-free host receipt containing the exact product/attempt
hashes, the valid current v3 receipt or one typed absence, command ordering,
and cleanup hashes. Hash and delete the relocated `.xctestrun`, xcresult, raw
launch binding, AFC scratch, logs, and any identity material; preserve only the
closed receipt and already sealed historical evidence. Stop on
`native_entry_failure`, `dartEntryFailure`, `bootstrapDocumentsFailure`, any
existing bootstrap/setup failure, `invalid`, automation failure, identity
binding failure, or `ready`. There is no second setup attempt. Even `ready`
clears only setup readiness and does not authorize the diagnostic helper,
claim, send, relay/staging mutation, or duplicate-root repair.

### Report-Bound Diagnostic Transaction

Use one checked-in helper:
`integration_test/scripts/ios_group_message_diagnostic_staging.py`.
It is Plan-398-specific coordination around the existing Sims preparation,
device runner, validator, SSH/systemd operations, and Plan 397 staging
authority. It must not become a new notification scenario, generic deployment
framework, or second capture harness.

The diagnostic has one fixed campaign root, `build/plan398/diagnostic/`, and
one Plan-398-wide exclusive claim,
`build/plan398/diagnostic-campaign-claimed.json`. The claim binds the owning
run ID `diagnostic`; starting a new shell or supplying another run ID cannot
create another diagnostic send. A later reviewed closure amendment must use a
separate closure-claim namespace.

Acquire one Plan-398 transaction lock before state resolution and hold it
through capture and verified remote restoration. A second helper process fails
before preparation, deployment, runner invocation, or send. Under that lock,
resolve this table before artifact purge or mutation:

| Diagnostic claim | Diagnostic artifact | Only permitted action |
|---|---|---|
| Absent | Absent | Fresh/pre-marker-resume path: reprepare/rebuild/compare, deploy, claim, and send once. |
| Absent | Present in any state | `incomplete_evidence`; no purge, deploy, or send. |
| Present | Complete and exactly bound to claim, owner run ID, build inputs/artifacts, candidate, and deployment receipt | Restore first if required, then validation-only; no prepare, deploy, purge, or send. |
| Present | Absent, incomplete, or mismatched | Restore first if required, then `incomplete_evidence`; no prepare, deploy, purge, or send. |

A command naming a different run ID after the campaign claim follows the
claim's owner state and performs zero build/deploy/runner/send calls. A
markerless pre-send resume with retained reports/candidate/receipt is allowed
only through the first row: it must regenerate preparation/build evidence and
compare equal before continuing once.

The fresh path is fail-closed:

1. Re-run content-addressed Android and iOS Sims preparation into temporary
   campaign-owned reports and perform a fresh deterministic Linux relay build
   before every markerless send. Compare the exact profile, suite source
   digest, attestation `inputDigest`, artifact digest, relay revision, and
   candidate SHA with retained products/receipt; atomically retain only equal
   products. A mismatch is `incomplete_evidence`, never permission to
   overwrite evidence. Store resolved input digests in the Plan-398 receipt;
   do not change the shared Sims report schema.
2. Accept prior authority only from
   `build/plan397/deployment-state-02.json`. Never recapture prior state from a
   candidate. Before capture, both the installed relay SHA and the running
   systemd `MainPID` executable SHA equal the candidate. Manifest changes use
   the existing SHA-CAS.
3. At the exact network-send boundary, the capture driver invokes the helper's
   narrow `claim-send` operation. While holding the outer lock, `run` creates
   a random mode-0600 active-transaction lease bound to its coordinator PID,
   fixed run ID, deployment receipt, and prepared snapshot. `claim-send` does
   not reacquire the non-reentrant lock; it must validate the inherited nonce,
   live coordinator, lease bindings, current suite source through the existing
   report verifier, retained input/artifact digests, candidate SHA/revision,
   deployment receipt, and installed/running relay identity. An unleased,
   out-of-sequence, dead-coordinator, or changed binding returns without claim
   or send.
4. `claim-send` then creates the Plan-398-wide claim exclusively with mode
   0600, stores the owner run ID and random claim value, and fsyncs the file and
   parent directory before returning. If execution stops after that flush,
   every resume follows a claim-present row and cannot resend.
5. Invoke the existing device runner with exactly
   `ios_chat_group_message_and_reaction_recipient`,
   `--diagnostic-only-message-window`, and `--no-child-builds`. The existing
   proof file uses `iosChatGroupMessageAndReactionScenarioId` as both the test
   name and the argument to `_validateScenario`.
6. Wrap deploy plus capture in `try/finally`. On completion or signal, revoke
   and delete the active lease, terminate and await the exact runner process
   group, then restore the manifest, installed relay, and running `MainPID`
   executable to the prior SHAs before releasing the transaction lock. Only
   after verified restoration may the helper invoke standalone
   `--validate-artifacts`. Route SIGINT, SIGTERM, and SIGHUP through that
   ordered path. After uncatchable termination, the next invocation restores
   from the retained receipt before validation or blocker return.
7. Retain only campaign-namespaced, hash-bound receipts and secret-free
   evidence; never serialize credentials or raw message content.

Extend
`scripts/test/group_reaction_notification_device_contract_test.sh`—do not
add another test owner—with small fake SSH/SCP/systemd/runner fixtures. It
prints `RUN: Plan 398 staging transaction contract` before its assertions and
proves:

- the four state rows and exact proof registration, not merely scenario census;
- a different run ID after claim and a concurrent second process make zero
  preparation/mutation/runner/send calls;
- the nested leased `claim-send` succeeds without releasing/reacquiring the
  outer lock, while an unleased or out-of-sequence claim makes zero claim/send;
- matching retained pre-marker products reprepare/rebuild, compare equal, and
  send once, while a mismatch fails closed;
- a source/input mutation between preparation and `claim-send` produces zero
  send;
- claim flush precedes send, and interruption after flush revokes the lease,
  terminates/awaits the child process group, restores staging, produces no
  post-restore send, and cannot resend; and
- installed-versus-running SHA checks and one representative injected capture
  failure restore before standalone validation.

These are one transaction contract, not an exhaustive fault-injection
framework.

After the focused host/native gates pass, run the transaction once:

```bash
set -euo pipefail
test "${PLAN398_STAGING_SINGLE_OWNER:-0}" = 1
test -n "$MKNOON_RELAY_ADDRESSES"

python3 integration_test/scripts/ios_group_message_diagnostic_staging.py run \
  --project-root "$PWD" \
  --run-id diagnostic \
  --prior-authority "$PWD/build/plan397/deployment-state-02.json" \
  --sender "$PLAN398_ANDROID_ID" \
  --recipient "$PLAN398_IPHONE_ID" \
  --staging-manifest "$MKNOON_257_STAGING_MANIFEST" \
  --relay-target "$MKNOON_257_RELAY_TARGET" \
  --relay-key "$MKNOON_257_RELAY_KEY" \
  --relay-addresses "$MKNOON_RELAY_ADDRESSES" \
  --service-account "$FIREBASE_SERVICE_ACCOUNT" \
  --single-owner
```

The helper owns these stable outputs under `build/plan398/diagnostic/`:
Android/iOS preparation reports and selected attestation input/artifact
digests, relay candidate and SHA/revision, `deployment-state.json`,
`physical-proof/diagnostic-message-window`, and the claim SHA binding. The
claim itself remains at
`build/plan398/diagnostic-campaign-claimed.json`. Its exit is either a sealed
`diagnostic_complete` disposition or a typed blocker after verified
restoration. A valid native FAIL remains capture evidence, not an environment
failure.

Stop after this diagnostic. Record its single disposition and amend this same
plan with the proven production seam, its causal test/mutation, the one later
full command, and the final `groups` gate. That closure run uses a separately
reviewed closure claim; it never reuses or bypasses the diagnostic claim.
Incomplete, `candidate_single_unattributed_duplicate`, or nonreproducing
evidence does not authorize a guessed repository repair.

Semantic outcomes:

- REDs select exact authored tests and fail on the named missing behavior.
- Focused GREEN exits zero with all named tests selected.
- Diagnostic exits with sealed `diagnostic_complete` or typed blocker, never
  closure PASS; the plan is amended before repair/full run.
- No post-fix command is executable in the evidence-gated revision. The later
  amendment must require exactly one useful canonical remote request, one relay
  logical dispatch, no bad source, reaction/tap PASS, zero child builds,
  independent validation, and exact staging rollback.

### Authorized Existing-State Trace-Only Course Change

The TC-398-09 report-bound helper stopped before claim because its destructive
setup path could not cross the native-to-Dart setup-entry boundary. Do not run
that helper again. The user instead authorizes one narrower evidence attempt
through the existing device runner and capture driver. This amendment
supersedes only the physical diagnostic command above; it does not authorize a
duplicate-behavior repair, a second framework, or closure.

Add sibling runner mode `--trace-only-existing-state`, restricted to
`ios_chat_group_message_and_reaction_recipient`, together with required
`--group-name <existing-chat-group>` and
`--existing-target-marker <existing-incoming-message>`. The target marker is a
transient installed-probe input required by the already-installed Pixel binary;
neither it nor the raw group name may be retained. The runner forwards
`--no-child-builds` itself and must not purge or replace the scenario's existing
authoritative artifact, verdict, retained Plan-398 campaign, or restoration
evidence.

The capture branch occurs after bounded configuration/topology/relay/APNs
checks and before `_preparePlan398DiagnosticAuthority`,
`_preparePlan397CentralArtifacts`, or `_runPlan397IosAvailableStages`. It may
open the already-installed apps, start bounded Android/iOS log readers, stage
and delete only the existing nonce-bound runtime-probe request/result files,
read installed-state receipts, and navigate the Pixel to the named group. It
must make zero build, install, uninstall, app-data/private-state clear,
identity/account setup, contact setup, group creation/acceptance, staging
deployment, reaction, notification-tap, or retained-evidence purge calls.

Before claim or send, fail closed unless all of these are true:

- both pinned devices and their already-installed app identities are present;
- the Pixel installed SQLCipher probe finds exactly one named `chat` group, a
  usable latest group-key epoch/hash, and exactly one supplied existing
  incoming/read target message in that group;
- the iPhone installed container has a non-empty existing `identity.db`, the
  app can launch without replacement, notification authorization is usable,
  and a fresh relay-token registration is observed;
- relay/APNs configuration is live, the named group is openable on the Pixel,
  and no trace artifact or durable trace claim already exists.

After every preflight passes, take the relay/syslog baselines, durably create a
private mode-0600 trace claim, generate one new marker internally, and perform
exactly one send-button tap. A committed outcome continues; recovery-pending,
ambiguous, or failed outcomes retain the claim and stop without a re-tap. Reuse
the existing message-window relay terminal metrics, strict first-attempt
provider journal binding, Android event/collapse hashes, native delivered-card
inventory, and dispatch-correlation join. Perform no reaction or notification
tap.

Write a distinct, non-overwriting trace artifact and self-validate it through
the existing criteria module. It contains only the trace-claim SHA-256,
installed-state receipt hashes/redacted group proof, the existing hash-only
message window, the unique Plan-398 diagnostic disposition, exact execution
counts, and redaction assertions. It is `trace_complete` with
`closurePassed=false`; it never replaces or upgrades the authoritative
diagnostic/closure artifact. A pre-claim prerequisite failure writes only a
trace-specific typed failure and leaves the send allowance unspent. A
post-claim failure remains terminal evidence and cannot be retried under this
amendment.

Extend the existing owners only:

- `scripts/test/group_reaction_notification_device_contract_test.sh` proves
  routing, restriction, non-purge behavior, the pre-central-preparation branch,
  forbidden-call absence, claim-before-one-tap ordering, and no recovery re-tap;
- `test/integration/group_reaction_notification_device_criteria_test.dart`
  proves the trace artifact/claim binding, exact installed-state fields,
  hash-only relay/native join, non-closure status, and representative raw-value
  and second-send mutations.

After authored RED and focused GREEN, run Graphify affected plus the incremental
architecture refresh. Then rediscover the availability-bounded matrix and run
one read-only preflight. Execute the trace only if the exact named group,
existing target, account, push, relay, and no-prior-claim prerequisites are
present. Stop after the first trace artifact, typed pre-claim blocker, or
retained post-claim failure; do not fall back to the old helper.

### Authorized Manual-Send Relay-Only Course Change

The user explicitly authorizes Codex to continue through the root repair and
main-bug closure, asks to avoid iOS harness construction, and will perform the
phone-to-phone message sends. This amendment supersedes the automated-send
detail of the existing-state trace and the reaction/tap requirement for this
main-bug closure only. It does not authorize a second diagnostic send, device
reinstallation, private-state reset, identity/group recreation, raw evidence,
or an NSE suppression workaround.

Add `--manual-send-existing-state` only as a sibling of
`--trace-only-existing-state`. The driver must make no Android UI send tap.
After every preflight passes and the durable trace claim is flushed, it prints
one generated marker, waits for an explicit stdin acknowledgement while the
user sends that marker exactly once in the already-open named group, and then
uses the existing installed Android observation to prove exactly one outgoing
row and derive the independent expected-collapse hash. A missing, duplicate,
or different marker is terminal post-claim evidence; it never prompts a
second send. The artifact records `automation=manual_message_send`,
`manualMessageSendCount=1`, `messageSendTapCount=0`, and zero build, install,
uninstall, clear, setup, group-create, reaction, and notification-tap counts.
The raw marker and group remain transient and must not be retained.

Define a separate non-mutating trace-manifest authority with schema
`mknoon.plan398.existing-state-trace-manifest.v1`. It exact-validates staging,
live relay revision/SHA/addresses, `provider=apns`, provider readiness,
`productionDeploymentPerformed=false`, `allowAppDataReset=false`, and only
the installed-app iOS fields actually used by this branch (`bundleId` and
`systemLogExecutable`). It is a new private/local authority file; it never
replaces or rewrites the restored prior manifest, the retained candidate
manifest, or restoration evidence.

The restored relay does not export the Plan-398 attribution metric. Extend the
existing Plan-398 staging transaction helper with one relay-only manual-trace
transaction. Under the existing non-reentrant lock it verifies the retained
prior/candidate binaries and manifest authorities, the live prior relay, the
absence of a trace claim/artifact, and the retained pre-claim failure SHA; it
then installs only the instrumented relay candidate, runs the manual trace
against the trace-specific manifest, and restores the prior installed/running
relay in `finally`. It performs no mobile build, iOS XCTest build or selector,
app install/uninstall, device data clear, setup, group mutation, or staging
manifest replacement. The retained failure remains byte-identical and the
restored manifest remains byte-identical before and after the transaction.

For live iOS eligibility, require USB membership from `idevice_id -l` plus the
existing successful DDI/CoreDevice access check. Do not reject an otherwise
reachable USB iPhone merely because `xcrun xctrace list devices` places it in
its `Devices Offline` section.

Extend only the existing runner/capture, criteria test, and device transaction
shell owner. First prove the manual option is rejected outside the trace,
claim-before-ready ordering, zero automated sends, one acknowledgement, raw
value redaction, trace-specific manifest exactness, topology eligibility, and
restore-on-success/failure. Preserve the fully automated v1 trace contract as
a sentinel. Run the focused Go provenance/dispatch tests, the exact manual
criteria selector, the existing diagnostic preservation selector, the shell
transaction contract, scoped analysis, Graphify affected, and incremental
refresh before the first user send.

The one manual diagnostic send may name a repository root only from the closed
relay/provider/native disposition. After a causal RED/GREEN/mutation repair,
one separately claimed manual closure send is sufficient for this plan's main
bug when it proves exactly one canonical useful remote request, one accepted
logical dispatch, one accepted first provider attempt, no noncanonical/local/
sanitized/unknown sibling, and verified relay restoration. Reaction and
notification-tap closure remain deferred to the broader Plan-397 rollout and
are not a condition of this user-requested main-bug closure.

### Authorized Evidence-Preserving Pre-Claim Recovery

After the first manual transaction failed before
`PLAN398_MANUAL_SEND_READY`, the user explicitly authorized one replacement
transaction. This amendment supersedes only the single-transaction stop in
TC-398-11. It does not authorize another diagnostic send: the first transaction
created no trace claim or artifact, printed no marker, opened no message
window, and the user sent no message, so the existing one-send allowance is
still the sole allowance.

Before any candidate relay deployment, the replacement transaction must
archive the failed attempt's exact command journal, Pixel log, trace manifest,
and restored relay-state bytes into the fixed private
`preclaim-attempts/attempt-01` namespace using atomic no-replace publication and
a canonical hash-only receipt. Bind them respectively to SHA-256
`f62874be7b49f3593d5d5d72b5aa95ea0b646ebf0426f3dc45011c3bde0b023d`,
`553071a186a7d4a69b1c8c54814c1aaddc68d9145b7dcf8f9d8615f39ff5e615`,
`65e23da2bffb949f0491fb00ac3de875d56063ef4307fc6f5f78d121ecf7f729`,
and `b0e1d7d2ac2ebf40c827224b7ac124340f11ef4cad0f6f0d00484e2b9bd32d69`.
The existing mode-0600 failure remains byte-identical at SHA-256
`d160e1e70f53b0651c91dfd45401daf26b0a0c7f001b659ca1c9eb3a3070900a`.
Any absent, symlinked, non-private, mismatched, pre-existing-conflicting, or
changed source/archive stops before deployment.

The build-free authorization parser must remain GREEN for one-line normalized
ready tuples and AppDelegate's SDK-backed raw authorization values `2|3|4`
with alert/badge value `2`, while rejecting denied, disabled, incomplete,
mixed, unrelated, and cross-line evidence. Reuse Pixel `21071FDF600CSC`, iPhone
`00008030-001A6D2801BB802E`, group `Test`, and target
`TC398Target-trial2` only after fresh USB/DDI, claim/artifact, failure,
staging, lock, archive-source, and live prior-relay checks pass.

The helper must again stop at `PLAN398_MANUAL_SEND_READY`. Codex asks the user
to send the exact printed marker once and writes `SENT` only after the user
confirms that send. Any replacement pre-claim failure restores the prior relay
and stops without a third transaction; any post-claim ambiguity or failure is
terminal and never permits a re-prompt or re-send.

### Authorized Final Same-Container Manual Trace Amendment

The user explicitly authorizes one narrowly superseding TC-398-15 amendment.
It supersedes the preceding prohibition on a third transaction only for one
final `attempt-03`; it does not create another message allowance. The original
manual group-message send remains the sole unspent one-shot. The focused host
implementation and tests required to enforce this amendment are authorized,
but no live mutation may begin until they are GREEN.

The final helper path requires literal authorization ID
`plan398-reviewed-final-same-container-manual-trace-v1`; no alias, implicit
default, environment-only grant, or generic attempt ordinal is accepted.

Preserve attempt-01 byte-for-byte and mode-for-mode. Its private chained
receipt remains SHA-256
`760ac4280f93415845b31c30b7cfbd1e4d0e10efccb4d626ebcd376605295060`,
and its already-bound journal, Pixel log, trace manifest, and restored relay
state remain respectively
`f62874be7b49f3593d5d5d72b5aa95ea0b646ebf0426f3dc45011c3bde0b023d`,
`553071a186a7d4a69b1c8c54814c1aaddc68d9145b7dcf8f9d8615f39ff5e615`,
`65e23da2bffb949f0491fb00ac3de875d56063ef4307fc6f5f78d121ecf7f729`,
and `b0e1d7d2ac2ebf40c827224b7ac124340f11ef4cad0f6f0d00484e2b9bd32d69`.
The existing private no-replace failure remains byte-identical at
`d160e1e70f53b0651c91dfd45401daf26b0a0c7f001b659ca1c9eb3a3070900a`.
Record explicitly that attempts 01 and 02 retained no exact failed-run iOS
system-log bytes; never reconstruct or infer those bytes.

Before reusing any stable live path, extend the existing Plan-398 staging
helper and its existing shell contract to seal attempt-02. First `lstat` its
four sources as regular, non-symlinked, distinct files and bind them to:

- command journal SHA-256
  `8b0da6ebd454a5696b4971507485b7f2e3f319eef0cb60fc0e25676c60acf2c3`;
- Pixel log SHA-256
  `3c6432e0726599d4143ee4858afccc57c452a47058c95f1564ab59fb3074f0b2`;
- trace manifest SHA-256
  `65e23da2bffb949f0491fb00ac3de875d56063ef4307fc6f5f78d121ecf7f729`;
  and
- restored relay-state SHA-256
  `b0e1d7d2ac2ebf40c827224b7ac124340f11ef4cad0f6f0d00484e2b9bd32d69`.

Change only the Pixel log metadata from mode `0644` to `0600`; rehash before
and after and require byte equality. Do not rewrite, normalize, copy over, or
replace any source. Create the fixed mode-`0700`
`preclaim-attempts/attempt-02` directory without replacement, publish each
mode-`0600` member with a no-replace primitive, independently rehash and fsync
every member and the directory, and publish the canonical receipt last as the
only commit marker. The entity is complete only when that no-replace receipt
exists and revalidates; the receipt chains the unchanged attempt-01 receipt,
all four source and archive hashes, modes, byte counts, and explicit
no-failed-run-iOS-log fact. Any partial source set, shared inode, mismatch,
symlink, pre-existing complete or partial attempt-02, collision, incomplete
entity, or fsync/publication failure stops before build, install, relay
deployment, claim, or send. A receipt-less partial remains terminal evidence;
it is never cleaned, completed by a later invocation, or retried. A complete
attempt-02 likewise consumes the authority and always rejects a second helper
invocation.

Extend only the existing capture/runner path, not a new iOS harness, so the
final attempt cannot lose the evidence that blocked attempts 01 and 02. Before
the updated Runner's first launch, start `idevicesyslog`, verify the stream is
connected, open private unique no-replace stdout and stderr spools, and set the
fresh cursor. Stream the exact received bytes before decoding them for the
strict parser. Bind readiness only to the new Runner process and require one
fresh public `native_notification_settings` record proving authorization
`authorized|provisional|ephemeral` (or SDK raw `2|3|4`) with alert and badge
enabled; `<private>` is never evidence. On success, timeout, signal, child
failure, decoder failure, overflow, or any other exit, stop and await the log
process, fsync and hash both bounded spools, and atomically publish them before
the failure/verdict. Publish a separate private no-replace attempt-03 terminal
receipt that binds byte counts, hashes, modes, Runner PID, terminal stage and
exit status without replacing the old fixed failure. Focused negative,
interruption, overflow, ordering, and no-replace tests must pass first.

After those host gates, build exactly one ordinary signed Release `Runner.app`
from the final reviewed source. Before any install, bind the source-tree digest,
app entity and file-content digests, executable digest, bundle ID
`com.mknoon.app`, Team/application identifier, entitlements and APNs
environment, provisioning-profile digest, version/build, Release configuration,
and build attestation. The product must contain no E2E/setup defines, receiver
bootstrap flags, XCTest/UI-test product, relocated `.xctestrun`, or new harness.
Any source or product change invalidates the authority; no rebuild or substitute
product is permitted after the install begins.

Permit exactly one direct standard in-place install of that bound product on
iPhone `00008030-001A6D2801BB802E`. Before and immediately after the install,
and before first launch, retain hash-only container/identity receipts proving
the same existing application container and unchanged `Documents/identity.db`.
Allow only process termination plus the exact in-place install command. Do not
uninstall, clear, reset, restore, copy data to the phone, recreate identity,
recreate group `Test` or target `TC398Target-trial2`, downgrade, or roll back by
reinstalling. An install failure or container/identity mismatch consumes the
install authority and stops permanently; the updated Runner remains installed
after later failures.

Immediately before install and again before the final helper invocation,
revalidate USB Pixel `21071FDF600CSC`, USB/DDI iPhone
`00008030-001A6D2801BB802E`, group `Test`, target `TC398Target-trial2`, both
sealed attempt archives, the old fixed failure, absent trace claim/artifact/
verdict/lease, the nonblocking transaction lock, no competing helper, live
installed/running prior relay
`0ae5c7d7926d5e16bd43571f772f94ea4e4118d461878c2e71db0224d698b5ee`,
prior manifest
`8ea8ddf591d0bc64d38423ba0124ac1248431dbe0444d8f5c8aac2717839137b`,
and exact candidate relay
`5322abbe97c56380680f9975846f281c0e55d431d4b642f96bc1c402c4ac7667`.
Any mismatch stops before the next mutation.

Invoke exactly one final `manual-trace` transaction. Start the retained iOS
byte capture before the updated Runner's first launch and prove a zero
group-message provider baseline. Deploy the exact candidate relay only after
product, container, and syslog readiness, and hold the existing lock throughout.
Create and fsync the trace claim before printing exactly one
`PLAN398_MANUAL_SEND_READY group=Test marker=...`. No Pixel sender automation,
text injection, provider group-message dispatch, preloaded `SENT`, or other
message may precede the user's action. Stop at the prompt; ask the user to send
the printed marker exactly once, and write `SENT` once only after the user
explicitly confirms that exact send. No retry, re-tap, second marker, second
install, or further transaction is authorized.

On every exit, finalize the private attempt-03 journal, Pixel log, iOS stdout/
stderr spools, and terminal receipt; restore and independently verify the prior
relay binary, manifest, and active state; release the lock; retain every sealed
artifact; and stop. The one install authority is consumed when installation
begins, and the one final trace authority is consumed when the helper begins,
regardless of outcome. A pre-send failure never spends the user's one manual
message, but it still does not authorize another install or trace.

## Device/Relay Proof Profile

- Profile: `os-notification-device-lab`.
- Boundary being proven:
  real FCM -> APNs headers -> NSE -> `UNUserNotificationCenter` identifiers and
  source -> SpringBoard presentation/tap. Lower tiers cannot prove the second
  real remote request or provider collapse.
- Live availability check:
  planning observed at least one USB Android, physical iPhone, and iOS
  simulator. Rediscover with `flutter devices --machine`, `adb devices -l`,
  and `xcrun simctl list devices available`; only discovered IDs may be
  pinned. Historical IDs and OS versions are not prerequisites.
- Required setup:
  pinned USB Android sender, physical iPhone, any available iOS XCTest
  destination, final-tree report-bound artifacts, validated candidate staging
  relay/manifest, credentials, automated message observation, validation,
  cleanup, and rollback.
- Two-peer default:
  iPhone is required for the APNs/NSE/request-identifier/SpringBoard boundary;
  Android emulator cannot substitute. Use any discovered USB Android plus any
  discovered physical iPhone; no user taps.
- Closure role:
  diagnostic run is required source evidence but cannot close; later full run
  is required closure.
- `FLUTTER_DEVICE_ID`:
  host selector only; sender, recipient, simulator, artifacts, relay, and
  manifest remain explicit.
- Registration:
  existing `ios_chat_group_message_and_reaction_recipient`
  `classify_path`/catalog, plus its missing exact test in the existing proof
  file. The diagnostic flag is a mode, not a new scenario/Sims
  capability/profile or proof file.
- Discovery command:
  `dart run integration_test/scripts/run_group_reaction_notification_device.dart --scenario ios_chat_group_message_and_reaction_recipient --list-scenarios`
  -> exact scenario once. No broad Sims discovery gate is needed because no
  scenario or capability is added.
- Closure command:
  absent while evidence-gated. The amendment must add one full runner command
  plus the correct `--validate-artifacts <dir>` form and final `groups` gate.
- Deferred device work:
  unavailable versions/hardware are
  `N/A (target unavailable by project policy)`; additional Apple/TestFlight
  matrix belongs to rollout.

## Execution Interpretation And Done Criteria

- Expected RED:
  TC-398-01 through TC-398-06 fail after authoring because HEAD lacks per-card
  diagnostics, the final deadline fetch, receipt v2, final pull, retained-FAIL
  disposition, dispatch attribution/fallback preservation, exact iOS chat
  proof registration, the closed resume transaction, and diagnostic mode.
- Green sentinel:
  TC-398-07 preserves retry collapse, trigger authority, full horizon,
  duplicate latch, protected receipt, and existing ordinary Android/iOS
  projection/provider boundary; TC-398-01 proves the added deadline edge.
- Pre-existing dirty tree / known failure:
  shared worktree is materially dirty and user-owned; stage only owned paths.
  Plan 397 run 21 is retained device RED; staging rollback is verified.
- Environment blocker:
  missing live target, DDI/CoreDevice failure, credentials, invalid/absent
  receipt, stale/unbound artifact, or unknown staging state. A missing
  current-attempt setup-readiness receipt after exact app launch is the typed
  `pre_entry_failure`, not proof that a foreground process is ready. Valid
  native FAIL is not environmental.
- Scope drift:
  entitlement/provisioning, production, downstream mitigation, a generic
  framework or second helper, raw diagnostics, second diagnostic, or
  pre-amendment repair.

Evidence-gate exit:

- [ ] The secret-free run-21 baseline and checksum are sealed or execution
      stops as a prerequisite blocker; neither is reconstructed from prose.
- [ ] TC-398-01 through TC-398-06 record causal RED/GREEN/mutation re-red.
- [ ] TC-398-07 sentinels pass.
- [ ] The exact iOS chat proof is registered, and the expanded existing shell
      contract proves all four claim/artifact states, plan-wide new-run and
      concurrent exclusion, equal pre-marker resume, final-boundary mismatch
      rejection, durable claim-before-send ordering, and one interrupted
      restoration path.
- [ ] Every markerless send regenerates and binds mobile input/artifact digests
      plus the relay candidate SHA/revision; capture uses zero child builds.
- [ ] The current signed Release setup product emits one exact, secret-free,
      current-attempt setup-readiness receipt; `ready` binds the independently
      hashed identity export, while every failure stage and receipt absence is
      closed without claim, send, or automatic second setup launch.
- [ ] One diagnostic-only physical window is sealed and independently
      validated with the exact deployment-receipt SHA, closed single-owner
      attestation, strict one-first-attempt/no-retry/no-fallback evidence, and
      the durably flushed Plan-398-wide claim proving no new shell/run ID could
      send again.
- [ ] Exactly one closed disposition has complete per-card/relay evidence.
- [ ] Prior active staging relay/manifest are restored by SHA CAS; both the
      installed relay and running `MainPID` executable match the prior SHA;
      restoration precedes standalone validation; namespaced recovery
      sidecars remain inert and hash-bound as evidence.
- [ ] Plan is amended with proven root or remains gated/prerequisite-blocked;
      no guessed repair.

Final closure after execution-ready amendment:

- [ ] Amendment names every root behavior, test, HEAD failure, mutation,
      literal command, registration, and preservation impact.
- [ ] Root RED/GREEN/mutation and TC-398-07 sentinels are recorded.
- [ ] One final-tree report-bound full campaign proves one canonical useful
      remote message and one relay dispatch before reaction.
- [ ] Reaction/tap pass; no local/sanitized/unknown/duplicate is latched.
- [ ] Independent validation, cleanup, exact rollback pass.
- [ ] `groups`, scoped hygiene, and Graphify affected/refresh pass; rerun the
      native family only if the amendment changes native surfaces.
- [ ] `flutter analyze` has no new issues if amended Dart production requires
      it; `git diff --check` is clean.
- [ ] Scope Contract And Guard is respected.

Current sufficiency decision:

- With the review corrections above, diagnostic behaviors, causal rows,
  transaction safety, gates, preservation, registration, and the real boundary
  are sufficient without another plan or framework.
- Production root/repair mutation remain unresolved, so status is
  `evidence-gated`. TC-398-08 full closure and root behavior edits remain
  unauthorized until the single diagnostic supplies an amendment.

## Handoff

- First causal RED:
  `xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination "$PLAN398_IOS_TEST_DESTINATION" -only-testing:RunnerTests/IosNotificationRecoveryTests/testTC398GroupInventoryFiltersBeforeBoundAndMapsClosedDiagnostics`.
- Preservation:
  `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . -run '^TestRelayNotificationClosure_GroupMessageRetryCollapse$' -v -count=1`
  plus TC-397 XCTest selectors above.
- Manual registration:
  add three TC-398 XCTest selectors and the exact TC-398-03 Python unittest to
  `scripts/test/run_ios_nse_native_373.sh`, updating its native cardinality
  from 17 to 20; add the exact iOS chat test to the existing group/announcement
  proof file. The existing shell contract owns registration and transaction
  assertions, the criteria test is in `GROUP_TESTS`, Go auto-registers via
  `^TestRelayNotificationClosure_`, and the physical scenario remains
  classified.
- Migration:
  none.
- Boundary closure:
  one diagnostic-only USB-Android-to-iPhone message run, then only after root
  amendment/repair one final-tree full message/reaction/tap run.
- Unresolved evidence:
  producer of noncanonical request and root repair. A
  `candidate_single_unattributed_duplicate` requires an audit of
  uninstrumented repository bypasses before provider/Apple escalation;
  missing entitlement, nonreproduction, or incomplete capture does not
  authorize a repo fix.

## Execution Progress History

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-25 21:03 CEST | direct execution after user superseded plan authorization gates | `IosLocalNotificationFinalEffect.swift`, `NseInboxCandidateAdapter.swift`, existing `NotificationServiceConfigurationTests.swift`; existing staging helper and shell owner; no new harness | The user explicitly directed Codex to ignore this document as execution authority and finish from independent analysis. Both latent Release imports now use `#if DEBUG && canImport(Runner)`, with independent static regression checks; parse/typecheck, mutation predicates, diff check, and Graphify affected `2b0e022001354d26` pass. The install continuity seam now takes two fresh pre-claim samples and one post sample, keeps the bundle app URL literal and changed, binds optional literal app-data-container equality or AFC-root creation time plus `Documents/identity.db` path/type/creation time, requires a nonempty single-link DB, and treats size, modification time, and SHA only as diagnostics. Python/Bash syntax, the full staging/device shell contract, Graphify affected, and incremental refresh pass. | No build, install, relay mutation, claim, marker, or send occurred after the user's override. Independent current-code mapping found no receipt-free command: the existing `manual-trace` already owns relay deploy/restore, byte-exact `idevicesyslog`, existing-group/manual-send flow, and disposition, but obsolete final-runner receipt validation blocks it. This ledger is historical/checkpoint evidence only and no longer gates execution. Phase cursor `TC-398-direct-live-diagnostic-red`. | Next exact action: add one explicit `--live-diagnostic` branch to the existing Python/Dart/criteria owners, using a fresh artifact directory and preserving every topology, logger, group/target, relay verification/restoration, and terminal-evidence check while bypassing only obsolete attempt/final-runner receipts. Run focused tests plus combined affected/refresh; then build and independently attest a fresh signed Runner, capture twice-fresh preinstall continuity, install in place, verify postinstall continuity, and execute the smallest live diagnostic to classification and repair. |
| 2026-08-25 19:57 CEST | TC-398-16 authorized final build consumed with terminal Release failure; install forbidden | fixed attempt-01/02 evidence, final-Runner claim/receipt namespace, preserved Xcode activity log, read-only iPhone/container and relay guards; no source repair | The patched temporary-namespace live probe bound installed `com.mknoon.app` as `1.0.0+260825140300`, literal `Runner.app` URL, AFC-root SHA-256 binding `0af6fe88a608e611e3c2f4af1123c28122475fedc650c4c0da5983019961bc74`, and a non-empty identity file. All fixed absence, mode/hash, lock, USB/DDI, manifest, and remote relay guards then passed. Exactly one `prepare-final-runner-update` invocation used `1.2.398+260825200001`. It privately sealed attempt-02 receipt SHA-256 `909d7293a6be4087683379a082f47a09425e89eb58cc5d2c814b4054f55fb8a1` and entity SHA-256 `7bb31c0cf205ab2388b95c5d9928f6b009297bc70f69beb53b38dfa7c9f6aa0e`, then claimed the sole build as SHA-256 `b2b3f0aa09d46801fa1c27b00e7a53f23b45b5de5d9f4f9fd14c08130b1e82bb`. The ordinary Flutter Release build exited nonzero and the helper committed failed terminal receipt SHA-256 `16a9cddbce4a4d1abc36c15ab29814caa314e1cd0d2e929350ea7ec7834dc5b5` with `failure=final_runner_build_command_failed`; current suite-source SHA-256 remains the claimed `103bb1fec00c38a84fa35a963f474ef5611c4629a3b9d3c2e0aca778ab0e7804`. Independent Xcode activity-log SHA-256 `e7236b38c42507595bd595a089a95169bd7a9708c79ebbdd18f3918d20e1c114` identifies the exact compiler error: Release NotificationService compiled `IosLocalNotificationFinalEffect.swift` with `@testable import Runner`, but Release Runner was not compiled for testing. The same latent clean-tree guard exists in `NseInboxCandidateAdapter.swift`; both date to commit `ffe37b71af5759320e677fab5495b5635bd661ea`, while the synchronized extension source group includes both and excludes only `Info.plist`. | The prior signed `Runner.app` remains the older `1.0.01529.137.260824182546+260824182546` product and is not the claimed build. No successful signed product receipt, install claim/receipt, device install, relay deployment, trace claim/terminal/artifact/verdict, marker, or send exists. Post-failure inventory still reports the same installed version, literal app URL, and AFC-root container binding; the remote installed/running relay remains `0ae5c7d7926d5e16bd43571f772f94ea4e4118d461878c2e71db0224d698b5ee` and the manifest remains `8ea8ddf591d0bc64d38423ba0124ac1248431dbe0444d8f5c8aac2717839137b`. Separate read-only pulls showed `Documents/identity.db` byte hashes `afea311e11993159d4b1fee0bbc7a5c50f4f5486cd2122051be599e1ff08b631`, then `73e58b894288930a4d2b3d97ae6055f8dce1ff8ef352153ee06892235a25a4aa`, then stable `c4368b882ed947e810731f1e38023f79589881e9d71c74024ed99e76276b5fdf` across three rapid pulls despite the unchanged AFC root, so whole live SQLite-file equality requires correction before it can serve as an install identity invariant. Live AFC metadata exposes the incumbent DB as regular, nonempty, single-link, with creation time `1787568103202707992`; a future proof can bind that creation time while treating mutable size, modification time, and bytes as diagnostics. The failed no-replace terminal receipt consumes the sole build authority and collides the fixed namespace; editing either source or invoking any build/install now would exceed the reviewed amendment and break the claimed source binding. Phase cursor `TC-398-16-final-build-terminal-failure`; build-failure grounding is `query_id=327f65885ea948ff`, `evidence_digest=aa1bfcac98e02bb0`; identity-invariant audit grounding is `query_id=02b2b99c63444d68`, `evidence_digest=0c4c55dc37183c4d`. | Stop without install or source mutation. Any recovery requires an explicit reviewed replacement amendment that preserves attempt-01, attempt-02, the failed build claim/receipt, and the unbound activity-log limitation; changes both clean NotificationService guards to `#if DEBUG && canImport(Runner)` under the existing native configuration-test owner with independent mutations; captures replacement build stdout/stderr durably; replaces mutable database-byte equality with twice-fresh preinstall and fresh postinstall equality over fixed UDID, bundle ID, literal CoreDevice app-container URL, AFC-root creation time, and `Documents/identity.db` path/type/creation time while requiring a nonempty single-link DB and retaining its size, modification time, and SHA-256 only as diagnostics; and grants at most one new no-replace namespace and signed build. This proves same container and same incumbent DB file object, not independent semantic account identity. Independently verify a successful product receipt before separately authorizing install. |
| 2026-08-25 19:41 CEST | TC-398-16 live CoreDevice/terminal safeguards GREEN; final signed build ready | existing Plan-398 staging helper and shell contract; existing capture/criteria/test owners; no new harness | Independent live preflight exposed two false-GREEN assumptions before any mutation: current CoreDevice app inventory supplies `version`/`bundleVersion`/`url` rather than the legacy short-version/executable/data-container fields, and single-file `copy from` requires an explicit destination file. Focused REDs now cover that exact schema, AFC-root birthtime binding, private explicit pulls, non-newer/no-op installs, changed app URL, source drift after install, a terminal appearing while waiting for the transaction lock, a genuine pre-Pixel failure, and success-terminal ordering. The existing owners now map both inventory schemas, bind `afc-root-sha256`, require a newer product and changed app URL with unchanged container/identity hashes, revalidate current source and absent terminal state under lock, permit `pixelLog: null` only for a true pre-logger failure, and publish success only after artifact/verdict validation. Combined Graphify affected is `query_id=369d6db503cf4bca`; incremental refresh is current. Python compile/Bash syntax, targeted Dart analysis, all 12 durable-trace tests, and the full staging/final-Runner shell contract pass. | No attempt-02 archive, final-runner namespace, signed build, install, relay deployment, trace claim, marker, or send was created. USB Pixel `21071FDF600CSC` and iPhone `00008030-001A6D2801BB802E` plus DDI are live; retained attempt-01/failure and attempt-02 source hashes/modes are exact; claim/artifact/verdict/lease remain absent; the transaction lock is acquirable; the prior relay is active with installed/running SHA-256 `0ae5c7d7926d5e16bd43571f772f94ea4e4118d461878c2e71db0224d698b5ee`, prior manifest SHA-256 `8ea8ddf591d0bc64d38423ba0124ac1248431dbe0444d8f5c8aac2717839137b`, and retained candidate SHA-256 `5322abbe97c56380680f9975846f281c0e55d431d4b642f96bc1c402c4ac7667`. The iPhone identity is still non-empty; three independent Pixel/Runner/SpringBoard log sessions remain live. Pixel currently shows the Orbit row for group `Test` rather than an open conversation, so no automated tap/send is authorized. Phase cursor `TC-398-16-final-build-live-guard`. | Next exact action: exercise only the patched read-only live inventory/identity functions through a temporary namespace. If the current schema, AFC root, and identity hash bind exactly, recheck the fixed absent/evidence/relay guards and invoke `prepare-final-runner-update` once with version `1.2.398` and a build number strictly above installed `260825140300`; independently verify the signed product receipt before invoking the one same-container install. |
| 2026-08-25 18:47 CEST | TC-398-16 attempt-02/raw-log/same-container host safeguards GREEN; independent audit next | existing staging helper and shell owner; existing capture/runner/criteria owners; no new iOS harness | Attempt-02 sealing now precedes build and proves only the authorized Pixel `0644` to `0600` metadata change, exact byte/hash equality, private no-replace members, a distinct v2 receipt committed last, preserved attempt-01, and consumed-authority rejection. The existing capture path now tees exact raw iOS bytes before decoding, binds a fresh Runner PID, and durably commits private stdout/stderr, journal, Pixel log, claim, and attempt-03 terminal receipt with directory fsync and exact archive/build/install/exit authorities while preserving legacy automated trace behavior. The helper claims and runs exactly one ordinary signed Release build, validates product/signing/profile fields, claims and runs one direct same-container install, proves pre/post container and identity equality, and read-only revalidates every receipt before final relay deploy. REDs covered missing authority/APIs, public/non-exact modes, schema collision, real preserved-state preflight, receipt/exit/order gaps, and the missing build/install subcommands. GREEN evidence is Dart format/analyze clean, 104/104 criteria tests, Python compile, Bash syntax, and the full legacy-plus-final Plan-398 shell contract ending `PASS: TC-398-15 final Runner update is signed, one-shot, and same-container`; Graphify affected includes `c81521a09676494a`, and incremental refresh completed. | No real attempt-02 metadata, build product, device, relay, install, trace claim, marker, or send was touched during implementation. The user's latest direction authorizes continued execution through the main-bug fix without further plan-approval pauses, retains manual phone sends, and forbids a new iOS harness. Phase cursor `TC-398-16-host-safeguards-green-independent-audit`; current Dart grounding is `query_id=f4e3857537bb470a`, `evidence_digest=7afcc3094e1313fe`, with final host affected `query_id=c81521a09676494a`. | Independently inspect the merged Python/Dart receipt schemas and rerun Python compile, Dart analyze, the 104-test criteria owner, and the full shell contract. If exact, revalidate live guards and invoke `prepare-final-runner-update` once so it seals attempt-02 before the one signed Release build; do not invoke install or trace until its product receipt is independently verified. |
| 2026-08-23 | review correction | Plan 398 | external review claims checked against current source | all six substantive claims confirmed; one helper is justified, extra plan/scenario/framework is not | retain evidence-gated structure and narrow delivery | execute focused RED/GREEN, transaction contract, then one diagnostic |
| 2026-08-24 | TC-398-01 through TC-398-06 implementation GREEN | the plan-owned iOS, host bootstrap, Dart criteria/probe/runner, relay, staging transaction, tests, and registration surfaces | the six exact host selectors, three bootstrap tests, five exact Dart selectors, six exact Go selectors, the 20-selector native family, and the existing device source/transaction contract all exited zero | retained authored RED logs exist for TC-398-01 inventory/horizon and TC-398-02 handoff; the implemented surfaces now satisfy the bounded diagnostics, protected receipt, terminal pull, retained-FAIL disposition, relay attribution/fallback, expected-collapse hash, diagnostic-mode, registration, and closed transaction contracts | diagnostic-only implementation is GREEN; this does not identify a production duplicate root and does not authorize repair or closure | run every row's prescribed representative mutation, restore, then preserve the unclaimed one-shot boundary |
| 2026-08-24 | representative mutation re-red and restoration | the six prescribed TC-398-01 through TC-398-06 mutation surfaces | all six named mutations failed on their bound causal assertion; every source was restored and its exact selector reran GREEN | restored SHA-256 values were checked, and the complete native/source contract reruns passed | TC-398-03 through TC-398-06 do not have retained original authored-RED log files; their fresh prescribed mutation re-reds are the causal record and no missing log is reconstructed | retain these limits explicitly and proceed to impact/graph plus physical preflight |
| 2026-08-24 | preservation, hygiene, and impact | Plan-398-owned surfaces | the required preservation selectors, source contract, formatting, syntax, scoped whitespace, and targeted analysis passed; Graphify affected covered all 26 changed paths and the incremental architecture refresh completed | no Plan-398-scoped hygiene or analyzed issue remains; repository-wide whitespace remains only in unrelated diagnostic logs | host evidence gate is ready for the single diagnostic; the wider host sweep remains correctly deferred by project cadence | run the smallest physical permission selector before any diagnostic claim/send |
| 2026-08-24 | physical permission preflight | reusable physical-iPhone permission boundary | the smallest Local Network selector failed before its test body with `Timed out while enabling automation mode`; developer services mounted successfully, the one bounded warm retry failed identically, terminating the orphaned automation writer before one clean recovery probe did not clear the timeout, and a fresh retry after the user explicitly unlocked the USB phone failed identically | xcresult proves testmanagerd connected, authorized the runner, and launched the UI-test runner, but the automation daemon never completed enablement; CoreDevice independently proved the USB phone was unlocked during the resumed attempt; the device retained both its automation writer and local-authentication UI service after failure; all relay-address, credential-shape, prior-authority, prepared-snapshot, and setup-app inputs are present and mutually bound; the Plan-398 claim, active lease, and diagnostic artifact remain absent, and no capture/helper process or provider send was started | typed device-side UI Automation authorization prerequisite below the app boundary; ordinary screen unlock is insufficient; the Local Network alert automation itself was not reached, and the one diagnostic message window remains wholly unconsumed | on the USB iPhone, enable/approve UI Automation under Developer settings and enter its passcode if prompted; keep it unlocked, pass only the Local Network selector, then invoke the single staging helper transaction |
| 2026-08-24 | resumed harness architecture audit | shared capture core, Plan-398 transaction helper, physical permission/identity staging, retained pre-claim xcresults | shared-core unit/contract, Python compile, and the full existing Plan-398 transaction contract pass; live inventory pins USB Pixel `21071FDF600CSC`, physical iPhone 13 `00008110-00184D622289801E`, and an available simulator; retained xcresults prove the strict reset-and-tap Local Network selector later passed on that same iPhone 13, while subsequent campaign retries either timed out enabling device automation, found no new Local Network prompt, or reached the later identity-export boundary; no campaign claim/artifact exists and staging is restored | the campaign is non-idempotent because it reuses the destructive strict permission-proof selector on every pre-claim retry and equates an absent already-settled prompt with build failure; Apple documents UI automation as an XCTest/device authorization boundary and the repository already has a durable strict permission proof, so campaign readiness must be a separate prompt-if-present path without weakening the reset-and-tap proof | native fallback query `f39c8a1d353a4104`, digest `aefa5678893cb723`; author a focused source contract for distinct strict-proof versus idempotent campaign selectors, implement the shared permission helper/capture selection, run host/native GREEN, then rerun only the smallest iPhone-13 readiness leg before the still-unspent diagnostic |
| 2026-08-24 | idempotent physical permission readiness | `ios/RunnerUITests/NotificationTapUITests.swift`; `integration_test/scripts/capture_group_reaction_notification_device.dart`; `scripts/test/group_reaction_notification_device_contract_test.sh` | the focused transaction/source contract, Dart formatting/analyze, and exact simulator `build-for-testing` pass; a current signed physical build completed; the patched `.xctestrun` exact selector passed on iPhone 11 `00008030-001A6D2801BB802E` with the honest `action=no_prompt` marker; two pinned iPhone 13 attempts stopped before test launch because Xcode reported `Device is busy (Preparing iPhone)` | strict reset-and-tap proof and idempotent campaign readiness are now separate; `query_id=057fd4e45ed542f4`, `evidence_digest=19538d4b446a48de`, affected query `d389e56702414656`; Graphify incremental refresh passed; the Plan-398 claim and diagnostic artifact remain absent, so the one-shot send is unspent | when iPhone 13 `00008110-00184D622289801E` leaves Xcode preparation, rerun only `testSettleLocalNetworkPermissionForCampaign` from the current signed `.xctestrun`; if GREEN, invoke the single staging helper transaction on that iPhone, otherwise retain the typed physical-device blocker without claiming or sending |
| 2026-08-24 | rollover recovery and current pre-claim audit | current live matrix, signed readiness `.xctestrun`, retained diagnostic root, and Plan-398 transaction source | `xcrun devicectl device info ddiServices --device 00008110-00184D622289801E --auto-mount-ddis --timeout 60` exited 2 after the full bound, before the exact readiness selector launched; the authoritative scenario artifact, campaign claim, active lease, XCTest result, staging mutation, and provider send remain absent | the USB iPhone 13 is still blocked below XCTest; independently, the retained unclaimed deployment/setup receipt binds suite source digest `d5995a332e351817047451a2d5e358e0bfa84fff43b62107ff68409404cec925`, while the current transaction inventory is `8281a7628d61cc31501040624cfd4d00022be36dfd8819c4484f269502e38710`; current helper source correctly rejects this as `retained_ios_setup_binding_invalid` before deployment rather than overwriting retained evidence; Graphify `query_id=6ec4df95b0cf4d1b`, `evidence_digest=014be87f23accab7`, native follow-up `query_id=1af356d9dd904b96`, `evidence_digest=aefa5678893cb723`, and helper query `query_id=28326e0e25a348f5`, `evidence_digest=0c4c55dc37183c4d` | remain pre-claim `incomplete_evidence`; do not invoke the diagnostic helper or reset/archive retained products without an explicit reviewed amendment that preserves the old unclaimed evidence and defines a current-source campaign restart; the diagnostic allowance remains wholly unspent |
| 2026-08-24 | restarted iPhone-13 readiness recovery | current signed Release UI-test products and physical iPhone 13 `00008110-00184D622289801E` | after the phone restart, DDI services became usable and the first Debug-product selector exited zero, but the user's on-device observation of Flutter's debug-only launch warning invalidated that pass as readiness evidence; a fresh `Release` `build-for-testing` with the exact setup profile and existing bound relay defines succeeded, its patched `.xctestrun` proved zero `Debug-iphoneos` paths, and `testSettleLocalNetworkPermissionForCampaign` then passed 1/1 from `iphone13-release-idempotent-resume-01.xcresult` with `action=no_prompt` | the physical iPhone 13 automation/readiness blocker is cleared on an independently launchable Release app; Graphify `query_id=fff4f519226c48ba`, `evidence_digest=19538d4b446a48de`; the campaign claim, active lease, and authoritative diagnostic artifact remain absent, while the retained campaign source digest still differs from current source (`d5995a332e351817047451a2d5e358e0bfa84fff43b62107ff68409404cec925` versus `8281a7628d61cc31501040624cfd4d00022be36dfd8819c4484f269502e38710`) | the user authorized an evidence-preserving current-source restart; keep the one-shot send unspent until its exact fail-closed transaction proof is GREEN |
| 2026-08-24 | current-source restart amendment accepted | existing staging transaction helper and shell contract | the user explicitly authorized proceeding; the amendment is now normative and grounded with `query_id=f893f78ca3984092`, `evidence_digest=02a7ce143737588b`, plus registration query `query_id=9852e6b40c744cba`, `evidence_digest=8bcfc6e4472c731b` | only the literal-authorized, lock-held, restored, unclaimed, artifact-free atomic archive/restart is permitted; the diagnostic allowance is still unspent | author the focused existing-contract RED for claim-present rejection and move-before-receipt recovery, implement the helper seam, then run exact GREEN and mutation before any live archive |
| 2026-08-24 15:18 CEST | current-source restart RED/GREEN/mutation | `integration_test/scripts/ios_group_message_diagnostic_staging.py`; `scripts/test/group_reaction_notification_device_contract_test.sh` | the expanded existing contract first failed on the absent `restart-current-source` parser branch; after implementation it passed, bypassing the claim-present guard failed with `TC-398-08 current-source restart moved a claimed campaign`, and the inverse patch restored GREEN; Python compile, shell syntax, scoped whitespace, Graphify affected `query_id=047d9a2bc0574563`, and incremental graph refresh passed | the literal authorization, existing nonblocking lock, exact old/current digest binding, restored/unclaimed/artifact-free/lease-free guards, complete-entity atomic archive, mode-0600 receipt, move-before-receipt recovery, sealed idempotency, collision rejection, and one fresh-run continuation are causally covered; branch grounding is `query_id=aabdc53792744c29`, `evidence_digest=02a7ce143737588b` | compute the final source digest and perform the one reviewed live archive before any diagnostic transaction |
| 2026-08-24 15:22 CEST | authorized live current-source restart | retained campaign and `build/plan398/preclaim-campaign-archives/current-source-restart-d5995a332e35-ef4afcfbf523.json` | the helper recomputed final source digest `ef4afcfbf5232a0f641fc8c16a57cbdc3598dc8f12a4025bc4e7adb1d9accee0`, atomically archived retained digest `d5995a332e351817047451a2d5e358e0bfa84fff43b62107ff68409404cec925`, and an independent traversal validated entity SHA-256 `745d7265cc8ef72a1fb8ee3107cc275eefb0b41db09cb000f699ab04a428ae30`; live Pixel 6 `21071FDF600CSC`, physical iPhone 13 `00008110-00184D622289801E`, and available simulator were rediscovered | the fixed live campaign root, diagnostic claim, active lease, and authoritative artifact are absent, so the one-shot send remains unspent; the fresh execution shell does not contain `PLAN398_STAGING_SINGLE_OWNER`, `MKNOON_RELAY_ADDRESSES`, `MKNOON_257_STAGING_MANIFEST`, `MKNOON_257_RELAY_TARGET`, `MKNOON_257_RELAY_KEY`, or `FIREBASE_SERVICE_ACCOUNT`, and those live declarations/secret paths cannot be reconstructed from redacted receipts | re-export the six live staging inputs and freshly attest `PLAN398_STAGING_SINGLE_OWNER=1`; then invoke the already-written single `run --run-id diagnostic` transaction with the rediscovered device IDs |
| 2026-08-24 15:45 CEST | TC-398-08 pre-claim identity-export recovery | checked-in campaign configuration, fresh diagnostic root, physical iPhone 13, and retained failure/journal/restoration evidence | the user directed reuse of checked-in bindings; all five values in `docker-ws/run_reaction_campaign_386.sh` matched Plan-397 target/manifest authority, credential/key shape, restored installed/running relay identity, and the live device matrix. The single helper transaction rebuilt and verified both mobile profiles, completed the fresh central Release setup build plus RunnerTests dependency build, and passed `testSettleLocalNetworkPermissionForCampaign` 1/1 with `action=no_prompt`, then exited 78 at `plan397_fixture_staging` with `timed_out_waiting_for_physical iOS identity export for chat_member_target_author` | the plan-wide claim, active lease, and authoritative artifact are absent, so no provider send occurred and the one-shot boundary is unspent; prior manifest plus installed and running relay were independently reverified restored and restoration receipt SHA-256 is `5fb1ef1679dcfd47d261106a3a690b1558b034960ade80bbd4eff794ec122c17`. The retained journal records repeated `afcclient` exit `-2` during identity polling. Failure branch grounding: `query_id=23921536ed4c4a7a`, `evidence_digest=965915fd6254e69a`; phase cursor `TC-398-08-identity-export-recovery` | do not rerun or purge. First perform one bounded, read-only `afcclient` prompt/EOF probe against the retained installed app and source-verify `_runIosAfcCommands`; if the client completed the commands but the harness waited for a nonexistent trailing prompt, author the focused existing contract RED, implement the smallest process-completion repair, rerun focused GREEN/mutation, then resume only through the markerless helper path |
| 2026-08-24 16:20 CEST | TC-398-08 AFC completion hypothesis resolved | retained installed `com.mknoon.app` on physical iPhone 13; `_runIosAfcCommands`; command journal; claim/lease/artifact/restoration state | one bounded read-only `afcclient` probe issued two `info` commands, observed all three expected `> ` prompts, confirmed both identity/result files were absent, and then interrupted the intentionally interactive client after 20 seconds; retained attempts recur about every 2.2 seconds rather than the source's 15-second completion timeout | the process-completion hypothesis is refuted: the source prompt counter can complete and the prior `-2` journal values reflect SIGINT plus missing-file command failure, not a missing trailing prompt. Fresh branch grounding is `query_id=418e293749054c36`, `evidence_digest=4397481239c494ea`. The campaign claim, active lease, and authoritative artifact remain absent; the retained failure artifact and `status=restored` receipt remain present; no diagnostic process is running | remain pre-claim `incomplete_evidence`; do not patch `_runIosAfcCommands`, rerun/purge the campaign, or consume the one-shot send. A reviewed amendment must first authorize investigation of why the Release setup app did not emit `intro_e2e_identity.json` |
| 2026-08-24 16:35 CEST | TC-398-08 Release setup identity-readiness audit authorized | `runSimulatorAutoSetupIfConfigured`; `exportIdentityForIntroE2E`; exact setup profile/receipt; physical readiness XCTest; retained pre-claim archives | the user authorized proceeding. Current source and the signed setup receipt prove Release + `E2E_TEST_MODE` + exact profile activation, but the readiness selector proves only a foreground process. Auto setup can return without evidence at username, identity generation/reload, or QR/export failure, and an uncaught pre-`runApp` failure also leaves the native process foreground. Retained iPhone 11 and iPhone 13 attempts reproduce the missing identity; the earlier XCTest launch-environment and stage-order repairs are therefore superseded rather than candidates to repeat | no crash report exists for the latest attempt, the installed app process remains alive, both requested AFC files remain absent, staging is restored, and claim/lease/authoritative artifact remain absent. Producer grounding: `query_id=7a6bbe4fc4c4473d`, `evidence_digest=365784e9cf636287`; UI/native proof grounding: `query_id=9379794d1d254b92`, native follow-up `query_id=4ff90719a7214d58`, `evidence_digest=aefa5678893cb723`; phase cursor `TC-398-08-release-identity-readiness` | amend this same plan with one closed, secret-free setup-readiness receipt and one existing-owner causal contract that distinguish profile/launch, generation, reload, QR/export, and pre-entry failure. Author RED, implement and mutate/restore GREEN, then use an evidence-preserving pre-claim current-source archive/restart before one setup-only readiness attempt; do not claim/send until identity readiness is exact |
| 2026-08-24 17:23 CEST | TC-398-08 setup-readiness RED/GREEN and one physical setup-only attempt | exact setup profile/runner/export owners, existing host/native source contract, current-source archive, Release product, and physical iPhone 13 | the named existing-owner test first failed on the absent readiness API, then passed; removing the post-generation reload arm re-red with `identity_generation_failed` instead of `identity_reload_failed`, and restoring SHA-256 `c9d1dae32c0ca6c30b56d0a922a22b8b8b845399052ca2e8e2c58a9e3d6ae9fd` returned GREEN. Focused core/composition/criteria tests, the existing staging/source shell contract, affected `query_id=7a4df8d301ea4342`, targeted analysis, scoped hygiene, preservation tests, and incremental Graphify refresh passed. The reviewed restart archived retained source `ef4afcfbf5232a0f641fc8c16a57cbdc3598dc8f12a4025bc4e7adb1d9accee0` to current source `1090314618bc2b05fae1a9b10db444b96140269384e1d7dfd05334e89f12896c`; archive entity SHA-256 is `d86b339953e1b1278a3429d72399586d40032e9967d141af4502e636b3b78801` and private receipt SHA-256 is `d45ea2f60c5ff647eb04372364d2a0b16f4436ab051cc4a56d9be990f711c414`. One current Release `build-for-testing` succeeded; the exact selector passed 1/1 on iPhone 13 without warm retry and launch-attempt SHA-256 `60712e4955844af15d9ebfb911308021bb9bc36f2be53681028ada355c762d7c`, but CoreDevice and AFC both proved the current-attempt readiness and identity files absent while PID 756 remained alive and the local signed product contained all four readiness strings | the closed disposition is `pre_entry_failure`, retained in mode-0600 host receipt SHA-256 `d5ce6f9e6d636807e67d7b8de3e6f3b93b3b52a4577cb92755e673eef1ca8ecb`; raw launch binding, xcresult, and empty raw pull area were deleted after hashing. The live diagnostic root, claim, lease, authoritative artifact, provider send, and staging mutation remain absent, so the one-shot diagnostic allowance is wholly unspent. Producer grounding is `query_id=671c31395b554178`, `evidence_digest=4575d22595b1dfd1`; host/native grounding is `query_id=43f3ac553a6c45d5`, native follow-up `query_id=7220501710ed4b47`, `evidence_digest=aefa5678893cb723`; phase cursor `TC-398-08-pre-entry-failure-closure` | do not relaunch, claim, send, or invoke the diagnostic helper. First amend this same plan with a pre-entry causal audit and an earlier durably armed exact-profile receipt boundary, using current bootstrap milestones to distinguish a stalled/failed bootstrap before `runSimulatorAutoSetupIfConfigured`; author its existing-owner RED before any further physical attempt |
| 2026-08-24 17:52 CEST | TC-398-08 v2 pre-entry receipt RED/GREEN/mutation closure | production bootstrap, exact setup profile/root, existing phase/profile/composition/criteria owners, and existing Plan-398 transaction contract | the new phase selector first RED because the pre-join share arm was absent (`shareStage=-1`), and the existing profile selector separately RED on the absent bootstrap API/dispositions. The implementation attaches the first exact-profile v2 arm to the documents future before the share join, then advances before database, identity-store, and auto-setup intervals. Both selectors, all four focused owner files (97 tests), DTR-14, the staging/source shell contract, targeted analysis, and scoped code hygiene pass. Moving the first arm after the join re-red with `a stalled share-intent probe must leave a current-attempt receipt`; the inverse restoration returned production SHA-256 `982303fdcc738c5a5cf6e10e17fdd7ee5cf9eda358f1c19ce78e49b44ed687e0` and GREEN. Graphify affected is `query_id=a59076d751dc45dc`; incremental refresh passed; review grounding is `query_id=2be62ba836234496`, `evidence_digest=cd56935372880f9e` | a user-requested concurrent `core-host-all` audit was intentionally non-authoritative for this amendment: item 1 and the later manifest contract passed, while the 431-path batch exposed at least ten unrelated dirty-tree failures (including duplicate pre-existing startup checkpoint IDs and unclassified PiP paths) before interruption; the wrapper's signal-handling printed PASS despite those failures, so this row does not claim that broad gate. Every changed-surface/plan-prescribed gate is independently GREEN. The live diagnostic root, claim, lease, authoritative artifact, provider send, and staging mutation remain absent; one-shot allowance remains wholly unspent. Phase cursor `TC-398-08-v2-setup-only-preflight` | rediscover the availability-bounded device matrix, prove claim/send/helper absence, build one fresh exact Release setup product from the final tree, and perform at most one fresh-attempt `testSettleLocalNetworkPermissionForCampaign` plus readiness/identity pull. Retain a mode-0600 closed host receipt and stop; do not invoke the diagnostic helper, claim, or send even if v2 reaches `ready` |
| 2026-08-24 18:15 CEST | TC-398-08 v2 setup-only physical closure | final-tree Release setup product, continuity physical iPhone `00008110-00184D622289801E`, exact permission-settle selector, and AFC readiness/identity boundary | the availability-bounded matrix was rediscovered and the plan-owned diagnostic root, claim, lease, authoritative artifact, helper/send process, provider send, and staging mutation were absent. One fresh `Release` `build-for-testing` from suite source digest `de9ef3bd48007f34556a96e037688418facb86de29982ba0dbcbe2fe2badcf14` succeeded; its signed app has entity SHA-256 `6e1ab6110dacfdad26567089d68e1b66ab621930ba2db8a5008fcd78fd589ecc`, file-content SHA-256 `d35800dd13051722ec824c895c979e9f9804dadb6bcf03ed9dc3f028d8ba3494`, all v2 bootstrap markers, and a private relocated `.xctestrun` with 15 Release paths and zero Debug paths. The sole `testSettleLocalNetworkPermissionForCampaign` invocation passed 1/1 with no warm retry and launch-attempt SHA-256 `9dcd898155407222d503926ba8bd10d9d1ab0736dc7956dd9de362146750bd23` | all 17 AFC container probes succeeded across the bounded 187-second poll, but neither a current-attempt `intro_e2e_setup_readiness.json` nor `intro_e2e_identity.json` existed. The closed disposition is therefore `pre_entry_failure`, retained in mode-0600 host receipt SHA-256 `70912d6f158bfd4f85bdc932d51e8573a91ec63b77434dd33833966463398434`; raw build/test logs, xcresult, launch binding, private `.xctestrun`, AFC scratch, and temporary materializer were hash-bound and deleted. This bounds the failure before the earliest durable documents-path v2 arm and remains pre-claim `incomplete_evidence`; it does not identify a production duplicate root. Execution grounding is `query_id=3ec54ccfebd84195`, `evidence_digest=0c4c55dc37183c4d`; phase cursor `TC-398-08-v2-pre-entry-failure-closure` | stop. Do not relaunch, invoke the diagnostic helper, claim, send, mutate staging, or purge retained evidence. Any further physical attempt or earlier native-to-Dart/bootstrap-entry instrumentation requires a new reviewed amendment; the one-shot diagnostic allowance remains wholly unspent |
| 2026-08-24 | TC-398-08 v3 native-to-Dart entry boundary authorized | existing exact setup receipt/profile, iOS `AppDelegate`, Dart `main`, production bootstrap, and the setup-only physical boundary | the user explicitly authorized the proposed next diagnostic boundary after reviewing the v2 result. The intended scope is one hash-only, exact-profile-gated progression in the existing receipt namespace: native `AppDelegate` acknowledgement, Dart-`main` acknowledgement, then the existing bootstrap/setup stages; no generic logger, second receipt, diagnostic helper, relay deploy, claim, provider send, staging mutation, fixture mutation, or authoritative diagnostic artifact. After causal RED/GREEN/mutation and preservation gates, at most one fresh Release setup-only attempt may classify this interval; the one-shot diagnostic allowance remains unspent | v2 proves the XCTest runner received and forwarded the bounded launch attempt, the exact Release app reached foreground, and AFC remained usable, but it cannot distinguish app-side launch-environment propagation, Flutter/Dart entry, and the pre-documents bootstrap interval because the first current receipt is armed only after `getApplicationDocumentsDirectory()` resolves and the Dart gate silently returns on a missing attempt. Review grounding is `query_id=b9637c5474e946f0`, `evidence_digest=97c3bfb1740d0aca`; phase cursor `TC-398-08-v3-entry-boundary-authorized` | start a new code-only Graphify branch for `AppDelegate.swift`, `main.dart`, the exact setup-profile gate, existing native channels/atomic writers, and current causal owners; amend this same plan with the exact v3 schema, fail-closed gating, test/mutation contract, and single-attempt closure before editing production source |
| 2026-08-24 | TC-398-08 v3 native-to-Dart amendment authored | current `AppDelegate` implicit-engine channel lifecycle, synchronous Documents access, native fsync/rename/read-back writers, Dart `main`/bootstrap ordering, exact setup-profile resolver, existing Swift/Dart/device/shell owners | the reviewed amendment now fixes schema `mknoon.plan398.ios-setup-readiness.v3`, the runtime key `MKNOON_398_SETUP_ENTRY_PROFILE_ID`, channel `mknoon/plan398_ios_setup_entry`, native and Dart entry stages, two acknowledgement booleans, exact absent/native-only/Dart-only dispositions, monotonic one-file progression, secret-free atomic durability, fail-closed exact-profile behavior, causal selectors/mutation, and one setup-only physical stop rule. No production source was edited while authoring it | architecture grounding is `query_id=08cfb2bbbc1747bd`, `evidence_digest=74ff84619702d35a`, with native follow-up `query_id=0c72c13fc86d4b79`, `evidence_digest=a4689e2f672a29c1`; the post-document handoff and atomic-owner refinement are `query_id=b02c7e55b06c4a67` / `7a7edf64a3e34aa1` and `query_id=e8887b54519f4e41` / `a23fac6d35f8467f`. Phase cursor `TC-398-08-v3-entry-boundary-red` | author the exact Swift and Dart existing-owner REDs plus preservation/host REDs before implementing `AppDelegate`, `main`, receipt schema, channel, or harness production behavior |
| 2026-08-24 18:59 CEST | TC-398-08 v3 causal REDs and Dart receipt-domain GREEN | existing Swift handoff owner on booted iPhone 16e simulator `DBE8C32E-9F19-4593-860A-B41113791D79`; exact setup-profile Dart owner; existing composition/device/shell owners | the Swift selector failed to compile only because `IosSetupReadinessEntryCoordinator` and its outcomes were absent; the exact Dart selector failed only on the absent v3 schema, entry builder/gate/dispositions/transition API; and the Plan-398 shell contract failed on absent runtime-profile forwarding. The setup-profile production owner now implements the v3 allow-list, native/Dart entry builders and dispositions, exact-profile fail-closed acknowledgement contract, secret-free attempt hashing, and monotonic stage graph; its complete 5-test file is GREEN | no `AppDelegate`, `main`, composition adapter, bootstrap writer, XCTest, capture driver, or host-classifier production behavior has yet been changed for v3. Host branch grounding is `query_id=9cf8299826bf4718`, `evidence_digest=7faa655b93035160`; native branch grounding remains `query_id=e8887b54519f4e41`, native follow-up `query_id=a23fac6d35f8467f`, `evidence_digest=b826167faf3d3714`. Phase cursor `TC-398-08-v3-native-coordinator-green` | implement the Plan-398 coordinator inside `ios/Runner/AppDelegate.swift`, wire its pre-super native arm and implicit-engine/root fallback channel, then rerun the exact Swift selector to GREEN before wiring the Dart adapter/main and monotonic filesystem writer |
## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-25 23:49 CEST | authorized retry build consumed with terminal signature failure; install/live trace forbidden | private `final-runner-update-authorized-retry-01` build claim/terminal receipt; uninstalled Flutter/Xcode build products; read-only Xcode activity log and restored relay | Exactly one reviewed `prepare-final-runner-update --attempt-namespace authorized-retry-01` invocation used `1.2.399+260825234500`. It sealed build claim SHA-256 `29c4f55b1ce9cb12385b7efd64cde97746f10a2cdac5087fdf1146c73f6346a9` and failed terminal receipt SHA-256 `52b647325f8452720915004c9e2c830fa33d02a0d73f1c4634d55c9c65a011c7` with `failure=final_runner_codesign_verify_failed`; the closed namespace entity SHA-256 is `28313c331bbb93c6760bb754f5175bac0cad131ccf85808a4eb834cd8081d917`. Independent verification found the Flutter final copy at `build/ios/iphoneos/Runner.app` invalid because `Flutter.framework/Info.plist` was changed after signing from `BuildMode=release` to `BuildMode=profile`; the Xcode product at `build/ios/Release-iphoneos/Runner.app` remains signature-valid, but carries `aps-environment=development` and `get-task-allow=true`, so it also fails the reviewed production-signing contract. The contemporaneous unbound Xcode activity log SHA-256 is `ba3c30417aee1feff3105674edc35b67fe0bfe592feaa70f34ef2d480fd13662`. | The retry namespace contains exactly the private claim and failed receipt; no retained `Runner.app`, install claim/receipt, retry live output, device install, app launch, relay deployment, trace claim, marker, or message send exists. The installed app/container is unchanged and the remote installed/running relay remains prior SHA-256 `0ae5c7d7926d5e16bd43571f772f94ea4e4118d461878c2e71db0224d698b5ee`. Phase cursor `TC-398-authorized-retry-build-terminal-failure`; failure grounding is `query_id=c17f73a42bbe49ec`, `evidence_digest=4ebb814fd6506480`. | The one reviewed build authority and its literal namespace are consumed. The apparently valid Xcode output cannot be salvaged under current authority because its signing identity is development, not the required production APNs distribution identity. Install, relay mutation, live diagnostic, and manual send remain unspent but unreachable. | Stop without install or live mutation. Any recovery requires explicit reviewed authority for a new no-replace namespace and a corrected distribution-signing build/export path that retains stdout/stderr or an activity-log binding, selects only a post-build signature-valid product, and independently proves production APNs entitlements before permitting install. |
| 2026-08-25 23:42 CEST | authorized retry host closure and read-only live preflight READY | existing Plan-398 staging helper and shell contract; sealed attempts/first live trace/original failed build; live Pixel/iPhone, installed app container, and restored relay | The literal `authorized-retry-01` sibling namespace, exclusive retained `Runner.app`, paired build/install receipts, immutable prior-evidence binding, post-pause revalidation, compatible live runner route, and private outer live receipt passed Python compile, shell syntax, scoped diff, the full fake-host transaction contract, independent counterexample audit, Graphify affected `f28c6f04974a41af`, and incremental refresh. Read-only preflight then passed exact authority validation, USB/DDI discovery, a fresh/acquirable transaction state, installed `com.mknoon.app` continuity sampling, and remote installed/running relay verification. | Suite source digest is `c6fd5f2b28972f81daf8b27c6fbcd34e9b56bcdab10c0964221d4f517c4d2c3e`; installed app is `1.2.398+260825220001` with unchanged AFC root birthtime `1787568077974598721` and `Documents/identity.db` birthtime `1787568103202707992`; prior installed/running relay remains `0ae5c7d7926d5e16bd43571f772f94ea4e4118d461878c2e71db0224d698b5ee`, retained candidate remains `5322abbe97c56380680f9975846f281c0e55d431d4b642f96bc1c402c4ac7667`, and both the retry build namespace and retry live-output namespace are absent. Grounding is `query_id=dbf2598703c64c45`, `evidence_digest=0c4c55dc37183c4d`; phase cursor `TC-398-authorized-retry-live-build`. | The one reviewed build, install, relay transaction, and manual message remain unspent. No blocker is present; any command failure consumes only its literal no-replace authority and stops. | Invoke exactly one `prepare-final-runner-update` for `authorized-retry-01` with a version/build newer than the installed product, independently validate its retained signed-product receipt, then invoke exactly one same-container install. Only after continuity is sealed may the fresh retry live diagnostic start and pause at its single printed marker for the user's one manual send. |
| 2026-08-25 23:07 CEST | authorized second physical trace pre-mutation audit | sealed first live-trace namespace; consumed failed final-Runner build namespace; existing staging helper and shell owner | Read-only audit proved the first live trace, attempt-01/02 archives, retained failure, and failed build claim/receipt are private, hash-bound, and immutable. The live trace already supports a fresh output directory, but the final-Runner build/install owner is fixed to the consumed failed namespace and mutable global product path. No build, install, device, SSH, relay, claim, marker, or send occurred. Grounding is `query_id=b243b074ee70412c`, `evidence_digest=4397481239c494ea`. | User authorized one in-place install, one relay transaction, and one manual message while preserving all prior evidence. Safe execution is blocked until a literal retry namespace retains its own signed product and paired build/install receipts without changing the original namespace. Phase cursor `TC-398-authorized-retry-namespace-red`. | Add `authorized-retry-01` support under the existing helper and shell contract, preserving identical-namespace replay rejection; run focused RED/GREEN plus affected/refresh before any live mutation. |
| 2026-08-25 post-compaction | direct-live sealed-evidence salvage; plan retained as historical record only | sealed `build/plan398/direct-live-diagnostic` terminal/claim/journal/Pixel/raw-iOS files; read-only relay journal; current build/logger source anchors | All terminal references rehash exactly. Pixel evidence proves one outgoing row and one successful `live_and_inbox` publish to one recipient. The remote systemd window contains exactly one complete `group_inbox` primary provider acceptance and one first-attempt push success; its claimed-collapse SHA equals the independently reconstructed Android expected-collapse SHA `ec63c84176a9f5707e9897b251c005fc5ab02c7e50e3b54c979395982c009953`. The raw iOS stdout ends with `[disconnected]` at 20:02:46Z, while the send occurred at 20:04:27Z; the terminal is sealed `typed_failure` / `chat_group_message_native_inventory_receipt_missing`. | Closed disposition is `incomplete_evidence`: Android/relay provenance is canonical and single-dispatch, but there are no post-send iOS bytes or native card inventory, so duplicate count/source cannot be inferred. The installed ordinary Release build omitted `MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP`, and current logger handling did not fail when `idevicesyslog` exited before the send. No second send, relaunch, install, or relay mutation is permitted or planned. Grounding: compact `5233573d29464661` / `38b2d01e208316c0`, native `835b13320b804288` / `b826167faf3d3714`. | Add focused existing-owner REDs for the diagnostic build define and pre-send logger liveness, implement those two offline harness fixes, run focused gates plus Graphify affected/refresh, and report without another device attempt. |
| 2026-08-24 19:22 CEST | TC-398-08 v3 native and Dart entry wiring GREEN | `ios/Runner/AppDelegate.swift`; `lib/main.dart`; `lib/debug/debug_e2e_composition_root.dart`; `lib/core/debug/intro_e2e_runner.dart`; existing Swift/composition causal owners | `IosSetupReadinessEntryCoordinator` now accepts only the complete exact runtime gate, persists only the attempt SHA-256, commits a mode-0600 complete-protection receipt through unique-temp flush, atomic POSIX rename, directory fsync, and exact read-back, permanently closes on commit failure, and advances once through the implicit-engine/root-fallback channel. Dart now initializes the binding and exact-profile adapter before `runApplicationBootstrap`; later filesystem publication validates the retained receipt and permits only the current-attempt next stage. The composition selector first RED at the absent Dart-main call and then passed; the tightened native selector passed again on booted iPhone 16e (`0.030s`). | Host capture/classifier production behavior and the Plan-398 shell/runtime-profile forwarding remain to be made GREEN; no physical app launch, diagnostic helper, claim, provider send, relay/staging mutation, fixture mutation, or evidence purge occurred. Dart branch grounding is `query_id=f9e354b9d19444f1`, `evidence_digest=e78c11d3238a409d`, with measured native fallback `query_id=4187d0a320c547f6`. Phase cursor `TC-398-08-v3-host-contract-green`. | Run the exact profile, phase, device-criteria, and Plan-398 shell selectors to isolate the remaining host/runtime-profile RED; implement only the v3 capture/classifier and stop-rule wiring, then run the representative missing-attempt mutation before any physical build or launch. |
| 2026-08-24 19:35 CEST | TC-398-08 v3 host/runtime-profile GREEN and mutation closure | `ios/RunnerUITests/NotificationTapUITests.swift`; `integration_test/scripts/capture_group_reaction_notification_device.dart`; exact profile/composition/phase/device/shell/native owners | The XCTest campaign selector now exact-validates and forwards `MKNOON_398_SETUP_ENTRY_PROFILE_ID`; both relocated and process environments carry the same profile; typed receipt absence maps to `native_entry_failure`; and the existing identical-product/attempt automation warm retry remains one logical attempt. The complete 5-test setup-profile owner, exact composition and phase selectors, device-criteria selector, Plan-398 staging/source shell contract, and exact Swift coordinator selector all passed; the Swift selector passed on iPhone 16e simulator `DBE8C32E-9F19-4593-860A-B41113791D79` (`0.261s`). Returning `false` for a missing exact-profile attempt re-RED with `Expected: throws StateError; Actual: emitted false`; restoring the inverse branch returned every focused gate GREEN. Targeted analysis, formatting, syntax, and scoped whitespace passed. | Graphify affected covered the 14-file v3 batch at `query_id=2bb5125236ee48cd`; the later capture-only correction was re-covered at `query_id=85bd7b883b9e4f06`; both incremental architecture refreshes passed. No physical app launch occurred before these gates, and no helper, claim, provider send, relay/staging mutation, fixture mutation, or evidence purge occurred. | Rediscover the live matrix and active-state guards, then perform at most one final-tree Release setup-only attempt and stop on its first closed v3 disposition. |
| 2026-08-24 20:02 CEST | TC-398-08 v3 setup-only physical closure | final-tree exact-profile Release product; continuity iPhone `00008110-00184D622289801E`; private relocated `.xctestrun`; native/Dart readiness receipt; AFC boundary | The availability-bounded matrix rediscovered USB Pixel `21071FDF600CSC`, Android emulator `emulator-5554`, three USB iPhones, and four available simulators. The active diagnostic root, claim, lease, authoritative artifact, helper/send process, provider send, and staging mutation were absent and the transaction lock was nonblockingly acquirable. One fresh `Release` `build-for-testing` from suite digest `abf0f727b356b398317b8bbf4b7c9a5be55951ca4a57f4a5b9b4d311b56ae5d8` produced a valid signed app with entity SHA-256 `c41dec8fd6f76a0ce60ee0d16068b27aa3a50e0a899b00233ce628cd881cbf9d`, file-content SHA-256 `40d9ba5bd051e00431245fb5e831a2417e986a913303804d1bfdc434c7d8a5a7`, and every v3 schema/stage/channel/profile marker in the native and Dart binaries. The private `.xctestrun` had 15 Release application paths and zero Debug paths. The sole logical `testSettleLocalNetworkPermissionForCampaign` invocation passed 1/1 with no warm retry and attempt SHA-256 `abfd8feb17ffd162220eb85267d0f74dc91b903cc99520f9c805cab74e8ccbb5`; the first successful AFC probe retrieved the exact current v3 receipt and no identity. | The durable receipt is `status=FAIL`, `stage=native_app_delegate`, `reason=dart_main_not_reached`, `nativeEntryAcknowledged=true`, and `dartEntryAcknowledged=false`, so the closed disposition is `dartEntryFailure`: native launch/environment acceptance and atomic publication succeeded, but no durable Dart-main acknowledgement followed. A temporary validator initially labeled it `invalid` only because Dart build-hook progress prefixed the disposition on the same stdout line; direct production classification returned `dartEntryFailure`. The corrected mode-0600 host receipt preserves the original receipt verbatim and hash `ab975cd588365be5d548ec12ffac9050d6382856a539690736a7113578c3f9f9`, records `physicalRelaunchPerformed=false`, and has final SHA-256 `9f90a28625d7fc5a6c38b82a249b415127702dfc3d617963f1d445ddbca4b34e`. All raw build/test logs, xcresult, launch binding, username, identity material, AFC scratch, private `.xctestrun`, DerivedData, and temporary materializers were hash-bound and deleted; only the closed receipt remains. This remains pre-claim `incomplete_evidence` and identifies no notification-duplicate production root. | Stop. Do not relaunch, invoke the diagnostic helper, claim, send, mutate relay/staging state, repair duplicate behavior, or purge retained evidence. Any investigation beyond the native receipt into Flutter engine/Dart entry requires a new reviewed amendment; the one-shot diagnostic allowance remains wholly unspent. |
| 2026-08-25 10:24 CEST | TC-398-09 provider-to-device provenance instrumentation partial GREEN | relay source/projection/retry journal; native Swift and host Python causal owners | The user authorized observability only: a unique logical-dispatch correlation, Firebase response hashes, claimed collapse hash, and delivered-request hashes; suppression/dedupe behavior remains forbidden. Relay causal tests first failed on the absent generator/schema and now pass for retry stability, distinct logical sends, invalid-provenance fail-open, Android exclusion, and strict Firebase response-name parsing. Native and host test owners contain authored RED expectations only; no native/host production implementation or physical run has started. | Relay grounding is `query_id=17fbdcae0206464d`, `evidence_digest=4afbf3d5243d4845`; native grounding is `query_id=3f055c1e349e4523`, `evidence_digest=bf0affe4b15806d6`, native fallback `query_id=7cfd43799ad54d2d`, `evidence_digest=6dd4934c3164bd24`; host grounding is `query_id=48bce90b10974f5a`, `evidence_digest=cab874bf1f1e852d`. Phase cursor `TC-398-09-provenance-native-red`. The one-shot diagnostic remains unspent. | Resume by asserting relay strict-fallback tuple/journal privacy, then run the three exact native selectors RED and implement native result v3/diagnostics v2; finish host receipt/artifact v3/v2 propagation and focused gates before any device campaign. |
| 2026-08-25 10:55 CEST | TC-398-09 provenance implementation GREEN; focused QA active | relay strict-fallback/journal owners; native inventory/result/handoff owners; Python bootstrap; Dart receipt/artifact/capture owners | Relay attribution, fallback, Android-exclusion, and hash-only journal selectors pass. Native result v3/diagnostics v2 first RED on absent provenance members and then passed 3/3 exact selectors plus preservation. Python result-v3/receipt-v3 parsing passes all 13 bootstrap tests. Dart artifact v2 and the strict accepted-dispatch journal join pass their focused tests. Independent native review found that noncanonical exact-useful cards could still publish PASS and that aggregate rows could contradict counts; causal tests were added, the missing PASS predicate first RED at compile, and the five-selector repair run passed. | No physical launch, diagnostic helper, claim, provider send, relay/staging mutation, or evidence purge occurred; the one-shot diagnostic remains unspent. Native repair grounding is `query_id=6681688922ce4117`, `evidence_digest=eb41845575d6a462`; latest test fallback is `query_id=de607e299e094666`, `evidence_digest=32da3f09893447eb`. Phase cursor `TC-398-09-provenance-focused-qa`. | Run the combined focused Dart/Python/Go/native QA, complete one combined Graphify affected check and incremental refresh, resolve any host counterexample findings, then evaluate the availability-bounded one-shot device campaign without launching it before every gate passes. |
| 2026-08-25 12:28 CEST | TC-398-09 provenance counterexample closure and registered-family GREEN | relay journal/projection; native inventory/result/handoff; Python receipt; Dart capture/criteria; native family registration | Counterexample review found and closed final-inventory-versus-latched-union false rejection, contradictory FAIL aggregates/open result codes, canonical FAIL/PASS inversion, empty native final-record bypass, provider source/claimed-collapse misjoin, subprocess exit mismatch, and typed-capture rewrapping. Focused RED/GREEN passed: 8 Go sentinels, 27 Dart support tests, both Plan-398 criteria selectors, all 13 Python bootstrap tests, and four exact native selectors. The Plan-398 transaction/source contract passed. The first registered native-family run reached 21 passing tests but correctly failed its stale 20-pass summary; all five remaining cardinality literals were changed to 21 and the complete wrapper reran GREEN with mutation restoration and `PASS: Plan 373 iOS NSE native host contract`. Targeted formatting, analysis, compile/syntax, and scoped diff checks passed. | Artifact v2 remains hash-only; provider source and claimed-collapse are transient join inputs, provider-message equality remains diagnostic-only, valid transient native FAIL remains capture evidence, and only exact canonical PASS/`ok` can pass. Graphify affected completed at `query_id=6c321182d96c41a9`; incremental refresh is current. Review grounding is `query_id=2fca7fdb4aac41d8`, `evidence_digest=66d044903faabce6`. No physical launch, helper, claim, provider send, staging mutation, or evidence purge occurred; the one-shot diagnostic remains unspent. Phase cursor `TC-398-09-provenance-live-preflight`. | Rediscover the availability-bounded device matrix and read-only active-state guards, close the one outstanding measured Graphify fallback follow-up, then invoke the single report-bound diagnostic transaction only if claim/artifact/lease/helper/send/staging guards and current-source preparation are exact; otherwise retain a typed pre-claim blocker. |
| 2026-08-25 12:31 CEST | TC-398-09 live diagnostic preflight READY | live device matrix; fixed diagnostic namespace; checked-in staging bindings and protected inputs | Rediscovery found USB Pixel 6 `21071FDF600CSC`, physical iPhone `00008110-00184D622289801E`, Android emulator `emulator-5554`, and available/booted iPhone simulators. The fixed `build/plan398/diagnostic` root, plan-wide claim, deployment receipt, prepared snapshot, active lease, restoration receipt, and authoritative artifact are all absent; no helper/capture/runner process exists and the transaction lock is nonblockingly acquirable. Service-account, relay-key, staging-manifest, and Plan-397 prior-authority inputs exist and pass bounded shape checks. The missing measured fallback was executed as native `query_id=3abf42d4a4124a77`, `evidence_digest=5ff8a92cf280b1be`, following `50233f63234e4a7e`. | This is the fresh/absent state-table row. No claim, send, deploy, staging mutation, or device launch occurred during preflight; the one-shot diagnostic remains unspent. Phase cursor `TC-398-09-report-bound-diagnostic-run`. | Invoke exactly one helper `run --run-id diagnostic` with the pinned Pixel/iPhone and the reviewed checked-in staging inputs under a fresh `PLAN398_STAGING_SINGLE_OWNER=1` declaration; let the helper reprepare/rebuild, claim only at the exact send boundary, restore in `finally`, independently validate, and stop on its first sealed disposition or typed pre-claim blocker. |
| 2026-08-25 13:01 CEST | TC-398-09 report-bound transaction stopped pre-claim | merged native/Python/Dart provenance validators; fresh mobile/relay preparation; exact-profile Release setup selector; retained Plan-398 campaign and restoration evidence | Post-integration QA passed: four exact native selectors on simulator `DBE8C32E-9F19-4593-860A-B41113791D79`, all 13 Python bootstrap tests, 115 Dart support/criteria tests plus targeted analysis, eight exact Go sentinels, and the existing Plan-398 staging transaction contract. Combined Graphify affected is `query_id=91fb43b01b2a494f` and the incremental architecture refresh is current. The single helper invocation regenerated Android/iOS preparation, built relay candidate SHA-256 `5322abbe97c56380680f9975846f281c0e55d431d4b642f96bc1c402c4ac7667` from suite digest `d56ba9a7996eff4c8a9cd59fe0e168a59154abd21289adf7376c8b1cff4d3b82`, built the exact-profile Release setup product, and passed `testSettleLocalNetworkPermissionForCampaign` 1/1 with `action=no_prompt`; capture then closed at `plan397_fixture_staging` with `plan398_ios_setup_readiness_dartEntryFailure`, and the helper returned `INCOMPLETE_EVIDENCE: diagnostic_runner_failed_1`. | This is a typed pre-claim blocker, not the notification diagnostic: the plan-wide claim, active lease, and authoritative scenario artifact are absent, and no provider send occurred. The retained capture-failure SHA-256 is `3dc1cff5d2acd81bac07d774522fb26e3fbbd03b5ecfdeebc1840d3e8cfd07f0`; the orchestrator-verdict SHA-256 is `55537c891a82523a01ff9005927a8bd38977dd843d3110762b6f45942a7f7754`. Restoration receipt status is `restored`; independent SSH/SHA verification proves the active installed and running relay match prior SHA-256 `0ae5c7d7926d5e16bd43571f772f94ea4e4118d461878c2e71db0224d698b5ee`, and the manifest matches prior SHA-256 `8ea8ddf591d0bc64d38423ba0124ac1248431dbe0444d8f5c8aac2717839137b`. The one-shot provider-send allowance remains unspent. Phase cursor `TC-398-09-dart-entry-preclaim-blocker`. | Stop. Do not rerun, purge the retained campaign, claim, send, mutate staging, or repair duplicate behavior. Any further attempt requires a reviewed amendment that resolves the repeated exact-profile `dartEntryFailure` while preserving the retained prepared/deployment/restoration and failure evidence. |
| 2026-08-25 13:15 CEST | TC-398-10 narrow trace-only course change authorized; design active | existing device runner/capture, installed-state probe, relay/provider journal, and native delivered-inventory seams | The user explicitly rejected another full bootstrap loop and authorized one narrow Pixel-to-iPhone group-message trace. Current-source verification confirms why the old path cannot be reused: diagnostic mode still prepares central artifacts, clears every Pixel private app entry, reinstalls and reinitializes Android, uninstalls the iPhone app, requires the failing exact-profile identity setup, and creates a fresh fixture before it ever sends. The existing message window below that setup already supplies one-message/no-reaction/no-tap behavior, hash-only Android event/collapse binding, relay terminal/provider correlation, and native delivered-request inventory. Grounding is `query_id=45848f2949334499`, `evidence_digest=19538d4b446a48de`; installed-state seam refinement is `query_id=d8602395492b4da6`, `evidence_digest=ed1bf193054745a5`. | Add no second framework and do not rerun the old helper. Extend the existing runner/capture with a sibling trace-only mode that performs no build, install, uninstall, identity setup, private-state clearing, group creation, reaction, or tap; it must verify a named existing group and installed-state prerequisites before any deploy/claim/send, send exactly one generated marker, and reuse the existing hash-only relay/native provenance closure. If the group/account/push prerequisites are absent, fail fast before external mutation. Phase cursor `TC-398-10-trace-only-red`. | Finish the exact seam/test-owner audit, amend the focused contract, author RED, implement the trace-only branch, run focused QA plus Graphify affected/refresh, then preflight and execute it only if the existing device state is usable. |
| 2026-08-25 15:04 CEST | TC-398-10 trace-only RED/GREEN; live prerequisite blocker | existing runner/capture/criteria and shell/Dart owners; read-only live installed-state inventory | The reviewed amendment now fixes the sibling flag, required named group and existing incoming target, zero-build/install/uninstall/clear/setup/create/reaction/tap path, non-overwriting fixed artifact/0600 atomic claim, one-tap/no-retry send, hash-only installed-state/window contract, and non-closure disposition. The shell owner first failed at the absent runner route and the Dart owner failed at the absent schema/validator; runner, capture, and criteria implementations now format/analyze cleanly, the exact TC-398-10 selector and existing Plan-398 diagnostic preservation selector pass, and the full existing device/source transaction shell contract passes. Review grounding is `query_id=c746ffb81a4b4de7`, `evidence_digest=19538d4b446a48de`. | Strictly read-only rediscovery found Pixel `21071FDF600CSC` has a valid installed identity but no current reusable `TC397` chat/target after its 2026-08-25 private-state reset. iPhone `00008030-001A6D2801BB802E` still has a non-empty `Documents/identity.db`, but membership in any group shared with the current Pixel is unproven; iPhone `00008110-00184D622289801E` has no identity database. Retained historical group/message markers predate the Pixel reset and include no usable incoming target. Therefore the exact group/target preflight is absent, the trace claim/artifact remain absent, and no launch, send, install, relay mutation, or device-state mutation was performed. Phase cursor `TC-398-10-focused-review`. | Finish the trace-specific counterexample audit and runner failure-preservation correction, rerun the exact focused gates, run one combined Graphify affected check plus incremental refresh, then record the typed `existing_group_or_target_absent` pre-claim blocker and stop without invoking the trace. |
| 2026-08-25 15:25 CEST | TC-398-10 trace-only focused closure and typed staging-manifest blocker | trace runner/capture/criteria and shell owner; refreshed installed Pixel/iPhone apps; manual existing group state; retained restored staging manifest; fixed trace failure namespace | The trace-specific failure-preservation counterexample first RED because a trace child configuration failure replaced the authoritative scenario verdict. The shared mode-0600 atomic no-replace failure writer now preserves authoritative evidence across runner topology/driver/launch, child pre-owner configuration, nonzero child exit, and outer validation paths. The full shell contract, exact `TC-398-10 existing-state trace binds one send to redacted installed state` selector, existing Plan-398 diagnostic preservation selector, targeted analyzer, and scoped diff check passed. Graphify affected covered the four-file correction at `query_id=c7c1b8c616a44165`, and the incremental architecture refresh passed. The user then prepared existing group `Test`; a transient exact-path Pixel probe proved exactly one `chat` row, usable group key, exactly one incoming/read `TC398Target-trial2` target, and zero reactions. USB Pixel `21071FDF600CSC` and iPhone `00008030-001A6D2801BB802E` were live with preserved non-empty identities; the fixed trace root was absent; and restored prior-manifest SHA-256 `8ea8ddf591d0bc64d38423ba0124ac1248431dbe0444d8f5c8aac2717839137b` matched the independent restoration record. | The sole trace runner invocation exited `78` at `stage=configuration` before device inventory because the restored prior manifest lacks required `iosCapture`, declares a non-APNs provider, and therefore fails the trace staging-manifest contract. Private failure `build/plan398/tc398-10-existing-state/plan398_existing_state_trace_failure.json` is mode `0600`, SHA-256 `d160e1e70f53b0651c91dfd45401daf26b0a0c7f001b659ca1c9eb3a3070900a`, records `traceAttemptClaimed=false` and no completed stages. The fixed claim, trace artifact, and trace verdict are absent; no Pixel send, provider send, relay/staging mutation, reaction, or tap occurred. Phase cursor `TC-398-10-staging-manifest-preclaim-blocker`; inspection grounding is `query_id=0123158c01104627`, `evidence_digest=59cfdac53348a9ba`. | Stop. Do not rerun or replace the retained failure, claim, send, mutate staging, or fall back to the old helper. Any future trace attempt requires a separately reviewed amendment that defines a non-mutating trace manifest authority with the required APNs/`iosCapture` contract while preserving this failure evidence and the unspent send allowance. |
| 2026-08-25 15:46 CEST | TC-398-11 manual-send relay-only path GREEN; live preflight next | existing runner/capture/criteria, Plan-398 staging helper, criteria owner, and existing transaction shell owner | The user authorized completion of the main bug, no iOS harness build, and manual phone sends. The amendment adds a trace-only manual flag, exact private non-mutating APNs manifest with only bundle/system-log inputs, DDI-plus-USB topology, claim-before-ready stdin acknowledgement, zero Android UI send taps, and a relay-only lock/deploy/restore transaction. The automated trace contract remains a sentinel. Targeted analysis is clean; the exact automated/manual criteria selector, trace-manifest selector, USB/topology selectors, diagnostic preservation selector, five focused Go provenance/dispatch sentinels, and the full staging/source transaction shell contract pass. The shell transaction proves manual success, runner failure, retained-failure mismatch, no mobile/relay build, no manifest swap, one send bracket, and prior installed/running relay restoration. Graphify affected is `query_id=296044b7bb3d4b84`; incremental refresh passed. | The restored relay remains prior SHA-256 `0ae5c7d7926d5e16bd43571f772f94ea4e4118d461878c2e71db0224d698b5ee` and lacks the attribution family; retained instrumented candidate SHA-256 is `5322abbe97c56380680f9975846f281c0e55d431d4b642f96bc1c402c4ac7667`. The private retained failure remains mode `0600` and SHA-256 `d160e1e70f53b0651c91dfd45401daf26b0a0c7f001b659ca1c9eb3a3070900a`; trace claim/artifact remain absent, so no send allowance is spent. Grounding is `query_id=c879768cccbc452e`, `evidence_digest=4397481239c494ea`, with manual counterexample audit `query_id=4fc11173fa534a14`, `evidence_digest=02a7ce143737588b`. Phase cursor `TC-398-11-manual-trace-live-preflight`. | Rediscover the live USB Pixel/iPhone matrix and read-only claim/artifact/failure/staging/relay guards. If exact, start the single `manual-trace` transaction with Pixel `21071FDF600CSC`, iPhone `00008030-001A6D2801BB802E`, group `Test`, and target `TC398Target-trial2`; stop at `PLAN398_MANUAL_SEND_READY`, ask the user to send the printed marker once, acknowledge with `SENT`, retain the closed disposition, and restore before any root repair. |
| 2026-08-25 16:29 CEST | TC-398-12 manual pre-claim parser blocker; recovery preparation GREEN, authority pending | live manual-trace transaction; current AppDelegate/syslog contract; capture/criteria owners; staging helper and existing transaction shell owner | The single TC-398-11 transaction passed the exact local/USB/DDI/lock/staging/retained-product/live-relay guards, deployed the retained instrumented relay, and then failed closed before `PLAN398_MANUAL_SEND_READY` with `timed_out_waiting_for_existing iOS notification authorization`. The user correctly sent no message. Claim, artifact, verdict, message marker, message-window metrics, provider send, and native observation are absent; the prior installed/running relay SHA-256 `0ae5c7d7926d5e16bd43571f772f94ea4e4118d461878c2e71db0224d698b5ee` and prior manifest SHA-256 `8ea8ddf591d0bc64d38423ba0124ac1248431dbe0444d8f5c8aac2717839137b` were independently reverified after restoration. Retained attempt hashes are journal `f62874be7b49f3593d5d5d72b5aa95ea0b646ebf0426f3dc45011c3bde0b023d`, Pixel log `553071a186a7d4a69b1c8c54814c1aaddc68d9145b7dcf8f9d8615f39ff5e615`, trace manifest `65e23da2bffb949f0491fb00ac3de875d56063ef4307fc6f5f78d121ecf7f729`, restored relay state `b0e1d7d2ac2ebf40c827224b7ac124340f11ef4cad0f6f0d00484e2b9bd32d69`, and unchanged mode-0600 failure `d160e1e70f53b0651c91dfd45401daf26b0a0c7f001b659ca1c9eb3a3070900a`. Current source and retained native logs prove the host accepted only normalized settings words while AppDelegate emits Swift `rawValue` descriptions; the physical run retained no iOS syslog, so its observed tuple remains unknown, while the user independently confirmed Allow Notifications, Alerts, and Badges are enabled. A build-free pure parser now accepts only one-line normalized ready tuples or SDK-backed raw authorization `2|3|4` with alert/badge `2`; the raw-setting mutation REDs and the restored focused selector passes 3/3. A fail-closed recovery seam archives the four exact prior attempt files as private no-replace attempt-01 evidence before any candidate deploy and blocks changed evidence or a further recovery before deploy. Targeted formatting/analyzer, Python/Bash syntax, scoped diff, and the full fake staging/source transaction contract pass. | The one manual-send allowance remains unspent, but the separately single TC-398-11 transaction authorization has been consumed. Phase cursor `TC-398-12-replacement-transaction-authority-pending`; review grounding is `query_id=8233820b4e754d41`, `evidence_digest=19538d4b446a48de`. Do not invoke the helper, deploy the candidate relay, claim, or ask the user to send under the current amendment. | Obtain explicit user authorization for exactly one evidence-preserving replacement pre-claim transaction. If granted, add a reviewed normative amendment binding the four archive hashes above, rerun read-only live guards, invoke `manual-trace` with the four `--prior-manual-preclaim-*` SHA authorities, and again stop at `PLAN398_MANUAL_SEND_READY` before requesting the one manual send. |
| 2026-08-25 16:35 CEST | TC-398-13 evidence-preserving replacement transaction authorized; live preflight next | explicit user authorization; normative recovery amendment; parser/archive counterexample closure | The user explicitly authorized the precisely bounded replacement transaction. The normative amendment permits exactly one replacement pre-claim transaction while retaining the original single send allowance and forbids a third attempt. Counterexample review found two gaps before live use: orphan manifest/relay-state evidence was not treated as recovery state, and duplicated trailing settings fields could false-pass. The archive gate now treats any subset of its four sources as evidence requiring complete hash authority and rejects an orphan relay-state before deployment. The parser now accepts only one exact, nonduplicated normalized or raw AppDelegate record with a closed sound enum and rejects duplicate markers/fields and unknown values. The new negative cases, the 3/3 focused authorization selector, targeted format/analyzer, Python/Bash syntax, scoped diff check, and the full fake staging/source transaction contract pass. Combined Graphify affected is `query_id=b222761ef97f46fa`; incremental architecture and TDD overlays are current. No real device, relay, claim, artifact, or send action occurred during recovery implementation/review. | Authorization is limited to Pixel `21071FDF600CSC`, iPhone `00008030-001A6D2801BB802E`, group `Test`, target `TC398Target-trial2`, the four fixed prior-attempt hashes, and one stop-before-send prompt. Phase cursor `TC-398-13-replacement-live-preflight`; code grounding is `query_id=8233820b4e754d41`, `evidence_digest=19538d4b446a48de`. | Rediscover the live USB/DDI matrix and revalidate claim/artifact/failure/staging/lock/live-prior-relay plus all four archive-source hashes. If exact, invoke the one authorized replacement `manual-trace` with the four `--prior-manual-preclaim-*` hashes, stop at `PLAN398_MANUAL_SEND_READY`, and ask the user to send the printed marker exactly once before writing `SENT`. |
| 2026-08-25 16:52 CEST | TC-398-14 replacement preflight stopped on non-private source evidence | live USB/DDI matrix; claim/artifact/failure/staging/lock/live relay guards; four fixed recovery sources; staging helper and transaction contract | USB Pixel `21071FDF600CSC` and iPhone `00008030-001A6D2801BB802E` are live, DDI services are usable, the fixed claim/artifact/archive are absent, the failure and all four authorized content hashes match, the lock is nonblockingly acquirable, no competing helper is running, retained staging/deployment bindings are exact, and the live installed/running relay remains prior SHA-256 `0ae5c7d7926d5e16bd43571f772f94ea4e4118d461878c2e71db0224d698b5ee`. The final counterexample audit found the retained command journal and Pixel log are mode `0644`, contradicting the amendment's private-source precondition; no candidate deploy or helper invocation occurred. The helper now validates all four sources as private before reading any bytes, and a new `0644` negative proves unchanged events, no archive/deploy, unchanged source mode, and exact restoration. Python/Bash syntax, scoped diff, and the full fake staging/source transaction contract pass; Graphify affected is `query_id=82df1de63949406c` and incremental refresh passed. | The authorized replacement transaction and sole send allowance are both unconsumed, but live invocation is fail-closed until the two exact-hash retained sources are made private under separately explicit metadata-repair authority. Phase cursor `TC-398-14-preclaim-source-privacy-authority-pending`; code grounding is `query_id=4e6c463c49ac481b`, `evidence_digest=0c4c55dc37183c4d`. | Obtain explicit authorization to change only `build/plan398/tc398-10-existing-state/plan398_existing_state_trace_command_journal.json` and `build/plan398/tc398-10-existing-state/device_logcat_21071FDF600CSC.log` from mode `0644` to `0600` without changing their bytes. If granted, revalidate their four fixed hashes plus every live guard, then invoke the still-authorized replacement transaction and stop at `PLAN398_MANUAL_SEND_READY`. |
| 2026-08-25 17:13 CEST | TC-398-15 authorized replacement stopped pre-claim; public settings-log correction GREEN | private attempt-01 archive; second live manual-trace transaction; retained command/Pixel logs; same-device launch-console/syslog evidence; `AppDelegate` and existing push project-config owner | The user authorized the exact two-file `0644` to `0600` metadata repair; both bytes retained their fixed hashes. Fresh USB/DDI, claim/artifact/archive, failure, staging, lock, process, retained-product, and live prior-relay guards all passed. The one authorized replacement atomically sealed attempt-01, deployed only the retained instrumented relay, then again timed out after one minute on `existing iOS notification authorization` before `PLAN398_MANUAL_SEND_READY`; no marker was printed and the user sent nothing. The helper restored the prior installed/running relay SHA-256 `0ae5c7d7926d5e16bd43571f772f94ea4e4118d461878c2e71db0224d698b5ee`, preserved manifest SHA-256 `8ea8ddf591d0bc64d38423ba0124ac1248431dbe0444d8f5c8aac2717839137b`, released the lock, and left claim/artifact absent. Attempt-01 is private and binds the original four hashes; the second attempt's current journal is SHA-256 `8b0da6ebd454a5696b4971507485b7f2e3f319eef0cb60fc0e25676c60acf2c3` and Pixel log is `3c6432e0726599d4143ee4858afccc57c452a47058c95f1564ab59fb3074f0b2`. The journal proves fresh iOS relay registration matched before the exact authorization timeout. Same-device launch-console SHA-256 `828db36d18ecb092a4f3cd55c7cfa54221a85ff022c41416834b5c9ecf617b4b` exposes the accepted raw settings tuple, while idevicesyslog SHA-256 `cc33e3a2f132e313c20e0c1b146bd38540e862590768fd969ffdd510d41536dc` exposes Flutter registration but replaces native Runner notices with `<private>`. A causal source test first RED on `NSLog`; `logNotificationSettings` now uses `os_log` with five `%{public}@` fields, the exact focused test passes, Swift parse/typecheck and scoped diff pass, and the incremental architecture/TDD refresh is current. | The replacement transaction is consumed but the sole manual send remains unspent. The strongest causal classification is unified-log privacy redaction before the strict parser, compounded by non-persistence of the exact failed-run iOS bytes; accepting `<private>` or widening the parser is forbidden. A third transaction and any app rebuild/install remain unauthorized. Phase cursor `TC-398-15-public-settings-log-green-third-attempt-authority-pending`; code grounding is compact `query_id=48f2dd7ddcdb477c`, native `query_id=2f17712f9d124379`, `evidence_digest=b826167faf3d3714`. | Stop live work. Obtain a reviewed explicit amendment before changing the second-attempt evidence or invoking anything again. The proposed bounded amendment must preserve and bind attempt-01, make the second current Pixel log private without changing bytes, add a private no-replace attempt-02 archive bound to journal `8b0da6ebd454a5696b4971507485b7f2e3f319eef0cb60fc0e25676c60acf2c3`, Pixel log `3c6432e0726599d4143ee4858afccc57c452a47058c95f1564ab59fb3074f0b2`, trace manifest `65e23da2bffb949f0491fb00ac3de875d56063ef4307fc6f5f78d121ecf7f729`, and restored relay state `b0e1d7d2ac2ebf40c827224b7ac124340f11ef4cad0f6f0d00484e2b9bd32d69`, then permit one normal signed Runner in-place update that preserves the iPhone container and one final stop-before-send manual trace. No new iOS harness may be constructed. |
| 2026-08-25 17:31 CEST | TC-398-16 final same-container manual trace amendment authorized; host safeguards RED next | explicit user authorization; attempt-01/02 evidence; existing staging helper, capture/runner, shell contract, signed Runner and container proof seams | The user explicitly authorized the reviewed bounded amendment. The normative section now preserves attempt-01 and the fixed failure, binds the four exact attempt-02 hashes, permits only the Pixel-log `0644` to `0600` metadata repair plus a complete private atomic no-replace attempt-02 archive, requires exact raw iOS stdout/stderr and a terminal receipt on every final-attempt exit, and separates one ordinary signed Runner in-place install from one final stop-before-send trace. No live mutation occurred while recording authority. | The helper is still hard-coded to attempt-01, failed-run iOS bytes are still memory-only, no per-attempt terminal receipt exists, and no final source/product/signing or pre/post container identity binding exists. Those are implementation REDs, not permission to install or invoke. Phase cursor `TC-398-16-attempt02-syslog-terminal-red`; implementation grounding is `query_id=62f4605a6fab44a1`, `evidence_digest=4397481239c494ea`. | Author focused archive/log-persistence/terminal-receipt REDs in existing owners, implement them without a new harness, run focused GREEN/mutation restoration plus Graphify affected/refresh, and only then perform read-only live guards and bind the one signed product. |
| 2026-08-25 21:33 CEST | direct live-diagnostic fail-closed integration GREEN; read-only live preflight active | existing staging helper, runner/capture/criteria owners, existing shell/criteria tests, Release import guards, and same-container continuity seam | Independent audits found and closed wrapper legacy-fallthrough, automated-live artifact acceptance, missing terminal binding, artifact-root/output link acceptance, and stranded-candidate recovery gaps. Live mode now routes through the existing wrapper, exact-validates dedicated artifact/terminal authority, requires one manual send, uses private no-replace outputs, restores a stranded candidate and stops, and rejects legacy receipts. Python/Bash syntax, targeted Dart analysis, all 108 criteria tests, the full staging/same-container shell contract, scoped diff check, Graphify affected `09c47d951dda4d27`, and incremental refresh pass. Release NotificationService compiled and the two Debug import selectors passed independently. | Live rediscovery pins USB Pixel `21071FDF600CSC` and USB iPhone `00008030-001A6D2801BB802E`; `00008150-001C3C6A3684401C` is Flutter-visible but absent from `idevice_id -l` and is excluded. The continuity proof is explicitly an AFC path/type/birthtime fingerprint, not semantic account identity or a kernel inode proof. No live build, install, relay mutation, trace claim, marker, or send occurred in this phase. Branch context is `query_id=1baeeab9035643b5`, `evidence_digest=02a7ce143737588b`; affected context is `09c47d951dda4d27`. Phase cursor `TC-398-direct-live-preflight`. | Next exact action: finish read-only DDI, retained deployment/candidate/prior hash, lock, fresh-output, installed app/container, and live prior-relay guards; resolve the literal staging-manifest path-only blocker without weakening content CAS; then bind one fresh ordinary signed Release Runner, take two preinstall continuity samples, perform one in-place install, take one postinstall sample, and start the receipt-free `manual-trace --live-diagnostic` transaction. Stop at its single printed marker for the user's one manual send. |
