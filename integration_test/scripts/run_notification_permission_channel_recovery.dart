import '../support/android_notification_payload_campaign.dart'
    show
        androidNotificationChannelImportance,
        androidNotificationChannelsForBody;
import 'contact_transfer_native_evidence.dart';

Future<List<String>> validateNotificationPermissionChannelRecoveryObservations(
  ContactTransferNativeEvidence evidence,
) async {
  final failures = <String>[];
  final observed = evidence.observations;
  final phases = journeyGapRows(observed['phases']);
  if (phases.map((row) => row['id']).join(',') !=
      'app_permission_denied,channel_blocked,recovered') {
    failures.add(
      'actual permission denial, channel block and recovery must occur in order',
    );
  }
  for (final row in phases) {
    final delivered = await evidence.json(row['persistedMessagePath']);
    if (delivered['messageId'] != row['messageId'] ||
        delivered['text'] != row['expectedText'] ||
        delivered['countAfterReopen'] != 1 ||
        delivered['authenticatedSender'] != true) {
      failures.add(
        '${row['id']}: delivery and exact durable message cannot be lost when notifications are denied',
      );
    }
    final recovered = row['id'] == 'recovered';
    if (row['platform'] == 'android') {
      final dump = await evidence.file(row['nativeDumpPath']).readAsString();
      final importance = androidNotificationChannelImportance(
        dump,
        packageName: row['packageName'] as String,
        channelId: row['channelId'] as String,
      );
      final channels = androidNotificationChannelsForBody(
        dump,
        packageName: row['packageName'] as String,
        body: row['expectedBody'] as String,
      );
      if (recovered
          ? channels.length != 1 || importance == null || importance <= 0
          : channels.isNotEmpty ||
                row['id'] == 'channel_blocked' && importance != 0) {
        failures.add(
          '${row['id']}: actual native card/channel effective state does not match denial/recovery',
        );
      }
    } else if (row['platform'] == 'ios') {
      final native = await evidence.json(row['nativePermissionPath']);
      if (native['notificationsEffective'] != recovered ||
          native['observedCardCount'] != (recovered ? 1 : 0)) {
        failures.add(
          '${row['id']}: actual iOS effective authorization/presentation required',
        );
      }
    } else {
      failures.add('actual supported platform required');
    }
    if (row['uiClaimsEnabled'] != recovered ||
        row['effectivePermissionEnabled'] != recovered ||
        row['id'] == 'app_permission_denied' &&
            row['nativePermission'] != 'denied') {
      failures.add(
        '${row['id']}: user-facing enabled state must agree with effective native permission/channel',
      );
    }
  }
  if (observed['ownedPermissionAndChannelStateRestored'] != true) {
    failures.add('restore exact permission/channel state owned by this run');
  }
  return failures;
}

Future<void> main(List<String> arguments) async {
  final failures = <String>[];
  var evaluated = false;
  if (arguments.contains('--receipt')) {
    try {
      final evidence = await ContactTransferNativeEvidence.load(
        arguments,
        journeyId: 'NOTIFY-004',
        requiredKinds: [
          'native-permission',
          'native-channel-dump',
          'durable-message-delivery',
          'truthful-user-facing-state',
          'owned-state-restoration',
        ],
      );
      evaluated = true;
      failures.addAll(
        await validateNotificationPermissionChannelRecoveryObservations(
          evidence,
        ),
      );
    } on ContactTransferCaptureUnavailable {
      // Capture absence is NOT RUN; it is not an app failure.
    } on Object {
      failures.add(
        'NOTIFY-004 observations are incomplete, malformed or not independently bound',
      );
    }
  }
  writeContactTransferNativeResult(
    journeyId: 'NOTIFY-004',
    ids: ['DC-023', 'NOTIFY-004'],
    captureGap:
        'Existing OS channel parsers and payload campaigns are available; no exact reusable permission/channel denial -> retained delivery -> truthful UI -> recovery capture owner covers this conjunction.',
    prerequisites: [
      'Future fapp uses actual Appium/native OS permission and channel settings with current installed artifact and available targets.',
      'Reuse actual Android dump parsers for importance/card channel, and retain independent iOS native authorization observations where available.',
      'Persist exact received message before/after reopen, compare effective native and user-facing state, and restore only the run-owned permission/channel changes.',
    ],
    failures: failures,
    evaluated: evaluated,
  );
}
