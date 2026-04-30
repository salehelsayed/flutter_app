# EK-002 Application-Layer Storage Privacy Plan

## Real Scope

EK-002 owns row-specific proof that relay, mailbox, and stored sync paths carry opaque encrypted group payloads rather than readable group content, media keys, invite secrets, or private group state.

This is a privacy-evidence session. It may add focused Go or Dart tests and docs, but it must not redesign transport security, app-layer signatures, epoch repair, secure storage, or broad relay architecture.

## Closure Bar

Move EK-002 from `Partial` to `Covered` only if current repo tests prove:

- live relay-visible group PubSub envelopes contain only v3 envelope metadata plus `encrypted.ciphertext` and `encrypted.nonce`, without plaintext group message content, media keys, invite secrets, or private group state.
- group mailbox or inbox-store requests preserve an opaque encrypted replay envelope and do not expose plaintext content or secrets to relay-visible request JSON.
- durable offline or retry sync payloads that are submitted to mailbox/storage paths are encrypted envelopes, not decoded plaintext payloads.
- safe push preview metadata remains intentionally minimal and does not carry the protected secret fragments.

If any storage path still submits plaintext group content, group key material, media keys, invite secrets, or private state to relay/mailbox/sync storage, leave EK-002 `Partial` or `blocked` with exact missing evidence.

## Source Of Truth

- Source matrix: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- Session breakdown: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- Test inventory: `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- Go group envelope and node tests: `go-mknoon/internal/group_envelope_test.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/node/group_inbox_test.go`
- Flutter group send, inbox retry, drain, onboarding, and removal tests: `test/features/groups/**`

Current code/tests beat stale matrix prose. Test output is the execution source of truth for this row.

## Session Classification

`implementation-ready`.

Reason: EK-002 is `Partial` and current evidence already proves important encrypted-envelope boundaries, but the row needs a single EK-002-owned storage-path privacy proof that ties relay-visible live, mailbox, and stored/retry sync payloads together. Add focused tests only where the current proof is missing.

## Exact Problem Statement

The row asks whether infrastructure peers that store or relay group traffic can inspect protected group data. Existing tests prove encrypted wire envelopes exist, but the source row remains Partial because the proof is spread across adjacent protocol, inbox, media, and replay tests and does not yet close the full relay/mailbox/stored-sync path contract for EK-002.

## Files And Repos To Inspect Next

- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/group_inbox_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/internal/group_envelope.go`
- `go-mknoon/internal/group_envelope_test.go`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`

## Existing Evidence To Reuse

- `go-mknoon/node/pubsub_test.go` includes relay-visible envelope tests around plaintext omission and decryptable encrypted payloads.
- `go-mknoon/node/group_inbox_test.go` includes `TestBuildGroupInboxStoreRequest_PreservesOpaqueReplayEnvelope`, proving inbox-store request JSON preserves the encrypted replay envelope and omits sensitive plaintext fragments.
- Flutter group media and replay tests added by prior rows prove encrypted descriptors and replay paths, but EK-002 must only cite the portions that prove infrastructure-visible payloads stay opaque.

## Regression / Tests To Add First

Add the smallest focused proof needed after inspecting the current tests. Prefer extending existing tests rather than introducing a new abstraction.

Recommended target:

1. Add or extend a Dart test around pending inbox-store retry/offline sync payloads to assert the persisted retry payload and replay submission remain encrypted envelopes and do not contain protected fragments such as message body, media key, invite secret, or history/private-state text.
2. If Go live PubSub and Go inbox-store tests already prove relay/mailbox opacity, do not duplicate them; cite them in the execution evidence.
3. Keep push title/body expectations explicit: generic safe preview text is acceptable, protected content fragments are not.

## Step-By-Step Implementation Plan

1. Snapshot `git status --short`.
2. Inspect the current Go PubSub and group inbox opacity tests.
3. Inspect Flutter send/offline retry/replay tests for persisted storage-path payload assertions.
4. Add a focused missing test only for the storage path that lacks EK-002-specific proof.
5. Run the focused EK-002 Go and Dart suites.
6. Run the broader adjacent groups or Go security/protocol slice only if focused tests pass.
7. Update the source matrix EK-002 row to `Covered` only if all three proof surfaces are covered.
8. Add EK-002 evidence to `test-inventory.md`.
9. Update the breakdown status, closure log, closure ledger, and ordered session row.
10. Run `./scripts/run_test_gates.sh completeness-check` and `git diff --check`.

## Exact Tests And Gates To Run

Focused Go:

```bash
cd go-mknoon && go test ./node -run 'TestPublishGroupMessage_RelayVisibleEnvelopeOmitsPlaintext|TestPublishGroupReaction_RelayVisibleEnvelopeOmitsPlaintext|TestBuildGroupInboxStoreRequest_PreservesOpaqueReplayEnvelope|TestGroupProtocolInboxStoreUsesVersionedInboxProtocol' -v
```

Focused Dart, adjust to the final touched tests:

```bash
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
```

Broader adjacent gate:

```bash
./scripts/run_test_gates.sh groups
```

Docs/gates:

```bash
./scripts/run_test_gates.sh completeness-check
git diff --check
```

## Known-Failure Interpretation

- A protected fragment appearing in relay-visible PubSub, inbox-store, or persisted retry/sync payload JSON is EK-002-blocking.
- A test that only proves libp2p transport security belongs to EK-001 and does not close EK-002.
- A test that only proves signature failure belongs to EK-004.
- A test that only proves unknown/future epoch behavior belongs to EK-005.
- Device-lab proof is supplemental for EK-002 when the infrastructure-visible storage JSON can be asserted directly in host tests.

## Done Criteria

EK-002 accepted:

- Live relay-visible group envelopes omit protected plaintext/secrets.
- Group inbox/mailbox store requests preserve opaque encrypted replay envelopes and omit protected plaintext/secrets.
- Persisted or retried stored sync/offline payloads remain encrypted envelopes and omit protected plaintext/secrets.
- Safe push preview fields are generic or metadata-minimized and do not include protected fragments.
- Source matrix EK-002 is `Covered` with concrete evidence.
- Test inventory records the row evidence.
- Breakdown ledger records EK-002 accepted with reopen rule.
- `./scripts/run_test_gates.sh completeness-check` and `git diff --check` pass.

EK-002 blocked:

- Any relay/mailbox/sync storage path submits protected plaintext or secret-bearing state.
- The repo lacks a reachable assertion point for one required storage path.
- Source row remains `Partial` with exact missing proof.

## Scope Guard

Do not implement or modify:

- EK-001 transport security
- EK-003 identity binding
- EK-004 signature verification
- EK-005 future epoch repair
- EK-013 secret deletion or secure storage
- media encryption internals already owned by MD rows
- relay persistence architecture or database schema unless a direct plaintext leak is proven and cannot be tested otherwise

## Accepted Differences / Intentionally Out Of Scope

- Raw packet capture is not required when tests assert the exact relay/mailbox request JSON and encrypted envelope body.
- Generic notification preview text is acceptable if it does not include protected content or secrets.
- Push metadata privacy beyond the stored payload body remains owned by NT/SP rows unless it carries protected EK-002 fragments.

## Dependency Impact

EK-004/EK-005/EK-012 may cite EK-002 for encrypted storage-path opacity, but they still need their own signature, epoch, and replay-protection proof.

## Structural Blockers Remaining

None for planning.

## Why The Plan Is Safe To Execute Now

The plan is safe because it narrows EK-002 to observable infrastructure-visible storage payloads, reuses existing encryption-envelope tests, and only adds focused assertions for missing storage-path evidence.

## Execution Evidence

Execution fallback: local controller completed EK-002 execution after the spawned execution agent timed out without leaving trustworthy current-session execution evidence.

Implemented test:

- Added `EK-002 pending inbox retry stores encrypted replay without protected plaintext` to `test/features/groups/application/send_group_message_use_case_test.dart`.
- The test uses `_OpaqueReplayInboxStoreFailBridge`, which returns opaque `group.encrypt` ciphertext while forcing `group:inboxStore` failure so the relay-bound retry payload remains persisted for inspection.
- The test proves pending inbox retry JSON and the attempted `group:inboxStore` command both carry a `group_offline_replay` encrypted envelope and omit protected text, invite/private-state fragments, and media encryption key material. It also confirms no plaintext push preview fields are present.

Existing evidence reused:

- `go-mknoon/node/pubsub_test.go` proves live relay-visible group message and reaction envelopes omit protected plaintext while remaining decryptable by the group key.
- `go-mknoon/node/group_inbox_test.go` proves group inbox-store request JSON preserves an opaque encrypted replay envelope and omits sensitive plaintext fragments.
- `go-mknoon/node/protocol_version_test.go` keeps `GroupInboxStore` on the versioned `InboxProtocol`.

Verification:

```bash
cd go-mknoon && go test ./node -run 'TestGroupRelayVisibleMessageEnvelope_EncryptsContentBeforeRelay|TestGroupRelayVisibleReactionEnvelope_EncryptsContentBeforeRelay|TestBuildGroupInboxStoreRequest_PreservesOpaqueReplayEnvelope|TestGroupProtocolInboxStoreUsesVersionedInboxProtocol' -v
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "EK-002 pending inbox retry stores encrypted replay without protected plaintext"
flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
./scripts/run_test_gates.sh groups
```

All commands passed.

Execution verdict: accepted pending closure.
