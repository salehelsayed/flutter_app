# Contact-request MCP cases on available Android emulators

Execution owner: `flutter_app`. Use two currently available, pinned, owned
Android emulators; no creation of extra targets and no required API/model band.
Missing targets are N/A by project policy. Planning estimate: 35–60 minutes for
the eight cases, excluding build preparation. Astra performs no device actions.

## Shared setup, evidence and verdict

- Reuse the existing prepared production-main test artifact and its installation/
  state guard. Use isolated test identities, real native crypto/transport and
  ordinary UI input. Do not seed contacts or pending requests. If using
  `ProductionAndroidJourney` preparation, set `prepareContactMesh: false`.
  Identity setup for these cases is not RG-002 onboarding proof.
- Current production bootstrap explicitly leaves `autoAcceptAndReciprocate`
  null (`production_application_bootstrap.dart:6596–6608`), preserving the real
  Accept/Decline dialog. A legacy test that injects an auto-accept callback does
  not certify consent. Do not enable that callback to make a case pass.
- Use the actual Appium MCP tools, current native trees and screenshots. Enter
  genuine UI-generated contact QR data through scanning or a supported paste
  route and label which was used. Paste/emulated camera input does not prove a
  physical camera. Reuse [camera/permission operations](priority-e2e-camera-permission-mcp.md)
  with `entry=contact_scan`. No second WebDriver client or replacement UI.
- Start each independent case/branch with fresh **owned disposable** relationships.
  Preserve identity/data across that branch's restart checkpoints. Never reuse
  an already accepted contact to claim an unsolicited pending-request case.
  Keep codes, keys, peer/device identities and message contents out of mail.
- Save exact candidate/artifact/configuration, native action traces, private
  before/after counts/relationships, screenshots and first failures. Use existing
  read-only production observations when UI cannot establish request identity,
  relay custody or the actual failed send. Do not add a new app control channel.
  A scan tap, radio icon or local “added” message does not prove remote delivery.
- Use 60 seconds for ordinary arrival/linking and 90 seconds for automatic
  reconnect recovery. Preserve first deadlines; no rescan, manual drain or
  extra acceptance may rescue a case that requires automatic recovery.

Generate a private receipt per case, fill only observed checks, then validate:

```sh
python3 scripts/priority_e2e_verdict.py template --case CR-001 --source FULL_INSTALLED_SOURCE_REVISION > PRIVATE_ATTEMPT/receipt.json
python3 scripts/priority_e2e_verdict.py check --case CR-001 --source FULL_INSTALLED_SOURCE_REVISION --receipt PRIVATE_ATTEMPT/receipt.json
```

Change `--case` for each entry below. Bind both roles as Android emulators,
with actual artifact/source/version evidence; `target_kind` is
`android_emulator`. Contact observations require `observed_by: mcp`; a host
control alone cannot complete an emulator observation. Existing host controls
below remain separate causal evidence, never a new device PASS.
`PASS_RECORDED` is a completeness verdict on the executor's supplied facts,
not independent interpretation of screenshots, database contents or crypto.

## CR-001 — explicit acceptance and mutual first chat

Bob enters Alice's real contact code through the supported UI. Alice receives
one pending request identifying Bob and has no accepted contact for him before
her explicit Accept. Accept once, then require reciprocal linking/keys, one
contact each and a distinct exact first message each way. Reopen without data
clear and verify the same relationships and unique messages. Scanner-side local
addition is not proof that the receiving user accepted.

Reuse `contact_request_roundtrip_test.dart` for the two initiating roles and
`contact_request_flow_test.dart` for local pending/accept behavior. Their fake
network/crypto and simulated scan do not certify this emulator UI run.

## CR-002 — decline persists and later consent is fresh

Alice explicitly declines Bob's pending request. Assert no **receiver-side**
accepted contact and restart Alice; the declined request stays terminal and
does not add/re-prompt by itself. Bob may still have his own outgoing local
intent; that alone is not a receiver consent failure. Use the ordinary supported
fresh request/re-add flow from Bob's owned test relationship. Alice must receive
a new pending request requiring another explicit decision, never automatic
re-add. Do not erase Alice's persisted decline to obtain this result.

Existing causal control: `contact_request_flow_test.dart` full-decline and
declined-request rescan cases; database/request repository tests cover persistence.

## CR-003 — missed/opened request stays pending

With Alice's app backgrounded or on a supported surface that cannot present the
request dialog, Bob sends once. Bring Alice back without a resend: the same
request remains discoverable and waits for her answer. Repeat via its real OS
notification tap; navigation/presentation suppression must release and show
the durable pending request without another network delivery. With an owned
sender blocked through the existing supported UI before pending presentation
is released, that sender must not be shown. If the exact UI/state precondition
cannot be established, retain that subleg as incomplete; do not seed state.

Reuse `contact_request_notification_dedupe_integration_test.dart` for the exact
missed-notification suppression race and `pending_request_shell_test.dart`
for retained Feed/Orbit, restart and blocked-peer filtering. MCP observations
are real missed/open UI behavior; the precisely held controller race is host
evidence unless the existing fixture actually witnesses it on the target.

## CR-005 — crossed requests, one relationship and no loop

Capture both genuine codes before either is submitted. With Alice offline,
Alice submits Bob's code (her explicit user intent); Bob then submits Alice's
code (his explicit user intent). Reconnect Alice and retain observations of
both crossing requests. Require one relationship/contact per peer, at most one
relevant pending dialog, no duplicate UI and no endless reciprocal traffic or
re-prompt after restart. Both users' own scan actions are explicit intent;
deduplication alone cannot supply missing consent in the unsolicited CR-001 leg.

This device receipt has scope `emulator_crossed_requests_ui`. It does **not**
claim a same-envelope live-plus-inbox fault was injected. Those exact duplicate
and replay controls already exist in `p2p_service_contact_request_inbox_replay_test.dart`,
`contact_request_flow_test.dart` and the retained-shell tests. To claim that
additional native leg, use an existing fixture and retain the actual identical
request receipt on both paths; repeated taps, a rescan blocked locally, or two
different request IDs cannot stand in for it. No new fault harness is required
by this packet.

## CR-006 — receiver offline for less than a day

Start with a fresh code/request. Make Alice genuinely offline and stop her owned
app. Bob submits once; retain actual relay/inbox custody, not a send tick. Keep
the absence bounded (for example 60 seconds), recording real timestamps below
24 hours. Reconnect and cold-start Alice. Without Bob resending, one pending
request arrives; Alice explicitly accepts and first chat works both ways.
Do not advance clocks or claim that a short absence tests the 24-hour boundary
or longer retention. The catalog does not guarantee delivery beyond that limit.

Reuse the existing inbox-replay and `contact_request_flow_test.dart` offline
bootstrap control; they prove causal protocol/storage behavior through fakes.

## CR-012 — scanner offline and automatic retry

Bob captures Alice's real code, then goes offline before submitting it through
the ordinary scanner/paste UI. Retain the failed/incomplete outbound result and
the same locally owned pending intent. Restore Bob's network and wait for his
own online transition to retry automatically, without rescanning or a manual
drain. Alice sees one pending request, explicitly accepts, and both can chat.
If no retry owner exists or the request cannot be recovered, the UI must report
an honest outcome; a successful-looking local addition is not remote delivery.
The current local “Added to your circle” copy was already refuted as a separate
bug (`TESTING.md:5090–5097`); record actual pending ownership/outcome instead.

Reuse `key_exchange_retry_flow_test.dart` and the incomplete-key retry controls.

## CR-018 — acceptance survives a failed reciprocal and restart

Deliver Bob's request to Alice while both are online. Make **Alice** offline
before she taps Accept; record her committed local acceptance and the actual
failed/uncompleted reciprocal send with retained retry ownership. Restart her
owned app without data clear, then reconnect. Bob must receive the reciprocal
key automatically without another scan/accept; both have one contact, no second
consent prompt, and successful first chat both ways. A normal restart after an
already successful reciprocal is not this failure case.

The old catalog gap is superseded by current durable ownership:
`accept_and_reciprocate_use_case.dart:40–46` queues before accepted status;
production UI/materializer callers pass secure storage. Reuse
`acceptance_reaches_peer_after_restart_test.dart` for the exact before-egress
crash/encryption-failure boundaries. Those held boundaries remain host causal
proof, separate from this real offline-send/restart observation. No app fix here.

## CR-021 — camera refusal/cancel, paste and route closure

Use fresh owned relationships for independent valid-entry branches. With the
shared camera block, deny permission and cancel camera/scanner separately:
neither adds a contact nor sends a request. Grant permission through real OS
UI and complete a valid scan once; an unavailable camera leg stays incomplete,
and paste success cannot certify camera recovery. Separately paste real valid
QR data through the supported UI and require the normal one-request handoff.
Invalid data must produce no contact/request. Submit valid data and observe the
normal scanner close while checking completes; only a successful verification
may complete the add/send/navigation handoff. Do not cancel the async result
because the scanner route closed. Preserve the first unsuccessful result.

Reuse `qr_scanner_wired_test.dart`'s held-verifier/unmounted completion controls
(`TESTING.md:395–425`). MCP must record the actual route/effects; an exact held
verification window is host-only unless an existing target fixture proves it.
Restore this run's permission/network/UI state through the shared camera block.
