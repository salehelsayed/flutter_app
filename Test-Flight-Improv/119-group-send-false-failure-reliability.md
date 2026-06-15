# 119 — Group Send False-Failure: Reliable & Seamless Group Sending TDD Plan

Status: PLAN ONLY (no implementation)
Date: 2026-06-13
Branch: 121-improvements
Source findings: two real-device screenshots (group "جروب العيد", a just-added member "Ibra" sending "test" the instant after "Ibra joined the group" at 3:37 PM) plus a graph-first multi-investigator root-cause synthesis (3 ranked RCs) and a three-lens adversarial critique (all three RCs' *stated mechanisms* refuted, the underlying false-failure surface confirmed real). Cited line numbers below are the **current** anchors on `121-improvements`, re-confirmed by direct source read this session (`send_group_message_use_case.dart` 256–1170, `bridge.go` 2170–2189, `node/pubsub.go` 415–438 / 2825–2860).
Related plans (do NOT duplicate, ALIGN): the send-truthfulness program `114` (LAN ack-after-commit), `115` (relay inbox custody, migration 077/v77), `116` (edit retry fidelity) — see `project_114_116_send_truthfulness_plans.md`; and the group-image dup/false-error (10s `BRIDGE_TIMEOUT` re-mint) bug — see `project_group_image_dup_bug.md` and `project_group_double_card_bug.md`. This plan is the **group text/first-send** truthfulness sibling of 114–116, scoped to the *just-joined live-but-marked-failed* surface.

---

## Problem statement (tied to the screenshots)

A freshly-added member can send a group message that is **actually delivered live to every connected peer**, yet the sender's own UI marks it `failed` (red error icon), then **self-heals to `sent`** without any user action — the red icon clears on its own and the message reappears correct after the user leaves and re-enters the chat.

The captured sequence:

1. "Ibra joined the group" at 3:37 PM (Discussion-type group "جروب العيد").
2. **Immediately** after joining, Ibra sends a text "test" at 3:37 PM.
3. On **Ibra's** device (German locale, own row shown as "Du"): the "test" row carries a **RED error icon** — status `failed`. It read as a send FAILURE.
4. On **Saleh's** device (English locale): the SAME "test" arrived and rendered normally at 3:37 PM. Delivery **actually succeeded** via live GossipSub (`WithFloodPublish(true)` pushes the RPC to ALL connected topic peers, not just the mesh subset).
5. When Ibra **left the chat and came back**, "test" rendered correctly (no red icon) — status had reconciled to `sent`.

Transport context: one device on airplane-mode + Wi-Fi (LAN-only), the other on 5G + Wi-Fi, plausibly the same Wi-Fi LAN. The EC2 relay (custody/inbox) was therefore unreliable-to-unreachable for at least the LAN-only device this session.

This is a **false send failure**: live delivery succeeded; the sender's UI lied; the lie self-corrected out of band. The just-joined + immediate-send timing is the precise enabler — at that instant the GossipSub mesh is not yet grafted and the relay circuit is not yet warmed, so the reliable-send **delivery-confirmation signals are structurally absent even though floodPublish already delivered**.

The fix must make group sending **truthful and seamless**: never paint a red `failed` when live fanout reached ≥1 connected peer or when custody is merely *in-doubt*; reconcile in-doubt sends to `sent` **without** requiring the user to leave and return; and never re-deliver a payload that was already delivered live (no duplicate cards on the receiver).

---

## Device evidence (2026-06-13, clean-HEAD two-device repro)

A real two-device repro on the CURRENT branch (build `1.0.0+105`, **debug**; the in-doubt guard committed in `74e8436c` "build 104" is present and unmodified) **did NOT reproduce the red icon**. Setup: alice (iPhone13, creator/admin) created a Discussion group + invited bob (Pixel6, debug); bob sent "Test" the instant after joining.

- **bob (`pixel.log`)** — `GROUP_SEND_MSG_USE_CASE_SUCCESS` + `GROUP_SEND_MSG_TIMING outcome=success status=sent` for msg `1e883977`, with `publishSucceeded` (`deliveryMode=live_only`), `topicPeers:1`, `inboxStored:false`, **`expectedRecipientCount:0`**, `liveFanoutState:full_peers`. Preceded by `GROUP_SEND_MSG_INVITE_REPO_ABSENT_USING_JOIN_TIMELINE memberJoinedTimelineCount:1`.
- **alice (`iphone-13.log`)** — `group_message:received` + `GROUP_HANDLE_INCOMING_MSG_SUCCESS` text "Test" `deliverySource:live` → **live delivery confirmed**.

**OQ-2 (build skew) — CONFIRMED.** On current code the just-joined first send is marked `sent` (delivered live), not red. The field red came from a build predating `74e8436c` ("build 104"). **Shipping build 104+ removes the user-visible red icon** — the primary remediation is a release, not new code.

**OQ-1 — resolved for this build.** The send took the `canMarkSent==true` path → `sent`, dominated by `expectedRecipientCount:0` (just-joined member, invite repo absent). The `topicPeers=0` race window was not hit live (`topicPeers:1` — alice already connected). Per the matrix, even the worst-case just-joined state (`expected>0 + topicPeers:0`) routes to the `:1080` PENDING guard → a **clock**, never red, on HEAD. The only HEAD paths to red (`reliableOk=false` / `null topicPeers`) did not occur (`ok:true`, `publishSucceeded`, integer `topicPeers:1`).

**NEW finding — false-SUCCESS risk (reframes scope).** `expectedRecipientCount:0` makes `canMarkSent` trivially true, so a just-joined member whose roster has not synced is marked `sent` REGARDLESS of whether any peer received. Here alice was connected and received, so `sent` was truthful; but `topicPeers:0` AND `expected:0` would mark `sent` with zero delivery — a false SUCCESS (worse than the false failure, it hides real loss). The invariants below must therefore ALSO reserve `sent` for positive proof of delivery (≥1 peer actually in the topic), not a vacuous `expected:0`. Net: the red-icon phases (2/3/6) are largely already landed on HEAD; the live remaining gaps are (a) ship 104+, (b) the `expected:0` false-success, (c) the still-wrong mesh-`topicPeers`-as-delivery-signal, (d) reconcile-by-republish dedup, (e) **the recipient-eligibility heuristic below**.

### Root cause of `expectedRecipientCount:0` — recipient-eligibility heuristic drops incumbents for a joiner (CONFIRMED)

The recipient set is built in `_loadGroupSendMembership` (`send_group_message_use_case.dart:84-104`); a member is kept only if `!_isMissingInviteStatusInTrackedGroup(...)` (`:193-204` → `inviteStatus == null && hasJoinedInviteEvidence && !hasJoinedTimelineEvidence`). For bob's send all three held for alice (the creator):
1. **`inviteStatus == null`** — `getStatusesForGroupMembers` is built only from `getAttemptsForGroup` (`group_invite_delivery_attempt_repository_impl.dart:97-98`), i.e. only members THIS device invited. bob (joiner) invited no one → `{}` → alice null. The repo being `null` (the `INVITE_REPO_ABSENT` log event) is **incidental**: the empty-statuses path yields the identical exclusion, so wiring the repo does NOT fix this.
2. **`hasJoinedInviteEvidence == true`** — bob's store has exactly one `sys-member_joined:` entry, his OWN join (`memberJoinedTimelineCount:1`).
3. **`!hasJoinedTimelineEvidence` for alice** — alice is the creator; creators never emit a `sys-member_joined:` message (`group_membership_timeline_message.dart:66`); "Saleh added Ibra" is the different `sys-members_added:` prefix (`:43`) which the scanner ignores (`send_group_message_use_case.dart:173`).

→ `_isMissingInviteStatusInTrackedGroup(null, true, false) == true` → alice excluded → `recipientPeerIds:[]` → `expectedRecipientCount:0`.

**Consequences:** (a) vacuous `sent` (canMarkSent trivially true); (b) `recipientPeerIds:[]` → NO relay inbox custody (`inboxStored:false` confirmed) → **silent loss if any incumbent is offline**.

**PERSISTENCE + SILENT LOSS — now EMPIRICALLY CONFIRMED (2nd repro, 12 bob sends, groupId `4f1842b8`).** Every one of bob's 12 sends carried `expectedRecipientCount:0` + `inboxStored:false` (`INVITE_REPO_ABSENT_USING_JOIN_TIMELINE memberJoinedTimelineCount:1` on each) — so the exclusion is NOT first-send-only; the creator stays permanently excluded. The **offline send `bd49b0b3`** (19:12:26, `topicPeers:0`, `liveFanoutState:zero_peers`, `inboxStored:false`) was marked **`sent`/`success`** on bob, yet appears **0 times in alice's entire log → permanently lost**, and because it is `sent` (not `failed`) the retrier never re-sends it. By contrast the two genuinely-failed offline sends (`reliable_failed`, 19:12:33/38) DID recover via re-publish on reconnect (→ `a77c8c25`/`cfda9351`, `sent`, `topicPeers:1`). So the truthfulness inversion is real on-device: the message marked **sent was the lost one**; the ones marked **failed recovered**. (Also observed — note-1: alice logged TWO `member_joined` events for bob, `sequence:2` @19:04:14 and `sequence:3` @19:04:19 → "bob joined the group" rendered twice; a separate duplicate-join-event defect, related to the group double-card bug.)

A failing Phase-0 RED test for this root cause exists: `test/features/groups/application/send_group_message_recipient_eligibility_test.dart` (`REG-119`) — asserts a confirmed-member joiner counts the incumbent creator (`expectedRecipientCount >= 1`) and creates custody targeting them; fails on HEAD with `expected 0` / empty `recipientPeerIds`. A second test PINs that the legacy zero-peer path stays `failed` (passes today).

**Heuristic intent vs bug:** `_isMissingInviteStatusInTrackedGroup` is an inviter/admin-centric guard (don't count invited-but-not-joined members). Applied to a joiner it inverts and drops legitimate incumbents.

**FIX — IMPLEMENTED (2026-06-13, uncommitted on 121-improvements).** Added a **group-creator exemption** to `_isMissingInviteStatusInTrackedGroup` (`send_group_message_use_case.dart`): the creator (`group.createdBy`, threaded into `_loadGroupSendMembership` as `creatorPeerId`) is definitionally joined and is never dropped on absence of invite/join evidence. This reconciles the two perspectives: **INV-106** (sender = admin/creator) keeps excluding a real pending invitee (not the creator) via the join-timeline; **REG-119** (sender = joiner) no longer drops the creator. Verified: `REG-119` test passes; `send_group_message_use_case_test.dart` 144/144 (INV-106 included) and full `test/features/groups/application/` 1064/1064 green; `flutter analyze` clean.

**Residual — NOW CLOSED (2026-06-13, uncommitted).** The creator exemption only rescued `group.createdBy`; a joiner could still drop a **non-creator incumbent** it never witnessed joining (3+ member group). Fixed by gating the WHOLE timeline-absence exclusion to the inviter/tracker device: in `_loadGroupSendMembership`, `isInviterTrackerDevice = inviteStatuses.isNotEmpty || senderRole == GroupRole.admin` (`group.myRole` threaded as `senderRole`), passed to `_isMissingInviteStatusInTrackedGroup` as the FIRST guard `if (!isInviterTrackerDevice) return false;` (creator exemption kept as inner defense; `_isPersistedNonJoinedInviteStatus` stays unconditional). Rationale: the not-yet-joined-invitee inference is only valid on a device that issued the invites; a joiner's roster is a signed config snapshot of confirmed-or-staged members it cannot distinguish, so it must include every deliverable incumbent. **INV-106 preserved** because its sender is the admin/creator (`myRole == admin` keeps the gate open → pending invitee `charlie` still excluded). Tests: `REG-119b` (joiner + non-creator incumbent → `expectedRecipientCount == 2`, custody targets both) added & green; `REG-119`/PIN green; INV-106 5/5; full `groups/application` 1065/1065; analyze clean.

**Knock-on benefit (silent-loss resolution):** because a joiner now counts ≥1 real recipient, the device's `bd49b0b3` offline send no longer hits the `expectedRecipientCount <= 0` short-circuit in `canMarkSent`. On the reliable path `{publishSucceeded, topicPeers:0, inbox:false, expected≥1}` now routes to the `_reliablePublishSucceededWithoutCustody` in-doubt guard → **`pending`** (retryable), not a vacuous **`sent`** that the retrier ignores. So GAP 1 converts the proven silent loss into a self-healing pending row.

## Remaining gaps — ALL IMPLEMENTED (2026-06-13, uncommitted on 121-improvements)

GAP1 → GAP3b → GAP3a → GAP2 all landed TDD (RED→GREEN). Verification gates:
- **GAP 3b** (duplicate join): `_handleMemberJoined` idempotent per `(groupId, peerId)` via `getLatestSystemEventTimestampForTarget` — skips SAVE+EMIT only when a join row exists under a DIFFERENT id; exact-id re-delivery still flows through `_saveTimelineMessagePreservingReadState`. Test `member_joined twice with different timestamps saves exactly one row (note-1 dedup)` green; "replay preserves read state" preserved; `group_message_listener_test` 166/166.
- **GAP 3a** (reconcile reorder): moved the publish-free `retryFailedGroupInboxStoresFn` BEFORE the re-publish `retryFailedGroupMessagesFn` in `pending_message_retrier.dart` (both touch 'pending' rows; confirm-first avoids re-publishing — duplicating — a pending row custody resolved). Order test `GFR-002` updated + green; `pending_message_retrier_test` 23/23.
- **GAP 2** (temporal topicPeers): Go `GroupReliableSendResult.ConnectedTopicPeerCount` = post-publish `liveGroupTopicPeerSet` recount (after `wg.Wait()`, main scope) + `group:publish_debug` `connectedTopicPeers` + bridge `connectedTopicPeerCount`; Dart `effectiveTopicPeers = connectedTopicPeerCount ?? topicPeers` drives the in-doubt guard + `canMarkSent` + fail gate (byte-equivalent today; trusts the connected count when present). Go `go test ./bridge/ ./node/` green (`TestGroupSendReliable_ReportsConnectedTopicPeerCount` added); Dart `GAP2: post-publish connected peer marks sent even when mesh topicPeers reads 0` green; groups/application 1069/1069. **Go half needs a `gomobile` rebuild (`cd go-mknoon && make all && cd ../ios && pod install`) before devices see `connectedTopicPeerCount`; Dart half is byte-equivalent until then.**

Design record (graph-first design + adversarial verify). Key corrections from verification:
- **GAP 3b — duplicate "X joined the group" (note-1).** NOT a double-broadcast: the same join arrives over two transports (live GossipSub + offline-replay inbox) with two **different envelope timestamps**; `_handleMemberJoined` rebuilds the row id from the timestamp (discarding the deterministic messageId) → two `sys-member_joined:` ids → both saved. Fix: make `_handleMemberJoined` idempotent per `(groupId, peerId)` via the existing `getLatestSystemEventTimestampForTarget` pattern, **skipping SAVE+EMIT only when a join row exists under a DIFFERENT id** (exact-id re-delivery must still flow through `_saveTimelineMessagePreservingReadState`, or the "replay preserves read state" test regresses). MUST preserve the id shape — GAP 1's `_memberJoinedTimelinePeerId` parses peerId from it. Landable now, S, no deps. First test: `group_message_listener_test.dart :: member_joined twice with different timestamps saves exactly one row`.
- **GAP 3a — reconcile-by-republish.** The clean NOW fix is **not** a new use case — it's a **reorder** in `pending_message_retrier.dart`: the publish-free `retryFailedGroupInboxStoresFn` (already promotes pending→sent on relay re-store success, L522-526) runs AFTER the re-publish `retryFailedGroupMessagesFn` (L408-418); swap so confirm-first. (A new `reconcileInDoubtGroupSends` use case ~90% duplicates the existing sweep and forces a 6-fake interface audit — avoid.) The authoritative `'inboxed'`→sent half is the only part blocked on 115P1. Group store returns `Future<void>` → success==custody, no duplicate signal.
- **GAP 2 — topicPeers semantics.** Verification FALSIFIED the "mesh subset" premise: with scoring off, floodPublish target set == `ListPeers` set; the real defect is **TEMPORAL** — `topicPeerCount` is sampled PRE-publish (`pubsub.go:422`, never re-read), so a peer subscribing during the settle window is delivered-to but uncounted. Fix: Go `ConnectedTopicPeerCount` post-publish recount (use an OUTER-scope `var connectedAfter int`, not `:=` in the goroutine) + bridge field; Dart collapses the in-doubt guard + `canMarkSent` onto one non-null `effectiveConnectedPeers = connectedTopicPeerCount ?? topicPeers ?? 0`. Dart half is byte-equivalent today (lands first); Go half needs a **gomobile rebuild** (not device-landable this session). The null-vs-0 asymmetry is unreachable on HEAD (the reliable block guarantees non-null topicPeers). No 115 dep.

---

## Confirmed root causes (ranked) with file:line evidence

> Critical adversarial finding (carried forward, NOT hidden): on the **current** tree the exact integer tuple `{publishSucceeded:true, topicPeers:0(int), inboxOk:false, expected>0}` is **intercepted** by the in-doubt PENDING guard `_reliablePublishSucceededWithoutCustody` (`send_group_message_use_case.dart:261-274`, consumed at `:1072-1080`) and routed to a **clock (`pending`)**, NOT a red `failed`. So the red icon on current HEAD requires escaping that guard via RC1 (a real publish/bridge error → `!reliableOk`) or RC2 (a `null` `topicPeers`). RC3 is the deepest *systemic* hole but is, by itself, only an **enabler** on current source. Each RC's *stated causal mechanism* was adversarially **refuted**; the *false-failure surface* they collectively point at is **confirmed real** (the screenshot is real, the self-heal is real). The plan therefore fixes the **invariant**, not one disputed line, and locks every escape branch with a regression test. Where the screenshot's exact branch is undecidable from source, the plan calls it an **open question to settle from device FLOW logs** (see OQ-1) rather than asserting it.

### RC1 (rank 1) — `!reliableOk` / `publishSucceeded:false` at the just-joined instant paints red at L1132, while floodPublish already delivered live

The red branch fires at `send_group_message_use_case.dart:1132-1133`: `if (!reliableOk || (!publishSucceeded && !inboxOk)) { updateMessageStatus(..., 'failed'); }`. Two ways to reach it at fresh join:

- (a) the bridge call throws and is mapped to `{ok:false, errorCode:'RELIABLE_SEND_FAILED'}` (`send_group_message_use_case.dart:1045-1051`) → `reliableOk=false` → L1132 taken.
- (b) Go `topic.Publish(ctx, …)` returns an error under the 30s `PubSubTimeout` context (`node/pubsub.go:420-423`, `result.PublishSucceeded = publishErr == nil` at `:429`), e.g. a transient send-time fault → `publishSucceeded=false`; combined with `inboxOk=false` (relay not warmed) → L1132 taken.

`inboxOk=false` is **structurally guaranteed** at fresh join: the relay circuit is not warmed, and the airplane-mode+Wi-Fi device may never reach EC2 this session, so custody is deterministically absent.

**Adversarial caveat (must be honored):** the critique refuted the *specific* "floodPublish delivers as PART of `Publish`'s push pipeline while the same `Publish` errors" mechanism — in go-libp2p-pubsub, `Topic.Publish` returns once the message is **enqueued** onto `p.sendMsg` (validation.go), and the floodPublish fanout runs on a **separate** processLoop goroutine (pubsub.go), so a `publishErr != nil` means **pre-enqueue/validate failure → no fanout**. Therefore RC1(b) cannot, by itself, coexist with Saleh receiving live **via Ibra's own publish**. The screenshot's live delivery on Saleh is real, so either (i) the red came from RC1(a) (a **bridge-level** throw — `RELIABLE_SEND_FAILED` — that is NOT a Go `Publish` error and does NOT prove no fanout, because the Go node may have published before the Dart bridge call's own timeout/throw), or (ii) delivery to Saleh arrived via a path independent of the errored local publish. **OQ-1 settles which from device FLOW logs.** Either way the **invariant** is the fix: a bridge-layer error or a single publish error is NOT proof of non-delivery.

Evidence:
- `send_group_message_use_case.dart:1132-1133` — the red `failed` assignment.
- `send_group_message_use_case.dart:1045-1051` — thrown bridge call → `RELIABLE_SEND_FAILED` → `reliableOk=false`.
- `go-mknoon/node/pubsub.go:420-423` — `ctx,cancel := context.WithTimeout(n.ctx, PubSubTimeout)`; `publishErr = topic.Publish(ctx, …)`.
- `go-mknoon/node/pubsub.go:429` — `result.PublishSucceeded = publishErr == nil`.
- `go-mknoon/node/pubsub.go:431-438` — `group:publish_debug` is emitted **only when** `result.PublishSucceeded` (so its presence/absence in logs disambiguates RC1).
- `go-mknoon/node/pubsub.go:66-72` — `WithFloodPublish(true)` ("sent to ALL connected peers … not just the GossipSub mesh subset").

Truthfulness invariant violated: **a bridge/publish error that does not actually disprove fanout must not be rendered as a hard `failed`** — under floodPublish the RPC may already be on the wire to every connected peer.

### RC2 (rank 2) — `topicPeers` arriving as `null` routes past the PENDING guard into the red L1158 branch (null-vs-0 asymmetry)

The PENDING rescue requires a **non-null** zero (`topicPeers != null && topicPeers <= 0`, `:272-273`), but the red gate coalesces null→0 (`if (!canMarkSent && (topicPeers ?? 0) <= 0)`, `:1158`; `canMarkSent` at `:1154-1157`). So for `{reliableOk:true, publishSucceeded:true, inboxOk:false, expected>0}`: integer-0 `topicPeers` → caught at `:1080` → `pending` (clock); but **null** `topicPeers` → `:1072` guard returns false (the `!= null` test fails) → falls through L1132 (not taken, `publishSucceeded:true`) → reaches L1158 where `(null ?? 0) <= 0` is true and `canMarkSent` is false → **red**. The legacy path NEVER fails on null `topicPeers` (it degrades to `pending`), so the reliable path is strictly **less truthful** here.

**Adversarial caveat:** `bridge.go:2177-2189` ALWAYS emits both `topicPeerCount` and `topicPeers` as concrete ints when the Go call returns `ok==true` (`TopicPeerCount` is a plain `int`, never `*int`, no `omitempty`; the bridge is a lossless JSON string transport). So `topicPeers` is null in Dart **only when `reliableOk=false`** — in which case L1132 (`!reliableOk`) fires FIRST (→ RC1), not L1158. The critique further established (via `git -S`) that the red L1158 branch and the Go dual-field emission landed in the SAME commit, so there was never a shipped build where the red branch existed while Go omitted the fields under `ok==true`. **Net: RC2's null-routing mechanism is dormant on current source** — it becomes live only if a future/forked code path returns `ok==true` without the peer-count fields, or a hand-built result map omits them. It is a **real latent asymmetry worth hardening** and a regression we must lock, even though it is not the screenshot's branch on HEAD.

Evidence:
- `send_group_message_use_case.dart:268-273` — PENDING guard requires `topicPeers != null && topicPeers <= 0`.
- `send_group_message_use_case.dart:1058-1060` — `topicPeers = _intResultField(...,'topicPeerCount') ?? _intResultField(...,'topicPeers')` (null if both absent/non-int).
- `send_group_message_use_case.dart:276-281` — `_intResultField` returns null for non-num.
- `send_group_message_use_case.dart:1154-1158` — red gate coalesces null→0.
- `go-mknoon/bridge/bridge.go:2177-2189` — always emits both peer-count fields as ints under `ok==true`.

Truthfulness invariant violated: **a missing/null peer-count signal must never be treated as proof of zero delivery.** The failed gate coalescing null→0 while the pending rescue requires non-null converts an *absent measurement* into a *hard failure*.

### RC3 (rank 3) — mesh-vs-floodPublish measurement gap: `topicPeerCount` (mesh subset, captured pre-publish, never re-read) is used as a delivery gate, but floodPublish bypasses the mesh

`canMarkSent` gates `sent` on `publishSucceeded && (topicPeers ?? 0) > 0` (`:1154-1157`), treating the mesh peer count as the live-delivery signal. But `topicPeerCount = len(topic.ListPeers())` is sampled **BEFORE** `topic.Publish()` with only a 150ms zero-peer settle at fresh join (`node/pubsub.go:2832`, settle at `:2848-2852`, `GroupPublishZeroPeerSettleWait = 150ms`), is **never re-read** after fanout (`result.TopicPeerCount = topicPeerCount` at `:427`), and floodPublish delivers to ALL connected topic peers regardless of mesh graft. Go itself classifies a publish-only result as a valid delivery mode `live_only` (`reliableGroupDeliveryMode`, `:430`). So the matrix contradicts the transport's own design.

**Adversarial caveat (decisive on current source):** the critique confirmed floodPublish and `ListPeers` key off the **same** `p.topics[topic]` SUBSCRIBE map, so "mesh not grafted → ListPeers=0 while floodPublish delivers" is NOT *generally* reachable; the realistic divergence is a narrow connection-bookkeeping race. AND even when `topicPeers=0` as an **integer**, the `:1080` PENDING guard rescues it to a clock. So RC3 alone produces a lingering **clock that self-heals**, not the red icon — it is the **deepest systemic reliability hole and the false-failure ENABLER**, but on current source it needs RC1 or RC2 to paint red. The fix is to stop using a pre-publish mesh snapshot as a *delivery* gate at all.

Evidence:
- `go-mknoon/node/pubsub.go:2832` / `:2848-2852` / `config.go:54` — pre-publish `ListPeers` sample + 150ms zero-peer settle.
- `go-mknoon/node/pubsub.go:422-423,427` — count captured before `Publish`, stored as `result.TopicPeerCount`, never re-read.
- `go-mknoon/node/pubsub.go:430` — `live_only` is a valid delivery mode.
- `send_group_message_use_case.dart:1154-1157` — `canMarkSent` gates on `topicPeers > 0`.

Truthfulness invariant violated: **`topicPeerCount` (mesh subset, pre-publish, never re-read) is not a delivery signal under floodPublish and must not gate send failure;** `publishSucceeded` under floodPublish with ≥1 *connected* peer already implies fanout.

### Reconcile-on-re-entry (why the red self-heals) — the masking mechanism

The self-heal is **NOT** caused by reopening the screen. The group conversation screen's `initState` / `didChangeAppLifecycleState(resumed)` call only `_loadMessages()` (a pure DB read that re-renders whatever status the row holds — never re-sends, never mutates status). The `failed → sent` flip happens **out of band, before re-entry**, via `PendingMessageRetrier` (`lib/core/services/pending_message_retrier.dart`): a 5-minute periodic timer **plus** offline→online and relay-ready P2P state transitions (`:106-144`). On each sweep it runs `recoverStuckSendingGroupMessages` then `retryFailedGroupMessages`, which **re-invokes `sendGroupMessage` with the SAME `messageId`/`logicalDeliveryId`/timestamp** (`retry_failed_group_messages_use_case.dart:316-317`). Because the ids match, `_canReuseOutgoingMessageId` (`send_group_message_use_case.dart:361-374`) takes the in-place-update path (no new row). By the time the retrier fires (seconds-to-minutes later — and the airplane↔5G/Wi-Fi flap right after join is a plausible offline→online trigger), the mesh has grafted and/or the relay is warm, so the second send reports `topicPeers>0` or `inboxOk=true` and the row is overwritten to `sent`. The next `_loadMessages` on re-entry simply re-reads the already-corrected row → no red icon.

**Three consequences this plan must address:**
1. **The retrier is a HOPEFUL second send, not a confirmation** of the original live floodPublish. It **masks** the truthfulness bug from operators (no surfaced telemetry that the false-failure fired and self-corrected).
2. It **re-publishes a payload Saleh already received live** → duplicate-delivery risk, bounded only by receiver `messageId`-only dedup which has documented divergent-id holes (the group double-card bug). A new wire transmission of the identical payload can materialize a second card on some paths.
3. The inbox-store sweep `retryFailedGroupInboxStores` (`retry_failed_group_inbox_stores_use_case.dart`) **cannot** self-heal a red row — its SQL filters `status IN ('sent','pending')` and EXCLUDES `failed` rows. So once a row is red, ONLY the re-send retrier (or, uncertainly, a sender self-echo reconcile) can flip it. This is exactly backwards for a *false* failure: the row that is actually-delivered-but-mislabeled is the one the cheap custody sweep refuses to touch.

---

## Send-truthfulness invariants this plan establishes

These are the contract this plan locks at both layers (Go reliable result + Dart status matrix), each with a regression test:

- **INV-1 (no-red-on-live-fanout).** NEVER render/persist `failed` when the live publish reached ≥1 connected peer. Under floodPublish, `publishSucceeded` with ≥1 connected topic peer (raw libp2p connectivity, NOT mesh `ListPeers`) is proof of fanout → `sent`.
- **INV-2 (in-doubt degrades, never fails).** When delivery is *in-doubt* — publish/bridge error of unknown delivery effect, OR custody unconfirmed, OR an **absent/null** peer measurement — the status degrades to `pending`/`sending` (self-healing, clock icon), NEVER to red `failed`. A `failed` is reserved for **positive proof of non-delivery** (no connected peers AND publish definitively failed AND no custody AND expected recipients exist), not for the *absence* of a confirmation.
- **INV-3 (null is in-doubt, not zero).** A null/missing peer-count must take the SAME in-doubt path as integer-0, never the red path. The fail gate must require a **non-null positive proof of zero delivery**; the asymmetry between `:272-273` (non-null) and `:1158` (null→0) is removed.
- **INV-4 (mesh count is not a delivery signal).** `topicPeerCount` (mesh subset, pre-publish, never re-read) must NOT gate `failed`. Replace it as a delivery gate with either a post-publish connected-peer count or a Go-classified delivery mode (`live_only`/`stored`/`both`).
- **INV-5 (reconcile without re-entry, without re-delivery).** In-doubt sends reconcile to `sent` via a background custody/delivery confirmation (NOT a hopeful re-publish) so the user never has to leave and return; reconciliation must NEVER re-transmit a payload that was already delivered live (no duplicate cards).
- **INV-6 (just-joined readiness).** A send issued inside the post-join transitional window (mesh not grafted, relay not warm) is treated as `pending`/`sending` until readiness or confirmation — never `failed` by the absence of not-yet-available signals.
- **INV-7 (observability).** Whenever the matrix would have painted red but the invariants keep it `pending`/`sent`, emit a structured FLOW event so operators learn the false-failure surface fired (closes the "masked by retrier" gap).

---

## Phased session breakdown (strict TDD: RED first, then minimal fix)

Every phase is test-then-code (RED → GREEN → refactor) UNLESS labeled VERIFICATION/CHARACTERIZATION (the test is expected to pass against the post-fix code; a failure there is the signal to scope a fix, not a red-first step). Dart tests mirror `lib/` under `test/`; Go tests live beside the package.

### Phase 0 (CHARACTERIZATION) — pin every current false-failure escape branch as a red-first matrix table

> **VERIFICATION/CHARACTERIZATION + setup for the matrix tests.** No production change. Builds the exhaustive parameterized matrix the later phases assert against and proves the current behavior of each escape branch so the fix is provably scoped.

Tests (write first; some PASS today, some are the RED targets later phases own):
- `test/features/groups/application/send_group_message_status_matrix_test.dart` (create) — a single parameterized harness over the reliable result tuple `{reliableOk, publishSucceeded, inboxOk, topicPeers(null|0|N), expectedRecipientCount, deliveryMode, bridgeTimeout}` driving `sendGroupMessage` with a fake bridge that returns a hand-built reliable result and asserts the persisted status. Characterize and PIN current outcomes:
  - `{ok:false}` (RELIABLE_SEND_FAILED) → **`failed`** today (RC1(a)) — this becomes a RED target in Phase 2.
  - `{ok:true, publish:false, inbox:false, expected>0}` → **`failed`** today (RC1(b)/L1132) — RED target Phase 2.
  - `{ok:true, publish:true, inbox:false, topicPeers:0, expected>0}` → **`pending`** today (guard `:1080`) — PIN as the desired behavior (regression guard).
  - `{ok:true, publish:true, inbox:false, topicPeers:null, expected>0}` → **`failed`** today (RC2/L1158) — RED target Phase 3.
  - `{ok:true, publish:true, inbox:false, topicPeers:N>0, expected>0}` → **`sent`** today — PIN.
  - `{ok:false, errorCode:'BRIDGE_TIMEOUT'}` → **`pending`** today (`_reliableGroupSendTimedOut`, `:256-259`/`:1080`) — PIN (NOT red; aligns with the group-image dup bug's timeout strand — do NOT re-litigate timeout here).

First failing test: `send_group_message_status_matrix_test.dart::matrix pins every reliable-result tuple to its current status` (the table assertions for the RED-target rows fail once the desired-behavior expectations are written in; until then this phase records the *current* outcomes verbatim as the baseline).

GREEN: none (characterization). Output: a checked-in matrix the reviewer reads to confirm scope.

### Phase 1 (GO LAYER) — emit a truthful, post-publish connected-peer / delivery signal; stop the pre-publish mesh snapshot from being the delivery gate

Goal: give Dart a signal that actually reflects fanout. Add a **post-publish connected-peer count** (raw libp2p connectivity intersected with the topic SUBSCRIBE set, sampled AFTER `topic.Publish` enqueues) and/or surface the existing `deliveryMode` as the authoritative gate. `topicPeerCount` (pre-publish mesh snapshot) stays for diagnostics but is no longer the sole delivery proof.

RED tests (write first), in `go-mknoon/node/pubsub_test.go` + `go-mknoon/bridge/bridge_test.go`:
- `TestSendGroupMessageReliable_ReportsConnectedPeersAfterPublish` — a fake/loopback topic where ≥1 peer is connected to the topic SUBSCRIBE map but the **pre-publish** `ListPeers` snapshot read 0 (simulating the fresh-join settle race). Assert the result carries a post-publish connected-peer count ≥1 (new field, e.g. `ConnectedTopicPeerCount`) and `DeliveryMode == "live_only"` (or `both`), even though `TopicPeerCount` (pre-publish) is 0. **Fails today**: no post-publish recount; only the pre-publish `TopicPeerCount` exists (`node/pubsub.go:422,427`).
- `TestGroupSendReliable_BridgeEmitsConnectedPeerField` — `bridge.go` reliable map includes the new field as an int under `ok==true` (mirrors `:2180-2186`), always present, never omitted. **Fails today**: the field does not exist.
- `TestSendGroupMessageReliable_DeliveryModeLiveOnlyWhenPublishSucceededNoInbox` — pin `live_only` for `{publish:true, inbox:false}` (already true via `reliableGroupDeliveryMode`, `:430`; PIN as the contract Dart will trust).

GREEN production change (minimal, plan-level):
- `go-mknoon/node/pubsub.go` (~`:415-438`): after `topic.Publish` enqueues, compute a post-publish connected-topic-peer count (the SUBSCRIBE-map ∩ connected-peers set the floodPublish path actually targets) and set a new `ConnectedTopicPeerCount` on the result; keep `TopicPeerCount` (pre-publish) for diagnostics. Do NOT change the floodPublish path or the publish itself.
- `go-mknoon/node/pubsub.go` result struct: add `ConnectedTopicPeerCount int`.
- `go-mknoon/bridge/bridge.go:2177-2189`: add `"connectedTopicPeerCount": sendResult.ConnectedTopicPeerCount` to the success map (concrete int, no `omitempty`).

Refactor notes: keep `live_only` semantics intact; the new field is additive and never null under `ok==true` (preserves INV-3's Go-side guarantee).

### Phase 2 (DART MATRIX — RC1) — never paint red on a bridge/publish error of unknown delivery effect; degrade to pending

Goal: close INV-1/INV-2/INV-6 for the L1132 branch. A `RELIABLE_SEND_FAILED` bridge throw or a single `publishSucceeded:false` is treated as **in-doubt** (`pending`, self-healing) when fanout cannot be disproven — NOT red — unless there is positive proof of non-delivery (no connected peers AND publish definitively failed AND no custody AND expected>0).

RED tests (write first), in `test/features/groups/application/send_group_message_use_case_test.dart`:
- `reliable bridge throw at fresh join degrades to pending not failed` — fake bridge throws on `group:sendReliable` (→ `RELIABLE_SEND_FAILED`, `:1045-1051`); group has remote members (`expected>0`); no custody. Assert status `pending` (clock), result `success`, and a `GROUP_SEND_MSG_USE_CASE_RELIABLE_IN_DOUBT` (or new reason) FLOW event with reason `bridge_error_indeterminate`. **Fails today**: L1132 → `failed`.
- `publishSucceeded false with connected peers present degrades to pending` — `{ok:true, publish:false, inbox:false, connectedTopicPeerCount:1, expected>0}`. Assert `pending`, not `failed` (publish flag alone is not proof of non-delivery when peers were connected). **Fails today**: `(!publishSucceeded && !inboxOk)` at L1132 → `failed`.
- `positive proof of non-delivery still fails` (regression guard, PASS after change) — `{ok:true, publish:false, inbox:false, connectedTopicPeerCount:0, topicPeers:0, expected>0}` AND no live fanout evidence → status `failed` is legitimate (true non-delivery; the user SHOULD see an error they can retry). This proves the fix does NOT make every send unconditionally non-red.

GREEN production change:
- `send_group_message_use_case.dart:1132-1152`: replace the L1132 condition so a `failed` is assigned ONLY on positive proof of non-delivery (e.g. `!reliableOk && connectedTopicPeerCount == 0 && !inboxOk && expected>0` AND not a `BRIDGE_TIMEOUT`), and route the indeterminate cases (`reliableOk=false` with peers connected, or `publishSucceeded=false` with `connectedTopicPeerCount>0`) into the existing in-doubt `pending` branch (`:1080-1129`) by widening `_reliablePublishSucceededWithoutCustody` / adding a sibling `_reliableSendIndeterminate(...)` predicate. Emit INV-7 telemetry for every diverted-from-red case.

Refactor notes: keep the in-doubt branch the single source of `pending` truth; do not add a second `pending` writer. Reuse the existing `emitGroupSendTiming(outcome: 'reliable_in_doubt')` with a distinguishing reason.

### Phase 3 (DART MATRIX — RC2/RC3) — null/0/mesh peer count is in-doubt, never red; use the connected-peer / delivery-mode gate

Goal: close INV-3/INV-4 for the L1158 branch. Treat null `topicPeers` identically to integer-0 (in-doubt → pending). Make `canMarkSent` trust `connectedTopicPeerCount` / `deliveryMode`, not the pre-publish mesh `topicPeers`.

RED tests (write first), in `send_group_message_use_case_test.dart`:
- `null topicPeers with publishSucceeded degrades to pending not failed` — `{ok:true, publish:true, inbox:false, topicPeers:null, connectedTopicPeerCount:absent, expected>0}`. Assert `pending`, not `failed`. **Fails today**: `:1072` guard `!= null` returns false → falls to L1158 → null→0 → `failed`.
- `connected peers mark sent even when mesh topicPeers is 0` — `{ok:true, publish:true, inbox:false, topicPeers:0, connectedTopicPeerCount:1, deliveryMode:'live_only', expected>0}`. Assert `sent` (INV-1: live fanout reached a connected peer). **Fails today**: `canMarkSent` requires `topicPeers>0` (mesh), so `topicPeers:0` → today goes to the `:1080` clock, NOT `sent` — the fix promotes a *confirmed* live_only delivery to `sent`.
- `deliveryMode live_only alone is sent-worthy under floodPublish` — `{ok:true, publish:true, inbox:false, connectedTopicPeerCount:2, deliveryMode:'live_only'}` → `sent`. PIN INV-4.
- `legacy-path null topicPeers still degrades to pending` (regression guard) — assert the legacy `callGroupPublish` path's existing null-safe `pending` behavior is unchanged (it already degrades, not fails). Locks parity so the reliable path is never *less* truthful than legacy.

GREEN production change:
- `send_group_message_use_case.dart:1058-1060`: read `connectedTopicPeerCount` from the reliable result (with `topicPeerCount`/`topicPeers` retained for diagnostics).
- `send_group_message_use_case.dart:1154-1158`: redefine `canMarkSent` to `expected<=0 || inboxOk || (publishSucceeded && connectedTopicPeerCount > 0) || deliveryMode in {live_only, both}`; and remove the null→0 coalesce in the fail gate — require a **non-null** zero-and-no-connected-peers proof before red (falls through to the in-doubt `pending` branch otherwise). Align `_reliablePublishSucceededWithoutCustody` (`:261-274`) to treat null `topicPeers`/absent `connectedTopicPeerCount` as in-doubt (drop the `!= null` requirement, OR gate on the absence of positive delivery proof).

Refactor notes: this is the symmetry fix — both the pending rescue and the fail gate must use the SAME null/zero handling (INV-3). Keep one predicate for "positive delivery proof exists" and one for "positive non-delivery proof exists"; in-doubt is the gap between them and always degrades.

### Phase 4 (RECONCILE — INV-5) — background custody/delivery sweep that flips in-doubt → sent WITHOUT re-publishing, and WITHOUT re-entry

Goal: in-doubt (`pending`) group sends reconcile to `sent` via a **confirmation** sweep (custody store success and/or a delivery/ack signal), not via the hopeful re-publish retrier. The user never has to leave and return; reconciliation NEVER re-transmits a payload already delivered live (no duplicate cards).

> Aligns with 115 (relay inbox custody: `'inboxed'` + migration 077/v77) and 116 (edit retry fidelity) — this phase is the **group send** consumer of that custody-confirmation seam. Do NOT duplicate 115's custody storage; consume it. The mandatory landing order from 114–116 (115P1 → 116P1-2 → 115P2-3 → 114P1-3 → 116P3) means **this phase HARD-depends on 115P1's custody-store signal existing**; if 115 has not landed the `'inboxed'` confirmation, Phase 4 lands the *reconcile-on-custody* half against whatever delivery confirmation the relay already returns and defers the inbox half until 115P1.

RED tests (write first):
- `test/features/groups/application/reconcile_in_doubt_group_send_test.dart` (create) — *custody-confirmed in-doubt flips to sent without re-publishing*. Arrange a `pending` (in-doubt) group row with a persisted `inboxRetryPayload`; run the reconcile sweep with a fake that reports custody now stored (or a delivery ack now present); assert the row flips to `sent` AND **no new wire publish was issued** (spy the bridge `group:sendReliable`/`group:publish` calls = 0). **Fails today**: only `retryFailedGroupMessages` (a re-publish) can flip an in-doubt row toward `sent`; there is no publish-free custody-confirm reconcile, and the inbox-store sweep excludes non-`pending` and never promotes `pending→sent` on its own.
- *reconcile does NOT re-deliver a live-delivered payload* — arrange an in-doubt row whose live floodPublish already reached the peer (no custody yet); the reconcile must confirm via custody/ack and flip to `sent` WITHOUT a second publish. Assert publish-call-count 0 and exactly one logical delivery. **Fails today**: the retrier re-publishes (duplicate-delivery risk, the masking mechanism).
- *failed rows that are TRUE failures still re-publish via the existing retrier* — regression guard: a genuinely non-delivered `failed` row (positive non-delivery proof) is still picked up by `retryFailedGroupMessages` and re-sent. PIN that the reconcile sweep is additive and does NOT replace legitimate retry.
- *reconcile is idempotent and dedup-safe* — running the sweep twice on the same in-doubt row flips it once and never double-counts; receiver-side, assert the same `messageId`/`logicalDeliveryId` is preserved so no divergent-id copy is created (guards against the group double-card bug being re-triggered by reconciliation).

GREEN production change (plan-level):
- New use case (or extend `retry_failed_group_inbox_stores_use_case.dart`): a **publish-free** reconcile that, for `pending` in-doubt rows, attempts only **custody confirmation** (relay inbox store / ack lookup) and, on success, flips `pending→sent` (and records `inboxStored`). Widen the inbox-store sweep SQL to also consider `pending` rows that lack custody (it already includes `pending`), and add the `pending→sent` promotion on confirmed custody. Critically: this sweep must NOT call `sendGroupMessage` / re-publish.
- Wire the reconcile into `PendingMessageRetrier` (`:106-144`) so it runs on the SAME triggers (periodic + offline→online + relay-ready) but BEFORE / instead of the hopeful re-send for *in-doubt* rows (re-send stays for true `failed`). The reconcile must run while the user is ON the chat screen too (so red/clock self-heals live, no re-entry needed).
- Ensure the on-screen status stream surfaces the flip: the reconcile's `updateMessageStatus` must reach the group conversation screen's live `GroupOutgoingLocalMessageChange` / `groupMessageStream` listeners so the user sees the correction WITHOUT re-entry (covered by Phase 6 widget test).

Refactor notes: this is the heart of INV-5. The distinction is **confirm (no re-send) vs retry (re-send)**: in-doubt → confirm-only; true-failed → retry. Keep them as two separate code paths with two separate triggers.

### Phase 5 (JUST-JOINED READINESS — INV-6) — defer/queue or pending-mark the first send until mesh/relay readiness

Goal: a send issued inside the post-join transitional window is never `failed` for the absence of not-yet-available signals; it is `pending`/`sending` and reconciled by Phase 4. Optionally, brief readiness gating so the FIRST send waits a bounded window for graft/warm before classifying.

RED tests (write first):
- `test/features/groups/application/send_group_message_just_joined_test.dart` (create) — *first send in the post-join window is pending, never failed* — simulate a send where readiness signals (mesh grafted / relay warm) are absent at send instant but `publishSucceeded:true`; assert `pending` (clock), reconciled later by Phase 4. **Fails today** only if it escapes the `:1080` guard (i.e. via the RC1/RC2 branches Phases 2/3 already fix) — so this is largely a COMPOSITION test proving the just-joined scenario can no longer reach red.
- `go-mknoon/node/pubsub_test.go` — `TestSendGroupMessageReliable_FreshJoinSettleDoesNotZeroDeliverySignal` — with the just-joined settle race (pre-publish `ListPeers=0`, peer actually connected to the topic), assert the result reports a non-zero `ConnectedTopicPeerCount` (Phase 1) so the just-joined send is classified live, not zero-peer. Pins INV-6 at the Go layer.
- *optional readiness defer* (only if owner picks the defer-strategy in OQ-3) — assert that when no topic peers are connected at all at send instant, the use case marks `sending`/`pending` and lets the reconcile/retry path own it, rather than blocking the UI or marking red.

GREEN production change: largely emergent from Phases 1–4 (the just-joined window is exactly the union of RC1/RC2/RC3 escape branches). The only net-new is the Go fresh-join connected-peer recount (Phase 1) and, if owner-selected, a bounded readiness gate in the send path. Keep the bounded gate ≤ the existing settle budget so the UI is not slowed.

### Phase 6 (UI STATUS) — the red icon never appears for an in-doubt/live send, and the live correction shows without re-entry

Goal: prove the *rendered* status truth at the widget layer: the just-joined live send shows a clock (not red) and flips to sent live (no leave-and-return), and a genuine failure still shows red.

RED tests (write first), in `test/features/groups/presentation/screens/group_conversation_wired_test.dart` (extend; the wired harness owns the live streams):
- *in-doubt send renders a clock, never the red error icon* — drive an outgoing group send that resolves to `pending` (in-doubt); assert the row renders the pending/clock indicator, NOT the failed/red error icon. **Fails today** for the RC1/RC2 tuples (they render red before the fix).
- *reconcile flips clock→sent live, no re-entry* — with the row in-doubt on-screen, fire the Phase-4 reconcile (custody confirmed) and assert the on-screen row updates to `sent` via the live `GroupOutgoingLocalMessageChange`/`groupMessageStream` listener WITHOUT re-running `_loadMessages` / re-entering the screen. **Fails today**: today the flip is driven by the out-of-band retrier and is observed only after re-entry (the screenshot behavior).
- *true failure still renders red and is retry-affordant* — a positive-non-delivery row renders the red error icon and exposes the retry affordance. PIN that the fix does not hide legitimate failures.

GREEN production change: ensure the reconcile's `updateMessageStatus` emits on the stream the screen subscribes to (may be already true via `group_message_repository_impl` status-change emission; if the flip does not reach the on-screen listener, add the emission — scope only if the test demands).

### Phase 7 (VERIFICATION — duplicate-delivery characterization) — reconcile-not-retry produces zero duplicate cards on the receiver

> **VERIFICATION/CHARACTERIZATION, not RED→GREEN.** Expected: PASS against Phases 1–4. A failure is the signal that reconcile is still re-publishing or that receiver dedup is leaking (the group double-card bug) and must be scoped.

Tests (write to characterize/lock):
- `test/integration/group_send_no_duplicate_on_reconcile_test.dart` (create) — two `GroupTestUser`s on `FakeGroupPubSubNetwork`; the just-joined sender's first send is delivered live AND lands in-doubt; run reconcile; assert the receiver has exactly ONE row for that `messageId` (no second card from a re-publish). Assert publish-call-count on the sender = 1 (the original), 0 additional from reconcile.
- *retry of a TRUE failure does not double-deliver either* — a genuinely non-delivered row re-sent by the retrier with the SAME `messageId`/`logicalDeliveryId` yields exactly one receiver row (relies on receiver id-dedup; if a divergent-id copy appears, that is the group double-card bug surfacing — flag for the owner, do NOT silently absorb).

GREEN production change: none expected. If a duplicate survives, the minimal fix is on the reconcile path (confirm-only, never re-publish) — already the Phase-4 design; scope only if a test demands.

### Phase 8 (INTEGRATION) — end-to-end just-joined send is truthful and seamless

Goal: the unit/Go seams cannot prove the full bridge→Go→matrix→reconcile→UI composition for the exact screenshot scenario. Add narrow integration coverage.

RED tests (write first):
- `test/integration/group_just_joined_send_truthfulness_test.dart` (create) — wire a fake bridge returning the just-joined reliable result (`publish:true`, pre-publish `topicPeers:0`, post-publish `connectedTopicPeerCount:1`, `inbox:false`, `deliveryMode:'live_only'`, `expected>0`). Assert ALL of:
  1. the sender's row is `pending` (clock), NOT `failed`;
  2. the receiver received exactly one copy (live);
  3. the Phase-4 reconcile (custody confirmed later) flips the sender's row to `sent` with NO second publish;
  4. the on-screen status updates without re-entry;
  5. INV-7 telemetry (`GROUP_SEND_*`) recorded the in-doubt classification.
- *true-failure end-to-end* — a no-peers, no-custody, publish-failed send renders red, is retry-affordant, and the retrier re-sends it (one receiver copy) once connectivity returns.

GREEN/refactor: no new production beyond Phases 1–6; the integration test is the proof the pieces compose.

---

## Mandatory landing order & dependencies

```
Phase 0  (characterization matrix)              ← baseline; no production change
   └─> Phase 1 (Go: post-publish connected-peer + deliveryMode signal)   ← provides the signal Dart will trust
        ├─> Phase 2 (Dart RC1: bridge/publish error → pending not red)    ← HARD-depends on 1 (uses connectedTopicPeerCount)
        ├─> Phase 3 (Dart RC2/RC3: null/mesh → in-doubt; connected/mode gate) ← HARD-depends on 1
        │     └─> Phase 6 (UI: clock-not-red + live flip)                 ← depends on 2+3
        └─> Phase 4 (reconcile: custody-confirm flip, no re-publish)      ← depends on 2+3; HARD-depends on 115P1 custody signal (consume, don't build)
              ├─> Phase 5 (just-joined readiness)                         ← emergent from 1–4; +optional Go fresh-join recount
              ├─> Phase 7 (duplicate-delivery VERIFY)                     ← VERIFY; depends on 4
              └─> Phase 8 (integration)                                   ← depends on ALL above
```

- **Phases 1–3 are the false-failure fix** (no red on live/in-doubt). Phase 4 makes the self-heal seamless and dedup-safe. Phases 5–6 cover the just-joined window and the rendered truth. Phases 7–8 verify and prove end-to-end.
- **Minimum landing to kill the red icon:** `0 → 1 → 2 → 3 → 6`. This alone makes the just-joined live send render a clock that the EXISTING retrier still self-heals (no re-entry guarantee yet, but no false red).
- **For seamless (no re-entry, no duplicate):** add `4 → 5 → 7 → 8`. Phase 4 HARD-depends on the 115P1 custody-store signal; if 115 has not landed, Phase 4 lands the ack/delivery half and defers the inbox-custody half — see the 114–116 mandatory order.
- **Do NOT touch the `BRIDGE_TIMEOUT → pending` strand** (`:256-259`, `:1080`): it is already truthful (clock, not red) and is owned by the group-image dup/false-error work. This plan only ensures the NON-timeout escape branches also degrade, never fail.

---

## Out of scope (explicit)

- The **`BRIDGE_TIMEOUT` re-mint / group-image duplicate** bug (10s timeout → composer re-mints `messageId` → 3× copies). Owned by `project_group_image_dup_bug.md`. This plan keeps the timeout strand untouched and only aligns the *non-timeout* false-failure.
- **Receiver-side id-dedup divergent-id holes** (the group double-card bug, `project_group_double_card_bug.md`). Phase 7 *characterizes* duplicate-delivery and flags a divergent-id leak if it appears, but FIXING receiver dedup (content-UNIQUE index, etc.) is its own workstream.
- **114 LAN ack-after-commit** and **115 relay inbox custody storage** and **116 edit retry fidelity** themselves — Phase 4 *consumes* 115's custody-confirm signal; it does not re-implement custody storage, the LAN ack-commit, or edit-retry poisoning guards.
- **1:1 send truthfulness** (the same red-icon class on direct messages) — separate surface; this plan is group-only.
- **Notifications / calm UX** for group sends (owned by docs 106 / 118). No notification behavior changes here.
- **GossipSub mesh-graft timing tuning, rendezvous/discovery cadence, relay warm-up speed** — performance levers, not truthfulness; out of scope beyond the bounded just-joined readiness gate (OQ-3).
- **Migration / DB schema changes** — Phase 4 reuses existing `status`/`inboxStored`/`inboxRetryPayload` columns and 115's custody signal; no new migration is planned here (if Phase 4 needs a custody-confirm column it must coordinate with 115's migration 077/v77, NOT add a new one).

---

## Open questions for the owner

1. **OQ-1 (which branch the screenshot actually hit).** Source alone cannot decide RC1(a) (bridge throw) vs RC1(b) (Go publish error) vs RC2 (null `topicPeers`, dormant on HEAD) vs a pre-guard build. **Settle from device FLOW logs**: which of `GROUP_SEND_MSG_USE_CASE_RELIABLE_IN_DOUBT` / `reliable_failed` / `zero_peers_inbox_failed` fired for Ibra's 3:37 send, and whether Go emitted `group:publish_debug` (emitted ONLY when `PublishSucceeded`, `pubsub.go:431`). Capture before committing to one RC. The invariant-based fix is correct regardless, but the log decides which RED-target test is the *primary* repro.
2. **OQ-2 (build-version drift).** The in-doubt PENDING guard (`:1080`) and the reliable contract may post-date Ibra's field build. `send_group_message_use_case.dart` is heavily modified + uncommitted on `121-improvements`. Confirm the device build vs HEAD so we know whether the integer-0 path (RC3-direct, pre-guard) or the null/error path (RC1/RC2) is the live repro on the shipped binary.
3. **OQ-3 (just-joined strategy: pending-mark vs bounded defer).** Phase 5 defaults to *mark pending + reconcile* (never block the UI). Alternative: a bounded readiness gate that waits ≤ the existing settle budget for graft/warm before classifying. Confirm the default (pending-mark) vs a brief defer; a defer risks UI latency, a pending-mark risks a momentary clock the user must trust will resolve.
4. **OQ-4 (reconcile cadence / on-screen self-heal latency).** The retrier's periodic interval is 5 min with a 5s online-transition debounce. For a *seamless* on-screen flip (no re-entry), is a faster reconcile tick acceptable while the user is viewing the chat (e.g. a short foreground reconcile timer), or is the existing offline→online/relay-ready trigger sufficient? Default: run reconcile on the existing triggers PLUS a foreground tick while the group screen is visible.
5. **OQ-5 (when is a `failed` legitimately shown?).** The plan reserves red for *positive proof of non-delivery* (no connected peers AND publish failed AND no custody AND expected>0). Confirm this is the desired bar — i.e. a user on a fully-offline device sending to a group with no reachable peers SHOULD still see a red retry-affordant error (vs an indefinite clock). Default: yes, true-offline shows red.
6. **OQ-6 (deliveryMode trust).** Is Go's `live_only` classification trustworthy enough to mark `sent` on its own (INV-4), or should `sent` always require EITHER custody OR a post-publish connected-peer count >0 (not the mode string alone)? Default: require `publishSucceeded && connectedTopicPeerCount>0` OR custody; treat `deliveryMode` as corroborating, not sole, evidence.
7. **OQ-7 (Phase 4 vs 115 sequencing).** If 115 (relay inbox custody `'inboxed'`) has NOT landed, Phase 4's custody-confirm half cannot consume it. Confirm whether to (a) block Phase 4 on 115P1, or (b) land Phase 4's ack/delivery-confirm half now and the inbox-custody half after 115P1. Default: (b).
8. **OQ-8 (self-echo reconcile as a second confirm source).** It is unverified whether libp2p loops a publisher's own GossipSub message back (`_reconcileOutgoingSelfEchoDuplicate`). If it does, the self-echo could be a *publish-free* confirmation source for Phase 4 (better than custody, since it proves live delivery). Should Phase 4 also consult the self-echo path? Default: design Phase 4 to accept the self-echo as a confirm source IF a two-device repro confirms the loopback exists.

---

## Device / manual evidence checklist (iPhone13 / Pixel6)

Per project memory: iPhone13 `00008110-…` (use `--profile`/AOT — debug JIT crashes on iOS 26.5), Pixel6 `21071FDF600CSC`.

1. **Reproduce the screenshot first (pre-fix, log capture).** Add Ibra to a group, have Ibra send IMMEDIATELY after "joined". On Ibra's device, capture FLOW: which `GROUP_SEND_*` outcome fired, `topicPeers`/`connectedTopicPeerCount`/`inboxStored`/`publishSucceeded`/`deliveryMode`, and whether Go emitted `group:publish_debug`. Confirm Saleh received it live. This settles OQ-1/OQ-2.
2. **Post-fix just-joined send is a clock, not red.** Same scenario → Ibra's row shows a pending clock (never the red error icon); Saleh receives exactly one copy live.
3. **Seamless self-heal, no re-entry.** While Ibra STAYS on the chat screen, the clock flips to sent on its own (Phase 4 reconcile) within the reconcile window — no leave-and-return needed.
4. **No duplicate on the receiver.** Saleh sees exactly ONE "test" card after Ibra's row reconciles (reconcile is confirm-only, no re-publish).
5. **True failure still shows red + retry.** Put Ibra fully offline (no peers, no relay) and send → red error icon with a retry affordance; on reconnect the retrier re-sends, one receiver copy.
6. **LAN-only device (airplane + Wi-Fi) parity.** Reproduce the exact transport mix (one airplane+Wi-Fi, one 5G+Wi-Fi, same LAN) → live LAN delivery classified `sent`/`pending`, never a false red, even with the relay unreachable the whole session.
7. **Group regression unchanged.** Existing group send (already-grafted member, custody available) still marks `sent` immediately; muted/membership behavior untouched.

Capture FLOW for `GROUP_SEND_MSG_USE_CASE_RELIABLE_IN_DOUBT`, `reliable_failed`, `zero_peers_inbox_failed`, the new reconcile event, `group:publish_debug`, and `group:discovery` (publish_peer_refresh) to confirm classification + reconcile routing.

---

## Closure bar

Closed only when ALL hold:

- Every red-first test above is written first, fails for the intended reason, then passes after the minimal implementation. (Phases 0/7 are characterization/verification: their tests are expected to pass against the post-fix code; a failure is the signal to scope a fix, not a red-first step.)
- A just-joined live group send whose RPC reached ≥1 connected peer (floodPublish) is NEVER rendered/persisted `failed` — verified at the Go layer (post-publish connected-peer signal), the Dart matrix (RC1/RC2/RC3 branches), and the `group_conversation_wired` widget (clock, not red).
- A null/missing peer-count and a single bridge/publish error both degrade to `pending`/`sending` (in-doubt), never red; the `:272-273` (non-null) vs `:1158` (null→0) asymmetry is removed (INV-3).
- An in-doubt send reconciles to `sent` via a publish-free custody/delivery confirmation, WITHOUT requiring the user to leave and return, and WITHOUT re-transmitting a payload already delivered live (no duplicate cards on the receiver) — verified by the reconcile unit test, the Phase-6 live-flip widget test, and the Phase-7 no-duplicate characterization.
- A genuine non-delivery (positive proof: no connected peers AND publish failed AND no custody AND expected>0) STILL shows red with a retry affordance, and the existing retrier still re-sends it once connectivity returns (one receiver copy) — the fix does not hide legitimate failures.
- The `BRIDGE_TIMEOUT → pending` strand and the group-image dup/double-card workstreams are untouched; this plan aligns with (does not duplicate) 114/115/116.
- INV-7 telemetry fires whenever the matrix would have painted red but the invariants kept it pending/sent, so operators can observe the false-failure surface.
- The characterization matrix (Phase 0) is checked in and every escape branch has a regression test; Group Messaging host gate + the touched Go (`go test ./node/... ./bridge/...`) and Dart suites are green; `graphify update .` run.
