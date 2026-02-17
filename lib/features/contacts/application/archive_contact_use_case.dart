import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';

/// Archives a contact, hiding them from the active friends list.
///
/// The contact's messages are preserved but notifications are silenced.
Future<void> archiveContact({
  required ContactRepository contactRepo,
  required String peerId,
}) async {
  emitFlowEvent(
    layer: 'UC',
    event: 'ARCHIVE_CONTACT_START',
    details: {'peerId': peerId.substring(0, 10)},
  );

  try {
    await contactRepo.archiveContact(peerId);

    emitFlowEvent(
      layer: 'UC',
      event: 'ARCHIVE_CONTACT_SUCCESS',
      details: {'peerId': peerId.substring(0, 10)},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'UC',
      event: 'ARCHIVE_CONTACT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
