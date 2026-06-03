# Group Chat — Review & Improvement Proposal

> Goal: make the group-chat feature a **seamless and reliable** experience.
> Generated 2026-06-02 by a 37-agent review workflow (12 subsystem reviewers → adversarial verifiers → synthesis → per-theme writers).
> Coverage: **12 subsystems**, **86 findings** raised, **80 verified-kept**, **6 dropped as false-positives**.

This is a **review and proposal package** — no production code was changed. Each theme below is a standalone, implementation-ready proposal document.

---

## How to read this

1. Start with the **Executive Summary** and **Scorecard** below.
2. Work the **Prioritized Roadmap** top-down — P0 themes are what make the app *feel* broken today.
3. Each theme links to a detailed doc: why it matters, current behaviour + `file:line` evidence, root cause, concrete code-level fixes, affected files, test strategy, risks, and effort.
4. The **[Findings Appendix](./appendix-findings.md)** has all 80 verified findings with verifier verdicts, plus per-subsystem current-state & strengths.

---

## Executive Summary

## Overall verdict

The mknoon group-chat feature is **architecturally mature and security-rigorous, but not yet seamless or dependably reliable from the user's seat.** The deep machinery is genuinely good: the send path centralizes optimistic persistence behind a disciplined result matrix that correctly distinguishes live fanout (`topicPeers`) from real delivery and classifies timeouts as in-doubt rather than false-failed (`send_group_message_use_case.dart`); the receive path is heavily defended with layered dedup, serialized live processing, and DB-merge-on-conflict; the transport validator and the crypto/audit verification are strong; and the offline-inbox drain is a robust three-phase, cursor-paginated, lock-aware pipeline. The bones are right.

The problem is that **the gaps cluster precisely where the user forms their judgment of reliability: "did my message send, can I read theirs, and did the app respect my settings."** The single largest systemic risk is the **duplicate-delivery / stuck-state cascade** documented in doc 102. It is not one bug but an emergent loop spanning four subsystems: a Flutter reliable-send timeout (10s) shorter than the native budget (15s+30s) pushes sends into in-doubt `pending`; the open conversation screen never observes background status changes; failed text has no in-place retry; and restored-composer resends mint a fresh `messageId`. A user who sees a clock/error icon retypes, and because the original often did deliver via flood-publish/relay custody, recipients get two copies. Verified in code: group conversation wires retry for media only, with no `onRetryFailedMessage` callback.

The second systemic risk is **undecryptable / silently-dropped messages around membership changes.** The `KeyRotationGracePeriod = 30s` (confirmed in `config.go`) is far too short for mobile reality, the Go node retains only one previous epoch, key repair is entirely passive (a member who misses a key never asks for it and only retries on the next key update), and live decryption-failure placeholders can never resolve and sit alongside the real message once it arrives. Layered on top, rotation fails closed and rolls back a removal if any remaining member lacks a usable ML-KEM key — meaning an admin can fail to remove someone, and the removed member keeps the live key. These produce the worst possible group-chat experience: messages that are permanently unreadable for some members and present for others, right after the group changes.

The third systemic risk is **notifications ignoring the user's settings and membership boundaries.** Mute is only checked on the live GossipSub path and has no presence in the iOS NSE resolver or the Android background handler (confirmed by grep — zero matches), so muted groups keep buzzing exactly when notifications matter most (backgrounded/offline). Android previews are never decrypted, so every group push reads a generic "New Message." Removed members keep getting notified. The test matrix itself flags duplicate notifications and removed-member notifications as P0.

A fourth, more contained risk is **state divergence in the consensus layer.** Role-update skips the mutation lock and stale-gate that add/remove use; full-config snapshots carried by membership/role events silently regress independently-versioned metadata (the group name flips back and forth); metadata edits aren't atomic with broadcast and have no rollback; and equal-microsecond events are dropped as stale. These are lower-frequency but high-trust-damage when they hit.

The **multi-device story is documented but largely inert at runtime**: a restored second device materializes no groups, members, or keys, and no path admits a sibling device into a roster, so its messages are silently dropped. The convergence "proof" is test-only. This is honestly a scoping/claims problem as much as an engineering one — UX-013 should not be marked closed.

The recommended program is **stabilize-the-loop first, then close the trust gaps.** Phase 0 (P0) attacks the duplicate cascade and the undecryptable-message cluster end-to-end, plus the mute/membership notification leaks — these are what make the app *feel* broken. Phase 1 (P1) hardens recovery orchestration (the advisory gate that isn't a lock, overlapping passes, no backoff), the relay-inbox cross-instance cursor/eviction hazards, membership convergence, and media size/terminalization gaps. Phase 2 (P2) is the polish and honesty layer: i18n, scroll-to-message, list debounce, distinct no-peers feedback, and either implementing real multi-device convergence or downgrading the closed claim. The encouraging news is that a disproportionate amount of P0-relevant value is **small-effort** — the text-retry button, id-stable resends, the timeout-budget bump, mute checks on the Android/fallback path, the dead-tap fix, and the range-hash golden-vector test are all quick wins that directly defuse the most visible failures.

---

## Subsystem Scorecard

Reliability and UX scored 1–5 (5 = excellent) by the synthesis pass over verified findings.

| Subsystem | Reliability | UX | Top risk |
|---|:--:|:--:|---|
| **Send path** | ●●●○○ (3) | ●●○○○ (2) | Duplicate-delivery cascade: 10s Flutter timeout vs 15s+30s native budget pushes sends to in-doubt 'pending'; no in-place text retry + non-id-stable restored-composer resend means recipients get two copies of one intended message (doc 102). |
| **Receive path** | ●●●●○ (4) | ●●●○○ (3) | Live decryption-failure placeholders never resolve and sit alongside the real message once it arrives, reading as a stuck/duplicated message; reactions arriving before their target are silently dropped and processed unserialized. |
| **Transport / GossipSub** | ●●●○○ (3) | ●●●○○ (3) | Publish is fire-and-forget with no per-recipient confirmation, newer-epoch messages are ValidationReject'd (penalized + permanently dropped) instead of Ignored, and synchronous member dialing in the send hot path adds visible send latency. |
| **Recovery & reliability** | ●●●○○ (3) | ●●●○○ (3) | GroupRecoveryGate is advisory not a lock, so startup/resume/retrier can drain the same groups concurrently; the 30s stuck-sweep keys off creation time and can flap an in-flight retry failed->sending->failed, risking duplicates; no backoff/jitter anywhere. |
| **Invites** | ●●●○○ (3) | ●●○○○ (2) | Accept couples invite-consumption to a best-effort drain (scenario-7 'joined but still catching up' over a stale snapshot, re-tappable invite); 24h freshness vs 7d card expiry silently rejects still-shown invites; no on-join metadata resync, no revoke UI, no expiry sweep. |
| **Membership & lifecycle** | ●●●○○ (3) | ●●●○○ (3) | Role-update has no lock/stale-gate (roles diverge across members), and membership/role full-config snapshots silently regress independently-versioned name/description/avatar so the group name flips back and forth; metadata edit is non-atomic with broadcast with no rollback. |
| **Crypto & key management** | ●●○○○ (2) | ●●○○○ (2) | Undecryptable-message cluster: 30s grace + single retained prev-epoch + fully passive key repair (no active pull, retried only on next key update) leaves permanent 'waiting for key' placeholders; rotation fails closed and rolls back a removal if any remaining member lacks a usable ML-KEM key, re-granting the key to the removed member. |
| **Relay server inbox** | ●●●○○ (3) | ●●●○○ (3) | Cursor IDs are per-process/per-INCR counters not portable across restart/failover, so a resumed cursor silently restarts pagination from head; 500-cap eviction orphans an offline member's cursor into a silent gap; range-hash must stay byte-identical across Go/Dart or every gap-repair silently fails. |
| **Multi-device convergence** | ●○○○○ (1) | ●○○○○ (1) | Convergence is test-only: a restored second device materializes no groups/members/keys and no path admits a sibling device, so its messages are silently dropped while showing 'sent' locally. The 'all my devices converge' contract is unreachable at runtime. |
| **UI / UX** | ●●●○○ (3) | ●●●○○ (3) | Delivery-feedback and recovery seams: no failed-text retry, security/MITM warnings computed but never shown in-conversation, notification taps don't scroll to the target message, hardcoded 12h AM/PM breaks de/ar, and the list does a full O(N) reload per incoming message with no debounce. |
| **Media** | ●●●○○ (3) | ●●●○○ (3) | The only real size gate is 5GB (multi-GB videos accepted, huge sends/downloads), download failures retry forever with no terminal state, and 7-day relay TTL + frozen ACL can leave media permanently unavailable for offline/late-joining members while others see it. |
| **Notifications** | ●●○○○ (2) | ●●○○○ (2) | Mute is enforced on only one of several producing paths (no presence in iOS NSE resolver or Android background handler), Android previews are never decrypted (always generic), removed members keep being notified, and iOS remote-vs-live dedupe depends on the Dart background isolate firing — all test-matrix P0s. |

---

## Prioritized Roadmap

### P0 — Blocks a seamless/reliable experience (do first)

#### [Kill the duplicate-delivery / stuck-send cascade (doc 102)](./01-P0-duplicate-delivery-cascade.md)

_Extend the doc-102 cascade fix (which landed for **images**) to the **text** and **voice** paths, close the **timeout asymmetry** doc 102 deferred, and prove the closure doc 102 left `blocked`._

**Why this priority:** This is the single most visible reliability failure: users see clock/error icons, retype, and recipients get duplicates because the original actually delivered. **Scope note (verified in code):** doc 102 + GIRD-001…007 already fixed this for **images/media** and several fixes are live (timeout no longer false-fails, same-id self-echo repairs even failed rows, open screen refreshes on stream events). The residue this theme owns is narrower but real — the same cascade on **plain text** (no in-place text retry, text retype mints a fresh id) and **recorded voice** (separate `_onRecordStop()` path the doc-102 fix never touched; a re-record produces different bytes no dedup can collapse), the **root 10s-vs-~30s timeout** doc 102 explicitly declined to change, and doc 102's own end-to-end closure being `blocked with evidence`. Most pieces are small-to-medium and directly defuse the residue.

**Findings:** 8 · **Subsystems:** Receive path, Recovery & reliability, Send path, UI / UX

#### [Eliminate permanently-undecryptable messages around membership/key changes](./02-P0-undecryptable-messages-self-heal.md)

_Widen the grace/epoch retention, add an active key-pull, and make decryption-failure placeholders resolve or self-clear instead of sitting next to the real message forever._

**Why this priority:** Messages that are unreadable for some members and present for others, right after a group change, is the deepest possible trust break for a PQ messenger. The current model (30s grace, one prev epoch, passive repair) cannot survive normal mobile offline patterns. High effort in places but non-negotiable for a reliable group chat.

**Findings:** 8 · **Subsystems:** Crypto & key management, Receive path, Transport / GossipSub

#### [Make member removal durable and security-correct](./03-P0-removal-rotation-fails-closed.md)

_Decouple removal/rotation durability from full-fanout success so a kicked member always loses the key, even if an unrelated member's ML-KEM key is missing._

**Why this priority:** An admin who cannot reliably remove someone — and worse, a rollback that re-grants the live key to the removed member — is a correctness and security failure that undermines the entire membership boundary. Combined with the related leave/rotation split-brain it leaves the roster ambiguous across members.

**Findings:** 2 · **Subsystems:** Crypto & key management, Membership & lifecycle

#### [Make notifications honor mute, membership, and one-per-message](./04-P0-notifications-respect-settings-and-membership.md)

_Enforce mute and removed-member suppression on ALL push paths, decrypt Android previews, and make NSE-vs-live dedupe authoritative._

**Why this priority:** Mute and membership leaks plus duplicate notifications are explicitly P0 in the test matrix and make the app feel like it ignores the user. Mute has literally zero presence in the NSE/background paths today. The Android generic-preview and full mute-everywhere fixes are large, but the Android/fallback mute check and the dead-tap fix are quick wins that ship immediately.

**Findings:** 8 · **Subsystems:** Notifications, Receive path

### P1 — Significant reliability/trust hardening

#### [Harden recovery orchestration: real locking, scoping, and backoff](./05-P1-recovery-orchestration-hardening.md)

_Turn the advisory gate into a real mutex, keep follow-on retries inside it, drain the first page fast, and add jitter/backoff to stop thundering-herd convergence._

**Why this priority:** Overlapping startup/resume/retrier passes waste work and contend on the DB during the most performance-sensitive moment, slowing the catch-up the user is staring at, and the all-or-nothing ack can strand a node in needsGroupRecovery forever. Significant but mechanical; makes coming-back-online feel fast instead of janky.

**Findings:** 7 · **Subsystems:** Recovery & reliability

#### [Guarantee complete, ordered offline catch-up across relay lifecycle](./06-P1-relay-inbox-catchup-integrity.md)

_Make cursors backend-portable, surface cap-eviction as an explicit gap, lock the range-hash byte-for-byte, and collapse the two divergent pagination paths._

**Why this priority:** Cross-instance cursor breakage, silent cap eviction, and a fragile cross-language range hash can silently drop or re-replay an offline member's backlog — the conversation diverges across members invisibly. The range-hash golden-vector test is a quick win that protects the entire gap-repair safety net.

**Findings:** 9 · **Subsystems:** Relay server inbox, Transport / GossipSub

#### [Make membership/role/metadata converge consistently](./07-P1-membership-convergence-consistency.md)

_Lock and stale-gate role updates, stop membership snapshots from regressing metadata, make metadata edits atomic with broadcast, and break equal-timestamp ties deterministically._

**Why this priority:** Diverging roles, a group name that flips back and forth, and silently-dropped same-microsecond edits read as a broken/untrustworthy group. Lower frequency than the P0 clusters but high trust-damage; the role-update lock+stale-gate is a small, high-value fix.

**Findings:** 5 · **Subsystems:** Membership & lifecycle

#### [Make joining a group clean, current, and manageable](./08-P1-invite-join-reliability.md)

_Decouple invite-consumption from the drain, resync authoritative metadata on join, align freshness/expiry, and wire revoke + expiry sweeps._

**Why this priority:** The scenario-7 'joined but still catching up over a stale snapshot, re-tappable invite' and the 24h-vs-7d silent-reject are confusing first impressions for a brand-new member. Mostly medium effort; the freshness/expiry alignment and the expiry sweep are near-quick-wins that remove dead/misleading invite cards.

**Findings:** 6 · **Subsystems:** Invites

#### [Bound media size and give media an honest terminal state](./09-P1-media-bounded-and-honest.md)

_Add product-tuned per-type size limits, cap download retries with a real 'unavailable' terminal state, and make group-media retention member-aware._

**Why this priority:** A 5GB-only gate means multi-GB sends and forever-spinning downloads; combined with 7-day TTL + frozen ACL, media diverges across members and never resolves to an honest state. The per-type size table and GIF consolidation are small; retention/ACL backfill is large but can follow.

**Findings:** 6 · **Subsystems:** Media, UI / UX

### P2 — Polish, honesty & performance

#### [Make reactions as reliable as messages](./10-P2-reaction-reliability.md)

_Give reactions offline custody, serialize add/remove with last-writer-wins, and buffer reactions that arrive before their target._

**Why this priority:** Divergent reaction state across members is a noticeable but lower-stakes trust issue than missing messages. Reasonable medium effort; the offline-custody fallback is small and removes silent reaction drops.

**Findings:** 3 · **Subsystems:** Receive path, Send path

#### [Close the in-conversation feedback, i18n, and performance seams](./11-P2-in-conversation-feedback-and-i18n-polish.md)

_Surface security warnings in-thread, scroll to the tapped message, localize timestamps, debounce the list, and give no-peers sends a truthful indicator._

**Why this priority:** These are visible polish gaps that make the app feel less native/finished (especially for de/ar users) but don't break correctness. Mostly small effort, ideal fast-follow after the P0 stabilization.

**Findings:** 11 · **Subsystems:** Receive path, Send path, Transport / GossipSub, UI / UX

#### [Make multi-device real or stop claiming it](./12-P2-multi-device-honesty.md)

_Implement true second-device hydration + sibling-device admission, or downgrade the UX-013 'closed' claim to 'device-local until a sync channel exists'._

**Why this priority:** The contract is documented and unit-modeled but inert at runtime, so a restored second device silently drops messages. Real convergence is large effort; the honest interim is to scope the claim down. Low frequency today (most users single-device) so P2, but the closed-claim overstates reliability.

**Findings:** 6 · **Subsystems:** Crypto & key management, Multi-device convergence

---

## Quick Wins

Small-effort, high-value changes that directly defuse the most visible failures — shippable without large redesign:

- Add an in-place retry for failed text messages: wire onRetryFailedMessage in group_conversation_screen.dart/wired (render when canWrite && isSent && status=='failed') calling the existing id-stable retryFailedGroupMessage. The screen already wires retry for media only — this directly removes the retype-and-duplicate behavior. (send-path:no-text-message-retry-affordance, ui-ux:no-retry-for-failed-text-messages)
- Make restored-composer text resends id-stable: in _restoreComposerSnapshot, always record draftText/quote/timestamp/messageId for failed text rows so a matching resend reuses the original messageId (already done for media). Removes a primary duplicate source. (send-path:restored-composer-text-resend-not-id-stable)
- Raise the Flutter reliable-send timeout (~10s) to comfortably exceed the native 15s+30s budget (e.g. ~35-40s) so the common slow-network case resolves to a real 'sent' instead of in-doubt 'pending'. One-line-ish change in bridge_group_helpers.dart. (send-path:reliable-send-timeout-budget-mismatch)
- Build group notifications from the persisted, sanitized result.senderUsername/result.text instead of raw wire fields — removes the impersonation/injection surface and matches the timeline. (receive-path:notification-uses-unsanitized-wire-username-text)
- Wrap updateGroupMemberRole in runGroupMembershipMutationLocked and add the isStaleGroupMembershipEvent guard (mirroring add/remove) so concurrent role changes converge. (membership-lifecycle:role-update-no-lock-no-stale-gate)
- Add the isMuted check to the Android Dart background handler and the foreground/error fallback so those paths respect mute today (full NSE/relay mute can follow). (notifications:mute-not-enforced-on-push-paths)
- Fix the dead-tap: on the group-missing branch, navigate to the group list/home and show a transient 'Couldn't open — still catching up' with retry instead of returning silently. (notifications:dead-tap-on-unrecoverable-group-push)
- Lock the history-gap range hash with a cross-language golden-vector test (Go + Dart produce identical hex for the same reduced {from,message,timestamp} projection) so gap-repair can never silently fail. (relay-inbox:history-gap-hash-parity-risk)
- Localize timestamps: replace the hardcoded 12h AM/PM _formatTime with intl.DateFormat.jm(localeName) in group conversation and list screens — fixes de/ar immediately. (ui-ux:hardcoded-ampm-time-format)
- Invoke deleteExpiredPendingInvites/Revoked/Consumed on startup + periodic timer (alongside PendingMessageRetrier wiring) and filter expired/materialized rows out of getPendingInvites so dead invite cards stop accumulating. (invites:no-expiry-sweep-lingering-invites)
- Stage the reaction replay-outbox entry BEFORE the live publish so a publish failure leaves a retryable, durable reaction instead of a silent drop — mirrors the message path. (send-path:reaction-no-offline-fallback)
- Compute the invite card's effective expiry as min(policy expiry, proof.expiresAt) and distinguish the expired-freshness snackbar with 'ask the admin to resend' so 24h-stale invites no longer show an enabled-but-failing Accept. (invites:freshness-ttl-vs-invite-ttl-mismatch-silent-reject)
- On the user's own send, scroll the reverse ListView to the live edge in a post-frame callback so they always see their just-sent message even when scrolled up. (ui-ux:optimistic-send-no-scroll-into-view)
- Add explicit per-type media size limits (e.g. ~25MB image, ~100MB video, ~16MB voice) in GroupMediaSizePolicy.validateSize decoupled from the 5GB budget, surfaced via the existing media_too_large UX before upload starts. (media:media-size-gate-is-effectively-5gb)

---

## Theme Index

| # | Priority | Theme | Findings |
|--:|:--:|---|:--:|
| 01 | P0 | [Kill the duplicate-delivery / stuck-send cascade (doc 102)](./01-P0-duplicate-delivery-cascade.md) | 8 |
| 02 | P0 | [Eliminate permanently-undecryptable messages around membership/key changes](./02-P0-undecryptable-messages-self-heal.md) | 8 |
| 03 | P0 | [Make member removal durable and security-correct](./03-P0-removal-rotation-fails-closed.md) | 2 |
| 04 | P0 | [Make notifications honor mute, membership, and one-per-message](./04-P0-notifications-respect-settings-and-membership.md) | 8 |
| 05 | P1 | [Harden recovery orchestration: real locking, scoping, and backoff](./05-P1-recovery-orchestration-hardening.md) | 7 |
| 06 | P1 | [Guarantee complete, ordered offline catch-up across relay lifecycle](./06-P1-relay-inbox-catchup-integrity.md) | 9 |
| 07 | P1 | [Make membership/role/metadata converge consistently](./07-P1-membership-convergence-consistency.md) | 5 |
| 08 | P1 | [Make joining a group clean, current, and manageable](./08-P1-invite-join-reliability.md) | 6 |
| 09 | P1 | [Bound media size and give media an honest terminal state](./09-P1-media-bounded-and-honest.md) | 6 |
| 10 | P2 | [Make reactions as reliable as messages](./10-P2-reaction-reliability.md) | 3 |
| 11 | P2 | [Close the in-conversation feedback, i18n, and performance seams](./11-P2-in-conversation-feedback-and-i18n-polish.md) | 11 |
| 12 | P2 | [Make multi-device real or stop claiming it](./12-P2-multi-device-honesty.md) | 6 |

- [Findings Appendix (all 80 verified findings + subsystem strengths)](./appendix-findings.md)

---

## Methodology

- **Review (12 agents):** one `code-reviewer` per subsystem, each reading the real Dart/Go code and grounding every finding in `file:line` evidence. Seeded with the existing C4 flow docs and the two known-bug analyses (doc 102 image-retry duplicate delivery; doc 104 scenario-7 invite stale metadata).
- **Verify (12 agents):** an independent adversarial verifier per subsystem re-read the cited code and tried to refute each finding (confirmed / partially-confirmed / already-mitigated / false-positive / needs-investigation). 6 findings were dropped as false-positives.
- **Synthesize (1 agent):** clustered the 80 verified findings into 12 prioritized themes, scored each subsystem, and drafted the executive summary + quick wins.
- **Write (12 agents):** one writer per theme produced the detailed proposal docs.

> Findings are claims grounded in code at review time (commit on branch `121-improvements`, 2026-06-02). Verify `file:line` references before implementing — the codebase is under active change.
