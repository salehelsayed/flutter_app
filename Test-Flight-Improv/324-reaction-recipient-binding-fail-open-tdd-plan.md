# 324 - Relay: group-reaction recipient binding fails open

Status: execution-ready (NOT executed — queued behind plans 322 and 323 by user decision 2026-08-02)
Type: Bug (security hardening — latent, no current user impact)
Spec: free-text intent — found during plan 323 grounding; recorded at `323-…` Deferred/accepted difference
Classification: implementation-ready
Closure tier: relay (Go host tests + production deploy to v1.7.6)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-02 | Evidence Collector | `reaction_push.go`, `inbox.go`, `send_group_reaction_use_case.dart` | Fail-open confirmed; honest clients never reach it | Establish blast radius before choosing fix shape |
| 2026-08-02 | Planner | `canonicalGroupReactionPeerIDs`, `parseGroupReactionPeerIDs` | Both sides canonicalize identically ⇒ reject-on-mismatch is safe but destructive; prefer signed-set fallback | Emit contract |

## Problem And Evidence

- **Behavior to improve:** the relay's group-reaction recipient ACL is not bound to the cryptographically signed recipient set. A sender device can store its own byte-identical reaction envelope with an arbitrary **wider** `recipientPeerIds` and the relay will grant those extra peers durable custody of the reaction ciphertext.
- **Impact:** latent. No shipping client can trigger it (see below), so there is **no current user impact** — this is hardening against a modified or compromised sender client, not a live defect. Recorded honestly so it is not sold as a user-facing fix.
- **Confirmed root cause:** the request-vs-signed comparison and envelope *validity* share one boolean.
  - `reaction_push.go:192-196` — when `requestRecipientPeerIDs != nil` and the canonicalized request set differs from the signed `replayRecipients`, the extractor returns `valid=false`.
  - `inbox.go:1602-1616` — the signed-set override is gated on `recognizedReaction && validReaction`:
    ```go
    if recognizedReaction && validReaction {
        normalizedRecipients = append([]string(nil), reaction.ReplayRecipientTransportPeerIDs...)
    }
    result, err := s.store(groupId, from, message, normalizedRecipients)
    ```
    So a mismatch **skips** the override and the client-supplied set reaches `s.store` at `:1616`. The check meant to *reject* a mismatch instead *disables the binding that constrains it*.
  - `extractMessageId` calls the extractor with `nil` request recipients (`inbox.go:1234`), so the dedupe key still resolves to `transitionId` and the store lands on the **merge** branch rather than erroring — `mergePeerIds` (`inbox.go:2012-2033`) unions the extra peers in, applied at `backend_redis.go:637-640` / `backend_memory.go:373-376`. The union is monotone; custody cannot be taken back before TTL.
- **Why no shipping client reaches it:** `send_group_reaction_use_case.dart:376` sends `recipientPeerIds: recipients.replayRecipientTransportPeerIds` — the *same* value embedded in the signed envelope. Both sides then canonicalize through the identical function: the request set via `canonicalGroupReactionPeerIDs` (`reaction_push.go:320-336`; trim, dedupe, sort) and the signed set via `parseGroupReactionPeerIDs` (`:338-359`), which returns the output of that same function at `:351`/`:358`. There is **no canonicalization asymmetry**, so an honest client always compares equal and always takes the override branch.
- **Remaining barrier today:** the client-side entitlement check — `throw GroupOfflineReplaySignatureException('recipient_not_entitled')` (`group_offline_replay_envelope.dart:576-581`) — which is skipped when `expectedRecipientPeerId` is null (`:577`). It is a second line of defense, not the binding itself.
- **Existing coverage:** `group_reaction_push_test.go` covers push construction; no test asserts what `s.store` receives when the request set disagrees with the signed set.
- **Missing coverage:** the mismatch geometry entirely, in both directions.
- **Refuted findings (do NOT re-introduce):** *"reactions cannot be widened at the relay because it always persists the signed set"* — refuted; the override is conditional, and the mismatch path is exactly the one that skips it.
- **Unresolved findings:** none.
- **Affected files:** `go-relay-server/inbox.go`, `go-relay-server/reaction_push.go`, `go-relay-server/group_reaction_push_test.go` (or a new `reaction_recipient_binding_test.go`).

## Graph Grounding Snapshot
- Graph fingerprint / freshness: `a5d1d9254ab1fe95` (arch graph is app-owned Dart; the Go relay is outside it).
- Query / profile: N/A for the Go half — the arch graph does not cover `go-relay-server/`. Grounded by direct source reads, recorded above with exact lines.
- Anchors: `buildGroupReactionPushMessage`, `extractGroupReactionPushMetadata`, `storeGroupInboxMessage`.
- Surfaced proof/gate files: `go-relay-server/group_reaction_push_test.go`, `go-relay-server/inbox_test.go`.
- Graph gaps that required raw source search: all of it (Go is out of graph scope by design).
- Reuse rule: anchors are search starting points; every conclusion is re-verified in current source.

## Scope Contract And Guard

In scope:
- Separate **envelope validity** from **request-set agreement** so a disagreement can never widen the stored ACL.

Must preserve:
- Honest sends are byte-for-byte unaffected → TC-324-01 GREEN sentinel.
- Genuinely malformed / unrecognized reaction envelopes keep today's behavior → TC-324-05 sentinel.
- Notification-recipient subset validation (`reaction_push.go:233`) unchanged → TC-324-06 sentinel.
- The `transitionId` dedupe key and the merge branch unchanged → TC-324-04 sentinel.

Hard `Do not`:
- **Do not reject the store on mismatch.** Rejecting would destroy reaction custody for any client that ever disagreed, converting a latent hardening fix into a live outage vector. The fix must fail *safe*, not *closed*.
- Do not change the ordinary (non-reaction) message lane — it legitimately persists the client-supplied set (`inbox.go:1616` with `recognizedReaction == false`).
- Do not touch the client.

Deferred / accepted difference:
- The client-side `recipient_not_entitled` check is skipped when `selfPeerId` is unresolved (`group_offline_replay_envelope.dart:577`). Out of scope here (client change, and this plan removes the need for it as a primary defense). Owner: notification-reliability wave.

Dependencies:
- Lands **after** plans 322 and 323 (user decision 2026-08-02) so those close host-only with no deploy risk.

## Test Contract
Zero empty cells. All rows are Go host tests (`go test ./...` in `go-relay-server/`).

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-324-01 | An honest store (request set == signed set) is unchanged | `reaction_recipient_binding_test.go::TestHonestReactionStoreUsesSignedRecipients` | Go host / in-memory backend | GREEN sentinel → stored set == signed set, result `Duplicate`/`Stored` as today | make the override unconditional-but-wrong (use request set always) → TC-324-01 still passes ⇒ pair with TC-324-02 | `cd go-relay-server && go test ./... -run ReactionRecipientBinding`; AUTO (Go package) |
| TC-324-02 | A WIDER request set never widens the stored ACL | `reaction_recipient_binding_test.go::TestWiderRequestRecipientsDoNotWidenStoredACL` | Go host / in-memory backend | causal RED (HEAD stores the wider client set) → stored set == signed set exactly | restore the `validReaction` gate on the override → TC-324-02 red | same |
| TC-324-03 | A NARROWER request set also cannot alter the stored ACL | `reaction_recipient_binding_test.go::TestNarrowerRequestRecipientsDoNotNarrowStoredACL` | Go host / in-memory backend | causal RED (HEAD stores the narrower client set, silently dropping custody) → stored set == signed set | same as TC-324-02 | same |
| TC-324-04 | The mismatch path still MERGES rather than erroring (dedupe key unchanged) | `reaction_recipient_binding_test.go::TestMismatchedRequestStillDedupesOnTransitionId` | Go host / in-memory backend, two stores of the same envelope | GREEN sentinel → second store returns `Duplicate`, one record | change `extractMessageId`'s reaction branch → TC-324-04 red | same |
| TC-324-05 | A malformed / unrecognized reaction envelope keeps today's behavior | `reaction_recipient_binding_test.go::TestMalformedReactionEnvelopeUnchanged` | Go host / in-memory backend | GREEN sentinel → client set persisted as today (not a reaction we can bind) | make the fix swallow unrecognized envelopes too → TC-324-05 red | same |
| TC-324-06 | Notification-recipient subset validation is untouched | `group_reaction_push_test.go` (existing subset tests) | Go host | GREEN sentinel → unchanged | widen `groupReactionPeerIDsSubset` → existing test reds | `cd go-relay-server && go test ./...` |
| TC-324-07 | Live production relay still stores reactions after deploy | `docker-ws/verify_reaction_recipient_binding_324.sh` | manual/relay proof against production v1.7.6 | manual proof → one real reaction stored and retrieved by an entitled peer; zero `conflicting group inbox messageId` in logs | N/A — deploy-time verification | run post-deploy inside the 90s stability window |

### Test Notes
- TC-324-02 and TC-324-03 exist as a pair because a fix that simply pins the request set to the signed set in one direction would pass only one of them. Assert the stored set on the backend, not the return value.
- TC-324-01 alone is not sufficient evidence of correctness (an always-use-request-set implementation also passes it) — it is a sentinel, and TC-324-02/03 carry the causal weight.

## Implementation Steps
1. Snapshot `git status --short`. Add TC-324-01..05 first; confirm 02/03 red for the documented reason.
2. In `reaction_push.go`, split the return so a caller can distinguish *"this is a well-formed reaction envelope"* from *"the request set agrees with the signed set"* — e.g. return the metadata with `recognized=true, valid=true` for a well-formed envelope and surface the request-set disagreement separately, rather than collapsing both into `valid=false` at `:194-196`.
3. In `inbox.go:1602-1616`, apply the signed-set override whenever the envelope is a **recognized, well-formed** reaction — regardless of whether the request set agreed. Emit a counter/log line on disagreement so a misbehaving client is observable.
   Stop-if: separating the two conditions requires changing the extractor's contract for any non-reaction caller → stop and replan rather than widening the signature blindly (`extractMessageId` at `:1234` passes `nil` and must keep its current result).
4. No client change. No migration.
5. Run Go host tests → build with the pinned toolchain → deploy v1.7.6 → TC-324-07.

## Risks And Blind Spots
- **Deploy risk is the dominant risk, not code risk.** Production relay has no staging twin (see memory `relay-ec2-deployment`). Mitigated by: backup before upload, `go version` on the built binary, 90s stability window, TC-324-07 live verification.
- Behavior change for honest clients: **none** — proven by the canonicalization analysis above and locked by TC-324-01.
- Sibling-surface consistency: the ordinary-message lane deliberately keeps client-supplied recipients → TC-324-05 plus the untouched `recognizedReaction == false` path.
- Destructive-action side effects: none — the fix only narrows what can be written; it never deletes.
- Invariant re-verification under new transitions: the merge/dedupe branch is re-pinned by TC-324-04.
- Construction/call-site census: `grep -n 'extractGroupReactionPushMetadata' go-relay-server/*.go` → re-derive at execution; `inbox.go:1234` (nil request set) and `:1602` (real request set) are the two known callers.
- Build-artifact provenance: `GOTOOLCHAIN=go1.25.0` pinned; verify `go version <binary>` before upload (deploy contract from plan 320).

## Gate Cadence
- Per-plan closure: TC-324-01..06 Go host + `cd go-relay-server && go test ./...` + TC-324-07 live proof.
- Graph-affected first: N/A — no app-owned Dart file changes, so the arch graph has no dependents to name.
- Full `host-all` is **not** a per-plan gate; no Dart surface changes here at all.
- Shared tests outside the feature/core globs: N/A.

## Acceptance Gates  (literal — copy/paste)
```bash
git status --short

# Causal RED (before the fix) — must FAIL for the documented reason
cd go-relay-server && go test ./... -run TestWiderRequestRecipientsDoNotWidenStoredACL

# Focused GREEN (after the fix) — exit 0
cd go-relay-server && go test ./... -run ReactionRecipientBinding

# Full relay package — exit 0, zero failures
cd go-relay-server && go test ./...

# Build with the pinned toolchain, then PROVE the toolchain in the binary
cd go-relay-server && GOTOOLCHAIN=go1.25.0 GOOS=linux GOARCH=amd64 go build -o relay-server .
go version relay-server        # expect: go1.25.0

# Deploy (backup first; 90s stability window) — see docker-ws/deploy_relay_v175.sh for the shape
# Post-deploy live proof
bash docker-ws/verify_reaction_recipient_binding_324.sh   # expect: stored+retrieved, zero conflicting-messageId

# Hygiene
cd go-relay-server && gofmt -l .     # expect: empty
git diff --check
```

## Execution Interpretation And Done Criteria
- Expected RED: TC-324-02 and TC-324-03 — HEAD stores the client-supplied set when it disagrees with the signed set.
- GREEN sentinel: TC-324-01 (honest path unchanged), TC-324-04 (dedupe/merge intact), TC-324-05 (malformed unchanged), TC-324-06 (notification subset intact).
- Pre-existing dirty tree / known failure: the three user-owned claude-docker files — never staged.
- Environment blocker (NOT a product blocker): none — Go host tests run in-container; the deploy needs the production box.
- Scope drift (BLOCKING): any client change; any change to the ordinary-message recipient lane; any rejection-on-mismatch behavior.

- [ ] Every behavior has a named test or a justified proof.
- [ ] Causal RED, focused GREEN, and representative mutation re-red are recorded.
- [ ] Preservation sentinels and named gates pass with semantic outcomes.
- [ ] Harness registration is implemented AND verified — N/A (Go package, no curated array).
- [ ] Relay deploy proof (TC-324-07) passes inside the stability window.
- [ ] `gofmt -l .` empty; `git diff --check` clean.
- [ ] The Scope Contract And Guard is respected.

## Handoff
- First causal RED command: `cd go-relay-server && go test ./... -run TestWiderRequestRecipientsDoNotWidenStoredACL`.
- Preservation command: `cd go-relay-server && go test ./...`.
- Manual registration: none.
- Migration: none.
- Boundary closure: relay deploy to v1.7.6 + TC-324-07 live proof.
- Unresolved evidence: none.

## Device/Relay Proof Profile
- Profile: relay (single production box; no staging twin).
- Boundary being proven: that a real reaction still stores and is retrieved by an entitled peer after the binding change — host tests use the in-memory backend, production uses redis.
- Live availability check: relay reachable per `docker-ws/` deploy scripts; version confirmed with `Starting relay-server v1.7.6` in the unit log.
- Rollback: keep `relay-server.pre-324-<stamp>` backup; restore + restart on any failure inside the 90s window. Client is unaffected either way (no wire change).

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started (queued behind 322/323) | - | - | - | user decision 2026-08-02: plan only, do not implement | await 322/323 closure |
