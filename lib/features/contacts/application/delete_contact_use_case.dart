import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

/// Deletes a contact and all their messages.
Future<void> deleteContactAndMessages({
  required ContactRepository contactRepo,
  required MessageRepository messageRepo,
  required String peerId,
}) async {
  emitFlowEvent(
    layer: 'UC',
    event: 'DELETE_CONTACT_START',
    details: {'peerId': peerId.substring(0, 10)},
  );

  try {
    final deletedCount = await messageRepo.deleteMessagesForContact(peerId);

    emitFlowEvent(
      layer: 'UC',
      event: 'DELETE_CONTACT_MESSAGES_PURGED',
      details: {
        'peerId': peerId.substring(0, 10),
        'deletedMessages': deletedCount,
      },
    );

    await contactRepo.deleteContact(peerId);

    emitFlowEvent(
      layer: 'UC',
      event: 'DELETE_CONTACT_SUCCESS',
      details: {'peerId': peerId.substring(0, 10)},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'UC',
      event: 'DELETE_CONTACT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
