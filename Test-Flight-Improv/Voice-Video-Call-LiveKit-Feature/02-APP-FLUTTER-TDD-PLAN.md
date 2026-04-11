# LiveKit Voice/Video Call — Flutter App TDD Plan

> Integration of LiveKit voice/video calling into the mknoon Flutter + Go app.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        Flutter App                          │
│                                                             │
│  ┌───────────┐   ┌─────────────┐   ┌────────────────────┐  │
│  │ CallWired │──►│ CallService │──►│ livekit_client SDK │  │
│  │ CallScreen│   │             │   │  (Room, Tracks)    │  │
│  └───────────┘   └──────┬──────┘   └────────┬───────────┘  │
│                         │                    │              │
│                         │ signaling          │ media        │
│                         ▼                    ▼              │
│  ┌──────────────────────────┐   ┌────────────────────────┐  │
│  │ P2PService (libp2p)     │   │ LiveKit Server (EC2)   │  │
│  │ call_signal messages    │   │ wss://lk.mknoon.xyz   │  │
│  └──────────────────────────┘   └────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────┐                               │
│  │ CallSignalListener      │  ← incoming call signals      │
│  │ (like ChatMessageListener)                               │
│  └──────────────────────────┘                               │
└─────────────────────────────────────────────────────────────┘
```

**Call Flow:**
1. Caller taps "Call" on a contact → `CallService.initiateCall(contact)`
2. `CallService` generates a room name (`call-<sortedPeerIds>`) and requests a LiveKit token from the EC2 token service
3. Caller sends a `call_signal` P2P message (type: `offer`, room name, token URL) via existing libp2p
4. `CallSignalListener` on receiver detects incoming call → shows incoming call UI / push notification
5. Receiver accepts → requests their own token → both connect to LiveKit room
6. LiveKit handles all media (audio/video, ICE, TURN, adaptive quality)
7. Either party hangs up → disconnect from LiveKit room → send `call_signal` (type: `hangup`)

---

## File Structure (New Files)

```
lib/
  features/
    call/
      domain/
        models/
          call_signal_model.dart          # CallSignal: offer/answer/reject/hangup/busy
          call_state.dart                 # CallState enum: idle/ringing/connecting/connected/ended
      data/
        repositories/
          call_token_repository.dart      # HTTP GET to token service
      application/
        call_service.dart                 # Manages call lifecycle + LiveKit room
        call_signal_listener.dart         # Listens for incoming call signals
        use_cases/
          initiate_call.dart              # Start outgoing call
          answer_call.dart                # Accept incoming call
          reject_call.dart                # Decline incoming call
          end_call.dart                   # Hang up active call
      presentation/
        screens/
          call_wired.dart                 # StatefulWidget — call state management
          call_screen.dart                # StatelessWidget — call UI
          incoming_call_wired.dart        # Incoming call overlay/screen
          incoming_call_screen.dart       # Incoming call UI (accept/reject)
        widgets/
          call_controls.dart              # Mute, speaker, video toggle, hangup buttons
          call_timer.dart                 # Duration display
          video_grid.dart                 # Video track renderers (1:1 or group)

test/
  features/
    call/
      domain/
        models/
          call_signal_model_test.dart
          call_state_test.dart
      data/
        repositories/
          call_token_repository_test.dart
      application/
        call_service_test.dart
        call_signal_listener_test.dart
        use_cases/
          initiate_call_test.dart
          answer_call_test.dart
          reject_call_test.dart
          end_call_test.dart
```

---

## Phase 1: Domain Models — TDD Steps

### Test 1.1: CallSignal model

```dart
// test/features/call/domain/models/call_signal_model_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/call/domain/models/call_signal_model.dart';

void main() {
  group('CallSignal', () {
    test('fromJson parses offer signal', () {
      final json = {
        'type': 'call_signal',
        'signal': 'offer',
        'roomName': 'call-12D3KooWA-12D3KooWB',
        'callId': 'uuid-123',
        'callerPeerId': '12D3KooWA',
        'callerName': 'Alice',
        'mediaType': 'audio',       // 'audio' or 'video'
        'timestamp': 1712764800000,
      };

      final signal = CallSignal.fromJson(json);

      expect(signal.signal, CallSignalType.offer);
      expect(signal.roomName, 'call-12D3KooWA-12D3KooWB');
      expect(signal.callId, 'uuid-123');
      expect(signal.callerPeerId, '12D3KooWA');
      expect(signal.mediaType, MediaType.audio);
    });

    test('fromJson parses answer signal', () {
      final json = {
        'type': 'call_signal',
        'signal': 'answer',
        'callId': 'uuid-123',
        'roomName': 'call-12D3KooWA-12D3KooWB',
      };

      final signal = CallSignal.fromJson(json);
      expect(signal.signal, CallSignalType.answer);
    });

    test('fromJson parses reject signal', () {
      final json = {
        'type': 'call_signal',
        'signal': 'reject',
        'callId': 'uuid-123',
        'reason': 'declined',
      };

      final signal = CallSignal.fromJson(json);
      expect(signal.signal, CallSignalType.reject);
      expect(signal.reason, 'declined');
    });

    test('fromJson parses hangup signal', () {
      final json = {
        'type': 'call_signal',
        'signal': 'hangup',
        'callId': 'uuid-123',
      };

      final signal = CallSignal.fromJson(json);
      expect(signal.signal, CallSignalType.hangup);
    });

    test('fromJson parses busy signal', () {
      final json = {
        'type': 'call_signal',
        'signal': 'busy',
        'callId': 'uuid-123',
      };

      final signal = CallSignal.fromJson(json);
      expect(signal.signal, CallSignalType.busy);
    });

    test('toJson produces valid envelope', () {
      final signal = CallSignal(
        signal: CallSignalType.offer,
        roomName: 'call-12D3KooWA-12D3KooWB',
        callId: 'uuid-123',
        callerPeerId: '12D3KooWA',
        callerName: 'Alice',
        mediaType: MediaType.audio,
        timestamp: 1712764800000,
      );

      final json = signal.toJson();

      expect(json['type'], 'call_signal');
      expect(json['signal'], 'offer');
      expect(json['roomName'], 'call-12D3KooWA-12D3KooWB');
    });

    test('toWireEnvelope wraps in v1 envelope', () {
      final signal = CallSignal(
        signal: CallSignalType.offer,
        roomName: 'call-room',
        callId: 'uuid-1',
        callerPeerId: '12D3KooWA',
        callerName: 'Alice',
        mediaType: MediaType.audio,
        timestamp: 1712764800000,
      );

      final envelope = signal.toWireEnvelope();

      expect(envelope['type'], 'call_signal');
      expect(envelope['version'], '1');
      expect(envelope['payload'], isA<Map>());
    });
  });
}
```

```dart
// lib/features/call/domain/models/call_signal_model.dart

enum CallSignalType { offer, answer, reject, hangup, busy }
enum MediaType { audio, video }

class CallSignal {
  final CallSignalType signal;
  final String callId;
  final String? roomName;
  final String? callerPeerId;
  final String? callerName;
  final MediaType? mediaType;
  final int? timestamp;
  final String? reason;

  CallSignal({
    required this.signal,
    required this.callId,
    this.roomName,
    this.callerPeerId,
    this.callerName,
    this.mediaType,
    this.timestamp,
    this.reason,
  });

  factory CallSignal.fromJson(Map<String, dynamic> json) { /* ... */ }
  Map<String, dynamic> toJson() { /* ... */ }
  Map<String, dynamic> toWireEnvelope() { /* ... */ }
}
```

**Red:** Model class doesn't exist.
**Green:** All serialization tests pass.

---

### Test 1.2: CallState enum and transitions

```dart
// test/features/call/domain/models/call_state_test.dart

void main() {
  group('CallState', () {
    test('initial state is idle', () {
      final state = CallStateData.idle();
      expect(state.status, CallStatus.idle);
      expect(state.contact, isNull);
      expect(state.callId, isNull);
    });

    test('ringing state has contact and callId', () {
      final state = CallStateData.ringing(
        contact: mockContact,
        callId: 'uuid-1',
        isOutgoing: true,
        mediaType: MediaType.audio,
      );
      expect(state.status, CallStatus.ringing);
      expect(state.isOutgoing, true);
    });

    test('connecting state', () {
      final state = CallStateData.connecting(
        contact: mockContact,
        callId: 'uuid-1',
        roomName: 'call-room',
        mediaType: MediaType.audio,
      );
      expect(state.status, CallStatus.connecting);
      expect(state.roomName, 'call-room');
    });

    test('connected state has start time', () {
      final state = CallStateData.connected(
        contact: mockContact,
        callId: 'uuid-1',
        roomName: 'call-room',
        mediaType: MediaType.audio,
        startTime: DateTime.now(),
      );
      expect(state.status, CallStatus.connected);
      expect(state.startTime, isNotNull);
    });

    test('ended state has reason', () {
      final state = CallStateData.ended(reason: CallEndReason.hungUp);
      expect(state.status, CallStatus.ended);
    });
  });
}
```

```dart
// lib/features/call/domain/models/call_state.dart

enum CallStatus { idle, ringing, connecting, connected, ended }
enum CallEndReason { hungUp, rejected, busy, timeout, error, missed }

class CallStateData {
  final CallStatus status;
  final ContactModel? contact;
  final String? callId;
  final String? roomName;
  final MediaType? mediaType;
  final bool isOutgoing;
  final DateTime? startTime;
  final CallEndReason? endReason;

  // Named constructors for each state...
}
```

**Red:** Model doesn't exist.
**Green:** All state tests pass.

---

## Phase 2: Token Repository — TDD Steps

### Test 2.1: CallTokenRepository fetches token from server

```dart
// test/features/call/data/repositories/call_token_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

void main() {
  group('CallTokenRepository', () {
    test('getToken returns JWT on success', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/token');
        expect(request.url.queryParameters['room'], 'call-room-1');
        expect(request.url.queryParameters['identity'], 'peer-alice');
        expect(request.headers['Authorization'], 'Bearer app-secret');

        return http.Response('{"token": "eyJ.test.jwt"}', 200);
      });

      final repo = CallTokenRepository(
        baseUrl: 'https://lk.mknoon.xyz',
        appSecret: 'app-secret',
        httpClient: mockClient,
      );

      final token = await repo.getToken(room: 'call-room-1', identity: 'peer-alice');
      expect(token, 'eyJ.test.jwt');
    });

    test('getToken throws on 401', () async {
      final mockClient = MockClient((request) async {
        return http.Response('unauthorized', 401);
      });

      final repo = CallTokenRepository(
        baseUrl: 'https://lk.mknoon.xyz',
        appSecret: 'wrong-secret',
        httpClient: mockClient,
      );

      expect(
        () => repo.getToken(room: 'room', identity: 'id'),
        throwsA(isA<CallTokenException>()),
      );
    });

    test('getToken throws on network error', () async {
      final mockClient = MockClient((request) async {
        throw http.ClientException('Network error');
      });

      final repo = CallTokenRepository(
        baseUrl: 'https://lk.mknoon.xyz',
        appSecret: 'secret',
        httpClient: mockClient,
      );

      expect(
        () => repo.getToken(room: 'room', identity: 'id'),
        throwsA(isA<CallTokenException>()),
      );
    });

    test('getToken uses correct URL format', () async {
      String? capturedUrl;
      final mockClient = MockClient((request) async {
        capturedUrl = request.url.toString();
        return http.Response('{"token": "jwt"}', 200);
      });

      final repo = CallTokenRepository(
        baseUrl: 'https://lk.mknoon.xyz',
        appSecret: 'secret',
        httpClient: mockClient,
      );

      await repo.getToken(room: 'call-abc', identity: 'peer-xyz');
      expect(capturedUrl, contains('lk.mknoon.xyz'));
      expect(capturedUrl, contains('room=call-abc'));
      expect(capturedUrl, contains('identity=peer-xyz'));
    });
  });
}
```

```dart
// lib/features/call/data/repositories/call_token_repository.dart

class CallTokenException implements Exception {
  final String message;
  CallTokenException(this.message);
}

class CallTokenRepository {
  final String baseUrl;
  final String appSecret;
  final http.Client httpClient;

  CallTokenRepository({
    required this.baseUrl,
    required this.appSecret,
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client();

  Future<String> getToken({required String room, required String identity}) async {
    // GET $baseUrl/token?room=$room&identity=$identity
    // Header: Authorization: Bearer $appSecret
    // Returns: {"token": "eyJ..."}
  }
}
```

**Red:** Repository doesn't exist.
**Green:** All HTTP tests pass.

---

## Phase 3: Call Signal Listener — TDD Steps

### Test 3.1: CallSignalListener processes incoming offer

> **Architecture note:** `CallSignalListener` receives a typed `Stream<ChatMessage>` from
> `IncomingMessageRouter.callSignalStream` — NOT from `p2pService.messageStream` directly.
> The router already filters `isIncoming` and routes by `type` field. This matches the pattern
> used by `ChatMessageListener`, `GroupInviteListener`, `ReactionListener`, etc.
> The listener must NOT subscribe to the raw P2P stream or hold a reference to `P2PService`/`IncomingMessageRouter`.

```dart
// test/features/call/application/call_signal_listener_test.dart

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CallSignalListener', () {
    late StreamController<ChatMessage> callSignalStreamController;
    late CallSignalListener listener;

    setUp(() {
      // This simulates messageRouter.callSignalStream — already filtered to call_signal type only
      callSignalStreamController = StreamController<ChatMessage>.broadcast();
      listener = CallSignalListener(
        callSignalStream: callSignalStreamController.stream,
      );
      listener.start();
    });

    tearDown(() {
      listener.dispose();
      callSignalStreamController.close();
    });

    test('emits CallSignal on incoming offer', () async {
      final completer = Completer<CallSignal>();
      listener.incomingCallStream.listen((signal) {
        completer.complete(signal);
      });

      // Simulate incoming P2P message with call_signal type
      callSignalStreamController.add(ChatMessage(
        from: '12D3KooWA',
        isIncoming: true,
        body: jsonEncode({
          'type': 'call_signal',
          'version': '1',
          'payload': {
            'signal': 'offer',
            'callId': 'uuid-1',
            'roomName': 'call-room',
            'callerPeerId': '12D3KooWA',
            'callerName': 'Alice',
            'mediaType': 'audio',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          },
        }),
      ));

      final signal = await completer.future.timeout(Duration(seconds: 2));
      expect(signal.signal, CallSignalType.offer);
      expect(signal.callerPeerId, '12D3KooWA');
      expect(signal.roomName, 'call-room');
    });

    test('ignores outgoing messages', () async {
      var received = false;
      listener.incomingCallStream.listen((_) => received = true);

      callSignalStreamController.add(ChatMessage(
        from: '12D3KooWA',
        isIncoming: false, // outgoing — should be ignored
        body: jsonEncode({
          'type': 'call_signal',
          'version': '1',
          'payload': {'signal': 'offer', 'callId': 'uuid-1'},
        }),
      ));

      await Future.delayed(Duration(milliseconds: 100));
      expect(received, false);
    });

    test('emits hangup signal', () async {
      final completer = Completer<CallSignal>();
      listener.incomingCallStream.listen((signal) {
        completer.complete(signal);
      });

      callSignalStreamController.add(ChatMessage(
        from: '12D3KooWA',
        isIncoming: true,
        body: jsonEncode({
          'type': 'call_signal',
          'version': '1',
          'payload': {'signal': 'hangup', 'callId': 'uuid-1'},
        }),
      ));

      final signal = await completer.future.timeout(Duration(seconds: 2));
      expect(signal.signal, CallSignalType.hangup);
    });

    test('handles malformed messages gracefully', () async {
      // Should not throw — just log and skip
      callSignalStreamController.add(ChatMessage(
        from: '12D3KooWA',
        isIncoming: true,
        body: 'not valid json',
      ));

      await Future.delayed(Duration(milliseconds: 100));
      // No crash — listener still alive
      expect(listener.isActive, true);
    });
  });
}
```

```dart
// lib/features/call/application/call_signal_listener.dart

class CallSignalListener {
  final Stream<ChatMessage> callSignalStream;
  final _incomingCallController = StreamController<CallSignal>.broadcast();

  StreamSubscription? _subscription;

  CallSignalListener({required this.callSignalStream});

  Stream<CallSignal> get incomingCallStream => _incomingCallController.stream;
  bool get isActive => _subscription != null;

  void start() {
    _subscription = callSignalStream
        .where((msg) => msg.isIncoming)
        .listen(_onMessage);
  }

  void _onMessage(ChatMessage message) {
    // Parse envelope → extract payload → CallSignal.fromJson
    // Emit on _incomingCallController
    // Log with emitFlowEvent
  }

  void dispose() {
    _subscription?.cancel();
    _incomingCallController.close();
  }
}
```

**Red:** Listener doesn't exist.
**Green:** All listener tests pass.

---

### Test 3.2: IncomingMessageRouter routes call_signal type

> **This is the key integration point.** The existing `IncomingMessageRouter` (at
> `lib/core/services/incoming_message_router.dart`) has a `_route()` method with a switch
> on `json['type']`. It currently handles 17 message types. Adding `call_signal` requires:
> 1. A new `_callSignalController = StreamController<ChatMessage>.broadcast()`
> 2. A new `Stream<ChatMessage> get callSignalStream => _callSignalController.stream`
> 3. A new `case 'call_signal': _callSignalController.add(message);` in the switch
> 4. Close `_callSignalController` in `dispose()`

```dart
// test/core/services/incoming_message_router_call_signal_test.dart

void main() {
  test('routes call_signal type to callSignalStream', () async {
    final router = IncomingMessageRouter(p2pService: mockP2PService);
    final completer = Completer<ChatMessage>();

    router.callSignalStream.listen((msg) => completer.complete(msg));
    router.start();

    // Inject a message with type: call_signal
    mockP2PService.emitMessage(ChatMessage(
      from: 'peer-a',
      isIncoming: true,
      body: jsonEncode({
        'type': 'call_signal',
        'version': '1',
        'payload': {'signal': 'offer', 'callId': 'uuid-1'},
      }),
    ));

    final msg = await completer.future.timeout(Duration(seconds: 2));
    expect(msg.from, 'peer-a');
  });

  test('does not route call_signal to chatMessageStream', () async {
    final router = IncomingMessageRouter(p2pService: mockP2PService);
    var received = false;
    router.chatMessageStream.listen((_) => received = true);
    router.start();

    mockP2PService.emitMessage(ChatMessage(
      from: 'peer-a',
      isIncoming: true,
      body: jsonEncode({
        'type': 'call_signal',
        'version': '1',
        'payload': {'signal': 'offer', 'callId': 'uuid-1'},
      }),
    ));

    await Future.delayed(Duration(milliseconds: 100));
    expect(received, false);
  });
}
```

**Files to modify:**
- `lib/core/services/incoming_message_router.dart` — add `_callSignalController`, `callSignalStream` getter, `'call_signal'` case in `_route()`, close in `dispose()`

---

## Phase 4: CallService — TDD Steps

### Test 4.1: initiateCall creates room and sends offer

```dart
// test/features/call/application/call_service_test.dart

void main() {
  late CallService callService;
  late MockP2PService mockP2PService;
  late MockCallTokenRepository mockTokenRepo;
  late MockIdentityRepository mockIdentityRepo;

  setUp(() {
    mockP2PService = MockP2PService();
    mockTokenRepo = MockCallTokenRepository();
    mockIdentityRepo = MockIdentityRepository();

    // Mock identity
    when(mockIdentityRepo.getIdentity()).thenAnswer((_) async =>
      IdentityModel(peerId: '12D3KooWA', username: 'Alice'));

    // Mock token
    when(mockTokenRepo.getToken(room: anyNamed('room'), identity: anyNamed('identity')))
        .thenAnswer((_) async => 'mock-jwt-token');

    callService = CallService(
      p2pService: mockP2PService,
      tokenRepository: mockTokenRepo,
      identityRepository: mockIdentityRepo,
    );
  });

  group('initiateCall', () {
    test('transitions state: idle → ringing', () async {
      final states = <CallStatus>[];
      callService.stateStream.listen((s) => states.add(s.status));

      await callService.initiateCall(
        contact: ContactModel(peerId: '12D3KooWB', username: 'Bob'),
        mediaType: MediaType.audio,
      );

      expect(states, contains(CallStatus.ringing));
    });

    test('sends offer signal via P2P', () async {
      await callService.initiateCall(
        contact: ContactModel(peerId: '12D3KooWB', username: 'Bob'),
        mediaType: MediaType.audio,
      );

      verify(mockP2PService.sendMessage(
        '12D3KooWB',
        argThat(contains('"signal":"offer"')),
      )).called(1);
    });

    test('room name uses sorted peer IDs', () async {
      await callService.initiateCall(
        contact: ContactModel(peerId: '12D3KooWB', username: 'Bob'),
        mediaType: MediaType.audio,
      );

      // Peer IDs sorted: 12D3KooWA < 12D3KooWB
      final captured = verify(mockP2PService.sendMessage(
        any, captureAny,
      )).captured.last as String;

      expect(captured, contains('call-12D3KooWA-12D3KooWB'));
    });

    test('generates unique callId', () async {
      await callService.initiateCall(
        contact: ContactModel(peerId: '12D3KooWB', username: 'Bob'),
        mediaType: MediaType.audio,
      );

      final captured = verify(mockP2PService.sendMessage(
        any, captureAny,
      )).captured.last as String;

      final decoded = jsonDecode(captured);
      expect(decoded['payload']['callId'], isNotEmpty);
    });

    test('throws if already in a call', () async {
      await callService.initiateCall(
        contact: ContactModel(peerId: '12D3KooWB', username: 'Bob'),
        mediaType: MediaType.audio,
      );

      expect(
        () => callService.initiateCall(
          contact: ContactModel(peerId: '12D3KooWC', username: 'Carol'),
          mediaType: MediaType.audio,
        ),
        throwsA(isA<CallAlreadyActiveException>()),
      );
    });
  });
}
```

---

### Test 4.2: answerCall connects to LiveKit room

```dart
  group('answerCall', () {
    test('fetches token and transitions to connecting', () async {
      final states = <CallStatus>[];
      callService.stateStream.listen((s) => states.add(s.status));

      // Simulate incoming offer
      callService.handleIncomingSignal(CallSignal(
        signal: CallSignalType.offer,
        callId: 'uuid-1',
        roomName: 'call-room',
        callerPeerId: '12D3KooWB',
        callerName: 'Bob',
        mediaType: MediaType.audio,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));

      await callService.answerCall();

      expect(states, containsAllInOrder([
        CallStatus.ringing,
        CallStatus.connecting,
      ]));
      verify(mockTokenRepo.getToken(
        room: 'call-room',
        identity: '12D3KooWA',
      )).called(1);
    });

    test('sends answer signal via P2P', () async {
      callService.handleIncomingSignal(CallSignal(
        signal: CallSignalType.offer,
        callId: 'uuid-1',
        roomName: 'call-room',
        callerPeerId: '12D3KooWB',
        callerName: 'Bob',
        mediaType: MediaType.audio,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));

      await callService.answerCall();

      verify(mockP2PService.sendMessage(
        '12D3KooWB',
        argThat(contains('"signal":"answer"')),
      )).called(1);
    });

    test('throws if no incoming call', () {
      expect(
        () => callService.answerCall(),
        throwsA(isA<NoIncomingCallException>()),
      );
    });
  });
```

---

### Test 4.3: rejectCall sends reject signal

```dart
  group('rejectCall', () {
    test('sends reject signal and returns to idle', () async {
      final states = <CallStatus>[];
      callService.stateStream.listen((s) => states.add(s.status));

      callService.handleIncomingSignal(CallSignal(
        signal: CallSignalType.offer,
        callId: 'uuid-1',
        roomName: 'call-room',
        callerPeerId: '12D3KooWB',
        callerName: 'Bob',
        mediaType: MediaType.audio,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));

      await callService.rejectCall();

      verify(mockP2PService.sendMessage(
        '12D3KooWB',
        argThat(contains('"signal":"reject"')),
      )).called(1);

      expect(states.last, CallStatus.idle);
    });
  });
```

---

### Test 4.4: endCall disconnects LiveKit and sends hangup

```dart
  group('endCall', () {
    test('disconnects from LiveKit room', () async {
      // Setup: get into connected state
      await callService.initiateCall(
        contact: ContactModel(peerId: '12D3KooWB', username: 'Bob'),
        mediaType: MediaType.audio,
      );
      // Simulate answer received → connected
      callService.handleIncomingSignal(CallSignal(
        signal: CallSignalType.answer,
        callId: callService.currentCallId!,
      ));

      await callService.endCall();

      // Verify LiveKit room disconnected
      verify(mockRoom.disconnect()).called(1);
    });

    test('sends hangup signal to peer', () async {
      await callService.initiateCall(
        contact: ContactModel(peerId: '12D3KooWB', username: 'Bob'),
        mediaType: MediaType.audio,
      );
      callService.handleIncomingSignal(CallSignal(
        signal: CallSignalType.answer,
        callId: callService.currentCallId!,
      ));

      await callService.endCall();

      verify(mockP2PService.sendMessage(
        '12D3KooWB',
        argThat(contains('"signal":"hangup"')),
      )).called(1);
    });

    test('transitions to ended then idle', () async {
      final states = <CallStatus>[];
      callService.stateStream.listen((s) => states.add(s.status));

      await callService.initiateCall(
        contact: ContactModel(peerId: '12D3KooWB', username: 'Bob'),
        mediaType: MediaType.audio,
      );
      callService.handleIncomingSignal(CallSignal(
        signal: CallSignalType.answer,
        callId: callService.currentCallId!,
      ));

      await callService.endCall();

      expect(states, containsAllInOrder([
        CallStatus.ended,
        CallStatus.idle,
      ]));
    });
  });
```

---

### Test 4.5: Busy signal when already in a call

```dart
  group('busy handling', () {
    test('auto-sends busy when receiving offer while in call', () async {
      // Already in a call
      await callService.initiateCall(
        contact: ContactModel(peerId: '12D3KooWB', username: 'Bob'),
        mediaType: MediaType.audio,
      );

      // Another person calls
      callService.handleIncomingSignal(CallSignal(
        signal: CallSignalType.offer,
        callId: 'uuid-other',
        callerPeerId: '12D3KooWC',
        callerName: 'Carol',
        roomName: 'call-other',
        mediaType: MediaType.audio,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));

      verify(mockP2PService.sendMessage(
        '12D3KooWC',
        argThat(contains('"signal":"busy"')),
      )).called(1);
    });
  });
```

---

### Test 4.6: Call timeout (no answer after 30s)

```dart
  group('timeout', () {
    test('outgoing call times out after 30 seconds', () {
      fakeAsync((async) {
        final states = <CallStatus>[];
        callService.stateStream.listen((s) => states.add(s.status));

        callService.initiateCall(
          contact: ContactModel(peerId: '12D3KooWB', username: 'Bob'),
          mediaType: MediaType.audio,
        );

        // Advance 30 seconds with no answer
        async.elapse(Duration(seconds: 30));

        expect(states, contains(CallStatus.ended));
        expect(callService.currentState.endReason, CallEndReason.timeout);
      });
    });
  });
```

---

### Test 4.7: CallService LiveKit room event handling

```dart
  group('LiveKit room events', () {
    test('transitions to connected when remote participant joins', () async {
      final states = <CallStatus>[];
      callService.stateStream.listen((s) => states.add(s.status));

      await callService.initiateCall(
        contact: ContactModel(peerId: '12D3KooWB', username: 'Bob'),
        mediaType: MediaType.audio,
      );

      // Simulate answer → connecting → LiveKit connected
      callService.handleIncomingSignal(CallSignal(
        signal: CallSignalType.answer,
        callId: callService.currentCallId!,
      ));

      // Simulate LiveKit ParticipantConnectedEvent
      callService.onParticipantConnected('12D3KooWB');

      expect(states, contains(CallStatus.connected));
    });

    test('ends call when remote participant disconnects', () async {
      // Get to connected state...
      // Simulate LiveKit ParticipantDisconnectedEvent
      callService.onParticipantDisconnected('12D3KooWB');

      expect(callService.currentState.status, CallStatus.ended);
      expect(callService.currentState.endReason, CallEndReason.hungUp);
    });

    test('handles LiveKit reconnecting event', () async {
      // Get to connected state...
      // Simulate RoomReconnectingEvent
      callService.onReconnecting();
      // Should NOT end the call — just update UI
      expect(callService.currentState.status, CallStatus.connected);
      expect(callService.currentState.isReconnecting, true);
    });
  });
```

---

## Phase 5: Use Cases — TDD Steps

> **Pattern:** All use cases in this codebase are **top-level functions**, never classes.
> The `emitFlowEvent` convention uses `layer: 'UC'` for use cases and `layer: 'FL'` for listeners.

### Test 5.1: initiateCall use case

```dart
// test/features/call/application/use_cases/initiate_call_test.dart

void main() {
  test('initiateCall orchestrates CallService', () async {
    final callService = MockCallService();
    final contact = ContactModel(peerId: '12D3KooWB', username: 'Bob',
      publicKey: 'pk', rendezvous: '/ip4/...', signature: 'sig', scannedAt: '2026-01-01');

    await initiateCall(
      callService: callService,
      contact: contact,
      mediaType: MediaType.audio,
    );

    verify(callService.initiateCall(
      contact: contact,
      mediaType: MediaType.audio,
    )).called(1);
  });
}
```

```dart
// lib/features/call/application/use_cases/initiate_call.dart

// Top-level function — NOT a class. Matches codebase convention.
Future<void> initiateCall({
  required CallService callService,
  required ContactModel contact,
  required MediaType mediaType,
}) async {
  emitFlowEvent(layer: 'UC', event: 'INITIATE_CALL_START', details: {
    'peerId': contact.peerId,
    'mediaType': mediaType.name,
  });
  await callService.initiateCall(contact: contact, mediaType: mediaType);
}
```

Same pattern for `answerCall`, `rejectCall`, `endCall` use cases — all top-level functions with `emitFlowEvent(layer: 'UC', ...)`.

---

## Phase 6: Platform Configuration — TDD Steps

### Test 6.1: iOS permissions

> **Current state of Info.plist:**
> - `NSMicrophoneUsageDescription` exists but says "record voice messages" — must be updated to cover calls
> - `NSCameraUsageDescription` exists but says "profile photos and QR codes" — must be updated to cover video calls
> - `UIBackgroundModes` currently has `fetch` and `remote-notification` only — must add `audio` (required for LiveKit background audio)

```xml
<!-- ios/Runner/Info.plist — UPDATE existing entries (not add new ones) -->

<!-- UPDATE existing description to cover both voice messages AND calls -->
<key>NSCameraUsageDescription</key>
<string>mknoon needs camera access for video calls, profile photos, and QR code scanning</string>
<key>NSMicrophoneUsageDescription</key>
<string>mknoon needs microphone access for voice calls, video calls, and voice messages</string>

<!-- UPDATE existing UIBackgroundModes — add 'audio' to the existing array -->
<key>UIBackgroundModes</key>
<array>
  <string>fetch</string>
  <string>remote-notification</string>
  <string>audio</string>           <!-- NEW: required for LiveKit background call audio -->
</array>
```

> **Note:** Adding `voip` to UIBackgroundModes is only needed if using CallKit/PushKit for
> VoIP push notifications. For the initial implementation (P2P signaling + FCM), `audio` alone
> is sufficient. CallKit integration can be added in a future phase.

**Test:** Build app → check Info.plist has updated descriptions and `audio` in UIBackgroundModes.
**Verify:** iOS deployment target >= 12.1 (LiveKit minimum). Currently 13.0 — OK.

---

### Test 6.2: Android permissions

> **Current state:** `CAMERA`, `RECORD_AUDIO`, and `INTERNET` already exist in AndroidManifest.xml.
> The following need to be **added** (not duplicated):

```xml
<!-- android/app/src/main/AndroidManifest.xml — ADD these (CAMERA/RECORD_AUDIO already exist) -->
<uses-feature android:name="android.hardware.camera" android:required="false" />
<uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<!-- BLUETOOTH_CONNECT is REQUIRED on Android 12+ (API 31+) for Bluetooth audio routing -->
<!-- Without it, SecurityException is thrown when routing audio to BT headsets -->
```

**Test:** Build APK → verify permissions in merged manifest. Verify on Android 12+ device that Bluetooth headset routing works during a call.

---

### Test 6.3: pubspec.yaml dependencies

> **Current state:** None of these packages exist in `pubspec.yaml`. All three must be added.
> The `http` package is NOT a transitive dependency — it must be explicitly declared.

```yaml
dependencies:
  livekit_client: ^2.7.0       # LiveKit Flutter SDK (WebRTC, Room management)
  permission_handler: ^11.0.0  # Runtime permission requests for camera/mic/bluetooth
  http: ^1.2.0                 # HTTP client for token service API calls
```

> **Note:** `livekit_client` requires Flutter >= 3.27.0 (Dart >= 3.6.0). Verify the current
> Flutter SDK version in the CI pipeline. The `permission_handler` package is needed because
> `livekit_client` does NOT handle camera/mic permission requests itself — the app must
> request permissions before enabling tracks.

**Test:** `flutter pub get` succeeds, no version conflicts.

---

## Phase 7: DI Wiring — TDD Steps

### Test 7.1: CallService wired in main.dart

> **Important:** `MyApp` is defined at the bottom of `lib/main.dart` (not in a separate `app.dart`).
> The `startLiveServices()` function (around line 1473) calls `.start()` on every listener in
> sequence. `CallSignalListener.start()` must be added here.
>
> **DI threading chain:** `main.dart → MyApp → StartupRouter → FeedWired → OrbitWired → ConversationWired`
> Every widget that needs `callService` must have it threaded through its constructor.

```dart
// Changes to lib/main.dart (pseudocode for the wiring)

// After P2PServiceImpl construction:
final callTokenRepository = CallTokenRepository(
  baseUrl: 'https://lk.mknoon.xyz',
  appSecret: await secureKeyStore.read('livekit_app_secret') ?? '',
);

final callService = CallService(
  p2pService: p2pService,
  tokenRepository: callTokenRepository,
  identityRepository: identityRepository,
);

// IncomingMessageRouter already has callSignalStream (added in Phase 3.2)
// Wire CallSignalListener:
final callSignalListener = CallSignalListener(
  callSignalStream: messageRouter.callSignalStream,
);

// Connect listener to service:
callSignalListener.incomingCallStream.listen((signal) {
  callService.handleIncomingSignal(signal);
});

// In startLiveServices() — add alongside other .start() calls:
callSignalListener.start();

// Thread through to MyApp (defined at bottom of main.dart):
runApp(MyApp(
  // ...existing params...
  callService: callService,
));
```

**Files to modify:**
- `lib/main.dart` — construct CallTokenRepository, CallService, CallSignalListener (MyApp is defined here, not in a separate `app.dart`)
- `lib/core/services/incoming_message_router.dart` — add `_callSignalController`, `callSignalStream` getter, and `'call_signal'` case in `_route()`
- `lib/main.dart` (MyApp class, defined at bottom of main.dart) — add `callService` parameter
- `lib/features/identity/presentation/startup_router.dart` — thread `callService` to FeedWired
- `lib/features/orbit/presentation/screens/orbit_wired.dart` — thread `callService`
- `lib/features/conversation/presentation/screens/conversation_wired.dart` — add `callService`, wire call button callback
- `lib/features/conversation/presentation/screens/conversation_screen.dart` — add `onCall` callback prop
- `lib/features/conversation/presentation/widgets/conversation_header.dart` — add call icon button (this is a custom widget with `Row`, NOT a Flutter AppBar)

---

## Phase 8: UI — TDD Steps

### Test 8.1: CallScreen renders correctly for each state

```dart
// test/features/call/presentation/screens/call_screen_test.dart

void main() {
  group('CallScreen', () {
    testWidgets('shows contact name and "Calling..." for ringing state', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CallScreen(
          state: CallStateData.ringing(
            contact: ContactModel(peerId: 'p', username: 'Bob'),
            callId: 'uuid-1',
            isOutgoing: true,
            mediaType: MediaType.audio,
          ),
          onEndCall: () {},
          onToggleMute: () {},
          onToggleSpeaker: () {},
          onToggleVideo: () {},
        ),
      ));

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Calling...'), findsOneWidget);
      expect(find.byIcon(Icons.call_end), findsOneWidget);
    });

    testWidgets('shows accept/reject for incoming ringing', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CallScreen(
          state: CallStateData.ringing(
            contact: ContactModel(peerId: 'p', username: 'Alice'),
            callId: 'uuid-1',
            isOutgoing: false,
            mediaType: MediaType.audio,
          ),
          onAnswerCall: () {},
          onRejectCall: () {},
          onEndCall: () {},
          onToggleMute: () {},
          onToggleSpeaker: () {},
          onToggleVideo: () {},
        ),
      ));

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Incoming call...'), findsOneWidget);
      // Accept (green) and reject (red) buttons
      expect(find.byIcon(Icons.call), findsOneWidget);
      expect(find.byIcon(Icons.call_end), findsOneWidget);
    });

    testWidgets('shows timer for connected state', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CallScreen(
          state: CallStateData.connected(
            contact: ContactModel(peerId: 'p', username: 'Bob'),
            callId: 'uuid-1',
            roomName: 'room',
            mediaType: MediaType.audio,
            startTime: DateTime.now(),
          ),
          onEndCall: () {},
          onToggleMute: () {},
          onToggleSpeaker: () {},
          onToggleVideo: () {},
        ),
      ));

      expect(find.text('Bob'), findsOneWidget);
      expect(find.byType(CallTimer), findsOneWidget);
      expect(find.byIcon(Icons.call_end), findsOneWidget);
      expect(find.byIcon(Icons.mic_off), findsOneWidget);
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
    });

    testWidgets('shows video renderers for video call', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CallScreen(
          state: CallStateData.connected(
            contact: ContactModel(peerId: 'p', username: 'Bob'),
            callId: 'uuid-1',
            roomName: 'room',
            mediaType: MediaType.video,
            startTime: DateTime.now(),
          ),
          localVideoTrack: mockLocalVideoTrack,
          remoteVideoTrack: mockRemoteVideoTrack,
          onEndCall: () {},
          onToggleMute: () {},
          onToggleSpeaker: () {},
          onToggleVideo: () {},
        ),
      ));

      expect(find.byType(VideoTrackRenderer), findsNWidgets(2));
    });

    testWidgets('shows "Call Ended" for ended state', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CallScreen(
          state: CallStateData.ended(reason: CallEndReason.hungUp),
          onEndCall: () {},
          onToggleMute: () {},
          onToggleSpeaker: () {},
          onToggleVideo: () {},
        ),
      ));

      expect(find.text('Call Ended'), findsOneWidget);
    });
  });
}
```

---

### Test 8.2: CallWired manages state and LiveKit lifecycle

```dart
// test/features/call/presentation/screens/call_wired_test.dart

void main() {
  group('CallWired', () {
    testWidgets('subscribes to callService.stateStream on init', (tester) async {
      final mockCallService = MockCallService();
      when(mockCallService.stateStream).thenAnswer(
        (_) => Stream.value(CallStateData.idle()),
      );

      await tester.pumpWidget(MaterialApp(
        home: CallWired(
          callService: mockCallService,
          contact: ContactModel(peerId: 'p', username: 'Bob'),
          mediaType: MediaType.audio,
        ),
      ));

      verify(mockCallService.stateStream).called(greaterThanOrEqualTo(1));
    });

    testWidgets('calls endCall on hangup button tap', (tester) async {
      final mockCallService = MockCallService();
      when(mockCallService.stateStream).thenAnswer(
        (_) => Stream.value(CallStateData.connected(
          contact: ContactModel(peerId: 'p', username: 'Bob'),
          callId: 'uuid-1',
          roomName: 'room',
          mediaType: MediaType.audio,
          startTime: DateTime.now(),
        )),
      );
      when(mockCallService.currentState).thenReturn(/* connected state */);

      await tester.pumpWidget(MaterialApp(
        home: CallWired(
          callService: mockCallService,
          contact: ContactModel(peerId: 'p', username: 'Bob'),
          mediaType: MediaType.audio,
        ),
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.call_end));
      verify(mockCallService.endCall()).called(1);
    });

    testWidgets('toggles mute', (tester) async {
      // Tap mute button → verify callService.toggleMute() called
    });

    testWidgets('toggles speaker', (tester) async {
      // Tap speaker button → verify callService.toggleSpeaker() called
    });

    testWidgets('pops screen on call ended', (tester) async {
      // When state transitions to ended → screen auto-pops after 2s
    });

    testWidgets('disposes LiveKit resources on widget dispose', (tester) async {
      // Verify callService.endCall() called when widget is disposed
    });
  });
}
```

---

### Test 8.3: Call button on ConversationHeader

> **Architecture note:** The conversation screen does NOT use a Flutter `AppBar`. It uses a
> custom `ConversationHeader` widget (`lib/features/conversation/presentation/widgets/conversation_header.dart`)
> built with `BackdropFilter` + `Container` + `Row`. The header currently has: back button,
> UserAvatar, username text, connection date, and an overflow button (`Icons.more_vert`).
> A call icon must be added to the `Row` alongside the overflow button.

```dart
// test — verify call button appears in conversation header

testWidgets('conversation header shows call button', (tester) async {
  // Render ConversationScreen with a contact
  // Verify IconButton with Icons.call exists in ConversationHeader Row
  // Tap it → verify onCall callback is invoked
});

testWidgets('tapping call button navigates to CallWired', (tester) async {
  // Render ConversationWired with callService
  // Tap call icon in ConversationHeader
  // Verify navigation push to CallWired
});
```

**Files to modify:**
- `lib/features/conversation/presentation/widgets/conversation_header.dart` — add `VoidCallback? onCall` param, add call icon in the `Row` (next to overflow button)
- `lib/features/conversation/presentation/screens/conversation_screen.dart` — thread `onCall` callback to ConversationHeader
- `lib/features/conversation/presentation/screens/conversation_wired.dart` — add `callService`, implement call button tap → navigate to CallWired

---

## Phase 9: Incoming Call Notification — TDD Steps

### Test 9.1: Show notification for incoming call when app is in foreground

```dart
void main() {
  test('incoming offer shows local notification', () async {
    final mockNotificationService = MockNotificationService();
    final callService = CallService(/* ... */);

    callService.handleIncomingSignal(CallSignal(
      signal: CallSignalType.offer,
      callId: 'uuid-1',
      roomName: 'call-room',
      callerPeerId: '12D3KooWB',
      callerName: 'Bob',
      mediaType: MediaType.audio,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));

    verify(mockNotificationService.showNotification(
      title: 'Incoming call',
      body: 'Bob is calling...',
    )).called(1);
  });
}
```

---

### Test 9.2: Push notification for incoming call when app is backgrounded

> **Critical architecture note:** The background FCM handler (`background_message_handler.dart`)
> runs in a **completely separate Dart isolate**. It has NO access to in-memory services
> (`p2pService`, `messageRouter`, `CallSignalListener`, `CallService`). It cannot invoke
> the live listener infrastructure. This is a fundamental constraint.
>
> **Approach for background calls:**
> 1. The relay server's FCM push payload must include a `type` field for `call_signal`
> 2. The background handler checks this type and shows a **high-priority local notification**
>    with call-specific actions (Accept/Reject)
> 3. When the user taps the notification, the app opens in foreground
> 4. On foreground resume, the app drains the P2P inbox → `CallSignalListener` fires normally
> 5. If the call signal has expired (>30s old), auto-dismiss
>
> **Future enhancement:** Use iOS PushKit/VoIP push for instant wake-up + CallKit integration.

```dart
void main() {
  test('background handler shows high-priority notification for call_signal FCM', () async {
    // Simulate FCM background message with data: { type: 'call_signal', callerName: 'Bob' }
    // Verify: high-priority local notification shown with title "Incoming call" and body "Bob is calling..."
    // Verify: notification has Accept and Reject action buttons
  });

  test('expired call signals are not shown as notifications', () async {
    // Simulate FCM message with timestamp > 30s ago
    // Verify: no notification shown (call already timed out)
  });
}
```

**File to modify:** `lib/features/push/application/background_message_handler.dart` — add `call_signal` case for local notification display only (no in-memory listener invocation).

---

## Phase 10: Audio Session Management — TDD Steps

### Test 10.1: Audio session doesn't conflict with voice messages

```dart
void main() {
  test('call audio session is configured correctly', () async {
    // LiveKit SDK handles this automatically via Hardware.instance
    // Verify: when LiveKit room connects, audio session switches to voiceChat mode
    // Verify: when LiveKit room disconnects, audio session is released
    // Verify: existing AudioRecorderService (record package) still works after call ends
    // Verify: existing just_audio playback still works after call ends
  });

  test('token refresh for long calls', () async {
    // Token TTL is 10 minutes — calls longer than ~8 minutes need a refresh
    // Verify: CallService monitors token expiry and requests a new token before expiry
    // Verify: LiveKit room reconnects transparently with new token
  });
}
```

> **Audio session management:** The `livekit_client` SDK automatically manages audio sessions.
> On iOS: sets `AVAudioSession` to `playAndRecord` + `voiceChat` mode during calls.
> On Android: sets `communication` audio mode.
> Both are released when the LiveKit room disconnects. No manual configuration needed.
> `Hardware.instance.isAutomaticConfigurationEnabled` defaults to `true`.
>
> **Key concern:** The existing `record` package and `just_audio` both manage audio sessions.
> After a call ends, verify these packages can re-acquire the audio session for voice messages
> and audio playback. If conflicts arise, use LiveKit's `onConfigureNativeAudio` callback to
> customize session behavior.

---

## Phase 11: Group Voice Calls (Extension) — TDD Steps

### Test 11.1: Group call uses group ID as room name

```dart
void main() {
  test('initiateGroupCall uses group-<groupId> room name', () async {
    await callService.initiateGroupCall(
      group: Group(id: 'grp-abc', name: 'Team'),
      mediaType: MediaType.audio,
    );

    verify(mockTokenRepo.getToken(
      room: 'group-grp-abc',
      identity: '12D3KooWA',
    )).called(1);
  });

  test('group call offer sent via GossipSub', () async {
    await callService.initiateGroupCall(
      group: Group(id: 'grp-abc', name: 'Team'),
      mediaType: MediaType.audio,
    );

    // Group call signals use existing group pubsub via callGroupPublish
    // (NOT publishGroupMessage — that function doesn't exist)
    // Note: callGroupPublish encrypts with group key (v3 envelope) via Go bridge
    verify(mockBridge.send('group:publish', argThat(
      containsPair('groupId', 'grp-abc'),
    ))).called(1);
  });

  test('group call room allows up to 20 participants', () async {
    // Token request includes maxParticipants hint
    // Server-side: room created with max_participants: 20
  });
}
```

---

## Implementation Order (Dependencies)

```
Phase 1: Domain Models (no deps)
    ↓
Phase 2: Token Repository (needs models)
    ↓
Phase 3: CallSignalListener + MessageRouter changes (needs models)
    ↓
Phase 4: CallService (needs models, token repo, listener)
    ↓
Phase 5: Use Cases (needs CallService)
    ↓
Phase 6: Platform Config (iOS/Android permissions, pubspec)
    ↓
Phase 7: DI Wiring (needs all services)
    ↓
Phase 8: UI (CallScreen, CallWired, call button on conversation)
    ↓
Phase 9: Notifications (incoming call overlay + push)
    ↓
Phase 10: Audio Session (integration concern)
    ↓
Phase 11: Group Calls (extension of Phase 4-8)
```

---

## Files Modified (Existing)

| File | Change |
|------|--------|
| `pubspec.yaml` | Add `livekit_client`, `permission_handler`, `http` (none exist yet) |
| `lib/main.dart` | Wire CallTokenRepository, CallService, CallSignalListener; add to `startLiveServices()`; thread to MyApp (MyApp is defined here, not in app.dart) |
| `lib/core/services/incoming_message_router.dart` | Add `_callSignalController`, `callSignalStream` getter, `'call_signal'` case in `_route()` switch, close in `dispose()` |
| `ios/Runner/Info.plist` | **Update** existing `NSCameraUsageDescription` and `NSMicrophoneUsageDescription` to cover calls; add `audio` to existing `UIBackgroundModes` array |
| `android/app/src/main/AndroidManifest.xml` | Add `MODIFY_AUDIO_SETTINGS`, `BLUETOOTH` (maxSdk 30), `BLUETOOTH_CONNECT` (CAMERA/RECORD_AUDIO already exist) |
| `lib/features/conversation/presentation/widgets/conversation_header.dart` | Add `VoidCallback? onCall` param, add call icon button in header `Row` (this is NOT a Flutter AppBar) |
| `lib/features/conversation/presentation/screens/conversation_screen.dart` | Thread `onCall` callback to ConversationHeader |
| `lib/features/conversation/presentation/screens/conversation_wired.dart` | Add `callService` param, implement call button → navigate to CallWired |
| `lib/features/orbit/presentation/screens/orbit_wired.dart` | Thread `callService` through to ConversationWired |
| `lib/features/identity/presentation/startup_router.dart` | Thread `callService` to FeedWired |
| `lib/features/push/application/background_message_handler.dart` | Add `call_signal` case for local notification only (runs in separate isolate — cannot invoke in-memory listeners) |
| `ios/Podfile` | Verify deployment target >= 12.1 (currently 13.0 — OK) |

## Files Created (New)

| File | Purpose |
|------|---------|
| `lib/features/call/domain/models/call_signal_model.dart` | Call signal types and serialization |
| `lib/features/call/domain/models/call_state.dart` | Call state machine |
| `lib/features/call/data/repositories/call_token_repository.dart` | HTTP token fetching |
| `lib/features/call/application/call_service.dart` | Call lifecycle + LiveKit room management |
| `lib/features/call/application/call_signal_listener.dart` | Incoming signal stream processing |
| `lib/features/call/application/use_cases/initiate_call.dart` | Use case |
| `lib/features/call/application/use_cases/answer_call.dart` | Use case |
| `lib/features/call/application/use_cases/reject_call.dart` | Use case |
| `lib/features/call/application/use_cases/end_call.dart` | Use case |
| `lib/features/call/presentation/screens/call_wired.dart` | Call screen state management |
| `lib/features/call/presentation/screens/call_screen.dart` | Call screen pure UI |
| `lib/features/call/presentation/screens/incoming_call_wired.dart` | Incoming call overlay state |
| `lib/features/call/presentation/screens/incoming_call_screen.dart` | Incoming call overlay UI |
| `lib/features/call/presentation/widgets/call_controls.dart` | Mute/speaker/video/hangup buttons |
| `lib/features/call/presentation/widgets/call_timer.dart` | Duration counter |
| `lib/features/call/presentation/widgets/video_grid.dart` | Video track renderers |
| + All corresponding test files under `test/features/call/` |

---

## Key Design Decisions

1. **Signaling via existing P2P, media via LiveKit** — no new bridge commands needed. LiveKit SDK connects directly from Dart to the LiveKit server via WebSocket. The Go bridge is not involved in call media at all. Call signals travel as `type: 'call_signal'` messages through the existing P2P messaging pipeline → `IncomingMessageRouter` → `CallSignalListener`.

2. **Room naming convention** — `call-<sortedPeerId1>-<sortedPeerId2>` for 1:1, `group-<groupId>` for group calls. Deterministic names prevent duplicate rooms. Room names validated server-side with allowlist regex `^(call|group)-[a-zA-Z0-9-]{1,120}$`.

3. **Token service on same EC2** — lightweight Go HTTP server co-deployed with LiveKit, accessible only via Caddy reverse proxy (not directly exposed). App authenticates with a shared secret stored in `SecureKeyStore`. Token TTL is 10 minutes with client-side refresh for long calls.

4. **CallService as singleton** — only one active call at a time. Second incoming call gets auto-rejected with `busy` signal.

5. **LiveKit SDK manages WebRTC entirely** — no Pion in Go bridge, no ICE handling, no custom TURN. LiveKit abstracts all of this. The SDK also manages audio sessions automatically (`playAndRecord` + `voiceChat` mode during calls).

6. **Audio session handoff** — LiveKit SDK automatically configures `AVAudioSession` (iOS) and sets `communication` audio mode (Android) during calls. When call ends, audio session is released. Existing voice message recording unaffected. No manual audio session management needed — the SDK's `Hardware.instance.isAutomaticConfigurationEnabled` defaults to true.

7. **Permission handling** — The app must explicitly request camera/mic/bluetooth permissions using `permission_handler` before enabling LiveKit tracks. The LiveKit SDK does NOT handle permission requests itself.

8. **Background call handling** — The FCM background handler runs in a separate Dart isolate with no access to in-memory services. For background incoming calls, the handler shows a high-priority local notification. The full call flow activates on foreground resume via P2P inbox drain → `CallSignalListener`. Future phase: iOS PushKit/VoIP push + CallKit integration.

9. **Model naming** — Uses `ContactModel` (field: `username`, not `displayName`) and `IdentityModel` (field: `username`) consistent with the existing codebase. Wire messages use `fromJson`/`toJson` (not `fromMap`/`toMap` which are for DB).

10. **Group call signals** — Use `callGroupPublish` (the actual bridge helper function in `bridge_group_helpers.dart`), not a non-existent `publishGroupMessage`. This sends a `group:publish` command to the Go bridge, which handles v3 envelope encryption and signing.
