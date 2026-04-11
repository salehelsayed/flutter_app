# Audit Gap To Matrix / Prompt Map For `_Intro-reliability-gap-audit.md`

This file maps the concrete audit gaps from:

- `Test-Flight-Improv/Intro-Feature/_Intro-reliability-gap-audit.md`

to:

- owning matrix row(s) in `libp2p_introduction_test_matrix_full_with_rules.md`
- current closure state in `libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`
- whether execution prompt history is present in `libp2p_introduction_test_matrix_full_with_rules-session-breakdown-prompts.md`

Mapping notes:

- "Prompt history present" means the row id or its concrete execution handoff appears in `libp2p_introduction_test_matrix_full_with_rules-session-breakdown-prompts.md`.
- Prompt-history absence does not mean the work never happened. It means this specific prompt-record file does not capture the executed prompts for that row.
- This filtered map intentionally keeps only audit gaps that are still partially implemented or still open in the current repo state.
- The prompt log does not currently capture the execution prompts for the remaining item tied to `RM-013`.
- Where the audit gap is broader than a single matrix row, the closest owning row is named and any residual open scope is called out explicitly.

Distinct audit coverage item count: 3

## 1. Avatar failure does not roll back the contact after mutual acceptance

Audit source:

- Group C in `_Intro-reliability-gap-audit.md`
- the best-effort avatar follow-up concern after the contact is created

Owning matrix row(s):

- primary: `RM-013` (`Mutual acceptance creates system message and new-connection notification; avatar retry failure does not roll back the contact`)

Current breakdown state:

- `RM-013` is `accepted` in `libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`
- the breakdown records `create_connection_on_mutual_acceptance_test.dart` no-rollback coverage, `introduction_listener_test.dart` notification coverage, and a green rerun of `./scripts/run_test_gates.sh intro`

Prompt history in prompt log:

- `absent`

Coverage verdict:

- the matrix closes the narrower "avatar failure does not roll back the contact" sub-problem
- the prompt record does not capture the `RM-013` execution prompts

Notes:

- This is only a partial match to the audit's broader avatar-reliability concern.
- `RM-013` proves no rollback; it does not by itself prove a durable eventual-settlement substrate or smoke/e2e avatar recovery path.

## 2. Explicit top-level `integration_test/` intro acceptance reliability journey

Audit source:

- the current-gap note in `_Intro-reliability-gap-audit.md` that says there is no explicit top-level `integration_test/` intro acceptance reliability journey in the checked-in tree

Owning matrix row(s):

- no exact owning row found in `libp2p_introduction_test_matrix_full_with_rules.md`

Current breakdown state:

- no row-owned closure found in `libp2p_introduction_test_matrix_full_with_rules-session-breakdown.md`
- current evidence is host-side intro integration plus three-simulator proof, not a checked-in top-level `integration_test/` journey

Prompt history in prompt log:

- `absent`

Coverage verdict:

- still open at the audit level
- not covered by the prompt record

Notes:

- This is a real remaining audit gap, not just a prompt-log omission.
- The matrix does contain strong intro proof elsewhere, but it does not explicitly own this top-level `integration_test/` shape as a row.

## 3. Durable avatar eventual settlement after failure

Audit source:

- `TC-68-EC-04` in `_Intro-reliability-gap-audit.md`
- the current-gap note that avatar follow-up is still only partially covered and lacks smoke/e2e proof for durable eventual settlement

Owning matrix row(s):

- no exact owning row found for durable eventual settlement
- closest related row: `RM-013`

Current breakdown state:

- `RM-013` is `accepted`, but it closes only the no-rollback portion of the avatar problem
- no separate row-owned closure was found for durable retry, durable eventual settlement, or smoke/e2e avatar recovery after failure

Prompt history in prompt log:

- `absent`

Coverage verdict:

- still open at the audit level
- only partially covered by `RM-013`
- not covered by the prompt record

Notes:

- This is the clearest place where the audit remains broader than the currently closed matrix row.
- If this gap should become row-owned, it likely needs a new explicit matrix row or a broadened replacement for `RM-013`.
