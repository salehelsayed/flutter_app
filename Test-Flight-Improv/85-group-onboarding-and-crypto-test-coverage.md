# 1. Title and Type

- Title: Group Onboarding, Media Reception, and Real-Crypto Test Coverage Audit
- Issue type: `test-coverage-gap`
- Output doc path: `Test-Flight-Improv/85-group-onboarding-and-crypto-test-coverage.md`
- Related references:
  - `Test-Flight-Improv/18-group-discussion-reliability-audit.md`
  - `Test-Flight-Improv/20-group-discussion-reliability-closure-reference.md`
  - `Test-Flight-Improv/21-announcement-reliability-closure-reference.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_messaging_test_matrix_1to1_and_group_with_media.md`
  - `Test-Flight-Improv/50-two-simulator-user-journey-tests.md`
  - `Network-Arch/Resilient-libp2p-TDD-Plan.md`

---

# 2. Problem Statement

The Group feature (Discussion + Announcement) has a broad but uneven test
suite. Unit and fake-network coverage of text messaging, membership state
machines, and offline drain is strong. But several scenarios that matter
most for **end-user trust at the boundary of joining a group** are either
unverified or only proven with cryptography bypassed. Two specific gaps are
the immediate concern for this audit:

1. **A new member joining an existing group is never verified to receive
   subsequent media** (image, video, or voice) sent into that group. The
   send-side payload path is covered, and existing-member text fan-out is
   covered, but no test exercises a freshly-added user receiving a media
   message from a pre-existing member.

2. **The cryptographic key exchange that runs when a new user is added is
   never verified as a complete group-onboarding flow with real
   ML-KEM-768 + AES-256-GCM.** The Go crypto and bridge layers do verify
   ML-KEM and group AES-GCM round-trips, but the Dart fake-network group
   tests still use fake/passthrough crypto paths. The full path
   "Bob joins → receives ML-KEM-encrypted group key → accepts the key →
   decrypts a subsequent group message" is not asserted as one integrated
   Flutter group-onboarding scenario, and no such scenario runs in the
   standard CI gate.

The first pass through TC-1 through TC-21 covers the main onboarding surface,
but five additional user-visible edge cases still matter before this spec can
be treated as complete: reaction fan-out to a newly-added member, quoted
replies whose parent message predates the join, admin-add/send races at the
epoch boundary, media recovery through the foreground-push drain path, and a
real-crypto re-add-after-rotation decrypt proof.

In addition, the simulator/integration coverage that exercises the real Go
P2P + GossipSub + circuit relay stack is not part of the standard CI gate.
The CLI-backed recovery test silently skips when its peer fixture is unset,
and the multi-device harness requires fixture orchestration outside the
standard group gate, so regressions in real network behavior go undetected
automatically.

A follow-up codebase review also found that the existing paired
two-simulator group harness is useful but not sufficient by itself: several
orchestrator checks currently pass on publish success or rotation execution
even when Bob's receive-side evidence is partial or pending. That means the presence of
`group_smoke_alice_harness.dart`, `group_smoke_bob_harness.dart`, and
`run_routing_smoke_e2e.dart` should be treated as partial evidence until the
missing onboarding scenarios are added and the pass criteria require
receiver-visible outcomes.

The simulator coverage is therefore not sufficient against the repo's mobile
network-resilience expectations. The missing device-context proof is not just
"some simulator test exists"; it is the combination of group catch-up after
resume, announcement catch-up for offline readers, exactly-once recovery when
live and inbox paths both deliver, and fixture-backed real-network execution
that fails clearly when its prerequisites are unavailable.

Kanban task `0346d` added a simulator-audit view of the same risk. Its absent
and partial findings broaden the simulator closure bar beyond onboarding crypto:
true two-simulator Discussion and Announcement UI journeys, admin add/remove
with stale notification/deep-link denial, full media send/download/render
coverage after restart, OS-level group notification routing, relay/libp2p
failover, out-of-order replay, same-account multi-device convergence, and
failure/recovery UI states are still not proven by recurring device-context
tests.

This is a product-trust problem because group onboarding is the moment a new
member forms a first impression of the group. If that member receives no
media, decrypts nothing, or only sees future text, the product fails its
core promise even though every component test passes.

---

# 3. Impact Analysis

- **Users joining groups mid-conversation** (the most common onboarding
  flow) cannot be relied on to receive image, video, or voice messages sent
  to the group after they join. There is no automated proof of this path.
- **Admins adding new members** cannot be relied on to have completed the
  full group-onboarding key exchange as a user-visible flow. Lower-level Go
  tests prove the ML-KEM and AES-GCM primitives, but the app-layer group
  add/invite tests do not prove that the newly-added recipient accepts the
  delivered group key and decrypts a subsequent group message.
- **Forward secrecy on member removal** is only proven at the network layer
  (unsubscribe + `groupNotFound` on send). A removed member who retains
  their last group epoch key has no negative test confirming they cannot
  decrypt a post-rotation ciphertext.
- **Real-network regressions** (rendezvous discovery latency, GossipSub
  mesh formation, circuit relay path) cannot be caught by the current CI
  gate because the group gate is host-side fake-network coverage. The
  `nightly` pool lists one CLI-backed real-bridge group test, but that pool
  is not invoked by `groups` or `all`, and direct runs of the test can
  silently skip when the fixture is absent.
- **New-member edge cases around message context and side channels** can
  regress silently: reactions may not fan out to the newly-added reader,
  quoted replies can reference a parent the reader is not allowed to backfill,
  and foreground-push media recovery can behave differently from live media
  delivery.
- **Concurrent membership/message timing** is not pinned. If an admin adds a
  member while an existing member sends at the epoch boundary, the product
  contract for whether the new member receives that message is not captured by
  an automated test.
- **Simulator sufficiency is currently overstated** if it is judged by the
  presence of harness files alone. The existing set does not yet give a
  recurring fixture-backed signal for group onboarding over real GossipSub,
  real-crypto join/decrypt, announcement offline-reader catch-up, or
  exactly-once live+inbox recovery. Some two-simulator checks also pass on
  partial delivery, sender-side success, or rotation execution while
  receive-side delivery is still incomplete, so their pass criteria must be
  tightened before they count as sufficient user experience proof.
- **Notification and deep-link trust** can regress silently for group flows.
  Existing notification-open coverage proves useful pieces, but the simulator
  audit still lacks foreground/background/terminated group-message and invite
  journeys with inbox drain, mute handling, active-conversation suppression,
  removed/dissolved-group suppression, and stale-tap access denial.
- **Same-account multi-device consistency** is not proven on simulator. Fake
  tests cover convergence, but there is no recurring phone/tablet-style proof
  that sent history, membership state, unread state, mute state, and
  notification behavior stay consistent across devices for the same identity.
- **Relay/libp2p and replay ordering failures** remain under-specified at the
  simulator layer. Direct-to-relay fallback, relay-down behavior, multi-relay
  failover, partition-heal recovery, duplicate live+inbox delivery, and
  out-of-order replay need receiver-visible assertions rather than sender-side
  success or skipped fixture runs.
- **Failure/recovery UI states** are mostly host-side evidence today. Publish
  failures, inbox-store failures, zero-peer sends, upload failures, rapid
  pause/resume, and restart with pending group sends/media still need
  simulator-visible assertions before they count as user-journey coverage.
- **Scope:** affects every group, every announcement, every onboarding
  flow, and every key rotation. Affects iOS and Android equally because the
  Go bridge is the canonical implementation.
- **Cost of the gap:** silent regressions in onboarding, media delivery, or
  key derivation can ship without being caught; user-visible failures are
  the first signal.

---

# 4. Current State

## 4.1 Existing tests (what we have)

### Unit tests

- `test/features/groups/application/group_message_listener_test.dart` —
  text, quoted reply, dedupe, malformed data, system membership events,
  watermark ordering, notification suppression, media-download trigger.
- `test/features/groups/application/send_group_message_use_case_test.dart`
  — happy-path send, FLOW timing events, `groupNotFound`, `groupDissolved`,
  unauthorized announcement send, missing bootstrap key, recovery gate,
  media attachments in publish payload, inbox store ordering, publish/inbox
  failure, concurrent send gating.
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
  — incoming message persistence, removedAt cutoff, dedupe.
- `test/features/groups/application/create_group_with_members_use_case_test.dart`
  — group creation with ML-KEM-keyed contacts, partial save failure,
  membership limit, announcement type.
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
  — distribution-before-broadcast invariant, per-non-self-member
  `message.encrypt` call count.
- `test/features/groups/application/add_group_member_use_case_test.dart`
  and `remove_group_member_use_case_test.dart` — admin-only enforcement,
  member save + bridge call.
- `test/features/groups/application/rejoin_group_topics_use_case_test.dart`
  — `group:join` issued for each active group on watchdog restart.
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  — cursor pagination, dedupe, multi-group bounds, and encrypted replay
  parsing for mixed image/video/GIF/file/audio attachment descriptors.
- `test/features/groups/application/send_group_reaction_use_case_test.dart`
  — reaction send + bridge call + repo save.
- `test/features/groups/application/handle_incoming_group_reaction_use_case_test.dart`
  — reaction upsert/remove, malformed payload handling, sender mismatch,
  dissolve cutoff, and replayed pre-dissolve reactions.
- `test/features/groups/application/dissolve_group_use_case_test.dart` —
  admin-only, dissolution state, broadcast.

### Widget tests

- `test/features/groups/presentation/group_info_wired_test.dart` —
  add/remove controls hidden for non-admins, remove confirmation flow,
  dissolved-state display, delete-local flow.
- `test/features/groups/presentation/group_conversation_wired_test.dart` —
  current-user removal notice and route exit, recovery gate behavior.

### Fake-network integration tests (all bypass real group crypto)

- `test/features/groups/integration/group_messaging_smoke_test.dart` —
  3-user fan-out, 4-user round-robin, simultaneous sends, same-sender
  ordering, quoted-reply fan-out, app-restart persistence, and late-joiner
  no-backfill/future-only text delivery.
- `test/features/groups/integration/group_membership_smoke_test.dart` —
  admin removes member; removed member cannot send; leave + promote;
  concurrent admin-change convergence; multiple adds; add-member syncs all
  member lists; removed-while-offline inbox drain; re-add after removal with
  current fake-network epoch state and no removed-period traffic.
- `test/features/groups/integration/group_resume_recovery_test.dart` —
  offline inbox drain (partial delivery), dedupe live+inbox, retry failed
  messages, inbox-store failure, stuck-sending recovery, key rotation +
  post-rotation receive, announcement image/media and voice send via widget,
  announcement offline-reader resume recovery, temporary partition→inbox→heal
  recovery, unread dedupe, multi-group drain bounds, removed-while-offline.
  These are still fake-network/widget-backed tests, not real Go P2P simulator
  proof.
- `test/features/groups/integration/invite_round_trip_test.dart` —
  invite send/receive, bootstrap key persistence, multiple-member config,
  remove→rotate→re-invite on the rotated fake/passthrough epoch, and
  new-member history remaining future-only while post-join replay is allowed.
- `test/features/groups/integration/announcement_happy_path_test.dart` —
  announcement create, admin send, reader read-only receive, member reaction,
  and admin-posted GIF/image receive through fake-network delivery.
- `test/features/groups/integration/group_reaction_roundtrip_test.dart` —
  group reaction publish/listener round-trip and dissolved-group rejection;
  this proves a newly-added member can react to a post-join message, but it
  does not prove reactions fan out **to** a newly-added member as recipient.
- `test/features/groups/integration/group_multi_device_convergence_test.dart`
  — fake-backed same-user multi-device convergence for group state; useful
  lower-layer coverage, but not a real simulator phone/tablet proof and not
  sufficient for device-local mute, unread, or notification behavior.

### Go crypto / bridge tests (real primitives, not full onboarding)

- `go-mknoon/crypto/mlkem_test.go` and `go-mknoon/bridge/bridge_test.go`
  — ML-KEM-768 encrypt/decrypt round-trip and wrong-key failure.
- `go-mknoon/crypto/group_test.go` and `go-mknoon/bridge/bridge_test.go`
  — AES-256-GCM group encrypt/decrypt round-trip, wrong-key failure,
  tampered ciphertext, tampered nonce, invalid input behavior, and large
  plaintext crypto round-trip.
- `go-mknoon/node/pubsub_decryption_failure_test.go` — node-level group
  subscription emits `group:decryption_failed` and does not emit
  `group_message:received` for wrong local key, tampered nonce, or tampered
  ciphertext.
- `go-mknoon/node/pubsub_key_rotation_grace_test.go` — node validator accepts
  previous-epoch envelopes during the configured grace window and rejects them
  after grace expires. This is useful rotation evidence, but it is not the
  removed-member retained-key negative decrypt proof.

### Integration / simulator tests (real Go bridge and simulator/fake partial evidence)

- `integration_test/group_recovery_e2e_test.dart` — uses
  `FakeGroupPubSubNetwork`; not a real-network test despite its directory.
- `integration_test/foreground_group_push_drain_test.dart` — foreground
  push drains targeted group inbox for text payloads, dedupe, 1:1 isolation;
  it uses fake bridge/network plumbing and does not cover a newly-added
  member receiving media through the push drain path.
- `integration_test/notification_open_ui_smoke_test.dart` — notification-open
  smoke coverage for group invite routing and group-message tap after inbox
  drain. It does not cover the full OS group-notification matrix for
  foreground/background/terminated states, mute, active conversation
  suppression, removed/dissolved group suppression, or stale notification taps.
- `integration_test/scripts/run_foreground_group_push_simulator_smoke.dart`
  with `foreground_group_push_simulator_alice_harness.dart` /
  `foreground_group_push_simulator_bob_harness.dart` — two-simulator real
  bridge/P2P stack proof for text foreground group push gap recovery and
  live+push dedupe. It imports the group fixture/key, is text-only, is not in
  a named gate, and does not cover new-member media.
- `integration_test/media_message_journey_e2e_test.dart` — simulator/widget
  journey proves an existing group recipient can see a sent image in the group
  thread through fake-network delivery. It is useful media UI evidence, but
  it is not new-member onboarding, video/voice coverage, or real Go network
  proof.
- `integration_test/media_stable_id_smoke_test.dart` — simulator/widget
  coverage proves an announcement image keeps stable attachment IDs for sender
  and reader through fake-network delivery. It is not a real-network,
  new-reader onboarding, or real-crypto proof.
- `integration_test/benchmark_encryption_harness.dart` — simulator benchmark
  using `GoBridgeClient` for ML-KEM keygen, message encrypt/decrypt, and
  group encrypt/decrypt assertions. This is real-bridge primitive evidence
  and performance telemetry, not group-onboarding correctness evidence.
- `integration_test/group_recovery_cli_e2e_test.dart` — real
  `GoBridgeClient` + P2P node; **silently skips** when `CLI_PEER_FIXTURE`
  is unset in direct runs. The adjacent `run_group_recovery_e2e.dart`
  wrapper provisions the fixture, but that wrapper is not part of the
  standard `groups` gate.
- `integration_test/multi_relay_failover_test.dart` — group recovery under
  multi-relay failover, but only when `MKNOON_RELAY_ADDRESSES` provides at
  least two relays. Without that fixture it is skipped, so it is partial
  evidence rather than a recurring relay/libp2p regression signal.
- `integration_test/group_smoke_alice_harness.dart` +
  `integration_test/group_smoke_bob_harness.dart` — paired two-simulator
  harness covering G1 publish, G2 warm burst ×5, G3 bidirectional, G4
  offline→inbox→drain, G5 full lifecycle, G6 discovery timing, G7 key
  rotation under traffic, G8 flood publish. Current orchestrator pass
  criteria are permissive for some rows: G2 accepts 3/5 deliveries, G4 can
  pass with Bob receipt still pending, G5 only checks timeline length and can
  include pending receive entries, G7 can pass when rotation ran even if Bob
  did not receive both messages, and G8 can pass on Alice publish success
  regardless of Bob receipt timing.
- `integration_test/group_multi_device_real_harness.dart` — same-user
  two-device convergence; requires a CLI peer fixture and fails when that
  fixture is absent, but is not part of the standard group gate.
- `integration_test/benchmark_group_publish_harness.dart` — performance
  benchmark, not a correctness gate.

## 4.2 Concrete coverage gaps

### A. New-member onboarding scenarios — the user's named gaps

| # | Scenario | Status | Evidence |
|---|---|---|---|
| A-1 | New member joins existing group → receives subsequent **text** from existing members | COVERED | `group_messaging_smoke_test.dart` "late joiner receives messages only after joining"; `group_membership_smoke_test.dart` separately proves new-member participation and member-list convergence |
| A-2 | New member joins existing group → receives subsequent **image** from existing members | MISSING | No test exists |
| A-3 | New member joins existing group → receives subsequent **video** from existing members | MISSING | No test exists |
| A-4 | New member joins existing group → receives subsequent **voice note** from existing members | MISSING | No test exists |
| A-5 | New member receives history backfill OR explicit "no backfill" policy is asserted | COVERED (discussion / invite bootstrap) | `group_messaging_smoke_test.dart` late joiner receives only post-join text; `invite_round_trip_test.dart` asserts invite bootstrap does not preload pre-join history and allows post-join replay |
| A-6 | New member's ML-KEM key exchange completes end-to-end with **real crypto**, and Bob decrypts a subsequent group message using the delivered group key | MISSING (integrated flow) | Go crypto/bridge tests cover primitives; fake-network group tests use fake/passthrough crypto; current real-network harnesses do not assert the full new-member key-acceptance + decrypt path |
| A-7 | New member added to **announcement** group receives subsequent admin-posted media | PARTIAL | `announcement_happy_path_test.dart` covers admin-posted GIF/image after a reader is added, and `group_resume_recovery_test.dart` covers announcement image/media and voice recovery through fake-network/widget paths; no new-reader video, no announcement no-backfill assertion, no real-network simulator assertion, and no real-crypto proof |
| A-8 | Multiple members selected in one user-facing group-creation/add flow all converge on identical group key epoch and can decrypt the same message | PARTIAL | `create_group_with_members_use_case_test.dart` checks per-recipient invite/encrypt behavior; no end-to-end multi-recipient decrypt proof |
| A-9 | Re-joining after leaving — re-added member is on the current epoch, not a stale one | PARTIAL | `group_membership_smoke_test.dart` asserts re-add on fake-network epoch 2 with no removed-period traffic; `invite_round_trip_test.dart` covers remove→rotate→re-invite on a passthrough epoch; real-crypto/simulator decrypt proof remains missing |
| A-10 | Reaction fan-out reaches a newly-added member after they join | PARTIAL | Reaction unit tests and `group_reaction_roundtrip_test.dart` cover reaction handling and a newly-added member sending a reaction; no onboarding scenario proves a newly-added member receives another member's reaction |
| A-11 | Quoted reply references a pre-join parent message | PARTIAL | Quoted-message propagation and missing-parent UI fallback are covered separately; no test combines new-member no-backfill with a post-join quoted reply whose parent is absent |
| A-12 | Concurrent admin add + existing-member send at the epoch boundary has a deterministic user-visible contract | MISSING | No test races member add/key acceptance against a same-epoch group send |
| A-13 | Newly-added member receives post-join media through the foreground-push drain path | MISSING | `foreground_group_push_drain_test.dart` covers text inbox drain, dedupe, and 1:1 isolation only |
| A-14 | Re-added member after rotation decrypts the current epoch with real crypto | MISSING | TC-8 records persisted epoch state as partial evidence and TC-13 covers first-add real decrypt; no test proves re-added Bob decrypts an E2 message after removal/rotation/re-add |

### B. Cryptography & forward-secrecy scenarios

| # | Scenario | Status |
|---|---|---|
| B-1 | Initial group epoch key derivation on creation | PARTIAL: Go group-key generation is covered; app-layer creation tests cover persistence/call behavior, not multi-recipient decrypt proof |
| B-2 | Key rotation on member **add** — current product behavior (rotation or no rotation) is asserted | MISSING |
| B-3 | Key rotation on member **remove** — distribution-before-broadcast ordering | COVERED |
| B-4 | Removed member retaining old key **cannot decrypt** post-rotation ciphertext (ciphertext-level forward secrecy) | PARTIAL: removed members are excluded from key update distribution, and Go validator rejects previous epochs after grace; direct retained-old-key decrypt failure for removed Bob is missing |
| B-5 | Wrong/missing/corrupt ciphertext on receive — graceful failure, no crash, listener tolerates malformed envelope | COVERED at Go/node decrypt boundary; PARTIAL at Dart app boundary |
| B-6 | Replay protection — duplicate encrypted envelope with same nonce is rejected beyond ordinary messageId dedupe, or the product contract explicitly records messageId dedupe as the replay boundary | MISSING |
| B-7 | Membership-event signature verification at the envelope layer, not just sender-is-admin at the app layer | PARTIAL: generic Go group-envelope signature validation and app-layer admin authorization are covered; a membership-system-event-specific app integration assertion for forged signed events is missing |
| B-8 | Real ML-KEM-768 + AES-256-GCM round-trip verified at least once in an automated test | PARTIAL: primitive and bridge round-trips covered; integrated group-onboarding decrypt proof missing |
| B-9 | Re-add-after-rotation decrypt proof — Bob removed at E1, re-added at E2, and decrypts only the current epoch with real crypto | MISSING |

### C. Media scenarios beyond new-member onboarding

| # | Scenario | Status |
|---|---|---|
| C-1 | Existing member receives **image** sent to discussion group via fan-out | PARTIAL (send-side media payload, incoming media persistence, inbox media parsing, and fake/simulator UI image delivery are covered; new-member image onboarding and real Go network delivery are not pinned) |
| C-2 | Existing member receives **video** sent to discussion group | PARTIAL (inbox parsing for video descriptors exists; live discussion-group fan-out is not pinned) |
| C-3 | Existing member receives **voice note** sent to discussion group | PARTIAL (send-side voice payload and inbox/audio descriptor parsing exist; live discussion-group fan-out is not pinned) |
| C-4 | Long text payload (multi-kilobyte) — fragmentation / single-publish behavior | PARTIAL: Go group crypto covers 1 MB plaintext round-trip; app/network publish and delivery behavior for long group text is not pinned |
| C-5 | Message retention boundary — backlog policy on receive | MISSING (planning matrix flags this) |

### D. Network and transport — beyond fake network

| # | Scenario | Status |
|---|---|---|
| D-1 | GossipSub mesh formation — measurable peer count after settle | PARTIAL (smoke harness asserts delivery; not mesh state) |
| D-2 | Rendezvous discovery — register/discover roundtrip | MISSING (only observable in CLI harness) |
| D-3 | Circuit relay path — DialPeerViaRelay correctness | MISSING (only observable in CLI harness) |
| D-4 | 3-party fan-out (A/B/C) on real GossipSub | MISSING (planning matrix flags this as P0) |
| D-5 | Partition / heal — dropped live delivery later recovers through durable group inbox drain | PARTIAL (fake-network partition→inbox→heal recovery is covered with cursor order and resumed live delivery; real-network simulator/GossipSub partition recovery is not pinned) |
| D-6 | New member joins over real GossipSub (subscription timing, discovery latency) | MISSING |
| D-7 | Simulator resilience matrix for Group + Announcement: group catch-up after resume, announcement catch-up for offline readers, and exactly-once recovery when live + inbox both deliver | PARTIAL (foreground push drain, fake-network drain coverage, the foreground-push two-simulator smoke, and manual two-simulator harnesses exist, but no recurring real-network simulator proof covers the full matrix with strict receive-side assertions) |
| D-8 | Foreground push drains newly-added member media, not only text | MISSING (`foreground_group_push_drain_test.dart` is text-only and does not combine add-member with media payloads) |
| D-9 | True two-simulator Discussion UI journey: create/invite/accept, bidirectional text, group list, unread/read, restart, and catch-up | PARTIAL (host-side fake-network and paired harness pieces exist, but no full UI journey pins all receiver-visible outcomes) |
| D-10 | True two-simulator Announcement permissions: admin sends text/media/voice, reader receives/reacts, reader compose is blocked, and no optimistic bubble is stranded | PARTIAL (fake/widget Announce coverage exists; simulator UI permission and media journey remains missing) |
| D-11 | Admin add/remove end-to-end on simulator, including membership propagation, removed-user route exit, no new notifications, and stale notification/deep-link denial | PARTIAL (host-side membership coverage exists; simulator notification/access denial is missing) |
| D-12 | Real relay/libp2p recovery matrix: direct-to-relay fallback, relay down, multi-relay failover, partition heal, duplicate live+inbox delivery, and out-of-order replay | PARTIAL (`multi_relay_failover_test.dart` is env-gated; fake-network recovery covers pieces; out-of-order simulator replay is not pinned) |
| D-13 | Same-account multi-device simulator consistency for sent history, membership, unread, mute, and notifications | PARTIAL (`group_multi_device_convergence_test.dart` is fake-backed; real simulator multi-device proof is missing) |
| D-14 | Failure/recovery UI flows: publish failure, inbox-store failure, zero peers, upload failure, rapid pause/resume, and restart with pending group sends/media | PARTIAL (host tests cover many branches; simulator UI coverage is thin) |
| D-15 | OS-level group notification and deep-link routing across foreground, background, and terminated app states | PARTIAL (`notification_open_ui_smoke_test.dart` covers invite and group-message tap pieces; full group notification matrix is missing) |

### E. CI gate sufficiency

- The standard `./scripts/run_test_gates.sh groups` gate runs host-side
  `flutter test` group suites from `test/features/groups/integration/`.
  Those are fake-network tests; the gate does not run any simulator/E2E
  group test.
- The standard `./scripts/run_test_gates.sh all` gate also does not execute
  the `NIGHTLY_ONLY_TESTS` pool, so listing
  `integration_test/group_recovery_cli_e2e_test.dart` there does not make it
  part of the normal `all` regression gate.
- `integration_test/group_recovery_cli_e2e_test.dart` silently returns
  success when `CLI_PEER_FIXTURE` is absent in direct runs. The
  `integration_test/scripts/run_group_recovery_e2e.dart` wrapper provisions
  the CLI fixture, but the wrapper is not invoked by the standard group gate.
  `group_multi_device_real_harness.dart` requires a fixture and fails when it
  is absent, but it is also outside the standard group gate. Neither behavior
  gives CI a fixture-backed real-network regression signal by default.
- The two-simulator alice/bob harnesses require manual orchestration
  (`dart run integration_test/scripts/run_routing_smoke_e2e.dart`) and are
  not invoked by any automated gate. They also need stricter pass criteria
  before they count as simulator sufficiency: G2 currently accepts 3/5
  receives, G4 tolerates pending Bob receipt, G5 can pass with pending or
  missing receive entries because only timeline length is checked, G7 can pass
  on rotation execution if both receive checks are false, and G8 can pass on
  Alice publish success even when Bob receipt is pending.
- The current named gates do not encode a minimum simulator sufficiency bar
  for Group + Announcement. For this audit, that bar is TC-13 real crypto,
  TC-17 new-member join over real GossipSub, TC-20 group/announcement
  catch-up + exactly-once recovery, TC-21 recurring gate execution,
  TC-25 foreground-push media drain for newly-added members, and the
  TC-27 through TC-34 device-context rows added from the `0346d` simulator
  audit.
- Net effect: zero recurring fixture-backed automated regression coverage
  for the real Go P2P + GossipSub + circuit relay stack on group flows.

---

# 5. Scope

## 5.1 In-scope

This spec covers test-coverage closures for:

- New-member onboarding paths for **all** message types (text, image,
  video, voice) on both discussion and announcement groups.
- Preservation or extension of the existing history-backfill-policy
  assertions wherever new onboarding/media/announcement tests introduce a
  new boundary.
- One automated end-to-end real-crypto proof of ML-KEM key exchange and
  group message decryption by a freshly-added member.
- One ciphertext-level forward-secrecy negative test for removed members,
  run at a layer that can observe real encrypted payloads.
- Existing-member media reception (image, video, voice) for discussion
  groups, where current coverage is announcement-image only.
- New-member side-channel and context behavior: reaction fan-out after join,
  quoted replies that point at missing pre-join parents, and deterministic
  handling of an admin-add/member-send race at the epoch boundary.
- Foreground-push recovery for post-join media delivered to a newly-added
  member through the group inbox drain path.
- Re-add-after-rotation behavior where Bob returns after removal and decrypts
  the current epoch with real crypto rather than stale epoch material.
- A simulator-level new-member-joins scenario that runs over the real Go
  bridge.
- A simulator-level Group + Announcement resilience proof covering group
  catch-up after resume, announcement catch-up for offline readers, and
  exactly-once recovery when live and inbox paths both deliver.
- True two-simulator Discussion and Announcement UI journeys where
  invite/accept, read/write permissions, media visibility, unread/read state,
  restart catch-up, and receiver-visible delivery are asserted together.
- Admin add/remove simulator behavior, including membership propagation,
  removed-user route exit, blocked sends, no new removed-user notifications,
  and stale notification/deep-link access denial.
- Group notification/deep-link journeys for foreground, background, and
  terminated app states, scoped to group invites and group messages.
- Relay/libp2p device-context recovery, including direct-to-relay fallback,
  relay-down behavior, multi-relay failover, partition heal, duplicate
  live+inbox delivery, and out-of-order replay.
- Same-account multi-device consistency for group sent history, membership,
  unread state, mute state, and notification behavior.
- Failure/recovery UI flows for publish failure, inbox-store failure, zero
  peers, upload failure, rapid pause/resume, and restart with pending group
  sends or media.
- Closing the CI-gate sufficiency gap so at least one real-network group
  scenario runs as part of an automated gate (nightly or pre-release).

## 5.2 Out-of-scope

- Re-implementing or refactoring the group feature itself. This spec adds
  tests; it does not change product behavior.
- Performance benchmarks beyond what
  `benchmark_group_publish_harness.dart` already provides.
- Replacing fake or passthrough crypto everywhere. The bypass is fine for
  unit and fake-network tests; the gap is that **at least one integrated
  group-onboarding** path must also be proven with the real crypto bridge.
- Treating plaintext fake-network listener tests as ciphertext-level crypto
  evidence. Those tests can close app-layer behavior only; integrated
  ML-KEM/AES-GCM group-onboarding claims require the real bridge, while
  primitive crypto claims can cite the existing Go crypto/bridge tests.
- 1:1 messaging tests — out of scope for this audit.
- Push-notification flows outside group invites and group-message journeys,
  such as generic push-token registration or unrelated 1:1 push behavior.
- Building a new orchestration framework. New simulator rows may add focused
  harness files, but they should reuse the existing filesystem-signal pattern,
  `FakeGroupPubSubNetwork`, `GroupTestUser`, and the current alice/bob
  harness conventions.

## 5.3 Constraints

- Tests must follow the project's existing patterns: unit tests in
  `test/features/groups/application/`, widget tests in
  `test/features/groups/presentation/`, fake-network integration in
  `test/features/groups/integration/`, simulator harnesses in
  `integration_test/`.
- Tests must not duplicate existing coverage — every new test below has
  been chosen because the matching scenario is not already covered.
- Real-crypto test must use `GoBridgeClient` against the live Go bridge,
  matching the pattern in `group_recovery_cli_e2e_test.dart`.
- Real-crypto onboarding closure must not pre-save or fixture-inject Bob's
  group key as the proof mechanism. Bob must receive the group key through the
  app's group invite/key-acceptance path and use that accepted key to decrypt
  the subsequent group message.
- Real-crypto and real-network acceptance evidence may be skipped in local
  ad hoc runs when the peer fixture is absent, but a skipped fixture-backed
  test does **not** count as closure for this audit or for CI coverage.
- Ciphertext, wrong-key, and same-nonce assertions must run at a layer that
  sees encrypted payloads or bridge crypto results. The current Dart
  `GroupMessageListener` receives already-decrypted/plaintext maps in
  fake-network tests, so listener-only tests cannot close B-4, B-6, or the
  integrated group-onboarding part of B-8. Dart listener tests can only
  supplement the Go/node evidence for B-5.
- Member-add epoch tests must use the repo's existing user-facing flows
  (`createGroupWithMembers(...)` and/or repeated `addGroupMember(...)`);
  this spec does not assume a separate `addGroupMembers(...)` API exists.
- Quoted-reply onboarding tests must assert both sides of the contract: Bob
  receives the post-join reply, and the missing pre-join parent renders through
  the established unavailable-parent fallback instead of leaking history.
- Concurrent add/send tests must pin the current product contract once decided:
  either the same-epoch message is intentionally excluded from Bob, or Bob
  receives it exactly once with the accepted epoch. The test must not accept
  nondeterministic outcomes.
- Each new test must include FLOW event assertions where the product code
  emits them, to remain consistent with the established testing style.
- New simulator scenarios must reuse the existing alice/bob harness pair
  pattern (filesystem signals for synchronization) rather than introducing
  a new orchestration layer.
- Simulator scenarios that claim delivery or recovery must fail on missing
  receive-side evidence. Sender-side publish success, rotation execution, or
  a pending receiver result is useful telemetry but does not satisfy the
  user-visible experience bar for this audit.
- Simulator sufficiency for this audit requires the combined evidence of
  TC-13, TC-17, TC-20, TC-21, and TC-25. Any smaller set may be useful partial
  evidence, but should not be recorded as sufficient simulator coverage.

---

# 6. Test Cases

The following are the specific test cases this spec proposes. Each one is
written as a scenario, not as an implementation outline. Test files
referenced are suggested locations; the implementer may consolidate where
it makes sense.

## 6.1 New-member onboarding — text and media reception

### TC-1: Newly-added member receives subsequent text message
- **File:** `test/features/groups/integration/group_new_member_onboarding_test.dart`
- **Setup:** Alice creates discussion group with herself only. Alice sends
  `M0` text message. Alice adds Bob (with ML-KEM-keyed contact). Alice
  sends `M1` text message.
- **Assertion:** Bob's group repo contains `M1`. Bob's group repo does
  **not** contain `M0` (no backfill).
- **Status today:** A-1 and discussion no-backfill are covered by existing
  late-joiner/future-only tests. This case remains useful as a consolidated
  preservation assertion if the new media-onboarding suite is added.

### TC-2: Newly-added member receives subsequent **image** message
- **File:** same as TC-1
- **Setup:** Alice + Bob in group from TC-1. Alice sends image attachment
  via `sendGroupMessage(...)` with media payload.
- **Assertion:** Bob's `group_message_listener` produces a message with
  the expected media descriptor; Bob's media-download trigger fires; the
  resulting feed/conversation shows the image.
- **Status today:** A-2 missing.

### TC-3: Newly-added member receives subsequent **video** message
- **File:** same as TC-1
- **Setup:** Same as TC-2 with video attachment.
- **Assertion:** Same as TC-2 with video.
- **Status today:** A-3 missing.

### TC-4: Newly-added member receives subsequent **voice note**
- **File:** same as TC-1
- **Setup:** Same as TC-2 with voice attachment (`upload_pending` →
  uploaded → published).
- **Assertion:** Bob receives the voice attachment with the correct
  duration/encoding metadata.
- **Status today:** A-4 missing.

### TC-5: Announcement-group new reader receives subsequent admin-posted media
- **File:** `test/features/groups/integration/announcement_new_reader_onboarding_test.dart`
- **Setup:** Alice (admin) creates announcement group. Alice posts initial
  text `M0`. Alice adds Bob as reader. Alice posts image/GIF, video if
  supported by the group media path, and voice-note media as admin.
- **Assertion:** Bob receives every post-join admin media item with intact
  descriptors and does not receive `M0`.
- **Status today:** A-7 partial. Existing coverage proves a reader added
  before the send receives an admin-posted GIF/image, and fake-network/widget
  recovery coverage proves announcement image/media and voice can survive
  resume fallback. It still does not pin announcement no-backfill onboarding,
  video coverage, real-network simulator delivery, or real-crypto proof.

### TC-6: History-backfill policy assertion
- **File:** same as TC-1 (folded into the same suite)
- **Setup:** Alice posts 5 text messages, then adds Bob.
- **Assertion:** Bob's repo has zero messages with timestamps before his
  `joinedAt`. This pins the no-backfill policy as a contract so future
  changes that accidentally leak history will fail.
- **Status today:** A-5 is covered for discussion groups by
  `group_messaging_smoke_test.dart` and for invite bootstrap by
  `invite_round_trip_test.dart`. Keep this case only if the new media or
  announcement onboarding suites need their own no-backfill preservation
  assertion.

### TC-7: Multiple members added in one batch all converge on the same epoch
- **File:** same as TC-1
- **Setup:** Alice creates a group with Bob and Charlie selected in the
  same user-facing creation/add flow, using the repo's existing
  `createGroupWithMembers(...)` path or repeated `addGroupMember(...)`
  calls if that is the shipped flow. Alice sends one message after both
  members are active.
- **Assertion:** Bob and Charlie both receive the message and have
  identical observable group epoch evidence, such as persisted latest-key
  state or delivered message `keyGeneration`. Per-recipient invite/encrypt
  call-count evidence remains useful at unit level, but does not replace
  receive/decrypt proof.
- **Status today:** A-8 partial.

### TC-8: Re-joining after leaving — epoch correctness
- **File:** same as TC-1
- **Setup:** Bob in group at epoch `E1`. Bob leaves. Alice rotates
  (epoch `E2`). Alice re-adds Bob. Alice sends message.
- **Assertion:** Bob receives the post-rejoin message at the current epoch
  (`E2` in this scenario), not the stale epoch, and Bob's repo does not
  show messages sent during his absence. Fake-network evidence may assert
  persisted epoch state; real decrypt proof belongs to TC-13.
- **Status today:** A-9 partial. `group_membership_smoke_test.dart` and
  `invite_round_trip_test.dart` cover the fake/passthrough epoch-state
  version of this behavior; real-crypto and simulator decrypt proof remains
  open.

## 6.2 Cryptography & forward secrecy

### TC-9: Removed member with retained old key cannot decrypt post-rotation ciphertext
- **File:** `integration_test/group_real_crypto_onboarding_test.dart` or a
  Go bridge crypto test with equivalent real-ciphertext visibility.
- **Setup:** Bob is a member at epoch `E1` and retains the `E1` group key.
  Alice removes Bob, the remaining members advance to `E2`, and Alice sends
  a post-rotation message. The test captures the real encrypted payload or
  bridge decrypt input and attempts decryption using Bob's retained `E1`
  material.
- **Assertion:** Decryption fails with no partial plaintext leak. If the app
  listener observes the failure path in that test layer, it must not insert
  a successful message row. A fake-network plaintext listener test does not
  satisfy this case.
- **Status today:** B-4 partial. Key-update distribution excludes removed
  members, and Go node validation rejects previous epochs after grace, but no
  test captures Bob's retained old key and proves it cannot decrypt a
  post-removal ciphertext.

### TC-10: Wrong/corrupt ciphertext on receive — graceful failure
- **File:** same as TC-9
- **Setup:** A real encrypted group payload is corrupted before decrypt
  (for example one ciphertext/tag byte is flipped) while the surrounding
  group/message metadata remains otherwise valid.
- **Assertion:** The decrypt path fails cleanly. If routed through the app
  listener, the listener does not crash and does not insert a successful
  message row. Diagnostic FLOW evidence should be asserted only where the
  product already emits it or where the implementation adds it as part of
  the product behavior.
- **Status today:** B-5 is covered at the Go/node decrypt boundary by
  `pubsub_decryption_failure_test.go` for wrong local key, tampered nonce,
  and tampered ciphertext. Dart app-boundary listener coverage remains only
  supplemental because fake-network tests do not see real ciphertext.

### TC-11: Replay protection — duplicate envelope with same nonce
- **File:** same as TC-9
- **Setup:** Replay the same encrypted envelope/nonce through the real
  decrypt-or-receive path.
- **Assertion:** The second receive is rejected or ignored by the product's
  declared replay boundary. If the current contract is messageId/content
  dedupe rather than nonce-level rejection, the test must assert that
  contract explicitly and the matrix must stop claiming nonce rejection is
  implemented.
- **Status today:** B-6 missing beyond ordinary messageId/content dedupe.

### TC-12: Membership-event signature verification at the envelope layer
- **File:** `test/features/groups/application/group_message_listener_signature_test.dart`
- **Setup:** Inject a `members_added` system event with a forged sender
  signature (sender claims to be admin but signature is invalid).
- **Assertion:** Listener rejects the event and does not mutate group
  membership state.
- **Status today:** B-7 partial. App-layer admin authorization already rejects
  unauthorized `member_added` / `member_removed` events, and Go validates
  generic group-envelope signatures. The remaining gap is a membership-system
  app integration assertion for forged signed membership events.

### TC-13: Integrated real-crypto onboarding — Bob joins, receives key, decrypts message
- **File:** `integration_test/group_real_crypto_onboarding_test.dart`
  (modeled on `group_recovery_cli_e2e_test.dart`)
- **Setup:** Two `GoBridgeClient` nodes against the real Go bridge. Alice
  creates a group and adds Bob (whose contact has a real ML-KEM public
  key produced by `mlkem.keygen`). Alice sends a plaintext-input message
  that the bridge encrypts with the new group epoch key. Bob receives it.
- **Assertion:** Bob's listener produces the original plaintext. The Go
  diagnostic events `group:discovery` and `group:publish_debug` show
  successful discovery, `topicPeers` ≥ 1 when the publish expects a live
  peer, and successful publish.
  No fake or passthrough crypto bridge involved, and no pre-saved or
  fixture-injected Bob group key can be used as the closure evidence.
- **CI note:** A local fixture skip is acceptable for developer machines,
  but it does not count as audit closure. The recurring gate that claims
  TC-13 evidence must provision the peer fixture or fail clearly.
- **Note:** This is the canonical closure for A-6 and the integrated
  onboarding portion of B-8. It does not replace the existing lower-level
  ML-KEM/AES-GCM primitive tests; it connects those primitives to the
  Flutter group-onboarding flow.
- **Status today:** A-6 missing; B-8 primitive/bridge coverage exists, but
  integrated group-onboarding decrypt proof is missing.

## 6.3 Existing-member media in discussion groups

### TC-14: Existing member receives image in discussion group
- **File:** `test/features/groups/integration/group_media_fanout_test.dart`
- **Setup:** Alice + Bob both already in discussion group from creation.
  Alice sends image.
- **Assertion:** Bob receives image with correct media descriptor.
- **Status today:** C-1 partial. Send-side media payload, incoming media
  persistence, inbox media parsing, and fake/simulator existing-member group
  image UI delivery are covered. Real Go network delivery, new-member image
  onboarding, and non-image media fan-out remain open.

### TC-15: Existing member receives video in discussion group
- **File:** same as TC-14
- **Status today:** C-2 partial. Inbox replay parsing covers video
  descriptors, but live discussion-group video fan-out is not pinned.

### TC-16: Existing member receives voice note in discussion group
- **File:** same as TC-14
- **Status today:** C-3 partial. Send-side voice payload and inbox/audio
  descriptor parsing are covered, but live discussion-group voice fan-out is
  not pinned.

## 6.4 Simulator / real-network scenarios

### TC-17: New member joins over real GossipSub mid-conversation (alice/bob simulator harness)
- **File:** add a new scenario `G9` to
  `integration_test/group_smoke_alice_harness.dart` and
  `integration_test/group_smoke_bob_harness.dart`
- **Setup:** Alice creates group alone, posts one message. Alice adds Bob
  (Bob enrolls and runs the second simulator instance). Alice posts text
  + image + voice.
- **Assertion:** Bob receives all three post-join messages. Bob does not
  receive the pre-join message. `topicPeers` ≥ 1 is measured via existing
  diagnostic events, and the orchestrator must fail if Bob's receive-side
  evidence is absent or pending.
- **Status today:** D-6 missing (the existing G1–G8 scenarios start with
  both peers already in the group from boot and do not cover adding Bob
  mid-conversation).

### TC-18: 3-party fan-out scenario with media (planning-matrix P0)
- **File:** a small simulator row that reuses the existing filesystem-signal
  harness pattern, such as `group_three_party_alice_harness.dart` +
  `_bob_harness.dart` + `_charlie_harness.dart` or one alice-side script that
  drives two passive peers.
- **Setup:** A creates group, adds B and C. A sends text + image. Both
  B and C receive.
- **Assertion:** Both B and C receive both messages. No duplicates. No
  partial fan-out.
- **Status today:** D-4 missing.

### TC-19: Partition / heal using existing `FakeGroupPubSubNetwork` hooks
- **File:** `test/features/groups/integration/group_partition_heal_test.dart`
- **Setup:** Bob is unavailable for live group delivery while Alice sends
  3 messages that are staged into the durable group inbox. Live delivery is
  restored, Alice sends one more message, then Bob's offline-inbox drain
  runs.
- **Assertion:** Bob ends up with all 4 messages exactly once. The 3
  dropped ones arrive via inbox drain; the 4th arrives live.
- **Status today:** D-5 partial. Fake-network partition→durable-inbox→heal
  behavior is already covered with cursor ordering and resumed live delivery;
  the remaining gap is the same recovery contract over the real
  bridge/GossipSub simulator path.

### TC-20: Simulator Group + Announcement recovery sufficiency matrix
- **File:** extend an existing fixture-backed simulator/orchestrated group
  recovery harness, or add an adjacent one if the existing harness cannot
  express all rows cleanly.
- **Setup:** Run a real-network simulator flow with the required fixture.
  The flow must include a group participant resuming and catching up missed
  group traffic, an announcement reader recovering admin-posted announcement
  traffic after being offline or unavailable for live delivery, and one
  message that is observable through both live and inbox paths.
- **Assertion:** Group catch-up and announcement catch-up both complete with
  the expected messages visible exactly once. The live+inbox overlap does
  not duplicate rows, unread counts, or media descriptors. The run uses the
  real bridge/network path needed for simulator sufficiency, not only
  `FakeGroupPubSubNetwork`.
- **Status today:** D-7 partial. Existing fake-network and foreground-push
  tests cover pieces of this behavior, and the paired simulator harness covers
  related group lifecycle paths. However, the current simulator assertions are
  too permissive on several rows and no recurring real-network simulator
  proof covers the full matrix with strict receive-side success criteria.

## 6.5 CI gate sufficiency closure

### TC-21: Add at least one real-network simulator scenario to an automated gate
- **What:** Wire the alice/bob smoke harness (or just G7 + new G9 from
  TC-17, plus the recovery matrix from TC-20) into a recurring nightly or
  pre-release gate with the required simulator/peer fixture. A skipped
  fixture-backed run does not count as passing evidence.
- **Status today:** E missing. `scripts/run_test_gates.sh groups` is
  host-side fake-network only, and `scripts/run_test_gates.sh all` does not
  execute the `NIGHTLY_ONLY_TESTS` pool where the CLI-backed group recovery
  test is listed.

## 6.6 Additional new-member onboarding edge cases

### TC-22: Reaction fan-out reaches a newly-added member
- **File:** `test/features/groups/integration/group_new_member_onboarding_test.dart`
  or extend `test/features/groups/integration/group_reaction_roundtrip_test.dart`
- **Setup:** Alice creates a discussion group, sends pre-join message `M0`,
  adds Bob, then sends post-join message `M1`. A current member reacts to
  `M1` after Bob is active.
- **Assertion:** Bob receives the reaction on `M1` exactly once and the
  reaction is visible through the same reaction repository/listener path used
  by the conversation UI. Bob does not receive reaction state for `M0` unless
  the product later changes the no-backfill policy.
- **Status today:** A-10 partial. Reaction parsing and round-trip behavior are
  covered, but not the newly-added-member-as-recipient onboarding case.

### TC-23: Quoted reply to a pre-join parent renders deterministically
- **File:** same as TC-22, plus a focused widget assertion if the repository
  layer cannot observe the missing-parent rendering state.
- **Setup:** Alice sends pre-join message `M0`. Alice adds Bob. Alice or
  another current member sends post-join reply `M1` with `quotedMessageId`
  pointing to `M0`.
- **Assertion:** Bob receives `M1` and the `quotedMessageId` is preserved.
  Bob's thread does not contain `M0`, and the UI renders the established
  unavailable-parent fallback for the quote preview instead of blank content,
  a crash, or leaked pre-join history.
- **Status today:** A-11 partial. Quoted-message propagation and missing-parent
  UI fallback are covered separately, but not as one onboarding scenario.

### TC-24: Concurrent admin add + member send race has a pinned contract
- **File:** `test/features/groups/integration/group_new_member_onboarding_test.dart`
  or `test/features/groups/integration/group_membership_smoke_test.dart`
- **Setup:** Alice starts adding Bob while an existing member sends message
  `M1` at the same membership/key epoch boundary.
- **Assertion:** The outcome is deterministic and product-approved. Either
  Bob intentionally does not receive `M1`, or Bob receives `M1` exactly once
  with the accepted epoch. Alice, Bob, and the existing sender converge on the
  same member list and no message remains stuck in sending or inbox limbo.
- **Status today:** A-12 missing.

### TC-25: Foreground push drains new-member media
- **File:** `integration_test/foreground_group_push_drain_test.dart`
- **Setup:** Alice adds Bob to a group. Bob is unavailable for live group
  delivery. Alice sends a post-join media message that is staged into the
  durable group inbox. A foreground group push for that message arrives while
  Bob is in the app.
- **Assertion:** Bob's foreground push drain inserts the message once, surfaces
  the expected in-app notification, preserves the media descriptor, and
  triggers the same media-download behavior as live delivery. The test should
  cover at least one representative media type; image is the minimum useful
  case, and voice/video can share the broader TC-2 through TC-4 evidence if
  the media drain path is common.
- **Status today:** A-13 / D-8 missing. The existing foreground-push drain test
  covers text only.

### TC-26: Re-added Bob decrypts current epoch after rotation with real crypto
- **File:** `integration_test/group_real_crypto_onboarding_test.dart` or an
  adjacent real-bridge crypto onboarding test.
- **Setup:** Bob is a member at epoch `E1`. Alice removes Bob and the group
  advances to `E2`. Alice re-adds Bob through the real ML-KEM group-key
  exchange and sends an encrypted `E2` group message.
- **Assertion:** Bob decrypts the `E2` message plaintext after re-add. Bob
  does not receive messages sent during his absence, and retained `E1` material
  cannot decrypt the `E2` ciphertext. This case is stronger than TC-8's
  fake-network epoch-state assertion and narrower than TC-13's first-add
  real-crypto onboarding proof.
- **Status today:** A-14 / B-9 missing.

## 6.7 Additional simulator/device-context findings from task 0346d

### TC-27: True two-simulator Discussion happy path
- **File:** extend the existing paired group simulator harnesses or add an
  adjacent Discussion journey harness that uses the same synchronization style.
- **Setup:** Alice creates a Discussion group through the user-facing flow,
  invites Bob, Bob accepts, both users send text, one simulator restarts, and
  the restarted side catches up.
- **Assertion:** Both simulators show the group in the list, the expected
  conversation rows, bidirectional messages, correct unread/read transitions,
  and post-restart catch-up. The row fails if either side has only
  sender-side publish success or pending receiver evidence.
- **Status today:** D-9 partial. Host-side fake-network tests and paired
  harness pieces exist, but no full simulator UI journey pins the whole
  receiver-visible Discussion experience.

### TC-28: True two-simulator Announcement permissions and media journey
- **File:** extend the group simulator harnesses with an Announcement row.
- **Setup:** Alice creates an Announcement group as admin and adds Bob as a
  reader. Alice sends text, media, and voice where supported. Bob receives and
  reacts, then attempts to compose.
- **Assertion:** Bob receives every admin post exactly once, media renders or
  downloads as expected, Bob can react, Bob cannot send, and no optimistic
  reader bubble is left stranded.
- **Status today:** D-10 partial. Fake/widget Announcement coverage exists,
  but simulator-level permission and media coverage is missing.

### TC-29: Admin add/remove end-to-end with stale notification denial
- **File:** paired group simulator harness or notification-open simulator
  smoke extension.
- **Setup:** Alice adds a third member, confirms membership propagation, then
  removes that member. After removal, Alice sends a group message and a stale
  notification/deep link for the removed member is opened.
- **Assertion:** Current members converge on the updated member list. The
  removed user exits or cannot open the conversation, cannot send, receives no
  new group notification for post-removal traffic, and stale notification taps
  do not reopen access.
- **Status today:** D-11 partial. Host-side membership tests cover add/remove
  and removed-user send blocking; simulator notification/access denial is
  absent.

### TC-30: Full group media matrix on simulator
- **File:** simulator media journey coverage for group Discussion and
  Announcement.
- **Setup:** Send image, video, GIF, and audio/voice media through Discussion
  and Announcement flows where those media types are supported. Include a
  failed download/retry case and reopen the thread after process restart.
- **Assertion:** Sender and receiver surfaces show stable rows, correct
  descriptors, successful downloads/renders, retry recovery, and post-restart
  visibility for each covered media type.
- **Status today:** D-10 / D-14 partial. Existing simulator proof is mainly
  image-focused; non-image media, retry, and restart visibility are not pinned
  as a group simulator matrix.

### TC-31: OS-level group notification and deep-link journey
- **File:** `integration_test/notification_open_ui_smoke_test.dart` or an
  adjacent group notification simulator smoke.
- **Setup:** Exercise group invite and group-message notifications in
  foreground, background, and terminated app states, including active
  conversation suppression, mute, removed group, and dissolved group cases.
- **Assertion:** Notification taps drain the correct inbox before opening the
  target group; suppressed notifications stay suppressed; removed/dissolved or
  stale notification taps do not grant access; unread state remains truthful.
- **Status today:** D-15 partial. `notification_open_ui_smoke_test.dart`
  covers useful invite and group-message tap pieces, but not the full group
  OS-state matrix.

### TC-32: Relay/libp2p failover and replay ordering matrix
- **File:** extend the real-network group recovery or relay failover simulator
  coverage.
- **Setup:** Exercise direct-to-relay fallback, relay down, multi-relay
  failover, partition heal, duplicate live+inbox delivery, and intentionally
  out-of-order durable replay.
- **Assertion:** Receiver-visible messages converge exactly once, in the
  product-approved order, with stable unread counts and media descriptors.
  Fixture absence must fail clearly for a closure run rather than silently
  passing as coverage.
- **Status today:** D-12 partial. `multi_relay_failover_test.dart` is
  env-gated, fake-network recovery covers pieces, and out-of-order simulator
  replay is not pinned.

### TC-33: Same-account multi-device simulator consistency
- **File:** `integration_test/group_multi_device_real_harness.dart` or an
  adjacent fixture-backed same-account simulator harness.
- **Setup:** Run two devices for the same account plus at least one remote
  participant. Send and receive group messages, mutate membership, change
  mute/unread state, and restart one device.
- **Assertion:** Sent history and membership converge across same-account
  devices; device-local mute, unread, and notification behavior stays
  predictable and does not leak into the wrong device state.
- **Status today:** D-13 partial. `group_multi_device_convergence_test.dart`
  is fake-backed and `group_multi_device_real_harness.dart` is outside the
  standard gate.

### TC-34: Failure/recovery UI flows on simulator
- **File:** group simulator recovery smoke or focused UI journey tests.
- **Setup:** Exercise publish failure, inbox-store failure, zero live peers,
  media upload failure, rapid pause/resume, and app restart while group sends
  or media uploads are pending.
- **Assertion:** Rows settle into honest success, retryable failure, or
  recoverable pending states without duplicate rows, stuck optimistic bubbles,
  lost media descriptors, or false notifications.
- **Status today:** D-14 partial. Host tests cover many failure branches, but
  simulator-visible UI recovery remains thin.

---

# 7. Open Questions

The following questions need product-side decisions before some tests
above can pin concrete contracts:

- **Should adding a member continue to avoid key rotation?** The current
  implementation adds the member and sends the current latest group key; it
  does not rotate as part of `addGroupMember`. TC-7 / TC-8 must assert the
  intended product contract, not treat rotation-on-add as an implementation
  unknown.
- **Is "no history backfill" a permanent policy, or might we add a
  bounded backfill window later?** Existing tests assert no-backfill for
  discussion late-joiner and invite bootstrap flows. If a bounded window is
  later added, those contracts and any new media/announcement onboarding
  assertions must be updated together.
- **What is the approved same-epoch contract when an admin add overlaps an
  existing-member send?** TC-24 can accept either "Bob does not receive the
  racing message" or "Bob receives it exactly once," but it must not leave the
  behavior nondeterministic.
- **How broad should the foreground-push media sample be?** TC-25 requires at
  least one media type through the new-member push-drain path. If image, video,
  and voice have meaningfully different drain behavior, TC-25 should cover all
  three rather than relying on TC-2 through TC-4 for the shared path.
- **Where does replay-nonce enforcement live — at the Go bridge, in the
  Dart listener, or both?** TC-11's assertion target depends on the
  answer.
- **Should TC-13 be its own integration_test file or extend
  `group_recovery_cli_e2e_test.dart`?** The simplest path is to add a
  new focused file that reuses the fixture pattern, but the recurring gate
  that claims TC-13 evidence must not silently pass when the fixture is
  absent.
- **Should TC-20 be one simulator file or a small orchestrated matrix?** It
  can reuse existing group recovery, foreground push drain, or two-simulator
  harness patterns, but the closure evidence must report all three rows:
  group catch-up, announcement catch-up, and exactly-once live+inbox
  recovery.
- **Which OS notification states are required for TC-31 closure?** The
  minimum should include foreground, background, and terminated group-message
  and invite taps, but the product team should confirm whether mute,
  active-conversation suppression, removed-group, and dissolved-group cases
  must all be in the same simulator run.
- **What is the product-approved ordering contract for out-of-order durable
  replay?** TC-32 can assert timestamp order, sequence order, or another
  declared ordering rule, but it must not accept nondeterministic row order.
- **Which same-account state is shared versus device-local?** TC-33 depends on
  clear expectations for sent history and membership convergence versus
  unread, mute, and notification state.
- **Which relay fixture is the recurring closure fixture?** TC-32 should not
  count as closed through an env-gated skip; the recurring gate needs an
  explicit relay fixture or a clear failure when it is unavailable.

---

# 8. Priority Ordering

Recommended implementation order (highest impact first):

1. **TC-2, TC-3, TC-4, TC-5, TC-22, TC-23** — close the highest-impact
   new-member user experience gaps: media, reaction fan-out, and quote context
   after join. Preserve the existing no-backfill assertions from TC-1 / TC-6
   where the new onboarding suites introduce another boundary.
2. **TC-13 and TC-26** — close the real-crypto onboarding gap for first-add and
   re-add-after-rotation. Higher infrastructure cost (uses `GoBridgeClient` +
   live bridge), but this is the missing integrated proof on top of existing
   primitive/bridge coverage.
3. **TC-25, TC-29, TC-31** — cover foreground-push media and group
   notification/deep-link access boundaries, including removed-user stale-tap
   denial.
4. **TC-9** — ciphertext-level forward secrecy. Important for the
   security claim and must use real-ciphertext visibility; fake-network
   listener coverage alone is insufficient.
5. **TC-7, TC-8, TC-24** — multi-add, re-join correctness, and add/send race
   determinism; mostly cheap wins on existing infrastructure once the race
   contract is chosen.
6. **TC-11, TC-12**, plus TC-10 only if app-boundary supplement is needed —
   replay-boundary and membership-signature crypto paths.
7. **TC-14, TC-15, TC-16, TC-30** — existing-member media in discussion
   groups plus the broader simulator media matrix.
8. **TC-17, TC-18, TC-19, TC-20, TC-27, TC-28, TC-32, TC-33, TC-34** —
   simulator and recovery scenarios. Higher cost but close the real-network,
   relay, multi-device, Announcement, and failure/recovery coverage gaps.
   Tighten the current G4/G7/G8 pass criteria as part of this work so pending
   receiver-side delivery cannot be reported as a pass.
9. **TC-21** — wire one real-network scenario into an automated gate.
   Audit closure requires the actual recurring gate evidence, not only a
   follow-up plan.

---

# 9. Acceptance

This audit is closed when:

- All TC-1 through TC-34 are either implemented as automated tests or
  explicitly mapped to existing automated tests with matching acceptance
  evidence.
- New-member onboarding coverage includes media, reactions, quoted replies
  with missing pre-join parents, add/send race determinism, and foreground-push
  media recovery rather than text-only happy paths.
- TC-13 runs against the real Go bridge with no fake/passthrough crypto
  involvement and proves a complete ML-KEM key exchange + group message
  decrypt by a freshly-added member.
- TC-26 proves re-add-after-rotation with real crypto: Bob decrypts the current
  epoch after re-add, does not receive absence-window messages, and retained
  stale epoch material cannot decrypt the current ciphertext.
- Simulator sufficiency is explicitly satisfied by TC-13 + TC-17 + TC-20 +
  TC-21 + TC-25 + TC-27 through TC-34: real-crypto onboarding,
  new-member join over real GossipSub, group catch-up after resume,
  announcement offline-reader catch-up, exactly-once live+inbox recovery,
  foreground-push media drain for a newly-added member, true Discussion and
  Announcement simulator journeys, group notification/deep-link routing,
  admin add/remove access denial, relay/libp2p failover, out-of-order replay,
  same-account multi-device consistency, failure/recovery UI behavior, and a
  recurring fixture-backed gate that fails clearly when unavailable.
- Any simulator row used as closure fails when the receiver-side message,
  media descriptor, unread state, route/deep-link result, notification state,
  multi-device state, relay recovery result, or failure/recovery state is
  absent. Sender publish success, partial warm-burst delivery, timeline length
  alone, rotation success, fixture skips, or "pending" receive evidence does
  not count as a passing user-visible assertion.
- Group notification closure includes foreground, background, and terminated
  group-message or invite routing with inbox drain, active-conversation
  suppression, mute behavior, and removed/dissolved or stale-tap denial.
- Relay/libp2p closure includes a fixture-backed direct-to-relay, relay-down,
  multi-relay failover, partition-heal, duplicate live+inbox, and out-of-order
  replay proof with receiver-visible delivery and ordering assertions.
- Same-account multi-device closure proves sent-history and membership
  convergence while preserving the declared device-local behavior for unread,
  mute, and notification state.
- Failure/recovery UI closure proves publish failure, inbox-store failure,
  zero peers, upload failure, rapid pause/resume, and restart with pending
  group sends or media settle into truthful visible states.
- TC-9 through TC-11 are satisfied only by tests that observe real encrypted
  payloads or bridge crypto results, or by existing Go/node tests that
  already observe those payloads. Fake-network plaintext listener tests do
  not count as ciphertext-level evidence.
- TC-21 is implemented: at least one real-network group scenario runs in a
  recurring nightly or pre-release gate with the required fixture, or fails
  clearly when the fixture is not available. A silent skip does not count as
  closure.
- The closure-reference documents (`20-group-discussion-reliability-closure-reference.md`
  and `21-announcement-reliability-closure-reference.md`) are updated to
  reference the new tests as part of their evidence base.
