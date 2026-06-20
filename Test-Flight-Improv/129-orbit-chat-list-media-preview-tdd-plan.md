# 129 — Orbit chat-list blank preview for media (voice/image) messages: surface a localized media label

Status: **IMPLEMENTED** (2026-06-19, host-green, uncommitted). All 6 slices landed for BOTH 1:1
and groups, with counts. No DB migration. `flutter analyze` 0 new issues; orbit + media-repo suites
green (262 tests), push + load_conversation regression green (228).

Implementation notes / deviations from the plan:
- The metadata-only loader is exposed as a **separate capability interface**
  `MediaPreviewDescriptorLookup` (sibling of `MediaAttachmentByIdLookup`), not a method on the main
  `MediaAttachmentRepository` — so the 13 existing fakes that `implements MediaAttachmentRepository`
  need no change. The orbit loaders use the key-free fast path when present and fall back to
  `getAttachmentsForMessages` + `MediaPreviewDescriptor.fromAttachments` otherwise (shared helper
  `lib/features/orbit/application/load_latest_media_descriptors.dart`).
- The descriptor is carried as a single `MediaPreviewDescriptor? latestMedia` on `OrbitFriend`/
  `OrbitGroup` (+ `bool isLatestDeleted` on `OrbitFriend`) rather than four flattened fields.
- New files: `lib/features/conversation/domain/models/media_preview_descriptor.dart`,
  `lib/features/orbit/application/load_latest_media_descriptors.dart`,
  `lib/features/orbit/presentation/widgets/orbit_media_preview_label.dart`; new tests:
  `media_attachment_repository_descriptors_test.dart`, `orbit_media_preview_label_test.dart` (+ INV-4
  vocabulary lock vs `notificationBodyForMessage`); extended `orbit_friend_test`,
  `load_orbit_data_use_case_test`, `load_orbit_groups_use_case_test`, `friend_row_test`,
  `group_row_bidi_test`. Six l10n keys added to EN/AR/DE (codegen run).
- Deferred per Open Questions: device verification; unifying the three label builders + localizing the
  9 English-only `mediaPreviewText` call sites and the English `notificationBodyForMessage`.

---

Status (original): PLAN. No code committed. TDD-first. No DB migration (reads existing `media_attachments` columns only).

## The symptom
On the chat list (the "orbit" friends list — tabs All / Intros / Archived), a 1:1 conversation row
(e.g. "Charlie") shows the contact name, a relative-time stamp, and an unread badge, but the
last-message **preview line is BLANK** when the latest message is a voice note or image(s) with no
caption. Text messages preview fine. Group rows have the same defect and show "Sender: " followed by
a blank subtitle. Reporter: Charlie received a voice message and images; neither is reflected in the
row's preview subtitle.

Note on the report's wording: "Active now" is **not** a presence indicator. It is
`formatRelativeTime(...)` returning "Active now" when the latest-message timestamp is < 1 minute old
(`lib/features/feed/domain/utils/format_message_time.dart:29`), rendered from
`friend.lastMessageTimestamp` (`friend_row.dart:116-123`). The timestamp and the unread badge come
from the **same** summary path that feeds the preview — so the data is loading correctly; only the
text-derived preview is empty. This rules out any "row not loading / different cause" theory.

## What is PROVEN (hard evidence, verified against source at file:line)

### Media-only messages persist text='' (empty string, never null), on BOTH ends
1. `lib/features/conversation/domain/models/conversation_message.dart:108` — `text: map['text'] as String`
   is a HARD non-nullable cast. A media-only row therefore MUST persist `text=''` (not null) or the
   summary load throws. This is exactly what produces a **non-null-but-empty** `lastActivity`.
2. `lib/features/conversation/application/send_chat_message_use_case.dart:248` allows a media-only
   send only when sanitized text is empty AND there are attachments; the saved row uses
   `text: sanitizedText` (= ''). Media persists separately in `media_attachments`.
3. `lib/core/utils/text_sanitizer.dart:45-47` — `sanitizeMessageText('')` returns `''` (strips bidi
   only; never null/empty conversion).
4. Receive path: a media-only wire payload arrives with `text=''` and is stored via
   `payload.toConversationMessage(...)`; media saved separately. (`message_payload` rejects
   `text==null`, so the empty string is the canonical media-only value.)
5. **Caption nuance (load-bearing):** a 1:1 media send CAN carry a non-empty caption
   (`conversation_wired.dart` passes both `text:` and `mediaAttachments:` in one send). An
   image-with-caption stores `text=<caption>` and **previews fine today**. The bug is strictly
   media **WITHOUT** a caption (voice notes are always caption-less; images may or may not be). Tests
   must seed `text=''` deliberately.

### The orbit summary loads ONLY scalar message columns — media never reaches the row
6. `lib/core/database/helpers/messages_db_helpers.dart:243-299` `dbLoadConversationThreadSummaries`
   selects only `latest.<scalar>` columns; the only LEFT JOIN is to `messages latest` — **NO join to
   `media_attachments`**. The aggregate filters `hidden_at IS NULL` (`_visibleMessageFilter`) and the
   inner latest-row subquery filters `inner_latest.hidden_at IS NULL` — but **neither filters
   `deleted_at`**. `latest_deleted_at` IS projected (`:266`).
7. `lib/features/conversation/domain/repositories/message_repository_impl.dart:454-500`
   `getConversationThreadSummaries` builds `latestMessage` via `ConversationMessage.fromMap({scalars})`;
   the transient `media` list defaults to `const []` (`conversation_message.dart:99`) and is never
   populated here.
8. `lib/features/orbit/application/load_orbit_data_use_case.dart:107` —
   `lastActivity: summary.latestMessage?.text` (the preview is the message TEXT only); `:108`
   timestamp; `:109` unreadCount. `OrbitFriend` is built one-per-CONTACT (`:27-35`), so the row always
   exists; only the subtitle is empty. The use case **never reads `deletedAt`** (no reference in the
   file).

### Presentation treats '' as "has preview"
9. `lib/features/orbit/presentation/widgets/friend_row.dart:95` —
   `if (friend.lastActivity != null) ... Text(friend.lastActivity!, maxLines:1, ellipsis)`. `''` is
   non-null, so the branch is TAKEN → it renders `Text('')` = a blank preview line. `:32-34`
   `lastActivity` also drives `detectTextDirection` for RTL.
10. `lib/features/orbit/domain/models/orbit_friend.dart:7-28` — fields are
    `contact / messageCount / lastActivity(String?) / lastMessageTimestamp / unreadCount`. **No media
    descriptor exists.**

### GROUP rows have the IDENTICAL defect (the brief's "more developed" framing is wrong)
11. `lib/features/orbit/application/load_orbit_groups_use_case.dart:118-120` —
    `latestMessageText: latestMessage?.text` and `latestMessage: latestMessage?.text` (both text-only).
12. `lib/core/database/helpers/group_messages_db_helpers.dart:306-355` `dbLoadGroupThreadSummaries`
    selects only `latest.<scalar>` columns; LEFT JOIN to `group_messages latest` only — **NO media
    join**. It excludes only the removal-cutoff system message (`id NOT LIKE …`), not arbitrary deletes.
13. `lib/features/orbit/presentation/widgets/group_row.dart:58-59` —
    `latestMessageText = group.latestMessageText ?? group.latestMessage; hasStructuredPreview = text != null`.
    `''` is non-null → the structured branch (`:127-167`) renders `senderName + ': ' + Text('')` → a
    dangling **"Sender: " then blank** — arguably worse than 1:1.
14. **Asymmetry confirmed:** `lib/features/groups/domain/models/group_message.dart` has fields
    `id/groupId/senderPeerId/.../text/timestamp/.../media` but **NO `deletedAt` or `hiddenAt`** (verified
    field-by-field). So the deleted-latest hazard (see #20) is a **1:1-only** concern; groups never
    carry soft-delete state through this model.

### Three overlapping media-label builders already exist (must reconcile, not add a 4th divergent one)
15. `lib/features/push/application/show_notification_use_case.dart:24-40` —
    `notificationBodyForMessage(text, media)`: caption-first; `image→'Photo'` (`isAnimated`→`'GIF'`),
    `video→'Video'`, `audio→'Voice message'`, `file→'File'`, mixed→`'Media'`, empty→`'Message'`.
    Hardcoded English. **No counts.** This is the **canonical vocabulary** for the orbit label and is
    already live in the 1:1 chat notification path.
16. `lib/shared/widgets/media/media_preview_text.dart:9-51` — `mediaPreviewText(media)`: has per-type
    counts ('3 photos', '2 photos · Video'), GIF special-case, but audio→`'Audio · 0:24'` (NOT
    "Voice message") and **no caption rule**. Hardcoded English. Consumed by 9 quoted-reply/feed call
    sites (conversation_screen, conversation_wired, group_conversation_screen, group_conversation_wired,
    feed_screen ×2, scrollable_message_preview, collapsed_mode_card_body). Localizing it in place would
    ripple to all 9 — **DEFERRED** (see Open Questions).

### Media model + reusable loader
17. `lib/features/conversation/domain/models/media_attachment.dart:30-31` — `mediaType ∈
    {'image','video','audio','file'}`; `:39` `durationMs`; `:52` `waveform`; `:99`
    `isAnimated => mime == 'image/gif'`. Separate table; multiple per message.
18. **All audio == voice (verified):** the only audio producer is the voice path
    (`send_voice_message_use_case` persists `mediaType:'audio'` with durationMs+waveform); there is no
    audio-file attach path. So `mediaType=='audio'` safely maps to "Voice message" with no count. This is
    a stated load-bearing assumption.
19. `lib/features/conversation/domain/repositories/media_attachment_repository.dart:14-16` —
    `getAttachmentsForMessages(List<String>) → Map<messageId, List<MediaAttachment>>`. The impl hydrates
    each encrypted attachment's key via `SecureKeyStore.read(...)` — one secure-store round-trip PER
    encrypted attachment. On a hot orbit-load over N contacts this is N keychain reads solely to render
    a label that never needs the key. → the plan adds a **metadata-only** loader instead (Slice 2).

### Deleted-latest hazard (1:1 only) — a LIVE regression the naive fix would introduce
20. The summary SQL excludes `hidden_at` but **not** `deleted_at` (#6). A soft-deleted message
    (`deleted_at` set, `hidden_at` null) can still be the chosen "latest" row, and its `media_attachments`
    rows are NOT removed by a soft delete. Today that surfaces as `text=''` → blank (benign-looking).
    After the fix, a media descriptor built from those still-present rows would render "Photo"/"Voice
    message" for a **deleted** message — resurrecting it. The summary already carries `deletedAt`
    end-to-end (`messages_db_helpers.dart:266` → `message_repository_impl.dart` parse →
    `conversation_message.dart:116`), so this is detectable in the pure use case with zero new plumbing.

### Wiring already present
21. `lib/features/orbit/presentation/screens/orbit_wired.dart:103` — `OrbitWired` ALREADY holds
    `final MediaAttachmentRepository mediaAttachmentRepo` and threads it to neighbouring use-cases
    (`:1214,:1693,:1730,:2147,:2195`). It is NOT passed to `loadOrbitData` (`:466,:492`),
    `loadOrbitFriendSnapshot` (`:633`), or `loadOrbitGroups` (`:530,:562`). So the screen-side plumbing
    cost is "pass the field that already exists".

### l10n shapes
22. `lib/l10n/app_en.arb:79-86` — `compose_attachments` ICU plural + `@`-metadata block to mirror.
23. `lib/l10n/app_ar.arb:423` — `group_member_count` uses the **full CLDR set**
    `=1 =2 few many other` (NOT EN-style `=1/other`). New Arabic plurals MUST use the full set.
24. `conversation_message_deleted` already exists in EN/AR/DE (`app_*.arb:197`) — reuse it for the
    deleted-latest case. No new key needed for that.

## Root cause (one sentence)
A media-only message persists `text=''` (never null), the orbit summary surfaces only that scalar text
(no media join, and it drops `deletedAt`), and `friend_row.dart:95` / `group_row.dart:59` treat the
empty string as "has preview" — so the row renders `Text('')`. **Both** the data layer (surface
latest-message media type+count) **and** the presentation layer (build a localized label when text is
empty-but-media-present) must change, or the bug persists.

## Invariants (each gets a locking test)
- **INV-1 (media-only → label):** a contact/group whose latest visible message has `text==''` and ≥1
  media attachment renders a non-blank, localized media label, never `Text('')`.
- **INV-2 (caption wins):** a latest message with non-empty `text` AND media renders the text (caption),
  not the media label, and preserves the caption's own text direction.
- **INV-3 (text regression guard):** a plain text latest message previews unchanged; timestamp +
  unread badge unchanged.
- **INV-4 (vocabulary consistency):** for the same message, the orbit label uses the same wording as
  `notificationBodyForMessage` — Voice message / Photo / Video / File / GIF / Media — with counts added
  for multiples. A locking test asserts orbit-label words == notification-body words for shared inputs.
- **INV-5 (deleted-latest, 1:1):** when `summary.latestMessage?.deletedAt != null`, the media
  descriptor is suppressed and the row shows `conversation_message_deleted`, never a media label.
- **INV-6 (group parity):** an orbit GROUP row with a media-only latest message renders
  `"Sender: <media label>"` (label AFTER the colon), never `"Sender: " + blank`.
- **INV-7 (RTL):** when a media LABEL is shown, its direction follows the label (locale); when a CAPTION
  wins, direction follows the caption's own script. Arabic label is RTL; a Latin caption stays LTR.
- **INV-8 (no key dependency):** the label renders from `mediaType`/`mime`/count metadata only; an
  encrypted latest message with a missing secure key still labels correctly (no decryption needed).
- **INV-9 (empty conversation):** a contact/group with no messages → no descriptor, no preview line
  (unchanged); no crash on a null descriptor.

## Fix approach decision (Data: Option A vs B)
**Reject Option A (SQL aggregate `COUNT` + `GROUP_CONCAT(DISTINCT media_type)` in the summary SQL):**
- It loses fidelity the existing labelers have: per-type counts ('3 photos'), GIF-vs-photo (GIF is a
  `mime=='image/gif'` distinction, both are `media_type='image'`), and would force aggregating distinct
  MIME too — uglier SQL.
- It couples the orbit-preview feature to the shared summary schema (also consumed by single-summary +
  potentially other callers).
- Test cost: `test/core/database/helpers/messages_db_helpers_test.dart` setUp does **not** run migration
  `010_media_attachments`, so a DB-helper RED test would fail on a *missing table* (false red) until
  setUp is amended — defeating the TDD intent.

**Reject naive Option B (reuse `getAttachmentsForMessages`):** correct semantically (full
`MediaAttachment` objects preserve GIF/voice/count) but it pays a `SecureKeyStore.read` per encrypted
attachment on a hot screen-load path (#19), purely to render a label that never needs the key.

**Chosen: Option B′ — a metadata-only batch loader.** Add a narrow interface method that returns just
`{mediaType, mime, count}` (or a small descriptor) per message id, reading existing `media_attachments`
columns with **no key hydration**. This preserves GIF/voice/count fidelity, adds no migration, and
threads the already-present `mediaAttachmentRepo` (#21) into the use cases. No change to the summary SQL,
the summary models, or `ConversationMessage`/`GroupMessage`.

**Localization placement:** the label is built in the **widgets** (`friend_row`/`group_row`, both
already have `AppLocalizations` + `detectTextDirection`), keeping l10n out of the pure use cases (no
`BuildContext`, tests stay pure). The widgets receive a structured descriptor and call a shared,
context-fed label builder.

## TDD Slices (each starts with a FAILING test, then the minimal production change)

### Slice 1 — Structured media descriptor on the orbit models (RED: model defaults)
**Failing test:** `test/features/orbit/domain/models/orbit_friend_test.dart` — construct `OrbitFriend`
with new fields and assert defaults + pass-through:
`expect(OrbitFriend(...).latestMediaType, isNull)`, `…latestMediaCount, 0)`, and that a constructed
descriptor round-trips. (Add a parallel test for `OrbitGroup` in
`test/features/orbit/domain/models/` if one exists, or extend the group bidi test's `makeGroup`.)
**Production change:** add nullable descriptor fields to `OrbitFriend`
(`lib/features/orbit/domain/models/orbit_friend.dart`) and `OrbitGroup`
(`lib/features/orbit/domain/models/orbit_group.dart`):
- `latestMediaType` (`String?` — `'image'|'video'|'audio'|'file'|null`)
- `latestMediaIsGif` (`bool` — to preserve GIF-vs-photo without re-deriving from mime in the widget)
- `latestMediaCount` (`int`, default 0)
- `latestMediaIsMixed` (`bool`, default false — for the mixed-type generic fallback)
Keep `lastActivity`/`latestMessageText` as the optional caption. `OrbitGroup.copyWith` carries them
through. No behaviour change yet — the use case doesn't populate them, so the row is unaffected.

### Slice 2 — Metadata-only batch loader (RED: loader contract)
**Failing test:** `test/features/conversation/domain/repositories/media_attachment_repository_*_test.dart`
(or the in-memory fake's test) — seed two messages, one with a single image, one with a voice
attachment, call the new metadata-only loader, assert it returns the right `{type,count,isGif}` per id
**without** touching the secure store (assert via a spy store that `read` is never called).
**Production change:** add to `MediaAttachmentRepository`
(`lib/features/conversation/domain/repositories/media_attachment_repository.dart`) a method:
`Future<Map<String, MediaPreviewDescriptor>> getMediaPreviewDescriptors(List<String> messageIds)`
returning a tiny value object `MediaPreviewDescriptor { String? type; int count; bool isGif; bool isMixed; }`.
Impl reads `media_attachments` (existing `SELECT … WHERE message_id IN (…)`) projecting `media_type`,
`mime`, grouping by `message_id` — **no `_hydrateRow`/key read**. Update both the real impl and the test
fakes (`test/shared/fakes/in_memory_media_attachment_repository.dart`,
`test/features/conversation/domain/repositories/fake_media_attachment_repository.dart`) to serve it from
their already-seeded attachments.

### Slice 3 — Wire 1:1 use case to populate the descriptor + suppress on delete (RED: use-case behaviour)
**Failing test:** `test/features/orbit/application/load_orbit_data_use_case_test.dart` — inject a
`FakeMediaAttachmentRepository`; seed a contact whose latest message has `text=''` + one audio
attachment; assert the produced `OrbitFriend.latestMediaType == 'audio'` and `latestMediaCount == 1`.
Add cases: (a) multi-image → `latestMediaCount > 1`, type `'image'`; (b) **caption wins** — `text`
non-empty + media → `lastActivity == <caption>` and the descriptor still carries media but the widget
test (Slice 5) proves the caption is shown; (c) **deleted-latest** (INV-5) — latest message
`text=''`, one image, `deletedAt != null` → descriptor suppressed (`latestMediaType == null`) so the
widget shows the deleted placeholder. Mirror the existing mixed-script RTL fixtures.
**Production change:** thread an optional `MediaAttachmentRepository? mediaAttachmentRepo` into
`loadOrbitData` + `loadOrbitFriendSnapshot` (`lib/features/orbit/application/load_orbit_data_use_case.dart`).
After building summaries, collect non-null `summary.latestMessage?.id` where `deletedAt == null`,
call `getMediaPreviewDescriptors(latestIds)` once, and fold each into the new `OrbitFriend` fields in
`_buildOrbitFriend`. When `summary.latestMessage?.deletedAt != null`, leave the descriptor empty
**and** carry a deleted flag/sentinel so the widget can show `conversation_message_deleted` (simplest:
set `lastActivity` to null and add an `isLatestDeleted` bool, or reuse a known sentinel — pick one and
test it). Pass `widget.mediaAttachmentRepo` at `orbit_wired.dart:466` AND `:492` (archived) AND `:633`.

### Slice 4 — Shared localized label builder (RED: builder vocabulary + INV-4)
**Failing test:** a new pure helper test, e.g.
`test/features/orbit/presentation/widgets/orbit_media_preview_label_test.dart`, that builds a label from
a descriptor + an `AppLocalizations` (pumped via a tiny `MaterialApp(locale:'en')` harness) and asserts:
audio→l10n "Voice message"; 1 image→"Photo"; 3 images→"3 photos"; GIF→"GIF"; video→"Video"; file→"File";
mixed→"Attachment"/"{n} attachments". **INV-4 lock:** for each single-type input, assert the produced
words equal `notificationBodyForMessage('', [matching media])` (proving the orbit vocabulary matches the
shipped notification vocabulary; counts are the only intentional addition).
**Production change:** add a small widget-layer function (NOT in the pure use case) that maps a
`MediaPreviewDescriptor`-shaped input + caption to the localized string using the new l10n keys (Slice 6),
applying precedence: deleted → `conversation_message_deleted`; else non-empty caption → caption; else
mixed → `orbit_preview_attachment(count)`; else by type. Live next to `friend_row`/`group_row` so both
reuse it.

### Slice 5 — Render the label in friend_row + group_row (RED: widget)
**Failing test (1:1):** `test/features/orbit/presentation/widgets/friend_row_test.dart` — extend
`_makeFriend` with the new media params. Build `FriendRow` for a friend with audio/count-0-caption →
`expect(find.text(l10n.orbit_preview_voice_message), findsOneWidget)`; multi-image → "{n} photos";
caption-wins → finds the caption text, not the label; deleted-latest → finds
`conversation_message_deleted`. Add an RTL assertion mirroring the existing `detectTextDirection` tests:
Arabic label → `TextDirection.rtl`; Latin caption in EN locale → `TextDirection.ltr`.
**Failing test (group):** `test/features/orbit/presentation/widgets/group_row_bidi_test.dart` — extend
`makeGroup`; media-only group latest → `find.text` matches `"Sender: <label>"` structure (label after
the colon); blank-after-colon assertion is gone.
**Production change:**
- `friend_row.dart`: change the gate so the preview renders when there is a caption OR a media
  descriptor OR a deleted-latest; compute the displayed string via the Slice-4 builder; drive
  `detectTextDirection` from whichever string is shown.
- `group_row.dart`: in the structured branch (`:127-167`), when `latestMessageText` is empty but a media
  descriptor exists, render the localized label in the `Expanded` Text slot (keep the
  `senderName + ': '` prefix); preserve `detectTextDirection` on the label.

### Slice 6 — Wire the group use case + l10n keys EN/AR/DE (RED: group use case)
**Failing test:** `test/features/orbit/application/load_orbit_groups_use_case_test.dart` (extend or
create) — inject a media repo fake; seed a group whose latest message has `text=''` + one image; assert
`OrbitGroup.latestMediaType == 'image'`, `latestMediaCount == 1`. (No deleted-latest case for groups —
`GroupMessage` has no `deletedAt`, #14.)
**Production change:**
- Thread `MediaAttachmentRepository? mediaAttachmentRepo` into `loadOrbitGroups` +
  `loadOrbitGroupSnapshot` (`lib/features/orbit/application/load_orbit_groups_use_case.dart`); populate
  the `OrbitGroup` descriptor in `_buildOrbitGroup` via `getMediaPreviewDescriptors`. Pass
  `widget.mediaAttachmentRepo` at `orbit_wired.dart:530` AND `:562` AND `:679`.
- Add the l10n keys below to **all three** arb files; run codegen; verify the build.

## l10n keys (EN / AR / DE)
Add to `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`, `lib/l10n/app_de.arb` (each pluralized key needs its
`@`-metadata `placeholders` block with `count:int`, mirroring `compose_attachments` at `app_en.arb:79-86`).
Reuse the existing `conversation_message_deleted` (`app_*.arb:197`) for the deleted-latest case — no new
key.

EN (`app_en.arb`):
```
"orbit_preview_voice_message": "Voice message",
"orbit_preview_gif": "GIF",
"orbit_preview_photo": "{count, plural, =1{Photo} other{{count} photos}}",
"orbit_preview_video": "{count, plural, =1{Video} other{{count} videos}}",
"orbit_preview_file": "{count, plural, =1{File} other{{count} files}}",
"orbit_preview_attachment": "{count, plural, =1{Attachment} other{{count} attachments}}"
```
DE (`app_de.arb`) — German is 2-category (`=1/other` acceptable):
```
"orbit_preview_voice_message": "Sprachnachricht",
"orbit_preview_gif": "GIF",
"orbit_preview_photo": "{count, plural, =1{Foto} other{{count} Fotos}}",
"orbit_preview_video": "{count, plural, =1{Video} other{{count} Videos}}",
"orbit_preview_file": "{count, plural, =1{Datei} other{{count} Dateien}}",
"orbit_preview_attachment": "{count, plural, =1{Anhang} other{{count} Anhänge}}"
```
AR (`app_ar.arb`) — MUST use the FULL CLDR set `=1 =2 few many other` (mirroring `group_member_count`
at `app_ar.arb:423`):
```
"orbit_preview_voice_message": "رسالة صوتية",
"orbit_preview_gif": "صورة متحركة",
"orbit_preview_photo": "{count, plural, =1{صورة} =2{صورتان} few{{count} صور} many{{count} صورة} other{{count} صورة}}",
"orbit_preview_video": "{count, plural, =1{فيديو} =2{فيديوهان} few{{count} فيديوهات} many{{count} فيديو} other{{count} فيديو}}",
"orbit_preview_file": "{count, plural, =1{ملف} =2{ملفان} few{{count} ملفات} many{{count} ملفًا} other{{count} ملف}}",
"orbit_preview_attachment": "{count, plural, =1{مرفق} =2{مرفقان} few{{count} مرفقات} many{{count} مرفقًا} other{{count} مرفق}}"
```
(Arabic wordings are placeholders for the translator; the **plural-category shape** is the hard
requirement.)

## Group-row parity decision
**IN SCOPE.** Verified identical root cause (#11-13) and that the brief's "more developed" framing is
wrong. Group is fixed as a sibling of 1:1 (same descriptor on `OrbitGroup`, same metadata loader, same
shared label builder, same l10n keys), with the label placed **after** the `"Sender: "` prefix in
`group_row.dart`. The one asymmetry: groups have **no** deleted-latest suppression because `GroupMessage`
carries no `deletedAt` (#14) — the group summary SQL only excludes the removal-cutoff system message.

## Edge cases / handling
- **Voice note** (`mediaType=='audio'`, text='') → "Voice message", no count, not "Audio · 0:24".
- **Single image** → "Photo"; **multiple** → "{n} photos".
- **GIF** (`mime=='image/gif'`) → "GIF", distinct from "Photo".
- **Image(s) + caption** → caption shown (INV-2), media label suppressed; caption keeps its own RTL.
- **Mixed single message** (image+video) → generic "Attachment"/"{n} attachments" (matches
  `notificationBodyForMessage`'s `Media` branch; we add counts).
- **File only** → "File"/"{n} files".
- **Soft-deleted media latest (1:1)** → `conversation_message_deleted`, never a media label (INV-5).
- **Hidden latest** already excluded by the summary SQL — the NEXT visible message (possibly itself
  media) drives the preview correctly.
- **Encrypted latest, key missing** → label still renders from metadata (INV-8); the metadata loader
  never reads the key.
- **No messages** → no descriptor, no preview line, no crash (INV-9).
- **System/sys-* latest with text** → existing text shown, no spurious media label.

## Accessibility
The preview is a `Text` subtitle; the localized label is screen-reader-meaningful out of the box (no
icon-only state). The deleted-latest case reads the existing localized "This message was deleted". No
new semantics widget required; the RTL `textDirection` is set per INV-7 so assistive tech reads the
correct direction.

## Test list
- `orbit_friend_test.dart` — new descriptor fields default null/0/false (Slice 1).
- `orbit_group_test.dart` / group bidi `makeGroup` — group descriptor defaults (Slice 1).
- media-attachment repo / fake test — `getMediaPreviewDescriptors` returns type+count+isGif without a
  secure-store read (Slice 2).
- `load_orbit_data_use_case_test.dart` — media-only→descriptor; multi-image count; caption-wins;
  deleted-latest suppression (Slice 3).
- `orbit_media_preview_label_test.dart` — per-type localized label + INV-4 vocabulary lock vs
  `notificationBodyForMessage` (Slice 4).
- `friend_row_test.dart` — voice/photo/{n}/caption-wins/deleted labels + RTL (Slice 5).
- `group_row_bidi_test.dart` — "Sender: <label>" structure, no blank-after-colon, RTL (Slice 5).
- `load_orbit_groups_use_case_test.dart` — group media-only→descriptor (Slice 6).
- l10n codegen + build passes with the 6 new keys in EN/AR/DE.

## Gates
- `flutter analyze` — 0 new issues.
- Suites: `test/features/orbit/` (application + domain/models + presentation/widgets),
  `test/features/conversation/domain/repositories/` (media attachment repo + fakes), and the l10n
  codegen build. Spot-run `test/features/push/` to confirm `notificationBodyForMessage` is unchanged
  (we only *read* its vocabulary).
- No migration; confirm DB version unchanged.

## Risks / open questions
- **Vocabulary divergence (managed, not eliminated):** three labelers now exist
  (`notificationBodyForMessage`, `mediaPreviewText`, the new orbit builder). INV-4 locks orbit↔notification
  wording. Fully unifying all three (and localizing the 9 English-only `mediaPreviewText` call sites +
  the English notification body) is a larger cleanup, **DEFERRED**.
- **Counts vs notifications:** the row adds counts ("3 photos") that notifications don't carry — an
  intentional, tested divergence (Open Question 1).
- **Deleted-latest (1:1 only):** the fix must suppress the descriptor on `deletedAt != null` or it
  resurrects deleted media (Open Question 2; INV-5). Groups are unaffected (#14).
- **Mixed-type fallback:** generic "Attachment(s)" loses the per-type detail `mediaPreviewText` shows in
  quoted replies; acceptable for a one-line row (Open Question 4).
- **Legacy `group_list_wired.dart` getLatestMessage path:** out of scope unless still reachable
  (Open Question 5).
- **Perf:** one extra metadata-only batched query per orbit load (single `IN`, no key hydration);
  bounded by contact/group count; acceptable on a screen-load path.
- **Test-infra gotchas:** seeding a media-only row requires `text=''` (NOT null) or
  `ConversationMessage.fromMap`'s hard cast (`:108`) throws; the use-case RED test requires injecting a
  media-repo fake (the message-repo fakes return empty `.media`); chose Option B′ specifically so
  `messages_db_helpers_test.dart` setUp does NOT need migration 010 added.
