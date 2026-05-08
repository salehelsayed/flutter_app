---
name: run-flutter-host-gates
description: Run this Flutter repo's host-side non-simulator gates, including host-all, feature-host-all, core-host-all, performance-host, existing named host gates, completeness checks, and fix-as-you-go host test loops without resolving mobile devices.
---

# Run Flutter Host Gates

## Workflow

1. Start from the Flutter repo root, or pass `--repo <path>` to the bundled script.
2. Prefer dry-run/list mode first for broad host scopes unless the user explicitly asks to execute.
3. Use the bundled helper for broad host scopes:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-host-gates/scripts/run_host_gates.sh" host-all --list
```

4. Execute the requested scope after the plan looks correct:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-host-gates/scripts/run_host_gates.sh" host-all
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-host-gates/scripts/run_host_gates.sh" feature-host-all
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-host-gates/scripts/run_host_gates.sh" core-host-all
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-host-gates/scripts/run_host_gates.sh" performance-host
```

## Scopes

- `host-all`: all `test/**/*_test.dart` except `test/performance/**`.
- `feature-host-all`: all `test/features/**/*_test.dart`.
- `core-host-all`: all `test/core/**/*_test.dart`.
- `performance-host`: all `test/performance/**/*_test.dart`.
- Existing named host gates can still be run through `./scripts/run_test_gates.sh`: `baseline`, `1to1`, `intro`, `groups`, `feed`, `posts`, `runtime-telemetry`, `benchmark`, and `completeness-check`.

Do not use this skill for simulator/device-backed reliability suites. Use `$run-flutter-reliability-sims` for `reliability-sim`, 1:1/group/intro simulator checks, relay env handling, and multi-device resolution.

## Fix As You Go

When the user says `fix-as-you-go`, run a fail-fast repair loop:

1. Run the dry-run/list pass and keep the planned command numbers.
2. Run the requested broad host scope without `--continue-on-failure`.
3. If command `#N` fails, debug before retrying.
4. Decide whether the failure is test/harness/environment or product code.
5. Fix the correct layer without weakening real assertions.
6. Rerun only the failed command:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-host-gates/scripts/run_host_gates.sh" host-all --only N
```

7. When it passes, continue from the next command:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-host-gates/scripts/run_host_gates.sh" host-all --start-at N_PLUS_1
```

8. At the end, rerun the full requested broad host scope once.

Do not repeatedly rerun commands that already passed during the fix loop. Do not use `--continue-on-failure` for `fix-as-you-go` unless the user explicitly asks for an inventory of all failures first.

## Useful Options

Forward these through the bundled script for broad host scopes:

```bash
--list
--only <N|path>
--start-at <N>
--continue-on-failure
```

## Reporting

In the final answer, include:

- the scope requested,
- the exact command plan source used,
- every failing command and root cause,
- files changed,
- final commands run,
- final pass/fail status.
