import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Result enumeration for restore identity operation
enum RestoreIdentityResult {
  success,
  invalidMnemonicFormat, // word count != 12
  invalidMnemonicCore, // Bridge returned INVALID_MNEMONIC
  coreLibError, // Bridge returned other error
  dbError, // DB save failed
}

/// Use case: Restore identity from a 12-word BIP39 mnemonic
///
/// This function validates the mnemonic format locally, calls the bridge
/// to restore the identity, and saves it to the database.
///
/// Parameters:
/// - [input]: Raw mnemonic string from UI (may have extra spaces, wrong case)
/// - [callRestore]: Injected bridge function that calls identity.restore
/// - [repo]: IdentityRepository for persisting the identity
///
/// Returns:
/// - [RestoreIdentityResult] indicating the outcome of the operation
Future<RestoreIdentityResult> restoreIdentityFromMnemonic({
  required String input,
  required Future<Map<String, dynamic>> Function(String) callRestore,
  required IdentityRepository repo,
}) async {
  // Emit start event
  emitFlowEvent(
    layer: 'FL',
    event: 'ID_M1_RESTORE_START',
    details: {},
  );

  // Step 1: Local validation - normalize and validate word count
  final normalizedMnemonic = _normalizeMnemonic(input);
  final words = normalizedMnemonic.split(' ');
  final wordCount = words.where((w) => w.isNotEmpty).length;

  if (wordCount != 12) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_RESTORE_VALIDATION_FAIL',
      details: {'wordCount': wordCount},
    );
    return RestoreIdentityResult.invalidMnemonicFormat;
  }

  // Step 2: Call bridge to restore identity
  emitFlowEvent(
    layer: 'FL',
    event: 'ID_M1_RESTORE_JS_CALL',
    details: {},
  );

  final Map<String, dynamic> response;
  try {
    response = await callRestore(normalizedMnemonic);
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_RESTORE_CORELIB_ERROR',
      details: {'error': e.toString()},
    );
    return RestoreIdentityResult.coreLibError;
  }

  // Step 3: Handle JS response
  final ok = response['ok'] as bool? ?? false;

  if (!ok) {
    final errorCode = response['errorCode'] as String? ?? '';

    if (errorCode == 'INVALID_MNEMONIC') {
      emitFlowEvent(
        layer: 'FL',
        event: 'ID_RESTORE_INVALID_MNEMONIC_CORE',
        details: {'errorMessage': response['errorMessage']},
      );
      return RestoreIdentityResult.invalidMnemonicCore;
    } else {
      emitFlowEvent(
        layer: 'FL',
        event: 'ID_RESTORE_CORELIB_ERROR',
        details: {
          'errorCode': errorCode,
          'errorMessage': response['errorMessage'],
        },
      );
      return RestoreIdentityResult.coreLibError;
    }
  }

  // Step 4: Build IdentityModel from response
  final identityJson = response['identity'] as Map<String, dynamic>;
  final peerId = identityJson['peerId'] as String;

  emitFlowEvent(
    layer: 'FL',
    event: 'ID_M1_RESTORE_JS_OK',
    details: {'peerId': peerId},
  );

  final identity = IdentityModel.fromJson(identityJson);

  // Step 5: Save to database
  try {
    await repo.saveIdentity(identity);
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_M1_DB_SAVE_SUCCESS',
      details: {'source': 'restore'},
    );
    return RestoreIdentityResult.success;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_M1_DB_SAVE_ERROR',
      details: {
        'source': 'restore',
        'error': e.toString(),
      },
    );
    return RestoreIdentityResult.dbError;
  }
}

/// Normalizes a mnemonic string by:
/// - Trimming leading/trailing whitespace
/// - Converting to lowercase
/// - Collapsing multiple spaces into single spaces
String _normalizeMnemonic(String input) {
  return input
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');
}
