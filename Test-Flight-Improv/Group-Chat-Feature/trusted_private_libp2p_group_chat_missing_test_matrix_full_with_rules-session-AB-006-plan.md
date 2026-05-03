# AB-006 Session Plan - Suspicious or oversized media does not auto-download

Status: accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T10:03:00+02:00 | Local evidence auditor completed | AB-006 source matrix row; ordered-session AB-006 row; group media MIME, size, integrity policy tests; send, listener, offline replay, and fake-network media tests | Current repo already has direct AB-006 evidence for dangerous MIME, MIME mismatch, oversized descriptors, hashless descriptors, oversized fake-network delivery, and tampered downloads. | Persist AB-006 as `Covered` with evidence-only closure. |

## real scope

AB-006 asks that suspicious or oversized group media stays blocked or manual-only until validation passes. The closure covers:

- dangerous or unsupported MIME descriptors
- mediaType mismatch
- oversized single attachment and oversized aggregate descriptors
- missing content hashes before live listener auto-download
- dangerous encrypted offline replay
- oversized fake-network delivery to recipients
- tampered downloaded content failing integrity before done/display

## closure bar

AB-006 can be resolved when direct tests prove suspicious media does not reach persistence, publish/inbox fanout, notification preview, recipient auto-download, durable media rows, or completed display state before validation passes.

## session classification

`implementation-ready`, closed through existing row-specific evidence. No production code change was needed.

## Device/Relay Proof Profile

- Profile for this session: host-only policy, application, listener, offline replay, and fake-network integration proof.
- Real-network proof is supplemental because the row's row-owned behavior is validation before persistence/download/display side effects.

## files touched

- closure docs only

## exact tests and gates run

- `flutter test --no-pub test/core/media/group_media_size_policy_test.dart test/core/media/group_media_mime_policy_test.dart test/core/media/group_media_integrity_policy_test.dart` passed (`+18`).
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'rejects dangerous media MIME'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'rejects oversized'` passed (`+2`).
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'rejects mediaType mismatch'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'auto-download'` passed (`+3`).
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'dangerous media'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'oversized fake-network media is not stored or downloaded by recipients'` passed (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name 'tampered fake-network media download fails integrity before done'` passed (`+1`).
- `git diff --check` passed before closure-doc edits.

## Final Execution Verdict

Accepted on 2026-05-01. AB-006 is covered by existing direct tests: suspicious and oversized media is rejected before send persistence/publish/inbox storage, before listener notification preview or auto-download, before encrypted replay persistence, and before fake-network recipient download/storage; tampered downloads are quarantined as integrity failures before done/display state.
