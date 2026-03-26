# Session 22 Plan: Add Media Download Deduplication / In-Flight Guard

## 1. real scope

Prevent overlapping callers from racing the same attachment download.

Concrete repo evidence says the issue is still real, not stale:

- `lib/features/conversation/application/download_media_use_case.dart` marks an attachment `downloading` and immediately calls `callP2PMediaDownload(...)`, but it has no in-flight map, no coordinator, and no early join path for a second caller.
- The same helper is already used by more than one production caller:
  - `lib/features/conversation/application/chat_message_listener.dart`
  - `lib/features/groups/application/group_message_listener.dart`
  - `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/posts/application/download_post_media_use_case.dart` is a separate seam with a similar download shape, and `lib/main.dart` wires it into both `PostListener` and `PostPassListener`.
- Current direct tests are single-call success/failure tests. There is no current concurrency regression in `test/features/conversation/application/download_media_use_case_test.dart`, and there is no small direct unit test for `download_post_media_use_case.dart`.

Default scope:

- fix the in-flight race at the existing `downloadMedia()` seam
- keep the change small and local
- preserve current success, failure, cleanup, and immediate-UI-path behavior

Posts decision:

- inspect the post path before coding
- do **not** generalize to posts by default
- only touch `download_post_media_use_case.dart` if a shared guard/coordinator is clearly smaller and safer than a conversation/group-only fix

Explicit scope guard for this session:

- no lazy-download redesign
- no product settings or auto-download policy work
- no larger media subsystem rewrite
- no bridge contract redesign

## 2. session classification

`implementation-ready`

Why:

- the missing guard is explicit in `download_media_use_case.dart`
- the risky overlap shape is already present because multiple production callers can hit the same helper
- the first proving layer is clear: a deterministic concurrency regression in `download_media_use_case_test.dart`
- no external dependency or profile capture is needed before implementation

Status call:

- the issue is still real
- it is not stale
- it is not prerequisite-blocked

## 3. files and repos to inspect next

Primary production files:

- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/posts/application/download_post_media_use_case.dart`
- `lib/core/media/media_file_manager.dart`
- `lib/main.dart`

Only if a shared abstraction is actually justified:

- `lib/core/media/download_coordinator.dart`

Primary tests:

- `test/features/conversation/application/download_media_use_case_test.dart`
- `test/features/conversation/application/chat_message_listener_test.dart`
- `test/features/conversation/integration/media_attachment_flow_test.dart`
- `test/features/conversation/integration/voice_message_exchange_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/posts/improvement/post_pass_encrypted_media_integration_test.dart`

Conditional adjacent verification if execution changes shared helper semantics more than internal dedup:

- `test/features/groups/application/group_message_listener_test.dart`

Repo boundary:

- single repo only
- no external tree work is expected

## 4. existing tests covering this area

Useful current coverage:

- `test/features/conversation/application/download_media_use_case_test.dart` already covers:
  - successful download result shape
  - bridge command shape
  - status transition `pending -> downloading -> done`
  - bridge error -> `failed`
  - thrown error -> `failed`
  - preservation of original attachment fields
- `test/features/conversation/application/chat_message_listener_test.dart` already covers:
  - conversation auto-download success
  - skip when already downloaded
  - skip when no attachments
  - skip when `mediaFileManager` is null
  - failure and thrown-download handling
- `test/features/conversation/integration/media_attachment_flow_test.dart` and `test/features/conversation/integration/voice_message_exchange_test.dart` already protect message/media metadata propagation and pending-download persistence
- `test/features/groups/application/group_message_listener_test.dart` currently protects group receive/persist behavior, but it does not directly exercise `downloadMedia(...)`
- `test/features/groups/presentation/group_conversation_wired_test.dart` is the more relevant adjacent proving seam for the shared pending-download UI path if a landed helper change needs explicit group-side verification
- `test/features/posts/improvement/post_pass_encrypted_media_integration_test.dart` already proves one successful `downloadPostMedia(...)` path after encrypted repost hydration

What is missing:

- no concurrency regression for overlapping `downloadMedia(...)` calls on the same attachment
- no proof that overlapping callers collapse to one real bridge download
- no proof that concurrent success/failure callers converge on one stable terminal DB state
- no small direct post-media unit test if a shared coordinator is introduced

## 5. regression/tests to add first, if any

Add the first regression at the lowest proving layer in `test/features/conversation/application/download_media_use_case_test.dart`:

- same attachment, same context, two overlapping `downloadMedia(...)` calls
- fake bridge deliberately delays completion so the overlap is real
- expect exactly one real `media:download` bridge call
- expect stable DB transitions:
  - one logical move into `downloading`
  - one terminal `done` or `failed`
  - no oscillation back to `pending`
- expect both callers to converge on the same logical outcome
  - same absolute local path on success
  - or both return `null` on failure

Add a second regression in the same file if needed to pin failure sharing:

- overlapping callers when the download fails or throws
- expect one real bridge call
- expect terminal `failed`
- expect cleanup still occurs once and no stale `downloading` state remains

If posts are intentionally brought under the same guard in this session:

- add one small direct posts-side regression first
- the regression must hit a seam that actually calls `downloadPostMedia()` or a shared coordinator beneath it
- do not rely only on `hydratePostMediaFn` proxy wiring tests or the existing repost integration test as the primary proof

## 6. evidence to capture first, if the session is profile-gated or evidence-gated

Not applicable. Session 22 is not profile-gated or evidence-gated.

## 7. step-by-step implementation or evidence-collection plan

1. Reconfirm the current call graph for `downloadMedia()` and `downloadPostMedia()`.
2. Decide the dedup key deliberately before coding.
   - The guard must be context-aware enough to avoid cross-wiring different storage destinations.
   - A raw blob ID alone is risky because conversation/group/post downloads can resolve to different local paths.
3. Add the red concurrency regression first in `test/features/conversation/application/download_media_use_case_test.dart`.
4. Choose the smallest implementation boundary:
   - default: add the in-flight guard at the existing `downloadMedia()` seam
   - only introduce a reusable `download_coordinator.dart` helper if it materially simplifies the code or if posts are intentionally included
5. Keep posts as an explicit fork in the plan:
   - if the smallest safe fix lives entirely inside `downloadMedia()`, leave posts untouched
   - if the implementation intentionally shares the guard with posts, add the direct posts regression first and then patch `download_post_media_use_case.dart`
6. Preserve current behavior while deduplicating:
   - immediate caller still gets an absolute path for display on success
   - DB still stores relative path
   - that absolute-path-to-caller contract applies to `downloadMedia()` only
   - `downloadPostMedia()` currently returns the relative stored path and should stay that way unless the session intentionally changes that contract
   - failure still marks `failed`
   - cleanup still removes partial files
7. Re-run the direct use-case test first.
8. Re-run `chat_message_listener_test.dart` to confirm auto-download behavior is unchanged except for dedup.
9. Re-run the 1:1 media integration tests.
10. If posts were touched, run the direct posts proof and then the existing encrypted repost integration.
11. Because `downloadMedia()` is also used by live group receive/download paths, run one targeted group direct suite as adjacent protection whenever a landed change modifies that shared helper.
12. If existing group tests do not directly prove the pending-download dedup path, add one small regression in `test/features/groups/presentation/group_conversation_wired_test.dart`.
13. Run the required named gates:
   - `1:1 Reliability Gate`
   - `Group Messaging Gate` for any landed change in the shared `downloadMedia()` helper
   - `Posts / Privacy Gate` only if posts were touched
   - `Baseline Gate`

## 8. risks and edge cases

- The dedup key can be wrong if it is too broad. The same blob ID can appear in different storage contexts, so keying only by blob ID risks returning the wrong local path or joining unrelated work.
- The guard must clear itself on both success and error; otherwise stale in-flight entries will block later legitimate downloads.
- Two overlapping callers must not leave `download_status` stuck at `downloading`.
- Success must still preserve the current relative-path-in-DB / absolute-path-to-UI split.
- `downloadMedia()` is already shared with group callers, so silent behavior changes can leak beyond 1:1 even if posts stay untouched.
- `downloadPostMedia()` has different responsibilities, including encrypted file handling and a different repository API, so blindly forcing it under the same abstraction may broaden scope more than Session 22 needs.

## 9. exact tests to run after implementation, if code changes occur

- `flutter test test/features/conversation/application/download_media_use_case_test.dart`
- `flutter test test/features/conversation/application/chat_message_listener_test.dart`
- `flutter test test/features/conversation/integration/media_attachment_flow_test.dart`
- `flutter test test/features/conversation/integration/voice_message_exchange_test.dart`

Only if posts are touched:

- `flutter test test/features/posts/application/download_post_media_use_case_test.dart`
- `flutter test test/features/posts/improvement/post_pass_encrypted_media_integration_test.dart`

Because the helper is shared with group callers:

- `flutter test test/features/groups/presentation/group_conversation_wired_test.dart`

- `flutter test test/features/groups/application/group_message_listener_test.dart`

## 10. subsystem gate(s), if relevant

- `1:1 Reliability Gate` is required for any landed change in planned scope
- `Group Messaging Gate` is required for any landed change in the shared `downloadMedia()` helper because group receive/download callers already use that seam
- `Posts / Privacy Gate` is required only if `download_post_media_use_case.dart` or shared post download wiring is touched

## 11. whether Baseline Gate is required

Yes, if Flutter production code changes land.

Reason:

- Session 22 is implementation-ready
- the expected fix is a Flutter production-code change in shared media download behavior

## 12. whether Startup / Transport Gate is required

No, in planned scope.

Reason:

- the session is about deduplicating callers around the existing download path
- it does not need to change startup, resume, reconnect, or transport selection
- only run `Startup / Transport Gate` if execution changes the bridge media-download contract itself

## 13. done criteria

- overlapping callers for the same attachment/context no longer race into multiple real downloads
- one real bridge `media:download` call serves overlapping callers
- the final DB state is stable and correct on both success and failure
- no incorrect `download_status` oscillation remains
- cleanup still works on failure
- current single-caller behavior remains intact
- if posts were intentionally included:
  - posts have a direct regression too
  - `Posts / Privacy Gate` is green
- if the landed fix changes the shared helper used by group receive/download callers:
  - targeted group direct verification is green
  - `Group Messaging Gate` is green
- the direct test set, `1:1 Reliability Gate`, `Group Messaging Gate`, and `Baseline Gate` are green
- the change remains a small in-flight guard/coordinator, not a lazy-download redesign

## 14. dependency impact on later sessions if this session blocks

- Session 23 media timing and hotspot signals remain noisier, because duplicate callers can still inflate download work and muddle local measurements
- later media UX or lazy-download work would still inherit an undefined duplicate-caller contract
- posts can continue independently because their download seam is separate today, but there would still be no reusable dedup contract if future work wants one
