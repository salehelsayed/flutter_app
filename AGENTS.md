## Skill invocation policy

- No skill may be selected implicitly in this project.
- Invoke every skill only when the user's current message affirmatively asks to use that skill by name (for example, `use $tdd-exec`). A negative mention, question, or request to audit a skill is not an invocation.
- A matching task, a plan path, “implement/execute/continue/finish this plan,” skill names inside a plan or repo document, an existing `*-session-breakdown.md`, or a prior assistant recommendation is not permission to invoke a skill.
- Without an explicit skill request, perform the requested work directly. Do not automatically use `tdd-exec`, decompose a plan into sessions, create session-breakdown artifacts, or route work through implementation rollout/pipeline/execution orchestrators.
- Explicit permission for one skill does not authorize a different skill it references; each additional skill must also be affirmatively requested by the user.

## Code navigation

Use targeted `rg`, file discovery, source reading, and test inspection for code navigation.

## Codex document memory

Use `codex-memory/` for what was specified, decided, refuted, deferred, or superseded. Current source establishes code behavior and relationships.

- Before a broad multi-file search over plans, specs, PRDs, architecture, reviews, or project history, run `python3 codex-memory/memory.py query "<one focused document question>"` and use its provenance to select documents.
- A complete read of one explicitly named plan/spec is allowed. In the root task, prefix its first document-only read with `CODEX_MEMORY_PRIMARY_READ=1`. Size long documents first; read once with sufficient output capacity or consecutive bounded ranges. Follow any output-safety retry instructions; never restart at line 1 because output was clipped. For implementation, extract code paths, symbols, tests, and gates, then inspect those anchors.
- Keep document reads/searches in document-only tool cells, one configured document per broad-read cell. Give document/history workers a separately labeled `document memory context:` with the focused question, returned provenance, and open question, separate from code evidence.
- Queries auto-refresh the index. Use `python3 codex-memory/memory.py status --verify-content` for a hash audit. Keep tracked defaults in `codex-memory/config.json`, local overrides in ignored `config.local.json`, and source-code globs out of this corpus.
- Before changing memory tooling, debugging hook/read behavior, measuring adoption or token savings, or running comparisons, read the applicable sections of `codex-memory/OPERATIONS.md` and its linked README references. Hook files alone do not prove that hooks ran; check local enablement and current execution evidence.
- Keep durable knowledge in its canonical source with provenance and explicit superseded/refuted status. Update the relevant existing record instead of adding session diaries; use `docs/testing/TESTING.md` for verified testing knowledge. Derived caches do not replace source records or historical evidence.

## Mobile device test availability

- Mobile device tests and proof legs may use only targets that are available at execution time: USB-connected Android devices, USB-connected iPhones, available iOS simulators, and available Android emulators.
- Resolve the live matrix with `flutter devices --machine`, `adb devices`, and `xcrun simctl list devices available` as applicable. Pin every command to an explicit discovered target ID.
- When a test needs two phones/peers and the behavior is not iOS-specific, use one USB-connected physical Android device plus one available Android emulator by default. Pin both Android IDs and automate setup, permissions, navigation, actions, and assertions through Appium MCP where it can prove the behavior, or an existing campaign for its documented protocol/native proof requirement. Do not choose an iPhone merely as the second endpoint or require the user to tap through an iPhone flow.
- Use an iPhone/iOS simulator only for an iOS-specific OS boundary or an explicit Android/iOS parity claim that the Android pair cannot prove. Keep that platform proof separate from the default automated two-peer Android topology.
- Do not require, wait for, or block a plan on an Android/iOS model, OS release, or API band that is not present in that live matrix. An unavailable version-specific hardware leg is `N/A (target unavailable by project policy)`, not an `environment_blocker`, `evidence_gap`, or failed gate.
- Preserve version-specific production behavior with host/native unit tests, compile-time availability tests, fakes, and emulators/simulators that are actually available. For example, Android API 24-28 branches remain causally native-tested but do not require an API 24-28 physical device unless one is already connected.
- Future specs, TDD plans, execution contracts, QA verdicts, and closure docs must use this availability-bounded device matrix. They may recommend additional hardware confidence as optional follow-up, but unavailable hardware cannot be a required closure condition.

## Device campaign preparation and recovery

- Use Appium MCP by default for live UI exploration, reproduction, permissions, notification taps, navigation, lifecycle actions, and visual evidence. Use the actual MCP tools; a broken MCP connection is a setup issue to diagnose, not permission to silently build another UI harness. This tool preference does not invoke a skill.
- Reuse existing unit, native, protocol, backend, and media tests for assertions they can prove. Before creating or extending a custom device harness, record the specific assertion Appium MCP and existing tests cannot establish, and why. Keep any necessary adapter limited to that gap; do not rebuild generic UI automation. Existing campaign exceptions need a concrete `ui_driver_reason` in `tool/testing/selection.json`.
- Before a long campaign, use the existing check wrapper's setup checks and read the relevant recovery guidance in `docs/testing/TESTING.md`. Confirm the available pinned targets, exact source/build/configuration, host dependencies, and campaign-specific peer/provider readiness. A successful setup check is not a passing scenario.
- One automation owner may control a device at a time. End your own Appium MCP session before handing the device to a campaign that uses Android instrumentation; preserve other sessions and running campaigns. The wrapper's device leases coordinate cooperating launchers across checkouts, but do not fence external tools or prove iOS automation is idle.
- When setup blocks, diagnose and repair known, reversible problems within the task's existing authorization, recheck the prerequisite, then continue. Do not hand routine setup work back to the user or repeatedly request an approval already given. Ask only for genuinely missing information, access, or authorization; explain the precise remaining blocker. Never stop another owner's processes or expand access as an assumed repair.
- Keep first-attempt failures and redacted diagnostic evidence. Use a small causal probe before another full campaign; keep original assertions and deadlines. Device campaigns do not automatically rerun with `--rerun-failed`; inspect cleanup and restore only the state owned by that run before starting a fresh attempt. After a launched campaign fails or blocks, the wrapper leaves subsequent device campaigns unrun until that review and a fresh invocation.

## TDD gate cadence

- Individual TDD plan closure runs focused causal tests, exact preservation sentinels, the affected curated lane gate, and only the justified `core-host-all`, `feature-host-all`, or performance family sweep for production surfaces actually changed by that plan.
- Do not add or run full `host-all` as a default per-plan acceptance gate. Run full `host-all` once after the relevant dependency wave/batch is complete and once again at final rollout or release closure.
- Shared tests outside feature/core globs run by exact command during the plan and remain registered for the later wave-level `host-all`; registration under `host-all` does not make it a per-plan execution obligation.

## Regression checks and testing memory

- Before choosing tests for code-changing work, read the relevant entries in `docs/testing/TESTING.md` and consult `tool/testing/selection.json`. Follow applicable narrower instructions as well. The manifest owns executable selection; the knowledge file owns verified explanations, limitations, and evidence references.
- Use `python3 scripts/mknoon_checks.py validate`, then preview and run the appropriate change selection with an explicit verified `--base` and `--local` for working-tree changes. Report required checks that were not executed; neither an inventory nor a passing unrelated test is validation.
- Review affected mappings when behavior, shared dependencies, tests, fixtures, runners, dependencies, native/build configuration, or feature flags change. Update renamed/deleted selectors and preserve mandatory release checks. Narrow coverage only with evidence, never because a check is slow or failed once.
- Record confirmed new regression/dependency/runtime/reliability knowledge by updating the relevant knowledge entry; label hypotheses and retain redacted raw evidence in ignored run artifacts. Do not append session diaries or duplicate executable mappings in prose.
- Release checks use the actual previous published revision and exact candidate source/configuration/artifact. Missing required manual/device evidence remains incomplete; source-build tests do not certify an untested signed candidate. Keep first-attempt failures visible after diagnostic reruns.
- The repository-local `mknoon-change-check`, `mknoon-release-check`, and `mknoon-test-maintenance` skills are optional adapters over the same wrapper and rules. The skill invocation policy above still applies: invoke them only when explicitly requested by name; otherwise perform the underlying checks directly.
