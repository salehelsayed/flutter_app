import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/debug/e2e_test_mode.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/push/application/issue_wake_tokens_use_case.dart';
import 'package:flutter_app/features/push/application/wake_token_wiring.dart';
import 'package:flutter_app/features/push/domain/received_wake_token_store.dart';
import 'package:flutter_app/features/push/domain/wake_token_store.dart';

import 'wake_token_directionality_e2e_protocol.dart';

export 'wake_token_directionality_e2e_protocol.dart';

const String _installedSimsBuildProfile = String.fromEnvironment(
  'SIMS_BUILD_PROFILE_ID',
);

typedef RegisterWakeTokensForE2E = Future<bool> Function(List<String> tokens);
typedef WakeTokenWaitCycle = Future<void> Function();

/// One active, exact-operation capture for the accepted production
/// `inbox:store` attachment boundary.
///
/// [observeAccepted] receives hashes computed inside `P2PServiceImpl`; raw
/// tokens and peer IDs never cross this observer. The expected peer and message
/// hashes make a concurrent, unrelated inbox write unable to satisfy the run.
final class WakeTokenAcceptedAttachmentObserver {
  _WakeTokenAttachmentArm? _active;

  bool get isArmed => _active != null;

  void observeAccepted({
    required String toPeerIdSha256,
    required String messageSha256,
    required String wakeTokenSha256,
  }) {
    final active = _active;
    if (active == null ||
        active.peerIdSha256 != toPeerIdSha256 ||
        active.messageSha256 != messageSha256 ||
        !_isSha256(wakeTokenSha256) ||
        active.completer.isCompleted) {
      return;
    }
    active.completer.complete(wakeTokenSha256);
  }

  Future<WakeTokenAttachmentCapture> capture({
    required String expectedPeerId,
    required String expectedMessage,
    required Future<InboxStoreOutcome> Function() dispatch,
    required Duration timeout,
  }) async {
    if (_active != null) {
      throw StateError('wake-token attachment observer is already armed');
    }
    final arm = _WakeTokenAttachmentArm(
      peerIdSha256: _sha256(expectedPeerId),
      messageSha256: _sha256(expectedMessage),
    );
    _active = arm;
    try {
      final outcome = await dispatch();
      if (!outcome.accepted) {
        throw StateError('real inbox:store did not accept the attachment');
      }
      final tokenHash = await arm.completer.future.timeout(timeout);
      return WakeTokenAttachmentCapture(
        wakeTokenSha256: tokenHash,
        storeStatus: outcome.status.name,
      );
    } finally {
      if (identical(_active, arm)) _active = null;
    }
  }
}

final class WakeTokenAttachmentCapture {
  const WakeTokenAttachmentCapture({
    required this.wakeTokenSha256,
    required this.storeStatus,
  });

  final String wakeTokenSha256;
  final String storeStatus;
}

final class _WakeTokenAttachmentArm {
  _WakeTokenAttachmentArm({
    required this.peerIdSha256,
    required this.messageSha256,
  });

  final String peerIdSha256;
  final String messageSha256;
  final Completer<String> completer = Completer<String>();
}

/// Runs A's real mint/persist/register boundary and returns only the hash of
/// the exact contact-bound token present in the relay-accepted register set.
Future<Map<String, Object?>> runWakeTokenIssuerE2EAction({
  required Map<String, dynamic> config,
  required WakeTokenStore wakeTokenStore,
  required RegisterWakeTokensForE2E registerWakeTokens,
  String Function()? mintToken,
  WakeTokenWaitCycle? onWaitCycle,
  Duration registrationRetryInterval = const Duration(seconds: 1),
  int maxRegistrationAttempts = 8,
  bool? debugModeOverride,
  bool? e2eModeOverride,
  bool? emissionEnabledOverride,
  String? installedProfileOverride,
}) async {
  final request = WakeTokenDirectionalityRequest.parse(
    config,
    expectedRole: wakeTokenIssuerRole,
    expectedAction: wakeTokenIssuerAction,
  );
  _requireRuntime(
    debugMode: debugModeOverride ?? kDebugMode,
    e2eMode: e2eModeOverride ?? kE2ETestMode,
    emissionEnabled: emissionEnabledOverride ?? shouldEmitWakeToken(),
    installedProfile: installedProfileOverride ?? _installedSimsBuildProfile,
  );
  if (maxRegistrationAttempts <= 0) {
    throw ArgumentError.value(
      maxRegistrationAttempts,
      'maxRegistrationAttempts',
      'must be positive',
    );
  }
  if (registrationRetryInterval.isNegative) {
    throw ArgumentError.value(
      registrationRetryInterval,
      'registrationRetryInterval',
      'must not be negative',
    );
  }

  String? registeredTokenSha256;
  final useCase = IssueWakeTokensUseCase(
    wakeTokenStore: wakeTokenStore,
    mintToken: mintToken,
    registerWakeTokens: (tokens) async {
      final persisted = await wakeTokenStore.readTokens();
      final contactToken = persisted[request.contactPeerId];
      if (tokens.length != 1 ||
          contactToken == null ||
          contactToken.isEmpty ||
          tokens.single != contactToken) {
        throw StateError(
          'relay register set is not bound to the requested contact',
        );
      }
      final accepted = await registerWakeTokens(tokens);
      if (accepted) registeredTokenSha256 = _sha256(tokens.single);
      return accepted;
    },
  );

  // The production use case deliberately performs one relay registration and
  // never spins in the background. This explicit E2E endpoint may instead
  // bridge a short app-start readiness race. Reusing the same use-case/store
  // instance is important: after the first attempt persists the contact token,
  // every retry registers that exact token rather than minting another one.
  final deadline = DateTime.now().add(request.timeout);
  var accepted = false;
  for (var attempt = 1; attempt <= maxRegistrationAttempts; attempt++) {
    accepted = await useCase.issueForContacts(<String>[request.contactPeerId]);
    if (accepted) break;
    if (attempt == maxRegistrationAttempts) break;

    await onWaitCycle?.call();
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) break;
    final delay = registrationRetryInterval < remaining
        ? registrationRetryInterval
        : remaining;
    await Future<void>.delayed(delay);
  }
  final registeredHash = registeredTokenSha256;
  if (!accepted || registeredHash == null) {
    throw StateError('relay did not accept register_wake_tokens');
  }
  return _endpointReceipt(request, <String, Object?>{
    'registeredTokenSha256': registeredHash,
    'registerRelayAccepted': true,
    'registeredMemberCount': 1,
  });
}

/// Runs B's independently sourced production store read and accepted
/// `inbox:store` attachment observation. The store value is hashed immediately;
/// only the P2P-service boundary may supply the attached-token hash.
Future<Map<String, Object?>> runWakeTokenPresenterE2EAction({
  required Map<String, dynamic> config,
  required ReceivedWakeTokenStore receivedWakeTokenStore,
  required DetailedInboxStore detailedInboxStore,
  required WakeTokenAcceptedAttachmentObserver attachmentObserver,
  WakeTokenWaitCycle? onWaitCycle,
  Duration pollInterval = const Duration(milliseconds: 250),
  bool? debugModeOverride,
  bool? e2eModeOverride,
  bool? emissionEnabledOverride,
  String? installedProfileOverride,
}) async {
  final request = WakeTokenDirectionalityRequest.parse(
    config,
    expectedRole: wakeTokenPresenterRole,
    expectedAction: wakeTokenPresenterAction,
  );
  _requireRuntime(
    debugMode: debugModeOverride ?? kDebugMode,
    e2eMode: e2eModeOverride ?? kE2ETestMode,
    emissionEnabled: emissionEnabledOverride ?? shouldEmitWakeToken(),
    installedProfile: installedProfileOverride ?? _installedSimsBuildProfile,
  );

  final deadline = DateTime.now().add(request.timeout);
  String? storedTokenSha256;
  while (DateTime.now().isBefore(deadline)) {
    final entry = await receivedWakeTokenStore.readTokenFor(
      request.contactPeerId,
    );
    final token = entry?['tok'];
    if (token != null && token.isNotEmpty) {
      storedTokenSha256 = _sha256(token);
      break;
    }
    await onWaitCycle?.call();
    await Future<void>.delayed(pollInterval);
  }
  if (storedTokenSha256 == null) {
    throw StateError('production ReceivedWakeTokenStore observation timed out');
  }

  final message = wakeTokenAttachmentMessage(request.runId, request.nonce);
  final remaining = deadline.difference(DateTime.now());
  if (remaining <= Duration.zero) {
    throw StateError('wake-token attachment window expired');
  }
  final attachment = await attachmentObserver.capture(
    expectedPeerId: request.contactPeerId,
    expectedMessage: message,
    timeout: remaining,
    dispatch: () => detailedInboxStore.storeInInboxDetailed(
      request.contactPeerId,
      message,
      timeoutMs: remaining.inMilliseconds.clamp(1000, 15000),
    ),
  );
  return _endpointReceipt(request, <String, Object?>{
    'storedTokenSha256': storedTokenSha256,
    'attachedTokenSha256': attachment.wakeTokenSha256,
    'receivedStorePersisted': true,
    'inboxStoreAccepted': true,
    'inboxStoreStatus': attachment.storeStatus,
  });
}

Map<String, Object?> wakeTokenE2EFailureReceipt({
  required Map<String, dynamic> config,
  required Object error,
}) {
  String safeToken(String key, String fallback) {
    final value = config[key];
    return value is String &&
            value.isNotEmpty &&
            value.length <= 180 &&
            RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)
        ? value
        : fallback;
  }

  return <String, Object?>{
    'schema': wakeTokenEndpointResultSchema,
    'scenario': wakeTokenDirectionalityScenarioId,
    'buildProfile': wakeTokenDirectionalityProfileId,
    'role': safeToken('role', 'invalid-role'),
    'stepId': safeToken('stepId', 'invalid-step'),
    'runId': safeToken('runId', 'invalid-run'),
    'nonce': safeToken('nonce', 'invalid-nonce'),
    'status': 'failed',
    'success': false,
    // Never serialize an exception string: it might contain bridge payloads.
    'errorType': error.runtimeType.toString(),
  };
}

final class WakeTokenDirectionalityRequest {
  const WakeTokenDirectionalityRequest({
    required this.role,
    required this.action,
    required this.stepId,
    required this.runId,
    required this.nonce,
    required this.contactPeerId,
    required this.timeout,
  });

  factory WakeTokenDirectionalityRequest.parse(
    Map<String, dynamic> config, {
    required String expectedRole,
    required String expectedAction,
  }) {
    final expectedSchema = expectedRole == wakeTokenIssuerRole
        ? wakeTokenIssuerRequestSchema
        : wakeTokenPresenterRequestSchema;
    if (config['schema'] != expectedSchema ||
        config['scenario'] != wakeTokenDirectionalityScenarioId ||
        config['profileId'] != wakeTokenDirectionalityProfileId ||
        config['role'] != expectedRole ||
        config['transport_action'] != expectedAction) {
      throw const FormatException('wake-token action tuple rejected');
    }
    final runId = _requiredToken(config, 'runId', maxLength: 80);
    final nonce = _requiredToken(config, 'nonce', maxLength: 128);
    final expectedStep = expectedRole == wakeTokenIssuerRole
        ? wakeTokenIssuerStepId(runId)
        : wakeTokenPresenterStepId(runId);
    if (config['stepId'] != expectedStep) {
      throw const FormatException('wake-token step is not bound to the run');
    }
    return WakeTokenDirectionalityRequest(
      role: expectedRole,
      action: expectedAction,
      stepId: expectedStep,
      runId: runId,
      nonce: nonce,
      contactPeerId: _requiredToken(config, 'contactPeerId', maxLength: 180),
      timeout: Duration(
        milliseconds: ((config['timeoutMs'] as num?)?.toInt() ?? 120000).clamp(
          5000,
          180000,
        ),
      ),
    );
  }

  final String role;
  final String action;
  final String stepId;
  final String runId;
  final String nonce;
  final String contactPeerId;
  final Duration timeout;
}

Map<String, Object?> _endpointReceipt(
  WakeTokenDirectionalityRequest request,
  Map<String, Object?> observations,
) => Map<String, Object?>.unmodifiable(<String, Object?>{
  'schema': wakeTokenEndpointResultSchema,
  'scenario': wakeTokenDirectionalityScenarioId,
  'buildProfile': wakeTokenDirectionalityProfileId,
  'role': request.role,
  'stepId': request.stepId,
  'runId': request.runId,
  'nonce': request.nonce,
  'status': 'complete',
  'success': true,
  ...observations,
});

void _requireRuntime({
  required bool debugMode,
  required bool e2eMode,
  required bool emissionEnabled,
  required String installedProfile,
}) {
  if (!debugMode || !e2eMode) {
    throw StateError('wake-token action requires debug E2E mode');
  }
  if (!emissionEnabled) {
    throw StateError('wake-token emission is not enabled in this build');
  }
  if (installedProfile != wakeTokenDirectionalityProfileId) {
    throw StateError(
      'wake-token action requires $wakeTokenDirectionalityProfileId',
    );
  }
}

String _requiredToken(
  Map<String, dynamic> config,
  String key, {
  required int maxLength,
}) {
  final value = config[key];
  if (value is! String ||
      value.isEmpty ||
      value.length > maxLength ||
      !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)) {
    throw FormatException('wake-token request has invalid $key');
  }
  return value;
}

String _sha256(String value) => sha256.convert(utf8.encode(value)).toString();

bool _isSha256(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
