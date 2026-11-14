import 'dart:convert';
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_app/features/contact_request/application/key_exchange_retry_coordinator.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/contact_request/application/mlkem_reannounce_marker.dart';
import 'package:flutter_app/features/contact_request/application/wake_token_pending_marker.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_cleanup.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_staging.dart';
import 'package:flutter_app/features/contact_request/application/retry_incomplete_key_exchanges_use_case.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_repair_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

const _journalKey = 'contact_request_retry_journal_v1';
const _peer = 'retry-recipient';

ContactModel _contact(DateTime scannedAt, {String peer = _peer}) =>
    ContactModel(
      peerId: peer,
      publicKey: 'recipient-key-$peer',
      rendezvous: '/p2p-circuit/relay',
      username: 'Recipient',
      signature: 'qr-signature',
      scannedAt: scannedAt.toUtc().toIso8601String(),
    );

IdentityModel _identity(String account) => IdentityModel(
  peerId: account,
  publicKey: '$account-public-key',
  privateKey: '$account-private-key',
  mnemonic12: 'one two three four five six seven eight nine ten eleven twelve',
  mlKemPublicKey: '$account-mlkem',
  mlKemSecretKey: '$account-mlkem-secret',
  createdAt: '2026-11-12T00:00:00Z',
  updatedAt: '2026-11-12T00:00:00Z',
);

FakeP2PService _transport() => FakeP2PService(
  initialState: const NodeState(
    isStarted: true,
    peerId: 'sender-account',
    circuitAddresses: ['/p2p-circuit/relay'],
  ),
)..storeInInboxResult = true;

class _FailingJournalStore extends FakeSecureKeyStore {
  @override
  Future<void> write(String key, String value) async {
    if (key == _journalKey) throw StateError('journal write unavailable');
    return super.write(key, value);
  }
}

class _JournalWriteHookStore extends FakeSecureKeyStore {
  _JournalWriteHookStore(this.onJournalWrite);
  final void Function(String value) onJournalWrite;

  @override
  Future<void> write(String key, String value) async {
    await super.write(key, value);
    if (key == _journalKey) onJournalWrite(value);
  }
}

class _SigningHookBridge extends FakeBridge {
  _SigningHookBridge(this.onSign);
  final void Function() onSign;

  @override
  Future<String> send(String message) {
    if ((jsonDecode(message) as Map)['cmd'] == 'payload.sign') onSign();
    return super.send(message);
  }
}

void main() {
  late DateTime now;
  late FakeContactRepository contacts;
  late FakeIdentityRepository identities;
  late FakeSecureKeyStore store;
  late FakeP2PService transport;
  late FakeBridge bridge;
  ContactRelationshipState? consent;
  String? wakeToken;
  CallWakeHandleGrant? callGrant;
  var pendingCall = false;
  void Function()? onReadConsent;

  setUp(() {
    now = DateTime.utc(2026, 11, 12);
    contacts = FakeContactRepository()..seed([_contact(now)]);
    identities = FakeIdentityRepository()..seed(_identity('sender-account'));
    store = FakeSecureKeyStore();
    transport = _transport();
    bridge = FakeBridge();
    bridge.responses['payload.sign'] = {'ok': true, 'signature': 'signature'};
    bridge.responses['contactrequest.encrypt'] = {
      'ok': true,
      'ephemeralPublicKey': 'ephemeral-key',
      'ciphertext': 'ciphertext',
      'nonce': 'nonce',
    };
    consent = null;
    wakeToken = null;
    callGrant = null;
    pendingCall = false;
    onReadConsent = null;
  });
  tearDown(() => transport.dispose());

  Future<int> retry({bool durableStore = true}) => withClock(
    Clock(() => now),
    () => retryIncompleteKeyExchanges(
      contactRepo: contacts,
      identityRepo: identities,
      p2pService: transport,
      bridge: bridge,
      secureKeyStore: durableStore ? store : null,
      resolveWakeToken: (_) async => wakeToken,
      resolveCallWakeHandle: (_) async => callGrant,
      loadPendingCallWakeHandleContactIds: () async =>
          pendingCall ? [_peer] : [],
      readConsent: (_) async {
        onReadConsent?.call();
        return consent == null
            ? null
            : ContactRelationshipConsent(
                state: consent!,
                revision: 1,
                updatedAtMs: now.millisecondsSinceEpoch,
              );
      },
    ),
  );

  Future<int> freshRetry() => KeyExchangeRetryCoordinator(
    now: () => now,
    performRetry: retry,
  ).retryNow(trigger: 'wake_token_registered', requireFresh: true);

  List<dynamic> entries(String raw) =>
      (jsonDecode(raw) as Map<String, dynamic>)['entries'] as List<dynamic>;

  CallWakeHandleGrant grant(int generation) => CallWakeHandleGrant(
    handle: generation == 1
        ? '0123456789abcdef0123456789abcdef'
        : 'fedcba9876543210fedcba9876543210',
    recipientDevicePeerId: 'recipientdevice123',
    deviceKeyEpoch: 7,
    generation: generation,
    issuedAtMs: 1,
    expiresAtMs: CallWakeHandleGrant.maxSafeInteger,
  );
  Future<void> stage(String marker) async {
    switch (marker) {
      case 'mlkem':
        await queueMlKemReannouncePeer(store, _peer);
      case 'wake':
        wakeToken = 'wake-one';
        await reconcileWakeTokenDistribution(
          secureKeyStore: store,
          registeredTokens: {_peer: wakeToken!},
        );
      case 'call':
        pendingCall = true;
        callGrant = grant(1);
    }
  }

  test('BL24-CLK injected future clock signs and sends one durable retry', () async {
    now = DateTime.now().toUtc().add(const Duration(days: 2));
    contacts.seed([_contact(now.subtract(const Duration(hours: 1)))]);

    final sent = await retry();
    final raw = await store.read(_journalKey);
    expect(raw, isNotNull);
    final entry = entries(raw!).single as Map;
    final envelope = entry['envelope'] as Map?;
    expect(
      {
        'sent': sent,
        'transmissions': transport.storeInInboxCallCount,
        'signedAtMs': envelope?['signedAtMs'],
      },
      {
        'sent': 1,
        'transmissions': 1,
        'signedAtMs': now.millisecondsSinceEpoch,
      },
    );
    final signCommand = bridge.sentMessages
        .map((message) => jsonDecode(message) as Map<String, dynamic>)
        .singleWhere((command) => command['cmd'] == 'payload.sign');
    final signed =
        jsonDecode((signCommand['payload'] as Map)['data'] as String) as Map;
    expect(DateTime.parse(signed['ts'] as String), now);
    final wire = jsonDecode(transport.lastStoreInInboxMessage!) as Map;
    expect(wire['ts'], now.toIso8601String());
    expect(bridge.commandLog.indexOf('contactrequest.encrypt'),
        greaterThan(bridge.commandLog.indexOf('payload.sign')));
  });

  for (final marker in ['mlkem', 'wake', 'call']) {
    test(
      'BL24E2 $marker dormant retries keep exact id back off and expire',
      () async {
        await stage(marker);
        transport.storeInInboxResult = false;
        await retry();
        expect(transport.storeInInboxCallCount, 1);
        final first = transport.lastStoreInInboxMessage;
        now = now.add(const Duration(minutes: 1));
        await retry();
        expect(
          transport.storeInInboxCallCount,
          1,
          reason: 'marker jobs share dormant backoff',
        );
        now = now.add(const Duration(minutes: 59));
        await retry();
        expect(transport.storeInInboxCallCount, 2);
        expect(transport.lastStoreInInboxMessage, first);
        expect((jsonDecode(first!) as Map)['intent'], 'key_exchange_retry');
        now = now.add(const Duration(days: 7));
        await retry();
        expect(transport.storeInInboxCallCount, 2);
      },
    );
    test(
      'BL24E2 $marker keyed marker keeps original fresh send path',
      () async {
        contacts.seed([
          _contact(now).copyWith(mlKemPublicKey: 'completed-key'),
        ]);
        await stage(marker);
        transport.storeInInboxResult = false;
        await retry();
        final first = transport.lastStoreInInboxMessage;
        expect(transport.storeInInboxCallCount, 1);
        now = now.add(const Duration(minutes: 1));
        await retry();
        expect(transport.storeInInboxCallCount, 2);
        expect(transport.lastStoreInInboxMessage, isNot(first));
        expect(await store.read(_journalKey), isNull);
      },
    );
  }
  for (final marker in ['wake', 'call']) {
    test(
      'BL24E2 $marker rotation replaces bytes only at reserved retry time',
      () async {
        await stage(marker);
        transport.storeInInboxResult = false;
        await retry();
        final first = transport.lastStoreInInboxMessage;
        wakeToken = 'wake-two';
        if (marker == 'call') callGrant = grant(2);
        now = now.add(const Duration(minutes: 30));
        await retry();
        expect(transport.storeInInboxCallCount, 1);
        now = now.add(const Duration(minutes: 30));
        await retry();
        expect(transport.storeInInboxCallCount, 2);
        expect(transport.lastStoreInInboxMessage, isNot(first));
        final second = transport.lastStoreInInboxMessage;
        now = now.add(const Duration(hours: 6));
        await retry();
        expect(transport.storeInInboxCallCount, 3);
        expect(transport.lastStoreInInboxMessage, second);
        if (marker == 'call') {
          final entry = entries((await store.read(_journalKey))!).single as Map;
          expect((entry['envelope'] as Map)['callWakeHandle']['generation'], 2);
        }
      },
    );
  }
  test(
    'BL24E2 token rotation while building never transmits stale material',
    () async {
      await stage('wake');
      bridge = _SigningHookBridge(() => wakeToken = 'rotated-during-build')
        ..responses.addAll(bridge.responses);
      await retry();
      expect(transport.storeInInboxCallCount, 0);
      now = now.add(const Duration(minutes: 1));
      await retry();
      expect(transport.storeInInboxCallCount, 0);
    },
  );
  test(
    'BL24E2 token rotation during final authority read retains reservation',
    () async {
      await stage('wake');
      consent = ContactRelationshipState.active;
      var consentReads = 0;
      onReadConsent = () {
        if (++consentReads == 2) wakeToken = 'rotated-during-final-authority';
      };
      await retry();
      expect(consentReads, 2);
      expect(transport.storeInInboxCallCount, 0);
      final reserved = await store.read(_journalKey);
      expect(reserved, isNotNull);
      now = now.add(const Duration(minutes: 1));
      await retry();
      expect(transport.storeInInboxCallCount, 0);
      expect(await store.read(_journalKey), reserved);
    },
  );
  test(
    'BL24E2 fresh event sends once and reserves the next periodic pass',
    () async {
      await stage('wake');
      transport.storeInInboxResult = false;
      await freshRetry();
      expect(transport.storeInInboxCallCount, 1);
      final reserved = await store.read(_journalKey);
      expect(reserved, isNotNull);
      await retry();
      expect(transport.storeInInboxCallCount, 1);
      expect(await store.read(_journalKey), reserved);
    },
  );
  test(
    'BL24E2 fresh event bypasses due time without resetting custody',
    () async {
      await stage('wake');
      transport.storeInInboxResult = false;
      await retry();
      final reserved = await store.read(_journalKey);
      now = now.add(const Duration(minutes: 1));
      await freshRetry();
      expect(transport.storeInInboxCallCount, 2);
      expect(await store.read(_journalKey), reserved);
      await retry();
      expect(transport.storeInInboxCallCount, 2);
      expect(await store.read(_journalKey), reserved);
    },
  );
  test(
    'BL24E2 fresh event never extends the original seven day horizon',
    () async {
      await stage('wake');
      transport.storeInInboxResult = false;
      await retry();
      final reserved = await store.read(_journalKey);
      now = now.add(const Duration(days: 6));
      await freshRetry();
      expect(transport.storeInInboxCallCount, 2);
      final before = entries(reserved!).single as Map;
      final after = entries((await store.read(_journalKey))!).single as Map;
      expect(after['expiresAtMs'], before['expiresAtMs']);
      expect(after['scannedAtMs'], before['scannedAtMs']);
      expect(after['attempts'], 2);
      await retry();
      expect(transport.storeInInboxCallCount, 2);
      now = now.add(const Duration(days: 1));
      await freshRetry();
      expect(transport.storeInInboxCallCount, 2);
      expect(await store.read(_journalKey), isNull);
    },
  );
  test(
    'BL24E2 fresh event rechecks material after final authority callback',
    () async {
      await stage('wake');
      var reads = 0;
      onReadConsent = () {
        if (++reads == 2) wakeToken = 'fresh-event-rotated';
      };
      await freshRetry();
      expect(transport.storeInInboxCallCount, 0);
      expect(await store.read(_journalKey), isNotNull);
      await retry();
      expect(transport.storeInInboxCallCount, 0);
    },
  );
  test(
    'BL24E2 fresh event skips peers without pending distribution work',
    () async {
      transport.storeInInboxResult = false;
      await freshRetry();
      expect(transport.storeInInboxCallCount, 0);
      expect(await store.read(_journalKey), isNull);
      await retry();
      expect(transport.storeInInboxCallCount, 1);
    },
  );
  test('BL24E2 queued fresh event cannot join a newer periodic run', () async {
    await stage('wake');
    transport.storeInInboxResult = false;
    await retry();
    now = now.add(const Duration(minutes: 1));
    final firstGate = Completer<void>();
    final secondGate = Completer<void>();
    final contexts = <bool>[];
    final coordinator = KeyExchangeRetryCoordinator(
      now: () => now,
      performRetry: () async {
        contexts.add(KeyExchangeRetryContext.current?.requireFresh == true);
        if (contexts.length == 1) await firstGate.future;
        if (contexts.length == 2) await secondGate.future;
        return retry();
      },
    );
    final first = coordinator.retryNow(trigger: 'periodic-a');
    final second = first.then(
      (_) => coordinator.retryNow(trigger: 'periodic-b'),
    );
    final fresh = coordinator.retryNow(
      trigger: 'wake_token_registered',
      requireFresh: true,
    );
    final sameFresh = coordinator.retryNow(
      trigger: 'call_grant_issued',
      requireFresh: true,
    );
    expect(identical(fresh, sameFresh), isTrue);
    firstGate.complete();
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(contexts, [false, false]);
    secondGate.complete();
    await second;
    await fresh;
    expect(contexts, [false, false, true]);
    expect(transport.storeInInboxCallCount, 2);
    await retry();
    expect(transport.storeInInboxCallCount, 2);
  });
  test(
    'BL24E2 acquired key drops marker custody and restores original path',
    () async {
      await stage('mlkem');
      transport.storeInInboxResult = false;
      await retry();
      expect(await store.read(_journalKey), isNotNull);
      contacts.seed([_contact(now).copyWith(mlKemPublicKey: 'completed-key')]);
      await retry();
      expect(await store.read(_journalKey), isNull);
      expect(transport.storeInInboxCallCount, 2);
    },
  );
  test(
    'BL24E2 archived granted call-wake recipient remains uncapped',
    () async {
      contacts.seed([
        _contact(
          now.subtract(const Duration(days: 8)),
        ).copyWith(isArchived: true),
      ]);
      await stage('call');
      transport.storeInInboxResult = false;
      await retry();
      await retry();
      expect(transport.storeInInboxCallCount, 2);
      expect(await store.read(_journalKey), isNull);
    },
  );

  test('BL24E causal first automatic request remains encrypted v2', () async {
    expect(await retry(), 1);
    final envelope = jsonDecode(transport.lastStoreInInboxMessage!) as Map;
    expect(envelope['type'], 'contact_request');
    expect(envelope['version'], '2');
    expect(envelope['intent'], 'key_exchange_retry');
    expect(envelope['msgId'], isNotEmpty);
    expect(envelope['encrypted'], isA<Map>());
  });

  test(
    'BL24E causal repeated reconnect backs off instead of minting a second id',
    () async {
      expect(await retry(), 1);
      final first = transport.lastStoreInInboxMessage;
      now = now.add(const Duration(seconds: 31));
      expect(await retry(), 0);
      expect(transport.storeInInboxCallCount, 1);
      expect(transport.lastStoreInInboxMessage, first);
    },
  );

  test(
    'BL24E causal due retry reuses the exact original envelope and msgId',
    () async {
      expect(await retry(), 1);
      final first = transport.lastStoreInInboxMessage!;
      expect((jsonDecode(first) as Map)['intent'], 'key_exchange_retry');
      now = now.add(const Duration(hours: 1));
      expect(await retry(), 1);
      expect(transport.storeInInboxCallCount, 2);
      expect(transport.lastStoreInInboxMessage, first);
    },
  );

  test('BL24E causal restart keeps the persisted envelope identity', () async {
    expect(await retry(), 1);
    final first = transport.lastStoreInInboxMessage;
    transport.dispose();
    transport = _transport();
    now = now.add(const Duration(hours: 1));
    expect(await retry(), 1);
    expect(transport.lastStoreInInboxMessage, first);
  });

  test(
    'BL24E causal older-than-seven-days contacts stop immediately',
    () async {
      contacts.seed([_contact(now.subtract(const Duration(days: 7)))]);
      expect(await retry(), 0);
      expect(transport.storeInInboxCallCount, 0);
    },
  );

  test(
    'BL24E untouched first-send use case still sends after automatic expiry',
    () async {
      contacts.seed([_contact(now.subtract(const Duration(days: 8)))]);
      final result = await sendContactRequest(
        p2pService: transport,
        identityRepo: identities,
        bridge: bridge,
        targetPeerId: _peer,
        recipientPublicKey: 'recipient-key-$_peer',
      );
      expect(result, SendContactRequestResult.success);
      expect(transport.storeInInboxCallCount, 1);
      expect(
        (jsonDecode(transport.lastStoreInInboxMessage!) as Map)['intent'],
        'new_request',
      );
    },
  );

  test(
    'BL24E causal built envelope records the actual signed timestamp locally',
    () async {
      final build = await buildContactRequestEnvelope(
        identityRepo: identities,
        bridge: bridge,
        targetPeerId: _peer,
        recipientPublicKey: 'recipient-key-$_peer',
        intent: ContactRequestSendIntent.keyExchangeRetry,
      );
      final signCommand = bridge.sentMessages
          .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
          .singleWhere((command) => command['cmd'] == 'payload.sign');
      final signed =
          jsonDecode((signCommand['payload'] as Map)['data'] as String) as Map;
      final signedAt = DateTime.parse(
        signed['ts'] as String,
      ).millisecondsSinceEpoch;
      expect(build.envelope, isNotNull);
      expect(build.envelope!.signedAtMs, signedAt);
      expect(
        (jsonDecode(build.envelope!.messageJson) as Map).containsKey(
          'signedAtMs',
        ),
        isFalse,
      );
    },
  );

  test(
    'BL24E persisted expiry is the earlier scan or actual signed cutoff',
    () async {
      expect(await retry(), 1);
      final signCommand = bridge.sentMessages
          .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
          .singleWhere((command) => command['cmd'] == 'payload.sign');
      final signed =
          jsonDecode((signCommand['payload'] as Map)['data'] as String) as Map;
      final signedAt = DateTime.parse(signed['ts'] as String);
      final earlier = now.isBefore(signedAt) ? now : signedAt;
      final raw = await store.read(_journalKey);
      expect(raw, isNotNull);
      expect(
        (entries(raw!).single as Map)['expiresAtMs'],
        earlier.add(const Duration(days: 7)).millisecondsSinceEpoch,
      );
    },
  );

  test(
    'BL24E clock rollback cannot emit a request signed before its contact scan',
    () async {
      final scannedAt = now;
      contacts.seed([_contact(scannedAt)]);
      var rolledBack = false;
      store = _JournalWriteHookStore((raw) {
        if (!rolledBack && entries(raw).isNotEmpty) {
          // The reservation was admitted before the clock moved backwards.
          now = scannedAt.subtract(const Duration(hours: 1));
          rolledBack = true;
        }
      });
      expect(await retry(), 0);
      expect(transport.storeInInboxCallCount, 0);
      expect(rolledBack, isTrue);
      final signCommand = bridge.sentMessages
          .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
          .singleWhere((command) => command['cmd'] == 'payload.sign');
      final signed =
          jsonDecode((signCommand['payload'] as Map)['data'] as String) as Map;
      expect(DateTime.parse(signed['ts'] as String), now);
      final reservation = entries((await store.read(_journalKey))!).single as Map;
      expect(reservation['envelope'], isNull);
      expect(reservation['attempts'], 1);
    },
  );

  test('BL24E retries wait 1h then6h then24h then daily', () async {
    expect(await retry(), 1);
    for (final gap in [1, 6, 24, 24]) {
      now = now.add(Duration(hours: gap) - const Duration(seconds: 1));
      final before = transport.storeInInboxCallCount;
      expect(await retry(), 0);
      expect(transport.storeInInboxCallCount, before);
      now = now.add(const Duration(seconds: 1));
      expect(await retry(), 1);
      expect(transport.storeInInboxCallCount, before + 1);
    }
    expect(
      transport.storeInInboxLog.map((e) => e.message).toSet(),
      hasLength(1),
    );
  });

  for (final state in [
    ContactRelationshipState.declined,
    ContactRelationshipState.withdrawn,
  ]) {
    test('BL24E causal $state suppresses automatic requests', () async {
      consent = state;
      expect(await retry(), 0);
      expect(transport.storeInInboxCallCount, 0);
    });
  }

  for (final transition in [
    'accepted',
    'declined',
    'withdrawn',
    'removed',
    'expired',
  ]) {
    test(
      'BL24E reconciles stale $transition entry before any resend',
      () async {
        expect(await retry(), 1);
        expect(await store.read(_journalKey), isNotNull);
        switch (transition) {
          case 'accepted':
            contacts.seed([
              _contact(now).copyWith(mlKemPublicKey: 'completed-key'),
            ]);
          case 'declined':
            consent = ContactRelationshipState.declined;
          case 'withdrawn':
            consent = ContactRelationshipState.withdrawn;
          case 'removed':
            contacts.seed([]);
          case 'expired':
            now = now.add(const Duration(days: 7));
        }
        now = now.add(const Duration(hours: 1));
        expect(await retry(), 0);
        expect(transport.storeInInboxCallCount, 1);
        final raw = await store.read(_journalKey);
        expect(raw == null || entries(raw).isEmpty, isTrue);
      },
    );
  }

  test(
    'BL24E journal bounds all live entries at200 without sending untracked ids',
    () {
      contacts.seed([
        for (var i = 0; i < 201; i++) _contact(now, peer: 'peer-$i'),
      ]);
      fakeAsync((time) {
        var finished = false;
        Future<void> inspect() async {
          expect(await retry(), 200);
          final raw = await store.read(_journalKey);
          expect(raw, isNotNull);
          expect(entries(raw!), hasLength(200));
          expect(transport.storeInInboxCallCount, 200);
          finished = true;
        }

        inspect();
        time.elapse(const Duration(minutes: 2));
        expect(finished, isTrue);
      });
    },
  );

  test(
    'BL24E account change prunes old-account envelopes before sending',
    () async {
      expect(await retry(), 1);
      final first = transport.lastStoreInInboxMessage;
      identities.seed(_identity('replacement-account'));
      now = now.add(const Duration(hours: 1));
      expect(await retry(), 1);
      expect(transport.lastStoreInInboxMessage, isNot(first));
      final raw = await store.read(_journalKey);
      expect(raw, isNotNull);
      expect(raw, isNot(contains('sender-account')));
    },
  );

  test(
    'BL24E decline during envelope build suppresses the pending send',
    () async {
      final hooked = _SigningHookBridge(
        () => consent = ContactRelationshipState.declined,
      );
      hooked.responses.addAll(bridge.responses);
      bridge = hooked;
      expect(await retry(), 0);
      expect(transport.storeInInboxCallCount, 0);
      final raw = await store.read(_journalKey);
      expect(raw == null || entries(raw).isEmpty, isTrue);
    },
  );

  test(
    'BL24E account change during build cannot send the previous account envelope',
    () async {
      final hooked = _SigningHookBridge(
        () => identities.seed(_identity('replacement-account')),
      );
      hooked.responses.addAll(bridge.responses);
      bridge = hooked;
      expect(await retry(), 0);
      expect(transport.storeInInboxCallCount, 0);
    },
  );

  test(
    'BL24E explicit account reset erases the journal through existing inventory',
    () async {
      expect(await retry(), 1);
      expect(await store.read(_journalKey), isNotNull);
      await MigrationSecureStorageCleanup(
        staging: MigrationSecureStorageStaging(primaryStore: store),
      ).eraseAccount(registryKeys: const [], explicitLocalReset: true);
      expect(await store.read(_journalKey), isNull);
    },
  );

  test(
    'BL24E unavailable durable storage cannot produce an untracked automatic id',
    () async {
      expect(await retry(durableStore: false), 0);
      expect(transport.storeInInboxCallCount, 0);
    },
  );

  test(
    'BL24E corrupt journal fails closed without minting another request',
    () async {
      await store.write(_journalKey, 'corrupt-journal');
      await retry().then<void>((_) {}, onError: (Object _) {});
      expect(transport.storeInInboxCallCount, 0);
    },
  );

  test(
    'BL24E journal persistence failure precedes every network send',
    () async {
      store = _FailingJournalStore();
      await retry().then<void>((_) {}, onError: (Object _) {});
      expect(transport.storeInInboxCallCount, 0);
    },
  );
}
