# EK-001 Secure Libp2p Channel Requirement Plan

## Real Scope

EK-001 owns the transport-security precondition for group protocol traffic. This session should prove that mknoon's Go libp2p hosts do not accept insecure/no-security peers before any mknoon protocol stream or group PubSub traffic can be exchanged.

This is a narrow Go-side proof session. It may add focused Go tests and documentation, but it must not redesign transports, change relay behavior, or modify app-layer group encryption.

## Closure Bar

Move source row EK-001 from `Open` to `Covered` only if current tests prove:

- mknoon production `Node.Start` hosts use secure libp2p defaults and do not opt into `libp2p.NoSecurity`.
- a deliberately insecure libp2p host cannot establish a transport connection to a mknoon node.
- because the connection is rejected before protocol negotiation, mknoon protocol streams such as chat/inbox/media and group PubSub cannot exchange payloads over the insecure channel.
- the failure happens before any group plaintext or group secret is handed to protocol handlers.

If the repo cannot instantiate an insecure peer or cannot directly prove the negative path, leave EK-001 `Partial` or `blocked` with the exact missing proof.

## Source Of Truth

- Source matrix: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- Session breakdown: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- Test inventory: `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- Go node code: `go-mknoon/node/node.go`
- Existing protocol tests: `go-mknoon/node/protocol_version_test.go`
- Existing harness helpers: `go-mknoon/node/multi_relay_test.go` and `go-mknoon/node/group_security_harness_test.go`

Current code/tests beat stale prose. `go test` output is the execution source of truth for this row.

## Session Classification

`implementation-ready`.

Reason: current code appears to rely on go-libp2p secure defaults, but EK-001 is still `Open` and no row-specific test proves insecure/no-security peers are rejected before mknoon group protocol exchange.

## Exact Problem Statement

The row asks for proof that insecure libp2p channels cannot exchange group protocol messages. `node.Start` creates a production libp2p host without `libp2p.NoSecurity`, so go-libp2p defaults should require secure transport negotiation. However the source matrix has no concrete EK-001 evidence, and existing tests focus on protocol version negotiation, encrypted payloads, and group envelope validation rather than transport security downgrade rejection.

## Files And Repos To Inspect Next

- `go-mknoon/node/node.go`
- `go-mknoon/node/protocol_version_test.go`
- `go-mknoon/node/multi_relay_test.go`
- `go-mknoon/node/group_security_harness_test.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/group_inbox_test.go`
- `go-mknoon/go.mod`

## Existing Tests Covering This Area

- `protocol_version_test.go` proves current mknoon protocol IDs are versioned, current chat stream negotiation works between mknoon secure nodes, unsupported chat protocol versions are rejected, and group inbox store uses `InboxProtocol`.
- Group security tests prove app-layer encrypted group envelopes fail closed on wrong keys, tampering, and parse errors.
- LP-007 and MD-004 evidence proves app-layer group content/media encryption, but that is not the same as EK-001 transport-security proof.

Missing:

- A negative test using `libp2p.NoSecurity`.
- A positive control showing two production mknoon secure nodes can still negotiate the representative protocol.
- Documentation in the source matrix/inventory that insecure rejection occurs before mknoon protocol payload exchange.

## Regression / Tests To Add First

Add a focused Go test, preferably in `go-mknoon/node/protocol_version_test.go` or a new `go-mknoon/node/secure_channel_test.go`, that:

1. Starts a production mknoon node with `startLocalNodeForMultiRelayTest`.
2. Starts a deliberately insecure libp2p host with `libp2p.NoSecurity`.
3. Attempts to connect the insecure host to the production mknoon node's peer ID and addresses.
4. Requires the connect or stream-open attempt to fail.
5. Asserts no connection remains from the insecure host to the mknoon peer.
6. Keeps the test payload-free, proving failure occurs before any group message, invite, media descriptor, or sync payload can be exchanged.
7. Keeps an existing secure-to-secure positive control green through `TestGroupProtocolChatStreamNegotiatesCurrentVersionOnly`.

## Step-By-Step Implementation Plan

1. Snapshot `git status --short`.
2. Add the EK-001 negative test in the Go node package.
3. Run the focused new test by name.
4. Run adjacent protocol tests:
   - current chat protocol negotiation
   - versioned protocol IDs
   - inbox protocol store
5. Run the broader Go node protocol/security slice if the focused tests pass.
6. Update the source matrix EK-001 row to `Covered` only if the focused negative test and adjacent protocol tests pass.
7. Add EK-001 evidence to `test-inventory.md`.
8. Update the breakdown status, closure log, closure ledger, and ordered session row.
9. Run `./scripts/run_test_gates.sh completeness-check` and `git diff --check`.

## Risks And Edge Cases

- A test that only checks app-layer encryption would not close EK-001; it must exercise libp2p transport security negotiation.
- A test that uses two production nodes only proves the positive path, not downgrade rejection.
- If `libp2p.NoSecurity` can still connect due an unexpected default or test harness mismatch, stop and reclassify the session; do not paper over the gap.
- Do not log or send a real group secret in the negative test.

## Exact Tests And Gates To Run

Focused:

```bash
cd go-mknoon && go test ./node -run 'TestSecureLibp2pChannelRequiredBeforeMknoonProtocols|TestGroupProtocolChatStreamNegotiatesCurrentVersionOnly|TestGroupProtocolIDs_AreVersionedCurrentContracts|TestGroupProtocolInboxStoreUsesVersionedInboxProtocol' -v
```

Broader adjacent Go slice:

```bash
cd go-mknoon && go test ./node -run 'Secure|Protocol|GroupTopicValidator|GroupRelayVisible|GroupInboxStore' -v
```

Docs/gates:

```bash
./scripts/run_test_gates.sh completeness-check
git diff --check
```

## Known-Failure Interpretation

- A failure in the new insecure-host test is EK-001-blocking.
- A failure in unrelated dirty-tree Flutter tests is outside EK-001 unless it involves secure-channel preconditions.
- Go integration tests requiring build tags or external relays are not required for this host-level security proof unless the direct Go node test cannot exercise the downgrade path.

## Done Criteria

EK-001 accepted:

- New focused Go test proves insecure/no-security host cannot connect or open mknoon protocol streams to a production mknoon node.
- Adjacent protocol tests still pass.
- Source matrix EK-001 is `Covered` with concrete evidence.
- Test inventory records the row evidence.
- Breakdown ledger records EK-001 accepted with reopen rule.
- `./scripts/run_test_gates.sh completeness-check` and `git diff --check` pass.

EK-001 blocked:

- The repo cannot exercise the insecure-host negative path, or the negative path fails.
- Source row remains `Open` or becomes `Partial` with exact missing proof.
- Breakdown and inventory record the blocker truthfully.

## Scope Guard

Do not implement or modify:

- app-layer encryption rows EK-002, EK-004, EK-005, EK-012, or EK-013
- media rows MD-001 through MD-014
- relay-visible privacy rows such as LP-007 or OS-005
- broad libp2p transport redesign
- relay address management, AutoRelay, or hole-punching behavior
- Flutter UI or database code

## Accepted Differences / Intentionally Out Of Scope

- The proof can be host-level and payload-free because the closure bar is that insecure transport fails before mknoon protocol negotiation.
- Raw packet capture is not required when the negative transport negotiation test proves no mknoon stream opens.
- Safe logging is satisfied by rejecting before group payload submission; no payload or secret should be introduced solely for log inspection.

## Dependency Impact

EK-002 and later app-layer encryption/signature rows may rely on EK-001 to establish the transport precondition, but they must still prove their own payload/cryptographic behavior.

## Reviewer Pass

Reviewer verdict: sufficient as implementation-ready.

The plan names the precise missing proof, a narrow negative test, adjacent positive controls, exact commands, and the source docs to update. It avoids broad transport redesign and does not conflate transport security with app-layer encryption.

## Arbiter Pass

Structural blockers: none.

Incremental details:

- If the new test lands in a new file, keep it in package `node` so it can reuse local helpers.
- If `Connect` fails before `NewStream`, that is acceptable proof; assert no connection remains.

Accepted differences:

- Device-lab proof is not required for this row when the Go host-level security negotiation can be tested directly.

## Structural Blockers Remaining

None for planning.

## Exact Docs/Files Used As Evidence

- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `go-mknoon/node/node.go`
- `go-mknoon/node/protocol_version_test.go`
- `go-mknoon/node/multi_relay_test.go`
- `Test-Flight-Improv/test-gate-definitions.md`

## Why The Plan Is Safe To Execute Now

The plan is safe because it adds a focused negative transport-security proof at the Go host boundary, keeps the test payload-free, preserves existing protocol positive controls, and limits acceptance to concrete test evidence rather than relying on assumptions about go-libp2p defaults.

## Execution Evidence

Execution fallback: local controller completed EK-001 execution after the spawned execution agent timed out without leaving trustworthy execution evidence.

Implemented test:

- Added `TestSecureLibp2pChannelRequiredBeforeMknoonProtocols` to `go-mknoon/node/protocol_version_test.go`.
- The test starts a production mknoon node through `Node.Start`, starts a deliberately insecure `libp2p.NoSecurity` host, filters the mknoon node to its raw TCP address, and proves the insecure host cannot connect or open `ChatProtocol`.
- The test also asserts neither side retains a connected insecure peer. It sends no group payload, invite, media descriptor, key material, or sync data, so the proof is strictly before mknoon protocol exchange.

Execution note:

- An initial broad-address version of the test attempted every advertised address and was too broad for EK-001 because advertised QUIC/WebTransport-style addresses can provide transport-level security outside the raw TCP/no-security negotiation being proven. The final test targets raw TCP specifically.

Verification:

```bash
cd go-mknoon && go test ./node -run 'TestSecureLibp2pChannelRequiredBeforeMknoonProtocols|TestGroupProtocolChatStreamNegotiatesCurrentVersionOnly|TestGroupProtocolIDs_AreVersionedCurrentContracts|TestGroupProtocolInboxStoreUsesVersionedInboxProtocol' -v
cd go-mknoon && go test ./node -run 'Secure|Protocol|GroupTopicValidator|GroupRelayVisible|GroupInboxStore' -v
```

Both commands passed.

Execution verdict: accepted pending closure.
