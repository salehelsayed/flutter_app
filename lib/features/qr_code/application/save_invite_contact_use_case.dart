import 'package:flutter_app/core/database/db_write_transaction.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/qr_code/application/confirm_contact_invite_use_case.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Saves a new invite contact under the current single-account authority.
///
/// [beforeCreate] may prepare the projection for an absent contact. It runs
/// inside the transaction and must not use the bridge or the same database.
Future<InviteContactSave> saveInviteContactIfAbsent({
  required Database database,
  required ContactModel contact,
  required String ownPeerId,
  required bool Function() canCommit,
  Future<void> Function()? beforeCreate,
}) async {
  if (ownPeerId.isEmpty || !canCommit()) return InviteContactSave.stale;

  try {
    return await dbWriteTransaction(database, (txn) async {
      if (!canCommit()) return InviteContactSave.stale;
      final identity = await txn.query(
        'identity',
        columns: ['peer_id'],
        where: 'id = 1',
        limit: 1,
      );
      if (!canCommit() ||
          identity.isEmpty ||
          identity.single['peer_id'] != ownPeerId) {
        return InviteContactSave.stale;
      }

      final existing = await txn.query(
        'contacts',
        columns: ['peer_id'],
        where: 'peer_id = ?',
        whereArgs: [contact.peerId],
        limit: 1,
      );
      if (!canCommit()) return InviteContactSave.stale;
      if (existing.isNotEmpty) return InviteContactSave.existing;

      await beforeCreate?.call();
      if (!canCommit()) return InviteContactSave.stale;
      await txn.insert('contacts', contact.toMap());
      if (!canCommit()) throw const _InviteWriteRetired();
      return InviteContactSave.created;
    });
  } on _InviteWriteRetired {
    return InviteContactSave.stale;
  }
}

final class _InviteWriteRetired implements Exception {
  const _InviteWriteRetired();
}
