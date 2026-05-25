# group:updateConfig stale membership session breakdown

## Run-mode snapshot

- Mode: standard
- Source bug: `group:updateConfig` can overwrite newer membership with stale membership.
- Scope guard: keep this Flutter-side and limited to stale membership-event handling; do not touch Go pubsub/key-state work or unrelated group UI changes.
- TDD anchor: `GM-029 older versioned config snapshots are ignored after newer version and same-version replay is idempotent` is the red regression.

## Recommended plan count

1

## Session ledger

| Session | Status | Owner files | Required gates |
| --- | --- | --- | --- |
| GUC-001 | Accepted | `lib/features/groups/application/group_message_listener.dart`; `test/features/groups/application/group_message_listener_test.dart` | Focused GM-029 test; stale add/remove/re-add regression subset; `git diff --check` |

## Ordered sessions

### GUC-001 - Reject stale explicit config removals

Create the smallest TDD fix for delayed older config-bearing `member_removed` events that arrive after a newer membership/config version. Preserve the existing rejoin-repair path for removals older than a local rejoin, but do not let an explicitly versioned stale removal apply over an existing current member.

Acceptance:

- `GM-029` passes and keeps Charlie as writer after the stale version 2 removal follows the version 4 role/config update.
- Same-version config replay remains idempotent and does not issue a second `group:updateConfig`.
- Existing stale add/remove/re-add tests still pass.
- No Go boundary or pubsub changes are made in this session.

## Final verdict

Closed.

Evidence:

- Red confirmed before the fix: focused `GM-029` failed because Charlie was deleted by the stale version 2 removal after version 4 was already applied.
- Green after the fix: focused `GM-029` passed.
- Green related subset: `GM-012 stale member_removed delivered after newer re-add|KE-012 delayed old config after re-add|ML-009 delayed older member_removed`.
- `dart format` is clean for `group_message_listener.dart`.
- `git diff --check` is clean for the touched session files.

Observed outside this session:

- The full `group_message_listener_test.dart` file currently has unrelated individual failures in self-peer caching, `GM-028` empty-peer handling, and notification delivery tests. The focused stale membership gates pass.
