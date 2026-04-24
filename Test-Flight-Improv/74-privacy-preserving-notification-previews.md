# 74 - Privacy-Preserving Notification Previews

## 1. Title and Type

- Title: Privacy-preserving notification previews
- Issue type: `feature-improvement`
- Output doc path: `Test-Flight-Improv/74-privacy-preserving-notification-previews.md`

## 2. Problem Statement

Users want incoming message notifications to be useful without weakening the app's end-to-end privacy expectations.

Today, 1:1 message notifications preserve privacy by showing generic copy such as `You have a new message`, but that gives the recipient less context. Group message notifications can show message-specific preview text, but the preview is sent to the relay as cleartext push metadata before the recipient device displays it.

This creates inconsistent user experience and an avoidable privacy gap: group recipients get useful previews, while relay-visible group push payloads can contain part of the message text.

## 3. Impact Analysis

- Affected users: users who receive 1:1 or group message notifications while the app is backgrounded, terminated, or otherwise relying on push delivery.
- Affected flows: 1:1 encrypted inbox fallback, group offline inbox push fanout, background local notification fallback, notification tap routing, and group-message notification copy.
- Severity: moderate privacy and UX issue. The message still remains encrypted in the stored inbox envelope, but current group push metadata can expose preview text to relay-side infrastructure and push providers.
- Frequency: every group message that is stored through the group inbox with non-empty push copy can carry cleartext preview metadata; 1:1 encrypted messages avoid that but lose useful preview text.
- User-visible cost: users see inconsistent notification behavior across 1:1 and group chats, and privacy-sensitive users cannot rely on group notification previews having the same privacy posture as encrypted message content.
- Upgrade impact: app-store rollouts create mixed sender/receiver versions. Legacy clients can continue producing legacy notification payload behavior until upgraded, while upgraded clients must not break notification visibility, tap routing, or message retrieval for users who have not updated yet.

## 4. Current State

- `lib/features/conversation/domain/models/message_payload.dart` builds v2 1:1 encrypted chat envelopes with cleartext `id`, `senderPeerId`, `senderUsername`, and an `encrypted` block. The decrypted inner payload contains `text`, but the relay cannot read it from the v2 envelope.
- `lib/features/conversation/application/send_chat_message_use_case.dart` sends the serialized 1:1 envelope to `p2pService.storeInInbox(...)` when active delivery falls back to the relay inbox.
- `lib/core/bridge/p2p_bridge_client.dart` sends 1:1 inbox store requests with `toPeerId` and `message`, but no separate preview fields.
- `go-relay-server/inbox.go` extracts push metadata from 1:1 `chat_message` envelopes. For v2 encrypted 1:1 messages, it can read `senderUsername` and `message_id`, but not the encrypted message text, so the body falls back to `pushNotificationBody`.
- `go-relay-server/inbox_test.go` covers the current encrypted 1:1 APNS behavior: a v2 chat envelope with `senderUsername` produces an alert title of `Alice` and the generic body constant.
- `lib/features/groups/application/send_group_message_use_case.dart` builds group push copy separately from the encrypted group offline replay envelope. It derives `pushTitle` from the group name and `pushBody` from sender plus text or media descriptor.
- `lib/features/groups/application/group_offline_replay_envelope.dart` encrypts the group offline replay payload into a `group_offline_replay` envelope with `ciphertext` and `nonce`, but also preserves optional `pushTitle` and `pushBody` fields in the retry/store wrapper.
- `lib/core/bridge/bridge_group_helpers.dart` forwards group inbox store requests with `groupId`, encrypted `message`, `recipientPeerIds`, and optional cleartext `pushTitle` / `pushBody`.
- `go-relay-server/inbox.go` accepts group inbox `pushTitle` and `pushBody`, fans them out through `SendGroupNotification`, and writes them into top-level notification, Android notification, APNS alert, and data fields.
- `go-relay-server/inbox_test.go` currently asserts group push messages include visible body text such as `Alice: hello` in the relay-built notification payload.
- `lib/features/push/application/background_push_notification_fallback.dart` resolves local fallback title/body from remote data keys such as `title`, `pushTitle`, `sender_username`, `body`, `pushBody`, `message`, and `text`, then falls back to `New Message` / `You have a new message`.
- `test/features/push/application/background_message_handler_test.dart` covers routable data-only pushes showing the generic fallback body when no specific title/body fields are present.
- `test/core/notifications/notification_route_contract_matrix_test.dart` covers route-target parsing for `new_message` and `group_message` push data and verifies the background fallback payload follows the same route contract.

## 5. Scope Clarification

- In scope: message notification previews for 1:1 chats and group chats where the recipient should see useful preview copy without relay-visible plaintext message content.
- In scope: privacy expectations for relay-facing and push-provider-facing message notification payloads.
- In scope: fallback behavior when a recipient device cannot produce a message-specific preview.
- In scope: preservation of notification tap routing and existing inbox-drain expectations for 1:1 and group messages.
- In scope: mixed-version behavior across old and new sender/receiver builds during staged app-store rollout.
- In scope: the cleartext metadata boundary for message pushes. Routing identifiers, message IDs, cryptographic lookup metadata, push timing, and ciphertext length may remain visible to relay or push infrastructure; plaintext message text, sender-authored media descriptors, sender display names/usernames used as preview copy, and group names used as preview copy must not be cleartext relay-visible or push-provider-visible preview data.
- In scope: notification-path logs, metrics, flow events, and telemetry that could otherwise reintroduce plaintext message content or preview-derived copy outside the recipient device.
- In scope: notification presentation continuity, including conversation/group notification stacking or threading behavior where the platform supports it.
- Non-goal: hiding traffic-analysis metadata that is already inherent to push delivery, such as the fact that a push happened, message timing, routing identifiers, or ciphertext size.
- Non-goal: changing contact request, introduction, group invite, group dissolve/system, post, or other non-message notification copy.
- Non-goal: changing in-app foreground local notifications that are generated after the app has already received and parsed message content.
- Non-goal: choosing the mobile platform mechanism, native target shape, key-sharing approach, or crypto implementation path.
- Non-goal: changing message encryption semantics, group membership rules, or relay inbox durability.
- Accepted ambiguity: the final product copy for fallback cases remains open, as long as it does not expose message content to relay-visible payload fields.
- Accepted ambiguity: media-only preview wording remains open, as long as it remains consistent with existing user-visible media notification descriptors.
- Accepted ambiguity: exact compatibility signaling, rollout cutoff policy, and legacy-client sunset timing remain open. The product requirement is that legacy users keep safe generic notifications where needed, upgraded users do not regress routing, and privacy limitations from legacy cleartext preview sends are explicitly measured rather than silently assumed away.
- Accepted ambiguity: the exact names, dashboards, counters, and alert thresholds for preview-degrade and legacy-cleartext exposure measurement remain open; the acceptance requirement is that the behavior is measurable without writing plaintext message content into metrics, logs, flow events, or telemetry labels.

## 6. Test Cases

### Happy Path

- 1:1 encrypted message preview: when Alice sends Bob an encrypted 1:1 text message and Bob receives a push notification, Bob sees a notification preview that includes useful message context, while relay-visible and push-provider-visible fields do not contain Alice's message text, preview display name, or other plaintext preview copy in cleartext.
- Group encrypted message preview: when Alice sends a group text message and Bob receives a group push notification, Bob sees the group name and useful sender/message context, while relay-visible and push-provider-visible fields do not contain the group message text, group name as preview copy, sender display name as preview copy, or other plaintext preview copy in cleartext.
- Media-only message preview: when an incoming 1:1 or group message contains media without text, the recipient sees a useful media descriptor, while relay-visible and push-provider-visible fields do not contain sender-authored message content or media descriptor preview copy in cleartext.
- Fallback preview: when the recipient device cannot produce a message-specific preview, the notification still appears with generic message copy and tap routing remains usable.

Required acceptance evidence:

- Unit evidence for deterministic notification body selection and privacy classification of relay-facing payload fields.
- Integration evidence that 1:1 and group push payloads preserve routing metadata without exposing message text in relay-visible notification/title/body/data fields.
- Simulator evidence that background or terminated notification delivery can show either a message-specific recipient-visible preview or the generic fallback without breaking notification tap routing.
- Privacy evidence that notification-path logs, metrics labels, flow events, and telemetry do not contain plaintext message content or plaintext preview-derived copy.
- Observability evidence that fallback/degrade outcomes are measurable by relevant delivery context without treating expected old-client fallback as an unexpected decrypt failure.
- Presentation evidence that notification stacking or threading remains stable for 1:1 conversations and groups after the payload shape changes.

### Privacy Boundary

- Allowed visible metadata: relay and push infrastructure may still observe routing identifiers, message IDs, cryptographic lookup metadata, push timing, and ciphertext length where those are required for delivery, deduplication, routing, or recipient-side preview rendering.
- Forbidden cleartext preview data: relay-visible and push-provider-visible message notification fields must not contain message text, sender display names/usernames used as preview copy, group names used as preview copy, or media descriptor preview copy.
- No plaintext reintroduction: logs, diagnostics, metrics labels, flow events, telemetry, and notification delivery traces must not reintroduce plaintext message content or plaintext preview-derived copy after the push payload itself is made private.
- Legacy exposure accounting: when a legacy sender still provides cleartext preview metadata during rollout, the exposure is counted as legacy behavior without copying the plaintext value into metrics, logs, or telemetry labels.

### Edge Cases

- Missing key or stale key: when the recipient cannot decrypt enough notification-time content to produce a preview, the notification falls back to generic copy and does not expose plaintext message content.
- Duplicate push delivery: repeated delivery of the same message notification does not show duplicate local notifications or duplicate previews for the same message.
- Muted group: a muted group does not start showing preview notifications just because the payload shape changes.
- Active conversation: when the recipient is already viewing the relevant conversation, the existing suppression behavior remains user-visible and the user is not shown an unnecessary duplicate notification.
- Long text: notification preview content is bounded to a user-readable preview and does not expose more message content than the product intends.
- Unknown or malformed message payload: the user sees either no notification or a generic fallback; no malformed payload exposes plaintext message content through relay-visible fields.

### Mixed-Version Compatibility

- Old sender to old receiver: existing notification visibility, tap routing, and message retrieval continue to work; the change does not create dead notifications for users who have not updated.
- Old sender to new receiver: the upgraded recipient still receives a usable notification and can open the correct message context. If the legacy sender emitted cleartext preview metadata, the test record must treat that exposure as legacy behavior that cannot be retroactively made private for that send.
- New sender to old receiver: the legacy recipient still receives at least a generic visible notification, can tap into the correct message context where supported by the old build, and can retrieve/decrypt the message in-app.
- New sender to new receiver: recipient-visible preview behavior meets the privacy requirement for both 1:1 and group messages, with no plaintext message content in relay-visible push preview fields.
- Dual-format transition: if a transitional payload contains both legacy preview metadata and privacy-preserving encrypted preview data, the recipient sees at most one notification, tap routing remains correct, and upgraded clients prefer the privacy-preserving recipient-side preview behavior where available.
- Staged rollout: partial adoption across iOS and Android does not cause silent message-notification loss, broken tap routing, or unrecoverable inbox messages for users on either side of the rollout.

### Regressions To Preserve

- Preservation/regression: 1:1 encrypted messages continue to route to the correct conversation when the user taps the notification.
- Preservation/regression: group message notifications continue to route to the correct group and trigger the correct group-inbox preparation path when opened.
- Preservation/regression: contact requests, introductions, group invites, group dissolve/system notifications, and post notifications keep their existing non-message routing and visible copy behavior.
- Preservation/regression: foreground local notifications created after normal message ingestion can still use already-decrypted local message content, subject to existing active-conversation suppression rules.
- Preservation/regression: group inbox fanout still excludes the sender and avoids duplicate notification sends to repeated recipients.
- Preservation/regression: relay-stored encrypted message envelopes remain retrievable by the recipient after notification delivery.
- Preservation/regression: old client versions that still receive message pushes continue to get a visible fallback notification rather than losing message awareness.
- Preservation/regression: notification stacking or threading remains stable for the same 1:1 conversation or group, so privacy changes do not scatter related notifications into unrelated OS notification groups.

Current partial coverage:

- `go-relay-server/inbox_test.go` partially covers current 1:1 encrypted fallback copy and current group cleartext push copy.
- `test/features/push/application/background_message_handler_test.dart` partially covers generic local fallback display and duplicate suppression for background data pushes.
- `test/core/notifications/notification_route_contract_matrix_test.dart` partially covers route-target parsing and preparation expectations for `new_message` and `group_message`.

Known coverage gaps:

- No current test proves that a recipient-visible message preview can be shown while relay-visible push payload fields omit plaintext message content.
- No current simulator-level evidence covers recipient-visible decrypted previews across background or terminated app states.
- No current regression case proves group message previews avoid plaintext `pushBody` exposure while preserving group notification routing.
- No current mixed-build matrix proves old/new sender and receiver combinations preserve notification visibility, routing, retrieval, and relay-visible plaintext expectations during rollout.
- No current test defines the allowed versus forbidden relay-visible metadata boundary for sender display names, group names, media descriptors, routing identifiers, timing, and ciphertext length.
- No current test proves notification-path logs, metrics, flow events, and telemetry avoid plaintext message content or plaintext preview-derived copy.
- No current acceptance case proves fallback/degrade outcomes and legacy cleartext preview exposure are measurable without storing plaintext in observability data.
- No current test covers dual-format transitional payloads that include both legacy preview metadata and privacy-preserving encrypted preview data.
- No current regression case proves conversation/group notification stacking or threading remains stable after message push payloads change.
- No current explicit regression case covers group dissolve/system notification copy as a non-message exception.
