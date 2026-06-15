Status: evidence-gated

# MIG-006 Plan: Group device identity, retained keys, and push-preview continuity

Source doc: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`
Breakdown artifact: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`
Session id: `MIG-006`
Session title: Group device identity, retained keys, and push-preview continuity

## Planning Progress

- 2026-06-07 01:38:00 CEST - Arbiter completed. Files inspected since last update: full MIG-006 draft, reviewer simulator-gate decision, explicit checklist ledger, source proposal residuals, and gate strategy. Decision/blocker: no structural blocker remains; plan is execution-ready with a group reliability simulator closure gate because this session touches group continuity and notification-preview secrets. Next action: execute only MIG-006 and stop before transfer, cutover, runtime migrated-out gates, pending-work ownership, UI, or final acceptance.
- 2026-06-07 01:38:00 CEST - Reviewer completed; Arbiter started. Files inspected since last update: drafted MIG-006 scope, closure bar, red tests, implementation steps, exact gates, group/NSE simulator rule, and source checklist coverage. Decision/blocker: plan is sufficient after requiring a group reliability simulator gate and explicitly choosing "preserve existing moved-account group device binding" as the MIG-006 host-side device policy. Next action: arbitrate accepted differences and final status.
- 2026-06-07 01:38:00 CEST - Planner completed; Reviewer started. Files inspected since last update: draft plan sections and evidence ledger. Decision/blocker: draft narrows implementation to account-migration group manifest/validation for retained group keys, pending drafts, shared mirrors, device rosters, sender metadata, and push-preview readiness. Next action: review for missing simulator/NSE proof, stale group-key assumptions, and scope drift into transfer/cutover/UI.
- 2026-06-07 01:32:00 CEST - Evidence Collector completed; Planner started. Files inspected since last update: `GroupKeyInfo`, group key retention policy, `GroupMember` device identities, sender-device binding, `GroupRepositoryImpl` key hydration/shared mirror/pruning/pending-draft behavior, `group_keys_db_helpers`, `GroupMessage`, group sync receipt/logical delivery migrations, `MigrationSecureStorageRegistry`, `MigrationSecureStorageReferenceCollector`, `MigrationSecureStorageStaging`, `push_decrypt_preview.dart`, `NotificationPreviewResolver.swift`, `NotificationPreviewResolverTests.swift`, and current group/push/account-migration tests. Decision/blocker: no existing account-migration group manifest/validator exists; current group repositories provide enough host-testable seams to plan one. Next action: draft scope, coverage ledger, tests, simulator gate, and stop rule.
- 2026-06-07 01:24:00 CEST - Evidence Collector started. Files inspected since last update: reusable breakdown row for MIG-006, source proposal group/NSE requirements, graphify queries for group migration/push preview context, and broad `rg` results for group keys, device IDs, shared mirrors, and notification preview. Decision/blocker: graphify returned weak field-level matches only, so targeted source/test evidence will drive the plan. Next action: inspect group key retention, group member device models, group key DB helpers, secure-storage migration registry, push preview resolver, NSE Swift resolver, and current group/push tests.

## Execution Evidence

- 2026-06-07 13:07:13 CEST - Command 17 (`ge005`) exited 255 after all three role harnesses reported `All tests passed`, because the orchestrator criteria still required Alice's 20 removed-window sends to have durable-recipient proof. Run id `1780829355033`; logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge005_gICK8l`. Triage evidence: `alice_sent_aliceGe005Removed01.json` was `deliveryMode: live_only`, `topicPeers: 1`, `actualTopicPeerProof: true`, `inboxStored: false`, and Bob received the message once while Charlie had zero removed-window plaintext. Classification: stale harness/criteria expectation, not product failure or device setup. Next action: patch GE-005 proof/criteria to accept durable or live-topic proof for the one-remaining-recipient removed window, add focused criteria coverage, rerun command 17, then resume at command 18 if it passes.
- 2026-06-07 13:09:10 CEST - GE-005 stale proof expectation was patched narrowly. `integration_test/group_multi_party_device_real_harness.dart` now records `actualLiveTopicPeerProof` for GE-005 live-topic sends; `integration_test/scripts/group_multi_party_device_criteria.dart` accepts durable or live-topic proof for Alice's removed-window send to Bob and Bob's re-add send to Alice/Charlie, with the live-topic minimum derived from expected recipient count; `test/integration/group_multi_party_device_criteria_test.dart` covers GE-005 live-only removed-window acceptance and no-proof rejection. Focused evidence passed: `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name GE-005` (`+4`). Next action: rerun command 17 with `run_with_devices.sh group --only 17`. MIG-006 remains evidence-gated.
- 2026-06-07 13:10:33 CEST - Focused command-17 rerun started with `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 17`. The helper started GE-005 with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge005_ZdFabX`, run id `1780830601406`. MIG-006 remains evidence-gated while this rerun is in progress.
- 2026-06-07 13:20:07 CEST - Focused command-17 rerun remains in progress under run id `1780830601406` and shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge005_ZdFabX`. Live output reached GE-005 cycle 10 of 20 and is waiting through the expected 31s key-grace retry window. No pass/fail verdict has been emitted yet; MIG-006 remains evidence-gated until this rerun and commands 18-123 complete.
- 2026-06-07 13:27:18 CEST - Focused command-17 rerun passed: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 17` completed with `[ORCH] ge005 proof passed: ge005 verdicts valid for alice, bob, charlie`, `PASS: #17 integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge005`, and `PASS: reliability simulations completed for scope: group`; logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge005_ZdFabX`, run id `1780830601406`. Remaining group simulator resume is now running with `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --start-at 18`; device resolution succeeded and reliability discovery is underway. MIG-006 remains evidence-gated while commands 18-123 are still running.
- 2026-06-07 13:28:44 CEST - Remaining group simulator resume expanded the command plan from #18 through #123 and started command 18 (`ge006`). Active run artifacts are under `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge006_XL4MOr`, run id `1780831632237`. MIG-006 remains evidence-gated while command 18 is in progress.
- 2026-06-07 13:37:25 CEST - Command 18 (`ge006`) exited 255. Run id `1780831632237`; logs/artifacts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge006_XL4MOr`. Failure symptom: Charlie timed out waiting for `aliceGe006PostReadd`, while Bob's post-readd durable message reached Charlie. Triage evidence: Alice's `gmp_1780831632237_alice_sent_aliceGe006PostReadd.json` had `deliveryMode: live_only`, `recipientPeerIds: []`, `actualDurablePayloadProof: false`, `topicPeers: 1`, and `expectedRecipientCount: 0`; Bob's `bobGe006PostReadd` had durable recipients including Alice and Charlie and Charlie received it. Classification: harness setup bug, not product delivery failure or simulator setup; GE-006 intentionally keeps Charlie offline until after the post-readd sends, but Alice's creator-side invite-delivery repo lacked joined evidence for the direct fixture invitees, causing the ordinary send recipient filter to exclude Bob/Charlie from durable replay. Fix: `integration_test/group_multi_party_device_real_harness.dart` now marks Bob and Charlie joined on Alice's direct fixture invite repo before the GE-006 removal/re-add sequence, and `integration_test/scripts/group_multi_party_device_criteria.dart` now verifies Alice's `aliceGe006PostReadd` sent record has actual durable payload proof with Bob+Charlie recipients. Focused evidence passed: `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name GE-006` (`+4`). Next action: rerun simulator command 18 only, then resume at command 19 if it passes.
- 2026-06-07 13:38:43 CEST - Focused command-18 rerun started with `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 18`. The helper started GE-006 with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge006_dnPqTB`, run id `1780832323589`. MIG-006 remains evidence-gated while this rerun is in progress.
- 2026-06-07 13:45:48 CEST - Focused command-18 rerun passed after the GE-006 fixture-joined-state fix: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 18` completed with `[ORCH] ge006 proof passed: ge006 verdicts valid for alice, bob, charlie`, `PASS: #18 integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge006`, and `PASS: reliability simulations completed for scope: group`; logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge006_dnPqTB`, run id `1780832323589`. Proof tightened as intended: Alice's `aliceGe006PostReadd` send used durable inbox coverage for Bob+Charlie, and Charlie drained the offline inbox after relaunch before sending `charlieGe006PostCatchUp`. Next action: resume the remaining group simulator at command 19. MIG-006 remains evidence-gated until commands 19-123 and final verification pass.
- 2026-06-07 13:47:13 CEST - Remaining group simulator resume started with `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --start-at 19`. The helper resolved devices, expanded commands #19-#123, and started command 19 (`ge007`) with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge007_wdUufT`, run id `1780832833394`. MIG-006 remains evidence-gated while commands 19-123 are running.
- 2026-06-07 13:57:40 CEST - Command 19 (`ge007`) exited 255. Run id `1780832833394`; logs/artifacts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge007_wdUufT`. Failure symptom: Bob timed out waiting for `aliceGe007RemovedWindow`; Alice then timed out waiting for `bob_sent_bobGe007PostCatchUp.json`, and Charlie timed out waiting for Bob's `bob_received_charlieGe007PostReadd.json` signal. Triage evidence: Alice's `aliceGe007RemovedWindow` and `aliceGe007PostReadd` sent records both had `recipientPeerIds: []`, `actualDurablePayloadProof: false`, `expectedRecipientCount: 0`, and `deliveryMode: live_only`, while Bob was intentionally offline during the mutation window. Classification: harness setup bug, not device setup or product delivery failure; GE-007 has the same direct-fixture joined-state precondition as GE-006, but Alice had not marked Bob/Charlie joined in her invite-delivery repo before Bob went offline. Fix: `integration_test/group_multi_party_device_real_harness.dart` now marks Bob and Charlie joined in `_runGe007Alice` before the offline mutation window, and `integration_test/scripts/group_multi_party_device_criteria.dart` now requires Alice's two GE-007 offline-observer sends to have actual durable payload proof including Bob. Focused evidence passed: `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name GE-007` (`+4`). Next action: rerun simulator command 19 only, then resume at command 20 if it passes. MIG-006 remains evidence-gated.
- 2026-06-07 13:58:55 CEST - Focused command-19 rerun started with `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 19`. The helper started GE-007 with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge007_GmRqit`, run id `1780833535285`. MIG-006 remains evidence-gated while this rerun is in progress.
- 2026-06-07 14:04:20 CEST - Focused command-19 rerun passed after the GE-007 fixture-joined-state fix: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 19` completed with `[ORCH] ge007 proof passed: ge007 verdicts valid for alice, bob, charlie`, `PASS: #19 integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge007`, and `PASS: reliability simulations completed for scope: group`; logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge007_GmRqit`, run id `1780833535285`. Proof tightened as intended: Alice's GE-007 removed-window and post-readd sends used durable Bob replay coverage, Bob drained the offline inbox on relaunch, and Bob's post-catch-up send completed. Next action: resume the remaining group simulator at command 20. MIG-006 remains evidence-gated until commands 20-123 and final verification pass.
- 2026-06-07 14:06:05 CEST - Remaining group simulator resume started with `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --start-at 20`. The helper resolved devices, expanded commands #20-#123, and started command 20 (`ge008`) with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge008_SvhNJb`, run id `1780833935526`. MIG-006 remains evidence-gated while commands 20-123 are running.
- 2026-06-07 14:12:28 CEST - Command 20 (`ge008`) exited 255 after Alice, Bob, and Charlie all reported `All tests passed`. Run id `1780833935526`; logs/artifacts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge008_SvhNJb`. Failure symptom: criteria rejected Alice's `aliceGe008Pre*`, `aliceGe008Removed*`, and `aliceGe008Post*` sent records for missing `recipientPeerIds`/durable proof. Triage evidence: Alice's sent records were successful live-only publishes with `actualTopicPeerProof: true`; pre/post sends had `topicPeers: 2`, removed-window sends had `topicPeers: 1`, Bob/Charlie received the expected eligible messages, and Charlie's stale removed-window sends were rejected. Classification: stale harness/criteria expectation, not product delivery failure or device setup. Fix: `integration_test/scripts/group_multi_party_device_criteria.dart` now uses the existing durable-or-live-topic recipient proof helper for GE-008 sent proof, preserving exact durable recipient checks when durable proof exists and requiring topic-peer coverage for live-only sends; `test/integration/group_multi_party_device_criteria_test.dart` covers GE-008 Alice live-topic acceptance and insufficient-topic-peer rejection. Focused evidence passed: `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name GE-008` (`+5`). Next action: rerun simulator command 20 only, then resume at command 21 if it passes. MIG-006 remains evidence-gated.
- 2026-06-07 14:13:57 CEST - Focused command-20 rerun started with `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 20`. The helper started GE-008 with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge008_lsHCBs`, run id `1780834411082`. MIG-006 remains evidence-gated while this rerun is in progress.
- 2026-06-07 14:17:42 CEST - Focused command-20 rerun passed after the GE-008 live-topic criteria fix: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 20` completed with `[ORCH] ge008 proof passed: ge008 verdicts valid for alice, bob, charlie`, `PASS: #20 integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge008`, and `PASS: reliability simulations completed for scope: group`; logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge008_lsHCBs`, run id `1780834411082`. Next action: resume the remaining group simulator at command 21. MIG-006 remains evidence-gated until commands 21-123 and final verification pass.
- 2026-06-07 14:18:49 CEST - Remaining group simulator resume started with `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --start-at 21`. The helper resolved simulator devices, expanded commands #21-#123, and started command 21 (`ge009`) with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge009_vDPuxr`, run id `1780834729539`. MIG-006 remains evidence-gated while commands 21-123 are running.
- 2026-06-07 14:26:20 CEST - Command 21 (`ge009`) exited 255 under run id `1780834729539`; logs/artifacts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge009_vDPuxr`. Failure symptom: Charlie timed out waiting for `aliceGe009PostReadd`; Alice timed out waiting for Charlie's `charlie_received_aliceGe009PostReadd.json`; Bob timed out waiting for Charlie's `charlie_received_bobGe009PostReadd.json`. Triage evidence: Alice's `aliceGe009PostReadd` sent record was live-only with `recipientPeerIds: []`, `actualDurablePayloadProof: false`, `expectedRecipientCount: 0`, `inboxStored: false`; Bob's `bobGe009PostReadd` did include durable recipients for Alice+Charlie and Charlie persisted it by replay, but Charlie blocked on Alice's missing replay before writing Bob's signal. Classification: harness setup bug, not device setup or product delivery failure; GE-009 Alice had not marked direct fixture invitees joined in the creator-side invite-delivery repo, so durable-recipient calculation excluded Bob/Charlie before Alice's post-readd send. Fix in progress: mark Bob and Charlie joined in `_runGe009Alice`, keep GE-009 criteria's durable-recipient requirement, add focused negative criteria coverage, then rerun command 21 only before resuming at command 22. MIG-006 remains evidence-gated.
- 2026-06-07 14:31:01 CEST - Focused GE-009 criteria coverage passed after the harness setup patch: `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name GE-009` completed with `+4`, including the new rejection for Alice's post-readd send missing durable Charlie proof. Focused command-21 rerun started with `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 21`; GE-009 run id `1780835480872`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge009_0UYCww`. MIG-006 remains evidence-gated while command 21 is in progress.
- 2026-06-07 14:35:10 CEST - Focused command-21 rerun passed after the GE-009 direct-fixture joined-state fix: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 21` completed with `[ORCH] ge009 proof passed: ge009 verdicts valid for alice, bob, charlie`, `PASS: #21 integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge009`, and `PASS: reliability simulations completed for scope: group`; logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge009_0UYCww`, run id `1780835480872`. Next action: resume the remaining group simulator at command 22. MIG-006 remains evidence-gated until commands 22-123 and final verification pass.
- 2026-06-07 14:36:33 CEST - Remaining group simulator resume started with `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --start-at 22`. The helper resolved simulator devices, expanded commands #22-#123, and started command 22 (`ge010`) with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge010_QlLkLv`, run id `1780835793387`. MIG-006 remains evidence-gated while commands 22-123 are running.
- 2026-06-07 14:45:32 CEST - Command 22 (`ge010`) exited 255 under run id `1780835793387`; logs/artifacts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge010_QlLkLv`. Failure symptom: Alice failed its own assertion with `Bad state: GE-010 Alice send must be zero-peer successNoPeers; outcome=success topicPeers=0`, then Bob and Charlie timed out waiting for `aliceGe010ZeroPeerFallback`. Triage evidence: Alice's sent record was zero-topic-peer but live-only (`recipientPeerIds: []`, `actualDurablePayloadProof: false`, `expectedRecipientCount: 0`, `inboxStored: false`), so there was no durable inbox fallback for receivers to drain after rejoining the live topic. Classification: harness setup bug, not product delivery or device setup; GE-010 uses a direct group fixture but Alice had not marked Bob/Charlie joined in the creator-side invite-delivery repo before computing durable zero-peer recipients. Fix: `_runGe010Alice` now marks Bob and Charlie joined after their join signals and before the zero-peer send, and focused GE-010 criteria coverage now rejects the failed no-durable-inbox shape. Evidence passed: `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name GE-010` (`+4`). Next action: rerun simulator command 22 only, then resume at command 23 if it passes. MIG-006 remains evidence-gated.
- 2026-06-07 14:52:16 CEST - Focused command-22 rerun passed after the GE-010 direct-fixture joined-state fix: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 22` completed with `[ORCH] ge010 proof passed: ge010 verdicts valid for alice, bob, charlie`, `PASS: #22 integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge010`, and `PASS: reliability simulations completed for scope: group`; logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge010_R04PUg`, run id `1780836416047`. Proof tightened as intended: Alice's `aliceGe010ZeroPeerFallback` send reported `outcome: successNoPeers`, `topicPeers: 0`, `recipientPeerIds` for Bob+Charlie, `actualDurablePayloadProof: true`, and `inboxStored: true`. Next action: resume the remaining group simulator at command 23. MIG-006 remains evidence-gated until commands 23-123 and final verification pass.
- 2026-06-07 14:53:50 CEST - Remaining group simulator resume started with `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --start-at 23`. The helper resolved simulator devices, expanded commands #23-#123, and started command 23 (`go001`) with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_go001_4yR21c`, run id `1780836803605`. MIG-006 remains evidence-gated while commands 23-123 are running.
- 2026-06-07 15:01:04 CEST - Command 23 (`go001`) passed inside the remaining simulator resume: `[ORCH] go001 proof passed: go001 verdicts valid for alice, bob, charlie` and `PASS: #23 integration_test/scripts/run_group_multi_party_device_real.dart --scenario go001`; logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_go001_4yR21c`, run id `1780836803605`. The same resumed sweep advanced to command 24 (`go002`) with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_go002_xS63rU`, run id `1780837065960`. MIG-006 remains evidence-gated while commands 24-123 are running.
- 2026-06-07 15:04:52 CEST - Command 24 (`go002`) exited 255 under run id `1780837065960`; logs/artifacts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_go002_xS63rU`. Failure symptom: Alice, Bob, and Charlie all reported `All tests passed`, but criteria rejected Alice's GO-002 sender-status proof because `recipientPeerIds` and `failedInboxRecipientPeerIds` were empty. Triage evidence: Bob and Charlie both received the live publish and later deduped the replay; Alice's send recorded `deliveryMode: live_only`, `topicPeers: 2`, `actualTopicPeerProof: true`, `inboxStoredBeforeRetry: false`, `retryPayloadBeforeRetry: true`, `retryCount: 1`, `inboxStoredAfterRetry: true`, and `actualDurablePayloadProof: true`, but the direct fixture had not marked Bob/Charlie joined in Alice's creator-side invite-delivery repo before durable retry recipients were computed. Classification: harness setup bug, not product delivery failure or device setup. Fix: `_runGo002Alice` now marks Bob and Charlie joined after their join signals before sending, and focused GO-002 criteria coverage now rejects the empty retry-recipient proof shape. Evidence passed: `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name GO-002` (`+3`). Next action: rerun simulator command 24 only, then resume at command 25 if it passes. MIG-006 remains evidence-gated.
- 2026-06-07 15:06:36 CEST - Focused command-24 rerun started with `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 24`. The helper started GO-002 with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_go002_HMxIrj`, run id `1780837569866`. MIG-006 remains evidence-gated while this rerun is in progress.
- 2026-06-07 15:09:44 CEST - Focused command-24 rerun passed after the GO-002 direct-fixture joined-state fix: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 24` completed with `[ORCH] go002 proof passed: go002 verdicts valid for alice, bob, charlie`, `PASS: #24 integration_test/scripts/run_group_multi_party_device_real.dart --scenario go002`, and `PASS: reliability simulations completed for scope: group`; logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_go002_HMxIrj`, run id `1780837569866`. Proof tightened as intended: Alice's `aliceGo002InboxStoreFailure` send now reports Bob+Charlie in `recipientPeerIds` and `failedInboxRecipientPeerIds`, `retryCount: 1`, `inboxStoredAfterRetry: true`, `actualDurablePayloadProof: true`, and `topicPeers: 2`. Next action: resume the remaining group simulator at command 25. MIG-006 remains evidence-gated until commands 25-123 and final verification pass.
- 2026-06-07 15:11:37 CEST - Remaining group simulator resume started with `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --start-at 25`. The helper resolved simulator devices, expanded commands #25-#123, and started command 25 (`go003`) with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_go003_9JBtdk`, run id `1780837862154`. MIG-006 remains evidence-gated while commands 25-123 are running.
- 2026-06-07 15:19:10 CEST - Command 25 (`go003`) exited 255 under run id `1780837862154`; logs/artifacts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_go003_9JBtdk`. Failure symptom: Alice, Bob, and Charlie all reported `All tests passed`, but orchestrator validation rejected Alice's healthy post-stale-reject send with `alice: sent aliceAfterStaleCharlieReject missing recipientPeerIds`. Triage evidence: Charlie's stale post-removal publish was accepted locally and then rejected by Alice/Bob as `non_member`; Alice's later `aliceAfterStaleCharlieReject` send was live-delivered and persisted by Bob, but Alice's sent proof had `recipientPeerIds: []`, `actualDurablePayloadProof: false`, `expectedRecipientCount: 0`, `deliveryMode: live_only`, `topicPeers: 1`, and `inboxStored: false`. Classification: stale criteria expectation, not product delivery failure or simulator setup; this healthy Bob-only send is an all-online live-topic proof after Charlie is removed and does not require durable inbox recipients. Fix: GO-003 now uses durable-or-live recipient proof for `aliceAfterStaleCharlieReject`, while the focused negative test still rejects a sender proof with neither durable nor live-topic evidence. Evidence passed: `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name GO-003` (`+2`). Next action: rerun simulator command 25 only, then resume at command 26 if it passes. MIG-006 remains evidence-gated.
- 2026-06-07 15:31:06 CEST - Focused command-25 rerun passed after the GO-003 durable-or-live criteria fix: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 25` completed with `[ORCH] go003 proof passed: go003 verdicts valid for alice, bob, charlie`, `PASS: #25 integration_test/scripts/run_group_multi_party_device_real.dart --scenario go003`, and `PASS: reliability simulations completed for scope: group`; logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_go003_vwUjKj`, run id `1780838765175`. Next action: resume the remaining group simulator at command 26. MIG-006 remains evidence-gated until commands 26-123 and final verification pass.
- 2026-06-07 15:34:58 CEST - Remaining group simulator resume started with `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --start-at 26`. The helper resolved simulator devices, expanded 98 commands (#26-#123), and started command 26 (`ge011`) with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge011_3PfA5Q`, run id `1780839266983`. MIG-006 remains evidence-gated while commands 26-123 are running.
- 2026-06-07 15:40:56 CEST - Command 26 (`ge011`) exited 255 under run id `1780839266983`; logs/artifacts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge011_3PfA5Q`. Failure symptom: Charlie timed out waiting for `aliceGe011PartialLiveFallback`, and Alice exited before writing a verdict because her sender row was `status=sent` but `inboxStored=false`. Triage evidence: Alice's sent record had `recipientPeerIds: []`, `actualDurablePayloadProof: false`, `expectedRecipientCount: 0`, `deliveryMode: live_only`, `topicPeers: 1`, and `actualTopicPeerProof: true`; Bob received the live copy once, but Charlie's post-rejoin durable inbox drain stayed empty. Classification: harness setup bug, not stale criteria and not device setup; GE-011 intentionally requires durable replay to Charlie after Charlie leaves the live topic, but Alice's direct-fixture invite-delivery repo had not marked Bob/Charlie joined before durable-recipient calculation. Fix: `_runGe011Alice` now marks Bob and Charlie joined after both role join signals and before the partial-live send, preserving the durable-recipient criteria. Focused evidence passed: `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name GE-011` (`+3`). Next action: rerun simulator command 26 only, then resume at command 27 if it passes. MIG-006 remains evidence-gated.
- 2026-06-07 15:47:04 CEST - Focused command-26 rerun passed after the GE-011 direct-fixture joined-state fix: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 26` completed with `[ORCH] ge011 proof passed: ge011 verdicts valid for alice, bob, charlie`, `PASS: #26 integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge011`, and `PASS: reliability simulations completed for scope: group`; logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge011_bjquWa`, run id `1780839728693`. The remaining simulator resume started with `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --start-at 27`; MIG-006 remains evidence-gated until commands 27-123 and final verification pass.
- 2026-06-07 15:52:02 CEST - Command 27 (`ge012`) passed inside the remaining simulator resume: `[ORCH] ge012 proof passed: ge012 verdicts valid for alice, bob, charlie` and `PASS: #27 integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge012`; logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge012_e2BLvc`, run id `1780840009700`. The same sweep advanced to command 28 (`ge013`) with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge013_DWWcoI`, run id `1780840291148`. MIG-006 remains evidence-gated while commands 28-123 are running.
- 2026-06-07 15:56:38 CEST - Command 28 (`ge013`) passed inside the remaining simulator resume: `[ORCH] ge013 proof passed: ge013 verdicts valid for alice, bob, charlie` and `PASS: #28 integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge013`; logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge013_DWWcoI`, run id `1780840291148`. The same sweep advanced to command 29 (`ge014`) with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge014_bVMRLa`, run id `1780840561232`. MIG-006 remains evidence-gated while commands 29-123 are running.
- 2026-06-07 13:02:53 CEST - Command 17 (`ge005`) remained in progress under the same resume run (`1780829355033`, `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge005_gICK8l`). Live output reached GE-005 cycle 17 of 20 and waited through the expected 31s key-grace retry window; no pass/fail verdict had been emitted yet. MIG-006 remained evidence-gated while command 17 and commands 18-123 were still running.
- 2026-06-07 12:49:43 CEST - Remaining group simulator resume is now running with `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --start-at 17`. The helper resolved four-device group simulators and started command 17 (`ge005`) with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge005_gICK8l`, run id `1780829355033`. MIG-006 remains evidence-gated while commands 17-123 are still running.
- 2026-06-07 12:48:10 CEST - Focused command-16 rerun passed after the GE-004 live-topic proof fix: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 16` completed with `[ORCH] ge004 proof passed: ge004 verdicts valid for alice, bob, charlie` and `PASS: #16 integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge004`; logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge004_DwUsZ4`, run id `1780828992673`. Next action: resume the remaining group simulator at command 17. MIG-006 remains evidence-gated until commands 17-123 pass and the required final verification/documentation sweep completes.
- 2026-06-07 12:42:26 CEST - Command 16 (`ge004`) failed during the resumed command 16-123 sweep with exit 255 after Alice/Bob/Charlie all reported `All tests passed`: the orchestrator rejected Alice's `ge004ReaddExchangeProof` because Alice's all-online post-readd send was live-only (`deliveryMode: live_only`, `topicPeers: 2`, `actualTopicPeerProof: true`, `inboxStored: false`) and therefore had no durable `recipientPeerIds`, even though Bob and Charlie both received/persisted it and Bob/Charlie also exchanged post-readd messages. Run id `1780828514946`; logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge004_h4WCiY`. Triage classification: stale harness/criteria expectation. Fix: `integration_test/group_multi_party_device_real_harness.dart` now records `actualLiveTopicPeerProof` for GE-004 re-add exchange proof, and `integration_test/scripts/group_multi_party_device_criteria.dart` accepts durable recipient proof or live topic-peer proof for the all-online GE-004 post-readd send while still rejecting missing delivery evidence. Focused test passed: `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name GE-004` (`+4`). Next action: rerun simulator command 16 only, then resume at command 17 if it passes.
- 2026-06-07 12:35:41 CEST - Command 15 (`ge003`) passed inside the `group --start-at 15` resume: `[ORCH] ge003 proof passed: ge003 verdicts valid for alice, bob, charlie` and `PASS: #15 integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge003`; logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge003_4ar9Lv`, run id `1780828303296`. The sweep advanced to command 16 (`ge004`) with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge004_h4WCiY`, run id `1780828514946`. MIG-006 remains evidence-gated while commands 16-123 are still running.
- 2026-06-07 12:32:09 CEST - Remaining group simulator resume is now running with `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --start-at 15`. The helper resolved simulator devices and started command 15 (`ge003`) with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge003_4ar9Lv`, run id `1780828303296`. MIG-006 remains evidence-gated while commands 15-123 are still running.
- 2026-06-07 12:30:20 CEST - Focused command-14 rerun passed after the GE-002 live-topic proof fix: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 14` completed with `[ORCH] ge002 proof passed: ge002 verdicts valid for alice, bob, charlie` and `PASS: #14 integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge002`; logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge002_ZeHBNl`, run id `1780827876140`. Next action: resume the remaining group simulator at command 15. MIG-006 remains evidence-gated until commands 15-123 pass and the required final verification/documentation sweep completes.
- 2026-06-07 12:23:45 CEST - Command 14 (`ge002`) failed during the resumed command 14-123 sweep with exit 255, not from a role crash: Alice/Bob/Charlie all reported `All tests passed`, but the orchestrator rejected Alice's `ge002RemovalContinuityProof` because `actualDurablePayloadProof` and `everyPostRemovalExcludedCharlie` were false. Run id `1780827310318`; logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge002_T7ajz7`. Triage classification: stale harness/criteria expectation. Evidence: Bob received all 10 post-removal messages, Charlie had `groupPresentAfterRemoval: false` and `postRemovalPlaintextCount: 0`, while Alice's sends were valid live-only remaining-pair deliveries (`deliveryMode: live_only`, `topicPeers: 1`, `inboxStored: false`) without durable inbox payloads. Fix: `integration_test/group_multi_party_device_real_harness.dart` now records `actualLiveTopicPeerProof` and computes removed-member exclusion from durable recipients or live topic-peer proof for GE-002/GE-003; `integration_test/scripts/group_multi_party_device_criteria.dart` accepts durable proof or live topic proof for those remaining-pair scenarios; `test/integration/group_multi_party_device_criteria_test.dart` covers GE-002/GE-003 live-only acceptance and GE-002 missing-proof rejection. Focused tests passed: `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name GE-002` (`+4`) and `flutter test test/integration/group_multi_party_device_criteria_test.dart --plain-name GE-003` (`+3`). Next action: rerun simulator command 14 only, then resume at command 15 if it passes.
- 2026-06-07 12:15:34 CEST - Remaining group simulator resume is now running with `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --start-at 14`. The helper resolved four-device group simulators and started command 14 (`ge002`) with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge002_T7ajz7`, run id `1780827310318`. MIG-006 is still evidence-gated while this command 14-123 sweep is in progress.
- 2026-06-07 12:14:16 CEST - Focused command-13 rerun passed after the harness fix: `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 13` completed with `[ORCH] ge001 proof passed: ge001 verdicts valid for alice, bob, charlie` and `PASS: #13 integration_test/scripts/run_group_multi_party_device_real.dart --scenario ge001`; logs/verdicts: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_ge001_VsAa9A`, run id `1780826975095`. Next action is the remaining group simulator resume from command 14. MIG-006 remains evidence-gated until commands 14-123 pass, followed by the required final verification/documentation sweep.
- 2026-06-07 12:10:08 CEST - Remaining group simulator resume started with `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --start-at 13`. Command 13 (`ge001`) failed before a product-delivery assertion: Alice threw `Bad state: Missing actual group:inboxStore payload for gmp_1780826422992_ge001_aliceGe001Initial_alice` while Bob and Charlie had received and persisted the live message. Classification: harness bug. The narrow fix in `integration_test/group_multi_party_device_real_harness.dart` keeps durable-required paths strict but lets live-only `_sendProofMessage` records carry `recipientPeerIds: []` and `actualDurablePayloadProof: false` instead of throwing. Focused rerun started with `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 13`, run id `1780826975095`. MIG-006 remains evidence-gated pending this rerun and the remaining command 14-123 sweep.
- 2026-06-07 11:48:14 CEST - Follow-up triage fixed the MD-004 command-12 timeout in the group reliability simulator. Root cause: the primary same-account send excluded the sender account peer ID from durable group recipients, while the restored sibling drains durable inbox state under that same account peer ID; live pubsub/topic-peer discovery was not a reliable proof path for this restored-sibling scenario. The fix adds an explicit `includeSenderPeerIdInDurableRecipients` opt-in to `sendGroupMessage`, keeps ordinary production sends excluding the sender account by default, and uses the opt-in only in the MD-004 multi-device harness. Evidence: `flutter test test/features/groups/application/send_group_message_use_case_test.dart` passed with `+144`; `./scripts/run_test_gates.sh groups` passed with `+324`; targeted `"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --only 12` passed with `[ORCH] MD-004 proof completed successfully`; `git diff --check` passed.
- 2026-06-07 10:46:57 CEST - MIG-006 follow-up implementation closed the review gap in the host-testable manifest/validator contract. The manifest now covers `group_pending_key_repairs`, `group_pending_membership_messages`, `group_welcome_key_package_tombstones`, and `group_inbox_cursors`; keeps sync receipt sender/source/timestamp metadata, `logical_delivery_id`, sender transport metadata, and welcome key-package metadata covered; and serializes hashes/metadata instead of raw group key bytes, key-package public material bytes, pending repair replay JSON, or pending membership payload JSON.
- 2026-06-07 02:32:06 CEST - MIG-006 implementation is code-complete for the host-testable manifest and validator contract. Added `migration_group_manifest.dart`, `migration_group_manifest_builder.dart`, and `migration_group_manifest_validator.dart` plus focused builder/validator tests.
- Focused MIG-006 tests passed with `+9`: `flutter test test/features/account_migration/application/migration_group_manifest_builder_test.dart test/features/account_migration/application/migration_group_manifest_validator_test.dart`.
- Affected direct account-migration/group/push bundle passed with `+385`, covering the updated MIG-006 tests plus secure-storage registry/collector/staging, group repository/member/key/listener/send/drain, pending key repair/pending invite repositories, and push preview tests.
- `./scripts/run_test_gates.sh groups` passed with `+324`.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed: host `+105`, `integration_test/loading_states_smoke_test.dart` `+7`, and `integration_test/posts_phase1_fake_test.dart` `+1`. macOS deployment-target/open foreground warnings were non-blocking because the gate exited green.
- Reliability simulator discovery passed after classifying `integration_test/migration_database_sqlcipher_capability_test.dart` as an ignored SQLCipher capability probe outside 1:1/group/intro reliability discovery. The resolved group plan listed 123 commands.
- Full `run_with_devices.sh group` was re-attempted before the MD-004 triage fix and did not pass. Commands 1-11 passed, including the repaired `integration_test/group_recovery_e2e_test.dart` command. Command 12 failed in `integration_test/scripts/run_group_multi_device_real.dart` with exit 255 after the live MD-004 multi-device scenario timed out: sibling timed out waiting for its proof condition, primary timed out waiting for `md004_1780823501807_sibling_send_verified`, and the orchestrator timed out waiting for `md004_1780823501807_cli_publish_ready`.
- Targeted/resumed command evidence now passes through command 28 after the explicit same-account durable-recipient opt-in and GE-001 through GE-013 harness/criteria fixes.
- Result: MIG-006 is still `evidence-gated`, not closed. The host-side group manifest/validator contract is implemented and locally proven, and known command 12-28 blockers are fixed/proven, but release-grade group reliability simulator closure still requires resume through commands 29-123 and the required final verification/documentation sweep.

## real scope

MIG-006 adds the account-migration group manifest and validation layer that later bundle, transfer, import, and cutover sessions consume.

In scope:

- Add group migration manifest models for committed group keys, pending group-key rotation drafts, group member device rosters, sender transport/device metadata, welcome key-package state references, and push-preview readiness.
- Verify committed retained group-key generations by resolved primary secure-store bytes and matching iOS shared-access-group mirror bytes, not by latest-key lookup or DB reference-string presence.
- Verify pending group-key rotation drafts by resolved primary secure-store bytes only; do not require pending drafts in the shared/NSE store under the current storage model.
- Enforce the current eight-generation retained group-key window from `minRetainedGroupKeyGeneration`.
- Capture group member `devices_json` device identities, including `deviceId`, `transportPeerId`, signing public key, ML-KEM public key, key package ID, public material, status, and revocation state.
- Define MIG-006's moved-account group device policy as preserving the existing active group device binding during migration staging. A migrated account must not add a second active group device entry in this session.
- Capture sender metadata and durable group sub-table state needed by later import/cutover sessions, including `group_messages.transport_peer_id`, `group_message_receipts.sender_device_id`, group welcome key-package recipient device fields, pending key repairs, pending membership state, welcome key-package tombstones, group inbox cursors, sync receipt source/timestamp metadata, and `logical_delivery_id` where present.
- Verify push-preview readiness by checking that every committed retained group key has a matching shared mirror named `group_key:<groupId>:<generation>`, which is the key read by the iOS notification service extension.
- Preserve existing normal group messaging, key rotation, retained-key pruning, shared mirror creation, Android push-preview fallback, and iOS NSE preview behavior.

Out of scope:

- No migration transfer, same-WiFi session, chunking, AEAD bundle encryption, or resume protocol.
- No durable cutover, old-phone migrated-out runtime gates, server lease cleanup, push-token lease cleanup, or queue ownership.
- No group roster rebind/revoke mutation at migration commit. Later cutover sessions may add an explicit rebind/revoke flow if preserving the existing device binding is no longer sufficient.
- No UI journey, wake lock, permission copy, or final success screens.
- No Swift/NSE code changes planned. If Swift resolver behavior or keychain access code must change, stop and replan MIG-006 instead of silently expanding scope.

## closure bar

MIG-006 is good enough when host tests and required group simulator evidence prove the migration layer can determine whether group state is safe to include before later sessions claim a migrated account preserves group history and notification-preview decryption.

| Checklist item | Required proof in this session |
| --- | --- |
| Committed retained group keys | Tests prove every retained generation from `minRetainedGroupKeyGeneration(latest)` through latest is represented and validated by resolved primary key bytes. |
| Shared-access-group mirrors | Tests prove every committed retained generation also requires a matching `group_key:<groupId>:<generation>` shared mirror with the same resolved key bytes for iOS NSE previews. |
| Not latest-key-only | Tests prove validation fails when an older retained generation is missing even if the latest generation exists. |
| Eight-generation boundary | Tests prove generation just outside the retention window is not required, while the oldest retained generation is required. |
| Pending rotation drafts | Tests prove pending drafts require primary resolved key bytes but do not require shared mirrors. |
| Group member device roster | Tests prove `devices_json` entries are carried with device ID, transport Peer ID, signing key, ML-KEM/key-package fields, status, and revocation metadata. |
| Moved-account device policy | Tests prove the moved account is accepted with exactly one preserved active device binding and rejected when migration would claim two active group device entries for the moved account. |
| Sender metadata | Tests prove manifest capture for group message transport peer IDs, sync receipt sender device IDs, welcome-package recipient device fields, and logical delivery IDs where rows provide them. |
| Durable group sub-tables | Tests prove pending key repairs, pending membership messages, welcome key-package tombstones, and group inbox cursors are represented without serializing private key bytes, serialized group key material, replay JSON, or payload JSON. |
| Push-preview readiness | Tests prove a group can be marked preview-ready only when retained shared mirrors exist and match primary key bytes; missing or mismatched mirrors fail before success. |
| Existing group behavior | Existing repository/listener/push-preview tests and group gate evidence remain green. |

Because this session touches group continuity and notification-preview secrets, closure includes the group reliability simulator gate. If simulator/device resolution is unavailable, the implementation may be code-complete but MIG-006 must be left `evidence-gated`, not closed.

## source of truth

- Primary product/security contract: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`, especially group device identity, retained group-key generation, pending draft, shared access group, notification-preview, and schema-version-74 rows.
- Session boundary: MIG-006 row in `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`.
- Existing dependencies: MIG-003 secure-storage registry/staging/cleanup and MIG-004 database schema manifest/import staging are closed. MIG-006 consumes those contracts and does not reopen them.
- Current code wins over stale prose. Evidence inspected includes group key retention/model/repository code, group member device identity model, group message/receipt models, group key DB helpers, account-migration secure-storage registry/collector/staging, Android push-preview resolver, iOS `NotificationPreviewResolver.swift`, and current group/push/account-migration tests.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` are the named gate sources. If they disagree, the script wins.
- Graphify was queried first as required, but returned weak field-level matches; targeted code and docs are authoritative where graph context was incomplete.

Dirty-worktree note: planning observed existing modified/untracked files from MIG-001 through MIG-005 plus this plan. Treat them as current rollout work and do not revert them.

## session classification

implementation-ready

The implementation is host-testable with existing model/repository seams. It becomes evidence-gated only if required group reliability simulators are unavailable after implementation, or if execution discovers that Swift/NSE keychain behavior must change to make host validation meaningful.

## exact problem statement

After MIG-005, the migration bundle can verify database, secure-storage, and app-owned file prerequisites, but it still has no group-specific migration manifest. A later import could claim success while missing retained non-latest group keys, missing iOS shared key mirrors needed by notification previews, losing pending group-key rotation drafts, dropping group device roster fields, or creating an ambiguous moved-account device identity.

The user-visible failure would be migrated group history that only decrypts latest-key messages, broken iOS notification previews on the new phone, lost pending group key rotations, or a group roster that treats the moved account as two active devices. Existing group messaging, key rotation, shared mirror pruning, Android push fallback, and iOS NSE preview behavior must stay unchanged.

## files and repos to inspect next

Production files likely to add:

- `lib/features/account_migration/domain/models/migration_group_manifest.dart`
- `lib/features/account_migration/application/migration_group_manifest_builder.dart`
- `lib/features/account_migration/application/migration_group_manifest_validator.dart`

Production files to inspect/update narrowly:

- `lib/features/account_migration/application/migration_secure_storage_reference_collector.dart`
- `lib/features/account_migration/application/migration_secure_storage_registry.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `lib/features/groups/domain/repositories/group_repository.dart`
- `lib/features/groups/domain/models/group_key_info.dart`
- `lib/features/groups/domain/models/group_key_retention_policy.dart`
- `lib/features/groups/domain/models/group_member.dart`
- `lib/features/groups/domain/models/group_message.dart`
- `lib/features/groups/domain/models/group_message_receipt.dart`
- `lib/features/groups/domain/models/group_welcome_key_package.dart`
- `lib/core/database/helpers/group_keys_db_helpers.dart`
- `lib/core/database/helpers/group_sync_receipts_db_helpers.dart`
- `lib/features/push/application/push_decrypt_preview.dart`
- `ios/NotificationService/NotificationPreviewResolver.swift` only as a key-name contract unless execution explicitly replans Swift changes.

Tests and docs:

- New `test/features/account_migration/application/migration_group_manifest_builder_test.dart`
- New `test/features/account_migration/application/migration_group_manifest_validator_test.dart`
- Existing `test/features/account_migration/application/migration_secure_storage_reference_collector_test.dart`
- Existing `test/features/groups/domain/repositories/group_repository_impl_test.dart`
- Existing `test/features/groups/domain/models/group_member_test.dart`
- Existing `test/features/groups/application/group_key_update_listener_test.dart`
- Existing `test/features/groups/application/send_group_message_use_case_test.dart`
- Existing `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- Existing `test/features/push/application/push_decrypt_preview_test.dart`
- Existing `ios/RunnerTests/NotificationPreviewResolverTests.swift` only if Swift/NSE files change after a replan.
- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`
- `Test-Flight-Improv/codebase-test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` only if new tests require explicit classification.

## existing tests covering this area

- `test/features/account_migration/application/migration_secure_storage_reference_collector_test.dart` proves committed group key rows create primary group-key references plus shared group mirrors, while pending drafts create primary references only.
- `test/features/account_migration/application/migration_secure_storage_registry_test.dart` proves the shared group mirror key name is `group_key:<groupId>:<generation>` and is classified critical/migrated.
- `test/features/account_migration/application/migration_secure_storage_staging_test.dart` proves primary/shared staged values must exist before critical promotion.
- `test/features/groups/domain/repositories/group_repository_impl_test.dart` proves committed keys are stored as primary secure references, hydrated before use, mirrored to shared push storage as resolved bytes, pruned outside the eight-generation window, and pending drafts do not become latest keys.
- `test/features/groups/domain/models/group_member_test.dart` proves `devices_json` round-trips active/revoked device identities and preserves device binding fields.
- `test/features/groups/application/group_key_update_listener_test.dart` and `test/features/groups/integration/group_messaging_smoke_test.dart` cover key update, historical key, sender-device, and replay behavior for normal group flows.
- `test/features/push/application/push_decrypt_preview_test.dart` and `ios/RunnerTests/NotificationPreviewResolverTests.swift` prove group push previews decrypt when the expected group key is available.
- MIG-004 schema inventory tests prove schema version 74 includes recent group fields, but they do not verify semantic group migration completeness.

Missing today:

- No account-migration group manifest model or validator exists.
- No migration test proves every retained committed group generation has resolved primary bytes and matching shared mirror bytes.
- No migration test proves pending group-key rotation drafts are primary-only but still critical.
- No migration test proves the full eight-generation retained window at the boundary.
- No migration test proves moved-account group device policy avoids creating a second active device entry.
- No migration test ties group sender metadata and notification-preview readiness into the account migration closure bar.

## regression/tests to add first

Add red tests before production implementation:

- `test/features/account_migration/application/migration_group_manifest_builder_test.dart`
  - Builds representative group rows with committed keys, pending rotation drafts, member `devices_json`, group messages, sync receipts, and welcome key-package rows.
  - Proves manifest output preserves retained key generations, source row identity, device roster fields, sender transport/device metadata, logical delivery IDs, and push-preview key names.
  - Proves the moved account is represented with exactly one preserved active group device binding.
- `test/features/account_migration/application/migration_group_manifest_validator_test.dart`
  - Proves missing primary key bytes fail retained committed generations.
  - Proves missing or mismatched shared mirrors fail committed retained generations.
  - Proves pending rotation drafts require primary bytes but not shared mirrors.
  - Proves the eight-generation boundary: latest 10 requires 3 through 10 and does not require 2.
  - Proves validation fails when the moved account has two active group devices in the same migrated roster.
  - Proves preview readiness is false/failing when any retained shared mirror is absent.

Then run affected existing group and push tests to prove normal behavior remains unchanged.

## step-by-step implementation plan

1. Add the red account-migration group manifest builder/validator tests with plain row fixtures and fake primary/shared secure stores.
2. Add group manifest domain models with deterministic ordering and JSON serialization. Do not include secret key bytes in serialized manifest payloads; store hashes or presence/check metadata only.
3. Add builder inputs as row collections for groups, committed group keys, pending group-key rotation drafts, group members, group messages, group message receipts, welcome key packages/tombstones, pending key repairs, pending membership messages, and sync cursor rows as needed by the tests.
4. Use `minRetainedGroupKeyGeneration(latestGeneration)` to determine required committed generations per group.
5. Resolve committed group key bytes from the primary secure store when `encrypted_key` is a `secure:` reference; accept inline legacy values only as source data to be wrapped/verified by existing repository behavior if tests cover that current path.
6. Verify each committed retained generation has a shared mirror named `group_key:<groupId>:<generation>` with the same resolved bytes. Record only a digest/check result in the manifest.
7. Verify pending rotation drafts through primary resolved bytes and explicitly mark them as not requiring shared mirrors.
8. Capture member device rosters from `devices_json`; validate active/revoked state and required active-device fields.
9. Implement the moved-account group device policy: preserve the current single active group device binding; reject or flag rosters that would claim two active moved-account devices before a later rebind/revoke session exists.
10. Capture sender metadata from group message transport Peer IDs, group message receipt sender device IDs, welcome key-package recipient device fields, pending repair transport metadata, and logical delivery IDs where present.
11. Keep Swift/NSE behavior unchanged. If execution requires changes to `NotificationPreviewResolver.swift` or keychain access, stop and replan because device/NSE acceptance scope changes.
12. Update source proposal and test inventory docs for MIG-006 evidence/residuals. Update gate definitions/script only if completeness-check requires explicit classification.
13. Run direct tests, group/push affected tests, format, diff check, completeness-check, baseline, group gate, group reliability simulator gate, and `graphify update .`.

## risks and edge cases

- Latest-key-only validation can pass while older retained group history remains undecryptable.
- A DB `secure:` reference can exist while the primary secure-store value is missing; validation must resolve bytes.
- A shared mirror can exist but contain stale bytes; migration must compare against the resolved primary bytes.
- Pending drafts are critical for pending key-rotation state but intentionally not mirrored into the shared/NSE store.
- Group IDs may contain punctuation; mirror key construction must match the current NSE key name exactly.
- Device rosters may include revoked devices; only active devices should count for the moved-account duplicate-active policy.
- Legacy members without `devices_json` still exist; do not rewrite normal group behavior, but migration should explicitly classify whether a legacy fallback binding is acceptable or requires later handling.
- Logs, manifest JSON, and docs must not expose group key bytes.

## exact tests and gates to run

Direct new MIG-006 tests:

```bash
flutter test test/features/account_migration/application/migration_group_manifest_builder_test.dart
flutter test test/features/account_migration/application/migration_group_manifest_validator_test.dart
```

Affected direct tests:

```bash
flutter test test/features/account_migration/application/migration_secure_storage_reference_collector_test.dart
flutter test test/features/account_migration/application/migration_secure_storage_registry_test.dart
flutter test test/features/account_migration/application/migration_secure_storage_staging_test.dart
flutter test test/features/groups/domain/repositories/group_repository_impl_test.dart
flutter test test/features/groups/domain/models/group_member_test.dart
flutter test test/features/groups/domain/models/group_key_info_test.dart
flutter test test/features/groups/application/group_key_update_listener_test.dart
flutter test test/features/groups/application/send_group_message_use_case_test.dart
flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
flutter test test/features/push/application/push_decrypt_preview_test.dart
```

Named/host gates:

```bash
dart format lib/features/account_migration test/features/account_migration
git diff --check
./scripts/run_test_gates.sh completeness-check
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh groups
```

Required simulator closure gate:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group
```

Optional only if execution changes push telemetry or runtime notification paths:

```bash
./scripts/run_test_gates.sh runtime-telemetry
```

Do not run Swift/Xcode tests by default because Swift/NSE changes are out of scope. If execution discovers Swift/NSE code must change, stop and replan MIG-006 before changing it.

## known-failure interpretation

- Treat failures in new MIG-006 tests as session-caused unless the red-before-green run already recorded the expected missing-API failure.
- Treat failures in group repository, group member, group key update, send group message, drain offline inbox, or push preview direct tests as session-caused unless a focused pre-change rerun proves the same failure already existed.
- Treat `./scripts/run_test_gates.sh groups` failures as session-caused if they involve key retention, group-device binding, replay, invite, or push-preview regressions touched by MIG-006.
- If the reliability simulator helper cannot resolve the required simulator devices, record the device-resolution blocker and leave MIG-006 evidence-gated rather than closed.
- Existing macOS build warnings, deployment-target warnings, or `Failed to foreground app; open returned 1` are not blockers if the gate exits green, matching prior sessions.

## done criteria

- Group migration manifest models and deterministic serialization exist without exposing key bytes.
- Builder captures committed retained keys, pending drafts, member device rosters, sender metadata, sync receipt metadata, welcome packages/tombstones, pending key repairs, pending membership messages, group inbox cursors, and push-preview mirror key names.
- Validator resolves primary group key bytes for every retained committed generation and pending draft.
- Validator requires matching shared mirror bytes for committed retained generations and never requires shared mirrors for pending drafts.
- Tests prove the eight-generation boundary and reject latest-key-only validation.
- Tests prove the moved-account group device policy preserves exactly one active device binding and rejects duplicate active moved-account devices.
- Tests prove push-preview readiness depends on matching retained shared mirrors.
- Existing normal group and push-preview tests pass.
- Source proposal and test inventory docs are updated for MIG-006 evidence and residuals.
- Required direct tests, `./scripts/run_test_gates.sh groups`, group reliability simulator gate, baseline, completeness-check, diff check, and `graphify update .` pass after implementation edits.

Coverage ledger:

| User-listed MIG-006 requirement | Closure state required |
| --- | --- |
| committed retained group-key generations | Covered by retained key manifest and validator tests |
| shared-access-group mirrors | Covered by shared mirror matching tests |
| pending group-key rotation drafts | Covered as primary-only critical draft tests |
| resolved key bytes, not latest/reference presence | Covered by missing/mismatched primary and shared byte tests |
| full eight-generation retained window | Covered by retention-boundary tests |
| group member device identities | Covered by device roster capture/validation tests |
| preserve or rebind/revoke moved account device | Covered by preserve-existing-single-active-device policy; rebind/revoke mutation remains later accepted difference |
| sender transport/device metadata | Covered by group message, receipt, pending repair, and welcome-package metadata capture tests |
| `group_pending_key_repairs` | Covered by manifest capture, missing pending-key repair validation, malformed-row validation, replay-envelope hashing, and private-material exclusion tests |
| `group_pending_membership_messages` | Covered by manifest capture, malformed-row validation, payload hashing, and private-material exclusion tests |
| `group_welcome_key_package_tombstones` | Covered by manifest capture and malformed-row validation tests |
| `group_inbox_cursors` | Covered by manifest capture, missing cursor validation when receipts exist, and malformed-row validation tests |
| notification-preview continuity | Covered by shared mirror readiness tests and existing push/NSE resolver contracts |
| no normal group behavior regression | Covered by affected direct tests, group gate, and group reliability simulator gate |

## scope guard

Non-goals:

- No transfer protocol, local discovery/session endpoint, bundle encryption, or resumable segment store.
- No final cutover, old-phone migrated-out runtime quieting, rendezvous/push unregister, or active-device server lease cleanup.
- No queue/pending-work ownership beyond pending group-key draft inventory.
- No UI, settings entry point, progress screen, wake lock, or migrated-out screen.
- No Swift/NSE code changes without replanning.
- No broad rewrite of `GroupRepositoryImpl`, group messaging listeners, push registration, or group send/drain flows.

Overengineering signals:

- Adding a new group roster mutation flow inside MIG-006 instead of validating the current preserved-device policy.
- Enumerating arbitrary keychain namespaces instead of using the closed MIG-003 registry/discovered-key model.
- Storing raw group key bytes in manifest JSON or logs.
- Expanding into final imported rendering or multi-device account cutover.

## accepted differences / intentionally out of scope

- MIG-006 preserves the moved account's existing active group device binding as the MVP device policy. Explicit rebind/revoke at cutover remains a later-session option if MIG-008/MIG-009 need it.
- MIG-006 proves shared key mirrors are present and byte-matched for committed retained keys; it does not prove real iOS Keychain lock/reboot/NSE lifecycle on device.
- MIG-006 does not prove the full imported app renders every group history row after transfer/import. MIG-012 owns final device acceptance.
- Pending drafts remain primary-store only. They are not required in the shared/NSE store under the current storage model.

## dependency impact

- MIG-007 depends on the group manifest shape if the transfer bundle includes group key and device-roster sections.
- MIG-008 depends on the moved-account device policy before durable cutover can claim exactly one active device.
- MIG-009 depends on the policy distinction between preserved group device binding and old-phone runtime network shutdown.
- MIG-010 depends on pending group-key draft inventory before pending work ownership can be assigned.
- MIG-011 depends on preview-ready/failure reasons for user-facing migration progress/failure UI.
- MIG-012 depends on MIG-006 evidence but must add final device/simulator proof that migrated groups decrypt, send, replay, and preview notifications on the new phone.

If MIG-006 becomes evidence-gated because simulator devices or NSE/device proof are unavailable, downstream sessions may plan against the manifest contract but should not claim final group/NSE continuity closure.

## docs-to-update contract

After implementation evidence, update only current docs needed for durable project state:

- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`: rows for retained group keys, shared mirrors, pending drafts, device identity policy, sender metadata, notification-preview continuity, and later final-device residuals.
- `Test-Flight-Improv/codebase-test-inventory.md`: new MIG-006 account-migration group tests and any relevant group/push notes.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`: only if completeness-check shows a new file needs explicit classification or if the simulator gate list changes.
- Do not update the session breakdown to `closed` during planning or coding. Closure status belongs to the later closure audit after accepted execution and gate evidence.

## reviewer outcome

Reviewer verdict: sufficient as-is for MIG-006 planning; no structural blocker.

- Mandatory sections: present.
- Checklist coverage: sufficient. Every MIG-006 source requirement maps to a concrete planned test/proof or an accepted later-session difference.
- Simulator gate: required and present because this session touches group continuity and notification-preview secrets.
- Stale assumptions: none found. Current code uses eight-generation retention, primary secure references, shared mirror key names, device rosters in `devices_json`, and NSE group preview key lookup.
- Scope guard: sufficient. Transfer, cutover, runtime migrated-out gates, pending-work ownership, UI, Swift/NSE changes, and final device acceptance are excluded.
- Minimum adjustment needed: none before execution.

## arbiter outcome

Final planning verdict: execution-ready.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact manifest JSON field names are implementation details as long as tests prove deterministic ordering, no raw key bytes, retained generation identity, device roster identity, and preview readiness.
- Exact handling of legacy members without `devices_json` can be an explicit manifest classification as long as tests prove it is not silently treated as a second active moved-account device.

Accepted differences intentionally left unchanged:

- Preserve existing moved-account group device binding in MIG-006; do not implement rebind/revoke yet.
- No Swift/NSE implementation change in MIG-006.
- No transfer, cutover, pending-work ownership, UI, or final device acceptance in MIG-006.
