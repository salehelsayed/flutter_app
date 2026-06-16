> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P1** · TDD plan for [09-P1-media-bounded-and-honest.md](./09-P1-media-bounded-and-honest.md)

---

# TDD plan — Bound media size & give media an honest terminal state

**Status: PLANNED (2026-06-16)** &nbsp;|&nbsp; Branch base: `124-harness-refactor` (HEAD `41061593`) &nbsp;|&nbsp; Scope: finding-09 Items **1 + 2 + 3** (+ Item 4b client half); Items 4a/4b-relay and 4c **deferred**

---

## 0. Verification verdict (why this plan exists)

A 13-agent verify+refute workflow (graphify-located, source-confirmed, adversarially refuted) checked all four evidence claims of finding 09 against current HEAD. **Result: the finding is FULLY UNRESOLVED** — every cited behaviour is intact in source today; both the verifier and the adversarial refuter (which attacked fix-under-different-name, call-site override, dead-path, and stale-line-masking-a-change) reached `UNRESOLVED` on all four claims. None of the proposed fix symbols (`groupMediaPerTypeLimitBytes`, `kMaxDownloadRetries`, `download_retry_count`, `download_failed`, `mediaMeta.Fetched`, `update_allowed_peers`) exist anywhere in `lib/`, `go-relay-server/`, or `test/`.

| Claim | Finding says | Current HEAD | Verdict |
|---|---|---|---|
| **A** | per-attachment + total group caps both alias 5 GB; only `image/gif`@25 MB sub-cap | `group_media_size_policy.dart:8-11` still bare aliases of `kGeneralMediaAttachmentBudgetBytes = 5 GiB` (`pending_composer_media.dart:6`); `validateSize:79-97` rejects only `>perMediaLimitBytes` + the single GIF special-case; relay `maxMediaSize=5 GB` single ceiling | **UNRESOLVED** |
| **B** | GIF gated on raw **pre-compression** bytes; everything else post-compression | pre-compression `File(path).lengthSync() > kMaxGifFileSize` branch intact, replicated across **3 live paths** (see §2) | **UNRESOLVED** |
| **C** | downloads retry forever, no ceiling, no terminal state | no `kMaxDownloadRetries`, no `download_retry_count`, no `download_failed`; plain `failed` rows re-recovered every render; `isRetryableDownloadFailure` returns true unconditionally | **UNRESOLVED** |
| **D** | 7-day TTL + member-blind per-peer prune + frozen upload-time ACL | `cleanupExpired`/`prunePeerLocked` have **zero** group/AllowedPeers awareness; `mediaMeta` has no per-recipient fetch field; no `update_allowed_peers` action; ACL set once at upload | **UNRESOLVED** |

### Corrections to the finding the implementer MUST apply (found during verification)

1. **Migration number is no longer free — BLOCKING.** The finding hard-codes new migration `077_..._download_retry_column` and "bump `version: 76 → 77`". On this branch the DB is **already at version 77** (`lib/core/database/app_database_version.dart:1`), and `077_message_relay_custody.dart` (doc-115) is taken. **Use migration `078`, bump `currentIdentityDatabaseVersion` 77 → 78.** Migrations are contiguous 001–077; 078 is the next free number. **⚠ Collision risk:** the sibling planned doc `02-P0-undecryptable-messages-self-heal-TDD-plan.md` *also* claims migration `078/v78`. Both are PLAN-ONLY — whichever lands first takes 078; the second to land must bump to **079/v79**. Re-check `app_database_version.dart` + the migrations dir at implementation time and take the actual next-free number.
2. **GIF pre-compression branch is replicated in THREE places**, not one. The finding only names the group path. All three must be reconciled or the asymmetry persists: `group_conversation_wired.dart` (~`:1089-1095`), `conversation_wired.dart` (~`:898`, 1:1), `share_batch_delivery_coordinator.dart` (~`:477-481`).
3. **`updateDownloadStatus` will NOT persist a new counter.** It is a single-column `UPDATE` (`media_attachment_repository_impl.dart:122-125` → `dbUpdateMediaDownloadStatus(id, status)`). To persist `downloadRetryCount` you MUST route through `saveAttachment` (full-row `toMap()` write at `:64-67`) via a `copyWith`, OR add a dedicated DB helper + repo method. The finding's "extend `updateDownloadStatus` usage" is wrong as written.
4. **`copyWith` has no clear-flag.** `uploadRetryCount` applies as `uploadRetryCount ?? this.uploadRetryCount` (`media_attachment.dart:277`) — there is no way to reset it to null. `downloadRetryCount` inherits this; we only need reset-to-0 (an int), which works fine, but do NOT assume you can null it back out.
5. **`toMap` includes `upload_retry_count` CONDITIONALLY** (`:172`, the only conditional key). Mirror that exact pattern for `download_retry_count`.
6. **Stale line numbers throughout the finding** (behaviour intact, lines drifted): relay size check `:331-334`→`:438-439`; per-peer count cap is **100** (`maxMediaPerPeer = maxMessagesPerPeer`, `inbox.go:26`) not 50; `media_attachment.dart:48`→`:56` (`uploadRetryCount`); `_shouldRecoverVisibleAttachment :2689-2694`→`~:3007-3013`; `media_grid_cell :88-90`→`~:114-116`; l10n `media_gif_too_large :382`→`:395`, `media_unavailable :383`→`:396`, `media_unavailable_now :798`→`:811`. **Re-confirm every line at edit time — do not trust either the finding's or this plan's line numbers blindly.**
7. **Minor over-attribution (no action, awareness):** §A frames `validateSize` as the gate proving *both* per-attachment and total are 5 GB. `validateSize` only takes `perMediaLimitBytes` (no `totalLimitBytes` param); the total cap is enforced in `validateAttachments`/`validateRawDescriptors` (`:16-17,:52-53`). Both constants are genuinely 5 GB aliases — the claim is true, the cited evidence just under-covers the total half.

### Things the finding got RIGHT (do not "fix")

- The "retry forever" headline is honest and correctly **narrowed**: `integrity_failed` is already excluded from auto-retry (`_shouldRecoverVisibleAttachment` lists only `pending`/`downloading`/`failed`; `_autoDownloadMedia` only re-runs `status=='pending'`). The live unbounded surface is **plain `failed`** rows. Keep that scoping.
- The frozen-ACL is correctly downgraded to a **latent design constraint** (no pre-join backfill is explicit product policy, NGM-013), not an active bug. The active loss is the **TTL/cap prune race for genuinely-offline existing recipients**.
- Dependency APIs the table needs are confirmed present and adequate: `MediaAttachment.mediaTypeFromMime` (`media_attachment.dart:119-124`), `GroupMediaMimePolicy.normalizeMime` (`group_media_mime_policy.dart:29-33`). The upload-retry machinery (`kMaxUploadRetries`, migration 042, `uploadRetryCount`) is a clean template to mirror.

---

## 1. Scope & rollout decision

**IN (this plan):** Items 1 + 2 + 3 — pure client work, plus the client half of Item 4b (relay `"not found"`/`"not authorized"` → terminal `download_failed` short-circuit). These deliver the two most visible failures' fixes (no realistic size gate; forever-spinning downloads) and an honest "expired on server" terminal state — **without any wire/protocol/relay change**.

**DEFERRED (separate work, gated):**
- **Item 4a + relay half of 4b** — relay-side member-aware retention (`mediaMeta.Fetched`, group-aware `cleanupExpired`/`prunePeerLocked`). Needs a relay build + EC2 deploy + soak; `mediaMeta` is in-memory + JSON sidecar only (no Redis backend for media), so no DB migration there. Higher risk, out-of-process. **Do after the client slice ships.**
- **Item 4c** — ACL backfill / P2P re-fetch. True protocol change (`update_allowed_peers` action OR descriptor-carried blob key + topic-membership authorization). **Gate behind an explicit backfill/replay product decision (OQ-3).**

**Mandatory landing order within this plan:** Phase 1 → Phase 2 (Phases 1+2 share root cause R1/R2, no migration) → Phase 3 (carries migration 078 + model + UI). Phase 3's relay-error short-circuit is the only piece of "Item 4b" that ships now.

---

## 2. Invariants (assert across phases; must never regress)

- **INV-SZ-1** A non-GIF group attachment whose **final (post-processing) bytes** exceed its per-type cap is rejected **pre-upload** with a **type-aware reason code**; no blob is uploaded on rejection.
- **INV-SZ-2** GIF is validated on the **same final-bytes path** as every other type (single code path), capped at `kMaxGifFileSize`. **No raw pre-compression `lengthSync` special-case remains** in any of the 3 sites.
- **INV-SZ-3** The relay's 5 GB `maxMediaSize` stays as a hard backstop only — this plan never raises it and never makes it the user-facing limit.
- **INV-SZ-4** `validateSize` with an explicit `perMediaLimitBytes` (test overrides, e.g. 512) keeps honoring the explicit value; the per-type table applies **only when the caller does not override**.
- **INV-DL-1** A plain `failed` download is retryable **only while** `downloadRetryCount < kMaxDownloadRetries`; at/over the ceiling it becomes terminal `download_failed` and is **excluded** from `_shouldRecoverVisibleAttachment` and from any auto-retry.
- **INV-DL-2** A successful download **resets** `downloadRetryCount` to 0.
- **INV-DL-3** `integrity_failed` (tamper) stays **non-retryable** unless the descriptor (content hash / encryption metadata) changes — never presented as endlessly retryable. (Already excluded from auto-retry; this plan only hardens the manual affordance.)
- **INV-DL-4** Relay `"not found"`/`"not authorized"` flips straight to terminal `download_failed` **without burning the retry budget** (honest "expired on server" state, client-only Item 4b).
- **INV-DL-5** `download_retry_count` defaults to **0** on existing rows after migration 078; old perpetual-`failed` rows simply enter the bounded budget and converge to terminal within `kMaxDownloadRetries` opens (no data fix needed).
- **INV-MIG** DB version becomes **78**; migration 078 is idempotent (ALTER guarded / no-op if column exists), registered in **both** `onCreate` and `onUpgrade (oldVersion < 78)`.

---

## 3. Phase plan (TDD: RED → GREEN per phase)

### Phase 1 — Per-type group-media size table (Item 1) · *small, no migration*

**Goal:** decouple group caps from the 5 GB composer budget; introduce product-tuned per-type caps + type-aware reason codes.

**RED (write first, expect fail):** in `test/core/media/group_media_size_policy_test.dart`
- `groupMediaPerTypeLimitBytes(mime)` returns: image→`kGroupMediaImageLimitBytes`, video→`kGroupMediaVideoLimitBytes`, audio→`kGroupMediaAudioLimitBytes`, `image/gif`→`kMaxGifFileSize`, unknown/`file`→`kGroupMediaFileLimitBytes`. Boundary cases at exactly limit / limit+1.
- `validateSize` (no explicit `perMediaLimitBytes`) rejects a 30 MB image → `image_size_exceeded`; a 150 MB video → `video_size_exceeded`; a 20 MB audio → `voice_size_exceeded`; accepts each at-cap.
- `validateAttachments` total-message cap rejects a set summing > `kGroupMediaTotalMessageLimitBytes` (200 MB) → `total_media_size_exceeded`.
- **INV-SZ-4 guard:** `validateSize(perMediaLimitBytes: 512, sizeBytes: 1024)` still rejects on 512 (explicit override wins, table ignored).

**GREEN:**
- `lib/core/media/group_media_size_policy.dart`: replace the two 5 GB aliases (`:8-11`) with per-type constants + a `groupMediaPerTypeLimitBytes(String? mime)` resolver (use `GroupMediaMimePolicy.normalizeMime` + `MediaAttachment.mediaTypeFromMime`). Change `validateSize` so that when the caller does **not** pass `perMediaLimitBytes`, it derives the cap from `groupMediaPerTypeLimitBytes(mime)`; return **type-aware reason codes** (`image_size_exceeded`/`video_size_exceeded`/`voice_size_exceeded`/`file_size_exceeded`) instead of bare `media_size_exceeded`. `validateAttachments`/`validateRawDescriptors` keep delegating (they already pass `perMediaLimitBytes`/`totalLimitBytes` — switch their defaults to the new total constant + per-type resolution).
- `lib/core/media/pending_composer_media.dart`: keep `kGeneralMediaAttachmentBudgetBytes` as the **composer** budget; stop letting it be the group per-attachment/total cap (the group constants now live in the size policy).
- Proposed default caps (**OQ-1 — confirm before merge**): image 25 MB, video 100 MB, audio/voice 16 MB, generic file 100 MB, **total/message 200 MB** (NOT 5 GB). Single constants, trivially tunable.

**Gate:** `group_media_size_policy_test` green; `flutter analyze` 0 new issues.

---

### Phase 2 — Fold GIF into the table & validate on final bytes (Item 2) · *small, no migration*

**Goal:** remove the raw pre-compression GIF special-case everywhere; GIF flows through the same final-bytes `validateSize` path as all media.

**RED (write first):**
- `group_media_size_policy_test`: a `image/gif` attachment is validated on its **passed `sizeBytes`** (final/budget bytes) via the resolver → `gif_size_exceeded` at >25 MB, valid at ≤25 MB — **no separate pre-compression branch**.
- Widget/wired test (extend existing `group_conversation_wired_test.dart`): selecting an oversized GIF surfaces the too-large UX **after** the single send-time `validateSize` check (on `pending.budgetBytes`), reusing `media_gif_too_large`; selecting an oversized video surfaces the type-aware reason via `media_too_large_prompt`/`media_too_large_after_compress`. Assert **no upload** is attempted on rejection (INV-SZ-1).
- Add/extend a 1:1 (`conversation_wired_test.dart`) and share-batch test asserting the GIF raw-bytes branch is gone (GIF validated on final bytes, consistent with other types).

**GREEN:**
- Delete the pre-compression GIF branch (`File(path).lengthSync()` vs `kMaxGifFileSize`, throwing `_RejectedPendingGroupMediaException` / `_showGifTooLargeMessage()`) in **all three** sites: `group_conversation_wired.dart` (~`:1089-1095`), `conversation_wired.dart` (~`:898`), `share_batch_delivery_coordinator.dart` (~`:477-481`). GIF is now covered by the table.
- Ensure the single send-time check (group ~`:1522-1525`) runs `validateSize` against `pending.budgetBytes` for **all** types including GIF, and routes the **type-aware reason** to existing UX: `media_gif_too_large` when the reason is the GIF cap, else `media_too_large_after_compress`/`media_too_large_prompt`. **No new pre-compression special-case.** Do **not** route any new copy through the non-localized `mediaPreviewText()`.
- **1:1 scope note (OQ-2):** the per-type *table* is group-scoped by design. For 1:1 + share-batch, the minimal mandated fix is **removing the GIF raw-bytes asymmetry** so GIF is validated on final bytes like other 1:1 media. Whether to extend the full per-type cap table to 1:1 is OQ-2; default = remove the asymmetry now, extend caps later if product wants 1:1 caps too.

**Gate:** size-policy + wired GIF tests green; reconfirm groups suite + 1:1 suite unaffected; 0 new analyze.

---

### Phase 3 — Bounded download retries + honest terminal state (Item 3, + client half of 4b) · *medium, migration 078*

**Goal:** mirror the upload-retry pattern for downloads; split transient `failed` from terminal `download_failed`; deliver an honest "media unavailable" terminal + an "expired on server" short-circuit.

**RED (write first):**
- `test/core/database/migrations/078_..._test.dart` (mirror the 042 test): idempotent `ALTER TABLE media_attachments ADD COLUMN download_retry_count INTEGER NOT NULL DEFAULT 0`; default 0; no-op when column already exists.
- `media_attachment_test.dart`: `downloadRetryCount` round-trips through `fromMap`/`toMap` (conditional include, mirroring `upload_retry_count`) and `copyWith`.
- `group_media_integrity_policy_test.dart`: `isRetryableDownloadFailure` returns true for `failed` **only while** `downloadRetryCount < kMaxDownloadRetries`, false at/over ceiling, false for `download_failed`, false for `integrity_failed` (unless descriptor changed); `isUnavailableMedia` **includes** `download_failed`.
- `download_media_use_case_test.dart`: counter increments on each transient failure; flips to `download_failed` at the ceiling; resets to 0 on success; relay `"not found"`/`"not authorized"` short-circuits straight to `download_failed` without consuming the budget (INV-DL-4); persistence goes through `saveAttachment` (full-row), NOT `updateDownloadStatus` (correction #3).
- Widget tests (`media_grid_cell` + `audio_player_widget`): a `download_failed` row renders a **terminal** label (reuse `media_unavailable`/`media_unavailable_now`) with **no retry affordance**; a `failed` row under the ceiling still shows the retry affordance; an `integrity_failed` row renders a new "Couldn't verify this media" terminal label.
- Wired test: `_shouldRecoverVisibleAttachment` does **not** re-recover `download_failed` rows (INV-DL-1).

**GREEN:**
- `lib/core/constants/retry_constants.dart`: `const int kMaxDownloadRetries = 3;`
- `lib/core/media/group_media_integrity_policy.dart`: add `kMediaDownloadStatusDownloadFailed = 'download_failed'`; make `isRetryableDownloadFailure(status, {int downloadRetryCount = 0})` honest per INV-DL-1/3; add `download_failed` to `isUnavailableMedia`.
- `lib/core/database/migrations/078_media_attachment_download_retry_column.dart` (new, mirror 042) + `app_database_version.dart` 77→**78** + register in `main.dart` `onCreate` (after the existing media-attachment migrations) and `onUpgrade` `if (oldVersion < 78) { await run...Migration(db); }`.
- `lib/features/conversation/domain/models/media_attachment.dart`: add `final int? downloadRetryCount;` (field + ctor); read `map['download_retry_count'] as int?` in `fromMap`; **conditional** write in `toMap` (mirror `:172`); add to `copyWith`. (`fromJson` does NOT parse it — matches `uploadRetryCount`; counters are DB-local, never wire.)
- `lib/features/conversation/application/download_media_use_case.dart`: on each non-integrity failure write (the ~7 sites: `:535-537`, invalid-file path, catch, etc.), `copyWith(downloadRetryCount: (current ?? 0) + 1)` then persist via `saveAttachment`; flip to `download_failed` once `>= kMaxDownloadRetries`; on success reset to 0; short-circuit to `download_failed` on relay `"not found"`/`"not authorized"` (surfaced via `errorMessage`).
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`: exclude `download_failed` from `_shouldRecoverVisibleAttachment` (~`:3007-3013`).
- `lib/shared/widgets/media/media_grid_cell.dart` (~`:114-116`, `_buildUnavailablePlaceholder` ~`:142`) + `lib/shared/widgets/media/audio_player_widget.dart`: render terminal label vs loading state; the retry affordance already keys off `isRetryableDownloadFailure` so terminal rows auto-lose it.
- **l10n:** existing keys `media_unavailable`/`media_unavailable_now`/`media_gif_too_large` are present with **ar+de parity** — reuse them. Add **new** keys for: the type-aware too-large variants if Phase 1/2 needs distinct copy beyond `media_too_large_prompt` (likely reuse is enough), and a **new** `media_could_not_verify` ("Couldn't verify this media") for the `integrity_failed` terminal — add to `app_en.arb` + `app_ar.arb` + `app_de.arb` and regenerate `app_localizations*.dart`. Do **not** route through `mediaPreviewText()`.

**Gate:** all Phase-3 unit + widget + migration tests green; full groups suite (`-j 1`) + 1:1 suite green; `flutter analyze` 0 new issues; integration `media_message_journey_e2e_test.dart` extended for oversized-reject (no upload) + a new download-terminal simulator proof (force repeated relay `"not found"` → `download_failed`, no infinite retry, distinct from `integrity_failed`).

---

## 4. New wire / DB / migration impact

| Change | Type | Notes |
|---|---|---|
| `download_retry_count INTEGER NOT NULL DEFAULT 0` on `media_attachments` | **DB migration 078** (NOT 077) | New `078_media_attachment_download_retry_column.dart`, mirror 042. `currentIdentityDatabaseVersion` 77→**78**. Register in `onCreate` + `onUpgrade (oldVersion < 78)`. |
| `download_failed` status string | App-internal | Local DB only; no wire change. |
| Per-type size constants + type-aware reason codes | App-internal | No wire change. |
| `media_could_not_verify` (+ any new type-aware copy) | l10n | en/ar/de + regenerate. Reuse existing `media_unavailable*`/`media_gif_too_large`/`media_too_large_*` where possible. |
| `mediaMeta.Fetched` + member-aware retention | **Relay (DEFERRED 4a/4b)** | In-memory + JSON sidecar only; no Redis media backend; no migration. Separate deploy/soak. |
| `update_allowed_peers` / descriptor-carried key | **Wire/protocol (DEFERRED 4c)** | Product-gated (OQ-3). |

---

## 5. Test & device gates

- **Unit (Dart):** `group_media_size_policy_test`, `group_media_integrity_policy_test`, `download_media_use_case_test`, `media_attachment_test`, `078_..._test`.
- **Widget:** `media_grid_cell` / `audio_player_widget` terminal-vs-loading; `group_conversation_wired_test` / `conversation_wired_test` GIF-fold + oversized-reject (no upload).
- **Integration (`integration_test/`):** extend `media_message_journey_e2e_test.dart` (oversized reject pre-upload, type-aware reason, no blob uploaded); new download-terminal simulator proof.
- **Device matrix:** `group_multi_device_real_harness.dart` (iPhone13 `00008110-…`, Pixel6 `21071FDF600CSC`) — confirm the size gate fires **before** upload and the terminal label renders on both platforms (vs a perpetual spinner).
- **Doc wiring:** update `02-integration-test-coverage.md` and `test-gate-definitions.md` with the new gates; cross-reference matrices `89-`, `90-`, `24-`, `102-`.

---

## 6. Risks & rollout

| Risk | Mitigation |
|---|---|
| Smaller caps reject sends users could previously make | Product-tuned for fast group chat; rejection surfaced pre-upload with type-aware copy; caps are single constants (OQ-1); relay 5 GB stays as backstop. |
| Existing perpetual-`failed` rows on upgrade | `download_retry_count` defaults 0 → re-enter bounded budget, converge within `kMaxDownloadRetries` opens (INV-DL-5). |
| Marking `integrity_failed` non-retryable hides a transient corruption | Re-allow retry when descriptor (content hash / enc metadata) changes (INV-DL-3). |
| Persisting counter via wrong API silently drops it | Mandated `saveAttachment` full-row path (correction #3); test asserts persistence. |
| 1:1 / share-batch GIF asymmetry left behind | Phase 2 mandates removing all 3 raw-bytes branches (correction #2). |

**Rollout:** Phase 1 + 2 (pure client, no migration) → Phase 3 (migration 078 + UI + l10n) in the same release. Relay-side 4a/4b after deploy/soak. 4c only if backfill/replay is greenlit.

---

## 7. Open questions (resolve before/at implementation)

- **OQ-1 (size caps):** confirm the proposed defaults — image 25 MB, video 100 MB, audio/voice 16 MB, file 100 MB, total/message 200 MB. These are the one genuine product decision; everything else is mechanical.
- **OQ-2 (1:1 scope):** Phase 2 removes the GIF pre-compression asymmetry on the 1:1 + share-batch paths. Do we also extend the full per-type cap table to 1:1, or leave 1:1 on its current (no per-type) policy and only de-special-case GIF? Default = de-special-case GIF now, extend caps later.
- **OQ-3 (4c product gate):** ACL backfill / P2P re-fetch is a real protocol change. Greenlight needed before any work — and it only matters if a backfill/replay/quote-of-old-media feature is on the roadmap (NGM-013 says no pre-join backfill today).
- **OQ-4 (relay per-peer byte cap):** finding suggests optionally tightening the relay's 5 GB per-peer byte cap later. Out of scope here; revisit with 4a.
