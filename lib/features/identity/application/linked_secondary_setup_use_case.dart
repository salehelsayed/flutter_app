import 'package:flutter_app/core/config/direct_linked_devices_flag.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/identity/application/restore_identity_use_case.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Outcome of the explicit linked-secondary setup flow.
enum LinkedSecondarySetupResult {
  success,

  /// The direct selector is off, so new linked authority may not be created.
  selectorDisabled,

  /// Persisted authority is already active, or is in a state this flow cannot
  /// advance from.
  refused,

  /// The transport credential could not be created or proven.
  credentialError,

  /// The mnemonic restore itself failed. Reported with its exact reason so the
  /// UI can distinguish "wrong words" from "bridge is down".
  restoreFailed,
}

/// Runs the crash-safe linked-secondary setup in its exact required order.
///
/// The ordering is the whole safety property, and it is deliberately
/// marker-first / activate-last:
///
///   1. write the expected-role marker,
///   2. create (or re-adopt) ONE transport credential in `preparing`,
///   3. restore the logical account identity + installation-local ML-KEM,
///   4. transition THAT EXACT credential to `active`.
///
/// Every crash point lands on a state that REFUSES normal startup rather than
/// one that silently looks like a primary:
///
///   * crash after 1 — marker only; setup may resume and mint its first
///     credential.
///   * crash after 2 — marker + `preparing`; setup resumes with the SAME
///     bytes. Minting a second identity here would strand any QR already
///     handed out.
///   * crash after 3 — still `preparing`; the account identity exists but the
///     installation has not claimed its transport, so it must not start.
///
/// Doing this in the opposite order would, at its worst crash point, leave an
/// installation holding a live restored account identity and no role marker —
/// indistinguishable from an ordinary primary, and therefore starting the
/// ACCOUNT transport. That is precisely the shared-mailbox failure this plan
/// exists to prevent.
Future<LinkedSecondarySetupResult> setUpLinkedSecondaryInstallation({
  required String mnemonic,
  required LinkedInstallationAuthority authority,
  required IdentityRepository identityRepo,
  required Future<Map<String, dynamic>> Function(String) callRestore,
  required Future<Map<String, dynamic>> Function() callMlKemKeygen,
  required Future<Map<String, dynamic>> Function() callIdentityGenerate,
  required Future<Map<String, dynamic>> Function(String data, String privateKey)
  callSign,
  required Future<bool> Function({
    required String publicKey,
    required String data,
    required String signature,
  })
  callVerify,
  DirectLinkedDeviceSelector selector = const DirectLinkedDeviceSelector(),
  void Function(String stage)? onProgress,
}) async {
  if (!selector.allowsLinkedDeviceAuthoring) {
    return LinkedSecondarySetupResult.selectorDisabled;
  }

  final initial = await authority.load();
  if (initial.disposition == LinkedInstallationDisposition.active ||
      initial.disposition == LinkedInstallationDisposition.failClosed) {
    return LinkedSecondarySetupResult.refused;
  }

  // Step 1 — the marker, before any key material exists.
  await authority.markExpectedLinkedRole();

  // The logical account identity must be known before a credential can be
  // bound to it. Restoring first would invert the ordering, so this flow
  // derives the account identity from the mnemonic through the SAME bridge
  // restore call it will later persist, without persisting it yet.
  final Map<String, dynamic> restoreProbe;
  try {
    restoreProbe = await callRestore(_normalizeMnemonicForProbe(mnemonic));
  } catch (error) {
    emitFlowEvent(
      layer: 'FL',
      event: 'LINKED_DEVICE_SETUP_RESTORE_PROBE_ERROR',
      details: {'errorType': error.runtimeType.toString()},
    );
    return LinkedSecondarySetupResult.restoreFailed;
  }
  if (restoreProbe['ok'] != true) {
    return LinkedSecondarySetupResult.restoreFailed;
  }
  final probeIdentity = restoreProbe['identity'];
  if (probeIdentity is! Map) {
    return LinkedSecondarySetupResult.restoreFailed;
  }
  final accountPeerId = (probeIdentity['peerId'] as String?)?.trim() ?? '';
  final accountPublicKey =
      (probeIdentity['publicKey'] as String?)?.trim() ?? '';
  if (accountPeerId.isEmpty || accountPublicKey.isEmpty) {
    return LinkedSecondarySetupResult.restoreFailed;
  }

  // Step 2 — exactly one credential, in `preparing`.
  onProgress?.call('preparing_transport');
  final (credentialResult, credential) = await authority
      .createOrResumeTransportCredential(
        accountPeerId: accountPeerId,
        accountPublicKey: accountPublicKey,
        callIdentityGenerate: callIdentityGenerate,
        callSign: callSign,
        callVerify: callVerify,
      );
  if (credentialResult != LinkedInstallationSetupResult.success ||
      credential == null) {
    return LinkedSecondarySetupResult.credentialError;
  }

  // Step 3 — persist the logical account identity and installation-local
  // ML-KEM through the incumbent restore owner, unchanged.
  final restoreResult = await restoreIdentityFromMnemonic(
    input: mnemonic,
    callRestore: callRestore,
    callMlKemKeygen: callMlKemKeygen,
    repo: identityRepo,
    onProgress: onProgress,
  );
  if (restoreResult != RestoreIdentityResult.success) {
    emitFlowEvent(
      layer: 'FL',
      event: 'LINKED_DEVICE_SETUP_RESTORE_FAILED',
      details: {'result': restoreResult.name},
    );
    return LinkedSecondarySetupResult.restoreFailed;
  }

  // Step 4 — activate THAT EXACT credential, last.
  final activation = await authority.activateTransportCredential(
    accountPeerId: accountPeerId,
    expectedTransportPeerId: credential.transportPeerId,
  );
  if (activation != LinkedInstallationSetupResult.success) {
    return LinkedSecondarySetupResult.credentialError;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'LINKED_DEVICE_SETUP_COMPLETE',
    details: const {},
  );
  return LinkedSecondarySetupResult.success;
}

String _normalizeMnemonicForProbe(String input) =>
    input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
