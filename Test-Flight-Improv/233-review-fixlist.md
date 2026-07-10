# 233 Review — Fix-List (apply against `233-1to1-shared-media-library-batch-tdd-plan.md`)

Source: 6-agent audit (2 self-verification passes + 5 dimension assessors + completeness critic) with
first-party source verification against committed plans 227–231. Date: 2026-07-10.

**The plan is NOT execution-ready as written, but needs no redesign** — the consumed foundation is
verified sound and device-backed; the gaps are surgical plan/test-contract corrections on the
destructive + egress safety surface. Apply this list, then it is execution-ready.

Dimension scores: Goal-clarity 78* · Compartmentalization 60 · **Anti-drift 50 (weak)** ·
Define-good 60 · Goal-verification 61. (*Goal-clarity graded the bookmark defect "moderate"; it is
material — effective ~adequate.)

## Decisions locked with the user
- **Batch over-cap → cap the multi-select UI at 10** (a global selection cap, aligned with
  `kMaxMediaEgressItems = 10`). The selection controller refuses the 11th tap, so batch Save/Share
  never reaches the service's `>kMaxMediaEgressItems` blanket rejection, and batch Delete is likewise
  bounded. (See §B.)
- **Delivery → this written fix-list.** Plan file left untouched.

## Verified facts this list relies on (checked against source myself)
- Plan-228 `MediaLibraryRepository.getMediaLibraryPage({scope, filter, limit=50, cursor})` enforces
  `1..kMediaLibraryMaxPageSize`(=100) rejection + scope/filter-bound opaque cursor **before any SQL**,
  newest-first — `media_attachment_repository_impl.dart:340-408`. ✅ **CORE BET SOUND.**
- Real bookmark writer is **`MediaLibraryStateRepository.setBookmarked(String id, {required bool
  bookmarked})`** — different interface, **no `MediaOwnerLane` arg** — `media_attachment_repository.dart:189-202`;
  impl `:335-337`. `dbSetMediaBookmarked` guards only row-exists + `media_type IN (image,video)`,
  **no `owner_lane` predicate** — `media_attachments_db_helpers.dart:547-586`. ✅
- `deleteMessageForMe(**required ConversationMessage message**, …)` — `delete_message_use_case.dart:18-24`;
  `cleanupDeletedMessageArtifacts` **hardcodes `owner: MediaOwnerLane.direct`** — `:436-461` (same-ID group
  sibling structurally survives). `MessageRepository.getMessage(String id) → Future<ConversationMessage?>`
  — `message_repository.dart:26`. ✅
- `kMaxMediaEgressItems = 10` — `received_media_egress.dart:5`; `perform()` returns
  `outcome: rejected, items: const []` when the deduped selection exceeds it — `received_media_egress_service.dart:51-56`.
  The service also self-dedups selection by `attachmentId` — `:40-50`. ✅
- Plan-230 viewer exposes `final MediaViewerActionCallback? onAction` — `full_screen_typed_media_viewer.dart:37`. ✅
- Plan 227 is `accepted` and **device-proven**: physical Pixel 6 API 36 (`mrei1liw`) + iPhone 11
  deny/allow (`mreicukp`/`mreikvlb`) — 227 ledger `:250-251,284-288`. ✅ Delegation is honest.
- `mediaTapHandler` is at `conversation_screen.dart:~634` (plan line 20 cites `:596-628`, which is
  quote-resolution / failed-media-flag code). ✅

---

## §A — Bookmark owner-safety: false-green against a non-existent API (blocker 1, MATERIAL)

The plan defines a headline "done" for bookmark-safety in terms of a **write-side owner-reject** that
production does not perform, cited against a signature that will not compile.

- **A1.** Plan **line 37** — replace `MediaLibraryRepository.setBookmarked(MediaOwnerLane.direct,
  attachmentId, value)` with the real call: **`MediaLibraryStateRepository.setBookmarked(attachmentId,
  bookmarked: value)`** (no owner argument; distinct interface from `MediaLibraryRepository`). *Why: the
  cited signature does not exist — `media_attachment_repository.dart:189-202`.*
- **A2.** **TC-233-05 (line 78)** — rewrite the safety claim from write-side to **read-side structural
  exclusion**: assert that the owner-scoped page (`getMediaLibraryPage(scope: MediaLibraryScope.direct(…))`)
  **never surfaces a group/unresolved ID**, so the controller never holds one to pass; and assert
  `setBookmarked` is invoked with `(id, bookmarked:)` using **only IDs drawn from that scoped page**.
  *Why: `dbSetMediaBookmarked` has no `owner_lane` predicate (`media_attachments_db_helpers.dart:547-586`);
  a group/unresolved image row passed to the write WOULD be bookmarked. The genuine guard is the read.*
- **A3.** **TC-233-05 mutation cell** — delete the fictional `omit/flip owner` and `update by
  message/scope` mutations (no such parameters). Replace with real discriminators: *(i)* "controller
  bookmarks an id absent from the direct-scoped page → red", *(ii)* "a group/unresolved row injected into
  the page fixture renders or becomes a bookmark target → red". *Why: mutations must revert real code;
  the mandatory "representative mutations re-red" gate (line 170) cannot be honestly met otherwise.*
- **A4.** Keep the persistence sub-claim but **rename it** (see E6) and route the fail-closed
  *exclusion* assertion to the plan-228 sentinel **TC-233-15 (line 88)** + cross-reference **plan-228
  TC-228-06/08** (line 47) as the owner of the exclusion guarantee. *Why: that is where the guarantee
  is real.*
- **A5.** Plan **line 55** ("do not default/infer owner … or mutate unresolved") — clarify this
  applies to **scope/read** construction (real: `MediaLibraryScope.direct` never accepts a group scope),
  not to a bookmark-write owner arg (which does not exist). *Why: avoid re-introducing the phantom
  write-side owner in implementation.*

## §B — Batch Save/Share over the egress cap: unmodeled rejection (blocker 2, MATERIAL) — DECISION: cap at 10

`kMaxMediaEgressItems = 10`; a deduped selection >10 returns `rejected` with an **empty item list**
(`received_media_egress_service.dart:51-56`), which TC-233-06/07's per-item / failed-only-retry logic
cannot map. The library is a 1,000-entry grid (TC-233-13) with no selection cap for Save/Share.

- **B1.** Add to the **Scope Contract "In scope"** (near lines 38–39) a **global selection cap**:
  introduce `const kMaxDirectMediaSelection = 10;` (kept `== kMaxMediaEgressItems`) and state the
  multi-select controller **refuses the 11th selection**, so every batch action (Save, Share, Delete)
  operates on ≤10 items and never triggers the service's `>kMaxMediaEgressItems` blanket rejection.
  *Why: bounds the batch below the OS-egress ceiling; keeps per-item-outcome logic always populated.*
- **B2.** Add a new **TC-233-16** (application/widget host): "selecting the 11th item is refused; the
  selected set never exceeds `kMaxDirectMediaSelection`; batch Save/Share therefore always yields a
  populated per-item outcome list (never a blanket `rejected`/empty-items result)." Mutation:
  "controller admits an 11th selection **or** requests egress for >10 candidates → red." Gate:
  `direct_media_library_batch_actions_test.dart --plain-name 'selection is capped at ten and never over-caps egress'`;
  AUTO + both 1:1 arrays. *Why: the decision must have a standing guard.*
- **B3.** In **line 59** note that the selection-cap for **Forward** remains 249-owned, but the
  Save/Share/Delete selection cap is **now owned here** (they are different actions). *Why: prevent the
  reader inferring all caps are deferred to 249.*
- **B4.** Note in **TC-233-13 (line 86)**: the 1,000-entry fixture stresses *library virtualization*,
  not selection — the ≤10 selection cap does not weaken the virtualization assertion. *Why: keep the two
  concerns distinct.*

## §C — Destructive batch Delete: under-compartmentalized + unnamed seam (blocker 3, MATERIAL)

- **C1.** **Split Implementation Step 4 (line 102)** into **4a** (non-destructive batch Save/Share over
  plan 227 — TC-233-06/07) and **4b** (irreversible batch Delete-for-Me — TC-233-08) as a standalone,
  separately-reviewed slice with its own test file (e.g. `direct_media_library_batch_delete_test.dart`).
  *Why: irreversible local data loss must be reviewable apart from additive egress.*
- **C2.** Give **4b an explicit Stop-if** (mirroring Step 2's, line 100): *stop if* a selection fans out
  to more than one `(direct, parentMessageId)` delete key per unique parent; *stop if* owner is not
  pinned to `MediaOwnerLane.direct`; *stop if* `getMessage` returns null and that partial-failure path is
  not asserted. Add a one-line review checkpoint to **Gate Cadence (lines 116-120)**: the 4b diff + its
  focused test + delete-fanout mutation pass before any later step proceeds. *Why: the single riskiest
  operation currently passes through no plan-level gate.*
- **C3.** In the Scope Contract (line 39) and Step 4b, **name the materialization seam**:
  `MessageRepository.getMessage(id) → Future<ConversationMessage?>` is how a `MediaLibraryEntry` becomes a
  deletable `ConversationMessage` for `deleteMessageForMe`. *Why: the library holds only attachments;
  `deleteMessageForMe` needs a full `ConversationMessage` (`delete_message_use_case.dart:18-24`). Unnamed,
  the executor may synthesize a fragile bare message.*
- **C4.** **TC-233-08 (line 81)** — add a fixture leg where `getMessage` **returns null** for one selected
  unique parent ID (message evicted between library load and delete) and pin the outcome: that message is
  **reported failed and stays selected**, the other unique messages delete once each, group/unresolved
  same-ID rows remain unmutated. *Why: the most realistic partial failure is currently uncovered; the
  partial-outcome contract (line 81) is otherwise ambiguous for a vanished message.*
- **C5.** **TC-233-08** — add a **confirmation-gate** assertion ("batch Delete is gated behind an explicit
  confirmation surface") and a mutation "**proceed without confirmation → red**." *Why: "confirm" is
  prose-only (lines 39/102); `showDialog`/`AlertDialog` appear nowhere in the Test Contract — an executor
  could ship ungated batch delete and TC-233-08 stays green.*
- **C6.** **TC-233-08 mutation cell** — replace `omit/flip owner` (owner is hardcoded in
  `cleanupDeletedMessageArtifacts:436-461`, not controller-passed, so the mutation can't re-red controller
  code) with real discriminators: "**call delete twice for message A's two attachments** (missing dedup) →
  red" and "**skip/mis-materialize message B** → red." *Why: keep every mutation a real revert.*

## §D — In-viewer single-item actions: in-scope but zero execution coverage (blocker 4, MATERIAL)

- **D1.** Add a **TC-233-17** (widget host) exercising the plan-230 viewer's `onAction`
  (`full_screen_typed_media_viewer.dart:37`) that 233 must wire: invoking **Save / Share / Delete /
  Bookmark on the current cross-message item actually performs the operation** (not just that the callback
  identity updates on swipe, which is all TC-233-03 checks). Include a current item **whose owning message
  is outside the conversation's loaded window** so the single-item Delete hits the same `getMessage`-null
  path as §C4. Gate: `conversation_shared_media_viewer_test.dart --plain-name 'in-viewer current-item
  actions execute for cross-message items'`; AUTO + both 1:1 arrays. *Why: line 101 lists "exact-current-item
  actions" as in-scope; without an execution TC, in-viewer delete inherits the materialization gap
  uncovered.*

## §E — Precision / hygiene (nits, but they cost trust or coverage)

- **E1.** **Line 20** — re-anchor `mediaTapHandler` from `:596-628` to **`conversation_screen.dart:634`**.
  *Why: `:596-628` is quote-resolution/failed-media code; a reviewer cross-checking lands on unrelated
  lines.*
- **E2.** **Acceptance Gates preservation block (lines 144-148)** — add the explicit
  `conversation_wired_test.dart` direct **initial/load-older 50-row pagination** sentinel as a focused
  `--plain-name` command (matching how delete-for-everyone is pinned at line 145). *Why: line 43 names it
  must-stay-green but it is only covered transitively via `run_test_gates.sh 1to1` (line 149).*
- **E3.** **TC-233-06 (line 79)** — the "duplicate a selected ID → red" mutation is inert unless pinned:
  the real service self-dedups by `attachmentId` (`received_media_egress_service.dart:40-50`). Either pin
  the fake to **record the raw selection verbatim** (no internal dedup) so the recorded-argument assertion
  discriminates, or drop the mutation and keep the load-bearing "map Files to Photos" and "mutate
  bookmark/path on failure" reverts. *Why: a mutation that production would survive is not a real guard.*
- **E4.** **Implementation Steps (lines 99-104)** — name the RED tests to author at the head of **each**
  step (Step 3 → TC-233-03/04/05/12; 4a → 06/07/16; 4b → 08; Step 5 → 09/10/11; Step 6 → 13/17) and move
  each slice's representative mutation **into that slice** rather than deferring all mutations to Step 6.
  *Why: Step 1 currently front-loads only 6 of the (now 17) REDs; the rest have no per-step RED point —
  a waterfall inside TDD.*
- **E5.** *(optional)* **Acceptance Gates preconditions (lines 129-130)** — replace `test -f
  <plan-228/230>.md` with a `grep` for the real landed symbol (e.g. `getMediaLibraryPage`,
  `full_screen_typed_media_viewer.dart`). *Why: `test -f` on a markdown file proves the plan exists, not
  that its code landed (moot today since 228/230 are committed, but the precondition should assert code).*
- **E6.** **TC-233-05 durability sub-claim** — rename "persists after route/repository recreation" to
  "**controller re-reads bookmark from the repository (no in-memory-only state)**" and cross-ref plan-228
  TC-228-06/08 as the real-DB durability owner. *Why: a fake-repo reopen proves controller-non-caching,
  not DB durability (delegated to 228, per line 111).*

---

## Priority order to apply
1. **Stop the false-greens / untested destructive paths (must fix before any execution):**
   §A (bookmark false-green — compile + semantic), §B1–B2 (over-cap cap + guard), §C5 (confirmation gate).
2. **Make the destructive slice safe & reviewable:** §C1–C4, §C6 (split 4a/4b, Stop-if, name `getMessage`
   seam, getMessage-null leg, real delete mutations), §D (in-viewer action execution).
3. **Coverage/process hygiene:** §E2 (pagination sentinel), §E3 (dedup-mutation calibration),
   §E4 (per-slice RED-first), §B3–B4.
4. **Citations & cleanup:** §A5, §E1, §E5, §E6.

Nothing here changes the architecture or the consumed contracts — the plan's foundation is verified
sound and device-backed. Apply §1–§2 and the plan is execution-ready.
