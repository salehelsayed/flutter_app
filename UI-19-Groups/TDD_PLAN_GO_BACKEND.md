# TDD Plan: Go Backend for Group Member Invite

## Status Quo Analysis

### Current Go Bridge Commands (group-related)

| Bridge Function       | Dart Command          | What It Does                                                |
|-----------------------|-----------------------|-------------------------------------------------------------|
| `GroupCreate`         | `group:create`        | Generate UUID + group key, build config with creator as admin, join topic |
| `GroupJoinTopic`      | `group:join`          | Join existing topic with provided groupId, groupConfig, groupKey, keyEpoch |
| `GroupLeaveTopic`     | `group:leave`         | Unsubscribe, cancel goroutines, clean up maps               |
| `GroupPublish`        | `group:publish`       | Encrypt + sign + publish v3 envelope to topic                |
| `GroupUpdateConfig`   | `group:updateConfig`  | Replace the in-memory `groupConfigs[groupId]` pointer        |
| `GroupRotateKey`      | `group:rotateKey`     | Generate new AES-256 key, increment epoch, update in-memory  |
| `GroupEncryptMessage` | `group.encrypt`       | Stateless AES-256-GCM encrypt                               |
| `GroupDecryptMessage` | `group.decrypt`       | Stateless AES-256-GCM decrypt                               |
| `GroupInboxStore`     | `group:inboxStore`    | Store encrypted message blob in relay group inbox            |
| `GroupInboxRetrieve`  | `group:inboxRetrieve` | Retrieve missed messages from relay group inbox              |
| `GenerateGroupKey`    | `group.keygen`        | Generate random 32-byte AES-256 key                          |

### Analysis of `GroupUpdateConfig` (Current State)

**File:** `go-mknoon/bridge/bridge.go` lines 1354-1386
**File:** `go-mknoon/node/pubsub.go` lines 209-213

What it does:
- Parses `{ "groupId": "...", "groupConfig": {...} }` from JSON
- Calls `n.UpdateGroupConfig(groupId, &config)` which just replaces the pointer in `n.groupConfigs[groupId]`
- Returns `{ "ok": true }`

**What is MISSING for the invite flow:**

1. **No topic validator refresh.** The topic validator is a closure created at `JoinGroupTopic` time. It captures `groupId` but reads `n.groupConfigs[groupId]` dynamically via the mutex. So updating the config pointer IS sufficient for the validator to see new members. **This is correct as-is** -- the validator reads `n.groupConfigs` under lock on every message, so adding a member to the config immediately takes effect for validation.

2. **No broadcast to existing members.** `GroupUpdateConfig` only updates the local node's in-memory config. It does NOT send the updated config to other group members. This is a **deliberate design choice**: config distribution is handled by the Flutter layer via 1:1 encrypted messages, not by the Go pubsub layer. The Go layer is the "dumb executor" -- Flutter is the orchestrator.

3. **No verification that the caller is admin.** The bridge function blindly replaces the config. Admin-check enforcement is done at the Flutter/use-case layer (`add_group_member_use_case.dart` line 36-43).

**Conclusion:** `GroupUpdateConfig` is correctly minimal for its role. The validator picks up new members immediately because it reads `groupConfigs[groupId]` under lock on every incoming message.

### Analysis of `GroupJoinTopic` (Current State)

**File:** `go-mknoon/bridge/bridge.go` lines 1216-1257
**File:** `go-mknoon/node/pubsub.go` lines 37-86

What it does:
- Parses `{ "groupId": "...", "groupConfig": {...}, "groupKey": "...", "keyEpoch": N }`
- Calls `n.JoinGroupTopic(groupId, &config, keyInfo)` which:
  - Registers a topic validator (checks membership + signature)
  - Joins the GossipSub topic
  - Subscribes and starts `handleGroupSubscription` goroutine
  - Stores config, key, topic, sub in Node maps
  - Starts `groupPeerDiscoveryLoop` (rendezvous register + periodic discover)

**What is MISSING for the invite flow:**

Nothing significant. The invitee needs:
- `groupId` -- provided by admin
- `groupConfig` (with the updated member list including themselves) -- provided by admin
- `groupKey` (current AES-256 key) -- provided by admin
- `keyEpoch` -- provided by admin

All of this is assembled on the Flutter side and passed through `group:join`.

### Analysis of Dart-Go Bridge Mismatch

**IMPORTANT:** There is a mismatch between what the Dart `callGroupJoin` helper sends and what the Go `GroupJoinTopic` expects:

- **Dart side** (`bridge_group_helpers.dart` lines 83-87): sends `{ "groupId": "...", "topicName": "..." }`
- **Go side** (`bridge.go` lines 1231-1236): expects `{ "groupId": "...", "groupConfig": {...}, "groupKey": "...", "keyEpoch": N }`

The Dart `callGroupJoin` helper is **stale/incomplete** -- it was written before the Go bridge was fully implemented. The `joinGroup` use case (`join_group_use_case.dart`) calls `callGroupJoin` but only passes `groupId` and `topicName`, missing the critical `groupConfig`, `groupKey`, and `keyEpoch` fields. This means the Go side would receive empty values and the join would either fail or create a broken subscription.

This mismatch must be fixed as part of the invite flow. The Dart `callGroupJoin` helper needs to be updated to pass the full config, key, and epoch. However, this is a **Dart-side fix**, not a Go-side change.

### Key Insight: No New Go Bridge Command Needed

The invite flow for adding a member does NOT require a new Go bridge command. Here is why:

**The invite flow (orchestrated by Flutter):**

1. Admin calls `addGroupMember` use case (Dart) -- saves new member to local DB
2. Admin updates local GroupConfig to include new member
3. Admin calls `group:updateConfig` -- updates Go in-memory config (validator now accepts new member)
4. Admin encrypts an invite payload (groupId, groupConfig, groupKey, keyEpoch) using the invitee's ML-KEM public key
5. Admin sends the encrypted invite via the existing 1:1 `message:send` or `inbox:store` bridge commands
6. Invitee receives the 1:1 message, decrypts the invite payload
7. Invitee calls `group:join` with the received config/key/epoch
8. Admin also needs to broadcast the updated config (with new member) to all existing members via 1:1 messages so their validators accept the new member

Steps 4-5 use existing bridge commands (`message.encrypt` / `message:send` / `inbox:store`). Step 8 also uses existing 1:1 messaging. No new Go command is needed.

**However**, we should verify and test that the existing Go commands handle the invite flow edge cases correctly.

---

## TDD Plan: Test-First Development

### Phase 1: Verify `GroupUpdateConfig` Handles Member Addition

These tests verify that when the config is updated to include a new member, the topic validator immediately accepts messages from that new member.

#### Test 1.1: Validator Accepts New Member After Config Update

**File:** `go-mknoon/node/pubsub_test.go`

```
TestGroupTopicValidator_AcceptsNewMemberAfterConfigUpdate
```

**What it asserts:**
1. Create a GroupConfig with only member A (admin).
2. Build a valid v3 envelope from member B (who is NOT in the config).
3. Validate the envelope -- expect `reject:non_member`.
4. Update the config to include member B (writer role).
5. Validate the same envelope again -- expect `accept`.

**Implementation to make it pass:**
No new code needed -- this should already pass because `validateGroupEnvelope` accepts config as a parameter. But this test verifies the pattern that the invite flow relies on. If it fails, we need to investigate.

---

#### Test 1.2: Validator Rejects Removed Member After Config Update

**File:** `go-mknoon/node/pubsub_test.go`

```
TestGroupTopicValidator_RejectsRemovedMemberAfterConfigUpdate
```

**What it asserts:**
1. Create a GroupConfig with members A (admin) and B (writer).
2. Build a valid v3 envelope from member B.
3. Validate -- expect `accept`.
4. Update the config to remove member B.
5. Validate the same envelope -- expect `reject:non_member`.

**Implementation to make it pass:**
No new code needed -- same reasoning as 1.1. The validator reads the config on each call.

---

#### Test 1.3: UpdateGroupConfig Replaces Config Atomically

**File:** `go-mknoon/node/pubsub_test.go`

```
TestUpdateGroupConfig_ReplacesConfigAtomically
```

**What it asserts:**
1. Start a node.
2. Join a group topic with a config containing 1 member.
3. Call `UpdateGroupConfig` with a new config containing 3 members.
4. Read back `n.groupConfigs[groupId]` and verify it has 3 members.
5. Verify the old config pointer is no longer referenced.

**Implementation to make it pass:**
Already passes with current `UpdateGroupConfig`. This test documents the contract.

---

#### Test 1.4: UpdateGroupConfig on Non-Existent Group

**File:** `go-mknoon/node/pubsub_test.go`

```
TestUpdateGroupConfig_NonExistentGroup
```

**What it asserts:**
1. Start a node (with no groups joined).
2. Call `UpdateGroupConfig("nonexistent-group", config)`.
3. Verify it does not panic and the config is stored (or silently ignored).

**Implementation to make it pass:**
Current code stores the config even for non-existent groups (no guard). This test documents whether that is acceptable or if we need to add a guard. If we decide a guard is needed, add an error return.

---

### Phase 2: Verify `GroupJoinTopic` Handles Invite Join

#### Test 2.1: JoinGroupTopic Succeeds With Multi-Member Config

**File:** `go-mknoon/node/pubsub_test.go`

```
TestJoinGroupTopic_WithMultiMemberConfig
```

**What it asserts:**
1. Start a node.
2. Create a GroupConfig with 3 members (admin, writer, reader) -- simulating an invitee receiving a config from the admin.
3. Call `JoinGroupTopic` with that config and a valid key.
4. Verify the topic, subscription, config, and key are all stored.
5. Verify the discovery loop started.

**Implementation to make it pass:**
Should already pass. This test documents the happy path for an invitee joining.

---

#### Test 2.2: JoinGroupTopic Sets Up Validator That Accepts All Listed Members

**File:** `go-mknoon/node/pubsub_test.go`

```
TestJoinGroupTopic_ValidatorAcceptsAllListedMembers
```

**What it asserts:**
1. Start a node.
2. Join a group topic with config listing members A (admin), B (writer), C (reader).
3. Build valid v3 envelopes from A, B, and C (for a chat group).
4. Validate all three -- all should `accept` (chat allows all members to write).
5. Build an envelope from unknown peer D -- should `reject:non_member`.

**Implementation to make it pass:**
Should already pass. The validator reads config from `n.groupConfigs[groupId]` and `findMember` searches the list. This test validates that the invite config propagation works end-to-end at the node level.

---

#### Test 2.3: JoinGroupTopic Fails With Missing PubSub

**File:** `go-mknoon/node/pubsub_test.go`

```
TestJoinGroupTopic_FailsWithoutPubSub
```

**What it asserts:**
1. Create a node but do NOT start it (so pubsub is nil).
2. Attempt to call `JoinGroupTopic`.
3. Expect an error: "pubsub not initialized".

**Implementation to make it pass:**
Already passes -- line 41-43 of pubsub.go checks for nil pubsub.

---

#### Test 2.4: JoinGroupTopic Fails When Already Joined

**File:** `go-mknoon/node/pubsub_test.go`

```
TestJoinGroupTopic_RejectsDoubleJoin
```

**What it asserts:**
1. Start a node.
2. Join a group topic with some config.
3. Attempt to join the same group again.
4. Expect an error: "already joined group topic".

**Implementation to make it pass:**
Already passes -- line 45-47 of pubsub.go checks `n.groupTopics[groupId]`.

---

### Phase 3: Bridge-Level Integration Tests

#### Test 3.1: GroupUpdateConfig Bridge -- Happy Path With New Member

**File:** `go-mknoon/bridge/bridge_test.go`

```
TestGroupUpdateConfig_WithNewMember
```

**What it asserts:**
1. Use `withFreshSingletonNode(t)` to set up a node.
2. Start the node.
3. Call `GroupCreate` to create a group (returns groupId, groupKey).
4. Build a new GroupConfig JSON that adds a second member to the original creator-only config.
5. Call `GroupUpdateConfig` with the new config.
6. Assert `ok: true`.

**Implementation to make it pass:**
Should already pass. Tests the bridge layer for the invite flow's "admin updates config" step.

---

#### Test 3.2: GroupJoinTopic Bridge -- Happy Path With Received Invite Data

**File:** `go-mknoon/bridge/bridge_test.go`

```
TestGroupJoinTopic_WithInviteData
```

**What it asserts:**
1. Use `withFreshSingletonNode(t)` + start node.
2. Build a GroupConfig with 2 members (simulating invite payload).
3. Generate a group key via `GenerateGroupKey`.
4. Call `GroupJoinTopic` with `{ "groupId": "invite-group-1", "groupConfig": {...}, "groupKey": "<key>", "keyEpoch": 1 }`.
5. Assert `ok: true`.

**Implementation to make it pass:**
Should already pass. Tests the invitee's perspective of the bridge-level join.

---

#### Test 3.3: GroupUpdateConfig Bridge -- Invalid JSON

**File:** `go-mknoon/bridge/bridge_test.go`

Already exists: `TestGroupUpdateConfig_InvalidJSON`.

---

#### Test 3.4: GroupUpdateConfig Bridge -- Missing GroupId

**File:** `go-mknoon/bridge/bridge_test.go`

Already exists: `TestGroupUpdateConfig_MissingGroupId`.

---

### Phase 4: Verify Validator Dynamics (Config Mutation After Join)

These tests simulate the full invite lifecycle from the Go node's perspective.

#### Test 4.1: Full Invite Lifecycle -- Admin Adds Member, Config Updated, New Member's Messages Accepted

**File:** `go-mknoon/node/pubsub_test.go`

```
TestInviteLifecycle_AdminAddsNewMember_ValidatorAcceptsNewMember
```

**What it asserts:**
1. Start a node.
2. Join a group topic with config containing only admin (peer-admin).
3. Generate keys for a new member (peer-new).
4. Build a v3 envelope from peer-new -- validate, expect `reject:non_member`.
5. Call `UpdateGroupConfig` with a config that includes peer-new as a writer.
6. Build a v3 envelope from peer-new with the correct pub key -- validate, expect `accept`.

**Implementation to make it pass:**
Should pass as-is. This is the critical test that proves the invite flow works at the Go level.

---

#### Test 4.2: Full Invite Lifecycle -- Announcement Group: New Writer Cannot Publish

**File:** `go-mknoon/node/pubsub_test.go`

```
TestInviteLifecycle_AnnouncementGroup_NewWriterCannotPublish
```

**What it asserts:**
1. Start a node.
2. Join an announcement group topic with config containing admin + new writer.
3. Build a v3 envelope from the new writer -- validate, expect `reject:unauthorized`.
4. Build a v3 envelope from the admin -- validate, expect `accept`.

**Implementation to make it pass:**
Should pass as-is. Verifies that announcement group restrictions apply to invited members.

---

#### Test 4.3: Validate Envelope Checks KeyEpoch Consistency

**File:** `go-mknoon/node/pubsub_test.go`

```
TestGroupTopicValidator_WrongKeyEpoch_InvalidSignature
```

**What it asserts:**
1. Build a v3 envelope signed with keyEpoch=1.
2. Validate with a keyInfo that has keyEpoch=2.
3. Expect `reject:bad_signature` (because the signature includes the epoch in the signed data, and the validator rebuilds sigData with the current epoch).

**Implementation to make it pass:**
Should pass as-is. This is important for the invite flow because when a key is rotated after adding a member, messages signed with the old epoch will be rejected.

---

### Phase 5: Group Key Info for Invite Payload

#### Test 5.1: GetGroupKeyInfo Returns Current Key

**File:** `go-mknoon/node/pubsub_test.go`

```
TestGetGroupKeyInfo_ReturnsCurrentKey
```

**What it asserts:**
1. Start a node.
2. Join a group topic with keyEpoch=1.
3. Call `GetGroupKeyInfo(groupId)` -- expect key and epoch=1.
4. Call `UpdateGroupKey(groupId, newKeyInfo)` with epoch=2.
5. Call `GetGroupKeyInfo(groupId)` -- expect new key and epoch=2.

**Implementation to make it pass:**
Should pass as-is -- `GetGroupKeyInfo` is a simple map lookup.

---

#### Test 5.2: GetGroupKeyInfo Returns Nil for Unknown Group

**File:** `go-mknoon/node/pubsub_test.go`

```
TestGetGroupKeyInfo_ReturnsNilForUnknownGroup
```

**What it asserts:**
1. Start a node.
2. Call `GetGroupKeyInfo("nonexistent")` -- expect nil.

**Implementation to make it pass:**
Should pass as-is.

---

### Phase 6: Bridge-Level GroupRotateKey for Post-Invite Key Distribution

#### Test 6.1: GroupRotateKey Increments Epoch

**File:** `go-mknoon/bridge/bridge_test.go`

```
TestGroupRotateKey_IncrementsEpoch
```

**What it asserts:**
1. Start a node.
2. Create a group (keyEpoch starts at 1).
3. Call `GroupRotateKey` for that group.
4. Assert response has `keyEpoch: 2` and a new `groupKey`.
5. Call `GroupRotateKey` again.
6. Assert response has `keyEpoch: 3`.

**Implementation to make it pass:**
Should pass as-is. Tests the key rotation that happens AFTER removing a member (not strictly part of invite-add, but closely related).

---

### Phase 7: Edge Cases and Error Handling

#### Test 7.1: GroupUpdateConfig With Empty Members List

**File:** `go-mknoon/node/pubsub_test.go`

```
TestGroupTopicValidator_EmptyMembersList_RejectsAll
```

**What it asserts:**
1. Create a config with zero members.
2. Build an envelope from any peer.
3. Validate -- expect `reject:non_member`.

**Implementation to make it pass:**
Should pass as-is -- `findMember` returns nil when the list is empty.

---

#### Test 7.2: GroupUpdateConfig Preserves Discovery Loop

**File:** `go-mknoon/node/pubsub_test.go`

```
TestUpdateGroupConfig_PreservesDiscoveryLoop
```

**What it asserts:**
1. Start a node.
2. Join a group topic.
3. Verify discovery context exists.
4. Call `UpdateGroupConfig` with a new config.
5. Verify discovery context still exists (was not cancelled).

**Implementation to make it pass:**
Should pass as-is -- `UpdateGroupConfig` only replaces the config pointer, it does not touch `groupDiscoveryCtx`.

---

#### Test 7.3: findMember With Duplicate PeerIds

**File:** `go-mknoon/node/pubsub_test.go`

```
TestFindMember_DuplicatePeerId_ReturnsFirst
```

**What it asserts:**
1. Create a config with two entries for the same peerId (different roles).
2. Call `findMember` -- expect it returns the first match.

**Implementation to make it pass:**
Should pass as-is (range loop returns first match).

---

### Phase 8: Identify New Code Needed (If Any)

Based on thorough analysis, **no new Go code is needed** for the basic invite flow. However, there are two areas where new Go code COULD improve the system:

#### 8A: (OPTIONAL) GroupConfig Event Emission

Currently, `UpdateGroupConfig` silently updates the in-memory config. If we want the Go layer to notify Flutter when the config changes (e.g., for debugging or UI refresh), we could add an event.

**Test:**
```
TestUpdateGroupConfig_EmitsConfigChangedEvent
```

**What it asserts:**
1. Start a node with a mock event callback.
2. Join a group topic.
3. Call `UpdateGroupConfig` with a new config.
4. Assert the callback received a `group_config:updated` event with the groupId.

**Implementation:**
Add `n.emitEvent("group_config:updated", ...)` to `UpdateGroupConfig`.

**Decision:** OPTIONAL. Flutter already knows when it calls `group:updateConfig`, so this event is not strictly necessary.

---

#### 8B: (OPTIONAL) Bridge: GroupGetConfig

Currently there is no way for Flutter to read back the in-memory GroupConfig from Go. If we want a "source of truth" check, we could add `GroupGetConfig`.

**Test:**
```
TestGroupGetConfig_ReturnsCurrentConfig
```

**Implementation:**
Add a new bridge function `GroupGetConfig(paramsJSON) string` that returns `{ "ok": true, "groupConfig": {...} }`.

**Decision:** OPTIONAL. Flutter maintains its own copy in the DB. Only useful for debugging.

---

## Summary: Files Modified/Created

### Tests Only (no new production code for basic invite flow)

| File | Action | Description |
|------|--------|-------------|
| `go-mknoon/node/pubsub_test.go` | MODIFY | Add tests 1.1-1.4, 2.1-2.4, 4.1-4.3, 5.1-5.2, 7.1-7.3 |
| `go-mknoon/bridge/bridge_test.go` | MODIFY | Add tests 3.1-3.2, 6.1 |

### No Production Go Code Changes Required

The existing Go bridge commands (`GroupUpdateConfig`, `GroupJoinTopic`, `GroupRotateKey`) are sufficient for the invite flow. The topic validator already reads the latest config dynamically. The key and config management functions work correctly for the invite lifecycle.

### Dart-Side Fix Required (Not in This Plan)

The `callGroupJoin` helper in `lib/core/bridge/bridge_group_helpers.dart` needs to be updated to pass `groupConfig`, `groupKey`, and `keyEpoch` instead of just `topicName`. This is a Dart-side change, not a Go-side change, and belongs in the Dart TDD plan.

---

## Execution Order

1. **Phase 1** (Tests 1.1-1.4): Run tests to verify `GroupUpdateConfig` behavior. All should pass GREEN immediately. If any fail, investigate.
2. **Phase 2** (Tests 2.1-2.4): Run tests to verify `GroupJoinTopic` behavior. All should pass GREEN immediately.
3. **Phase 3** (Tests 3.1-3.2): Run bridge-level integration tests. Require a started node, so use `withFreshSingletonNode` + `TestStartNode_Success` pattern.
4. **Phase 4** (Tests 4.1-4.3): Run full lifecycle tests that simulate the invite flow end-to-end at the Go level.
5. **Phase 5** (Tests 5.1-5.2): Quick tests for `GetGroupKeyInfo`.
6. **Phase 6** (Test 6.1): Bridge-level key rotation test.
7. **Phase 7** (Tests 7.1-7.3): Edge case tests.
8. **Phase 8** (Optional): Only if Flutter-side debugging requires it.

---

## Test Infrastructure Notes

### Existing Patterns to Reuse

1. **`testGroupConfig(groupType)`** -- factory for test configs with 3 members (admin, writer, reader).
2. **`generateEd25519KeyPair(t)`** -- generates real Ed25519 keys for signing tests.
3. **`buildTestEnvelope(t, ...)`** -- builds a complete v3 envelope with real crypto.
4. **`validateGroupEnvelope(data, groupId, config, keyInfo)`** -- pure-function validator for testing without a running libp2p host.
5. **`withFreshSingletonNode(t)`** -- sets up singleton for bridge-level tests.
6. **`generateTestKeyHex(t)`** -- generates valid Ed25519 private key for `StartNode`.
7. **`startNodeJSON(t, keyHex)`** -- builds valid `StartNode` input JSON.
8. **`parseJSON(t, s)` / `assertOk(t, m)` / `assertNotOk(t, m, code)`** -- bridge test assertions.

### Running Tests

```bash
cd go-mknoon && go test ./node/ -run "TestGroupTopicValidator_AcceptsNewMember" -v
cd go-mknoon && go test ./node/ -run "TestInviteLifecycle" -v
cd go-mknoon && go test ./bridge/ -run "TestGroupUpdateConfig_WithNewMember" -v
cd go-mknoon && go test ./... -v  # full suite
```

---

## Architectural Decision: Why No New Go Bridge Command for Invites

The group invite payload (groupId, groupConfig, groupKey, keyEpoch) is sent via the existing 1:1 encrypted messaging infrastructure:

```
Admin (Flutter) --> message.encrypt --> message:send / inbox:store --> Relay --> Invitee (Flutter) --> message.decrypt
```

This reuses ML-KEM encryption (post-quantum secure) and the relay inbox (for offline delivery) that already exist. Creating a dedicated `group:sendInvite` Go bridge command would:

1. Duplicate logic already in Flutter (ML-KEM encrypt + 1:1 send)
2. Couple group concerns with 1:1 messaging in the Go layer
3. Add complexity with no security benefit

The group invite is just a special payload type within the existing 1:1 message channel. Flutter wraps it in a typed envelope (e.g., `{ "type": "group_invite", "payload": { ... } }`) and the recipient's message listener recognizes it and triggers the join flow.
