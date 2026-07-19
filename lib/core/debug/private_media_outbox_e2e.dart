import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'private_media_outbox_e2e_protocol.dart';

export 'private_media_outbox_e2e_protocol.dart';

const String _installedPrivateMediaOutboxSimsBuildProfile =
    String.fromEnvironment('SIMS_BUILD_PROFILE_ID');

typedef PrivateMediaOutboxE2EProgressWriter =
    Future<void> Function(Map<String, Object?> progress);
typedef PrivateMediaOutboxE2EEndpoint =
    Future<Map<String, Object?>> Function(
      PrivateMediaOutboxE2ERequest request,
      PrivateMediaOutboxE2EProgressWriter writeProgress,
      PrivateMediaOutboxE2EHostReleaseWaiter waitForHostRelease,
    );
typedef PrivateMediaOutboxE2EHostReleaseWaiter =
    Future<void> Function(PrivateMediaOutboxE2ERequest request);
typedef OpenPrivateMediaOutboxConversation =
    Future<void> Function(String contactPeerId);

final class PrivateMediaOutboxE2ERequest {
  const PrivateMediaOutboxE2ERequest({
    required this.role,
    required this.phase,
    required this.runId,
    required this.nonce,
    required this.contactPeerId,
    required this.messageId,
    required this.attachmentId,
    required this.timeout,
  });

  factory PrivateMediaOutboxE2ERequest.fromConfig(Map<String, dynamic> config) {
    const exactKeys = <String>{
      'schema',
      'transport_action',
      'scenario',
      'role',
      'phase',
      'runId',
      'nonce',
      'stepId',
      'contactPeerId',
      'messageId',
      'attachmentId',
      'timeoutMs',
    };
    if (config.keys.toSet().length != exactKeys.length ||
        !config.keys.toSet().containsAll(exactKeys) ||
        config['schema'] != privateMediaOutboxE2ERequestSchema ||
        config['transport_action'] != privateMediaOutboxE2EAction ||
        config['scenario'] != privateMediaOutboxE2EScenario) {
      throw const FormatException('private-media outbox request rejected');
    }
    final role = _requiredToken(config, 'role', maxLength: 16);
    if (role != privateMediaOutboxSenderRole &&
        role != privateMediaOutboxReceiverRole) {
      throw const FormatException('private-media outbox role rejected');
    }
    final phase = config['phase'];
    if (phase is! int || (phase != 1 && phase != 2)) {
      throw const FormatException('private-media outbox phase rejected');
    }
    final runId = _requiredToken(config, 'runId', maxLength: 80);
    if (config['stepId'] != 'private-media-outbox-$role-$phase-$runId') {
      throw const FormatException('private-media outbox step rejected');
    }
    final timeoutMs = config['timeoutMs'];
    if (timeoutMs is! int) {
      throw const FormatException('private-media outbox timeout rejected');
    }
    final messageId = _requiredToken(config, 'messageId', maxLength: 8);
    // CHAT_MSG_SEND_SUCCESS exposes its complete eight-character ID. Keeping
    // the proof fixture at exactly that width makes the terminal send event an
    // exact identity match instead of a truncated-prefix heuristic.
    if (messageId.length != 8) {
      throw const FormatException(
        'private-media outbox message identity rejected',
      );
    }
    return PrivateMediaOutboxE2ERequest(
      role: role,
      phase: phase,
      runId: runId,
      nonce: _requiredToken(config, 'nonce', maxLength: 128),
      contactPeerId: _requiredToken(config, 'contactPeerId', maxLength: 160),
      messageId: messageId,
      attachmentId: _requiredToken(config, 'attachmentId', maxLength: 160),
      timeout: Duration(milliseconds: timeoutMs.clamp(60000, 300000).toInt()),
    );
  }

  final String role;
  final int phase;
  final String runId;
  final String nonce;
  final String contactPeerId;
  final String messageId;
  final String attachmentId;
  final Duration timeout;

  bool get isSender => role == privateMediaOutboxSenderRole;
  String get stepId => 'private-media-outbox-$role-$phase-$runId';
  String get runCorrelationSha256 =>
      privateMediaOutboxSafeHash('$runId:$nonce:$phase');
  String get messageIdHash => privateMediaOutboxSafeHash(messageId);
  String get attachmentIdHash => privateMediaOutboxSafeHash(attachmentId);
}

/// Single mounted-conversation registration point. Production builds create a
/// disabled controller, while the explicit E2E build may register one exact
/// live `ConversationWired` endpoint at a time.
final class PrivateMediaOutboxE2EController {
  PrivateMediaOutboxE2EController({required this.enabled});

  final bool enabled;
  Object? _ownerToken;
  PrivateMediaOutboxE2EEndpoint? _endpoint;

  bool get hasMountedEndpoint => _endpoint != null;

  Object registerEndpoint(PrivateMediaOutboxE2EEndpoint endpoint) {
    if (!enabled) {
      throw StateError('private-media outbox endpoint is disabled');
    }
    if (_endpoint != null) {
      throw StateError('private-media outbox endpoint already mounted');
    }
    final token = Object();
    _ownerToken = token;
    _endpoint = endpoint;
    return token;
  }

  void unregisterEndpoint(Object token) {
    if (!identical(_ownerToken, token)) return;
    _ownerToken = null;
    _endpoint = null;
  }

  Future<Map<String, Object?>> run(
    PrivateMediaOutboxE2ERequest request,
    PrivateMediaOutboxE2EProgressWriter writeProgress,
    PrivateMediaOutboxE2EHostReleaseWaiter waitForHostRelease,
  ) {
    if (!enabled) {
      throw StateError('private-media outbox endpoint is disabled');
    }
    final endpoint = _endpoint;
    if (endpoint == null) {
      throw StateError('private-media outbox conversation is not mounted');
    }
    return endpoint(request, writeProgress, waitForHostRelease);
  }
}

Future<Map<String, Object?>> runPrivateMediaOutboxE2EAction({
  required Map<String, dynamic> config,
  required PrivateMediaOutboxE2EController controller,
  required PrivateMediaOutboxE2EProgressWriter writeProgress,
  required PrivateMediaOutboxE2EHostReleaseWaiter waitForHostRelease,
  String? installedProfileOverride,
}) {
  requirePrivateMediaOutboxE2EBuildProfile(
    installedProfileId:
        installedProfileOverride ??
        _installedPrivateMediaOutboxSimsBuildProfile,
  );
  final request = PrivateMediaOutboxE2ERequest.fromConfig(config);
  return controller.run(request, writeProgress, waitForHostRelease);
}

Map<String, Object?> privateMediaOutboxE2EHostRelease(
  PrivateMediaOutboxE2ERequest request,
) => <String, Object?>{
  'schema': privateMediaOutboxE2EHostReleaseSchema,
  'scenario': privateMediaOutboxE2EScenario,
  'release': privateMediaOutboxSenderOfflineRelease,
  'role': privateMediaOutboxSenderRole,
  'phase': request.phase,
  'stepId': request.stepId,
  'runId': request.runId,
  'nonce': request.nonce,
  'runCorrelationSha256': request.runCorrelationSha256,
  'messageIdHash': request.messageIdHash,
  'attachmentIdHash': request.attachmentIdHash,
};

void validatePrivateMediaOutboxE2EHostRelease(
  PrivateMediaOutboxE2ERequest request,
  Map<String, dynamic> release,
) {
  final expected = privateMediaOutboxE2EHostRelease(request);
  if (!request.isSender ||
      release.keys.toSet().length != expected.keys.length ||
      !release.keys.toSet().containsAll(expected.keys) ||
      expected.entries.any((entry) => release[entry.key] != entry.value)) {
    throw const FormatException(
      'private-media outbox host release binding rejected',
    );
  }
}

/// Fails closed unless the installed artifact attests the exact SIMS profile
/// used to build the production main-app endpoint.
void requirePrivateMediaOutboxE2EBuildProfile({
  String installedProfileId = _installedPrivateMediaOutboxSimsBuildProfile,
}) {
  if (installedProfileId != privateMediaOutboxE2EBuildProfile) {
    throw StateError(
      'private-media outbox E2E requires the attested main-app APK',
    );
  }
}

/// Ensures the config-driven proof reaches the production conversation route
/// before dispatching to its mounted endpoint. The route launcher may return
/// before Flutter completes the push, so readiness is observed explicitly.
Future<void> ensurePrivateMediaOutboxE2EEndpoint({
  required PrivateMediaOutboxE2EController controller,
  required PrivateMediaOutboxE2ERequest request,
  required OpenPrivateMediaOutboxConversation? openConversationByPeerId,
  Duration timeout = const Duration(seconds: 20),
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  if (controller.hasMountedEndpoint) return;
  final open = openConversationByPeerId;
  if (open == null) {
    throw StateError('private-media outbox conversation launcher is not wired');
  }
  await open(request.contactPeerId);
  final deadline = DateTime.now().add(timeout);
  while (!controller.hasMountedEndpoint && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(pollInterval);
  }
  if (!controller.hasMountedEndpoint) {
    throw StateError('private-media outbox conversation did not mount');
  }
}

Map<String, Object?> privateMediaOutboxE2EArmedReceipt(
  PrivateMediaOutboxE2ERequest request,
) => _baseReceipt(request, status: 'armed', success: true);

Map<String, Object?> privateMediaOutboxE2EQueuedReceipt(
  PrivateMediaOutboxE2ERequest request,
) => <String, Object?>{
  ..._baseReceipt(request, status: 'queued', success: true),
  'queuedNoRed': true,
  'encryptionPreparedCount': 1,
  'uploadRequestCount': 1,
};

Map<String, Object?> privateMediaOutboxE2EResumedQueuedReceipt(
  PrivateMediaOutboxE2ERequest request,
) => <String, Object?>{
  ..._baseReceipt(request, status: 'resumed_queued', success: true),
  'queuedNoRed': true,
  'offlineResumeAttemptCount': 0,
  'pauseResumeRemainedQueued': true,
};

/// Safe endpoint evidence. The host validates the hashes and timestamps, then
/// strips [timestampMs] while assembling the exact six-event proof artifact.
Map<String, Object?> privateMediaOutboxE2EEventEvidence(
  PrivateMediaOutboxE2ERequest request, {
  required String event,
  required int timestampMs,
  String? source,
}) {
  const allowedEvents = <String>{
    privateMediaOutboxNetworkRestoredEvent,
    privateMediaOutboxLeaseClaimedEvent,
    privateMediaOutboxEncryptionPreparedEvent,
    privateMediaOutboxUploadStartEvent,
    privateMediaOutboxSendSuccessEvent,
    privateMediaOutboxReceivedEvent,
  };
  if (!allowedEvents.contains(event) || timestampMs < 0) {
    throw const FormatException('private-media outbox event rejected');
  }
  if ((event == privateMediaOutboxLeaseClaimedEvent) != (source != null) ||
      (source != null && source != privateMediaOutboxNetworkRestoredSource)) {
    throw const FormatException('private-media outbox event source rejected');
  }
  return <String, Object?>{
    'event': event,
    'runCorrelationSha256': request.runCorrelationSha256,
    'attachmentSha256': request.attachmentIdHash,
    'timestampMs': timestampMs,
    'source': ?source,
  };
}

Map<String, Object?> privateMediaOutboxE2ECompletedReceipt(
  PrivateMediaOutboxE2ERequest request, {
  required String messageIdHash,
  required String attachmentIdHash,
  required List<Map<String, Object?>> events,
}) => <String, Object?>{
  ..._baseReceipt(request, status: 'complete', success: true),
  'messageIdHash': _requiredHash(messageIdHash),
  'attachmentIdHash': _requiredHash(attachmentIdHash),
  'events': List<Map<String, Object?>>.unmodifiable(
    events.map((event) => Map<String, Object?>.unmodifiable(event)),
  ),
};

Map<String, Object?> privateMediaOutboxE2EFailureReceipt({
  required Map<String, dynamic> config,
  required Object error,
}) {
  final request = PrivateMediaOutboxE2ERequest.fromConfig(config);
  return <String, Object?>{
    ..._baseReceipt(request, status: 'failed', success: false),
    'errorType': error.runtimeType.toString(),
  };
}

String privateMediaOutboxSafeHash(String value) =>
    sha256.convert(utf8.encode(value)).toString();

Map<String, Object?> _baseReceipt(
  PrivateMediaOutboxE2ERequest request, {
  required String status,
  required bool success,
}) => <String, Object?>{
  'schema': privateMediaOutboxE2EEndpointResultSchema,
  'status': status,
  'success': success,
  'scenario': privateMediaOutboxE2EScenario,
  'buildProfile': privateMediaOutboxE2EBuildProfile,
  'role': request.role,
  'phase': request.phase,
  'stepId': request.stepId,
  'runId': request.runId,
  'nonce': request.nonce,
  'runCorrelationSha256': request.runCorrelationSha256,
  'messageIdHash': request.messageIdHash,
  'attachmentIdHash': request.attachmentIdHash,
};

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
    throw FormatException('private-media outbox request has invalid $key');
  }
  return value;
}

String _requiredHash(String value) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw const FormatException('private-media outbox hash rejected');
  }
  return value;
}
