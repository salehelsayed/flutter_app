import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository_impl.dart';

void main() {
  // In-memory storage for faked DB helper closures
  late Map<String, Map<String, Object?>> store;

  // Call tracking
  late List<String> upsertCalls;
  late List<(String, String)> updateStatusCalls;
  late List<String> deleteCalls;

  late ContactRequestRepositoryImpl repo;

  Map<String, Object?> makeRow({
    String peerId = 'peer-req-001',
    String publicKey = 'pk-base64',
    String rendezvous = '/dns4/relay',
    String username = 'Bob',
    String signature = 'sig-base64',
    String receivedAt = '2026-01-01T00:00:00.000Z',
    String status = 'pending',
    String? mlKemPublicKey,
  }) {
    return {
      'peer_id': peerId,
      'public_key': publicKey,
      'rendezvous': rendezvous,
      'username': username,
      'signature': signature,
      'received_at': receivedAt,
      'status': status,
      'ml_kem_public_key': mlKemPublicKey,
    };
  }

  setUp(() {
    store = {};
    upsertCalls = [];
    updateStatusCalls = [];
    deleteCalls = [];

    repo = ContactRequestRepositoryImpl(
      dbLoadPendingRequests: () async {
        return store.values
            .where((r) => r['status'] == 'pending')
            .toList()
          ..sort((a, b) =>
              (b['received_at'] as String).compareTo(a['received_at'] as String));
      },
      dbLoadRequest: (peerId) async {
        return store[peerId];
      },
      dbUpsertRequest: (row) async {
        final peerId = row['peer_id'] as String;
        upsertCalls.add(peerId);
        store[peerId] = row;
      },
      dbUpdateRequestStatus: (peerId, status) async {
        updateStatusCalls.add((peerId, status));
        if (store.containsKey(peerId)) {
          store[peerId] = {...store[peerId]!, 'status': status};
        }
      },
      dbDeleteRequest: (peerId) async {
        deleteCalls.add(peerId);
        store.remove(peerId);
      },
      dbRequestExists: (peerId) async {
        return store.containsKey(peerId);
      },
    );
  });

  group('addRequest', () {
    test('calls dbUpsertRequest with toMap output', () async {
      final request = ContactRequestModel(
        peerId: 'peer-add-001',
        publicKey: 'pk',
        rendezvous: '/dns4/relay',
        username: 'Alice',
        signature: 'sig',
        receivedAt: '2026-01-01T00:00:00.000Z',
        mlKemPublicKey: 'mlkem-pk',
      );

      await repo.addRequest(request);

      expect(upsertCalls, ['peer-add-001']);
      expect(store['peer-add-001']!['username'], 'Alice');
      expect(store['peer-add-001']!['ml_kem_public_key'], 'mlkem-pk');
      expect(store['peer-add-001']!['status'], 'pending');
    });
  });

  group('getRequest', () {
    test('returns null for non-existent peerId', () async {
      final result = await repo.getRequest('nonexistent');
      expect(result, isNull);
    });

    test('returns ContactRequestModel from DB row', () async {
      store['peer-001'] = makeRow(peerId: 'peer-001', username: 'Bob');

      final result = await repo.getRequest('peer-001');

      expect(result, isNotNull);
      expect(result!.peerId, 'peer-001');
      expect(result.username, 'Bob');
      expect(result.status, ContactRequestStatus.pending);
    });

    test('handles all status values', () async {
      store['peer-accepted'] = makeRow(peerId: 'peer-accepted', status: 'accepted');
      store['peer-declined'] = makeRow(peerId: 'peer-declined', status: 'declined');

      final accepted = await repo.getRequest('peer-accepted');
      final declined = await repo.getRequest('peer-declined');

      expect(accepted!.status, ContactRequestStatus.accepted);
      expect(declined!.status, ContactRequestStatus.declined);
    });
  });

  group('getPendingRequests', () {
    test('returns empty list when no requests', () async {
      final result = await repo.getPendingRequests();
      expect(result, isEmpty);
    });

    test('returns only pending requests', () async {
      store['peer-a'] = makeRow(peerId: 'peer-a', status: 'pending');
      store['peer-b'] = makeRow(peerId: 'peer-b', status: 'accepted');
      store['peer-c'] = makeRow(peerId: 'peer-c', status: 'pending');

      final result = await repo.getPendingRequests();

      expect(result.length, 2);
      expect(result.every((r) => r.status == ContactRequestStatus.pending), isTrue);
    });
  });

  group('updateStatus', () {
    test('converts accepted enum to string', () async {
      store['peer-001'] = makeRow(peerId: 'peer-001');

      await repo.updateStatus('peer-001', ContactRequestStatus.accepted);

      expect(updateStatusCalls, [('peer-001', 'accepted')]);
    });

    test('converts declined enum to string', () async {
      await repo.updateStatus('peer-x', ContactRequestStatus.declined);
      expect(updateStatusCalls, [('peer-x', 'declined')]);
    });

    test('converts pending enum to string', () async {
      await repo.updateStatus('peer-y', ContactRequestStatus.pending);
      expect(updateStatusCalls, [('peer-y', 'pending')]);
    });
  });

  group('deleteRequest', () {
    test('calls dbDeleteRequest with peerId', () async {
      store['peer-del'] = makeRow(peerId: 'peer-del');

      await repo.deleteRequest('peer-del');

      expect(deleteCalls, ['peer-del']);
      expect(store.containsKey('peer-del'), isFalse);
    });
  });

  group('requestExists', () {
    test('returns false for non-existent', () async {
      expect(await repo.requestExists('none'), isFalse);
    });

    test('returns true for existing', () async {
      store['peer-exists'] = makeRow(peerId: 'peer-exists');
      expect(await repo.requestExists('peer-exists'), isTrue);
    });
  });
}
