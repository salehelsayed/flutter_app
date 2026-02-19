import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../models/contact_model.dart';
import 'contact_repository.dart';

/// Implementation of ContactRepository using database helper functions.
class ContactRepositoryImpl implements ContactRepository {
  final Future<List<Map<String, Object?>>> Function() dbLoadAllContacts;
  final Future<Map<String, Object?>?> Function(String peerId) dbLoadContact;
  final Future<void> Function(Map<String, Object?> row) dbUpsertContact;
  final Future<void> Function(String peerId) dbDeleteContact;
  final Future<int> Function() dbGetContactCount;
  final Future<bool> Function(String peerId) dbContactExists;
  final Future<void> Function(String peerId) dbArchiveContact;
  final Future<void> Function(String peerId) dbUnarchiveContact;
  final Future<List<Map<String, Object?>>> Function() dbLoadActiveContacts;
  final Future<List<Map<String, Object?>>> Function() dbLoadArchivedContacts;
  final Future<void> Function(String peerId) dbBlockContact;
  final Future<void> Function(String peerId) dbUnblockContact;

  ContactRepositoryImpl({
    required this.dbLoadAllContacts,
    required this.dbLoadContact,
    required this.dbUpsertContact,
    required this.dbDeleteContact,
    required this.dbGetContactCount,
    required this.dbContactExists,
    required this.dbArchiveContact,
    required this.dbUnarchiveContact,
    required this.dbLoadActiveContacts,
    required this.dbLoadArchivedContacts,
    required this.dbBlockContact,
    required this.dbUnblockContact,
  });

  @override
  Future<void> addContact(ContactModel contact) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACTS_REPO_ADD_START',
      details: {'peerId': contact.peerId.substring(0, 10)},
    );

    try {
      await dbUpsertContact(contact.toMap());

      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_ADD_SUCCESS',
        details: {'peerId': contact.peerId.substring(0, 10)},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_ADD_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<ContactModel?> getContact(String peerId) async {
    final row = await dbLoadContact(peerId);
    if (row == null) return null;
    return ContactModel.fromMap(row);
  }

  @override
  Future<List<ContactModel>> getAllContacts() async {
    final rows = await dbLoadAllContacts();
    return rows.map((row) => ContactModel.fromMap(row)).toList();
  }

  @override
  Future<void> deleteContact(String peerId) async {
    await dbDeleteContact(peerId);
  }

  @override
  Future<bool> contactExists(String peerId) async {
    return await dbContactExists(peerId);
  }

  @override
  Future<int> getContactCount() async {
    return await dbGetContactCount();
  }

  @override
  Future<void> archiveContact(String peerId) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACTS_REPO_ARCHIVE_START',
      details: {'peerId': peerId.substring(0, 10)},
    );

    try {
      await dbArchiveContact(peerId);

      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_ARCHIVE_SUCCESS',
        details: {'peerId': peerId.substring(0, 10)},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_ARCHIVE_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<void> unarchiveContact(String peerId) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACTS_REPO_UNARCHIVE_START',
      details: {'peerId': peerId.substring(0, 10)},
    );

    try {
      await dbUnarchiveContact(peerId);

      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_UNARCHIVE_SUCCESS',
        details: {'peerId': peerId.substring(0, 10)},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_UNARCHIVE_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<List<ContactModel>> getActiveContacts() async {
    final rows = await dbLoadActiveContacts();
    return rows.map((row) => ContactModel.fromMap(row)).toList();
  }

  @override
  Future<List<ContactModel>> getArchivedContacts() async {
    final rows = await dbLoadArchivedContacts();
    return rows.map((row) => ContactModel.fromMap(row)).toList();
  }

  @override
  Future<void> blockContact(String peerId) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACTS_REPO_BLOCK_START',
      details: {'peerId': peerId.substring(0, 10)},
    );

    try {
      await dbBlockContact(peerId);

      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_BLOCK_SUCCESS',
        details: {'peerId': peerId.substring(0, 10)},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_BLOCK_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<void> unblockContact(String peerId) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACTS_REPO_UNBLOCK_START',
      details: {'peerId': peerId.substring(0, 10)},
    );

    try {
      await dbUnblockContact(peerId);

      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_UNBLOCK_SUCCESS',
        details: {'peerId': peerId.substring(0, 10)},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_UNBLOCK_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }
}
