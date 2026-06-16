> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P1** · TDD plan for [09-P1-media-bounded-and-honest.md](./09-P1-media-bounded-and-honest.md)

---

# TDD plan — Bound media size & give media an honest terminal state

**Status: PLANNED — re-verified against the current working tree (2026-06-16)** &nbsp;|&nbsp; Branch base: `124-harness-refactor` (HEAD `3b657723`) &nbsp;|&nbsp; Scope: finding-09 Items **1 + 2 + 3** (+ Item 4b client half); Items 4a/4b-relay and 4c **deferred**

> **Re-verification note (2026-06-16):** the working tree was re-checked symbol-by-symbol against this plan. All four finding claims remain **UNRESOLVED** (the bugs are still live), but the surrounding code has drifted under heavy concurrent work and the migration landscape has moved. In particular the tree now carries **uncommitted concurrent migrations 078–083** (key-distribution, dedup-key, repairs-index, pending-reactions, reaction-tombstone, last-membership-event-id), the DB is at **version 83**, and a **total-message size-cap constant already exists** (as a 5 GiB no-op). The migration number and several line anchors/symbol facts below were corrected accordingly — see §0 corrections #1, #2, #6, #8, #9.

---

## 0. Verification verdict (why this plan exists)

A 13-agent verify+refute workflow (graphify-located, source-confirmed, adversarially refuted) checked all four evidence claims of finding 09, and was re-run against the current working tree on 2026-06-16. **Result: the finding is FULLY UNRESOLVED** — every cited behaviour is intact in source today; both the verifier and the adversarial refuter (which attacked fix-under-different-name, call-site override, dead-path, and stale-line-masking-a-change) reached `UNRESOLVED` on all four claims. The proposed *fix* symbols (`groupMediaPerTypeLimitBytes`, `kMaxDownloadRetries`, `download_retry_count`, `downloadRetryCount`, `mediaMeta.Fetched`, `update_allowed_peers`) are still ABSENT everywhere in `lib/`, `go-relay-server/`, or `test/`. **Two important exceptions surfaced on re-verification** (see corrections #8 and #9): the per-message **total-size cap constant already exists** (as a 5 GiB alias, still a no-op), and the substring **`download_failed` is NOT greenfield** (it already exists as a Go bridge event name + a flow-event reason — the new *status* constant must stay namespace-distinct).

| Claim | Finding says | Current working tree | Verdict |
|---|---|---|---|
| **A** | per-attachment + total group caps both alias 5 GB; only `image/gif`@25 MB sub-cap | `group_media_size_policy.dart` — per-attachment alias `:8-9` AND **a now-existing total-message alias `:10-11`** both equal `kGeneralMediaAttachmentBudgetBytes = 5 GiB` (`pending_composer_media.dart:6`); `validateSize:79-97` rejects only `>perMediaLimitBytes` + the single GIF special-case (`:92`); total-cap reject already wired in `validateRawDescriptors:40-44` / `validateAttachments:69-73`; relay `maxMediaSize=5 GB` single ceiling (`media.go:27`) | **UNRESOLVED** (caps still 5 GiB no-ops; total-cap *scaffold* already present — see #8) |
| **B** | GIF gated on raw **pre-compression** bytes; everything else post-compression | pre-compression `File(path).lengthSync() > kMaxGifFileSize` branch intact, replicated across **3 live paths** (see §2) | **UNRESOLVED** |
| **C** | downloads retry forever, no ceiling, no terminal state | no `kMaxDownloadRetries`, no `download_retry_count`, no `downloadRetryCount`, no `download_failed` *status*; plain `failed` rows re-recovered every render; `isRetryableDownloadFailure(attachment)` (`group_media_integrity_policy.dart:73-76`) returns true for **both `failed` AND `integrity_failed`** with **no counter** gating either | **UNRESOLVED** |
| **D** | 7-day TTL + member-blind per-peer prune + frozen upload-time ACL | all in `go-relay-server/media.go` (NOT `inbox.go`): `cleanupExpired:94`/`prunePeerLocked:160` have **zero** group/AllowedPeers awareness; `mediaMeta:38-45` has no per-recipient fetch field; no `update_allowed_peers` action (`action` switch `:411-427`); ACL set once at upload (`:486-493`) | **UNRESOLVED** |

### Corrections to the finding the implementer MUST apply (found during verification)

1. **Migration number — re-checked and moved (BLOCKING).** The finding hard-codes new migration `077_..._download_retry_column` and "bump `version: 76 → 77`". The DB-version situation was re-checked on 2026-06-16: `lib/core/database/app_database_version.dart` has **`currentIdentityDatabaseVersion = 83`**, and migrations **078–083 are ALL consumed** by concurrent uncommitted work — `078_group_pending_key_distributions`, `079_message_dedup_key`, `080_group_pending_key_repairs_status_index`, `081_group_pending_reactions`, `082_message_reaction_tombstone`, `083_groups_last_membership_event_id` (test files for each are present under `test/core/database/migrations/`). **Use migration `084`, bump `currentIdentityDatabaseVersion` 83 → 84.** The original "collision with self-heal at 078" framing is **OBSOLETE** — those collisions already resolved themselves (self-heal landed 080; reaction work took 081/082). The next-free number is confirmed **084** as of 2026-06-16; still **re-check `app_database_version.dart` + the migrations dir at implementation time** and take the actual next-free number if more concurrent work lands first.
2. **GIF pre-compression branch is replicated in THREE places**, not one — and they are NOT symmetric. All three must be reconciled or the asymmetry persists:
   - **Group** — `group_conversation_wired.dart:1089-1095`: `_mimeFromPath=='image/gif'` → `File(path).lengthSync() > kMaxGifFileSize` → `_showGifTooLargeMessage()` (`:1134-1142`) + `throw const _RejectedPendingGroupMediaException()` (defined `:84-85`).
   - **1:1** — `conversation_wired.dart:907-913` (NOT `:898` — that line is now an unrelated SnackBar tail): same raw-bytes branch, but throws **`_RejectedPendingMediaException`** (the 1:1-specific exception, NOT the group's) + `_showGifTooLargeMessage()` (`:952-960`).
   - **Share** — `share_batch_delivery_coordinator.dart`: factored into a top-level helper **`bool _isOversizedGif(String path, File file)`** (`:477-482`, predicate `file.lengthSync() > kMaxGifFileSize` at `:481`), called from `_processSharedMedia` at `:234` (happy path) and `:251` (catch fallback). This site **throws nothing and shows no SnackBar** — it does `skippedOversizedGifCount++ + continue` and surfaces a **batch-level** message ("GIF files over 25 MB were skipped.", `:264-265`). The finding's "throw / `_showGifTooLargeMessage`" framing never matched the share site.
3. **`updateDownloadStatus` will NOT persist a new counter.** It is a single-column `UPDATE` (**`lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart:122-125`** → `dbUpdateMediaDownloadStatus(id, status)`). **Note the path:** the repo lives under **`domain/repositories/`**, not `data/repositories/`. To persist `downloadRetryCount` you MUST route through `saveAttachment` (full-row `_toStorageRow(...) → toMap()` write; insert at `:67`, `_toStorageRow` at `:238`) via a `copyWith`, OR add a dedicated DB helper + repo method. The finding's "extend `updateDownloadStatus` usage" is wrong as written.
4. **`copyWith` has no clear-flag.** `uploadRetryCount` applies as `uploadRetryCount ?? this.uploadRetryCount` (`media_attachment.dart:277`) — there is no way to reset it to null. `downloadRetryCount` inherits this; we only need reset-to-0 (an int), which works fine, but do NOT assume you can null it back out.
5. **`toMap` includes `upload_retry_count` CONDITIONALLY** (`media_attachment.dart:172`, the only conditional key). Mirror that exact pattern for `download_retry_count`.
6. **Stale line numbers / file paths throughout the finding** (behaviour intact, lines/files drifted):
   - Relay size check `:331-334`→**`media.go:438-439`** (the size check is in `media.go`, NOT `inbox.go`).
   - Per-peer count cap is **100** (`maxMediaPerPeer = maxMessagesPerPeer`): the alias `maxMediaPerPeer` lives at **`media.go:20`**, sourced from `maxMessagesPerPeer = 100` at **`inbox.go:27`**. NOT 50. (`inbox.go` is the *only* relay-media-relevant symbol; everything else — `cleanupExpired`, `prunePeerLocked`, `mediaMeta`, `maxMediaSize` — is in `media.go`.)
   - `media_attachment.dart:48`→**`:56`** (`uploadRetryCount`); `toMap` conditional include **`:172`**; `copyWith` assign **`:277`**.
   - `_shouldRecoverVisibleAttachment :2689-2694`→**`group_conversation_wired.dart:3007-3013`** (caller at `:3053`).
   - `media_grid_cell :88-90`→ `isUnavailableMedia` **`:89`**, `isRetryableDownloadFailure` **`:116`**, `_buildUnavailablePlaceholder` **`:227`**, `l10n.media_unavailable` rendered **`:244`**.
   - l10n: `media_gif_too_large :382`→**`:395`**, `media_unavailable :383`→**`:396`**, `media_unavailable_now :798`→**`:815`** (the finding's `:811` is also stale by +4; en/ar/de all parity at `:815`). `media_too_large_prompt` at `:382` (with `@`-metadata `:383-392`), `media_too_large_after_compress` at `:394`. Generated getters are **snake_case** (`media_unavailable`, `media_unavailable_now`) — the new key will generate as `media_could_not_verify`, NOT `mediaCouldNotVerify`.
   - **Re-confirm every line at edit time — do not trust either the finding's or this plan's line numbers blindly.**
7. **Minor over-attribution (no action, awareness):** §A frames `validateSize` as the gate proving *both* per-attachment and total are 5 GB. `validateSize` only takes `perMediaLimitBytes` (no `totalLimitBytes` param, default `kGroupMediaPerAttachmentLimitBytes` at `:82`); the total cap is enforced in `validateAttachments` (`:69-73`, default param `totalLimitBytes` at `:53`) / `validateRawDescriptors` (`:40-44`, default param at `:17`). Both constants are genuinely 5 GB aliases — the claim is true, the cited evidence just under-covers the total half.
8. **SCOPE CHANGE — the total-message cap already EXISTS (as a 5 GiB no-op).** ⚠️ On re-verification, **`kGroupMediaTotalMessageLimitBytes` already exists** at `group_media_size_policy.dart:10-11` (a bare alias of `kGeneralMediaAttachmentBudgetBytes = 5 GiB`), **and its reject path is already wired** in `validateAttachments:69-73` (reason `total_media_size_exceeded`) and `validateRawDescriptors:40-44`. It is still effectively uncapped, so Claim A is NOT invalidated — but the plan must **REPLACE the alias value** (and switch the default params to the new total constant), NOT introduce the constant or build the reject path from scratch. The constant is already **referenced by 3 group test files** (`retry_incomplete_group_uploads_use_case_test.dart:1136`, `send_group_message_use_case_test.dart:4323`, `handle_incoming_group_message_use_case_test.dart:2873`) — those tests must be reconciled when the value changes. The proposed **per-TYPE** symbols (`groupMediaPerTypeLimitBytes`, `kGroupMediaImageLimitBytes`, `kGroupMediaVideoLimitBytes`, `kGroupMediaAudioLimitBytes`, `kGroupMediaFileLimitBytes`) remain genuinely net-new (0 hits in `lib/`/`test/`).
9. **SCOPE NOTE — `download_failed` is NOT greenfield.** ⚠️ The substring `download_failed` already exists as **(a)** the Go bridge **event name** `'media:download_failed'` (`go_bridge_client.dart:45,675`, callback registration + switch case) and **(b)** a **flow-event reason** (`download_media_use_case.dart:1479`, `reportPreservedDownloadArtifacts(reason: 'download_failed')`). These are different namespaces, but the new DB **status** constant `kMediaDownloadStatusDownloadFailed = 'download_failed'` collides on the literal — keep the status constant distinct from the bridge event and verify no string-equality test conflates them.

### Things the finding got RIGHT (do not "fix")

- The "retry forever" headline is honest. The live unbounded surface is **plain `failed`** rows, re-recovered on every render via `_shouldRecoverVisibleAttachment` (which lists `pending`/`downloading`/`failed`, `group_conversation_wired.dart:3009-3011`). **Correction to the finding's narrowing:** `integrity_failed` is **NOT** currently excluded from `isRetryableDownloadFailure` — that predicate (`group_media_integrity_policy.dart:73-76`) returns true for **both** `failed` AND `integrity_failed`, with no counter gating either. (`_shouldRecoverVisibleAttachment`/`_autoDownloadMedia` happen not to re-arm `integrity_failed` rows, so the *auto*-loop is narrower — but the retry *predicate* itself is not.) The rewritten predicate (§3 Phase 3) must therefore both add the counter to gate `failed` AND explicitly keep `integrity_failed` non-retryable.
- The frozen-ACL is correctly downgraded to a **latent design constraint** (no pre-join backfill is explicit product policy, NGM-013), not an active bug. The active loss is the **TTL/cap prune race for genuinely-offline existing recipients** (`media.go` `cleanupExpired:94` / `prunePeerLocked:160`, both member-blind).
- Dependency APIs the table needs are confirmed present and adequate: `MediaAttachment.mediaTypeFromMime` (`media_attachment.dart:119-124`), `GroupMediaMimePolicy.normalizeMime` (`group_media_mime_policy.dart:29-33`). The upload-retry machinery (`kMaxUploadRetries` at `retry_constants.dart:7`, migration 042, `uploadRetryCount`) is a clean template to mirror.

---

## 1. Scope & rollout decision

**IN (this plan):** Items 1 + 2 + 3 — pure client work, plus the client half of Item 4b (relay `"not found"`/`"not authorized"` → terminal `download_failed` short-circuit). These deliver the two most visible failures' fixes (no realistic size gate; forever-spinning downloads) and an honest "expired on server" terminal state — **without any wire/protocol/relay change**.

**DEFERRED (separate work, gated):**
- **Item 4a + relay half of 4b** — relay-side member-aware retention (`mediaMeta.Fetched`, group-aware `cleanupExpired`/`prunePeerLocked`). All in **`go-relay-server/media.go`** (NOT `inbox.go`). Needs a relay build + EC2 deploy + soak; `mediaMeta` is in-memory + JSON sidecar only (no Redis backend for media), so no DB migration there. Higher risk, out-of-process. **Do after the client slice ships.**
- **Item 4c** — ACL backfill / P2P re-fetch. True protocol change (`update_allowed_peers` action OR descriptor-carried blob key + topic-membership authorization). **Gate behind an explicit backfill/replay product decision (OQ-3).**

**Mandatory landing order within this plan:** Phase 1 → Phase 2 (Phases 1+2 share root cause R1/R2, no migration) → Phase 3 (carries migration 084 + model + UI). Phase 3's relay-error short-circuit is the only piece of "Item 4b" that ships now.

---

## 2. Invariants (assert across phases; must never regress)

- **INV-SZ-1** A non-GIF group attachment whose **final (post-processing) bytes** exceed its per-type cap is rejected **pre-upload** with a **type-aware reason code**; no blob is uploaded on rejection.
- **INV-SZ-2** GIF is validated on the **same final-bytes path** as every other type (single code path), capped at `kMaxGifFileSize`. **No raw pre-compression `lengthSync` special-case remains** in any of the 3 sites.
- **INV-SZ-3** The relay's 5 GB `maxMediaSize` (`media.go:27`, check `:438-439`) stays as a hard backstop only — this plan never raises it and never makes it the user-facing limit.
- **INV-SZ-4** `validateSize` with an explicit `perMediaLimitBytes` (test overrides, e.g. 512) keeps honoring the explicit value; the per-type table applies **only when the caller does not override**.
- **INV-DL-1** A plain `failed` download is retryable **only while** `downloadRetryCount < kMaxDownloadRetries`; at/over the ceiling it becomes terminal `download_failed` and is **excluded** from `_shouldRecoverVisibleAttachment` and from any auto-retry.
- **INV-DL-2** A successful download **resets** `downloadRetryCount` to 0.
- **INV-DL-3** `integrity_failed` (tamper) stays **non-retryable** unless the descriptor (content hash / encryption metadata) changes — never presented as endlessly retryable. (The rewritten `isRetryableDownloadFailure` must keep `integrity_failed` false; today it returns true for it — see correction in §0.)
- **INV-DL-4** Relay `"not found"`/`"not authorized"` flips straight to terminal `download_failed` **without burning the retry budget** (honest "expired on server" state, client-only Item 4b). Depends on the relay error strings at `media.go:518` (`"not found"`) and `:526`/`:531` (`"not authorized"`), which are present.
- **INV-DL-5** `download_retry_count` defaults to **0** on existing rows after migration 084; old perpetual-`failed` rows simply enter the bounded budget and converge to terminal within `kMaxDownloadRetries` opens (no data fix needed).
- **INV-MIG** DB version becomes **84**; migration 084 is idempotent (ALTER guarded / no-op if column exists), registered in **both** `onCreate` and `onUpgrade (oldVersion < 84)`.

---

## 3. Phase plan (TDD: RED → GREEN per phase)

### Phase 1 — Per-type group-media size table (Item 1) · *small, no migration*

**Goal:** decouple group caps from the 5 GB composer budget; introduce product-tuned per-type caps + type-aware reason codes. **Note (correction #8):** the total-message cap constant + its reject path already exist as a 5 GiB no-op — this phase **replaces the alias value**, it does not introduce the constant.

**RED (write first, expect fail):** in `test/core/media/group_media_size_policy_test.dart` (existing, mirror its `validateAttachments`/`validateRawDescriptors` style)
- `groupMediaPerTypeLimitBytes(mime)` returns: image→`kGroupMediaImageLimitBytes`, video→`kGroupMediaVideoLimitBytes`, audio→`kGroupMediaAudioLimitBytes`, `image/gif`→`kMaxGifFileSize`, unknown/`file`→`kGroupMediaFileLimitBytes`. Boundary cases at exactly limit / limit+1.
- `validateSize` (no explicit `perMediaLimitBytes`) rejects a 30 MB image → `image_size_exceeded`; a 150 MB video → `video_size_exceeded`; a 20 MB audio → `voice_size_exceeded`; accepts each at-cap.
- `validateAttachments` total-message cap rejects a set summing > `kGroupMediaTotalMessageLimitBytes` (now 200 MB, was a 5 GiB no-op) → `total_media_size_exceeded` (the reject path at `:69-73` already exists; this test pins the *new value*).
- **INV-SZ-4 guard:** `validateSize(perMediaLimitBytes: 512, sizeBytes: 1024)` still rejects on 512 (explicit override wins, table ignored).

**GREEN:**
- `lib/core/media/group_media_size_policy.dart`:
  - Replace the per-attachment alias (`:8-9`) **and the existing total alias (`:10-11`)** (both currently `= kGeneralMediaAttachmentBudgetBytes`) with real per-type constants + a `groupMediaPerTypeLimitBytes(String? mime)` resolver (use `GroupMediaMimePolicy.normalizeMime` + `MediaAttachment.mediaTypeFromMime`).
  - Change `validateSize` so that when the caller does **not** pass `perMediaLimitBytes`, it derives the cap from `groupMediaPerTypeLimitBytes(mime)`; return **type-aware reason codes** (`image_size_exceeded`/`video_size_exceeded`/`voice_size_exceeded`/`file_size_exceeded`) instead of bare `media_size_exceeded`. Keep the GIF clamp at `:92`.
  - `validateAttachments` (`:69-73`) / `validateRawDescriptors` (`:40-44`) already enforce the total cap and per-media cap — only switch their **default params** (`perMediaLimitBytes` at `:16`/`:52`, `totalLimitBytes` at `:17`/`:53`) to the new total constant + per-type resolution; do NOT rebuild the reject logic.
- `lib/core/media/pending_composer_media.dart`: keep `kGeneralMediaAttachmentBudgetBytes` (`:6`) as the **composer** budget; stop letting it be the group per-attachment/total cap (the group constants now live in the size policy).
- **Reconcile the 3 existing tests** referencing `kGroupMediaTotalMessageLimitBytes` (`retry_incomplete_group_uploads_use_case_test.dart:1136`, `send_group_message_use_case_test.dart:4323`, `handle_incoming_group_message_use_case_test.dart:2873`) — their expectations change when the alias stops being 5 GiB.
- Proposed default caps (**OQ-1 — confirm before merge**): image 25 MB, video 100 MB, audio/voice 16 MB, generic file 100 MB, **total/message 200 MB** (NOT 5 GB). Single constants, trivially tunable.

**Gate (host-runnable proof, mandatory — not just device):**
- `group_media_size_policy_test` green; `flutter analyze` 0 new issues; the 3 reconciled group tests above pass.
- **Host sim proof (composer pre-upload reject):** extend the existing composer cases in `test/features/groups/presentation/group_conversation_wired_test.dart` ("oversized gallery attachment compresses under budget" `:1185` / "remains over budget after compression leaves no pending state" `:1291`) so that an **oversized non-GIF** attachment (e.g. a 150 MB video via `PendingComposerMedia(budgetBytes:)`) is **rejected pre-upload with the type-aware reason** and **NO blob is uploaded** — assert the send/upload call count is `0` and no pending media row is left (INV-SZ-1). This runs host-side; no device required.

---

### Phase 2 — Fold GIF into the table & validate on final bytes (Item 2) · *small, no migration*

**Goal:** remove the raw pre-compression GIF special-case everywhere; GIF flows through the same final-bytes `validateSize` path as all media.

**RED (write first):**
- `group_media_size_policy_test`: a `image/gif` attachment is validated on its **passed `sizeBytes`** (final/budget bytes) via the resolver → `gif_size_exceeded` at >25 MB, valid at ≤25 MB — **no separate pre-compression branch**.
- Widget/wired test (extend existing `group_conversation_wired_test.dart`): selecting an oversized GIF surfaces the too-large UX **after** the single send-time `validateSize` check (on `pending.budgetBytes`), reusing `media_gif_too_large`; selecting an oversized video surfaces the type-aware reason via `media_too_large_prompt`/`media_too_large_after_compress`. Assert **no upload** is attempted on rejection (INV-SZ-1).
- Add/extend a 1:1 (`conversation_wired_test.dart`) and share-batch test asserting the GIF raw-bytes branch is gone (GIF validated on final bytes, consistent with other types).

**GREEN:**
- Delete the pre-compression GIF branch (`File(path).lengthSync()` vs `kMaxGifFileSize`) in **all three** sites, respecting their different shapes (correction #2):
  - **Group** `group_conversation_wired.dart:1089-1095` — removes the `throw const _RejectedPendingGroupMediaException()` + `_showGifTooLargeMessage()` branch.
  - **1:1** `conversation_wired.dart:907-913` — removes the branch that throws **`_RejectedPendingMediaException`** (the 1:1 exception, NOT the group one) + `_showGifTooLargeMessage()` (`:952-960`).
  - **Share** `share_batch_delivery_coordinator.dart` — removes the `_isOversizedGif` helper (`:477-482`) and its two call sites (`:234`, `:251`); GIF now flows through the same final-bytes validation as other share media. (This site never threw / never called `_showGifTooLargeMessage` — it did `skippedOversizedGifCount++ + continue`; keep that skip semantic if product still wants a per-file skip, but base it on the unified `validateSize`, not raw `lengthSync`.)
- Ensure the single send-time check runs `validateSize` against `pending.budgetBytes` for **all** types including GIF, and routes the **type-aware reason** to existing UX: `media_gif_too_large` when the reason is the GIF cap, else `media_too_large_after_compress`/`media_too_large_prompt`. **Reconcile BOTH group send-time `validateSize` call sites** — `group_conversation_wired.dart:1522-1525` (reject `:1532`) **and** `:3589` (reject `:3603`, retry/durable path); consolidating to a "single" send-time policy authority must cover both. **No new pre-compression special-case.** Do **not** route any new copy through the non-localized `mediaPreviewText()` (`media_preview_text.dart:9`, hard-coded English).
- **1:1 scope note (OQ-2):** the per-type *table* is group-scoped by design. For 1:1 + share-batch, the minimal mandated fix is **removing the GIF raw-bytes asymmetry** so GIF is validated on final bytes like other 1:1 media. Whether to extend the full per-type cap table to 1:1 is OQ-2; default = remove the asymmetry now, extend caps later if product wants 1:1 caps too.

**Gate (host-runnable proof, mandatory):**
- size-policy + wired GIF tests green; reconfirm groups suite + 1:1 suite unaffected; 0 new analyze.
- **Host sim proof (GIF final-bytes + no upload):** in `group_conversation_wired_test.dart` and `conversation_wired_test.dart`, assert an oversized GIF is rejected on its **final `pending.budgetBytes`** by the single `validateSize` gate (no pre-compression `lengthSync` path), and **upload call count == 0** on rejection. PLUS extend `integration_test/media_message_journey_e2e_test.dart` (host-runnable: `IntegrationTestWidgetsFlutterBinding` + `FakeBridge`/`FakeP2PService`/`FakeGroupPubSubNetwork`; extension seam `_JourneyHarness.create()` `:326`, picker `FakeMediaPicker`) with an **oversized-attachment → no blob uploaded** scenario driving the real `GroupConversationWired`/`ConversationWired` widgets — assert the fake bridge records **zero `media:upload`** calls.

---

### Phase 3 — Bounded download retries + honest terminal state (Item 3, + client half of 4b) · *medium, migration 084*

**Goal:** mirror the upload-retry pattern for downloads; split transient `failed` from terminal `download_failed`; deliver an honest "media unavailable" terminal + an "expired on server" short-circuit.

**RED (write first):**
- `test/core/database/migrations/084_..._test.dart` (mirror the tiny `042_media_attachment_reliability_columns_test.dart`): idempotent `ALTER TABLE media_attachments ADD COLUMN download_retry_count INTEGER NOT NULL DEFAULT 0`; default 0; no-op when column already exists (`sqfliteFfiInit` + run prior media migrations + `PRAGMA table_info` assert column present + default 0).
- `media_attachment_test.dart`: `downloadRetryCount` round-trips through `fromMap`/`toMap` (conditional include, mirroring `upload_retry_count` at `:172`) and `copyWith`. (Note: `upload_retry_count` round-trip is NOT currently asserted in this file, so this is net-new, not a copy.)
- `group_media_integrity_policy_test.dart`: `isRetryableDownloadFailure(attachment, {downloadRetryCount})` returns true for `failed` **only while** `downloadRetryCount < kMaxDownloadRetries`, false at/over ceiling, false for `download_failed`, **false for `integrity_failed`** (today it returns true for `integrity_failed` — this RED test pins the corrected behaviour, INV-DL-3); `isUnavailableMedia` **includes** `download_failed`.
- `download_media_use_case_test.dart`: counter increments on each transient failure; flips to `download_failed` at the ceiling; resets to 0 on success; relay `"not found"`/`"not authorized"` short-circuits straight to `download_failed` without consuming the budget (INV-DL-4); persistence goes through `saveAttachment` (full-row), NOT `updateDownloadStatus` (correction #3). (The existing test "group policy rejects oversized declared attachment before media download" `:1200-1227` already proves `sendCallCount==0` on oversized-declared — extend, don't duplicate.)
- Widget tests (`media_grid_cell_test.dart` + `audio_player_widget_test.dart`): a `download_failed` row renders a **terminal** label (reuse `media_unavailable`/`media_unavailable_now`) with **no retry affordance** (mirror the existing `unavailable-media-retry-msg-…` `ValueKey` idiom at `media_grid_cell_test.dart:566-606`); a `failed` row under the ceiling still shows the retry affordance; an `integrity_failed` row renders a new "Couldn't verify this media" terminal label.
- Wired test: `_shouldRecoverVisibleAttachment` does **not** re-recover `download_failed` rows (INV-DL-1).

**GREEN:**
- `lib/core/constants/retry_constants.dart`: `const int kMaxDownloadRetries = 3;` (mirror `kMaxUploadRetries` at `:7`).
- `lib/core/media/group_media_integrity_policy.dart`: add `kMediaDownloadStatusDownloadFailed = 'download_failed'` (status namespace — keep distinct from the Go bridge event `'media:download_failed'`, correction #9); change `isRetryableDownloadFailure` to take `{int downloadRetryCount = 0}` and be honest per INV-DL-1/3 (gate `failed` on the counter; keep `integrity_failed` false — note this is a **behaviour change** from `:73-76` which currently returns true for `integrity_failed`); add `download_failed` to `isUnavailableMedia` (`:78-96`).
- `lib/core/database/migrations/084_media_attachment_download_retry_column.dart` (new, mirror 042) + `app_database_version.dart` 83→**84** + register in `main.dart` `onCreate` (after the existing media-attachment migrations) and `onUpgrade` `if (oldVersion < 84) { await run...Migration(db); }`.
- `lib/features/conversation/domain/models/media_attachment.dart`: add `final int? downloadRetryCount;` (field + ctor, mirror `uploadRetryCount` at `:56`); read `map['download_retry_count'] as int?` in `fromMap` (mirror `:148`); **conditional** write in `toMap` (mirror `:172`); add to `copyWith` (mirror param `:252` / assign `:277`). (`fromJson` does NOT parse it — matches `uploadRetryCount`; counters are DB-local, never wire.)
- `lib/features/conversation/application/download_media_use_case.dart`: on each non-integrity failure write — **re-anchor the sites at edit time**; current failure writes are at `:535-537` (local-miss), `:1481-1484` (relay error), `:1576-1579` (invalid-file/size), `:1904-1908` (catch), plus quarantine `:552-557` and pre-download stale-miss `:1405-1410` — `copyWith(downloadRetryCount: (current ?? 0) + 1)` then persist via `saveAttachment` (full-row, **not** `updateDownloadStatus`); flip to `download_failed` once `>= kMaxDownloadRetries`; on success reset to 0; short-circuit to `download_failed` on relay `"not found"`/`"not authorized"` (surfaced via `errorMessage`; the flow-event reason literal already at `:1479`). Keep the `download_failed` **status** distinct from the existing flow-event reason string.
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`: exclude `download_failed` from `_shouldRecoverVisibleAttachment` (`:3007-3013`, `statusIsRecoverable` list `:3009-3011`).
- `lib/shared/widgets/media/media_grid_cell.dart` (`isUnavailableMedia` gate `:89`, `isRetryableDownloadFailure` `:116`, `_buildUnavailablePlaceholder` `:227`, `l10n.media_unavailable` `:244`) + `lib/shared/widgets/media/audio_player_widget.dart`: render terminal label vs loading state; the retry affordance already keys off `isRetryableDownloadFailure` so terminal rows auto-lose it.
- **l10n:** existing keys `media_unavailable` (`app_en.arb:396`), `media_unavailable_now` (`:815`), `media_gif_too_large` (`:395`), `media_too_large_prompt` (`:382`), `media_too_large_after_compress` (`:394`), `btn_retry` (`:301`) are present with **full ar+de parity** (identical lines in `app_ar.arb`/`app_de.arb`) — reuse them. Add a **new** `media_could_not_verify` ("Couldn't verify this media") for the `integrity_failed` terminal — add to `app_en.arb` + `app_ar.arb` + `app_de.arb` and regenerate `app_localizations*.dart` (generated getter will be **`media_could_not_verify`**, snake_case, NOT `mediaCouldNotVerify`). Confirmed absent today. Do **not** route through `mediaPreviewText()`.

**Gate (host-runnable proofs, mandatory — device matrix is additional, see §5):**
- all Phase-3 unit + widget + `084_..._test` migration tests green; full groups suite (`-j 1`) + 1:1 suite green; `flutter analyze` 0 new issues.
- **Host sim proof #1 (bounded-retry → terminal, no infinite loop):** extend `test/features/conversation/application/media_download_slow_transfer_simulator_test.dart` (`fakeAsync`-style; existing `_HangingBridge`/`_SlowWritingBridge` + `transferStallTimeout`/`transferMaxTimeout` + `debugSetFlowEventSink` + `repo.downloadStatusUpdates`). Add a `_NotFoundBridge` that **always** returns `ok:false` with `"not found"`/`"not authorized"`, and assert: the download converges to terminal `download_failed`, **without burning past `kMaxDownloadRetries`** (assert the recorded retry-count never exceeds the ceiling and the `"not found"` short-circuit consumes **0** budget — INV-DL-4), and the row is then **NOT re-recovered** by `_shouldRecoverVisibleAttachment` (distinct from `integrity_failed`, which stays non-retryable — INV-DL-1/3).
- **Host sim proof #2 (counter reset):** a transient-failure-then-success path (e.g. `_SlowWritingBridge` failing N<ceiling times then succeeding) resets `downloadRetryCount` to **0** (INV-DL-2), asserted via the persisted attachment.
- **Host integration proof:** extend `integration_test/media_message_journey_e2e_test.dart` (host-runnable, `_JourneyHarness.create()` `:326`) for oversized-reject-pre-upload (no blob, type-aware reason) AND a download-terminal render proof (force repeated relay `"not found"` → terminal `download_failed` label, no perpetual spinner) on the real `ConversationWired`/`GroupConversationWired` widgets.

---

## 4. New wire / DB / migration impact

| Change | Type | Notes |
|---|---|---|
| `download_retry_count INTEGER NOT NULL DEFAULT 0` on `media_attachments` | **DB migration 084** (next-free as of 2026-06-16; was 077/078 in earlier drafts) | New `084_media_attachment_download_retry_column.dart`, mirror 042. `currentIdentityDatabaseVersion` 83→**84**. Register in `onCreate` + `onUpgrade (oldVersion < 84)`. Re-check next-free at edit time. Add migration 084 to `integration_test/group_multi_device_real_harness.dart` import list (currently stops at 082). |
| `download_failed` **status** string | App-internal | Local DB only; no wire change. Distinct from the existing Go bridge event `'media:download_failed'` and flow-event reason (correction #9). |
| Per-type size constants + type-aware reason codes | App-internal | No wire change. Replaces the existing 5 GiB per-attachment + **already-present** total aliases (`group_media_size_policy.dart:8-11`). |
| `media_could_not_verify` (new) | l10n | en/ar/de + regenerate (snake_case getter). Reuse existing `media_unavailable*`/`media_gif_too_large`/`media_too_large_*` where possible. |
| `mediaMeta.Fetched` + member-aware retention | **Relay (DEFERRED 4a/4b)** | All in `go-relay-server/media.go` (cleanupExpired `:94`, prunePeerLocked `:160`, mediaMeta `:38-45`, maxMediaSize `:27`) — NOT `inbox.go`. In-memory + JSON sidecar only; no Redis media backend; no migration. Separate deploy/soak. |
| `update_allowed_peers` / descriptor-carried key | **Wire/protocol (DEFERRED 4c)** | Product-gated (OQ-3). `action` switch at `media.go:411-427` has no such case today. |

---

## 5. Test & device gates

**Every phase has at least one HOST-RUNNABLE proof (fakeAsync / fake-relay / fake-network). The device matrix is additional real-hardware evidence on top, not a substitute.**

- **Unit (Dart):** `group_media_size_policy_test`, `group_media_integrity_policy_test`, `download_media_use_case_test`, `media_attachment_test`, `084_..._test` (mirror `042_media_attachment_reliability_columns_test.dart`).
- **Widget (host):** `media_grid_cell_test` / `audio_player_widget_test` terminal-vs-loading + no-retry-affordance for `download_failed`, retry for under-ceiling `failed`, new `media_could_not_verify` for `integrity_failed`; `group_conversation_wired_test` / `conversation_wired_test` GIF-fold + oversized-reject (**upload call count == 0**).
- **Host sim / integration proofs (mandatory per phase):**
  - **Phase 1** — `group_conversation_wired_test.dart`: oversized **non-GIF** rejected pre-upload, type-aware reason, **0 uploads** (INV-SZ-1).
  - **Phase 2** — `group_conversation_wired_test.dart` + `conversation_wired_test.dart`: oversized **GIF** rejected on **final bytes** (no pre-compression branch), **0 uploads**; `integration_test/media_message_journey_e2e_test.dart` (`_JourneyHarness.create()`): oversized → **no blob uploaded** on real widgets.
  - **Phase 3** — `media_download_slow_transfer_simulator_test.dart` (extend with a `_NotFoundBridge` always-`ok:false`): repeated `"not found"`/`"not authorized"` → terminal `download_failed`, **never exceeds `kMaxDownloadRetries`**, short-circuit burns 0 budget (INV-DL-4), and is **NOT re-recovered** by `_shouldRecoverVisibleAttachment` (distinct from `integrity_failed`); a transient-fail-then-success path **resets the counter to 0** (INV-DL-2); plus `media_message_journey_e2e_test.dart` download-terminal render proof (terminal label, no perpetual spinner).
- **Device matrix (additional evidence, on TOP of the host proofs):** `integration_test/group_multi_device_real_harness.dart` (DEVICE-REAL: real `GoBridgeClient` + `sqflite_sqlcipher`; iPhone13 `00008110-…`, Pixel6 `21071FDF600CSC`) — confirm the size gate fires **before** upload and the terminal label renders on both platforms (vs a perpetual spinner). **Reminder:** this harness's migration import list currently stops at 082 — add `084_media_attachment_download_retry_column.dart` to it once the migration lands, or the device DB will be a version behind.
- **Doc wiring:** update `02-integration-test-coverage.md` and `test-gate-definitions.md` with the new gates; cross-reference matrices `89-`, `90-`, `24-`, `102-`.

---

## 6. Risks & rollout

| Risk | Mitigation |
|---|---|
| Smaller caps reject sends users could previously make | Product-tuned for fast group chat; rejection surfaced pre-upload with type-aware copy; caps are single constants (OQ-1); relay 5 GB stays as backstop. |
| Total-cap constant already exists (5 GiB no-op) referenced by 3 tests | Phase 1 **replaces the alias value** (correction #8) and reconciles `retry_incomplete_group_uploads_use_case_test.dart`, `send_group_message_use_case_test.dart`, `handle_incoming_group_message_use_case_test.dart` rather than introducing the constant. |
| Existing perpetual-`failed` rows on upgrade | `download_retry_count` defaults 0 → re-enter bounded budget, converge within `kMaxDownloadRetries` opens (INV-DL-5). |
| Marking `integrity_failed` non-retryable hides a transient corruption | `isRetryableDownloadFailure` already returns true for `integrity_failed` today; the rewrite makes it false but re-allows retry when the descriptor (content hash / enc metadata) changes (INV-DL-3). |
| `download_failed` status collides with existing bridge event / flow-event reason | Keep the DB-status constant `kMediaDownloadStatusDownloadFailed` namespace-distinct from the Go bridge event `'media:download_failed'` and the flow-event reason (correction #9); verify no string-equality test conflates them. |
| Persisting counter via wrong API silently drops it | Mandated `saveAttachment` full-row path (correction #3, repo under `domain/repositories/`); test asserts persistence. |
| 1:1 / share-batch GIF asymmetry left behind | Phase 2 mandates removing all 3 raw-bytes branches with their distinct shapes (correction #2). |

**Rollout:** Phase 1 + 2 (pure client, no migration) → Phase 3 (migration 084 + UI + l10n) in the same release. Relay-side 4a/4b after deploy/soak. 4c only if backfill/replay is greenlit.

---

## 7. Open questions (resolve before/at implementation)

- **OQ-1 (size caps):** confirm the proposed defaults — image 25 MB, video 100 MB, audio/voice 16 MB, file 100 MB, total/message 200 MB. These are the one genuine product decision; everything else is mechanical. Note the **total/message cap constant already exists** (`kGroupMediaTotalMessageLimitBytes`, currently a 5 GiB no-op) — this OQ sets its real value, it does not introduce the constant.
- **OQ-2 (1:1 scope):** Phase 2 removes the GIF pre-compression asymmetry on the 1:1 + share-batch paths. Do we also extend the full per-type cap table to 1:1, or leave 1:1 on its current (no per-type) policy and only de-special-case GIF? Default = de-special-case GIF now, extend caps later.
- **OQ-3 (4c product gate):** ACL backfill / P2P re-fetch is a real protocol change. Greenlight needed before any work — and it only matters if a backfill/replay/quote-of-old-media feature is on the roadmap (NGM-013 says no pre-join backfill today).
- **OQ-4 (relay per-peer byte cap):** finding suggests optionally tightening the relay's 5 GB per-peer byte cap later (`maxMediaBytesPerPeer`, `media.go:28`). Out of scope here; revisit with 4a.
