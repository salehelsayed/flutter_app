import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/push/infrastructure/received_wake_token_store_impl.dart';

import '../secure_storage/fake_secure_key_store.dart';
import '../../shared/fakes/in_memory_inbox_staging_repository.dart';

// FDC-09 §12 / CV-14 (217 §A3 / A07) — the single 1:1 `inbox:store` funnel
// (P2PServiceImpl.storeInInboxDetailed) threads the recipient-issued wake-token
// by toPeerId, omits it for peers with no received token, and serves the lookup
// from the store's in-memory cache (no per-message SecureKeyStore read).

/// Counts SecureKeyStore reads so the hot-path cache assertion is observable.
class _CountingSecureKeyStore implements SecureKeyStore {
  final FakeSecureKeyStore _inner = FakeSecureKeyStore();
  int readCount = 0;

  @override
  Future<String?> read(String key) {
    readCount++;
    return _inner.read(key);
  }

  @override
  Future<void> write(String key, String value) => _inner.write(key, value);

  @override
  Future<void> delete(String key) => _inner.delete(key);

  @override
  Future<bool> containsKey(String key) => _inner.containsKey(key);
}

/// Captures the `inbox:store` payload and returns a canned success.
class _CapturingBridge extends Bridge {
  _CapturingBridge({this.storeResponse = const <String, Object?>{'ok': true}});

  final Map<String, Object?> storeResponse;
  Map<String, dynamic>? lastStorePayload;

  @override
  bool get isInitialized => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<void> reinitialize() async {}
  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final req = jsonDecode(message) as Map<String, dynamic>;
    if (req['cmd'] == 'node:start') {
      return jsonEncode(<String, Object?>{
        'ok': true,
        'peerId': 'self-peer',
        'isStarted': true,
        'listenAddresses': <String>[],
        'circuitAddresses': <String>[],
        'connections': <Object?>[],
      });
    }
    if (req['cmd'] == 'inbox:store') {
      lastStorePayload = req['payload'] as Map<String, dynamic>;
      return jsonEncode(storeResponse);
    }
    return jsonEncode({'ok': true});
  }
}

void main() {
  const initialEnvelope =
      ' { "type": "chat_message", "version": "2", '
      '"id": "historical-message", "senderPeerId": "self-peer", '
      '"encrypted": { "kem": "kem", "ciphertext": "ciphertext", '
      '"nonce": "nonce" } }\n';
  const acceptedCustody = <String, Object?>{
    'ok': true,
    'storeStatus': 'stored',
    'custodyContract': ackOrExpiryInboxCustodyContract,
  };

  test('threads token by toPeerId; empty when absent; served from cache '
      '(no per-message SecureKeyStore read)', () async {
    final counting = _CountingSecureKeyStore();
    final received = ReceivedWakeTokenStoreImpl(secureKeyStore: counting);
    await received.writeTokenFor('peerB', 'tok-B', '2026-07-06T00:00:00.000Z');
    final readsAfterSeed = counting.readCount;

    final bridge = _CapturingBridge();
    final service = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: InMemoryInboxStagingRepository(),
      receivedWakeTokenStore: received,
    );
    addTearDown(service.dispose);
    await _startService(service);

    // Send to a peer WITH a received token → wakeToken attached.
    await service.storeInInboxDetailed('peerB', 'hello');
    expect(bridge.lastStorePayload?['wakeToken'], 'tok-B');

    // A SECOND send does NOT re-read SecureKeyStore (cache loaded once).
    await service.storeInInboxDetailed('peerB', 'hello again');
    expect(bridge.lastStorePayload?['wakeToken'], 'tok-B');
    expect(counting.readCount, readsAfterSeed);

    // Send to a peer with NO received token → wakeToken omitted.
    await service.storeInInboxDetailed('peerC', 'hi C');
    expect(bridge.lastStorePayload?.containsKey('wakeToken'), isFalse);
  });

  test(
    'E2E observer sees hashes only after an accepted real attachment',
    () async {
      final secureStore = _CountingSecureKeyStore();
      final received = ReceivedWakeTokenStoreImpl(secureKeyStore: secureStore);
      await received.writeTokenFor(
        'peerB',
        'opaque-token-B',
        '2026-07-15T00:00:00.000Z',
      );
      final observations = <Map<String, String>>[];
      final accepted = P2PServiceImpl(
        bridge: _CapturingBridge(),
        inboxStagingRepository: InMemoryInboxStagingRepository(),
        receivedWakeTokenStore: received,
        acceptedInboxWakeTokenHashObserver:
            ({
              required toPeerIdSha256,
              required messageSha256,
              required wakeTokenSha256,
            }) => observations.add(<String, String>{
              'peer': toPeerIdSha256,
              'message': messageSha256,
              'wake': wakeTokenSha256,
            }),
      );
      addTearDown(accepted.dispose);
      await _startService(accepted);

      await accepted.storeInInboxDetailed('peerB', 'exact-message');
      expect(observations, hasLength(1));
      expect(observations.single, <String, String>{
        'peer': sha256.convert(utf8.encode('peerB')).toString(),
        'message': sha256.convert(utf8.encode('exact-message')).toString(),
        'wake': sha256.convert(utf8.encode('opaque-token-B')).toString(),
      });
      expect(jsonEncode(observations), isNot(contains('opaque-token-B')));

      final rejected = P2PServiceImpl(
        bridge: _CapturingBridge(
          storeResponse: const <String, Object?>{'ok': false},
        ),
        inboxStagingRepository: InMemoryInboxStagingRepository(),
        receivedWakeTokenStore: received,
        acceptedInboxWakeTokenHashObserver:
            ({
              required toPeerIdSha256,
              required messageSha256,
              required wakeTokenSha256,
            }) => observations.add(<String, String>{
              'unexpected': wakeTokenSha256,
            }),
      );
      addTearDown(rejected.dispose);
      await _startService(rejected);
      await rejected.storeInInboxDetailed('peerB', 'rejected-message');
      expect(observations, hasLength(1));

      final throwingObserver = P2PServiceImpl(
        bridge: _CapturingBridge(),
        inboxStagingRepository: InMemoryInboxStagingRepository(),
        receivedWakeTokenStore: received,
        acceptedInboxWakeTokenHashObserver:
            ({
              required toPeerIdSha256,
              required messageSha256,
              required wakeTokenSha256,
            }) => throw StateError('observer failure'),
      );
      addTearDown(throwingObserver.dispose);
      await _startService(throwingObserver);
      final outcome = await throwingObserver.storeInInboxDetailed(
        'peerB',
        'observer-must-not-change-outcome',
      );
      expect(outcome.accepted, isTrue);
    },
  );

  test(
    'awaits a fresh history decision before each exact direct STORE',
    () async {
      final received = ReceivedWakeTokenStoreImpl(
        secureKeyStore: FakeSecureKeyStore(),
      );
      await received.writeTokenFor(
        'peerB',
        'tok-B',
        '2026-07-06T00:00:00.000Z',
      );
      final bridge = _CapturingBridge(storeResponse: acceptedCustody);
      final checks = <(String, String)>[];
      final firstCheckEntered = Completer<void>();
      var decision = Completer<bool>();
      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
        receivedWakeTokenStore: received,
        shouldSuppressDirectInboxNotification: (peerId, wireEnvelope) {
          checks.add((peerId, wireEnvelope));
          if (!firstCheckEntered.isCompleted) firstCheckEntered.complete();
          return decision.future;
        },
      );
      addTearDown(service.dispose);
      await _startService(service);

      final pendingStore = service.storeInAckCustodyInboxDetailed(
        'peerB',
        initialEnvelope,
        custodyKind: AckCustodyKind.directTextV108,
      );
      await firstCheckEntered.future;
      expect(bridge.lastStorePayload, isNull);
      decision.complete(true);
      expect((await pendingStore).ackOrExpiryAccepted, isTrue);
      expect(bridge.lastStorePayload, <String, dynamic>{
        'toPeerId': 'peerB',
        'message': initialEnvelope,
        'wakeToken': 'tok-B',
        'suppressNotification': true,
        'custodyContract': ackOrExpiryInboxCustodyContract,
        'custodyKind': 'direct_text_v108',
      });

      decision = Completer<bool>()..complete(false);
      final retry = await service.storeInAckCustodyInboxDetailed(
        'peerB',
        initialEnvelope,
        custodyKind: AckCustodyKind.directTextV108,
      );
      expect(retry.ackOrExpiryAccepted, isTrue);
      expect(checks, <(String, String)>[
        ('peerB', initialEnvelope),
        ('peerB', initialEnvelope),
      ]);
      expect(bridge.lastStorePayload?['message'], initialEnvelope);
      expect(bridge.lastStorePayload?['wakeToken'], 'tok-B');
      expect(
        bridge.lastStorePayload?.containsKey('suppressNotification'),
        isFalse,
      );
    },
  );

  for (final mode in ['absent', 'false', 'throws']) {
    test(
      '$mode history callback preserves accepted custody without suppression',
      () async {
        final bridge = _CapturingBridge(storeResponse: acceptedCustody);
        var checks = 0;
        final service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: InMemoryInboxStagingRepository(),
          shouldSuppressDirectInboxNotification: mode == 'absent'
              ? null
              : (peerId, wireEnvelope) async {
                  checks++;
                  expect(peerId, 'peerB');
                  expect(wireEnvelope, initialEnvelope);
                  if (mode == 'throws') throw StateError('history unavailable');
                  return false;
                },
        );
        addTearDown(service.dispose);
        await _startService(service);

        final outcome = await service.storeInAckCustodyInboxDetailed(
          'peerB',
          initialEnvelope,
          custodyKind: AckCustodyKind.directTextV108,
        );

        expect(outcome.ackOrExpiryAccepted, isTrue);
        expect(checks, mode == 'absent' ? 0 : 1);
        expect(bridge.lastStorePayload, <String, dynamic>{
          'toPeerId': 'peerB',
          'message': initialEnvelope,
          'custodyContract': ackOrExpiryInboxCustodyContract,
          'custodyKind': 'direct_text_v108',
        });
      },
    );
  }

  test(
    'other custody kinds and edits never consult initial-message history',
    () async {
      final bridge = _CapturingBridge(storeResponse: acceptedCustody);
      var checks = 0;
      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
        shouldSuppressDirectInboxNotification: (_, _) async {
          checks++;
          return true;
        },
      );
      addTearDown(service.dispose);
      await _startService(service);

      for (final kind in [
        AckCustodyKind.directMutationV109,
        AckCustodyKind.groupContentV1,
      ]) {
        final outcome = await service.storeInAckCustodyInboxDetailed(
          'peerB',
          initialEnvelope,
          custodyKind: kind,
        );
        expect(outcome.ackOrExpiryAccepted, isTrue);
        expect(bridge.lastStorePayload?['message'], initialEnvelope);
        expect(bridge.lastStorePayload?['custodyKind'], kind.wireValue);
        expect(
          bridge.lastStorePayload?.containsKey('suppressNotification'),
          isFalse,
        );
      }

      for (final eventId in ['edit-event', null]) {
        final mutationEnvelope = jsonEncode({
          ...jsonDecode(initialEnvelope) as Map<String, dynamic>,
          'eventId': eventId,
        });
        final outcome = await service.storeInAckCustodyInboxDetailed(
          'peerB',
          mutationEnvelope,
          custodyKind: AckCustodyKind.directTextV108,
        );
        expect(outcome.ackOrExpiryAccepted, isTrue);
        expect(bridge.lastStorePayload?['message'], mutationEnvelope);
        expect(
          bridge.lastStorePayload?.containsKey('suppressNotification'),
          isFalse,
        );
      }

      final legacy = await service.storeInInboxDetailed(
        'peerB',
        initialEnvelope,
      );
      expect(legacy.accepted, isTrue);
      expect(bridge.lastStorePayload?['message'], initialEnvelope);
      expect(
        bridge.lastStorePayload?.containsKey('suppressNotification'),
        isFalse,
      );
      expect(checks, 0);
    },
  );
}

Future<void> _startService(P2PServiceImpl service) async {
  expect(
    await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer'),
    isTrue,
  );
}
