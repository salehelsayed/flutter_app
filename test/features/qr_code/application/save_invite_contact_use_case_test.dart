import 'dart:async';

import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/qr_code/application/confirm_contact_invite_use_case.dart';
import 'package:flutter_app/features/qr_code/application/save_invite_contact_use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show Database;

import '../../contact_request/presentation/support/contact_request_sql_fixture.dart';

const _deadline = Duration(seconds: 3);
const _activePeerId = 'current-local-account';
const _otherPeerId = 'other-local-account';
const _time = '2026-11-24T00:00:00.000Z';
const _contact = ContactModel(
  peerId: 'invite-contact',
  publicKey: 'invitation-public-key',
  rendezvous: '/dns4/fixture/tcp/443',
  username: 'Invite name',
  signature: 'invitation-signature',
  scannedAt: _time,
);

Map<String, Object?> _identityRow(String peerId) => {
  'peer_id': peerId,
  'public_key': 'fixture-local-public-key',
  'username': 'Local account',
  'created_at': _time,
  'updated_at': _time,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Database? database;
  Database getDatabase() => database!;

  setUp(() async {
    final opened = await openContactWidgetDatabase().timeout(_deadline);
    database = opened;
    await dbUpsertIdentityRow(
      opened,
      _identityRow(_activePeerId),
    ).timeout(_deadline);
  });

  tearDown(() async {
    await database?.close().timeout(_deadline);
    database = null;
  });

  Future<InviteContactSave> save({
    ContactModel contact = _contact,
    String ownPeerId = _activePeerId,
    bool Function()? canCommit,
    Future<void> Function()? beforeCreate,
  }) => saveInviteContactIfAbsent(
    database: getDatabase(),
    contact: contact,
    ownPeerId: ownPeerId,
    canCommit: canCommit ?? () => true,
    beforeCreate: beforeCreate,
  ).timeout(_deadline);

  Future<List<Map<String, Object?>>> contactRows() => getDatabase()
      .rawQuery('SELECT rowid, * FROM contacts')
      .timeout(_deadline);

  test(
    'inserts an absent contact once and prepares only the new row',
    () async {
      var preparations = 0;
      Future<void> prepare() async {
        preparations++;
      }

      expect(await save(beforeCreate: prepare), InviteContactSave.created);
      final inserted = await contactRows();
      expect(inserted, hasLength(1));
      expect(ContactModel.fromMap(inserted.single).toMap(), _contact.toMap());

      final second = _contact.copyWith(username: 'Do not replace');
      expect(
        await save(contact: second, beforeCreate: prepare),
        InviteContactSave.existing,
      );
      expect(preparations, 1);
      expect(await contactRows(), inserted);
    },
  );

  test(
    'preserves the existing blocked and archived row and skips preparation',
    () async {
      final existing = _contact.copyWith(
        publicKey: 'stored-trusted-key',
        username: 'Stored name',
        mlKemPublicKey: 'stored-ml-kem-key',
        isBlocked: true,
        blockedAt: _time,
        isArchived: true,
        archivedAt: _time,
        introsBannerDismissed: true,
      );
      await dbUpsertContact(getDatabase(), existing.toMap()).timeout(_deadline);
      final stored = await contactRows();
      var preparations = 0;

      final result = await save(
        beforeCreate: () async {
          preparations++;
        },
      );

      expect(result, InviteContactSave.existing);
      expect(preparations, 0);
      expect(await contactRows(), stored);
    },
  );

  test(
    'requires the active singleton account and a live commit guard',
    () async {
      // A matching row outside the singleton cannot authorize the requested account.
      await getDatabase()
          .insert('identity', {'id': 2, ..._identityRow(_otherPeerId)})
          .timeout(_deadline);
      var preparations = 0;
      Future<void> prepare() async {
        preparations++;
      }

      expect(
        await save(ownPeerId: _otherPeerId, beforeCreate: prepare),
        InviteContactSave.stale,
      );
      expect(
        await save(canCommit: () => false, beforeCreate: prepare),
        InviteContactSave.stale,
      );
      expect(preparations, 0);
      expect(await contactRows(), isEmpty);

      expect(await save(beforeCreate: prepare), InviteContactSave.created);
      expect(preparations, 1);
      expect(await contactRows(), hasLength(1));
    },
  );

  test('retirement while preparation is held leaves no contact', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var live = true;
    final pending = save(
      canCommit: () => live,
      beforeCreate: () async {
        entered.complete();
        await release.future.timeout(_deadline);
      },
    );

    try {
      expect(
        await _reachedPreparation(entered, pending),
        isTrue,
        reason: 'the save did not reach the preparation hook',
      );
      live = false;
    } finally {
      release.complete();
    }

    expect(await pending, InviteContactSave.stale);
    expect(await contactRows(), isEmpty);
  });

  test('concurrent same-peer admissions leave only the winning row', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final alternative = _contact.copyWith(username: 'Second admission');
    final first = save(
      beforeCreate: () async {
        entered.complete();
        await release.future.timeout(_deadline);
      },
    );
    late Future<InviteContactSave> second;
    try {
      expect(
        await _reachedPreparation(entered, first),
        isTrue,
        reason: 'the first save did not reach the preparation hook',
      );
      second = save(contact: alternative);
    } finally {
      release.complete();
    }

    final outcomes = await Future.wait([first, second]).timeout(_deadline);
    expect(
      outcomes,
      unorderedEquals([InviteContactSave.created, InviteContactSave.existing]),
    );
    final winner = outcomes.first == InviteContactSave.created
        ? _contact
        : alternative;
    final rows = await contactRows();
    expect(rows, hasLength(1));
    expect(ContactModel.fromMap(rows.single).toMap(), winner.toMap());
  });
}

Future<bool> _reachedPreparation(
  Completer<void> entered,
  Future<InviteContactSave> pending,
) =>
    Future.any([entered.future.then((_) => true), pending.then((_) => false)])
        .timeout(_deadline);
