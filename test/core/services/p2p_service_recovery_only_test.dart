import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/fakes/fake_push_token_store.dart';
import '../../shared/fakes/in_memory_inbox_staging_repository.dart';
import '../local_discovery/fake_local_p2p_service.dart';

final class _RecoveryBridge extends Bridge {
  final Map<
    String,
    FutureOr<Map<String, dynamic>> Function(Map<String, dynamic>)
  >
  _handlers = {};
  final List<String> commands = [];
  final Map<String, List<Map<String, dynamic>>> payloads = {};

  void when(
    String command,
    FutureOr<Map<String, dynamic>> Function(Map<String, dynamic>) handler,
  ) {
    _handlers[command] = handler;
  }

  @override
  bool get isInitialized => true;

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final command = request['cmd'] as String;
    final payload =
        (request['payload'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    commands.add(command);
    payloads.putIfAbsent(command, () => []).add(payload);
    final handler = _handlers[command];
    return jsonEncode(
      handler == null
          ? <String, dynamic>{
              'ok': false,
              'errorCode': 'UNHANDLED',
              'errorMessage': command,
            }
          : await handler(payload),
    );
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}
}

final class _ThrowingRecoveryRepository extends InMemoryInboxStagingRepository {
  @override
  Future<List<InboxStagingEntry>> getRecoverableEntries({int limit = 50}) =>
      Future<List<InboxStagingEntry>>.error(
        StateError('recovery snapshot failed'),
      );
}

Map<String, dynamic> _nodeState({
  required String peerId,
  bool isStarted = true,
}) => <String, dynamic>{
  'ok': true,
  'peerId': peerId,
  'isStarted': isStarted,
  'listenAddresses': <String>[],
  'circuitAddresses': <String>[],
  'connections': <dynamic>[],
  'relayState': 'online',
  'healthyRelayCount': 1,
};

String _chatEnvelope(String id) => jsonEncode(<String, dynamic>{
  'type': 'chat_message',
  'version': '1',
  'payload': <String, dynamic>{
    'id': id,
    'text': 'recovery',
    'senderPeerId': 'remote-peer',
    'senderUsername': 'Remote',
    'timestamp': '2026-08-16T00:00:00.000Z',
  },
});

ChatMessage _directMessage(String nonce) => ChatMessage(
  from: 'remote-peer',
  to: 'self-peer',
  content: _chatEnvelope(nonce),
  timestamp: '2026-08-16T00:00:00.000Z',
  isIncoming: true,
  transport: 'direct',
  confirmNonce: nonce,
);

InboxStagingEntry _protectedEntry(
  String entryId, {
  String status = 'pending',
  String? rejectReasonCode,
}) => InboxStagingEntry(
  entryId: entryId,
  ownerPeerId: 'self-peer',
  senderPeerId: 'remote-peer',
  messageType: 'group_content_v1',
  relayTimestamp: '2026-08-16T00:00:00.000Z',
  envelope: jsonEncode(<String, dynamic>{'type': 'group_content_v1'}),
  status: status,
  rejectReasonCode: rejectReasonCode,
  stagedAt: '2026-08-16T00:00:00.000Z',
);

void main() {
  const privateKey = 'cHJpdmF0ZWtleXRlc3Q=';

  test(
    'recovery-only start disables registration and foreground side effects while health is status-only',
    () async {
      final bridge = _RecoveryBridge()
        ..when('node:start', (_) => _nodeState(peerId: 'self-peer'))
        ..when('node:status', (_) => _nodeState(peerId: 'self-peer'));
      final pushTokens = FakePushTokenStore();
      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
        pushTokenStore: pushTokens,
        recoveryOnly: true,
      );
      addTearDown(service.dispose);

      expect(
        await service.startRecoveryOnlyNode(privateKey, 'self-peer'),
        isTrue,
      );
      expect(bridge.payloads['node:start']!.single['autoRegister'], isFalse);
      expect(pushTokens.readCallCount, 0);
      expect(bridge.commands, isNot(contains('inbox:retrieve')));
      expect(bridge.commands, isNot(contains('push:register')));
      expect(bridge.commands, isNot(contains('relay:reconnect')));

      final beforeUnsafeCalls = List<String>.of(bridge.commands);
      expect(await service.startNode(privateKey, 'self-peer'), isFalse);
      expect(await service.startNodeCore(privateKey, 'self-peer'), isFalse);
      expect(await service.registerPushToken('token', 'android'), isFalse);
      await service.warmBackground();
      await service.warmPeer('remote-peer');
      await service.startEarlyLocalDiscovery();
      await service.performImmediateHealthCheck();
      expect(bridge.commands, beforeUnsafeCalls);

      expect(
        await service.checkRecoveryNodeHealth(expectedPeerId: 'self-peer'),
        isTrue,
      );
      expect(
        bridge.commands.where((value) => value == 'node:status'),
        hasLength(1),
      );
      expect(bridge.commands, isNot(contains('relay:reconnect')));
      expect(bridge.commands, isNot(contains('inbox:retrieve')));
    },
  );

  test(
    'recovery-only start refuses a non-started or mismatched node',
    () async {
      final notStartedBridge = _RecoveryBridge()
        ..when(
          'node:start',
          (_) => _nodeState(peerId: 'self-peer', isStarted: false),
        );
      final notStarted = P2PServiceImpl(
        bridge: notStartedBridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
        recoveryOnly: true,
      );
      addTearDown(notStarted.dispose);
      expect(
        await notStarted.startRecoveryOnlyNode(privateKey, 'self-peer'),
        isFalse,
      );

      final mismatchBridge = _RecoveryBridge()
        ..when('node:start', (_) => _nodeState(peerId: 'wrong-peer'))
        ..when('node:stop', (_) => <String, dynamic>{'ok': true});
      final mismatch = P2PServiceImpl(
        bridge: mismatchBridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
        recoveryOnly: true,
      );
      addTearDown(mismatch.dispose);
      expect(
        await mismatch.startRecoveryOnlyNode(privateKey, 'self-peer'),
        isFalse,
      );
      expect(mismatchBridge.commands, contains('node:stop'));
    },
  );

  test(
    'recovery admission seal awaits admitted direct work and synchronously refuses later callbacks',
    () async {
      final bridge = _RecoveryBridge()
        ..when('node:start', (_) => _nodeState(peerId: 'self-peer'))
        ..when('message:confirm', (_) => <String, dynamic>{'ok': true});
      final repo = InMemoryInboxStagingRepository();
      final enteredHandler = Completer<void>();
      final releaseHandler = Completer<void>();
      var handlerCalls = 0;
      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: repo,
        recoveryOnly: true,
        replayLiveDirectChatMessage: (message, {stagedEntryId}) async {
          handlerCalls++;
          enteredHandler.complete();
          await releaseHandler.future;
          return (
            disposition: RecoveredInboxChatDisposition.committed,
            reasonCode: 'committed',
            reasonDetail: null,
          );
        },
      );
      addTearDown(service.dispose);
      expect(
        await service.startRecoveryOnlyNode(privateKey, 'self-peer'),
        isTrue,
      );

      bridge.onMessageReceived!.call(_directMessage('before-seal'));
      await enteredHandler.future;

      var sealCompleted = false;
      final sealed = service.sealRecoveryAdmissionAndAwaitInFlight().then((_) {
        sealCompleted = true;
      });
      expect(service.recoveryAdmissionRefusedAfterSeal, isFalse);
      bridge.onMessageReceived!.call(_directMessage('after-seal'));
      expect(service.recoveryAdmissionRefusedAfterSeal, isTrue);
      await Future<void>.delayed(Duration.zero);

      expect(sealCompleted, isFalse);
      expect(handlerCalls, 1);
      expect(repo.entry('direct:after-seal'), isNull);
      expect(
        bridge.commands.where((command) => command == 'message:confirm'),
        hasLength(1),
      );

      releaseHandler.complete();
      await sealed;
      expect(sealCompleted, isTrue);
      expect(handlerCalls, 1);
      expect(repo.entry('direct:before-seal'), isNull);
    },
  );

  test(
    'recovery drain retains an already-durable row when its typed handler is absent',
    () async {
      final bridge = _RecoveryBridge()
        ..when('node:start', (_) => _nodeState(peerId: 'self-peer'))
        ..when(
          'inbox:retrieve_pending',
          (_) => <String, dynamic>{
            'ok': true,
            'messages': <dynamic>[],
            'hasMore': false,
            'custodyContract': ackOrExpiryInboxCustodyContract,
          },
        );
      final repo = InMemoryInboxStagingRepository()
        ..seed(
          InboxStagingEntry(
            entryId: 'already-durable',
            ownerPeerId: 'self-peer',
            senderPeerId: 'remote-peer',
            messageType: 'chat_message',
            relayTimestamp: '2026-08-16T00:00:00.000Z',
            envelope: _chatEnvelope('already-durable'),
            stagedAt: '2026-08-16T00:00:00.000Z',
          ),
        )
        ..seed(
          InboxStagingEntry(
            entryId: 'self-readiness',
            ownerPeerId: 'self-peer',
            senderPeerId: 'self-peer',
            messageType: 'readiness_proof',
            relayTimestamp: '2026-08-16T00:00:00.000Z',
            envelope: jsonEncode(<String, dynamic>{
              'type': 'readiness_proof',
              'version': '1',
            }),
            stagedAt: '2026-08-16T00:00:00.000Z',
          ),
        )
        ..seed(
          InboxStagingEntry(
            entryId: 'foreign-readiness',
            ownerPeerId: 'self-peer',
            senderPeerId: 'remote-peer',
            messageType: 'readiness_proof',
            relayTimestamp: '2026-08-16T00:00:00.000Z',
            envelope: jsonEncode(<String, dynamic>{
              'type': 'readiness_proof',
              'version': '1',
            }),
            stagedAt: '2026-08-16T00:00:00.000Z',
          ),
        );
      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: repo,
        recoveryOnly: true,
      );
      addTearDown(service.dispose);
      var genericMessages = 0;
      final subscription = service.messageStream.listen((_) {
        genericMessages++;
      });
      addTearDown(subscription.cancel);

      expect(
        await service.startRecoveryOnlyNode(privateKey, 'self-peer'),
        isTrue,
      );
      final outcome = await service.drainOfflineInboxFully();

      expect(outcome.isSuccessful, isFalse);
      expect(outcome.hasMore, isTrue);
      expect(repo.entry('already-durable')?.status, 'retryable');
      expect(
        repo.entry('already-durable')?.rejectReasonCode,
        'typed_handler_unavailable',
      );
      expect(repo.entry('self-readiness'), isNull);
      expect(repo.entry('foreign-readiness')?.status, 'retryable');
      expect(
        repo.entry('foreign-readiness')?.rejectReasonCode,
        'typed_handler_unavailable',
      );
      expect(genericMessages, 0);
      expect(bridge.commands, isNot(contains('inbox:ack')));
      expect(bridge.commands, isNot(contains('inbox:store')));
    },
  );

  test('recovery seal awaits admitted LAN staged replay', () async {
    final bridge = _RecoveryBridge()
      ..when('node:start', (_) => _nodeState(peerId: 'self-peer'));
    final local = FakeLocalP2PService();
    final repo = InMemoryInboxStagingRepository();
    final enteredHandler = Completer<void>();
    final releaseHandler = Completer<void>();
    var handlerCalls = 0;
    final service = P2PServiceImpl(
      bridge: bridge,
      localP2PService: local,
      inboxStagingRepository: repo,
      recoveryOnly: true,
      replayLiveLanChatMessage: (message, {stagedEntryId}) async {
        handlerCalls++;
        enteredHandler.complete();
        await releaseHandler.future;
        return (
          disposition: RecoveredInboxChatDisposition.committed,
          reasonCode: 'committed',
          reasonDetail: null,
        );
      },
    );
    addTearDown(service.dispose);
    expect(
      await service.startRecoveryOnlyNode(privateKey, 'self-peer'),
      isTrue,
    );

    final first = await local.inboundChatCommitHandler!(
      LocalChatMessage(
        from: 'remote-peer',
        to: 'self-peer',
        content: _chatEnvelope('lan-before'),
        timestamp: DateTime.utc(2026, 8, 16),
        isIncoming: true,
      ),
      nonce: 'lan-before',
    );
    expect(first.isCommitted, isTrue);
    await enteredHandler.future;

    final sealed = service.sealRecoveryAdmissionAndAwaitInFlight();
    final refused = await local.inboundChatCommitHandler!(
      LocalChatMessage(
        from: 'remote-peer',
        to: 'self-peer',
        content: _chatEnvelope('lan-after'),
        timestamp: DateTime.utc(2026, 8, 16),
        isIncoming: true,
      ),
      nonce: 'lan-after',
    );
    expect(refused.isRejected, isTrue);
    expect(refused.reason, 'recovery_admission_sealed');
    expect(service.recoveryAdmissionRefusedAfterSeal, isTrue);

    releaseHandler.complete();
    await sealed;
    expect(handlerCalls, 1);
    expect(repo.entry('lan:lan-before'), isNull);
    expect(repo.entry('lan:lan-after'), isNull);
  });

  test(
    'recovery seal awaits protected replay and refuses a later drain',
    () async {
      final bridge = _RecoveryBridge()
        ..when('node:start', (_) => _nodeState(peerId: 'self-peer'))
        ..when(
          'inbox:retrieve_pending',
          (_) => <String, dynamic>{
            'ok': true,
            'messages': <dynamic>[],
            'hasMore': false,
            'custodyContract': ackOrExpiryInboxCustodyContract,
          },
        );
      final repo = InMemoryInboxStagingRepository()
        ..seed(
          InboxStagingEntry(
            entryId: 'protected-before',
            ownerPeerId: 'self-peer',
            senderPeerId: 'remote-peer',
            messageType: 'group_content_v1',
            relayTimestamp: '2026-08-16T00:00:00.000Z',
            envelope: jsonEncode(<String, dynamic>{'type': 'group_content_v1'}),
            stagedAt: '2026-08-16T00:00:00.000Z',
          ),
        );
      final enteredHandler = Completer<void>();
      final releaseHandler = Completer<void>();
      var handlerCalls = 0;
      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: repo,
        recoveryOnly: true,
        replayRecoveredProtectedGroupEnvelope: (message) async {
          handlerCalls++;
          enteredHandler.complete();
          await releaseHandler.future;
          return (
            disposition: ProtectedGroupReplayDisposition.applied,
            reasonCode: 'applied',
            reasonDetail: null,
          );
        },
      );
      addTearDown(service.dispose);
      expect(
        await service.startRecoveryOnlyNode(privateKey, 'self-peer'),
        isTrue,
      );

      final admittedDrain = service.drainOfflineInboxFully();
      await enteredHandler.future;
      final sealed = service.sealRecoveryAdmissionAndAwaitInFlight();
      final refusedDrain = await service.drainOfflineInboxFully();
      expect(refusedDrain.failureReason, 'recovery_admission_sealed');
      expect(service.recoveryAdmissionRefusedAfterSeal, isTrue);

      releaseHandler.complete();
      await admittedDrain;
      await sealed;
      expect(handlerCalls, 1);
    },
  );

  test('recovery seal surfaces the first admitted callback error', () async {
    final callbackEntered = Completer<void>();
    final bridge = _RecoveryBridge()
      ..when('node:start', (_) => _nodeState(peerId: 'self-peer'));
    final service = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: InMemoryInboxStagingRepository(),
      recoveryOnly: true,
      accountMigrationNetworkGate: ({peerId, required operation}) async {
        if (operation == 'p2p_inbound_message') {
          callbackEntered.complete();
          throw StateError('admitted callback failed');
        }
        return true;
      },
    );
    addTearDown(service.dispose);
    expect(
      await service.startRecoveryOnlyNode(privateKey, 'self-peer'),
      isTrue,
    );

    bridge.onMessageReceived!.call(_directMessage('throws'));
    await callbackEntered.future;
    await expectLater(
      service.sealRecoveryAdmissionAndAwaitInFlight(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'admitted callback failed',
        ),
      ),
    );
  });

  test(
    'typed protected recovery drain distinguishes reached fixed point',
    () async {
      final bridge = _RecoveryBridge()
        ..when('node:start', (_) => _nodeState(peerId: 'self-peer'))
        ..when(
          'inbox:retrieve_pending',
          (_) => <String, dynamic>{
            'ok': true,
            'messages': <dynamic>[],
            'hasMore': false,
            'custodyContract': ackOrExpiryInboxCustodyContract,
          },
        );
      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
        recoveryOnly: true,
      );
      addTearDown(service.dispose);
      expect(
        await service.startRecoveryOnlyNode(privateKey, 'self-peer'),
        isTrue,
      );

      final outcome = await service
          .drainProtectedGroupContentRecoveryFixedPoint();

      expect(
        outcome.disposition,
        ProtectedGroupRecoveryFixedPointDisposition.reachedFixedPoint,
      );
      expect(outcome.passes, 1);
      expect(outcome.isSuccessful, isTrue);
      expect(outcome.hasMore, isFalse);
      expect(outcome.failureReason, isNull);
    },
  );

  test('typed protected recovery drain distinguishes a local stall', () async {
    final bridge = _RecoveryBridge()
      ..when('node:start', (_) => _nodeState(peerId: 'self-peer'))
      ..when(
        'inbox:retrieve_pending',
        (_) => <String, dynamic>{
          'ok': true,
          'messages': <dynamic>[],
          'hasMore': false,
          'custodyContract': ackOrExpiryInboxCustodyContract,
        },
      );
    final repo = InMemoryInboxStagingRepository()
      ..seed(
        _protectedEntry(
          'protected-stalled',
          status: 'retryable',
          rejectReasonCode: 'missing_group_key',
        ),
      );
    final service = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: repo,
      recoveryOnly: true,
      replayRecoveredProtectedGroupEnvelope: (_) async => (
        disposition: ProtectedGroupReplayDisposition.prerequisiteWaiting,
        reasonCode: 'missing_group_key',
        reasonDetail: null,
      ),
    );
    addTearDown(service.dispose);
    expect(
      await service.startRecoveryOnlyNode(privateKey, 'self-peer'),
      isTrue,
    );

    final outcome = await service.drainProtectedGroupContentRecoveryFixedPoint(
      maxPasses: 3,
    );

    expect(
      outcome.disposition,
      ProtectedGroupRecoveryFixedPointDisposition.stalled,
    );
    expect(outcome.passes, 1);
    expect(outcome.isSuccessful, isFalse);
    expect(outcome.hasMore, isTrue);
    expect(outcome.failureReason, 'protected_group_recovery_stalled');
  });

  test('typed protected recovery drain distinguishes a failed pass', () async {
    final bridge = _RecoveryBridge()
      ..when('node:start', (_) => _nodeState(peerId: 'self-peer'))
      ..when(
        'inbox:retrieve_pending',
        (_) => <String, dynamic>{
          'ok': false,
          'errorMessage': 'relay_unavailable',
        },
      );
    final service = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: InMemoryInboxStagingRepository(),
      recoveryOnly: true,
    );
    addTearDown(service.dispose);
    expect(
      await service.startRecoveryOnlyNode(privateKey, 'self-peer'),
      isTrue,
    );

    final outcome = await service
        .drainProtectedGroupContentRecoveryFixedPoint();

    expect(
      outcome.disposition,
      ProtectedGroupRecoveryFixedPointDisposition.failed,
    );
    expect(outcome.passes, 1);
    expect(outcome.isSuccessful, isFalse);
    expect(outcome.hasMore, isTrue);
    expect(outcome.failureReason, 'relay_unavailable');
  });

  test(
    'typed protected recovery drain converts snapshot errors to failed',
    () async {
      final bridge = _RecoveryBridge()
        ..when('node:start', (_) => _nodeState(peerId: 'self-peer'));
      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: _ThrowingRecoveryRepository(),
        recoveryOnly: true,
      );
      addTearDown(service.dispose);
      expect(
        await service.startRecoveryOnlyNode(privateKey, 'self-peer'),
        isTrue,
      );

      final outcome = await service
          .drainProtectedGroupContentRecoveryFixedPoint();

      expect(
        outcome.disposition,
        ProtectedGroupRecoveryFixedPointDisposition.failed,
      );
      expect(outcome.passes, 0);
      expect(
        outcome.failureReason,
        'protected_group_recovery_exception:StateError',
      );
    },
  );

  test(
    'typed protected recovery drain distinguishes max-pass exhaustion and preserves the legacy count',
    () async {
      final bridge = _RecoveryBridge()
        ..when('node:start', (_) => _nodeState(peerId: 'self-peer'))
        ..when(
          'inbox:retrieve_pending',
          (_) => <String, dynamic>{
            'ok': true,
            'messages': <dynamic>[],
            'hasMore': false,
            'custodyContract': ackOrExpiryInboxCustodyContract,
          },
        );
      final repo = InMemoryInboxStagingRepository()
        ..seed(_protectedEntry('protected-progressing'));
      var replayCalls = 0;
      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: repo,
        recoveryOnly: true,
        replayRecoveredProtectedGroupEnvelope: (_) async {
          replayCalls++;
          return (
            disposition: ProtectedGroupReplayDisposition.retryable,
            reasonCode: 'retry_$replayCalls',
            reasonDetail: null,
          );
        },
      );
      addTearDown(service.dispose);
      expect(
        await service.startRecoveryOnlyNode(privateKey, 'self-peer'),
        isTrue,
      );

      final outcome = await service
          .drainProtectedGroupContentRecoveryFixedPoint(maxPasses: 2);

      expect(
        outcome.disposition,
        ProtectedGroupRecoveryFixedPointDisposition.maxPassesReached,
      );
      expect(outcome.passes, 2);
      expect(
        outcome.failureReason,
        'protected_group_recovery_max_passes_reached',
      );

      // The established foreground/source contract remains an integer count.
      expect(
        await service.drainProtectedGroupContentFixedPoint(maxPasses: 1),
        1,
      );
    },
  );

  test('post-seal typed drain refusal latches fail-closed state', () async {
    final service = P2PServiceImpl(
      bridge: _RecoveryBridge(),
      inboxStagingRepository: InMemoryInboxStagingRepository(),
      recoveryOnly: true,
    );
    addTearDown(service.dispose);

    await service.sealRecoveryAdmissionAndAwaitInFlight();
    expect(service.recoveryAdmissionRefusedAfterSeal, isFalse);

    final outcome = await service
        .drainProtectedGroupContentRecoveryFixedPoint();

    expect(
      outcome.disposition,
      ProtectedGroupRecoveryFixedPointDisposition.failed,
    );
    expect(outcome.failureReason, 'recovery_admission_sealed');
    expect(service.recoveryAdmissionRefusedAfterSeal, isTrue);
  });
}
