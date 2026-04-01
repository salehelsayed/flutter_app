import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

// ---------------------------------------------------------------------------
// Mock Bridge (same pattern as bridge_helpers_test.dart)
// ---------------------------------------------------------------------------
class _MockBridge extends Bridge {
  String? lastRawRequest;
  Map<String, dynamic>? lastParsedRequest;
  Map<String, dynamic> nextResponse = {'ok': true};
  bool shouldThrow = false;

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
    if (shouldThrow) throw Exception('bridge error');
    lastRawRequest = message;
    lastParsedRequest = jsonDecode(message) as Map<String, dynamic>;
    return jsonEncode(nextResponse);
  }
}

void main() {
  late _MockBridge bridge;

  setUp(() {
    flowEventLoggingEnabled = false;
    bridge = _MockBridge();
  });

  // ---------------------------------------------------------------------------
  // constants
  // ---------------------------------------------------------------------------
  group('constants', () {
    test('defaultRendezvousAddress is valid multiaddr', () {
      expect(defaultRendezvousAddress, startsWith('/dns/'));
      expect(defaultRendezvousAddress, contains('/wss/'));
      expect(defaultRendezvousAddress, contains('/p2p/'));
    });

    test('defaultQUICRelayAddress is valid multiaddr', () {
      expect(defaultQUICRelayAddress, startsWith('/dns/'));
      expect(defaultQUICRelayAddress, contains('/quic-v1/'));
      expect(defaultQUICRelayAddress, contains('/p2p/'));
    });

    test('default relay addresses use /dns/ not /dns4/', () {
      expect(defaultRendezvousAddress, isNot(contains('/dns4/')));
      expect(defaultQUICRelayAddress, isNot(contains('/dns4/')));
    });

    test('defaultRelayAddresses() returns /dns/ addresses', () {
      final addrs = defaultRelayAddresses();
      for (final addr in addrs) {
        expect(
          addr,
          isNot(contains('/dns4/')),
          reason: 'relay address should use /dns/ for dual-stack: $addr',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // callP2PNodeStart
  // ---------------------------------------------------------------------------
  group('callP2PNodeStart', () {
    test(
      'sends node:start with privateKeyHex and default relay addresses',
      () async {
        bridge.nextResponse = {'ok': true, 'peerId': '12D3KooWTest'};

        final result = await callP2PNodeStart(
          bridge,
          privateKeyHex: 'deadbeef',
        );

        expect(result['ok'], isTrue);
        final req = bridge.lastParsedRequest!;
        expect(req['cmd'], equals('node:start'));
        expect(req['payload']['privateKeyHex'], equals('deadbeef'));
        expect(
          req['payload']['relayAddresses'],
          contains(defaultRendezvousAddress),
        );
        // QUIC relay re-enabled after relay server dependency upgrade.
        expect(
          req['payload']['relayAddresses'],
          contains(defaultQUICRelayAddress),
        );
        expect(
          req['payload']['featureFlags'],
          equals(defaultResilienceFeatureFlags()),
        );
      },
    );

    test('default relay addresses include both WSS and QUIC', () async {
      bridge.nextResponse = {'ok': true, 'peerId': '12D3KooWTest'};

      await callP2PNodeStart(bridge, privateKeyHex: 'deadbeef');

      final payload =
          bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
      final relayAddresses = payload['relayAddresses'] as List;
      expect(relayAddresses, hasLength(2));
      expect(relayAddresses[0], equals(defaultRendezvousAddress));
      expect(relayAddresses[1], equals(defaultQUICRelayAddress));
    });

    test('default relay addresses honor MKNOON_RELAY_ADDRESSES style input', () {
      expect(
        defaultRelayAddresses(
          relayAddressesCsv:
              ' /ip4/127.0.0.1/tcp/4001/p2p/a , /ip4/127.0.0.1/tcp/4002/p2p/b ',
        ),
        equals([
          '/ip4/127.0.0.1/tcp/4001/p2p/a',
          '/ip4/127.0.0.1/tcp/4002/p2p/b',
        ]),
      );
    });

    test(
      'sends node:start with custom relay addresses when provided',
      () async {
        bridge.nextResponse = {'ok': true};

        await callP2PNodeStart(
          bridge,
          privateKeyHex: 'deadbeef',
          relayAddresses: ['/ip4/127.0.0.1/tcp/4001'],
        );

        final payload =
            bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
        expect(payload['relayAddresses'], equals(['/ip4/127.0.0.1/tcp/4001']));
      },
    );

    test('includes namespace in payload when provided', () async {
      bridge.nextResponse = {'ok': true};

      await callP2PNodeStart(
        bridge,
        privateKeyHex: 'deadbeef',
        namespace: 'mknoon:chat',
      );

      final payload =
          bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
      expect(payload['namespace'], equals('mknoon:chat'));
    });

    test('includes custom feature flags when provided', () async {
      bridge.nextResponse = {'ok': true};

      await callP2PNodeStart(
        bridge,
        privateKeyHex: 'deadbeef',
        featureFlags: const {
          'enableSharedRelayBackend': true,
          'enableMultiRelayRouting': false,
          'enableReservationAwareHealth': true,
          'enableInPlaceRelayRecovery': false,
          'enableResumeGroupRecovery': false,
        },
      );

      final payload =
          bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
      expect(payload['featureFlags']['enableMultiRelayRouting'], isFalse);
      expect(payload['featureFlags']['enableInPlaceRelayRecovery'], isFalse);
      expect(payload['featureFlags']['enableResumeGroupRecovery'], isFalse);
    });

    test('returns parsed response map', () async {
      bridge.nextResponse = {
        'ok': true,
        'peerId': '12D3KooWTest',
        'isStarted': true,
      };

      final result = await callP2PNodeStart(bridge, privateKeyHex: 'deadbeef');

      expect(result, isA<Map<String, dynamic>>());
      expect(result['peerId'], equals('12D3KooWTest'));
      expect(result['isStarted'], isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // callP2PNodeStop
  // ---------------------------------------------------------------------------
  group('callP2PNodeStop', () {
    test('sends node:stop and returns response', () async {
      bridge.nextResponse = {'ok': true, 'stopped': true};

      final result = await callP2PNodeStop(bridge);

      expect(result['ok'], isTrue);
      expect(result['stopped'], isTrue);
      expect(bridge.lastParsedRequest!['cmd'], equals('node:stop'));
    });
  });

  // ---------------------------------------------------------------------------
  // callP2PNodeStatus
  // ---------------------------------------------------------------------------
  group('callP2PNodeStatus', () {
    test('sends node:status and returns response', () async {
      bridge.nextResponse = {
        'ok': true,
        'isStarted': true,
        'peerId': '12D3KooW...',
      };

      final result = await callP2PNodeStatus(bridge);

      expect(result['ok'], isTrue);
      expect(result['isStarted'], isTrue);
      expect(bridge.lastParsedRequest!['cmd'], equals('node:status'));
    });
  });

  // ---------------------------------------------------------------------------
  // callP2PRelayReconnect
  // ---------------------------------------------------------------------------
  group('callP2PRelayReconnect', () {
    test('sends relay:reconnect and returns structured recoveryMode', () async {
      bridge.nextResponse = {
        'ok': true,
        'recoveryMode': 'watchdog_restart',
        'relayState': 'watchdog_restart',
        'healthyRelayCount': 0,
      };

      final result = await callP2PRelayReconnect(bridge);

      expect(result['ok'], isTrue);
      expect(result['recoveryMode'], equals('watchdog_restart'));
      expect(bridge.lastParsedRequest!['cmd'], equals('relay:reconnect'));
    });

    test('recoveryMode is sufficient without legacy recoveryMethod', () async {
      bridge.nextResponse = {
        'ok': true,
        'recoveryMode': 'in_place',
        'relayState': 'online',
        'healthyRelayCount': 1,
      };

      final result = await callP2PRelayReconnect(bridge);

      expect(result['ok'], isTrue);
      expect(result['recoveryMode'], equals('in_place'));
      expect(result.containsKey('recoveryMethod'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // callP2PRendezvousRegister
  // ---------------------------------------------------------------------------
  group('callP2PRendezvousRegister', () {
    test('sends rendezvous:register with defaults', () async {
      bridge.nextResponse = {'ok': true, 'registered': true};

      final result = await callP2PRendezvousRegister(bridge);

      expect(result['ok'], isTrue);
      expect(bridge.lastParsedRequest!['cmd'], equals('rendezvous:register'));
    });

    test('includes namespace and serverAddresses when provided', () async {
      bridge.nextResponse = {'ok': true};

      await callP2PRendezvousRegister(
        bridge,
        namespace: 'mknoon:chat:peer123',
        serverAddresses: ['/ip4/1.2.3.4/tcp/4001'],
      );

      final payload =
          bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
      expect(payload['namespace'], equals('mknoon:chat:peer123'));
      expect(payload['serverAddresses'], equals(['/ip4/1.2.3.4/tcp/4001']));
    });
  });

  // ---------------------------------------------------------------------------
  // callP2PRendezvousDiscover
  // ---------------------------------------------------------------------------
  group('callP2PRendezvousDiscover', () {
    test('sends rendezvous:discover with peerId', () async {
      bridge.nextResponse = {
        'ok': true,
        'peers': [
          {
            'id': 'peerA',
            'addresses': ['/ip4/1.2.3.4/tcp/4001'],
          },
        ],
      };

      final result = await callP2PRendezvousDiscover(
        bridge,
        peerId: '12D3KooWTargetPeer',
      );

      expect(result['ok'], isTrue);
      expect(bridge.lastParsedRequest!['cmd'], equals('rendezvous:discover'));
      final payload =
          bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
      expect(payload['peerId'], equals('12D3KooWTargetPeer'));
    });

    test(
      'includes namespace, serverAddresses, timeoutMs when provided',
      () async {
        bridge.nextResponse = {'ok': true, 'peers': []};

        await callP2PRendezvousDiscover(
          bridge,
          peerId: 'peer1',
          namespace: 'ns',
          serverAddresses: ['/addr'],
          timeoutMs: 5000,
        );

        final payload =
            bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
        expect(payload['namespace'], equals('ns'));
        expect(payload['serverAddresses'], equals(['/addr']));
        expect(payload['timeoutMs'], equals(5000));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // callP2PPeerDial
  // ---------------------------------------------------------------------------
  group('callP2PPeerDial', () {
    test('sends peer:dial with peerId', () async {
      bridge.nextResponse = {'ok': true, 'connected': true};

      final result = await callP2PPeerDial(
        bridge,
        peerId: '12D3KooWDialTarget',
      );

      expect(result['ok'], isTrue);
      expect(result['connected'], isTrue);
      expect(bridge.lastParsedRequest!['cmd'], equals('peer:dial'));
      final payload =
          bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
      expect(payload['peerId'], equals('12D3KooWDialTarget'));
    });

    test('includes addresses and timeoutMs when provided', () async {
      bridge.nextResponse = {'ok': true, 'connected': true};

      await callP2PPeerDial(
        bridge,
        peerId: 'peer1',
        addresses: ['/ip4/1.2.3.4/tcp/4001'],
        timeoutMs: 10000,
      );

      final payload =
          bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
      expect(payload['addresses'], equals(['/ip4/1.2.3.4/tcp/4001']));
      expect(payload['timeoutMs'], equals(10000));
    });
  });

  // ---------------------------------------------------------------------------
  // callP2PPeerDisconnect
  // ---------------------------------------------------------------------------
  group('callP2PPeerDisconnect', () {
    test('sends peer:disconnect with peerId', () async {
      bridge.nextResponse = {'ok': true, 'disconnected': true};

      final result = await callP2PPeerDisconnect(
        bridge,
        peerId: '12D3KooWDisconnectTarget',
      );

      expect(result['ok'], isTrue);
      expect(bridge.lastParsedRequest!['cmd'], equals('peer:disconnect'));
      final payload =
          bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
      expect(payload['peerId'], equals('12D3KooWDisconnectTarget'));
    });
  });

  // ---------------------------------------------------------------------------
  // callP2PInboxStore
  // ---------------------------------------------------------------------------
  group('callP2PInboxStore', () {
    test('sends inbox:store with toPeerId and message', () async {
      bridge.nextResponse = {'ok': true, 'stored': true};

      final result = await callP2PInboxStore(
        bridge,
        toPeerId: '12D3KooWInboxTarget',
        message: 'Hello offline!',
      );

      expect(result['ok'], isTrue);
      expect(bridge.lastParsedRequest!['cmd'], equals('inbox:store'));
      final payload =
          bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
      expect(payload['toPeerId'], equals('12D3KooWInboxTarget'));
      expect(payload['message'], equals('Hello offline!'));
    });
  });

  // ---------------------------------------------------------------------------
  // callP2PInboxRegisterToken
  // ---------------------------------------------------------------------------
  group('callP2PInboxRegisterToken', () {
    test('sends inbox:register_token with token and platform', () async {
      bridge.nextResponse = {'ok': true, 'registered': true};

      final result = await callP2PInboxRegisterToken(
        bridge,
        token: 'fcm_token_abc123',
        platform: 'ios',
      );

      expect(result['ok'], isTrue);
      expect(bridge.lastParsedRequest!['cmd'], equals('inbox:register_token'));
      final payload =
          bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
      expect(payload['token'], equals('fcm_token_abc123'));
      expect(payload['platform'], equals('ios'));
    });
  });

  // ---------------------------------------------------------------------------
  // callP2PInboxRetrieve
  // ---------------------------------------------------------------------------
  group('callP2PInboxRetrieve', () {
    test('sends inbox:retrieve', () async {
      bridge.nextResponse = {'ok': true, 'messages': []};

      final result = await callP2PInboxRetrieve(bridge);

      expect(result['ok'], isTrue);
      expect(bridge.lastParsedRequest!['cmd'], equals('inbox:retrieve'));
    });

    test('passes timeoutMs when provided', () async {
      bridge.nextResponse = {'ok': true, 'messages': [], 'hasMore': false};

      await callP2PInboxRetrieve(bridge, timeoutMs: 2500);

      final payload =
          bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
      expect(payload['timeoutMs'], equals(2500));
    });
  });

  // ---------------------------------------------------------------------------
  // callP2PInboxRetrievePending
  // ---------------------------------------------------------------------------
  group('callP2PInboxRetrievePending', () {
    test('sends inbox:retrieve_pending', () async {
      bridge.nextResponse = {'ok': true, 'messages': [], 'hasMore': false};

      final result = await callP2PInboxRetrievePending(bridge);

      expect(result['ok'], isTrue);
      expect(
        bridge.lastParsedRequest!['cmd'],
        equals('inbox:retrieve_pending'),
      );
    });

    test('passes timeoutMs when provided', () async {
      bridge.nextResponse = {'ok': true, 'messages': [], 'hasMore': false};

      await callP2PInboxRetrievePending(bridge, timeoutMs: 4000);

      final payload =
          bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
      expect(payload['timeoutMs'], equals(4000));
    });
  });

  // ---------------------------------------------------------------------------
  // callP2PInboxAck
  // ---------------------------------------------------------------------------
  group('callP2PInboxAck', () {
    test('sends inbox:ack with entryIds and optional timeout', () async {
      bridge.nextResponse = {'ok': true, 'acked': 2};

      final result = await callP2PInboxAck(
        bridge,
        entryIds: ['entry-1', 'entry-2'],
        timeoutMs: 1500,
      );

      expect(result['ok'], isTrue);
      expect(result['acked'], equals(2));
      expect(bridge.lastParsedRequest!['cmd'], equals('inbox:ack'));
      final payload =
          bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
      expect(payload['entryIds'], equals(['entry-1', 'entry-2']));
      expect(payload['timeoutMs'], equals(1500));
    });
  });

  // ---------------------------------------------------------------------------
  // callP2PMediaUpload
  // ---------------------------------------------------------------------------
  group('callP2PMediaUpload', () {
    test('sends media:upload with id, toPeerId, mime, filePath', () async {
      bridge.nextResponse = {'ok': true, 'id': 'uuid-123'};

      final result = await callP2PMediaUpload(
        bridge,
        id: 'uuid-123',
        toPeerId: '12D3KooWMediaTarget',
        mime: 'image/jpeg',
        filePath: '/tmp/photo.jpg',
      );

      expect(result['ok'], isTrue);
      expect(result['id'], equals('uuid-123'));
      expect(bridge.lastParsedRequest!['cmd'], equals('media:upload'));
      final payload =
          bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
      expect(payload['id'], equals('uuid-123'));
      expect(payload['to'], equals('12D3KooWMediaTarget'));
      expect(payload['mime'], equals('image/jpeg'));
      expect(payload['filePath'], equals('/tmp/photo.jpg'));
    });
  });

  // ---------------------------------------------------------------------------
  // callP2PMediaDownload
  // ---------------------------------------------------------------------------
  group('callP2PMediaDownload', () {
    test('sends media:download with id and outputPath', () async {
      bridge.nextResponse = {
        'ok': true,
        'id': 'uuid-456',
        'mime': 'image/png',
        'size': 1024,
      };

      final result = await callP2PMediaDownload(
        bridge,
        id: 'uuid-456',
        outputPath: '/tmp/downloaded.png',
      );

      expect(result['ok'], isTrue);
      expect(bridge.lastParsedRequest!['cmd'], equals('media:download'));
      final payload =
          bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
      expect(payload['id'], equals('uuid-456'));
      expect(payload['outputPath'], equals('/tmp/downloaded.png'));
    });
  });

  // ---------------------------------------------------------------------------
  // callP2PMediaDelete
  // ---------------------------------------------------------------------------
  group('callP2PMediaDelete', () {
    test('sends media:delete with id', () async {
      bridge.nextResponse = {'ok': true};

      final result = await callP2PMediaDelete(bridge, id: 'uuid-789');

      expect(result['ok'], isTrue);
      expect(bridge.lastParsedRequest!['cmd'], equals('media:delete'));
      final payload =
          bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
      expect(payload['id'], equals('uuid-789'));
    });
  });

  // ---------------------------------------------------------------------------
  // callP2PMediaList
  // ---------------------------------------------------------------------------
  group('callP2PMediaList', () {
    test('sends media:list', () async {
      bridge.nextResponse = {'ok': true, 'blobs': []};

      final result = await callP2PMediaList(bridge);

      expect(result['ok'], isTrue);
      expect(bridge.lastParsedRequest!['cmd'], equals('media:list'));
    });
  });

  // ---------------------------------------------------------------------------
  // callP2PProfileUpload
  // ---------------------------------------------------------------------------
  group('callP2PProfileUpload', () {
    test('sends profile:upload with mime and filePath', () async {
      bridge.nextResponse = {'ok': true};

      final result = await callP2PProfileUpload(
        bridge,
        mime: 'image/jpeg',
        filePath: '/tmp/avatar.jpg',
      );

      expect(result['ok'], isTrue);
      expect(bridge.lastParsedRequest!['cmd'], equals('profile:upload'));
      final payload =
          bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
      expect(payload['mime'], equals('image/jpeg'));
      expect(payload['filePath'], equals('/tmp/avatar.jpg'));
    });
  });

  // ---------------------------------------------------------------------------
  // callP2PProfileDownload
  // ---------------------------------------------------------------------------
  group('callP2PProfileDownload', () {
    test('sends profile:download with ownerPeerId and outputPath', () async {
      bridge.nextResponse = {'ok': true, 'mime': 'image/jpeg', 'size': 2048};

      final result = await callP2PProfileDownload(
        bridge,
        ownerPeerId: '12D3KooWProfileOwner',
        outputPath: '/tmp/profile.jpg',
      );

      expect(result['ok'], isTrue);
      expect(bridge.lastParsedRequest!['cmd'], equals('profile:download'));
      final payload =
          bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
      expect(payload['ownerPeerId'], equals('12D3KooWProfileOwner'));
      expect(payload['outputPath'], equals('/tmp/profile.jpg'));
    });
  });

  // ---------------------------------------------------------------------------
  // callP2PMessageSend
  // ---------------------------------------------------------------------------
  group('callP2PMessageSend', () {
    test('sends message:send with peerId and message', () async {
      bridge.nextResponse = {'ok': true, 'sent': true};

      final result = await callP2PMessageSend(
        bridge,
        peerId: '12D3KooWSendTarget',
        message: 'Hello, world!',
      );

      expect(result['ok'], isTrue);
      expect(result['sent'], isTrue);
      expect(bridge.lastParsedRequest!['cmd'], equals('message:send'));
      final payload =
          bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
      expect(payload['peerId'], equals('12D3KooWSendTarget'));
      expect(payload['message'], equals('Hello, world!'));
    });

    test(
      'preserves additive transport field from the bridge response',
      () async {
        bridge.nextResponse = {
          'ok': true,
          'sent': true,
          'acked': true,
          'transport': 'relay',
        };

        final result = await callP2PMessageSend(
          bridge,
          peerId: '12D3KooWSendTarget',
          message: 'Hello, relay!',
        );

        expect(result['acked'], isTrue);
        expect(result['transport'], equals('relay'));
      },
    );

    test('includes timeoutMs when provided', () async {
      bridge.nextResponse = {'ok': true, 'sent': true};

      await callP2PMessageSend(
        bridge,
        peerId: 'peer1',
        message: 'msg',
        timeoutMs: 30000,
      );

      final payload =
          bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
      expect(payload['timeoutMs'], equals(30000));
    });
  });

  // ---------------------------------------------------------------------------
  // error handling
  // ---------------------------------------------------------------------------
  group('error handling', () {
    test('propagates exception when bridge.send throws', () async {
      bridge.shouldThrow = true;

      expect(() => callP2PNodeStop(bridge), throwsA(isA<Exception>()));
    });
  });

  // ---------------------------------------------------------------------------
  // Phase 3: Multi-Relay Routing — explicit plan-required tests
  // ---------------------------------------------------------------------------
  group('Phase 3: Multi-Relay Routing', () {
    test('callP2PNodeStart sends all default relay addresses', () async {
      bridge.nextResponse = {'ok': true, 'peerId': '12D3KooWTest'};

      await callP2PNodeStart(bridge, privateKeyHex: 'deadbeef');

      final payload =
          bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
      final relayAddresses = payload['relayAddresses'] as List;

      // Must send both WSS and QUIC addresses.
      expect(relayAddresses, hasLength(2));
      expect(relayAddresses, contains(defaultRendezvousAddress));
      expect(relayAddresses, contains(defaultQUICRelayAddress));

      // Both addresses should point to the same relay peer.
      for (final addr in relayAddresses) {
        expect(addr, contains('/p2p/'));
      }
    });

    test(
      'callP2PRendezvousRegister forwards explicit serverAddresses',
      () async {
        bridge.nextResponse = {'ok': true};

        final explicitAddresses = [
          '/ip4/10.0.0.1/tcp/4001/p2p/12D3KooWRelay1',
          '/ip4/10.0.0.2/tcp/4001/p2p/12D3KooWRelay2',
        ];

        await callP2PRendezvousRegister(
          bridge,
          namespace: 'mknoon:chat:test',
          serverAddresses: explicitAddresses,
        );

        final payload =
            bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
        expect(payload['serverAddresses'], equals(explicitAddresses));
        expect(payload['serverAddresses'], hasLength(2));
      },
    );

    test(
      'callP2PRendezvousDiscover forwards explicit serverAddresses',
      () async {
        bridge.nextResponse = {'ok': true, 'peers': []};

        final explicitAddresses = [
          '/ip4/10.0.0.1/tcp/4001/p2p/12D3KooWRelay1',
          '/ip4/10.0.0.2/tcp/4001/p2p/12D3KooWRelay2',
        ];

        await callP2PRendezvousDiscover(
          bridge,
          peerId: 'peer1',
          namespace: 'mknoon:chat:test',
          serverAddresses: explicitAddresses,
          timeoutMs: 5000,
        );

        final payload =
            bridge.lastParsedRequest!['payload'] as Map<String, dynamic>;
        expect(payload['serverAddresses'], equals(explicitAddresses));
        expect(payload['serverAddresses'], hasLength(2));
      },
    );
  });
}
