# 267 - Group Invitation Send Lag (Bug, Evidence-First)

Status: planned (v1 authored 2026-07-20; awaiting $tdd-review audit; NOT executed)
Type: bug (perceived latency), evidence-first — measurement precedes any fix
Closure tier: measured before/after timings on real devices (sender phone + one
offline recipient + one online recipient); unit proof for the chosen fix
Boundary triggers: Flutter-only unless measurement proves a Go-side dial-deadline
change is required (then bridge-adjacent, separate approval)
Spec: free-text intent — user report 2026-07-20: "I notice lagging in sending group
invitations, I don't know why." Reproduced perception on TODAY'S provenance-verified
build (1.0.0-ad073dd39.*), so this is NOT the historical stale-build artifact: earlier
lag reports were explained by phones silently running old builds; that explanation is
exhausted for this instance.
Grounding: send-path anchors verified at HEAD ad073dd39; root-cause candidates below
are ranked hypotheses, not conclusions — the plan's first wave is measurement.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-20 | Planner | send_group_invite_use_case.dart, p2p_service_impl.dart (sendMessage), p2p_bridge_client.dart (callP2PMessageSend), contact_picker_wired.dart (not yet read — H2 open) | Hypotheses ranked; H1 has a verified unbounded-await anchor | Run $tdd-review 267, execute measurement wave first |

## Source Of Truth
- Spec / intent: inline above
- Gate definitions: scripts/run_test_gates.sh + scripts/run_host_test_gates.sh
- Numbering / index: Test-Flight-Improv/00-INDEX.md

## Session Classification
planning-only (no implementation in this session)

## Exact Problem Statement
Sending group invitations feels laggy on current, provenance-verified builds. The
delay's location (per-invite send await? UI batching? signing/encrypt legs? Go dial
deadline?) has never been measured on-device with the current pipeline.

## Verified Send-Path Anchors (HEAD ad073dd39)
- lib/features/groups/application/send_group_invite_use_case.dart:106 — documented
  order: "Try p2pService.sendMessage -> if fails, try p2pService.storeInInbox."
- :398 — the live attempt: `await p2pService.sendMessage(deliveryPeerId, envelopeJson)`.
- :432 — durable relay-inbox fallback only AFTER the live attempt resolves.
- :317 / :350 — signing (`callSignPayload`) and encryption (`callEncryptMessage`) legs
  precede the send.
- :527-533 — multi-invitee sends run under `Future.wait` (parallel), so aggregate lag
  is per-invite, not additive — unless the UI serializes (H2, unread).
- lib/core/services/p2p_service_impl.dart:2355-2419 — `sendMessage` passes NO
  `timeoutMs` to `callP2PMessageSend`.
- lib/core/bridge/p2p_bridge_client.dart:1408-1440 — with `timeoutMs == null` the
  Dart await is EXPLICITLY unbounded ("callers passing no timeoutMs (sendMessage)
  stay unbounded"); only the Go side self-bounds via its own deadline.

## Ranked Hypotheses (measurement decides)
- H1 (primary): an invite to an unreachable/cold peer holds the live `sendMessage`
  await for the full Go-side dial/ack deadline before the relay-inbox fallback runs;
  the user watches that window as "lag". Verified structural precondition: the await
  is unbounded on the Dart side (:1408-1440) and the fallback is strictly sequential
  (:398 → :432). The Go `message:send` deadline value must be read during execution
  (go-mknoon bridge/node message:send handler) and recorded here.
- H2: the invite UI (contact_picker_wired.dart / group creation flow) serializes
  per-invitee awaits or blocks the interaction on the full send future instead of the
  durable enqueue. (File unread at planning time — first execution read.)
- H3: signing/encrypt legs (:317, :350) are slow on a cold bridge (first use after
  launch) and charge their cost to the first invite.
- H4: relay round-trip inside `storeInInbox` (:432) is itself slow on the deployed
  relay (v1.6.0) — measurable server-side.

## Wave 0 — Measurement (RED = reproduced, quantified lag)
1. Build the sender phone with `--dart-define=FDC_FLOW_LOG=1` (main.dart:332-342
   forces flow logging + synchronous debugPrint in a realistic-timing profile build).
2. Journey: send invites to (a) an online peer, (b) an offline peer, (c) a
   never-connected peer, from the group-creation flow and from Group Info add.
3. Extract per-leg timings from the `[FLOW]` stream:
   `P2P_SERVICE_SEND_MESSAGE_BEGIN` → `SUCCESS`/`UNACKED`/`ERROR`
   (p2p_service_impl.dart:2360-2418), `P2P_MESSAGE_SEND_REQUEST`
   (p2p_bridge_client.dart:1414), plus the use case's own invite events.
4. Record the numbers IN THIS PLAN; the dominant leg selects the fix below.

## Fix Menu (choose by evidence, execution session implements)
- If H1: pass a bounded `timeoutMs` (proposal: 3000-5000 ms) for INVITE live sends —
  the F5 cap mechanism already exists and degrades to the durable fallback
  (:1430-1439); OR make invites durable-first (enqueue inbox envelope immediately,
  attempt live delivery opportunistically after). Durable-first is the stronger fix
  and matches how invites already survive offline recipients; it must preserve
  delivery-attempt records (record_group_invite_delivery_attempts.dart).
- If H2: decouple the UI from the aggregate future — optimistic per-invitee "sending"
  states driven by the existing delivery-attempt rows.
- If H3: warm the bridge crypto path at group-flow entry, or parallelize sign/encrypt
  across invitees (they are independent).
- If H4: relay-side investigation (out of this plan's boundary; record and split).

## RED-First Test Plan (post-measurement)
- For the chosen fix: a fake-clock unit test proving the invite send path never awaits
  the live leg longer than the bound (H1) / the UI state transitions without awaiting
  the aggregate (H2).
- Preservation: offline recipient still receives the invite via inbox replay
  (existing invite delivery-attempt suites); no duplicate invite on live+inbox both
  succeeding (dedup by invite id — verify existing guarantee in execution).

## Gates
- GROUP_TESTS: ./scripts/run_test_gates.sh groups
- AUTO_FEATURE_HOST: ./scripts/run_host_test_gates.sh feature-host-all
  --batch-flutter --concurrency 4 --reporter failures-only
- Explicit grep-gate registration for new tests; flutter analyze clean.
- Closure requires the Wave 0 before/after numbers recorded in this file.

## Risks / Open Questions
- Bounding the live send trades direct-delivery rate for latency; the bound must stay
  comfortably above typical LAN/relay ack times observed in Wave 0.
- Durable-first reorders the documented send contract (:106) — all consumers of
  delivery-attempt status must be audited for assumptions about attempt order.
