import 'package:flutter_app/core/debug/ios_sender_projection_fixture_contract.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';

Never _fail(String message) => throw StateError(message);

void _expect(bool condition, String message) {
  if (!condition) _fail(message);
}

Future<void> main() async {
  final now = DateTime.utc(2030, 3, 17, 12);
  final seed = _request(action: iosSenderProjectionSeedAction, now: now);
  final cleanup = _request(
    action: iosSenderProjectionCleanupAction,
    now: now.add(const Duration(seconds: 1)),
  );
  _expect(seed != null && cleanup != null, 'valid command was rejected');
  _expect(
    _request(
          action: iosSenderProjectionSeedAction,
          now: now,
          username: 'x' * 31,
        ) ==
        null,
    'sender username above the app sanitizer bound was accepted',
  );
  _expect(
    seed!.fixtureDigest == cleanup!.fixtureDigest,
    'seed and cleanup did not bind the same generation',
  );

  final backing = _Backing();
  backing.contacts['peer-unrelated'] = _realContact('peer-unrelated');
  backing.projections['peer-unrelated'] = <String, Object?>{
    'username': 'Unrelated',
    'blocked': false,
    'archived': false,
  };
  final coordinator = IosSenderProjectionFixtureCoordinator(backing.store);

  final seeded = await coordinator.execute(seed);
  _expect(
    seeded.status == 'seeded' && seeded.resultCode == 'ok',
    'fresh exact seed failed',
  );
  _expect(
    backing.contacts[seed.senderPeerId]?.isBlocked == false &&
        backing.contacts[seed.senderPeerId]?.isArchived == false,
    'database seed was not eligible',
  );
  _expect(
    backing.projections[seed.senderPeerId]?[iosSenderProjectionDigestField] ==
        seed.fixtureDigest,
    'projection generation tag is absent',
  );
  final repeated = await coordinator.execute(seed);
  _expect(
    repeated.status == 'seeded' && repeated.resultCode == 'idempotent',
    'exact seed retry was not idempotent',
  );

  final cleaned = await coordinator.execute(cleanup);
  _expect(
    cleaned.status == 'cleaned' && cleaned.resultCode == 'ok',
    'exact cleanup failed',
  );
  _expect(
    !backing.contacts.containsKey(seed.senderPeerId) &&
        !backing.projections.containsKey(seed.senderPeerId),
    'exact fixture survived cleanup',
  );
  _expect(
    backing.contacts.containsKey('peer-unrelated') &&
        backing.projections.containsKey('peer-unrelated'),
    'cleanup changed unrelated state',
  );
  final repeatedCleanup = await coordinator.execute(cleanup);
  _expect(
    repeatedCleanup.status == 'cleaned' &&
        repeatedCleanup.resultCode == 'idempotent',
    'absent cleanup was not idempotent',
  );

  final collision = _Backing();
  collision.contacts[seed.senderPeerId] = _realContact(seed.senderPeerId);
  final collisionResult = await IosSenderProjectionFixtureCoordinator(
    collision.store,
  ).execute(seed);
  _expect(
    collisionResult.status == 'rejected' &&
        collisionResult.resultCode == 'sender_state_collision',
    'pre-existing sender collision was not rejected',
  );
  _expect(
    collision.contacts[seed.senderPeerId]?.username == 'Real contact',
    'collision overwrote a real contact',
  );

  final changed = _Backing();
  final changedCoordinator = IosSenderProjectionFixtureCoordinator(
    changed.store,
  );
  await changedCoordinator.execute(seed);
  changed.contacts[seed.senderPeerId] = _realContact(seed.senderPeerId);
  changed.projections[seed.senderPeerId] = <String, Object?>{
    'username': 'Real contact',
    'blocked': false,
    'archived': false,
  };
  final mismatch = await changedCoordinator.execute(cleanup);
  _expect(
    mismatch.status == 'rejected' &&
        mismatch.resultCode == 'cleanup_state_mismatch',
    'changed state was not preserved by fail-closed cleanup',
  );
  _expect(
    changed.contacts[seed.senderPeerId]?.username == 'Real contact' &&
        changed.projections[seed.senderPeerId]?['username'] == 'Real contact',
    'cleanup removed concurrently changed state',
  );

}

IosSenderProjectionRequest? _request({
  required String action,
  required DateTime now,
  String username = 'Encrypted fixture title',
}) => IosSenderProjectionRequest.tryParse(<String, Object?>{
  'schema': iosSenderProjectionRequestSchema,
  'action': action,
  'captureNonce': 'nonce-sender-fixture-1234',
  'receiverDeviceId': '00008110-001A123E0E91801E',
  'bundleId': iosSenderProjectionBundleId,
  'senderPeerId': '12D3KooW${'2' * 44}',
  'senderUsername': username,
  'apnsPayloadSha256': 'a' * 64,
  'createdAt': now.toIso8601String(),
  'expiresAt': now.add(const Duration(minutes: 2)).toIso8601String(),
}, now: now);

ContactModel _realContact(String peerId) => ContactModel(
  peerId: peerId,
  publicKey: 'real-public-key',
  rendezvous: '/dns4/real.example/tcp/443',
  username: 'Real contact',
  signature: 'real-signature',
  scannedAt: '2030-03-17T10:00:00.000Z',
);

final class _Backing {
  final String localPeerId = '12D3KooW${'1' * 44}';
  final Map<String, ContactModel> contacts = <String, ContactModel>{};
  final Map<String, Map<String, Object?>> projections =
      <String, Map<String, Object?>>{};

  late final IosSenderProjectionFixtureStore store =
      IosSenderProjectionFixtureStore(
        loadLocalAccountPeerId: () async => localPeerId,
        loadProjectionAccountPeerId: () async => localPeerId,
        loadContact: (peerId) async => contacts[peerId],
        insertContactIfAbsent: (contact) async {
          if (contacts.containsKey(contact.peerId)) return false;
          contacts[contact.peerId] = contact;
          return true;
        },
        deleteContactIfExact: (expected) async {
          final current = contacts[expected.peerId];
          if (current == null || !_sameMap(current.toMap(), expected.toMap())) {
            return false;
          }
          contacts.remove(expected.peerId);
          return true;
        },
        loadProjectedContact: (peerId) async => projections[peerId],
        insertProjectedContactIfAbsent: (request) async {
          if (projections.containsKey(request.senderPeerId)) return false;
          projections[request.senderPeerId] = <String, Object?>{
            'username': request.senderUsername,
            'blocked': false,
            'archived': false,
            iosSenderProjectionDigestField: request.fixtureDigest,
          };
          return true;
        },
        deleteProjectedContactIfExact: (request) async {
          final expected = <String, Object?>{
            'username': request.senderUsername,
            'blocked': false,
            'archived': false,
            iosSenderProjectionDigestField: request.fixtureDigest,
          };
          final current = projections[request.senderPeerId];
          if (current == null) return true;
          if (!_sameMap(current, expected)) return false;
          projections.remove(request.senderPeerId);
          return true;
        },
      );
}

bool _sameMap(Map<String, Object?> left, Map<String, Object?> right) =>
    left.length == right.length &&
    right.entries.every((entry) => left[entry.key] == entry.value);
