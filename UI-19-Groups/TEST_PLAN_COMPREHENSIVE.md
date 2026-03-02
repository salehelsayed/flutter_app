# Comprehensive Test Plan: Group Member Invite Feature

## Table of Contents
1. [Existing Coverage Summary](#1-existing-coverage-summary)
2. [Missing Unit Tests](#2-missing-unit-tests)
3. [Missing Integration Tests](#3-missing-integration-tests)
4. [Missing Widget Tests](#4-missing-widget-tests)
5. [Go Backend Test Gaps](#5-go-backend-test-gaps)
6. [Smoke Test Procedures](#6-smoke-test-procedures)
7. [Regression Checklist](#7-regression-checklist)
8. [Priority Order](#8-priority-order)

---

## 1. Existing Coverage Summary

### What IS Already Tested

#### Models (Fully Covered)
| File | Tests | Status |
|------|-------|--------|
| `group_invite_payload_test.dart` | 14 tests | toInnerJson, fromInnerJson, toJson, fromJson, buildEncryptedEnvelope, parseEncryptedEnvelope, missing field nulls |
| `group_model_test.dart` | Exists | fromMap/toMap, copyWith, enums |
| `group_member_test.dart` | Exists | fromMap/toMap, equality |
| `group_key_info_test.dart` | Exists | fromMap/toMap, equality |
| `group_message_test.dart` | Exists | fromMap/toMap |
| `group_message_payload_test.dart` | Exists | toJson/fromJson |

#### Use Cases (Well Covered)
| File | Tests | Status |
|------|-------|--------|
| `add_group_member_use_case_test.dart` | 3 tests | admin adds, non-admin rejected, member saved |
| `send_group_invite_use_case_test.dart` | 7 tests | happy path, null ML-KEM, node not running, encrypt fail, send fail, inbox fallback, config in payload |
| `handle_incoming_group_invite_use_case_test.dart` | 11 tests | v1 parse, v2 decrypt, persists group/members/key, bridge:join, duplicate, invalid payloads (3), unknown sender, myRole=member, bridge timeout, decrypt failure |
| `group_invite_listener_test.dart` | 8 tests | v2 invite broadcast, unknown sender, duplicate group, decrypt failure, double start, stop, dispose, blocked contact |
| `send_group_message_use_case_test.dart` | Exists | |
| `handle_incoming_group_message_use_case_test.dart` | Exists | |
| `leave_group_use_case_test.dart` | 3 tests | leaves, cleans up all data, calls bridge |
| `remove_group_member_use_case_test.dart` | 3 tests | removes, rotates key, calls bridge |
| `group_message_listener_test.dart` | 5 tests | valid message, unknown group, stream emit, dispose, malformed data |

#### Bridge Helpers (Well Covered)
| File | Tests | Status |
|------|-------|--------|
| `bridge_group_helpers_test.dart` | 33+ tests | callGroupCreate (8), callGroupKeygen (2), callGroupPublish (3), callGroupEncrypt (2), callGroupDecrypt (2), callGroupJoin (3), callGroupJoinWithConfig (3), callGroupLeave (3), callGroupUpdateConfig (2), callGroupRotateKey (2), callGroupInboxStore (2), callGroupInboxRetrieve (4) |

#### Presentation (Partially Covered)
| File | Tests | Status |
|------|-------|--------|
| `contact_picker_screen_test.dart` | Exists | Pure screen tests |
| `contact_picker_wired_test.dart` | 7 tests | filter existing members, exclude self, confirmation dialog, cancel, confirm+pop, error snackbar, back button |
| `group_info_screen_test.dart` | 6 tests | shows members, roles, leave button, add member button admin/non-admin, callback |
| `group_list_screen_test.dart` | Exists | Pure screen tests |
| `group_conversation_screen_test.dart` | Exists | Pure screen tests |
| `create_group_screen_test.dart` | Exists | Pure screen tests |

#### Router (Covered)
| File | Tests | Status |
|------|-------|--------|
| `incoming_message_router_test.dart` | 10 tests | Routes contact_request, chat_message, group_invite (v1 and v2), message_reaction, delivery_receipt, unknown, unparseable, outgoing ignored, multiple messages |

#### Go Backend (Well Covered)
| File | Tests | Status |
|------|-------|--------|
| `pubsub_test.go` | 47+ tests | Validator (valid, invalid JSON, unknown group, unauthorized, announcement non-admin, bad sig, not-v3, empty members, wrong key epoch), findMember, isAllowedWriter, filterDiscoveredPeers, config serialization, key serialization, member serialization, encrypt/decrypt round-trip, UpdateGroupConfig (replaces atomically, non-existent), JoinGroupTopic (multi-member, validator accepts all, fails without pubsub, rejects double join), invite lifecycle (admin adds new member validator accepts, announcement new writer cannot publish), GetGroupKeyInfo, LeaveGroupTopic cancels discovery, StopNode cancels all discovery |

### What is NOT Tested (Gaps Identified)

1. **`addGroupMember` use case**: Missing test for group-not-found error path
2. **`sendGroupInvite` use case**: Missing test for encryption exception (throw, not ok=false)
3. **`handleIncomingGroupInvite` use case**: Missing tests for v2 with null ownMlKemSecretKey, empty members list in config, missing groupConfig subfields (name, createdBy), various GroupType parsing edge cases
4. **`GroupInviteListener`**: No test for bridgeError result (group persisted but bridge join failed)
5. **`ContactPickerWired`**: Missing tests verifying `callGroupUpdateConfig` is called with full config, verifying `sendGroupInvite` is called with correct parameters, verifying behavior when keyInfo is null
6. **`GroupInfoWired`**: No wired widget tests at all (only pure screen tests)
7. **`GroupListWired`**: No wired widget tests at all (only pure screen tests)
8. **`GroupConversationWired`**: No wired widget tests at all (only pure screen tests)
9. **`callGroupUpdateConfig`**: Missing test for malformed config (empty members list)
10. **Go backend**: Missing test for `UpdateGroupConfig` with concurrent reads (race test), missing test for `GroupUpdateConfig` bridge function parsing

---

## 2. Missing Unit Tests

### 2.1 `addGroupMember` — Missing Error Paths
**File:** `test/features/groups/application/add_group_member_use_case_test.dart`

| Test Name | Setup | Action | Expected Result |
|-----------|-------|--------|-----------------|
| `throws StateError when group does not exist` | groupRepo has no group with ID 'nonexistent' | Call addGroupMember with groupId='nonexistent' | Throws `StateError('Group not found: nonexistent')` |
| `does not save member when group not found` | groupRepo empty | Call addGroupMember, catch error | groupRepo.getMember returns null |
| `saves member with all fields (publicKey, mlKemPublicKey)` | adminGroup in repo | Add member with publicKey and mlKemPublicKey | Saved member has both keys preserved |

### 2.2 `sendGroupInvite` — Missing Exception Paths
**File:** `test/features/groups/application/send_group_invite_use_case_test.dart`

| Test Name | Setup | Action | Expected Result |
|-----------|-------|--------|-----------------|
| `returns sendFailed when bridge.send throws during encryption` | Bridge that throws Exception on message.encrypt | sendGroupInvite | Returns `SendGroupInviteResult.sendFailed` |
| `returns sendFailed when p2pService.sendMessage throws` | p2pService.sendMessage throws, storeInInbox also fails | sendGroupInvite | Returns `SendGroupInviteResult.sendFailed` |
| `returns success via inbox when direct send throws exception` | p2pService.sendMessage throws, storeInInbox returns true | sendGroupInvite | Returns `SendGroupInviteResult.success` |
| `payload includes senderPeerId and senderUsername` | Standard setup | sendGroupInvite, inspect inner payload | Inner JSON has correct senderPeerId and senderUsername |

### 2.3 `handleIncomingGroupInvite` — Missing Edge Cases
**File:** `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`

| Test Name | Setup | Action | Expected Result |
|-----------|-------|--------|-----------------|
| `returns decryptionFailed when v2 envelope and ownMlKemSecretKey is null` | v2 message, no secretKey | handleIncomingGroupInvite with ownMlKemSecretKey=null | Returns `(HandleGroupInviteResult.decryptionFailed, null)` |
| `persists group even when bridge general error (non-timeout)` | Bridge throws generic Exception on group:join | handleIncomingGroupInvite | Returns `(HandleGroupInviteResult.bridgeError, groupId)`, group is in repo |
| `handles empty members list in groupConfig gracefully` | Invite with groupConfig.members=[] | handleIncomingGroupInvite | Returns success, group persisted, getMembers returns empty list |
| `uses default name "Unnamed Group" when config has no name field` | Invite with groupConfig missing 'name' | handleIncomingGroupInvite | Group persisted with name='Unnamed Group' |
| `uses default GroupType.chat when config has unknown groupType` | Invite with groupType='unknown_value' | handleIncomingGroupInvite | Group persisted with type=GroupType.chat |
| `uses senderPeerId as createdBy when config has no createdBy` | Invite with groupConfig missing 'createdBy' | handleIncomingGroupInvite | Group persisted with createdBy = senderPeerId |
| `uses current time when config has invalid createdAt` | Invite with createdAt='not-a-date' | handleIncomingGroupInvite | Group persisted with createdAt close to now |
| `returns invalidPayload for completely malformed JSON` | ChatMessage with content='not json at all' | handleIncomingGroupInvite | Returns `(HandleGroupInviteResult.invalidPayload, null)` |
| `returns invalidPayload for valid JSON but wrong structure` | Content is `{"foo":"bar"}` | handleIncomingGroupInvite | Returns invalidPayload |
| `handles member with missing optional fields (publicKey, mlKemPublicKey)` | Members array has entries without publicKey | handleIncomingGroupInvite | Members persisted, nullable fields are null |
| `handles member with empty peerId` | Member entry has peerId='' | handleIncomingGroupInvite | Member persisted with empty peerId (no crash) |

### 2.4 `GroupInviteListener` — Missing Result Handling
**File:** `test/features/groups/application/group_invite_listener_test.dart`

| Test Name | Setup | Action | Expected Result |
|-----------|-------|--------|-----------------|
| `does not broadcast for bridgeError result (group persisted but bridge failed)` | Bridge that throws generic Exception on group:join | Inject v1 invite | groups list is empty (no broadcast), but group IS persisted in repo |
| `handles multiple invites to different groups in sequence` | Two sequential invites with different groupIds | Inject both | Both groups persisted, both broadcast |
| `handles rapid sequential invites without race conditions` | Send 3 invites rapidly | Inject all quickly | All 3 groups persisted |
| `does not process invite when getOwnMlKemSecretKey returns null (v2)` | getOwnMlKemSecretKey returns null | Inject v2 invite | No group created, no crash |

### 2.5 `GroupMessageListener` — Missing Edge Cases
**File:** `test/features/groups/application/group_message_listener_test.dart`

| Test Name | Setup | Action | Expected Result |
|-----------|-------|--------|-----------------|
| `calling start twice does not create duplicate subscriptions` | listener.start() called twice | Inject one message | Only one message processed (count=1) |
| `handles message with invalid timestamp gracefully` | Message with timestamp='not-a-date' | Inject | Message saved with current time fallback |
| `accepts message from non-member sender (stale member list)` | Group exists, sender not in members | Inject message | Message still saved (per current implementation) |

### 2.6 `removeGroupMember` — Missing Error Paths
**File:** `test/features/groups/application/remove_group_member_use_case_test.dart`

| Test Name | Setup | Action | Expected Result |
|-----------|-------|--------|-----------------|
| `throws StateError when group does not exist` | No group in repo | removeGroupMember | Throws `StateError('Group not found: ...')` |
| `throws StateError when caller is not admin` | Group with myRole=member in repo | removeGroupMember | Throws `StateError('Only admins can remove members')` |
| `throws when bridge rotateKey returns ok=false` | bridge.responses['group:rotateKey'] = {'ok': false, 'errorMessage': 'fail'} | removeGroupMember | Throws Exception with 'fail' message |

### 2.7 `leaveGroup` — Missing Error Paths
**File:** `test/features/groups/application/leave_group_use_case_test.dart`

| Test Name | Setup | Action | Expected Result |
|-----------|-------|--------|-----------------|
| `rethrows when bridge group:leave throws` | Bridge with throwOnSend=true | leaveGroup | Throws Exception |
| `leaves group even if group has no members or keys` | Group in repo but no members/keys | leaveGroup | Group deleted, no crash |

### 2.8 `GroupInvitePayload` — Missing Model Edge Cases
**File:** `test/features/groups/domain/models/group_invite_payload_test.dart`

| Test Name | Setup | Action | Expected Result |
|-----------|-------|--------|-----------------|
| `fromJson returns null when payload is null` | JSON with `"payload": null` | fromJson | Returns null |
| `fromInnerJson returns null when keyEpoch is wrong type (string)` | Inner JSON with `"keyEpoch": "1"` (string not int) | fromInnerJson | Returns null |
| `fromJson returns null for empty string input` | Empty string "" | fromJson | Returns null |
| `buildEncryptedEnvelope includes senderPeerId at top level` | Valid params | buildEncryptedEnvelope | JSON has senderPeerId outside encrypted block |

---

## 3. Missing Integration Tests

### 3.1 Full Invite Flow: Admin Invites -> Member Receives -> Member Sends Message
**File:** `test/features/groups/integration/invite_flow_integration_test.dart` (NEW)

```
Setup:
  - InMemoryGroupRepository for admin and member
  - InMemoryGroupMessageRepository
  - FakeContactRepository with reciprocal contacts
  - PassthroughCryptoBridge
  - FakeP2PService
  - Admin has group with admin role, key in repo

Test: 'full invite flow: admin invites, member receives and can send messages'
  1. Admin calls addGroupMember (saves member to admin's repo)
  2. Admin calls callGroupUpdateConfig (updates bridge config)
  3. Admin calls sendGroupInvite (encrypts and sends)
  4. Capture the sent message content
  5. Feed that content to handleIncomingGroupInvite as the member
  6. Verify member's repo now has: group, members, key
  7. Verify group:join was called on member's bridge
  8. Member calls sendGroupMessage
  9. Verify message is saved in member's repo
  Expected: All steps succeed, full round-trip works
```

### 3.2 Invite + Remove Member Cycle
**File:** `test/features/groups/integration/invite_remove_cycle_test.dart` (NEW)

```
Test: 'invite member then remove them, verify cleanup'
  1. Admin invites member (full flow above)
  2. Admin calls removeGroupMember
  3. Verify member removed from admin's repo
  4. Verify key was rotated (new generation > old)
  5. Verify admin's bridge received group:rotateKey command
```

### 3.3 Multiple Invites to Same Group
**File:** `test/features/groups/integration/multiple_invites_test.dart` (NEW)

```
Test: 'admin invites multiple members to same group sequentially'
  1. Admin invites Alice
  2. Admin invites Bob
  3. Verify group has 3 members (admin + Alice + Bob)
  4. Verify callGroupUpdateConfig was called twice
  5. Verify each sendGroupInvite included the growing members list

Test: 'inviting already-existing member results in noop or update'
  1. Admin invites Alice
  2. Admin invites Alice again
  3. Verify no duplicate members in repo
```

### 3.4 Invite While Group Messages Are Flowing
**File:** `test/features/groups/integration/invite_during_messaging_test.dart` (NEW)

```
Test: 'new member invite does not disrupt active group messaging'
  1. Start GroupMessageListener
  2. Send a group message
  3. While listener is active, admin invites new member
  4. Send another group message
  5. Verify both messages saved, listener still works
  6. Verify invite was processed correctly
```

### 3.5 DI Chain Integrity
**File:** `test/features/groups/integration/di_chain_test.dart` (NEW)

```
Test: 'ContactPickerWired compiles with all required dependencies'
  Assert: ContactPickerWired constructor accepts all required params

Test: 'GroupInfoWired compiles with all required dependencies'
  Assert: GroupInfoWired constructor accepts all required params

Test: 'GroupConversationWired compiles with all required dependencies'
  Assert: GroupConversationWired constructor accepts all required params

Test: 'GroupListWired compiles with all required dependencies'
  Assert: GroupListWired constructor accepts all required params
```

### 3.6 Bridge Command Format Verification
**File:** `test/core/bridge/bridge_group_helpers_integration_test.dart` (NEW)

```
Test: 'callGroupUpdateConfig sends full GroupConfig matching Go struct'
  1. Build groupConfig map with name, groupType, description, members (with all fields), createdBy, createdAt
  2. Call callGroupUpdateConfig
  3. Parse the JSON sent to bridge
  4. Verify payload.groupConfig has all fields matching Go's GroupConfig struct
  5. Verify each member has peerId, username, role, publicKey, mlKemPublicKey

Test: 'callGroupJoinWithConfig sends payload matching Go GroupJoinTopic params'
  1. Call callGroupJoinWithConfig with full params
  2. Parse the JSON sent to bridge
  3. Verify payload has groupId, groupConfig, groupKey, keyEpoch
  4. Verify groupConfig structure matches Go expectations
```

---

## 4. Missing Widget Tests

### 4.1 ContactPickerWired — Full Invite Flow Verification
**File:** `test/features/groups/presentation/contact_picker_wired_test.dart` (EXISTING, add tests)

| Test Name | Setup | Action | Expected Result |
|-----------|-------|--------|-----------------|
| `confirming invite calls callGroupUpdateConfig with full config` | Group with admin+bob members, Alice as contact, group has key | Tap Alice, confirm invite | Bridge received group:updateConfig command with groupConfig containing all 3 members (admin, bob, alice) |
| `confirming invite calls sendGroupInvite with correct params` | Same setup as above | Tap Alice, confirm invite | p2pService.sendMessage called with Alice's peerId, content is v2 group_invite envelope |
| `invite skips sendGroupInvite when no keyInfo exists` | Group with no key in repo | Tap Alice, confirm invite | Member added to repo, but p2pService.sendMessage NOT called |
| `invite does not crash when sendGroupInvite returns non-success` | p2pService returns false for sendMessage and storeInInbox | Tap Alice, confirm invite | Screen pops (member still added), flow event logged |
| `shows loading state during invite` | Standard setup | Tap Alice, confirm invite, check before async completes | isInviting=true renders ContactPickerScreen with isInviting=true |
| `confirming invite for contact without mlKemPublicKey still adds member` | Contact Charlie with mlKemPublicKey=null, group has key | Tap Charlie, confirm invite | Member added to repo, sendGroupInvite returns encryptionRequired, screen still pops |

### 4.2 GroupInfoWired — Wired Widget Tests (NEW)
**File:** `test/features/groups/presentation/group_info_wired_test.dart` (NEW)

| Test Name | Setup | Action | Expected Result |
|-----------|-------|--------|-----------------|
| `loads and displays members on init` | GroupRepo with 2 members | Pump widget | Both member names visible |
| `Add Member button navigates to ContactPickerWired` | Admin group | Tap "Add Member" | ContactPickerWired screen appears |
| `refreshes member list when returning from ContactPickerWired with true` | Admin group, contact available | Navigate to picker, select contact, confirm | Member list refreshes with new member, "Member invited" snackbar shown |
| `does not refresh when returning from ContactPickerWired with false` | Admin group | Navigate to picker, tap back | Member list unchanged |
| `Leave Group calls leaveGroup and pops to root` | Member group | Tap "Leave Group" | leaveGroup use case called, navigator pops to first route |
| `Remove Member calls removeGroupMember and refreshes` | Admin group with 2 members | Tap remove on a member | Member removed from list |
| `does not show Add Member or Remove buttons for non-admin` | Group with myRole=member | Pump widget | No "Add Member" button, no remove icons |

### 4.3 GroupListWired — Wired Widget Tests (NEW)
**File:** `test/features/groups/presentation/group_list_wired_test.dart` (NEW)

| Test Name | Setup | Action | Expected Result |
|-----------|-------|--------|-----------------|
| `loads and displays groups on init` | GroupRepo with 2 groups | Pump widget | Both group names visible |
| `auto-refreshes when groupInviteListener emits a new group` | GroupInviteListener with StreamController | Add group to repo, emit to stream | Group list refreshes, new group appears |
| `auto-refreshes when groupMessageListener emits a message` | GroupMessageListener with StreamController | Emit message | Group list refreshes (latest message / unread count updated) |
| `navigates to GroupConversationWired on group tap` | Group in repo | Tap group card | GroupConversationWired screen appears |
| `navigates to CreateGroupWired on create button tap` | Standard setup | Tap create button | CreateGroupWired screen appears |
| `refreshes groups when returning from conversation` | Group in repo | Navigate to conversation, pop back | Groups reloaded |
| `displays unread counts` | Group with 3 unread messages | Pump widget | Badge shows "3" |
| `displays latest message preview` | Group with messages | Pump widget | Latest message text shown |

### 4.4 GroupConversationWired — Wired Widget Tests (NEW)
**File:** `test/features/groups/presentation/group_conversation_wired_test.dart` (NEW)

| Test Name | Setup | Action | Expected Result |
|-----------|-------|--------|-----------------|
| `loads and displays messages on init` | msgRepo with 3 messages | Pump widget | All 3 messages visible |
| `sending a message calls sendGroupMessage and refreshes` | Standard setup | Enter text, tap send | sendGroupMessage called, message appears in list |
| `listens for new messages and refreshes` | groupMessageListener stream | Emit message for this group | Message list refreshes |
| `ignores messages for other groups` | groupMessageListener stream | Emit message for different groupId | Message list unchanged |
| `marks messages as read on load` | Messages with readAt=null | Pump widget | markAsRead called |
| `Info button navigates to GroupInfoWired` | Standard setup | Tap info button | GroupInfoWired screen appears |
| `canWrite is false for non-admin in announcement group` | Announcement group, member role | Pump widget | Compose area disabled/hidden |
| `canWrite is true for admin in announcement group` | Announcement group, admin role | Pump widget | Compose area enabled |
| `canWrite is true for any role in chat group` | Chat group, member role | Pump widget | Compose area enabled |

---

## 5. Go Backend Test Gaps

### 5.1 `UpdateGroupConfig` — Concurrent Access Tests
**File:** `go-mknoon/node/pubsub_test.go` (EXISTING, add tests)

| Test Name | Description |
|-----------|-------------|
| `TestUpdateGroupConfig_ConcurrentReadWrite` | Use goroutines to simultaneously read config (via validator) and write config (via UpdateGroupConfig). Run with `-race` flag. Verify no data race detected. |
| `TestUpdateGroupConfig_ConcurrentMultipleUpdates` | Multiple goroutines calling UpdateGroupConfig for the same group simultaneously. Verify final config is one of the written configs (no corruption). |

### 5.2 `GroupJoinTopic` — Config Propagation to Validator
**File:** `go-mknoon/node/pubsub_test.go` (EXISTING, add tests)

| Test Name | Description |
|-----------|-------------|
| `TestJoinGroupTopic_ValidatorUsesLatestConfigAfterUpdate` | Join group with 2 members, update config to add 3rd member, verify validator accepts messages from all 3 members. (Note: `TestInviteLifecycle_AdminAddsNewMember_ValidatorAcceptsNewMember` already covers this - verify it passes.) |
| `TestJoinGroupTopic_EmptyConfig_ValidatorRejectsAll` | Join with config that has empty Members slice, verify all messages rejected. (Note: `TestGroupTopicValidator_EmptyMembersList_RejectsAll` exists but tests config update, not initial join.) |

### 5.3 `GroupUpdateConfig` Bridge Function
**File:** `go-mknoon/bridge/bridge_test.go` (if exists, or NEW)

| Test Name | Description |
|-----------|-------------|
| `TestGroupUpdateConfig_ParsesFullGroupConfigFromJSON` | Call `GroupUpdateConfig` with JSON containing full GroupConfig struct (name, groupType, description, members with all fields, createdBy, createdAt). Verify the config is stored correctly. |
| `TestGroupUpdateConfig_MissingGroupId_ReturnsError` | Call with empty groupId. Verify error response. |
| `TestGroupUpdateConfig_InvalidJSON_ReturnsError` | Call with malformed JSON. Verify error response. |
| `TestGroupUpdateConfig_NodeNotInitialized_ReturnsError` | Call before Initialize. Verify NOT_INITIALIZED error. |

### 5.4 `GroupJoinTopic` Bridge Function
**File:** `go-mknoon/bridge/bridge_test.go`

| Test Name | Description |
|-----------|-------------|
| `TestGroupJoinTopic_ParsesConfigKeyAndEpochFromJSON` | Call with full JSON (groupId, groupConfig, groupKey, keyEpoch). Verify JoinGroupTopic called with correct params. |
| `TestGroupJoinTopic_MissingGroupKey_ReturnsError` | Call without groupKey. Verify INVALID_INPUT error. |

### 5.5 Validator After Key Rotation
**File:** `go-mknoon/node/pubsub_test.go`

| Test Name | Description |
|-----------|-------------|
| `TestGroupTopicValidator_AcceptsAfterKeyRotation` | Join group, rotate key (UpdateGroupKey), build envelope with new key epoch, verify validator accepts. |
| `TestGroupTopicValidator_RejectsOldKeyEpochAfterRotation` | Join group, rotate key, build envelope with OLD key epoch, verify signature mismatch/reject. |

---

## 6. Smoke Test Procedures

### 6.1 Happy Path: Create Group -> Invite -> Accept -> Chat
**Devices:** Device A (Admin), Device B (Member)
**Prerequisite:** Both devices have identities created and are mutual contacts (QR code exchange completed).

```
Step 1: Create Group (Device A)
  - Tap Groups tab in navigation bar
  - Tap "+" / Create Group button
  - Enter name: "Test Group"
  - Select type: Chat
  - Tap Create
  VERIFY: Group appears in group list on Device A

Step 2: Invite Member (Device A)
  - Tap the group to open conversation
  - Tap info/header to go to Group Info
  - Tap "Add Member"
  - Verify: Device B's username appears in contact picker
  - Tap on Device B's username
  - Tap "Invite" in confirmation dialog
  VERIFY: "Member invited" snackbar appears
  VERIFY: Device B appears in member list on Group Info screen

Step 3: Accept Invite (Device B)
  - Wait up to 30 seconds for invite to arrive
  VERIFY: Group "Test Group" appears in Device B's group list
  - Tap the group to open conversation

Step 4: Chat (Both Devices)
  - Device A: Type "Hello from Admin" and send
  VERIFY: Message appears in Device A's conversation
  - Wait up to 10 seconds
  VERIFY: Message appears in Device B's conversation
  - Device B: Type "Hello back!" and send
  VERIFY: Message appears in Device B's conversation
  - Wait up to 10 seconds
  VERIFY: Message appears in Device A's conversation
```

### 6.2 Edge Case: Invite User Without ML-KEM Key
**Devices:** Device A (Admin), Device C (Legacy Member without ML-KEM)
**Prerequisite:** Device C is a contact of Device A but has no ML-KEM public key (older client version or key not generated).

```
Step 1: Create Group (Device A)
  - Create a group as in 6.1

Step 2: Attempt Invite (Device A)
  - Go to Group Info -> Add Member
  - Select Device C
  - Confirm invite
  VERIFY: Member is added locally (appears in member list)
  VERIFY: Log shows GROUP_INVITE_SEND_ENCRYPTION_REQUIRED event
  NOTE: Invite cannot be sent encrypted; member is saved but invite delivery fails
  EXPECTED BEHAVIOR: Member added to local DB and config updated, but 1:1 invite not sent (or error shown)
```

### 6.3 Edge Case: Invite While Offline
**Devices:** Device A (Admin), Device B (Member)
**Prerequisite:** Both are mutual contacts.

```
Step 1: Create Group (Device A)

Step 2: Put Device B in airplane mode

Step 3: Invite (Device A)
  - Add Member -> Select Device B -> Confirm
  VERIFY: Member added to local member list
  VERIFY: Invite attempted via direct P2P (fails)
  VERIFY: Invite stored in relay inbox as fallback
  VERIFY: Log shows GROUP_INVITE_SEND_SUCCESS via 'inbox'

Step 4: Bring Device B online
  - Disable airplane mode
  - Wait for inbox drain (up to 60 seconds)
  VERIFY: Group appears in Device B's group list
  VERIFY: Device B can open the group and send messages
```

### 6.4 Edge Case: Double Invite
**Devices:** Device A (Admin), Device B (Member)

```
Step 1: Create Group and Invite B (Device A)
  - Complete full invite as in 6.1

Step 2: Attempt to re-invite (Device A)
  - Go to Group Info -> Add Member
  VERIFY: Device B does NOT appear in contact picker (already a member, filtered out)

Step 3: Simulate double invite (if somehow received)
  - If Device B receives a second invite for the same groupId
  VERIFY: handleIncomingGroupInvite returns duplicateGroup
  VERIFY: Original group data is unchanged
  VERIFY: No crash or error visible to user
```

### 6.5 Error Recovery: Bridge Timeout During Invite Send
**Devices:** Device A (Admin)
**Prerequisite:** Simulate bridge timeout (e.g., Go bridge is slow/unresponsive)

```
Step 1: Create Group

Step 2: Invite with slow bridge
  - Add Member -> Select contact -> Confirm
  - If callGroupUpdateConfig times out:
    VERIFY: Error snackbar "Failed to invite member" appears
    VERIFY: Member may have been saved to local DB (partial state)
  - If sendGroupInvite times out:
    VERIFY: Member was already saved and config updated
    VERIFY: Invite delivery failed but group state is consistent
```

### 6.6 Edge Case: Invite From Non-Contact
**Devices:** Device A, Device B (NOT contacts)

```
Step 1: Device A creates group
Step 2: Device A somehow sends invite to Device B (simulated)
  VERIFY: Device B's GroupInviteListener returns unknownSender
  VERIFY: No group created on Device B
  VERIFY: No crash
```

### 6.7 Full Lifecycle: Create -> Invite -> Chat -> Remove -> Leave
**Devices:** Device A (Admin), Device B (Member), Device C (Member)

```
Step 1: Create Group (Device A)
Step 2: Invite B and C (Device A)
Step 3: Chat: all three users send messages
  VERIFY: All users see all messages

Step 4: Remove B (Device A)
  - Group Info -> Remove B
  VERIFY: B disappears from member list
  VERIFY: Key rotation occurs (log shows GROUP_REMOVE_MEMBER_USE_CASE_SUCCESS)
  NOTE: B may still have old key but can no longer validate/publish

Step 5: Chat after removal
  - Device A sends "After removal"
  VERIFY: Device C sees the message
  NOTE: Device B may or may not still receive (depending on pubsub mesh state)

Step 6: Leave (Device C)
  - Group Info -> Leave Group
  VERIFY: Device C's group list no longer shows the group
  VERIFY: All local data (group, members, keys) deleted on Device C
```

---

## 7. Regression Checklist

### 7.1 1:1 Messaging
- [ ] Sending a 1:1 chat message still works after groups feature changes
- [ ] v2 encrypted 1:1 messages still encrypt/decrypt correctly
- [ ] Inbox fallback for 1:1 messages still works
- [ ] IncomingMessageRouter correctly routes chat_message type (not confused with group_invite)

### 7.2 Contact Requests
- [ ] Contact request flow (send/receive) unaffected by group invite listener
- [ ] IncomingMessageRouter correctly routes contact_request type
- [ ] Profile updates still route correctly

### 7.3 Group Creation (Pre-existing)
- [ ] createGroupUseCase still works
- [ ] Group appears in group list after creation
- [ ] Group key is generated and saved

### 7.4 Feed Display
- [ ] Feed screen still renders ConnectionFeedItem and MessageFeedItem
- [ ] No crash when groups exist but feed has no group items
- [ ] Navigation from feed to conversation still works

### 7.5 Navigation Flows
- [ ] Feed tab -> Groups tab navigation works
- [ ] Groups tab -> Group List -> Conversation -> Info -> Contact Picker flow works without crashes
- [ ] Back navigation from any depth returns correctly
- [ ] Pop-to-root from Leave Group works
- [ ] Orbit screen still constructs QRScannerWired correctly (DI chain intact)

### 7.6 Bridge Interface
- [ ] `Bridge.onGroupMessageReceived` callback field exists and is wired
- [ ] `Bridge.onAddressesUpdated` callback field exists (pre-existing requirement)
- [ ] GoBridgeClient dispatches group:updateConfig to correct Go function
- [ ] GoBridgeClient dispatches group:join to GroupJoinTopic (not legacy JoinGroup)

### 7.7 Database Migrations
- [ ] Migration 017 (groups tables) applies cleanly on fresh install
- [ ] Migration 018 (group messages) applies cleanly on fresh install
- [ ] Upgrade from pre-groups DB version works without data loss

### 7.8 Secure Storage
- [ ] ML-KEM secret key retrieval from SecureKeyStore still works
- [ ] ML-KEM key is correctly passed to GroupInviteListener's getOwnMlKemSecretKey callback

---

## 8. Priority Order

### P0 — Critical (Write First)
These tests cover the core invite flow and its most dangerous failure modes.

1. **`handleIncomingGroupInvite` — v2 with null ownMlKemSecretKey** (`handle_incoming_group_invite_use_case_test.dart`)
   - Risk: Silent data corruption if decryption proceeds with null key
   - Already partially covered but this specific case is missing

2. **`handleIncomingGroupInvite` — bridge general error persists group** (`handle_incoming_group_invite_use_case_test.dart`)
   - Risk: User sees error but group is actually saved, inconsistent UI state

3. **ContactPickerWired — verify callGroupUpdateConfig sends full config** (`contact_picker_wired_test.dart`)
   - Risk: If config is incomplete, Go validator rejects new member's messages; this was the original bug that prompted the fix

4. **ContactPickerWired — verify sendGroupInvite called with correct params** (`contact_picker_wired_test.dart`)
   - Risk: Invite sent with wrong key or config; member joins but can't decrypt

5. **Full invite flow integration test** (NEW file)
   - Risk: Individual unit tests pass but end-to-end flow fails due to serialization mismatch

### P1 — High (Write Second)
These tests cover important error paths and secondary flows.

6. **`addGroupMember` — group not found error** (`add_group_member_use_case_test.dart`)
7. **`removeGroupMember` — error paths (group not found, not admin, rotate fails)** (`remove_group_member_use_case_test.dart`)
8. **`GroupInviteListener` — bridgeError result handling** (`group_invite_listener_test.dart`)
9. **`sendGroupInvite` — encryption exception path** (`send_group_invite_use_case_test.dart`)
10. **GroupInfoWired — full wired tests** (NEW file)
11. **GroupListWired — auto-refresh on invite stream** (NEW file)
12. **Go: `TestGroupUpdateConfig_ConcurrentReadWrite`** (race detection)

### P2 — Medium (Write Third)
These tests cover edge cases and secondary widgets.

13. **`handleIncomingGroupInvite` — empty members, missing name, unknown type** (`handle_incoming_group_invite_use_case_test.dart`)
14. **GroupConversationWired — wired tests** (NEW file)
15. **Multiple invites integration test** (NEW file)
16. **Invite during messaging integration test** (NEW file)
17. **Go: `TestGroupJoinTopic_ParsesConfigKeyAndEpochFromJSON`** (bridge function)
18. **Go: Validator after key rotation** (pubsub_test.go)

### P3 — Low (Nice to Have)
These tests cover unlikely edge cases and documentation-level assertions.

19. **`GroupInvitePayload` — additional parsing edge cases** (`group_invite_payload_test.dart`)
20. **`leaveGroup` — error paths** (`leave_group_use_case_test.dart`)
21. **`GroupMessageListener` — double start, invalid timestamp** (`group_message_listener_test.dart`)
22. **DI chain compilation tests** (NEW file)
23. **`callGroupUpdateConfig` — malformed config** (`bridge_group_helpers_test.dart`)

---

## Appendix A: Test File -> Source File Mapping

| Source File | Test File | Status |
|------------|-----------|--------|
| `lib/features/groups/application/add_group_member_use_case.dart` | `test/features/groups/application/add_group_member_use_case_test.dart` | Exists, needs additions |
| `lib/features/groups/application/send_group_invite_use_case.dart` | `test/features/groups/application/send_group_invite_use_case_test.dart` | Exists, needs additions |
| `lib/features/groups/application/handle_incoming_group_invite_use_case.dart` | `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart` | Exists, needs additions |
| `lib/features/groups/application/group_invite_listener.dart` | `test/features/groups/application/group_invite_listener_test.dart` | Exists, needs additions |
| `lib/features/groups/application/send_group_message_use_case.dart` | `test/features/groups/application/send_group_message_use_case_test.dart` | Exists |
| `lib/features/groups/application/handle_incoming_group_message_use_case.dart` | `test/features/groups/application/handle_incoming_group_message_use_case_test.dart` | Exists |
| `lib/features/groups/application/remove_group_member_use_case.dart` | `test/features/groups/application/remove_group_member_use_case_test.dart` | Exists, needs additions |
| `lib/features/groups/application/leave_group_use_case.dart` | `test/features/groups/application/leave_group_use_case_test.dart` | Exists, needs additions |
| `lib/features/groups/application/group_message_listener.dart` | `test/features/groups/application/group_message_listener_test.dart` | Exists, needs additions |
| `lib/features/groups/domain/models/group_invite_payload.dart` | `test/features/groups/domain/models/group_invite_payload_test.dart` | Exists, needs additions |
| `lib/features/groups/presentation/screens/contact_picker_wired.dart` | `test/features/groups/presentation/contact_picker_wired_test.dart` | Exists, needs significant additions |
| `lib/features/groups/presentation/screens/group_info_wired.dart` | NONE | Needs NEW file |
| `lib/features/groups/presentation/screens/group_list_wired.dart` | NONE | Needs NEW file |
| `lib/features/groups/presentation/screens/group_conversation_wired.dart` | NONE | Needs NEW file |
| `lib/core/bridge/bridge_group_helpers.dart` | `test/core/bridge/bridge_group_helpers_test.dart` | Exists, needs additions |
| `lib/core/services/incoming_message_router.dart` | `test/core/services/incoming_message_router_test.dart` | Exists, complete |
| `go-mknoon/node/pubsub.go` | `go-mknoon/node/pubsub_test.go` | Exists, needs additions |
| `go-mknoon/bridge/bridge.go` | `go-mknoon/bridge/bridge_test.go` | Needs verification/additions |

## Appendix B: Available Test Fakes

| Fake | Location | Notes |
|------|----------|-------|
| `FakeBridge` | `test/core/bridge/fake_bridge.dart` | Pre-canned responses, call tracking, command log |
| `PassthroughCryptoBridge` | `test/core/bridge/fake_bridge.dart` | Passes plaintext through encrypt/decrypt |
| `FakeP2PService` | `test/core/services/fake_p2p_service.dart` | Configurable send/inbox results, call tracking |
| `InMemoryGroupRepository` | `test/shared/fakes/in_memory_group_repository.dart` | Full GroupRepository implementation |
| `InMemoryGroupMessageRepository` | `test/shared/fakes/in_memory_group_message_repository.dart` | Full GroupMessageRepository implementation |
| `InMemoryContactRepository` | `test/shared/fakes/in_memory_contact_repository.dart` | Full ContactRepository implementation |
| `FakeContactRepository` | `test/features/contacts/domain/repositories/fake_contact_repository.dart` | Seedable contact list |
| `FakeSecureKeyStore` | Referenced in MEMORY.md | In-memory Map for secure storage |

## Appendix C: Key Code References

### Critical Code Path: ContactPickerWired._inviteMember()
Location: `lib/features/groups/presentation/screens/contact_picker_wired.dart:87-182`

This is the most complex code path in the invite flow. It performs 3 sequential operations:
1. `addGroupMember()` - saves member to local DB
2. `callGroupUpdateConfig()` - sends full GroupConfig to Go bridge
3. `sendGroupInvite()` - encrypts and sends invite via 1:1 P2P

Failure at any step has different consequences:
- Step 1 fails: Nothing saved, error shown
- Step 1 succeeds, step 2 fails: Member saved locally but Go validator not updated (messages from new member will be rejected by pubsub)
- Steps 1-2 succeed, step 3 fails: Member saved and validator updated, but invite not delivered (new member doesn't know about group)

### Critical Code Path: handleIncomingGroupInvite()
Location: `lib/features/groups/application/handle_incoming_group_invite_use_case.dart:41-242`

This processes received invites. The v2 encrypted path (lines 63-106) is the most complex:
1. Parse v2 envelope
2. Decrypt with ML-KEM
3. Parse inner JSON
4. Validate sender is a contact
5. Check for duplicate group
6. Persist group, members, key
7. Call bridge to join topic

Key design decision: Steps 6-7 are NOT transactional. If bridge join fails, the group is still persisted (bridgeError result). This is intentional for retry-ability.

### Critical Go Code: groupTopicValidator()
Location: `go-mknoon/node/pubsub.go:237-299`

The validator runs for every incoming pubsub message. It must:
1. Verify v3 envelope format
2. Verify groupId matches
3. Look up current config (via `n.groupConfigs[groupId]`)
4. Find sender in members list
5. Check write permission (announcement: admin only)
6. Verify Ed25519 signature

When `UpdateGroupConfig` is called, the validator immediately uses the new config for subsequent messages. This is why the full config (with new member) must be sent before the new member starts publishing.
