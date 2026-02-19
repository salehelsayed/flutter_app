import '../models/contact_model.dart';

/// Repository interface for managing contacts.
abstract class ContactRepository {
  /// Adds a new contact to the database.
  ///
  /// If a contact with the same peerId already exists, it will be updated.
  Future<void> addContact(ContactModel contact);

  /// Retrieves a contact by their peer ID.
  ///
  /// Returns null if no contact with the given ID exists.
  Future<ContactModel?> getContact(String peerId);

  /// Retrieves all contacts from the database.
  ///
  /// Returns an empty list if no contacts exist.
  Future<List<ContactModel>> getAllContacts();

  /// Deletes a contact by their peer ID.
  Future<void> deleteContact(String peerId);

  /// Checks if a contact with the given peer ID exists.
  Future<bool> contactExists(String peerId);

  /// Returns the total number of contacts.
  Future<int> getContactCount();

  /// Archives a contact by peer ID.
  Future<void> archiveContact(String peerId);

  /// Unarchives a contact by peer ID.
  Future<void> unarchiveContact(String peerId);

  /// Retrieves only active (non-archived) contacts.
  Future<List<ContactModel>> getActiveContacts();

  /// Retrieves only archived contacts.
  Future<List<ContactModel>> getArchivedContacts();

  /// Blocks a contact by peer ID.
  Future<void> blockContact(String peerId);

  /// Unblocks a contact by peer ID.
  Future<void> unblockContact(String peerId);
}
