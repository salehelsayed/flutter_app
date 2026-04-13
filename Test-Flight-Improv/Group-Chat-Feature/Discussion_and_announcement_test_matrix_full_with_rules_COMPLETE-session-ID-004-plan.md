# Session ID-004 Plan - Non-friend onboarding scope boundary

## Final verdict

`stale/already-covered`

## Final plan

### real scope

- Resolve source row `ID-004` by pinning the current repo truth only.
- Do not invent or partially implement a non-friend onboarding feature in this
  session.
- Confirm whether the shipped product exposes a supported onboarding path for
  non-friend participants; if not, mark that boundary explicitly as unsupported
  current product scope.

### closure bar

- Repo evidence shows create/add-member selection is contact-only.
- Repo evidence shows incoming invites from unknown senders are rejected rather
  than creating pending or joined state.
- The source matrix row is updated from `Open` to `Unsupported` with concrete
  code/test references.
- The breakdown records the row as out of current product scope rather than as
  an unowned implementation gap.

### source of truth

- `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`
- `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`
- `test/features/groups/presentation/create_group_picker_wired_test.dart`
- `test/features/groups/presentation/contact_picker_wired_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Discussion-And-Announcement-Feature-Audit.md`

### exact problem statement

- Current repo behavior supports mixed-social-graph messaging once membership
  exists, but it does not ship a non-friend-compatible onboarding path.
- Both shipped onboarding selectors draw from active contacts, and invite intake
  rejects unknown senders.
- This row should therefore close as explicitly unsupported current scope, not
  as an implementation target for this rollout.
