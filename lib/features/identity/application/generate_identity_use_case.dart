import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Result of the generate identity use case
enum GenerateIdentityResult {
  /// Identity was successfully generated and saved
  success,

  /// Core library (bridge) returned an error
  coreLibError,

  /// Database save operation failed
  dbError,
}

/// Use case for generating a new identity.
///
/// This function orchestrates the identity generation flow:
/// 1. Calls the bridge to generate a new identity
/// 2. Maps the response to an IdentityModel
/// 3. Persists the identity to the repository
///
/// Dependencies are injected for testability.
Future<GenerateIdentityResult> generateNewIdentity({
  required Future<Map<String, dynamic>> Function() callGenerate,
  required Future<Map<String, dynamic>> Function() callMlKemKeygen,
  required IdentityRepository repo,
  void Function(String stage)? onProgress,
}) async {
  // Emit start event
  emitFlowEvent(
    layer: 'FL',
    event: 'ID_M1_GENERATE_START',
    details: {},
  );

  // Emit before bridge calls event
  emitFlowEvent(
    layer: 'FL',
    event: 'ID_M1_GENERATE_JS_CALL',
    details: {},
  );

  onProgress?.call('generating_keys');

  // Start ML-KEM keygen in parallel (independent of identity generation)
  final mlKemFuture = callMlKemKeygen();

  // Call bridge to generate identity
  final Map<String, dynamic> response;
  try {
    response = await callGenerate();
  } catch (e) {
    mlKemFuture.ignore();
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_M1_GENERATE_JS_ERROR',
      details: {'errorCode': 'CALL_EXCEPTION', 'errorMessage': e.toString()},
    );
    return GenerateIdentityResult.coreLibError;
  }

  // Check if bridge returned an error
  final ok = response['ok'] as bool? ?? false;
  if (!ok) {
    mlKemFuture.ignore();
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
    mlKemFuture.ignore();
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_M1_GENERATE_JS_ERROR',
      details: {'errorCode': 'MISSING_IDENTITY', 'errorMessage': 'Response missing identity field'},
    );
    return GenerateIdentityResult.coreLibError;
  }

  // Build IdentityModel from response
  var identity = IdentityModel.fromJson(identityJson);

  // Await ML-KEM keygen — failure is fatal (no plaintext-only identities)
  final Map<String, dynamic> mlKemResponse;
  try {
    mlKemResponse = await mlKemFuture;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_M1_MLKEM_KEYGEN_ERROR',
      details: {'error': e.toString()},
    );
    return GenerateIdentityResult.coreLibError;
  }

  if (mlKemResponse['ok'] != true) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_M1_MLKEM_KEYGEN_ERROR',
      details: {'errorCode': mlKemResponse['errorCode']},
    );
    return GenerateIdentityResult.coreLibError;
  }

  identity = IdentityModel(
    peerId: identity.peerId,
    publicKey: identity.publicKey,
    privateKey: identity.privateKey,
    mnemonic12: identity.mnemonic12,
    mlKemPublicKey: mlKemResponse['publicKey'] as String,
    mlKemSecretKey: mlKemResponse['secretKey'] as String,
    username: identity.username,
    avatarBlob: identity.avatarBlob,
    createdAt: identity.createdAt,
    updatedAt: identity.updatedAt,
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'ID_M1_MLKEM_KEYGEN_OK',
    details: {},
  );

  // Emit bridge success event
  emitFlowEvent(
    layer: 'FL',
    event: 'ID_M1_GENERATE_JS_OK',
    details: {'peerId': identity.peerId},
  );

  onProgress?.call('saving');

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
