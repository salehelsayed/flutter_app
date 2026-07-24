# 270 - Direct image/video private selection and received tap-tile redesign (Modification)

Status: execution-ready
Scope decision: KIND-01 is resolved — new direct 1:1 private-media selection supports images and videos only; GIFs remain ordinary “Keep in chat” media, pre-existing private-GIF intent is grandfathered without downgrade, and group chats are out of scope.
Type: Modification
Spec: free-text intent (no formal spec) — user request 2026-07-24 + approved mockup `docker-ws/protected-photo-mockup.html` (option B). Disappearing composition = option A (keep expiry title). New attachment selection = image + video only; GIF = “Keep in chat” only; group chats excluded (user decisions 2026-07-24). Existing durable/wire private-GIF intent remains private solely for backward-compatible privacy safety.
Classification: execution-ready
Closure tier: host

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-24 | Evidence Collector | direct_private_media_viewer.dart, group_conversation_screen.dart, conversation_screen.dart, letter_card.dart, app_{en,ar,de}.arb, l10n.yaml, run_test_gates.sh, integration_test device harness, 15 test files | 21-agent verify→refute workflow wf_7d204825-534: 2 REFUTED, 4 PARTIAL, 3 CONFIRMED. Card is shared by 4 sites; groups already have whole-bubble tap; device harness spared under this scope | Build matrix |
| 2026-07-24 | Planner | same | Scope = 1:1 received protected+disappearing only; groups untouched; tile-tap on the existing `private-media-card-visual` Container | Emit plan |
| 2026-07-24 | Reviewer (`/tdd-review`) | this plan + real source + Flutter SDK | 8-agent audit wf_0730119f-6d4: core bet SOUND; 2 material test defects (TC-04 unreachable, TC-06 a11y node-split) + ungated height/locale/onOpen. See Reviewer Findings | Tighten in place |
| 2026-07-24 | Arbiter | this plan | Applied fixes; disappearing→option A (dissolves TC-04); Semantics co-located; height/onOpen/locale gated. See Arbiter Decision | hand off to execution |
| 2026-07-24 | `$tdd-plan` sufficiency audit | current plan/index; Graphify snapshot; production widget/call sites; Flutter Semantics/GestureDetector source; direct/group tests and gate scripts | Prior ready verdict superseded: attachment-kind scope is unresolved; the former TC-10 fixture was unreachable; press/dim/opening semantics, disabled fallback, group preservation, literal commands, canonical contract, and gate cadence needed repair | Patch deterministic gaps; hold execution for kind decision |
| 2026-07-24 | User scope resolution + source recheck | `private_media_policy.dart`, direct composer/send/decode/retry seams and tests, plan 234 contract, group caller | KIND-01 resolved to new direct 1:1 image + video only; GIF must remain “Keep in chat” and groups are excluded. Current new-selection UI admits GIF, while durable retry/decode paths must retain old privacy intent; TC-18 now separates those contracts | Lock TC-18, compact-copy key, compatibility sentinels, and exclusions; promote |
| 2026-07-24 | `/tdd-review` fix-list recheck | `270-review-fixlist.md`; direct composer policy writers; all production `sendChatMessage` callers; compatibility decode/retry paths; TC-11/18 gates | Accepted the composer split but rejected the proposed retry-lane/front-guard subsystem as self-inflicted. New-composition containment is complete only when the four direct selection/reset decisions use the full image/video-plus-shape predicate. `sendChatMessage`, retry code, and the GIF-inclusive compatibility validator remain unchanged; therefore the plan makes no claim that arbitrary internal calls with an explicit private-GIF policy are rejected | Remove obsolete lane work/proofs, pin the normalization funnel, and retain cheap compatibility sentinels |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| - | not started | - | - | no planning blocker; implementation has not run | snapshot dirty tree, author causal REDs, then change production |

## Source Of Truth
- Spec / intent: user messages 2026-07-24 + `docker-ws/protected-photo-mockup.html` (option B). The latest user decisions limit new direct private selection to images/videos, keep GIF ordinary-only, and exclude groups. Pre-existing private-GIF state remains protected as a backward-compatibility safety rule, never as a selectable new mode. Historical grounding workflow: `wf_7d204825-534`; its journal path is not retained as a usable repository path, so the current Graph/source snapshot below is authoritative for execution.
- Review input: `270-review-fixlist.md` is an audit artifact, not an execution contract. Its DROP recommendation is accepted, but its setter-only writer claim and caller-census-retirement wording are superseded by the current source recheck and this revised plan.
- Gate definitions: `scripts/run_test_gates.sh` (family `1to1` → `ONE_TO_ONE_TESTS`; script wins over prose).
- l10n generation: `l10n.yaml` + `pubspec.yaml:113 generate: true`; regenerate with `flutter gen-l10n`.
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (270 is allocated to this plan).

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `3694ca43d7e36907`; `stale:ios/Flutter/flutter_export_environment.sh` only. That generated iOS file is outside this host-widget plan; all load-bearing conclusions below were rechecked in current source.
- Query / profile: `python3 graphify-arch/tdd_context.py query "Protected-photo tap tile redesign: DirectPrivateMediaOpenPlaceholder PrivateMediaVisualCard direct_private_media_viewer.dart private_media_protected_body_received ONE_TO_ONE_TESTS" --profile tdd --budget 700`.
- Kind-boundary refinement: `python3 graphify-arch/tdd_context.py query "lib/core/media/private_media_policy.dart PrivateMediaPolicy GIF image video ordinary protected disappearing conversation composer test" --profile tdd --budget 700` (`confidence=anchored`), followed by targeted reads of the direct policy, composer, send, decode, card, and gate tests.
- Anchors: `PrivateMediaVisualCard` → `lib/features/conversation/presentation/screens/direct_private_media_viewer.dart:457`; `ONE_TO_ONE_TESTS` → `scripts/run_test_gates.sh:21`.
- Surfaced proof/gate files: `direct_private_media_viewer.dart`, `conversation_screen.dart`, `group_conversation_screen.dart`, `direct_private_media_viewer_test.dart`, and `scripts/run_test_gates.sh`.
- Graph gaps requiring source search: direct placeholder-body/card/action/wired tests, the group preservation test, device-harness fixture direction, Flutter Semantics/GestureDetector behavior, the mockup's exact press transform, and attachment-kind derivation were verified by targeted current-source reads.
- Reuse rule: these anchors may be handed to review/execution, but every conclusion still requires current-source or command evidence.

## Session Classification
execution-ready (host-only direct-policy + widget + l10n work; no DB migration or device proof). The attachment-kind row is resolved and all Test Contract rows are defined.

## Problem And Evidence

- Behaviors to improve: (1) a new direct 1:1 GIF draft must expose only ordinary “Keep in chat,” while a single captionless, non-edit, non-forward image or video may expose private modes; and (2) an eligible received protected/disappearing image or video card must use its privacy-safe visual tile as the open affordance, with truthful visual and accessibility state while opening.
- Impact: the current 88px tile, repeated title/body copy, and separate button make the received card heavier and less direct than the approved option-B mockup.
- Confirmed current gap: `DirectPrivateMediaOpenPlaceholder.build` at `lib/features/conversation/presentation/screens/direct_private_media_viewer.dart:582-629` always supplies a title and `private-media-open` button, while `PrivateMediaVisualCard.build` at `:473-518` renders an inert 88px `Container`.
- Existing coverage: current direct widget/wiring tests pin the old title, body, and button path; `direct_private_media_card_test.dart:131-152` pins the no-real-pixels invariant; the curated registration is `ONE_TO_ONE_TESTS` in `scripts/run_test_gates.sh:21-278`.
- Missing coverage: press scale, dimming, disabled/opening semantics, the exact `onOpen == null` disabled button, group no-`onTap` preservation, and the image/video-only plus GIF-ordinary boundary.
- Refuted findings: the device harness does use `private-media-open`, but its mounted/tapped UI rows are outgoing protected and incoming view-once, so this received protected/disappearing UI change does not require device closure. An incoming disappearing lifecycle fixture exists, but it is not mounted as this UI.
- Resolved finding / current implementation gap: user intent is image + video only for **new direct composition**, but `PrivateMediaEligibility.allowsPrivateMedia` currently serves both composer eligibility and backward-compatible payload validation and admits GIF (`private_media_policy.dart:72-82`). Removing GIF from that compatibility getter would downgrade or reject older private-GIF state. The minimal correction is a second, full-shape `allowsNewPrivateMedia` predicate used by the four direct composer/reset decisions. That contains every production user-authored fresh path: selector visibility, pre-send composer guard, policy setter, and composer normalization. `sendChatMessage` and its caller set remain unchanged, so legacy retries continue through the existing GIF-inclusive validator. This is intentionally a product-composition boundary, not a domain-wide rejection guarantee for arbitrary internal calls that explicitly manufacture a private-GIF policy.
- Affected files: `private_media_policy.dart`; `conversation_wired.dart`; `compose_area.dart`; `direct_private_media_viewer.dart`; `app_{en,ar,de}.arb` plus generated localizations; direct policy/composer/wired and tile/body/viewer/action tests; cheap unchanged send/decode/native sentinels; one group preservation test; and `scripts/run_test_gates.sh`.

### Exact UX Contract
When user-A sends a protected photo to user-B, B's bubble renders a three-part card: an 88px gradient+lock tile, a **"Protected photo"** title, a two-sentence body **"You can view it again. {name} doesn't allow saving or sharing."**, and a green **"Open photo"** `FilledButton.tonalIcon`. The user finds this heavy: the button is redundant with the obvious lock tile, the title restates the icon, and the "You can view it again." lead-in is noise.

**What must improve (1:1 received image/video, protected + disappearing modes):**
- Remove the "Open photo"/"Open video" button (`FilledButton.tonalIcon`, key `private-media-open`) — both protected and disappearing.
- **Protected:** remove the visible "Protected photo"/"Protected video" title; body reduces to a single line **"{name} doesn't allow saving or sharing."** (drop the "You can view it again." lead-in).
- **Disappearing:** KEEP the media-appropriate "Photo/Video · disappears after {duration}" title — the time-critical expiry cue stays a bold primary line (user decision 2026-07-24, option A; the mockup only covered protected). Its image/video body also drops the "You can view it again." lead-in via the new scoped compact key. No new secondary line, no expiry demotion.
- Make the gradient tile itself the tap target that opens the image/video (both modes), **only when the card is openable** (`onOpen != null`).
- Grow the tile from 88px → 150px when it is tappable (mockup option B).
- Move the opening state (spinner + dim) from the button into the tile; add a light tap-down scale for press feedback (approximates the approved mockup's `:active` feel without needing an `InkWell`/`Material`).

**What must stay unchanged (→ preserved-green sentinels):**
- The tile stays icon/gradient-only — **no real pixels ever enter `PrivateMediaVisualCard`** (`direct_private_media_viewer.dart:454-456` contract; `card_test:131-152`).
- Screen-reader announcement still says the media-appropriate "Protected photo"/"Protected video" label (retained on the same enabled action node; TC-05/06 and TC-18 separately lock opening state/kind copy).
- **View-once** received card keeps its title + "View photo" confirmation button (irreversible-action guard) — untouched.
- **Not-yet-openable / open-denied** received protected image/video card (`onOpen == null`) keeps today's title, 88px tile, and present-but-disabled `private-media-open` button. The new scoped compact body still applies; only the tap-tile/title/button layout is gated on openability.
- **Outgoing/sender** card, **open-failure** card, **consumed/expired/unsupported** placeholders — untouched.
- **GIF:** ordinary “Keep in chat” is the only mode exposed by a new direct composer draft. Replacing an eligible image/video draft with GIF clears stale private policy before optimistic persistence and send. Pre-existing private-GIF wire/durable state remains private through the unchanged compatibility/decode/retry paths, retains existing platform protections, and keeps the legacy 88px/title/button/body presentation; it never receives the tap-tile/compact-copy redesign or a silent ordinary downgrade.
- **Group chats:** no group policy, copy, presentation, or gesture changes (see Scope Contract And Guard; TC-16 is preservation proof only).
- Disappearing mode keeps its expiry title (option A) — the expiry is never demoted or dropped.

## Current Mechanism And Confirmed Gap
The card change is a deliberate UX redesign. The current card is built by `DirectPrivateMediaOpenPlaceholder.build` (`direct_private_media_viewer.dart:582-629`), which feeds a **shared** `PrivateMediaVisualCard` (`:457-519`) with `title`, `body`, and an `action` button. The tile (`ValueKey('private-media-card-visual')`, `:482-503`) is a bare `Container` with **zero** gesture handling (CONFIRMED, claim 3). The `opening` spinner lives only inside the button (`:596-601`; CONFIRMED, claim 8).

The kind boundary is also a confirmed production mismatch, not a hypothetical branch: `PrivateMediaEligibility.allowsPrivateMedia` currently includes image, GIF, and video; `conversation_private_media_composer_test.dart:89-109` expects the selector for all three; and its `:425-446` path opens the GIF privacy sheet. That getter also validates decrypted legacy payloads and retry sends, so it cannot simply lose GIF. Add a distinct image/video-only **new-selection** predicate for composer paths while retaining the existing compatibility predicate unchanged for stored/wire private intent. Extend the ordinary-GIF transport sentinel to assert stored policy is ordinary and decrypted inner JSON has no `privateMedia`, not only MIME/animation.

**Refuted / do-NOT-re-introduce:**
- **(claim 4, REFUTED)** "No E2E taps the open affordance." FALSE in general — `integration_test/direct_private_media_device_local_journey_harness.dart:807` taps `private-media-open` and `:404` asserts it visible. **BUT** its tapped fixture is *outgoing* protected (`msg-p262-sender-pending`, `:538-548`) and its incoming fixture is *view-once* (`p260-production-incoming`, `:147-153`). **Under this plan's scope (1:1 received protected+disappearing), the device harness is entirely spared.** Do NOT edit the harness; do NOT treat this as a device-proof change.
- **(claim 6, REFUTED)** "Group body already contains the sender name." FALSE — group body is the name-less `group_private_media_notification_body` = "New private media" (`group_conversation_screen.dart:1032`). Irrelevant here because groups are out of scope, but recorded so a later group session doesn't assume free name plumbing.
- **(claim 3 HALF, REFUTED)** "Adding a tile tap is safe everywhere." FALSE for **groups**: the group bubble already has an opaque whole-bubble `GestureDetector` → open (`group_conversation_screen.dart:982-987`); a tile tap there steals the arena AND the existing group gate stays green (ancestor hit-center falls ~20px below the tile). This is the concrete reason groups are excluded from tile-tap.
- **(claim 5, PARTIAL → tightened further by current audit)** Keeping the existing outer `Semantics(label:)` at `:619-621` while adding an inner tile button can split label and action. The tappable branch must expose one explicit tile node with `button`, label, enabled state, and semantic tap action; its inner `GestureDetector` must use `excludeFromSemantics: true`. While opening, every pointer callback and semantic tap action is absent, the node is disabled, and localized `private_media_opening` is exposed as its state. For disappearing media, the still-visible title is excluded from semantics so its expiry label is announced exactly once by the tile button.
- **(claim 7/9, PARTIAL; tightened after KIND-01)** The ARB **keys** `private_media_card_title_protected_photo` and `private_media_open_photo` must be **KEPT** (still consumed by outgoing, group, legacy, and the retained Semantics label). The old *body* key `private_media_protected_body_received` must now also be kept exact; a new compact key is routed only to in-scope direct image/video cards. Only the visible title/button are removed at the eligible 1:1 received call site.

## Scope Contract And Guard
**In scope:**
1. `PrivateMediaVisualCard` contract changes (the shared-widget slice): (a) make `title` nullable and render the title plus its trailing 4px spacer only when `title != null`; keep the single 10px tile-to-content gap. (b) Add optional `onTap`, `opening`, `tapLabel`, and `openingLabel`, with a constructor assertion that labels are non-empty whenever `onTap != null`. The tappable branch delegates to a private stateful tile helper, leaving `PrivateMediaVisualCard` itself and its no-`onTap` branch stateless/render-identical. The helper owns `_pressed`, uses exact option-B feedback (`AnimatedScale`, `0.975`, 120ms), resets on up/cancel/drag loss, and wraps the keyed 150px `Container` in one explicit `Semantics(excludeSemantics: true, ...)` node. The inner `GestureDetector` is opaque and `excludeFromSemantics: true`; normal state exposes enabled+button+label+tap action, while opening nulls every pointer callback and semantic tap action, marks the node disabled, and exposes `openingLabel`. `excludeSemantics: true` suppresses the icon and `CircularProgressIndicator` descendant semantics so the spinner cannot create a second loading-role node. (c) Opening swaps the lock/timer icon for that semantics-excluded `CircularProgressIndicator` and dims the whole keyed tile with opacity below 1. The key remains on the inner `Container` (INV-1). **No secondary-body slot.**
2. `DirectPrivateMediaOpenPlaceholder` (1:1 received) — branch on mode, and only take the new path when **openable** (`onOpen != null`):
   - Define one exact `tapTileKind` predicate: `kind == image || kind == video`. It must be true in addition to protected/disappearing mode and `onOpen != null`.
   - **protected image/video, openable:** `title: null`, `onTap: onOpen`, `opening: opening`, no `action`; pass `tapLabel: privateMediaCardTitle(...)` and localized `openingLabel`.
   - **disappearing image/video, openable:** keep the expiry title, pass the same text as `tapLabel`, exclude the visible duplicate title from semantics, pass localized `openingLabel`, and remove the action button.
   - **protected/disappearing image/video, NOT openable (`onOpen == null`):** keep the visible title, 88px tile, and present disabled `private-media-open` button. The new compact received-body copy still applies to the selected image/video scope.
   - **GIF or any other excluded kind:** never enter the new tile/copy branch. If a durable legacy private row reaches this presentation seam, retain the existing title, 88px tile, body key, and button rather than broadening the redesign or weakening its privacy state.
   - **view-once and every other mode:** unchanged (title + button).
   - Drop the outer `Semantics(label:)` wrapper only for the tappable branch; keep it for legacy/non-tappable states.
3. Split direct **new-selection** eligibility from compatibility validation; do not remove GIF from the legacy validator:
   - Keep `PrivateMediaEligibility.allowsPrivateMedia`, `PrivateMediaPolicy.validatedFor`, and the decrypted-payload compatibility path unchanged and GIF-inclusive.
   - Add `allowsNewPrivateMedia` with the exact predicate `attachmentCount == 1 && (attachmentKind == PrivateMediaAttachmentKind.image || attachmentKind == PrivateMediaAttachmentKind.video) && !hasTextOrCaption && !isEdit && !isForward`. It differs from `allowsPrivateMedia` only by excluding GIF.
   - Point exactly four new-composition decisions at `allowsNewPrivateMedia`: `ComposeArea` selector visibility; `ConversationWired`'s pre-send composer guard; `_setPrivateMediaPolicy`; and `normalizePrivateMediaComposerPolicy`. A GIF draft has no selector, and replacing an eligible draft with GIF normalizes stale private policy to ordinary before optimistic persistence/upload/send.
   - Preserve the funnel invariant: the current external private-policy seeds are snapshot restore (`conversation_wired.dart:4409`, `:4449`), the selector setter (`:5508`), and the debug outbox (`:6522`); each must immediately reach `_updateComposerState`/`normalizePrivateMediaComposerPolicy`. The assignment at `:5575` is the sole post-normalization private-policy sink. The debug outbox source remains image/JPEG-only.
   - Re-run the `_privateMediaPolicy` writer and `sendChatMessage` caller census at execution. Any new fresh producer that can supply or inherit private policy without the direct-composer normalization funnel blocks closure and requires revisiting this boundary.
   - Do not add a new guard, enum, retry permission, or authority check to `sendChatMessage`; do not edit any retry use case. Existing durable/decrypted private-GIF intent remains private through the unchanged compatibility validator. This plan guarantees the production direct-composer behavior, not rejection of arbitrary internal calls that manufacture an explicit private-GIF policy.
   - Do not edit `GroupPrivateMediaEligibility`.
4. Scoped copy and validation text:
   - Add `private_media_protected_body_received_compact` (en/ar/de) with `"{name} doesn't allow saving or sharing."` and translations, then select it only for protected/disappearing image/video. Keep `private_media_protected_body_received` byte-for-byte for excluded/legacy paths; do not globally retext it.
   - Lock the legacy key's exact values before production edits: en `"You can view it again. {name} doesn't allow saving or sharing."`; ar `"يمكنك مشاهدته مجددًا. {name} لا يسمح بالحفظ أو المشاركة."`; de `"Du kannst es erneut ansehen. {name} erlaubt kein Speichern oder Teilen."`
   - Retext `private_media_invalid_shape` exactly: en `"Private media needs one photo or video with no caption."`; ar `"تتطلب الوسائط الخاصة صورة أو فيديو واحدًا بلا تعليق."`; de `"Private Medien benötigen ein Foto oder Video ohne Bildunterschrift."` Remove the contradictory GIF eligibility claim.
   - Run `flutter gen-l10n`. Keep the existing title/open/GIF sheet keys; the GIF sheet title becomes unreachable through the selector but removing historical keys is unnecessary scope.
5. Update the incoming-protected tests that tapped the old button to tap the tile; add new RED coverage for tile-tap / no-title / single-line-body / in-tile-spinner / a11y-label-retained, plus the exact image/video × protected/disappearing matrix and GIF exclusion contract.

**Must preserve:**
- Received view-once title, confirmation button, 88px tile, and one-view body → extend `test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart::view-once placeholder states single view`.
- `onOpen == null` protected title, 88px tile, and disabled button → TC-09 plus existing `test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart::private card title renders the protected media kind`.
- Outgoing/open-failure/no-pixel paths → existing viewer/card sentinels.
- Group title, 88px tile, inner action, and whole-bubble open → extend `group_private_media_capabilities_test.dart::GPL-09 active private bubble exposes only the dedicated open path`.
- Ordinary GIF send/MIME/animation behavior → existing `send_chat_message_use_case_test.dart::sends GIF-only media with image/gif preserved in the wire envelope`; extend it to assert ordinary persisted/effective policy and no decrypted inner `privateMedia` field. Transport/envelope code is unchanged, so this is semantic envelope preservation rather than a raw-byte claim.
- Durable private-GIF fallback remains privacy-safe and legacy-rendered → extend the tile/card tests to assert no 150px tap branch or compact-copy key for the defensive legacy fixture; run `full_screen_typed_media_viewer_test.dart::iOS private images and GIFs use the protected native surface`.
- Legacy private-GIF decode remains private → add one cheap `message_payload_test.dart` sentinel proving a GIF-inclusive legacy payload stays private and supported. Existing retry code and its curated tests remain untouched.

**Hard `Do not`:**
- Do NOT edit group-chat production or the device harness.
- Do NOT expose a private selector for a new GIF draft or let stale private policy survive an image/video → GIF replacement.
- Do NOT change `sendChatMessage`, retry use cases, the GIF-inclusive compatibility validator, or legacy payload semantics.
- Do NOT silently convert legacy private GIF to ordinary or apply the compact copy/tap tile to it.
- Do NOT globally retext `private_media_protected_body_received` or delete still-consumed ARB keys.
- Do NOT expose a second spinner/loading semantics node or keep split outer/inner action labels.
- Do NOT remove view-once/outgoing/failure controls or the disappearing expiry title.
- Do NOT apply the visual redesign when `onOpen == null`, add a secondary body line, add real pixels, or move the visual key off its no-pixel `Container`.

**Deferred / accepted differences:**
- **Groups** (`group_conversation_screen.dart:1088`) — deliberately untouched (user decision). TC-16 and the `groups` command are regression containment for a shared widget, not group feature scope; this plan creates no group follow-up requirement.
- **View-once** received mode — keeps title + "View photo" button (irreversible-action confirmation).
- **Outgoing/sender**, **open-failure**, **consumed/expired/unsupported** — untouched.
- The device E2E harness — spared under this scope; do not edit.
- Tap feedback is a scale, not ink, because the bubble has no local `Material`.
- Mechanical ar/de prefix trims remain subject to native-speaker follow-up; automated negative-prefix checks are required now.

**Resolved attachment-kind contract (KIND-01):**
- Included: direct 1:1 image and video. Both receive the tap-tile redesign for protected/disappearing modes and use correct photo/video semantic labels.
- Excluded from new privacy selection: GIF. New direct-composer GIF drafts expose/send only ordinary “Keep in chat,” and stale selected policy resets before persistence/send. Older peer/durable payloads remain private through unchanged compatibility paths and use the legacy card/body/native-protection path. No domain-wide explicit-private-GIF rejection is claimed.
- Excluded: all group-chat behavior. The group caller is observed only to prove the shared no-`onTap` branch did not change.
- TC-18 names the exact new-selection policy, composer normalization, legacy decode/native-protection, image/video UI matrix, legacy-GIF presentation, and ordinary-GIF proofs. No scope evidence gate remains.

**Dependencies:**
- Plan 270 supersedes only plan 234's direct GIF **new-selection** clause; its historical wire/durable privacy contract remains the compatibility floor and is not rewritten.
- The relevant direct protected-media presentation wave owns the later wave-level full `host-all`; this plan does not depend on or authorize a group alignment.

## Files To Inspect Next
Production:
- `lib/core/media/private_media_policy.dart` — unchanged GIF-inclusive `PrivateMediaEligibility.allowsPrivateMedia`, new full-shape image/video-only `allowsNewPrivateMedia`, unchanged `validatedFor`, and composer normalization (:51-82, :237-282).
- `lib/features/conversation/presentation/screens/direct_private_media_viewer.dart` — `PrivateMediaVisualCard` (:457), `DirectPrivateMediaOpenPlaceholder` (:566), `privateMediaCardTitle` (:532), `privateMediaModeLabel` (:441), body switch (:613-618).
- `lib/features/conversation/presentation/screens/conversation_screen.dart` — the only construction site of `DirectPrivateMediaOpenPlaceholder` (:1048-1067), `opening` from `_privateOpenInFlight` (:983).
- `lib/features/conversation/presentation/widgets/compose_area.dart` (:435-437) and `lib/features/conversation/presentation/screens/conversation_wired.dart` (:3306-3316, :4409-4413, :4449-4453, :5506-5511, :5569-5575, :6522-6529) — switch the four new-selection/reset decisions to `allowsNewPrivateMedia`; verify the three external seed families reach normalization and `:5575` remains the sole normalized sink.
- `lib/features/conversation/application/send_chat_message_use_case.dart` — inspect only to preserve the unchanged compatibility/send behavior; no production edit.
- `lib/features/conversation/domain/models/message_payload.dart` (:209-221, :298-327) — older private-GIF inner payload remains private through compatibility validation; inspect for preservation proof, no new-selection predicate here.
- `lib/l10n/app_{en,ar,de}.arb` — add `private_media_protected_body_received_compact`, preserve `private_media_protected_body_received`, and correct `private_media_invalid_shape`. `l10n.yaml`, `pubspec.yaml:113`.
Direct tests:
- `test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart` — new TC-01..10 file.
- `test/features/conversation/domain/models/private_media_policy_test.dart` (:49-115)
- `test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart` (:89-153, :385-446, :467-510)
- `test/features/conversation/application/send_chat_message_use_case_test.dart` — extend the existing ordinary-GIF proof to assert ordinary persisted/effective policy and no decrypted inner `privateMedia`; do not add retry-lane or arbitrary-explicit-call tests.
- `test/features/conversation/domain/models/message_payload_test.dart` (:607-756) — add older private-GIF decode preservation (private, never ordinary/unsupported).
- `test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart` (:1365-1467)
- `test/features/conversation/presentation/screens/direct_private_media_placeholder_body_test.dart` (:33-110)
- `test/features/conversation/presentation/screens/direct_private_media_card_test.dart` (:131-312)
- `test/features/conversation/presentation/screens/direct_private_media_continuity_test.dart` (:103-281)
- `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart` (:826-877, :1205-1237)
- `test/features/conversation/presentation/screens/conversation_wired_test.dart` — add a real image-private-selection → GIF-replacement integration proving the stale policy resets before optimistic persistence/upload/injected send; retain the existing hydration sentinels at :4464-4598 and :10796-10868.
- `test/features/groups/presentation/group_private_media_capabilities_test.dart` (:198-234)
- `test/l10n/private_media_ux_strings_test.dart`, `test/l10n/l10n_integrity_test.dart`
- `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart` — exact existing iOS private-GIF native-surface selector sentinel. Android route-scoped `FLAG_SECURE` and all native production code are unchanged and outside this plan's proof claim.
- `scripts/run_test_gates.sh` — add the new test once to `ONE_TO_ONE_TESTS`; verify that exact source array with the scoped `awk ... | rg` check and run the actual unbatched `1to1` gate. Do not use `1to1 --list`, which delegates to the separate host-only registry.
Dependency-only context:
- `lib/features/conversation/presentation/widgets/letter_card.dart` (:767-777 no-Material bubble; :900-905 long-press ancestor) — explains why a bare `GestureDetector` (not `InkWell`) is used.
- `integration_test/direct_private_media_device_local_journey_harness.dart` (:404, :807) — confirm spared, do NOT edit.

## Test Contract

The contract has 18 fully defined host/unit/widget rows. TC-18 locks the resolved image/video-only, GIF-ordinary, and direct-only boundary.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-01 | Protected tile opens | `test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart::tapping the tile opens a received protected photo` | widget / localized `DirectPrivateMediaOpenPlaceholder`, callback spy | HEAD tile is inert -> GREEN one tap invokes `onOpen` once | remove tile tap handler -> TC-01 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart --plain-name 'tapping the tile opens a received protected photo'`; AUTO feature glob + add to `ONE_TO_ONE_TESTS` |
| TC-02 | Openable protected removes visible title/button and orphan title spacing | `test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart::received protected card removes visible title button and orphan title spacing` | widget / protected image, non-null `onOpen` | HEAD shows title/button and title spacer -> GREEN neither widget exists and only the 10px tile-to-body gap remains | restore title/action or leave the 4px title spacer -> TC-02 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart --plain-name 'received protected card removes visible title button and orphan title spacing'`; AUTO + `ONE_TO_ONE_TESTS` |
| TC-03 | Received protected body is exact one-sentence sender copy | `test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart::received protected body is one exact sender-attributed line` | widget / English l10n | HEAD contains the lead-in -> GREEN exact `"pixel doesn't allow saving or sharing."` and no old lead-in | restore old ARB text and regenerate -> TC-03 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart --plain-name 'received protected body is one exact sender-attributed line'`; AUTO + `ONE_TO_ONE_TESTS` |
| TC-04 | Disappearing keeps visible expiry title, has one expiry announcement, loses button, and opens by tile | `test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart::disappearing card keeps one expiry announcement and opens from the tile` | widget / `PrivateMediaPolicy.disappearing(3600)`, callback + semantics | HEAD has button/inert tile -> GREEN visible expiry title, exactly one matching semantics node, no button, and one open | restore action, drop title, or expose duplicate title semantics -> TC-04 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart --plain-name 'disappearing card keeps one expiry announcement and opens from the tile'`; AUTO + `ONE_TO_ONE_TESTS` |
| TC-05 | Opening tile shows spinner/dim and one truthful disabled semantics node | `test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart::opening tile is dimmed busy disabled and has no tap or child spinner semantics` | widget / protected image, `opening:true`, callback spy + semantics tree | HEAD spinner/value live in button -> GREEN spinner is inside tile, opacity is below 1, localized opening state is present on exactly one tile button node, that node is disabled with no `SemanticsAction.tap`, no descendant `loadingSpinner` role/node survives, and pointer tap does not invoke callback | remove the opening-state branch or `excludeSemantics` -> TC-05 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart --plain-name 'opening tile is dimmed busy disabled and has no tap or child spinner semantics'`; AUTO + `ONE_TO_ONE_TESTS` |
| TC-06 | Enabled protected tile is exactly one labeled semantic button with activation | `test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart::enabled protected tile is one labeled semantic button with a tap action` | widget / semantics handle disposed by teardown | HEAD keyed tile is not a button (its ancestor may already supply a label) -> GREEN one `"Protected photo"` node is enabled, is a button, and has `SemanticsAction.tap` | restore outer/inner split, duplicate label, or omit semantic tap -> TC-06 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart --plain-name 'enabled protected tile is one labeled semantic button with a tap action'`; AUTO + `ONE_TO_ONE_TESTS` |
| TC-07 | Tile tap coexists with ancestor long-press and horizontal swipe-to-quote | `test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart::tile tap preserves ancestor long press and swipe to quote` | widget / real `SwipeToQuoteBubble` plus long-press ancestor | HEAD tap half fails -> GREEN tap opens only, long-press invokes ancestor only, horizontal drag quotes without opening, and canceled press scale resets | remove tile tap or add a competing tile drag recognizer -> TC-07 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart --plain-name 'tile tap preserves ancestor long press and swipe to quote'`; AUTO + `ONE_TO_ONE_TESTS` |
| TC-08 | Tile is 150px only when openable | `test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart::tile is 150px only when openable` | widget / same card pumped with non-null and null `onOpen` | HEAD both are 88px -> GREEN openable is 150px and null-open is 88px | force either fixed height -> TC-08 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart --plain-name 'tile is 150px only when openable'`; AUTO + `ONE_TO_ONE_TESTS` |
| TC-09 | `onOpen == null` preserves title, 88px tile, and disabled button | `test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart::not-openable protected card keeps title 88px tile and disabled button` | widget / null `onOpen` | GREEN sentinel on HEAD -> remains titled, non-button 88px tile, `private-media-open` present, and `FilledButton.onPressed == null` | apply tile branch unconditionally or remove disabled action -> TC-09 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart --plain-name 'not-openable protected card keeps title 88px tile and disabled button'`; AUTO + `ONE_TO_ONE_TESTS` |
| TC-10 | Press feedback matches approved option B and resets | `test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart::tap feedback scales to 0.975 and resets on up and cancel` | widget / pointer start, up, cancel/drag loss; inspect tile's `AnimatedScale` ancestor | HEAD has no scale state -> GREEN target scale is 0.975 on down and 1.0 after up/cancel within 120ms | remove private stateful helper or a reset callback -> TC-10 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart --plain-name 'tap feedback scales to 0.975 and resets on up and cancel'`; AUTO + `ONE_TO_ONE_TESTS` |
| TC-11 | Exact scoped en/ar/de compact body for protected/disappearing image/video and directionality; legacy body key unchanged | `test/features/conversation/presentation/screens/direct_private_media_placeholder_body_test.dart::protected and disappearing image and video placeholders show compact sender-attributed body`; `test/features/conversation/presentation/screens/direct_private_media_placeholder_body_test.dart::compact received bodies render literal ar and de copy without old lead-ins and remain RTL-safe`; `test/l10n/private_media_ux_strings_test.dart::plan 270 compact copy and image-video eligibility text are exact` | widget + host file-I/O / protected+disappearing × image/video; pump real `Locale('ar')` and `Locale('de')` generated localizations | HEAD compact key is absent, image/video use the old prefix, and invalid-shape copy claims GIF eligibility -> GREEN rendered text equals hard-coded Arabic `"{name} لا يسمح بالحفظ أو المشاركة."` and German `"{name} erlaubt kein Speichern oder Teilen."` expectations rather than localization-getter output; literal old lead-ins are absent; image/video-only validation text and `{name}` parity are exact while old `private_media_protected_body_received` values remain byte-for-byte | route compact copy only to protected, use generated getters as expected values, skip the German render, alter the legacy key, restore a compact prefix/GIF eligibility claim, or omit regeneration -> TC-11 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_placeholder_body_test.dart test/l10n/private_media_ux_strings_test.dart`; body test in existing `ONE_TO_ONE_TESTS`, l10n run explicitly |
| TC-12 | ConversationScreen tile reaches the typed private launcher | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::received protected tile reaches typed private launcher and never enters ordinary viewers` | widget/host wiring / completed image, typed-launcher identity spy | HEAD tile tap invokes nothing -> GREEN exact message/attachment identity reaches typed launcher once and ordinary viewers remain absent | drop call-site `onTap` wiring or route to ordinary viewer -> TC-12 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'received protected tile reaches typed private launcher and never enters ordinary viewers'`; existing `ONE_TO_ONE_TESTS` |
| TC-13 | Existing hydration/redaction tests migrate handles without pretending to be causal | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::private terminal and stale parents never enter typed or legacy ordinary viewers`; `test/features/conversation/presentation/screens/conversation_wired_test.dart::active private identity survives initial and live hydration until terminal`; `test/features/conversation/presentation/screens/conversation_wired_test.dart::private and unsupported parents skip visible recovery before policy or transfer` | GREEN sentinel / real screen fixtures | HEAD already has the tile key -> GREEN sentinel continues to count the scoped tile while secret bytes/ordinary viewers remain absent | remove tile/redaction or allow an extra scoped tile -> TC-13 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart test/features/conversation/presentation/screens/conversation_wired_test.dart`; existing `ONE_TO_ONE_TESTS` |
| TC-14 | ARB key/placeholder parity survives the new compact key and validation-copy update | `test/l10n/l10n_integrity_test.dart::l10n integrity ARB files have identical non-empty key and placeholder sets` | GREEN sentinel, host file-I/O / real ARBs | GREEN on HEAD -> remains green with the compact key in all locales and `{name}` parity | omit the key or `{name}` from one locale -> TC-14 red | `flutter test test/l10n/l10n_integrity_test.dart`; AUTO shared test, run explicitly |
| TC-15 | Received view-once keeps title, confirmation button, 88px tile, and open continuity | `test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart::view-once placeholder states single view`; `test/features/conversation/presentation/screens/direct_private_media_continuity_test.dart::one tap downloads then auto-continues under one single-flight` | GREEN sentinel / widget plus real ConversationScreen fake launcher | GREEN on HEAD -> title/body/button/88px and button-borne opening continuity remain unchanged | broaden tile predicate to view-once -> TC-15 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart test/features/conversation/presentation/screens/direct_private_media_continuity_test.dart`; viewer in `ONE_TO_ONE_TESTS`, continuity run explicitly |
| TC-16 | Group no-`onTap` branch keeps title, 88px tile, inner action, and whole-bubble open | extended `test/features/groups/presentation/group_private_media_capabilities_test.dart::GPL-09 active private bubble exposes only the dedicated open path` | GREEN sentinel / group widget fixture | GREEN on HEAD -> exact group title/action/height and `group-private-open-*` callback remain | leak new tile branch into no-`onTap` callers -> TC-16 red | `flutter test test/features/groups/presentation/group_private_media_capabilities_test.dart --plain-name 'GPL-09 active private bubble exposes only the dedicated open path'`; existing `GROUP_TESTS` |
| TC-17 | Shared no-pixel, outgoing, and open-failure branches stay render-compatible | `test/features/conversation/presentation/screens/direct_private_media_card_test.dart::card shows no-pixel visual header and media-kind title`; `test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart::sender protected and view-once expose one-more-look while disappearing and missing local media do not`; `test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart::typed open failure copy claims safety only for exact rollback` | GREEN sentinel / widget fixtures | GREEN on HEAD -> keyed widget remains a `Container` with no image, and sibling actions/copy remain | move key to wrapper, add pixels, or alter no-`onTap` branch -> TC-17 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_card_test.dart test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart`; existing `ONE_TO_ONE_TESTS` |
| TC-18 | New direct composition and the tap-tile redesign cover image/video only; GIF stays newly ordinary while compatibility remains unchanged | `test/features/conversation/domain/models/private_media_policy_test.dart::new private selection permits image and video while compatibility validation preserves GIF`; `test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart::selector appears only for one eligible image or video and GIF stays keep in chat`; `::every stale or ineligible composer shape resets private policy`; `test/features/conversation/presentation/screens/conversation_wired_test.dart::replacing a private image draft with GIF resets to keep in chat before optimistic persistence`; extended existing `test/features/conversation/application/send_chat_message_use_case_test.dart::sends GIF-only media with image/gif preserved in the wire envelope`; `test/features/conversation/domain/models/message_payload_test.dart::legacy private GIF inner policy remains private and never becomes ordinary`; `test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart::protected and disappearing tap tile covers image and video while legacy GIF keeps the old branch`; existing `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart::iOS private images and GIFs use the protected native surface` | host unit + widget / full predicate matrix; real image→GIF replacement; ordinary-GIF semantic envelope; legacy decode; protected/disappearing × image/video UI table; defensive legacy-GIF card and iOS selector | HEAD has no split predicate, composer selection admits GIF, and image/video use the inert 88px/button UI -> GREEN only a single captionless, non-edit, non-forward image/video is newly private-selectable; GIF replacement clears policy before optimistic persistence and reaches the injected seam as ordinary; ordinary GIF stores an ordinary policy and decrypted inner JSON has no `privateMedia`; legacy decode stays private/supported; every protected/disappearing × image/video fixture has a 150px tappable semantic tile, no old button, and the correct photo/video label; protected removes its title while disappearing preserves its expiry title; legacy GIF stays on the 88px/title/button/old-copy branch | weaken any shape guard, route new selection through compatibility eligibility, remove video, retain stale policy through GIF replacement, downgrade legacy policy, omit the kind/compact-key guard, or remove the iOS native selector -> TC-18 red | `private_media_policy_test.dart`, `conversation_wired_test.dart`, `send_chat_message_use_case_test.dart`, `message_payload_test.dart`, and the new `direct_private_media_tile_tap_test.dart` are `ONE_TO_ONE_TESTS` owners (add the new tile path exactly once); `conversation_private_media_composer_test.dart` is exact + AUTO, not curated; run `full_screen_typed_media_viewer_test.dart` by exact name outside `1to1` |

### Test Notes

- The new tile test must install `AppLocalizations.localizationsDelegates` / `supportedLocales`. Every semantics test stores `final handle = tester.ensureSemantics()` and disposes it with `addTearDown(handle.dispose)`.
- Use the positional factory `PrivateMediaPolicy.disappearing(3600)`.
- TC-05/06 use explicit `Semantics(excludeSemantics: true, enabled:, button:, label:, value:, onTap:)` around `GestureDetector(excludeFromSemantics: true)`. Null every pointer callback while opening; otherwise Flutter can retain a dead semantic tap action. `excludeSemantics` is also required so the indeterminate `CircularProgressIndicator` cannot contribute a second `loadingSpinner` node; TC-05 inspects the semantics tree for exactly one tile node.
- TC-04 excludes the visible disappearing title from semantics only on the tappable branch, so the expiry text remains visible but is announced once by the tile.
- TC-10 finds the `AnimatedScale` ancestor of the keyed `Container`; the private stateful helper is the sole owner of transient `_pressed` state.
- TC-11 pumps real Arabic and German locales and compares rendered output with hard-coded literal strings, including the substituted sender name; generated localization getters must not supply the expected values. It also asserts literal old prefixes are absent and the old key is preserved exactly.
- TC-12 extends the local screen builder with a typed private-launcher parameter and asserts the exact `DirectPrivateMediaViewerIdentity`; absence of ordinary viewers alone is not causal.
- TC-18 expectations must be authored before production edits. The new-selection getter/test initially compile-RED; once stubbed, composer/new-composition expectations remain assertion-RED because current paths use GIF-compatible `allowsPrivateMedia`. Move the GIF portion of `disclosure is platform-true and sender reopen is gated` to an eligible image fixture so sender-reopen coverage survives without retaining an unreachable GIF sheet.
- TC-18's ordinary-GIF, legacy decode, and iOS native-surface proofs are GREEN sentinels on HEAD and must remain green. Extend the ordinary test to assert `message.privateMediaPolicy == ordinary` and decrypted inner JSON has no `privateMedia`. The transport/envelope format is invariant because send and retry production code are untouched. “Keep in chat only” constrains new direct composition; it does not downgrade older private state or make `sendChatMessage` a new authorization boundary.
- Group chat is not part of TC-18's feature matrix. TC-16 is the sole group preservation row and must not be satisfied by editing group production.
- `classify_path` auto-discovers the new presentation test, but curated ownership is manual: add its exact path to `ONE_TO_ONE_TESTS`, verify that source array with the scoped `awk ... | rg` check, and run the actual unbatched `1to1` gate.

## Risks And Blind Spots
- **Lifecycle / derived-state durability:** the tile helper introduces only ephemeral `_pressed` UI state; TC-10 proves down/up/cancel reset. The kind correction is confined to composer-derived policy. Compatibility validation, send, and retry production paths remain unchanged, so existing durable private-GIF state is not reclassified.
- **Sibling-surface consistency:** TC-15 proves received view-once, TC-16 pins the out-of-scope group title/height/action/whole-bubble open, TC-17 pins outgoing/open-failure/no-pixel branches, and TC-18 locks image/video inclusion plus GIF exclusion.
- **Destructive-action side effects:** N/A — no delete/cleanup/cancel path changes. TC-12 positively proves the exact typed private identity reaches the existing launcher and that ordinary viewers remain absent.
- **Invariant re-verification under new transitions:** TC-05 covers opening visual/pointer/semantics state, TC-08/09 cover null↔non-null openability, and TC-10 covers press down/up/cancel. TC-07 exercises the real horizontal-drag competitor plus the long-press ancestor.
- **Group tap swallow:** never pass tile `onTap` from the group call site; TC-16 plus `groups` gate preserve the existing opaque whole-bubble open.
- **Semantics split/duplication:** use one explicit `excludeSemantics` tile node, exclude the inner detector and spinner/icon descendants, and exclude only the duplicate visible disappearing title. TC-04/05/06 distinguish normal, disappearing, and opening trees and reject a second loading-spinner node.
- **Generated-l10n split brain:** run `flutter gen-l10n` after all three ARBs; TC-11 proves exact strings and TC-14 proves key/placeholder parity.
- **Historical GIF contract:** plan 234 and current tests explicitly allowed direct private GIFs. This plan removes GIF only from new direct-composer selection/state, not from compatibility validation. Old durable/wire private-GIF retry, presentation, and iOS native-surface selection must not be weakened or receive the new tile/copy. TC-17/18 lock the changed boundary and cheap preservation sentinels.
- **Retired transport risks:** the read-only send-caller and policy-writer census is required evidence for composer containment, but no send caller is edited. Dropping the front guard retires the duplicate-authority lock hazard and the need for a new host-only transport-authorization proof.
- **Native scope:** the existing exact viewer sentinel locks iOS image/GIF native-surface selection. Android route-scoped `FLAG_SECURE` and all native production code are unchanged and explicitly outside Plan 270's proof claim.
- **Device-harness false alarm:** the harness's mounted/tapped UI fixtures are outgoing protected and incoming view-once. An incoming disappearing lifecycle fixture exists but is not mounted as this UI; no device edit or proof is required.

## Invariants (locked by tests)
- INV-1: Real pixels never enter `PrivateMediaVisualCard` — locked by `card_test:131-152` (no Image/RawImage/MediaGrid; tile stays `Container`+`BoxDecoration`). The GestureDetector wraps *around* the keyed Container so this stays green.
- INV-2: The actionable tile has exactly one label-bearing, enabled semantic button node with a tap action; its opening state is one disabled node with no tap action or descendant loading-spinner semantics — TC-04/05/06.
- INV-3: Exactly one open may be in flight — UI guard TC-05 plus positive ConversationScreen wiring TC-12 preserve `_privateOpenInFlight`.
- INV-4: View-once keeps its title, confirmation button, 88px tile, and continuity path — TC-15.
- INV-5: The tile is 150px only when openable, 88px otherwise — locked by TC-08.
- INV-6: A not-yet-openable/denied received protected card keeps its title, 88px tile, and present disabled button and is not a tile-button — TC-09.
- INV-7: Only a single captionless, non-edit, non-forward direct image/video is newly private-selectable and tap-tile eligible. A direct-composer GIF is ordinary “Keep in chat,” stale private policy normalizes away before persistence/send, and legacy private GIF remains compatibility-valid while never entering the new tile/copy branch — TC-18.
- INV-8: Group chats receive no policy, copy, gesture, or presentation change; TC-16 is preservation-only.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to defined causal rows during execution; this planning pass does not claim that evidence has run.

## Implementation Steps
0. **Snapshot and author RED first.** Record `git status --short`. Add the new tile tests, TC-12 positive wiring test, literal en/ar/de expectations, view-once/group preservation assertions, and TC-18 new-selection/normalization expectations before production edits. Add the new tile test path once to `ONE_TO_ONE_TESTS`. Run TC-01..08, TC-10..12, and the causal portions of TC-18 and record non-zero results; TC-09, TC-13..17, ordinary GIF, legacy decode, and iOS native-surface selection are explicitly GREEN sentinels.
1. **Split new-selection eligibility from compatibility validation.** Keep `allowsPrivateMedia` and `validatedFor` unchanged. Add the full-shape image/video-only `allowsNewPrivateMedia`, then move exactly the selector, pre-send composer guard, policy setter, and composer normalizer to it. Verify by assignment census that snapshot restore and the JPEG-only debug outbox continue to reach `_updateComposerState` normalization. Prove the full shape matrix, selector exclusion, stale/ineligible reset, and real image→GIF replacement reaching optimistic persistence/injected send as ordinary. Do not change `sendChatMessage`, retry use cases, `GroupPrivateMediaEligibility`, or legacy decode semantics. Stop if any private-capable composer writer bypasses normalization, if an ordinary GIF gains private composer state, or if older private-GIF payloads are downgraded.
2. **Add the isolated shared-widget slice.** Keep `PrivateMediaVisualCard` stateless, make `title` nullable, conditionally render title plus its 4px spacer, and delegate only the `onTap != null` branch to a private stateful tile helper. The helper owns `_pressed`; uses 0.975/120ms `AnimatedScale`; dims opening state; keeps the key on the 150px `Container`; controls one explicit `Semantics(excludeSemantics: true, ...)` node; sets `excludeFromSemantics: true` on the detector; suppresses icon/spinner descendant semantics; and nulls every pointer/semantic action while opening. Keep the no-`onTap` 88px branch structurally unchanged. Stop-if TC-05/09/15/16/17 change.
3. **Wire the image/video-only direct branch.** In `DirectPrivateMediaOpenPlaceholder`, require the exact image/video predicate plus protected/disappearing mode and `onOpen != null`; remove protected title/action, retain and semantics-exclude the duplicate disappearing title, pass localized photo/video tap/opening labels, and drop the old outer label only for this tappable branch. Keep view-once, null-open, GIF/other kinds, and every group call site on their legacy paths. Stop-if TC-04/05/06/18 or any preservation row fails.
4. **Add scoped copy and regenerate l10n.** Add, rather than overwrite, the compact received-body key:
   - `app_en.arb` `private_media_protected_body_received_compact` → `"{name} doesn't allow saving or sharing."`
   - `app_ar.arb` → `"{name} لا يسمح بالحفظ أو المشاركة."`
   - `app_de.arb` → `"{name} erlaubt kein Speichern oder Teilen."`
   Select it only for protected/disappearing image/video; keep `private_media_protected_body_received` exact for excluded/legacy paths. Retext `private_media_invalid_shape` exactly to en `"Private media needs one photo or video with no caption."`, ar `"تتطلب الوسائط الخاصة صورة أو فيديو واحدًا بلا تعليق."`, and de `"Private Medien benötigen ein Foto oder Video ohne Bildunterschrift."` Run `flutter gen-l10n` to regenerate the four tracked localization Dart files. Keep existing title/open/GIF sheet keys.
5. **GREEN and representative mutation re-red.** Run every focused row, then representative mutations for gesture, spinner/semantics opening, press reset, compact-key routing/regeneration, the full new-selection predicate, GIF normalization, legacy decode, and no-`onTap` group preservation. Revert each mutation immediately after its owning test re-reds; do not claim this planning document already ran them.
6. **Close with exact sentinels and named gates.** Verify per-file registration, run focused preservation files including the iOS native-surface selector, `1to1`, `groups` as shared-widget preservation only, l10n, analyzer, and diff checks. Full `host-all` remains owned by the wave/final cadence below.

## Gate Cadence

- Per-plan closure: focused TC-01..18 commands, exact direct-policy/composer/wired/send/decode/continuity/l10n/iOS-selector sentinels, curated `1to1`, and `groups` only because the shared card has a group caller whose unchanged branch needs preservation proof. Although the eligibility type lives under `lib/core`, its changed consumers are in the direct-composer path and groups use their separate `GroupPrivateMediaEligibility`; the exact tests plus `1to1` cover this without a per-plan `core-host-all`. No `feature-host-all`, performance, simulator, or device sweep is justified.
- Do not run full `host-all` for this individual plan. Run `./scripts/run_host_test_gates.sh host-all` once after the relevant direct protected-media presentation wave and once at final rollout/release closure.
- Shared tests outside feature/core globs: run `test/l10n/l10n_integrity_test.dart`, `test/l10n/private_media_ux_strings_test.dart`, and the exact `full_screen_typed_media_viewer_test.dart` native-GIF selector directly. `direct_private_media_continuity_test.dart` is inside the feature glob but outside the curated `1to1` array, so run it directly as TC-15.

## Acceptance Gates (literal — copy/paste)
```bash
# Dirty-tree snapshot FIRST (do not revert unrelated changes)
git status --short

# Recheck the DROP decision's source contract. Review every hit; a new
# unnormalized private-policy writer or private-capable fresh caller blocks.
rg -n '_privateMediaPolicy\s*=[^=]' \
  lib/features/conversation/presentation/screens/conversation_wired.dart
rg -n 'sendChatMessage(?:Fn)?(?:\s*=|\s*\()' lib

# First causal RED on pre-production HEAD; expect non-zero because the tile is inert
flutter test test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart \
  --plain-name 'tapping the tile opens a received protected photo'

# Kind-boundary RED after authoring the split predicate; HEAD still exposes GIF
flutter test test/features/conversation/domain/models/private_media_policy_test.dart \
  --plain-name 'new private selection permits image and video while compatibility validation preserves GIF'

# l10n regen (after ARB edits, before GREEN)
flutter gen-l10n

# Focused GREEN; every command must exit 0 with zero failed tests
flutter test test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart
flutter test \
  test/features/conversation/domain/models/private_media_policy_test.dart \
  test/features/conversation/domain/models/message_payload_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart \
  test/features/conversation/presentation/screens/direct_private_media_placeholder_body_test.dart \
  test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_test.dart

# Exact preservation sentinels; all exit 0 (group command proves non-change only)
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart \
  test/features/conversation/presentation/screens/direct_private_media_card_test.dart \
  test/features/conversation/presentation/screens/direct_private_media_continuity_test.dart
flutter test test/features/groups/presentation/group_private_media_capabilities_test.dart \
  --plain-name 'GPL-09 active private bubble exposes only the dedicated open path'
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  --plain-name 'iOS private images and GIFs use the protected native surface'

# l10n exact copy/key/placeholder preservation; exit 0
flutter test test/l10n/l10n_integrity_test.dart test/l10n/private_media_ux_strings_test.dart

# Fail-closed registration check scoped to the array used by the actual 1to1 gate.
# Do not use `1to1 --list`: it delegates to a different host-only registry.
awk '/^readonly ONE_TO_ONE_TESTS=\(/,/^\)/' scripts/run_test_gates.sh |
  rg -Fxc '  "test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart"' |
  rg -x '1'

# Named family gates; exit 0, zero failures, and output selects the new file.
# `groups` is shared-widget regression containment, not group feature scope.
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups

# Hygiene; no new analyzer issues and no whitespace errors
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-01..08 and TC-10..12 fail on pre-production HEAD for the named causal reason. TC-18's new-selection predicate initially compile-fails; after the test stub, composer/normalization expectations remain RED because HEAD exposes GIF, while its image/video tile matrix is RED because the tile is still inert/88px. TC-06 is RED because the keyed tile is not a button/tap action even though current `getSemantics` can climb to the outer label.
- Green sentinel: TC-09 and TC-13..17 plus TC-18's ordinary-GIF, legacy decode, and iOS native-surface proofs pass on HEAD and must remain green.
- Pre-existing dirty planning baseline: modified `Test-Flight-Improv/00-INDEX.md` plus untracked plan/mockup. Preserve unrelated work and record the execution-time snapshot.
- Environment blocker: none for host closure; use repository-relative commands and the discovered `flutter` on `PATH`.
- Scope drift: any new direct-composer GIF private selector/state, normalization bypass, shape-guard weakening, send/retry/compatibility production edit, image/video exclusion, legacy private-GIF downgrade, compact-copy/tile leakage to legacy GIF, iOS selector regression, view-once/outgoing/failure/group production change, real-pixel entry, duplicate/dead/loading-spinner semantics action, or device-harness edit blocks closure.

- [ ] TC-18 records real RED→GREEN evidence for image/video inclusion and GIF exclusion plus the ordinary-GIF sentinel; TC-16 separately records group preservation.
- [ ] The execution-time census records the known external private-policy seeds (`:4409`, `:4449`, `:5508`, `:6522`) flowing to normalization, `:5575` as the sole normalized sink, and no new private-capable fresh send producer outside the direct-composer funnel.
- [ ] Every remaining behavior has the named proof in the Test Contract.
- [ ] Causal RED, focused GREEN, and representative mutation re-red are recorded during execution.
- [ ] TC-09 and TC-13..18, exact l10n tests, `1to1`, and preservation-only `groups` pass with zero failures.
- [ ] The new tile test appears exactly once in the scoped `ONE_TO_ONE_TESTS` source block, and the actual unbatched `1to1` gate selects/runs it.
- [ ] l10n is regenerated; exact en/ar/de copy and `{name}` parity pass.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.
- [ ] The unified Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `flutter test test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart --plain-name 'tapping the tile opens a received protected photo'`.
- Kind-boundary RED command after the expectation is authored: `flutter test test/features/conversation/domain/models/private_media_policy_test.dart --plain-name 'new private selection permits image and video while compatibility validation preserves GIF'`.
- Preservation command: `flutter test test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart test/features/conversation/presentation/screens/direct_private_media_card_test.dart test/features/conversation/presentation/screens/direct_private_media_continuity_test.dart`.
- Manual registration: add `test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart` once to `ONE_TO_ONE_TESTS`. TC-18's policy, wired, send, and decode files are already registered; composer is exact + AUTO and the shared viewer runs by exact name. Verify the correct array with the scoped `awk ... | rg` command, not `1to1 --list`.
- Migration: none.
- Boundary closure: host-only; no simulator, device, relay, real crypto, or SQLCipher proof.
- Gate cadence: focused tests + exact sentinels + `1to1` + preservation-only `groups`; full `host-all` after the relevant direct presentation wave and at final release closure.
- Unresolved evidence: none. Implementation and runtime test evidence have not run.

## Reviewer Findings (historical `/tdd-review`)
`/tdd-review` 8-agent audit (`wf_0730119f-6d4`, 2026-07-24; 1 verifier died on a retry cap but its ground — sibling enumeration, blast radius — was independently re-established by the critic's B-2/B-3 sweep). Dimension scores: Goal 64 / Compartmentalization 72 / Anti-drift 51 (weak) / Define-good 67 / Goal-verification 50 (weak). **Core bet VERIFIED SOUND**: gesture routing (opaque `GestureDetector` `hitTestSelf`), long-press/swipe coexistence (onTap-only detector installs no long-press recognizer), blast-radius containment (the then-proposed retext key had one consumer; continuity tests + device harness genuinely spared), and the `card_test` Container-cast landmine handling. KIND-01 later tightened that copy design to a new scoped key so GIF is not changed.

Material blockers found by that review → resolved in that revision:
1. **TC-04 unreachable** — `body` is a single `Text` (`:513`); two `find.text` needed a secondary slot the plan never added. RESOLVED by option A (disappearing keeps its title; TC-04 rewritten; no secondary slot).
2. **TC-06 green-lit an a11y regression** — inner-button + outer-label = two Semantics nodes → tappable tile announces label-less "button". RESOLVED: co-locate button+label on one node (`group_conversation_screen.dart:979-988` pattern); TC-06 rewritten to `getSemantics` one node; reclassified HEAD-RED.
3. **Height 88→150 ungated** → RESOLVED (TC-08).
4. **`onOpen==null` inert-tile state** → RESOLVED (gate on `onOpen != null`; TC-09).
5. **ar/de compact copy unverified, no German render** → RESOLVED (TC-11 exact new-key/negative-lead-in + de case, with the legacy key held unchanged).
6. **No checkpoint between shared-widget and call-site slices** → RESOLVED (step-2 checkpoint).
7. Registration unenforced / no baseline count / updated tests never seen RED → that review accepted a grep/count/natural-RED repair. The current `$tdd-plan` audit refuted the fail-open grep, assertion-based count law, and post-production RED ordering; the canonical contract and gates above supersede them.

Findings DEEMED NON-BLOCKING / rejected on review: D3's `:852` off-by-one citation nit — the critic itself proved it wrong (assertion is at `:853`, inside the cited range); disregarded. Tap-feedback absence — downgraded to a light `AnimatedScale` (matches the approved mockup) rather than an `InkWell`/`Material` rework.

## Arbiter Decision (historical; superseded)
The earlier arbiter marked the plan ready after fixing the option-A and basic Semantics issues. The current source-grounded sufficiency audit supersedes that readiness finding because the kind boundary, state ownership, opening semantics, disabled fallback, positive wiring proof, group/view-once sentinels, canonical contract, and literal gates were not covered.

## Current TDD-Plan Sufficiency Finding

- Deterministic structural gaps are patched above: Graph snapshot, canonical 18-row contract, stateful press helper design, opening/duplicate/spinner semantics, disabled fallback, positive typed-launcher proof, protected+disappearing compact-copy coverage, view-once/group/shared sentinels, the full image/video-only new-selection predicate, assignment-funnel invariant, unchanged compatibility boundary, literal locale proofs, per-file gate ownership, valid commands, gate cadence, unified scope, and handoff.
- The source contradiction is explicit implementation work, not a remaining planning blocker: current composer paths expose private modes for GIF, while the accepted contract limits new direct private selection to images/videos. TC-18 supplies causal REDs for that correction and cheap ordinary/decode/iOS preservation sentinels. It deliberately does not claim a new domain-level authorization rule inside unchanged `sendChatMessage`.
- Group chats are excluded from production scope. Their single test/gate leg exists only because the modified shared card must remain render-compatible for its group caller.
- Verdict: `execution-ready`; implementation has not run.
