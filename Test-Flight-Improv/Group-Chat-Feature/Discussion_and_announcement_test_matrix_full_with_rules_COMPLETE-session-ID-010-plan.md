# Session ID-010 Plan - Readable non-friend fallback identity

## Final verdict

`implementation-ready`

## Final plan

### real scope

- Resolve source row `ID-010` only: when full avatar sharing is unavailable,
  non-friend fallback identity and avatar must remain readable and intentional.
- Reuse the current repo fallback instead of building new identity plumbing.
  `UserAvatar` already falls back to deterministic `RingAvatar`; this session
  should prove that group member rows and conversation rows preserve readable
  names alongside that fallback.

### closure bar

- Member-list rows still show readable participant names when no photo exists.
- Conversation rows still show readable sender names when no photo exists.
- Both surfaces render `RingAvatar` fallback through `UserAvatar`.
- Required direct tests pass.
- The source matrix row can be updated from `Partial` to `Covered` with
  concrete file-and-test evidence tied to `ID-010`.

### source of truth

- `lib/features/home/presentation/widgets/user_avatar.dart`
- `lib/features/home/presentation/widgets/ring_avatar.dart`
- `lib/features/groups/presentation/widgets/group_member_row.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `test/features/groups/presentation/group_info_screen_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart`

### exact problem statement

- The remaining trust contract is not guaranteed photo sync for non-friends; it
  is readable fallback identity when a real profile photo is unavailable.
- The repo already owns that fallback through `UserAvatar -> RingAvatar`, but
  the group surfaces need direct row-owned proof.

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/presentation/group_info_screen_test.dart`
- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart`
