# Closure Reference: Reliable Announcements

**Purpose:** define what "reliable enough" means for current announcement text/media/voice messaging in this repo, while keeping announcement-specific auth rules separate from general group-discussion semantics.

---

## Architecture Note

Announcements are a specialization of the group system:

- `GroupType.announcement`
- admin-only writers
- all members can read
- readers can react
- shared group send/retry/recovery machinery underneath

So announcement reliability closure is **not** a separate transport architecture. It is the combination of:

1. shared group-message durability/recovery remaining sound,
2. announcement writer enforcement remaining correct,
3. reader/read-only behavior remaining intact.

---

## Closure Statement

The current announcement system should be treated as **reliably closed for core messaging** when all of these remain true:

1. admins can reliably send text/media/voice announcements through the shared group pipeline,
2. non-admins cannot send announcements through the use case, UI, or repo-local Go publish path,
3. members can still receive, read, and react to announcements,
4. shared group retry/recovery changes do not silently break announcement behavior,
5. statuses remain honest group-style transport statuses rather than fake per-reader delivery proof.

This is the closure bar for current announcements.

---

## What Current Closure Already Includes

### 1. Shared durable send/recovery path

- Announcements ride the same durable group send/retry/recovery machinery as current group discussions.
- Session 28 already revalidated that the shared group reliability work did not regress announcement send, receive, recovery, or read-only behavior.

### 2. Writer enforcement at multiple layers

Current closure already includes all three enforcement seams:

1. use case enforcement in `send_group_message_use_case.dart`
2. UI/read-only compose enforcement in `group_conversation_screen.dart` and `group_conversation_wired.dart`
3. repo-local Go enforcement in `go-mknoon/node/pubsub.go`, with `bridge.go` delegating `GroupPublish()` into that path

### 3. Reader safety and reactions

- readers stay read-only for sending
- readers can still react
- existing integration/resume tests already cover meaningful receive/recovery behavior

### 4. Happy-path proof

`announcement_happy_path_test.dart` gives the repo a concise announcement create → send → read-only/reader → react proof without needing a separate announcement roadmap.

---

## Accepted Architectural Differences From 1:1 And Group Discussions

These differences are real and do **not** automatically mean announcements are unreliable:

1. announcements are admin-only writes, not open writer chat threads,
2. announcement delivery remains group-style and receipt-less, not 1:1 ACK-backed,
3. announcement readers are intentionally read-only for message send,
4. announcement reliability should be validated mainly as a focused acceptance layer on top of shared group reliability, not as a separate large implementation program.

---

## What Is Not Required For Announcement Reliability Closure

These are intentionally **not** part of the current closure bar:

- scheduled announcements
- analytics / engagement reporting
- per-reader read receipts
- announcement pinning
- admin post-send editing/deletion
- categories/tags
- a separate announcement-only retry subsystem
- extra bridge-package publish tests unless the package boundary itself becomes the risk area

Those are product or evidence niceties, not prerequisites for trusting the current announcement pipeline.

---

## When To Reopen Announcement Reliability

Reopen this area only if one of these happens:

1. shared group send/retry/recovery changes regress announcement behavior,
2. non-admins can send through any current enforcement seam,
3. announcement happy-path acceptance breaks,
4. role persistence or role-consistency changes create auth drift,
5. repo-local Go announcement enforcement changes in a way that needs new package-boundary proof.

Do **not** create a new announcement reliability program just because the feature lacks scheduling, analytics, or read receipts.

---

## Required Regression Contract

When touching announcement auth/send/recovery behavior:

1. add the direct regression first for the exact seam,
2. run the relevant direct suites, especially announcement happy-path and admin/read-only enforcement tests,
3. run `./scripts/run_test_gates.sh groups`,
4. run `./scripts/run_test_gates.sh baseline` when Flutter production code changes,
5. run `./scripts/run_test_gates.sh transport` only when lifecycle/startup/resume/recovery wiring changes,
6. run `go test ./node && go test ./bridge` from `go-mknoon/` if repo-local Go announcement enforcement or bridge publish code changes.

Use `Test-Flight-Improv/test-gate-definitions.md` as the execution source of truth and `Test-Flight-Improv/14-regression-test-strategy.md` as the policy/rationale reference.

---

## Bottom Line

The current repo already supports **trustworthy announcement text/media/voice messaging** for the current product shape:

- admins can send,
- readers can read/react,
- non-admin writer attempts are blocked,
- and shared group recovery changes have already been revalidated against announcements.

Future work should preserve those guarantees and avoid turning announcement maintenance into a separate open-ended reliability backlog unless a real regression proves it is needed.
