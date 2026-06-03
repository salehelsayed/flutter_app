> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P1** · [Findings appendix](./appendix-findings.md)

---

# Bound media size and give media an honest terminal state

**Priority: P1** &nbsp;|&nbsp; Theme owner: Group-Chat / Media reliability &nbsp;|&nbsp; Status: proposed

> Add product-tuned per-type size limits, cap download retries with a real "unavailable" terminal state, and make group-media retention member-aware so media converges to an honest state across all members.

---

## Why this matters (user experience)

mknoon's promise is a fast, dependable group chat. Today the media path violates that promise in three compounding ways:

1. **No realistic size gate.** Both the per-attachment and the total-message group-media limits resolve to **5 GB**. Only GIFs have a sub-5GB cap. A user can attach a multi-hundred-MB or multi-GB video and the app will happily encrypt it, hash it, upload it, and fan it out to *every* member. On mobile networks that means very long "sending" spinners, battery/data burn, relay storage pressure, and recipients stuck on multi-GB downloads.
2. **Downloads that never resolve.** Plain `failed` downloads (e.g. a blob that is gone) are re-attempted on every screen open with **no retry ceiling and no terminal state**. The user sees a forever-retryable spinner/affordance and never an honest "this media is permanently unavailable."
3. **Media diverges across members.** A 7-day relay TTL plus a per-peer cap (50 blobs / 5 GB) can prune a group blob before an offline member catches up, while present members still see it. Combined with the frozen upload-time ACL, that pruned blob cannot be re-fetched from any peer either.

The net effect: media that is too large to send fast, downloads that spin forever, and content that some members can see and others permanently cannot — the opposite of dependable group chat. The first two fixes are small and high-leverage; the retention/ACL backfill is larger and can follow.

---

## Current behaviour & evidence

### A. Per-attachment and total group-media limits are both 5 GB

- `kGroupMediaPerAttachmentLimitBytes` and `kGroupMediaTotalMessageLimitBytes` both alias `kGeneralMediaAttachmentBudgetBytes` — `group_media_size_policy.dart:8-11`.
- `kGeneralMediaAttachmentBudgetBytes = 5 * 1024 * 1024 * 1024` (5 GB) — `pending_composer_media.dart:6`.
- `GroupMediaSizePolicy.validateSize` rejects only `sizeBytes > perMediaLimitBytes` (5 GB), with a single sub-5GB special case: `normalizedMime == 'image/gif' && sizeBytes > kMaxGifFileSize` — `group_media_size_policy.dart:84-94`.
- `kMaxGifFileSize = 25 * 1024 * 1024` (25 MB) — `media_constants.dart:1`.
- Relay backstop `maxMediaSize int64 = 5 * 1024 * 1024 * 1024` and the only upload check is `req.Size > maxMediaSize` — `media.go:27, 331-334`.

> **Result:** a single 4 GB non-GIF file passes every Dart gate *and* the relay gate. GIF is the only per-file cap below 5 GB.

### B. GIF is gated on raw pre-compression bytes; everything else post-compression

- The GIF branch in `_preparePendingMedia` reads `File(path).lengthSync()` and compares to `kMaxGifFileSize` **before** any processing, then throws and shows `_showGifTooLargeMessage()` — `group_conversation_wired.dart:936-942`.
- All other media is validated on `pending.budgetBytes`, which for non-`original` quality is the **post-processing** file length — `pending_composer_media.dart:52-81`; send-time check at `group_conversation_wired.dart:1289-1300`.

> **Result:** a 30 MB GIF is rejected (raw bytes) while a multi-GB video is accepted. Same root cause as A, but visibly inconsistent across types and measuring different bytes.

### C. Downloads retry forever with no ceiling and no terminal state

- Uploads have a ceiling: `kMaxUploadRetries = 3` (`retry_constants.dart:7`) and flip to terminal `upload_failed` at `group_conversation_wired.dart:1464-1466` and `retry_incomplete_group_uploads_use_case.dart`. The attachment carries `uploadRetryCount` (`media_attachment.dart:48`), persisted via migration 042 (`042_media_attachment_reliability_columns.dart:30`).
- There is **no** `kMaxDownloadRetries` and **no** `download_retry_count` column anywhere in `lib`.
- `isRetryableDownloadFailure` returns true for **both** `failed` and `integrity_failed` unconditionally — `group_media_integrity_policy.dart:73-76` — and drives the user-facing `_canRetryUnavailableMedia` affordance (`media_grid_cell.dart:88-90`; same pattern in `audio_player_widget.dart`).
- On screen open, `_shouldRecoverVisibleAttachment` re-recovers `pending` / `downloading` / `failed` rows (`group_conversation_wired.dart:2440-2446`); on the failure path `downloadMedia` writes `kMediaDownloadStatusFailed` with no attempt counter (`download_media_use_case.dart:237-240`).

> **Verified nuance:** `integrity_failed` is **excluded** from `_shouldRecoverVisibleAttachment` and from `_autoDownloadMedia` (which only re-runs `status == 'pending'`, `group_message_listener.dart:1288`), so tampered blobs are *not* auto-re-quarantined on every open — they only carry a manual retry affordance. The genuine unbounded-auto-retry bug is **plain `failed`** rows, which re-attempt indefinitely.

### D. 7-day TTL + per-peer cap can expire group blobs before offline members catch up

- `mediaTTL = 7 * 24h`; `cleanupExpired` removes blobs with `CreatedAt < cutoff` — `media.go:21, 88-110`.
- `prunePeerLocked` evicts oldest blobs once a recipient exceeds `maxMediaPerPeer = 50` or `maxMediaBytesPerPeer = 5 GB` — `media.go:20, 28, 144-177`.
- Group blobs (`len(meta.AllowedPeers) > 0`) are correctly **not** auto-deleted after a single download — `media.go:440-446` — but they are still subject to TTL cleanup and per-peer pruning. There is no member-aware retention, no per-recipient delivery tracking, and no re-seed path (grep-confirmed).
- The ACL is frozen at upload time: `groupMediaAllowedPeersForMembers` builds `AllowedPeers` from current members (`group_media_allowed_peers.dart:4-15`), passed once to `callP2PMediaUpload` (`upload_media_use_case.dart:157-164`), stored verbatim (`media.go:374`), and enforced on every download via `containsPeer(meta.AllowedPeers, remotePeer)` (`media.go:401-405`). There is no `update_allowed_peers` / re-upload / backfill path.

> **Result:** a member offline for over a week, or a busy group exceeding the per-peer cap, receives the descriptor but finds the blob pruned — an unrecoverable "media unavailable" for content others still see. The frozen ACL additionally blocks any peer-to-peer fallback fetch.
>
> **Scope note (per verifier):** Report 89 makes "no pre-join media/text backfill" an *explicit* product policy (NGM-013), and there is no history-sync that surfaces historical descriptors to new joiners. So the frozen-ACL is a **latent design constraint** (it would block a *future* backfill/quote-of-old-media feature), not an active bug, and there is no text-vs-media asymmetry for historical content. The active, real-today problem in this finding is the **TTL/cap prune race for genuinely offline existing recipients**.

---

## Root cause(s)

| # | Root cause | Surfaces as |
|---|------------|-------------|
| R1 | Group media limits were aliased to the generic 5 GB composer budget instead of product-tuned per-type caps. | A, B |
| R2 | GIF is special-cased in the composer (raw bytes, pre-compression) rather than folded into a single per-type table validated on final bytes. | B |
| R3 | The download path has no attempt counter and no terminal-vs-loading state distinction (unlike uploads). `isRetryableDownloadFailure` conflates "transient failed" with "permanently unavailable / tampered." | C |
| R4 | Relay retention is per-peer/TTL-based with no member-aware "keep until all allowed peers fetched" notion; the ACL is frozen so no peer-to-peer re-fetch fallback exists. | D |

---

## Proposed improvements

Ordered by leverage-per-effort. Items 1–3 are small/medium and ship first; item 4 is larger and follows.

### 1. Per-type group-media size table (decouple from the 5 GB composer budget) — *small*

Introduce explicit, product-tuned caps keyed by logical media type, validated consistently on the **final attachment bytes**.

- In `group_media_size_policy.dart`, replace the two 5 GB aliases with a per-type map and a resolver:

  ```dart
  // group_media_size_policy.dart
  const int kGroupMediaImageLimitBytes = 25 * 1024 * 1024;   // ~25 MB
  const int kGroupMediaVideoLimitBytes = 100 * 1024 * 1024;  // ~100 MB
  const int kGroupMediaAudioLimitBytes = 16 * 1024 * 1024;   // ~16 MB voice
  const int kGroupMediaFileLimitBytes  = 100 * 1024 * 1024;  // generic file fallback
  // Total per message stays modest (e.g. 200 MB) — NOT 5 GB.
  const int kGroupMediaTotalMessageLimitBytes = 200 * 1024 * 1024;

  int groupMediaPerTypeLimitBytes(String? mime) {
    final normalized = GroupMediaMimePolicy.normalizeMime(mime);
    if (normalized == 'image/gif') return kMaxGifFileSize;     // folds GIF in
    final type = MediaAttachment.mediaTypeFromMime(normalized ?? '');
    return switch (type) {
      'image' => kGroupMediaImageLimitBytes,
      'video' => kGroupMediaVideoLimitBytes,
      'audio' => kGroupMediaAudioLimitBytes,
      _ => kGroupMediaFileLimitBytes,
    };
  }
  ```

- Change `validateSize` to derive `perMediaLimitBytes` from `groupMediaPerTypeLimitBytes(mime)` when the caller does not override it, and return a **type-aware reason code** (e.g. `image_size_exceeded` / `video_size_exceeded` / `voice_size_exceeded`) so copy can be specific. Keep `validateRawDescriptors` / `validateAttachments` delegating to it (they already do — `group_media_size_policy.dart:30-37, 61-65`).
- **Keep the relay 5 GB (`media.go:27`) as a hard backstop only** — it is not the user-facing limit. Optionally tighten the relay's per-peer byte cap later (item 4) but do not move the per-file backstop in this item.

### 2. Fold GIF into the table and validate on final bytes — *small*

- Delete the pre-compression GIF branch at `group_conversation_wired.dart:936-942`. GIF is now covered by `groupMediaPerTypeLimitBytes` (it maps to `kMaxGifFileSize`).
- Ensure the single send-time check at `group_conversation_wired.dart:1289-1300` runs against `pending.budgetBytes` (post-processing) for *all* types including GIF, and surfaces the type-aware reason through the existing **media_too_large** UX *before* upload starts. Reuse `media_gif_too_large` (already localized, `app_en.arb:382`) when the reason is the GIF cap; reuse `media_too_large_after_compress` / `media_too_large_prompt` otherwise. No new pre-compression special case.

### 3. Bounded download retries + honest terminal state — *medium*

Mirror the upload-retry pattern for downloads and split "transient failed" from "permanently unavailable / tampered."

- **New constant** in `retry_constants.dart`:
  ```dart
  /// Maximum transient download attempts before marking a blob terminal-unavailable.
  const int kMaxDownloadRetries = 3;
  ```
- **New terminal status** `download_failed` (terminal, distinct from transient `failed`) in `group_media_integrity_policy.dart` alongside the existing `kMediaDownloadStatus*` constants (lines 8-15):
  ```dart
  const String kMediaDownloadStatusDownloadFailed = 'download_failed';
  ```
- **New DB column** `download_retry_count INTEGER NOT NULL DEFAULT 0` via a new migration (see DB impact below), with a matching nullable `downloadRetryCount` field on `MediaAttachment` (mirror `uploadRetryCount` at `media_attachment.dart:48, 128, 152, 232, 257`).
- **In `download_media_use_case.dart`**, on each non-integrity failure path (`download_media_use_case.dart:237-240`, the invalid-file path 283-286, and the catch at 483-486), increment `downloadRetryCount` and flip to `download_failed` (terminal) once it reaches `kMaxDownloadRetries`; otherwise keep `failed` (retryable). On a successful download, reset the counter to 0.
- **In `group_media_integrity_policy.dart:73-76`**, make `isRetryableDownloadFailure` honest:
  - `failed` → retryable **only while** `downloadRetryCount < kMaxDownloadRetries`.
  - `download_failed` → **not** retryable (terminal).
  - `integrity_failed` (tamper) → **not** retryable unless the descriptor changes (content hash / encryption metadata differs from the quarantined row); this stops presenting tampered blobs as endlessly retryable.
  - Add `download_failed` to the `isUnavailableMedia` switch (`group_media_integrity_policy.dart:82-88`).
- **In `group_conversation_wired.dart`**, exclude `download_failed` from `_shouldRecoverVisibleAttachment` (`2440-2446`) so the screen stops auto-retrying terminal rows.
- **UI**: `media_grid_cell.dart:88-90` already keys the retry affordance off `isRetryableDownloadFailure`, so terminal rows automatically lose the retry button. Render a distinct terminal label (reuse `media_unavailable` / `media_unavailable_now`, `app_en.arb:383, 798`) in `_buildUnavailablePlaceholder` (`media_grid_cell.dart:97-103`) and the equivalent path in `audio_player_widget.dart`, clearly separate from the loading state. Add a localized "Couldn't verify this media" string for the `integrity_failed` terminal case (new l10n key across en/de/ar).
- **Optional short-circuit**: the relay already returns `"not found"` / `"not authorized"` (`media.go:396, 404`), surfaced as `errorMessage` (`p2p_bridge_client.dart:840`, `download_media_use_case.dart:245`). When `errorMessage` matches these, flip straight to `download_failed` without burning the retry budget.

### 4. Member-aware group-media retention (+ optional P2P re-fetch fallback) — *large, follows*

This is the structural fix for divergence. Two complementary pieces:

- **4a. Member-aware retention (relay).** In `media.go`, do not prune a group blob (TTL **or** per-peer cap) while any peer in `AllowedPeers` has not yet downloaded it:
  - Add a per-blob `Fetched map[string]bool` (or `[]string`) to `mediaMeta` recording which allowed peers have completed a download; populate it in `handleMediaDownload` after a successful `io.Copy` (`media.go:431-438`).
  - In `cleanupExpired` (`media.go:88-110`) and `prunePeerLocked` (`media.go:144-177`), skip group blobs (`len(AllowedPeers) > 0`) that still have un-fetched allowed peers, OR apply a longer `groupMediaTTL` to them and only hard-prune after all allowed peers fetched. Keep a sane absolute ceiling (e.g. 30 days) so a permanently-offline member cannot pin storage forever.
  - Note the per-peer index is keyed by recipient `To`, so group blobs are per-recipient copies (`media.go:136, 244-246`); retention can be evaluated per copy against that copy's intended recipient.
- **4b. Honest terminal "expired on server" state.** When the relay returns `"not found"` for a group blob the client still has a descriptor for, surface the item 3 terminal state (e.g. an `expired` reason on `download_failed`) rather than a generic failure — ties directly into item 3.
- **4c. (Stretch) P2P re-fetch fallback.** When an allowed peer needs a blob that the relay has pruned and an in-group peer still has it locally, fall back to a direct peer fetch. This requires authorizing by **group membership/topic** rather than the frozen `AllowedPeers` list — i.e. either (a) move blob-key delivery into the per-recipient encrypted descriptor and have the relay authorize group downloads by topic membership, or (b) add an `update_allowed_peers` relay action authorized by an existing allowed peer. **Make the no-pre-join-backfill policy explicit in code** (a comment/constant referencing report 89's NGM-013) so "historical media unavailable for new joiners" reads as intentional, not accidental.

> Items 4a/4b deliver most of the user-visible win (offline members stop losing still-available content) for moderate relay-side work. 4c is the only piece that touches the frozen-ACL constraint and should be gated behind an actual backfill/replay product decision.

---

## New wire / DB / migration impact

| Change | Type | Notes |
|--------|------|-------|
| `download_retry_count` column on `media_attachments` | **DB migration (new)** | New file `073_media_attachment_download_retry_column.dart`, mirroring `042` (`ALTER TABLE media_attachments ADD COLUMN download_retry_count INTEGER NOT NULL DEFAULT 0`). Bump `version: 72` → `73` and register in **both** `onCreate` (after `runMediaAttachmentReliabilityColumnsMigration`, `main.dart:330`) and `onUpgrade` with `if (oldVersion < 73)` (`main.dart:419-421`). Add `downloadRetryCount` to `MediaAttachment.fromMap/toMap/copyWith`. |
| `download_failed` status string + (item 4b) `expired` reason | App-internal | No wire change; status lives in the local DB only. |
| `mediaMeta.Fetched` + member-aware retention | **Relay struct change** | `media.go` `mediaMeta` gains a field; it is persisted only in the in-memory index (already non-durable across restarts), so no migration, but verify the Redis/memory backends in `go-relay-server/backend_*.go` if blob metadata is persisted there. |
| (Item 4c only) `update_allowed_peers` action OR descriptor-carried blob key | **Wire/protocol change** | Larger; deferred. Would touch `mediaRequest` (`media.go:250-258`), the per-recipient encrypted descriptor, and `upload_media_use_case.dart`. |
| New/updated l10n keys (type-aware too-large copy; "couldn't verify"; terminal unavailable) | l10n | Add to `app_en.arb`, `app_ar.arb`, `app_de.arb` and regenerate `app_localizations*.dart`. `mediaPreviewText()` is *not* locale-aware today, so do not route new strings through it. |

---

## Affected files & components

**Item 1–2 (size table + GIF fold):**
- `lib/core/media/group_media_size_policy.dart` — per-type table, type-aware reason codes.
- `lib/core/media/pending_composer_media.dart` — keep `kGeneralMediaAttachmentBudgetBytes` as the composer budget; stop aliasing it as the group cap.
- `lib/core/constants/media_constants.dart` — GIF cap referenced by the table.
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` — remove pre-compression GIF branch (`936-942`); type-aware too-large UX at the send-time check (`1289-1300`).

**Item 3 (bounded download retries + terminal state):**
- `lib/core/constants/retry_constants.dart` — `kMaxDownloadRetries`.
- `lib/core/media/group_media_integrity_policy.dart` — `download_failed` constant; honest `isRetryableDownloadFailure` (`73-76`); `isUnavailableMedia` (`82-88`).
- `lib/features/conversation/application/download_media_use_case.dart` — increment/reset retry count; terminal transition; optional relay-error short-circuit.
- `lib/features/conversation/domain/models/media_attachment.dart` — `downloadRetryCount` field/serde/copyWith.
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart` (+ impl) — a way to persist `downloadRetryCount` (extend `saveAttachment`/`updateDownloadStatus` usage).
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` — exclude `download_failed` from `_shouldRecoverVisibleAttachment` (`2440-2446`).
- `lib/shared/widgets/media/media_grid_cell.dart`, `lib/shared/widgets/media/audio_player_widget.dart` — terminal label vs loading state.
- `lib/core/database/migrations/073_media_attachment_download_retry_column.dart` (new) + `lib/main.dart` (version bump + registration).
- `lib/l10n/app_*.arb` + generated `app_localizations*.dart`.

**Item 4 (member-aware retention / ACL):**
- `go-relay-server/media.go` — `Fetched` tracking; member-aware `cleanupExpired` / `prunePeerLocked`; optional `update_allowed_peers`.
- `go-relay-server/backend_memory.go`, `go-relay-server/backend_redis.go` (if blob meta is persisted there).
- `lib/features/groups/application/group_media_allowed_peers.dart`, `lib/features/conversation/application/upload_media_use_case.dart`, `lib/features/conversation/application/download_media_use_case.dart` — only if 4c is pursued.

---

## Test & verification strategy

### Unit (Dart)
- **Size table:** `group_media_size_policy_test` — assert each type's cap (image ~25 MB, video ~100 MB, voice ~16 MB), total-message cap, GIF mapping, and type-aware reason codes. Boundary cases at exactly limit / limit+1.
- **GIF parity:** assert a GIF is validated on `pending.budgetBytes` (post-compression) and shares the same `validateSize` path as other media (no separate pre-compression branch).
- **Retry/terminal logic:** `group_media_integrity_policy_test` — `isRetryableDownloadFailure` returns true for `failed` only below `kMaxDownloadRetries`, false at/over the ceiling, false for `download_failed`, false for `integrity_failed` unless descriptor changes; `isUnavailableMedia` includes `download_failed`.
- **Download use case:** `download_media_use_case_test` — counter increments on each failure, flips to `download_failed` at the ceiling, resets on success, and short-circuits to terminal on relay `"not found"` / `"not authorized"`.
- **Migration:** `073_..._test` — idempotent ALTER, default 0, no-op when column exists (mirror the 042 test).

### Unit (Go, relay)
- `media_test` / `group_inbox_test` style: member-aware retention — a group blob with un-fetched allowed peers survives a TTL-cleanup pass and a per-peer prune; is eligible for prune only after all allowed peers fetched or after the absolute ceiling; `Fetched` populates on successful download.

### Integration harnesses (`integration_test/`)
- **`media_message_journey_e2e_test.dart`** — extend to assert oversized sends are rejected pre-upload with the correct type-aware reason, and that no blob is uploaded on rejection.
- **`group_new_member_media_simulator_proof_test.dart`** / **`group_new_member_media_simulator_proof`** — confirm the explicit no-pre-join-backfill policy still holds (item 4c guardrail) and that terminal states render rather than spinning.
- **`benchmark_media_harness.dart`** — sanity that the smaller caps reduce fan-out time/size.
- New simulator proof for the **download-terminal** path: force repeated relay `"not found"` for a group blob and assert the UI reaches `download_failed` (no infinite retry, no perpetual spinner), distinct from `integrity_failed`.
- New simulator proof for the **TTL/prune race**: offline recipient + TTL/cap → with member-aware retention the blob survives and downloads; without it, the client lands on the honest "expired on server" terminal state (not a spinner).

### Device matrix & gates
- Real-device runs via `group_multi_device_real_harness.dart` / `group_multi_party_device_real_harness.dart` (iPhone13 `00008110-…`, Pixel6 `21071FDF600CSC`) to confirm the size gate fires before upload and terminal labels render on both platforms.
- Wire into the existing **Test-Flight-Improv** matrices: `89-group-new-member-send-receive-media-voice-coverage.md`, `90-group-media-all-recipient-coverage.md`, `24-cancel-media-upload.md`, and `102-group-image-retry-duplicate-delivery-notifications-media-ux.md` (the terminal-state work directly complements the GIRD dedup/false-error workstream). Update `02-integration-test-coverage.md` and `test-gate-definitions.md` with the new gates.

---

## Risks, trade-offs & rollout

| Risk / trade-off | Mitigation |
|------------------|------------|
| Smaller caps could reject sends users could previously make. | These are product-tuned for a *fast group chat*; rejection is surfaced clearly pre-upload with type-aware copy. Caps are single constants — tune per product decision. Relay 5 GB stays as a backstop. |
| Existing rows in a perpetual `failed` state on upgrade. | New `download_retry_count` defaults to 0, so old `failed` rows simply re-enter the bounded retry budget and converge to terminal within `kMaxDownloadRetries` opens — no data fix needed. |
| Marking `integrity_failed` non-retryable could hide a genuinely-transient corruption. | Re-allow retry when the descriptor (content hash / encryption metadata) changes, so a legitimately re-shared blob is retryable again. |
| Member-aware retention could pin relay storage for permanently-offline members. | Absolute ceiling (e.g. 30 days) on top of "keep until all fetched"; keep per-peer byte cap as a final guard. |
| Relay struct change (`Fetched`) and any `update_allowed_peers` action interop with older clients. | Items 1–3 require no wire change. Item 4a is relay-internal and backward compatible (older clients just don't read `Fetched`). Defer 4c (true protocol change) behind an explicit product decision; gate it so mixed-version groups degrade to today's behaviour. |
| New l10n strings unlocalized at first. | Add en/de/ar in the same change; do **not** route through the non-localized `mediaPreviewText()`. |

**Rollout order (low risk → high):**
1. Items 1 + 2 (size table + GIF fold) — pure client, single-constant, no migration. Ship first.
2. Item 3 (bounded download retries + terminal state) — adds migration 073 (version 72→73) and UI labels. Ship behind the same release.
3. Item 4a/4b (member-aware retention + "expired" terminal) — relay-side, backward compatible. Ship after relay deploy/soak.
4. Item 4c (ACL backfill / P2P re-fetch) — only if a backfill/replay product feature is greenlit.

---

## Effort estimate

| Item | Scope | Effort |
|------|-------|--------|
| 1. Per-type size table | Client constants + reason codes | **Small** (~0.5 day) |
| 2. GIF fold into table | Remove special case, route through table | **Small** (~0.5 day) |
| 3. Bounded download retries + terminal state | Constant + status + migration 073 + use-case + policy + UI + l10n + tests | **Medium** (~2–3 days) |
| 4a/4b. Member-aware retention + "expired" terminal | Relay struct + cleanup/prune logic + Go tests + client terminal wiring | **Large** (~3–5 days) |
| 4c. ACL backfill / P2P re-fetch (optional) | Wire/protocol change + descriptor key delivery or `update_allowed_peers` | **Large / deferred** (gate behind product decision) |

**Recommended first slice (highest leverage):** items 1 + 2 + 3 — small/medium, no protocol change, and they remove the two most visible failures (no real size gate, forever-spinning downloads). Member-aware retention (4a/4b) follows once the relay change can soak.
