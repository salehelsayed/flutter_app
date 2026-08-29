import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/debug/android_notification_payload_e2e.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/push/application/push_envelope_staging.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _request({
  String action = androidNotificationPostTapObserveAction,
}) => <String, dynamic>{
  'schema': androidNotificationPayloadE2ERequestSchema,
  'transport_action': action,
  'scenario': androidNotificationPayloadE2EScenario,
  'stepId': 'notification-$action-run-notification-1',
  'runId': 'run-notification-1',
  'nonce': 'nonce-notification-1',
  'contactPeerId': 'peer-contact-1',
  'expectedText': 'Sims notification proof marker 1',
  'expectedMessageId': 'message-notification-1',
  'requireStagedBeforeTap': true,
  'timeoutMs': 90000,
};

const _notReady = NodeState(isStarted: true);
const _stopped = NodeState.stopped;
const _inboxReady = NodeState(isStarted: true, inboxCapabilityReady: true);
const _transportReady = NodeState(
  isStarted: true,
  relayState: 'online',
  healthyRelayCount: 1,
  sendCapabilityReady: true,
  inboxCapabilityReady: true,
);

ConversationMessage _message(String id) => ConversationMessage(
  id: id,
  contactPeerId: 'peer-contact-1',
  senderPeerId: 'peer-contact-1',
  text: 'Sims notification proof marker 1',
  timestamp: '2026-07-16T00:00:00.000Z',
  status: 'delivered',
  isIncoming: true,
  createdAt: '2026-07-16T00:00:00.000Z',
  transport: 'inbox',
);

Future<Map<String, dynamic>> _runReplay({
  required _DrainP2PService p2pService,
  required _PendingBridge bridge,
  required MessageRepository messageRepo,
}) => runAndroidNotificationPayloadE2EAction(
  config: _request(action: androidNotificationA6ObserveAction),
  p2pService: p2pService,
  bridge: bridge,
  messageRepo: messageRepo,
  pushEnvelopeStagingStore: _UnusedPushEnvelopeStagingStore(),
  writeProgress: (_) async {},
);

Future<Map<String, dynamic>> _runDrain({
  required _DrainP2PService p2pService,
  required _PendingBridge bridge,
  required _SequenceMessageRepository messageRepo,
}) => runAndroidNotificationPayloadE2EAction(
  config: _request(action: androidNotificationDrainObserveAction),
  p2pService: p2pService,
  bridge: bridge,
  messageRepo: messageRepo,
  pushEnvelopeStagingStore: _UnusedPushEnvelopeStagingStore(),
  writeProgress: (_) async {},
);

void main() {
  test(
    'dispatcher recognizes only the bounded Plan 258 notification actions',
    () {
      for (final action in <String>[
        androidNotificationUnregisterPushAction,
        androidNotificationRestorePushAction,
        androidNotificationClearStagingAction,
        androidNotificationStopNodeAndClearStagingAction,
        androidNotificationA6ObserveAction,
        androidNotificationPostTapObserveAction,
        androidNotificationDrainObserveAction,
        androidNotificationTransportReadyAction,
        androidNotificationDeletePushTokenAction,
      ]) {
        expect(isAndroidNotificationPayloadE2EAction(action), isTrue);
      }
      expect(
        isAndroidNotificationPayloadE2EAction('send_chat_message'),
        isFalse,
      );
      expect(isAndroidNotificationPayloadE2EAction(null), isFalse);
    },
  );

  test('parses an exact nonce/run/message-bound post-tap request', () {
    final request = AndroidNotificationPayloadE2ERequest.fromConfig(_request());
    expect(request.action, androidNotificationPostTapObserveAction);
    expect(request.runId, 'run-notification-1');
    expect(request.expectedMessageId, 'message-notification-1');
    expect(request.requireStagedBeforeTap, isTrue);
    expect(request.timeout, const Duration(seconds: 90));
  });

  test('control actions do not require or expose a message selector', () {
    final value = _request(action: androidNotificationRestorePushAction)
      ..remove('contactPeerId')
      ..remove('expectedText')
      ..remove('expectedMessageId');
    final request = AndroidNotificationPayloadE2ERequest.fromConfig(value);
    expect(request.contactPeerId, isNull);
    expect(request.expectedText, isEmpty);
    expect(request.expectedMessageId, isNull);
  });

  test('unregister retries a transient relay refusal', () async {
    final bridge = _UnregisterBridge(<Map<String, dynamic>>[
      <String, dynamic>{'ok': false, 'unregistered': false},
      <String, dynamic>{'ok': true, 'unregistered': true},
    ]);

    final receipt = await runAndroidNotificationPayloadE2EAction(
      config: _request(action: androidNotificationUnregisterPushAction),
      p2pService: _DrainP2PService(_inboxReady),
      bridge: bridge,
      messageRepo: _SequenceMessageRepository(const <List<ConversationMessage>>[
        <ConversationMessage>[],
      ]),
      pushEnvelopeStagingStore: _UnusedPushEnvelopeStagingStore(),
      writeProgress: (_) async {},
    );

    expect(receipt['status'], 'complete');
    expect(receipt['success'], isTrue);
    expect(receipt['unregistered'], isTrue);
    expect(bridge.unregisterCalls, 2);
  });

  test('transport readiness requires two consecutive exact samples', () async {
    final p2pService = _DrainP2PService(
      _notReady,
      statesAfterHealthCheck: const <NodeState>[
        _transportReady,
        _transportReady,
      ],
    );

    final receipt = await runAndroidNotificationPayloadE2EAction(
      config: _request(action: androidNotificationTransportReadyAction),
      p2pService: p2pService,
      bridge: _PendingBridge(<Map<String, dynamic>>[]),
      messageRepo: _SequenceMessageRepository(const <List<ConversationMessage>>[
        <ConversationMessage>[],
      ]),
      pushEnvelopeStagingStore: _UnusedPushEnvelopeStagingStore(),
      writeProgress: (_) async {},
    );

    expect(receipt['status'], 'complete');
    expect(receipt['transportReady'], isTrue);
    expect(receipt['sendCapabilityReady'], isTrue);
    expect(receipt['inboxCapabilityReady'], isTrue);
    expect(receipt['relayReady'], isTrue);
    expect(p2pService.healthCheckCalls, 2);
  });

  test('rejects stale schema, action, scenario, and step bindings', () {
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (value) => value['schema'] = 'stale',
      (value) => value['transport_action'] = 'send_chat_message',
      (value) => value['scenario'] = 'notifications.other',
      (value) => value['stepId'] = 'notification-stale',
      (value) => value['nonce'] = '../escape',
    ]) {
      final value = _request();
      mutate(value);
      expect(
        () => AndroidNotificationPayloadE2ERequest.fromConfig(value),
        throwsFormatException,
      );
    }
  });

  test('rejects unsafe or missing message selectors', () {
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (value) => value['contactPeerId'] = '',
      (value) => value['expectedMessageId'] = 'message/escape',
      (value) => value['expectedText'] = '',
      (value) => value['expectedText'] = 'line\nbreak',
    ]) {
      final value = _request();
      mutate(value);
      expect(
        () => AndroidNotificationPayloadE2ERequest.fromConfig(value),
        throwsFormatException,
      );
    }
  });

  test('clamps notification action timeout to its device proof budget', () {
    final low = _request()..['timeoutMs'] = 1;
    final high = _request()..['timeoutMs'] = 999999;
    expect(
      AndroidNotificationPayloadE2ERequest.fromConfig(low).timeout,
      const Duration(seconds: 30),
    );
    expect(
      AndroidNotificationPayloadE2ERequest.fromConfig(high).timeout,
      const Duration(minutes: 3),
    );
  });

  test('failure receipt contains no plaintext, peer ID, or error message', () {
    final receipt = androidNotificationPayloadE2EFailureReceipt(
      config: _request(),
      error: StateError('secret peer and plaintext marker'),
    );
    expect(receipt['status'], 'failed');
    expect(receipt['success'], isFalse);
    expect(receipt['errorType'], 'StateError');
    expect(receipt.toString(), isNot(contains('secret peer')));
    expect(receipt.toString(), isNot(contains('Sims notification proof')));
    expect(receipt.toString(), isNot(contains('peer-contact-1')));
  });

  test(
    'cold drain establishes inbox readiness and converges on two exact drains',
    () async {
      final message = _message('message-notification-1');
      final p2pService = _DrainP2PService(
        _stopped,
        statesAfterDrain: const <NodeState?>[_notReady, _inboxReady],
      );
      final messageRepo = _SequenceMessageRepository(
        <List<ConversationMessage>>[
          <ConversationMessage>[message],
          <ConversationMessage>[message],
        ],
      );
      final bridge = _PendingBridge(<Map<String, dynamic>>[
        <String, dynamic>{'ok': true, 'messages': <Object?>[]},
        <String, dynamic>{'ok': true, 'messages': <Object?>[]},
      ]);

      final receipt = await _runDrain(
        p2pService: p2pService,
        bridge: bridge,
        messageRepo: messageRepo,
      );

      expect(receipt['status'], 'complete');
      expect(receipt['success'], isTrue);
      expect(receipt['messageCount'], 1);
      expect(receipt['pendingRelayEntries'], 0);
      expect(p2pService.drainCalls, 3);
      expect(bridge.pendingCalls, 2);
    },
  );

  test(
    'cold drain fails before polling relay when a duplicate is observed',
    () async {
      final message = _message('message-notification-1');
      final p2pService = _DrainP2PService(_inboxReady);
      final messageRepo = _SequenceMessageRepository(
        <List<ConversationMessage>>[
          <ConversationMessage>[message, message],
        ],
      );
      final bridge = _PendingBridge(<Map<String, dynamic>>[
        <String, dynamic>{'ok': true, 'messages': <Object?>[]},
      ]);

      await expectLater(
        _runDrain(
          p2pService: p2pService,
          bridge: bridge,
          messageRepo: messageRepo,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'duplicate post-restore relay messages committed',
          ),
        ),
      );
      expect(p2pService.drainCalls, 1);
      expect(bridge.pendingCalls, 0);
    },
  );

  test('second exact-once drain rejects a duplicate replay', () async {
    final message = _message('message-notification-1');
    final p2pService = _DrainP2PService(_inboxReady);
    final messageRepo = _SequenceMessageRepository(<List<ConversationMessage>>[
      <ConversationMessage>[message],
      <ConversationMessage>[message, message],
    ]);
    final bridge = _PendingBridge(<Map<String, dynamic>>[
      <String, dynamic>{'ok': true, 'messages': <Object?>[]},
    ]);

    await expectLater(
      _runDrain(
        p2pService: p2pService,
        bridge: bridge,
        messageRepo: messageRepo,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'duplicate post-restore relay messages committed',
        ),
      ),
    );
    expect(p2pService.drainCalls, 2);
    expect(bridge.pendingCalls, 1);
  });

  test('A6 replay observation retries a non-empty pending list instead of '
      'reporting a custody failure', () async {
    final message = _message('message-notification-1');
    final p2pService = _DrainP2PService(_inboxReady);
    final messageRepo = _ReplayEventMessageRepository(
      <List<ConversationMessage>>[
        <ConversationMessage>[message],
      ],
    );
    // The relay re-serves an entry until its ACK purges it, so a sample
    // taken inside a replay window reads non-empty for a delivery that is
    // converging exactly once (device-measured 2026-08-19).
    final bridge = _PendingBridge(<Map<String, dynamic>>[
      <String, dynamic>{
        'ok': true,
        'messages': <Object?>[
          <String, dynamic>{'id': 'entry-still-being-replayed'},
        ],
      },
      <String, dynamic>{'ok': true, 'messages': <Object?>[]},
    ]);

    final receipt = await _runReplay(
      p2pService: p2pService,
      bridge: bridge,
      messageRepo: messageRepo,
    );

    expect(receipt['status'], 'complete');
    expect(receipt['success'], isTrue);
    expect(receipt['pendingRelayEntries'], 0);
    expect(bridge.pendingCalls, 2);
  });

  test(
    'A6 replay observation fails closed on a duplicate commit before it ever '
    'polls the relay',
    () async {
      final message = _message('message-notification-1');
      final p2pService = _DrainP2PService(_inboxReady);
      final messageRepo = _ReplayEventMessageRepository(
        <List<ConversationMessage>>[
          <ConversationMessage>[message],
          <ConversationMessage>[message, message],
        ],
      );
      final bridge = _PendingBridge(<Map<String, dynamic>>[
        <String, dynamic>{'ok': true, 'messages': <Object?>[]},
      ]);

      await expectLater(
        _runReplay(
          p2pService: p2pService,
          bridge: bridge,
          messageRepo: messageRepo,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'relay replay/ack did not remain exactly once',
          ),
        ),
      );
      // Duplicate commits are a custody verdict on the first sample; the
      // relay is never consulted to reach it.
      expect(bridge.pendingCalls, 0);
    },
  );

  test('delete-push-token action dispatches', () async {
    final messaging = _RotatingFakeMessaging(<String>[
      'token-before-rotation',
      'token-after-rotation',
    ]);

    final receipt = await runAndroidNotificationPayloadE2EAction(
      config: _tokenRotationRequest(),
      p2pService: _DrainP2PService(_inboxReady),
      bridge: _PendingBridge(<Map<String, dynamic>>[]),
      messageRepo: _SequenceMessageRepository(const <List<ConversationMessage>>[
        <ConversationMessage>[],
      ]),
      pushEnvelopeStagingStore: _UnusedPushEnvelopeStagingStore(),
      writeProgress: (_) async {},
      fcmTokenProvider: messaging.getToken,
      fcmTokenInvalidator: messaging.deleteToken,
    );

    expect(receipt['status'], 'complete');
    expect(receipt['success'], isTrue);
    expect(receipt['tokenRotated'], isTrue);
    expect(messaging.deleteCalls, 1);
    expect(receipt['tokenHashPrefixBefore'], isA<String>());
    expect(receipt['tokenHashPrefixAfter'], isA<String>());
    expect(
      receipt['tokenHashPrefixBefore'],
      isNot(receipt['tokenHashPrefixAfter']),
    );
    // The receipt must never echo raw provider material.
    expect(receipt.toString(), isNot(contains('token-before-rotation')));
    expect(receipt.toString(), isNot(contains('token-after-rotation')));
  });

  test('delete-push-token action polls past a stale unrotated read', () async {
    // `deleteToken` returning does NOT mean the next `getToken` already sees
    // the new token. Accepting the first read would report a rotation that
    // never happened.
    final messaging = _RotatingFakeMessaging(<String>[
      'token-before-rotation',
      'token-after-rotation',
    ], staleReadsAfterDelete: 2);

    final receipt = await runAndroidNotificationPayloadE2EAction(
      config: _tokenRotationRequest(),
      p2pService: _DrainP2PService(_inboxReady),
      bridge: _PendingBridge(<Map<String, dynamic>>[]),
      messageRepo: _SequenceMessageRepository(const <List<ConversationMessage>>[
        <ConversationMessage>[],
      ]),
      pushEnvelopeStagingStore: _UnusedPushEnvelopeStagingStore(),
      writeProgress: (_) async {},
      fcmTokenProvider: messaging.getToken,
      fcmTokenInvalidator: messaging.deleteToken,
    );

    expect(receipt['tokenRotated'], isTrue);
    expect(messaging.getCalls, greaterThanOrEqualTo(4));
    expect(
      receipt['tokenHashPrefixAfter'],
      _hashPrefix('token-after-rotation'),
    );
  });

  test(
    'delete-push-token action fails closed with no token to rotate',
    () async {
      final messaging = _RotatingFakeMessaging(const <String>['']);

      await expectLater(
        runAndroidNotificationPayloadE2EAction(
          config: _tokenRotationRequest(),
          p2pService: _DrainP2PService(_inboxReady),
          bridge: _PendingBridge(<Map<String, dynamic>>[]),
          messageRepo: _SequenceMessageRepository(
            const <List<ConversationMessage>>[<ConversationMessage>[]],
          ),
          pushEnvelopeStagingStore: _UnusedPushEnvelopeStagingStore(),
          writeProgress: (_) async {},
          fcmTokenProvider: messaging.getToken,
          fcmTokenInvalidator: messaging.deleteToken,
        ),
        throwsA(isA<StateError>()),
      );
      // The provider is never mutated when there was nothing to rotate.
      expect(messaging.deleteCalls, 0);
    },
  );

  test(
    'transient drain and pending failures retry within the action budget',
    () async {
      final message = _message('message-notification-1');
      final p2pService = _DrainP2PService(
        _inboxReady,
        drainOutcomes: <Object?>[StateError('transient drain'), null],
      );
      final messageRepo = _SequenceMessageRepository(
        <List<ConversationMessage>>[
          <ConversationMessage>[message],
          <ConversationMessage>[message],
          <ConversationMessage>[message],
        ],
      );
      final bridge = _PendingBridge(<Object>[
        const FormatException('transient pending response'),
        <String, dynamic>{'ok': true, 'messages': <Object?>[]},
        <String, dynamic>{'ok': true, 'messages': <Object?>[]},
      ]);

      final receipt = await _runDrain(
        p2pService: p2pService,
        bridge: bridge,
        messageRepo: messageRepo,
      );

      expect(receipt['status'], 'complete');
      expect(p2pService.drainCalls, 4);
      expect(bridge.pendingCalls, 3);
      expect(
        bridge.timeoutMsValues,
        everyElement(allOf(greaterThan(0), lessThanOrEqualTo(3000))),
      );
    },
  );
}

Map<String, dynamic> _tokenRotationRequest() =>
    _request(action: androidNotificationDeletePushTokenAction)
      ..remove('contactPeerId')
      ..remove('expectedText')
      ..remove('expectedMessageId')
      ..remove('requireStagedBeforeTap')
      ..['timeoutMs'] = 30000;

/// Mirrors the real provider side effect: `deleteToken` is what makes the next
/// `getToken` return a different value.
class _RotatingFakeMessaging {
  _RotatingFakeMessaging(this._tokens, {this.staleReadsAfterDelete = 0});

  final List<String> _tokens;
  final int staleReadsAfterDelete;
  int _index = 0;
  int _staleRemaining = 0;
  int deleteCalls = 0;
  int getCalls = 0;

  Future<String?> getToken() async {
    getCalls++;
    if (_staleRemaining > 0) {
      _staleRemaining--;
      return _tokens.first;
    }
    return _tokens[_index];
  }

  Future<void> deleteToken() async {
    deleteCalls++;
    _staleRemaining = staleReadsAfterDelete;
    if (_index + 1 < _tokens.length) _index++;
  }
}

String _hashPrefix(String token) =>
    sha256.convert(utf8.encode(token)).toString().substring(0, 12);

class _DrainP2PService implements P2PService {
  _DrainP2PService(
    this._state, {
    this.drainOutcomes = const <Object?>[],
    this.statesAfterDrain = const <NodeState?>[],
    this.statesAfterHealthCheck = const <NodeState>[],
  });

  NodeState _state;
  final List<Object?> drainOutcomes;
  final List<NodeState?> statesAfterDrain;
  final List<NodeState> statesAfterHealthCheck;
  int drainCalls = 0;
  int healthCheckCalls = 0;

  @override
  NodeState get currentState => _state;

  @override
  Future<void> drainOfflineInbox() async {
    final index = drainCalls;
    drainCalls++;
    if (index < drainOutcomes.length) {
      final outcome = drainOutcomes[index];
      if (outcome != null) throw outcome;
    }
    if (index < statesAfterDrain.length) {
      _state = statesAfterDrain[index] ?? _state;
    }
  }

  @override
  Future<void> performImmediateHealthCheck() async {
    final index = healthCheckCalls;
    healthCheckCalls++;
    if (index < statesAfterHealthCheck.length) {
      _state = statesAfterHealthCheck[index];
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingBridge implements Bridge {
  _PendingBridge(this.responses);

  final List<Object> responses;
  int pendingCalls = 0;
  final List<int> timeoutMsValues = <int>[];

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    if (request['cmd'] != 'inbox:retrieve_pending') {
      throw StateError('unexpected bridge command');
    }
    final payload = request['payload'] as Map<String, dynamic>;
    // The A6 replay probe calls `callP2PInboxRetrievePending` with no explicit
    // budget, so the field is genuinely absent on that path.
    final timeoutMs = payload['timeoutMs'] as num?;
    if (timeoutMs != null) timeoutMsValues.add(timeoutMs.toInt());
    final index = pendingCalls < responses.length
        ? pendingCalls
        : responses.length - 1;
    pendingCalls++;
    final outcome = responses[index];
    if (outcome is! Map<String, dynamic>) throw outcome;
    return jsonEncode(outcome);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnregisterBridge implements Bridge {
  _UnregisterBridge(this.responses);

  final List<Map<String, dynamic>> responses;
  int unregisterCalls = 0;

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    if (request['cmd'] != 'inbox:unregister_token') {
      throw StateError('unexpected bridge command');
    }
    final index = unregisterCalls < responses.length
        ? unregisterCalls
        : responses.length - 1;
    unregisterCalls++;
    return jsonEncode(responses[index]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Emits the staged->ack pair the A6 probe looks for from INSIDE the action.
///
/// `_observeReplayBeforeAck` installs its own E2E flow-event sink as its first
/// statement, so events emitted before the action starts are never seen.
class _ReplayEventMessageRepository implements MessageRepository {
  _ReplayEventMessageRepository(this.observations);

  final List<List<ConversationMessage>> observations;
  int reads = 0;

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async {
    if (reads == 0) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_STAGED_CHAT_COMMITTED',
        details: <String, dynamic>{
          'entryId': 'entry-1',
          'reasonCode': 'stored',
        },
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_SERVICE_INBOX_ACK_AFTER_STAGE_SUCCESS',
        details: <String, dynamic>{'requested': 1, 'acked': 1},
      );
    }
    final index = reads < observations.length ? reads : observations.length - 1;
    reads++;
    return observations[index];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SequenceMessageRepository implements MessageRepository {
  _SequenceMessageRepository(this.observations);

  final List<List<ConversationMessage>> observations;
  int reads = 0;

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async {
    final index = reads < observations.length ? reads : observations.length - 1;
    reads++;
    return observations[index];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedPushEnvelopeStagingStore implements PushEnvelopeStagingStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
