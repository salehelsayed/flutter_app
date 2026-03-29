# 25 - Swipe-to-Delete Introductions in Orbit

**New Feature**

---

## 1. Problem Statement

When a user navigates to the **Intros** tab under **Orbit**, there is no way to
delete (dismiss) an introduction. The user can only accept or pass on pending
intros. Once an intro has been acted on (accepted, passed, or expired), it
remains in the database indefinitely with no user-facing removal mechanism.

**What is missing:**

- No swipe gesture on intro rows (unlike friend rows, which already support
  swipe-to-reveal actions via `SwipeableFriendRow`).
- No delete button or callback wired into the intro UI or state management.
- No way for a user to clear an intro from their list so they can potentially
  receive the same introduction again in the future.

**Who is affected:** All users who receive introductions. This is especially
relevant for users who want to reconsider a previously passed intro or clean up
stale entries from their Intros tab.

**Current workaround:** None in the production UI. A debug-only deletion
mechanism exists in the settings screen (`settings_introduction_debug_card.dart`
/ `settings_wired.dart` line 260), proving the underlying delete infrastructure
works.

---

## 2. Impact Analysis

| Dimension | Assessment |
|-----------|-----------|
| Severity | Moderate — does not block core usage but limits user control over their intro list |
| Frequency | Every user with introductions; intros accumulate over time with no cleanup |
| User consequence | Stale/unwanted intros clutter the list; users cannot re-receive a deleted intro pair |
| Workaround | None in production UI |
| Platform scope | iOS and Android (Flutter) |

The feature directly improves the user's ability to manage their social graph
onboarding. Without it, the Intros tab becomes a growing, unmanageable list.

---

## 3. Current State

### 3.1 UI Layer

| File | Purpose | Key Lines |
|------|---------|-----------|
| `lib/features/orbit/presentation/screens/orbit_screen.dart` | Renders intro rows in the Intros tab | Lines 497–607: `_buildIntroSliver`, `_buildIntroEntry` |
| `lib/features/introduction/presentation/widgets/intro_row.dart` | Individual intro row widget | Lines 1–30: accepts `onAccept`, `onPass` callbacks; no `onDelete` |
| `lib/features/orbit/presentation/widgets/swipeable_friend_row.dart` | Existing swipe-to-reveal pattern for friends | Lines 1–60: `onDelete`, `onArchive`, `onBlock` callbacks, drag/snap mechanics |
| `lib/features/orbit/presentation/widgets/swipe_action_buttons.dart` | Reusable action buttons (including `DeleteActionButton`) | Lines 117–172: red gradient delete button with icon |
| `lib/features/orbit/presentation/widgets/confirmation_dialog.dart` | Reusable confirmation dialog for destructive actions | Lines 8–24: `showConfirmationDialog()` returns `Future<bool>` |

**Current intro row rendering** (orbit_screen.dart lines 585–603): Each intro is
rendered as a plain `IntroRow` widget inside a `Padding`. There is no swipeable
wrapper. The only interactive elements are Accept/Pass buttons (for pending
intros) or a Send Message button (for mutually accepted intros).

**Existing swipe pattern** (swipeable_friend_row.dart): Friend rows are wrapped
in `SwipeableFriendRow` which provides left-swipe to reveal action buttons.
Swipe mechanics: 8px drag locks direction, 50% threshold to snap open, 300ms
snap animation. A `ValueNotifier<Key?>` (`openRowNotifier`) ensures only one row
is open at a time.

### 3.2 State Management / Wiring

| File | Purpose | Key Lines |
|------|---------|-----------|
| `lib/features/orbit/presentation/screens/orbit_wired.dart` | Stateful wiring for Orbit business logic | Lines 657–696: `_onAcceptIntro`, `_onPassIntro` handlers |
| `lib/features/orbit/presentation/screens/orbit_screen.dart` | `OrbitIntrosViewData` projection | Lines 25–43: has `onAccept`, `onPass`, `onSendMessage`; **no `onDelete`** |

**Current callbacks in `OrbitIntrosViewData`:**
- `onAccept(String introductionId)` — accepts intro via use case
- `onPass(String introductionId)` — passes intro via use case
- `onSendMessage(String peerId)` — navigates to conversation (mutual acceptance)

**Missing:** No `onDelete` callback exists anywhere in the intro data flow.

### 3.3 Domain / Repository Layer

| File | Purpose | Key Lines |
|------|---------|-----------|
| `lib/features/introduction/domain/repositories/introduction_repository.dart` | Repository interface | Line 16: `deleteIntroduction(String id)` — **interface exists** |
| `lib/features/introduction/domain/repositories/introduction_repository_impl.dart` | Repository implementation | Lines 84–86: calls `dbDeleteIntroduction(id)` — **implementation exists** |
| `lib/features/introduction/domain/models/introduction_model.dart` | Introduction data model | Status enums: `pending`, `accepted`, `passed` (individual); `pending`, `mutualAccepted`, `passed`, `expired`, `alreadyConnected` (overall) |

**Key constraint:** There is no "deleted" status. Deletion is a hard delete
(`DELETE FROM introductions WHERE id = ?`), which means the intro record is
fully removed from the local database.

### 3.4 Database Layer

| File | Purpose | Key Lines |
|------|---------|-----------|
| `lib/core/database/helpers/introductions_db_helpers.dart` | DB helper functions | Lines 37–64: `dbDeleteIntroduction()` with flow events |
| `lib/core/database/migrations/019_introductions_table.dart` | Schema definition | Lines 6–25: `introductions` table with status constraints |

**Delete helper** (introductions_db_helpers.dart lines 38–64): Fully
implemented with flow events (`INTRODUCTIONS_DB_DELETE_START`,
`INTRODUCTIONS_DB_DELETE_SUCCESS`, `INTRODUCTIONS_DB_DELETE_ERROR`).

**Loading query** (introductions_db_helpers.dart ~line 406): Only loads intros
with `status IN ('pending', 'already_connected')`, so a hard-deleted record will
not reappear in the UI.

### 3.5 Use Cases

| File | Purpose |
|------|---------|
| `lib/features/introduction/application/accept_introduction_use_case.dart` | Accept pattern: update status, send P2P notification |
| `lib/features/introduction/application/pass_introduction_use_case.dart` | Pass pattern: update status, send P2P notification |
| `lib/features/introduction/application/expire_old_introductions_use_case.dart` | Marks intros older than 30 days as expired |
| `lib/features/introduction/application/load_introductions_use_case.dart` | Loads pending intros, groups by introducer |

**No delete use case exists.** The accept/pass use cases send P2P notifications
to the introducer and other party. Deletion is a local-only operation (no P2P
sync needed) since it simply removes the record so the user can be
re-introduced.

### 3.6 Re-introduction Behavior

When an intro is hard-deleted from the local DB, the introduction matching logic
on the introducer's side has no record of the previous introduction for this
pair. If the introducer sends the same introduction again, it will be treated as
a new introduction and appear in the recipient's Intros tab. This is the desired
behavior per the requirement ("user can receive the same intro again").

---

## 4. Scope Clarification

| Area | Status | Notes |
|------|--------|-------|
| Swipe-to-delete gesture on intro rows | **In scope** | New swipeable wrapper for intro rows |
| Delete button in swipe action area | **In scope** | Reuse existing `DeleteActionButton` pattern |
| Confirmation dialog before delete | **In scope** | Reuse existing `showConfirmationDialog` |
| `onDelete` callback in `OrbitIntrosViewData` | **In scope** | New callback field |
| Delete handler in `orbit_wired.dart` | **In scope** | New `_onDeleteIntro()` method |
| Hard delete from local DB via repository | **In scope** | Already implemented; just needs wiring |
| UI refresh after deletion | **In scope** | Call `_loadIntroductions()` after delete |
| P2P notification of deletion to other parties | **Out of scope** | Deletion is local-only by design |
| Soft-delete / "deleted" status in DB schema | **Out of scope** | Hard delete is sufficient; no migration needed |
| Batch delete (delete all intros at once) | **Out of scope** | Single-intro delete only |
| Undo/restore after deletion | **Out of scope** | Hard delete is final |
| Changes to intro expiry logic | **Out of scope** | Expiry remains unchanged |
| Changes to accept/pass behavior | **Unchanged** | Existing callbacks remain as-is |
| Changes to friend swipe behavior | **Unchanged** | Existing `SwipeableFriendRow` is not modified |

---

## 5. Test Cases

### Group A: Swipe Gesture Mechanics

**TC-25-A01** — Swipe left on a pending intro row reveals a delete button
Given the user is on the Intros tab with at least one pending introduction,
when the user swipes left on an intro row by more than 50% of the action area width,
then the row snaps open to reveal a delete action button with a red icon.

**TC-25-A02** — Swipe right (or insufficient left swipe) snaps the row closed
Given an intro row is in its default (closed) position,
when the user swipes left by less than 50% of the action area width and releases,
then the row snaps back to the closed position with no action buttons visible.

**TC-25-A03** — Only one intro row can be open at a time
Given the user has swiped open intro row A to reveal the delete button,
when the user begins swiping on intro row B,
then row A automatically snaps closed before row B begins responding to the swipe.

**TC-25-A04** — Swipe works on intros in all statuses (pending, accepted/waiting, passed, expired)
Given the user has intros in different states (pending action, waiting for other party, passed, expired),
when the user swipes left on each intro row,
then all intro rows reveal the delete button regardless of their current status.

**TC-25-A05** — Vertical scroll does not trigger horizontal swipe
Given the user is scrolling vertically through a list of intros,
when the initial drag direction is vertical (within the direction-lock threshold),
then no horizontal swipe action is triggered and the list scrolls normally.

### Group B: Delete Action

**TC-25-B01** — Tapping delete button shows a confirmation dialog
Given the user has swiped an intro row open to reveal the delete button,
when the user taps the delete button,
then a confirmation dialog appears asking the user to confirm the deletion.

**TC-25-B02** — Confirming deletion removes the intro from the list
Given the confirmation dialog is showing for a specific intro,
when the user taps the confirm/delete button in the dialog,
then the intro row is removed from the Intros tab list immediately.

**TC-25-B03** — Canceling the confirmation dialog keeps the intro
Given the confirmation dialog is showing for a specific intro,
when the user taps Cancel,
then the dialog closes, the intro remains in the list, and the swipe row snaps closed.

**TC-25-B04** — Deleting the last intro in a group removes the group header
Given an introducer group contains exactly one intro,
when the user deletes that intro,
then both the intro row and the introducer group header are removed from the UI.

**TC-25-B05** — Deleting the last intro overall shows the empty state
Given the Intros tab has exactly one introduction remaining,
when the user deletes that intro,
then the "No introductions yet" empty state message appears.

**TC-25-B06** — Intro count badge updates after deletion
Given the Intros tab shows a pending count (e.g., badge or counter),
when a pending intro is deleted,
then the pending count decreases by one.

### Group C: Database and Re-introduction

**TC-25-C01** — Deleted intro is removed from the local database
Given the user confirms deletion of an intro with ID X,
when the deletion completes,
then querying the `introductions` table for ID X returns no rows.

**TC-25-C02** — Re-introduction after deletion creates a new entry
Given the user previously deleted an intro between themselves and user B (introduced by user C),
when user C sends a new introduction for the same pair (user A ↔ user B),
then a new intro record appears in the Intros tab with a new ID and pending status.

**TC-25-C03** — Deleting an intro does not affect other intros from the same introducer
Given an introducer has sent 3 intros to the user,
when the user deletes one of those intros,
then the other 2 intros from the same introducer remain visible and unchanged.

**TC-25-C04** — Deleting an intro does not send a P2P message
Given the user deletes an intro,
when the deletion completes,
then no P2P payload or network request is sent to the introducer or the other party.

### Group D: Status-Specific Deletion

**TC-25-D01** — Delete a pending intro (not yet acted on)
Given an intro with overall status "pending" and the user has not accepted or passed,
when the user deletes it,
then it is removed from the DB and the user can be re-introduced to the same person.

**TC-25-D02** — Delete a "waiting" intro (user accepted, other party hasn't responded)
Given an intro where the user has accepted but the other party has not yet responded,
when the user deletes it,
then it is removed from the DB. The other party's copy is unaffected (no P2P sync).

**TC-25-D03** — Delete a passed intro
Given an intro that the user previously passed on,
when the user deletes it,
then it is removed from the DB and the user can be re-introduced to the same person.

**TC-25-D04** — Delete a mutually accepted intro
Given an intro with overall status "mutualAccepted",
when the user deletes it,
then it is removed from the Intros tab. The existing friendship/contact (if any) is not affected.

### Group E: Edge Cases and Error Handling

**TC-25-E01** — Delete while offline
Given the device has no network connectivity,
when the user deletes an intro,
then the deletion succeeds (it is a local-only DB operation) and the intro is removed from the list.

**TC-25-E02** — Delete during a concurrent intro status change
Given another party accepts/passes the same intro at the moment the user taps delete,
when the status-changed stream fires after the delete completes,
then the intro reload does not crash or re-insert the deleted record (record is gone from DB).

**TC-25-E03** — Rapid sequential deletes
Given the user deletes intro A, then immediately swipes and deletes intro B,
when both deletions complete,
then both intros are removed from the DB and the UI reflects the correct remaining list.

**TC-25-E04** — DB error during deletion
Given a database error occurs during the DELETE operation,
when the deletion fails,
then the intro remains in the list, no data is lost, and the user can retry.

### Group F: Regression — Existing Behavior Must Not Break

**TC-25-F01** — Accept button still works on pending intros
Given a pending intro with the swipe-to-delete wrapper applied,
when the user taps the Accept button (without swiping),
then the accept flow executes normally (status update, P2P notification, reload).

**TC-25-F02** — Pass button still works on pending intros
Given a pending intro with the swipe-to-delete wrapper applied,
when the user taps the Pass button (without swiping),
then the pass flow executes normally (status update, P2P notification, reload).

**TC-25-F03** — Send Message button still works on mutually accepted intros
Given a mutually accepted intro,
when the user taps the Send Message button,
then navigation to the conversation occurs normally.

**TC-25-F04** — Friend row swipe behavior is unchanged
Given the user is on the Friends tab (not Intros),
when the user swipes a friend row,
then the existing archive/block/delete actions appear as before with no regressions.

**TC-25-F05** — Intro received stream still triggers UI refresh
Given the user is on the Intros tab,
when a new intro arrives via the `introReceivedStream`,
then the new intro appears in the list without requiring manual refresh.
