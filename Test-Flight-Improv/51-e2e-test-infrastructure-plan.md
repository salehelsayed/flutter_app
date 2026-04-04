# E2E Test Infrastructure Plan

**Goal:** Automate the user journey tests in `50-two-simulator-user-journey-tests.md` so that failures are caught before every TestFlight publish. The infrastructure must be extensible — new test scenarios added to the journey doc should be easy to wire up without rearchitecting.

**Existing infrastructure we build on:**
- `reset_simulators.sh` — boots 3 sims, installs app with `AUTO_SETUP_USERNAME`
- `smoke_test_friends.sh` — reads exported identities, writes config JSON, relaunches apps
- `smoke_test_runner.dart` — in-app: reads config, sends contact requests, introductions, auto-accepts
- `soak_e2e_test.dart` — signal-file IPC between host orchestrator and on-device test
- `setup_device.dart` — headless device provisioning (real DB + real bridge)

**Core idea:** Each simulator runs a **command executor** loop inside the app (debug-only). A **host-side orchestrator** writes command files and reads result files. Test scenarios are plain Dart functions in the orchestrator that sequence commands across devices.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  HOST: test_orchestrator.dart (Dart CLI)                         │
│                                                                  │
│  ┌─────────────┐  ┌─────────────────┐  ┌──────────────────────┐ │
│  │ DeviceHandle │  │ TestScenario     │  │ Assertions / Report │ │
│  │ .sendCmd()   │  │ test_2_1_basic() │  │ JUnit XML + stdout  │ │
│  │ .waitResult()│  │ test_6_1_offline()│  │                     │ │
│  │ .simctl()    │  │ test_I1_intro()  │  │                     │ │
│  └─────────────┘  └─────────────────┘  └──────────────────────┘ │
│        │                                                         │
│  File I/O via xcrun simctl get_app_container                     │
└────────┬─────────────────────────────────┬───────────────────────┘
         │                                 │
    ┌────▼─────────┐                 ┌─────▼────────┐
    │  Simulator A  │                 │  Simulator B  │
    │  App (debug)  │                 │  App (debug)  │
    │               │                 │               │
    │  TestCommand  │                 │  TestCommand  │
    │  Executor     │                 │  Executor     │
    │  (polls       │                 │  (polls       │
    │   cmd.json,   │   ◄── P2P ──►  │   cmd.json,   │
    │   writes      │                 │   writes      │
    │   result.json)│                 │   result.json)│
    └──────────────┘                 └──────────────┘
```

---

## Part 1: On-Device Command Executor

**New file:** `lib/core/debug/test_command_executor.dart`

This replaces the one-shot `smoke_test_runner.dart` with a persistent command loop. The existing smoke test runner stays unchanged — the command executor is a new, additive component.

### 1.1 Command File Protocol

The orchestrator writes a JSON file to the device's Documents directory. The executor polls for it, executes, writes a result, and deletes the command file.

**Command format** (`Documents/e2e_cmd.json`):
```json
{
  "id": "t1_send_msg",
  "action": "send_message",
  "params": {
    "to_peer_id": "12D3Koo...",
    "text": "hello from A"
  }
}
```

**Result format** (`Documents/e2e_result_<id>.json`):
```json
{
  "id": "t1_send_msg",
  "status": "ok",
  "data": {
    "message_id": "abc-123",
    "timestamp": "2026-04-03T10:00:00Z"
  }
}
```

**Error format:**
```json
{
  "id": "t1_send_msg",
  "status": "error",
  "error": "contact not found: 12D3Koo..."
}
```

### 1.2 Command Executor Loop

```dart
// Pseudo-code — actual implementation will follow this structure
Future<void> startTestCommandExecutor({
  required P2PService p2pService,
  required Bridge bridge,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required ContactRequestRepository contactRequestRepo,
  required IntroductionRepository introRepo,
  required MessageRepository messageRepo,
  required MediaAttachmentRepository mediaRepo,
  // ... other repos as needed
}) async {
  if (!kDebugMode) return;

  final dir = await getApplicationDocumentsDirectory();
  final cmdPath = '${dir.path}/e2e_cmd.json';

  // Poll every 500ms for new commands
  Timer.periodic(const Duration(milliseconds: 500), (timer) async {
    final cmdFile = File(cmdPath);
    if (!await cmdFile.exists()) return;

    final cmd = jsonDecode(await cmdFile.readAsString());
    await cmdFile.delete(); // consume immediately

    final result = await _executeCommand(cmd, ...allDeps);

    final resultFile = File('${dir.path}/e2e_result_${cmd['id']}.json');
    await resultFile.writeAsString(jsonEncode(result));
  });
}
```

### 1.3 Command Catalog (Phase 1 — MVP)

These commands cover test sections 1-2, 5-6, 9, 14 from the journey doc:

| Command | Params | Returns | Covers |
|---------|--------|---------|--------|
| `ping` | — | `{status: "ok", node_state: "online"}` | Health check |
| `get_identity` | — | `{peer_id, username}` | Setup verification |
| `get_contacts` | — | `{contacts: [{peer_id, username, ...}]}` | 1.1, 1.2, 13.x |
| `get_contact_requests` | — | `{requests: [{peer_id, username, status}]}` | 1.1, 1.3 |
| `accept_contact_request` | `{peer_id}` | `{status: "ok"}` | 1.1, 1.3 |
| `decline_contact_request` | `{peer_id}` | `{status: "ok"}` | 1.3 |
| `send_message` | `{to_peer_id, text}` | `{message_id, status}` | 2.1-2.4 |
| `get_messages` | `{peer_id, ?limit}` | `{messages: [{id, text, status, direction, timestamp}]}` | 2.x, 5.x, 6.x |
| `get_message_status` | `{message_id}` | `{status}` ("sending"/"sent"/"delivered"/"failed") | 2.1, 5.x, 6.x |
| `wait_for_message` | `{from_peer_id, ?text, ?timeout_s}` | `{message_id, text}` or timeout error | 2.1, 6.x |
| `get_node_status` | — | `{state, relay_ready, has_circuit_addr}` | 5.x, 6.x, 16.x |
| `count_unread` | `{peer_id}` | `{count}` | 7.x, 8.x |
| `get_introductions` | — | `{intros: [{id, introducer, recipient, introduced, status}]}` | I-1 through I-12 |
| `accept_introduction` | `{introduction_id}` | `{status, overall_status}` | I-1, I-2 |
| `pass_introduction` | `{introduction_id}` | `{status, overall_status}` | I-2 |
| `get_feed_items` | — | `{items: [{type, peer_id, unread_count, latest_text}]}` | 8.x |
| `delete_message` | `{message_id, ?for_everyone}` | `{status: "ok"}` | 4.4, 4.5 |
| `delete_contact` | `{peer_id}` | `{status: "ok"}` | 13.3, 13.4 |

### 1.4 Command Catalog (Phase 2 — Media, Groups, Reactions)

Added later as we extend the journey doc:

| Command | Covers |
|---------|--------|
| `send_voice_message` | 3.1 |
| `send_image_message` | 3.2 |
| `send_video_message` | 3.3 |
| `add_reaction` | 4.1 |
| `remove_reaction` | 4.1 |
| `edit_message` | 4.3 |
| `create_group` | 10.1 |
| `invite_to_group` | 10.1 |
| `send_group_message` | 10.2 |
| `get_group_messages` | 10.2-10.5 |
| `leave_group` | 10.6 |
| `block_contact` | 13.1 |
| `unblock_contact` | 13.1 |
| `archive_contact` | 13.2 |

### 1.5 Integration into main.dart

The command executor starts alongside the existing smoke test runner, after `runApp()`:

```dart
// In main.dart, after the existing smoke test Timer:
if (kDebugMode) {
  startTestCommandExecutor(
    p2pService: p2pService,
    bridge: bridge,
    identityRepo: identityRepository,
    contactRepo: contactRepository,
    contactRequestRepo: contactRequestRepository,
    introRepo: introductionRepository,
    messageRepo: messageRepository,
    // ...
  );
}
```

**Guard:** Executor only runs when `const bool.fromEnvironment('E2E_TEST_MODE')` is true (passed via `--dart-define=E2E_TEST_MODE=true`). This prevents the polling loop from running in normal debug sessions.

---

## Part 2: Host-Side Orchestrator

**New file:** `integration_test/e2e/orchestrator.dart`

A standalone Dart CLI that boots simulators, installs the app, and runs test scenarios by writing command files and reading results.

### 2.1 DeviceHandle Class

```dart
class DeviceHandle {
  final String simulatorId;
  final String name; // "A", "B", "C"
  final String bundleId = 'com.mknoon.app';

  String get _docsDir {
    // Uses: xcrun simctl get_app_container <id> <bundle> data
    // Then appends /Documents/
  }

  /// Write a command and wait for the result (with timeout).
  Future<Map<String, dynamic>> sendCmd(
    String action, {
    Map<String, dynamic> params = const {},
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final id = '${name}_${DateTime.now().millisecondsSinceEpoch}';
    final cmdFile = File('$_docsDir/e2e_cmd.json');
    await cmdFile.writeAsString(jsonEncode({
      'id': id,
      'action': action,
      'params': params,
    }));

    // Poll for result file
    final resultPath = '$_docsDir/e2e_result_$id.json';
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final resultFile = File(resultPath);
      if (await resultFile.exists()) {
        final result = jsonDecode(await resultFile.readAsString());
        await resultFile.delete();
        if (result['status'] == 'error') {
          throw E2ECommandError(action, result['error']);
        }
        return result['data'] as Map<String, dynamic>? ?? {};
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
    throw E2ETimeoutError(action, timeout);
  }

  /// Run xcrun simctl commands for OS-level manipulation.
  Future<void> setNetwork({required bool enabled}) async {
    if (!enabled) {
      await Process.run('xcrun', [
        'simctl', 'status_bar', simulatorId, 'override',
        '--dataNetwork', 'none',
      ]);
    } else {
      await Process.run('xcrun', ['simctl', 'status_bar', simulatorId, 'clear']);
    }
  }

  Future<void> terminateApp() async {
    await Process.run('xcrun', ['simctl', 'terminate', simulatorId, bundleId]);
  }

  Future<void> launchApp() async {
    await Process.run('xcrun', ['simctl', 'launch', simulatorId, bundleId]);
  }
}
```

### 2.2 Assertion Helpers

```dart
void assertEq(dynamic actual, dynamic expected, String label) {
  if (actual != expected) {
    throw E2EAssertionError('$label: expected $expected, got $actual');
  }
}

void assertGte(num actual, num threshold, String label) {
  if (actual < threshold) {
    throw E2EAssertionError('$label: expected >= $threshold, got $actual');
  }
}

/// Retry an assertion up to N times with delay (for async P2P delivery).
Future<void> assertEventually(
  Future<void> Function() check, {
  int retries = 20,
  Duration delay = const Duration(seconds: 1),
  required String label,
}) async {
  for (var i = 0; i < retries; i++) {
    try {
      await check();
      return;
    } catch (_) {
      if (i == retries - 1) rethrow;
      await Future.delayed(delay);
    }
  }
}
```

### 2.3 Test Runner

```dart
Future<void> main(List<String> args) async {
  final simA = DeviceHandle(simulatorId: args[0], name: 'A');
  final simB = DeviceHandle(simulatorId: args[1], name: 'B');
  final simC = args.length > 2 ? DeviceHandle(simulatorId: args[2], name: 'C') : null;

  final runner = TestRunner(devices: [simA, simB, if (simC != null) simC]);

  // Setup: verify both devices are alive and P2P is online
  await runner.setup();

  // Run scenario functions
  await runner.run('1.1 Normal QR Scan Flow', () => test_1_1(simA, simB));
  await runner.run('2.1 Basic Send & Receive', () => test_2_1(simA, simB));
  await runner.run('6.1 Recipient Offline', () => test_6_1(simA, simB));
  // ... more scenarios

  // Print report
  runner.printReport();
  // Optionally write JUnit XML for CI
  runner.writeJUnitXml('e2e_results.xml');
}
```

---

## Part 3: Test Scenario Implementations

Each scenario from `50-two-simulator-user-journey-tests.md` becomes a function. Below are concrete implementations for representative scenarios from each section. The pattern is the same for all — it's just a different sequence of `sendCmd` calls.

### 3.1 Contact Exchange (Section 1)

#### Test 1.1 — Normal Contact Flow

Pre-condition: A and B are already contacts (handled by reset_simulators.sh + smoke_test_friends.sh during setup).

```dart
Future<void> test_1_1(DeviceHandle a, DeviceHandle b) async {
  // Verify both devices see each other as contacts
  final aContacts = await a.sendCmd('get_contacts');
  final bContacts = await b.sendCmd('get_contacts');

  final bPeer = await b.sendCmd('get_identity');
  final aPeer = await a.sendCmd('get_identity');

  assert(aContacts['contacts'].any((c) => c['peer_id'] == bPeer['peer_id']),
      'A should have B as contact');
  assert(bContacts['contacts'].any((c) => c['peer_id'] == aPeer['peer_id']),
      'B should have A as contact');
}
```

> **Note on QR scanning:** Programmatic QR scan is not possible across simulators. Instead, the contact exchange is bootstrapped by `reset_simulators.sh` + `smoke_test_friends.sh` which pre-populate contacts via exported identity payloads. This covers the same code path (ContactModel.fromQRPayload → addContact → sendContactRequest → acceptContactRequest) without needing camera access. Tests 1.1-1.4 verify the **result** of contact exchange, not the camera UI.

### 3.2 Text Messaging (Section 2)

#### Test 2.1 — Basic Send & Receive

```dart
Future<void> test_2_1(DeviceHandle a, DeviceHandle b) async {
  final bIdentity = await b.sendCmd('get_identity');
  final bPeerId = bIdentity['peer_id'];

  // A sends a message
  final sendResult = await a.sendCmd('send_message', params: {
    'to_peer_id': bPeerId,
    'text': 'hello from A',
  });
  final msgId = sendResult['message_id'];

  // Assert: A's message status reaches "delivered"
  await assertEventually(() async {
    final status = await a.sendCmd('get_message_status', params: {'message_id': msgId});
    assertEq(status['status'], 'delivered', 'A message delivery status');
  }, label: 'A message delivered');

  // Assert: B received exactly 1 message from A
  final bMessages = await b.sendCmd('get_messages', params: {'peer_id': bIdentity['peer_id']});
  // (get_messages uses A's peer ID from B's perspective — need A's peer ID)
  final aIdentity = await a.sendCmd('get_identity');
  final bMsgsFromA = await b.sendCmd('get_messages', params: {'peer_id': aIdentity['peer_id']});
  assertEq(bMsgsFromA['messages'].length, 1, 'B received message count');
  assertEq(bMsgsFromA['messages'][0]['text'], 'hello from A', 'B received message text');
}
```

#### Test 2.2 — Rapid Back-and-Forth

```dart
Future<void> test_2_2(DeviceHandle a, DeviceHandle b) async {
  final aId = (await a.sendCmd('get_identity'))['peer_id'];
  final bId = (await b.sendCmd('get_identity'))['peer_id'];

  final messageIds = <String>[];
  for (var i = 0; i < 5; i++) {
    final r1 = await a.sendCmd('send_message', params: {'to_peer_id': bId, 'text': 'A-$i'});
    messageIds.add(r1['message_id']);
    final r2 = await b.sendCmd('send_message', params: {'to_peer_id': aId, 'text': 'B-$i'});
    messageIds.add(r2['message_id']);
  }

  // Wait for all to reach delivered
  for (final id in messageIds) {
    await assertEventually(() async {
      // Check on whichever device sent it
      // (simplified — real impl would track which device owns which ID)
    }, label: 'message $id delivered', retries: 30);
  }

  // Assert: B has all 10 messages, in order, no duplicates
  final bMsgs = await b.sendCmd('get_messages', params: {'peer_id': aId, 'limit': 100});
  final fromA = bMsgs['messages'].where((m) => m['direction'] == 'incoming').toList();
  assertEq(fromA.length, 5, 'B received 5 messages from A');

  final aMsgs = await a.sendCmd('get_messages', params: {'peer_id': bId, 'limit': 100});
  final fromB = aMsgs['messages'].where((m) => m['direction'] == 'incoming').toList();
  assertEq(fromB.length, 5, 'A received 5 messages from B');
}
```

#### Test 2.3 — Long Message

```dart
Future<void> test_2_3(DeviceHandle a, DeviceHandle b) async {
  final bId = (await b.sendCmd('get_identity'))['peer_id'];
  final longText = 'x' * 5000;

  await a.sendCmd('send_message', params: {'to_peer_id': bId, 'text': longText});

  final aId = (await a.sendCmd('get_identity'))['peer_id'];
  await assertEventually(() async {
    final msgs = await b.sendCmd('get_messages', params: {'peer_id': aId});
    assertEq(msgs['messages'].last['text'].length, 5000, 'Long message not truncated');
  }, label: 'B receives long message');
}
```

### 3.3 Message Reliability (Section 5)

#### Test 5.2 — Send and Immediately Background

```dart
Future<void> test_5_2(DeviceHandle a, DeviceHandle b) async {
  final bId = (await b.sendCmd('get_identity'))['peer_id'];

  // A sends and we immediately terminate (simulates backgrounding)
  final sendResult = await a.sendCmd('send_message', params: {'to_peer_id': bId, 'text': 'bg test'});
  final msgId = sendResult['message_id'];

  // Terminate A's app after 1 second (message should already be in-flight)
  await Future.delayed(const Duration(seconds: 1));
  await a.terminateApp();

  // B should still receive it
  final aId = (await a.sendCmd('get_identity'))['peer_id']; // ← this will fail if app is dead
  // Instead, cache identity at start of test:
  // ... (real impl would cache peer IDs during setup)

  await Future.delayed(const Duration(seconds: 5));
  await a.launchApp();
  await Future.delayed(const Duration(seconds: 10)); // wait for restart + reconnect

  // Check A's message status after restart
  await assertEventually(() async {
    final status = await a.sendCmd('get_message_status', params: {'message_id': msgId});
    assert(status['status'] == 'delivered' || status['status'] == 'sent',
        'Message should not be stuck on "sending"');
  }, label: 'A message status after restart');
}
```

### 3.4 Offline & Reconnect (Section 6)

#### Test 6.1 — Recipient Offline, Inbox Delivery

```dart
Future<void> test_6_1(DeviceHandle a, DeviceHandle b) async {
  final aId = (await a.sendCmd('get_identity'))['peer_id'];
  final bId = (await b.sendCmd('get_identity'))['peer_id'];

  // B goes offline
  await b.setNetwork(enabled: false);
  await Future.delayed(const Duration(seconds: 3));

  // A sends a message
  final sendResult = await a.sendCmd('send_message', params: {
    'to_peer_id': bId,
    'text': 'offline delivery test',
  });
  final msgId = sendResult['message_id'];

  // A's status should be "sent" (stored in relay inbox, not direct-delivered)
  await Future.delayed(const Duration(seconds: 5));
  final statusWhileOffline = await a.sendCmd('get_message_status', params: {'message_id': msgId});
  assert(statusWhileOffline['status'] != 'delivered',
      'Should not be delivered while B is offline');

  // B comes back online
  await b.setNetwork(enabled: true);

  // B should receive the message via inbox drain
  await assertEventually(() async {
    final msgs = await b.sendCmd('get_messages', params: {'peer_id': aId});
    assert(msgs['messages'].any((m) => m['text'] == 'offline delivery test'),
        'B should receive offline message');
  }, label: 'B inbox drain', retries: 30, delay: const Duration(seconds: 2));

  // A's status should update to "delivered"
  await assertEventually(() async {
    final status = await a.sendCmd('get_message_status', params: {'message_id': msgId});
    assertEq(status['status'], 'delivered', 'A delivered after B reconnect');
  }, label: 'A delivery ack');
}
```

### 3.5 Introductions (Section 9 / I-*)

#### Test I-1.1 — Both Accept

```dart
Future<void> test_I_1_1(DeviceHandle a, DeviceHandle b, DeviceHandle c) async {
  // Pre-condition: A knows B and C, B and C do NOT know each other
  // (handled by setup — A introduced B and C, but auto_accept only covers
  //  contact requests, not necessarily this specific introduction)
  //
  // For a clean test, we could:
  //   1. Delete B↔C contact if it exists
  //   2. Have A send a fresh introduction

  final aId = (await a.sendCmd('get_identity'))['peer_id'];
  final bId = (await b.sendCmd('get_identity'))['peer_id'];
  final cId = (await c.sendCmd('get_identity'))['peer_id'];

  // A sends introduction of B to C
  // (This requires a new command: 'send_introduction')
  await a.sendCmd('send_introduction', params: {
    'recipient_peer_id': bId,
    'introduced_peer_id': cId,
  });

  // B receives introduction
  await assertEventually(() async {
    final intros = await b.sendCmd('get_introductions');
    assert(intros['intros'].any((i) =>
      i['introducer_peer_id'] == aId &&
      i['status'] == 'pending'
    ), 'B should have pending intro from A');
  }, label: 'B receives introduction');

  // C receives introduction
  await assertEventually(() async {
    final intros = await c.sendCmd('get_introductions');
    assert(intros['intros'].any((i) =>
      i['introducer_peer_id'] == aId &&
      i['status'] == 'pending'
    ), 'C should have pending intro from A');
  }, label: 'C receives introduction');

  // B accepts
  final bIntros = await b.sendCmd('get_introductions');
  final bIntroId = bIntros['intros'].firstWhere((i) => i['introducer_peer_id'] == aId)['id'];
  await b.sendCmd('accept_introduction', params: {'introduction_id': bIntroId});

  // C accepts
  final cIntros = await c.sendCmd('get_introductions');
  final cIntroId = cIntros['intros'].firstWhere((i) => i['introducer_peer_id'] == aId)['id'];
  await c.sendCmd('accept_introduction', params: {'introduction_id': cIntroId});

  // Assert: B and C are now contacts
  await assertEventually(() async {
    final bContacts = await b.sendCmd('get_contacts');
    assert(bContacts['contacts'].any((c_) => c_['peer_id'] == cId),
        'B should have C as contact');
  }, label: 'B↔C contact created', retries: 30);

  await assertEventually(() async {
    final cContacts = await c.sendCmd('get_contacts');
    assert(cContacts['contacts'].any((c_) => c_['peer_id'] == bId),
        'C should have B as contact');
  }, label: 'C↔B contact created');

  // B sends message to C — should work with encryption
  await b.sendCmd('send_message', params: {'to_peer_id': cId, 'text': 'hello via intro'});
  await assertEventually(() async {
    final msgs = await c.sendCmd('get_messages', params: {'peer_id': bId});
    assert(msgs['messages'].any((m) => m['text'] == 'hello via intro'),
        'C should receive encrypted message from B');
  }, label: 'C receives message from B');
}
```

### 3.6 Race Conditions (Section 14)

#### Test 14.5 — Simultaneous Messages

```dart
Future<void> test_14_5(DeviceHandle a, DeviceHandle b) async {
  final aId = (await a.sendCmd('get_identity'))['peer_id'];
  final bId = (await b.sendCmd('get_identity'))['peer_id'];

  // Both send at "the same time" (as close as file I/O allows)
  final aFuture = a.sendCmd('send_message', params: {'to_peer_id': bId, 'text': 'from A'});
  final bFuture = b.sendCmd('send_message', params: {'to_peer_id': aId, 'text': 'from B'});
  await Future.wait([aFuture, bFuture]);

  // Both should receive each other's message
  await assertEventually(() async {
    final bMsgs = await b.sendCmd('get_messages', params: {'peer_id': aId});
    assert(bMsgs['messages'].any((m) => m['text'] == 'from A'), 'B got A\'s message');
  }, label: 'B receives A');

  await assertEventually(() async {
    final aMsgs = await a.sendCmd('get_messages', params: {'peer_id': bId});
    assert(aMsgs['messages'].any((m) => m['text'] == 'from B'), 'A got B\'s message');
  }, label: 'A receives B');
}
```

### 3.7 Network Faults (Section 16)

#### Test 16.3 — Network Flapping

```dart
Future<void> test_16_3(DeviceHandle a, DeviceHandle b) async {
  final bId = (await b.sendCmd('get_identity'))['peer_id'];

  // Flap A's network 5 times
  for (var i = 0; i < 5; i++) {
    await a.setNetwork(enabled: false);
    await Future.delayed(const Duration(seconds: 5));
    await a.setNetwork(enabled: true);
    await Future.delayed(const Duration(seconds: 5));
  }

  // Send during an "on" window
  final sendResult = await a.sendCmd('send_message', params: {
    'to_peer_id': bId,
    'text': 'flap test',
  });

  // Should eventually deliver
  final aId = (await a.sendCmd('get_identity'))['peer_id'];
  await assertEventually(() async {
    final msgs = await b.sendCmd('get_messages', params: {'peer_id': aId});
    assert(msgs['messages'].any((m) => m['text'] == 'flap test'), 'Message delivered after flapping');
  }, label: 'delivery after flap', retries: 40, delay: const Duration(seconds: 3));

  // Assert no duplicates
  final msgs = await b.sendCmd('get_messages', params: {'peer_id': aId});
  final flapMsgs = msgs['messages'].where((m) => m['text'] == 'flap test').toList();
  assertEq(flapMsgs.length, 1, 'No duplicate messages');
}
```

---

## Part 4: Setup & Teardown

### 4.1 Full Setup Sequence

The orchestrator's `setup()` method reuses the existing scripts:

```
1. reset_simulators.sh              ← boot sims, install app with AUTO_SETUP_USERNAME
2. Wait 30s for identity generation
3. smoke_test_friends.sh             ← exchange contacts, introductions
4. Wait 120s for auto-accept to complete
5. For each device: sendCmd('ping')  ← verify command executor is alive
6. For each device: sendCmd('get_identity') ← cache peer IDs for tests
7. For each device: sendCmd('get_contacts') ← verify contacts exist
```

### 4.2 Per-Test Cleanup

Between tests, the orchestrator may need to:
- Clear result files from previous tests
- Verify devices are still responsive (`ping`)
- Wait for P2P reconnect if previous test toggled network

```dart
Future<void> betweenTests(List<DeviceHandle> devices) async {
  for (final d in devices) {
    // Ensure network is back on
    await d.setNetwork(enabled: true);
    // Clean stale result files
    await d.cleanResultFiles();
    // Verify alive
    await d.sendCmd('ping', timeout: const Duration(seconds: 10));
  }
  // Small settle time
  await Future.delayed(const Duration(seconds: 2));
}
```

### 4.3 Isolated Tests via Fresh Identities

Some tests (13.4 delete-and-re-add, 12.1 encryption upgrade) need a clean slate. For these, the orchestrator can:
1. Uninstall + reinstall on one simulator
2. Run `setup_device.dart` to provision a new identity
3. Re-exchange contacts via smoke_test_friends.sh flow

This is slow (~60s) so it's only used for tests that truly need fresh state.

---

## Part 5: What Cannot Be Automated (and Alternatives)

| Scenario | Why Not | Alternative |
|----------|---------|-------------|
| 7.x Push notification taps | Can't programmatically tap iOS system notifications | Test the routing logic via `prepare_notification_open_use_case` unit tests (already exist). Test push delivery by checking `wait_for_message` (the P2P path is identical). |
| 5.1 Lock phone | Can't lock simulator programmatically | Use `terminateApp()` as proxy (5.3 covers the harder case). |
| 8.x Visual stack card layout | Can't assert pixel-level UI from orchestrator | Assert DB state (`count_unread`, `get_feed_items`) — if the data is correct, UI rendering is covered by widget tests. |
| 16.4 Network Link Conditioner | Requires macOS system-level config, not per-simulator | Use `setNetwork(enabled: false)` + delays to approximate. Real slow-network testing remains manual. |
| 4.1 Emoji reactions (long-press UI) | No UI automation | Add `add_reaction` command that calls the use case directly (tests the logic, not the gesture). |

---

## Part 6: File Structure

```
flutter_app/
├── lib/core/debug/
│   ├── smoke_test_runner.dart          ← existing, unchanged
│   └── test_command_executor.dart      ← NEW: command loop + handlers
│
├── integration_test/e2e/
│   ├── orchestrator.dart               ← NEW: main CLI entry point
│   ├── device_handle.dart              ← NEW: per-device command/simctl wrapper
│   ├── assertions.dart                 ← NEW: assertEq, assertEventually, etc.
│   ├── test_runner.dart                ← NEW: run/report/JUnit output
│   │
│   ├── scenarios/
│   │   ├── contact_exchange_tests.dart ← tests 1.1-1.4
│   │   ├── messaging_tests.dart        ← tests 2.1-2.4
│   │   ├── media_tests.dart            ← tests 3.1-3.5
│   │   ├── interaction_tests.dart      ← tests 4.1-4.5
│   │   ├── reliability_tests.dart      ← tests 5.1-5.4
│   │   ├── offline_tests.dart          ← tests 6.1-6.5
│   │   ├── feed_tests.dart             ← tests 8.1-8.7
│   │   ├── introduction_tests.dart     ← tests I-1 through I-12
│   │   ├── group_tests.dart            ← tests 10.1-10.6
│   │   ├── race_condition_tests.dart   ← tests 14.1-14.9
│   │   ├── lifecycle_tests.dart        ← tests 15.1-15.4
│   │   └── network_fault_tests.dart    ← tests 16.1-16.4
│   │
│   └── README.md                       ← how to run
│
├── reset_simulators.sh                 ← existing
├── smoke_test_friends.sh               ← existing
└── run_e2e_suite.sh                    ← NEW: one-command entry point
```

---

## Part 7: One-Command Entry Point

**New file:** `run_e2e_suite.sh`

```bash
#!/bin/bash
set -euo pipefail

# Step 1: Reset simulators and install app with E2E_TEST_MODE
./reset_simulators.sh --dart-define=E2E_TEST_MODE=true

# Step 2: Wait for identity generation
sleep 30

# Step 3: Exchange contacts
./smoke_test_friends.sh

# Step 4: Wait for auto-accept
echo "Waiting 120s for auto-accept..."
sleep 120

# Step 5: Run orchestrator
dart run integration_test/e2e/orchestrator.dart \
  $DEVICE_A_UUID $DEVICE_B_UUID $DEVICE_C_UUID \
  "$@"
```

Usage:
```bash
# Run all tests
./run_e2e_suite.sh

# Run specific scenario
./run_e2e_suite.sh --filter "2.1"

# Run only messaging + offline tests
./run_e2e_suite.sh --filter "2.,6."
```

---

## Part 8: Implementation Sessions

### Session 1: Command Executor (on-device)
1. Create `lib/core/debug/test_command_executor.dart`
2. Implement command loop with file polling
3. Implement Phase 1 commands: `ping`, `get_identity`, `get_contacts`, `send_message`, `get_messages`, `get_message_status`, `wait_for_message`
4. Wire into `main.dart` behind `E2E_TEST_MODE` dart-define
5. Manual verification: boot one sim, write cmd.json by hand, verify result.json appears

### Session 2: Orchestrator Framework
1. Create `integration_test/e2e/device_handle.dart` — file I/O via simctl
2. Create `integration_test/e2e/assertions.dart`
3. Create `integration_test/e2e/test_runner.dart` — run, report, JUnit
4. Create `integration_test/e2e/orchestrator.dart` — CLI entry point
5. Verify: orchestrator sends `ping` to both sims, gets response

### Session 3: Core Test Scenarios
1. Implement `messaging_tests.dart` — tests 2.1, 2.2, 2.3
2. Implement `offline_tests.dart` — tests 6.1, 6.2
3. Implement `reliability_tests.dart` — test 5.2
4. Create `run_e2e_suite.sh`
5. End-to-end dry run: reset → exchange → run 5 tests → report

### Session 4: Contact & Introduction Commands
1. Add commands: `get_contact_requests`, `accept_contact_request`, `decline_contact_request`, `get_introductions`, `accept_introduction`, `pass_introduction`, `send_introduction`
2. Implement `contact_exchange_tests.dart` — tests 1.1-1.3
3. Implement `introduction_tests.dart` — tests I-1.1, I-2.1, I-3.1

### Session 5: Race Conditions & Network Faults
1. Implement `race_condition_tests.dart` — tests 14.1, 14.5
2. Implement `network_fault_tests.dart` — tests 16.1, 16.3
3. Implement `lifecycle_tests.dart` — test 15.1, 15.2

### Session 6: Feed, Groups, Media
1. Add commands: `get_feed_items`, `count_unread`, `create_group`, `send_group_message`, `send_image_message`
2. Implement `feed_tests.dart`, `group_tests.dart`, `media_tests.dart`

### Session 7: Polish
1. `--filter` flag for running subsets
2. JUnit XML output for CI integration
3. Timing report (which tests are slow)
4. Retry flaky tests once before failing

---

## Part 9: Extending for New Test Cases

When new scenarios are added to `50-two-simulator-user-journey-tests.md`:

1. **If the scenario uses existing commands** — just write a new test function in the appropriate `scenarios/*.dart` file and register it in `orchestrator.dart`

2. **If the scenario needs a new command** — add the handler to `test_command_executor.dart`, then use it from the scenario function

3. **If the scenario needs a new device action** (e.g., rotate device, change locale) — add a method to `DeviceHandle` using the appropriate `xcrun simctl` command

The command catalog is designed to grow. Each command is a small self-contained function that reads from repos/services and returns a JSON-serializable result. Adding a new one is ~10-20 lines of Dart.

---

## Test Case Coverage Matrix

Mapping each section in `50-two-simulator-user-journey-tests.md` to implementation session and automation approach:

| Section | Tests | Session | Approach |
|---------|-------|---------|----------|
| 1. Contact Exchange | 1.1-1.4 | 4 | Pre-bootstrapped contacts + command assertions |
| 2. Text Messaging | 2.1-2.4 | 3 | `send_message` + `get_messages` + `wait_for_message` |
| 3. Voice & Media | 3.1-3.5 | 6 | `send_voice/image/video_message` + file staging |
| 4. Message Interactions | 4.1-4.5 | 6 | `add_reaction`, `edit_message`, `delete_message` |
| 5. Reliability | 5.1-5.4 | 3 | `terminateApp` + `launchApp` + status checks |
| 6. Offline/Reconnect | 6.1-6.5 | 3 | `setNetwork(false)` + `wait_for_message` |
| 7. Push Notifications | 7.1-7.13 | — | **Not automatable** — logic covered by unit tests |
| 8. Feed/Stack Card | 8.1-8.7 | 6 | `get_feed_items` + `count_unread` |
| 9. Introduction | 9.1-9.5 | 4 | `send_introduction` + `accept/pass_introduction` |
| 10. Groups | 10.1-10.6 | 6 | `create_group` + `send_group_message` |
| 11. Posts | 11.1-11.5 | future | `create_post` + `get_posts` |
| 12. Encryption | 12.1-12.3 | 4 | Verify v1/v2 envelope via `get_messages` wire_envelope field |
| 13. Contact Management | 13.1-13.4 | 4 | `block/unblock/archive/delete_contact` |
| 14. Race Conditions | 14.1-14.9 | 5 | Concurrent `sendCmd` + `setNetwork` + `terminateApp` |
| 15. Lifecycle | 15.1-15.4 | 5 | `terminateApp`/`launchApp` cycling + message checks |
| 16. Network Faults | 16.1-16.4 | 5 | `setNetwork` toggling + delivery verification |
| 17. Startup Edge Cases | 17.1-17.3 | future | Uninstall/reinstall + identity restore |
| 18. Multi-Conversation | 18.1-18.2 | 3 | Multiple `send_message` + cross-conversation assertions |
| I-1 to I-12 Intros | ~50 tests | 4 | Three-sim orchestration + intro commands |
