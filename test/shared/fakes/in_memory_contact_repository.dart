import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';

/// In-memory [ContactRepository] for integration tests.
class InMemoryContactRepository implements ContactRepository {
  final Map<String, ContactModel> _contacts = {};

  void addTestContact(ContactModel contact) {
    _contacts[contact.peerId] = contact;
  }

  @override
  Future<void> addContact(ContactModel contact) async {
    _contacts[contact.peerId] = contact;
  }

  @override
  Future<ContactModel?> getContact(String peerId) async => _contacts[peerId];

  @override
  Future<List<ContactModel>> getAllContacts() async =>
      _contacts.values.toList();

  @override
  Future<void> deleteContact(String peerId) async {
    _contacts.remove(peerId);
  }

  @override
  Future<bool> contactExists(String peerId) async =>
      _contacts.containsKey(peerId);

  @override
  Future<int> getContactCount() async => _contacts.length;

  @override
  Future<void> archiveContact(String peerId) async {
    final c = _contacts[peerId];
    if (c != null) {
      _contacts[peerId] = c.copyWith(
        isArchived: true,
        archivedAt: DateTime.now().toUtc().toIso8601String(),
      );
    }
  }

  @override
  Future<void> unarchiveContact(String peerId) async {
    final c = _contacts[peerId];
    if (c != null) {
      _contacts[peerId] = c.copyWith(
        isArchived: false,
        clearArchivedAt: true,
      );
    }
  }

  @override
  Future<List<ContactModel>> getActiveContacts() async =>
      _contacts.values.where((c) => !c.isArchived).toList();

  @override
  Future<List<ContactModel>> getArchivedContacts() async =>
      _contacts.values.where((c) => c.isArchived).toList();

  @override
  Future<void> blockContact(String peerId) async {
    final c = _contacts[peerId];
    if (c != null) {
      _contacts[peerId] = c.copyWith(
        isBlocked: true,
        blockedAt: DateTime.now().toUtc().toIso8601String(),
      );
    }
  }

  @override
  Future<void> unblockContact(String peerId) async {
    final c = _contacts[peerId];
    if (c != null) {
      _contacts[peerId] = c.copyWith(
        isBlocked: false,
        clearBlockedAt: true,
      );
    }
  }
}
