import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';

/// Result of adding a contact.
enum AddContactResult {
  /// Contact was successfully added.
  success,

  /// Contact already exists in the database.
  alreadyExists,

  /// Database error occurred.
  dbError,
}

/// Adds a contact to the database.
///
/// Returns [AddContactResult.alreadyExists] if contact with same peerId exists.
Future<AddContactResult> addContact({
  required ContactRepository repository,
  required ContactModel contact,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'ADD_CONTACT_START',
    details: {'peerId': contact.peerId.substring(0, 10)},
  );

  try {
    // Check if contact already exists
    final exists = await repository.contactExists(contact.peerId);
    if (exists) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ADD_CONTACT_EXISTS',
        details: {'peerId': contact.peerId.substring(0, 10)},
      );
      return AddContactResult.alreadyExists;
    }

    // Add the contact
    await repository.addContact(contact);

    emitFlowEvent(
      layer: 'FL',
      event: 'ADD_CONTACT_SUCCESS',
      details: {'peerId': contact.peerId.substring(0, 10)},
    );

    return AddContactResult.success;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ADD_CONTACT_ERROR',
      details: {'error': e.toString()},
    );
    return AddContactResult.dbError;
  }
}
