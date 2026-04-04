# GAP-3: Remove Destructive Inbox Retrieve Fallbacks

## Context

The durable inbox drain path (`retrieve_pending → stage locally → ack relay`) is safe — messages stay on the relay until confirmed persisted locally. But four code paths silently fall back to the destructive legacy `_retrieveInboxPage` (which calls `inbox:retrieve` — relay deletes messages on read). If the app crashes during processing, those messages are permanently lost.

## The Four Dangerous Seams

All in `lib/core/services/p2p_service_impl.dart`:

| Line | Trigger | What happens |
|---|---|---|
| **507** | `_inboxStagingRepository == null` | Entire drain uses legacy destructive retrieve |
| **546** | `callP2PInboxRetrievePending` throws | Falls back to `_retrieveInboxPage` |
| **553** | `retrieve_pending` returns `ok != true` | Falls back to `_retrieveInboxPage` |
| **572** | Some raw messages fail `_stagingEntryFromRawInboxMessage` | Entire page falls back to `_retrieveInboxPage` |

All four call `fallbackToLegacyRetrieve()` (line 511) which calls `_retrieveInboxPage()` (line 655) which calls `callP2PInboxRetrieve` — the destructive relay command.

## Fix

### Principle: Never delete from the relay until local persistence is confirmed. If anything goes wrong, leave messages on the relay and retry later.

### Step 1: Make `_inboxStagingRepository` non-nullable

**File: `lib/core/services/p2p_service_impl.dart`**

Change the field from `InboxStagingRepository?` to `InboxStagingRepository`:
```dart
// Before:
final InboxStagingRepository? _inboxStagingRepository;

// After:
final InboxStagingRepository _inboxStagingRepository;
```

Update the constructor to require it. Remove the `if (_inboxStagingRepository != null)` guard at line 723 — always use the durable path.

**File: `lib/main.dart`**

Verify `_inboxStagingRepository` is already injected. If so, no change needed — just the type tightening.

### Step 2: Delete `fallbackToLegacyRetrieve` entirely

**File: `lib/core/services/p2p_service_impl.dart`**

Remove the entire `fallbackToLegacyRetrieve` closure (lines 511-537).

Replace each call site:

**Line 546 (retrieve_pending exception)**:
```dart
// Before:
} catch (e) {
  return fallbackToLegacyRetrieve(
    reasonCode: 'retrieve_pending_exception',
    reasonDetail: e.toString(),
  );
}

// After:
} catch (e) {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_SERVICE_INBOX_RETRIEVE_PENDING_ERROR',
    details: {'reasonCode': 'retrieve_pending_exception', 'error': e.toString()},
  );
  return (replayed: 0, staged: 0, hasMore: false);
  // Messages stay safe on relay — next drain cycle retries
}
```

**Line 553 (retrieve_pending returns error)**:
```dart
// Before:
if (response['ok'] != true) {
  return fallbackToLegacyRetrieve(
    reasonCode: 'retrieve_pending_error',
    reasonDetail: response['errorMessage']?.toString(),
  );
}

// After:
if (response['ok'] != true) {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_SERVICE_INBOX_RETRIEVE_PENDING_ERROR',
    details: {'reasonCode': 'retrieve_pending_error', 'errorMessage': response['errorMessage']?.toString()},
  );
  return (replayed: 0, staged: 0, hasMore: false);
  // Messages stay safe on relay — next drain cycle retries
}
```

**Line 572 (unstageable messages)**: Instead of discarding the entire page, stage the valid entries and skip the bad ones:
```dart
// Before:
final entries = rawMessages
    .map((raw) => _stagingEntryFromRawInboxMessage(raw, toPeerId))
    .whereType<InboxStagingEntry>()
    .toList();
if (entries.length != rawMessages.length) {
  return fallbackToLegacyRetrieve(
    reasonCode: 'retrieve_pending_unstageable_messages',
    ...
  );
}

// After:
final entries = <InboxStagingEntry>[];
var skipped = 0;
for (final raw in rawMessages) {
  final entry = _stagingEntryFromRawInboxMessage(raw, toPeerId);
  if (entry != null) {
    entries.add(entry);
  } else {
    skipped++;
  }
}
if (skipped > 0) {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_SERVICE_INBOX_STAGE_SKIPPED_MALFORMED',
    details: {'rawCount': rawMessages.length, 'skipped': skipped, 'staged': entries.length},
  );
}
if (entries.isEmpty) {
  return (replayed: 0, staged: 0, hasMore: response['hasMore'] == true);
}
// Continue with staging the valid entries...
```

### Step 3: Remove `_retrieveInboxPage` and its callers

**File: `lib/core/services/p2p_service_impl.dart`**

After step 2, `_retrieveInboxPage` (line 655) has no callers. Also check:
- `_continueDrainingOfflineInbox` (line 676) — calls `_retrieveInboxPage` at line 682. This is the legacy drain loop. Replace with `_continueDrainingOfflineInboxDurably` or remove entirely.
- `_drainOfflineInbox` (line 722) — the `if (repo == null)` branch at line 723 uses `_retrieveInboxPage`. After step 1 makes the repo non-nullable, this branch is dead code.

Remove:
- `_retrieveInboxPage` method (lines 655-674)
- `_continueDrainingOfflineInbox` method (lines 676-717)
- `_emitInboxMessages` helper if only used by the legacy path
- The `if (_inboxStagingRepository != null)` guard in `_drainOfflineInbox` — always go to `_drainOfflineInboxDurably`

### Step 4: Remove the `repo == null` guard in `_retrievePendingInboxPage`

Line 506-509 becomes dead code after step 1:
```dart
// Remove this:
final repo = _inboxStagingRepository;
if (repo == null) {
  return (replayed: 0, staged: 0, hasMore: false);
}
```

Just use `_inboxStagingRepository` directly since it's now non-nullable.

## Files Modified

| File | Change |
|---|---|
| `lib/core/services/p2p_service_impl.dart` | Make staging repo non-nullable, delete `fallbackToLegacyRetrieve`, delete `_retrieveInboxPage`, delete `_continueDrainingOfflineInbox`, fix unstageable handling, remove null guards |
| `lib/main.dart` | Verify staging repo injection (likely no change needed) |
| `test/core/services/p2p_service_impl_test.dart` and related lifecycle/stop-race tests | Rewrite legacy `inbox:retrieve` expectations for offline drain paths so they assert durable `retrieve_pending` behavior and absence of destructive fallback |

## Scope Caveats

- **Public `retrieveInbox()` remains destructive unless explicitly widened**: `P2PServiceImpl.retrieveInbox()` still calls `callP2PInboxRetrieve`. There are no current production callers under `lib/`, so GAP-3 can stay focused on the offline drain path. But the plan should not claim that every destructive inbox path is gone unless this API is also deprecated, converted, or removed in a follow-up.
- **Legacy test expectations must be updated, not preserved**: a meaningful part of the existing test suite still assumes `inbox:retrieve` is used during offline drain or stop-race flows. GAP-3 is not complete until those assertions are rewritten to prove durable retrieval and the absence of fallback.
- **Malformed relay entries are an accepted temporary tradeoff, not a final cleanup model**: the proposed behavior of skipping malformed entries locally while leaving them on the relay is correct for no-loss. But poison entries may keep resurfacing until relay TTL expiry or manual cleanup. That is acceptable for GAP-3; durable dropped-message journaling or quarantine remains follow-on hardening.

## Test Plan

### Unit Tests

1. **retrieve_pending throws → returns empty, no destructive call**: Mock bridge to throw on `inbox:retrieve_pending`. Verify `inbox:retrieve` is never called. Verify return is `(0, 0, false)`.

2. **retrieve_pending returns error → returns empty, no destructive call**: Mock bridge to return `{ok: false}`. Same assertions.

3. **Some messages unstageable → stages valid entries, skips bad ones**: Mock retrieve_pending with 3 messages, one with null entryId. Verify 2 are staged, 1 skipped, no destructive fallback.

4. **All messages unstageable → returns empty with hasMore forwarded**: Mock retrieve_pending with all malformed messages. Verify `(0, 0, hasMore)` returned.

5. **Happy path unchanged**: Mock retrieve_pending with valid messages. Verify staging + ack + replay works as before.

6. **Legacy drain tests rewritten around durable semantics**: Update existing offline-drain and stop-race tests so they assert `inbox:retrieve_pending` is used for drain, `inbox:retrieve` is not used as fallback, and retry-on-error leaves messages on the relay.

### Manual Test

7. Kill the relay server briefly while the app is draining inbox → verify the app does NOT delete messages, retries on next drain
8. Send messages while recipient is offline, recipient resumes → all messages arrive (existing behavior preserved)

## Risk

- **Relay `retrieve_pending` is broken on server**: The old code would fall back to destructive retrieve and still deliver messages (lossy but functional). The new code returns empty and retries — messages are delayed but never lost. This is the correct tradeoff: **delayed > lost**.
- **Malformed messages block the page**: The old code fell back to destructive retrieve for the entire page. The new code skips malformed entries and stages the rest. Malformed entries stay on the relay until TTL expiry (7 days) or manual cleanup. This is acceptable — we don't want to destructively consume messages we can't parse.
