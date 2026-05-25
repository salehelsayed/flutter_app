# GUC-001 TDD plan - reject stale explicit config removals

## Objective

Close the confirmed stale membership bug where an older explicit config snapshot can remove a member after a newer config/membership version has already been applied locally.

## Red

Use the existing focused regression:

```sh
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-029 older versioned config snapshots are ignored after newer version and same-version replay is idempotent'
```

Current failure: after applying version 4, a delayed version 2 `member_removed` deletes Charlie, so `groupRepo.getMember('group-1', 'peer-charlie')` returns `null`.

## Green implementation

Patch only `_shouldIgnoreStaleMemberRemovedEvent` in `group_message_listener.dart`.

Rules:

- If the removal is older than or equal to the membership watermark and the removed member rejoined after the event, keep the existing repair/delete-content behavior.
- If the removal is older than or equal to the membership watermark and the event has an explicit config version, ignore it instead of taking the conflict-applied path.
- Leave legacy/no-explicit-version conflict behavior unchanged.

## Verification

Run:

```sh
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GM-029 older versioned config snapshots are ignored after newer version and same-version replay is idempotent'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --name 'GM-012 stale member_removed delivered after newer re-add|KE-012 delayed old config after re-add|ML-009 delayed older member_removed'
git diff --check
```

## Closure bar

The session is closed when the focused red test turns green, the related stale membership subset stays green, and the diff is limited to the plan docs plus the minimal guard change.

## Execution result

Accepted.

- Red: focused `GM-029` failed before the patch with `persisted == null`.
- Fix: `_shouldIgnoreStaleMemberRemovedEvent` now ignores stale explicit-version removals before the legacy conflict-apply branch.
- Green: focused `GM-029` passed after the patch.
- Green: related stale membership subset passed.
- Clean: `dart format` and `git diff --check` for touched session files.

The full listener test file was sampled as an additional broad gate and still has unrelated individual failures outside this bug path.
