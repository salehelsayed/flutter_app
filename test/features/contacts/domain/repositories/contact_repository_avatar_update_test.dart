import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../contact_request/support/contact_repair_harness.dart';

const _peerId = 'contact-avatar-narrow-write-peer';
const _contact = ContactModel(
  peerId: _peerId,
  publicKey: 'fixture-account-key',
  rendezvous: '/dns4/fixture/tcp/443',
  username: 'Old name',
  signature: 'fixture-signature',
  scannedAt: '2026-01-01T00:00:00.000Z',
  avatarPath: 'media/avatars/old.jpg',
  avatarVersion: 'old-avatar',
  mlKemPublicKey: 'old-fixture-mlkem',
  mlKemKeyUpdatedTs: '2026-01-01T00:00:00.000Z',
);

ContactRepositoryImpl _repository(
  Database db, {
  required Future<void> Function() beforeAvatarUpdate,
  required void Function() changed,
}) => ContactRepositoryImpl(
  dbLoadAllContacts: () => dbLoadAllContacts(db),
  dbLoadContact: (id) => dbLoadContact(db, id),
  dbUpsertContact: (_) async =>
      throw StateError('avatar must not upsert a contact'),
  dbUpdateContactAvatar: (id, path, version) async {
    await beforeAvatarUpdate();
    return dbUpdateContactAvatar(
      db,
      id,
      avatarPath: path,
      avatarVersion: version,
    );
  },
  dbDeleteContact: (id) => dbDeleteContact(db, id),
  dbGetContactCount: () => dbGetContactCount(db),
  dbContactExists: (id) => dbContactExists(db, id),
  dbArchiveContact: (id) => dbArchiveContact(db, id),
  dbUnarchiveContact: (id) => dbUnarchiveContact(db, id),
  dbLoadActiveContacts: () => dbLoadActiveContacts(db),
  dbLoadArchivedContacts: () => dbLoadArchivedContacts(db),
  dbBlockContact: (id) => dbBlockContact(db, id),
  dbUnblockContact: (id) => dbUnblockContact(db, id),
  dbDismissIntroBanner: (id) => dbDismissIntroBanner(db, id),
  dbSetIntrosSentAt: (id, stamp) => dbSetIntrosSentAt(db, id, stamp),
  onPushEligibilityChanged: changed,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Database db;
  late String path;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('contact-avatar-update-');
    path = '${directory.path}/identity.db';
    db = await openRepairTestDatabase(path);
    await dbUpsertContact(db, _contact.toMap());
  });

  tearDown(() async {
    if (db.isOpen) await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'avatar completion preserves newer contact state through SQL reopen',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var notifications = 0;
      final repo = _repository(
        db,
        beforeAvatarUpdate: () async {
          started.complete();
          await release.future;
        },
        changed: () => notifications++,
      );
      final pending = repo.updateContactAvatar(
        _peerId,
        avatarPath: 'media/avatars/current.jpg',
        avatarVersion: 'new-avatar',
      );
      await started.future;
      final newer = _contact.copyWith(
        username: 'New name',
        mlKemPublicKey: 'new-fixture-mlkem',
        mlKemKeyUpdatedTs: '2026-10-30T12:00:00.000Z',
        isArchived: true,
        archivedAt: '2026-10-30T12:01:00.000Z',
        introsBannerDismissed: true,
        introsSentAt: '2026-10-30T12:02:00.000Z',
        introducedBy: 'Introducer',
        introducedByPeerId: 'introducer-fixture-peer',
      );
      await dbUpsertContact(db, newer.toMap());
      final expected = <String, Object?>{
        ...(await dbLoadContact(db, _peerId))!,
        'avatar_path': 'media/avatars/current.jpg',
        'avatar_version': 'new-avatar',
      };
      release.complete();
      final updated = await pending;
      expect(updated!.toMap(), ContactModel.fromMap(expected).toMap());
      expect(notifications, 1);
      await db.close();
      db = await openRepairTestDatabase(path);
      expect(await dbLoadContact(db, _peerId), expected);
    },
  );

  for (final blocked in [false, true]) {
    test(
      'avatar completion cannot update a ${blocked ? 'blocked' : 'deleted'} contact',
      () async {
        final started = Completer<void>();
        final release = Completer<void>();
        var notifications = 0;
        final repo = _repository(
          db,
          beforeAvatarUpdate: () async {
            started.complete();
            await release.future;
          },
          changed: () => notifications++,
        );
        final pending = repo.updateContactAvatar(
          _peerId,
          avatarPath: 'media/avatars/stale.jpg',
          avatarVersion: 'stale-avatar',
        );
        await started.future;
        if (blocked) {
          await dbBlockContact(db, _peerId);
        } else {
          await dbDeleteContact(db, _peerId);
        }
        release.complete();
        expect(await pending, isNull);
        expect(notifications, 0);
        await db.close();
        db = await openRepairTestDatabase(path);
        final current = await dbLoadContact(db, _peerId);
        if (blocked) {
          expect(current!['is_blocked'], 1);
          expect(current['avatar_path'], _contact.avatarPath);
          expect(current['avatar_version'], _contact.avatarVersion);
        } else {
          expect(current, isNull);
        }
      },
    );
  }
}
