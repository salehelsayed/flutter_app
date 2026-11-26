# Mknoon glossary

Look up the product term first, then follow the paths in **Where**. Update the row when its code moves. Add a row when you add a folder under `lib/features`.

## Messaging

| Term | Code names | Where | Means | Not to confuse with |
| --- | --- | --- | --- | --- |
| Home | `FeedWired`, `FirstTimeExperienceWired` | `lib/features/feed/presentation/screens/feed_wired.dart`, `lib/features/home/presentation/screens/first_time_experience_wired.dart` | Home opens the app shell on Orbit, or shows first-contact setup when there are no contacts. | Settings |
| Conversation | `ConversationWired` | `lib/features/conversation/presentation/screens/conversation_wired.dart` | The one-to-one chat screen wires the timeline and composer to the selected contact. | Group conversation |
| Send message | `sendChatMessage` | `lib/features/conversation/application/send_chat_message_use_case.dart` | The direct send use case authors or submits a chat message and records its outcome. | Send group message |
| Quoted reply | `ConversationMessage.quotedMessageId` | `lib/features/conversation/domain/models/conversation_message.dart` | A message can carry the ID of the earlier message it quotes. | Thought reply |
| Delivery receipt | `DeliveryReceiptListener`, `handleDeliveryReceipt` | `lib/features/conversation/application/delivery_receipt_listener.dart`, `lib/features/conversation/application/handle_delivery_receipt_use_case.dart` | A delivery receipt records that the receiving side got the message. | Read state |
| Share into Mknoon | `handleShareIntent` | `lib/features/share/application/handle_share_intent_use_case.dart`, `lib/features/share/presentation/screens/share_target_picker_wired.dart` | Content shared from another app enters the route that picks a recipient. | Forwarding an existing message |

## Thoughts

| Term | Code names | Where | Means | Not to confuse with |
| --- | --- | --- | --- | --- |
| Thoughts | `OrbitWired`, `ThoughtCardScreen` | `lib/features/orbit/presentation/screens/orbit_wired.dart`, `lib/features/posts/presentation/screens/thought_card_screen.dart` | Thoughts are audience-scoped posts. A note in flat Orbit opens its Thought card. In 3D Orbit, the card appears alongside its author. | Direct message |
| New Thought | `ComposePostSheet` | `lib/features/posts/presentation/widgets/compose_post_sheet.dart` | The sheet collects the content and audience for a new Thought. | Chat composer |
| Pick People | `ThoughtPeoplePickerSheet` | `lib/features/posts/presentation/widgets/thought_audience.dart`, `lib/features/posts/presentation/widgets/compose_post_sheet.dart` | The picker selects contacts for the Thought audience. | Group contact picker |
| Thought reply | `ThoughtReplyDock`, `sendThoughtReply` | `lib/features/posts/presentation/widgets/thought_reply_dock.dart`, `lib/features/posts/application/send_thought_reply_use_case.dart` | A text reply to a Thought goes into a direct conversation with its author. | Quoted reply |
| Thought sticker reply | `sendThoughtStickerReply` | `lib/features/posts/application/send_thought_sticker_reply_use_case.dart` | A sticker reply to a Thought uses the direct message path with the Thought context. | Sticker picker |
| Thought expiry | `PostModel.expiresAt` | `lib/features/posts/domain/models/post_model.dart` | The expiry time marks when a Thought stops being current. | Author retraction |
| Reply grace | `ThoughtReplyDraft.grace` | `lib/features/posts/domain/thought_reply_draft.dart`, `lib/features/posts/application/send_thought_reply_use_case.dart` | An eligible in-progress text reply has up to 60 seconds after Thought expiry to send. | Thought lifetime |
| Author retraction | `retractThought`, `handleIncomingPostRetract` | `lib/features/posts/application/retract_thought_use_case.dart`, `lib/features/posts/application/handle_incoming_post_retract_use_case.dart` | An authenticated retraction removes the matching retained incoming Thought from its recipient. | Expiry or hiding a Thought |

## Orbit/3D

| Term | Code names | Where | Means | Not to confuse with |
| --- | --- | --- | --- | --- |
| Orbit | `OrbitWired`, `OrbitScreen` | `lib/features/orbit/presentation/screens/orbit_wired.dart`, `lib/features/orbit/presentation/screens/orbit_screen.dart` | Orbit displays peer activity and opens the related conversations or Thoughts. | Feed pane |
| 3D view | `OrbitDepthSurface`, `MKNOON_ENABLE_ORBIT_DEPTH` | `lib/features/orbit/presentation/widgets/orbit_depth_surface.dart`, `lib/core/config/thoughts_feature_flags.dart` | The depth surface renders Orbit with the 3D interaction controlled by a build define. | Flat Orbit |
| Depth ring | `OrbitDepthLayer.inner`, `orbit-depth-ring` | `lib/features/orbit/domain/orbit_depth_geometry.dart`, `lib/features/orbit/presentation/widgets/orbit_depth_surface.dart` | The inner depth ring seats friends with a live Thought. | Flat surface |
| Flat Orbit | `OrbitDepthLayer.flat` | `lib/features/orbit/domain/orbit_depth_geometry.dart`, `lib/features/orbit/presentation/widgets/orbit_depth_surface.dart` | The flat Orbit surface stays mounted beneath the depth controls. | Depth ring |

## Calls

| Term | Code names | Where | Means | Not to confuse with |
| --- | --- | --- | --- | --- |
| Calls | `CallsPage` | `lib/features/call/presentation/screens/calls_page.dart` | The Calls screen shows call history and provides actions for its rows. | Active call screen |
| Call history | `CallHistoryRepository` | `lib/features/call/data/call_history_repository.dart` | The repository reads and writes local call records. | Live call state |
| Call outcome screens | `ForegroundCallOverlay`, `_buildTerminalNotice` | `lib/features/call/presentation/foreground_call_overlay.dart` | The terminal notice shows how the call ended and offers the applicable follow-up actions. | Call history |
| Return bar | `CallReturnBar` | `lib/features/call/presentation/widgets/call_return_bar.dart` | The in-app bar returns the user to the active call. | Android picture-in-picture |
| Minimize call | `ForegroundCallBackGuard`, `setAndroidCallOwnsBack` | `lib/features/call/presentation/foreground_call_back_guard.dart`, `lib/features/call/presentation/widgets/call_return_bar.dart` | Android Back minimizes a connected or outgoing call into the app while the call continues. | Picture-in-picture |
| Tried to call you chip | `call_suggestion_tried_to_call`, `_useCallMessageSuggestion` | `lib/features/conversation/presentation/screens/conversation_wired.dart`, `lib/l10n/app_en.arb` | The suggestion can fill an empty direct-message composer with call follow-up text. | Saved draft |
| Missed-call notification | `MissedCallNotifier` | `lib/features/call/application/missed_call_notifier.dart` | The notifier prepares the system notification for an eligible missed call. | Missed-call history row |
| Picture-in-picture | `CallPictureInPictureController`, `CallPictureInPictureHandler` | `lib/features/call/application/call_picture_in_picture.dart`, `android/app/src/main/kotlin/com/mknoon/app/call/CallPictureInPictureHandler.kt` | Android picture-in-picture shows a call in a system overlay window. | Return bar |

## Stickers

| Term | Code names | Where | Means | Not to confuse with |
| --- | --- | --- | --- | --- |
| Sticker picker | `StickerPanel` | `lib/features/stickers/presentation/sticker_panel.dart` | The sticker panel lets the user choose a sticker to send. | Pick People |
| Create sticker | `StickerCreateFlow` | `lib/features/stickers/custom/create/sticker_create_flow.dart`, `lib/features/stickers/custom/create/sticker_create_screens.dart` | The creation flow opens the source and editing screens for a custom sticker. | Sticker picker |
| Sticker cutout | `StickerCutout`, `StickerCutoutService` | `lib/features/stickers/application/sticker_cutout.dart`, `lib/features/stickers/application/method_channel_sticker_cutout_service.dart` | The cutout service creates a sticker image from a subject in the source image. | Cropping |
| Camera rotation | `VideoRotationAngleProvider`, `rotationAngleForVideoData` | `third_party/camera_avfoundation/darwin/camera_avfoundation/Sources/camera_avfoundation/CameraConfiguration.swift`, `third_party/camera_avfoundation/darwin/camera_avfoundation/Sources/camera_avfoundation/DefaultCamera.swift` | The iOS recorder rotates preview and saved video frames for the current camera. | Front camera mirroring |
| Saved custom sticker | `StickerCreateSaved` | `lib/features/stickers/custom/create/sticker_create_flow.dart` | The creation flow returns a saved result when a custom sticker is ready for the caller. | Sending a sticker |

## Translator

| Term | Code names | Where | Means | Not to confuse with |
| --- | --- | --- | --- | --- |
| Private translator | `translate_preview`, `PrivateTranslatorSheet` | `lib/features/translate_preview/private_translator_sheet.dart`, `lib/features/translate_preview/private_translator_settings_section.dart` | The sheet and Settings section present the translator model and its availability. | One translation result |
| Model delivery | `ModelDeliveryManifest`, `ModelDeliveryState` | `lib/features/translate_preview/model_delivery_core.dart`, `lib/features/translate_preview/model_delivery_contract.dart` | Model delivery manages the download, verification, and readiness of the on-device model. | Translate |
| Model adoption | `_startExistingModelVerification` | `lib/features/translate_preview/model_delivery_core.dart` | Verification can restore Ready for a model already stored on the device when its delivery record is missing. | A new model download |
| Model Ready | `ModelReady` | `lib/features/translate_preview/model_delivery_contract.dart` | Ready is the delivery state that makes the local model available to the app. | A finished translation |
| Translate | `OnDeviceAi.translate` | `lib/features/translate_preview/on_device_ai.dart` | Translate converts text into the requested language on the device. | Transcribe |
| Transcribe | `OnDeviceAi.transcribe` | `lib/features/translate_preview/on_device_ai.dart`, `lib/features/conversation/presentation/screens/conversation_screen.dart` | Transcribe turns a voice note into text that the conversation can display. | Translate |

## Groups

| Term | Code names | Where | Means | Not to confuse with |
| --- | --- | --- | --- | --- |
| Group conversation | `GroupConversationWired` | `lib/features/groups/presentation/screens/group_conversation_wired.dart` | This screen wires a group timeline and composer to group messaging. | One-to-one conversation |
| Group Info | `GroupInfoWired` | `lib/features/groups/presentation/screens/group_info_wired.dart` | Group Info presents the group's details, member actions, and leave controls. | Contact profile |
| Group invitation | `sendGroupInvite`, `PendingGroupInvite` | `lib/features/groups/application/send_group_invite_use_case.dart`, `lib/features/groups/domain/models/pending_group_invite.dart` | An invitation offers a contact membership in a specific group. | Contact request |
| Pending role sync | `GroupExitIntentRequestStatus.pendingRoleSync` | `lib/features/groups/presentation/screens/group_info_wired.dart` | The Group Info recovery sheet shows that role information is still needed for the leave action. | Queued leave |
| Queued leave | `GroupExitRecoverySheet.queuedLeave` | `lib/features/groups/presentation/screens/group_info_wired.dart` | The recovery sheet shows that a group leave is queued for later processing. | Pending role sync |

## Contacts/Identity

| Term | Code names | Where | Means | Not to confuse with |
| --- | --- | --- | --- | --- |
| Contact | `ContactModel`, `ContactRepository` | `lib/features/contacts/domain/models/contact_model.dart`, `lib/features/contacts/domain/repositories/contact_repository.dart` | A contact is the local record for a person the user has added. | Local identity |
| Contact request | `sendContactRequest` | `lib/features/contact_request/application/send_contact_request_use_case.dart`, `lib/features/contact_request/presentation/widgets/contact_request_dialog.dart` | A contact request asks another person to connect. | Group invitation |
| Contact profile | `ContactProfileScreen` | `lib/features/contact_profile/presentation/screens/contact_profile_screen.dart` | The profile screen shows the selected person's information and contact actions. | Settings |
| Scan a friend's code | `QRScannerScreen` | `lib/features/qr_code/presentation/screens/qr_scanner_screen.dart` | The scanner reads a QR payload and routes it to the supported connection or pairing flow. | Show my QR code |
| Introduction | `IntroductionModel`, `FriendPickerWired` | `lib/features/introduction/domain/models/introduction_model.dart`, `lib/features/introduction/presentation/screens/friend_picker_wired.dart` | An introduction connects two chosen contacts through the introducing person. | Direct contact request |
| Identity | `IdentityModel`, `IdentityChoiceWired` | `lib/features/identity/domain/models/identity_model.dart`, `lib/features/identity/presentation/screens/identity_choice_wired.dart` | An identity represents the account the app uses on the device. | Contact |
| Linked device | `LinkedDeviceSetupWired` | `lib/features/identity/presentation/screens/linked_device_setup_wired.dart`, `lib/features/qr_code/application/direct_linked_device_qr.dart` | Linking enrolls a device with the existing account. | Account transfer |
| Account transfer | `AccountMigrationTransferRequest`, `AccountMigrationTransferStep` | `lib/features/account_migration/application/account_migration_transfer_flow.dart`, `lib/features/account_migration/presentation/screens/account_migration_journey_wired.dart` | Account transfer coordinates moving the account's data between devices. | Linked-device setup |
| Settings | `SettingsWired` | `lib/features/settings/presentation/screens/settings_wired.dart`, `lib/features/settings/presentation/screens/settings_screen.dart` | Settings connects account and app preferences to controls the user can change. | Contact profile |

## Relay/Push

| Term | Code names | Where | Means | Not to confuse with |
| --- | --- | --- | --- | --- |
| Relay | `RelaySelector`, `RelayInfo` | `go-mknoon/node/relay_selector.go`, `go-mknoon/node/relay_session.go` | The relay code selects and manages intermediaries for peer connectivity. | Direct peer connection |
| Peer message | `ChatMessage` | `lib/features/p2p/domain/models/chat_message.dart`, `go-mknoon/bridge/bridge.go` | The transport message carries peer addressing, message type, and content. | Local timeline row |
| Wake token | `IssueWakeTokensUseCase`, `ReceivedWakeTokenStore` | `lib/features/push/application/issue_wake_tokens_use_case.dart`, `lib/features/push/domain/received_wake_token_store.dart` | A wake token lets a sender request a wake for a recipient device. | Provider registration token |
| Push notification | `FlutterNotificationService`, `notification_preview_copy` | `lib/core/notifications/flutter_notification_service.dart`, `lib/features/push/application/notification_preview_copy.dart` | The notification path prepares the visible copy and hands off to the operating system. | Inbox delivery |
| Inbox custody | `AckOrExpiryInboxStore` | `lib/core/services/inbox_store_outcome.dart` | The inbox store reports whether it accepted responsibility for holding a message until acknowledgment or expiry. | Delivery receipt |

## Updates

| Term | Code names | Where | Means | Not to confuse with |
| --- | --- | --- | --- | --- |
| Update check | `UpdateCheckService` | `lib/features/update_check/application/update_check_service.dart`, `lib/features/update_check/domain/update_check_policy.dart` | The service checks the installed build against the update policy. | Translator model delivery |
| Required update | `UpdateRequiredGate` | `lib/features/update_check/presentation/update_required_gate.dart` | The required-update gate blocks app entry when the installed build is below the required minimum. | Update available banner |
| Update available banner | `UpdateAvailableBanner` | `lib/features/update_check/presentation/update_available_banner.dart` | The banner offers an available update while the user can still use the app. | Required update |

## Process words

| Term | Code names | Where | Means | Not to confuse with |
| --- | --- | --- | --- | --- |
| Lane | Check ID | `tool/testing/selection.json` | A lane is a named check or suite with a defined runner and scope. | Scenario row |
| Row | Scenario or assertion ID | `tool/sims/critical_features.json`, `docs/testing/TESTING.md` | A row is one scenario or observation in a test matrix with its own expected outcome. | Whole lane |
| Packet | Execution brief | `docs/testing/TESTING.md` | A packet gives one test owner the source pin, setup, selected checks, and evidence to return. | Test result |
| RED/GREEN | First failure and passing result | `docs/testing/TESTING.md` | RED shows the intended assertion failing before the fix, and GREEN shows the same assertion passing afterward. | Setup failure |
| Native lease | `mknoon.shared-native-build` | `scripts/lease_status.py` | A native lease reserves the shared build and native test resources for one owner. | Device lease |
| DTR-18 | Layering relocation and placement closure contracts | `test/unit/dtr18_layering_relocation_contract_test.dart`, `test/unit/dtr18_placement_closure_contract_test.dart` | DTR-18 checks that the pinned app and bootstrap wiring stays with its reviewed owners. | Device proof |
| Composition | Candidate HEAD and tree | `docs/testing/TESTING.md`, `scripts/mknoon_checks.py` | A release composition combines reviewed source and verifies the resulting Git tree. | App dependency wiring |
| Baseline | `--base` | `scripts/mknoon_checks.py` | The baseline is the exact comparison revision used to select affected checks. | Candidate |
| Receipt | `results.json` and raw evidence | `scripts/mknoon_checks.py`, `docs/testing/TESTING.md` | A test receipt ties an outcome to the source, scope, and supporting evidence. | Execution packet |
| Ready (build or fix) | Readiness statement | `docs/testing/TESTING.md` | Ready means every planned check for that build or fix has finished and passed or has an owner-approved disposition. If any planned check is still pending, say "ready except <check>", with what it protects and how long it takes, and let the owner decide. Never move a planned check past a handover without the owner's OK. | Uploaded, published, or "not blocking" |

## Rename candidates

- Thoughts uses the older names `posts` and `PostModel`. Consider Thought names for this feature's models and screens.
- `PostsWired` has no production caller. Delete later?
- Private translator appears under `translate_preview`. Consider aligning the module folder with the product term.
- Orbit's 3D view also appears as depth in `OrbitDepthSurface` and `MKNOON_ENABLE_ORBIT_DEPTH`. Consider one name for the 3D feature after reviewing define compatibility.
- Account transfer appears as `account_migration` and `AccountMigrationTransferStep`. Consider matching the product's transfer wording in the flow names.
