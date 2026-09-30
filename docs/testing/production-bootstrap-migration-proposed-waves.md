# Production-bootstrap migration: proposed waves and remaining work

Reference roadmap prepared on 2026-09-29. This summarizes the existing wave order and recommends the next bounded work within it. Saving or reading this file does not authorize execution, resume paused waves, invoke skills, or approve original-test changes.

The [main migration plan](production-bootstrap-migration-plan.md) owns requirements. The [migration crosswalk](production-bootstrap-migration-crosswalk.md) owns assertion correspondence and recorded evidence. [TESTING.md](TESTING.md) owns verified testing and recovery knowledge. Those records and current source take precedence over this dated summary. Executable selection remains in `tool/testing/selection.json` and `tool/sims/critical_features.json`.

## Proposed order

| Wave | Purpose | Recorded position at this reference point | Exit condition |
| --- | --- | --- | --- |
| 0 | Preserve and reconcile the baseline | Baseline, preservation records and crosswalk exist; refresh relevant identities before resuming. | Every discovered obligation has a disposition, and local edits/evidence are preserved. |
| 1 | Shared production controls and foreground-push pilot | Implemented, with prior cold/warm S1–S3 evidence. | Equivalent assertions, causal negative controls, production-owned graph and verified build reuse. |
| 2 | Routing, notifications, payload lifecycle and private media | All four integrated-main Android campaigns have recorded passes; remaining closure evidence is described below. | Required assertions, available-platform proofs, cleanup, preservation and applicable wave gates are complete. |
| 3 | Shared group stack and complete group catalog | Partial replacements exist; further implementation remains paused. | Every applicable catalog case and direct consumer has equivalent production coverage or an explicitly retained purpose. |
| 4 | Remaining transport/application measurements and shared XCTest consumption | Startup/resume measurement and an XCTest adapter exist; further implementation remains paused. | Every remaining harness has a verified replacement or accurately scoped retained owner. |
| 5 | Additive closure and reviewable retirement | Not complete; retirement remains subject to separate approval. | Stable-candidate full closure, complete accounting and an evidence-backed retirement proposal; only specifically approved retirement is executed. |

Recommended progression: reconcile the current baseline, finish Wave 2 closure, then request authorization for Wave 3, followed by Wave 4 and Wave 5. An earlier partial implementation in a later wave does not establish that wave's completion.

## Wave 0 — baseline and preservation

Before new implementation or long verification:

1. Read `AGENTS.md`, inspect current main and identify active campaign/device owners.
2. Record the verified comparison SHA, local/staged/untracked changes, source/configuration fingerprints and exact approved original-file bytes.
3. Reconcile new obligations and concurrent changes into the existing crosswalk. Preserve historical candidates and first-attempt evidence.
4. Validate metadata and preview affected selection using an explicit verified `--base` and `--local`.

Reuse the existing baseline work where it still applies. Do not reset or commit user changes to obtain a clean candidate. If isolated verification is necessary, preserve the relevant local inputs and reconcile the resulting changes carefully into main.

## Wave 1 — shared controls and foreground group-push pilot

Maintain the production bootstrap as the service-construction owner. Scenario controls and observations must use those production instances and retain invocation/profile/role/run-ID/nonce checks.

The pilot preserves:

- S1: deliberately missed live delivery, exact push recovery once and the correct notification route payload.
- S2: live delivery followed by push produces one stored message and one notification request.
- S3: the narrowly injected missing-group drain failure goes through production eligibility handling and suppresses fallback notification.

Prior cold/warm pilot passes demonstrate reuse for their recorded source and artifact. Preserve the original iOS route and its assertion boundary. Revalidate affected pilot behavior if later shared changes invalidate its evidence; do not rebuild or rerun it merely because a new reference document was written.

## Wave 2 — finish the remaining closure evidence first

### Recorded progress

The [2026-09-29 integrated-main continuation](production-bootstrap-migration-crosswalk.md#2026-09-29-integrated-main-device-continuation) records passing notification-open, notification-sound, routing and private-media Android campaigns with exact two-peer cleanup. The four SIMS reports share campaign source digest `82d32bb186b69fea5fe9b77dbf811ca997a47afaa629ff19a2f3e058f43a94fc` and compatible sender/receiver APK identities.

These newer results supersede the earlier review's finding that no integrated-main Wave 2 campaigns had run. They do not erase earlier failures or certify subsequent source changes. Broader wrapper fingerprints include additional checkout inputs and must be interpreted separately from campaign/artifact identity.

The latest crosswalk also records a full Dart host rerun with 18,334 passing tests and two skips, passing Go/relay and Android native results, and a separate passing Plan 371 iOS check. Its first group-notification batch failure and later diagnostic passes remain visible; a cause was not established.

The [2026-09-30 bounded closure audit](production-bootstrap-migration-crosswalk.md#2026-09-30-bounded-wave-2-closure-audit) supersedes the earlier pending Plan 373 status: the pinned iPhone 17 Pro native wrapper passed three expected-red controls, one restored-source control and all 28 final XCTest methods, then restored its source and owned build data. A system-audio positive control captured known Settings previews, but a single fresh full sound campaign stopped after S7 on a no-step Maestro timeout, with exact cleanup. It never reached S16 and produced no attributable acoustic waveform. The scoped preservation audit confirms the original Wave 2 integration harnesses unchanged and lists wider dirty-tree differences separately. The user then accepted the prior S16 unmuted SystemUI speaker-path receipt as sufficient audible-device evidence for Wave 2, with direct hearing unverified. **WAVE 2 COMPLETE; Waves 3–5 remain paused.**

### Closure scope and later work

1. **Retain the S16 acoustic limitation.** The accepted native speaker-path evidence closes the Wave 2 audible-device criterion. No waveform or human hearing observation attributable to that S16 arrival exists. The later global recorder's positive control does not fill that window; do not schedule another sound campaign automatically.
2. **Keep acceptance scopes distinct.** The Plan 373 result, host rerun, Android campaign artifacts and scoped original-file audit are recorded with their receipts. The broad affected selection and unrelated dirty-tree original changes are not certified by those Wave 2 checks; the first UP-012 host failure remains visible.

Do not restart all four passing Android campaigns automatically. Repeat only what a source/configuration change, failed assertion or missing obligation justifies. If later evidence has already closed one of these items, verify and retain it rather than recreating it.

The earlier configuration diagnosis was superseded: the wrapper accepts an explicit `--device-config`, and existing ignored configuration passed the review preview. An absent `tool/testing/config.local.json` alone is not a blocker. Always rediscover devices, verify fixture isolation and ownership, and run actual setup checks before using historical configuration.

### Boundaries to preserve

- Real cold/warm, foreground/background, unread, payload and navigation distinctions.
- Notification sound S1–S16 and the S15 post-clear control, including S14's first-card-before-update proof.
- All 27 routing cases, exact stored text and intermediate receipts.
- Private-media UI, committed SQL transitions, file/attachment ownership, cleanup, cold persistence and refusal assertions; retain component/native proof at its intended boundary.
- Production Firebase configuration for the emulator receiver and disposable sender identity, with both peer states protected and restored.

The [original Luna prompt](production-bootstrap-wave-2-luna-prompt.md) and [continuation prompt](production-bootstrap-wave-2-continuation-luna-prompt.md) remain historical handoffs. Their earlier missing-work lists require reconciliation against the newer evidence before reuse.

## Wave 3 — complete production-composed group coverage

Resume only after explicit authorization. Use the shared production composition already established; scenario orchestration stays outside bootstrap.

Recommended implementation order:

1. Complete small group smoke, invite/status and lifecycle journeys, including direct consumers of `setupGroupMultiDeviceStack`.
2. Finish and verify the existing initial catalog replacements: ML-001 creation, PL-009 reaction roundtrip, RT-001 reaction toggle convergence and PL-010 removed-member reaction rejection. Reconcile their current implementation and evidence before adding new work.
3. Add the remaining catalog families incrementally, preserving each case's roles, topology, timing, intermediate assertions and terminal receipts.
4. Reconcile the complete catalog and direct/full-mode selection behavior, then run the dependency-wave gate.

The planning catalog contained 109 cases. Refresh discovery and account for later additions; do not use that historical count to omit newly discovered obligations. Keep the original graph available to original callers. A differently named test service container is not a production-composed replacement.

Exit: each applicable catalog obligation has evidence or a justified availability-bounded disposition, and replacement application journeys no longer depend on duplicated group composition.

## Wave 4 — transport, application measurements and shared XCTest

Resume only after explicit authorization. Apply the established assertion-boundary classification rather than migrating every component test into application startup.

Recommended work:

1. Complete separately named production measurements for transport census, relay/reconnect recovery, routing and end-user latency where those claims require production startup.
2. Preserve original intervals and thresholds. Keep existing crypto, bridge, algorithm and narrow inbox-custody proofs isolated where that isolation defines the assertion.
3. Reconcile the existing startup/resume B/M/BR measurement and its evidence; it does not certify the other performance families.
4. Connect the additive shared-XCTest adapter to actual compatible consumers. Prove attested bundle reuse through `test-without-building`, independent per-selector fixtures/results, provenance rejection and exact cleanup.
5. Compare build counts and setup costs without changing original fresh-build owners, then run the applicable wave gate.

Exit: every remaining harness has verified production replacement coverage or a documented retained purpose whose scope matches its evidence.

## Wave 5 — additive closure and retirement proposal

First complete additive migration accounting with original routes retained:

1. Reconcile all original/new obligations, platform variants, executable owners, intermediate assertions and retained component purposes.
2. Retain or extend the focused guard preventing replacement journeys from reconstructing application graphs or importing legacy stacks. Do not apply that prohibition to deliberately retained originals or component tests.
3. Demonstrate cold-build and warm-reuse targets for compatible replacement artifacts, no hidden child builds, and honest aggregate costs while originals also execute.
4. Run the final required host gate and one canonical full run on the stable candidate without `--only`. Missing manual/device evidence remains incomplete; unavailable hardware receives the project-policy N/A disposition.
5. Prepare an exact retirement proposal listing each original route/file, its replacement, preserved assertions/variants/platforms, comparative evidence and expected build/execution reduction.

Retirement requires separate explicit approval. If deferred, report additive completion and retained duplicate costs. If approved, change only the approved owners/files/profiles/selectors, preserve original evidence, update fingerprints/runtime roots and perform the required post-change closure checks.

## Gates that apply across waves

- No implicit skills or sub-agents. Follow current `AGENTS.md` and explicit user authorization.
- Preserve original tests/harnesses except exact separately approved patches. Consult the current canonical approval records; older prompts may not include later approvals. No approval authorizes unrelated changes or weaker assertions.
- Keep fixture preparation, actions/fault injection and observation distinct. Readiness is not a scenario pass.
- Use Appium MCP for live exploration and OS interaction, Maestro for stable UI flows, and existing native/protocol adapters for their documented non-UI assertions.
- Discover and pin available targets. Default non-iOS-specific two-peer work to a connected Android phone plus an available emulator. Respect current iOS-specific restrictions and other automation owners.
- Unavailable hardware is `N/A (target unavailable by project policy)`. Missing access or fixtures on an available target require precise diagnosis.
- Validate metadata, preview/run affected selection with explicit verified `--base` and `--local`, and execute causal tests plus preservation sentinels per slice.
- Run full `host-all` at completed dependency-wave boundaries and final closure, not after every edit. Broaden or repeat checks only when new changes, failures or unresolved concerns justify it.
- Distinguish assertion failures, actual setup blockers, diagnostic omissions and unmapped local-change gaps. A subset wrapper's `BLOCKED` status does not convert its passing selected cases into failures or certify omitted obligations.
- Preserve failures and cleanup evidence. Review a failed device run and use a causal probe before a fresh attempt; do not automatically rerun campaigns or extend deadlines.
- Keep run receipts in ignored artifacts and durable facts in the existing canonical records. Do not create session diaries or another executable inventory.

## Provenance and use

This roadmap summarizes the main plan and the latest crosswalk sections read on 2026-09-29. No builds, tests or device campaigns were run to prepare it; the status statements above are attributed to those records, not a new independent validation.

Reference session ID: `01a0e30a-5b68-7cd2-92fe-036a6b19e1b2`.

When returning later, begin with current `AGENTS.md`, source, plan and crosswalk. Reconcile what has changed before choosing the next authorized bounded batch.
