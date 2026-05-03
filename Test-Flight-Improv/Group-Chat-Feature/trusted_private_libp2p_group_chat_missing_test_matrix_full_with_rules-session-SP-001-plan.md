# SP-001 Session Plan - Peer authentication and request authorization cover every protocol

Status: accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T10:37:00+02:00 | Local planner completed | SP-001 source matrix row; ordered-session SP-001 row; `go-mknoon/node/pubsub.go`; `go-mknoon/node/protocol_version_test.go`; `go-relay-server/inbox.go`; `go-relay-server/media.go`; `go-relay-server/rendezvous.go`; relay inbox/media tests | Current evidence covers secure libp2p channel setup, PubSub member/signature validation, and media recipient ACLs. Relay group inbox remains an implementation-owned gap because `group_store` can trust caller-supplied `from`, and `group_retrieve` / `group_retrieve_cursor` can return group replay messages to any authenticated peer that knows the group id. | Patch group inbox relay auth, add raw-protocol tests, then close SP-001 only if direct Go gates pass and docs record concrete evidence. |

## Execution Progress

| timestamp | role | files inspected or updated | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T10:54:00+02:00 | Local executor completed | `go-relay-server/inbox.go`; `go-relay-server/group_inbox_store.go`; `go-relay-server/backend_memory.go`; `go-relay-server/backend_redis.go`; `go-relay-server/inbox_test.go` | Implemented authenticated relay group inbox request authorization: `group_store` now rejects spoofed `from` identities and empty recipient ACLs, stores normalized per-message recipients, and retrieve/cursor responses are filtered to the sender or stored recipients. | Run focused relay and node gates. |
| 2026-05-01T11:03:00+02:00 | Local verifier completed | relay group inbox/media tests; Go node protocol/PubSub/group/security gate; `go-mknoon/node/pubsub_delivery_test.go`; `git diff --check` | Relay gate passed. First node gate exposed a stale test fixture using sender id `sender-zero` under strict sender/transport binding; same-session recovery updated the fixture to use `n.PeerId()`, and the rerun passed. | Update source matrix, inventory, and session ledger to `Covered`/accepted. |

## real scope

SP-001 asks that peer authentication and request authorization cover invite, sync, media, receipt, key, diagnostics, and relay request surfaces. This session covers the repo-owned request protocols that currently exist in this codebase:

- PubSub group envelopes, including system event families such as membership, metadata, key rotation, and diagnostics-like validation events
- relay group inbox store/retrieve/retrieve-cursor replay requests
- relay media upload/download/delete/list recipient ACLs
- secure libp2p protocol negotiation before any mknoon stream

## closure bar

SP-001 can be resolved when direct code and tests prove:

- `group_store` binds sender identity to the authenticated libp2p remote peer
- group replay messages are stored with a recipient ACL derived from the caller's current group fanout
- `group_retrieve` and `group_retrieve_cursor` only return messages to the sender or stored recipients
- unauthorized relay retrieve attempts return no group messages and do not delete or mutate authorized messages
- existing PubSub and media authorization tests still pass

## session classification

`needs_code_and_tests`, reclassified from evidence-gated because the relay group inbox proof exposed a row-owned implementation gap.

## Device/Relay Proof Profile

- Profile for this session: host-only Go/raw-protocol proof.
- The row mentions relay proof, but the needed relay auth behavior is covered by local libp2p stream tests against in-process relay hosts.
- Real device, simulator, packet-capture, and live relay proof are supplemental for this row because the repo-owned request authorization contract can be proved by raw Go protocol tests.

## files expected to change

- `go-relay-server/inbox.go`
- `go-relay-server/backend_memory.go`
- `go-relay-server/backend_redis.go`
- `go-relay-server/group_inbox_store.go`
- `go-relay-server/inbox_test.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- SP-001 closure docs after tests pass

## exact tests and gates run

- `cd go-relay-server && go test ./... -run 'GroupInbox|HandleInboxStream|Unauthorized|RedisGroupInbox|TwoRelayServers_SharedGroupInbox' -count=1` passed.
- `cd go-mknoon && go test ./node -run 'Protocol|PubSub|Group|Security' -v -count=1` first failed only in `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` with strict `peer_mismatch` after the test used non-node sender id `sender-zero`.
- `cd go-mknoon && go test ./node -run 'TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers|Protocol|PubSub|Group|Security' -v -count=1` passed after same-session fixture recovery.
- `git diff --check` passed.

## Recovery Input

- Failed command: `cd go-mknoon && go test ./node -run 'Protocol|PubSub|Group|Security' -v -count=1`.
- Failure: `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` used `senderPeerId := "sender-zero"` and now correctly hit `peer_mismatch` under the strict PubSub transport-peer binding already required by this rollout.
- Blocker class: implementation-owned/current-row stale test contract, not a production regression.
- Recovery edit: `go-mknoon/node/pubsub_delivery_test.go` now uses `senderPeerId := n.PeerId()` so the zero-peer publish test still verifies zero peer count without violating the authenticated sender contract.
- Recovery gate: `cd go-mknoon && go test ./node -run 'TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers|Protocol|PubSub|Group|Security' -v -count=1` passed.

## scope guard

Do not add a new group membership authority to the relay. The relay can enforce the authenticated transport peer, caller-supplied recipient ACL, and stored per-message ACL. Full authoritative group-state validation across live membership epochs remains outside the current relay data model unless a separate signed group-state control-plane row introduces that state.

## Final Execution Verdict

`accepted`: SP-001 is covered for the shipped repo-owned protocol surfaces. Relay group inbox requests now authenticate the transport peer, reject spoofed sender identity and empty recipient ACLs, persist message ACLs, and filter replay retrieval to authorized sender/recipient peers. Existing Go node and relay media proofs cover secure libp2p protocol negotiation, PubSub sender/member/signature/system-event authorization, and media ACL rejection. No unresolved SP-001 implementation blocker remains; a live authoritative relay group-state control plane is outside the current relay data model and remains separate scope.
