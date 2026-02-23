import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';

void main() {
  const testPeerId = '12D3KooWTestPeerIdABCDEF';
  const testPublicKey = 'pubkey-base64';
  const testRendezvous = '/dns4/relay/tcp/443/wss';
  const testUsername = 'Alice';
  const testSignature = 'sig-base64';
  const testReceivedAt = '2026-01-15T12:00:00.000Z';
  const testMlKem = 'mlkem-pub-base64';

  ContactRequestModel makeRequest({
    ContactRequestStatus status = ContactRequestStatus.pending,
    String? mlKemPublicKey,
  }) {
    return ContactRequestModel(
      peerId: testPeerId,
      publicKey: testPublicKey,
      rendezvous: testRendezvous,
      username: testUsername,
      signature: testSignature,
      receivedAt: testReceivedAt,
      status: status,
      mlKemPublicKey: mlKemPublicKey,
    );
  }

  group('ContactRequestModel', () {
    group('fromP2PPayload', () {
      test('maps ns/pk/rv/un/sig/mlkem from payload', () {
        final payload = {
          'ns': testPeerId,
          'pk': testPublicKey,
          'rv': testRendezvous,
          'un': testUsername,
          'sig': testSignature,
          'mlkem': testMlKem,
        };

        final model = ContactRequestModel.fromP2PPayload(payload);

        expect(model.peerId, testPeerId);
        expect(model.publicKey, testPublicKey);
        expect(model.rendezvous, testRendezvous);
        expect(model.username, testUsername);
        expect(model.signature, testSignature);
        expect(model.mlKemPublicKey, testMlKem);
      });

      test('defaults username to Unknown when un is missing', () {
        final payload = {
          'ns': testPeerId,
          'pk': testPublicKey,
          'rv': testRendezvous,
          'sig': testSignature,
        };

        final model = ContactRequestModel.fromP2PPayload(payload);
        expect(model.username, 'Unknown');
      });

      test('status defaults to pending', () {
        final payload = {
          'ns': testPeerId,
          'pk': testPublicKey,
          'rv': testRendezvous,
          'un': testUsername,
          'sig': testSignature,
        };

        final model = ContactRequestModel.fromP2PPayload(payload);
        expect(model.status, ContactRequestStatus.pending);
      });

      test('receivedAt is set to approximately now', () {
        final before = DateTime.now().toUtc();
        final model = ContactRequestModel.fromP2PPayload({
          'ns': testPeerId,
          'pk': testPublicKey,
          'rv': testRendezvous,
          'un': testUsername,
          'sig': testSignature,
        });
        final after = DateTime.now().toUtc();

        final receivedAt = DateTime.parse(model.receivedAt);
        expect(
          receivedAt.isAfter(before.subtract(const Duration(seconds: 1))),
          isTrue,
        );
        expect(
          receivedAt.isBefore(after.add(const Duration(seconds: 1))),
          isTrue,
        );
      });
    });

    group('fromMap / toMap', () {
      test('round-trips correctly', () {
        final original = makeRequest(mlKemPublicKey: testMlKem);
        final map = original.toMap();
        final restored = ContactRequestModel.fromMap(map);

        expect(restored.peerId, original.peerId);
        expect(restored.publicKey, original.publicKey);
        expect(restored.rendezvous, original.rendezvous);
        expect(restored.username, original.username);
        expect(restored.signature, original.signature);
        expect(restored.receivedAt, original.receivedAt);
        expect(restored.status, original.status);
        expect(restored.mlKemPublicKey, original.mlKemPublicKey);
      });

      test('status string conversion for pending', () {
        final model = makeRequest(status: ContactRequestStatus.pending);
        final map = model.toMap();
        expect(map['status'], 'pending');

        final restored = ContactRequestModel.fromMap(map);
        expect(restored.status, ContactRequestStatus.pending);
      });

      test('status string conversion for accepted', () {
        final model = makeRequest(status: ContactRequestStatus.accepted);
        final map = model.toMap();
        expect(map['status'], 'accepted');

        final restored = ContactRequestModel.fromMap(map);
        expect(restored.status, ContactRequestStatus.accepted);
      });

      test('status string conversion for declined', () {
        final model = makeRequest(status: ContactRequestStatus.declined);
        final map = model.toMap();
        expect(map['status'], 'declined');

        final restored = ContactRequestModel.fromMap(map);
        expect(restored.status, ContactRequestStatus.declined);
      });

      test('toMap uses snake_case keys', () {
        final map = makeRequest().toMap();
        expect(map.containsKey('peer_id'), isTrue);
        expect(map.containsKey('public_key'), isTrue);
        expect(map.containsKey('received_at'), isTrue);
        expect(map.containsKey('ml_kem_public_key'), isTrue);
      });
    });

    group('toContactModel', () {
      test('copies peerId, publicKey, rendezvous, username, signature', () {
        final request = makeRequest(mlKemPublicKey: testMlKem);
        final contact = request.toContactModel();

        expect(contact.peerId, request.peerId);
        expect(contact.publicKey, request.publicKey);
        expect(contact.rendezvous, request.rendezvous);
        expect(contact.username, request.username);
        expect(contact.signature, request.signature);
        expect(contact.mlKemPublicKey, request.mlKemPublicKey);
      });

      test('sets scannedAt to approximately now', () {
        final before = DateTime.now().toUtc();
        final contact = makeRequest().toContactModel();
        final after = DateTime.now().toUtc();

        final scannedAt = DateTime.parse(contact.scannedAt);
        expect(
          scannedAt.isAfter(before.subtract(const Duration(seconds: 1))),
          isTrue,
        );
        expect(
          scannedAt.isBefore(after.add(const Duration(seconds: 1))),
          isTrue,
        );
      });
    });

    group('copyWith', () {
      test('updates single field and preserves others', () {
        final original = makeRequest(mlKemPublicKey: testMlKem);
        final updated = original.copyWith(username: 'Bob');

        expect(updated.username, 'Bob');
        expect(updated.peerId, original.peerId);
        expect(updated.publicKey, original.publicKey);
        expect(updated.rendezvous, original.rendezvous);
        expect(updated.signature, original.signature);
        expect(updated.receivedAt, original.receivedAt);
        expect(updated.status, original.status);
        expect(updated.mlKemPublicKey, original.mlKemPublicKey);
      });

      test('updates status', () {
        final original = makeRequest();
        final updated =
            original.copyWith(status: ContactRequestStatus.accepted);
        expect(updated.status, ContactRequestStatus.accepted);
      });
    });

    group('equality', () {
      test('equal by peerId only', () {
        final a = makeRequest();
        final b = makeRequest();
        expect(a, equals(b));
      });

      test('not equal when peerId differs', () {
        final a = makeRequest();
        final b = ContactRequestModel(
          peerId: 'different-peer-id',
          publicKey: testPublicKey,
          rendezvous: testRendezvous,
          username: testUsername,
          signature: testSignature,
          receivedAt: testReceivedAt,
        );
        expect(a, isNot(equals(b)));
      });

      test('equal even if username differs (equality is by peerId only)', () {
        final a = makeRequest();
        final b = a.copyWith(username: 'DifferentName');
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

    group('toString', () {
      test('truncates peerId and includes username and status', () {
        final model = makeRequest();
        final str = model.toString();
        // peerId is truncated to first 10 chars
        expect(str, contains(testPeerId.substring(0, 10)));
        expect(str, contains(testUsername));
        expect(str, contains('pending'));
      });
    });
  });
}
