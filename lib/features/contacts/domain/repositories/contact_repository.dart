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
}
