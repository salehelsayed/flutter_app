# INTEGRATE-ST-012 Plan - Standard Integration Contract

Status: accepted

## Scope

Import and verify historical row `ST-012`: "Topic subscription leak test after many churn cycles."

This was standard worktree-to-main integration, not gap-closure. The historical source plan and closure evidence stayed the source of truth; no original implementation plan was regenerated.

## Source Evidence

- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-012-plan.md`.
- Source row-owned proof selector:
  - `cd go-mknoon && go test ./node -run TestST012 -count=1`
- Source 3-party E2E: `N/A`.

## Imported Delta

- Imported the row-owned native many-cycle churn selector proving repeated join/leave cycles remove all topic, subscription, config, key, subscription-context, and discovery-context runtime entries, and that the final re-add topic remains publishable.
- Imported the row-owned local multi-node churn selector proving Charlie receives no removed-window deliveries across repeated leave/rejoin cycles, each re-add delivery arrives exactly once through the active subscription, and Charlie can publish after the final active re-add.

## Verification

Passed:

- `go test ./node -run TestST012 -count=1` from `go-mknoon`
- `gofmt -w go-mknoon/node/pubsub_test.go go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`
- `gofmt -l go-mknoon/node/pubsub_test.go go-mknoon/node/pubsub_unsubscribe_exit_paths_test.go`
- `git diff --check`

## Verdict

`accepted`

ST-012 is imported and verified. The integration stayed limited to row-owned native topic-subscription churn proof artifacts. Existing blocked rows remain unchanged.
