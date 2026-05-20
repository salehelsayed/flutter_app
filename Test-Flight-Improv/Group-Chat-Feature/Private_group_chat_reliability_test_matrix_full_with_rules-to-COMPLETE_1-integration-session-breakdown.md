# Private Group Chat Full-With-Rules To COMPLETE_1 Integration Session Breakdown

Status: decomposition-ready

## Decomposition Progress

| timestamp | phase | rows/files inspected | decision/blocker | next action |
|---|---|---|---|---|
| 2026-05-16 17:07 CEST | Matrix Intake completed | Worktree `Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`; main `Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md` | Source and compatibility artifacts identified. | Build completed-row inventory. |
| 2026-05-16 17:07 CEST | Row Inventory completed | Worktree Session Ledger rows | 200 row-owned worktree rows are accepted/completed. Shared prerequisite is excluded; blocked `ML-012` and `ST-014` are excluded. | Write integration contract and session ledger. |
| 2026-05-16 17:07 CEST | Evidence Map completed | Worktree Cross-Checkout Duplication Guard; main COMPLETE_1 session ledger | Known high-overlap COMPLETE_1 rows copied into the integration guard; all other sessions must compute overlap from changed files before integrating. | Write ordered session breakdown. |
| 2026-05-16 17:07 CEST | Breakdown Write completed | This artifact | One pending integration session exists for each completed worktree row. No implementation work has been performed. | Execute sessions later, one row at a time. |

## Recommended Plan Count

Recommended plan count: 200 integration plans.

This artifact intentionally creates one integration session for each completed row-owned worktree session in the full-with-rules breakdown. It does not create a session for `PREREQ-MULTI-PARTY-DEVICE-HARNESS` because that is not a source matrix row. It does not create sessions for `ML-012` or `ST-014` because those rows are still `blocked`, not completed, in the worktree ledger.

## Decomposition Artifact

- artifact path: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-to-COMPLETE_1-integration-session-breakdown.md`
- worktree source breakdown: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md`
- main compatibility breakdown: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
- integration target checkout: `/Users/I560101/Project-Sat/mknoon-2/flutter_app`
- worktree source checkout: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`

## Overall Closure Bar

This integration rollout is closed only when every row in the Session Ledger has final integration ledger status:

- `accepted`: meaningful row-owned worktree changes were integrated into main, focused row tests and affected COMPLETE_1 tests passed, and integration notes identify exact code/test/doc files accepted.
- `skipped_already_present`: the row's exact meaningful changes and proof are already present in main or COMPLETE_1-equivalent coverage, no duplicate code/test/doc work was added, and the skip note identifies the evidence.
- `blocked_conflict`: affected rows from both breakdowns were mapped, the conflict is documented with exact files and tests, and the row was not partially integrated.

Any other status means this integration rollout remains open.

## Source Of Truth

The source row truth for this integration is the worktree full-with-rules breakdown's accepted row-owned Session Ledger. The compatibility truth is the main COMPLETE_1 breakdown and its plan files. Current main code and tests outrank stale prose in either breakdown.

Per-session integration must not cherry-pick a broad worktree diff. Each session owns exactly one completed worktree row and may integrate only the row-owned meaningful delta after duplicate and conflict checks.

## Integration Session Contract

Every Session Ledger row below is one integration session. For each row `R`, the future executor must:

1. Inspect the worktree row in the full-with-rules breakdown, including the Session Ledger row and `### Session R`.
2. Inspect the worktree plan file `Private_group_chat_reliability_test_matrix_full_with_rules-session-R-plan.md`.
3. Inspect overlapping or conflicting rows in the COMPLETE_1 breakdown and their plan files, using the Known COMPLETE_1 Overlap Guard plus changed-file and scenario search.
4. Identify exact worktree row-owned files before any edit, split into code, tests, and docs. If the plan file does not list them directly, reconstruct them from row-specific checkpoint commits, plan evidence, `git log --name-status --grep=R`, and the row's focused test evidence.
5. Compare those files against main and avoid duplicate work already present in main.
6. If conflict exists, map the affected worktree rows and COMPLETE_1 rows before resolving. If that mapping is incomplete, mark the row `blocked_conflict`.
7. Integrate only meaningful row-owned changes needed in main. Do not import unrelated worktree churn, broad formatting, generated noise, or changes owned by another row.
8. Run the worktree row's focused tests and any affected COMPLETE_1 focused tests. If a test is intentionally not run, record why in the row's integration plan and ledger note.
9. Update this artifact's integration ledger row to `accepted`, `skipped_already_present`, or `blocked_conflict`, with exact files, tests, and evidence.

## Known COMPLETE_1 Overlap Guard

These high-overlap mappings are mandatory starting points, not the full overlap set. Every integration session must also discover overlaps from its exact changed-file list.

| worktree row | COMPLETE_1 rows to inspect first | risk |
|---|---|---|
| `ML-006` | `GM-005`, `GM-018`, `GM-020` | High |
| `ML-007` | `GM-006`, `GM-007`, `GM-008`, `GM-019`, `GM-021`, `GM-024` | High |
| `ML-008` | `GM-022`, `GM-009`, `GM-010`, `GM-024` | High |
| `ML-009` | `GM-011`, `GM-012`, `GM-013`, `GM-014` | High |
| `ML-011` | `GM-009` and related stale-ordering rows | High |
| `KE-005` | `GL-015` | High |
| `KE-016` | `GM-021` | High |
| `IR-005` | `GM-007`, `GM-019` | High |
| `RA-002` | `GM-007`, `GM-016`, `GM-017`, `GM-018`, `GM-019`, `GM-024` | High |
| `RA-003` | `GM-007`, `GM-016`, `GM-017`, `GM-018`, `GM-019`, `GM-024` | High |
| `RA-010` | `GM-007`, `GM-016`, `GM-017`, `GM-018`, `GM-019`, `GM-024` | High |
| `RA-014` | `GM-007`, `GM-016`, `GM-017`, `GM-018`, `GM-019`, `GM-024` | High |
| `RA-017` | `GM-007`, `GM-016`, `GM-017`, `GM-018`, `GM-019`, `GM-024` | High |
| `NW-004` | `GL-017`, `GL-018` | Medium |
| `UP-002` | `GM-024`, `GM-030`, `GM-031` | Medium |
| `UP-009` | `GM-024`, `GM-030`, `GM-031` | Medium |
| `SV-001` | `GM-017`; inspect relevant `GA-*` authorization rows | Medium |
| `SV-002` | `GM-017`; inspect relevant `GA-*` authorization rows | Medium |

Shared proof surfaces that must trigger duplicate checks include `./scripts/run_test_gates.sh groups`, `./scripts/run_test_gates.sh completeness-check`, `integration_test/group_multi_party_device_real_harness.dart`, `integration_test/scripts/run_group_multi_party_device_real.dart`, `integration_test/scripts/group_multi_party_device_criteria.dart`, `test/integration/group_multi_party_device_criteria_test.dart`, group membership/messaging/recovery Flutter tests, and Go group inbox/pubsub/envelope tests.

## Row Traceability Rule

Every completed worktree row maps to exactly one integration session id: `INTEGRATE-<row-id>`. Later closure work must report final truth per worktree source row and must not collapse these sessions by subsystem, shared files, test suite, or COMPLETE_1 overlap family.

## Session Ledger

| # | integration session id | worktree row | priority | worktree plan file | integration ledger status |
|---|---|---|---|---|---|
| 1 | INTEGRATE-BB-001 | BB-001 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-001-plan.md` | pending_integration |
| 2 | INTEGRATE-BB-002 | BB-002 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-002-plan.md` | pending_integration |
| 3 | INTEGRATE-BB-003 | BB-003 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-003-plan.md` | pending_integration |
| 4 | INTEGRATE-BB-004 | BB-004 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-004-plan.md` | pending_integration |
| 5 | INTEGRATE-BB-006 | BB-006 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-006-plan.md` | pending_integration |
| 6 | INTEGRATE-BB-007 | BB-007 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-007-plan.md` | pending_integration |
| 7 | INTEGRATE-BB-008 | BB-008 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-008-plan.md` | pending_integration |
| 8 | INTEGRATE-BB-009 | BB-009 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-009-plan.md` | pending_integration |
| 9 | INTEGRATE-BB-010 | BB-010 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-010-plan.md` | pending_integration |
| 10 | INTEGRATE-BB-011 | BB-011 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-011-plan.md` | pending_integration |
| 11 | INTEGRATE-BB-012 | BB-012 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-012-plan.md` | pending_integration |
| 12 | INTEGRATE-BB-013 | BB-013 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-013-plan.md` | pending_integration |
| 13 | INTEGRATE-ML-001 | ML-001 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-001-plan.md` | pending_integration |
| 14 | INTEGRATE-ML-002 | ML-002 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-002-plan.md` | pending_integration |
| 15 | INTEGRATE-ML-003 | ML-003 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-003-plan.md` | pending_integration |
| 16 | INTEGRATE-ML-004 | ML-004 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-004-plan.md` | pending_integration |
| 17 | INTEGRATE-ML-005 | ML-005 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-005-plan.md` | pending_integration |
| 18 | INTEGRATE-ML-006 | ML-006 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-006-plan.md` | pending_integration |
| 19 | INTEGRATE-ML-007 | ML-007 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-007-plan.md` | pending_integration |
| 20 | INTEGRATE-ML-008 | ML-008 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-008-plan.md` | pending_integration |
| 21 | INTEGRATE-ML-009 | ML-009 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-009-plan.md` | pending_integration |
| 22 | INTEGRATE-ML-011 | ML-011 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-011-plan.md` | pending_integration |
| 23 | INTEGRATE-ML-013 | ML-013 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-013-plan.md` | pending_integration |
| 24 | INTEGRATE-ML-014 | ML-014 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-014-plan.md` | pending_integration |
| 25 | INTEGRATE-ML-015 | ML-015 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-015-plan.md` | pending_integration |
| 26 | INTEGRATE-ML-017 | ML-017 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-017-plan.md` | pending_integration |
| 27 | INTEGRATE-ML-018 | ML-018 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-018-plan.md` | pending_integration |
| 28 | INTEGRATE-ML-019 | ML-019 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-019-plan.md` | pending_integration |
| 29 | INTEGRATE-KE-001 | KE-001 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-001-plan.md` | pending_integration |
| 30 | INTEGRATE-KE-002 | KE-002 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-002-plan.md` | pending_integration |
| 31 | INTEGRATE-KE-003 | KE-003 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-003-plan.md` | pending_integration |
| 32 | INTEGRATE-KE-005 | KE-005 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-005-plan.md` | pending_integration |
| 33 | INTEGRATE-KE-006 | KE-006 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-006-plan.md` | pending_integration |
| 34 | INTEGRATE-KE-007 | KE-007 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-007-plan.md` | pending_integration |
| 35 | INTEGRATE-KE-008 | KE-008 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-008-plan.md` | pending_integration |
| 36 | INTEGRATE-KE-009 | KE-009 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-009-plan.md` | pending_integration |
| 37 | INTEGRATE-KE-010 | KE-010 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-010-plan.md` | pending_integration |
| 38 | INTEGRATE-KE-011 | KE-011 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-011-plan.md` | pending_integration |
| 39 | INTEGRATE-KE-012 | KE-012 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-012-plan.md` | pending_integration |
| 40 | INTEGRATE-KE-013 | KE-013 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-013-plan.md` | pending_integration |
| 41 | INTEGRATE-KE-014 | KE-014 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-014-plan.md` | pending_integration |
| 42 | INTEGRATE-KE-015 | KE-015 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-015-plan.md` | pending_integration |
| 43 | INTEGRATE-KE-016 | KE-016 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-016-plan.md` | pending_integration |
| 44 | INTEGRATE-KE-017 | KE-017 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-017-plan.md` | pending_integration |
| 45 | INTEGRATE-KE-018 | KE-018 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-018-plan.md` | pending_integration |
| 46 | INTEGRATE-KE-019 | KE-019 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-019-plan.md` | pending_integration |
| 47 | INTEGRATE-KE-020 | KE-020 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-020-plan.md` | pending_integration |
| 48 | INTEGRATE-KE-021 | KE-021 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-021-plan.md` | pending_integration |
| 49 | INTEGRATE-DE-001 | DE-001 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-001-plan.md` | pending_integration |
| 50 | INTEGRATE-DE-002 | DE-002 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-002-plan.md` | pending_integration |
| 51 | INTEGRATE-DE-003 | DE-003 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-003-plan.md` | pending_integration |
| 52 | INTEGRATE-DE-004 | DE-004 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-004-plan.md` | pending_integration |
| 53 | INTEGRATE-DE-005 | DE-005 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-005-plan.md` | pending_integration |
| 54 | INTEGRATE-DE-006 | DE-006 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-006-plan.md` | pending_integration |
| 55 | INTEGRATE-DE-007 | DE-007 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-007-plan.md` | pending_integration |
| 56 | INTEGRATE-DE-008 | DE-008 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-008-plan.md` | pending_integration |
| 57 | INTEGRATE-DE-009 | DE-009 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-009-plan.md` | pending_integration |
| 58 | INTEGRATE-DE-011 | DE-011 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-011-plan.md` | pending_integration |
| 59 | INTEGRATE-DE-012 | DE-012 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-012-plan.md` | pending_integration |
| 60 | INTEGRATE-DE-013 | DE-013 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-013-plan.md` | pending_integration |
| 61 | INTEGRATE-DE-014 | DE-014 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-014-plan.md` | pending_integration |
| 62 | INTEGRATE-DE-017 | DE-017 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-017-plan.md` | pending_integration |
| 63 | INTEGRATE-DE-019 | DE-019 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-019-plan.md` | pending_integration |
| 64 | INTEGRATE-IR-001 | IR-001 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-001-plan.md` | pending_integration |
| 65 | INTEGRATE-IR-002 | IR-002 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-002-plan.md` | pending_integration |
| 66 | INTEGRATE-IR-004 | IR-004 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-004-plan.md` | pending_integration |
| 67 | INTEGRATE-IR-005 | IR-005 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-005-plan.md` | pending_integration |
| 68 | INTEGRATE-IR-006 | IR-006 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-006-plan.md` | pending_integration |
| 69 | INTEGRATE-IR-007 | IR-007 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-007-plan.md` | pending_integration |
| 70 | INTEGRATE-IR-008 | IR-008 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-008-plan.md` | pending_integration |
| 71 | INTEGRATE-IR-009 | IR-009 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-009-plan.md` | pending_integration |
| 72 | INTEGRATE-IR-012 | IR-012 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-012-plan.md` | pending_integration |
| 73 | INTEGRATE-IR-013 | IR-013 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-013-plan.md` | pending_integration |
| 74 | INTEGRATE-IR-014 | IR-014 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-014-plan.md` | pending_integration |
| 75 | INTEGRATE-IR-015 | IR-015 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-015-plan.md` | pending_integration |
| 76 | INTEGRATE-IR-017 | IR-017 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-017-plan.md` | pending_integration |
| 77 | INTEGRATE-IR-018 | IR-018 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-018-plan.md` | pending_integration |
| 78 | INTEGRATE-IR-019 | IR-019 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-019-plan.md` | pending_integration |
| 79 | INTEGRATE-RA-001 | RA-001 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-001-plan.md` | pending_integration |
| 80 | INTEGRATE-RA-002 | RA-002 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-002-plan.md` | pending_integration |
| 81 | INTEGRATE-RA-003 | RA-003 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-003-plan.md` | pending_integration |
| 82 | INTEGRATE-RA-004 | RA-004 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-004-plan.md` | pending_integration |
| 83 | INTEGRATE-RA-005 | RA-005 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-005-plan.md` | pending_integration |
| 84 | INTEGRATE-RA-006 | RA-006 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-006-plan.md` | pending_integration |
| 85 | INTEGRATE-RA-007 | RA-007 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-007-plan.md` | pending_integration |
| 86 | INTEGRATE-RA-008 | RA-008 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-008-plan.md` | pending_integration |
| 87 | INTEGRATE-RA-009 | RA-009 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-009-plan.md` | pending_integration |
| 88 | INTEGRATE-RA-010 | RA-010 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-010-plan.md` | pending_integration |
| 89 | INTEGRATE-RA-011 | RA-011 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-011-plan.md` | pending_integration |
| 90 | INTEGRATE-RA-012 | RA-012 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-012-plan.md` | pending_integration |
| 91 | INTEGRATE-RA-014 | RA-014 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-014-plan.md` | pending_integration |
| 92 | INTEGRATE-RA-015 | RA-015 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-015-plan.md` | pending_integration |
| 93 | INTEGRATE-RA-016 | RA-016 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-016-plan.md` | pending_integration |
| 94 | INTEGRATE-RA-017 | RA-017 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-017-plan.md` | pending_integration |
| 95 | INTEGRATE-RA-018 | RA-018 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-018-plan.md` | pending_integration |
| 96 | INTEGRATE-NW-001 | NW-001 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-001-plan.md` | pending_integration |
| 97 | INTEGRATE-NW-002 | NW-002 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-002-plan.md` | pending_integration |
| 98 | INTEGRATE-NW-003 | NW-003 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-003-plan.md` | pending_integration |
| 99 | INTEGRATE-NW-004 | NW-004 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-004-plan.md` | pending_integration |
| 100 | INTEGRATE-NW-006 | NW-006 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-006-plan.md` | pending_integration |
| 101 | INTEGRATE-NW-007 | NW-007 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-007-plan.md` | pending_integration |
| 102 | INTEGRATE-NW-010 | NW-010 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-010-plan.md` | pending_integration |
| 103 | INTEGRATE-NW-011 | NW-011 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-011-plan.md` | pending_integration |
| 104 | INTEGRATE-NW-012 | NW-012 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-012-plan.md` | pending_integration |
| 105 | INTEGRATE-NW-013 | NW-013 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-013-plan.md` | pending_integration |
| 106 | INTEGRATE-NW-014 | NW-014 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-014-plan.md` | pending_integration |
| 107 | INTEGRATE-PL-002 | PL-002 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-002-plan.md` | pending_integration |
| 108 | INTEGRATE-PL-005 | PL-005 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-005-plan.md` | pending_integration |
| 109 | INTEGRATE-PL-006 | PL-006 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-006-plan.md` | pending_integration |
| 110 | INTEGRATE-PL-007 | PL-007 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-007-plan.md` | pending_integration |
| 111 | INTEGRATE-PL-010 | PL-010 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-010-plan.md` | pending_integration |
| 112 | INTEGRATE-PL-014 | PL-014 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-014-plan.md` | pending_integration |
| 113 | INTEGRATE-UP-001 | UP-001 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-001-plan.md` | pending_integration |
| 114 | INTEGRATE-UP-003 | UP-003 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-003-plan.md` | pending_integration |
| 115 | INTEGRATE-UP-005 | UP-005 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-005-plan.md` | pending_integration |
| 116 | INTEGRATE-UP-007 | UP-007 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-007-plan.md` | pending_integration |
| 117 | INTEGRATE-UP-008 | UP-008 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-008-plan.md` | pending_integration |
| 118 | INTEGRATE-UP-012 | UP-012 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-012-plan.md` | pending_integration |
| 119 | INTEGRATE-UP-013 | UP-013 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-013-plan.md` | pending_integration |
| 120 | INTEGRATE-SV-001 | SV-001 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-001-plan.md` | pending_integration |
| 121 | INTEGRATE-SV-002 | SV-002 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-002-plan.md` | pending_integration |
| 122 | INTEGRATE-SV-003 | SV-003 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-003-plan.md` | pending_integration |
| 123 | INTEGRATE-SV-004 | SV-004 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-004-plan.md` | pending_integration |
| 124 | INTEGRATE-SV-005 | SV-005 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-005-plan.md` | pending_integration |
| 125 | INTEGRATE-SV-006 | SV-006 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-006-plan.md` | pending_integration |
| 126 | INTEGRATE-SV-007 | SV-007 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-007-plan.md` | pending_integration |
| 127 | INTEGRATE-SV-008 | SV-008 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-008-plan.md` | pending_integration |
| 128 | INTEGRATE-SV-009 | SV-009 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-009-plan.md` | pending_integration |
| 129 | INTEGRATE-SV-010 | SV-010 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-010-plan.md` | pending_integration |
| 130 | INTEGRATE-SV-011 | SV-011 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-011-plan.md` | pending_integration |
| 131 | INTEGRATE-SV-013 | SV-013 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-013-plan.md` | pending_integration |
| 132 | INTEGRATE-SV-016 | SV-016 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-016-plan.md` | pending_integration |
| 133 | INTEGRATE-OB-002 | OB-002 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-002-plan.md` | pending_integration |
| 134 | INTEGRATE-OB-004 | OB-004 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-004-plan.md` | pending_integration |
| 135 | INTEGRATE-OB-006 | OB-006 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-006-plan.md` | pending_integration |
| 136 | INTEGRATE-OB-007 | OB-007 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-007-plan.md` | pending_integration |
| 137 | INTEGRATE-OB-008 | OB-008 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-008-plan.md` | pending_integration |
| 138 | INTEGRATE-OB-011 | OB-011 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-011-plan.md` | pending_integration |
| 139 | INTEGRATE-OB-012 | OB-012 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-012-plan.md` | pending_integration |
| 140 | INTEGRATE-ST-001 | ST-001 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-001-plan.md` | pending_integration |
| 141 | INTEGRATE-ST-002 | ST-002 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-002-plan.md` | pending_integration |
| 142 | INTEGRATE-ST-003 | ST-003 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-003-plan.md` | pending_integration |
| 143 | INTEGRATE-ST-005 | ST-005 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-005-plan.md` | pending_integration |
| 144 | INTEGRATE-ST-006 | ST-006 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-006-plan.md` | pending_integration |
| 145 | INTEGRATE-ST-007 | ST-007 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-007-plan.md` | pending_integration |
| 146 | INTEGRATE-ST-008 | ST-008 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-008-plan.md` | pending_integration |
| 147 | INTEGRATE-ST-011 | ST-011 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-011-plan.md` | pending_integration |
| 148 | INTEGRATE-ST-013 | ST-013 | P0 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-013-plan.md` | pending_integration |
| 149 | INTEGRATE-BB-005 | BB-005 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-005-plan.md` | pending_integration |
| 150 | INTEGRATE-BB-014 | BB-014 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-014-plan.md` | pending_integration |
| 151 | INTEGRATE-BB-015 | BB-015 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-015-plan.md` | pending_integration |
| 152 | INTEGRATE-BB-016 | BB-016 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-016-plan.md` | pending_integration |
| 153 | INTEGRATE-ML-010 | ML-010 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-010-plan.md` | pending_integration |
| 154 | INTEGRATE-ML-016 | ML-016 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-016-plan.md` | pending_integration |
| 155 | INTEGRATE-ML-020 | ML-020 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ML-020-plan.md` | pending_integration |
| 156 | INTEGRATE-KE-004 | KE-004 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-004-plan.md` | pending_integration |
| 157 | INTEGRATE-KE-022 | KE-022 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-022-plan.md` | pending_integration |
| 158 | INTEGRATE-DE-010 | DE-010 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-010-plan.md` | pending_integration |
| 159 | INTEGRATE-DE-015 | DE-015 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-015-plan.md` | pending_integration |
| 160 | INTEGRATE-DE-016 | DE-016 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-016-plan.md` | pending_integration |
| 161 | INTEGRATE-DE-020 | DE-020 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-020-plan.md` | pending_integration |
| 162 | INTEGRATE-IR-003 | IR-003 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-003-plan.md` | pending_integration |
| 163 | INTEGRATE-IR-010 | IR-010 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-010-plan.md` | pending_integration |
| 164 | INTEGRATE-IR-011 | IR-011 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-011-plan.md` | pending_integration |
| 165 | INTEGRATE-IR-016 | IR-016 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-016-plan.md` | pending_integration |
| 166 | INTEGRATE-RA-013 | RA-013 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-013-plan.md` | pending_integration |
| 167 | INTEGRATE-NW-005 | NW-005 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-005-plan.md` | pending_integration |
| 168 | INTEGRATE-NW-008 | NW-008 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-008-plan.md` | pending_integration |
| 169 | INTEGRATE-NW-009 | NW-009 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-009-plan.md` | pending_integration |
| 170 | INTEGRATE-NW-015 | NW-015 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-015-plan.md` | pending_integration |
| 171 | INTEGRATE-PL-001 | PL-001 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-001-plan.md` | pending_integration |
| 172 | INTEGRATE-PL-003 | PL-003 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-003-plan.md` | pending_integration |
| 173 | INTEGRATE-PL-004 | PL-004 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-004-plan.md` | pending_integration |
| 174 | INTEGRATE-PL-008 | PL-008 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-008-plan.md` | pending_integration |
| 175 | INTEGRATE-PL-009 | PL-009 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-009-plan.md` | pending_integration |
| 176 | INTEGRATE-PL-011 | PL-011 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-011-plan.md` | pending_integration |
| 177 | INTEGRATE-PL-012 | PL-012 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-012-plan.md` | pending_integration |
| 178 | INTEGRATE-PL-013 | PL-013 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-013-plan.md` | pending_integration |
| 179 | INTEGRATE-UP-002 | UP-002 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-002-plan.md` | pending_integration |
| 180 | INTEGRATE-UP-004 | UP-004 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-004-plan.md` | pending_integration |
| 181 | INTEGRATE-UP-006 | UP-006 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-006-plan.md` | pending_integration |
| 182 | INTEGRATE-UP-009 | UP-009 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-009-plan.md` | pending_integration |
| 183 | INTEGRATE-UP-010 | UP-010 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-010-plan.md` | pending_integration |
| 184 | INTEGRATE-UP-011 | UP-011 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-011-plan.md` | pending_integration |
| 185 | INTEGRATE-UP-014 | UP-014 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-UP-014-plan.md` | pending_integration |
| 186 | INTEGRATE-SV-012 | SV-012 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-012-plan.md` | pending_integration |
| 187 | INTEGRATE-SV-014 | SV-014 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-014-plan.md` | pending_integration |
| 188 | INTEGRATE-SV-015 | SV-015 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-015-plan.md` | pending_integration |
| 189 | INTEGRATE-OB-001 | OB-001 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-001-plan.md` | pending_integration |
| 190 | INTEGRATE-OB-003 | OB-003 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-003-plan.md` | pending_integration |
| 191 | INTEGRATE-OB-005 | OB-005 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-005-plan.md` | pending_integration |
| 192 | INTEGRATE-OB-010 | OB-010 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-010-plan.md` | pending_integration |
| 193 | INTEGRATE-ST-004 | ST-004 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-004-plan.md` | pending_integration |
| 194 | INTEGRATE-ST-009 | ST-009 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-009-plan.md` | pending_integration |
| 195 | INTEGRATE-ST-010 | ST-010 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-010-plan.md` | pending_integration |
| 196 | INTEGRATE-ST-012 | ST-012 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-012-plan.md` | pending_integration |
| 197 | INTEGRATE-ST-015 | ST-015 | P1 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-015-plan.md` | pending_integration |
| 198 | INTEGRATE-DE-018 | DE-018 | P2 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-DE-018-plan.md` | pending_integration |
| 199 | INTEGRATE-IR-020 | IR-020 | P2 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-IR-020-plan.md` | pending_integration |
| 200 | INTEGRATE-OB-009 | OB-009 | P2 | `Private_group_chat_reliability_test_matrix_full_with_rules-session-OB-009-plan.md` | pending_integration |

## Ordered Session Breakdown

Run sessions in the Session Ledger order. Each table row is the ordered session entry for that completed worktree row.

For each `INTEGRATE-R` session:

- intended plan file: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-to-COMPLETE_1-integration-session-R-plan.md`
- exact scope: integrate only row-owned meaningful changes from worktree row `R` into main, or skip if already present.
- row ownership: code, tests, and docs are owned only after the session identifies the exact changed-file inventory from the worktree row and plan file.
- COMPLETE_1 compatibility: inspect the known overlap map first when `R` appears there; otherwise search COMPLETE_1 by scenario, changed files, test names, and row-family proof surface.
- required tests: the row's focused worktree tests from its plan plus any affected COMPLETE_1 tests or named gates touched by shared files.
- docs to update when executed: this integration ledger row, the row's integration plan, and any relevant row crosswalk/test-inventory note only if the execution changes main truth.

## Downstream Execution Path

1. Create the row-specific integration plan for the next pending row.
2. Complete intake before any code edit: worktree row, worktree plan, exact changed-file inventory, COMPLETE_1 overlap/conflict map.
3. Integrate only the row-owned delta, or prove it is already present.
4. Run the row-focused test set and affected COMPLETE_1 tests.
5. Update the Session Ledger status to `accepted`, `skipped_already_present`, or `blocked_conflict` with exact files and test evidence.
6. Continue to the next pending row.

No implementation work is part of this artifact.
