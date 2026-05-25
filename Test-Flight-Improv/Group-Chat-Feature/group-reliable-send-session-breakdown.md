# Reliable Group Send Session Breakdown

Status: closed
Source bug: "There is still no single reliable send group message path"

## Program Scope

Close the group-message reliability gap by adding one native send path that builds a single live group envelope, stores that exact envelope to group inbox for the active recipient set, publishes it live, and returns delivery evidence that Flutter can use without claiming "sent" prematurely.

## Session Ledger

| Session | Status | Scope | Plan |
| --- | --- | --- | --- |
| GSR-001 | accepted | Native reliable group send plus Flutter send-status contract | `group-reliable-send-session-GSR-001-plan.md` |

## Controller Progress

- 2026-05-23: Intake complete. Existing code has separate `group:publish` and `group:inboxStore`; group inbox ACLs are peer IDs on the relay stream, which means active device transport peer IDs for deviceful groups.
- 2026-05-23: GSR-001 accepted. Added native reliable group send, bridge/Dart route, Flutter status gating, v3 offline replay decode, platform wrapper routes, local gomobile artifact refresh, and focused regression evidence.

## Final Program Verdict

accepted

The normal group message path now has a single reliable native command that builds one v3 group envelope, stores that exact envelope for native active recipients, publishes it live, and returns delivery evidence. Flutter marks the message sent only when inbox storage succeeds or live topic fanout covers all expected active recipients; partial live-only delivery remains pending/retryable.
