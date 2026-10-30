import 'package:flutter_app/features/contact_request/application/resolve_contact_request_notification_target_use_case.dart';

import '../../tool/sims/production_notification_open_criteria.dart';
import 'contact_transfer_native_evidence.dart';
import 'run_intro_accept_notification_android.dart'
    show exactNotificationTitleNodeBounds;

Future<List<String>> validateContactRequestNotificationLifecycleObservations(
  ContactTransferNativeEvidence evidence,
) async {
  final failures = <String>[];
  final cases = journeyGapRows(evidence.observations['cases']);
  final seen = <String>{};
  final platforms = journeyGapMap(
    evidence.receipt['targets'],
  ).values.map((value) => journeyGapMap(value)['platform']).toSet();
  for (final row in cases) {
    final item = (
      platform: row['platform'] as String,
      state: row['state'] as String,
      event: row['eventId'] as String,
      senderVerified: row['senderVerified'] as bool,
    );
    if (!seen.add('${item.platform}/${item.state}/${item.senderVerified}')) {
      failures.add('each lifecycle/privacy case must occur exactly once');
    }
    final before = journeyGapMap(row['beforeOpen']);
    final after = journeyGapMap(row['afterOpen']);
    final target = journeyGapMap(
      journeyGapMap(evidence.receipt['targets'])[row['targetRole']],
    );
    if (target['platform'] != item.platform ||
        target['deviceId'] != row['deviceId']) {
      failures.add(
        'notification case must bind its actual pinned target/platform',
      );
    }
    if ((before['contactCount'] as int) < 0 ||
        (before['acceptedRequestCount'] as int) < 0 ||
        (before['acceptSendAttempts'] as int) < 0 ||
        item.event.isEmpty ||
        row['runId'] != evidence.receipt['runId'] ||
        before['contactCount'] != after['contactCount'] ||
        before['acceptedRequestCount'] != after['acceptedRequestCount'] ||
        before['acceptSendAttempts'] != after['acceptSendAttempts']) {
      failures.add(
        '${item.state}: tap or opening in-app reachability cannot silently accept a request',
      );
    }
    final expected = await evidence.json(row['expectedCopyPath']);
    final title = expected['title'] as String;
    final body = expected['body'] as String;
    final forbidden = (row['forbiddenIdentityTokens'] as List).cast<String>();
    if (expected['candidateSource'] != evidence.receipt['candidateSource'] ||
        expected['locale'] != row['locale'] ||
        title.isEmpty ||
        body.isEmpty ||
        forbidden.length < 2 ||
        forbidden.any(
          (token) =>
              token.isEmpty || title.contains(token) || body.contains(token),
        ) ||
        !item.senderVerified && expected['copyClass'] != 'generic' ||
        item.senderVerified &&
            ((row['verifiedDisplayName'] as String).isEmpty ||
                !('$title $body').contains(
                  row['verifiedDisplayName'] as String,
                ))) {
      failures.add(
        '${item.state}: verified identity/generic copy must be independently pinned and omit raw identifiers/keys',
      );
    }
    final expectedCards =
        ['foreground', 'permission_denied'].contains(item.state) ? 0 : 1;
    if (item.platform == 'android') {
      final dump = await evidence
          .file(row['nativeCardDumpPath'])
          .readAsString();
      final card = productionNotificationOpenNativeCard(
        dump,
        package: row['packageName'] as String,
        body: body,
      );
      if (expectedCards == 0
          ? card != null
          : card == null || card['title'] != title) {
        failures.add(
          '${item.state}: exact request card must match actual native copy/card multiplicity',
        );
      }
      if (expectedCards == 1) {
        final xml = await evidence
            .file(row['trayHierarchyPath'])
            .readAsString();
        if (exactNotificationTitleNodeBounds(xml, title).length != 1 ||
            row['tapUsedExactNode'] != true) {
          failures.add(
            'notification activation requires the exact owned native tray node',
          );
        }
      }
    } else if (item.platform == 'ios') {
      final card = await evidence.json(row['nativeCardObservationPath']);
      if (card['eventId'] != item.event ||
          card['activeCardCount'] != expectedCards ||
          expectedCards == 1 &&
              (card['title'] != title || card['body'] != body)) {
        failures.add(
          '${item.state}: exact event-bound iOS request card observation required',
        );
      }
    } else {
      failures.add('actual Android/iOS platform required');
    }
    if (item.state == 'locked' && row['nativeDeviceLocked'] != true ||
        item.state == 'terminated' &&
            (row['nativePidBeforeDispatch'] != 0 ||
                row['nativePidBeforeTap'] != 0 ||
                !evidence.files.containsKey(row['ownedProcessDeathPath'])) ||
        item.state == 'permission_denied' &&
            (row['nativeNotificationPermission'] != 'denied' ||
                row['inAppRequestReachable'] != true)) {
      failures.add(
        '${item.state}: actual native lifecycle/permission boundary and denied in-app reachability required',
      );
    }
    final persisted = journeyGapMap(row['persistedTarget']);
    final expectedRoute = persisted['blocked'] == true
        ? ContactRequestNotificationTargetState.missing
        : persisted['contactExists'] == true
        ? ContactRequestNotificationTargetState.conversation
        : persisted['requestStatus'] == 'pending'
        ? ContactRequestNotificationTargetState.pendingRequest
        : ContactRequestNotificationTargetState.missing;
    if (after['targetState'] != expectedRoute.name ||
        expectedRoute != ContactRequestNotificationTargetState.missing &&
            after['targetPeerId'] != row['senderPeerId'] ||
        after['resurrectedRequestCount'] != 0) {
      failures.add(
        '${item.state}: route must resolve current persisted request/contact authority without resurrection',
      );
    }
  }
  for (final platform in platforms) {
    for (final state in [
      'foreground',
      'background',
      'terminated',
      'locked',
      'permission_denied',
    ]) {
      for (final verified in [true, false]) {
        if (!seen.contains('$platform/$state/$verified')) {
          failures.add(
            '$platform/$state/$verified: lifecycle/privacy control missing',
          );
        }
      }
    }
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
        journeyId: 'CR-008',
        requiredKinds: [
          'provider-dispatch',
          'native-tray',
          'native-notification-permission',
          'lifecycle-state',
          'ui-route',
          'sql-request-before-after',
        ],
      );
      evaluated = true;
      failures.addAll(
        await validateContactRequestNotificationLifecycleObservations(evidence),
      );
    } on ContactTransferCaptureUnavailable {
      // Missing capture is NOT RUN; it is not an application failure.
    } on Object {
      failures.add(
        'CR-008 evidence is incomplete, malformed or not independently bound',
      );
    }
  }
  writeContactTransferNativeResult(
    journeyId: 'CR-008',
    ids: ['CR-008'],
    captureGap:
        'Existing Android/iOS notification campaigns cover message payload custody; '
        'no existing request-specific lifecycle/privacy/denied-reachability capture producer exists.',
    prerequisites: [
      'Future fapp uses actual authenticated request dispatch and Appium/native foreground/background/terminated/real-lock/tray/permission actions.',
      'Capture independently pinned localized verified/generic expected copy, raw owned tray card, current SQL authority and route before/after; message-payload campaign success is insufficient.',
      'Retain permission-denied in-app reachability and current/terminal-target controls on actual available target kinds; no fabricated receipt/native PASS.',
    ],
    failures: failures,
    evaluated: evaluated,
  );
}
