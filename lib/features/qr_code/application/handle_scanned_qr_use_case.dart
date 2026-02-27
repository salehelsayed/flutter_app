import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/application/add_contact_use_case.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/qr_code/application/parse_qr_payload_use_case.dart';

/// Result of handling a scanned QR code.
enum HandleScannedQRResult {
  success,
  alreadyExists,
  selfScan,
  invalidJson,
  missingFields,
  invalidSignature,
  expired,
  dbError,
}

/// Handles a scanned QR code string end-to-end.
///
/// 1. Parses and validates the QR payload
/// 2. Adds the contact to the database
/// 3. Sends a contact request in the background
///
/// Returns the result of the operation.
Future<HandleScannedQRResult> handleScannedQR({
  required String qrData,
  required Bridge bridge,
  required ContactRepository contactRepo,
  required IdentityRepository identityRepo,
  required P2PService p2pService,
  required String ownPeerId,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'QR_HANDLE_SCANNED_START',
    details: {'length': qrData.length},
  );

  // 1. Parse and validate
  final (parseResult, contact) = await parseQRPayload(
    qrString: qrData,
    bridge: bridge,
    ownPeerId: ownPeerId,
  );

  switch (parseResult) {
    case ParseQRResult.invalidJson:
      return HandleScannedQRResult.invalidJson;
    case ParseQRResult.missingFields:
      return HandleScannedQRResult.missingFields;
    case ParseQRResult.invalidSignature:
      return HandleScannedQRResult.invalidSignature;
    case ParseQRResult.expired:
      return HandleScannedQRResult.expired;
    case ParseQRResult.selfScan:
      return HandleScannedQRResult.selfScan;
    case ParseQRResult.success:
      break;
  }

  // 2. Add contact
  final addResult = await addContact(
    repository: contactRepo,
    contact: contact!,
  );

  switch (addResult) {
    case AddContactResult.alreadyExists:
      return HandleScannedQRResult.alreadyExists;
    case AddContactResult.dbError:
      return HandleScannedQRResult.dbError;
    case AddContactResult.success:
      break;
  }

  // 3. Send contact request in background (fire and forget)
  sendContactRequest(
    p2pService: p2pService,
    identityRepo: identityRepo,
    bridge: bridge,
    targetPeerId: contact.peerId,
    recipientPublicKey: contact.publicKey,
  ).then((sendResult) {
    emitFlowEvent(
      layer: 'FL',
      event: 'QR_HANDLE_SCANNED_REQUEST_SENT',
      details: {'result': sendResult.name},
    );
  });

  return HandleScannedQRResult.success;
}
