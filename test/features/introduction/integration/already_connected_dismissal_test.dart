import 'dart:io';

import 'package:flutter_app/core/database/helpers/introduction_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/introductions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_introduction_responses_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/019_introductions_table.dart';
import 'package:flutter_app/core/database/migrations/022_introduction_keys.dart';
import 'package:flutter_app/core/database/migrations/023_introduction_recipient_keys.dart';
import 'package:flutter_app/core/database/migrations/025_introduction_already_connected_status.dart';
import 'package:flutter_app/core/database/migrations/046_pending_introduction_responses.dart';
import 'package:flutter_app/core/database/migrations/047_introduction_outbox.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/introduction/application/handle_incoming_introduction_use_case.dart';
import 'package:flutter_app/features/introduction/data/repositories/introduction_repository_impl.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';

void main() {
  late Directory directory;
  late Database db;
  late FakeSecureKeyStore store;
  late List<String> retired;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database> open() => openDatabase(
    '${directory.path}/intros.db',
    version: 1,
    onCreate: (database, _) async {
      await runIntroductionsTableMigration(database);
      await runIntroductionKeysMigration(database);
      await runIntroductionRecipientKeysMigration(database);
      await runIntroductionAlreadyConnectedMigration(database);
      await runPendingIntroductionResponsesMigration(database);
      await runIntroductionOutboxMigration(database);
    },
  );

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('intro-dismissal-');
    db = await open();
    store = FakeSecureKeyStore();
    retired = [];
  });

  tearDown(() async {
    if (db.isOpen) await db.close();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  IntroductionModel intro(
    String id, {
    IntroductionOverallStatus status =
        IntroductionOverallStatus.alreadyConnected,
    String recipient = 'peer-B',
    String introduced = 'peer-C',
  }) => IntroductionModel(
    id: id,
    introducerId: 'peer-A',
    recipientId: recipient,
    introducedId: introduced,
    status: status,
    createdAt: '2026-11-01T16:00:00.000Z',
  );

  IntroductionRepositoryImpl repository({
    SecureKeyStore? keyStore,
    Future<void> Function(String)? retire,
  }) => _repository(
    db,
    keyStore ?? store,
    onRetired: retire ?? (id) async => retired.add(id),
  );

  test(
    'IN-DISMISS SQL reopen and same-ID redelivery stay hidden locally',
    () async {
      final repo = repository();
      await repo.saveIntroduction(intro('same-offer'));

      expect(
        await repo.dismissAlreadyConnectedIntroductions(
          introductionIds: ['same-offer'],
          ownPeerId: 'peer-B',
        ),
        isTrue,
      );
      expect(await repo.getPendingIntroductionsForUser('peer-B'), isEmpty);
      expect(retired, ['same-offer']);
      expect(
        (await repo.getIntroduction('same-offer'))!.status,
        IntroductionOverallStatus.alreadyConnected,
      );
      expect(
        await repo.loadOutboxDeliveriesForIntroduction('same-offer'),
        isEmpty,
      );

      await db.close();
      db = await open();
      final restarted = repository();
      expect(await restarted.getPendingIntroductionsForUser('peer-B'), isEmpty);
      final (result, replayed) = await handleIncomingIntroduction(
        payload: IntroductionPayload(
          action: 'send',
          introductionId: 'same-offer',
          introducerId: 'peer-A',
          recipientId: 'peer-B',
          introducedId: 'peer-C',
          timestamp: '2026-11-01T16:00:00.000Z',
        ),
        introRepo: restarted,
        contactRepo: InMemoryContactRepository(),
        ownPeerId: 'peer-B',
        transportSenderPeerId: 'peer-A',
      );
      expect(result, HandleIntroductionResult.alreadyExists);
      expect(replayed!.status, IntroductionOverallStatus.alreadyConnected);
      expect(await restarted.getPendingIntroductionsForUser('peer-B'), isEmpty);
      expect(
        await restarted.loadOutboxDeliveriesForIntroduction('same-offer'),
        isEmpty,
      );
      expect(
        await restarted.getPendingIntroductionsForUser('peer-C'),
        hasLength(1),
      );
    },
  );

  test(
    'IN-DISMISS folded predecessors persist before exact retirement',
    () async {
      final repo = repository(
        retire: (id) async {
          expect(await store.readAll(), hasLength(2));
          retired.add(id);
        },
      );
      await repo.saveIntroduction(intro('older'));
      await repo.saveIntroduction(intro('newer'));
      await repo.saveIntroduction(intro('unrelated', introduced: 'peer-D'));
      await repo.saveIntroduction(
        intro('pending', status: IntroductionOverallStatus.pending),
      );

      expect(
        await repo.dismissAlreadyConnectedIntroductions(
          introductionIds: ['older', 'newer', 'older', 'pending'],
          ownPeerId: 'peer-B',
        ),
        isTrue,
      );
      expect(retired.toSet(), {'older', 'newer'});
      expect(retired, hasLength(2));
      expect(
        (await repo.getPendingIntroductionsForUser(
          'peer-B',
        )).map((row) => row.id).toSet(),
        {'unrelated', 'pending'},
      );
      expect(await repo.getIntroduction('older'), isNotNull);
      expect(await repo.getIntroduction('newer'), isNotNull);
      expect(await repo.loadOutboxDeliveriesForIntroduction('older'), isEmpty);
    },
  );

  test(
    'IN-DISMISS account and introduction key boundaries do not alias',
    () async {
      final repo = repository();
      await repo.saveIntroduction(intro('b', recipient: 'account:a'));
      await repo.saveIntroduction(intro('a:b', recipient: 'account'));
      expect(
        await repo.dismissAlreadyConnectedIntroductions(
          introductionIds: ['b'],
          ownPeerId: 'account:a',
        ),
        isTrue,
      );
      expect(await repo.getPendingIntroductionsForUser('account:a'), isEmpty);
      expect(
        (await repo.getPendingIntroductionsForUser('account')).single.id,
        'a:b',
      );
    },
  );

  test('IN-DISMISS introducer and other states cannot be dismissed', () async {
    final repo = repository();
    for (final status in IntroductionOverallStatus.values) {
      await repo.saveIntroduction(intro(status.name, status: status));
    }
    expect(
      await repo.dismissAlreadyConnectedIntroductions(
        introductionIds: IntroductionOverallStatus.values
            .map((status) => status.name)
            .toList(),
        ownPeerId: 'peer-A',
      ),
      isFalse,
    );
    expect(
      await repo.dismissAlreadyConnectedIntroductions(
        introductionIds: IntroductionOverallStatus.values
            .where(
              (status) => status != IntroductionOverallStatus.alreadyConnected,
            )
            .map((status) => status.name)
            .toList(),
        ownPeerId: 'peer-B',
      ),
      isFalse,
    );
    expect(await store.readAll(), isEmpty);
    expect(retired, isEmpty);
  });

  test(
    'IN-DISMISS failed persistence keeps the offer and does not retire',
    () async {
      final failing = _FailingStore(1);
      final repo = repository(keyStore: failing);
      await repo.saveIntroduction(intro('keep-on-failure'));

      await expectLater(
        repo.dismissAlreadyConnectedIntroductions(
          introductionIds: ['keep-on-failure'],
          ownPeerId: 'peer-B',
        ),
        throwsStateError,
      );
      expect(await repo.getPendingIntroductionsForUser('peer-B'), hasLength(1));
      expect(retired, isEmpty);
    },
  );

  test(
    'IN-DISMISS partial folded write failure never retires the card',
    () async {
      final failing = _FailingStore(2);
      final repo = repository(keyStore: failing);
      await repo.saveIntroduction(intro('first'));
      await repo.saveIntroduction(intro('second'));

      await expectLater(
        repo.dismissAlreadyConnectedIntroductions(
          introductionIds: ['first', 'second'],
          ownPeerId: 'peer-B',
        ),
        throwsStateError,
      );
      expect(await repo.getPendingIntroductionsForUser('peer-B'), isNotEmpty);
      expect(retired, isEmpty);
      expect(await repo.getIntroduction('first'), isNotNull);
      expect(await repo.getIntroduction('second'), isNotNull);
    },
  );

  test('IN-DISMISS partial folded retry retires all original IDs', () async {
    final failing = _FailingStore(2);
    final repo = repository(keyStore: failing);
    await repo.saveIntroduction(intro('first'));
    await repo.saveIntroduction(intro('second'));

    await expectLater(
      repo.dismissAlreadyConnectedIntroductions(
        introductionIds: ['first', 'second'],
        ownPeerId: 'peer-B',
      ),
      throwsStateError,
    );

    final restarted = repository(keyStore: failing);
    final visibleIds = (await restarted.getPendingIntroductionsForUser(
      'peer-B',
    )).map((row) => row.id).toList();
    expect(visibleIds, ['second']);
    expect(
      await restarted.dismissAlreadyConnectedIntroductions(
        introductionIds: visibleIds,
        ownPeerId: 'peer-B',
      ),
      isTrue,
    );
    expect(await restarted.getPendingIntroductionsForUser('peer-B'), isEmpty);
    expect(retired.toSet(), {'first', 'second'});
    expect(retired, hasLength(2));
  });

  test('IN-DISMISS retirement error does not undo stored dismissal', () async {
    final repo = repository(
      retire: (_) async => throw StateError('native center unavailable'),
    );
    await repo.saveIntroduction(intro('retirement-error'));

    expect(
      await repo.dismissAlreadyConnectedIntroductions(
        introductionIds: ['retirement-error'],
        ownPeerId: 'peer-B',
      ),
      isTrue,
    );
    expect(
      await repository().getPendingIntroductionsForUser('peer-B'),
      isEmpty,
    );
  });

  test('IN-DISMISS concurrent independent IDs retain both markers', () async {
    final repo = repository();
    await repo.saveIntroduction(intro('first'));
    await repo.saveIntroduction(intro('second', introduced: 'peer-D'));
    final results = await Future.wait([
      repo.dismissAlreadyConnectedIntroductions(
        introductionIds: ['first'],
        ownPeerId: 'peer-B',
      ),
      repo.dismissAlreadyConnectedIntroductions(
        introductionIds: ['second'],
        ownPeerId: 'peer-B',
      ),
    ]);
    expect(results, [true, true]);
    expect(
      await repository().getPendingIntroductionsForUser('peer-B'),
      isEmpty,
    );
    expect(await store.readAll(), hasLength(2));
  });
}

class _FailingStore extends FakeSecureKeyStore {
  _FailingStore(this.failAt);
  final int failAt;
  int writes = 0;

  @override
  Future<void> write(String key, String value) async {
    if (++writes == failAt) throw StateError('local storage unavailable');
    await super.write(key, value);
  }
}

IntroductionRepositoryImpl _repository(
  Database db,
  SecureKeyStore store, {
  required Future<void> Function(String) onRetired,
}) => IntroductionRepositoryImpl(
  secureKeyStore: store,
  dbInsertIntroduction: (row) => dbInsertIntroduction(db, row),
  dbLoadIntroduction: (id) => dbLoadIntroduction(db, id),
  dbDeleteIntroduction: (id) => dbDeleteIntroduction(db, id),
  dbLoadIntroductionsByRecipient: (id) =>
      dbLoadIntroductionsByRecipient(db, id),
  dbLoadIntroductionsByIntroduced: (id) =>
      dbLoadIntroductionsByIntroduced(db, id),
  dbLoadIntroductionsByIntroducer: (id) =>
      dbLoadIntroductionsByIntroducer(db, id),
  dbLoadIntroductionsForRecipientAndIntroducer: (recipient, introducer) =>
      dbLoadIntroductionsForRecipientAndIntroducer(db, recipient, introducer),
  dbUpdateRecipientStatus: (id, status, respondedAt) =>
      dbUpdateRecipientStatus(db, id, status, respondedAt),
  dbUpdateIntroducedStatus: (id, status, respondedAt) =>
      dbUpdateIntroducedStatus(db, id, status, respondedAt),
  dbUpdateOverallStatus: (id, status) => dbUpdateOverallStatus(db, id, status),
  dbLoadPendingIntroductionsForUser: (peerId) =>
      dbLoadPendingIntroductionsForUser(db, peerId),
  dbCountPendingIntroductions: (peerId) =>
      dbCountPendingIntroductions(db, peerId),
  dbUpsertPendingIntroductionResponse: (row) =>
      dbUpsertPendingIntroductionResponse(db, row),
  dbLoadPendingIntroductionResponses: (id) =>
      dbLoadPendingIntroductionResponses(db, id),
  dbDeletePendingIntroductionResponse: (key) =>
      dbDeletePendingIntroductionResponse(db, key),
  dbUpsertIntroductionOutboxDelivery: (row) =>
      dbUpsertIntroductionOutboxDelivery(db, row),
  dbSaveIntroductionWithOutboxDeliveries: (row, deliveries) =>
      dbSaveIntroductionWithOutboxDeliveries(db, row, deliveries),
  dbReplaceIntroductionWithPendingResponseMigration:
      ({
        required introductionRow,
        required deliveryRows,
        required replacedIntroductionIds,
      }) => dbReplaceIntroductionWithPendingResponseMigration(
        db,
        introductionRow: introductionRow,
        deliveryRows: deliveryRows,
        replacedIntroductionIds: replacedIntroductionIds,
      ),
  dbSaveIntroductionResponseWithOutboxDeliveries:
      ({
        required introductionId,
        required isRecipient,
        required responseStatus,
        required respondedAt,
        required overallStatus,
        required deliveryRows,
      }) => dbSaveIntroductionResponseWithOutboxDeliveries(
        db,
        introductionId: introductionId,
        isRecipient: isRecipient,
        responseStatus: responseStatus,
        respondedAt: respondedAt,
        overallStatus: overallStatus,
        deliveryRows: deliveryRows,
      ),
  dbLoadIntroductionOutboxDeliveriesForIntroduction: (id) =>
      dbLoadIntroductionOutboxDeliveriesForIntroduction(db, id),
  dbLoadRetryableIntroductionOutboxDeliveries:
      ({required olderThan, limit = 100}) =>
          dbLoadRetryableIntroductionOutboxDeliveries(
            db,
            olderThan: olderThan,
            limit: limit,
          ),
  dbDeleteIntroductionOutboxDelivery: (id) =>
      dbDeleteIntroductionOutboxDelivery(db, id),
  dbDeleteIntroductionOutboxDeliveriesForIntroduction: (id) =>
      dbDeleteIntroductionOutboxDeliveriesForIntroduction(db, id),
  onResponseSaved: onRetired,
);
