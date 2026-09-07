import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/app/bootstrap/call_signaling_composition.dart';
import 'package:flutter_app/app/bootstrap/production_call_signaling_graph.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/migrations/112_direct_linked_device_addressing.dart';
import 'package:flutter_app/core/database/migrations/117_call_history.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/call/application/voice_call_feature_flags.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/ios_call_lifecycle_adapter.dart';
import 'package:flutter_app/features/call/infrastructure/ios_voip_token_coordinator.dart';
import 'package:flutter_app/features/call/infrastructure/issued_call_wake_handle_store_impl.dart';
import 'package:flutter_app/features/call/infrastructure/received_call_wake_handle_store_impl.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../secure_storage/fake_secure_key_store.dart';

/// Plan 400 B: an iOS graph must never tear down a live call over a failed
/// capability re-advertisement or a relay-rejected VoIP token, and an idle
/// transient rollback keeps the VoIP token (a client CAS revoke is what
/// poisons the relay's refresh-epoch high-water).
final _callA = CallId.parse('11111111-1111-4111-8111-111111111111');
final _activeAt = DateTime.fromMillisecondsSinceEpoch(2_000_000, isUtc: true);

void main() {
  tearDown(() => debugSetFlowEventSink(null));

  test(
    'failed advertisement during a live call revokes nothing and ends no CallKit call',
    () async {
      final fixture = await _createFixture();
      await fixture.composition.start();
      expect(fixture.composition.isStarted, isTrue);
      final graph = fixture.graphs.single;
      await _ringIncoming(graph);
      final session = graph.coordinator.activeSession!;
      final commandsBefore = fixture.bridge.commands.length;
      fixture.tokenSet.reject = true;

      await fixture.composition.onResume();

      expect(fixture.composition.isStarted, isTrue);
      expect(
        fixture.bridge.commands.sublist(commandsBefore),
        isNot(contains('call_endpoint_revoke_v1')),
      );
      expect(
        fixture.bridge.commands.sublist(commandsBefore),
        isNot(contains('call_token_revoke_v1')),
      );
      expect(fixture.lifecycleMethods, isNot(contains('failClosed')));
      expect(identical(graph.coordinator.activeSession, session), isTrue);
      expect(session.isTerminal, isFalse);
      expect(
        _details(fixture.flowEvents, 'CALL_CAPABILITY_ADVERTISEMENT_RESULT'),
        anyElement(
          equals(<String, Object?>{
            'stage': 'voip_token',
            'outcome': 'deferred_live_call',
          }),
        ),
      );
      expect(
        _details(fixture.flowEvents, 'CALL_SIGNALING_RESUME_RESULT').last,
        containsPair('outcome', 'advertisement_deferred'),
      );
    },
  );

  test(
    'backgrounding during a failed refresh retains the native call',
    () async {
      final fixture = await _createFixture();
      await fixture.composition.start();
      final graph = fixture.graphs.single;
      await _ringIncoming(graph);
      final session = graph.coordinator.activeSession!;
      final refreshEntered = Completer<void>();
      final refreshResponse = Completer<Map<String, Object?>>();
      fixture.bridge.responseHandlers['call_endpoint_set_v1'] = (_) {
        refreshEntered.complete();
        return refreshResponse.future;
      };

      final refresh = fixture.composition.onContactEligibilityChanged();
      await refreshEntered.future;
      await fixture.composition.onBackgrounded();
      expect(fixture.composition.current, isNull);
      refreshResponse.complete(const <String, Object?>{'ok': false});
      await refresh;

      expect(fixture.composition.isStarted, isTrue);
      expect(graph.coordinator.activeSession, same(session));
      expect(graph.current?.session, same(session));
      expect(session.isTerminal, isFalse);
      expect(fixture.composition.current, isNull);
      expect(fixture.lifecycleMethods, isNot(contains('failClosed')));
      expect(
        fixture.bridge.commands,
        isNot(contains('call_endpoint_revoke_v1')),
      );
      expect(
        _details(fixture.flowEvents, 'CALL_SIGNALING_RECONCILE_RESULT').last,
        containsPair('outcome', 'advertisement_deferred'),
      );
    },
  );

  test(
    'background native call keeps polling without another session event',
    () async {
      final fixture = await _createFixture();
      await fixture.composition.start();
      final graph = fixture.graphs.single;
      await _ringIncoming(graph);
      await fixture.composition.onBackgrounded();
      final polled = Completer<void>();
      fixture.bridge.responseHandlers['call_retrieve_v1'] = (_) async {
        if (!polled.isCompleted) polled.complete();
        return const <String, Object?>{
          'ok': true,
          'events': <Object?>[],
          'receiptAtMs': 1,
          'expiresAtMs': 1,
          'hasMore': false,
        };
      };

      // No resume, wake, media callback, or additional coordinator event can
      // restart the timer: this must be the poll retained across backgrounding.
      await polled.future.timeout(const Duration(seconds: 5));

      expect(fixture.composition.current, isNull);
      expect(graph.coordinator.activeSession?.isTerminal, isFalse);
    },
  );

  test(
    'token authority invalidation during a live call defers withdrawal until the call ends',
    () async {
      final fixture = await _createFixture();
      await fixture.composition.start();
      final graph = fixture.graphs.single;
      await _ringIncoming(graph);
      fixture.tokenSet.reject = true;

      await fixture.composition.onResume();
      await _settle();

      // Deferred at both the graph (no rollback) and the composition (no
      // withdrawal) while the session is live.
      expect(fixture.composition.isStarted, isTrue);
      expect(
        fixture.bridge.commands,
        isNot(contains('call_endpoint_revoke_v1')),
      );
      expect(fixture.bridge.commands, isNot(contains('call_token_revoke_v1')));
      expect(fixture.lifecycleMethods, isNot(contains('failClosed')));
      expect(graph.coordinator.activeSession?.isTerminal, isFalse);

      await _endCall(graph);
      await _until(() => !fixture.composition.isStarted);
      await _until(() => fixture.lifecycleMethods.contains('detach'));

      expect(
        fixture.bridge.commands.where(
          (command) => command == 'call_endpoint_revoke_v1',
        ),
        hasLength(1),
      );
      expect(fixture.bridge.commands, isNot(contains('call_token_revoke_v1')));
      expect(
        fixture.lifecycleMethods.where((method) => method == 'failClosed'),
        hasLength(1),
      );
    },
  );

  test(
    'deferred advertisement is retried once at the terminal snapshot',
    () async {
      final fixture = await _createFixture();
      await fixture.composition.start();
      final graph = fixture.graphs.single;
      await _ringIncoming(graph);
      fixture.tokenSet.reject = true;
      await fixture.composition.onResume();
      expect(fixture.composition.isStarted, isTrue);
      final tokenSetsBeforeTerminal = fixture.tokenSet.calls;
      final endpointSetsBeforeTerminal = fixture.bridge.commands
          .where((command) => command == 'call_endpoint_set_v1')
          .length;
      fixture.tokenSet.reject = false;

      await _endCall(graph);
      await _until(
        () =>
            fixture.bridge.commands
                .where((command) => command == 'call_endpoint_set_v1')
                .length ==
            endpointSetsBeforeTerminal + 1,
      );
      await _settle();

      expect(fixture.tokenSet.calls, tokenSetsBeforeTerminal + 1);
      expect(fixture.composition.isStarted, isTrue);
      expect(
        fixture.bridge.commands,
        isNot(contains('call_endpoint_revoke_v1')),
      );
      expect(fixture.bridge.commands, isNot(contains('call_token_revoke_v1')));
      expect(fixture.lifecycleMethods, isNot(contains('failClosed')));
      expect(
        _details(
          fixture.flowEvents,
          'CALL_CAPABILITY_ADVERTISEMENT_RESULT',
        ).last,
        <String, Object?>{'stage': 'ready', 'outcome': 'ready'},
      );
    },
  );

  test('idle advertisement failure revokes the endpoint only', () async {
    final fixture = await _createFixture();
    await fixture.composition.start();
    expect(fixture.composition.isStarted, isTrue);
    fixture.tokenSet.reject = true;

    await fixture.composition.onResume();
    await _until(() => fixture.lifecycleMethods.contains('detach'));

    expect(fixture.composition.isStarted, isFalse);
    expect(
      fixture.bridge.commands.where(
        (command) => command == 'call_endpoint_revoke_v1',
      ),
      hasLength(1),
    );
    expect(fixture.bridge.commands, isNot(contains('call_token_revoke_v1')));
    expect(
      fixture.lifecycleMethods.where((method) => method == 'failClosed'),
      hasLength(1),
    );
    final advertisements = _details(
      fixture.flowEvents,
      'CALL_CAPABILITY_ADVERTISEMENT_RESULT',
    );
    expect(
      advertisements,
      anyElement(
        equals(<String, Object?>{
          'stage': 'voip_token',
          'outcome': 'unavailable',
        }),
      ),
    );
    expect(
      advertisements.any(
        (details) => details['outcome'] == 'deferred_live_call',
      ),
      isFalse,
    );
  });

  test(
    'relay stale epoch advances the native epoch and keeps the graph callable',
    () async {
      final fixture = await _createFixture();
      await fixture.composition.start();
      expect(fixture.composition.isStarted, isTrue);
      fixture.tokenSet.reject = true;
      fixture.tokenSet.advanceTo = 1_900_000_000;

      await fixture.composition.onResume();

      expect(fixture.composition.isStarted, isTrue);
      expect(fixture.tokenSet.advanceCalls, 1);
      final tokenSets = fixture.bridge.requests
          .where((request) => request['cmd'] == 'call_token_set_v1')
          .map(
            (request) =>
                (request['payload'] as Map<String, dynamic>)['refreshEpoch'],
          )
          .toList(growable: false);
      expect(tokenSets, <Object?>[41, 41, 1_900_000_000]);
      expect(fixture.bridge.commands, isNot(contains('call_token_revoke_v1')));
      expect(
        fixture.bridge.commands,
        isNot(contains('call_endpoint_revoke_v1')),
      );
      expect(fixture.lifecycleMethods, isNot(contains('failClosed')));
      expect(
        _details(fixture.flowEvents, 'CALL_VOIP_TOKEN_EPOCH_ADVANCE_RESULT'),
        <Map<String, Object?>>[
          <String, Object?>{'outcome': 'advanced'},
        ],
      );
      expect(
        _details(
          fixture.flowEvents,
          'CALL_CAPABILITY_ADVERTISEMENT_RESULT',
        ).last,
        <String, Object?>{'stage': 'ready', 'outcome': 'ready'},
      );
      expect(
        _details(fixture.flowEvents, 'CALL_SIGNALING_RESUME_RESULT').last,
        containsPair('outcome', 'ready'),
      );
    },
  );

  test('a call wake drains the production call mailbox', () async {
    final fixture = await _createFixture();
    await fixture.composition.start();
    expect(fixture.composition.isStarted, isTrue);
    int retrieves() => fixture.bridge.commands
        .where((command) => command == 'call_retrieve_v1')
        .length;
    final before = retrieves();

    await fixture.composition.onCallWake();

    expect(retrieves(), before + 1);
    expect(fixture.composition.isStarted, isTrue);
    expect(
      _details(fixture.flowEvents, 'CALL_SIGNALING_WAKE_RESULT').last,
      containsPair('outcome', 'drained'),
    );
  });

  test('a relay recovery drains the production call mailbox once', () async {
    final fixture = await _createFixture();
    await fixture.composition.start();
    int retrieves() => fixture.bridge.commands
        .where((command) => command == 'call_retrieve_v1')
        .length;
    final before = retrieves();

    // The node lost its relay link (the app was suspended) and recovered.
    fixture.p2p.states.add(
      const NodeState(
        peerId: 'local-account',
        isStarted: true,
        relayState: 'recovering',
        healthyRelayCount: 0,
      ),
    );
    fixture.p2p.states.add(
      const NodeState(
        peerId: 'local-account',
        isStarted: true,
        relayState: 'healthy',
        healthyRelayCount: 1,
      ),
    );
    fixture.p2p.states.add(
      const NodeState(
        peerId: 'local-account',
        isStarted: true,
        relayState: 'healthy',
        healthyRelayCount: 1,
      ),
    );
    await _settle();

    expect(retrieves(), before + 1);
  });

  test('shutdown revokes endpoint and token', () async {
    final fixture = await _createFixture();
    await fixture.composition.start();
    expect(fixture.composition.isStarted, isTrue);

    await fixture.composition.shutdown();

    expect(
      fixture.bridge.commands.where(
        (command) => command == 'call_endpoint_revoke_v1',
      ),
      hasLength(1),
    );
    final tokenRevokes = fixture.bridge.requests
        .where((request) => request['cmd'] == 'call_token_revoke_v1')
        .map((request) => request['payload'] as Map<String, dynamic>)
        .toList(growable: false);
    expect(tokenRevokes, <Map<String, Object?>>[
      <String, Object?>{'tokenKind': 'ios_voip', 'expectedRefreshEpoch': 41},
    ]);
  });

  test(
    'advertisement failure with a terminal session performs the idle rollback',
    () async {
      final fixture = await _createFixture();
      await fixture.composition.start();
      final graph = fixture.graphs.single;
      await _ringIncoming(graph);
      await _endCall(graph);
      await _settle();
      expect(graph.coordinator.activeSession?.isTerminal ?? true, isTrue);
      fixture.tokenSet.reject = true;

      await fixture.composition.onResume();
      await _until(() => fixture.lifecycleMethods.contains('detach'));

      expect(fixture.composition.isStarted, isFalse);
      expect(
        fixture.bridge.commands.where(
          (command) => command == 'call_endpoint_revoke_v1',
        ),
        hasLength(1),
      );
      expect(fixture.bridge.commands, isNot(contains('call_token_revoke_v1')));
      final advertisements = _details(
        fixture.flowEvents,
        'CALL_CAPABILITY_ADVERTISEMENT_RESULT',
      );
      expect(advertisements.last, <String, Object?>{
        'stage': 'voip_token',
        'outcome': 'unavailable',
      });
      expect(
        advertisements.any(
          (details) => details['outcome'] == 'deferred_live_call',
        ),
        isFalse,
      );
    },
  );
}

List<Map<String, dynamic>> _details(
  List<Map<String, dynamic>> events,
  String event,
) => events
    .where((entry) => entry['event'] == event)
    .map((entry) => Map<String, dynamic>.from(entry['details'] as Map))
    .toList(growable: false);

Future<void> _ringIncoming(ProductionCallSignalingGraph graph) async {
  await graph.coordinator.dispatch(
    CallEvent(
      type: CallEventType.remoteInvite,
      eventId: 'live-guard-remote-invite',
      occurredAt: _activeAt,
      callId: _callA,
      contactPeerId: 'remote-account',
      localAccountPeerId: 'local-account',
      localDeviceId: 'local-account',
      remoteAccountPeerId: 'remote-account',
      remoteDeviceId: 'remote-device',
      expiresAt: _activeAt.add(const Duration(seconds: 45)),
      transportRoute: CallRouteClass.direct,
    ),
  );
  await graph.coordinator.dispatch(
    CallEvent(
      type: CallEventType.incomingValidated,
      eventId: 'live-guard-incoming-validated',
      occurredAt: _activeAt,
      callId: _callA,
      contactPeerId: 'remote-account',
    ),
  );
  expect(graph.coordinator.activeSession?.callId, _callA);
  expect(graph.coordinator.activeSession?.isTerminal, isFalse);
}

Future<void> _endCall(ProductionCallSignalingGraph graph) =>
    graph.coordinator.dispatch(
      CallEvent(
        type: CallEventType.remoteTerminate,
        eventId: 'live-guard-remote-terminate',
        occurredAt: _activeAt.add(const Duration(seconds: 1)),
        callId: _callA,
        contactPeerId: 'remote-account',
      ),
    );

Future<void> _settle() async {
  for (var turn = 0; turn < 8; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _until(bool Function() predicate) async {
  for (var attempt = 0; attempt < 200 && !predicate(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(predicate(), isTrue);
}

final class _TokenSetScript {
  bool reject = false;
  int calls = 0;

  /// When set, the fake native answers `advanceRefreshEpoch` with this epoch
  /// and the relay accepts it (the rejection above applies to epoch 41 only).
  int? advanceTo;
  int advanceCalls = 0;
}

final class _Fixture {
  const _Fixture({
    required this.composition,
    required this.bridge,
    required this.lifecycleMethods,
    required this.graphs,
    required this.flowEvents,
    required this.tokenSet,
    required this.p2p,
  });

  final CallSignalingComposition composition;
  final _Bridge bridge;
  final List<String> lifecycleMethods;
  final List<ProductionCallSignalingGraph> graphs;
  final List<Map<String, dynamic>> flowEvents;
  final _TokenSetScript tokenSet;
  final _P2P p2p;
}

Future<_Fixture> _createFixture() async {
  databaseFactory = databaseFactoryFfi;
  final database = await openDatabase(
    inMemoryDatabasePath,
    version: 1,
    onCreate: (db, _) async {
      await db.execute(
        'CREATE TABLE contacts('
        'peer_id TEXT PRIMARY KEY, username TEXT, public_key TEXT, '
        'ml_kem_public_key TEXT, is_blocked INTEGER)',
      );
      await runDirectLinkedDeviceAddressingMigration(db);
      await runCallHistoryMigration(db);
      await db.insert('contacts', <String, Object?>{
        'peer_id': 'remote-account',
        'username': 'Remote contact',
        'public_key': 'remote-public-key',
        'ml_kem_public_key': 'remote-mlkem-public-key',
        'is_blocked': 0,
      });
    },
  );
  final tokenSet = _TokenSetScript();
  final bridge = _Bridge();
  bridge.responseHandlers['call_token_set_v1'] = (request) async {
    tokenSet.calls++;
    final epoch = (request['payload']! as Map<String, dynamic>)['refreshEpoch'];
    if (tokenSet.reject && epoch == 41) {
      return const <String, Object?>{
        'ok': false,
        'errorCode': 'CALL_STALE_EPOCH',
      };
    }
    return <String, Object?>{
      'ok': true,
      'generation': 3,
      'refreshEpoch':
          (request['payload']! as Map<String, dynamic>)['refreshEpoch'],
    };
  };
  final p2p = _P2P();
  final router = IncomingMessageRouter(p2pService: p2p)..start();
  final lifecycleMethods = <String>[];
  final tokenEvents = StreamController<Object?>.broadcast(sync: true);
  final graphs = <ProductionCallSignalingGraph>[];
  final flowEvents = <Map<String, dynamic>>[];
  debugSetFlowEventSink(flowEvents.add);
  final identity = IdentityModel(
    peerId: 'local-account',
    publicKey: 'local-public-key',
    privateKey: 'local-private-key',
    mnemonic12: 'unused fixture words',
    mlKemPublicKey: 'local-mlkem-public-key',
    mlKemSecretKey: 'local-mlkem-secret-key',
    createdAt: '2026-08-30T00:00:00.000Z',
    updatedAt: '2026-08-30T00:00:00.000Z',
  );
  final secureKeyStore = FakeSecureKeyStore();
  final composition = createProductionCallSignalingComposition(
    featureFlags: <String, bool>{
      ...defaultVoiceCallFeatureFlags(),
      'voice_call_capability_v1': true,
      'voice_call_outgoing_enabled': true,
      'voice_call_incoming_enabled': true,
      'voice_call_turn_enabled': true,
      'voice_call_android_native_enabled': false,
      'voice_call_ios_native_enabled': true,
    },
    platform: CallEndpointPlatform.ios,
    database: database,
    bridge: bridge,
    p2pService: p2p,
    messageRouter: router,
    loadIdentity: () async => identity,
    networkEffectsAllowed: () => true,
    isVoiceNoteRecording: () => false,
    issuedCallWakeHandleStore: IssuedCallWakeHandleStoreImpl(
      secureKeyStore: secureKeyStore,
    ),
    receivedCallWakeHandleStore: ReceivedCallWakeHandleStoreImpl(
      secureKeyStore: secureKeyStore,
    ),
    iosCallLifecycleAdapterFactory:
        ({
          required coordinator,
          required resolveAuthenticatedHandle,
          required clock,
        }) => IosCallLifecycleAdapter(
          invokeMethod: (method, arguments) async {
            lifecycleMethods.add(method);
            if (method == 'attach') {
              return const <String, Object?>{
                'version': 1,
                'descriptor': null,
                'events': <Object?>[],
                'nativeCallId': null,
                'highestSequence': 0,
              };
            }
            return true;
          },
          nativeEvents: const Stream<Object?>.empty(),
          coordinator: coordinator,
          resolveAuthenticatedHandle: resolveAuthenticatedHandle,
          clock: clock,
        ),
    iosVoipTokenCoordinatorFactory:
        ({
          required authorityClient,
          required clock,
          required publicationAllowed,
        }) => IosVoipTokenCoordinator(
          invokeMethod: (method, arguments) async {
            var epoch = 41;
            if (method == 'advanceRefreshEpoch') {
              tokenSet.advanceCalls++;
              final advanceTo = tokenSet.advanceTo;
              if (advanceTo == null) {
                throw StateError('epoch advance unavailable');
              }
              epoch = advanceTo;
            }
            return <String, Object?>{
              'version': 1,
              'token': List<String>.filled(64, 'c').join(),
              'environment': 'development',
              'topic': 'com.mknoon.app.voip',
              'capabilityVersion': 1,
              'refreshEpoch': epoch,
              'invalidated': false,
            };
          },
          nativeEvents: tokenEvents.stream,
          authorityClient: authorityClient,
          clock: clock,
          publicationAllowed: publicationAllowed,
        ),
    isForeground: () => true,
    nowMs: () => 2_000_000,
    onGraphBuilt: graphs.add,
  );
  addTearDown(() async {
    debugSetFlowEventSink(null);
    await composition.shutdown();
    router.dispose();
    await p2p.messages.close();
    await p2p.states.close();
    await tokenEvents.close();
    await database.close();
  });
  return _Fixture(
    composition: composition,
    bridge: bridge,
    lifecycleMethods: lifecycleMethods,
    graphs: graphs,
    flowEvents: flowEvents,
    tokenSet: tokenSet,
    p2p: p2p,
  );
}

final class _Bridge implements Bridge {
  final List<String> commands = <String>[];
  final List<Map<String, dynamic>> requests = <Map<String, dynamic>>[];
  final Map<String, Future<Map<String, Object?>> Function(Map<String, dynamic>)>
  responseHandlers =
      <String, Future<Map<String, Object?>> Function(Map<String, dynamic>)>{};

  @override
  bool get isInitialized => true;

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    requests.add(request);
    final command = request['cmd']! as String;
    commands.add(command);
    final handler = responseHandlers[command];
    if (handler != null) return jsonEncode(await handler(request));
    return jsonEncode(switch (command) {
      'payload.sign' => const <String, Object?>{
        'ok': true,
        'signature': 'c2lnbmF0dXJl',
      },
      'call_endpoint_set_v1' => const <String, Object?>{'ok': true},
      'call_endpoint_revoke_v1' => const <String, Object?>{
        'ok': true,
        'revoked': true,
      },
      'call_wake_handle_set_v1' => const <String, Object?>{'ok': true},
      'call_wake_handle_revoke_v1' => const <String, Object?>{
        'ok': true,
        'revoked': true,
      },
      'call_token_revoke_v1' => const <String, Object?>{
        'ok': true,
        'revoked': true,
      },
      'call_retrieve_v1' => const <String, Object?>{
        'ok': true,
        'events': <Object?>[],
        'receiptAtMs': 1,
        'expiresAtMs': 1,
        'hasMore': false,
      },
      _ => const <String, Object?>{'ok': false},
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _P2P implements P2PService {
  final StreamController<ChatMessage> messages =
      StreamController<ChatMessage>.broadcast();
  final StreamController<NodeState> states =
      StreamController<NodeState>.broadcast(sync: true);

  @override
  NodeState get currentState =>
      const NodeState(peerId: 'local-account', isStarted: true);

  @override
  Stream<ChatMessage> get messageStream => messages.stream;

  @override
  Stream<NodeState> get stateStream => states.stream;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async => const SendMessageResult(sent: false, acked: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
