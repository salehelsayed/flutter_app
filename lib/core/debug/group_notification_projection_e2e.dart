const String groupNotificationProjectionE2EAction =
    'group_notification_projection_android';
const String groupNotificationProjectionE2ECommandSchema =
    'mknoon.plan330.android-endpoint-command.v1';
const String groupNotificationProjectionE2EResultSchema =
    'mknoon.plan330.android-endpoint-result.v1';
const String groupNotificationProjectionTargetReceiptSchema =
    'mknoon.plan330.group-media-reaction-target.v1';
const String groupNotificationProjectionScenario =
    'android_group_notification_projection_durability';
const String groupNotificationProjectionBuildProfile = 'android.production_fcm';

const String groupNotificationProjectionObserveGroupPhase = 'observe_group';
const String groupNotificationProjectionSendMediaPhase = 'send_media';
const String groupNotificationProjectionReactMediaPhase = 'react_media';

const Map<String, String> groupNotificationProjectionExternalKindByFixtureKind =
    <String, String>{'jpeg': 'photo', 'mp4': 'video', 'voice': 'voiceMessage'};
const Map<String, String> groupNotificationProjectionMediaTypeByFixtureKind =
    <String, String>{'jpeg': 'image', 'mp4': 'video', 'voice': 'audio'};

final class GroupNotificationProjectionE2ERequest {
  const GroupNotificationProjectionE2ERequest({
    required this.phase,
    required this.role,
    required this.runId,
    required this.nonce,
    required this.groupName,
    required this.kind,
    required this.messageIds,
    required this.attachmentIds,
  });

  factory GroupNotificationProjectionE2ERequest.fromConfig(
    Map<String, dynamic> config,
  ) {
    const keys = <String>{
      'schema',
      'transport_action',
      'scenario',
      'stepId',
      'phase',
      'role',
      'runId',
      'nonce',
      'groupName',
      'kind',
      'messageIds',
      'attachmentIds',
    };
    if (config.keys.toSet().length != keys.length ||
        !config.keys.toSet().containsAll(keys) ||
        config['schema'] != groupNotificationProjectionE2ECommandSchema ||
        config['transport_action'] != groupNotificationProjectionE2EAction ||
        config['scenario'] != groupNotificationProjectionScenario) {
      throw const FormatException('Plan 330 endpoint command rejected');
    }
    final phase = _safeToken(config['phase'], maxLength: 32);
    final role = _safeToken(config['role'], maxLength: 32);
    final runId = _safeToken(config['runId'], maxLength: 96);
    final nonce = _safeToken(config['nonce'], maxLength: 128);
    final groupName = _safeToken(config['groupName'], maxLength: 64);
    final kind = _safeToken(config['kind'], maxLength: 24);
    final messageIds = _fixtureIdMap(config['messageIds']);
    final attachmentIds = _fixtureIdMap(config['attachmentIds']);
    final fixtureGroup = RegExp(
      r'^Plan330[AB]-[A-Za-z0-9]{6,32}$',
    ).hasMatch(groupName);
    final groupAOnlyPhase =
        phase == groupNotificationProjectionSendMediaPhase ||
        phase == groupNotificationProjectionReactMediaPhase;
    if (!const <String>{
          groupNotificationProjectionObserveGroupPhase,
          groupNotificationProjectionSendMediaPhase,
          groupNotificationProjectionReactMediaPhase,
        }.contains(phase) ||
        !const <String>{'physical_author', 'emulator_reactor'}.contains(role) ||
        !const <String>{'group', 'jpeg', 'mp4', 'voice'}.contains(kind) ||
        (phase == groupNotificationProjectionReactMediaPhase &&
            !groupNotificationProjectionExternalKindByFixtureKind.containsKey(
              kind,
            )) ||
        (phase != groupNotificationProjectionReactMediaPhase &&
            kind != 'group') ||
        !fixtureGroup ||
        (groupAOnlyPhase && !groupName.startsWith('Plan330A-')) ||
        config['stepId'] != 'plan330-$phase-$kind-$runId') {
      throw const FormatException('Plan 330 endpoint phase rejected');
    }
    return GroupNotificationProjectionE2ERequest(
      phase: phase,
      role: role,
      runId: runId,
      nonce: nonce,
      groupName: groupName,
      kind: kind,
      messageIds: messageIds,
      attachmentIds: attachmentIds,
    );
  }

  final String phase;
  final String role;
  final String runId;
  final String nonce;
  final String groupName;
  final String kind;
  final Map<String, String> messageIds;
  final Map<String, String> attachmentIds;

  String get stepId => 'plan330-$phase-$kind-$runId';
}

Map<String, Object?> groupNotificationProjectionE2EFailureReceipt({
  required Map<String, dynamic> config,
  required Object error,
}) {
  String bound(String key, String fallback) {
    final value = config[key];
    return value is String &&
            value.isNotEmpty &&
            value.length <= 180 &&
            RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)
        ? value
        : fallback;
  }

  return <String, Object?>{
    'schema': groupNotificationProjectionE2EResultSchema,
    'transport_action': groupNotificationProjectionE2EAction,
    'scenario': groupNotificationProjectionScenario,
    'stepId': bound('stepId', 'invalid-step'),
    'phase': bound('phase', 'invalid-phase'),
    'role': bound('role', 'invalid-role'),
    'runId': bound('runId', 'invalid-run'),
    'nonce': bound('nonce', 'invalid-nonce'),
    'status': 'failed',
    'success': false,
    'errorType': error.runtimeType.toString(),
    'errorCode': groupNotificationProjectionFailureCode(error),
  };
}

/// Maps endpoint failures to a fixed diagnostic vocabulary without returning
/// exception text, group IDs, peer IDs, or fixture IDs to the host harness.
String groupNotificationProjectionFailureCode(Object error) {
  if (error is FormatException) return 'invalid_request';
  if (error is! StateError) return 'unexpected_error';

  final message = error.message;
  const exact = <String, String>{
    'Plan 330 endpoint requires the Android production-FCM profile':
        'profile_mismatch',
    'Plan 330 endpoint identity is unavailable': 'identity_unavailable',
    'Plan 330 exact group lookup did not settle': 'group_lookup_unsettled',
    'Plan 330 group must contain one remote member':
        'remote_member_cardinality',
    'Plan 330 remote transport authority is ambiguous':
        'remote_transport_ambiguous',
    'group-media send identity discriminator failed':
        'sender_identity_discriminator',
    'receiver active transport roster did not converge':
        'receiver_transport_roster_unsettled',
    'group-media ACL did not select receiver transport': 'media_acl_invalid',
    'group-media fixture IDs are incomplete or reused': 'fixture_id_invalid',
    'group-media fixture attachment lease was denied':
        'attachment_lease_denied',
    'group-media voice fixture lacks RECORD_AUDIO':
        'record_audio_permission_missing',
    'group-media voice fixture recording is invalid': 'voice_fixture_invalid',
    'group-media voice fixture is not AAC/M4A': 'voice_fixture_invalid',
    'group-media foreground leaf ACL lost transport authority':
        'media_acl_invalid',
    'group-media authority policy rejected': 'media_authority_policy_rejected',
    'Plan 330 production reaction did not commit': 'reaction_commit_failed',
    'Plan 330 media target did not arrive': 'media_target_unsettled',
  };
  final known = exact[message];
  if (known != null) return known;
  if (message.startsWith('group-media ') &&
      message.endsWith(' fixture policy rejected')) {
    return 'media_fixture_policy_rejected';
  }
  if (message.startsWith('group-media ') &&
      message.endsWith(' foreground completion failed')) {
    return 'media_upload_completion_failed';
  }
  if (message.startsWith('group-media ') &&
      message.endsWith(' publication failed')) {
    return 'media_publication_failed';
  }
  if (message.startsWith('Plan 330 ') &&
      message.endsWith(' author attachment did not settle')) {
    return 'author_attachment_unsettled';
  }
  return 'unexpected_state';
}

String? resolvePlan330AccountBoundRemoteTransport({
  required String remoteAccountPeerId,
  required Iterable<String> activeTransportPeerIds,
}) {
  final account = remoteAccountPeerId.trim();
  final transports = activeTransportPeerIds
      .map((transport) => transport.trim())
      .toList(growable: false);
  if (account.isEmpty ||
      account != remoteAccountPeerId ||
      transports.length != 1 ||
      transports.single.isEmpty ||
      transports.single != account) {
    return null;
  }
  return transports.single;
}

Map<String, String> _fixtureIdMap(Object? value) {
  if (value is! Map ||
      value.keys.toSet().length != 3 ||
      !value.keys.toSet().containsAll(
        groupNotificationProjectionExternalKindByFixtureKind.keys,
      )) {
    throw const FormatException('Plan 330 fixture ID map rejected');
  }
  final result = <String, String>{};
  for (final kind
      in groupNotificationProjectionExternalKindByFixtureKind.keys) {
    result[kind] = _safeToken(value[kind], maxLength: 160);
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(result[kind]!)) {
      throw const FormatException('Plan 330 fixture ID is not UUIDv4');
    }
  }
  if (result.values.toSet().length != result.length) {
    throw const FormatException('Plan 330 fixture IDs are reused');
  }
  return Map<String, String>.unmodifiable(result);
}

String _safeToken(Object? value, {required int maxLength}) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maxLength ||
      !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)) {
    throw const FormatException('Plan 330 safe token rejected');
  }
  return value;
}
