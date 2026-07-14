# Plan 247 — Announcement Media “Message Sender” Decision

Status: accepted
Decision date: 2026-07-11
Applies to: Plan 247 — Announcement Media Private Reply Routing
Boundary: local Flutter navigation only; no send, upload, payload, persistence, Bridge, Go, relay, or native contract

## Accepted Product And Privacy Contract

| Decision | Accepted Wave-1 answer |
|---|---|
| D-247-01 — label and expectation | The action is **Message sender**. It is not called Reply or Reply privately and does not imply a same-thread, quoted, forwarded, or copied relationship. The exact action labels are English `Message sender`, German `Absender anschreiben`, and Arabic `مراسلة المرسل`. |
| D-247-02 — sender eligibility | Only the current existing `ContactModel` for the reloaded `senderPeerId` qualifies. The contact must have `isArchived == false` and `isBlocked == false`; the sender must not be the current identity; the reloaded source must still be an incoming announcement-media message; and a complete app-owner opener must be available. The action never auto-adds a contact, starts an introduction or contact request, unarchives, or unblocks. |
| D-247-03 — context crossing | Open the existing fully wired 1:1 conversation with its default blank composer. No `initialText`, caption, media, attachment id/path/bytes, quote id, group id/title, source label, sender display metadata, key/nonce, or hidden diagnostic seed crosses into the direct draft or payload. The local typed request contains only `sourceMessageId` and `senderPeerId` for stale-state qualification and has no JSON, wire, Bridge, or persistence representation. |
| D-247-04 — exceptional states | Fail closed for a self-authored/outgoing source; a missing, changed, deleted, or locally tombstoned source; a non-announcement, missing, dissolved, deleted, left, or otherwise unavailable group or membership; a missing visual-media relationship; an unknown, archived, or blocked contact; a missing opener; or opener/route failure. Ineligible state before render hides the action. State that becomes stale after the menu opens dismisses the transient surface, opens no route, and shows privacy-minimized unavailable feedback. A route/open exception shows the separate open-failure feedback. |

## Exact Localized Copy

| Meaning | English | German | Arabic |
|---|---|---|---|
| Action | `Message sender` | `Absender anschreiben` | `مراسلة المرسل` |
| State became unavailable | `Message sender is unavailable.` | `Der Absender kann nicht angeschrieben werden.` | `مراسلة المرسل غير متاحة.` |
| Eligible route failed to open | `Couldn’t open the conversation.` | `Die Unterhaltung konnte nicht geöffnet werden.` | `تعذّر فتح المحادثة.` |

The unavailable copy deliberately does not disclose whether the source, membership, contact, block state, or opener changed. The open-failure copy is used only after eligibility succeeded and the app-owner route failed. Later implementation may select localization keys, but it must preserve these user-visible meanings and keep English, German, and Arabic semantically aligned.

## Exact Eligibility Matrix

The action is eligible only when every row below is true both when capability is built and when the user invokes it:

| Required fact | Accepted qualification |
|---|---|
| Source group | The reloaded group exists, is `GroupType.announcement`, is not dissolved/deleted/unavailable, and the local user still has current membership. |
| Source message | The reloaded row exists under that group, still has the requested id and sender, is incoming, is not locally deleted/tombstoned, and is not a system/text-only row. |
| Media relationship | The source has a current visual image/video attachment relationship under `MediaOwnerLane.group`. Same-id attachment rows in another owner lane do not qualify. Existing protection, expiry, availability, and shared-viewer capability checks remain fail closed and are not weakened. |
| Sender | `senderPeerId` is non-empty and differs from the reloaded current identity. |
| Contact | `ContactRepository.getContact(senderPeerId)` returns the current existing contact with `isArchived == false` and `isBlocked == false`. |
| Route owner | A complete injected app-owner opener is available. A surface with incomplete direct-message dependencies must keep the opener null and the action absent. |

Any false, missing, malformed, or contradictory fact denies the action. Unknown data never defaults to eligibility.

## Invocation And Revalidation Contract

1. The bubble or viewer creates a local request containing only `sourceMessageId` and `senderPeerId` for the item the user actually selected.
2. Invocation is coalesced so repeated taps cannot open multiple routes.
3. Immediately before navigation, the coordinator re-loads current identity, group, local membership, message, local-deletion authority, group-owned visual media relationship, contact, and opener availability.
4. The transient menu/viewer action surface is dismissed before navigation or feedback.
5. If any fact changed, no route opens and the localized unavailable feedback is shown.
6. If every fact still qualifies, the injected app-owner opener opens the existing direct conversation with a blank composer. If that route throws or reports failure, the localized open-failure feedback is shown.

Returning to the announcement reconstructs eligibility from current repositories. Plan 247 adds no durable draft or cached authorization decision.

## No-Cross-Lane And No-Auto-Send Boundary

- Choosing **Message sender** is terminal navigation. It must not invoke `sendChatMessage`, `sendGroupMessage`, upload, Forward, `group:publish`, `group:inboxStore`, a Bridge/P2P command, or any payload encoder.
- It writes no direct message, group message, quote relationship, forwarded marker, source id, group context, attachment, file, or encryption material.
- Source download state is not copied into the direct route and is not a reason to transfer media. Existing lifecycle/protection restrictions remain authoritative.
- Unknown, archived, or blocked senders remain ineligible; this feature does not silently broaden contact authority.
- Announcement reader publishing stays read-only and reaction behavior stays unchanged.

## Change Control

This artifact is the accepted product/privacy authority for Plan 247 Sessions 02–04. A later change that introduces copied context, unknown-sender introduction, automatic delivery, serialized provenance, or relaxed lifecycle/protection checks requires a new explicit decision and a revised TDD contract; it is not an implementation detail.
