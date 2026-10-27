# Thoughts build 128 final acceptance

This is the test handoff for the final integrated Thoughts candidate, not a
release verdict. Scope comes from Kayan `m-cb24d971`, the A–K definitions in
`m-9fedda5b`, and the owner's K exclusion in `m-03deceb6`. The inspected branch
base is `b250c450424948c36a444329cdf2d74e3f2a5bed`. Later A/D/F/H and J work must
be integrated before final execution. Astra owns host test/doc preparation;
`flutter_app` owns every device action and device result.

## Coverage map

Paths below are repository relative. A test's presence does not establish that
it passed on the final candidate. Pending author tests are not counted as
landed coverage, and are not duplicated in this preparation branch.

| Item | Required behavior | Existing or planned host evidence | Remaining acceptance |
| --- | --- | --- | --- |
| A | Clear posting status and one-tap retry, including photos/offline | Codex-UI's pending `thought_card_screen_test.dart` case `own posting retry stays in place and follows repository progress`; existing retry/media delivery suites remain separate. | Integrate author tests; prove actual offline photo retry once on the final pair. |
| B | Bigger plus target; first-use hint retires permanently | `test/features/orbit/presentation/widgets/orbital_visualization_test.dart:131` now requires a 44-point target and taps its outer corner separately from the self-avatar. `test/features/orbit/presentation/screens/orbit_wired_test.dart:1245` covers hint persistence; `:1278` covers composer-open before the stored flag loads. | Run the strengthened host assertion; confirm edge taps and persisted hint behavior on the final installed UI. |
| C | Replacement explanation and all-friends/24-hour explanation | `test/features/posts/improvement/thought_compose_sheet_test.dart:50`, `:78`, `:245`; Orbit's own-thought composer case at `orbit_wired_test.dart:1333`. | Read the actual composer with and without an existing Thought during the final run. |
| D | Reply/reaction sends in place with Sent/Retry; chat opens only on request | Codex-UI's pending card cases cover in-place sends, retry with the same reply ID/text, and queued-to-Sent progress. The base's old close-before-reply test must be replaced by that author change. | Integrate author tests; prove receiver delivery, one reply after retry, and explicit Open chat on the final pair. |
| E | A live chat quote reopens the Thought; a reply stays in the same chat | `orbit_wired_test.dart:1522` is the same-chat integration case; `:1553` covers a missing Thought. `:1474` covers a quote thumbnail arriving after download; `:1577`, `:1593`, `:1632` cover removal/races/deadline. | Reopen the quote and reply in the installed chat; no duplicate conversation. |
| F | Group reactions from distinct friends | Folded into H. Codex-UI's pending own-activity card case covers viewers and grouped distinct actors. | Integrate H; check actor deduplication and grouped copy. Three actors cannot be established by only the requested two-peer device topology, so keep the grouped-count assertion in host tests. |
| G | Unseen notes are distinct beyond bold and labelled as new | `test/features/orbit/presentation/widgets/orbit_thought_notes_test.dart:197` checks outline, semantics and seen styling; `:330` covers the labelled note action. | Observe an unseen note, then its seen state; preserve accessible labels. |
| H | Own Thought shows actual viewers and reactors; delivered does not mean seen | Migration 124 supplies `post_view_receipts`. Codex-UI's pending card case `a photo-only placeholder is not a view before content arrives` separates arrival from viewing. Its own-activity case covers names/reaction grouping. | Integrate H's receipt send/store/retry tests; prove no view on delivery or placeholder-only card, then a view after actual content is displayed. |
| I | Real blurred preview before the photo downloads, safely encrypted | `post_create_envelope_media_keys_test.dart` covers encrypted-only preview, no v1 leak, malformed/oversize/no-preview input; `post_create_encrypted_media_integration_test.dart` covers preview delivery. `thought_card_screen_test.dart:747` proves the held-download preview, but never completes its download future; it does not yet prove the transition. `124_thought_photo_previews_and_view_receipts_test.dart` covers schema, null legacy preview, receipt dedup and quote index. Astra adds the data-preservation test below. | Card test owner should complete/assert the preview-to-full-photo transition. Verify that transition on device too. Claude-UI's pending Thoughts-only true-ratio MediaGrid change still needs integration; ordinary chat remains a separate renderer. |
| J | Preview picked photos before Share; choose Fit or Crop | Codex author commit `0e87b94bc5af5d288f09288116d6a1386d85d831` adds `test/features/posts/improvement/thought_photo_preview_test.dart`: Fit preserves originals/order, Crop exports actual framed files with orientation, mixed framing, failure cleanup/retry, Cancel/draft preservation, small RTL controls. Not yet in the inspected base. | Integrate the author commit; use Fit and Crop, cancel once, then share the retained draft on the final pair. |
| K | 24-hour expiry / notification device measurement | **EXCLUDED BY OWNER** (`m-03deceb6`). Existing `thought_expiry_scheduler_test.dart`, lifetime and widget-expiry tests are unchanged. | No 24-hour wait, clock change, new device gate or missing-proof blocker for K. |

## Astra additions and execution limits

`test/core/database/migrations/124_thought_upgrade_preserves_data_test.dart`
creates a real file-backed SQLite database through the production registry at
version 123, seeds identity/contact/chat/Thought/attachment/recipient/read-state
rows, and opens that same file at 124. It compares every previous column,
requires old previews to be null, and requires delivered Thoughts to create no
view receipts. It also checks cached bytes and persistence of newly written
preview/receipt data after another close/open. This is host SQLite proof when
executed, not a signed SQLCipher install-over result.

The existing encrypted-envelope test now explicitly requires a pre-128 payload
without a preview to parse. Existing attachment tests now retain the preview
through storage and download-status copies, tolerate old rows without it, and
keep it out of renderable plaintext metadata. Existing v1-leak tests are reused.
The plus/self-avatar fixture additionally asserts the 44-point hit target and
actually taps its outer corner beyond the visible disc.

At preparation time, the unchanged `docker-ws/run_sims_safe.py:host_gate()`
returned `passed=false`: memory was 69%, swapout pages stayed flat and load was
below 15, but the worktree volume had only 10.947 GiB free, below the required
20 GiB. No Flutter test was launched and no guard was overridden. Raw evidence:
`.codex-test-logs/thoughts128-final-prep-20261027/host-guard-first.json`.
New assertions remain **NOT RUN** until a real admitted run supplies results.
No production feature is labelled KNOWN GAP merely because a host run is blocked.

Focused files for the first admitted, serial host run are:

```text
test/core/database/migrations/124_thought_upgrade_preserves_data_test.dart
test/features/posts/improvement/post_create_envelope_media_keys_test.dart
test/features/posts/improvement/post_media_attachment_crypto_fields_test.dart
test/features/orbit/presentation/widgets/orbital_visualization_test.dart
```

Each new test path is already selected by the existing storage/surfaces mappings
in `tool/testing/selection.json`; no selector is narrowed. Run metadata validation
and preview against an explicitly verified base. Keep required omitted checks
as NOT RUN. If an unlanded implementation still requires a test, retain a causal
failure before using the project's KNOWN GAP skip convention; do not write a
skipped fixture that cannot compile or count a skip as proof.

## Final device checklist — flutter_app only

Run this numbered checklist once, after all accepted author commits are
integrated and the single final full host lane has completed. Use the owner's requested iPhone 13
and one Hetzner emulator only if available at execution. `flutter_app` resolves
and pins available targets, owns UI automation, and retains identifiers/private
data in ignored local evidence. An unavailable target leg is
`N/A (target unavailable by project policy)`. Astra does not discover or control
devices. Keep original attempts and source/configuration/artifact identities.

1. **Install over and keep data.** Before install, record redacted identity,
   contact/chat/Thought/media counts and the installed schema. Build the exact
   final source without Thoughts/depth Dart defines; record the build command
   and artifact hash. Install over the existing app with data retained, never
   uninstall or clear storage. If the old database is 123, verify upgrade to
   124 and the same identity, chats, quotes and cached photos after relaunch.
   If it was already 124, label the actual install-over result honestly; the
   host 123→124 test is a separate result.
2. **Defaults and entry points.** On that defines-free build, Thoughts plus and
   notes are visible and the 3D Orbit view opens (owner turned it on for
   128). Tap the plus near its outer edge and the
   self-avatar separately. Observe the first-use hint when applicable; opening
   and dismissing the composer retires it across relaunch. Check unseen outline
   and new-Thought accessibility label, then the seen style after opening.
3. **Composer and replacement.** Read the all-friends/24-hour copy and the
   replacement explanation with an existing Thought. Pick a portrait photo,
   inspect the preview, try Fit and Crop, cancel once without losing the draft,
   then share. Confirm only the newest own/friend Thought remains visible.
4. **Photo arrival and shape.** Hold the recipient's photo download using an
   existing supported test control. Before bytes arrive, require the sender's
   blurred preview; an old sender without a preview must show the shaped
   placeholder. Release the hold and confirm the actual photo, contained at its
   true ratio over blur, opens in the viewer. Ordinary chat layout stays usable.
   If download cannot be controlled, record that boundary as unproven rather
   than treating a fully cached photo as preview proof.
5. **Offline posting retry.** From an offline sender, post text plus a photo.
   Require clear pending/failure state. Restore connectivity and tap retry once;
   require progress, one final Thought and the matching recipient photo. The
   card stays open; repeated taps do not create duplicate sends.
6. **In-place reply and reaction, then quote reopen.** Send from the friend's
   card without leaving it; observe Sent. Exercise a recoverable failure and
   Retry without changing the reply or creating a duplicate. Open chat only by
   its explicit action, check the photo quote thumbnail (including late download
   refresh), tap its live quote, and reply again to that same chat. A deleted or
   unavailable Thought must not reopen a stale card.
7. **Actual views and reactions.** On the author, delivery alone must not add a
   viewer. A recipient looking only at a photo placeholder must not add one;
   displaying the real Thought must. Reopen/retry once and require one viewer
   identity. Send a reaction and check the correct actor/grouped summary, with
   repeat receipts causing no duplicate actor. Distinct multi-actor grouping
   remains covered by the host fixture with more actors.
8. **Close evidence.** Relaunch both apps, confirm retained data and final UI,
   and attach exact candidate/build hashes plus numbered PASS/FAIL/NOT RUN/N/A
   results. No 24-hour wait, device-clock change or K measurement is requested.

## Catalog proposals — coordinator edits testplan.yaml

Only TH-001 existed in the inspected `/Volumes/CrucialX9/Kayan/testplan.yaml`
at line 2751. The following IDs are proposals, subject to Kayan reserving them;
none is marked ready or passed by this document. Reuse the final device run for
the matching checklist legs, and preserve host/device proof as separate fields.

| Proposed ID | Title / items | Host references | Device leg |
| --- | --- | --- | --- |
| TH-002 | Defines-free Thoughts on / depth on; distinct unseen notes (G) | `test/core/config/thoughts_feature_flags_test.dart`; `orbit_thought_notes_test.dart`; existing forced-off Orbit/Settings scan controls | 2 |
| TH-003 | Thought entry, first-use hint, replacement and photo framing (B/C/J) | `orbital_visualization_test.dart`; `orbit_wired_test.dart`; `thought_compose_sheet_test.dart`; author's `thought_photo_preview_test.dart` | 2–3 |
| TH-004 | Offline photo posting progress and one-tap retry (A) | Codex-UI's posting card cases; existing delivery/retry suites | 5 |
| TH-005 | Encrypted preview, true-ratio photo and late quote thumbnail (I) | `post_create_envelope_media_keys_test.dart`; `post_create_encrypted_media_integration_test.dart`; `thought_card_screen_test.dart`; `thought_quote_block_test.dart`; Orbit's late-download quote case | 4 and 6 |
| TH-006 | In-place reply/reaction Retry and same-chat quote reopen (D/E) | Codex-UI's in-place/retry cases; `orbit_wired_test.dart` live/gone quote cases | 6 |
| TH-007 | Actual viewers and deduplicated grouped reactions (F/H) | Codex-UI's receipt/own-activity/placeholder cases and delivery persistence tests; migration receipt uniqueness case | 7; multi-actor grouping host-only in this topology |
| TH-008 | DB123→124 preserves identity, chat, Thought and cached photo | Both `124_*_test.dart` migration files and `full_migration_chain_test.dart` | 1 and 8, only if installed baseline is actually123 |

K has no new catalog gate. Existing TH-001 deletion coverage and existing host
expiry coverage are retained. Final candidate proof, skipped assertions, signed
upgrade and provider delivery must each keep their actual verified limits.
