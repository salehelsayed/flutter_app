import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../bridge/fake_bridge.dart';
import '../services/fake_p2p_service.dart';
import '../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../features/conversation/domain/repositories/fake_message_repository.dart';
import '../../features/identity/domain/repositories/fake_identity_repository.dart';

final class _IntentRepository extends FakeMessageRepository
    implements AuthoredDirectTextIntentRepository {
  final intents = <AuthoredDirectTextIntent>[];
  @override
  bool get supportsAuthoredDirectTextIntents => true;
  @override
  Future<List<AuthoredDirectTextIntent>>
  loadAuthoredDirectTextIntents() async => intents;
  @override
  Future<bool> saveAuthoredDirectTextIntent(
    AuthoredDirectTextIntent intent,
  ) async {
    intents.add(intent);
    return true;
  }

  @override
  Future<bool> cancelAuthoredDirectTextIntent(
    AuthoredDirectTextIntent intent,
  ) async => intents.remove(intent);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppDiagnostics diagnostics;
  late _IntentRepository messages;
  late FakeContactRepository contacts;
  late FakeIdentityRepository identity;
  late FakeP2PService transport;
  late FakeBridge bridge;
  late bool priorFlow;

  setUp(() async {
    priorFlow = flowEventLoggingEnabled;
    flowEventLoggingEnabled = false;
    directory = await Directory.systemTemp.createTemp('recover-observation-');
    diagnostics = await AppDiagnostics.installForTesting(directory: directory);
    messages = _IntentRepository();
    contacts = FakeContactRepository();
    identity = FakeIdentityRepository()
      ..seed(
        IdentityModel(
          peerId: 'PRIVATE_RECOVERY_SELF',
          publicKey: 'PRIVATE_RECOVERY_PK',
          privateKey: 'PRIVATE_RECOVERY_SK',
          mnemonic12: 'PRIVATE_RECOVERY_WORDS',
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
        ),
      );
    transport = FakeP2PService();
    bridge = FakeBridge();
  });
  tearDown(() async {
    flowEventLoggingEnabled = priorFlow;
    await diagnostics.dispose();
    await directory.delete(recursive: true);
  });

  void seed({required String lane, String? key}) {
    contacts.seed([
      ContactModel(
        peerId: 'PRIVATE_RECOVERY_PEER',
        publicKey: 'PRIVATE_RECOVERY_PEER_PK',
        rendezvous: 'PRIVATE_RECOVERY_ROUTE',
        username: 'PRIVATE_RECOVERY_NAME',
        signature: 'PRIVATE_RECOVERY_SIG',
        scannedAt: '2026-01-01T00:00:00.000Z',
        mlKemPublicKey: key,
      ),
    ]);
    for (var i = 0; i < 3; i++) {
      if (lane != 'rows') {
        messages.intents.add(
          AuthoredDirectTextIntent(
            id: 'PRIVATE_RECOVERY_INTENT_$i',
            contactPeerId: 'PRIVATE_RECOVERY_PEER',
            text: 'PRIVATE_RECOVERY_CONTENT_$i',
            timestamp: '2026-01-01T00:00:00.000Z',
            token: 'PRIVATE_RECOVERY_TOKEN_$i',
          ),
        );
      }
    }
    if (lane != 'intents') {
      messages.seed(
        List.generate(
          3,
          (i) => ConversationMessage(
            id: 'PRIVATE_RECOVERY_ROW_$i',
            contactPeerId: 'PRIVATE_RECOVERY_PEER',
            senderPeerId: 'PRIVATE_RECOVERY_SELF',
            text: 'PRIVATE_RECOVERY_CONTENT_$i',
            timestamp: '2026-01-01T00:00:00.000Z',
            createdAt: '2026-01-01T00:00:00.000Z',
            status: 'failed',
            isIncoming: false,
          ),
        ),
      );
    }
  }

  Future<int> recover() => retryFailedMessages(
    messageRepo: messages,
    identityRepo: identity,
    contactRepo: contacts,
    p2pService: transport,
    bridge: bridge,
  );
  Future<List<Map<String, dynamic>>> records() async {
    final preview = await diagnostics.exportPreview();
    expect(preview, isNot(contains('PRIVATE_RECOVERY')));
    return ((jsonDecode(preview) as Map)['events'] as List)
        .cast<Map<String, dynamic>>()
        .where((e) => e['feature'] == 'message')
        .toList();
  }

  Future<void> expectNoSend() async {
    expect(bridge.commandLog, isEmpty);
    expect(transport.storeInInboxCallCount, 0);
    expect(transport.sendMessageWithReplyCallCount, 0);
    for (final row in await messages.getFailedOutgoingMessages()) {
      expect(row.status, 'failed');
      expect(row.wireEnvelope, isNull);
    }
  }

  for (final lane in ['intents', 'rows', 'both']) {
    for (final key in <String?>[null, '', ' \t\n ']) {
      test(
        'missing-key $lane ${key == null
            ? 'null'
            : key.isEmpty
            ? 'empty'
            : 'whitespace'} is one anonymous block per bulk pass',
        () async {
          seed(lane: lane, key: key);
          for (var pass = 1; pass <= 2; pass++) {
            expect(await recover(), 0);
            await expectNoSend();
            final events = await records();
            expect(events, hasLength(pass));
            for (final e in events) {
              expect(e['stage'], 'recover');
              expect(e['outcome'], 'blocked');
              expect(e['reason'], 'recipient_key_missing');
              expect(e['values'], isEmpty);
              expect(e.containsKey('traceId'), isFalse);
              expect(e.containsKey('attemptId'), isFalse);
            }
          }
          expect(messages.intents, hasLength(lane == 'rows' ? 0 : 3));
          expect(
            await messages.getFailedOutgoingMessages(),
            hasLength(lane == 'intents' ? 0 : 3),
          );
        },
      );
    }
  }
  test('opt-out preserves both deferred lanes without recording', () async {
    seed(lane: 'both');
    await diagnostics.setEnabled(false);
    expect(await recover(), 0);
    await expectNoSend();
    expect(await records(), isEmpty);
    expect(messages.intents, hasLength(3));
    expect(await messages.getFailedOutgoingMessages(), hasLength(3));
  });
  test('unavailable observer preserves both deferred lanes', () async {
    seed(lane: 'both');
    var writes = 0;
    diagnostics = await AppDiagnostics.installForTesting(
      directory: directory,
      persist: (_, _) async {
        writes++;
        throw StateError('PRIVATE_RECOVERY_OBSERVER');
      },
    );
    final before = writes;
    expect(await recover(), 0);
    await diagnostics.exportPreview();
    expect(writes, greaterThan(before));
    await expectNoSend();
    expect(messages.intents, hasLength(3));
    expect(await messages.getFailedOutgoingMessages(), hasLength(3));
  });
}
