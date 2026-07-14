# Plan 234 Session 02 — Compose, Receive Ordering, Redaction, and Private Download Entry

Status: accepted
Source: `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-breakdown.md` Session 02
Run mode: implementation-committed gap-closure
Dependency: Session 01 accepted; DB v100 landed; no migration is permitted here

## Planning Progress

- `2026-07-11 11:10 CEST` — Evidence Collector verified the accepted Session-01 policy/codec/v100 seams and current send, receive, listener, notification, composer, and download entry points. No blocker; Session 02 is host-only.
- `2026-07-11` — Local bounded planning fallback completed after the fresh planner stopped with a grounded but non-reusable intake draft. Exact RED/GREEN, owner files, privacy order, ordinary sentinels, and curated gate are frozen below.

## Problem And Evidence

Session 01 made private policy representable and durable, but no product path selects or uses it. Current direct sends build `MessagePayload` without `privateMedia`; the incoming sanitizer rebuild drops the typed policy; listener previews still derive text/media and calls auto-download after emission; decrypted push previews still expose ordinary caption/media copy; the composer permits up to ten attachments and has no private mode; visible-media recovery and explicit download have no parent-policy context.

The privacy boundary is one ordered journey:

1. select a valid private mode for one image/GIF/video with no text;
2. validate before upload/encryption/persistence;
3. place the typed policy only in encrypted inner JSON and retain the already-persisted envelope for retry;
4. normalize inbound shape and persist policy/state on the direct parent before UI, notification, or download decisions;
5. redact every local/decrypted-push preview to the localized meaning `Private media`;
6. prohibit automatic/recovery download while allowing only an explicit canonical app-local download before a terminal/unsupported state.

## Scope Contract And Guard

In scope:

- Extend direct composer state/UI with ordinary, protected, view-once, and disappearing (1 hour/1 day/7 days) selection for exactly one eligible image/GIF/video.
- Reset private selection whenever text/caption becomes non-empty, attachment count/type becomes ineligible, edit/Forward/voice mode starts, attachment is removed/replaced, or the completed send clears the draft. Restore it only with the same failed composer snapshot.
- Validate the typed message shape in both UI and `sendChatMessage` before upload/envelope/persistence; return a typed invalid-private-media result without dispatch.
- Pass `PrivateMediaPolicy` through optimistic/persisted `ConversationMessage`, `MessagePayload`, and encrypted v2 inner JSON. Retry reuses the persisted wire envelope; it must not silently remint or downgrade policy.
- Preserve the policy through inbound sanitization. Normalize malformed/ineligible private shape to typed `unsupported`, generic/redacted copy, and state `unsupported`; valid private rows begin `available` and disappearing rows compute receiver-local `receivedAt`, `expiresAt`, and clock high-water at the durable receive boundary.
- Preserve an existing stricter/terminal policy/state on same-ID duplicate/replay. Duplicate media repair must not reopen or overwrite a private terminal/unsupported parent.
- Ensure parent policy/state is saved before attachment persistence completes and before handler return; listener UI emission, notification, and any download decision occur only after that durable save.
- Make foreground/local and decrypted one-to-one push previews return `Private media` for every private or unsupported policy, without caption/thumbnail/kind/mode/duration/expiry/path/key/state leakage.
- Skip listener auto-download and visible-row recovery for private/unsupported messages. Explicit user retry/download may call the existing integrity-verified canonical app-storage path only when current policy/state allows it; unsupported or terminal states fail closed before bridge/file mutation.
- Add English/German/Arabic localization keys for composer labels, duration/copy truth, invalid-state copy, and generic notification body; generated localization files may update through the repo generator.

Likely production owner files:

- `lib/core/media/private_media_policy.dart`
- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/push/application/show_notification_use_case.dart`
- `lib/features/push/application/push_decrypt_preview.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/compose_area.dart` and, if useful, one private-mode picker widget
- `lib/l10n/app_en.arb`, `app_de.arb`, `app_ar.arb` and generated localization outputs

Out of scope:

- New schema/migration/version changes, v101, group/announcement behavior, Go/relay changes.
- Opening/reveal/consume/expiry sweep/cleanup/restart engine (Session 03).
- Save/Share/Forward/bookmark/library/PiP central qualification (Session 04).
- Private viewer/capture/native platform protection (Session 05).

Hard guards:

- Never emit policy/mode/duration/state in the clear envelope, v1 writer, logs, notification payload/body, or relay metadata.
- Never treat malformed/unknown/ineligible private policy as ordinary.
- Never upload or persist an invalid composer combination.
- Never auto-download private/unsupported media, including visible-row recovery.
- Never let a caller-supplied stale boolean grant a private download; qualify the current message policy/state at the owning UI/repository boundary.
- Preserve ordinary/legacy direct media behavior and all accepted Session-01 v100 fields.

## Test Contract

Author the following causal tests before production changes and observe at least one focused RED per owned boundary.

1. `test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart`
   - private selector appears only for exactly one image/GIF/video;
   - protected/view-once/disappearing selections and exact durations flow to send;
   - text, second attachment, file/audio, edit/Forward/voice, removal/replacement reset or reject before upload;
   - same failed draft restores the selection; successful send cannot leak selection to the next draft;
   - copy states device-local expiry/view-once truth.
2. Extend `test/features/conversation/application/send_chat_message_use_case_test.dart`
   - valid policy reaches `MessagePayload.privateMediaPolicy`, persisted parent, and encrypted inner plaintext;
   - outer envelope/log diagnostics contain none of the forbidden fields/caption;
   - every invalid shape returns a typed rejection before encrypt/send/save;
   - failed/retry flow retains the original encrypted envelope and policy.
3. Extend `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart` and/or add `chat_message_listener_private_media_test.dart`
   - inbound sanitizer preserves policy;
   - valid receive saves version/mode/state/timestamps before returned UI/notification/download work;
   - invalid/unknown shape persists unsupported and redacted;
   - duplicate/retry cannot downgrade/reopen terminal or unsupported parent;
   - same-ID group/unresolved attachment rows remain untouched.
4. Extend `test/features/conversation/application/chat_message_listener_test.dart`
   - private/unsupported parent is emitted only after durable save;
   - notification body is `Private media`;
   - auto-download decider/bridge are never called for private or unsupported rows;
   - ordinary auto-download tests remain green.
5. Extend `test/features/push/application/show_notification_use_case_test.dart` and `push_decrypt_preview_test.dart`
   - local and decrypted push paths redact all private/unsupported variants;
   - route payload/identity remains usable but no policy/caption/media metadata leaks;
   - ordinary caption/type preview remains unchanged.
6. Extend `test/features/conversation/application/download_media_use_case_test.dart` plus the wired screen test
   - explicit available private download reaches existing canonical integrity-verified storage;
   - unsupported/terminal state returns before bridge, staging, or row mutation;
   - visible recovery/auto paths never call download for private rows;
   - ordinary explicit retry remains unchanged.
7. Run `test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart` as the encrypted ordinary-media preservation sentinel.

Representative mutations that must fail: drop policy during sanitize rebuild; notify before parent save; call auto-download for protected; map unsupported to ordinary; serialize mode in outer envelope; accept private text/second attachment; reset terminal state on duplicate; allow explicit download for unsupported; reuse a prior private selection on the next draft.

## Implementation Sequence

1. Write composer/send, receive-order, notification/push, and download-boundary REDs.
2. Add pure message-shape normalization/download eligibility to the shared private policy without adding lifecycle execution.
3. Thread policy through send/optimistic persistence and preserve it on retry.
4. Preserve/normalize policy on receive and seed v100 fields at durable commit; enforce duplicate monotonicity.
5. Gate listener/visible recovery, local notification, decrypted push, and explicit download.
6. Add composer UI/state/localization and stale-selection/failed-draft behavior.
7. Run focused tests, exact ordinary sentinels, curated `1to1`, scoped analyzer, and diff/scope guards; perform independent QA.

## Device/Relay Proof Profile

- Profile: `host-only`.
- This session changes Flutter application/presentation behavior but no native OS boundary, real-network authority, SQLCipher schema, paired-device contract, or relay protocol.
- No device command is required for closure. Session 01 already proved v100 on explicit Android/iOS targets; Session 05 owns platform privacy proof.
- Relay-authoritative consume/revocation remains N/A by accepted product policy.

## Acceptance Gates

```bash
git status --short

flutter test test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart
flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart
flutter test test/features/conversation/application/chat_message_listener_test.dart
flutter test test/features/push/application/show_notification_use_case_test.dart
flutter test test/features/push/application/push_decrypt_preview_test.dart
flutter test test/features/conversation/application/download_media_use_case_test.dart
flutter test test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart

./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh 1to1 --list

dart analyze lib/core/media/private_media_policy.dart lib/features/conversation/application/send_chat_message_use_case.dart lib/features/conversation/application/handle_incoming_chat_message_use_case.dart lib/features/conversation/application/chat_message_listener.dart lib/features/conversation/application/download_media_use_case.dart lib/features/push/application/show_notification_use_case.dart lib/features/push/application/push_decrypt_preview.dart lib/features/conversation/presentation/screens/conversation_wired.dart lib/features/conversation/presentation/screens/conversation_screen.dart lib/features/conversation/presentation/widgets/compose_area.dart
git diff --check
git diff --name-only -- lib/core/database/migrations lib/core/database/app_database_version.dart lib/core/database/production_migration_registry.dart go-mknoon go-relay-server lib/features/groups lib/features/announcements
```

No `core-host-all`, `feature-host-all`, device leg, or full `host-all` is a Session-02 gate.

## Done Criteria

- [x] Causal REDs precede production changes for composer/send, receive ordering, redaction, and download gating.
- [x] Valid private mode/duration is available only for the accepted one-item image/GIF/video shape; invalid/stale combinations never upload or dispatch.
- [x] Private policy is encrypted-inner-only, survives failed-send retry, and persists on outgoing and incoming direct parents.
- [x] Receive commits normalized policy/state/timestamps before UI, notification, attachment download, or duplicate mutation; terminal/unsupported state is monotonic.
- [x] Local and decrypted push preview bodies are exactly the localized meaning `Private media`, with forbidden metadata absent.
- [x] Private/unsupported auto-download and visible recovery are disabled; explicit available private download uses canonical verified app storage; unsupported/terminal explicit download is denied pre-mutation.
- [x] Ordinary/legacy direct media send, receive, preview, download, retry, and encryption sentinels remain green.
- [x] No migration/v101/group/announcement/Go/relay change lands.
- [x] Focused tests, curated `1to1`, host inventory, analyzer, diff/scope guards, and independent QA pass.

## Execution Contract

- **Exact scope and source of truth:** this Session-02 plan and ledger row `02 | Compose, send/receive ordering, redacted previews, and private download entry | implementation-ready`, under repo instructions and the current `1to1` gate definitions. Implement the complete host-only direct sender-to-durable-receiver slice; Session-01 policy/codec/v100 work is an accepted dependency, not work to rewrite.
- **Closure bar:** every Done Criteria item above, every exact direct test and named gate below, a coherent attributable diff, and independent QA with no blocking finding.
- **Code-entry files:** `lib/core/media/private_media_policy.dart`; direct send, inbound handler, listener, download, local-notification, decrypted-push, wired/screen/composer files named in Scope; localization ARBs and generated localization outputs only when required by the composer copy.
- **RED regressions first:** the seven Test Contract boundaries above. `conversation_private_media_composer_test.dart` is currently absent and must be authored; the six named application/push test files must gain focused causal locks before their production seam changes. The ordinary encrypted-media round-trip is preservation evidence, not a new RED.
- **Exact direct tests:** the eight `flutter test ...` commands under Acceptance Gates, including the new composer file and ordinary encryption round-trip sentinel.
- **Named gates and structural guards:** `./scripts/run_test_gates.sh 1to1`; `./scripts/run_host_test_gates.sh 1to1 --list`; the exact scoped `dart analyze ...`; `git diff --check`; and the exact forbidden-scope `git diff --name-only -- ...` command. No family-host-all, full-host-all, device, schema, migration, v101, group, announcement, Go, or relay command is authorized.
- **Known-failure interpretation:** none is pre-authorized. The governing `1to1` record is green; any required failure starts as `pending_triage` and is acceptable only if focused evidence proves it pre-existing and unwidened.
- **Done criteria and privacy order:** invalid composer shape rejects before upload/encrypt/save/dispatch; policy is encrypted-inner-only and retry-stable; inbound normalized policy/state/timestamps save before UI/notification/download; duplicate state is monotonic; local and decrypted-push copy is `Private media`; private/unsupported auto and visible recovery stay off; only explicit `available` private media may enter canonical verified app storage.
- **Non-goals/scope guard:** opening/reveal/consume/expiry cleanup, action qualification, private viewer/native protection, and every out-of-scope surface in Scope Contract And Guard remain untouched.
- **Scoped pre-existing worktree changes:** accepted Session-01/v100 changes already exist in `private_media_policy.dart`, message models/payload codec, DB version/registry/migration/tests, direct media-repository tests, gate registration, and Graphify artifacts. Other dirty reporting/group docs/tests, `.gitignore`, `info.plist`, mockups, and Graphify tooling are unattributed baseline and must be preserved. Session-02 edits must be attributable from this snapshot.
- **Graph Grounding Snapshot:** the current architecture query (`profile=tdd`, `confidence=anchored`, fingerprint `e7cc4ee8228c26f7`) anchored `ComposeArea` and `MessagePayload.privateMediaPolicy`; it surfaced the composer/screen/message-payload path. It did not resolve the runtime send/receive/listener/download/push symbols, so those are explicit graph gaps requiring targeted current-source verification. After the scoped diff, run one `affected` query and verify surfaced callers/tests; refresh once only after accepted QA.

## Execution Progress

| Time | Phase | Files / commands | Result | Next |
|---|---|---|---|---|
| 2026-07-11 12:37 CEST | post-localization structural gates GREEN | ran scoped analyzer including the new shared helper, `git diff --check`, forbidden-scope guard, and an exact hardcode/usage search | analyzer exit 0 with no issues; diff check exit 0; forbidden-scope output remains only accepted Session-01 version/registry files; no production `return 'Private media'` remains and both preview paths call the generated-key helper | rerun exact curated `./scripts/run_test_gates.sh 1to1`, then hand to independent QA if green |
| 2026-07-11 12:38 CEST | final Executor curated gate GREEN | reran exact `./scripts/run_test_gates.sh 1to1` after the locale repair | exit 0 in about 36s, 1810/1810; initial Executor has no known blocking gap and no QA has started yet | hand the unchanged worktree and complete evidence ledger to a fresh independent QA agent |
| 2026-07-11 12:44 CEST | independent QA fix pass 1 — `B1` | independent QA returned `blocking_findings`: `show_notification_use_case_test.dart` has broad formatter-only rewrites in legacy regions despite behavioral gates being green; no behavioral/privacy blocker was confirmed | blocking attribution/coherence finding `B1`; normal diff is +165/-122 while Session-02 causal content is only the private-policy import and two new tests | restore every legacy byte from HEAD while retaining only the import/two tests; rerun the two affected push files, scoped analyzer, and `git diff --check`, then request a fresh QA fix pass without a broad-gate rerun |
| 2026-07-11 12:45 CEST | QA `B1` fix pass 1 complete (`fix_passes=1`) | reconstructed `show_notification_use_case_test.dart` from HEAD and reapplied only the private-policy import plus the two private/localization tests; reran exact show+push files, scoped analyzer including helper, and `git diff --check` | push tests exit 0, 52/52; analyzer exit 0 with no issues; diff check exit 0; show-test normal and whitespace-insensitive stats now both exactly +42/-0, proving legacy bytes restored | request independent post-fix QA focused on `B1` attribution and any remaining counterexample |
| 2026-07-11 12:46 CEST | independent post-fix QA accepted | independent QA re-audited `B1`, shared localization, privacy/download counterexamples, and same-ID replay handling after fix pass 1 | verdict `accepted`, zero blocking findings; `B1` resolved at matching +42/-0 normal/`-w` stats; same-ID `opening`/`viewing` parents are preserved because replay returns without saving | run the single post-acceptance incremental Graphify refresh, final diff/scope guards, and persist the execution result |
| 2026-07-11 12:47 CEST | post-acceptance graph/final guards GREEN | ran the one authorized `./graphify-arch/refresh_arch_graph.sh --incremental`, then final `git diff --check`, forbidden-scope guard, `git status --short`, and `B1` normal/`-w` stats | refresh exit 0: 23 changed code files, 2436 unchanged, graph 46876 nodes/72979 edges, TDD overlay 1248 files/12221 tests/945 targets; diff check exit 0; forbidden scope remains only accepted Session-01 version/registry; `B1` remains +42/-0 in both stats | close Session 02 as accepted with no blocker |

## Execution Result

- **Verdict:** `accepted`. Session 02 implements the host-only direct private-media compose/send/receive/redaction/download-entry slice, all Done Criteria are satisfied, and no required work remains in this session.
- **Topology:** one initial Executor, one independent QA reviewer, and one bounded QA fix pass (`fix_passes=1`). QA first returned attribution finding `B1`, then accepted the reconstructed diff with zero blocking findings.
- **Production result:** private policy is shape-normalized before work, carried only inside the encrypted direct payload, persisted on both parents, and retained on retry/edit. Receive saves normalized policy/state/timestamps before attachment work and preserves terminal, unsupported, opening, and viewing state across duplicate replay. Private/unsupported auto-download and visible recovery are disabled; explicit private download requalifies the current durable parent and permits only `available`. Composer selection, replacement reset, failed-draft restore, and success reset are wired for one image/GIF/video with no caption.
- **Notification result:** local and decrypted-push private previews share `localizedPrivateMediaNotificationBody`, resolve generated en/de/ar copy without a `BuildContext` (including the background isolate), default safely to English, and exclude caption/blob/MIME/policy metadata.
- **Primary production files:** `lib/core/media/private_media_policy.dart`; direct send, inbound, listener, and download application files; `conversation_wired.dart`, `conversation_screen.dart`, and `compose_area.dart`; local/push preview files plus `private_media_notification_body.dart`; en/de/ar ARBs and generated localization outputs.
- **Test files:** the eight exact acceptance files, plus coherent preservation updates in `media_download_slow_transfer_simulator_test.dart`, `send_then_lock_delivery_test.dart`, and `conversation_wired_offline_send_ux_test.dart`. The QA-repaired show-notification diff contains only its import and two new causal tests (`+42/-0` normal and whitespace-insensitive).
- **Focused evidence:** the original eight exact files passed 380/380; the two added locale cases raise the acceptance corpus to 382, with the affected local/push files rerun green at 52/52 after the final mechanical QA repair. The three curated-fallout files passed 35/35.
- **Gate evidence:** final exact `./scripts/run_test_gates.sh 1to1` passed 1810/1810; `./scripts/run_host_test_gates.sh 1to1 --list` discovered 72 commands and executed none; scoped analyzer passed with no issues; final `git diff --check` passed.
- **Failure ledger:** the ordinary round-trip fixture initially failed four downloads because it lacked the new durable-parent repository; the first curated gate exposed two callback-signature fixtures and one slow-download parent fixture; one parallel Flutter invocation hit a native-asset signing race; the locale tests produced the intended compile-time RED; QA `B1` found formatter-only test churn. Every item was causally isolated and resolved, with no known failure carried forward.
- **Scope and safety:** no Session-02 migration, v101, group, announcement, Go, relay, device, family-host-all, or full-host-all change/run occurred. The forbidden-scope guard lists only the accepted Session-01 database version/registry baseline. Unrelated dirty worktree changes were preserved and no git commit was created.
- **Graph evidence:** one post-acceptance incremental architecture refresh completed successfully; no second refresh was run.
- **Deferred by contract:** opening/reveal/consume/expiry cleanup, action qualification, private viewer/native protection, and device/platform proof remain owned by later sessions and are not Session-02 blockers.

## Session Closure Audit

- Closure verdict: `closed`; breakdown ledger status: `accepted`.
- What is now closed: Session 02's eligible one-item private composer state, pre-dispatch validation, encrypted-inner-only direct send/retry policy flow, durable receive-before-preview/download ordering, replay-monotonic private parent state, localized foreground/decrypted-push redaction, private/unsupported automatic-download suppression, and durable-parent-qualified explicit private download entry.
- Residual-only items: none for Session 02.
- Still-open items: Sessions 03-06 remain program work and are not Session-02 residuals; Session 03 is now dependency-satisfied. Opening/reveal/consume/expiry cleanup, central egress/action enforcement, private viewer/native protection, platform/device proof, and final cross-session acceptance retain their assigned later-session owners.
- Accepted differences: this is intentionally a host-only, device-local delivery/redaction/download-entry slice. It adds no schema beyond accepted v100, Go/relay authority, account-wide consumption, native capture protection, lifecycle terminalization engine, or device proof.
- Reopen rule: reopen Session 02 only for a regression in private compose eligibility/reset/restore, pre-work send validation or encrypted policy retention, receive ordering/replay monotonicity, notification redaction, automatic/visible download suppression, or explicit durable-parent download qualification—not for work assigned to Sessions 03-06.
- Maintenance safety: the eight exact acceptance files, ordinary-media preservation sentinels, curated `1to1` gate, 72-command host inventory, scoped analyzer, diff/scope guards, and the localized-preview counterexamples remain the Session-02 closure reference. Independent QA accepted after one attributable-diff fix pass, and the architecture graph was refreshed exactly once after acceptance.

## Post-Closure Repair — iOS NSE Private Preview (2026-07-12)

- **Why Session 02 was reopened:** Session-06 reconnaissance produced concrete regression evidence at the native decrypted-push seam. `ios/NotificationService/NotificationPreviewResolver.swift` decrypted a direct payload and always derived the body from `text`/`media`; a payload with a present encrypted-inner `privateMedia` key could therefore disclose text or an ordinary descriptor such as `Photo`. This reopened only D-234-06 notification redaction. The accepted composer, receive ordering, download, lifecycle, action, and viewer work was not reopened.
- **Preserved overlap:** both Swift files already contained uncommitted Plan-256 reaction-notification work. The repair was applied additively to the current files, preserving its tone lease, event emitter, reaction routing/projection/dedupe, staging, sound, and tests. Pre-repair SHA-256 values were `2ec2134cfbd84af46e02306af8b45e0a42f6ffaceba58ab8225b49b7943a6939` for the resolver and `abb5920a1676300970119e5d67491b294ebae9674034ab2447a1905aa0849942` for its XCTest file.
- **Causal RED:** `testPrivateMediaPreviewIsGenericForSupportedLocalesAndMalformedPolicy` was added before production. Its exact simulator run failed at compile time with `Extra argument 'localeIdentifierProvider' in call`, proving the locale-aware fail-closed seam was absent.
- **Production repair:** the resolver now accepts a defaulted locale provider and checks key presence with `payload.keys.contains("privateMedia")` before calling `pushPreviewBody`. Any present value—including supported modes, an unknown future policy, a malformed scalar, or JSON `null`—returns only the exact localized generic body: English/default `Private media`, German `Private Medien`, or Arabic `وسائط خاصة`. A missing key remains ordinary. Sender title, thread identifier, `didDecrypt`, reason, and reaction behavior are unchanged.
- **GREEN and preservation evidence:** the exact causal XCTest passed 1/1 on simulator `674DFFF6-5F38-4235-93F6-AF7FBF86AE65`; the full `NotificationPreviewResolverTests` suite passed 30/30, including every Plan-256 reaction test and the ordinary direct sentinel; the two Dart local/decrypted-push suites passed 55/55. `git diff --check` passed for both Swift files. Final SHA-256 values are `7d41f72cc5eafc632797f99506b883f2cbb439c199bae467d8bf446aae9b5bad` and `49839d36ae98e95583a26ce1fa4d09ff52ff6b89a3944f1045c4f222fee1fce8` respectively.
- **Independent QA:** a fresh reviewer accepted the repair with zero blocking findings. The original Session-02 `fix_passes=1` remains historical; this separate causal repair is recorded as `post_closure_fix_passes=1` and `behavior_fix_passes=1`.
- **Graphify:** the final attributable production file was queried with `affected`, which resolved `ios/NotificationService/NotificationService.swift` as the caller. After QA, exactly one incremental refresh ran successfully and reported `0` changed code, `2,519` unchanged, graph current, TDD overlay `1,280` files / `12,496` named tests / `962` production targets. Because the refresh reported no native code delta, the anchored affected query plus current source/XCTest verification remain the load-bearing native impact evidence. No second repair refresh is authorized.
- **Closure:** Session 02 is accepted and closed again with no residual. No migration/v101, group, announcement, Go/relay, native channel, device claim, family-host-all, or full `host-all` work occurred. Session 06 may consume this repaired native preview boundary as accepted evidence.
