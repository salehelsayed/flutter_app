# UI-005 Session Plan - Undecryptable placeholders are safe and policy-compliant

Status: accepted

## Planning Progress

| timestamp | role | files inspected | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T10:26:00+02:00 | Local planner completed | UI-005 source matrix row; ordered-session UI-005 row; `drain_group_offline_inbox_use_case.dart`; focused offline replay and group conversation screen tests | The row-owned gap is direct placeholder evidence. Current repo behavior creates a generic `undecryptable` placeholder for missing future key material and renders it without original plaintext or failed-media controls. | Rerun direct application and presentation tests, then close UI-005 as evidence-only if they pass. |

## real scope

UI-005 asks that undecryptable content placeholders stay safe and policy-compliant when messages cannot decrypt or key material is missing. This session covers:

- missing future-epoch offline replay storing a single generic placeholder
- no decrypt attempt or plaintext exposure when the matching key is unavailable
- conversation rendering of the placeholder text
- no failed-media retry/delete controls on undecryptable placeholder rows

## closure bar

UI-005 can be resolved when direct tests prove the stored and rendered placeholder:

- uses safe generic copy instead of original plaintext
- preserves enough metadata to avoid layout or ordering corruption
- marks the message as `undecryptable`
- does not expose failed-media controls or unsafe media actions

## session classification

`implementation-ready`, closed through existing row-specific evidence if focused reruns pass. No production code change is expected.

## Device/Relay Proof Profile

- Profile for this session: host-only application and widget proof.
- Real-device and real-relay proof is supplemental because the row-owned behavior is local persistence/rendering of an already-unrecoverable placeholder.

## files expected to change

- closure docs only, unless focused tests expose a real UI-005 gap

## exact tests and gates to run

- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'future epoch encrypted replay creates one undecryptable placeholder without decrypting'`
- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'renders undecryptable epoch placeholders as safe text'`
- `git diff --check`

## scope guard

Do not claim the missing live key-repair lifecycle from ER-004. UI-005 closes only the safe placeholder persistence/rendering behavior that exists today.

## Execution Progress

| timestamp | role | files inspected or changed | decision | next action |
| --- | --- | --- | --- | --- |
| 2026-05-01T10:27:00+02:00 | Local evidence auditor completed | `drain_group_offline_inbox_use_case.dart`; `drain_group_offline_inbox_use_case_test.dart`; `group_conversation_screen_test.dart` | Existing direct tests satisfy the row-owned placeholder bar: future-epoch replay stores one generic `undecryptable` placeholder without decrypting plaintext, and the conversation UI renders safe copy without failed-media controls. | Persist UI-005 as `Covered` with evidence-only closure. |

## exact tests and gates run

- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'future epoch encrypted replay creates one undecryptable placeholder without decrypting'` passed (`+1`).
- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart --plain-name 'renders undecryptable epoch placeholders as safe text'` passed (`+1`).
- `git diff --check` passed.

## Final Execution Verdict

Accepted on 2026-05-01. UI-005 is covered for safe placeholder persistence and rendering: missing future key material stores a single generic `undecryptable` message, preserves key epoch/status metadata, does not attempt `group.decrypt`, does not expose original plaintext, and renders in the conversation without unsafe failed-media retry/delete controls. The live repair lifecycle remains ER-004 scope and is not claimed here.
