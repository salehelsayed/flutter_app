import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/identity/application/restore_identity_use_case.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

const String _kMnemonic12 = 'identity_mnemonic12';

enum SecureStoreIdentityRecoveryResult {
  noStoredMnemonic,
  restored,
  restoreFailed,
}

Future<SecureStoreIdentityRecoveryResult> recoverIdentityFromSecureStore({
  required SecureKeyStore secureKeyStore,
  required IdentityRepository repo,
  required Future<Map<String, dynamic>> Function(String mnemonic) callRestore,
  required Future<Map<String, dynamic>> Function() callMlKemKeygen,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'ID_STARTUP_SECURE_RESTORE_CHECK',
    details: {},
  );

  final storedMnemonic = await secureKeyStore.read(_kMnemonic12);
  if (storedMnemonic == null || storedMnemonic.trim().isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_STARTUP_SECURE_RESTORE_MISSING',
      details: {},
    );
    return SecureStoreIdentityRecoveryResult.noStoredMnemonic;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'ID_STARTUP_SECURE_RESTORE_FOUND',
    details: {},
  );

  final result = await restoreIdentityFromMnemonic(
    input: storedMnemonic,
    callRestore: callRestore,
    callMlKemKeygen: callMlKemKeygen,
    repo: repo,
  );

  if (result == RestoreIdentityResult.success) {
    emitFlowEvent(
      layer: 'FL',
      event: 'ID_STARTUP_SECURE_RESTORE_SUCCESS',
      details: {},
    );
    return SecureStoreIdentityRecoveryResult.restored;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'ID_STARTUP_SECURE_RESTORE_FAIL',
    details: {'result': result.name},
  );
  return SecureStoreIdentityRecoveryResult.restoreFailed;
}
