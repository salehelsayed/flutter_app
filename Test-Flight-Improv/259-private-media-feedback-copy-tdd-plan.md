# 259 - Private Media & Feedback Revised Copy (Modification)

Status: execution-ready (v2.1 — /tdd-review audit wf_d3da2753-fc2 applied 2026-07-18; host-all gates demoted to optional per user, same date)
Spec: free-text intent (no formal spec). Source design: `Test-Flight-Improv/private-media-feedback-ux-mockup-codex.html` — the **Revised** copy variant (inline text; `data-alt` attributes hold pre-revision copy) plus its §06 revision table and "Kept as-is" list.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-18 | Evidence Collector | Workflow `wf_2242d205-89e` (32 agents): 2 graphify scouts, test+l10n inventories, 14 verify + 14 refute agents over every mockup surface | 14/14 surfaces grounded with file:line; 6 mockup copy claims refuted as lies-against-HEAD; 5 mockup "current state" claims misdescribe HEAD | hand to Planner |
| 2026-07-18 | Planner | compose_area.dart, direct_private_media_viewer.dart, conversation_screen.dart, settings_wired.dart, orbit_wired.dart, upload_progress_banner.dart, group_conversation_wired.dart, mic_permission_prompt.dart, app_en/ar/de.arb, run_test_gates.sh | Scope = copy + copy-plus-small-ui only; every needs-behavior-change surface deferred to named follow-ups | hand to Reviewer |
| 2026-07-18 | Reviewer (sufficiency) | 8-agent /tdd-review audit `wf_d3da2753-fc2` (2 verifiers, 5 dimension assessors, completeness critic) + orchestrator source cross-checks | D1 86 / D2 61 / D3 85 / D4 88 / D5 64; verdict "no — one mechanical revision pass required"; 5 material blockers, all with enumerated fixes (see Reviewer Findings) | apply v2 revision |
| 2026-07-18 | Arbiter | v2 of this plan | All 5 material blockers closed in place (TC-10 retarget, catalog-1 arithmetic, pins-to-update table, compile-RED quarantined to new file + required-param decision, analyze/l10n-commit gates). Rejected findings documented with reasons. | hand off to execution |
| 2026-07-18 | User + Planner (v2.1) | run_test_gates.sh array membership re-verified | feature-host-all too slow for a copy-only diff → host-all globs demoted to optional pre-commit; replaced by focused P4/P5 commands + stale-literal sweep (see Accepted Differences) | execute |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + counts) | gate green | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

## Source Of Truth
- Copy: **this plan's Copy Contract wins wherever it differs from the mockup**; every delta is refutation-driven or a HEAD-structure adaptation, recorded in Accepted Differences. (Known deltas: expiry detail reworded because the menu offers fixed durations — the mockup's "a time you choose" is picker-redesign copy; outgoing body drops ", in the app" as redundant with "Only {name} can view it"; typographic apostrophes normalized to the straight-quote ARB convention.)
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (no sim rows in this plan)
- Numbering / index: `Test-Flight-Improv/00-INDEX.md`
- Toolchain (corrected 2026-07-18, user directive — match the host): **host Flutter 3.41.4 via `/claude-host-bin/flutter`** (first on PATH in the container; executes on the Mac against `/workspace`, which is Mac-pub-resolved). `flutter gen-l10n` AND all `flutter test` runs happen in `/workspace` through the host shim — no scratchpad copy needed. NEVER run the outdated in-container 3.38.4 SDK (`/claude-home/tools/flutter`) against `/workspace`.

## Session Classification
implementation-ready

## Exact Problem Statement
The mockup revises user-facing copy so private-media choices read as consequences ("Keep in chat", "Protected view"), private bubbles reassure instead of rendering bare buttons, and feedback strings stop echoing titles or naming internal modes. On HEAD the composer chooser labels modes "Ordinary"/"Protected" (internal vocabulary), the received private-media bubble is a bare "Open private media" button with a one-word caption and no reassurance body, the sender bubble is a mode chip with no explanation, the mic-permission dialog title/body echo each other, settings save-failures show a control-naming string twice (inline **and** a redundant snackbar), the removed-from-group read-only banner hides the cause ("…you are not an active member"), ten Orbit invite-outcome snackbars are hardcoded English duplicates of existing ARB keys (broken ar/de), and the upload banner shows raw byte counts.

What must improve: the copy at each surface above, exactly per the Copy Contract below.
What must stay unchanged (→ preserved-green sentinels): the offline text-send promise "Will send when you're back online" (kept-as-is by the mockup, pinned by `conversation_wired_offline_send_ux_test.dart`); the red media-upload failure lane and its strings (behavior-owned, deferred); the mic prompt's "Not now"/"Open Settings" recovery; the hard-delete removed-from-group snackbar+pop branch; message send/upload/retry behavior everywhere.

## Root Cause (verify → refute confirmed; line-verified again by the /tdd-review audit)
Not a bug — a copy-quality modification. The grounded mechanism per surface:

- **Chooser**: 6 flat `PopupMenuItem`s over existing `PrivateMediaPolicy` values; labels are ARB keys `private_media_ordinary`/`private_media_protected`/… (`app_en.arb:1676-1687`; `compose_area.dart:346-426`; group sibling `group_conversation_screen.dart:1318-1383` reuses the same keys, single-line). Retitling = ARB value edits; detail lines for ordinary/protected = switching two items to the existing `_privateMediaMenuLabel` helper (`compose_area.dart:330-344`). NOTE: the PopupMenuButton **trigger Chip** (`compose_area.dart:417-423`, label from the `:349-358` switch) shows the selected-mode label and stays in the tree beneath the open menu — with the default ordinary policy, "Keep in chat" renders on BOTH the chip and the menu item (test arithmetic must expect 2). The group selector chip has the same shape.
- **Receiver bubble (1:1)**: `DirectPrivateMediaOpenPlaceholder` (`direct_private_media_viewer.dart:435-481`) receives only `{onOpen, opening, policy}`; body copy and the peer name require one new constructor param, available at the mounting site (`conversation_screen.dart:918-938`; `widget.contactUsername` declared at `:186` — citation audit-verified exact).
- **Sender bubble (1:1)**: `DirectPrivateMediaOutgoingPlaceholder` (`direct_private_media_viewer.dart:487-519`) renders mode label only; mounted at `conversation_screen.dart:905-907`; same param plumb for a body line.
- **Group receiver bubble does NOT inherit E4**: `group_conversation_screen.dart:931-942` wraps the bubble in a Semantics/GestureDetector tap target (label `private_media_open` at `:934`) — no placeholder widget. Deliberately left asymmetric (see Accepted Differences); group port belongs to the picker-redesign follow-up.
- **Mic permission**: already a rationale **dialog** with working "Open Settings" (`mic_permission_prompt.dart:17-47`; ARB `mic_perm_dialog_title/_body`). Title/body revision = pure ARB value edit.
- **Settings save failure**: inline `errorText` already wired (`settings_wired.dart:732`, `:388`; rendered `background_choice_control.dart:140-150`, `media_download_matrix_control.dart:115-126`); the snackbars at `settings_wired.dart:303-305`/`:372-374` are redundant duplicates of the same string.
- **Removed-from-group**: dominant retained path already replaces the composer with a persistent read-only banner whose removed-case text is `group_read_only_not_active` (`group_conversation_wired.dart:6554-6571`, banner `group_conversation_screen.dart:313-314, 1090-1115`). Value edit. Truthfulness bounds (audit-corrected): the `!_isCurrentUserActiveMember` fallback gate is removal-only in practice (voluntary leave hard-deletes, `leave_group_use_case.dart:49-55`; the check fails open on null peer/empty members, `group_conversation_wired.dart:1551-1554`), but the removed-**latch** fires on ANY `SendGroupMessageResult.unauthorized`, which has one reachable non-removal producer — a transient roster-read exception during a private-media send (`send_group_message_use_case.dart:1383-1388`, reason `roster_unavailable`). The latch self-heals on positive re-add (`group_conversation_wired.dart:6643-6652`). Accepted: rare, transient, self-healing — see Risks.
- **Orbit invites**: the **accept** switch at `orbit_wired.dart:1562-1606` hardcodes ten outcome strings that duplicate ARB keys `app_en.arb:1567-1580` byte-identically (audit re-verified all ten); the **decline** switch (`:1853-1859`) is ALREADY l10n on HEAD and already pinned by a passing de-locale test (`orbit_wired_test.dart:3861-3905`). Only the accept switch is in scope. The accept-**expired** outcome is UI-unreachable in a test: `pending_group_invite_card.dart:67` computes `isExpired` and `:180` disables Accept (`onPressed: isProcessing || isExpired ? null : onAccept`) — TC-10 therefore targets the accept-**notFound** outcome (hardcoded `'Invite no longer available'` at `:1563`), reachable by deleting the seeded invite behind the cached row (`_pendingGroupInvites` refreshes only on reload, `orbit_wired.dart:929-938`).
- **Upload banner**: `UploadProgressViewState` already exposes `progress` 0..1 (`upload_progress_banner.dart:16-20`); the byte label at `:22-24` is presentation-only. The banner has THREE mounting surfaces — 1:1 (`conversation_screen.dart:450-452`), group (`group_conversation_screen.dart:270-273`), and share picker (`share_target_picker_screen.dart:144-152`, which already overrides `title:` during the sending phase) — E7's byte→percent change lands on all three (ruled in-scope; share tests pin the byte label and are in the pins-to-update table).

Refuted / do-NOT-re-introduce (each verified by the grounding refute pass):
1. **"You can reopen it once here after sending"** (picker disclosure) — sender-side reopen does not exist; eligibility hard-denies outgoing parents (`private_media_action_eligibility.dart:141,164-166`; `conversation_screen.dart:900-907`).
2. **"No saving, sharing, or screenshots" / "can't … screenshot it"** — blanket screenshot-blocking is false on iOS (app's own capture-limit copy `app_en.arb:1693-1695`). Only save/share/forward denial is true (`private_media_action_eligibility.dart:111-118`).
3. **"Couldn't save. Check your connection…"** (settings) — the failing write is a local secure-keystore write, not network (`settings_wired.dart:283,359`; `background_preference_use_cases.dart:15-23`).
4. **"Your one view is still available." + Try again** (open failure) — post-lease prepare failures CONSUME the view (`direct_private_media_viewer_controller.dart:250-258`; only pre-frame decode rolls back :378-388), and no failure state reaches the UI today.
5. **"Link copied"** for QR — the QR payload is signed identity JSON, not a link; the "QR data copied" snackbar is **debug-only** (`qr_code_section.dart:47-49`) — not a production surface. Production copy-confirmations already use `showQuietConfirm`/inline swaps.
6. **Mic snackbar "Microphone permission is required…"** — already dead copy (`perm_microphone_record` unused; negative guards pin its absence at `conversation_wired_test.dart:9398,9485`, `group_conversation_wired_test.dart:14916,14986`).
7. **"Couldn't save this preference."** — no such string; HEAD has two distinct ARB strings, already shown inline.
8. **Removed-from-group "the screen otherwise stays the same"** — false; retained path already shows a persistent banner and disables the composer; the snackbar fires only on the legacy hard-delete branch that pops to root (`group_conversation_wired.dart:2082-2113`).
9. **"Sent to inbox"** — visible string does not exist (semantics-only `message_sent_via_inbox`, `letter_card.dart:1235`).
10. **Queued-media red-failure mismatch is real but behavior-owned**: media stamped `failed` genuinely auto-retries (`retry_incomplete_uploads_use_case.dart:176`; triggers `pending_message_retrier.dart:153-224,640`), yet honest queued presentation requires a new keepRetriable-style branch in the upload-failure path (`conversation_wired.dart:3589-3628` unconditionally restores composer + stamps failed) — NOT a copy swap. Deferred (see Scope).
11. **(from review)** TC-10 must NOT be written against the accept-expired or decline paths: expired is UI-unreachable (disabled button), decline is already l10n on HEAD — a decline-based "fallback" test would be GREEN on HEAD and violate INV-RED-FIRST.

## Real Scope
In scope (copy + copy-plus-small-ui only):
- **E1 — ARB value edits** (en+ar+de + `flutter gen-l10n`): `private_media_ordinary` "Ordinary"→"Keep in chat"; `private_media_protected` "Protected"→"Protected view"; `private_media_view_once_copy` →"Disappears after they open it once."; `private_media_expiry_device_local` →"Deleted from their device after this time."; `mic_perm_dialog_title` →"Allow microphone access"; `mic_perm_dialog_body` →"To record voice messages, turn it on in your phone's settings."; `settings_background_save_fail` and `settings_media_save_fail` →"Couldn't save. Try again."; `group_read_only_not_active` →"You were removed from this group. You can still read past messages."
- **E2 — new ARB keys** (5, en+ar+de): `private_media_ordinary_detail`, `private_media_protected_detail`, `private_media_protected_body_received` ({name}), `private_media_view_once_body_received`, `private_media_outgoing_body` ({name}) — values in the Copy Contract. Each `{name}` key ships with `"@<key>": {"placeholders": {"name": {"type": "String"}}}` in ALL THREE ARB files, mirroring the existing `@posts_header_subtitle` pattern (`app_en.arb:49-56`).
- **E3 — 1:1 chooser detail lines**: switch the ordinary/protected `PopupMenuItem`s in `compose_area.dart:366-375` to `_privateMediaMenuLabel` with the two new detail keys (`height: 72`, matching siblings). Group menu stays single-line (guarded — see catalog-2).
- **E4 — receiver/sender bubble bodies**: add a **`required String contactDisplayName`** param to `DirectPrivateMediaOpenPlaceholder` AND `DirectPrivateMediaOutgoingPlaceholder` (required ⇒ the compiler enforces both mounting sites, closing the blank-name-body hole); add a mode-discriminated body `Text` (bodySmall) BELOW the existing mode caption inside the open placeholder's Column (`:467-479`) — protected & disappearing → `private_media_protected_body_received`; viewOnce → `private_media_view_once_body_received`; the null/non-private early return keeps the bare button (no body). Outgoing placeholder gets `private_media_outgoing_body` below its mode label. Pass `widget.contactUsername` at both mounting sites (`conversation_screen.dart:905-907` outgoing, `:918-938` receiver). The existing const constructions in `direct_private_media_viewer_test.dart:993-1005` get `contactDisplayName: 'Layla'` added (a const-compatible string literal — the const list survives).
- **E5 — settings save-failure**: delete the two redundant `SnackBar` calls (`settings_wired.dart:303-305`, `:372-374`); inline `errorText` becomes the sole surface (it already exists and the sheets stay open with rollback).
- **E6 — Orbit invite outcome l10n unification** (accept switch only, full mapping — all byte-identical, audit-verified):
  | orbit_wired.dart | literal | ARB key |
  |---|---|---|
  | :1563 | Invite no longer available | group_invite_no_longer_available |
  | :1566 | Invite expired | group_invite_expired |
  | :1572 | Invite was revoked | group_invite_revoked |
  | :1575 | Invite already used | group_invite_already_used |
  | :1578 | Invite is for another identity | group_invite_wrong_identity |
  | :1581 | Invite needs fresh key material | group_invite_needs_key |
  | :1584 | Invite is no longer valid | group_invite_invalid |
  | :1587 | Group already added | group_invite_duplicate_group |
  | :1590, :1606 | Failed to accept invite | group_invite_accept_failed |
  (`:1569` already uses `l10n.group_invite_expired_ask_resend` — untouched.) Zero visible English change; fixes ar/de.
- **E7 — upload banner percent**: replace the byte label (`upload_progress_banner.dart:22-24`) with `'${(progress * 100).round()}%'`; title stays `upload_progress_title` ("Uploading media" — shared with `letter_card.dart:915,934` and `media_grid_cell.dart:275`, so it must NOT become media-kind-specific). Propagates to all three mounting surfaces (1:1, group, share) — in-scope; the two share byte-label test pins are updated (pins table).

Out of scope (deferred, named owner):
- Offline/queued media presentation, terminal-cause discrimination ("Photo is no longer on this phone"), upload "Sent" confirmation, and the durable-outbox worker → **follow-up plan "offline media outbox" (mockup §03)**.
- Sender one-more-look reopen ("View photo" on outgoing bubble) and any "reopen once" copy → same follow-up or its own plan (new eligibility lane + lifecycle path).
- View-once open-failure UI ("Couldn't open this photo") → blocked on a consumed/not-consumed failure signal (refuted item 4).
- Picker structural redesign (bottom sheet, 4-option nesting with "Set an expiry"/"Delete after" duration panel, summary chip + "Change", per-mode disclosure, CTA), `{name}` interpolation in picker copy, and the **group receiver-bubble reassurance port** → **follow-up "protection picker sheet"**.
- Orbit invite row-state port (outcome-on-the-row exists on group-list already) and "Ask for a new invite" (needs a recipient→admin request signal that doesn't exist) → follow-up.
- Mic dialog→bottom-sheet conversion → no user value beyond presentation.
- QR/copy-success changes → refuted item 5 (debug-only surface; production already quiet).
- Media-kind-aware button labels ("Open photo"/"View photo") → deferred with the picker redesign. Button strings `private_media_open`/`private_media_opening` stay.

## Files To Inspect Next
Production: `lib/l10n/app_en.arb`, `app_ar.arb`, `app_de.arb` (+ regenerated `app_localizations*.dart`); `lib/features/conversation/presentation/widgets/compose_area.dart`; `lib/features/conversation/presentation/screens/direct_private_media_viewer.dart`; `lib/features/conversation/presentation/screens/conversation_screen.dart`; `lib/features/settings/presentation/screens/settings_wired.dart`; `lib/features/orbit/presentation/screens/orbit_wired.dart`; `lib/features/conversation/presentation/widgets/upload_progress_banner.dart`
Direct tests (extended in place): `conversation_private_media_composer_test.dart`; `direct_private_media_viewer_test.dart`; `group_conversation_wired_test.dart`; `settings_wired_test.dart`; `orbit_wired_test.dart` (harness: `buildOrbitWired`, `orbit_wired_test.dart:284` locale param, de-locale precedent `:3879-3886`, `makePendingInvite` `:481-600`, `tapPendingGroupInviteAccept` `:390-411`)
NEW test files: `test/features/conversation/presentation/screens/direct_private_media_placeholder_body_test.dart` (catalog-3/5/12 — quarantines the compile-RED); `test/core/permissions/mic_permission_prompt_test.dart`; `test/features/conversation/presentation/widgets/upload_progress_banner_test.dart`
Pins-to-update (existing literal assertions of OLD copy — see table): `group_conversation_wired_test.dart`, `conversation_wired_test.dart`, `conversation_private_media_composer_test.dart`, `settings_sub_sheets_test.dart`, `share_target_picker_screen_test.dart`, `share_target_picker_wired_test.dart`
Dependency-only context: `lib/core/permissions/mic_permission_prompt.dart`; `lib/features/groups/presentation/screens/group_conversation_screen.dart`; `lib/features/settings/presentation/widgets/background_choice_control.dart`, `media_download_matrix_control.dart`; `lib/features/groups/presentation/widgets/pending_group_invite_card.dart` (why accept-expired is untestable); `lib/features/groups/domain/repositories/pending_group_invite_repository.dart:31` (`deletePendingInvite` for TC-10 seeding)

## Existing Tests Covering This Area (audit-corrected)
- `conversation_private_media_composer_test.dart` — selector visibility + typed policy emission by widget key, **but :207-214 literally pins the two detail strings E1 changes** (updated by catalog-1)
- `direct_private_media_viewer_test.dart` — placeholder strings via l10n getters incl. RTL test (:960) (getter-based, survives value edits; its const placeholder constructions :993-1005 gain the new required param at GREEN)
- `conversation_wired_test.dart` — sentinels for upload-failure strings (:1320 etc.) + mic guards, **but :1222 pins `find.text('Ordinary')`** (updated per pins table; the update doubles as the chip-default sentinel)
- `group_conversation_wired_test.dart` — hard-delete snackbar sentinel (:9617, stays green — exact-match `find.text` does not collide with the longer new banner string), **but pins the current `group_read_only_not_active` value at 8 sites** (5 single-line + 3 multi-line concat; pins table)
- `settings_wired_test.dart` (:860, :1183) AND **`settings_sub_sheets_test.dart` (:217)** pin current save-fail strings (updated by catalog-8 + pins table)
- `share_target_picker_screen_test.dart:331` + `share_target_picker_wired_test.dart:781` pin the byte label `'25 B / 100 B'` (updated per pins table → `'25%'`)
- `conversation_wired_offline_send_ux_test.dart` — pins the kept-as-is offline text strings literally (sentinel, untouched)
- `group_list_wired_test.dart` — 'Invite declined' (:2036) (untouched surface)
- Orbit: `orbit_wired_test.dart:3861-3905` "orbit decline snackbars are localized" (de) — passing sentinel proving the DECLINE path is already l10n; no test covers the hardcoded ACCEPT path (→ TC-10)
- MISSING: chooser label copy assertions; placeholder body copy; mic dialog copy; accept-path outcome localization; banner label format
Already in curated family arrays?: `conversation_wired_test` (:83), `conversation_wired_offline_send_ux_test` (:93), `direct_private_media_viewer_test` (:220) in `ONE_TO_ONE_TESTS`; `group_conversation_wired_test`, `group_list_wired_test` (:334-335) in `GROUP_TESTS`. All other named files auto-glob only.

## Existing Pins To Update (in-place edits shipped WITH the production change — expected reds otherwise)
| # | File:line | Old pinned literal | New assertion |
|---|---|---|---|
| P1 | `group_conversation_wired_test.dart` :4417(concat), :8062, :8134, :8381, :8425, :8724-8725(concat), :8794-8795(concat), :9238 | "You can read this group's history, but you are not an active member." (8 sites — grep the fragment `not an active`, NOT the full sentence: 3 sites are adjacent-string concatenations) | "You were removed from this group. You can still read past messages." |
| P2 | `conversation_private_media_composer_test.dart:207-214` | 'Available for one view on this device.' findsOneWidget; 'The expiry time is calculated on the receiving device.' findsNWidgets(3) | new detail values (folded into catalog-1) |
| P3 | `conversation_wired_test.dart:1222` | `find.text('Ordinary')` findsOneWidget | `find.text('Keep in chat')` findsOneWidget (chip default after policy reset — doubles as chip-default sentinel) |
| P4 | `settings_sub_sheets_test.dart:217` | 'Background choice could not be saved' findsWidgets | "Couldn't save. Try again." findsOneWidget (inline only, post-E5) |
| P5 | `share_target_picker_screen_test.dart:331`, `share_target_picker_wired_test.dart:781` | `find.text('25 B / 100 B')` | `find.text('25%')` |
| P6 | `background_choice_control_test.dart:384,387` | supplies `errorText: 'Background choice could not be saved'` as a direct widget param (does NOT break on E1 — fixture-owned literal) | supply "Couldn't save. Try again." — keeps the fixture realistic and the stale-literal sweep at zero |

## Copy Contract (authoritative values; ar/de are Claude-curated, land with the en edit)
| Key | New en value | ar | de |
|---|---|---|---|
| private_media_ordinary | Keep in chat | يبقى في الدردشة | Im Chat behalten |
| private_media_protected | Protected view | عرض محمي | Geschützte Ansicht |
| private_media_view_once_copy | Disappears after they open it once. | يختفي بعد أن يفتحوه مرة واحدة. | Verschwindet, nachdem es einmal geöffnet wurde. |
| private_media_expiry_device_local | Deleted from their device after this time. | يُحذف من جهازهم بعد هذه المدة. | Wird nach dieser Zeit von ihrem Gerät gelöscht. |
| private_media_ordinary_detail (NEW) | They can save or share it. | يمكنهم حفظه أو مشاركته. | Kann gespeichert oder geteilt werden. |
| private_media_protected_detail (NEW) | They can view it again, but not save or share it. | يمكنهم مشاهدته مجددًا دون حفظه أو مشاركته. | Kann erneut angesehen, aber nicht gespeichert oder geteilt werden. |
| private_media_protected_body_received (NEW, {name}) | You can view it again. {name} doesn't allow saving or sharing. | يمكنك مشاهدته مجددًا. {name} لا يسمح بالحفظ أو المشاركة. | Du kannst es erneut ansehen. {name} erlaubt kein Speichern oder Teilen. |
| private_media_view_once_body_received (NEW) | You can only view this once. | يمكنك مشاهدة هذا مرة واحدة فقط. | Du kannst dies nur einmal ansehen. |
| private_media_outgoing_body (NEW, {name}) | Only {name} can view it. They can't save or share it. | {name} فقط يمكنه مشاهدته، ولا يمكنه حفظه أو مشاركته. | Nur {name} kann es ansehen und weder speichern noch teilen. |
| mic_perm_dialog_title | Allow microphone access | السماح بالوصول إلى الميكروفون | Mikrofonzugriff erlauben |
| mic_perm_dialog_body | To record voice messages, turn it on in your phone's settings. | لتسجيل الرسائل الصوتية، فعِّله من إعدادات هاتفك. | Um Sprachnachrichten aufzunehmen, aktiviere ihn in den Einstellungen deines Telefons. |
| settings_background_save_fail | Couldn't save. Try again. | تعذّر الحفظ. حاول مجددًا. | Speichern fehlgeschlagen. Versuch es erneut. |
| settings_media_save_fail | Couldn't save. Try again. | تعذّر الحفظ. حاول مجددًا. | Speichern fehlgeschlagen. Versuch es erneut. |
| group_read_only_not_active | You were removed from this group. You can still read past messages. | تمت إزالتك من هذه المجموعة. لا يزال بإمكانك قراءة الرسائل السابقة. | Du wurdest aus dieser Gruppe entfernt. Du kannst frühere Nachrichten weiterhin lesen. |

Parity invariant: en/ar/de each go 875 → 880 keys (5 new), zero missing/extra (current 875/875/875 audit-verified).

## RED Test Catalog (add BEFORE any production code — INV-RED-FIRST)
Authoring order (quarantines the compile-RED): FIRST author catalog-1/2/4/6a/6b/8/9/10/11 (assertion-REDs in existing/new-independent files) and record their failure reasons; THEN create the new placeholder-body file (catalog-3/5/12) whose whole-file compile-RED is expected (plan-211 precedent: compile-RED is acceptable for a brand-NEW file; the 16 existing viewer tests keep compiling and running through the whole RED phase).

1. `conversation_private_media_composer_test.dart`::`private media menu uses consequence-led labels and details` (updates P2 in place)
   - Tier: widget. Setup: existing harness; open `private-media-selector` menu (the trigger Chip stays in the tree beneath the menu).
   - RED on HEAD: menu renders "Ordinary"/"Protected"; the four detail strings don't exist.
   - GREEN asserts: `find.text('Keep in chat')` **findsNWidgets(2)** (trigger chip at default-ordinary + menu item — documented chip double-render); `find.text('Protected view')`, `find.text('They can save or share it.')`, `find.text('They can view it again, but not save or share it.')`, `find.text('Disappears after they open it once.')` each findsOneWidget; `find.text('Deleted from their device after this time.')` findsNWidgets(3); `find.text('Ordinary')` findsNothing.
   - Mutation: revert E1/E3 → red.
2. `group_conversation_wired_test.dart`::`group private media menu uses consequence-led labels`
   - Tier: widget. Setup: group harness, open `group-private-media-selector`.
   - RED on HEAD: "Ordinary"/"Protected" render.
   - GREEN asserts: 'Keep in chat' + 'Protected view' **findsWidgets** (deliberately tolerant — group trigger chip shares the double-render shape); 'Ordinary' findsNothing; **'They can save or share it.' findsNothing** (negative guard locking the group menu single-line Accepted Difference).
   - Mutation: revert E1 → red.
3. NEW `direct_private_media_placeholder_body_test.dart`::`protected placeholder shows sender-attributed reassurance body`
   - Tier: widget. Setup: pump `DirectPrivateMediaOpenPlaceholder(policy: protected, contactDisplayName: 'Layla', …)`.
   - RED on HEAD: whole-file compile-RED — `contactDisplayName` param does not exist (new file; existing viewer file unaffected).
   - GREEN asserts: `find.text("You can view it again. Layla doesn't allow saving or sharing.")` findsOneWidget.
   - Mutation: revert E4 body/param → red.
4. `direct_private_media_viewer_test.dart`::`view-once placeholder states single view`
   - Tier: widget. RED: body absent on HEAD (assertion-RED — file still compiles; the body assertion uses l10n getter/literal only, no new param needed at RED). GREEN: `find.text('You can only view this once.')`; discriminator: protected body findsNothing. Mutation: revert E4 mode switch → red.
5. NEW file (same as 3)::`outgoing placeholder explains recipient-only view without screenshot claim`
   - Tier: widget. RED: compile-RED (shared with catalog-3, same new file). GREEN: `find.text("Only Layla can view it. They can't save or share it.")`; **discriminator: `find.textContaining('screenshot')` findsNothing** (locks refuted item 2 out). Mutation: revert E4 outgoing body → red.
6. TC-06 sibling-consistency, two named halves with explicit RED commands:
   - 6a `direct_private_media_viewer_test.dart`::`mode caption renders Protected view` — RED: caption resolves to "Protected". GREEN: `private-media-mode-label` renders "Protected view". Mutation: revert `private_media_protected` value → red.
   - 6b `conversation_private_media_composer_test.dart`::`chip renders Protected view after protected selection` — RED: chip shows "Protected". GREEN: after selecting protected, chip label is "Protected view". Mutation: same revert → red.
7. NEW `test/core/permissions/mic_permission_prompt_test.dart`::`denied mic prompt uses allow-microphone copy with settings recovery`
   - Tier: widget (dialog). Setup: `MaterialApp` + real l10n delegates; call `showMicPermissionDeniedPrompt` with a recording fake `MicPermissionGateway`.
   - RED on HEAD: title is "Microphone access needed", body "…allow microphone access in Settings."
   - GREEN asserts: 'Allow microphone access' + "To record voice messages, turn it on in your phone's settings." + 'Not now' + 'Open Settings' present; tapping 'Open Settings' invokes `gateway.openAppSettings()`.
   - Mutation: revert `mic_perm_dialog_*` values → red.
8. `settings_wired_test.dart`::`save failure shows inline couldnt-save copy and no snackbar` (background + media-matrix variants; updates :860/:1183 in place)
   - Tier: widget. RED on HEAD: old strings AND a SnackBar appears (today the string renders on BOTH surfaces, masked by findsWidgets — audit-verified).
   - GREEN asserts: inline errorText "Couldn't save. Try again." findsOneWidget AND `find.byType(SnackBar)` findsNothing (inline-present ∧ snackbar-absent discriminator).
   - Mutation: restore the deleted snackbar call or revert the ARB value → red.
9. `group_conversation_wired_test.dart`::`removed member sees removed-banner copy on retained group` (P1 updates ship together)
   - Tier: widget. RED on HEAD: banner text is the old not-active sentence.
   - GREEN asserts: `find.text('You were removed from this group. You can still read past messages.')` findsOneWidget; hard-delete snackbar assertion (:9617) untouched and still green.
   - Mutation: revert `group_read_only_not_active` value → red.
10. `orbit_wired_test.dart`::`accept feedback for a missing invite is localized under ar` (RETARGETED per audit — accept-notFound outcome)
    - Tier: widget. Setup: seed a VALID invite via `makePendingInvite`; pump `buildOrbitWired(locale: const Locale('ar'), …)` (locale param `:284`, de precedent `:3879-3886`); `await pendingInviteRepo.deletePendingInvite(invite.groupId)` (row survives via the cached `_pendingGroupInvites` list, `orbit_wired.dart:929-938`); `tapPendingGroupInviteAccept` (`:390-411`); settle.
    - RED on HEAD: hardcoded English `'Invite no longer available'` (`orbit_wired.dart:1563`) renders regardless of locale.
    - GREEN asserts: `find.text(AppLocalizationsAr().group_invite_no_longer_available)` findsOneWidget AND `find.text('Invite no longer available')` findsNothing (locale discriminator — proves l10n lookup).
    - Fallback if the delete seam is awkward in the harness: seed a REVOKED invite (use case `:174-183`) → hardcoded `'Invite was revoked'` (`:1572`), same assertion shape. Do NOT use accept-expired (disabled button) or any decline path (already l10n).
    - Mutation: revert the E6 notFound line → red.
11. NEW `upload_progress_banner_test.dart`::`upload banner shows percent progress with unchanged title`
    - Tier: widget. Setup: pump `UploadProgressBanner(state: UploadProgressViewState(sentBytes: 68, totalBytes: 100))`.
    - RED on HEAD: byte-formatted label, no percent text.
    - GREEN asserts: `find.textContaining('68%')` findsOneWidget; title 'Uploading media' findsOneWidget (guards the shared `upload_progress_title` key); `find.textContaining(' / ')` findsNothing.
    - Mutation: revert E7 label → red.
12. NEW file (same as 3)::`reassurance bodies render localized and RTL-safe under ar`
    - Tier: widget. Setup: pump both placeholders under `Locale('ar')` + `Directionality.rtl` with `contactDisplayName` (mirrors the :960 RTL test pattern).
    - RED on HEAD: compile-RED (shared with catalog-3/5).
    - GREEN asserts: the ar values of `private_media_protected_body_received` / `private_media_outgoing_body` (via `AppLocalizationsAr()` getters with the name substituted) render without overflow.
    - Mutation: drop the ar ARB entries or the @-placeholder metadata → red (missing getter/compile or missing-substitution failure).

## Test Coverage Matrix (ZERO empty cells)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 chooser 1:1 labels+details | UI copy (chip double-render aware) | widget | conversation_private_media_composer_test.dart::catalog-1 | old labels, no details | revert E1/E3 | `flutter test …/conversation_private_media_composer_test.dart` | AUTO (features glob) |
| TC-02 chooser group propagation + single-line guard | UI copy, shared key | widget | group_conversation_wired_test.dart::catalog-2 | old labels | revert E1 | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS |
| TC-03 receiver protected body | UI copy + required-param plumb | widget | direct_private_media_placeholder_body_test.dart::catalog-3 | compile-RED (new file; param absent on HEAD) | revert E4 | `flutter test …/direct_private_media_placeholder_body_test.dart` | AUTO (features glob) + **add to ONE_TO_ONE_TESTS** beside run_test_gates.sh:220 |
| TC-04 receiver view-once body | UI copy, mode discrim | widget | direct_private_media_viewer_test.dart::catalog-4 | assertion-RED: no body | revert E4 mode switch | `flutter test …/direct_private_media_viewer_test.dart` | already in ONE_TO_ONE_TESTS |
| TC-05 outgoing body, no screenshot claim | UI copy + honesty lock | widget | direct_private_media_placeholder_body_test.dart::catalog-5 | compile-RED (same new file) | revert E4 outgoing | same as TC-03 | same as TC-03 |
| TC-06 mode caption/chip consistency | shared-key sibling | widget | catalog-6a (viewer file) + catalog-6b (composer file) | caption/chip still "Protected" | revert E1 protected value | both --plain-name cmds in block 1 | ONE_TO_ONE_TESTS + AUTO |
| TC-07 mic dialog copy | UI copy | widget | mic_permission_prompt_test.dart::catalog-7 | old title/body | revert E1 mic values | `flutter test test/core/permissions/mic_permission_prompt_test.dart` | AUTO (core glob; classify_path 'core component direct suite' — discovery proven by the completeness check, no full core-host-all run required) |
| TC-08 settings inline-only save error | UI copy + snackbar removal | widget | settings_wired_test.dart::catalog-8 | old strings + snackbar present | restore snackbar lines / revert values | `flutter test …/settings_wired_test.dart` | AUTO (features glob) |
| TC-09 removed-banner copy | UI copy | widget | group_conversation_wired_test.dart::catalog-9 | old banner value | revert E1 group_read_only_not_active | `./scripts/run_test_gates.sh groups` | already in GROUP_TESTS |
| TC-10 orbit accept-outcome l10n (notFound) | l10n unification | widget | orbit_wired_test.dart::catalog-10 | hardcoded English under ar | revert E6 notFound line | `flutter test …/orbit_wired_test.dart` | AUTO (features glob) |
| TC-11 upload banner percent + title guard | UI presentation + shared-key guard | widget | upload_progress_banner_test.dart::catalog-11 | byte label, no % | revert E7 | `flutter test …/upload_progress_banner_test.dart` | AUTO (features glob) |
| TC-12 ar/RTL body rendering | l10n {name} substitution + RTL | widget | direct_private_media_placeholder_body_test.dart::catalog-12 | compile-RED (same new file) | drop ar entries/@-metadata | same as TC-03 | same as TC-03 |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability**: N/A — every edit is stateless copy or a constructor-prop plumb; no latches/caches/derived flags added. The settings inline error is pre-existing state with unchanged semantics (rollback + sheet-stays-open verified at `settings_wired.dart:287,362,739-742`).
- **Sibling-surface consistency**: covered — TC-02 (group menu propagation + single-line negative guard), TC-06a/6b (caption+chip from one key), TC-11 title guard (`upload_progress_title` consumers stay "Uploading media"), TC-07 asserts 'Open Settings' unchanged (`compose_open_settings` shared with `compose_post_sheet.dart:862` — value untouched). Non-inheriting siblings NAMED: group receiver bubble (`group_conversation_screen.dart:931-942`, semantics-only — deliberate asymmetry, Accepted Differences); all three `UploadProgressBanner` mounts enumerated in E7.
- **Destructive-action side-effects**: covered — TC-08 asserts what is removed (the snackbar) AND what is preserved (inline error; existing rollback assertions stay green).
- **Invariant re-verification under new transitions**: N/A — no new state transitions introduced.
- Untested-assumption guard: offline text promise pinned by `conversation_wired_offline_send_ux_test.dart`; red media-failure lane pinned by `conversation_wired_test.dart:1320,8382,8652,8675`; mic legacy-key absence pinned by 4 findsNothing guards; hard-delete snackbar pinned by `:9617`; group menu single-line pinned by catalog-2's negative guard; chip default pinned by P3's updated assertion. None left untested.

## Invariants (locked by tests)
- INV-1: Private-media copy never claims screenshot blocking → catalog-5 discriminator.
- INV-2: The offline text promise string is byte-identical to HEAD → offline-send UX sentinel.
- INV-3: One shared mode key renders identically on chooser chip, receiver caption, and outgoing label → catalog-6a+6b.
- INV-4: `upload_progress_title` stays media-kind-neutral → catalog-11 title assertion.
- INV-5: en/ar/de ARB key parity (880/880/880) → parity gate (runs against /workspace).
- INV-6: `contactDisplayName` is a required param → compiler enforces both mounting sites (no blank-name body can ship silently).
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan (per-slice green checkpoints — no all-red-then-all-green waterfall)
1. Contract extraction: record `git status --short` (pre-existing light-theme diffs — do not revert). Baselines: `./scripts/run_test_gates.sh 1to1` (B3) and `groups` (B4) — fresh counts supersede the ≈ priors; `flutter analyze > analyze_baseline.txt` (B5). Host-all globs (feature-host-all / core-host-all) are NOT required for this plan — coverage is replaced by the focused P4/P5 commands + the stale-literal sweep in block 4; an optional one-time feature-host-all run before commit is allowed but never gates iteration (user decision 2026-07-18).
2. RED authoring, in quarantine order: (a) assertion-REDs — catalog-1, 2, 4, 6a, 6b, 8, 9, 10, 11 (+ pins P1–P5 updated in the same commits as their tests) — run each focused command, record its documented failure; (b) THEN the new `direct_private_media_placeholder_body_test.dart` (catalog-3/5/12) — whole-file compile-RED recorded once. Resolve TC-10's seeding (delete vs revoked variant) HERE, before any production edit.
3. E1+E2: edit the three ARBs in /workspace per the Copy Contract (incl. the two `@…placeholders` blocks); `flutter gen-l10n` in /workspace; run the parity gate against /workspace; sync `lib/` to the scratchpad copy. **Checkpoint: catalog-2, 7, 9 go green** (pure ARB propagation).
4. E3 (chooser two-line items). **Checkpoint: catalog-1 green.**
5. E4 (required `contactDisplayName` + bodies + mounting sites + the :993-1005 const call-site updates). Stop-if: any need to touch the viewer controller, eligibility engine, or lifecycle engine → replan. **Checkpoint: catalog-3/5/12 compile+green, catalog-4/6a green.**
6. E5 (delete two snackbar blocks). **Checkpoint: catalog-8 green; P4 green.**
7. E6 (accept-switch l10n swap per mapping table). **Checkpoint: catalog-10 green.**
8. E7 (percent label). **Checkpoint: catalog-11 green; P5 green.**
9. Full preservation + named gates + hygiene (blocks 4–5 below).

## Risks And Edge Cases
- Removed-latch honesty bound: `SendGroupMessageResult.unauthorized` from a transient `roster_unavailable` (`send_group_message_use_case.dart:1383-1388`) can transiently render the removed-banner copy to a still-member until the latch self-heals on re-add (`:6643-6652`). Accepted: rare, transient, self-healing, and the OLD copy misled in the same scenario (claimed "not an active member"). Do not add cause-discrimination here (behavior work).
- Empty/odd `contactUsername` renders a blank name in the body → required-param + catalog-3 pin a normal name; execution adds no invented fallback.
- `{name}` grammar in ar (gendered verbs) — curated values use masculine-default forms consistent with existing ar copy; RTL + substitution locked by catalog-12.
- Two-line ordinary/protected menu items change popup height — visual-only; no menu count/height assertions exist (audit-verified).
- TC-10 seeding relies on the cached `_pendingGroupInvites` list not refreshing between delete and tap (`orbit_wired.dart:929-938`); if a reactive reload fires in the harness, use the revoked-invite variant instead.
- Share-picker byte→percent propagation is a user-visible change on the share screen — deliberately in-scope (consistency), P5 locks it.

## Device/Relay Proof Profile
host-only for closure — copy/presentation changes with no OS-boundary, DB, crypto, transport, or multi-device behavior. No `/sims` scenario, no device-proof, no migration (no `DB v##`).
PROD-CRITICAL leg: N/A (justified) — no wire/transport leg is touched; the nearest transport-adjacent surfaces (offline snackbar, upload-failure lane) are explicitly frozen and sentinel-pinned. (Audit concurred: demanding a device leg here would itself be over-engineering.)

## Acceptance Gates (literal — everything runs in /workspace via the host Flutter 3.41.4 shim on PATH)
```bash
# 0) Baselines (before any edit) — fresh captures are authoritative; ≈ figures are stale priors
git status --short                                     # snapshot dirty tree
./scripts/run_test_gates.sh 1to1                       # B3 (prior ≈1,672)
./scripts/run_test_gates.sh groups                     # B4 (prior ≈1,926)
flutter analyze > analyze_baseline.txt 2>&1; tail -1 analyze_baseline.txt   # B5 issue count

# 1) RED (per authoring order in step 2) — every command must FAIL for its documented reason
flutter test test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart --plain-name 'private media menu uses consequence-led labels and details'
flutter test test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart --plain-name 'chip renders Protected view after protected selection'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'group private media menu uses consequence-led labels'
flutter test test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart --plain-name 'view-once placeholder states single view'
flutter test test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart --plain-name 'mode caption renders Protected view'
flutter test test/core/permissions/mic_permission_prompt_test.dart
flutter test test/features/settings/presentation/screens/settings_wired_test.dart --plain-name 'save failure shows inline couldnt-save copy and no snackbar'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'removed member sees removed-banner copy on retained group'
flutter test test/features/orbit/presentation/screens/orbit_wired_test.dart --plain-name 'accept feedback for a missing invite is localized under ar'
flutter test test/features/conversation/presentation/widgets/upload_progress_banner_test.dart
flutter test test/features/conversation/presentation/screens/direct_private_media_placeholder_body_test.dart   # whole-file compile-RED (new file)

# 2) l10n regen + parity (in /workspace, after ARB edits; then sync lib/ to scratchpad)
flutter gen-l10n
python3 - <<'EOF'
import json,sys
c={f:len([k for k in json.load(open(f'lib/l10n/app_{f}.arb'))if not k.startswith('@')])for f in('en','ar','de')}
print(c); sys.exit(0 if len(set(c.values()))==1 and c['en']==880 else 1)
EOF

# 3) Direct GREEN — every command in block 1 now passes (11 commands, 13 catalog tests + P1-P5 updated pins)

# 4) Preservation sentinels + named gates (counts = fresh baseline + new tests, 0 fail)
flutter test test/features/conversation/presentation/screens/conversation_wired_offline_send_ux_test.dart
./scripts/run_test_gates.sh 1to1        # expect B3 + new tests (catalog-4/6a + updated :1222; also runs share_target_picker_wired_test and the pinned placeholder-body file)
./scripts/run_test_gates.sh groups      # expect B4 + 2 new group tests (P1 pins updated in place; also runs orbit_wired_test)
flutter test test/features/share/presentation/share_target_picker_screen_test.dart      # P5 — in no curated array
flutter test test/features/settings/presentation/screens/settings_sub_sheets_test.dart  # P4 — in no curated array
# Stale-literal sweep — proves the P1-P5 pin sweep is complete without running the host-all globs
grep -rn -e "not an active" -e "Available for one view" -e "expiry time is calculated" \
  -e "text('Ordinary')" -e "Background choice could not be saved" \
  -e "Couldn't save media download settings" -e "25 B / 100 B" test/ \
  | grep -v "reason:"    # expect ZERO output lines (the one 'reason:' hit is a comment, not a pin)
# Dry-run verified 2026-07-18: on HEAD this sweep finds exactly the P1-P6 sites (18 lines) and nothing else,
# so zero-after-change proves the pin sweep is complete.
# OPTIONAL, pre-commit only — not a required gate and never gates the iteration loop:
# ./scripts/run_host_test_gates.sh feature-host-all   # prior ≈731 files + 3 new

# 5) Hygiene (includes the committed-l10n staleness discriminator)
flutter analyze > analyze_after.txt 2>&1; diff <(tail -1 analyze_baseline.txt) <(tail -1 analyze_after.txt)  # 0 new vs B5
grep -q 'Keep in chat' /workspace/lib/l10n/app_localizations_en.dart && \
  grep -q 'private_media_outgoing_body' /workspace/lib/l10n/app_localizations.dart   # committed generated dart is fresh
git diff --check
```

## Known-Failure Interpretation
- Expected RED: the block-1 commands, each for its catalog-documented reason (the new placeholder-body file as a whole-file compile-RED; everything else assertion-RED).
- Expected reds during implementation if pins lag their edit: P1 (8 banner pins, groups gate), P2 (composer details), P3 ('Ordinary' chip), P4 (settings sub-sheet), P5 (share byte labels) — these are PLANNED in-place updates shipped with their production slice, NOT scope drift.
- Pre-existing dirty: light-theme readability edits in 10 lib files + 2 test files and untracked docker-ws/graphify artifacts — never revert.
- Environment blocker (NOT product): missing scratchpad Flutter test copy → create it per the local-toolchain convention.
- Scope drift (BLOCKING): any diff in `conversation_wired.dart` send/upload/retry paths, `direct_private_media_viewer_controller.dart`, `private_media_action_eligibility.dart`, `private_media_lifecycle_engine.dart`, group selector structure, `group_compose_area.dart`, or the group receiver-bubble mounting (`group_conversation_screen.dart:931-942`).

## Done Criteria
- [ ] RED added first in the quarantine order; each block-1 command failed for its documented reason.
- [ ] Mutation-verified: each production edit named in the matrix re-reds its row when reverted.
- [ ] Direct GREEN + preservation sentinels + named gates pass at fresh-baseline+new counts; P1–P5 updated in place and the stale-literal sweep returns zero hits.
- [ ] No migration (none needed); no sim/device rows (host-only closure).
- [ ] en/ar/de parity 880/880/880 verified in /workspace; committed `app_localizations*.dart` passes the block-5 staleness grep.
- [ ] flutter analyze 0 new vs recorded B5; git diff --check clean; no Scope Guard violations.
- [ ] New placeholder-body test file added to ONE_TO_ONE_TESTS (run_test_gates.sh, beside :220) and visible in the gate run.

## Scope Guard (hard "Do not")
- Do not change send/upload/retry/queue behavior or add any new branch to the media upload-failure path (follow-up "offline media outbox" owns it).
- Do not add sender-side reopen, "View photo" on outgoing bubbles, or any "reopen after sending" copy.
- Do not add open-failure UI or "your one view is still available" copy (blocked on consumed/not-consumed signal).
- Do not restructure the picker (no bottom sheet, no 4-option nesting, no summary chip, no disclosure/CTA) and do not interpolate `{name}` in picker copy.
- Do not touch the group receiver-bubble mounting (`group_conversation_screen.dart:931-942`) — the group reassurance port is deferred.
- Do not claim screenshot blocking anywhere; do not add "Check your connection" to settings save errors.
- Do not write TC-10 against accept-expired (disabled button) or any decline path (already l10n) — refuted item 11.
- Do not remove the `perm_microphone_record` ARB key (4 negative guards reference the getter) or convert the mic dialog to a sheet.
- Do not rename/retitle shared keys beyond the Copy Contract — in particular `upload_progress_title` and `compose_open_settings` keep their values.
- Do not touch `group_removed_snackbar` (hard-delete branch) or the orbit decline+UNDO flow.
- Do not edit `app_localizations*.dart` by hand — only via `flutter gen-l10n`.
- Do not `pub get` in /workspace; ARB edits + gen-l10n in /workspace, tests in the scratchpad copy.

## Accepted Differences / Intentionally Out Of Scope
- Copy Contract deltas vs mockup §06 (Copy Contract wins): expiry detail says "Deleted from their device after this time." because the menu offers fixed durations ("a time you choose" is picker-redesign copy) and "Deleted" names the event; outgoing body drops ", in the app" as redundant; typographic apostrophes normalized to the repo's straight-quote ARB convention.
- The §06 composer line "You can't send messages in this group" is structurally moot on HEAD — the read-only banner REPLACES the composer (`group_conversation_screen.dart:313-314, 1090-1115`); the single banner string carries both sentences.
- Receiver **disappearing**-mode bubbles reuse the protected body — truthful (viewable until expiry); a dedicated expiry body belongs to the picker-redesign follow-up.
- Group chooser stays single-line (guarded by catalog-2's negative assert); group receiver bubble keeps tap-to-open with no reassurance body (`group_conversation_screen.dart:931-942`) — group port deferred with the picker redesign.
- Button labels stay "Open private media"/"Opening private media…" — media-kind-aware labels deferred (kind plumb).
- Composer detail copy is name-free ("They…") — `{name}` interpolation deferred with the picker redesign; group cannot name a single recipient at all.
- Orbit invite outcomes stay snackbars (row-state port deferred); "Ask for a new invite" not built (no recipient→admin signal exists).
- QR copy snackbar untouched (debug-only surface, refuted item 5).
- Host-all glob gates (`feature-host-all` / `core-host-all`) are NOT required for closure of this copy-only diff (user decision 2026-07-18): every affected test file runs via a focused command or the 1to1/groups curated gates (verified: `orbit_wired_test` is in GROUP_TESTS :337, `share_target_picker_wired_test` in both family arrays :194/:442); repo-wide compile risk from the required param is covered by `flutter analyze`, and pin-sweep completeness by the block-4 stale-literal grep. The only two gate-invisible files (`share_target_picker_screen_test`, `settings_sub_sheets_test`) get their own focused commands. An optional one-time `feature-host-all` pre-commit sweep is permitted.

## Dependency Impact
- Follow-up "offline media outbox" (mockup §03) will reuse this plan's vocabulary (queued wording must match the kept offline promise string) and the unused `failed_media_upload_pending_retry` key noted in grounding.
- Follow-up "protection picker sheet" builds on the E1/E2 key family (must not fork a second set of mode names) and owns the group receiver-bubble reassurance port + media-kind-aware labels.

## Reviewer Findings (8-agent /tdd-review audit `wf_d3da2753-fc2`, 2026-07-18 — verdict "no: one mechanical revision pass required"; scores D1 86 / D2 61 / D3 85 / D4 88 / D5 64)
Material blockers (all APPLIED in this v2, each linchpin re-verified in source by the orchestrator):
1. ~13 existing literal pins of old copy would red the curated gates with a perfect implementation (8 banner pins incl. 3 multi-line concats; composer detail literals; 'Ordinary' chip pin; settings sub-sheet pin; 2 share byte pins) → **Existing Pins To Update table (P1–P5)**; Existing-Tests section corrected (its "no test pins the banner copy" and "survives label edits" claims were false).
2. TC-10 unsound on both legs (accept-expired UI-unreachable — `pending_group_invite_card.dart:180` disables Accept; decline fallback already l10n on HEAD) → **retargeted to accept-notFound** with revoked-variant fallback; decline fallback deleted; refuted item 11 added.
3. Catalog-1 green-unsatisfiable (trigger Chip double-renders 'Keep in chat' with the menu open) → **findsNWidgets(2)**; catalog-2 made deliberately findsWidgets.
4. Compile-RED would poison the 16-test viewer file for the whole RED phase + unresolved required-vs-optional param → **catalog-3/5/12 quarantined into a NEW file** (plan-211 precedent), **param decided: required** + the :993-1005 const call sites updated (const-compatible literal), which also closes D5's untested-mounting-plumb hole (INV-6).
5. No analyze baseline; no committed-l10n staleness gate (scratchpad↔workspace seam) → **B5 analyze baseline + block-5 staleness grep** added; parity gate pinned to /workspace.
Also applied (moderate/cheap): per-slice green checkpoints replacing the all-red-then-all-green waterfall; full E6 mapping table (ellipsis removed); `@placeholders` metadata spelled out; E4 body placement + null-policy behavior pinned; group receiver bubble named as the non-inheriting sibling (Accepted Differences + Scope Guard); all three banner mounts enumerated + share propagation ruled in-scope; TC-12 promoted from a Risks-section mention to a full catalog/matrix row; copy-authority precedence + §06 delta notes; removed-latch truthfulness bound corrected (roster_unavailable producer); baseline battery halved (B3/B4+B5 pre-edit; B1/B2 terminal-only).
Rejected findings (with reasons):
- D3's "correct `contactUsername` citation to :185" — wrong; the critic and orchestrator verified `:186` is exact.
- D5's "TC-10 feasible exactly as written" strength + its accept-expired verify-prompt — refuted by direct source read (disabled button); discarded in favor of the domain verifier.
- "Exclude E7 from the shared widget" (D5 alternative) — rejected; percent on all three mounts is the consistent, desirable outcome; P5 covers the share pins.
- Cutting E5 or E7 as over-engineering — the critic judged both earn their place (E5: verified duplicate surface; E7: one-line change, test-locked, three consistent surfaces); concur.
- Splitting TC-06 out of existing files into its own file — unnecessary once 6a/6b have explicit names + RED commands.

## Arbiter Decision
Structural blockers: none remaining — all five material blockers closed in v2 with source-verified fixes. | Deferred details: TC-10 delete-vs-revoked seeding variant resolved at RED-authoring time (step 2b); exact body-Text styling matches the existing caption's bodySmall. | Accepted differences: as listed (each traced to a refutation or HEAD structure). Ready to execute.

## Final Execution Verdict
(pending)
