# 253 Review — Fix-List (apply against `253-external-share-immediate-media-progress-tdd-plan.md`)

Source: 8-agent audit (workflow `wf_8903961d-19d`: 2 source-grounded verifiers + 5 dimension assessors + completeness critic) + orchestrator source verification, 2026-07-10. Plan is **ready-with-tightening**; the core rendering bet is **verified sound** (scores: D1 80 / D2 66 / D3 70 / D4 78 / D5 68; critic: yes-with-tightening).

Decisions locked with the user (2026-07-10):
- **Plan 236 lands (commits) BEFORE any 253 production edit** — no carry-forward of the dirty coordinator.
- **Group-target blank frame is DEFERRED explicitly** (named follow-up), not fixed in 253.
- **Progress half closes with device-truth host fixtures AND one required physical share-sheet replay** (closure tier for symptom 2 becomes host + 1 device replay).
- Delivery mode: findings + this fix-list; plan file not edited by the review.

Verified facts this list relies on (checked against source by the orchestrator):
- The four first-save funnels are exactly `send_chat_message_use_case.dart:1171/:1216/:1333/:2099`, each followed by `_persistOutgoingMedia` and enrichment at `:1198/:1238/:1364/:2147`; no fifth first-save site exists in `lib/`. ✅
- Inline media on the first published event renders: `saveMessage` publishes the in-memory object (`message_repository_impl.dart:126-155`; media transient, never serialized — `conversation_message.dart:81,134-157`), and `ConversationWired` hydration falls back to event media when the attachments-table read is empty (`conversation_wired.dart:1701-1706, 4398-4425`). ✅
- `messageChanges` has exactly TWO consumers, both tolerant of inline media (conversation_wired re-hydrates; `feed_wired.dart:1124-1131` replaces event media wholesale). ✅
- `run_test_gates.sh` `1to1` with ANY extra arg delegates wholesale to `run_host_test_gates.sh` (`scripts/run_test_gates.sh:898-903`); its dry-run prints only `ONE_TO_ONE_HOST_TESTS` (`run_host_test_gates.sh:241`). ✅
- Go emits an unconditional `sentBytes=0` event before and a full-size event after every upload (`go-mknoon/node/media.go:380,386`), and event bytes count the ENCRYPTED artifact (+16-byte GCM tag; `upload_media_use_case.dart:373-374`) while `budgetBytes` is plaintext (`pending_composer_media.dart:52-58`). ✅
- Group sends pre-persist a media-free row before the network attempt (`send_group_message_use_case.dart:1096`; media only at terminal funnels `:1180/:1280/:1415/:1494/:1559`). ✅
- The picker files contain zero `PopScope`/`WillPopScope`/wake-lock references (rg across screen/wired/route). ✅
- `mediaUploadProgressStream` is a process-global singleton (`bridge.dart:51-52,86-87`) fed solely by `go_bridge_client.dart:709-711` with `{id, sentBytes, totalBytes, toPeerId}` keyed by the coordinator-minted blob ID — no DI instance mismatch is possible. ✅

Plain-English gloss: "the coordinator" = `DefaultShareBatchDeliveryCoordinator` (external OS-share batch delivery); "the picker" = the external share target-picker screen pair; "funnel" = a terminal code path in the 1:1 send use case that performs the message's FIRST `saveMessage`.

---

## §A — Plan-236 sequencing (locked: land 236 first)

- **A1.** Rewrite Step 1's gate as: "Plan 236 must be COMMITTED before any 253 production edit (user decision 2026-07-10). Record its commit SHA in Execution Progress before Step 3." Delete the three vague phrasings ("until its owner state is known" :268-269, "Land it or carry it intact" :222, "settled or explicitly carried forward" :14). The current wording lets an executor self-declare settlement against a coordinator that is user-dirty right now.
- **A2.** Move the implementor census re-run (`rg -n "implements ShareBatchDeliveryCoordinator" lib test`) from Step 1 into Step 4's first sentence — Step 4 is where the census is consumed (adding the optional callback to every `deliver` override; `implements` fakes get no default bodies in this repo).
- **A3.** Run TC-09 once at Step 1 (post-236-land) and record its GREEN baseline. The plan asserts TC-09's baseline "not run during planning" (:248) — a mid-execution TC-09 failure currently has no pre-committed interpretation beyond compile errors (:419-420).
- **A4.** After 236 lands, re-pin every citation in the two 236-touched files and add one sentence declaring the tree state citations reference. Known corrections against today's working tree: `_buildSummary` is at `share_target_picker_wired.dart:501-534` (plan's `:470-499` is wrong — that range is coordinator-resolution territory); the three SnackBar blocks span `:379-386 / :392-396 / :407-414` (plan's `:289-388` misses two); coordinator `_sendToContact` spans `:470-573`. The plan currently mixes HEAD-state picker citations with dirty-tree coordinator citations — no single checkout reproduces all its anchors.

## §B — Progress model vs device reality (locked: fixtures + 1 device replay)

- **B1.** Step 5: mandate a per-upload clamp — each upload's event bytes clamp to that upload's budget before folding into the cumulative total (in-app pattern at `conversation_wired.dart:669, :714-719`). Why: device events count ciphertext (+16 B GCM per file per target) while the total counts plaintext `budgetBytes`; an unclamped tracker exceeds 100% and TC-03's literal "reach total" assertion contradicts raw event arithmetic.
- **B2.** Step 5: strict active-ID-only event acceptance, and clear the active blob ID BEFORE folding the manual completion for that upload. Explicitly forbid copying the in-app adopt-any-id-when-null pattern (`conversation_wired.dart:666-672`). Why: Go's final full-size event rides an async channel and can land AFTER the Dart upload future resolves — if the just-completed ID is still active (or re-adopted), that file's bytes double-count.
- **B3.** TC-03: add two fixtures — (a) an over-budget, ciphertext-sized event (budget+16) for the active upload → clamped, cumulative total still exactly `sum(budgetBytes) × targets`; (b) a late final full-size event for a JUST-completed blob → no double count. The existing unrelated-ID case covers neither.
- **B4.** TC-03 (or a sibling case): one no-injection case — construct `DefaultShareBatchDeliveryCoordinator` WITHOUT an injected stream, drive the production default via `emitMediaUploadProgressEvent` (`bridge.dart:105`; test pattern at `conversation_wired_test.dart:7657`) during a gated upload, and assert the callback advances. Why: every planned progress test injects the stream (:242, :293) — a wrong/dead production default ships fully green.
- **B5.** Rewrite the "fast upload emits no intermediate event" premise (:155, :260): on device Go ALWAYS emits a 0-byte initial and a full-size final event per upload (`media.go:380,:386`); zero-event uploads exist only under host fakes. Manual completion stays required (host fakes emit nothing; the final event can arrive late), but the risk direction inverts — the hazard is double-counting, not missing completion.
- **B6.** Closure change (locked): add a required-once physical share-sheet replay for the progress half before closure — send a multi-file image/video batch from the OS share sheet to a real contact and observe: bar never exceeds 100%, never jumps backward, reaches completion, and the `Sending…` title appears after bytes complete. Update Closure tier (:7), Boundary closure (:447-448), and the Deferred bullet (:211-213) accordingly. Symptom 1 (first-frame render) stays host-only — it is pure Dart ordering.
- **B7.** Extend the Deferred/accepted-difference note: two silent freeze windows sit INSIDE the determinate `uploading` phase, not in the deferred compression phase — per-target full-file AES re-encryption (`upload_media_use_case.dart:347-352`, budget up to minutes via `callBlobEncrypt`) and, for same-WiFi contacts, an AWAITED WS LAN transfer of the full ciphertext with zero progress events (`share_batch_delivery_coordinator.dart:492-512`; `media_lan.go` emits none). Name them as accepted, or report the `uploading` phase-change only after the LAN leg. Also record two adjacent facts: the LAN leg reuses the SAME blob ID as the relay upload (coordinator `:502` vs `:523`) — a latent double-count seam if LAN progress events are ever added; and the coordinator omits the existing `onVideoProgress` hook (`pending_composer_media.dart:37`; coordinator `:426-431`) — the deferred-ETA follow-up's natural seam.

## §C — Registration gate (vacuous as written)

- **C1.** Replace the second registration dry-run (:393) with `rg -n 'external_share_media_ux_test.dart' scripts/run_test_gates.sh scripts/run_host_test_gates.sh` expecting exactly one hit per file, and reword done-checkbox :430 to reference that command. Why: `run_test_gates.sh 1to1 --dry-run` delegates to the host script (`run_test_gates.sh:898-903`) — both plan dry-runs print the SAME host array, so a missing `ONE_TO_ONE_TESTS` registration passes both gates and the curated sim lane silently never gains the test.

## §D — Group-target scope (locked: defer explicitly)

- **D1.** Add a Deferred/accepted-difference line: "External share to a GROUP target retains the pre-persist blank-frame window (`send_group_message_use_case.dart:1096` saves media-free before the bridge call; media persists only at terminal funnels `:1180/:1280/:1415/:1494/:1559`; the group UI reloads from DB on outgoing changes, `group_conversation_wired.dart:1666-1685`). Owner: follow-up plan." Groups are selectable on the same picker (`share_target_picker_screen.dart:465-482`) — without this line, a user repeating the reported flow with a group target will file the bug as un-fixed.
- **D2.** Re-word TC-01/TC-02 behavior cells (and the Scope bullet :145-146) from "external media send" / "every ordinary 1:1 media send" to explicitly "1:1" so the contract does not over-claim what Step 3 delivers.

## §E — Slice checkpoints + funnel coverage

- **E1.** Add per-slice GREEN checkpoints: end of Step 3 — "Run TC-01, TC-02, TC-07, TC-08 to GREEN before starting Step 4"; end of Step 5 — "TC-03 GREEN"; end of Step 7 — "TC-04/05/06 GREEN". Step 8 becomes lanes/sweeps/hygiene only. Why: the shared hot-path edit (every 1:1 send) currently has no GREEN gate until four steps later, fused with unrelated share-UI work.
- **E2.** Table-drive TC-01 over the four terminal outcomes (live success, inbox accepted, inbox-full retryable, terminal failure), with the mutation stated as "revert the helper at ANY single funnel → re-red" — OR add an acceptance grep-gate that `messageRepo.saveMessage(` appears only inside the new helper within `send_chat_message_use_case.dart`. Why: TC-01 as written samples 1 of the 4 funnels it modifies; a partial adoption (e.g. only the live-success funnel) passes all planned tests, and the inbox-accepted funnel is the LIKELY real path for an offline recipient.

## §F — Picker lifecycle (new finding — no prior guard)

- **F1.** Add to Steps 5/7: acquire/release `UploadWakeLockController` around the delivery (in-app pattern at `conversation_wired.dart:681-699`) and a `PopScope` blocking pop while `_isSending` — or, if consciously out of scope, an explicit Deferred line owning both plus an accepted-difference note that mid-send back-out loses all outcome feedback. Why: the picker files have zero wake-lock/back-guard references while in-app 1:1 has both (TC-08 preserves them); a locked screen mid multi-target upload freezes the new "truthful" bar, and the plan deletes all three post-pop SnackBars — HEAD's buggy post-pop SnackBar was, ironically, the only feedback a user got after backing out mid-send.

## §G — Smaller tightenings

- **G1.** Amend done criterion :428: mandate a RECORDED behavioral mutation re-red for both intentional-compile-RED rows (TC-03, TC-04) — a compile RED proves the props don't exist, not that behavior is right; "representative mutation" lets TC-04's spinner-suppression/phase-title falsification never run.
- **G2.** Pin the l10n deliverable: name the keys TC-04/TC-06 assert against; add the `Sending…` title-override and inline-feedback strings to all three ARBs (en/de/ar) + l10n regen, and list the ARB/generated files in Affected files (:101-107). `upload_progress_title` already exists; do NOT blind-reuse the suspicious existing key `n` (= "Sending...") in `app_en.arb`.
- **G3.** Note the second-order event-shape change: after Step 3, STATUS-FLIP events also carry inline media via the repo snapshot cache (`message_repository_impl.dart:145,:521-524,:532-536`). Both consumers verified tolerant — add either one TC-01 assertion on a subsequent flip event's media or a one-line accepted-difference note, so it stops being an untested assumption.
- **G4.** Add a `flutter analyze` baseline snapshot to Step 1 — the tree is knowingly dirty, so the "no new analyzer issues" gate (:399-400) needs a measured before-state.
- **G5.** Add two pre-refutations to Refuted findings (D1): (a) composer-clearing SnackBar margins (`_composerClearingSnackBarMargin`, used at `conversation_wired.dart:2289` etc.) are NOT a viable smaller fix for the success summary because it paints post-pop on the root messenger over an arbitrary underlying route; (b) routing external media through `ConversationWired`'s optimistic path is already a hard Do-not (:186-188) — keep both so the decisions can't reopen under schedule pressure.

---

## Priority order to apply

1. **§A (236 sequencing)** — gates every production edit; the one near-irreversible failure available to this plan is clobbering the uncommitted 236 work.
2. **§C + §B1–B4** — make green mean the win: the registration gate and the progress arithmetic are the two places the plan can close "done" while the deliverable is silently broken.
3. **§D + §F** — scope honesty (group-target deferral) and the feedback-loss/wake-lock regression the SnackBar removal introduces.
4. **§B5–B7, §E, §G** — premise correction, slice checkpoints, funnel table-drive, and spec pins.
