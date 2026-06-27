# FDC-09b — presence resolver fg/bg branch (read-side emphasis fix)  (Modification)

Status: **ready (host-testable; fix now — does NOT wait on the device/native rebuild).** Read-side
twin of FDC-09's `presence_set` write, consumed by FDC-08's `presence_get` + send-emphasis.

Parent: `FDC-09-foreground-self-publish-push-hardening-tdd-plan.md` (post-review design-note #2).
Spec source: FDC-S3 `FDC-S3-presence-signal-decision.md` §"Canonical contract" (resolver ladder + §6.3
emphasis branch) + the post-review confirmation against `presence_store.go:113-141`.

---

## Exact Problem Statement

The relay presence resolver `PresenceStore.Lookup` (`go-relay-server/presence_store.go:137-141`) collapses
**any** fresh self-published `presence_set` state to `reachable` — rule #1 never branches on the
`selfState` field:

```go
// (1) Prefer a fresh self-published state ...
if ok && e.selfState != "" && now.Sub(e.selfPublishedAt) < e.selfTTL {
    return presenceResolution{presence: presenceReachable, ageMs: ageMs}   // fg AND bg both -> reachable
}
```

So `presence_set{background}` reads `reachable`, which ships the §6.3 emphasis **backwards for the primary
iOS-background case**: a peer that explicitly self-published "I'm backgrounded" drives
`reachable → inbox lazy + direct-race` (wasted dials to a soon-suspended peer) instead of the
`unreachable → inbox-first + push-to-wake` a backgrounded peer needs (commit the durable copy FIRST so the
relay store→push fires sooner, before iOS suspends).

**Severity:** wake-promptness / emphasis, **NOT** delivery-loss — `PRESENCE_NEVER_LOAD_BEARING`
(TC-09-13 / FDC-08 C7) guarantees the message still delivers via inbox + push regardless. But it degrades
the exact case the feature targets, so fix before activation.

**What must stay locked (preserved sentinels):**
- `PRESENCE_IS_ONLINE_ISH_NOT_FOREGROUND` — the `presence_get` response exposes ONLY
  `reachable|unreachable|unknown`, **no fg/bg field** (`TestPresenceResponseNeverClaimsForeground`,
  `inbox_presence_test.go:145`). The relay consumes the self-published fg/bg **internally** to pick the
  coarse value — that is exactly where Option C's "express foreground/background" purpose is realized.
- `foreground → reachable` unchanged (`TestPresenceSet_AdditiveAction_StoresState`).
- TTL-expiry → `unknown` unchanged: a stale self-state falls through to the connectedness-seeded last-seen
  (seeded by `RecordSeen` at publish) and degrades to `unknown`, never silently `unreachable`
  (`TestPresenceSet_TTLExpiry_DegradesToUnknown`, which publishes `background` then advances past TTL — it
  asserts only the POST-expiry value, so it stays green).
- `PRESENCE_NEVER_LOAD_BEARING` — store→push is presence-independent (TC-09-13); delivery unaffected.

---

## Root Cause (verify→refute confirmed)

| # | Mechanism (file:line) | Confirmed |
|---|---|---|
| RC1 | Resolver rule #1 returns `presenceReachable` for any non-empty `selfState`; it never reads the fg/bg value the `presence_set` write recorded (`presence_store.go:139-141`). "Prefer self-published state" was implemented as "entry-exists ⇒ reachable" instead of "use its fg/bg to decide." | ✅ read |

**Refuted / do-not-reintroduce:**
- ❌ Do NOT expose fg/bg in the wire response (FDC-S3 hard invariant; the response stays coarse).
- ❌ Do NOT make `background` resolve to `unknown` — the peer is definitively-self-reported, not "we're not
  sure"; §6.3 wants `unreachable → inbox-first + push-to-wake`. (`unknown` is the stale-TTL degrade only.)
- ❌ Do NOT gate delivery on presence (TC-09-13 stays green; store→push fires regardless).
- ❌ Do NOT reorder rule #1 below the connectedness branch — a self-reported `background` must win over a
  lingering iOS socket (that is the whole point; live legs stay best-effort on the send side).

---

## Real Scope

**In scope (FDC-09b):** branch resolver rule #1 in `presence_store.go` on `selfState`
(`foreground → reachable`, else `unreachable`); reconcile the ladder doc-comment; add the Go-unit RED lock;
reconcile the FDC-S3 canonical-contract ladder note + the FDC-09 plan's Accepted-Differences note.

**Out of scope:** the §6.3 send-emphasis branch in Dart (FDC-08-owned; consumes the coarse value, already
maps `unreachable → inbox-first`); the §12 wake-gate ship-order (FDC-09 H1, separate); native dispatch +
framework rebuild (deferred); device rows.

---

## RED Test Catalog

- **TC-09b-01** · `go-relay-server/inbox_presence_test.go::TestPresenceSet_BackgroundResolvesUnreachable_ForegroundReachable`
  · **Tier:** Go-unit (relay)
  · **Setup:** two DISCONNECTED peers (`genDisconnectedPeerID`, so `connected=false` — the connectedness
  branch cannot mask the self-state branch); seed `env.presence.SetSelfPublished(fg,"foreground",TTL)` and
  `SetSelfPublished(bg,"background",TTL)`; query each via `sendPresenceGet` (full dispatch →
  `handlePresenceGet` → `Lookup`).
  · **RED on HEAD because:** rule #1 returns `reachable` for any `selfState`, so the `background → unreachable`
  assertion fails (HEAD returns `reachable`).
  · **GREEN asserts:** `foreground → reachable`; `background → unreachable`. (Response still coarse — no
  fg/bg key; the existing invariant test holds that separately.)
  · **Mutation that re-reds:** revert the resolver branch (back to unconditional
  `return reachable`) → `background` reads `reachable` → re-reds.

---

## Test Coverage Matrix

| Spec case | Behavior property | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| §6.3 bg emphasis | fresh `background` self-state → `unreachable` | Go-unit | `inbox_presence_test.go::TestPresenceSet_BackgroundResolvesUnreachable_ForegroundReachable` | rule #1 returns `reachable` for any selfState (`:139-141`) | revert resolver branch to unconditional reachable | `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...` | go test (no array) |
| §6.3 fg emphasis | fresh `foreground` → `reachable` (unchanged) | Go-unit | same test (fg arm) + `TestPresenceSet_AdditiveAction_StoresState` (regression floor) | n/a (preserved) | n/a (regression) | `GOTOOLCHAIN=go1.25.0 go test ./...` | go test |
| FDC-S3 invariant | response exposes no fg/bg field | Go-unit | `TestPresenceResponseNeverClaimsForeground` (regression floor) | n/a (locked) | n/a | `GOTOOLCHAIN=go1.25.0 go test ./...` | go test |
| TTL freshness | stale `background` → `unknown` (not `unreachable`) | Go-unit | `TestPresenceSet_TTLExpiry_DegradesToUnknown` (regression floor; asserts POST-expiry only) | n/a (preserved via last-seen path) | n/a | `GOTOOLCHAIN=go1.25.0 go test ./...` | go test |
| HINT-only | wrong/any presence still delivers via inbox+push | Go-unit | `TestWakePush_StillDelivers_WhenPresenceWrong` (TC-09-13 regression floor) | n/a (store→push presence-independent) | n/a | `GOTOOLCHAIN=go1.25.0 go test ./...` | go test |

*No empty cells. Single behavior-bearing edit (resolver branch) → one re-red mutation (TC-09b-01).*

### Blind-spot sweep
- **Lifecycle / derived-state durability:** the bg read is derived; after `selfTTL` it degrades to `unknown`
  via the connectedness last-seen (`RecordSeen` seeds it at publish) — covered by the TTL-expiry regression
  floor. Pre-expiry bg→`unreachable` + post-expiry bg→`unknown` transition both locked.
- **Sibling-surface consistency:** FDC-08's Dart `lookupRelayPresence` consumes the COARSE value; the
  contract (reachable|unreachable|unknown) is unchanged, only which value a bg self-state yields. No FDC-08
  Dart test publishes a real `background` (they fake the coarse value), so none breaks — **N/A** (verified by
  inspection; the relay→Dart wire contract is unchanged).
- **Destructive-action side-effects:** N/A — read-only resolver, no state mutation.
- **Invariant re-verification under new transition:** `PRESENCE_NEVER_LOAD_BEARING` re-checked — bg→`unreachable`
  does NOT suppress the store→push (presence-independent seam); TC-09-13 is the regression floor.

---

## Step-By-Step Implementation Plan

1. **(RED)** Add `TestPresenceSet_BackgroundResolvesUnreachable_ForegroundReachable` to
   `inbox_presence_test.go`. Confirm RED on HEAD (bg arm fails: returns `reachable`).
2. **(GREEN)** Branch resolver rule #1 (`presence_store.go:137-141`) on `e.selfState`:
   `foreground → reachable`, else `unreachable`. Keep `ageMs` as-is. Surgical edit — co-owned contested file
   on shared `new-orbit`; **no git checkout**.
3. **(DOC)** Reconcile the `Lookup` ladder doc-comment (`presence_store.go:113`) so rule #1 reads
   "fresh self-published state → `reachable` iff `foreground`, else `unreachable`"; add a one-line note to the
   FDC-S3 doc's canonical-contract ladder and the FDC-09 plan's Accepted-Differences design-note.
4. **(VERIFY)** Run the mutation (revert the branch → TC-09b-01 re-reds); then the full Go gate (incl `-race`)
   under `GOTOOLCHAIN=go1.25.0`; confirm the FDC-09 foreground/TTL-expiry/invariant/HINT-only floors stay green.

---

## Acceptance Gates

```bash
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...        # all relay tests incl TC-09b-01 + FDC-09 floors GREEN
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && GOTOOLCHAIN=go1.25.0 go test -race ./...  # presence map still race-clean
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && make lint                                 # 0 issues (FDC-S5 gofmt nit pre-existing, NOT this change)
```
Expected: PASS (0 fail). TC-09b-01 GREEN; `TestPresenceSet_AdditiveAction_StoresState` /
`TestPresenceSet_TTLExpiry_DegradesToUnknown` / `TestPresenceResponseNeverClaimsForeground` /
`TestWakePush_StillDelivers_WhenPresenceWrong` all still GREEN.

---

## Scope Guard (hard Do-not)
- Do **not** expose fg/bg in the wire response (FDC-S3 invariant; `TestPresenceResponseNeverClaimsForeground`).
- Do **not** make `background → unknown` (that is the stale-TTL degrade only).
- Do **not** reorder rule #1 below the connectedness branch.
- Do **not** gate delivery on presence (TC-09-13 stays green).
- Surgical edit to the contested `presence_store.go` only; **no git checkout / stash** of shared files.

## Done Criteria
- [ ] TC-09b-01 authored RED-first, GREEN after the branch, mutation re-reds.
- [ ] `GOTOOLCHAIN=go1.25.0 go test ./...` (+ `-race`) green; FDC-09 foreground/TTL-expiry/invariant/HINT-only
      floors green; `make lint` no new issues.
- [ ] Ladder doc-comment + FDC-S3 ladder note + FDC-09 Accepted-Differences note reconciled.
