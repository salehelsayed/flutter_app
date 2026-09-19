import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/debug/notification_dual_path_e2e_sender.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/push/domain/received_wake_token_store.dart';

Map<String, dynamic> config() => {
  'transport_action': notificationDualPathSenderAction,
  'stepId': 'step-1',
  'runId': 'run-1',
  'nonce': 'nonce-1',
  'targetPeerId': 'receiver',
  'text': 'fixture',
  'timeoutMs': 180000,
};

class Identities implements IdentityRepository {
  IdentityModel? value = IdentityModel(
    peerId: 'sender',
    publicKey: 'public',
    privateKey: 'private',
    mnemonic12: 'private',
    mlKemPublicKey: 'ownkem',
    username: 'Sender',
    createdAt: 'now',
    updatedAt: 'now',
  );
  @override
  Future<IdentityModel?> loadIdentity() async => value;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Contacts implements ContactRepository {
  ContactModel? value = const ContactModel(
    peerId: 'receiver',
    publicKey: 'contactpub',
    rendezvous: 'rv',
    username: 'Receiver',
    signature: 'sig',
    scannedAt: 'now',
    mlKemPublicKey: 'receiverkem',
  );
  @override
  Future<ContactModel?> getContact(String peer) async => value;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Tokens implements ReceivedWakeTokenStore {
  Map<String, String>? value = {'tok': 'real-contact-grant', 'ts': 'now'};
  @override
  Future<Map<String, String>?> readTokenFor(String peer) async => value;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class CryptoBridge implements Bridge {
  final requests = <Map<String, dynamic>>[];
  @override
  Future<String> send(String command) async {
    final request = jsonDecode(command) as Map<String, dynamic>;
    requests.add(request);
    return jsonEncode({
      'ok': true,
      'kem': 'real-bridge-kem',
      'ciphertext': 'real-bridge-cipher',
      'nonce': 'real-bridge-nonce',
    });
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Service implements P2PService, AckOrExpiryInboxStore {
  final events = <String>[];
  String? storedWire, liveWire;
  AckCustodyKind? kind;
  @override
  NodeState currentState = const NodeState(
    peerId: 'sender',
    isStarted: true,
    sendCapabilityReady: true,
    inboxCapabilityReady: true,
  );
  @override
  Future<InboxStoreOutcome> storeInAckCustodyInboxDetailed(
    String peer,
    String wire, {
    required AckCustodyKind custodyKind,
    int? timeoutMs,
  }) async {
    expect(timeoutMs, inInclusiveRange(1, 180000));
    events.add('store');
    storedWire = wire;
    kind = custodyKind;
    return const InboxStoreOutcome(
      status: InboxStoreStatus.stored,
      storeStatus: 'stored',
      custodyContract: ackOrExpiryInboxCustodyContract,
    );
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peer,
    String wire, {
    int? timeoutMs,
  }) async {
    events.add('live');
    liveWire = wire;
    return const SendMessageResult(
      sent: true,
      acked: true,
      transport: 'direct',
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  test(
    'installed gate excludes ordinary production and other E2E profiles',
    () {
      for (final debug in [true, false]) {
        for (final e2e in [true, false]) {
          for (final fcm in [true, false]) {
            for (final profile in [
              'android.production_fcm',
              'android.production_fcm.fixed_wake',
              'android.e2e',
              '',
            ]) {
              expect(
                allowsNotificationDualPathSender(
                  debugMode: debug,
                  e2eTestMode: e2e,
                  productionFcm: fcm,
                  installedProfileId: profile,
                ),
                debug && e2e && fcm && profile == 'android.production_fcm',
              );
            }
          }
        }
      }
    },
  );
  test(
    'application adapter uses real crypto typed custody and same live envelope',
    () async {
      final ids = Identities(),
          contacts = Contacts(),
          tokens = Tokens(),
          bridge = CryptoBridge(),
          service = Service();
      final sender = createNotificationDualPathSender(
        enabled: true,
        service: service,
        bridge: bridge,
        identities: ids,
        contacts: contacts,
        wakeTokens: tokens,
      );
      Map<String, dynamic>? release;
      final result = await sender.run(
        request: NotificationDualPathRequest.fromConfig(config()),
        writePrepared: (p) async {
          service.events.add('provider-observed-by-host');
          release = {
            for (final k in [
              'schema',
              'stepId',
              'runId',
              'nonce',
              'messageId',
              'wireSha256',
            ])
              k: p[k],
          };
        },
        readControl: () async => release,
        cleanupControl: (_) async {},
      );
      expect(bridge.requests, hasLength(1));
      expect(bridge.requests.single['cmd'], 'message.encrypt');
      expect(
        bridge.requests.single['payload']['recipientPublicKey'],
        'receiverkem',
      );
      expect(
        jsonDecode(
          bridge.requests.single['payload']['plaintext'],
        )['senderPeerId'],
        'sender',
      );
      expect(service.events, ['store', 'provider-observed-by-host', 'live']);
      expect(service.kind, AckCustodyKind.directTextV108);
      expect(service.liveWire, service.storedWire);
      final envelope = jsonDecode(service.liveWire!);
      expect(envelope['encrypted']['ciphertext'], 'real-bridge-cipher');
      expect(result['acked'], true);
      expect(
        result.keys,
        containsAll(['expiresAtMs', 'ciphertextSha256', 'wireSha256']),
      );
      expect(jsonEncode(result), isNot(contains('real-contact-grant')));
      expect(jsonEncode(result), isNot(contains('real-bridge-cipher')));
    },
  );
  for (final missing in ['identity', 'contact', 'wake', 'node', 'blocked']) {
    test('missing $missing authority forbids even encryption', () async {
      final ids = Identities(),
          contacts = Contacts(),
          tokens = Tokens(),
          bridge = CryptoBridge(),
          service = Service();
      switch (missing) {
        case 'identity':
          ids.value = null;
        case 'contact':
          contacts.value = null;
        case 'wake':
          tokens.value = null;
        case 'node':
          service.currentState = NodeState.stopped;
        case 'blocked':
          contacts.value = const ContactModel(
            peerId: 'receiver',
            publicKey: 'pub',
            rendezvous: 'rv',
            username: 'Receiver',
            signature: 'sig',
            scannedAt: 'now',
            mlKemPublicKey: 'kem',
            isBlocked: true,
          );
      }
      final sender = createNotificationDualPathSender(
        enabled: true,
        service: service,
        bridge: bridge,
        identities: ids,
        contacts: contacts,
        wakeTokens: tokens,
      );
      await expectLater(
        sender.run(
          request: NotificationDualPathRequest.fromConfig(config()),
          writePrepared: (_) async {},
          readControl: () async => null,
          cleanupControl: (_) async {},
        ),
        throwsA(
          isA<NotificationDualPathFailure>().having(
            (e) => e.code,
            'code',
            'authority_unavailable',
          ),
        ),
      );
      expect(bridge.requests, isEmpty);
      expect(service.events, isEmpty);
    });
  }
  test('private control cleanup preserves a foreign request', () async {
    final directory = await Directory.systemTemp.createTemp(
      'notification-dual-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/$notificationDualPathReleaseFileName');
    final control = NotificationDualPathFileControl(file);
    final request = NotificationDualPathRequest.fromConfig(config());
    await file.writeAsString(
      jsonEncode({
        ...request.binding,
        'nonce': 'foreign',
        'decision': 'cancel',
      }),
    );
    await control.cleanup(request);
    expect(await file.exists(), true);
    await file.writeAsString(
      jsonEncode({...request.binding, 'decision': 'cancel'}),
    );
    expect((await control.read())!['decision'], 'cancel');
    await control.cleanup(request);
    expect(await file.exists(), false);
  });
  test('file control rejects malformed and oversized input', () async {
    final directory = await Directory.systemTemp.createTemp(
      'notification-dual-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/control');
    final control = NotificationDualPathFileControl(file);
    for (final raw in ['[]', 'x' * 4097]) {
      await file.writeAsString(raw);
      await expectLater(
        control.read(),
        throwsA(isA<NotificationDualPathFailure>()),
      );
    }
  });
  test('closed request rejects added operations and deadline extension', () {
    for (final change in [
      {'send_message': true},
      {'timeoutMs': 180001},
      {'text': ''},
    ]) {
      expect(
        () => NotificationDualPathRequest.fromConfig({...config(), ...change}),
        throwsA(isA<NotificationDualPathFailure>()),
      );
    }
  });
  test('dispatch is before generic drain and shutdown closes sender first', () {
    final source = File(
      'lib/core/debug/intro_e2e_runner.dart',
    ).readAsStringSync();
    final poller = source.indexOf('void startIntroE2EPoller');
    final branch = source.indexOf(
      "config['transport_action'] == notificationDualPathSenderAction",
      poller,
    );
    final generic = source.indexOf('await runIntroE2EActions(', poller);
    expect(branch, greaterThan(poller));
    expect(branch, lessThan(generic));
    final action = source.indexOf('await notificationSender.run(', branch);
    expect(
      source.indexOf('await _deleteConfigIfPresent();', branch),
      lessThan(action),
    );
    final shutdown = source.substring(
      source.indexOf('Future<void> stopIntroE2EPoller()'),
      source.indexOf(
        '@visibleForTesting',
        source.indexOf('Future<void> stopIntroE2EPoller()'),
      ),
    );
    expect(
      shutdown.indexOf('_notificationDualPathSender?.close();'),
      lessThan(shutdown.indexOf('_introE2EPollerLifecycle?.dispose()')),
    );
  });
}
