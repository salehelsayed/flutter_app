# 339 - Attachment-Envelope Live-Relay Eligibility

Status: implemented — causal, curated, and feature-host gates green
Type: Feature Improvement
Spec: UI-14-Conn-Type/go-libp2p-transport-assessment-review.md, R5
Classification: implementation-complete / host-green
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-05 21:55 CEST | Evidence Collector | R5 assessment; current send orchestration, payload/media models, media producers, Dart fakes, Go relay framing, and test gates | Confirmed the live-relay gate rejects every attachment and measures Dart code units even though the relay send carries only the encoded encrypted envelope | Bound R5 to one Dart eligibility predicate and existing tests |
| 2026-08-05 22:05 CEST | Planner | Existing FDC-02 unit/integration contracts, upload/encryption sentinels, protected-photo thumbnail exception, R1-R3 settlement proofs | Two existing tests enforce the obsolete ban and should be rewritten; existing fakes expose the frame and relay leg, so no new harness, protocol, or readiness state is needed | Define causal REDs, preservation sentinels, and closure gates |
| 2026-08-05 22:11 CEST | Planner | R4/R5 ordering and current gate registration | R1-R3 are the hard correctness dependencies. R4 is the preferred execution predecessor because both plans touch send orchestration, but R5 has an independently verifiable host contract | Submit the bounded plan to independent TDD review |
| 2026-08-05 22:18 CEST | Independent Reviewer | Full Plan 339 draft against current fakes, frame format, producer census, opposite contracts, R1-R3 sentinels, and gate scripts | Initial verdict `plan-fixes-required`: dedup was vacuous; circuit fixtures needed isolation; exact cap equality was unpinned; multibyte and protected-thumbnail claims were overstated; R2/R3 names were vague | Apply only the six bounded proof corrections |
| 2026-08-05 22:22 CEST | Planner / Reviewer | First revision of TC-339-01 through TC-339-08, Test Notes, acceptance commands, and review findings | Dedup, probe isolation, equality, synthetic-input wording, thumbnail scope, and exact preservation names were repaired | Re-submit the revised plan rather than self-certify it |
| 2026-08-05 22:27 CEST | Independent Reviewer / Planner | Revised plan plus default `FakeP2PService` direct behavior | Second pass found TC-339-03 and the new exact-cap fixture could still pass through default direct delivery; both now pin direct/probe off and assert the relay discriminator | Final verdict `ready`; hand off after R4/rebase |

## Problem And Evidence

- Behavior to improve: an already-uploaded attachment's small encrypted message envelope should be eligible for an existing circuit-relay connection when the actual UTF-8 frame fits the conservative live-relay ceiling.
- User impact: today a recipient reachable through an existing relay cannot receive attachment metadata live. Even though the encrypted media object is uploaded separately, the sender skips the relay-live leg and waits for a direct path or durable inbox custody.
- Confirmed root cause:
  - `lib/features/conversation/application/send_chat_message_use_case.dart:1076-1083` calls `_liveRelayEligible(hasAttachments, jsonString.length)`;
  - `_liveRelayEligible` at `:1674-1678` requires `!hasAttachments`, so attachment presence is an unconditional exclusion;
  - the eligibility API accepts Dart code-unit length even though the downstream stream and frame limit operate on UTF-8 bytes. Current valid Go v2 encryption material is base64 ASCII, so no production multibyte undercount was demonstrated; UTF-8 remains the correct contract at this Dart boundary and prevents future/noncanonical inputs from being measured in the wrong unit.
- Confirmed existing boundaries:
  - the relay-live leg passes only `jsonString` to `sendMessageWithReply`; no media file or blob buffer is passed by `_tryRelayLiveSend` (`send_chat_message_use_case.dart:1680-1715`);
  - `MediaAttachment.toJson()` emits remote descriptor, integrity, and encryption metadata but omits `localPath`, `downloadStatus`, `ownerLane`, and local `messageId` (`lib/features/conversation/domain/models/media_attachment.dart:247-264`);
  - ordinary composer, voice, share, edit, and retry producers call `sendChatMessage` with attachment descriptors only after upload succeeds; the canonical send boundary also fails closed when required encrypted-media metadata is absent;
  - Go converts the Dart string to bytes and writes that exact frame, already admits limited circuit-v2 connections, and enforces `MaxFrameLen = 128 * 1024` (`go-mknoon/node/config.go:77`, `go-mknoon/node/node.go:1638-1651,1777,1820-1824,2447-2477`);
  - Dart's existing `kLiveRelayMaxPayloadBytes = 96 * 1024` therefore retains headroom below the native maximum.
- Obsolete opposite contracts:
  - `send_chat_message_use_case_test.dart::FDC-02 media never live-relay: media payload with a live circuit skips the relay-live leg`;
  - `ranked_race_relay_penalty_test.dart::FDC-02 e2e: media send with live circuit reaches the receiver via inbox, never the live circuit`.
  These must be rewritten, not kept alongside contradictory R5 tests.
- Important exception: protected photos intentionally embed one bounded, derived inline thumbnail in the encrypted inner message. R5 preserves that established behavior and claims only that the primary encrypted media blob/local file does not traverse the chat-envelope stream.
- Refuted additions:
  - no Go/native change is needed for the existing limited stream or frame cap;
  - no `mediaRecoveryReady` field, media-availability state, second ACK level, upload token, or pending-inbox protocol is justified. Current production producers already establish upload-before-send, and a new Boolean at `sendChatMessage` would not independently prove relay custody;
  - no new coordinator, queue, discovery racer, or real-relay test harness is needed for this local eligibility decision.
- Unresolved evidence / stop condition: `sendChatMessage` is a public application boundary and tests can construct descriptors directly. If execution finds a production caller that sends a fresh attachment before upload success, stop and split that producer defect from R5 rather than inventing a global readiness protocol here.

Principal production file:

- `lib/features/conversation/application/send_chat_message_use_case.dart`

Principal test files:

- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/integration/ranked_race_relay_penalty_test.dart`

Exact preservation files:

- `test/features/conversation/application/upload_media_use_case_test.dart`
- `test/features/conversation/application/send_voice_message_use_case_test.dart`
- `test/features/conversation/application/send_protected_photo_thumbnail_test.dart`
- `test/core/database/helpers/outgoing_transport_settlement_test.dart`

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `f2fc4f7373078fa3`; `confidence=anchored`, `freshness=current`.
- Query / profile: `python3 graphify-arch/tdd_context.py query "R5 attachment envelopes over live circuit relay allowLiveRelay attachment envelopeBytes mediaRecoveryReady send_chat_message_use_case.dart transport assessment" --profile tdd --budget 700`.
- Primary anchor: `send_chat_message_use_case.dart`; related nodes included `MessagePayload`, `MediaAttachment`, P2P service boundaries, and `send_chat_message_use_case_test.dart`.
- Source verification beyond the graph: current relay send/frame code, every production attachment producer family, the two obsolete tests, protected-thumbnail behavior, and both gate arrays were checked directly.
- Graph decision: the affected app-owned path is localized to the 1:1 send use case. Native/source census refutes a Go change and a new cross-file architecture seam.
- Review query / profile: `python3 graphify-arch/tdd_context.py query "Plan 339 attachment-envelope live-relay eligibility _liveRelayEligible utf8 kLiveRelayMaxPayloadBytes ranked_race_relay_penalty_test ONE_TO_ONE_TESTS bypass counterexample" --profile review --budget 800`; `confidence=anchored`, same current fingerprint.

## Scope Contract And Guard

In scope:

- Replace attachment-presence eligibility with the actual UTF-8 byte length of the complete encrypted outer envelope.
- Retain the inclusive ceiling: `encodedEnvelopeBytes <= kLiveRelayMaxPayloadBytes`.
- Compute the encoded size only for a peer with an existing circuit connection; do not add an unconditional second serialization on sends that cannot use the live relay.
- Reduce `_liveRelayEligible` to a size-only predicate and update its stale comment. Reuse the existing `dart:convert` import.
- Preserve the 96 KiB application ceiling and the 128 KiB native frame limit.
- Reuse the existing uploaded/encrypted attachment descriptor contract. An attachment's declared blob size may exceed 96 KiB when its envelope is small; the declared media size is not the live-frame size.
- Rewrite the two old attachment-ban tests in place and add only the byte-boundary and failure cases that those tests do not cover.
- Keep R1 atomic status advancement, R2 authenticated committed-proof authority, and R3 deadline allocation unchanged.

Must preserve:

- An authenticated, explicitly committed relay ACK is required for `delivered`; an attempted or uncommitted relay write is not proof.
- Relay staggering, direct work, local-WebSocket de-authority, route labels, sticky learning, message-ID deduplication, and one durable inbox fallback remain unchanged.
- ASCII and multibyte envelopes over the 96 KiB byte ceiling never start the relay-live leg.
- Attachment encryption metadata and content hash remain mandatory at the send boundary.
- Primary media upload occurs before the descriptor is sent. The chat frame contains descriptor metadata, not `localPath`, local ownership/download fields, or primary blob content.
- The established protected-photo inline-thumbnail exception remains bounded and byte-counted as part of the envelope.
- Text-only envelopes under the cap retain their existing live-relay behavior.

Hard `Do not`:

- Do not send the primary image/video/audio/file bytes through `sendMessageWithReply`.
- Do not add a media readiness flag, durable token, database column, schema migration, native spool, ACK/protocol version, or media-availability update.
- Do not change upload APIs, download/recovery semantics, protected-media policy, encryption format, Go framing, circuit limits, relay classification, connection ranking, deadlines, or DCUtR behavior.
- Do not change presence ordering or introduce the R4 inbox hedge. If R4 is already implemented at execution time, join and preserve its one scheduled inbox operation rather than recreating fallback logic.
- Do not add a new test fake, relay server, device topology, gate script entry, or duplicate host registration unless an existing fixture is demonstrably unable to expose a required assertion.

Dependencies and sequencing:

- Hard dependencies: Plans 336-338 / R1-R3 are implemented and supply monotonic persistence, authenticated first-proof settlement, and the bounded deadline contract.
- Preferred predecessor: R4, because it deliberately changes presence/inbox scheduling in the same large use case. R5 may be planned and reviewed now, but execute it after R4 to minimize merge/test churn.
- If R5 is intentionally executed before R4, it remains independently correct; R4 must later re-run TC-339-05 and preserve exactly one inbox deposit. Do not encode current pre-R4 timing into R5 assertions.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-339-01 | A ready attachment descriptor whose encrypted UTF-8 envelope fits the cap uses the existing live relay, while primary blob/local-only data stays out of the chat frame | rewrite as `send_chat_message_use_case_test.dart::R5 uploaded attachment envelope under the UTF-8 cap uses live relay` | Dart host; existing `FakeP2PService`, circuit-only state, `dialPeerResult:false`, `probeRelayResult:error`, `storeInInboxResult:true`, explicit relay ACK, passthrough crypto, encrypted `done` attachment with declared size above the cap and a unique local-path sentinel | HEAD skips relay and lands in inbox -> GREEN starts one relay-live send and settles `delivered/relay`; the captured frame is under the byte cap, contains descriptor/hash/key metadata, and omits local path, download/owner/message-local fields, and the primary-blob sentinel | restore `!hasAttachments`, compare declared media size, or serialize `localPath` -> test red | exact focused test; file already in `ONE_TO_ONE_TESTS`, `ONE_TO_ONE_HOST_TESTS`, and feature auto-glob |
| TC-339-02 | The attachment relay route preserves receiver message-ID idempotency across two real send attempts | rewrite as `ranked_race_relay_penalty_test.dart::R5 attachment envelope uses live relay and receiver message-ID dedup keeps one row`; existing `two_user_message_exchange_test.dart::Duplicate messages are rejected` | Dart host integration; existing `DurableLanFakeP2PService`, recipient in `localPeers`, circuit-only state, `dialPeerResult:false`, `probeRelayResult:error`, `storeInInboxResult:true`, fixed message ID, and receiver row fake; separate production receiver integration sentinel | HEAD has one LAN write, zero relay-live starts, and inbox custody -> GREEN has one unauthenticated LAN write plus one committed relay-live send and settles `delivered/relay`; assert exactly two live transmissions, replay both fixed-ID transmissions, and retain exactly one receiver row; the existing production receiver sentinel independently stores/emits one row after duplicate injection | restore attachment ban -> relay/route assertion red; remove fake or production receiver ID dedup -> two-row/emit assertion red | exact two integration tests; both already in `ONE_TO_ONE_TESTS` and feature auto-glob; no duplicate host-array registration required |
| TC-339-03 | Eligibility uses the stream's UTF-8 byte domain rather than Dart code units | new `send_chat_message_use_case_test.dart::R5 multibyte envelope is capped by UTF-8 bytes not Dart code units` | Dart host; text-only circuit fixture, `dialPeerResult:false`, `probeRelayResult:error`, `storeInInboxResult:true`, and intentionally synthetic non-base64 `message.encrypt` ciphertext accepted at the current Dart bridge seam | Fixture asserts the actual outer envelope's code-unit length is at/below 96 KiB while `utf8.encode(frame).length` is above it. HEAD starts exactly one relay-live send and delivers -> GREEN starts none, stores once, and ends `inboxed/inbox`. This is a defensive unit-domain contract, not evidence that current Go base64 output undercounts | replace UTF-8 length with `jsonString.length` -> relay count/final route red | exact focused test; existing registration |
| TC-339-04 | Size-only eligibility preserves under-cap text, admits exactly 96 KiB, and rejects envelopes above the ceiling | existing `send_chat_message_use_case_test.dart::FDC-02 relay penalty: when LAN+direct both fail, the staggered relay-live leg still carries`; new `::R5 live-relay UTF-8 ceiling includes exactly 96 KiB`; update existing `::FDC-02 large payload never live-relay: a >budget text payload skips the relay-live leg` to assert captured UTF-8 bytes exceed the cap | Dart host; existing relay observer/small-text control; exact-cap circuit fixture pins `dialPeerResult:false`, `probeRelayResult:error`, and uses a deterministic ASCII crypto response calibrated from `MessagePayload.buildEncryptedEnvelope`; oversized passthrough fixture | GREEN on HEAD and after R5 -> small text and exact-cap captured frame use exactly one relay-live leg; oversized actual frame does not | change `<=` to `<` -> exact-cap relay-count case red; remove the size ceiling -> oversized case red; retain attachment-only eligibility -> controls stay green but TC-339-01 red | exact names in focused file and curated `1to1` |
| TC-339-05 | Failure of an otherwise eligible attachment relay attempt reaches one durable inbox operation | new `send_chat_message_use_case_test.dart::R5 eligible attachment relay-live failure falls to one durable inbox deposit` | Dart host; circuit-only, `dialPeerResult:false`, `probeRelayResult:error`, relay returns `sent:false, acked:false`, `storeInInboxResult:true`; compatible with the future R4 scheduled hedge | HEAD reaches inbox without attempting relay -> GREEN proves `relayLiveSendCount == 1`, `sendCallCount == 1`, exactly one inbox call, final `inboxed/inbox`, and no `delivered` mint | restore attachment ban -> missing relay start; treat failure as proof -> missing inbox; create a second fallback -> count red | exact focused test; existing registration |
| TC-339-06 | Existing upload and send gates remain the only readiness contract | existing `upload_media_use_case_test.dart::returns MediaAttachment on success`, `::sends correct command to bridge`; existing `send_voice_message_use_case_test.dart::voice upload produces encrypted attachment metadata and passes the send gate`; existing `send_chat_message_use_case_test.dart::send fails closed when an attachment lacks encryption metadata` | Dart host; fake blob encryption/upload and send gate | GREEN sentinels -> upload completes before descriptor return, returns `done` plus crypto/hash metadata, voice passes that descriptor, and incomplete metadata still fails before transport | bypass upload ordering or relax `_sanitizeDirectMediaAttachments` -> sentinel red | exact commands; existing curated/feature registration, no new gate edit |
| TC-339-07 | Protected-photo inline thumbnail remains the one bounded derived-byte exception | existing `send_protected_photo_thumbnail_test.dart::protected photo send embeds one bounded inline thumbnail`; verified source order `thumbnail -> inner JSON -> encryption -> outer envelope -> eligibility` | Dart host; existing image processor/crypto fake plus direct source-order inspection | GREEN preservation on HEAD and after R5 -> bounded thumbnail remains embedded before the final envelope is measured | remove or unbound the established thumbnail -> existing preservation test red; no separate pre-thumbnail route mutation is claimed | exact protected-photo file; feature auto-glob |
| TC-339-08 | R1-R3 proof/status contracts remain authoritative when attachment relay and inbox complete in either order | existing `outgoing_transport_settlement_test.dart::first delivered result owns fields across both callback orders`; existing `ranked_race_relay_penalty_test.dart::R2 written direct or relay result cannot suppress later committed live proof`; existing `send_chat_message_use_case_test.dart::R3 committed ACK window is shared by reuse sticky cold direct and live relay` | Dart host; real SQL settlement helper and existing fakes | GREEN on HEAD and after R5 -> committed relay may deliver, uncommitted relay cannot, late weaker custody cannot downgrade delivery, and R3 supplies the remaining committed-send timeout | bypass atomic settlement, accept written relay evidence, or restore a fresh relay timeout -> owning sentinel red | exact three named commands plus focused files; no core family sweep because the core production contract is unchanged |

### Test Notes

- TC-339-01 must inspect the exact string captured by `sendMessageWithReply`, not rebuild an approximation. Decode the passthrough-crypto inner payload and assert descriptor fields explicitly. Pin direct dial and the probe tail off so no identically labelled send can overwrite the capture. Use a large declared `size` and unique `localPath` sentinel without allocating a large test file; this proves the decision and frame are envelope-based, not that an artificial file upload occurred inside this unit test.
- Do not assert that an attachment envelope contains no media-derived bytes at all. Protected photos deliberately carry one bounded inline thumbnail. The exact R5 invariant is that no primary blob/local file is placed on the chat stream.
- TC-339-02 must observe exactly one LAN write plus one relay-live send before replaying the fixed ID twice. Pairing that route-specific fake with `Duplicate messages are rejected` avoids treating the fake receiver as the production dedup implementation.
- TC-339-03 must use a text-only envelope so the current attachment ban cannot mask the byte-domain defect. Its non-base64 multibyte ciphertext is intentionally synthetic at the Dart bridge seam; assert both fixture inequalities before route behavior and do not present it as observed Go output. Pin default direct and probe paths off, then assert relay and inbox counts on both sides of the change. A malformed boundary fixture is a test failure, not a valid GREEN.
- TC-339-04 derives the exact-cap ciphertext length from the real outer-envelope builder with fixed ID/peer/KEM/nonce values, then asserts the captured frame is exactly `kLiveRelayMaxPayloadBytes` and `relayLiveSendCount == 1`. It pins direct/probe off and does not hard-code JSON-overhead arithmetic.
- TC-339-05 is schedule-agnostic. Its load-bearing assertions are one attempted relay-live leg, one total inbox deposit, and the final monotonic milestone. It must pass whether that single inbox future was started by current fallback or the future R4 hedge.

## Implementation Steps

1. Snapshot `git status --short` and `git diff --cached --name-status`. Preserve the current uncommitted R2 cleanup, Plan 337/338 records, index edits, and Graphify output; do not stage or rewrite unrelated hunks.
2. Rewrite the two obsolete attachment-ban tests as TC-339-01 and TC-339-02. Add causal TC-339-03/05, add the exact-cap GREEN sentinel, and strengthen the existing oversized assertion in TC-339-04. Run each named causal RED before production edits. A missing relay start or wrong route is valid RED; a compile failure, runner timeout, invalid byte-boundary fixture, or one-transmission “dedup” pass is not.
3. In `send_chat_message_use_case.dart`, compute the encrypted outer envelope's UTF-8 byte length inside the existing-circuit eligibility branch, remove `hasAttachments` from `_liveRelayEligible`, and retain the inclusive 96 KiB comparison. Update only the now-stale relay comments.
4. Run focused GREEN and mutation re-reds: temporarily restore the attachment exclusion for TC-339-01/02/05, replace UTF-8 bytes with code-unit length for TC-339-03, change `<=` to `<` for the exact-cap sentinel, and remove the ceiling for the oversized TC-339-04 case. Restore the intended implementation after each mutation.
5. Run TC-339-06/07/08 preservation sentinels. Stop-if any production attachment producer bypasses upload success or if making TC-339-05 pass requires a second inbox operation, status writer, timeout change, or proof-authority change; return that work to its owning plan.
6. Run the focused files, curated `1to1`, affected `feature-host-all`, analyzer/format/diff hygiene, and refresh Graphify once after the coherent source change. Do not change gate arrays: both causal files already run in the curated lane and feature family.

## Risks And Blind Spots

- A nominally small attachment can produce a large encrypted frame through metadata, caption/ciphertext growth, or the protected thumbnail -> eligibility measures the final outer frame, and TC-339-03/04 pin the byte-domain and cap behavior without claiming current Go ciphertext is multibyte.
- A large primary media object can have a small descriptor -> TC-339-01 deliberately uses a declared size above the relay ceiling while requiring a small captured frame.
- A test can prove relay delivery while accidentally leaking local-only fields -> TC-339-01 inspects the exact transmitted envelope and a unique sentinel.
- A one-path integration can pass after receiver dedup is removed -> TC-339-02 requires exactly two live transmissions and pairs the fake with the existing production duplicate-injection test.
- Direct or relay-probe sends can masquerade as the live-relay result because they share `sendMessageWithReply` -> TC-339-01 through TC-339-05 pin the competing paths where route admission is load-bearing and use `relayLiveSendCount` as the leg discriminator.
- Removing the attachment ban can expose an upload-before-send bypass -> production caller census plus TC-339-06 preserve current producer/gate contracts; the stop condition prevents R5 from papering over a real bypass with a Boolean.
- R4 can change which callback starts inbox storage -> TC-339-05 asserts one joined deposit and final milestone rather than current timer/order details.
- An uncommitted relay write can be mistaken for the desired fast path -> TC-339-05 and R2 preservation require explicit authenticated commitment before delivery.
- The protected-thumbnail exception makes an absolute “no media bytes” claim false -> the plan uses the narrower primary-blob invariant and keeps the established thumbnail test.
- Lifecycle / derived-state durability: N/A — no marker, cache, schema, or reconstruction rule changes; R1's SQL transition proof is rerun exactly.
- Sibling-surface consistency: text and uploaded image/voice descriptors share the same final-envelope predicate; group messaging, introduction/contact/reaction protocols, cached inbox-only retries, and media download remain out of scope.
- Native/mobile boundary: the code under change selects a Dart route from a fully formed string. Host fakes capture that exact string and route attempt, while existing Go code already enforces the larger native frame cap. No OS callback, socket implementation, or iOS-specific claim needs a device leg.

## Gate Cadence

- Per-plan closure: four causal RED/GREEN cases in the two affected files; exact upload, protected-thumbnail, R1-R3, under-cap text, and oversized-envelope sentinels; `./scripts/run_test_gates.sh 1to1`; and affected `feature-host-all` because the shared 1:1 send production file is changed.
- Do not run `core-host-all`: R5 changes no core production file, schema, bridge, native code, or core contract. The exact SQL settlement test is sufficient preservation for the unchanged R1 boundary.
- Do not run full `host-all` as an individual Plan 339 causal gate. After both R4 and R5 are complete, run one full `host-all` as the durability/relay rollout-wave and final rollout/release receipt.
- No required Android, iOS, or real-relay leg: deterministic host tests observe the exact encoded frame, relay-leg admission, ACK outcome, inbox fallback, and receiver dedup. A real relay-and-media journey may support later rollout confidence on available targets, but it is not a Plan 339 closure condition.

## Acceptance Gates

```bash
# Snapshot before execution; record unrelated staged/unstaged work.
git status --short
git diff --cached --name-status

# First causal RED: rewrite the obsolete opposite test, then expect non-zero on
# HEAD because attachment presence still suppresses the relay-live leg.
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'R5 uploaded attachment envelope under the UTF-8 cap uses live relay'

# Independent REDs: existing integration policy, byte/code-unit mismatch, and
# eligible relay failure. Expect each named test to be selected and non-zero.
flutter test test/features/conversation/integration/ranked_race_relay_penalty_test.dart \
  --plain-name 'R5 attachment envelope uses live relay and receiver message-ID dedup keeps one row'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'R5 multibyte envelope is capped by UTF-8 bytes not Dart code units'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'R5 eligible attachment relay-live failure falls to one durable inbox deposit'

# Exact-cap GREEN sentinel is deliberately not RED on HEAD; expect one selected
# passing test before and after production changes.
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'R5 live-relay UTF-8 ceiling includes exactly 96 KiB'

# Focused GREEN; expect exit 0 and zero failures.
flutter test \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/integration/ranked_race_relay_penalty_test.dart

# Production receiver message-ID dedup preservation; expect one persisted and
# emitted message after an explicit duplicate injection.
flutter test test/features/conversation/integration/two_user_message_exchange_test.dart \
  --plain-name 'Duplicate messages are rejected'

# Existing upload/encryption and protected-thumbnail preservation.
flutter test test/features/conversation/application/upload_media_use_case_test.dart \
  --plain-name 'returns MediaAttachment on success'
flutter test test/features/conversation/application/upload_media_use_case_test.dart \
  --plain-name 'sends correct command to bridge'
flutter test test/features/conversation/application/send_voice_message_use_case_test.dart \
  --plain-name 'voice upload produces encrypted attachment metadata and passes the send gate'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'send fails closed when an attachment lacks encryption metadata'
flutter test test/features/conversation/application/send_protected_photo_thumbnail_test.dart \
  --plain-name 'protected photo send embeds one bounded inline thumbnail'

# Exact R1-R3 settlement, proof, and remaining-deadline sentinels.
flutter test test/core/database/helpers/outgoing_transport_settlement_test.dart \
  --plain-name 'first delivered result owns fields across both callback orders'
flutter test test/features/conversation/integration/ranked_race_relay_penalty_test.dart \
  --plain-name 'R2 written direct or relay result cannot suppress later committed live proof'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'R3 committed ACK window is shared by reuse sticky cold direct and live relay'

# Curated and affected-family closure. Do not substitute per-plan full host-all.
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh feature-host-all \
  --batch-flutter --concurrency 4 --reporter failures-only

# Hygiene and topology refresh.
dart format --output=none --set-exit-if-changed \
  lib/features/conversation/application/send_chat_message_use_case.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/integration/ranked_race_relay_penalty_test.dart
flutter analyze
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental
```

Wave-level command after both R4 and R5 close, not a Plan 339 done gate:

```bash
./scripts/run_host_test_gates.sh host-all \
  --batch-flutter --concurrency 4 --reporter failures-only
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-339-01/02/05 report no relay-live start because of `!hasAttachments`; TC-339-03 starts relay because `String.length` undercounts its multibyte frame. TC-339-04 and TC-339-06/07/08 are labelled GREEN preservation sentinels on HEAD.
- Green sentinel: text-only under-cap relay behavior, oversized ASCII exclusion, upload/encryption ordering, protected-photo thumbnail behavior, authenticated ACK authority, and atomic settlement remain unchanged.
- Pre-existing dirty tree: execution must record and preserve the uncommitted R2 resilience/fake/documentation cleanup, Plan 337/338 status edits, index hunks, and refreshed Graphify files described at planning time.
- Environment blocker: none for host closure. Device availability is irrelevant to the causal claim and unavailable platforms are N/A by project policy.
- Scope drift: any need for upload state, wire/native changes, schema work, another inbox operation, proof/deadline changes, or a new relay harness blocks R5 and requires a separate decision.

- [x] All four causal cases fail for their documented behavioral reason before production edits; every named test is selected.
- [x] TC-339-01 proves an uploaded attachment descriptor under the actual UTF-8 cap uses one live-relay attempt and contains no primary-blob/local-only fields.
- [x] TC-339-02 proves the new route while receiver message-ID dedup retains one row across actual transmissions.
- [x] TC-339-03 and TC-339-04 prove UTF-8 byte accounting, inclusive bounded eligibility, and text-path preservation.
- [x] TC-339-05 proves relay failure/uncommitted evidence reaches exactly one durable inbox deposit without minting delivery.
- [x] Upload/encryption gates and protected-thumbnail behavior pass unchanged; no readiness state or protocol is added.
- [x] R1-R3 atomic settlement, authenticated commitment, and deadline contracts pass their exact sentinels.
- [x] Representative old-behavior, code-unit, and no-cap mutations re-red, then the intended implementation is restored.
- [x] Focused tests, curated `1to1`, affected `feature-host-all`, analyzer, formatting, diff hygiene, and incremental Graphify refresh pass.
- [x] No gate registration, migration, Go/native, device, iOS, media protocol, presence, or inbox-scheduling change is introduced.
- [x] Scope Contract And Guard is respected, including the protected-thumbnail exception and R4 sequencing boundary.

## Handoff

- First causal RED command: `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart --plain-name 'R5 uploaded attachment envelope under the UTF-8 cap uses live relay'`.
- Smallest production delta: use `utf8.encode(jsonString).length` inside the existing-circuit branch and make `_liveRelayEligible` size-only; update stale comments.
- Manual registration: none. Both changed causal files are already selected by curated `1to1` and feature-family discovery.
- Migration: none.
- Boundary closure: host-only. The existing fake captures the exact frame and relay leg; receiver integration proves ID dedup; existing Go framing is preserved rather than modified.
- Execution order: R5 landed before R4 under the requested Plan 339 execution. TC-339-05 is schedule-agnostic and green with exactly one inbox deposit; R4 must re-run it and retain that single joined operation.
- Deferred rollout evidence: full `host-all` once after the R4-R5 wave; any available automated real-relay/media journey is supporting final-rollout evidence, not a Plan 339 blocker.

## Reviewer Findings

Initial verdict: **plan-fixes-required**. The implementation scope was appropriately small, but six proof details could permit a partial or overstated implementation to pass.

| Review finding | Evidence state | Minimal revision applied | Status |
|---|---|---|---|
| The R5 integration could “prove” dedup with only one transmission | confirmed / high | TC-339-02 now requires one LAN write plus one relay-live send, asserts exactly two live transmissions, replays both fixed IDs, and pairs the fake with the existing production duplicate-injection test | resolved |
| Direct or probe sends could mask the relay-live leg or fallback | confirmed / medium | TC-339-01/02/05 now pin direct dial failure, probe error, inbox outcome, exact relay result, and leg/send counts | resolved |
| Inclusive `<=` behavior had no equality proof | confirmed / medium | TC-339-04 adds an exact 96 KiB captured-envelope GREEN sentinel and a `<` mutation | resolved |
| Multibyte wording implied an observed production defect despite ASCII base64 native output | confirmed / medium | Problem text and TC-339-03 now classify the non-base64 fixture as a synthetic Dart-boundary/domain contract, not production evidence | resolved |
| The existing protected-thumbnail test could not catch pre-thumbnail sizing | confirmed / medium | TC-339-07 is honestly preservation-only; verified source order supplies context without adding a bespoke route test | resolved |
| R2/R3 preservation names were vague | confirmed / low | TC-339-08 and Acceptance Gates now name and execute the exact proof-ordering and shared-ACK-window sentinels | resolved |
| Revised multibyte/exact-cap tests could pass through the fake's default direct route | confirmed on second pass / high | TC-339-03/04 now pin direct dial failure and probe error and require the exact relay-live count; TC-339-03 also pins one inbox fallback on GREEN | resolved |

Refuted claims: the initial TC-339-02 mutation sensitivity; the initial TC-339-07 pre-thumbnail mutation sensitivity; and any claim that current valid Go ciphertext itself demonstrates a multibyte undercount. Unresolved findings: none.

Five-lens re-audit: root cause and classification are exact; all four changed-behavior cases have honest RED contrasts; duplicate/probe/cap bypasses are closed; every named command has an existing registration or exact invocation; persistence, producer, protected-media, R4, native, and device boundaries are explicit. Adding a readiness state, Go change, custom relay harness, duplicate host registration, or device leg would not close a stronger in-scope claim.

Final independent review verdict: **READY**. The revised plan is coherent, sufficient, and bounded to the eligibility decision.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-05 execution | causal RED and baseline | two affected Dart test files | TC-339-01/02/03/05 each exited non-zero for the named route mismatch; exact-cap TC-339-04 passed on HEAD | Attachment cases skipped relay, the synthetic multibyte frame was admitted by code-unit length, and the failure case had no relay attempt; every RED compiled and selected the intended test | None; R1-R3 are present and no production upload-before-send bypass was found | Implement the bounded predicate change |
| 2026-08-05 execution | implementation and focused GREEN | send use case plus two affected test files | focused files -> `+158`; exact R5 selectors -> `+5` | The captured final UTF-8 envelope governs admission; ready attachment descriptors use relay, exact 96 KiB is inclusive, oversized frames skip relay, failed/uncommitted relay falls to one inbox deposit, and the two-transmission receiver fixture retains one row | None | Run mutation and preservation proofs |
| 2026-08-05 execution | mutation and preservation | affected tests plus exact upload/protected-photo/R1-R3 sentinels | old attachment ban, code-unit length, exclusive cap, and removed-cap mutations each re-red; restored preservation set -> `+11` | Each decision edge is mutation-sensitive; upload/encryption, primary-blob exclusion, protected thumbnail, duplicate rejection, atomic settlement, authenticated proof, and shared R3 ACK-window contracts remain green | None | Run registered gates |
| 2026-08-05 execution | curated and affected host closure | registered `1to1` and feature host families | `./scripts/run_test_gates.sh 1to1` -> Flutter `+2821` plus relay Go contracts; `feature-host-all` -> `+8832 ~1` | The bounded change is green in both required registered scopes; the one feature skip is expected | None | Complete hygiene and topology closure |
| 2026-08-05 22:54 CEST | hygiene, graph, and independent implementation review | three changed Dart files, plan/index, architecture graph | formatter -> 3 files / 0 changes; analyzer and diff check -> pass; incremental refresh -> 3 changed code / 3071 unchanged / 0 deleted; review -> approve | Graphify affected-context remained localized and refreshed to current fingerprint `6b96acb19b528031`; no migration, Go/native, gate registration, device, presence, readiness, protocol, proof, deadline, or inbox-scheduling change was introduced | None; pre-existing R2/R3/resilience/fake/Graphify work remains outside the Plan 339 commit | Commit the isolated Plan 339 change; R4 later re-runs TC-339-05 |
