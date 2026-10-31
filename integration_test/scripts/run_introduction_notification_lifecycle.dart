import '../../tool/sims/production_notification_open_criteria.dart';
import 'contact_transfer_native_evidence.dart';
import 'run_intro_accept_notification_android.dart'
    show exactNotificationTitleNodeBounds, isIntroAcceptanceResult;

Future<List<String>> validateIntroductionNotificationLifecycleObservations(
  ContactTransferNativeEvidence evidence,
) async {
  final failures = <String>[];
  final cases = journeyGapRows(evidence.observations['cases']);
  final observedCases = <String>{};
  final platforms = journeyGapMap(
    evidence.receipt['targets'],
  ).values.map((value) => journeyGapMap(value)['platform']).toSet();
  for (final row in cases) {
    final item = (
      platform: row['platform'] as String,
      state: row['state'] as String,
      kind: row['notificationKind'] as String,
      eventId: row['eventId'] as String,
    );
    if (!observedCases.add('${item.platform}/${item.kind}/${item.state}')) {
      failures.add(
        'each introduction notification lifecycle case must occur exactly once',
      );
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
    if ((before['acceptedIntroductions'] as int) < 0 ||
        (before['participantContacts'] as int) < 0 ||
        (before['acceptanceSendAttempts'] as int) < 0 ||
        item.eventId.isEmpty ||
        row['runId'] != evidence.receipt['runId'] ||
        before['acceptedIntroductions'] != after['acceptedIntroductions'] ||
        before['participantContacts'] != after['participantContacts'] ||
        before['acceptanceSendAttempts'] != after['acceptanceSendAttempts']) {
      failures.add(
        '${item.kind}/${item.state}: notification opening cannot grant consent or create a participant relationship',
      );
    }
    if (item.state == 'locked' && row['nativeDeviceLocked'] != true ||
        item.state == 'terminated' &&
            (row['nativePidBeforeDispatch'] != 0 ||
                row['nativePidBeforeTap'] != 0 ||
                !evidence.files.containsKey(row['ownedProcessDeathPath']))) {
      failures.add(
        '${item.kind}/${item.state}: actual lock/process-death witness required before dispatch and tap',
      );
    }
    final expected = await evidence.json(row['expectedCopyPath']);
    final title = expected['title'] as String;
    final body = expected['body'] as String;
    if (title.isEmpty ||
        body.isEmpty ||
        expected['candidateSource'] != evidence.receipt['candidateSource'] ||
        expected['locale'] != row['locale']) {
      failures.add(
        'independent expected localized copy must bind the exact candidate and locale',
      );
    }
    if (item.kind == 'mutual_acceptance' &&
        row['locale'] == 'en' &&
        (title != 'Introduction accepted' ||
            body != 'Someone accepted an introduction involving you.')) {
      failures.add(
        'English acceptance notification must retain the existing exact acceptance copy',
      );
    }
    final expectedCards = item.state == 'foreground' ? 0 : 1;
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
          '${item.kind}/${item.state}: exact Android native copy/card count is required',
        );
      }
      if (expectedCards == 1) {
        final xml = await evidence
            .file(row['trayHierarchyPath'])
            .readAsString();
        if (exactNotificationTitleNodeBounds(xml, title).length != 1 ||
            row['tapUsedExactNode'] != true) {
          failures.add(
            'Android tray activation must use the unique actual title node',
          );
        }
      }
    } else if (item.platform == 'ios') {
      final card = await evidence.json(row['nativeCardObservationPath']);
      if (card['eventId'] != item.eventId ||
          card['activeCardCount'] != expectedCards ||
          expectedCards == 1 &&
              (card['title'] != title || card['body'] != body)) {
        failures.add(
          '${item.kind}/${item.state}: iOS native card observation must match this event and copy',
        );
      }
    } else {
      failures.add('actual Android/iOS target platform required');
    }
    if (row['terminalTarget'] == true) {
      if (after['route'] != 'safe_fallback' ||
          after['resurrectedIntroductionCount'] != 0) {
        failures.add(
          'stale terminal notification must not resurrect an introduction or accept it',
        );
      }
    } else if (item.kind == 'recipient_offer') {
      if (after['route'] != 'orbit_introductions' ||
          after['pendingIntroductionId'] != row['introductionId']) {
        failures.add(
          'recipient offer opens the exact pending introduction review without auto-consent',
        );
      }
    } else if (item.kind == 'mutual_acceptance') {
      final completion = await evidence.json(row['acceptanceStepPath']);
      if (!isIntroAcceptanceResult(
            Map<String, dynamic>.from(completion),
            stepId: row['acceptanceStepId'] as String,
          ) ||
          after['route'] != 'conversation' ||
          after['peerId'] != row['expectedRecipientPeerId']) {
        failures.add(
          'mutual-acceptance tap must follow a real completed acceptance and reach the intended current recipient',
        );
      }
    } else {
      failures.add('unsupported introduction notification kind');
    }
  }
  for (final platform in platforms) {
    for (final kind in ['recipient_offer', 'mutual_acceptance']) {
      for (final state in [
        'foreground',
        'background',
        'terminated',
        'locked',
      ]) {
        if (!observedCases.contains('$platform/$kind/$state')) {
          failures.add('$platform/$kind/$state: lifecycle observation missing');
        }
      }
    }
  }
  if (!cases.any((row) => row['terminalTarget'] == true)) {
    failures.add('a stale terminal-target control is required');
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
        journeyId: 'IN-008',
        requiredKinds: [
          'provider-dispatch',
          'native-tray',
          'lifecycle-state',
          'ui-route',
          'sql-consent-before-after',
        ],
      );
      evaluated = true;
      failures.addAll(
        await validateIntroductionNotificationLifecycleObservations(evidence),
      );
    } on ContactTransferCaptureUnavailable {
      // Missing capture is NOT RUN; it is not an application failure.
    } on Object {
      failures.add(
        'IN-008 evidence is incomplete, malformed or not independently bound',
      );
    }
  }
  writeContactTransferNativeResult(
    journeyId: 'IN-008',
    ids: ['IN-008'],
    captureGap:
        'Existing Android acceptance campaign covers terminated introducer copy/tap only; '
        'no existing producer covers recipient offers plus foreground/background/real-lock/stale/no-consent matrix.',
    prerequisites: [
      'Reuse run_intro_accept_notification_sims.dart and its exact Android copy/node/acceptance predicates only for their documented subset.',
      'Future fapp captures real recipient offers and mutual acceptance notifications, actual OS lifecycle/tray actions and current persisted consent state.',
      'Bind captures to available target kinds/artifacts and independent source/run; unavailable platform legs are N/A, never assumed parity.',
    ],
    failures: failures,
    evaluated: evaluated,
  );
}
