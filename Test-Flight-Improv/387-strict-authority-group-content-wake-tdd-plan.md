# 387 - Strict-Authority Group Content Never Woke The Recipient (G26)

Status: executed 2026-08-19 (host green, mutation-verified; **NOT deployed — behaviour is OFF in production**)
Type: Bug
Spec: free-text intent (no formal spec) — closes **G26** from the [UI-23 E2E map](../UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Behavior_and_E2E_Test_Map.md) §4.7; PRD clause at `Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` §1.3 (`Suspended/killed → FCM wake → Card`)
Classification: implementation-ready
Closure tier: host (device leg does not exist — see Deferred)

**This document was written after execution, not before it.** G26 was found by Plan 384's producer
census and implemented directly on request, so there is no pre-execution planning record to reproduce
and none is invented here. What follows is the source-verified problem, what shipped, and what did not.

## Problem And Evidence

- Behavior to improve: a strict/fresh-authority group (Plan 377) delivered its messages to relay
  custody and then went completely silent. No push, no wake, no counter. §1.3's
  `Suspended/killed → FCM wake → Card` row was unreachable on that lane **by construction** — not a
  parity failure like G19, an absent push.
- Impact: total for that lane, for both backgrounded and killed recipients. A strict group's messages
  became visible only when the recipient's app next ran and drained the inbox. The messages themselves
  were never lost — only the wake.
- **Root cause (two halves, both re-verified in source during execution rather than inherited from the
  planning-time census that first surfaced it):**
  1. **Strict sends never reach the group topic.** `sendGroupMessage` returns before
     `callGroupSendReliable` (`send_group_message_use_case.dart:3040-3072`) and instead signs ONE
     `group_offline_replay` envelope per recipient into the DIRECT inbox under the `group_content_v1`
     ack-custody namespace (`group_offline_replay_envelope.dart:1286-1325`, custody kind at
     `inbox_store_outcome.dart:23`). The relay admits and stores it
     (`ack_custody.go:331-440`).
  2. **The direct push seam could not see that shape.** `launchStoredDirectPush`
     (`go-relay-server/inbox.go:2090`) recognized exactly two things: a `type: message_reaction`
     direct reaction, and `extractChatPushMetadata`'s switch on `envelope["type"]`
     (`inbox.go:1358-1468`). A replay envelope has **no `type` field at all**, so it fell to that
     switch's `default:` and produced `ShouldNotify: false`. `directWakeOutcomeProducer` reached the
     same verdict, so the durable wake-outcome path also declined. Nothing incremented.
- Why it was invisible: there was no counter on any of those declines. The lane produced no metric, no
  log line, and no artifact — the only observable was a user not getting a notification.
- **Facts that made the fix small, each verified before writing code:**
  - The envelope already carries every field `buildGroupPushMessage` needs: `groupId`, `keyEpoch`,
    top-level `ciphertext`/`nonce`, `messageId`, `senderTransportPeerId`. `addGroupEncryptedPushData`
    (`inbox.go:1221-1256`) already falls back to top-level ciphertext/nonce, so it reads this shape
    unmodified.
  - **The recipient needed no change.** It routes on `data['type']` alone and ignores `kind`
    (`background_message_handler.dart:2579,:2683,:3030`).
  - **Plaintext parity agrees.** The strict plaintext is the id-complete `inboxPayload`
    (`send_group_message_use_case.dart:2567-2589`), and `contentEventId == resolvedMessageId ==
    plaintext.messageId == outer message_id`, so the recipient's parity check passes. This is the
    shape that never needed Plan 384's null guard.
  - **The route resolves.** Strict custody recipients are `device.transportPeerId`
    (`send_group_message_use_case.dart:431-457`), and `register_token` keys push tokens by the
    authenticated `remotePeer` (`inbox.go:3699-3708`) — the same namespace.
  - Both the plain `Store` path and the ack-custody path converge on `launchStoredDirectPush`
    (`inbox.go:1930`, `ack_custody.go:1029-1033`), so one branch covers both.
- Refuted during execution (do NOT re-introduce):
  - "The recipient must learn a new push type" — refuted: it routes on `type` and this push IS
    `type: group_message`.
  - "The group-reaction wake already covers this" — refuted: `fanOutGroupReactionPush` is on the GROUP
    INBOX path (`s.store(groupId, …)`), which strict content never touches.
  - "A `case` in `extractChatPushMetadata` is enough" — refuted: that function switches on `type`, and
    adding a `kind` case there would entangle the strict lane's audience rules with the chat grammar.

## Scope Contract And Guard

In scope:
- **W1:** recognize strict group content at the direct push seam and route `payloadType:
  group_message` through the existing `buildGroupPushMessage`.
- **W2:** a wake counter for every decision this lane makes, including the declines.
- **W3:** a default-off kill switch matching every sibling push flag.

Must preserve:
- Custody is never affected by the flag — only the wake. (Pinned by
  `TestInboxStore_StrictGroupContentStaysSilentWhenDisabled`, which asserts the row is still stored.)
- The ordinary chat, direct-reaction and group-topic push lanes are byte-unchanged.
- The oversized/unusable-envelope fallbacks keep applying, so a bad key epoch degrades to a
  routing-only push rather than to silence.

Hard `Do not`:
- Do not route `payloadType: group_reaction` onto the group-message push. Its audience is author-only
  (PRD §6.5) and its copy comes from a separate notification-extension grammar; the group-message
  fanout would alert every member. → deferred as **G27**.
- Do not change the envelope, the custody admission, or any wire format. The producer already emits
  everything needed.
- Do not weaken the wake-token gate. This lane uses the ordinary-message gate (fail-open when the
  recipient registered no set), because this envelope IS the group's ordinary message traffic.

## Test Contract

| Case | Behavior | Named test/proof | Tier | HEAD state → GREEN | Mutation that re-reds |
|---|---|---|---|---|---|
| TC-387-01 | The generic extractor cannot see strict group content — the root cause itself | `group_content_push_test.go::TestExtractChatPushMetadata_StrictGroupContentIsInvisible` | host (Go) | GREEN sentinel (documents why a dedicated lane is required, not optional) | n/a — a sentinel |
| TC-387-02 | A complete strict group message is recognized and eligible; a reaction is recognized and DECLINED; a non-custody replay envelope is not recognized at all; missing routing fields decline | `…::TestExtractGroupContentPushMetadata` (6 subtests) | host (Go) | causal RED by construction → green | making reactions eligible; dropping the custody check; dropping the routing-field guard — each reds its own subtest |
| TC-387-03 | **The causal row:** a stored strict group message wakes the recipient with the 7 data keys it routes on | `…::TestInboxStore_StrictGroupContentWakesTheRecipient` | host (Go) | causal RED (HEAD sends nothing) → green | delete the branch → red |
| TC-387-04 | **The production path:** the same wake through the ACK-CUSTODY store, whose admission validates signature, canonical signed payload and recipient set | `…::TestStoreAckCustody_StrictGroupContentWakesTheRecipient` (+ its disabled sibling) | host (Go) | causal RED → green | delete the branch → red |
| TC-387-05 | The kill switch suppresses the wake and never drops custody | `…::TestInboxStore_StrictGroupContentStaysSilentWhenDisabled` | host (Go) | causal RED by construction → green | ignore the flag → red |
| TC-387-06 | Strict group reactions stay silent custody | `…::TestInboxStore_StrictGroupReactionStaysSilentCustody` | host (Go) | GREEN by construction → stays green | make reactions eligible → red |
| TC-387-07 | An unusable key epoch degrades to a routing-only push, never to silence | `…::TestInboxStore_StrictGroupContentWithUnusableEpochStillWakes` | host (Go) | causal RED → green | delete the branch → red |
| TC-387-08 | The flag is default-OFF and accepts only `1`/`true` | `…::TestLoadGroupContentPushEnabledFromEnv` | host (Go) | GREEN by construction | flip the default → red |
| TC-387-09 | **The recipient half:** the exact 10 data keys the relay now emits render a trusted card with ZERO `PUSH_ANDROID_DATA_DECRYPT_FAIL`; the routing-only fallback still cards generically | `push_decrypt_preview_test.dart::'strict-lane group content push renders the trusted group card'` + `'strict-lane routing-only fallback still returns a trusted card'` | host (Dart) | GREEN on first run — which is the finding: **no client change was needed** | n/a — the row exists to prove the no-change claim rather than to drive one |

### Test Notes
- TC-387-04 is load-bearing and was added after TC-387-03 already passed. Strict content never reaches
  `InboxStore.Store`; proving the wake only there would be the same class of gap that let G19 ship — a
  host row green on a path the real traffic does not take.
- TC-387-09's fixture is the relay's own output shape, not an invented one. Pin the anchors in a
  comment so a future relay change tells the reader which side moved.
- Two closure gates census the EXACT caller set of `sendSelectedPushThroughGateway`
  (`opaque_wake_closure_test.go`, `push_token_vault_closure_test.go`). Any new push adapter reds both
  until it is declared in their `wantCallers` lists. That is by design and is easy to mistake for a
  real break.

## Affected Files
- `go-relay-server/group_content_push.go` (**new** — extractor, gateway adapter, flag loader)
- `go-relay-server/group_content_push_test.go` (**new**)
- `go-relay-server/inbox.go` (the branch + the `groupContentPushEnabled` field and setter)
- `go-relay-server/main.go` (flag wiring + startup log)
- `go-relay-server/metrics.go` (`relay_group_content_wake_total`)
- `go-relay-server/opaque_wake_closure_test.go`, `go-relay-server/push_token_vault_closure_test.go`
  (declare the new adapter in the caller census)
- `test/features/push/application/push_decrypt_preview_test.dart` (recipient rows)

## Gate Cadence
- `cd go-relay-server && gofmt -l . && go vet ./... && go test ./...` — the authoritative gate for this
  change. The `groups` lane runs the same Go suite at its end.
- `flutter test test/features/push/application/push_decrypt_preview_test.dart` for the recipient rows.
- `./scripts/run_test_gates.sh groups` — carries a KNOWN INTERMITTENT red in
  `group_conversation_wired_test.dart`'s voice block (a different row each run, all pass in isolation).
  It is unrelated: this change touches zero `lib/` files. Verify with
  `git diff --stat HEAD -- lib/` before investigating.
- No `host-all` sweep: no production Dart changed.

## Acceptance Gates  (literal — copy/paste)
```bash
cd go-relay-server && gofmt -l . && go vet ./... && go test ./...   # exit 0, gofmt silent
cd .. && flutter test test/features/push/application/push_decrypt_preview_test.dart   # exit 0
flutter analyze            # 0 new issues
git diff --check
```

## Deferred / Accepted Difference
- **G27 — strict group REACTIONS stay silent custody.** Deliberate: author-only audience (PRD §6.5)
  plus a separate notification-extension grammar. `extractGroupContentPushMetadata` returns them
  recognized-but-ineligible so they can never fall through, and TC-387-06 pins that. The natural fix is
  a strict-custody sibling of `fanOutGroupReactionPush` that reuses the group-topic reaction's audience
  resolution. Unowned.
- **Deployment.** `GROUP_CONTENT_PUSH_ENABLED` is default-OFF, so deploying the binary alone changes
  nothing. Enabling needs a relay deploy plus the env var, on a PRODUCTION box with no staging twin.
  Not done here. Sibling landmine on record: the Plan-344 custody admission flag sat default-off and
  silently killed every offline send until it was flipped on 2026-08-16.
- **Device leg.** None exists. No registered scenario creates a strict-authority group, so
  `groups.muted_notification_campaign` cannot reach this path. A device proof needs a new fixture
  branch that forces the strict lane, and it can only run after the deploy above.
- **Durable wake-outcome ledger.** Strict group content does not participate in the Plan-370
  wake-outcome admission (`directWakeOutcomeProducer` still declines it), so there is no durable
  delivery-outcome row for these wakes. Not a regression — today there is no wake at all — but it is
  the next observability step after the deploy.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-19 | Re-verify the finding | send use case, replay envelope, `inbox.go`, `ack_custody.go`, `reaction_push.go` | source read end to end | strict lane returns before `callGroupSendReliable`; envelope has no `type`; `extractChatPushMetadata` default → `ShouldNotify:false`; direct-reaction extractor also requires `type` | G26 confirmed and BROADER than recorded — reactions are unpushed on this lane too | design |
| 2026-08-19 | Feasibility checks | `addGroupEncryptedPushData`, bmh type routing, `inboxPayload`, `_strictPhysicalGroupRecipientPeerIds`, `register_token` | source read | builder reads this shape unmodified; client routes on `type` only; inner/outer ids agree; recipient ids share the push-token namespace | recipient needs NO change; fix is relay-only | implement |
| 2026-08-19 | W1+W2+W3 | `group_content_push.go` (new), `inbox.go`, `main.go`, `metrics.go` | `go build`/`go vet` clean | branch placed BEFORE the chat switch; declines return rather than fall through | reactions deliberately declined | tests |
| 2026-08-19 | TC-387-01..08 | `group_content_push_test.go` (new) | `go test -run 'GroupContent\|StrictGroup'` green | 9 rows incl. two on the ack-custody path | TC-387-04 added after noticing TC-387-03 proved a path the traffic never takes | mutations |
| 2026-08-19 | Mutation walk (5) | same | every mutation caught | drop branch → wake rows red on BOTH paths; reactions-eligible → 2 red; ignore flag → 1 red; drop custody check → 1 red; drop routing-field guard → 2 red | causality established | recipient half |
| 2026-08-19 | TC-387-09 | `push_decrypt_preview_test.dart` | `+44 All tests passed` | both rows green on first run | confirms the no-client-change claim | full gates |
| 2026-08-19 | Gates | closure census gates | full relay suite green after declaring the new adapter; `flutter analyze` clean; `git diff --check` clean | `groups` lane red is the pre-existing `group_conversation_wired_test.dart` voice flake — zero `lib/` files changed | landed as `37dd2eb20` | deploy + device leg (both open) |

## Handoff
- Turning it on: deploy the relay binary, then set `GROUP_CONTENT_PUSH_ENABLED=1`. The startup log
  prints the resolved value, so confirm it there rather than assuming.
- Watch `relay_group_content_wake_total` after enabling. `attempted` should track strict-group sends;
  a spike in `invalid_or_disabled` means the flag never took or an envelope shape drifted.
- First device experiment: force a strict-authority group on the pinned pair, kill the recipient, send
  one text, and read the recipient's own flow log for
  `PUSH_BACKGROUND_MESSAGE_RECEIVED → PUSH_ANDROID_DATA_DECRYPT_OK → PUSH_BACKGROUND_NOTIFICATION_SHOWN`.
- Unresolved: no device evidence exists for this lane at any tier, and none can until the deploy lands.
