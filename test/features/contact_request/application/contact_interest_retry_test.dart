import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_repair_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../support/interest_retry_fixture.dart';

class _UnavailableStore extends FakeSecureKeyStore {
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('journal unavailable');
}

void main() {
  late InterestRetryFixture f;
  setUp(() => f = InterestRetryFixture());
  tearDown(() => f.dispose());

  test(
    'E3 automatic recovery alone leaves a stopped contact stopped',
    () async {
      expect(await f.retry(), 0);
      expect(f.transport.storeInInboxCallCount, 0);
    },
  );

  test('E3 interest starts one fresh signed encrypted silent cycle', () async {
    expect(await f.retry(interest: interestPeer), 1);
    expect(f.wire['version'], '2');
    expect(f.wire['intent'], 'key_exchange_retry');
    expect(f.wire['msgId'], isNotEmpty);
    final entry = await f.entry();
    expect(entry['interestStartedAtMs'], f.now.millisecondsSinceEpoch);
    expect(
      entry['expiresAtMs'],
      f.now.add(const Duration(days: 7)).millisecondsSinceEpoch,
    );
    final signs = f.bridge.sentMessages
        .map(jsonDecode)
        .where((m) => m['cmd'] == 'payload.sign')
        .toList();
    expect(signs, hasLength(1));
    expect(
      (entry['envelope'] as Map)['signedAtMs'],
      f.now.millisecondsSinceEpoch,
    );
    expect(f.wire['ts'], f.now.toIso8601String());
  });

  test('E3 repeated opens including due time cannot restart or send', () async {
    await f.retry(interest: interestPeer);
    final original = await f.store.read(interestJournalKey);
    f.now = f.now.add(const Duration(hours: 2));
    expect(await f.retry(interest: interestPeer), 0);
    expect(await f.store.read(interestJournalKey), original);
    expect(f.transport.storeInInboxCallCount, 1);
  });

  test(
    'E3 next cycle after seven days has new id and signed timestamp',
    () async {
      await f.retry(interest: interestPeer);
      final first = f.wire;
      f.now = f.now.add(const Duration(days: 7));
      expect(await f.retry(), 0);
      expect(await f.retry(interest: interestPeer), 1);
      expect(f.wire['msgId'], isNot(first['msgId']));
      expect(f.wire['ts'], isNot(first['ts']));
      expect((await f.entry())['attempts'], 1);
    },
  );

  test(
    'E3 automatic retries reuse new cycle bytes with original backoff',
    () async {
      await f.retry(interest: interestPeer);
      final first = f.transport.lastStoreInInboxMessage;
      for (final hours in [1, 6, 24, 24]) {
        f.now = f.now.add(Duration(hours: hours) - const Duration(seconds: 1));
        expect(await f.retry(), 0);
        f.now = f.now.add(const Duration(seconds: 1));
        expect(await f.retry(), 1);
        expect(f.transport.lastStoreInInboxMessage, first);
      }
    },
  );

  test('E3 concurrent opens admit one durable cycle', () async {
    expect(
      await Future.wait([
        f.retry(interest: interestPeer),
        f.retry(interest: interestPeer),
      ]),
      [1, 0],
    );
    expect(f.transport.storeInInboxCallCount, 1);
  });

  test(
    'E3 interest touches only its target, not another due contact',
    () async {
      final other = ContactModel(
        peerId: 'other',
        publicKey: 'other-key',
        rendezvous: '/relay',
        username: 'Other',
        signature: 'signature',
        scannedAt: f.now.toIso8601String(),
      );
      f.contacts.seed([f.contact, other]);
      expect(await f.retry(interest: interestPeer), 1);
      expect(f.transport.storeInInboxCallCount, 1);
      final journal =
          jsonDecode((await f.store.read(interestJournalKey))!) as Map;
      expect((journal['entries'] as List).map((e) => e['peerId']), [
        interestPeer,
      ]);
    },
  );

  for (final state in ['fresh', 'keyed', 'blocked', 'archived', 'missing']) {
    test('E3 opening $state contact does not change retry custody', () async {
      f.contacts.seed(switch (state) {
        'missing' => <ContactModel>[],
        'fresh' => [
          ContactModel(
            peerId: interestPeer,
            publicKey: 'recipient-key',
            rendezvous: '/relay',
            username: 'Alice',
            signature: 'sig',
            scannedAt: f.now.toIso8601String(),
          ),
        ],
        'keyed' => [f.contact.copyWith(mlKemPublicKey: 'received-key')],
        'blocked' => [f.contact.copyWith(isBlocked: true)],
        _ => [f.contact.copyWith(isArchived: true)],
      });
      expect(await f.retry(interest: interestPeer), 0);
      expect(f.transport.storeInInboxCallCount, 0);
      expect(await f.store.read(interestJournalKey), isNull);
    });
  }

  for (final consent in [
    ContactRelationshipState.declined,
    ContactRelationshipState.withdrawn,
  ]) {
    test('E3 interest cannot override $consent consent', () async {
      f.consent = consent;
      expect(await f.retry(interest: interestPeer), 0);
      expect(f.transport.storeInInboxCallCount, 0);
    });
  }

  test('E3 unavailable journal cannot authorize a new cycle', () async {
    f.store = _UnavailableStore();
    expect(await f.retry(interest: interestPeer), 0);
    expect(f.transport.storeInInboxCallCount, 0);
  });

  test(
    'E3 read-only projection clears when interest starts without global hook',
    () async {
      var globalPreparation = 0;
      final retrier = f.retrier(beforeRetry: () async => globalPreparation++);
      try {
        await withClock(Clock(() => f.now), () async {
          await retrier.refreshRetryStatus();
          expect(retrier.stoppedPeerIds.value, {interestPeer});
          expect(f.transport.storeInInboxCallCount, 0);
          expect(await retrier.retryOnInterest(interestPeer), 1);
          expect(retrier.stoppedPeerIds.value, isEmpty);
          expect(globalPreparation, 0);
        });
      } finally {
        retrier.dispose();
      }
    },
  );
}
