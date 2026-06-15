# Group messaging — 3-device repro guide (for log capture)

> **Goal.** Drive the field-bug scenarios on 3 real devices/simulators so the `[FLOW]` logs tell us which group bugs are **actually open** vs already fixed on this branch. You run `flutter run`; the app emits structured `[FLOW] {…json…}` lines for free — you just perform the steps and keep the 3 logs.

## Setup

**Roles:** **alice** = creator/admin · **bob** = member (will be promoted then demoted) · **charlie** = 3rd member / late-ish joiner.

**Launch + capture (one terminal per device):**
```bash
# Find device ids
flutter devices

# Simulators (debug is fine):
flutter run -d <alice_device_id> 2>&1 | tee alice.log
flutter run -d <bob_device_id>   2>&1 | tee bob.log
flutter run -d <charlie_device_id> 2>&1 | tee charlie.log
```
- **iPhone 13 physical device:** use `--profile` (debug JIT crashes on iOS 26.5 — see project memory). Simulators/Pixel: debug is fine.
- **Capture the identity line at startup** on each device (its `peerId`) so I can map logs→actors and trace recipient sets. Grep after: `grep -m1 -iE 'IDENTITY|peerId|MY_PEER' alice.log`.
- **Between steps, drop a marker** so I can line up the timeline: send yourself a note, or just record wall-clock (`date`) when you start each step. Optional but very helpful.
- Start each pair as **friends** first (the app requires contact before group invite): alice↔bob, then introduce charlie so alice↔charlie and bob↔charlie are friends, as the steps require.

**Reading the logs.** Every event is a line like `[FLOW] {"event":"GROUP_…","details":{…}}`. Grep by event name or `groupId`/`messageId`:
```bash
grep '"event":"GROUP_' bob.log | grep -iE 'METADATA|MEMBER|ROLE|DISSOLV|UNAUTH|REJECT|AUDIT'
```

---

## The step script (do these in order; note the step # in each log if you can)

### Phase 1 — Create + first member (baseline)
1. **alice** creates group **"test"**, adds **bob**.
2. **bob** accepts the invite; both send a message; confirm both see each other's messages.

**Look for** — alice: group create + invite-send; bob: invite accept → `GROUP_MESSAGE_LISTENER_MEMBER_JOINED`; both: `GROUP_SEND_MSG_TIMING` (sender) + `GROUP_HANDLE_INCOMING_MSG_BEGIN` (receiver). *Pass = both directions deliver.*

### Phase 2 — Metadata edit (S1-bug1 / S3-bug1: name+desc convergence)
3. **alice** → Group Info → Edit details → name **"test me"**, description **"do you see me?"** → Save.

**Look on bob.log:**
- ✅ **PASS:** `GROUP_MESSAGE_LISTENER_GROUP_METADATA_UPDATED` **and** bob's title/desc actually change.
- 🔴 **BUG:** any of `GROUP_MESSAGE_LISTENER_SIGNED_AUDIT_REJECTED` (look at the `reason` — `device_mismatch`/`transport_mismatch`), `GROUP_MESSAGE_LISTENER_METADATA_SIGNATURE_INVALID`, `GROUP_MESSAGE_LISTENER_STALE_METADATA_EVENT_IGNORED`, `GROUP_MESSAGE_LISTENER_STALE_CONFIG_METADATA_FIELDS_IGNORED`, `GROUP_MESSAGE_LISTENER_METADATA_STATE_HASH_MISMATCH` — **or no metadata event at all** (delivery never reached bob).

### Phase 3 — Photo change (S1-bug4 / S2-bug1: photo convergence)
4. **alice** changes the group photo → Save.

**Look on bob.log:** `GROUP_MESSAGE_LISTENER_GROUP_METADATA_UPDATED` (text part) **then** an avatar download (`GROUP_MESSAGE_LISTENER_METADATA_EVENT_RETRYING_AVATAR_DOWNLOAD` / avatar-storage download events). *🔴 BUG = name/desc updated but photo stays as initials (blob fetch failed or never started).*

### Phase 4 — Promote (sets up S1-bug2 / S5)
5. **alice** promotes **bob** to admin.

**Look on bob.log:** `GROUP_MESSAGE_LISTENER_MEMBER_ROLE_UPDATED` → bob's Group Info should now show admin controls (edit/add/remove/dissolve). *🔴 BUG = bob's UI still has no admin controls (role event dropped / `UNAUTHORIZED_MEMBERSHIP_EVENT`).*

### Phase 5 — Add 3rd member (S2-bug1: late-member photo)
6. Make **charlie** a friend of alice (and bob). **alice** (or bob, now admin) adds **charlie**; **charlie** accepts.

**Look on charlie.log:** invite accept → `MEMBER_JOINED`, then charlie's Group Info shows **"test me" / "do you see me?" / the photo**. *🔴 BUG = charlie sees name+desc but NOT the photo, or sees the STALE old name (S7-bug3 class).*

### Phase 6 — Fanout from each sender (S1-bug3 / S2-bug2 / S3-bug2: subset delivery)
7. **alice** sends a message → confirm **bob + charlie** receive.
8. **bob** sends a message → confirm **alice + charlie** receive.
9. **charlie** sends a message → confirm **alice + bob** receive. ← **the classic bug.**

**For each send, on the SENDER log** grab the `GROUP_SEND_MSG_TIMING` line and note: `expectedRecipientCount`, `topicPeers`, `liveFanoutState`, `inboxStored`, `status`.
**On each RECEIVER log** find `GROUP_HANDLE_INCOMING_MSG_BEGIN` with the same `groupId` (and ideally the messageId).
- 🔴 **BUG (subset):** a receiver has **no** incoming line for that message. Cross-check the sender's `expectedRecipientCount` (was the missing member even *expected*? → roster/eligibility bug) and `topicPeers`/`liveFanoutState` (was it live or relay-only?).
- Also watch any receiver for `GROUP_RECEIVED_MESSAGE_KEY_EPOCH_AHEAD_OF_LOCAL` (epoch skew) or decrypt placeholders.

### Phase 7 — Demote + permission leak (S5-bug1/2/3)
10. **alice** demotes **bob** (Remove Admin).
11. **bob** tries to edit name/description.
12. **bob** tries to add a new member (a friend of bob's, e.g. a 4th identity or charlie's friend).

**Look:**
- bob.log: `GROUP_MESSAGE_LISTENER_MEMBER_ROLE_UPDATED` (bob→writer) — did bob **apply** the demotion? *🔴 If the demotion event was dropped on bob (`UNAUTHORIZED_MEMBERSHIP_EVENT` / `SIGNED_AUDIT_REJECTED` / never arrived), bob still thinks he's admin → can still edit/add = S5-bug2/bug3.*
- All logs: was the demotion **reported** (a "removed admin" timeline card)? *🔴 S5-bug1 = not reported.*
- If bob's edit/add **succeeds** and only **some** members apply it → roster divergence (S5-bug2).

### Phase 8 — Recovery / resync UX (S6: "Group recovery is in progress")
13. Background one device for ~30s and reopen it (or kill + relaunch). **Immediately** on reopen, as **alice**, try an admin edit (name or add member).

**Look on that device's log:** `GROUP_REJOIN_TOPICS_BEGIN` … `GROUP_REJOIN_TOPICS_DONE` (the resync window) and, if you hit it, a `*_RECOVERY_PENDING` event / the `groupRecoveryPendingError` string. *This reproduces the "try again after resync completes" block. Note whether the edit fails then works on retry, and whether add-member shows the generic "Failed to invite members."*

### Phase 9 — Dissolve (terminal convergence)
14. **alice** dissolves the group.

**Look on bob.log + charlie.log:** `GROUP_MESSAGE_LISTENER_GROUP_DISSOLVED` → composer goes read-only ("This group has been dissolved"). *🔴 BUG = bob/charlie still see a live group (dissolve rejected — check for `SIGNED_AUDIT_REJECTED`/`device_mismatch`).*

### (Optional) Phase 10 — Late-joiner stale snapshot (S7) — needs a 4th device
If you have a 4th device **dana**: alice invites dana, **then** alice changes name/desc/photo, **then** dana accepts. *🔴 BUG = dana joins showing the STALE old name/desc/photo + the invite card lingers after accept.*

---

## What to send me

The three logs (`alice.log`, `bob.log`, `charlie.log`) + a note of **which step # was running at roughly what time** (even rough is fine). Optional but ideal: the per-device `peerId` from startup so I can label them.

I'll then produce a per-bug **red/green** verdict (open vs already-fixed-on-branch vs build-skew) by correlating the markers above — and route each confirmed-open bug to its fix.

## Quick grep cheat-sheet
```bash
# metadata convergence on a receiver
grep -E '"event":"GROUP_MESSAGE_LISTENER_(GROUP_METADATA_UPDATED|SIGNED_AUDIT_REJECTED|METADATA_SIGNATURE_INVALID|STALE_METADATA_EVENT_IGNORED|STALE_CONFIG_METADATA_FIELDS_IGNORED)"' bob.log
# membership/role apply vs drop
grep -E '"event":"GROUP_MESSAGE_LISTENER_(MEMBER_ROLE_UPDATED|MEMBER_REMOVED|MEMBERS_ADDED|MEMBER_JOINED|UNAUTHORIZED_MEMBERSHIP_EVENT)"' bob.log
# send fanout truth (sender)
grep '"event":"GROUP_SEND_MSG_TIMING"' charlie.log
# who received a given message (receiver)
grep '"event":"GROUP_HANDLE_INCOMING_MSG_BEGIN"' alice.log
# recovery window
grep -E '"event":"GROUP_REJOIN_TOPICS_(BEGIN|DONE)"|RECOVERY_PENDING' alice.log
# dissolve apply
grep '"event":"GROUP_MESSAGE_LISTENER_GROUP_DISSOLVED"' bob.log
```
