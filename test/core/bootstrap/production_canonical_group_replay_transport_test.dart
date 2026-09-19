import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/app/bootstrap/production_canonical_group_replay_composition.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/protected_group_envelope.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../bridge/fake_bridge.dart';

void main() {
  group('protected group runtime transport', () {
    for (final account in ['receiver-account', 'receiver-transport']) {
      test('ordinary primary $account uses actual node for authority', () async {
        final f = _Fixture(account: account);
        final result = await f.composition.replay(_authority());
        expect(result.reasonCode, 'authority_rejected');
        expect(
          f.decrypts,
          1,
          reason:
              'Recipient routing admits crypto; fake crypto deliberately refuses application.',
        );
      });
    }
    for (final foreign in [
      'foreign-transport',
      'sibling-transport',
      'receiver-account',
    ]) {
      test(
        'authority cannot select local identity from destination $foreign',
        () async {
          final f = _Fixture();
          final result = await f.composition.replay(_authority(to: foreign));
          expect(
            result.disposition,
            ProtectedGroupReplayDisposition.terminalRejected,
          );
          expect(f.decrypts, 0);
        },
      );
    }
    test(
      'linked secondary preserves exact persisted account and transport',
      () async {
        final f = _Fixture(installation: _linked());
        await f.composition.replay(_authority());
        expect(f.decrypts, 1);
      },
    );
    for (final installation in [
      _linked(transport: 'sibling-transport'),
      _linked(account: 'foreign-account'),
      _linked(publicKey: 'foreign-public'),
      const LinkedInstallationAuthoritySnapshot(
        disposition: LinkedInstallationDisposition.failClosed,
        credential: null,
        failClosedReason: 'malformed',
      ),
    ]) {
      test(
        'missing or stale linked authority ${installation.credential?.transportPeerId}/${installation.credential?.accountPeerId}/${installation.credential?.accountPublicKey} stays pending',
        () async {
          final f = _Fixture(installation: installation);
          final result = await f.composition.replay(_authority());
          expect(
            result.disposition,
            ProtectedGroupReplayDisposition.prerequisiteWaiting,
          );
          expect(result.reasonCode, 'local_transport_authority_unavailable');
          expect(f.decrypts, 0);
        },
      );
    }
    for (final transport in <String?>[null, '']) {
      test(
        'absent actual node $transport does not fall back to account',
        () async {
          final f = _Fixture()..runtimeTransport = transport;
          final result = await f.composition.replay(_authority());
          expect(
            result.disposition,
            ProtectedGroupReplayDisposition.prerequisiteWaiting,
          );
          expect(f.decrypts, 0);
        },
      );
    }
    test(
      'runtime cutover while identity loads refuses stale dispatch',
      () async {
        final f = _Fixture();
        f.onIdentity = () async => f.runtimeTransport = 'replacement-transport';
        final result = await f.composition.replay(_authority());
        expect(
          result.disposition,
          ProtectedGroupReplayDisposition.prerequisiteWaiting,
        );
        expect(f.decrypts, 0);
      },
    );
    test(
      'strict content for actual transport reaches authenticated history gate',
      () async {
        final f = _Fixture();
        final result = await f.composition.replay(
          await f.content('receiver-transport'),
        );
        expect(
          result.disposition,
          ProtectedGroupReplayDisposition.prerequisiteWaiting,
        );
        expect(
          result.reasonCode,
          'authenticated_authority_version_unavailable',
          reason:
              'Empty test history cannot authorize projection, but correct transport must pass recipient entitlement.',
        );
      },
    );
    for (final target in [
      'foreign-transport',
      'sibling-transport',
      'receiver-account',
    ]) {
      test(
        'strict content recipient $target cannot replace runtime identity',
        () async {
          final f = _Fixture();
          final result = await f.composition.replay(await f.content(target));
          expect(
            result.disposition,
            ProtectedGroupReplayDisposition.unverifiedRejected,
          );
          expect(result.reasonCode, 'recipient_not_entitled');
        },
      );
    }
    test(
      'content history await rechecks original current node before dispatch',
      () async {
        final f = _Fixture();
        final wire = await f.content('receiver-transport');
        f.database.onRead = () => f.runtimeTransport = 'replacement-transport';
        final result = await f.composition.replay(wire);
        expect(
          result.disposition,
          ProtectedGroupReplayDisposition.prerequisiteWaiting,
        );
        expect(result.reasonCode, 'local_transport_authority_unavailable');
      },
    );
    test('foreground and recovery roots inject independent active P2P state', () {
      for (final path in [
        'lib/app/bootstrap/production_application_bootstrap.dart',
        'lib/app/bootstrap/production_canonical_inbox_projection_composition.dart',
      ]) {
        final source = File(path).readAsStringSync();
        final start = source.indexOf(
          'ProductionCanonicalProtectedGroupReplayComposition(',
        );
        expect(start, greaterThanOrEqualTo(0));
        expect(
          source.substring(
            start,
            source.indexOf('retryPendingKeyRepairs:', start),
          ),
          contains(
            'readCurrentTransportPeerId: () => p2pService.currentState.peerId,',
          ),
        );
      }
    });
  });
}

ChatMessage _authority({String to = 'receiver-transport'}) => ChatMessage(
  from: 'sender-transport',
  to: to,
  content: ProtectedGroupEnvelope(
    type: protectedGroupAuthorityEnvelopeType,
    id: 'routing-test-authority',
    senderPeerId: 'sender-transport',
    recipientPeerId: to,
    kem: 'test-kem',
    ciphertext: 'test-ciphertext',
    nonce: 'test-nonce',
  ).toJson(),
  timestamp: '2026-09-18T00:00:00Z',
  isIncoming: true,
);

LinkedInstallationAuthoritySnapshot _linked({
  String transport = 'receiver-transport',
  String account = 'receiver-account',
  String publicKey = 'account-public',
}) => LinkedInstallationAuthoritySnapshot(
  disposition: LinkedInstallationDisposition.active,
  credential: LinkedTransportCredential(
    state: LinkedTransportCredentialState.active,
    accountPeerId: account,
    accountPublicKey: publicKey,
    deviceId: 'receiver-device',
    transportPeerId: transport,
    transportPublicKey: 'device-public',
    transportPrivateKey: 'device-private',
    createdAt: '2026-09-18T00:00:00Z',
    activatedAt: '2026-09-18T00:00:01Z',
  ),
  failClosedReason: null,
);

class _Fixture {
  _Fixture({
    String account = 'receiver-account',
    LinkedInstallationAuthoritySnapshot? installation,
  }) {
    identity = IdentityModel(
      peerId: account,
      publicKey: 'account-public',
      privateKey: 'account-private',
      mnemonic12: 'test-only',
      mlKemPublicKey: 'receiver-kem',
      mlKemSecretKey: 'receiver-secret',
      createdAt: '2026-09-18T00:00:00Z',
      updatedAt: '2026-09-18T00:00:00Z',
    );
    this.installation =
        installation ??
        const LinkedInstallationAuthoritySnapshot(
          disposition: LinkedInstallationDisposition.primary,
          credential: null,
          failClosedReason: null,
        );
  }
  final database = _EmptyHistoryDatabase();
  final repository = _UnusedRepository();
  final bridge = FakeBridge(
    initialResponses: {
      'message.decrypt': {'ok': false},
      'group.encrypt': {
        'ok': true,
        'ciphertext': 'ciphertext',
        'nonce': 'nonce',
      },
    },
  );
  late IdentityModel identity;
  late LinkedInstallationAuthoritySnapshot installation;
  String? runtimeTransport = 'receiver-transport';
  Future<void> Function()? onIdentity;
  int get decrypts =>
      bridge.commandLog.where((c) => c == 'message.decrypt').length;
  late final composition = ProductionCanonicalProtectedGroupReplayComposition(
    database: database,
    bridge: bridge,
    groupRepository: repository,
    groupMessageListener: _UnusedMessages(),
    groupKeyUpdateListener: _UnusedKeys(),
    authoritySupport: ProductionCanonicalProtectedGroupAuthoritySupport(
      database: database,
      bridge: bridge,
      groupRepository: repository,
    ),
    loadIdentity: () async {
      await onIdentity?.call();
      return identity;
    },
    loadLinkedAuthority: (_) async => installation,
    readCurrentTransportPeerId: () => runtimeTransport,
    applySystemAuthorityReplay: (_, _, _) async =>
        throw StateError('No application before verified history'),
    retryPendingKeyRepairs: (_) async => throw StateError('No repair expected'),
  );
  Future<ChatMessage> content(String target) async {
    final wire = await buildGroupOfflineReplayEnvelope(
      bridge: bridge,
      groupRepo: repository,
      groupId: 'group-id',
      payloadType: groupOfflineReplayPayloadTypeMessage,
      plaintext: jsonEncode(<String, Object?>{}),
      senderPeerId: 'sender-account',
      senderPublicKey: 'sender-public',
      senderPrivateKey: 'sender-private',
      senderDeviceId: 'sender-device',
      senderTransportPeerId: 'sender-transport',
      recipientPeerIds: [target],
      messageId: 'message-id',
      contentEventId: 'message-id',
      keyInfo: GroupKeyInfo(
        groupId: 'group-id',
        keyGeneration: 1,
        encryptedKey: 'key',
        createdAt: DateTime.utc(2026, 9, 18),
      ),
      contentAuthorityVersion: GroupContentAuthorityVersion(
        eventAt: DateTime.utc(2026, 9, 18),
        eventId: 'authority-id',
        keyEpoch: 1,
      ),
    );
    return ChatMessage(
      from: 'sender-transport',
      to: target,
      content: wire,
      timestamp: '2026-09-18T00:00:01Z',
      isIncoming: true,
    );
  }
}

class _EmptyHistoryDatabase implements Database {
  void Function()? onRead;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #query || invocation.memberName == #rawQuery) {
      onRead?.call();
      return Future<List<Map<String, Object?>>>.value(<Map<String, Object?>>[]);
    }
    throw StateError('Unexpected database mutation');
  }
}

class _UnusedRepository implements GroupRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected repository access');
}

class _UnusedMessages implements GroupMessageListener {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected message application');
}

class _UnusedKeys implements GroupKeyUpdateListener {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected key application');
}
