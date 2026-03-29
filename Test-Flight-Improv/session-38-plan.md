# Session 38 Plan — Relay/Local 5 GB Cap And Byte-Safe Retention Contract

## Real Scope

What changes in this session:

- raise the general media size contract from `100 MB` to `5 GB` in the relay
  media path and the local-discovery media server
- keep voice recordings on their separate `100 MB` validation path in
  `send_voice_message_use_case.dart`
- replace the relay's currently count-only pending-media retention behavior with
  an explicit byte-safe per-recipient cap so the new `5 GB` product claim does
  not imply an accidental `250 GB` pending window
- add or tighten direct transport-side tests for:
  - over-limit rejection
  - exact-boundary acceptance
  - zero-byte rejection
  - partial-upload cleanup
  - per-recipient byte-cap pruning behavior
- keep Session `38` limited to transport/local-discovery/voice validation seams

What does not change in this session:

- no attach-time overflow dialog or shared composer budget logic
- no share-hydration attach contract work
- no upload progress banner, leave guard, or wake-lock work
- no closure-doc or stale-spec refresh outside plan/ledger updates
- no change to profile-avatar or repost-avatar limits

---

## Closure Bar

This session is sufficient when all of the following are true:

- relay uploads accept general media up to `5 GB` and reject `5 GB + 1 byte`
- local discovery offers accept general media up to `5 GB` and reject
  `5 GB + 1 byte`
- relay pending-media retention is no longer governed only by
  `maxMediaPerPeer = 50`; an explicit per-recipient byte cap is enforced in a
  way that keeps storage bounded under the new blob size contract
- the relay test suite proves the chosen byte-cap behavior deterministically
  with small fixtures
- the local media server suite still proves boundary acceptance and rejection
  without requiring a real `5 GB` test upload
- voice-message validation still rejects recordings above `100 MB`
- no doc/spec refresh is attempted early; final closure docs remain owned by
  Session `41`

---

## Source Of Truth

Authoritative sources for this session:

- proposal and decomposition:
  - `Test-Flight-Improv/22-media-transfer-size-limit.md`
  - `Test-Flight-Improv/22-media-transfer-size-limit-session-breakdown.md`
- regression/gate policy:
  - `Test-Flight-Improv/14-regression-test-strategy.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- current transport/local behavior:
  - `go-relay-server/media.go`
  - `go-relay-server/media_test.go`
  - `lib/core/local_discovery/local_media_server.dart`
  - `test/core/local_discovery/local_media_server_test.dart`
  - `test/core/local_discovery/local_media_integration_test.dart`
  - `lib/features/conversation/application/send_voice_message_use_case.dart`
  - `test/features/conversation/application/send_voice_message_use_case_test.dart`
- stale secondary evidence to refresh later, not to overrule current code:
  - `UI-10-Media/media-server-spec.md`

Conflict rules:

- current code and current tests beat stale prose
- `test-gate-definitions.md` and `scripts/run_test_gates.sh` win on named-gate
  execution
- the breakdown artifact controls session order and closure ownership

---

## Session Classification

`evidence-gated`

Why:

- the only real ambiguity was the relay retention contract after raising the
  single-blob cap to `5 GB`
- current repo evidence shows count-only pruning at `50` blobs, which becomes
  operationally unsafe at the new limit
- the evidence is now strong enough to settle that ambiguity inside this plan:
  keep prune-oldest semantics, but add an explicit per-recipient byte cap so
  pending storage stays bounded

---

## Exact Problem Statement

Today the repo has three conflicting or incomplete facts:

- relay uploads reject anything above `100 MB`
- local discovery rejects anything above `100 MB`
- voice messages also use `100 MB`, but that limit is intentionally specific to
  in-app recordings and should not govern general attachments

At the same time, the relay stores pending blobs with a count-only policy:

- `maxMediaPerPeer = 50`
- `mediaTTL = 7 days`

At `100 MB`, that policy is rough but bounded enough to tolerate. At `5 GB`,
the same logic implies a potential `250 GB` pending window for one recipient,
which is not safe to ship as an unqualified product contract.

What must improve:

- the relay and local-discovery general media cap must rise to `5 GB`
- the relay must enforce an explicit byte-safe pending-storage rule per
  recipient
- the test suites must prove the new boundary behavior without giant fixtures
- the voice-message path must stay on `100 MB`

What must stay unchanged:

- the relay remains a transient prune/TTL store, not durable archival storage
- voice recordings remain on their current validation path
- attach-time composer UX and upload-progress UX stay out of scope for this
  session

---

## Files And Repos To Inspect Next

Production files:

- `go-relay-server/media.go`
- `lib/core/local_discovery/local_media_server.dart`
- `lib/features/conversation/application/send_voice_message_use_case.dart`

Primary tests:

- `go-relay-server/media_test.go`
- `test/core/local_discovery/local_media_server_test.dart`
- `test/core/local_discovery/local_media_integration_test.dart`
- `test/features/conversation/application/send_voice_message_use_case_test.dart`

Secondary references:

- `UI-10-Media/media-server-spec.md`

Docs to update later, not in this session:

- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
- `Test-Flight-Improv/test-gate-definitions.md` only if test classification
  changes
- `UI-10-Media/media-server-spec.md`
- `UI-10-Media/media-client-spec.md`

---

## Existing Tests Covering This Area

Already covered:

- relay oversize upload rejection:
  `go-relay-server/media_test.go` `TestSizeLimitExceeded`
- relay count-based pruning:
  `go-relay-server/media_test.go` `TestPeerPruning`
- local-discovery rejection for oversized offers, zero size, shorter/longer
  body mismatch, SHA mismatch cleanup, and a streamed exact-boundary test:
  `test/core/local_discovery/local_media_server_test.dart`
- local media sender/receiver integration:
  `test/core/local_discovery/local_media_integration_test.dart`
- voice-recording invalid-size rejection:
  `test/features/conversation/application/send_voice_message_use_case_test.dart`

Missing or stale against the new contract:

- relay proof for the chosen byte-cap retention behavior
- explicit relay proof for exact-boundary acceptance at the configured max using
  a reduced test override instead of giant payloads
- local media boundary proof that does not try to stream an actual `5 GB` file
- an explicit regression that the voice-message max remains `100 MB`

---

## Regression / Tests To Add First

Add or tighten these tests first:

1. `go-relay-server/media_test.go`
   - add a small-fixture boundary test by temporarily lowering the relay size
     cap inside the test and proving:
     - exact max is accepted
     - max + 1 is rejected
   - add a byte-cap pruning test by temporarily lowering the per-recipient byte
     cap and verifying oldest blobs are pruned until total pending bytes fit
   - keep the existing zero-byte / incomplete-upload coverage intact

2. `test/core/local_discovery/local_media_server_test.dart`
   - replace the current streamed `LocalMediaServer.maxFileSize` boundary proof
     with a boundary-safe test seam:
     - assert the production constant is `5 GB`
     - instantiate a test server with a smaller override limit and prove exact
       boundary acceptance plus over-limit rejection there
   - keep existing mismatch/cleanup coverage unchanged

3. `test/features/conversation/application/send_voice_message_use_case_test.dart`
   - add an explicit assertion that voice still rejects `100 MB + 1 byte`
     and that the constant stays on the dedicated voice-validation path

Do not add any new large binary fixtures.

---

## Step-By-Step Implementation Plan

1. In `go-relay-server/media.go`, replace the hardcoded `100 MB` general-media
   limit with `5 GB`.
2. Add an explicit per-recipient pending-byte cap in the relay store.
   Recommended contract:
   - keep the existing prune-oldest behavior
   - prune by bytes as well as count
   - set the byte cap so pending relay storage per recipient remains bounded at
     the same order as the new single-blob product limit
3. Refactor the relay store logic minimally so tests can verify boundary and
   byte-cap behavior with small payloads.
4. In `lib/core/local_discovery/local_media_server.dart`, raise the default
   general-media limit to `5 GB`.
5. Add the smallest safe test seam to `LocalMediaServer` so the direct suite
   can verify exact-boundary behavior with a small override limit instead of
   allocating or hashing `5 GB`.
6. Leave `send_voice_message_use_case.dart` functionally unchanged except for
   any comment or explicit regression needed to pin the separate `100 MB`
   contract.
7. Run the direct tests.
8. Run required named gates because Flutter production code changed in shared
   media paths.
9. If new test files or gate classifications are added, run
   `./scripts/run_test_gates.sh completeness-check`; otherwise skip it.

Stop rule inside implementation:

- if the relay byte-cap contract cannot be implemented without a broader server
  persistence redesign, stop and mark the session blocked
- do not widen into upload UX or attach-time validation if the transport
  contract lands cleanly

---

## Risks And Edge Cases

- pruning by byte size can accidentally prune the newly uploaded blob if the
  algorithm is ordered incorrectly; the store must keep the newest blob when it
  alone fits within the cap
- using a real `5 GB` local test fixture would make the direct suite
  impractical; the test seam must prove logic without giant I/O
- group-mode blobs use `AllowedPeers`, but storage still keys by `To`; the new
  byte-cap logic must preserve that existing behavior
- a byte-cap pruning rule changes retention semantics and must be explicit in
  tests so it is not misread as a regression later
- the voice-message contract can be accidentally widened if a shared media-size
  constant leaks into the recorder path

---

## Exact Tests And Gates To Run

Direct tests:

- `cd go-relay-server && go test ./...`
- `flutter test test/core/local_discovery/local_media_server_test.dart`
- `flutter test test/core/local_discovery/local_media_integration_test.dart`
- `flutter test test/features/conversation/application/send_voice_message_use_case_test.dart`

Required named gates:

- `./scripts/run_test_gates.sh baseline`
- `./scripts/run_test_gates.sh 1to1`
- `./scripts/run_test_gates.sh groups`

Not required by default:

- `./scripts/run_test_gates.sh transport`
  - only if the landed change spills into resume/bootstrap/media-recovery wiring
- `./scripts/run_test_gates.sh completeness-check`
  - only if this session adds new test files or edits gate classifications

---

## Known-Failure Interpretation

- no target-area known failure is documented in the sources read for this
  session
- if a required named gate fails outside the changed relay/local/voice seams,
  treat it as a session blocker only if the failure reproduces against the
  changed paths or the changed tests
- do not classify unrelated red tests from the already-dirty worktree as
  Session `38` regressions without a concrete file-level link

---

## Done Criteria

- relay general-media uploads are capped at `5 GB`
- local-discovery general-media offers are capped at `5 GB`
- relay pending storage per recipient is byte-bounded, not count-only
- direct relay/local/voice tests pass
- required named gates pass
- Session `38` can hand off a settled transport contract to Session `39`
  without reopening the retention ambiguity

---

## Scope Guard

- do not add attach-time overflow dialogs or compression decisions here
- do not add upload progress plumbing, wake locks, or leave-guard UI here
- do not redesign relay persistence beyond the minimal byte-safe retention rule
- do not refresh stable closure docs early
- do not change the dedicated voice-recording `100 MB` product contract

---

## Accepted Differences / Intentionally Out Of Scope

- the relay remains a transient pending-blob store with TTL and pruning, not a
  durable archival service
- this session accepts prune-oldest retention semantics rather than inventing a
  new sender-visible quota negotiation protocol
- local and relay size-cap changes do not imply receiver-side download UX
  changes
- stale `UI-10-Media/*` docs stay untouched until Session `41`

---

## Dependency Impact

- Session `39` depends on this session to settle the authoritative general-media
  size contract and preserve the voice exception
- if this session blocks on the relay retention contract, Sessions `39`, `40`,
  and `41` must be revisited against that blocker before continuing
- if this session lands cleanly, later sessions can treat the `5 GB`
  general-media transport cap and `100 MB` voice cap as fixed inputs
