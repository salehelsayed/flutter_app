# Finish Wave 2 — continuation prompt for GPT-6-Luna

Finish the outstanding Wave 2 implementation and verification in `/Volumes/CrucialX9/flutter_app`. Read `AGENTS.md` first. Do not invoke skills or sub-agents.

## Authorization and outcome

I authorize continuation of Wave 2 and the necessary shared prerequisites. Implement the missing work, run the applicable host and device proofs, reconcile the result into main, and update the existing migration records. Do not stop after a plan, configuration preview, or passing prerequisite checks.

Waves 3–5 remain paused. Their already-integrated code must be preserved, but further scenario implementation is outside this task. Necessary shared registration repairs are allowed. Do not commit, push, publish, retire original routes, or run whole-migration release closure.

Work autonomously through routine reversible setup and implementation problems. Ask only for genuinely missing information, access, authorization, or intent. A missing optional local filename, an unexecuted check, or an available but uninspected configuration is not an established external blocker.

## Preservation requirements

- Preserve all local edits, staged changes, untracked files, worktrees, evidence and first-attempt failures. Do not reset, bulk-overwrite, delete worktrees, or stop another owner's processes.
- Keep original tests and harnesses unchanged except the exact previously approved DTR-18 fingerprint updates, notification-readiness patch, and Go-wrapper candidate-binding/exit-status patch. Carry those approvals forward without asking again. They do not authorize further original-file edits or new expected-hash changes.
- Preserve the already-integrated discovery/runtime-root registrations and Git-path repair. Inspect their current source rather than blindly applying historical patches.
- Add replacements and causal tests alongside originals. Do not delete, disable, exclude, redirect, weaken or change original assertions or deadlines.
- If another protected original-file change is necessary, prepare and separately verify the exact proposal before asking for that specific approval. Continue independent authorized work while waiting.
- Bind replacement journeys to production-created services. Do not construct a replacement service graph or synthesize successful observations.

## First: reconcile the current state

Follow `AGENTS.md` document-memory rules. Use focused queries before broad document searches; read the named plan with the required primary-read marker. Do not invoke an execution skill or create session-breakdown files.

Read these sources with their appropriate scope:

- `docs/testing/production-bootstrap-migration-plan.md`
- Wave 2 and checkpoint sections of `docs/testing/production-bootstrap-migration-crosswalk.md`
- Relevant setup, recovery and Wave 2 entries in `docs/testing/TESTING.md`
- `tool/testing/selection.json`
- `tool/sims/critical_features.json`
- `.codex-test-logs/production-bootstrap-migration-20260928/wave2-review-001/review.json`

Record current HEAD, local changes, relevant fingerprints, approved original-file hashes, and campaign/device ownership. Verify the baseline used for every command; do not assume the historical SHA is still HEAD.

Use current main as the implementation baseline. Historical candidate worktrees and receipts provide provenance, not a license to overwrite main. If concurrent work requires an isolated candidate, preserve the complete relevant local inputs and reconcile your changes back into main before the final report. Acceptance evidence must identify the exact tested source/configuration; mixed-candidate passes cannot certify closure.

## Priority 1: resolve setup using the configuration that already exists

The previous continuation stopped because `tool/testing/config.local.json` was absent. A subsequent review established that the wrapper accepts an explicit `--device-config`; that particular filename is not required.

Existing configuration:

`.codex-test-logs/production-bootstrap-migration-20260927/routing-catalog-cached-device-config.json`

The review used that file in a fresh explicit-base/local preview. These four campaigns had no reported blocked prerequisites:

- `production-notification-open`
- `production-notification-sound`
- `production-routing`
- `production-private-media`

The exact preview invocation and result are retained in:

- `.codex-test-logs/production-bootstrap-migration-20260928/wave2-review-001/preview-invocation.json`
- `.codex-test-logs/production-bootstrap-migration-20260928/wave2-review-001/preview/plan.json`

Inspect the configuration, fixture reference, cleanup history and declared isolation. Rediscover available devices and verify current ownership before using it. The previously recorded pair was USB Android `21071FDF600CSC` and `emulator-5556`; these are historical observations, not current reservations.

Reuse that configuration if it remains valid. If adjustment is needed, create a fresh ignored configuration with only verified target/fixture changes and retain the old file. Do not manufacture an isolation attestation or blindly reuse stale devices or accounts.

Run the wrapper's actual campaign setup checks with the verified configuration. Preview readiness alone does not establish live provider readiness, scenario success or cleanup. Diagnose and repair known reversible setup failures. Do not repeat the disproven claim that no configuration exists.

## Priority 2: finish the provider path and its causal tests

The mixed sender/receiver implementation was integrated unfinished. The review found no dedicated causal tests for that new path. Existing generic journey/build contracts do not establish its full behavior.

Start at:

- `integration_test/support/production_android_artifact.dart`
- Production Android journey support under `integration_test/support/production_*`
- `tool/sims/build_orchestrator.dart`
- `tool/sims/executor.dart`
- `lib/debug/production_journeys/production_journey_controller.dart`
- Relevant build profiles, campaign metadata and new host tests

Preserve the decided topology:

- Sender: `android.e2e.main`, disposable package `com.mknoon.sims.connectivity`.
- Emulator receiver: additive `android.production_fcm.journey`, package `com.mknoon.app`.

The user already specified the production Firebase configuration in the codebase. It configures `com.mknoon.app`. Do not ask for a separate disposable-package Firebase client or relabel the production client. Preserve the original provider profile and ordinary production activation rules. Do not replace the physical sender's production app.

Add meaningful causal tests, demonstrate the intended failure for negative controls, and repair the implementation as necessary. Cover:

- Correct per-peer profile, package, input digest and artifact digest binding.
- Missing, stale, swapped, foreign and ambient artifact rejection.
- No hidden child builds or unchecked artifact fallback.
- Correct per-peer install, lifecycle, notification and cleanup operations.
- Both state guards captured before mutation; cleanup of every owned peer even if an earlier cleanup operation fails.
- Profile/role/run-ID/nonce restrictions and inactive controls during ordinary production startup.

Then establish actual Firebase registration and background delivery on the verified emulator fixture. Token availability is not delivery proof. Redact credentials and sensitive provider data from receipts.

## Priority 3: complete the actual Wave 2 campaigns

Execute one bounded slice at a time. Make readiness dependencies explicit and use small causal probes before repeating a failed long campaign.

### Notification opening and payload persistence

Complete the original cold/warm, foreground/background, same-peer/other-chat, unread, route-count and payload-identity assertions using production navigation, lifecycle and notification handling.

A cold tap must prove actual initial-payload processing from the native notification. A fresh process or new invocation acknowledgement is insufficient. Preserve native/headless payload proofs without making them depend on a previous foreground launch. Close the additive production lifecycle/persistence obligations in the assertion crosswalk.

### Notification sound

Complete S1–S16 and S15's post-clear control. Preserve upstream versus effective silence, exact content/notification identities, encrypted descriptor assertions, stable IDs, suppression windows and native disposition checks.

S14 requires the first-card observation before its update. Resolve S16's real fixture/provider proof. Keep internal decisions, OS card/channel behavior and required audible-device evidence distinct; do not substitute one for another.

### Routing

Complete all 27 ordered cases with their intermediate and terminal receipts. The prior S14 failure requested `relay fallback` but stored `relay Fallback`. The additive flow already has keyboard dismissal and case-sensitive composer/bubble checks. Verify that fix before adding another.

Preserve exact stored-text assertions and the original three-minute deadline. IME interference remains a hypothesis until established causally. A successful input probe does not satisfy the full routing campaign.

### Private media

Reconcile every original assertion with a production-entrypoint journey or an appropriate retained component/native owner. Verify required projection, open/close, committed SQL transitions, exact bytes and file ownership, attachment cleanup, privacy, cold persistence and consumed refusal.

The eleven-stage local journey has prior candidate evidence; it is not a current-source pass. Preserve the separate crypto, policy and native assertions. Do not invent additional remote-transfer or account-wide obligations beyond the original plan and tests.

## Execution and validation rules

- Use Appium MCP for live UI exploration and diagnosis, and existing Maestro flows for repeatable journeys. Diagnose a broken MCP connection rather than silently replacing it with a new generic UI harness.
- Use native/protocol adapters only for their documented assertion gaps. Retain concrete driver reasons in executable metadata.
- Discover the live matrix and pin every device command. Default to a connected Android phone plus an available emulator. Use iOS only for actual iOS-specific or explicit parity obligations.
- Unavailable hardware is `N/A (target unavailable by project policy)`, not a required blocker. Missing access or fixtures on an available target must be diagnosed precisely.
- Respect leases and external owners. End your Appium session before handing the device to a campaign. Restore only state owned by your run.
- Prepare all peer artifacts before timed scenarios. Reuse verified compatible builds; meaningful package/provider/configuration differences require their own artifacts.
- Preserve first-attempt failures. Review cleanup after a failed device run, repair the cause, and use a fresh invocation/output directory. Do not automatically retry device campaigns or relax assertions.
- Run `python3 scripts/mknoon_checks.py validate`, then preview and execute focused affected selections with a verified explicit `--base` and `--local`. Supply `--device-config` for device prerequisites/execution.
- Use the SDK matching package configuration. The verified historical SDK was Flutter 3.47.2/Dart 3.13.2; verify it at execution time.
- Run focused causal tests, original-preservation sentinels and affected curated gates per slice. Once the Wave 2 dependency batch is complete, run the required wave-boundary `host-all` gate. Do not launch a full host sweep after every edit or the whole-migration canonical full run.
- Record cold builds, warm rebuilds/cache hits, setup time, scenario time, per-case receipts and cleanup separately. Verify reuse on unchanged compatible identities and invalidation on meaningful changes.

## Interpret wrapper status correctly

The earlier resumption ran eight of 149 selected checks and left 141 unrun. Its report also listed 604 unmapped local paths. Those are historical counts to reconcile, not 604 demonstrated implementation bugs.

Distinguish:

1. Actual failing assertions.
2. Verified setup/access blockers.
3. Required checks intentionally omitted from a diagnostic subset.
4. Unmapped local-change inventory gaps.

Account for Wave 2 and shared-dependency mappings without silently excluding original coverage. Do not expand this task into implementing unrelated later waves merely to make a broad dirty-tree report green. Run the checks required for Wave 2, report other outstanding obligations accurately, and keep overall migration closure separate.

An example of an invalid stopping reason is: “config.local.json is absent, so device work cannot proceed,” without inspecting and validating the known `--device-config` file.

An example of honest partial evidence is: “Routing host criteria pass; S14 failed on candidate X and the full 27-case run remains incomplete.”

## Completion and final report

Update the existing plan, crosswalk and `TESTING.md` with verified results. Correct the premature missing-configuration diagnosis with provenance. Keep historical failures and their cleanup records. Do not create session diaries or duplicate executable inventories.

Wave 2 is complete only when its original assertions and required available-target variants are accounted for, implementations and causal controls are tested, campaigns have exact passing receipts and verified cleanup, build-reuse requirements are demonstrated, applicable host gates pass, and preservation is audited on the reconciled source.

If a genuine external blocker remains after authorized recovery, continue independent work and report the exact missing dependency, attempts made, evidence, and minimal user action required. Do not call Wave 2 complete or stop merely because the easy host checks pass.

Give concise progress updates. End with:

1. Verdict: `WAVE 2 COMPLETE` or `WAVE 2 INCOMPLETE`.
2. What changed in main and why.
3. Acceptance matrix with exact source/configuration/artifact and receipt paths.
4. Passing, failing, blocked and unrun checks, with their distinct causes.
5. Build/cache accounting and cleanup results.
6. Original-file preservation audit and any outstanding approval.
7. Remaining work; Waves 3–5 stay paused.

Stop after that report and wait for further instruction.

## Historical evidence anchors

- Plan: `docs/testing/production-bootstrap-migration-plan.md`.
- Earlier handoff: `docs/testing/production-bootstrap-wave-2-luna-prompt.md`; this continuation incorporates the subsequent review findings.
- Original integration: `.codex-test-logs/production-bootstrap-migration-20260927/integration-checkpoint-001/`.
- Prerequisite work: `.codex-test-logs/production-bootstrap-migration-20260928/wave2-resumption-001/`.
- Independent review: `.codex-test-logs/production-bootstrap-migration-20260928/wave2-review-001/`.
- Historical verified comparison base: `fbe1ae45f07e24e523cc6b63a0f8eb67fab42aab`.
- HEAD observed during the review's final host checks: `06d5ab5704cf0106e730f0dab17b0abfd645fe7c`.
- Review source fingerprint: `e6130e3970c8ed93590cc5f15ea08a684d654467523dced88dc8ebc420861572`.
- The review freshly passed metadata validation, bootstrap 21/21 and debug-composition boundaries 121/121, without a source-change gap. It audited the earlier eight passing host checks and found 65 migration implementation/support/test files unchanged from the unfinished integration checkpoint. It launched no device campaign.

Reverify historical identities and availability; do not assume they are current. Begin with the current baseline and configuration, then finish the provider tests and actual Wave 2 proofs.
