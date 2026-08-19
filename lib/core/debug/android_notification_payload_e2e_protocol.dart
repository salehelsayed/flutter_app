const String androidNotificationPayloadE2ERequestSchema =
    'mknoon.plan258.android-notification-request.v1';
const String androidNotificationPayloadE2EResultSchema =
    'mknoon.plan258.android-notification-result.v1';
const String androidNotificationPayloadE2EScenario =
    'notifications.android_payload_campaign';

const String androidNotificationUnregisterPushAction =
    'notification_unregister_push';
const String androidNotificationRestorePushAction = 'notification_restore_push';
const String androidNotificationClearStagingAction =
    'notification_clear_staging';
const String androidNotificationStopNodeAndClearStagingAction =
    'notification_stop_node_and_clear_staging';
const String androidNotificationA6ObserveAction =
    'notification_a6_replay_observe';
const String androidNotificationPostTapObserveAction =
    'notification_post_tap_observe';
const String androidNotificationDrainObserveAction =
    'notification_drain_observe';

/// Rotates the installed app's FCM registration token in place: delete it,
/// then poll until the provider hands back a DIFFERENT one. Deleting alone is
/// not proof of rotation, so the receipt reports both token hash prefixes.
const String androidNotificationDeletePushTokenAction =
    'notification_delete_push_token';

const Set<String> _actions = <String>{
  androidNotificationUnregisterPushAction,
  androidNotificationRestorePushAction,
  androidNotificationClearStagingAction,
  androidNotificationStopNodeAndClearStagingAction,
  androidNotificationA6ObserveAction,
  androidNotificationPostTapObserveAction,
  androidNotificationDrainObserveAction,
  androidNotificationDeletePushTokenAction,
};

bool isAndroidNotificationPayloadE2EAction(Object? action) =>
    action is String && _actions.contains(action);

/// A fail-closed, nonce-bound request accepted by the installed main app.
///
/// Plaintext is used only as a run-unique local DB selector. Results never echo
/// it, peer IDs, provider tokens, or encrypted payload material.
final class AndroidNotificationPayloadE2ERequest {
  const AndroidNotificationPayloadE2ERequest({
    required this.action,
    required this.runId,
    required this.nonce,
    required this.stepId,
    required this.contactPeerId,
    required this.expectedText,
    required this.expectedMessageId,
    required this.requireStagedBeforeTap,
    required this.timeout,
  });

  factory AndroidNotificationPayloadE2ERequest.fromConfig(
    Map<String, dynamic> config,
  ) {
    String token(String key, {int maxLength = 180}) {
      final value = config[key];
      if (value is! String ||
          value.isEmpty ||
          value.length > maxLength ||
          !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)) {
        throw FormatException('invalid Android notification $key');
      }
      return value;
    }

    if (config['schema'] != androidNotificationPayloadE2ERequestSchema ||
        config['scenario'] != androidNotificationPayloadE2EScenario) {
      throw const FormatException(
        'Android notification request schema/scenario rejected',
      );
    }
    final action = token('transport_action');
    if (!_actions.contains(action)) {
      throw const FormatException('Android notification action rejected');
    }
    final runId = token('runId', maxLength: 96);
    final stepId = token('stepId');
    if (stepId != 'notification-$action-$runId') {
      throw const FormatException('Android notification step binding rejected');
    }
    final nonce = token('nonce', maxLength: 128);
    final needsMessage = <String>{
      androidNotificationA6ObserveAction,
      androidNotificationPostTapObserveAction,
      androidNotificationDrainObserveAction,
    }.contains(action);
    final needsMessageId = <String>{
      androidNotificationPostTapObserveAction,
      androidNotificationDrainObserveAction,
    }.contains(action);
    final contactPeerId = needsMessage
        ? token('contactPeerId')
        : _optionalToken(config['contactPeerId']);
    final expectedMessageId = needsMessageId
        ? token('expectedMessageId')
        : _optionalToken(config['expectedMessageId']);
    final expectedText = config['expectedText'];
    if (needsMessage &&
        (expectedText is! String ||
            expectedText.isEmpty ||
            expectedText.length > 240 ||
            expectedText.contains(RegExp(r'[\x00-\x1f\x7f]')))) {
      throw const FormatException('Android notification expectedText rejected');
    }
    final timeoutMs = ((config['timeoutMs'] as num?)?.toInt() ?? 120000)
        .clamp(30000, 180000)
        .toInt();
    return AndroidNotificationPayloadE2ERequest(
      action: action,
      runId: runId,
      nonce: nonce,
      stepId: stepId,
      contactPeerId: contactPeerId,
      expectedText: needsMessage ? expectedText as String : '',
      expectedMessageId: expectedMessageId,
      requireStagedBeforeTap: config['requireStagedBeforeTap'] == true,
      timeout: Duration(milliseconds: timeoutMs),
    );
  }

  final String action;
  final String runId;
  final String nonce;
  final String stepId;
  final String? contactPeerId;
  final String expectedText;
  final String? expectedMessageId;
  final bool requireStagedBeforeTap;
  final Duration timeout;
}

String? _optionalToken(Object? value) {
  if (value == null) return null;
  if (value is! String ||
      value.isEmpty ||
      value.length > 180 ||
      !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)) {
    throw const FormatException('invalid optional Android notification token');
  }
  return value;
}

Map<String, dynamic> androidNotificationPayloadE2EFailureReceipt({
  required Map<String, dynamic> config,
  required Object error,
}) {
  String safe(String key, String fallback) {
    final value = config[key];
    return value is String &&
            value.isNotEmpty &&
            value.length <= 180 &&
            RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)
        ? value
        : fallback;
  }

  return <String, dynamic>{
    'schema': androidNotificationPayloadE2EResultSchema,
    'transport_action': safe('transport_action', 'invalid-action'),
    'scenario': androidNotificationPayloadE2EScenario,
    'stepId': safe('stepId', 'invalid-step'),
    'runId': safe('runId', 'invalid-run'),
    'nonce': safe('nonce', 'invalid-nonce'),
    'status': 'failed',
    'success': false,
    'errorType': error.runtimeType.toString(),
  };
}
