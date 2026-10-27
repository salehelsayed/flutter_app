import 'dart:convert';

import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/push/infrastructure/received_wake_token_store_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/fakes/in_memory_inbox_staging_repository.dart';
import '../../shared/fakes/recording_fake_bridge.dart';
import '../secure_storage/fake_secure_key_store.dart';

const _recipient = 'author-peer';
const _wakeToken = 'recipient-issued-token';
const _viewEnvelope =
    ' { "type": "post_view", "version": "2", '
    '"event_id": "view-event", "sender_peer_id": "self-peer", '
    '"post_id": "thought-1", "created_at": "2026-10-27T12:00:00.000Z", '
    '"post_created_at": "2026-10-27T11:00:00.000Z", '
    '"encrypted": { "kem": "view-kem", "ciphertext": "view-ciphertext", '
    '"nonce": "view-nonce" } }\n';
const _chatEnvelope =
    '{"type":"chat_message","version":"2","id":"chat-1",'
    '"senderPeerId":"self-peer",'
    '"encrypted":{"kem":"kem","ciphertext":"ciphertext","nonce":"nonce"}}';

void main() {
  late RecordingFakeBridge bridge;
  late P2PServiceImpl service;
  late ReceivedWakeTokenStoreImpl receivedTokens;
  late bool historySaysDelivered;
  late int historyChecks;

  setUp(() async {
    historySaysDelivered = false;
    historyChecks = 0;
    bridge = RecordingFakeBridge()
      ..whenCommand(
        'node:start',
        (_) => jsonEncode({
          'ok': true,
          'peerId': 'self-peer',
          'isStarted': true,
          'listenAddresses': <String>[],
          'circuitAddresses': <String>[],
          'connections': <Object?>[],
        }),
      )
      ..whenCommand(
        'inbox:store',
        (payload) => jsonEncode({
          'ok': true,
          'storeStatus': 'stored',
          if (payload?['custodyContract'] != null)
            'custodyContract': payload!['custodyContract'],
        }),
      )
      ..whenCommand(
        'inbox:retrieve_pending',
        (_) => jsonEncode({'ok': true, 'entries': <Object?>[]}),
      );
    receivedTokens = ReceivedWakeTokenStoreImpl(
      secureKeyStore: FakeSecureKeyStore(),
    );
    await receivedTokens.writeTokenFor(
      _recipient,
      _wakeToken,
      '2026-10-27T12:00:00.000Z',
    );
    service = P2PServiceImpl(
      bridge: bridge,
      inboxStagingRepository: InMemoryInboxStagingRepository(),
      receivedWakeTokenStore: receivedTokens,
      shouldSuppressDirectInboxNotification: (_, _) async {
        historyChecks++;
        return historySaysDelivered;
      },
    );
    addTearDown(service.dispose);
    expect(
      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer'),
      isTrue,
    );
  });

  Map<String, dynamic> lastStore() => bridge.payloadsFor('inbox:store').last!;

  test(
    'an encrypted view receipt is quiet without changing its exact relay fallback',
    () async {
      final outcome = await service.storeInInboxDetailed(
        _recipient,
        _viewEnvelope,
      );

      expect(outcome.accepted, isTrue);
      expect(lastStore(), {
        'toPeerId': _recipient,
        'message': _viewEnvelope,
        'wakeToken': _wakeToken,
        'suppressNotification': true,
      });
      expect(historyChecks, 0);
    },
  );

  test(
    'quiet receipt storage preserves an explicitly requested custody contract',
    () async {
      final outcome = await service.storeInAckCustodyInboxDetailed(
        _recipient,
        _viewEnvelope,
        custodyKind: AckCustodyKind.directTextV108,
      );

      expect(outcome.ackOrExpiryAccepted, isTrue);
      expect(lastStore(), {
        'toPeerId': _recipient,
        'message': _viewEnvelope,
        'wakeToken': _wakeToken,
        'custodyContract': ackOrExpiryInboxCustodyContract,
        'custodyKind': 'direct_text_v108',
        'suppressNotification': true,
      });
      expect(historyChecks, 0);
    },
  );

  test(
    'ordinary chat and other controls keep their existing notification behavior',
    () async {
      final view = jsonDecode(_viewEnvelope) as Map<String, dynamic>;
      final controls = [
        _chatEnvelope,
        for (final type in [
          'post_create',
          'post_retract',
          'post_comment',
          'delivery_receipt',
        ])
          jsonEncode({...view, 'type': type}),
      ];
      for (final wire in controls) {
        final outcome = await service.storeInInboxDetailed(_recipient, wire);

        expect(outcome.accepted, isTrue);
        expect(lastStore(), {
          'toPeerId': _recipient,
          'message': wire,
          'wakeToken': _wakeToken,
        }, reason: wire);
      }
      expect(historyChecks, 0);
    },
  );

  test(
    'invalid JSON, versions, and cipher shapes do not gain quiet storage',
    () async {
      final view = jsonDecode(_viewEnvelope) as Map<String, dynamic>;
      final encrypted = view['encrypted'] as Map<String, dynamic>;
      final controls = [
        '{broken',
        'null',
        '[]',
        jsonEncode({...view, 'version': '1'}),
        jsonEncode({...view, 'version': 2}),
        jsonEncode({...view}..remove('version')),
        jsonEncode({...view}..remove('encrypted')),
        jsonEncode({...view, 'encrypted': null}),
        jsonEncode({...view, 'encrypted': <Object?>[]}),
        for (final field in ['kem', 'ciphertext', 'nonce']) ...[
          jsonEncode({
            ...view,
            'encrypted': {...encrypted}..remove(field),
          }),
          jsonEncode({
            ...view,
            'encrypted': {...encrypted, field: ''},
          }),
          jsonEncode({
            ...view,
            'encrypted': {...encrypted, field: '  '},
          }),
          jsonEncode({
            ...view,
            'encrypted': {...encrypted, field: 1},
          }),
        ],
      ];
      for (final wire in controls) {
        final outcome = await service.storeInInboxDetailed(_recipient, wire);

        expect(outcome.accepted, isTrue);
        expect(lastStore(), {
          'toPeerId': _recipient,
          'message': wire,
          'wakeToken': _wakeToken,
        }, reason: wire);
      }
      expect(historyChecks, 0);
    },
  );

  test(
    'quiet classification leaves semantic receipt validation to its receiver',
    () async {
      final typedCipher = jsonEncode({
        'type': 'post_view',
        'version': '2',
        'encrypted': {
          'kem': 'kem',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        },
      });

      final outcome = await service.storeInInboxDetailed(
        _recipient,
        typedCipher,
      );

      expect(outcome.accepted, isTrue);
      expect(lastStore()['message'], typedCipher);
      expect(lastStore()['toPeerId'], _recipient);
      expect(lastStore()['suppressNotification'], isTrue);
      expect(historyChecks, 0);
    },
  );

  test(
    'the existing direct-chat delivered-history policy still controls chat custody',
    () async {
      for (final delivered in [false, true]) {
        historySaysDelivered = delivered;
        final outcome = await service.storeInAckCustodyInboxDetailed(
          _recipient,
          _chatEnvelope,
          custodyKind: AckCustodyKind.directTextV108,
        );

        expect(outcome.ackOrExpiryAccepted, isTrue);
        expect(lastStore(), {
          'toPeerId': _recipient,
          'message': _chatEnvelope,
          'wakeToken': _wakeToken,
          'custodyContract': ackOrExpiryInboxCustodyContract,
          'custodyKind': 'direct_text_v108',
          if (delivered) 'suppressNotification': true,
        });
      }
      expect(historyChecks, 2);
    },
  );
}
