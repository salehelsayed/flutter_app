import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';

/// In-memory [ContactRepository] for tests.
///
/// Stores contacts in a map, tracks call counts.
class FakeContactRepository implements ContactRepository {
  final Map<String, ContactModel> _contacts = {};

  // Call tracking
  int addContactCallCount = 0;
  int getContactCallCount = 0;
  int getAllContactsCallCount = 0;
  int deleteContactCallCount = 0;

  // Last arguments
  ContactModel? lastAddedContact;

  // Configurable errors
  bool throwOnAddContact = false;

  /// Seed contacts for testing.
  void seed(List<ContactModel> contacts) {
    _contacts.clear();
    for (final c in contacts) {
      _contacts[c.peerId] = c;
    }
  }

  @override
  Future<void> addContact(ContactModel contact) async {
    addContactCallCount++;
    lastAddedContact = contact;
    if (throwOnAddContact) {
      throw Exception('FakeContactRepository: addContact error');
    }
    _contacts[contact.peerId] = contact;
  }

  @override
  Future<ContactModel?> getContact(String peerId) async {
    getContactCallCount++;
    return _contacts[peerId];
  }

  @override
  Future<List<ContactModel>> getAllContacts() async {
    getAllContactsCallCount++;
    return _contacts.values.toList();
  }

  @override
  Future<void> deleteContact(String peerId) async {
    deleteContactCallCount++;
    _contacts.remove(peerId);
  }

  @override
  Future<bool> contactExists(String peerId) async {
    return _contacts.containsKey(peerId);
  }

  @override
  Future<int> getContactCount() async {
    return _contacts.length;
  }

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
  Future<List<ContactModel>> getActiveContacts() async {
    return _contacts.values.where((c) => !c.isArchived).toList();
  }

  @override
  Future<List<ContactModel>> getArchivedContacts() async {
    return _contacts.values.where((c) => c.isArchived).toList();
  }

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
