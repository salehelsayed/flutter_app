import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final harness = File(
    'integration_test/scripts/capture_1to1_reaction_head_provenance.dart',
  ).readAsStringSync();
  final appProof = File(
    'lib/core/debug/intro_e2e_runner.dart',
  ).readAsStringSync();
  final applicationRootSource = File(
    'lib/app/application_root.dart',
  ).readAsStringSync();
  final routeDiagnostics = File(
    'lib/core/notifications/initial_local_notification_route_diagnostics.dart',
  ).readAsStringSync();
  final proofSupport = File(
    'integration_test/scripts/reaction_notification_proof_support.dart',
  ).readAsStringSync();

  test('direct-text mode is explicit and exact Gate A artifact bound', () {
    expect(harness, contains("args.contains('--direct-text-only')"));
    expect(harness, contains('--gate-a-artifact <json> and its exact'));
    expect(harness, contains('--gate-a-artifact-sha256 <sha256>'));
    expect(
      harness,
      contains('--dart-define=MKNOON_DIRECT_TEXT_RELAY_TOKEN_PROOF=true'),
    );
    expect(appProof, contains("FirebaseMessaging.instance.getToken"));
    expect(appProof, contains("'tokenSha256Matched': true"));
    expect(appProof, contains("'gateAArtifactSha256'"));
    expect(appProof, contains("'accountIdentitySha256'"));
    expect(appProof, contains("'transportIdentitySha256'"));
    expect(appProof, contains('directTextRelayTokenProofCommandSchemaV2'));
    expect(appProof, contains('directTextRelayTokenProofReceiptSchemaV2'));
    expect(appProof, contains("'authorizationArtifactSha256'"));
    expect(appProof, contains("'gateACommandGenerationId'"));
    expect(appProof, contains("'containsSecrets': false"));
    expect(harness, contains('direct_text_token_registration.log'));
    expect(harness, contains("'recipientAccountIdentitySha256'"));
    expect(harness, contains("'registrationEvidencePath'"));
    expect(
      harness,
      contains(
        "gateAAuthorization['authorizationKind'] !=\n"
        '          backgroundCryptoCurrentTokenAuthorizationKind',
      ),
    );
  });

  test('Gate B uses only the exact current-token v2 command and receipt', () {
    final stageStart = harness.indexOf(
      'Future<void> _stageDirectTextTokenProofCommand()',
    );
    final stageEnd = harness.indexOf(
      'Future<void> _waitForDirectTextTokenProofReceipt()',
      stageStart,
    );
    final stage = harness.substring(stageStart, stageEnd);
    expect(stage, contains('directTextRelayTokenProofCommandSchemaV2'));
    expect(stage, contains("authorization['authorizationKind']"));
    expect(stage, contains("authorization['authorizationArtifactSha256']"));
    expect(stage, contains("authorization['gateACommandGenerationId']"));
    expect(stage, contains("authorization['gateAArtifactSha256']"));
    expect(stage, contains("authorization['accountIdentitySha256']"));
    expect(stage, contains("authorization['transportIdentitySha256']"));
    expect(stage, isNot(contains("'refreshArtifactSha256'")));
    expect(stage, isNot(contains("'tokenGenerationId'")));

    final receiptEnd = harness.indexOf(
      'Future<BackgroundCryptoTransportResult>',
      stageEnd,
    );
    final receipt = harness.substring(stageEnd, receiptEnd);
    expect(receipt, contains('parseDirectTextRelayTokenProofReceiptV2('));
    expect(receipt, contains('authorizationArtifactSha256:'));
    expect(receipt, contains('gateACommandGenerationId:'));
    expect(receipt, isNot(contains('refreshArtifactSha256:')));
    expect(receipt, isNot(contains('tokenGenerationId:')));
  });

  test('authorization is fresh at staging, receipt, sends, and pass', () {
    final stage = harness.indexOf("'command_staging'");
    final receiptWait = harness.indexOf("'receipt_wait_start'");
    final receiptRead = harness.indexOf(
      "'current Firebase token SHA-256 receipt'",
    );
    final receiptAcceptance = harness.indexOf("'receipt_acceptance'");
    final sendAcceptance = harness.indexOf(
      "'message_\${_directTextRelaySends.length + 1}_send'",
    );
    final restore = harness.indexOf('await _restoreExactInitialDeviceState();');
    final passAcceptance = harness.indexOf("'authorization_before_pass'");
    final passWrite = harness.indexOf('_writeDirectTextPassedArtifact(');

    expect(stage, greaterThan(0));
    expect(receiptWait, greaterThan(stage));
    expect(receiptRead, greaterThan(receiptWait));
    expect(receiptAcceptance, greaterThan(receiptRead));
    expect(sendAcceptance, greaterThan(receiptAcceptance));
    expect(restore, greaterThan(0));
    expect(passAcceptance, greaterThan(restore));
    expect(passWrite, greaterThan(passAcceptance));
  });

  test('command-stage authorization is revalidated after awaited cleanup', () {
    final start = harness.indexOf(
      'Future<void> _stageDirectTextTokenProofCommand()',
    );
    final end = harness.indexOf(
      'Future<void> _waitForDirectTextTokenProofReceipt()',
      start,
    );
    final method = harness.substring(start, end);
    final cleanup = method.indexOf(
      'await _removeAndVerifyDirectTextTokenProofFiles();',
    );
    final revalidation = method.indexOf(
      "await _revalidateGateAAuthorization(\n      'command_staging',",
    );
    final construction = method.indexOf('final now = DateTime.now().toUtc();');
    final copy = method.indexOf(
      'await copyBackgroundCryptoCommandBytesToAppPrivateFile(',
    );

    expect(cleanup, greaterThan(0));
    expect(revalidation, greaterThan(cleanup));
    expect(construction, greaterThan(revalidation));
    expect(copy, greaterThan(construction));
    expect(
      method.substring(revalidation + 'await '.length, copy),
      isNot(contains('await ')),
    );
  });

  test('each public-relay send occurs with a killed recipient', () {
    final start = harness.indexOf(
      'Future<Map<String, Object?>> _captureUnreadLifecycle({',
    );
    final end = harness.indexOf(
      'Future<void> _reopenRecipientAtOrbit()',
      start,
    );
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final method = harness.substring(start, end);
    expect(
      RegExp(r'await _terminateRecipient\(\)').allMatches(method).length,
      3,
    );
    expect(
      RegExp(r'await _sendUiMessageFromSender\(').allMatches(method).length,
      2,
    );
    expect(
      method.indexOf('await _terminateRecipient()'),
      lessThan(method.indexOf('await _sendUiMessageFromSender(')),
    );
    expect(
      method,
      contains("'recipientKilledBeforeEachSend': publicRelayProof"),
    );
    expect(
      method,
      contains("'recipientKilledBeforeNotificationTap': publicRelayProof"),
    );
  });

  test(
    'recipient termination uses bounded stop-app fallback without force-stop',
    () {
      final start = harness.indexOf('Future<void> _terminateRecipient()');
      final end = harness.indexOf(
        'Future<bool> _recipientProcessAndActivityAbsentWithin',
        start,
      );
      final method = harness.substring(start, end);
      final kill = method.indexOf("'kill'");
      final stopApp = method.indexOf("'stop-app'");
      expect(kill, greaterThan(0));
      expect(stopApp, greaterThan(kill));
      expect(method, contains("['cmd', 'activity', 'stop-app', appPackage]"));
      expect(method, contains('_recipientProcessAndActivityAbsentWithin'));
      expect(method, isNot(contains('_recipientProcessAbsentWithin')));
      expect(method, contains('_waitForProcessAndActivityAbsent'));
      expect(method, isNot(contains("'force-stop'")));
    },
  );

  test('termination fallback decision checks both process and activity', () {
    final start = harness.indexOf(
      'Future<bool> _recipientProcessAndActivityAbsentWithin',
    );
    final end = harness.indexOf(
      'Future<String> _waitForReactionSuccess',
      start,
    );
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final method = harness.substring(start, end);
    expect(method, contains('_requireProcessAndActivityAbsent(recipientId)'));
    expect(method, contains('on _CampaignFailure'));
    expect(method, contains('return false'));
  });

  test(
    'bounded relay evidence requires ordered store and provider success',
    () {
      final start = harness.indexOf('Future<void> _sendUiMessageFromSender(');
      final end = harness.indexOf('Future<void> _waitForOrbitUnread', start);
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));
      final method = harness.substring(start, end);
      expect(method, contains('await _waitForRelayStore(since)'));
      expect(method, contains('_providerObservationDelay'));
      expect(method, contains('!capture.relayMatchedEvent'));
      expect(method, contains('!capture.providerMatchedEvent'));
      expect(method, contains('capture.providerFailureMatched'));
      expect(method, contains('pushIndex <= storeIndex'));
      expect(method, contains('_directTextRelaySends.add('));
    },
  );

  test(
    'cold local tap on production main requires exact route timing and drain proof',
    () {
      final normalInstall = harness.indexOf(
        'await _installApk(recipientId, _build!.normalApk);',
      );
      final directCapture = harness.indexOf(
        'final unreadLifecycle = await _captureUnreadLifecycle(',
      );
      expect(normalInstall, greaterThan(0));
      expect(directCapture, greaterThan(normalInstall));

      final lifecycleStart = harness.indexOf(
        'Future<Map<String, Object?>> _captureUnreadLifecycle({',
      );
      final lifecycleEnd = harness.indexOf(
        'Future<void> _reopenRecipientAtOrbit()',
        lifecycleStart,
      );
      final lifecycle = harness.substring(lifecycleStart, lifecycleEnd);
      final finalKill = lifecycle.lastIndexOf('await _terminateRecipient()');
      final tap = lifecycle.indexOf('await _tapAndClassifyRoute(');
      expect(finalKill, greaterThan(0));
      expect(tap, greaterThan(finalKill));
      expect(
        lifecycle,
        contains('expectedPeerId: publicRelayProof ? sender.peerId : null'),
      );
      expect(lifecycle, contains('requireColdLocalProof: publicRelayProof'));
      expect(
        lifecycle,
        contains(
          "'coldLocalNotificationOpen': coldLocalOpenEvidence!.toJson()",
        ),
      );

      final tapStart = harness.indexOf('Future<String> _tapAndClassifyRoute(');
      final tapEnd = harness.indexOf(
        'Future<(int, int)> _waitForNotificationCardInShade(',
        tapStart,
      );
      final tapMethod = harness.substring(tapStart, tapEnd);
      final parse = tapMethod.indexOf(
        'parseAndroidColdLocalNotificationOpenEvidence(',
      );
      final terminal = tapMethod.indexOf('evidence.hasTerminalFailure');
      final complete = tapMethod.indexOf('evidence.isComplete');
      expect(parse, greaterThan(0));
      expect(terminal, greaterThan(parse));
      expect(complete, greaterThan(terminal));
      expect(tapMethod, contains('tappedRoutePayload: card.routePayload'));
      expect(tapMethod, contains('const Duration(seconds: 90)'));
      expect(
        tapMethod.substring(parse, complete),
        isNot(contains('CONVERSATION_NOTIFICATION_ROUTE_ALREADY_ACTIVE')),
      );

      final passBoundary = harness.indexOf(
        'void _writeDirectTextPassedArtifact({',
      );
      final routeFilter = harness.indexOf(
        'String _notificationRouteLines(String logcat)',
      );
      expect(
        harness.substring(passBoundary, routeFilter),
        contains(
          '_directTextColdLocalNotificationOpenEvidence?.isComplete != true',
        ),
      );
      final filter = harness.substring(routeFilter);
      expect(
        filter,
        contains('sanitizeAndroidColdLocalNotificationRouteEvidence(logcat)'),
      );
      expect(proofSupport, contains("line.contains('CHAT_MSG_LOAD_PAGE_')"));
      expect(
        proofSupport,
        contains("line.contains('CONV_FL_NOTIF_DRAIN_REFETCH')"),
      );
      expect(
        proofSupport,
        contains("line.contains('CONV_FL_DRAIN_REFETCH_ERROR')"),
      );
    },
  );

  test('cold local proof is bound to privacy-safe consumed-route marker', () {
    expect(
      routeDiagnostics,
      contains("'INITIAL_LOCAL_NOTIFICATION_ROUTE_PARSED'"),
    );
    for (final field in const <String>[
      'payloadSha256',
      'payloadUtf8Length',
      'routeKind',
      'peerSha256',
      'canonicalPayloadMatched',
    ]) {
      expect(routeDiagnostics, contains("'$field'"));
      expect(proofSupport, contains("'$field'"));
    }
    expect(routeDiagnostics, isNot(contains("'payload': normalizedPayload")));
    expect(routeDiagnostics, isNot(contains("'peerId': normalizedPeer")));

    final initialOpenStart = applicationRootSource.indexOf(
      'Future<void> _handleInitialLocalNotificationLaunch() async',
    );
    final warmOpenStart = applicationRootSource.indexOf(
      'Future<void> _onNotificationTap(String payload) async',
      initialOpenStart,
    );
    final initialOpen = applicationRootSource.substring(
      initialOpenStart,
      warmOpenStart,
    );
    final marker = initialOpen.indexOf(
      'event: initialLocalNotificationRouteParsedEvent',
    );
    final prepare = initialOpen.indexOf(
      'preparedContext = _createNotificationOpenRouteContext(target)',
    );
    expect(marker, greaterThan(0));
    expect(prepare, greaterThan(marker));

    expect(
      proofSupport,
      isNot(contains('tappedRoutePayload?.trim() == normalizedPeerId')),
    );
    expect(proofSupport, contains('parsedRouteMarkerCount == 1 &&'));
    expect(proofSupport, contains('matchingParsedRouteMarkerCount == 1'));
    expect(proofSupport, contains("'CHAT_MSG_LOAD_PAGE_REDACTED'"));
    expect(proofSupport, contains("'NOTIFICATION_ROUTE_EVIDENCE_REDACTED'"));
    expect(
      proofSupport,
      contains('_androidColdLocalNotificationEvidenceDetails'),
    );
    expect(
      proofSupport,
      isNot(
        contains('if (!line.contains(\'CHAT_MSG_LOAD_PAGE_\')) return line'),
      ),
    );
    expect(proofSupport, isNot(contains("safeDetails['contactPeerId']")));
  });

  test('cleanup restores package, APK bytes, private data, and permission', () {
    final capture = harness.indexOf(
      'Future<void> _captureInitialDeviceState()',
    );
    final restore = harness.indexOf(
      'Future<void> _restoreExactInitialDeviceState()',
    );
    final artifact = harness.indexOf('void _writeDirectTextPassedArtifact(');
    expect(capture, greaterThan(0));
    expect(restore, greaterThan(capture));
    expect(artifact, greaterThan(restore));
    final cleanup = harness.substring(capture, artifact);
    expect(cleanup, contains("'pull'"));
    expect(cleanup, contains("'install-multiple'"));
    expect(cleanup, contains("'uninstall'"));
    expect(cleanup, contains("'tar'"));
    expect(cleanup, contains("'sha256sum'"));
    expect(cleanup, contains('256 * 1024'));
    expect(cleanup, contains("expected ? 'grant' : 'revoke'"));
    expect(cleanup, contains("'pidof'"));
    expect(
      cleanup,
      contains("'dumpsys',\n      'activity',\n      'activities'"),
    );
    expect(cleanup, contains("'%a:%u:%g:%s'"));
    expect(cleanup, contains('_verifyPrivateBackupBeforeRestore'));
    expect(
      cleanup,
      contains('Private backup changed before destructive restoration'),
    );
    expect(cleanup, contains("failures.add('host_build_cleanup')"));
    expect(cleanup, contains('recovery backups retained'));
    expect(cleanup, contains('Host state backup survived restoration'));
  });

  test(
    'restoration quiescence and host cleanup are fail-closed and aggregated',
    () {
      final oneStart = harness.indexOf('Future<void> _restoreOneDeviceState(');
      final oneEnd = harness.indexOf(
        'Future<void> _finishHostRestoration()',
        oneStart,
      );
      final one = harness.substring(oneStart, oneEnd);
      final firstForceStop = one.indexOf("'force-stop'");
      final firstQuiescence = one.indexOf(
        'await _waitForProcessAndActivityAbsent(deviceId)',
      );
      final restoreBranch = one.indexOf(
        'if (safeToRestore && !state.installed)',
      );
      expect(firstForceStop, greaterThan(0));
      expect(firstQuiescence, greaterThan(firstForceStop));
      expect(restoreBranch, greaterThan(firstQuiescence));
      expect(
        one.substring(firstForceStop, firstQuiescence),
        isNot(contains('allowFail: true')),
      );

      final privateStart = harness.indexOf(
        'Future<void> _restorePrivateAppData(',
      );
      final privateEnd = harness.indexOf(
        'Future<void> _verifyPrivateBackupBeforeRestore(',
        privateStart,
      );
      final privateRestore = harness.substring(privateStart, privateEnd);
      expect(
        privateRestore.indexOf('_waitForProcessAndActivityAbsent'),
        lessThan(privateRestore.indexOf('_verifyPrivateBackupBeforeRestore')),
      );
      expect(
        privateRestore.indexOf('_verifyPrivateBackupBeforeRestore'),
        lessThan(privateRestore.indexOf("'rm'")),
      );

      final hostStart = harness.indexOf(
        'Future<void> _finishHostRestoration()',
      );
      final hostEnd = harness.indexOf(
        'Future<void> _restoreOriginalApks(',
        hostStart,
      );
      final host = harness.substring(hostStart, hostEnd);
      expect(
        host.indexOf('await _cleanupGeneratedBuildArtifacts()'),
        lessThan(host.indexOf('backup.delete(recursive: true)')),
      );
      expect(host, contains("'e2e_apk': _build?.e2eApk"));
      expect(host, contains("'normal_apk': _build?.normalApk"));
      expect(host, contains("'metadata': File("));
      expect(host, contains('for (final entry in files.entries)'));
      expect(host, contains('recovery backup retained'));
    },
  );

  test(
    'exact APK metadata repair precedes canonical hash and backup deletion',
    () {
      final privateStart = harness.indexOf(
        'Future<void> _restorePrivateAppData(',
      );
      final privateEnd = harness.indexOf(
        'Future<void> _repairPackageMetadataAfterPrivateRestore(',
        privateStart,
      );
      final privateRestore = harness.substring(privateStart, privateEnd);
      final extract = privateRestore.indexOf("'tar',\n      '-xf'");
      final repair = privateRestore.indexOf(
        '_repairPackageMetadataAfterPrivateRestore',
      );
      final canonical = privateRestore.indexOf('restored.tar');
      final compare = privateRestore.indexOf('restoredSha != originalSha');
      final backupDelete = privateRestore.lastIndexOf("'rm'");
      expect(extract, greaterThan(0));
      expect(repair, greaterThan(extract));
      expect(canonical, greaterThan(repair));
      expect(compare, greaterThan(canonical));
      expect(backupDelete, greaterThan(compare));

      final repairStart = privateEnd;
      final repairEnd = harness.indexOf(
        'Future<void> _restoreNotificationPermission(',
        repairStart,
      );
      final metadataRepair = harness.substring(repairStart, repairEnd);
      expect(metadataRepair, contains('_restoreOriginalApks(deviceId, state)'));
      expect(metadataRepair, contains('_waitForProcessAndActivityAbsent'));
      expect(metadataRepair, contains('_restoreNotificationPermission'));
      expect(metadataRepair, contains('versionCode='));
      expect(metadataRepair, contains('versionName='));
      expect(metadataRepair, contains("<String>['cache', 'code_cache']"));
      expect(metadataRepair, isNot(contains("'uninstall'")));
      expect(metadataRepair, isNot(contains("'clear'")));
      expect(metadataRepair, isNot(contains("'start'")));
    },
  );

  test(
    'body and cleanup failures preserve primary causality in all combinations',
    () {
      final runStart = harness.indexOf('Future<void> run() async {');
      final runEnd = harness.indexOf(
        'void writeFailure(_CampaignFailure failure',
        runStart,
      );
      final run = harness.substring(runStart, runEnd);
      final bodyCatch = run.indexOf(
        'on _CampaignFailure catch (failure, stackTrace)',
      );
      // Keep this structural check independent of dartfmt's wrapping of the
      // restoration predicate. The first try after the body catch owns cleanup.
      final cleanupTry = run.indexOf('try {', bodyCatch);
      final composite = run.indexOf('cleanupFailure: cleanup');
      final originalStack = run.indexOf('Error.throwWithStackTrace(');
      final cleanupOnly = run.indexOf('if (cleanup != null)');
      expect(bodyCatch, greaterThan(0));
      expect(cleanupTry, greaterThan(bodyCatch));
      expect(composite, greaterThan(cleanupTry));
      expect(originalStack, greaterThan(composite));
      expect(cleanupOnly, greaterThan(originalStack));
      expect(run, contains('primary.stage'));
      expect(run, contains('primary.message'));
      expect(run, contains('primaryStackTrace ?? StackTrace.current'));
      expect(run, contains('throw cleanup;'));

      final failureWriter = harness.substring(runEnd);
      expect(failureWriter, contains("'stage': failure.stage"));
      expect(failureWriter, contains("'cleanupFailure':"));
      expect(failureWriter, contains("'stage': failure.cleanupFailure!.stage"));
      expect(
        failureWriter,
        contains("'error': sanitize(failure.cleanupFailure!.message)"),
      );
    },
  );

  test('pass artifact disclaims attribution to the earlier Gate A frame', () {
    expect(
      harness,
      contains("'earlierRegistrationFrameExactCausalAttribution': false"),
    );
    expect(harness, contains("'relayPersistenceClaimFromEarlierGate': false"));
    expect(harness, contains("'rawFirebaseTokenPersisted': false"));
    expect(
      harness,
      contains(
        "receipt['authorizationArtifactSha256'] !=\n"
        "            gateAAuthorization?['authorizationArtifactSha256']",
      ),
    );
    expect(
      harness,
      contains(
        "receipt['gateACommandGenerationId'] !=\n"
        "            gateAAuthorization?['gateACommandGenerationId']",
      ),
    );
    expect(
      harness,
      contains("'stableConversationNotificationIdAcrossDismissAndResurface'"),
    );
    expect(harness, isNot(contains("'replacementObserved': publicRelayProof")));
  });
}
