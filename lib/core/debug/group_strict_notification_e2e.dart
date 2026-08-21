const String groupStrictNotificationE2EAction =
    'group_strict_notification_authority';
const String groupStrictNotificationScenario =
    'android_strict_group_notification_closure';
const String groupStrictNotificationCommandSchema =
    'mknoon.plan393.strict-authority-command.v1';
const String groupStrictNotificationResultSchema =
    'mknoon.plan393.strict-authority-result.v1';
const String groupStrictNotificationTransferSchema =
    'mknoon.plan393.strict-authority-transfer.v1';
const String groupStrictNotificationAuthorPhase = 'author_authority';
const String groupStrictNotificationInstallPhase = 'install_authority';

final class GroupStrictNotificationE2ERequest {
  const GroupStrictNotificationE2ERequest({
    required this.phase,
    required this.stepId,
    required this.runId,
    required this.nonce,
    required this.groupName,
    required this.authorityTransfer,
  });

  factory GroupStrictNotificationE2ERequest.fromConfig(
    Map<String, dynamic> config,
  ) {
    const keys = <String>{
      'schema',
      'transport_action',
      'scenario',
      'stepId',
      'phase',
      'runId',
      'nonce',
      'groupName',
      'authorityTransfer',
    };
    if (config.keys.toSet().length != keys.length ||
        !config.keys.toSet().containsAll(keys) ||
        config['schema'] != groupStrictNotificationCommandSchema ||
        config['transport_action'] != groupStrictNotificationE2EAction ||
        config['scenario'] != groupStrictNotificationScenario) {
      throw const FormatException('Plan 393 strict authority command rejected');
    }
    final phase = _token(config['phase'], 32);
    final runId = _token(config['runId'], 96);
    final nonce = _token(config['nonce'], 128);
    final groupName = _token(config['groupName'], 64);
    final stepId = _token(config['stepId'], 180);
    if (!const <String>{
          groupStrictNotificationAuthorPhase,
          groupStrictNotificationInstallPhase,
        }.contains(phase) ||
        !RegExp(r'^Plan393S-[A-Za-z0-9]{6,32}$').hasMatch(groupName) ||
        stepId != 'plan393-strict-$phase-$runId') {
      throw const FormatException('Plan 393 strict authority phase rejected');
    }
    final transfer = config['authorityTransfer'];
    if ((phase == groupStrictNotificationAuthorPhase && transfer != null) ||
        (phase == groupStrictNotificationInstallPhase && transfer is! Map)) {
      throw const FormatException(
        'Plan 393 strict authority transfer rejected',
      );
    }
    return GroupStrictNotificationE2ERequest(
      phase: phase,
      stepId: stepId,
      runId: runId,
      nonce: nonce,
      groupName: groupName,
      authorityTransfer: transfer == null
          ? null
          : Map<String, dynamic>.from(transfer as Map),
    );
  }

  final String phase;
  final String stepId;
  final String runId;
  final String nonce;
  final String groupName;
  final Map<String, dynamic>? authorityTransfer;
}

T parseGroupStrictAuthorityTransfer<T>(
  Map<String, dynamic> transfer, {
  required T? Function(Object? rawProof) parseProof,
}) {
  const keys = <String>{'schema', 'runId', 'proof'};
  if (transfer.keys.toSet().length != keys.length ||
      !transfer.keys.toSet().containsAll(keys) ||
      transfer['schema'] != groupStrictNotificationTransferSchema ||
      _token(transfer['runId'], 96).isEmpty) {
    throw const FormatException('Plan 393 strict authority transfer malformed');
  }
  final proof = parseProof(transfer['proof']);
  if (proof == null) {
    throw const FormatException('Plan 393 strict authority proof malformed');
  }
  return proof;
}

Map<String, Object?> groupStrictNotificationE2EFailureReceipt({
  required Map<String, dynamic> config,
  required Object error,
}) {
  String bound(String key, String fallback) {
    try {
      return _token(config[key], 180);
    } catch (_) {
      return fallback;
    }
  }

  return <String, Object?>{
    'schema': groupStrictNotificationResultSchema,
    'transport_action': groupStrictNotificationE2EAction,
    'scenario': groupStrictNotificationScenario,
    'stepId': bound('stepId', 'invalid-step'),
    'phase': bound('phase', 'invalid-phase'),
    'runId': bound('runId', 'invalid-run'),
    'nonce': bound('nonce', 'invalid-nonce'),
    'status': 'failed',
    'success': false,
    'errorType': error.runtimeType.toString(),
    'errorCode': error is FormatException
        ? 'invalid_request'
        : 'authority_setup_failed',
  };
}

String _token(Object? value, int maximumLength) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maximumLength ||
      !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)) {
    throw const FormatException('Plan 393 strict authority token rejected');
  }
  return value;
}
