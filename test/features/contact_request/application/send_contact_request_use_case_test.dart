import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeIdentityRepo implements IdentityRepository {
  IdentityModel? identity;

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {}
}

class _FakeBridge extends Bridge {
  Map<String, dynamic> signResponse = {'ok': true, 'signature': 'fakeSig'};
  Map<String, dynamic> encryptResponse = {
    'ok': true,
    'ephemeralPublicKey': 'ephPubBase64',
    'ciphertext': 'ctBase64',
    'nonce': 'nonceBase64',
  };
  Map<String, dynamic>? lastEncryptPayload;
  Map<String, dynamic>? lastSignPayload;
  bool encryptCalled = false;

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
    if (req['cmd'] == 'payload.sign') {
      lastSignPayload = req['payload'] as Map<String, dynamic>?;
      return jsonEncode(signResponse);
    }
    if (req['cmd'] == 'contactrequest.encrypt') {
      encryptCalled = true;
      lastEncryptPayload = req['payload'] as Map<String, dynamic>?;
      return jsonEncode(encryptResponse);
    }
    return jsonEncode({'ok': true});
  }
}

class _FakeP2PService implements P2PService {
  NodeState _state = const NodeState(isStarted: true, peerId: 'ownPeer');
  SendMessageResult sendWithReplyResult = const SendMessageResult(
    sent: true,
    acked: true,
    reply: 'ack',
  );
  bool dialResult = true;
  DiscoveredPeer? discoveredPeer;
  bool localPeerResult = false;
  bool localSendResult = false;
  bool storeInInboxResult = false;
  SendMessageResult Function(String peerId, String message)?
  sendWithReplyHandler;
  int sendWithReplyCalls = 0;
  int localSendCalls = 0;
  int storeInInboxCalls = 0;

  String? lastSentMessage;
  String? lastSentPeerId;

  @override
  NodeState get currentState => _state;
  set currentState(NodeState s) => _state = s;

  @override
  Stream<NodeState> get stateStream => const Stream.empty();
  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();

  @override
  Future<bool> startNode(String pk, String pid) async => true;
  @override
  Future<bool> startNodeCore(String pk, String pid) async => true;
  @override
  Future<void> warmBackground() async {}
  @override
  Future<bool> stopNode() async => true;

  @override
  Future<bool> sendMessage(String peerId, String message) async {
    lastSentPeerId = peerId;
    lastSentMessage = message;
    return sendWithReplyResult.sent && sendWithReplyResult.acknowledged;
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String pid,
    String msg, {
    int? timeoutMs,
  }) async {
    sendWithReplyCalls += 1;
    lastSentPeerId = pid;
    lastSentMessage = msg;
    return sendWithReplyHandler?.call(pid, msg) ?? sendWithReplyResult;
  }

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async =>
      discoveredPeer;

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
  }) async => dialResult;

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    storeInInboxCalls += 1;
    return storeInInboxResult;
  }

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async =>
      [];

  @override
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  Future<void> drainOfflineInbox() async {}

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  bool isLocalPeer(String peerId) => localPeerResult;

  @override
  String? lastKnownGoodTransport(String peerId) => null;

  @override
  void recordSuccessfulTransport(String peerId, String transport) {}

  @override
  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async => false;

  @override
  Future<void> warmPeer(String peerId, {bool preferQuic = false}) async {}

  @override
  Stream<LocalMediaReady> get incomingLocalMediaStream => const Stream.empty();

  @override
  Future<bool> sendLocalMessage(
    String pid,
    String msg,
    String from, {
    int? timeoutMs,
  }) async {
    localSendCalls += 1;
    return localSendResult;
  }

  @override
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
    bool enc = false,
    String? encScheme,
  }) async => false;

  @override
  String? get lastRecoveryMethod => null;

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

final _testIdentity = IdentityModel(
  peerId: '12D3KooWOwnPeerIdForTesting',
  publicKey: 'ownPubKey',
  privateKey: 'ownPrivKey',
  mnemonic12:
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
  mlKemPublicKey: 'ownMlKemPub',
  createdAt: '2024-01-01T00:00:00Z',
  updatedAt: '2024-01-01T00:00:00Z',
);

void main() {
  late _FakeIdentityRepo identityRepo;
  late _FakeBridge bridge;
  late _FakeP2PService p2pService;

  setUp(() {
    identityRepo = _FakeIdentityRepo()..identity = _testIdentity;
    bridge = _FakeBridge();
    p2pService = _FakeP2PService()
      ..discoveredPeer = DiscoveredPeer(
        id: 'targetPeer123456789',
        addresses: ['/ip4/127.0.0.1/tcp/4001'],
      );
  });

  test('success: discovers, dials, and sends contact request', () async {
    final result = await sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: 'targetPeer123456789',
    );

    expect(result, equals(SendContactRequestResult.success));
    expect(p2pService.lastSentPeerId, equals('targetPeer123456789'));

    // Verify the sent message is a proper contact_request envelope
    final sent =
        jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
    expect(sent['type'], equals('contact_request'));
    expect(sent['version'], equals('1'));
    expect(sent['payload']['ns'], equals(_testIdentity.peerId));
    expect(sent['payload']['pk'], equals(_testIdentity.publicKey));
    expect(sent['payload']['sig'], equals('fakeSig'));
    expect(sent['payload']['mlkem'], equals('ownMlKemPub'));
  });

  test('default intent marks visible requests as new_request', () async {
    final result = await sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: 'targetPeer123456789',
    );

    expect(result, equals(SendContactRequestResult.success));
    final sent =
        jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
    expect(
      sent['intent'],
      equals(ContactRequestSendIntent.newRequest.wireValue),
    );
  });

  test(
    'sanitizes dangerous bidi controls in outgoing username payload',
    () async {
      identityRepo.identity = IdentityModel(
        peerId: _testIdentity.peerId,
        publicKey: _testIdentity.publicKey,
        privateKey: _testIdentity.privateKey,
        mnemonic12: _testIdentity.mnemonic12,
        mlKemPublicKey: _testIdentity.mlKemPublicKey,
        createdAt: _testIdentity.createdAt,
        updatedAt: _testIdentity.updatedAt,
        username: 'A\u202Eli\u200Fce',
      );

      final result = await sendContactRequest(
        p2pService: p2pService,
        identityRepo: identityRepo,
        bridge: bridge,
        targetPeerId: 'targetPeer123456789',
      );

      expect(result, equals(SendContactRequestResult.success));
      final sent =
          jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
      expect(sent['payload']['un'], equals('Ali\u200Fce'));
    },
  );

  test('nodeNotRunning: returns error when P2P node is stopped', () async {
    p2pService.currentState = const NodeState(isStarted: false);

    final result = await sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: 'targetPeer123456789',
    );

    expect(result, equals(SendContactRequestResult.nodeNotRunning));
  });

  test('noIdentity: returns error when no identity in repo', () async {
    identityRepo.identity = null;

    final result = await sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: 'targetPeer123456789',
    );

    expect(result, equals(SendContactRequestResult.noIdentity));
  });

  test('signingError: returns error when bridge signing fails', () async {
    bridge.signResponse = {
      'ok': false,
      'errorCode': 'SIGN_FAILED',
      'errorMessage': 'Key not found',
    };

    final result = await sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: 'targetPeer123456789',
    );

    expect(result, equals(SendContactRequestResult.signingError));
  });

  test(
    'sendFailed: falls back to inbox when peer not found and inbox also fails',
    () async {
      p2pService.discoveredPeer = null;
      p2pService.storeInInboxResult = false;

      final result = await sendContactRequest(
        p2pService: p2pService,
        identityRepo: identityRepo,
        bridge: bridge,
        targetPeerId: 'targetPeer123456789',
      );

      expect(result, equals(SendContactRequestResult.sendFailed));
    },
  );

  test(
    'success via inbox fallback: stores in inbox when direct send fails',
    () async {
      p2pService.discoveredPeer = null;
      p2pService.storeInInboxResult = true;

      final result = await sendContactRequest(
        p2pService: p2pService,
        identityRepo: identityRepo,
        bridge: bridge,
        targetPeerId: 'targetPeer123456789',
      );

      expect(result, equals(SendContactRequestResult.success));
    },
  );

  test(
    'success via local WiFi: sends via local P2P when peer is local',
    () async {
      p2pService.localPeerResult = true;
      p2pService.localSendResult = true;

      final result = await sendContactRequest(
        p2pService: p2pService,
        identityRepo: identityRepo,
        bridge: bridge,
        targetPeerId: 'targetPeer123456789',
      );

      expect(result, equals(SendContactRequestResult.success));
    },
  );

  test(
    'success via inbox fallback: unacked direct send falls back to inbox',
    () async {
      p2pService.sendWithReplyResult = const SendMessageResult(
        sent: true,
        acked: false,
      );
      p2pService.storeInInboxResult = true;

      final result = await sendContactRequest(
        p2pService: p2pService,
        identityRepo: identityRepo,
        bridge: bridge,
        targetPeerId: 'targetPeer123456789',
      );

      expect(result, equals(SendContactRequestResult.success));
    },
  );

  // --- v2 encrypted contact request tests ---

  test('v2: encrypts signed payload and sends v2 envelope', () async {
    final result = await sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: 'targetPeer123456789',
      recipientPublicKey: 'recipientEdPubBase64',
    );

    expect(result, equals(SendContactRequestResult.success));
    expect(bridge.encryptCalled, isTrue);

    // Verify sent message is v2 envelope
    final sent =
        jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
    expect(sent['type'], equals('contact_request'));
    expect(sent['version'], equals('2'));
    expect(sent['msgId'], isA<String>());
    expect(sent['ts'], isA<String>());
    expect(sent['encrypted'], isA<Map>());
    expect(sent['encrypted']['ephemeralPublicKey'], equals('ephPubBase64'));
    expect(sent['encrypted']['ciphertext'], equals('ctBase64'));
    expect(sent['encrypted']['nonce'], equals('nonceBase64'));
    // No top-level payload/sig/pk in v2
    expect(sent.containsKey('payload'), isFalse);
  });

  test('v2: key-exchange retry uses silent retry intent', () async {
    final result = await sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: 'targetPeer123456789',
      recipientPublicKey: 'recipientEdPubBase64',
      intent: ContactRequestSendIntent.keyExchangeRetry,
    );

    expect(result, equals(SendContactRequestResult.success));
    final sent =
        jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
    expect(
      sent['intent'],
      equals(ContactRequestSendIntent.keyExchangeRetry.wireValue),
    );
  });

  test('v2: envelope contains valid UUID msgId', () async {
    await sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: 'targetPeer123456789',
      recipientPublicKey: 'recipientEdPubBase64',
    );

    final sent =
        jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
    final msgId = sent['msgId'] as String;
    // UUID v4 format
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(msgId),
      isTrue,
      reason: 'msgId should be a valid UUID v4',
    );
  });

  test('v2: envelope ts is valid ISO-8601', () async {
    await sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: 'targetPeer123456789',
      recipientPublicKey: 'recipientEdPubBase64',
    );

    final sent =
        jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
    final ts = sent['ts'] as String;
    expect(DateTime.tryParse(ts), isNotNull);
    expect(ts, endsWith('Z'));
  });

  test('v2: envelope carries senderUsername when available', () async {
    identityRepo.identity = IdentityModel(
      peerId: _testIdentity.peerId,
      publicKey: _testIdentity.publicKey,
      privateKey: _testIdentity.privateKey,
      mnemonic12: _testIdentity.mnemonic12,
      mlKemPublicKey: _testIdentity.mlKemPublicKey,
      createdAt: _testIdentity.createdAt,
      updatedAt: _testIdentity.updatedAt,
      username: 'Alice',
    );

    await sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: 'targetPeer123456789',
      recipientPublicKey: 'recipientEdPubBase64',
    );

    final sent =
        jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
    expect(sent['senderUsername'], equals('Alice'));
  });

  test(
    'v2: signed payload is inside ciphertext, not visible at top level',
    () async {
      await sendContactRequest(
        p2pService: p2pService,
        identityRepo: identityRepo,
        bridge: bridge,
        targetPeerId: 'targetPeer123456789',
        recipientPublicKey: 'recipientEdPubBase64',
      );

      final sent =
          jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
      expect(sent.containsKey('payload'), isFalse);
      expect(sent.containsKey('sig'), isFalse);
      expect(sent.containsKey('pk'), isFalse);
    },
  );

  test('v2: returns encryptionError when encryption fails', () async {
    bridge.encryptResponse = {
      'ok': false,
      'errorCode': 'INTERNAL_ERROR',
      'errorMessage': 'bad key',
    };

    final result = await sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: 'targetPeer123456789',
      recipientPublicKey: 'badRecipientKey',
    );

    // Does NOT fall back to v1
    expect(result, equals(SendContactRequestResult.encryptionError));
  });

  test(
    'v2: returns encryptionError when encrypt response is malformed',
    () async {
      // Bridge says ok:true but missing required fields
      bridge.encryptResponse = {'ok': true};

      final result = await sendContactRequest(
        p2pService: p2pService,
        identityRepo: identityRepo,
        bridge: bridge,
        targetPeerId: 'targetPeer123456789',
        recipientPublicKey: 'recipientEdPubBase64',
      );

      expect(result, equals(SendContactRequestResult.encryptionError));
    },
  );

  test(
    'v2: returns encryptionError when encrypt response has empty fields',
    () async {
      bridge.encryptResponse = {
        'ok': true,
        'ephemeralPublicKey': '',
        'ciphertext': 'ctBase64',
        'nonce': 'nonceBase64',
      };

      final result = await sendContactRequest(
        p2pService: p2pService,
        identityRepo: identityRepo,
        bridge: bridge,
        targetPeerId: 'targetPeer123456789',
        recipientPublicKey: 'recipientEdPubBase64',
      );

      expect(result, equals(SendContactRequestResult.encryptionError));
    },
  );

  test('v1: sends v1 when recipientPublicKey is null', () async {
    final result = await sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: 'targetPeer123456789',
      recipientPublicKey: null,
    );

    expect(result, equals(SendContactRequestResult.success));
    expect(bridge.encryptCalled, isFalse);

    final sent =
        jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
    expect(sent['version'], equals('1'));
    expect(sent['payload'], isA<Map>());
  });

  test('v2: msgId and ts are passed as AAD to encrypt', () async {
    await sendContactRequest(
      p2pService: p2pService,
      identityRepo: identityRepo,
      bridge: bridge,
      targetPeerId: 'targetPeer123456789',
      recipientPublicKey: 'recipientEdPubBase64',
    );

    expect(bridge.lastEncryptPayload, isNotNull);
    expect(bridge.lastEncryptPayload!['msgId'], isA<String>());
    expect(bridge.lastEncryptPayload!['ts'], isA<String>());
    // Verify the msgId/ts in the encrypt payload match the envelope
    final sent =
        jsonDecode(p2pService.lastSentMessage!) as Map<String, dynamic>;
    expect(bridge.lastEncryptPayload!['msgId'], equals(sent['msgId']));
    expect(bridge.lastEncryptPayload!['ts'], equals(sent['ts']));
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 217 / CV-14 wake-token send leg (A01). INV-6: `wt` rides ONLY the v2
  // encrypted, signed envelope — never v1. INV-5: the per-send resolver is
  // READ-ONLY (it never mints/registers).
  // ───────────────────────────────────────────────────────────────────────────
  group('217 CV-14 wake-token send', () {
    test(
      'v2 embeds signed wt inside the encrypted envelope; v1 never carries wt; '
      'the per-send resolver is read-only',
      () async {
        var resolverCalls = 0;
        Future<String?> resolver(String peerId) async {
          resolverCalls++;
          return 'tok-for-$peerId';
        }

        // v2: recipientPublicKey != null → wt is signed (present in the
        // plaintext the encrypt step wraps, i.e. covered by the signature).
        final v2 = await sendContactRequest(
          p2pService: p2pService,
          identityRepo: identityRepo,
          bridge: bridge,
          targetPeerId: 'targetPeer123456789',
          recipientPublicKey: 'recipientPubKey',
          resolveWakeToken: resolver,
        );
        expect(v2, equals(SendContactRequestResult.success));
        final signedPlaintext =
            bridge.lastEncryptPayload!['plaintext'] as String;
        expect(signedPlaintext, contains('"wt":"tok-for-targetPeer123456789"'));
        // Read once, per-send (not per-retry) — the resolver is a pure read.
        expect(resolverCalls, 1);

        // v1: recipientPublicKey == null → NO wt (INV-6); the resolver is not
        // even consulted (gated on recipientPublicKey).
        resolverCalls = 0;
        final v1Bridge = _FakeBridge();
        final v1p2p = _FakeP2PService()
          ..discoveredPeer = DiscoveredPeer(
            id: 'targetPeer123456789',
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          );
        final v1 = await sendContactRequest(
          p2pService: v1p2p,
          identityRepo: identityRepo,
          bridge: v1Bridge,
          targetPeerId: 'targetPeer123456789',
          resolveWakeToken: resolver,
        );
        expect(v1, equals(SendContactRequestResult.success));
        final v1Sent =
            jsonDecode(v1p2p.lastSentMessage!) as Map<String, dynamic>;
        expect((v1Sent['payload'] as Map).containsKey('wt'), isFalse);
        expect(v1p2p.lastSentMessage, isNot(contains('wt')));
        expect(resolverCalls, 0);
      },
    );
  });

  group('call-only wake-handle grant transport', () {
    final grant = CallWakeHandleGrant(
      handle: '0123456789abcdef0123456789abcdef',
      // The handle targets the local issuer/callee endpoint; it is distributed
      // to a different remote contact/caller.
      recipientDevicePeerId: '12D3KooWLocalCallEndpoint1',
      deviceKeyEpoch: 3,
      generation: 5,
      issuedAtMs: 1,
      expiresAtMs: CallWakeHandleGrant.maxSafeInteger,
    );

    test(
      'v2 signs cwh and receipt challenge; v1 never resolves or carries it',
      () async {
        var resolverCalls = 0;
        final distributed = <({String peerId, CallWakeHandleGrant grant})>[];
        p2pService.sendWithReplyHandler = (_, _) {
          final signedData =
              jsonDecode(bridge.lastSignPayload!['data'] as String)
                  as Map<String, dynamic>;
          return SendMessageResult(
            sent: true,
            acked: true,
            reply: jsonEncode({'callWakeReceipt': signedData['cwr']}),
          );
        };

        final v2 = await sendContactRequest(
          p2pService: p2pService,
          identityRepo: identityRepo,
          bridge: bridge,
          targetPeerId: 'targetPeer123456789',
          recipientPublicKey: 'recipientPubKey',
          resolveCallWakeHandle: (peerId) async {
            resolverCalls += 1;
            expect(peerId, 'targetPeer123456789');
            return grant;
          },
          onCallWakeHandleDistributed: (peerId, value) async {
            distributed.add((peerId: peerId, grant: value));
          },
        );

        expect(v2, SendContactRequestResult.success);
        final signedPlaintext =
            jsonDecode(bridge.lastEncryptPayload!['plaintext'] as String)
                as Map<String, dynamic>;
        expect(signedPlaintext['cwh'], grant.toCanonicalMap());
        final signedData =
            jsonDecode(bridge.lastSignPayload!['data'] as String)
                as Map<String, dynamic>;
        expect(signedData['cwh'], grant.toCanonicalMap());
        expect(signedData['cwr'], isA<String>());
        expect(signedPlaintext['cwr'], signedData['cwr']);
        expect(resolverCalls, 1);
        expect(distributed, [(peerId: 'targetPeer123456789', grant: grant)]);

        resolverCalls = 0;
        distributed.clear();
        final v1Bridge = _FakeBridge();
        final v1P2p = _FakeP2PService()
          ..discoveredPeer = DiscoveredPeer(
            id: 'targetPeer123456789',
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          );
        final v1 = await sendContactRequest(
          p2pService: v1P2p,
          identityRepo: identityRepo,
          bridge: v1Bridge,
          targetPeerId: 'targetPeer123456789',
          resolveCallWakeHandle: (_) async {
            resolverCalls += 1;
            return grant;
          },
          onCallWakeHandleDistributed: (peerId, value) async {
            distributed.add((peerId: peerId, grant: value));
          },
        );

        expect(v1, SendContactRequestResult.success);
        final v1Envelope =
            jsonDecode(v1P2p.lastSentMessage!) as Map<String, dynamic>;
        expect((v1Envelope['payload'] as Map).containsKey('cwh'), isFalse);
        expect(resolverCalls, 0);
        expect(distributed, isEmpty);
      },
    );

    test('distribution callback runs only after successful delivery', () async {
      p2pService
        ..sendWithReplyResult = const SendMessageResult(
          sent: false,
          acked: false,
        )
        ..storeInInboxResult = false;
      var distributed = false;

      final result = await sendContactRequest(
        p2pService: p2pService,
        identityRepo: identityRepo,
        bridge: bridge,
        targetPeerId: 'targetPeer123456789',
        recipientPublicKey: 'recipientPubKey',
        resolveCallWakeHandle: (_) async => grant,
        onCallWakeHandleDistributed: (_, _) async => distributed = true,
      );

      expect(result, SendContactRequestResult.sendFailed);
      expect(distributed, isFalse);
    });

    test(
      'ordinary cwh send accepts generic ACK but keeps distribution pending',
      () async {
        p2pService
          ..localPeerResult = true
          ..localSendResult = true;
        var distributed = false;

        final result = await sendContactRequest(
          p2pService: p2pService,
          identityRepo: identityRepo,
          bridge: bridge,
          targetPeerId: 'targetPeer123456789',
          recipientPublicKey: 'recipientPubKey',
          resolveCallWakeHandle: (_) async => grant,
          onCallWakeHandleDistributed: (_, _) async => distributed = true,
        );

        final signedData =
            jsonDecode(bridge.lastSignPayload!['data'] as String)
                as Map<String, dynamic>;
        expect(result, SendContactRequestResult.success);
        expect(signedData['cwh'], grant.toCanonicalMap());
        expect(signedData['cwr'], isA<String>());
        expect(distributed, isFalse);
        expect(p2pService.localSendCalls, 0);
        expect(p2pService.sendWithReplyCalls, 1);
        expect(p2pService.storeInInboxCalls, 0);
      },
    );

    test(
      'ordinary cwh inbox fallback never marks receiver durability',
      () async {
        p2pService
          ..localPeerResult = true
          ..localSendResult = true
          ..discoveredPeer = null
          ..storeInInboxResult = true;
        var distributed = false;

        final result = await sendContactRequest(
          p2pService: p2pService,
          identityRepo: identityRepo,
          bridge: bridge,
          targetPeerId: 'targetPeer123456789',
          recipientPublicKey: 'recipientPubKey',
          resolveCallWakeHandle: (_) async => grant,
          onCallWakeHandleDistributed: (_, _) async => distributed = true,
        );

        expect(result, SendContactRequestResult.success);
        expect(distributed, isFalse);
        expect(p2pService.localSendCalls, 0);
        expect(p2pService.sendWithReplyCalls, 0);
        expect(p2pService.storeInInboxCalls, 1);
      },
    );

    group('exact call-wake receipt', () {
      test(
        'rejects an old generic ACK without local or inbox fallback',
        () async {
          p2pService
            ..localPeerResult = true
            ..localSendResult = true
            ..storeInInboxResult = true
            ..sendWithReplyResult = const SendMessageResult(
              sent: true,
              acked: true,
              reply: 'ack',
            );
          var distributed = false;

          final result = await sendContactRequest(
            p2pService: p2pService,
            identityRepo: identityRepo,
            bridge: bridge,
            targetPeerId: 'targetPeer123456789',
            recipientPublicKey: 'recipientPubKey',
            resolveCallWakeHandle: (_) async => grant,
            onCallWakeHandleDistributed: (_, _) async => distributed = true,
            requireExactCallWakeReceipt: true,
          );

          expect(result, SendContactRequestResult.sendFailed);
          expect(distributed, isFalse);
          expect(p2pService.localSendCalls, 0);
          expect(p2pService.sendWithReplyCalls, 1);
          expect(p2pService.storeInInboxCalls, 0);
        },
      );

      test('accepts and marks only the exact encrypted signed receipt', () async {
        p2pService.sendWithReplyHandler = (_, _) {
          final signedData =
              jsonDecode(bridge.lastSignPayload!['data'] as String)
                  as Map<String, dynamic>;
          return SendMessageResult(
            sent: true,
            acked: true,
            reply: jsonEncode({'callWakeReceipt': signedData['cwr']}),
          );
        };
        final distributed = <({String peerId, CallWakeHandleGrant grant})>[];

        final result = await sendContactRequest(
          p2pService: p2pService,
          identityRepo: identityRepo,
          bridge: bridge,
          targetPeerId: 'targetPeer123456789',
          recipientPublicKey: 'recipientPubKey',
          resolveCallWakeHandle: (_) async => grant,
          onCallWakeHandleDistributed: (peerId, value) async {
            distributed.add((peerId: peerId, grant: value));
          },
          requireExactCallWakeReceipt: true,
        );

        expect(result, SendContactRequestResult.success);
        final signedData =
            jsonDecode(bridge.lastSignPayload!['data'] as String)
                as Map<String, dynamic>;
        final signedPlaintext =
            jsonDecode(bridge.lastEncryptPayload!['plaintext'] as String)
                as Map<String, dynamic>;
        final challenge = signedData['cwr'];
        expect(challenge, isA<String>());
        expect(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ).hasMatch(challenge as String),
          isTrue,
        );
        expect(signedPlaintext['cwr'], challenge);
        expect(signedPlaintext['cwh'], grant.toCanonicalMap());
        expect(p2pService.lastSentMessage, isNot(contains(challenge)));
        expect(distributed, [(peerId: 'targetPeer123456789', grant: grant)]);
      });

      test(
        'rejects a mismatched receipt without marking distribution',
        () async {
          p2pService
            ..storeInInboxResult = true
            ..sendWithReplyResult = SendMessageResult(
              sent: true,
              acked: true,
              reply: jsonEncode({'callWakeReceipt': 'different-challenge'}),
            );
          var distributed = false;

          final result = await sendContactRequest(
            p2pService: p2pService,
            identityRepo: identityRepo,
            bridge: bridge,
            targetPeerId: 'targetPeer123456789',
            recipientPublicKey: 'recipientPubKey',
            resolveCallWakeHandle: (_) async => grant,
            onCallWakeHandleDistributed: (_, _) async => distributed = true,
            requireExactCallWakeReceipt: true,
          );

          expect(result, SendContactRequestResult.sendFailed);
          expect(distributed, isFalse);
          expect(p2pService.storeInInboxCalls, 0);
        },
      );

      test('rejects an ACK whose JSON receipt field is missing', () async {
        p2pService
          ..storeInInboxResult = true
          ..sendWithReplyResult = SendMessageResult(
            sent: true,
            acked: true,
            reply: jsonEncode({'status': 'ok'}),
          );
        var distributed = false;

        final result = await sendContactRequest(
          p2pService: p2pService,
          identityRepo: identityRepo,
          bridge: bridge,
          targetPeerId: 'targetPeer123456789',
          recipientPublicKey: 'recipientPubKey',
          resolveCallWakeHandle: (_) async => grant,
          onCallWakeHandleDistributed: (_, _) async => distributed = true,
          requireExactCallWakeReceipt: true,
        );

        expect(result, SendContactRequestResult.sendFailed);
        expect(distributed, isFalse);
        expect(p2pService.storeInInboxCalls, 0);
      });

      test(
        'direct failure and peer absence never use inbox fallback',
        () async {
          p2pService
            ..storeInInboxResult = true
            ..sendWithReplyResult = const SendMessageResult(
              sent: false,
              acked: false,
            );

          final directFailure = await sendContactRequest(
            p2pService: p2pService,
            identityRepo: identityRepo,
            bridge: bridge,
            targetPeerId: 'targetPeer123456789',
            recipientPublicKey: 'recipientPubKey',
            resolveCallWakeHandle: (_) async => grant,
            requireExactCallWakeReceipt: true,
          );

          expect(directFailure, SendContactRequestResult.sendFailed);
          expect(p2pService.storeInInboxCalls, 0);

          p2pService
            ..discoveredPeer = null
            ..sendWithReplyCalls = 0;
          final peerAbsent = await sendContactRequest(
            p2pService: p2pService,
            identityRepo: identityRepo,
            bridge: bridge,
            targetPeerId: 'targetPeer123456789',
            recipientPublicKey: 'recipientPubKey',
            resolveCallWakeHandle: (_) async => grant,
            requireExactCallWakeReceipt: true,
          );

          expect(peerAbsent, SendContactRequestResult.sendFailed);
          expect(p2pService.sendWithReplyCalls, 0);
          expect(p2pService.storeInInboxCalls, 0);
        },
      );

      test('requires encrypted v2 and a current call-wake grant', () async {
        final noV2 = await sendContactRequest(
          p2pService: p2pService,
          identityRepo: identityRepo,
          bridge: bridge,
          targetPeerId: 'targetPeer123456789',
          resolveCallWakeHandle: (_) async => grant,
          requireExactCallWakeReceipt: true,
        );
        expect(noV2, SendContactRequestResult.sendFailed);

        final expiredGrant = CallWakeHandleGrant(
          handle: grant.handle,
          recipientDevicePeerId: grant.recipientDevicePeerId,
          deviceKeyEpoch: grant.deviceKeyEpoch,
          generation: grant.generation,
          issuedAtMs: 1,
          expiresAtMs: 2,
        );
        final noCurrentGrant = await sendContactRequest(
          p2pService: p2pService,
          identityRepo: identityRepo,
          bridge: bridge,
          targetPeerId: 'targetPeer123456789',
          recipientPublicKey: 'recipientPubKey',
          resolveCallWakeHandle: (_) async => expiredGrant,
          requireExactCallWakeReceipt: true,
        );
        expect(noCurrentGrant, SendContactRequestResult.sendFailed);
        expect(p2pService.sendWithReplyCalls, 0);
        expect(p2pService.storeInInboxCalls, 0);
      });
    });
  });
}
