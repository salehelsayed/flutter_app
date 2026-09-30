Finish Wave 2 of the production-bootstrap migration, including the prerequisites necessary to implement and verify it. Work in /Volumes/CrucialX9/flutter_app.

Read AGENTS.md first. Do not invoke skills or sub-agents.

## Role and authorization

Act as the implementation and verification owner for Wave 2.

I explicitly resume Wave 2 and its necessary shared prerequisites. This supersedes the earlier rollout pause only within that scope. Waves 3–5 remain paused, except minimal shared registration or infrastructure repairs needed to execute Wave 2 checks.

Implement, test, collect evidence, update the existing records, and leave the completed changes reconciled in the main worktree. Continue beyond planning and host-only implementation until the applicable Wave 2 acceptance criteria are met or a genuine external blocker prevents further progress.

Necessary focused host checks, Wave 2 builds/device campaigns, and the required wave-boundary host gate are authorized. Do not commit, push, publish, retire original routes, or start later-wave implementation.

## Preservation and scope rules

1. Preserve all existing local edits, staged changes, candidate worktrees, evidence, and first-attempt failures. Do not reset, bulk-overwrite, stash away another owner’s work, or delete worktrees.

2. Keep every original test and harness unchanged except the exact previously approved patches:
   - DTR-18 expected-fingerprint updates, including the final reconciled three-hash approval.
   - The notification-readiness patch to scripts/run_ios_notification_tap_ui_smoke.sh.
   - The candidate-binding/exit-status patch to docker-ws/alltests_go_test.sh.

   These approvals already apply; do not ask again. They do not authorize additional fingerprint changes or other edits to original tests/harnesses.

3. Add replacement coverage alongside originals. Do not delete, disable, exclude, redirect, weaken, or silently reclassify original coverage. Do not extend deadlines or loosen predicates to obtain a pass.

4. Additive executable metadata repairs are in scope. If a necessary repair would alter a protected original test or harness beyond the approved patches, first prepare the exact patch and verify it separately, then request that specific approval. Continue independent authorized work while awaiting it.

5. Use production-created services. Replacement journeys must not construct their own application graph, repositories, listeners, notification service, or substitute application root.

6. Fix routine reversible setup problems yourself. Ask only for genuinely missing access, information, authorization, or ambiguous intent that cannot be resolved from source and recorded decisions.

## Priority 0: establish the current baseline

Before editing or launching campaigns:

- Identify running processes, campaigns, device leases and ownership. Do not interrupt another owner or control their device.
- Record current HEAD, staged/unstaged/untracked state, relevant file fingerprints, and the exact approved original-file bytes.
- Treat current main as the starting source of truth. Older worktrees and receipts are historical evidence, not replacement sources to copy wholesale.
- Reconcile changes made since the integration checkpoint.
- Use a stable source snapshot for verification. If concurrent edits require an isolated candidate, preserve all current local inputs, record its provenance, and carefully reconcile your changes back into main before the final report.
- Never combine results from different source/configuration identities into one passing candidate.

Follow AGENTS.md document-memory rules. Read the named plan completely, then use focused memory queries and source anchors rather than broad document searches.

Read:

- docs/testing/production-bootstrap-migration-plan.md
- Relevant sections of docs/testing/production-bootstrap-migration-crosswalk.md
- Relevant setup, recovery and Wave 2 entries in docs/testing/TESTING.md
- tool/testing/selection.json
- tool/sims/critical_features.json

Update the existing crosswalk with a compact Wave 2 acceptance matrix:
original assertion/variant → replacement or retained owner → implementation status → required proof → evidence identity → remaining gap.

Do not create a session diary or a second executable inventory.

## Priority 1: repair prerequisites before long campaigns

Reproduce and diagnose the checkpoint’s relevant host failures with small causal checks.

Known unfinished registrations:

- Six runners lack reliability-discovery classification:
  run_production_group_create.dart
  run_production_group_invite_reliability.dart
  run_production_group_reaction.dart
  run_production_group_reaction_toggle.dart
  run_production_group_removed_reaction.dart
  run_production_startup_resume_performance.dart
- The three reaction runners lack runtime-root registrations.

Repair these shared registrations if still necessary for Wave 2 gates. This does not authorize implementing their later-wave scenarios.

The architecture checker also rejected a pre-existing evidence filename ending:
step-035-assertCondition-[0-9]+_items_pending.json

Diagnose that failure while preserving the evidence and the checker’s trust-boundary guarantees. Do not rename/delete evidence, exclude it merely to pass, or weaken original assertions. Establish whether the defect is path handling, invocation, or another cause before changing anything.

Validate metadata, preview the affected selection, and run the focused prerequisite checks with an explicitly verified --base and --local. Use the repository’s actual package-config SDK; the checkpoint used Flutter 3.47.2/Dart 3.13.2.

## Priority 2: finish Wave 2 in small verified slices

A. Provider-enabled notification foundation

Finish and causally test the integrated mixed sender/receiver implementation before another full notification campaign.

The user already chose the production Firebase configuration in the codebase. It configures com.mknoon.app. Do not request a new disposable-package Firebase client or relabel that configuration.

The intended arrangement is:

- Disposable sender: android.e2e.main / com.mknoon.sims.connectivity.
- Emulator receiver: additive android.production_fcm.journey / com.mknoon.app.

Preserve the original provider profile and ordinary production activation rules. Do not replace the physical sender’s production app.

Verify:

- Per-peer package and lifecycle operations.
- Correct profile-specific input/artifact digest binding.
- Rejection of missing, stale, foreign or swapped artifacts.
- No hidden child-build fallback.
- Both peers’ state guards are captured before mutation.
- All owned state is restored even when a peer or cleanup operation fails.
- Real provider readiness and delivery rather than token readiness alone.
- Existing invocation/profile/role/nonce restrictions remain effective.

B. Notification opening and payload persistence

Complete the original cold/warm, foreground/background, same-peer/other-chat, unread, route-count and payload assertions using production startup, navigation, lifecycle and notification handling.

For cold taps, prove actual initial-payload processing after the tap. A fresh process or readiness acknowledgement alone is insufficient.

Complete the additive production lifecycle/payload-persistence coverage. Retain headless/native proofs at their intended boundary; do not make them depend on prior foreground startup.

C. Notification sound

Complete all original S1–S16 cases and S15’s post-clear control.

Preserve requested versus effective silence, exact notification identity/content, descriptor metadata, stable IDs, suppression windows and native disposition checks.

S14 requires the actual first-card observation before its update. Resolve S16’s real fixture/provider proof without synthetic success.

Distinguish internal notification decisions, OS card/channel behavior, and actual audible-device evidence. One does not substitute for another.

D. Routing

Complete all 27 ordered routing cases and intermediate assertions.

The prior S14 failure requested “relay fallback” but observed “relay Fallback”. The additive flow already gained keyboard dismissal and case-sensitive composer/bubble checks. Inspect and test that implementation before adding another fix.

Keep exact stored-text assertions and the original three-minute deadline. IME interference was a hypothesis, not an established cause. Probe success is not a full routing pass.

E. Private media

Reconcile every original private-media assertion with either:

- a production-entrypoint application journey, or
- an explicitly retained component/native owner appropriate to that assertion.

The local production journey has prior candidate evidence for eleven stages. Verify the remaining required projection, open/close, committed SQL transitions, file/attachment cleanup, privacy, cold persistence and refusal behavior.

Do not replace database, crypto, policy or native proof with screenshots. Do not invent broader remote-transfer or account-wide claims beyond the original obligations.

## Campaign and verification discipline

- Use Appium MCP for live exploration, permissions, lifecycle interaction and diagnosis; use existing Maestro flows for repeatable UI journeys.
- Keep native/protocol adapters only for documented assertions those UI tools cannot prove.
- Discover the live device matrix and pin every command to an available target.
- Default to one connected physical Android device plus one available Android emulator for non-iOS-specific two-peer proof.
- Use iOS only for an actual iOS boundary or explicit parity requirement.
- Mark unavailable hardware N/A under project policy; do not fabricate missing hardware requirements.
- Follow wrapper setup checks and recovery guidance before long campaigns.
- End your Appium session before handing a device to a campaign. Preserve other owners’ sessions.
- Prepare all peer artifacts before timed scenarios. Preserve meaningful provider/package/configuration variants.
- Record builds, cache hits, setup time, scenario time, exact receipts and cleanup separately.
- Preserve failures. After a failed campaign, review cleanup and run a small causal probe before a fresh invocation. Do not automatically rerun failed device campaigns.
- Add meaningful causal tests for new behavior and negative controls for identity, readiness, receipt completeness, artifact reuse and cleanup.
- Run focused causal tests, exact preservation sentinels and affected curated checks per slice.
- Run full host-all once at the completed Wave 2 dependency boundary, following AGENTS.md. Do not use it as the default gate after every fix.
- Do not launch the whole-migration canonical full run; that belongs to later closure.

## Completion criteria and reporting

Wave 2 is complete only when:

- Every Wave 2 original assertion and required variant has an implemented replacement or justified retained owner.
- Required available-target scenarios have exact passing receipts and verified cleanup.
- Relevant negative controls fail for the intended reason.
- Compatible runtime changes reuse verified artifacts without hidden builds.
- Applicable host gates and the wave-boundary gate pass on a stable, identified source/configuration.
- Original-test/harness preservation is audited.
- Completed changes are reconciled into main without discarding concurrent work.
- Existing plan, crosswalk and TESTING.md accurately record outcomes and limitations.

If something is blocked, continue independent work and report the precise unresolved dependency. Do not label a partial implementation “Wave 2 complete”.

Use concise progress updates with findings, the next bounded action, and blockers. At the end report:

1. Wave 2 verdict: COMPLETE or INCOMPLETE.
2. Changes implemented and their main-worktree locations.
3. Acceptance matrix with exact evidence identities.
4. Checks/scenarios passed, failed, blocked or unrun.
5. Build/cache counts and cleanup results.
6. Preservation audit and any approvals still required.
7. Remaining work, with Waves 3–5 explicitly still paused.

Example evidence wording:
“Routing: INCOMPLETE — S14 failed on candidate X; later input probes passed, but the complete 27-case campaign has not passed.”
Do not convert that into “Routing passed”.

## Historical context to verify against current source

The integration checkpoint was based on:
fbe1ae45f07e24e523cc6b63a0f8eb67fab42aab

Evidence root:
.codex-test-logs/production-bootstrap-migration-20260927/

Checkpoint:
integration-checkpoint-001/

Useful checkpoint records:

- integration-decisions.json
- preservation-audit.json
- final-checkpoint-audit.json
- bounded-host-results.json
- workflow-failure-review.json
- concurrent-main-changes.json

Both checkpoint host runs reported source changes during execution and invalidated candidate certification. Their passing checks are diagnostic observations only.

Existing implementation anchors:

- lib/debug/production_journeys/
- integration_test/scripts/run_production_*.dart
- integration_test/support/production_journey_peer.dart
- integration_test/support/production_android_artifact.dart
- tool/sims/executor.dart
- tool/sims/critical_features.json
- tool/testing/selection.json
- tool/runtime_roots/runtime_roots.json

Start by reconciling the current baseline, then execute the prerequisites and Wave 2 work. Stop after the Wave 2 report and wait for further instruction.
