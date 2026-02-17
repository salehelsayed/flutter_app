import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';

/// Blocks a contact, preventing messages from being received or displayed.
Future<void> blockContact({
  required ContactRepository contactRepo,
  required String peerId,
}) async {
  emitFlowEvent(
    layer: 'UC',
    event: 'BLOCK_CONTACT_START',
    details: {'peerId': peerId.substring(0, 10)},
  );

  try {
    await contactRepo.blockContact(peerId);

    emitFlowEvent(
      layer: 'UC',
      event: 'BLOCK_CONTACT_SUCCESS',
      details: {'peerId': peerId.substring(0, 10)},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'UC',
      event: 'BLOCK_CONTACT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
