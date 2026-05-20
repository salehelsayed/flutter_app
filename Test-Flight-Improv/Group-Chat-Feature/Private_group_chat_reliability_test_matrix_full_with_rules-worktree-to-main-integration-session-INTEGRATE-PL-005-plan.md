# INTEGRATE-PL-005 Worktree-To-Main Contract

Status: accepted

Source-of-truth:

- `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-PL-005-plan.md`

Imported PL-005 delta only:

- Added `groupMediaAllowedPeersForMembers` to build media relay ACLs from active group member rows by trimming peer ids, dropping blanks, deduping, and preserving membership order.
- Replaced ordinary group media upload, voice upload, and incomplete group upload retry ACL construction with the shared helper.
- Added row-named helper, ordinary upload, voice upload, retry upload, and fake-network media upload selectors.
- Updated adjacent retry assertions to match source PL-005 retry semantics: media `allowedPeers` includes the active local sender/admin and Bob, while durable inbox recipients still exclude the sender and removed peers.

Out of scope:

- No source worktree edits.
- No integration breakdown ledger or `test-inventory.md` edits.
- No live simulator or 3-party E2E proof; source marks it `N/A`.
- No PL-006, PL-007, PL-012, PL-013, PL-014, UP, or ML behavior imports.

Verification:

- `dart format --set-exit-if-changed` over the seven scoped Dart files passed with `0 changed`.
- `flutter analyze --no-pub` over the seven scoped Dart files passed with `No issues found`.
- `flutter test --no-pub test/features/groups/application/group_media_allowed_peers_test.dart test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/integration/group_media_fanout_test.dart --plain-name "PL-005"` passed with `+5`.
- Adjacent retry selector `reuploads only group upload_pending attachments and uses blobId` passed.
- Adjacent retry selector `MD-011 retry excludes a removed member from media ACLs and inbox recipients` passed.
- Adjacent fake-network selector `PL-002 fake-network media-only message reaches recipients with empty text` passed.
- Adjacent fake-network selector `MD-011 removed member is excluded from future media descriptors and downloads` passed.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remained red at `+250 -9` only on known non-PL-005 residuals.
- `./scripts/run_test_gates.sh completeness-check` remained red at `735/736` only on unmatched `test/shared/fakes/fake_group_pubsub_network_test.dart`.
- `git diff --check` over the scoped files passed.

Residuals outside PL-005:

- Existing widget selectors `ordinary media pre-persists the parent row before upload completes and finalizes after sendGroupMessage` and `successful voice send uses the durable copy, cleans pending uploads, and survives temp deletion` still fail on `GROUP_SEND_MSG_USE_CASE_EMPTY_MEMBERSHIP_DISSOLVED` before PL-005-specific allowedPeers logic.
- Broad `groups` residuals remain `BB-007`, `BB-012`, `NW-004`, `IR-003`, `IR-018`, `GE-017`, `GE-019`, `GE-020`, and `GM-029`.
