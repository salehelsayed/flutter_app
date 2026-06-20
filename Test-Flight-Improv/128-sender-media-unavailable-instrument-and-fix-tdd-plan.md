# 128 — Sender "Media unavailable" (1:1 own-sent image): instrument-then-fix TDD plan

Status: PLAN. Round 4 of the same symptom. Goal: stop guessing — make the render gate **observable
on-device**, get one definitive device read, then apply the fix the telemetry proves correct.

## The symptom (unchanged across 4 rounds)
Sender's own 1:1 image shows "Media unavailable"; the recipient shows it fine. Latest:
bob (iOS sim 38FECA55) → alice, blob `5984e08d`, msg `9cc50d7e`, 21:30 UTC.

## What is PROVEN (hard evidence, this round)
1. The durable plaintext file EXISTS on bob's sim **right now**:
   `…/Application/07135F93…/Documents/media/12D3KooWGVu5…/5984e08d-….jpg` (1012567 bytes), and
   `07135F93…` is bob's CURRENT container (`simctl get_app_container`).
2. bob.log: durable copy committed (`fileExists:true`), status stayed `done`, **no retrier**, **no**
   `MEDIA_DURABILITY_DONE_PATH_MISSING`, no `download_failed`/`integrity_failed`. Pure sender render.
3. The image render path is `MediaGridCell` (`media_grid_cell.dart:261`) — the only image
   "Media unavailable" site (audio uses `audio_player_widget.dart:296`; not this).
4. The round-3 render-boundary fix IS in the source (uncommitted, branch `124-harness-refactor`):
   `MediaFileManager.resolveStoredPathSync` + `cacheDocumentsDir` seed at `main.dart`, used in
   `MediaGridCell._hasExistingLocalFile` and `MediaThumbnailImage`. Host tests pass + mutation-verified.
5. `getApplicationDocumentsDirectory()` resolves `media/<peer>/<blob>.jpg` to exactly the on-disk
   file location → with the fix seeded, the gate MUST pass. It doesn't on-device.

## The unresolved fork (this is what we must DISAMBIGUATE, not guess)
With the file present + the host fix correct, an on-device failure can only be:
- **(A) the installed binary lacks the fix** (build didn't pick up the uncommitted edits / stale
  install / hot-reload didn't re-run `main()` so the cache seed never ran), OR
- **(B) the binary has the fix but the render gate sees a path the resolver can't fix** — most
  plausibly a stale **`pending_uploads` ABSOLUTE** path retained from the optimistic durable-prep
  upsert (`conversation_wired.dart:1920-1934`), which after upload is deleted, AND which
  `resolveStoredPathSync` passes through unchanged (it handles `/media/`,`/local_media/`,`/post_media/`
  legacy-absolute rebase but NOT legacy-absolute `/pending_uploads/`), OR a relative path that
  never got resolved because the cache was null.

Four rounds of "looks right in host, fails on device" means we MUST settle A-vs-B empirically.

## Phase 0 — Instrument the render gate (RED telemetry; ships first)
Add low-frequency, build-identifying telemetry so ONE device run is conclusive:
1. `main.dart` (right after `MediaFileManager.cacheDocumentsDir`): emit
   `MEDIA_RENDER_RESOLVER_SEEDED {seeded:true}`.
   - Next log HAS it ⇒ binary contains the round-3 fix and the cache is seeded (rules out A).
   - Next log MISSING it ⇒ **stale build** (A) — definitively; stop blaming code.
2. `MediaFileManager.resolveStoredPathSync`: when `_cachedDocumentsDir == null`, emit
   `MEDIA_RESOLVE_SYNC_NO_CACHE` once per process. Present ⇒ gate ran but cache unseeded (A/ordering).
3. `MediaGridCell`: when an `image`/`video` attachment is `done` + has a localPath but
   `!_isDisplayableDoneMedia` (the exact failure), emit ONCE per attachment id
   `MEDIA_RENDER_GATE_UNAVAILABLE { rawLocalPathKind, resolvedPathKind, existsAtResolved,
   cacheSeeded, downloadStatus }` (kinds, not raw paths, for privacy: relative-media /
   pending-uploads-abs / owned-media-abs / other).
   - This reveals exactly what the gate saw: was the path the deleted `pending_uploads` abs (B), a
     still-relative path (cache null → A), or an owned-media abs that genuinely doesn't exist.

Tests (Phase 0):
- `media_file_manager_test`: `resolveStoredPathSync` with null cache emits `MEDIA_RESOLVE_SYNC_NO_CACHE`
  once (capture flow events); with cache seeded, no event.
- `media_grid_cell_test`: a `done` image whose resolved path does NOT exist emits
  `MEDIA_RENDER_GATE_UNAVAILABLE` with `existsAtResolved:false` and the correct `rawLocalPathKind`
  (cover both a relative path with null cache → `cacheSeeded:false`, and a deleted
  `pending_uploads` absolute path → `rawLocalPathKind:pending-uploads-abs`).

## Phase 1 — Fix, contingent on the Phase-0 device read
- **If `MEDIA_RENDER_RESOLVER_SEEDED` is ABSENT (A):** the build is stale. No code change needed —
  the round-3 fix is correct; do a clean `flutter clean && flutter run`/install and re-verify. The
  telemetry makes this unambiguous (not another "just rebuild").
- **If present + `MEDIA_RENDER_GATE_UNAVAILABLE { rawLocalPathKind: pending-uploads-abs }` (B):** the
  displayed message retained the deleted optimistic `pending_uploads` absolute path. Fix:
  (a) extend `resolveStoredPathSync` to also rebase legacy-absolute `/pending_uploads/` (defense), AND
  (b) the real fix — stop persisting/retaining the `pending_uploads` path as the display path: after
  the durable copy, the in-memory message must carry the `media/<peer>/<blob>` path (not the
  pending one). RED test: a message whose attachment localPath is a deleted `pending_uploads` abs
  path renders (gate resolves to the owned-media copy) — fails pre-fix.
- **If present + `cacheSeeded:false` at the gate:** the seed ran in `main()` but a render happened
  with the static still null (ordering/isolate). Fix: resolve lazily/defensively or assert seed
  ordering. RED test reproduces a null-cache gate.
- **If present + `existsAtResolved:false` with `owned-media-abs`:** genuine path mismatch — the
  durable write path and the resolver disagree; reconcile `localPathForAttachment` vs
  `resolveStoredPathSync` (add an equivalence test).

## Phase 2 — Lock it
- Keep the round-3 render-boundary resolution (it is correct and necessary).
- Add the regression test matching the confirmed cause from Phase 1.
- Re-run: media suites, conversation_wired, full-screen viewer, share. `flutter analyze` 0 new.

## RESOLVED 2026-06-19 — instrumentation pinpointed it, fix landed
The Phase-0 telemetry in the device's `alice.log` (build that DID contain the round-3 fix:
`MEDIA_RENDER_RESOLVER_SEEDED` present, `MEDIA_RESOLVE_SYNC_NO_CACHE` absent) gave the conclusive
read: `MEDIA_RENDER_GATE_UNAVAILABLE { rawLocalPathKind: pending-uploads-abs, resolvedPathKind:
pending-uploads-abs, existsAtResolved: false, cacheSeeded: true, downloadStatus: done }`.
**Confirmed Cause B**: the displayed in-memory attachment carries the **deleted optimistic
`pending_uploads` ABSOLUTE path** (set at `conversation_wired.dart` durable-prep, never swapped for
the durable `media/<peer>` copy — the send-result/reload swap is unreliable), and the resolver
passes a `pending_uploads` abs path through unchanged. The durable owned copy exists at
`media/<peer>/<blob>.jpg`.

**FIX (render-boundary owned-copy fallback — single chokepoint, timing-independent):**
- `MediaGridCell._resolvedExistingLocalPath`: if the displayed `localPath` doesn't resolve to an
  existing file, fall back to the canonical owned copy
  `MediaFilePathConvention.relativePathForAttachment(ownedMediaPeerId, attachment.id, mime)` →
  `resolveStoredPathSync` → use if it exists. `_hasExistingLocalFile` + the `MediaThumbnailImage`
  `mediaPath` use it.
- Threaded `ownedMediaPeerId` (1:1 contact peerId) `ConversationScreen` → `LetterCard` → `MediaGrid`
  → `MediaGridCell`.
- TDD: `media_grid_cell_test` `128 round-5: stale display path falls back to the durable owned copy`
  (replicates the exact device state: pending path deleted + owned copy present) — **mutation-verified**
  (removing the fallback → no `MediaThumbnailImage`, fails). 205 suite tests green; 0 new analyze.

## 2026-06-19 — GROUP extension + sim/regression coverage (the session goal closeout)
- **Group screen wiring**: `group_conversation_screen.dart` `buildLetterCard` now passes
  `ownedMediaPeerId: group.id`. Group durable media is keyed under `media/<groupId>/<blob>` (confirmed
  at `group_conversation_wired.dart` `relativePathForAttachment(contactPeerId: widget.group.id)`, 4
  call sites). The verified-content-hash gate still applies — the fallback only supplies the path,
  never bypasses verification (asserted by the negative-guard test).
- **Regression tests (host, mutation-verified):**
  - `media_grid_cell_test.dart`: `128 round-5 (group): verified group media … falls back to the
    durable owned copy keyed under media/<groupId>` (positive) + `… WITHOUT ownedMediaPeerId the stale
    path stays unavailable (fallback is required; verification is never bypassed)` (negative guard).
  - `group_conversation_screen_test.dart`: `128 group wiring: own-sent group image with a stale
    display path renders from the durable owned copy` — drives the **real** `GroupConversationScreen`;
    **mutation-verified** (removing `ownedMediaPeerId: group.id` → `Found 0 MediaThumbnailImage`, fails).
- **Sim/device proof** (`integration_test/sender_media_unavailable_fallback_proof_test.dart`): drives
  the REAL `ConversationScreen` (1:1) and `GroupConversationScreen` (group) through the exact device
  residue (stale deleted `pending_uploads` abs path + durable owned copy at `media/<id>/<blob>`),
  seeds the sync resolver cache like main.dart, asserts the sender grid renders (MediaGrid +
  MediaThumbnailImage, no `Media unavailable`, no broken-image) on first build AND after reopen.
- Gates: full `media_grid_cell_test` (27) + `group_conversation_screen_test` (78) host-green; 0 new
  analyze (only pre-existing `info` lints in the group screen).
- **DEVICE PROOF PASSED (iPhone 16e sim, 2026-06-19):** both legs of
  `sender_media_unavailable_fallback_proof_test.dart` green on-device (`+2 All tests passed`) — the
  render-boundary owned-copy fallback resolves the durable copy through the REAL `ConversationScreen`
  / `GroupConversationScreen` on a simulator, not just host. (First device run caught a test-only
  harness bug: `ConversationScreen` has no embedded Scaffold/Material, so its compose `TextField`
  needs a `Scaffold` ancestor — fixed to mount it like the production route; not a product defect.)
  REMAINING: the ultimate confirmation is the original two-device LIVE repro (alice↔bob send → relay →
  render) after a clean `flutter clean` rebuild — the sim proof verifies the render fallback, not the
  full send/upload pipeline.

## Gates / honesty
- No DB migration. All host-provable except the Phase-0 device read, which is the POINT — it
  converts 4 rounds of deploy-ambiguity into one definitive signal.
- Do NOT claim the device bug fixed until a device log shows the image rendering AND
  `MEDIA_RENDER_GATE_UNAVAILABLE` no longer fires for own-sent images.
