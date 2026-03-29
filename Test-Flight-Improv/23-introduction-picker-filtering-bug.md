# 23 - Introduction Picker Contact Filtering Bug

**Bug**

## Problem Statement

When a user (A) has multiple friends and has previously introduced one friend (D) to another friend (B), the "introduce to your circle" contact picker incorrectly hides contacts that should be available for new introductions.

### Reproduction steps

1. User A has contacts: B, C, and D
2. User A introduces D to B (creates introduction: introducer=A, recipient=B, introduced=D)
3. User B accepts the introduction, but User D never responds
   - Introduction state: recipientStatus=accepted, introducedStatus=pending, overall status=pending
4. User A opens User B's chat screen and taps "introduce to your circle"
   - **Expected**: User C appears in the picker (C has never been introduced to B)
   - **Actual**: User C does not appear in the picker
5. User A opens User C's chat screen and taps "introduce to your circle"
   - **Expected**: User B appears in the picker (B has never been introduced to C)
   - **Actual**: User B does not appear in the picker

### What is wrong

The contact picker filters out contacts that should be eligible for introduction. The filtering logic in `FriendPickerWired._loadFriends()` builds an exclusion set from ALL introduction records where the current user is the introducer, but the logic on paper appears correct for excluding only the specific (recipient, introduced) pair. This means the bug may lie in unexpected data — such as duplicate or bidirectional introduction records being created — rather than in the filter algorithm itself.

### Who is affected

All users who attempt to make a second introduction to a recipient after a prior introduction to that same recipient is still pending (partially accepted or fully pending).

## Impact Analysis

| Scenario | Severity | Frequency |
|---|---|---|
| First introduction to a contact | Not affected | N/A |
| Second introduction to the same recipient after a fully completed (mutualAccepted) prior intro | Likely affected | Moderate |
| Second introduction to the same recipient after a pending/partial prior intro | Affected (confirmed) | Common |
| Introduction to a new recipient (no prior intros to that recipient) | Not affected | N/A |

- **Severity**: Blocks functionality — the user literally cannot find the contact they want to introduce
- **Workaround**: None — the contact does not appear in the picker, so the user cannot proceed
- **User-visible consequence**: The introduction feature appears broken after the first use with a given recipient

## Current State

### Filtering logic

**File**: `lib/features/introduction/presentation/screens/friend_picker_wired.dart:53-85`

The `_loadFriends()` method builds the contact list:

1. Loads all active contacts via `contactRepo.getActiveContacts()`
2. Loads all introductions where the current user is the introducer via `introRepo.getIntroductionsByIntroducer(identity.peerId)`
3. Builds an `alreadyIntroduced` exclusion set:
   - For each introduction: if `intro.recipientId` matches the current recipient, add `intro.introducedId` to the set
   - For each introduction: if `intro.introducedId` matches the current recipient, add `intro.recipientId` to the set
4. Filters contacts: exclude the recipient themselves, blocked contacts, and anyone in `alreadyIntroduced`

### Database query

**File**: `lib/core/database/helpers/introductions_db_helpers.dart:151-167`

The `dbLoadIntroductionsByIntroducer()` query:

```sql
SELECT * FROM introductions WHERE introducer_id = ? ORDER BY created_at DESC
```

This query returns ALL introduction records regardless of status (pending, mutual_accepted, passed, expired, already_connected). There is no status-based filtering.

### Introduction statuses

**File**: `lib/features/introduction/domain/models/introduction_model.dart`

Individual party status (`IntroductionStatus`): pending, accepted, passed

Overall status (`IntroductionOverallStatus`): pending, mutualAccepted, passed, expired, alreadyConnected

Status derivation logic (lines 140-162):
- Both accepted → mutualAccepted
- Either passed → passed
- Older than 30 days and still pending → expired
- Otherwise → pending

### Database schema

**File**: `lib/core/database/migrations/019_introductions_table.dart`

```
introductions table:
  id TEXT PRIMARY KEY
  introducer_id TEXT NOT NULL
  recipient_id TEXT NOT NULL
  introduced_id TEXT NOT NULL
  recipient_status TEXT NOT NULL DEFAULT 'pending'
  introduced_status TEXT NOT NULL DEFAULT 'pending'
  status TEXT NOT NULL DEFAULT 'pending'
  created_at TEXT NOT NULL
  ...
```

Indexes exist on `recipient_id`, `introduced_id`, and `introducer_id`.

### Data flow: "introduce to your circle"

1. User opens a conversation → `ConversationWired`
2. Taps "introduce to your circle" → `_onIntroduce()` (conversation_wired.dart)
3. Opens `FriendPickerWired` as a modal bottom sheet with the current contact as `recipient`
4. `FriendPickerWired.initState()` calls `_loadFriends()` → builds filtered contact list
5. User selects contacts and taps "Introduce" → `_onSend()` calls `sendIntroductions()` use case
6. `sendIntroductions()` creates one introduction record per selected friend and sends P2P messages

### Related files

| File | Purpose |
|---|---|
| `lib/features/introduction/presentation/screens/friend_picker_wired.dart` | Contact filtering and selection state |
| `lib/features/introduction/presentation/screens/friend_picker_screen.dart` | Pure UI rendering of the picker |
| `lib/features/introduction/application/send_introduction_use_case.dart` | Creates introduction records and sends P2P messages |
| `lib/features/introduction/domain/models/introduction_model.dart` | Model with status enums and derivation logic |
| `lib/features/introduction/domain/repositories/introduction_repository.dart` | Repository interface |
| `lib/core/database/helpers/introductions_db_helpers.dart` | Raw SQL queries |
| `lib/core/database/migrations/019_introductions_table.dart` | Table schema |
| `lib/core/database/migrations/025_introduction_already_connected.dart` | Added already_connected status |
| `lib/features/conversation/presentation/screens/conversation_wired.dart` | Entry point (_onIntroduce) |

### Existing test coverage

| Test file | What it covers | What it misses |
|---|---|---|
| `test/features/introduction/regression/introduction_regression_test.dart` (lines 437-491) | Basic exclusion: contact already introduced to the same recipient is filtered out | No test for partial acceptance + second introduction to same recipient |
| `test/features/introduction/integration/introduction_smoke_test.dart` (lines 197-219) | Duplicate prevention | No multi-step sequential introductions |
| `test/features/introduction/presentation/screens/friend_picker_test.dart` | Pure UI rendering | Does not test FriendPickerWired's _loadFriends() logic at all |

### Key gap in existing tests

No test covers the exact bug scenario:
- Create introduction (A introduces D to B)
- Partially resolve it (B accepts, D does not)
- Attempt a second introduction to the same recipient (A tries to introduce C to B)
- Verify C appears in the picker

## Scope Clarification

| Area | Status | Notes |
|---|---|---|
| FriendPickerWired._loadFriends() filtering logic | In scope | Primary suspect |
| getIntroductionsByIntroducer() DB query | In scope | No status filtering — may return records that should be ignored |
| Introduction model status derivation | In scope (read-only) | Need to understand which statuses should exclude contacts |
| sendIntroductions() use case | In scope (read-only) | May be creating unexpected records |
| Introduction listener (incoming intro handling) | In scope (read-only) | May be saving duplicate records from the recipient/introduced side |
| ConversationWired._onIntroduce() entry point | Out of scope | Just opens the picker, no filtering logic |
| FriendPickerScreen (pure UI) | Out of scope | Renders whatever it receives |
| Introduction acceptance/rejection flow | Out of scope | Not related to the picker filtering |
| P2P message format for introductions | Out of scope | Not related to the picker filtering |

## Test Cases

### Picker filtering — basic correctness

- TC-PF-01: User A has 3 friends (B, C, D). A has never introduced anyone. A opens B's chat and taps "introduce to circle". Both C and D should appear in the picker (B should not appear).
- TC-PF-02: User A has 3 friends (B, C, D). A opens B's chat and taps "introduce to circle". B should NOT appear in the picker (cannot introduce someone to themselves).
- TC-PF-03: User A has 3 friends (B, C, D). Contact D is blocked. A opens B's chat and taps "introduce to circle". Only C should appear (D is blocked, B is the recipient).
- TC-PF-04: User A has only 1 friend (B). A opens B's chat and taps "introduce to circle". The picker should show an empty list (no one to introduce).

### Picker filtering — single prior introduction (the bug scenario)

- TC-PF-05: A has friends B, C, D. A introduced D to B. Both B and D accepted (mutualAccepted). A opens B's chat picker — C should appear (D correctly excluded). **This is the basic exclusion case.**
- TC-PF-06: A has friends B, C, D. A introduced D to B. B accepted, D never responded (pending). A opens B's chat picker — C should appear. **This is the exact reported bug.**
- TC-PF-07: A has friends B, C, D. A introduced D to B. Neither B nor D responded (both pending). A opens B's chat picker — C should appear.
- TC-PF-08: A has friends B, C, D. A introduced D to B. B passed (rejected). A opens B's chat picker — both C and D should appear (the passed introduction should no longer block D from being re-introduced).
- TC-PF-09: A has friends B, C, D. A introduced D to B. The introduction expired (>30 days, both still pending). A opens B's chat picker — both C and D should appear (expired introductions should not block re-introduction).

### Picker filtering — bidirectional (from the other contact's chat)

- TC-PF-10: A has friends B, C, D. A introduced D to B (pending). A opens C's chat picker — B should appear (B was the recipient in a different introduction, not related to C). **This is the second part of the reported bug.**
- TC-PF-11: A has friends B, C, D. A introduced D to B (pending). A opens C's chat picker — D should appear (D was introduced to B, not to C).
- TC-PF-12: A has friends B, C, D. A introduced D to B (pending). A opens D's chat picker — B should NOT appear (D was already introduced to B, even though from the other direction). C should appear.

### Picker filtering — multiple prior introductions

- TC-PF-13: A has friends B, C, D, E. A introduced C to B (mutualAccepted). A introduced D to B (pending). A opens B's chat picker — only E should appear (C and D are correctly excluded for B).
- TC-PF-14: A has friends B, C, D. A introduced C to B (mutualAccepted). A introduced D to C (pending). A opens B's chat picker — D should appear (D was introduced to C, not to B). C should not appear (C was introduced to B).
- TC-PF-15: A has friends B, C, D. A introduced C to B. A introduced D to B. A introduced D to C. A opens B's chat picker — neither C nor D should appear. A opens C's chat picker — only D if not already introduced to C, otherwise empty. A opens D's chat picker — neither B nor C if already introduced to both.

### Picker filtering — status-based re-introduction eligibility

- TC-PF-16: A introduced D to B. B passed (rejected). A opens B's chat picker — D should be eligible again (a passed introduction should not permanently block re-introduction).
- TC-PF-17: A introduced D to B. D passed (rejected). A opens B's chat picker — D should be eligible again.
- TC-PF-18: A introduced D to B. Introduction expired (>30 days). A opens B's chat picker — D should be eligible again.
- TC-PF-19: A introduced D to B. Status is alreadyConnected (they connected independently). A opens B's chat picker — D should NOT appear (they are already connected, re-introduction is meaningless).
- TC-PF-20: A introduced D to B. Both accepted (mutualAccepted). A opens B's chat picker — D should NOT appear (introduction was successful, no re-introduction needed).

### Picker filtering — data integrity

- TC-PF-21: Verify that `getIntroductionsByIntroducer()` returns ONLY introductions where the current user is the introducer. If introduction records are synced to the recipient and introduced parties, those records should not appear in the introducer's query results (they have the same introducer_id, so they should — verify no ID collision).
- TC-PF-22: After A introduces D to B, verify exactly 1 introduction record exists in A's local database for that (A, B, D) triple. If more than 1 record exists (e.g., from P2P sync), the filtering may double-count.
- TC-PF-23: After A introduces D to B, check what records exist on B's device and D's device. Verify that the `introducer_id` in those records still points to A, so B's or D's picker queries (which filter by THEIR identity as introducer) do not pick up A's introduction records.

### Picker — UI and state

- TC-PF-24: A opens B's chat picker, sees C and D. A selects C and sends the introduction. A immediately opens B's chat picker again — C should no longer appear (just introduced). D should still appear.
- TC-PF-25: A opens B's chat picker. The picker shows a loading state while contacts are being fetched, then transitions to the filtered list.
- TC-PF-26: A has 20 friends. A opens B's chat picker. All 19 non-B, non-blocked, non-already-introduced friends appear. A types a search query — only matching friends are shown.
- TC-PF-27: A opens B's chat picker. The list shows correctly. A closes the picker without sending. A opens B's chat picker again — the same correct list appears (no stale state from the previous open).

### Regression — existing introduction behavior

- TC-RG-01: A introduces C to B. Both accept. The mutualAccepted flow works correctly (contact exchange happens). Verify this is not broken by any fix to the picker filtering.
- TC-RG-02: A introduces C to B. C passes (rejects). The passed flow works correctly. Verify the introducer (A) sees the correct status update.
- TC-RG-03: A introduces C to B from B's chat screen. Then A introduces D to B from B's chat screen. Both introductions are created as separate records with distinct IDs.
- TC-RG-04: The existing regression test "already-introduced contacts excluded from friend list" (introduction_regression_test.dart lines 437-491) still passes.
- TC-RG-05: The existing smoke test for duplicate prevention (introduction_smoke_test.dart lines 197-219) still passes.

### Group conversation introduction picker (if applicable)

- TC-GP-01: Verify whether the "introduce to circle" feature is available in group conversations. If yes, verify the same filtering logic applies and the same bug scenarios are tested. If no, confirm it is intentionally absent.
