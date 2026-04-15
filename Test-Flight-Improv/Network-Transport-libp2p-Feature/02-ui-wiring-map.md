# UI Wiring Map — Widget Tree and Navigation

> **Scope:** The UI widget layer.
> **Includes:** All Wired widgets (key constructor deps, stream subscriptions, primary use cases/calls, child widgets constructed), navigation graph, shared state holders, stream subscription summary matrix.
> **Excludes:** Listener internals and lower-level service wiring (see `01`), Go protocols and bridge commands (see `00`), detailed screen styling, and dedicated timeout-policy analysis (see `03`).

---

## 1. Architecture Pattern

Most feature surfaces use a **Wired + Screen** split:
- **Wired** — coordinates state, subscriptions, and navigation; many are `StatefulWidget`s, with a few stateless pass-through wrappers
- **Screen** — presentation-first widget; may be `StatelessWidget` or `StatefulWidget` depending on local UI state

There are no `InheritedWidget`s, `Provider`s, or service locators. Dependencies are passed explicitly via constructors, threaded from `main.dart` into `MyApp`, then through `StartupRouter` and direct route builders into feature widgets.

Reactive UI binding uses `ValueListenableBuilder` (18 instances across 9 files). Wired widgets hold local `ValueNotifier`s and notifier-backed stores (e.g. `FeedStore`, `FeedReactionStore`, unread count notifiers). Shared controllers still exist, but they are passed explicitly rather than provided through an inherited reactive layer.

---

## 2. Shared State Holders

Three shared state-holder types / four app-wide instances are threaded explicitly (not inherited):

| Controller | Type | Key Consumers | Purpose |
|---|---|---|---|
| `AppShellController` | `ChangeNotifier` | `MyApp`, `FeedWired`, `OrbitWired`, `SettingsWired`, `PostsWired`, notification/open helpers | Tab switching; notification/post helpers switch tabs through it |
| `ActiveConversationTracker` (conversation instance) | Simple mutable state | `MyApp`, routes that can open `ConversationWired`, `ChatMessageListener`, notification display gate | Suppress notifications for the open 1:1 conversation |
| `ActiveConversationTracker` (group instance) | Simple mutable state | `MyApp`, routes that can open `GroupConversationWired`, `GroupMessageListener`, notification display gate | Suppress notifications for the open group conversation |
| `PendingPostTargetStore` | `ChangeNotifier` | `MyApp`, `StartupRouter`, `FeedWired`, `OrbitWired`, `PostsWired`, QR/onboarding/share routes | Deferred post-target routing from notifications |

`MyApp` also holds a static `navigatorKey` (`GlobalKey<NavigatorState>`) for imperative navigation from notification handlers.

---

## 3. Navigation Graph

```
main() builds MyApp
  |
  MaterialApp.home = StartupRouter
  |
  +-- needsIdentity -----------> IdentityChoiceWired
  |                                 |
  |                                 +-- onNavigateToMain --> FirstTimeExperienceWired
  |                                                            |
  |                                                            +-- contact accepted --> FeedWired
  |                                                            +-- QR button --> QRScannerWired
  |                                                                  +-- first contact --> FeedWired
  |
  +-- hasIdentityNoContacts ----> FirstTimeExperienceWired
  |
  +-- hasIdentityWithContacts --> (pending share intent?) --> ShareTargetPickerWired
  |                                                            +-- onClose --> FeedWired
  +-- hasIdentityWithContacts --> FeedWired
                                    |
                                    FeedWired (side-by-side panels, swipe animated)
                                    |
                                    +-- embedded --> OrbitWired
                                    |     +-- contact tap --> ConversationWired
                                    |     |     +-- intro button --> FriendPickerWired
                                    |     |     +-- confirmation --> SentConfirmationWired
                                    |     +-- QR button --> QRScannerWired
                                    |     +-- show QR --> QRDisplayWired
                                    |     +-- group tap --> GroupConversationWired
                                    |     |     +-- info --> GroupInfoWired
                                    |     |           +-- add members --> ContactPickerWired
                                    |     +-- new group --> CreateGroupPickerWired
                                    |           +-- success --> GroupConversationWired
                                    |
                                    +-- feed card tap --> ConversationWired
                                    +-- group card tap --> GroupConversationWired
                                    +-- avatar tap --> SettingsWired
```

### Notification-Triggered Navigation (from MyApp)

| Notification Target | UI Target / Action |
|---|---|
| `conversation` | ConversationWired |
| `group` | GroupConversationWired |
| `contactRequest` | ContactRequestDialog (if still pending) or ConversationWired (if already accepted) |
| `intros` | OrbitWired (with `initialFilterTab: 'intros'`) |
| `post` / `postComment` | Posts surface reveal via `PostNotificationOpenCoordinator` → sets `PendingPostTargetStore` target → switches `AppShellController` to feed tab (Posts tab hidden for TestFlight) → `popUntil(isFirst)` → reveals when the target post is observed |

**Deferred Routing**: If the navigator is not ready when a notification arrives, the route target is stored in `_deferredNotificationRouteTarget` and flushed on the next frame via `addPostFrameCallback`.

---

## 4. Wired Widget Catalogue

### FeedWired — Main App Shell

**File**: `lib/features/feed/presentation/screens/feed_wired.dart`

| Aspect | Detail |
|---|---|
| Mixin | `SingleTickerProviderStateMixin` (swipe animation) |
| Key deps | Broad shell DI surface: contacts, messages, groups, intros, media, and app-shell state |

**Streams subscribed**:
- `contactRequestListener.requestStream` -> shows ContactRequestDialog
- `chatMessageListener.incomingMessageStream` -> refreshes feed card
- `chatMessageListener.contactUpdatedStream` -> contact display refresh
- `(messageRepository as MessageRepositoryChangeSource).messageChanges` -> outgoing status updates (sent/delivered/failed)
- `reactionListener.incomingReactionChangeStream` -> inline reaction state
- `groupMessageListener.groupReactionChangeStream` -> group reaction state
- `groupMessageListener.groupMessageStream` -> group feed card refresh
- `groupInviteListener.groupJoinedStream` -> adds group to feed
- `groupInviteListener.pendingInviteStream` -> pending invite badge
- `introductionListener.introReceivedStream` -> orbit badge refresh
- `introductionListener.introStatusChangedStream` -> orbit badge refresh

**Primary use cases called**: `loadImageQualityPreference`, `loadVideoQualityPreference`, `loadFeed`, `loadContactFeedSnapshot`, `loadGroupFeedSnapshot`, `loadReactionsForConversation`, `expireOldIntroductions`, `markConversationRead`, `sendChatMessage`, `editChatMessage`, `deleteMessageForMe`, `deleteMessageForEveryone`, `sendReaction`, `removeReaction`, `sendGroupMessage`, `sendGroupReaction`, `removeGroupReaction`, `acceptAndReciprocateContactRequest`, `declineContactRequest`

**Constructs**: OrbitWired (embedded), ConversationWired, GroupConversationWired, SettingsWired

---

### OrbitWired — Contacts & Groups List

**File**: `lib/features/orbit/presentation/screens/orbit_wired.dart`

| Aspect | Detail |
|---|---|
| Mixin | `TickerProviderStateMixin` (collapse, search dock, search trigger animations) |
| Mode | Embedded inside FeedWired in the main shell; also pushed directly for intro-notification routing |

**Streams subscribed**:
- `chatMessageListener.incomingMessageStream`
- `chatMessageListener.contactUpdatedStream`
- `contactRequestListener.requestStream`
- `groupMessageListener.groupMessageStream`
- `groupInviteListener.groupJoinedStream`
- `groupInviteListener.pendingInviteStream`
- `introductionListener.introReceivedStream`
- `introductionListener.introStatusChangedStream`

**Primary use cases called**: `loadImageQualityPreference`, `loadVideoQualityPreference`, `loadOrbitData`, `loadOrbitGroups`, `loadOrbitFriendSnapshot`, `loadOrbitGroupSnapshot`, `loadIntroductionsForUser`, `expireOldIntroductions`, `markConversationRead`, `archiveContact`, `unarchiveContact`, `deleteContactAndMessages`, `blockContact`, `unblockContact`, `acceptIntroduction`, `passIntroduction`, `acceptPendingGroupInvite`, `declinePendingGroupInvite`, `archiveGroup`, `unarchiveGroup`, `deleteGroupAndMessages`, `acceptAndReciprocateContactRequest`, `declineContactRequest`

**Constructs**: ConversationWired, QRScannerWired, QRDisplayWired, GroupConversationWired, CreateGroupPickerWired

---

### ConversationWired — 1:1 Chat

**File**: `lib/features/conversation/presentation/screens/conversation_wired.dart`

| Aspect | Detail |
|---|---|
| Key deps | `contact`, `messageRepo`, `chatMessageListener`, `p2pService` |

**Streams subscribed**:
- `chatMessageListener.incomingMessageStream` (filtered by contact)
- `chatMessageListener.contactUpdatedStream` (filtered by contact)
- `reactionListener.incomingReactionChangeStream`
- `(messageRepo as MessageRepositoryChangeSource).messageChanges` (filtered by contact) -> outgoing status updates

**Primary use cases called**: `loadConversationPage`, `sendChatMessage`, `editChatMessage`, `sendVoiceMessage`, `uploadMedia`, `downloadMedia`, `sendReaction`, `removeReaction`, `deleteMessageForMe`, `deleteMessageForEveryone`, `markConversationRead`, `retryFailedMessage`, `blockContact`, `unblockContact`, `deleteContactAndMessages`, `loadReactionsForConversation`, `shouldShowIntroBanner`

**Constructs**: FriendPickerWired, SentConfirmationWired

---

### GroupConversationWired — Group Chat

**File**: `lib/features/groups/presentation/screens/group_conversation_wired.dart`

| Aspect | Detail |
|---|---|
| Key deps | `group`, `groupRepo`, `msgRepo`, `groupMessageListener`, `bridge` |

**Streams subscribed**:
- `groupMessageListener.groupMessageStream` (filtered by group)
- `groupMessageListener.groupReactionChangeStream`
- `groupMessageListener.groupRemovedStream`

**Primary use cases called**: `sendGroupMessage`, `sendGroupReaction`, `removeGroupReaction`, `uploadMedia`, `downloadMedia`, `retryFailedGroupMessage`, `loadReactionsForConversation`

**Constructs**: GroupInfoWired

---

### GroupInfoWired — Group Settings

**File**: `lib/features/groups/presentation/screens/group_info_wired.dart`

| Aspect | Detail |
|---|---|
| Key deps | `group`, `groupRepo`, `contactRepo`, `bridge`, `identityRepo`, `p2pService` |

No streams. **Primary use cases**: `leaveGroup`, `dissolveGroup`, `removeGroupMember`, `updateGroupMemberRole`, `rotateAndDistributeGroupKey`, `updateGroupMetadata`, `setGroupMuted`, `uploadMedia`

**Constructs**: ContactPickerWired

---

### CreateGroupPickerWired — New Group Flow

**File**: `lib/features/groups/presentation/screens/create_group_picker_wired.dart`

| Aspect | Detail |
|---|---|
| Key deps | `groupType`, `groupRepo`, `msgRepo`, `groupMessageListener`, `contactRepo`, `bridge`, `identityRepo`, `p2pService` |

No streams. **Primary use case**: `createGroupWithMembers`

**Constructs**: GroupConversationWired (pushReplacement on success)

---

### ContactPickerWired — Add Group Members

**File**: `lib/features/groups/presentation/screens/contact_picker_wired.dart`

| Aspect | Detail |
|---|---|
| Key deps | `groupId`, `groupRepo`, `contactRepo`, `bridge`, `identityRepo`, `p2pService` |

No streams. **Primary use cases**: `addGroupMember`, `sendGroupInvitesInParallel`

---

### QRScannerWired — Add Contact via QR

**File**: `lib/features/qr_code/presentation/screens/qr_scanner_wired.dart`

| Aspect | Detail |
|---|---|
| Type | StatelessWidget (coordinator, not stateful) |
| Key deps | `bridge`, `contactRepository`, `contactRequestRepository`, `identityRepository`, `p2pService` |

No streams. **Primary use cases**: `parseQRPayload`, `addContact`, `sendContactRequest`, `downloadProfilePicture`

**Constructs**: FeedWired (after first contact scan)

---

### QRDisplayWired — Show Own QR Code

**File**: `lib/features/qr_code/presentation/screens/qr_display_wired.dart`

| Aspect | Detail |
|---|---|
| Key deps | `repo` (identity), `bridgeClient` |

No streams. **Primary use case**: `buildQRPayload`

---

### FirstTimeExperienceWired — Onboarding

**File**: `lib/features/home/presentation/screens/first_time_experience_wired.dart`

| Aspect | Detail |
|---|---|
| Key deps | Broad onboarding DI surface: identity, contacts, QR, notifications, media, and feed handoff |

**Streams subscribed**: `contactRequestListener.requestStream` -> shows ContactRequestDialog

**Primary use cases**: `buildQRPayload`, `acceptAndReciprocateContactRequest`, `declineContactRequest`, `uploadProfilePicture`

**Constructs**: QRScannerWired, FeedWired (pushReplacement after first contact)

---

### SettingsWired

**File**: `lib/features/settings/presentation/screens/settings_wired.dart`

| Aspect | Detail |
|---|---|
| Key deps | `identityRepo`, `bridge`, `contactRepo`, `p2pService`, `secureKeyStore`, `imageProcessor` |

No streams. **Primary use cases**: `uploadProfilePicture`, `loadImageQualityPreference`, `saveImageQualityPreference`, `loadVideoQualityPreference`, `saveVideoQualityPreference`. Identity persistence is done via `identityRepo.saveIdentity()` directly (no use case wrapper).

---

### PostsWired — Posts Surface

**File**: `lib/features/posts/presentation/screens/posts_wired.dart`

| Aspect | Detail |
|---|---|
| Key deps | `identityRepo`, `contactRepo`, `postRepo`, `p2pService` |

**Streams subscribed**:
- `postRepository.postChanges` -> refreshes posts feed on change

**Primary use cases called**: `createLocalPost`, `prepareCreatedLocalPostMedia`, `createLocalPostComment`, `deliverCreatedLocalPostComment`, `createLocalPostPass`, `deliverCreatedLocalPostPass`, `sendPostReaction`, `sendPostCommentReaction`, `pinPost`, `removePin`, `dismissPin`, `editPinnedPost`, `loadPostsFeed`, `loadPinnedPosts`, `loadPostComments`, `sweepExpiredPosts`

**Constructs**: ConversationWired (from pinned-post author action), SettingsWired (on nearby location settings redirect)

**Note**: This widget is defined but not currently instantiated anywhere in the running app. Post creation uses local-create-then-deliver pattern (`createLocalPost` + delivery) rather than direct send functions.

---

### ShareTargetPickerWired — External Share

**File**: `lib/features/share/presentation/screens/share_target_picker_wired.dart`

| Aspect | Detail |
|---|---|
| Key deps | `shareIntent`, `contactRepository`, `messageRepository`, `bridge`, `p2pService` |

No streams. **Primary calls**: `loadImageQualityPreference`, `loadVideoQualityPreference`, `ShareBatchDeliveryCoordinator.deliver`

---

### IdentityChoiceWired — Identity Creation/Restore

**File**: `lib/features/identity/presentation/screens/identity_choice_wired.dart`

| Aspect | Detail |
|---|---|
| Key deps | `repository`, `callIdentityGenerate`, `callIdentityRestore`, `callMlKemKeygen` |

No streams. **Primary use case**: `generateNewIdentity`

**Constructs**: MnemonicInputWired (for restore flow)

---

### MnemonicInputWired — Restore Identity from Mnemonic

**File**: `lib/features/identity/presentation/screens/mnemonic_input_wired.dart`

| Aspect | Detail |
|---|---|
| Type | StatelessWidget |
| Key deps | `repository`, `callIdentityRestore`, `callMlKemKeygen` |

No streams. **Primary use case**: `restoreIdentityFromMnemonic`

Pushed from IdentityChoiceWired when user chooses the restore path.

---

### GroupListWired — Groups Tab

**File**: `lib/features/groups/presentation/screens/group_list_wired.dart`

| Aspect | Detail |
|---|---|
| Type | StatefulWidget |
| Key deps | `groupMessageListener`, `groupInviteListener`, `groupRepo`, `contactRepo`, `bridge` |

**Streams subscribed**:
- `groupMessageListener.groupMessageStream`
- `groupInviteListener.groupJoinedStream`
- `groupInviteListener.pendingInviteStream`

**Constructs**: GroupConversationWired (on group tap). Handles accept/decline of pending invites.

**Note**: This widget is defined but not currently instantiated anywhere in the running app.

---

### FriendPickerWired — Send Introduction

**File**: `lib/features/introduction/presentation/screens/friend_picker_wired.dart`

| Aspect | Detail |
|---|---|
| Key deps | `recipient`, `contactRepo`, `introRepo`, `p2pService`, `bridge`, `identityRepo` |

No streams. **Primary use case**: `sendIntroductions`

---

### SentConfirmationWired — Intro Confirmation

**File**: `lib/features/introduction/presentation/screens/sent_confirmation_wired.dart`

| Aspect | Detail |
|---|---|
| Type | `StatelessWidget` |
| Key deps | `introductionCount`, `introducedUsernames`, `onBackToConversation` |

No streams. No use cases. **Constructs**: `SentConfirmationScreen`

---

## 5. Stream Subscription Summary

Which Wired widgets subscribe to which listener streams:

| Listener Stream | FeedWired | OrbitWired | ConversationWired | GroupConversationWired | GroupListWired | PostsWired | FTE |
|---|---|---|---|---|---|---|---|
| chatMessageListener.incomingMessageStream | x | x | x (filtered) | | | | |
| chatMessageListener.contactUpdatedStream | x | x | x (filtered) | | | | |
| contactRequestListener.requestStream | x | x | | | | | x |
| reactionListener.incomingReactionChangeStream | x | | x | | | | |
| groupMessageListener.groupMessageStream | x | x | | x (filtered) | x | | |
| groupMessageListener.groupReactionChangeStream | x | | | x | | | |
| groupMessageListener.groupRemovedStream | | | | x | | | |
| groupInviteListener.groupJoinedStream | x | x | | | x | | |
| groupInviteListener.pendingInviteStream | x | x | | | x | | |
| introductionListener.introReceivedStream | x | x | | | | | |
| introductionListener.introStatusChangedStream | x | x | | | | | |
| messageRepo.messageChanges (outgoing status) | x | | x (filtered) | | | | |
| postRepository.postChanges | | | | | | x | |

FeedWired subscribes to the most streams (11, including repo `messageChanges`) because it's the main shell and must reflect all state changes. GroupListWired subscribes to 3 group-related streams independently of OrbitWired.
