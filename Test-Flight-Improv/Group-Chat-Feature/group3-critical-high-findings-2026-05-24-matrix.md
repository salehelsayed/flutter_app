# Group 3 Critical/High Findings Review Matrix

Source: user-provided Group 3 review findings, reviewed against the current repo on 2026-05-24.

Status vocabulary:
- `Open`: accepted for this rollout.
- `Covered`: current code already covers the material risk or the finding does not match the current contract.
- `Skipped`: real concern, but not a narrow/safe fix for this rollout.
- `Closed`: fixed in this rollout with concrete evidence.

| Row | Finding | Status | Decision | Evidence / Closure Bar |
| --- | --- | --- | --- | --- |
| G3-001 | `addGroupMember` can save a member into the wrong group | Closed | Implemented | `addGroupMember` rejects mismatched `GroupMember.groupId` before write/config sync; covered by `G3-001 rejects member group mismatch before save or config sync`. |
| G3-002 | Invite signature validation does not verify cryptographic signature in the model parser | Covered | Skip exact model-parser change | Acceptance paths verify Ed25519 via `verifyGroupInviteAttestation` and `callVerifyPayload`; keeping pure model parse structural avoids async bridge dependency in domain model. |
| G3-003 | Expired or stale invites can parse as valid | Closed | Implemented narrowed fix | `GroupInvitePayload` supports opt-in `validationTime`; acceptance rejects expired policy, invalid welcome package, and stale freshness proof before bridge work while parse-only inspection remains available. |
| G3-004 | Invite permission can assign admin/privileged member | Closed | Implemented | Invite-only actors are blocked from adding admins or permission overrides unless they can manage roles; covered by `G3-004 invite-only writer cannot add admin or permission overrides`. |
| G3-005 | Remove permission can remove admins without a role boundary | Closed | Implemented | Removing an admin now requires manageRoles/admin authority in addition to last-admin protection; covered by `G3-005 writer with remove permission cannot remove an admin`. |
| G3-006 | Stale membership events can remove re-added members / config `joinedAt` precedence | Closed | Implemented | Add/remove reject stale/equal membership event times, and config parsing now prefers explicit config `joinedAt`; covered by G3-006 tests. |
| G3-007 | Membership mutations are not atomic and can race | Closed | Implemented narrowed fix | Added per-group async membership mutation lock around add/remove validation, local mutation, and config sync; covered by same-group serialization test. |
| G3-008 | Local DB rollback after ambiguous bridge failure | Skipped | Too large | Needs durable pending group-config sync state, schema, retry/reconciliation worker, and bridge contract. Not safe as a narrow use-case patch. |
| G3-009 | Removed-member verification material is not preserved | Closed | Implemented | `removeGroupMember` saves a removed-member snapshot before deletion and requires the repository capability; covered by `G3-009 saves removed member snapshot before deleting member`. |
| G3-010 | Add/remove allow mutation of dissolved groups | Closed | Implemented | Add and remove reject dissolved groups immediately after load; covered by G3-010 add/remove tests. |
| G3-011 | Reaction target message is not scoped to group | Closed | Implemented | Outbound send rejects messages outside the requested group; incoming/replay validates target group when message repository state is available. |
| G3-012 | Reaction sender key/device is not enforced | Closed | Implemented | Outbound sender key must bind to a legacy member key or active device key; incoming device/key mismatch is rejected when provided. |
| G3-013 | Reaction `action` is accepted but ignored | Closed | Implemented | Parser now rejects invalid actions, invalid timestamps, and blank required fields; handler only applies explicit add/remove. |
| G3-014 | Reaction sends are not idempotent | Closed | Implemented narrowed fix | Add reaction IDs are deterministic for `groupId/messageId/senderPeerId/emoji`; focused send test proves repeat add keeps one stored reaction. |
| G3-015 | Reaction published before durable local state | Skipped | Too large | Requires pending reaction state/status schema or repository extensions. Deterministic IDs reduce duplicate retry risk, but durable pending-send is a separate rollout. |
| G3-016 | Repository defaults silently disable durable replay state | Covered | Skip | Production `GroupMessageRepositoryImpl.runInboxPageTransaction` already fails fast when the transaction helper is absent; fakes intentionally provide durable in-memory behavior. |
| G3-017 | Pending invite repository keyed by group, not invite/device | Skipped | Too large | Real feature gap, but fixing requires pending invite primary-key migration, repository contract migration, UI accept-by-invite changes, and multi-device UX decisions. |
| G3-018 | Invite delivery attempt cannot represent real attempts | Skipped | Too large | Real feature gap, but requires schema/model/repo/UI migration from group+peer status to attempt/invite/device/envelope state. |
| G3-019 | Device identity validation incomplete and invalid devices silently dropped | Closed | Implemented | Config key-material validation now rejects missing device id/transport/signing key and duplicate device ids while preserving legacy aliases. |
| G3-020 | Repair models/repositories lack lease and retry scheduling | Skipped | Too large | Real feature gap, but requires repair scheduler semantics, schema migration, worker claim protocol, and stale lease recovery. |
| G3-COMPAT | Dart null-aware map-value syntax may require newer Dart | Covered | Skip | `pubspec.yaml` requires Dart SDK `^3.9.0`, so the syntax is compatible. |
