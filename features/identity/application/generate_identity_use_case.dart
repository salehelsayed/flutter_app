import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Result of the generate identity use case
enum GenerateIdentityResult {
  /// Identity was successfully generated and saved
  success,

  /// Core library (JS bridge) returned an error
  coreLibError,

  /// Database save operation failed
  dbError,
}

/// Use case for generating a new identity.
///
/// This function orchestrates the identity generation flow:
/// 1. Calls the JS bridge to generate a new identity
/// 2. Maps the response to an IdentityModel
/// 3. Persists the identity to the repository
///
/// Dependencies are injected for testability.
Future<GenerateIdentityResult> generateNewIdentity({
  required Future<Map<String, dynamic>> Function() callJsGenerate,
  required IdentityRepository repo,
}) async {
  // Emit start event
  emitFlowEvent(
    layer: 'FL',
    event: 'ID_M1_GENERATE_START',
    details: {},
  );

  // Emit before JS call event
  emitFlowEvent(
    layer: 'FL',
    event: 'ID_M1_GENERATE_JS_CALL',
    details: {},
  );

  // Call JS bridge to generate identity
  final Map<String, dynamic> response;
  try {
    response = await callJsGenerate();
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_M1_GENERATE_JS_ERROR',
      details: {'errorCode': 'CALL_EXCEPTION', 'errorMessage': e.toString()},
    );
    return GenerateIdentityResult.coreLibError;
  }

  // Check if JS bridge returned an error
  final ok = response['ok'] as bool? ?? false;
  if (!ok) {
    final errorCode = response['errorCode'] as String? ?? 'UNKNOWN';
    final errorMessage = response['errorMessage'] as String? ?? 'Unknown error';
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_M1_GENERATE_JS_ERROR',
      details: {'errorCode': errorCode, 'errorMessage': errorMessage},
    );
    return GenerateIdentityResult.coreLibError;
  }

  // Extract identity data from response
  final identityJson = response['identity'] as Map<String, dynamic>?;
  if (identityJson == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_M1_GENERATE_JS_ERROR',
      details: {'errorCode': 'MISSING_IDENTITY', 'errorMessage': 'Response missing identity field'},
    );
    return GenerateIdentityResult.coreLibError;
  }

  // Build IdentityModel from response
  final identity = IdentityModel.fromJson(identityJson);

  // Emit JS success event
  emitFlowEvent(
    layer: 'FL',
    event: 'ID_M1_GENERATE_JS_OK',
    details: {'peerId': identity.peerId},
  );

  // Save identity to repository
  try {
    await repo.saveIdentity(identity);
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_M1_DB_SAVE_SUCCESS',
      details: {'source': 'generate'},
    );
    return GenerateIdentityResult.success;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_M1_DB_SAVE_ERROR',
      details: {'source': 'generate', 'error': e.toString()},
    );
    return GenerateIdentityResult.dbError;
  }
}
