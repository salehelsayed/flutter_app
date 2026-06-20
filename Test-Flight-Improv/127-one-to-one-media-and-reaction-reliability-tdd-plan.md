# 127 — 1:1 media + reaction reliability (4 device-found bugs) — TDD plan

Status: **ALL 4 IMPLEMENTED + HOST-GREEN (uncommitted)** 2026-06-18. Found live on Pixel 6 ↔ iOS
sims (alice/bob/charlie). Logs: `pixel.log` / `charlie.log` / `bob.log` / `alice.log` at repo root.
(Bug D added after confirming the reaction-notification gap is NOT 1:1-only.)

## Closeout (2026-06-18)
- **Bug B** — `MediaUploadInFlightTracker` (new, process-wide) + `retryIncompleteUploads`
  `isUploadInFlight` guard (deferral, no terminalize) + foreground `begin/end` in
  `conversation_wired` send loop (outer finally, all exit paths) AND voice path + wired both
  `main.dart` retrier call sites. Tests: retry suite +34 (new in-flight test), tracker suite +5.
- **Bug A** — `_resolveDisplayMedia` helper + resolved display media applied in BOTH send-result
  branches (`conversation_wired`). Widget test in `conversation_wired_test.dart`
  (**mutation-verified**: reverting the else-branch fix fails it — message keeps deleted `pick.png`).
- **Bug C** — optional notification deps on `handleIncomingReaction` → `maybeShowNotification` on a
  fresh ADD upsert only (remove/stale/blocked stay silent); wired via a mutable holder in
  `main.dart` populated after the notification stack, read by `replayInboxReaction` (covers all 3
  reaction receive paths). Tests: reaction use-case suite +5 (add notifies / remove silent /
  viewing-suppressed / explicit-suppress / no-deps-no-throw).
- **Bug D** — reaction-notification gap also exists in **group** chats (separate pipeline:
  `handle_incoming_group_reaction_use_case.dart` + `group_message_listener._handleReaction`). Log
  proof: bob received 4 group ❤️ reactions (18:06–18:08) with zero `NOTIFICATION_*`. FIX: new
  `_maybeNotifyGroupReaction` in `group_message_listener.dart`, called from the LIVE `_handleReaction`
  on a fresh ADD upsert — mirrors the group MESSAGE gates (skip own via `_resolveSelfPeerId`, group
  **mute**, viewing-suppression + tone debounce), routes to `group:<id>`, names the reactor from the
  group roster (`getMembers`). Recovery/drain/buffer-flush call the use case directly (not this LIVE
  path), so a resume drain never spams. Tests: group listener suite +3 (add notifies / remove silent
  / muted silent), **mutation-verified** (removing the call fails the add test). Full suite 189 green.
- Gates: `flutter analyze` 0 new issues across all 6 touched files; suites green —
  conversation_wired (76), conversation_screen + 3 sibling wired suites (72), reaction use-case (21),
  reaction listener (65 combined), retry/tracker (34/5). No DB migration.
- REMAINING (external-only): device re-verification on Pixel↔sims; optional follow-up — wire the
  rare non-staged `ReactionListener` path (constructor deps) and reaction l10n (body is a literal,
  mirroring `post_reaction_listener`).

## Reliability-test pass (flutter-reliability-test-writer skill, 2026-06-18)
Added reliability-invariant coverage on top of the base RED tests; all green, 325 across the 5
affected suites; `dart format` + `flutter analyze` clean on touched test files.
- Bug A: `127-Bug-A: own-sent MULTI-image (3) all render when send returns null` (the original
  device symptom was multi-image) — all 3 resolve to absolute `/media/` paths, no "Media unavailable".
- Bug B: `127-Bug-B: foreground send marks the blob in-flight during upload and clears it after` —
  proves the LIVE send actually engages `mediaUploadInFlightTracker` (the retrier's guard) and
  releases it post-send (the production-wiring proof the use-case/unit tests couldn't give).
- Bug C: `rapid reactions debounce the tone — the second notification is silent` — burst of
  reactions never spams a sound (per-conversation 30s tone debounce).
- Bug D: `own reaction (mesh echo) does NOT self-notify` (getSelfPeerId==reactor) +
  `reaction is suppressed while viewing the group conversation` (resumed + tracker.setActive).
ALL host-proven only (no simulator/device run in this pass).

## Device re-test 2026-06-18 22:38 (pixel→charlie, 1 image) — Bug B timing-hole found + fixed
Fresh `pixel.log` (PID 10137, app reinstalled 22:34) still reproduced: sender "Media unavailable"
(screenshot) + blob `3bbb1ed3` encrypted TWICE + `RETRY_INCOMPLETE_UPLOAD_SUCCESS`, with NO
`RETRY_INCOMPLETE_UPLOAD_SKIP_IN_FLIGHT`. Timeline: `23.839` foreground LAN BLOB_ENCRYPT →
`23.976` **RETRY_INCOMPLETE_UPLOAD_START** (retrier check) → `23.978` retrier BLOB_ENCRYPT#2 →
`23.993` foreground relay MEDIA_UPLOAD_START (where the guard's `begin()` ran).
**Root cause of the hole:** `mediaUploadInFlightTracker.begin()` was set only at the relay-upload
step (`conversation_wired.dart` ~2028), AFTER the LAN-direct send — so a retrier firing during the
LAN-send window (~17ms before the mark) slipped through and double-uploaded. That spurious retrier
also re-saves the relative `local_path` after the send-path resolved it, re-introducing Bug A on
the sender (A and B are coupled).
**Fix:** mark all optimistic media ids in-flight at the EARLIEST point — right after `optimisticMedia`
is built (`conversation_wired.dart` ~1872), before durable prep + LAN send (the optimistic ids ARE
the upload blobIds). New mutation-verified test `127-Bug-B: blob is in-flight at the FIRST
(optimistic) persist …` (fails if `begin()` is moved back to the relay step). conversation_wired
suite 79 green, analyze clean.
**IMPORTANT:** the running device build did NOT contain a working fix (host-only/uncommitted edits
were never compiled into the installed APK, or it had the holed version). The fixes MUST be
rebuilt + installed from the current working tree to validate on-device — a host green gate cannot
prove a deploy.

## Round 3 (2026-06-18 22:54, alice→bob iOS) — DURABLE render-boundary fix (the real Bug A fix)
Symptom persisted: alice (sender) "Media unavailable", bob (receiver) fine. Single image, durable
copy committed (`70579635`), **no retrier** — pure sender render. alice.log had NO
`MEDIA_DURABILITY_DONE_PATH_MISSING` (file existed at resolve), so a *resolving* path would have
shown it.
**Why rounds 1-2 failed (the real lesson):** I patched PRODUCERS of the path (the send-result
branches, the retrier race) but never the **render gate itself**. `MediaGridCell._hasExistingLocalFile`
and `MediaThumbnailImage` do `File(attachment.localPath).existsSync()` VERBATIM; the DB persists a
RELATIVE path (`media/<peer>/<blob>.jpg`); relative→absolute resolution is scattered across FOUR
async call sites and the render boundary resolves NOTHING. Any path that upserts the raw DB row
(incoming-stream `_onIncomingMessage`/`_autoDownloadMedia`, voice send, or a merge re-selecting a
stale relative `current`) re-feeds the relative path → gate fails. Round 2 only patched 2 producers
of many → whack-a-mole, and it can't survive build skew or future upsert paths.
**Durable fix (workflow-synthesized, 3-lens verified):** resolve at the single render chokepoint via
a SYNC cached-dir resolver, mirroring `UserAvatar.setDocumentsDir`:
- `media_file_manager.dart`: `static cacheDocumentsDir(path)` + `static resolveStoredPathSync(stored)`
  (pure-string port of the async resolver; pass-through when unseeded; idempotent on absolute;
  self-corrects stale-container absolute paths via the `/media/` rebase).
- `main.dart:388-393`: seed `MediaFileManager.cacheDocumentsDir(appDocDir.path)` next to the avatar one.
- `media_grid_cell.dart:59-68,151-153` + `media_thumbnail_image.dart:_resolvedMediaPath,_buildImage`:
  resolve through `resolveStoredPathSync` before every `File(...)`. Covers initial-load, live-reload,
  send-result, voice, incoming, retrier uniformly; immune to the merge re-selection + build skew.
Tests: `media_file_manager_test` sync-resolver group (6) + `media_grid_cell_test`
`127 round-3 … RELATIVE localPath renders` widget test (**mutation-verified**: reverting the gate to
raw `File(localPath)` → no `MediaThumbnailImage`, fails). Suites green: media (63), media_file_manager,
full_screen_viewer + share (61), conversation_wired (79). 0 new analyze. STILL device-unverified
(needs rebuild+install), but the fix is now at the gate so it holds regardless of producer path/build.

All three are **1:1-only** regressions in the newer encrypted-1:1-media + reaction code (docs
112/117/118). The **group** equivalents already have the missing protection, which is why group
media + group reactions behave correctly on the same devices.

---

## Bug B (P0 — silent data loss to recipient): 1:1 media `content_hash_mismatch`

**Symptom:** recipient sees "Couldn't verify this media" (status `integrity_failed`) for some 1:1
images; the next image from the same sender works. Intermittent.

**Root cause (log + source confirmed):** there is no per-blob upload idempotency between the
foreground send (`conversation_wired.dart:2029`, encrypt-once-correct: `preparedArtifact` reused
for LAN+relay at `:1999`/`:2045`) and the background `PendingMessageRetrier`
(`pending_message_retrier.dart:542-544` → `retry_incomplete_uploads_use_case.dart:186`). While the
attachment row is `upload_pending`, a connectivity edge fires the retrier, which calls
`uploadMediaFn` **without** `preparedArtifact` → `prepareEncryptedMediaArtifact` re-encrypts with a
**fresh AES-GCM nonce** (`go-mknoon/crypto/file_crypto.go:50-55`) → different ciphertext + different
SHA-256 than the foreground artifact. The chat envelope advertises ONE `contentHash`; the relay can
end up serving the other encryption's bytes. The receiver's PRE-decrypt ciphertext-hash gate
(`download_media_use_case.dart:869-899`) rejects → `integrity_failed`.

Device proof: failed blob `4726d737` had **2× `BLOB_ENCRYPT`**, **2× `MEDIA_UPLOAD_START`**,
**2× `MEDIA_UPLOAD_SUCCESS`** (`storedPersistently:true` then `false`); its LAN ciphertext hash
`169666…` never appears in `charlie.log`. Every singly-encrypted blob succeeded.

**Fix:** a process-wide in-flight upload guard so the retrier never re-encrypts/re-uploads a blob
the foreground send is actively handling.
- New `MediaUploadInFlightTracker` (process-wide `Set<String>` of blobIds, `begin/end/isInFlight`).
- `conversation_wired.dart`: `begin(mediaId)` before the foreground upload, `end(mediaId)` after the
  whole send completes (finally), so the retrier can't slip in during either the upload OR the
  envelope-send window.
- `retry_incomplete_uploads_use_case.dart`: inject `bool Function(String blobId)? isUploadInFlight`
  (default `() => false`). Before `uploadMediaFn` (`:186`), if in-flight → **defer** the whole
  message (leave rows `upload_pending`, emit `RETRY_INCOMPLETE_UPLOAD_SKIP_IN_FLIGHT`, do NOT
  re-encrypt, do NOT terminalize). Wire the tracker in `main.dart`.

Note: re-encrypt-on-retry is **correct when the retrier runs alone** (foreground crashed mid-send):
the existing KC-2 logic (`:252-279`) invalidates the stale wire envelope and the subsequent
`sendChatMessage` re-advertises the new `contentHash`. The guard only suppresses the *concurrent*
double, which is the only inconsistent case.

**Tests** (`test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`):
1. `isUploadInFlight` returns true for the pending blob → `uploadMediaFn` NOT called, attachment
   stays `upload_pending` (deferred, not `upload_failed`), no `sendChatMessage`. Mutation-verify by
   flipping the guard off → upload runs.
2. `isUploadInFlight` false (default) → existing behavior unchanged (regression guard).

---

## Bug A (P2 — sender-side, self-heals): own multi-image 1:1 thumbnails show "Media unavailable"

**Symptom:** sender's own grid of multiple 1:1 images renders "Media unavailable" though the durable
files exist on disk; self-heals after leaving + re-entering the chat; worse with more images.

**Root cause (log + source confirmed):** own-sent media stores a **relative** `local_path`
(`media/<peer>/<blob>.jpg`, `upload_media_use_case.dart:435-439,518-535`, status `done`).
`MediaGridCell` checks `File(attachment.localPath).existsSync()` verbatim with no resolution
(`media_grid_cell.dart:58-61`) → a relative path resolves against CWD (`/`) → `false` even though
the file exists. The only in-memory relative→absolute resolution after send is gated behind
`if (message != null)` (`conversation_wired.dart:2149-2162`); the `message == null` else branch
(`:2174`) only updates status and never re-resolves the media. DB-load resolves on re-entry
(`resolveStoredPath`, `media_file_manager.dart:144-178`) → self-heal. pixel.log shows **no**
`MEDIA_DURABILITY_DONE_PATH_MISSING` and **no** status downgrade → confirms the "relative path
unresolved" mechanism, not a status-downgrade.

**Fix:** always resolve uploaded attachments to absolute before display, in BOTH send-result
branches.
- Extract `_resolveDisplayMedia(List<MediaAttachment>?)` (maps each non-null `localPath` via
  `mediaFileManager.resolveStoredPath`).
- Build `displayMedia` once before the `if (message != null)` branch; upsert resolved media in the
  `message != null` branch AND in the `message == null` else branch (currently status-only).

**Tests** (`test/features/conversation/presentation/.../conversation_wired_*_test.dart` widget test,
mirroring existing harness): own-sent 1:1 multi-image with a relative durable `local_path` renders
the image (no `media_unavailable`) when `sendChatMessageFn` returns `message == null` AND when it
returns a non-null message. Plus a focused unit test of `_resolveDisplayMedia` if extracted to a
testable seam.

---

## Bug C (P2 — missing feature/hook): no notification when a contact reacts to your 1:1 message

**Symptom:** A reacts 👍 to B's 1:1 message; B stores it but gets no notification. Group + post
reactions are unaffected (posts DO notify — `post_reaction_listener.dart:81-85`).

**Root cause (log + source confirmed):** the incoming `message_reaction` path
(`incoming_message_router.dart:178` → staged via `p2p_service_impl.dart:879-892` →
`replayInboxReaction` `main.dart:1983` → `handleIncomingReaction`) stores + commits the reaction
and **never invokes the notification layer**. The chat path does
(`chat_message_listener.dart:571` → `maybeShowNotification`). bob.log: reaction-receive window has
zero `NOTIFICATION_*` events. All 3 reaction receive paths (relay/live-direct/LAN) funnel through
the single `replayInboxReaction` chokepoint (it discards the `change`).

**Fix:** notify on a genuine incoming reaction **add** (upsert), reusing `maybeShowNotification` so
all existing suppression gates apply (viewing-conversation, recent-remote-push dedup,
NotificationToneTracker 30s per-conversation debounce). Hook inside `handleIncomingReaction` via new
optional notification deps (covers the staged path that is the real delivery), passed from
`replayInboxReaction`.
- Notify only when `action == 'add'` and the reaction is a fresh, non-stale upsert.
- **Never** notify on `remove` / stale-ignored (`change == null`) / blocked sender.
- Body: `"Reacted {emoji} to your message"`; title = sender username; payload routes to the chat.
- No double-notify: live and staged paths are mutually exclusive per reaction, and LWW makes a
  re-processed duplicate return a stale/no-change result (no second notify).

**Tests** (`test/features/conversation/application/handle_incoming_reaction_use_case_test.dart`):
1. incoming `add` + fake NotificationService → `showMessageNotification` called once, body contains
   the emoji, title = sender username.
2. incoming `remove` → NOT called.
3. stale `add` (older than current) → NOT called.
4. blocked/unknown-sender / no deps → NOT called (and no throw).
5. viewing-the-conversation suppression path → suppressed (gate reused).

---

## Landing order & gates
1. Bug B (P0 data loss) → 2. Bug A → 3. Bug C.
- Per bug: write failing test → implement → green; mutation-verify the new guard.
- Final: `flutter analyze` (0 new), run the touched suites (conversation app + reaction + push +
  media widget). No DB migration required for any of the three.
