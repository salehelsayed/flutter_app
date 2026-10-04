# Handover: GE-009 pending re-add recipients, remaining gaps

Written 2026-10-04. Branch `wave3-baseline-20260930` (HEAD `58db8f9bb`).
Read-only review so far. No code was changed and nothing was run.

## Current state

- The bug: the inviter (Alice) left a pending re-added member (Charlie) out of
  her recipients, while other members (Bob) included him. Reason: only the
  inviting device stores invite-attempt rows, and the send path filtered on them.
- Fixed on this branch in `24ce99cd2`, by the user decision of 2026-10-03:
  "include everywhere" (`docs/testing/production-bootstrap-migration-crosswalk.md:2272-2285`).
  `_loadGroupSendMembership` (`lib/features/groups/application/send_group_message_use_case.dart:372-400`)
  and `send_group_reaction_use_case.dart` now include every deliverable roster member.
- `main` / `origin/main` (`f574c0f4a`) still has the bug. The fix is local only.
- The legacy oracle `tool/sims/production_group_ge009_criteria.dart` is unchanged
  (last changed `d8121493c`). Keep it that way.

## Gaps to close

1. **No device proof for GE-009 after the fix.** The last recorded run is the
   failing `T200850Z`. Run check `production.group_catalog.ge009`
   (`tool/sims/critical_features.json:4943`). Also run one negative probe: change
   one expectation, confirm it fails at that step, then restore it.
   Confirm on all three devices:
   - Alice's durable copy lists Charlie in `recipientPeerIds`.
   - Charlie gets each post-re-add message exactly once, both live and from the relay inbox.
   - No `GROUP_DRAIN_OFFLINE_INBOX_REPLAY_RECIPIENT_SKIPPED` in Charlie's catch-up.
   - Bob's behaviour is unchanged.
2. **O10 wording is out of date.** `docs/testing/beta-test-coverage.md:82` says
   "Not delivered, by design". Now the inviter's copy does reach the device. The
   relay stores it and sends a push, and the receiving app hides it. First check
   in code that the receive side really hides it: Android drops it when there is
   no local group state, and iOS cleans it before display. Then re-test O10 with
   a brand-new invitee and reword the row. A re-added member who still has the
   group stored locally can now see messages sent before he accepts. Record that
   as intended.
3. **Record the results** in the crosswalk (new dated section) and in
   `beta-test-coverage.md`. Update `selection.json` mappings only if a test is added.

## Do not fix without a user decision

- **GE-006:** a member offline through both his removal and his re-add loses the
  re-add invitation (`handle_incoming_group_invite_use_case.dart:620-640`, `:875-890`).
- **ML-008:** a removal inside the 10-minute key grace window does not rotate the
  key (`go-mknoon/node/config.go:57`, `go-mknoon/bridge/bridge.go:3049-3053`).

Reproduce and report only. Both change membership or key rules.

## Devices

Three devices, one per role (alice, bob, charlie):
- USB Pixel 6 `21071FDF600CSC`
- `emulator-5554` (Pixel_7)
- `emulator-5556` (Pixel_6a)

O10 was first checked on an iPhone. Use an iPhone as Charlie to re-check it
on the same platform.

- Only one automation tool may drive each device. appium-qa also uses
  `emulator-5556` and can reinstall the app on it. Check logcat before you start.
- The Pixel has a PIN lock. Steps that tap on its screen need the user to unlock it.
- Keep emulator windows visible. macOS slows down hidden emulators.

## Commands (from the Wave 3 recipe)

- Host tests: `host-run bash docker-ws/flutter_sdk.sh test <files>`
- Device run: `host-run bash docker-ws/run_wave3_group_campaigns.sh <check-id>`
- Device config: `.codex-test-logs/production-bootstrap-migration-20260930/wave3-device-config.json`

## Rules

- Do not push, merge, deploy or change the relay without explicit approval.
- Do not weaken assertions or change the legacy oracles.
- Do not stash `/workspace`. Other sessions edit it.

## Status (2026-10-04, picked up in the Wave 3 list)

- **Gap 1:** GE-009 passed on the three devices after the fix (2026-10-03,
  unchanged legacy oracle; Alice's durable copy lists Charlie). Its negative
  probe (Charlie accepts at once, no partition) failed as intended. Still to
  record explicitly: no `GROUP_DRAIN_OFFLINE_INBOX_REPLAY_RECIPIENT_SKIPPED` on
  Charlie, and live versus inbox receipt. The catalog watch will record those
  events and GE-009 will be re-run once the current device queue finishes.
- **Gap 2 (O10):** the Android form already has device proof: DE-007 (Alice
  sends before Bob and Charlie accept; each receives it once, from the relay
  inbox, after accepting) passed 2026-10-03. Receive-side hiding before accept
  is being checked in code; the iPhone re-check (brand-new invitee) is open.
- **Gap 3:** open; written once gaps 1 and 2 close.
- **GE-006 and ML-008:** the user decided both on 2026-10-04. GE-006 is fixed
  (an invite ahead of the local key is kept; Orbit shows it once the removal
  applies) and passed on devices. ML-008: a removal now rotates even inside the
  grace window unless that would evict a held key replaced less than 10 minutes
  ago (Go, option C), with a once-a-minute retry for that case; its device run
  is in progress. Not committed yet.

### Gap 2 code check (2026-10-04, read-only)

The INV-106 receive-side claim holds:
- Android: the relay's data-only `group_message` push for a group with no local
  row is suppressed (`group_message_local_state_ineligible`,
  `lib/features/push/application/background_message_handler.dart:3697-3712`,
  `:3234-3240`); nothing is shown.
- iOS: the Notification Service Extension cannot resolve the group
  (`ios/NotificationService/NotificationPreviewResolver.swift:1231-1254`) and
  replaces the card with a passive one: "Mknoon" / "Open the app to view
  updates.", no sound, no badge, no preview (`:148-178`).
- In the app nothing is stored before accept: the inbox drain only visits
  local groups (`drain_group_offline_inbox_use_case.dart:162`), so the copy
  waits on the relay; the accept-time drain delivers it once
  (`accept_pending_group_invite_use_case.dart:434`), skipping replays stamped
  before the device's own `joinedAt` (`drain…:652-703`).
- Correction to gap 2 above: a re-added member who still has the group stored
  sees nothing before he accepts (notifications suppressed as `self_removed`,
  drain skipped as `skippedSelfRemoved`); after he accepts he receives the
  messages sent since his re-add (GE-009, GE-006, DE-007 on devices).

Proposed O10 wording (iPhone part still to re-test): "Message sent before the
invite is accepted: delivered once after accept (from the relay inbox). Before
accept, Android shows nothing; the iPhone shows a passive 'Mknoon - Open the
app to view updates.' card."
- Member offline through his removal and re-add (GE-006, invite kept as
  `GROUP_INVITE_STORE_PENDING_AHEAD_OF_LOCAL_MEMBERSHIP`): until his removal
  applies he still lists himself as a member but holds no key for the new
  epoch, so a push cannot be decrypted (`missing_group_decrypt_input`;
  Android `push_decrypt_preview.dart:924-941`, likely no card, catch site not
  traced; iOS `NotificationPreviewResolver.swift:1300-1307`, passive card). No
  readable content before he accepts.

### Gap 1 closed (2026-10-04, run `T133639Z`, PASS)

- Alice's durable copy of `aliceGe009PostReadd` lists Bob and Charlie (2
  recipients, 1 live topic peer at send).
- Charlie holds every proof message exactly once: before the partition Alice's
  and Bob's arrived live; after the re-add `aliceGe009PostReadd` and
  `bobGe009PostReadd` came from the relay inbox. Bob's behaviour is unchanged.
- `GROUP_DRAIN_OFFLINE_INBOX_REPLAY_RECIPIENT_SKIPPED` still fires 3 times on
  Charlie (13:43:32, 13:44:01, 13:48:06), but none of them is a proof message:
  all six arrived. The timing matches Charlie's own acceptance records, which
  the relay returns to their author; the event carries no message id, so this
  is not proven.

### Gaps 2 and 3 closed (2026-10-04)

- **Gap 2:** O10 re-tested with the USB Pixel as admin and the iPhone 13 as a
  brand-new invitee, both on this branch. The message was delivered once after
  accept, from the relay inbox. Before accept the iPhone showed only the invite
  card and the passive "Mknoon / Open the app to view updates." card. The O10
  row in `beta-test-coverage.md` now uses the proposed wording.
- **Gap 3:** recorded in the crosswalk section "2026-10-04 O10 iPhone re-check
  and GE-009 gap closure" and in `beta-test-coverage.md`. No test was added, so
  `selection.json` is unchanged.
