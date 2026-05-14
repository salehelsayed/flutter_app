# GK-033 Session Plan: Reaction Epoch And Device Validation

Status: accepted/closed

Source breakdown: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`
Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GK-033`

## Planning Progress

| Timestamp | Role | Files inspected since last update | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-05-12 21:09:13 CEST | Evidence Collector started | Source matrix GK-033 row; breakdown row 81; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_decryption_failure_test.go`; `go-mknoon/node/pubsub_key_rotation_grace_test.go` | Source row GK-033 is `Open`, marked evidence-gated, and the plan file was missing. Existing production routes `group_reaction` envelopes through the same `groupTopicValidator` member, active-device, transport-peer, signature, and key-epoch checks as `group_message`, but there is no exact row-owned GK-033 proof. | Add exact pure validator and live PubSub tests for reaction current-epoch acceptance, stale-epoch rejection, and revoked-device rejection. |
| 2026-05-12 21:09:13 CEST | Reviewer completed | Same files plus reaction dispatch and raw-publish helpers | GK-033 is currently a proof gap unless the exact tests expose different behavior. Keep production unchanged unless a row-owned failure appears. Use live raw-publish rejection evidence so reactions cannot bypass removal or key epoch at validator time. | Add tests, run focused/adjacent/broader/race Go gates, then close the row with evidence or reclassify if code is needed. |

## Real Scope

GK-033 owns only proof that `group_reaction` envelopes use the same epoch, member, active-device, transport-peer, and signature validation as group messages. It may add Go node test helpers and exact node tests. It must not change reaction payload schema, message payload parsing, encryption/signature formats, key-rotation policy, publish APIs, Flutter UI, replay entitlement, or relay behavior unless exact GK-033 proof fails.

## Required Implementation

1. Prove a valid current-epoch active-device `group_reaction` envelope validates and emits `group_reaction:received`.
2. Prove a previous-epoch `group_reaction` after grace expiry rejects as `bad_signature_or_epoch` and emits no reaction/message/decrypt side effects.
3. Prove a revoked-device `group_reaction` rejects as `unbound_device` and emits no reaction/message/decrypt side effects.
4. Keep the reaction payload parser behavior from GK-025 intact.
5. Leave production unchanged if existing validator behavior satisfies the row.

## Required Evidence

| Evidence | Command |
| --- | --- |
| Focused GK-033 regression | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGK033')` |
| Adjacent reaction/security coverage | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GK025|GK033|GroupReaction|Reaction|ValidationReject|Unbound|BadSignature')` |
| Broader Go node/internal/crypto selector | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator|GroupEnvelope|GroupReaction|GroupMessage|BadSignature|Unbound|GK033')` |
| Race check for live PubSub evidence | `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGK033|GroupReaction|ValidationReject')` |
| Formatting and whitespace | `gofmt -w go-mknoon/node/pubsub_test.go go-mknoon/node/pubsub_decryption_failure_test.go`; `git diff --check` |

## Done Criteria

- Source matrix GK-033 can move to `Covered` only after concrete file/test/gate evidence is recorded.
- Reactions from active current-epoch members emit once.
- Stale-epoch reactions after grace expiry are rejected before receive/decrypt side effects.
- Revoked-device reactions are rejected before receive/decrypt side effects.
- Residual work, if any, must be outside GK-033 row ownership and must not hide an unresolved repo-owned blocker.

## Execution Progress

| Timestamp | Phase | Files inspected or touched | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-05-12 21:09:13 CEST | Contract extracted | `Private_group_chat_reliability_test_matrix_COMPLETE_1-session-GK-033-plan.md`; `go-mknoon/node/pubsub.go`; `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_decryption_failure_test.go` | Execute GK-033 locally in the controller. Existing production appears to share validator behavior between messages and reactions, so start with exact tests and do not change code unless proof fails. | Add exact pure and live reaction epoch/device validation tests, then run required Go gates. |
| 2026-05-12 21:15:06 CEST | Executor completed | `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_decryption_failure_test.go` | Added `buildTestDeviceEnvelopeWithPlaintext`, a pure GK-033 validator test for current active-device acceptance, expired previous-epoch rejection, and revoked-device rejection, plus a live PubSub test proving current reactions receive while stale-epoch and revoked-device raw publishes emit validation rejects and no receive/decrypt side effects. No production code changed. | Record gate evidence and close GK-033. |
| 2026-05-12 21:15:06 CEST | QA completed | Same files plus `go-mknoon/node/pubsub.go` validator/dispatch path | Required evidence passed: focused, adjacent, broader node/internal/crypto, race, gofmt, and diff hygiene. The row is satisfied by existing shared reaction/message envelope validation plus exact tests. | Close GK-033 as Covered in source matrix and breakdown. |

## Evidence Captured

| Evidence | Result |
|---|---|
| Focused GK-033 regression | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'TestGK033')` -> `ok node 5.778s` |
| Adjacent reaction/security coverage | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node -run 'GK025\|GK033\|GroupReaction\|Reaction\|ValidationReject\|Unbound\|BadSignature')` -> `ok node 11.415s` |
| Broader Go node/internal/crypto selector | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test ./node ./internal ./crypto -run 'GroupTopicValidator\|GroupEnvelope\|GroupReaction\|GroupMessage\|BadSignature\|Unbound\|GK033')` -> `ok node 10.159s`, `ok internal 0.572s`, `ok crypto 0.309s` |
| Race check for live PubSub evidence | Pass: `(cd go-mknoon && GOCACHE=/private/tmp/codex-go-build-cache go test -race ./node -run 'TestGK033\|GroupReaction\|ValidationReject')` -> `ok node 7.872s` |
| Formatting and whitespace | Pass: `gofmt -w go-mknoon/node/pubsub_test.go go-mknoon/node/pubsub_decryption_failure_test.go`; `git diff --check` |

## Final Verdict

Final verdict: accepted

Spawned-agent isolation used: no.

Local sequential fallback used: yes.

Files changed: `go-mknoon/node/pubsub_test.go`; `go-mknoon/node/pubsub_decryption_failure_test.go`; this GK-033 plan.

Tests added or updated: `buildTestDeviceEnvelopeWithPlaintext`; `TestGK033ValidateGroupReactionUsesMessageEpochAndDeviceValidation`; `TestGK033GroupReactionRejectsStaleEpochAndRevokedDeviceWithoutReceive`.

Blocking issues remaining: none.

Non-blocking follow-ups deferred: none.

Why safe to consider complete: exact pure and live Go node proof shows reactions share the same validator path as messages for active device binding and key epoch policy; invalid stale/revoked reactions are rejected before receive/decrypt side effects, and all required gates passed.

## Closure Note

Controller closure recorded at 2026-05-12 21:15 CEST. The source matrix GK-033 row and breakdown GK-033 inventory, disposition, closure ledger, session ledger, and ordered session row are now `Covered`/`covered/accepted` with concrete tests and gate evidence from this plan. No blockers or follow-ups remain. GA-001 is covered separately and GA-002 is covered separately and GA-003 is covered separately and GP-005 remains the next unresolved P0 row, and no final program verdict was written.
