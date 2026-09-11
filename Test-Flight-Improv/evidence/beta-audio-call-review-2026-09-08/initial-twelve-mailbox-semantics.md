# Initial twelve beta handles: mailbox interpretation audit

Reviewed 2026-09-08. This is a read-only source and counterexample audit supporting the per-handle reconstruction in `redis-call-timeline.json`. It does not identify encrypted events, establish media outcomes, or attribute a specific client defect to a beta attempt.

## Provenance and historical applicability

- Reused relay Graphify context: query `1a0b4914e6e744a4`, evidence digest `7a2cfaa5a97cd184`. Load-bearing claims below were checked against current source and exact existing test assertions.
- Compared current files with beta base commit `d8b919c5b34575d570a78eb5fbbc4203f56f875b`. The following command returned exit 0 with no differences:

  ```sh
  git diff --exit-code d8b919c5b34575d570a78eb5fbbc4203f56f875b -- go-relay-server/call_control.go go-relay-server/call_control_redis.go go-relay-server/call_control_test.go go-relay-server/wake_outcome.go go-relay-server/wake_token_store_redis.go go-relay-server/call_store_wake_status_test.go go-relay-server/call_wake_attached_recipient_test.go go-relay-server/call_control_adversarial_test.go
  ```

- Root verified the retained old relay backup SHA-256 `d933c15e8dfca516de560312640bab137016215d6f59a5c7145207afd200b6d9` matches the original snapshot. Its embedded build metadata reports `vcs.revision=298934482b0a30960dee47dd1adfd5c4d8e4f40d` and `vcs.modified=true`.
- A second narrow comparison, `git diff --exit-code 298934482b0a30960dee47dd1adfd5c4d8e4f40d d8b919c5b34575d570a78eb5fbbc4203f56f875b --` followed by the same eight paths above, also returned exit 0 with no differences; `git diff --stat` for that exact revision pair and path set was empty. All eight tracked files are byte-identical across the embedded revision, audited base, and reviewed working tree. In particular, there are no tracked changes to the audited Store, ACK, Cancel, RevokeEndpoint, or wake-completion semantics between those revisions.
- **Historical binary limit:** `vcs.modified=true` means the binary was built from a modified working tree. Neither matching tracked files between commits nor the backup's matching binary hash reveals those build-time modifications. The source semantics below are therefore consistent across both tracked revisions, but cannot establish that no uncommitted change affected the historical executable. This comparison requires no change to the audited source conclusions; their application to that binary retains this explicit provenance caveat.
- Tests were inspected, not rerun. No source or device state was changed for this audit.
- The retained export contains 23 directional mailboxes grouped into 12 opaque call-handle aliases. It has no encrypted envelope contents. Root verified that original AOF history was rewritten/deleted at 11:04:34; omitted timing fields cannot now be recovered from that original sequence.

## What each observable establishes

| Observable | Supported interpretation | Unsupported interpretation |
|---|---|---|
| Stored unique event | Relay accepted the request under its authenticated sender identity, validated the matching unexpired wake grant, and committed an opaque envelope to the recipient-scoped mailbox. | Recipient decrypted/validated it, admitted the call, displayed ringing, answered, or received media. |
| First observed sender/direction | Sender of that retained directional relay Store. | Original call initiator or earliest signaling action across all transports. |
| Reverse mailbox event | A stored opaque envelope from the other peer under the same handle. | A ringing acknowledgement, rejection, acceptance, SDP answer, or hangup reason. |
| ACK increase | Authenticated recipient requested removal of matching stored message IDs, and relay committed that removal. | User acceptance, successful decryption, canonical call admission, audible ringing, or media. |
| `pending` tombstone after all events ACKed | Normal replay protection while the mailbox remains eligible for later events until its deadline. | An active or stuck call. |
| `canceled` tombstone | Successful sender-authorized Cancel of that directional mailbox. | A human tapped Cancel, the original caller canceled, or a particular encrypted terminal reason occurred. |
| `expired` tombstone | Relay terminalized a mailbox whose deadline had been reached during a Retrieve or ACK path. | A user-facing no-answer outcome or WebRTC timeout. |
| Final pending event | No successful ACK for that stored envelope appears before the retained state ends. | Failed delivery, failed media, or the kind of that envelope. |
| Wake `completed` | Further wake work for that event was suppressed/completed in relay bookkeeping. | A push was submitted, provider accepted it, device received it, or OS displayed ringing. |

Store keys are scoped by recipient and call handle; the stored sender must remain consistent. Wake grants are checked separately from endpoint/token dispatch availability (`go-relay-server/call_control_redis.go:103`, `:114`, `:166`). A duplicate message ID with the same envelope digest returns duplicate without adding an event; a conflicting digest is rejected (`:172`). Consequently append counts are not request counts.

Retrieve reads and returns unexpired stored events without removing them (`go-relay-server/call_control_redis.go:348`, `:364`). Even a recorded Retrieve would prove a relay response was prepared, not that the response reached or was accepted by the client. ACK is recipient-scoped and removes only requested IDs actually present (`:413`, `:434`). On success it updates pending count and cumulative ACK count, retaining identity/replay facts (`:472`, `:477`, `:495`). The existing partial-ACK test verifies retained pending data, exact replay deduplication, conflicting replay rejection, and no additional wake for an ACKed replay (`go-relay-server/call_control_adversarial_test.go:172`).

Root independently verified the unchanged client launches direct and mailbox sends for each envelope (`lib/features/call/application/call_signaling_service.dart:155`). Therefore one stored event in each direction cannot exclude successful media: other control traffic may have used the direct transport. This audit does not infer how many SDP/ICE messages a successful call requires or whether any particular envelope packs candidates. Envelope count is insufficient without that additional transport evidence.

## Cancel, expiry, and registration deletion are different operations

`Cancel` verifies the authenticated sender against the existing directional mailbox before invoking terminalization (`go-relay-server/call_control_redis.go:514`, `:538`). Automatic client terminal cleanup may make this request; the tombstone contains no user-action or call-reason field. It terminates only that recipient-scoped mailbox, so the reverse direction can have a later Store or later Cancel.

The only `terminalizeTx` call sites are expired Retrieve (`:357`), expired ACK (`:424`), and sender Cancel with state `canceled` (`:541`). Terminalization records the relay clock sample in `TerminalAtMs`, deletes the mailbox payload/identity/claim keys, and retains a payload-free replay tombstone (`:1726`, `:1750`, `:1759`). An unexpired in-flight wake ownership barrier can temporarily reject ACK/Cancel; after provider completion they can succeed (`:1746`). The exact test `TestVC202WakeDispatchGuardSerializesTerminalState` covers this ordering (`go-relay-server/call_control_adversarial_test.go:1070`). Thus request initiation, clock samples, provider invocation, and Redis commit order must not be treated as one timestamp.

Natural Redis key expiry can leave the older `pending` replay tombstone after payload keys disappear. Neither a missing `canceled` marker nor an observed `pending` marker establishes continued client activity. Hard-TTL/replay preservation and sender Cancel are covered by `TestVC202CallMailboxHardTTLCapacityCancelAndProcessHandoff` (`go-relay-server/call_control_test.go:233`).

Endpoint revocation operates on separate endpoint keys: account endpoint DEL, endpoint-device DEL, then separate endpoint-tombstone high-water HSETs (`go-relay-server/call_control_redis.go:1252`). Endpoint publication instead writes account/route records and a combined high-water HSET (`:1178`). The retained adjacent endpoint/route deletion plus split high-water writes match the explicit revoke path; TTL exhaustion alone does not produce these high-water writes. They do not identify which app lifecycle, permission, preference, or token callback requested revocation.

Call-token revoke deletes only its typed token key (`go-relay-server/call_control_redis.go:1502`); matching-token invalidation has the same limited scope (`:1561`). None of these paths writes call-mailbox terminal tombstones. They can prevent subsequent wake dispatch while mailbox storage remains possible with a still-valid wake grant. Provider-invalid-token cleanup can itself follow a dispatch failure and wake completion (`go-relay-server/call_control.go:403`, `:413`). Therefore token/endpoint deletion may precede or follow mailbox cleanup, but adjacency alone cannot establish causation. The typed authority independence test is at `go-relay-server/call_control_test.go:331`; revoked endpoint high-water preservation is at `go-relay-server/call_control_adversarial_test.go:1349`.

## Wake claims: completion is not a provider outcome

There are several distinct ways to produce `completed`:

1. Every successfully ACKed message ID is written as a fresh completed claim, even if no provider invocation occurred (`go-relay-server/call_control_redis.go:484`, `:496`). A subsequent identical completed entry may be ordinary ACK bookkeeping after earlier wake completion.
2. Once an iOS directional mailbox has any ACKed event, later event wakes can be suppressed and written completed (`:665`; attachment definition `:737`). The later envelope is still stored and retrievable. Android continues data wakes for later events. Exact preservation tests: `go-relay-server/call_wake_attached_recipient_test.go:101`, `:146`, `:168`.
3. `CallControlService.Store` calls `CompleteWake` after provider success **and** provider error. It also calls it when the context/deadline check skips provider entry (`go-relay-server/call_control.go:388`, `:392`, `:398`, `:403`). `CompleteWake` receives no provider-success parameter and writes completed when no active/current owners remain (`go-relay-server/call_control_redis.go:1001`, `:1046`).
4. Bounded retry exhaustion can complete bookkeeping without another invocation (`go-relay-server/call_control_redis.go:592`). Ambiguous completion can permit a second provider invocation after lease recovery. Exact recovery-count assertions are in `go-relay-server/call_control_adversarial_test.go:562`.

Consequently even `claimed → dispatching → completed` does not establish a provider submission. Initial claimed state means route/token checks and reservation passed; dispatching state records ownership authorization/lease, not delivery. The service receipt's `WakeStatus=dispatched` is stronger evidence of a nil dispatcher return; `failed` records a dispatch error or pre-dispatch deadline/context failure. Those receipt outcomes are not present merely because the exported claim says completed. Neither receipt is an OS-ringing acknowledgement. Exact receipt assertions distinguish success, provider failure, and attached-iOS suppression (`go-relay-server/call_store_wake_status_test.go:14`); provider-failure custody and ACK-before-wake counterexamples are in `go-relay-server/call_control_adversarial_test.go:308`. The hard-expiry test proves provider entry can be prevented even after durable authorization (`:811`).

Do not equate claim entries, completed entries, unique event ordinals, or maximum attempts with actual push counts. A single event can produce multiple bookkeeping writes; retry recovery can also invoke a provider more than once. Provider attempt/success metrics or receipts must supply that separate fact.

### Lease-derived times

The configured call dispatch lease is five seconds (`go-relay-server/call_control.go:43`). Each of `WakeCurrent`, `WakeDispatchOwned`, and `AuthorizeWakeDispatch` writes a lease of `min(sampled now + 5s, mailbox expiry)` (`go-relay-server/call_control_redis.go:835`, `:900`, `:975`). The latter two can renew the same owner/attempt. `WakeCurrent` only increments attempts on a new/taken-over attempt (`:786`).

- If a retained lease is strictly below the mailbox expiry in force for that write, subtracting 5,000 ms reconstructs the sampled input clock for that specific lease mutation.
- If the lease equals the mailbox expiry, clamping is possible; subtraction gives only a lower bound on that input clock.
- Neither result is an exact provider invocation or AOF commit timestamp. Several such timestamps may belong to the same attempt. Store can reuse an earlier clock sample before its transaction finishes (`go-relay-server/call_control.go:323`); authorization samples its own clock before the authorization transaction (`:359`).

The ordinary direct/group message/reaction outcome machinery in `go-relay-server/wake_outcome.go:47` has separate semantics and must not be substituted for these call-specific claims.

## Expiry and retained timing limits

The relay clamps every Store request to at most sampled relay time plus 45 seconds, independent of encrypted event kind (`go-relay-server/call_control.go:32`, `:301`). A shorter supplied expiry remains shorter. The stored mailbox deadline is the monotonically retained maximum of seen event deadlines, and ACK does not lower it (`go-relay-server/call_control_redis.go:220`, `:235`, `:477`). Differences in event or mailbox expiry cannot reliably identify invite, ringing, accept, reject, candidate, or terminal events. They also need not equal an opaque inner envelope's original signed deadline.

The source can write `lastRetrieveAtMs` when preparing a live mailbox Retrieve (`go-relay-server/call_control_redis.go:381`), but successful nonempty ACK does not write a dedicated ACK time; `lastAckAtMs` is written only in the no-matching-ACK branch (`:463`). Root verified that neither field was exported for these 12 handles. The retained meta transitions contain only first-receipt time, expiry, pending count, and cumulative ACK count. Exact fetch/ACK times are therefore unavailable; do not present the theoretical source fields as recovered incident evidence.

For call-095's reverse mailbox, the retained ordered transitions show the first seven events drained to zero pending/seven ACKs before the eighth append at 10:12:21.939 UTC. Only that final envelope lacks a retained ACK; aggregate eight stored/seven ACKs alone would not identify which event remained. This is still not evidence of a media failure or of that final envelope's type.

## Corrections required in any per-call conclusion

- Replace “caller canceled” with “sender of this directional mailbox canceled relay custody” unless independent client evidence identifies the caller and action.
- Replace “reply/rejection/answer” inferred from a reverse envelope with “reverse-direction opaque signaling event.”
- Replace “push sent/rang” inferred from completed claims with “wake bookkeeping completed; provider/device outcome unavailable.”
- Replace “not connected because only one message each way” with “sparse retained mailbox traffic; direct traffic and media outcome unknown.”
- Replace “stuck pending call” after full ACK with “normal retained replay mailbox state.”
- Keep explicit endpoint/token withdrawal distinct from both mailbox cancellation and ordinary TTL exhaustion; the requesting client reason remains unproven.

The retained facts support directional storage, observed ACK counts, authenticated mailbox cancellation, registration mutations, and bounded clock samples. They do not provide a defensible per-handle encrypted reason, ringing outcome, user decision, or media verdict by themselves.
