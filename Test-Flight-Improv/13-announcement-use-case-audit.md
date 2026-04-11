# Use Case Audit: Announcements

**Status:** Core announcement behavior is solid across Flutter and repo-local Go enforcement, and Session 28 revalidated that the shared group reliability work did not regress announcement behavior
**QA Group Type:** Placeholder only (filtered out of UI, cannot currently be created)

---

## Implementation Overview

Announcements are a `GroupType.announcement` where only admins can send, while all members can read and react. Enforcement is visible at these layers:
1. **Use Case:** `sendGroupMessage()` rejects non-admin writers
2. **UI:** current group conversation UI hides/locks compose for non-admins
3. **Go / bridge side:** repo-local proof now exists in `go-mknoon/node/pubsub.go`, and `go-mknoon/bridge/bridge.go` delegates `GroupPublish()` into that enforcement path

---

## Announcement Creation & Configuration

| # | Use Case | File | Test | Quality | Notes |
|---|----------|------|------|---------|-------|
| 1 | GroupType enum (`chat` / `announcement` / `qa`) | `group_model.dart` | YES | Good | Serialization tested |
| 2 | Create announcement group | `create_group_use_case.dart` | YES | Good | Session 13 added direct announcement create/use-case, repository round-trip, create-with-members, and picker-route regressions |
| 3 | Type-specific create route into picker UI | `orbit_wired.dart`, `create_group_picker_wired.dart` | YES | Good | Orbit routes `GroupType.announcement` into the picker flow; QA remains filtered out |
| 4 | Group type badge display | `group_type_badge.dart` | YES | Good | Announcement badge rendering covered |

---

## Admin-Only Message Sending (Enforcement)

| # | Use Case | File | Test | Quality | Notes |
|---|----------|------|------|---------|-------|
| 5 | Authorization check in send use case | `send_group_message_use_case.dart` | YES | Good | Non-admin send blocked |
| 6 | Bridge/server-side permission enforcement | `go-mknoon/node/pubsub.go`, `go-mknoon/bridge/bridge.go` | YES | Good | `PublishGroupMessage()` checks `isAllowedWriter(...)` before publish, the topic validator rejects unauthorized announcement `group_message` envelopes, direct tests exist in `pubsub_test.go` / `rendezvous_test.go`, and `go test ./node` plus `go test ./bridge` are green; bridge publish tests are still mostly chat-shaped |
| 7 | UI compose hidden / read-only for non-admin | `group_conversation_screen.dart`, `group_conversation_wired.dart` | YES | Good | Non-admins cannot use normal compose path |
| 8 | `canWrite` logic for announcement groups | `group_conversation_wired.dart` | YES | Good | Writer gating is covered in Flutter tests |

---

## Message Receiving & Reactions

| # | Use Case | File | Test | Quality | Notes |
|---|----------|------|------|---------|-------|
| 9 | Members receive announcement messages | group listener / resume recovery flow | YES | Good | Covered across current integration/resume tests |
| 10 | Members can react | `send_group_reaction_use_case.dart` | YES | Good | Non-admin reaction path explicitly covered |
| 11 | Read-only UI state for readers | group conversation UI | YES | Good | Compose is hidden / read-only behavior covered |

---

## Role Management

| # | Use Case | File | Test | Quality | Notes |
|---|----------|------|------|---------|-------|
| 12 | Role persistence (`admin` / `member`) | groups schema + model paths | YES | Good | Valid role values covered |
| 13 | `GroupMember` model | `group_member.dart` | YES | Good | Earlier “no tests” claim was stale |

---

## Test Coverage Summary

| Category | Coverage | Notes |
|----------|----------|-------|
| Authorization (use case) | **Good** | Non-admin send blocked and tested |
| Authorization (bridge/Go) | **Good** | Repo-local proof exists in `go-mknoon/node`; Session 14 verified `go test ./node` and `go test ./bridge` are green |
| UI enforcement | **Good** | Read-only / hidden compose behavior covered |
| Reactions allowed | **Good** | Explicitly covered for non-admin readers |
| Resume/read/media behavior | **Good** | Existing integration/resume tests cover meaningful announcement flows |
| Single concise create → send → read → react flow | **Good** | `announcement_happy_path_test.dart` plus Session 28 acceptance evidence keep this flow easy to verify |

---

## Critical Gaps

1. **Bridge-package publish coverage is thinner than node-side proof**
   - `bridge.go` delegates into the node enforcement path and `go test ./bridge` is green, but bridge publish tests are still mostly chat-shaped rather than announcement-specific
2. **Role consistency across `groups.my_role` and `group_members.role` is not directly asserted**
   - Lower risk, but worth a targeted check if schema work resumes

---

## QA Group Type Status

`GroupType.qa` still exists but remains **intentionally disabled**:
- Filtered out of current create-group UI
- Cannot be created via normal product flow
- Has badge/model support but no dedicated product flow

---

## Missing Announcement Features

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| 1 | Scheduled announcements | Medium | Post at future time |
| 2 | Read receipts / engagement tracking | Medium | Aggregate read/engagement state |
| 3 | Announcement pinning | Low | Pin important messages |
| 4 | Admin editing after send | Medium | Post-send corrections |
| 5 | Admin deletion of announcements | Medium | Remove/tombstone after send |
| 6 | Categories/tags | Low | Optional classification/filtering |
| 7 | Member mute | Low | Silent notifications |
| 8 | Announcement analytics | Low | View/reaction reporting |

---

## Recommended Tests to Add

| # | Test | Priority | What it verifies |
|---|------|----------|-----------------|
| 1 | **Optional bridge-package announcement `GroupPublish()` regression** | LOW | Adds package-boundary proof on top of the already-sufficient node-side enforcement evidence |
| 2 | **Role consistency across group/member storage** | LOW | Guards against schema drift |

---

## Verdict

**Core announcement functionality is solid across the Flutter tree and the repo-local Go layer.** Session 13 closed the announcement-specific create-group gap, Session 14 verified that Go-side writer enforcement is directly present in `go-mknoon/node/pubsub.go`, and Session 28 revalidated that the shared group reliability changes did not regress announcement auth/send/recovery/read-only behavior. The remaining evidence caveat is narrower: bridge publish tests are still mostly chat-shaped, even though `bridge.go` delegates into the already-verified node enforcement path.
