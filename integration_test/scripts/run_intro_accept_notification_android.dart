#!/usr/bin/env dart

/// Plan 252 D1/D2: three-party intro-acceptance notification/tap device proof.
///
/// Proves on a real relay + real Android FCM boundary that:
///  - each acceptance push shows `Introduction accepted` /
///    `Someone accepted an introduction involving you.` (never `New Message`),
///  - a terminated-app notification tap cold-launches introducer A into the
///    A-B conversation (`finalPeer=<B prefix>`), first with
///    `statusContext=b_accept_recorded` (B accepts) and then
///    `statusContext=bc_connected` (C accepts).
///
/// Scenarios:
///  - `physical_introducer`: A = physical Android, B = Android emulator,
///    C = a second Android emulator for the sims-major adapter (legacy direct
///    runs may still supply an iOS simulator).
///  - `emulator_introducer`:  A = Android emulator, B = physical Android,
///    C = a second Android emulator for the sims-major adapter (legacy direct
///    runs may still supply an iOS simulator).
///
/// The orchestrator performs ALL setup/actions/taps itself through the
/// debug-build intro E2E config channel (`intro_e2e_config.json`), `adb`, and
/// `simctl`. It never uses `am force-stop` (which cancels notifications and
/// stops the package): app termination is `am kill` + empty-`pidof`
/// verification, keeping the push/tap boundary faithful. Notification taps are
/// bounded-node taps: the shade is expanded, the UIAutomator XML dump is
/// searched for this app's node with the exact acceptance title, and the tap
/// lands on that node's bounds center. Fixed screen coordinates are forbidden.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../support/android_app_state_guard.dart';
import '_android_app_package.dart';

const _iosBundleId = 'com.mknoon.app';
const _acceptTitle = 'Introduction accepted';
const _acceptBody = 'Someone accepted an introduction involving you.';
const _forbiddenTitle = 'New Message';
const _redirectEvent = 'INTRO_ACCEPT_NOTIFICATION_CONVERSATION_REDIRECT';
const _navErrorEvents = [
  'NOTIFICATION_TAP_NAV_ERROR',
  'INITIAL_LOCAL_NOTIFICATION_ROUTE_ERROR',
];
const Duration introAcceptanceCampaignBudget = Duration(minutes: 24);

typedef IntroDeadlineClock = DateTime Function();

List<({int left, int top, int right, int bottom})>
exactNotificationTitleNodeBounds(String xml, String title) {
  final bounds = <({int left, int top, int right, int bottom})>[];
  for (final match in RegExp(r'<node[^>]*/?>').allMatches(xml)) {
    final node = match.group(0)!;
    if (!node.contains('text="$title"')) {
      continue;
    }
    final boundsMatch = RegExp(
      r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
    ).firstMatch(node);
    if (boundsMatch == null) {
      continue;
    }
    bounds.add((
      left: int.parse(boundsMatch.group(1)!),
      top: int.parse(boundsMatch.group(2)!),
      right: int.parse(boundsMatch.group(3)!),
      bottom: int.parse(boundsMatch.group(4)!),
    ));
  }
  return bounds;
}

/// Accepts ActivityManager's successful launch result and its bounded
/// `am start -W` wait timeout.
///
/// A wait timeout does not mean the launch intent failed: the process can keep
/// starting after ActivityManager's synchronous wait expires. The campaign's
/// next phase still requires a fresh identity export from every launched app,
/// so accepting this provisional status cannot turn a non-launch into proof.
bool isAndroidActivityStartAccepted(String output) {
  return RegExp(
    r'^Status:[ \t]+(?:ok|timeout)[ \t]*\r?$',
    multiLine: true,
  ).hasMatch(output);
}

/// One absolute campaign deadline with phase allocations underneath it.
///
/// Beginning a new phase grants that phase its declared allocation, capped by
/// the campaign deadline. Repeated waits inside the same phase consume the
/// same deadline; they cannot each obtain a fresh timeout.
final class IntroCampaignDeadline {
  IntroCampaignDeadline({
    required this.campaignDeadline,
    IntroDeadlineClock? now,
  }) : _now = now ?? DateTime.now;

  final DateTime campaignDeadline;
  final IntroDeadlineClock _now;
  DateTime? _phaseDeadline;
  String? _phaseName;

  String? get phaseName => _phaseName;

  void beginPhase(String name, Duration budget) {
    if (name.trim().isEmpty || budget <= Duration.zero) {
      throw ArgumentError('Intro campaign phases require a name and budget.');
    }
    final allocated = _now().add(budget);
    _phaseName = name;
    _phaseDeadline = allocated.isBefore(campaignDeadline)
        ? allocated
        : campaignDeadline;
  }

  Duration remaining({Duration? ceiling}) {
    final phaseDeadline = _phaseDeadline ?? campaignDeadline;
    final effectiveDeadline = phaseDeadline.isBefore(campaignDeadline)
        ? phaseDeadline
        : campaignDeadline;
    final value = effectiveDeadline.difference(_now());
    if (value <= Duration.zero) return Duration.zero;
    if (ceiling != null && ceiling < value) return ceiling;
    return value;
  }
}

/// True only for the explicit acceptance completion belonging to [stepId].
///
/// Health checks and inbox replay occur before every Intro E2E action. Their
/// completion is not acceptance evidence, even when it is otherwise healthy.
bool isIntroAcceptanceResult(
  Map<String, dynamic> result, {
  required String stepId,
}) {
  if (result['stepId'] != stepId ||
      result['status'] != 'complete' ||
      result['success'] != true) {
    return false;
  }
  final action = result['introAction'];
  final custody = result['introDeliveryCustody'];
  if (action is! Map || custody is! Map || action['action'] != 'accept_all') {
    return false;
  }
  final actedOn = action['actedOn'];
  if (actedOn is! List || actedOn.isEmpty) return false;
  final introductionIds = actedOn.whereType<String>().where(
    (value) => value.isNotEmpty,
  );
  final uniqueIntroductionIds = introductionIds.toSet();
  if (uniqueIntroductionIds.length != actedOn.length) return false;
  final custodyCount = custody['introductionCount'];
  return custody['status'] == 'confirmed' &&
      custodyCount is int &&
      custodyCount >= uniqueIntroductionIds.length;
}

/// Shares one cleanup operation across timeout, late-event, and finally paths.
final class IntroLateEventCleanup {
  Future<void>? _operation;

  Future<void> run(Future<void> Function() cleanup) {
    return _operation ??= Future<void>.sync(cleanup);
  }
}

final class _CommandResult {
  const _CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

class _Scenario {
  const _Scenario({
    required this.id,
    required this.testCase,
    required this.summary,
  });

  final String id;
  final String testCase;
  final String summary;
}

const List<_Scenario> _scenarios = <_Scenario>[
  _Scenario(
    id: 'physical_introducer',
    testCase: 'TC-12',
    summary:
        'physical Android introducer; Android emulators B/C acceptances '
        'show acceptance copy; automated terminated-app taps open A-B',
  ),
  _Scenario(
    id: 'emulator_introducer',
    testCase: 'TC-13',
    summary:
        'Android emulator introducer; physical B + Android emulator C '
        'acceptances '
        'show acceptance copy; automated terminated-app taps open A-B',
  ),
];

late String _appPackage;
bool _verbose = false;

Future<void> main(List<String> args) async {
  _appPackage = resolveAndroidAppPackage();
  final listScenarios = args.contains('--list-scenarios');
  final scenarioArg = _valueFor(args, '--scenario') ?? 'all';
  _verbose = args.contains('--verbose');

  final selected = scenarioArg == 'all'
      ? _scenarios
      : _scenarios.where((item) => item.id == scenarioArg).toList();
  if (selected.isEmpty) {
    stderr.writeln(
      'Unknown --scenario "$scenarioArg". Expected all or one of: '
      '${_scenarios.map((item) => item.id).join(', ')}',
    );
    exit(64);
  }

  if (listScenarios) {
    for (final item in selected) {
      stdout.writeln(item.id);
    }
    return;
  }

  final introducer = _valueFor(args, '--introducer');
  final recipient = _valueFor(args, '--recipient');
  final introducedAndroid = _valueFor(args, '--introduced-android');
  final introduced = introducedAndroid ?? _valueFor(args, '--introduced');
  final preparedArtifact = _valueFor(args, '--artifact');
  final campaignDeadlineValue = _valueFor(args, '--campaign-deadline-epoch-ms');
  final campaignDeadlineEpochMs = campaignDeadlineValue == null
      ? null
      : int.tryParse(campaignDeadlineValue);
  if (scenarioArg == 'all' ||
      introducer == null ||
      recipient == null ||
      introduced == null ||
      (campaignDeadlineValue != null && campaignDeadlineEpochMs == null)) {
    stderr.writeln(
      'Usage: dart run integration_test/scripts/'
      'run_intro_accept_notification_android.dart '
      '--scenario <physical_introducer|emulator_introducer> '
      '--introducer <android-id> --recipient <android-id> '
      '--introduced-android <second-android-emulator-id> '
      '--artifact <central-prebuilt-apk> [--artifact-dir <dir>] '
      '[--campaign-deadline-epoch-ms <utc-epoch-ms>] [--verbose]',
    );
    stderr.writeln(
      'All three sims-major parties are Android adb targets. A legacy direct '
      'run may use --introduced <ios-sim-udid> for party C.',
    );
    exit(64);
  }

  final scenario = selected.single;
  final artifactDir = Directory(
    _valueFor(args, '--artifact-dir') ??
        'build/intro_accept_notification_proof/${scenario.id}',
  )..createSync(recursive: true);
  final campaignDeadline = campaignDeadlineEpochMs == null
      ? DateTime.now().add(introAcceptanceCampaignBudget)
      : DateTime.fromMillisecondsSinceEpoch(
          campaignDeadlineEpochMs,
          isUtc: true,
        );
  if (!campaignDeadline.isAfter(DateTime.now())) {
    stderr.writeln('FAIL: intro campaign deadline is already expired');
    exit(64);
  }

  try {
    final campaign = _Campaign(
      scenario: scenario,
      introducerAndroidId: introducer,
      recipientAndroidId: recipient,
      introducedDeviceId: introduced,
      introducedIsIos: introducedAndroid == null,
      preparedArtifact: preparedArtifact == null
          ? null
          : File(preparedArtifact).absolute,
      statePreparedByParent: args.contains('--android-state-prepared'),
      artifactDir: artifactDir,
      campaignDeadline: campaignDeadline,
    );
    await campaign.run();
    stdout.writeln('PASS: ${scenario.id} artifacts at ${artifactDir.path}');
  } on _CampaignFailure catch (failure) {
    stderr.writeln('FAIL: ${failure.message}');
    exit(1);
  }
}

class _CampaignFailure implements Exception {
  _CampaignFailure(this.message);
  final String message;
}

class _Party {
  _Party({required this.role, required this.deviceId, required this.isIos});

  final String role; // A / B / C
  final String deviceId;
  final bool isIos;
  String peerId = '';
  String username = '';
  String qrPayload = '';
  String? mlKemPublicKey;

  String get peerPrefix =>
      peerId.length > 12 ? peerId.substring(0, 12) : peerId;
}

class _Campaign {
  static const Duration _preflightBudget = Duration(minutes: 2);
  static const Duration _installBudget = Duration(minutes: 4);
  static const Duration _bootstrapBudget = Duration(minutes: 5);
  static const Duration _fixtureBudget = Duration(minutes: 7);
  static const Duration _acceptanceBudget = Duration(minutes: 6);
  static const Duration _finalizationBudget = Duration(minutes: 2);

  _Campaign({
    required this.scenario,
    required this.introducerAndroidId,
    required this.recipientAndroidId,
    required this.introducedDeviceId,
    required this.introducedIsIos,
    required this.preparedArtifact,
    required this.statePreparedByParent,
    required this.artifactDir,
    required DateTime campaignDeadline,
  }) : deadline = IntroCampaignDeadline(campaignDeadline: campaignDeadline),
       a = _Party(role: 'A', deviceId: introducerAndroidId, isIos: false),
       b = _Party(role: 'B', deviceId: recipientAndroidId, isIos: false),
       c = _Party(
         role: 'C',
         deviceId: introducedDeviceId,
         isIos: introducedIsIos,
       );

  final _Scenario scenario;
  final String introducerAndroidId;
  final String recipientAndroidId;
  final String introducedDeviceId;
  final bool introducedIsIos;
  final File? preparedArtifact;
  final bool statePreparedByParent;
  final Directory artifactDir;
  final IntroCampaignDeadline deadline;

  final _Party a;
  final _Party b;
  final _Party c;

  final Map<String, bool> checks = <String, bool>{};
  final IntroLateEventCleanup _lateEventCleanup = IntroLateEventCleanup();
  String copyExtractor = '';

  Future<void> run() async {
    AndroidAppStateGuard? directStateGuard;
    await _runPhase('preflight', _preflightBudget, () async {
      await _verifyTargetsAvailable();
      if (!statePreparedByParent) {
        try {
          directStateGuard = await AndroidAppStateGuard.capture(
            devices: <String>[a.deviceId, b.deviceId, if (!c.isIos) c.deviceId],
            packageName: _appPackage,
            backupLabel: 'intro-accept-direct',
          );
        } on AndroidAppStateBlocked catch (error) {
          throw _CampaignFailure(error.detail);
        } on AndroidAppStateFailure catch (error) {
          throw _CampaignFailure(error.detail);
        }
      }
    });
    try {
      await _runPhase(
        'install',
        _installBudget,
        () => _installPreparedArtifactIfPresent(directStateGuard),
      );
      await _runPhase('bootstrap', _bootstrapBudget, () async {
        await _launchAll();
        await _collectIdentities();
      });
      await _runPhase('fixture', _fixtureBudget, () async {
        await _setupContacts();
        await _sendIntroduction();
      });

      // Leg 1: B accepts while A is terminated.
      await _runPhase(
        'b_accept',
        _acceptanceBudget,
        () => _acceptanceLeg(
          responder: b,
          legLabel: 'b_accept',
          expectedStatusContext: 'b_accept_recorded',
        ),
      );
      await _dismissExactAcceptanceCards();

      // Leg 2: C accepts while A is terminated again.
      await _runPhase(
        'c_accept',
        _acceptanceBudget,
        () => _acceptanceLeg(
          responder: c,
          legLabel: 'c_accept',
          expectedStatusContext: 'bc_connected',
        ),
      );

      await _runPhase(
        'finalize',
        _finalizationBudget,
        _assertNoNavigationErrors,
      );
    } finally {
      await _cleanupAfterLateEvents();
      try {
        await directStateGuard?.restoreAll();
      } on AndroidAppStateFailure catch (error) {
        throw _CampaignFailure(error.detail);
      }
    }
    _writeArtifact();
  }

  Future<T> _runPhase<T>(
    String name,
    Duration phaseBudget,
    Future<T> Function() action,
  ) {
    deadline.beginPhase(name, phaseBudget);
    if (deadline.remaining() <= Duration.zero) {
      throw _CampaignFailure(
        'intro campaign deadline expired before phase $name',
      );
    }
    _log(
      'phase $name started with '
      '${deadline.remaining().inMilliseconds}ms remaining',
    );
    return action();
  }

  // ---- Phase 0: discovery -------------------------------------------------

  Future<void> _verifyTargetsAvailable() async {
    final adbDevices = await _run('adb', ['devices']);
    final androidParties = <_Party>[a, b, if (!c.isIos) c];
    if (androidParties.map((party) => party.deviceId).toSet().length !=
        androidParties.length) {
      throw _CampaignFailure('All Android party target IDs must be distinct.');
    }
    for (final android in androidParties) {
      if (!adbDevices.contains(android.deviceId)) {
        throw _CampaignFailure(
          'Android target ${android.deviceId} (${android.role}) is not '
          'listed by `adb devices`. Re-run discovery and substitute a live '
          'ID; an unavailable target is N/A under project policy.',
        );
      }
    }
    if (!c.isIos) {
      final aIsEmulator = await _isAndroidEmulator(a.deviceId);
      final bIsEmulator = await _isAndroidEmulator(b.deviceId);
      final cIsEmulator = await _isAndroidEmulator(c.deviceId);
      final topologyMatches = switch (scenario.id) {
        'physical_introducer' => !aIsEmulator && bIsEmulator && cIsEmulator,
        'emulator_introducer' => aIsEmulator && !bIsEmulator && cIsEmulator,
        _ => false,
      };
      if (!topologyMatches) {
        throw _CampaignFailure(
          '${scenario.id} requires one physical Android plus two distinct '
          'Android emulators in the declared A/B/C roles.',
        );
      }
      checks['targetsDiscovered'] = true;
      return;
    }
    final simList = await _run('xcrun', [
      'simctl',
      'list',
      'devices',
      'available',
    ]);
    if (!simList.contains(introducedDeviceId)) {
      throw _CampaignFailure(
        'iOS simulator $introducedDeviceId (C) is not available. Boot it '
        'explicitly before use.',
      );
    }
    final booted = await _run('xcrun', ['simctl', 'list', 'devices']);
    if (!booted.contains('$introducedDeviceId) (Booted)')) {
      // Boot explicitly before use (idempotent when already booted).
      await _run('xcrun', [
        'simctl',
        'boot',
        introducedDeviceId,
      ], allowFail: true);
    }
    checks['targetsDiscovered'] = true;
  }

  Future<bool> _isAndroidEmulator(String deviceId) async {
    if (deviceId.startsWith('emulator-')) return true;
    final qemu = await _adbShell(deviceId, <String>[
      'getprop',
      'ro.kernel.qemu',
    ], allowFail: true);
    return qemu.trim() == '1';
  }

  Future<void> _installPreparedArtifactIfPresent(
    AndroidAppStateGuard? directStateGuard,
  ) async {
    final artifact = preparedArtifact;
    if (artifact == null) return;
    if (!artifact.existsSync()) {
      throw _CampaignFailure(
        'Prepared Android artifact is missing: ${artifact.path}',
      );
    }
    for (final party in <_Party>[a, b, if (!c.isIos) c]) {
      if (directStateGuard != null) {
        await directStateGuard.prepareFreshInstall(
          device: party.deviceId,
          artifact: artifact,
        );
      } else {
        final paths = await _adbShell(party.deviceId, <String>[
          'pm',
          'path',
          _appPackage,
        ]);
        if (!paths.contains('package:')) {
          throw _CampaignFailure(
            'Parent-prepared APK is missing on ${party.deviceId}.',
          );
        }
      }
      final sdkRaw = await _adbShell(party.deviceId, <String>[
        'getprop',
        'ro.build.version.sdk',
      ]);
      final sdk = int.tryParse(sdkRaw.trim());
      if (sdk != null && sdk >= 33) {
        await _adbShell(party.deviceId, <String>[
          'pm',
          'grant',
          _appPackage,
          'android.permission.POST_NOTIFICATIONS',
        ]);
      }
      await _writeAppDocumentsFile(
        party,
        'auto_setup.json',
        jsonEncode(<String, Object?>{'username': 'SimsIntro${party.role}'}),
      );
    }
    checks['centralPreparedArtifactInstalled'] = true;
  }

  // ---- Phase 1: launch + identity export ----------------------------------

  Future<void> _launchAll() async {
    for (final party in <_Party>[a, b, if (!c.isIos) c]) {
      final output = await _adbShell(party.deviceId, [
        'am',
        'start',
        '-W',
        '-n',
        '$_appPackage/.MainActivity',
      ]);
      if (!isAndroidActivityStartAccepted(output)) {
        throw _CampaignFailure(
          'Parent-prepared APK did not launch on ${party.deviceId}.',
        );
      }
    }
    if (c.isIos) {
      await _run('xcrun', [
        'simctl',
        'launch',
        introducedDeviceId,
        _iosBundleId,
      ], allowFail: true);
    }

    // Precondition: no stale acceptance card may remain on A before the
    // first acceptance, or copy/tap attribution would be ambiguous. The
    // foreground launch above gives the app a chance to clear delivered
    // notifications; a persisting stale card is a dirty pre-state failure.
    await _waitFor(
      'clean acceptance-card slate on A',
      const Duration(seconds: 20),
      () async {
        final cards = await _notificationTitlesOnA();
        return !cards.contains(_acceptTitle);
      },
      onTimeoutHint:
          'a stale "$_acceptTitle" card remains on ${a.deviceId}; the '
          'campaign pre-state is dirty',
    );
  }

  Future<void> _collectIdentities() async {
    for (final party in [a, b, c]) {
      final raw = await _waitForValue(
        'identity export for ${party.role}',
        const Duration(seconds: 120),
        () => _readAppDocumentsFile(party, 'intro_e2e_identity.json'),
      );
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      party.qrPayload = decoded['qrPayload'] as String;
      party.mlKemPublicKey = decoded['mlKemPublicKey'] as String?;
      final qr = jsonDecode(party.qrPayload) as Map<String, dynamic>;
      party.peerId = qr['ns'] as String;
      party.username = (qr['un'] as String?) ?? party.role;
      _log('${party.role} peer prefix: ${party.peerPrefix}');
    }
    checks['identitiesCollected'] = true;
  }

  // ---- Phase 2/3: contacts + introduction ---------------------------------

  Map<String, dynamic> _contactEntry(_Party party) {
    return {
      'qrPayload': party.qrPayload,
      'mlKemPublicKey': party.mlKemPublicKey,
    };
  }

  Future<void> _setupContacts() async {
    // A adds B and C, sends contact requests; B and C accept everything.
    await _writeConfigAndAwait(a, {
      'stepId': '252-${scenario.id}-a-contacts',
      'add_contacts': [_contactEntry(b), _contactEntry(c)],
      'send_contact_requests_for_added_contacts': true,
      'contact_settle_delay_ms': 2000,
    });
    await _writeConfigAndAwait(b, {
      'stepId': '252-${scenario.id}-b-accept-contacts',
      'contact_request_action': 'accept_all',
    });
    await _writeConfigAndAwait(c, {
      'stepId': '252-${scenario.id}-c-accept-contacts',
      'contact_request_action': 'accept_all',
    });
    checks['contactsEstablished'] = true;
  }

  Future<void> _sendIntroduction() async {
    await _writeConfigAndAwait(a, {
      'stepId': '252-${scenario.id}-a-send-intro',
      'send_introductions': [
        {
          'recipientPeerId': b.peerId,
          'friendPeerIds': [c.peerId],
        },
      ],
      'introduction_settle_delay_ms': 2000,
    });
    checks['introductionSent'] = true;
  }

  // ---- Phase 4/5: acceptance legs ------------------------------------------

  Future<void> _acceptanceLeg({
    required _Party responder,
    required String legLabel,
    required String expectedStatusContext,
  }) async {
    // Terminate A faithfully: background, am kill, verify pidof empty.
    // NEVER am force-stop (cancels notifications + stopped state).
    await _terminateIntroducer();
    checks['${legLabel}IntroducerTerminatedBeforeSend'] = true;

    // Responder accepts every pending introduction via the E2E channel.
    final response = await _writeConfigAndAwait(responder, {
      'stepId': '252-${scenario.id}-$legLabel',
      'introduction_action': 'accept_all',
      'poll_cycles': 40,
      'poll_interval_ms': 1000,
      'require_introducer_acceptance_custody': true,
      'introducer_acceptance_custody_timeout_ms': 150000,
    });
    checks['${legLabel}AcceptanceEventDiscriminated'] = true;
    final custody = response['introDeliveryCustody'];
    if (custody is! Map<String, dynamic> ||
        custody['status'] != 'confirmed' ||
        custody['introductionCount'] is! int ||
        (custody['introductionCount'] as int) < 1) {
      throw _CampaignFailure(
        '$legLabel did not return exact introducer-custody confirmation',
      );
    }
    stdout.writeln('INTRODUCER_CUSTODY: PASS ($legLabel)');
    checks['${legLabel}IntroducerCustody'] = true;

    // Wait for the relay-built FCM card on terminated A.
    await _waitFor(
      '$legLabel acceptance card on A',
      const Duration(seconds: 90),
      () async => (await _notificationTitlesOnA()).contains(_acceptTitle),
    );
    // FCM delivery may start a headless process after the card is staged.
    // Kill that process without force-stopping the package so the existing
    // notification PendingIntent still exercises a true cold tap.
    await _terminateIntroducer();
    await _requirePidofEmpty('after $legLabel card arrived / before tap');
    checks['${legLabel}IntroducerStillTerminatedBeforeTap'] = true;

    // Copy assertion through the feasibility-probed extractor.
    final copy = await _extractAcceptanceCopy();
    if (copy.title != _acceptTitle || !copy.body.contains(_acceptBody)) {
      throw _CampaignFailure(
        '$legLabel card copy mismatch: title="${copy.title}" '
        'body="${copy.body}"',
      );
    }
    if (copy.title == _forbiddenTitle || copy.body.contains(_forbiddenTitle)) {
      throw _CampaignFailure('$legLabel card shows forbidden "New Message"');
    }
    stdout.writeln('ACCEPTANCE_COPY: PASS ($legLabel via $copyExtractor)');
    checks['${legLabel}AcceptanceCopy'] = true;

    await _screenshotA('$legLabel-card');

    // Bounded node tap: expand shade, find the app's node with the exact
    // acceptance title, tap its bounds center.
    final logcatMark = await _logcatMark();
    await _boundedNotificationTap(legLabel);
    stdout.writeln('BOUNDED_NODE_TAP: PASS ($legLabel)');
    checks['${legLabel}BoundedNodeTap'] = true;

    // Machine-readable route markers from the coordinator flow event.
    final redirect = await _waitForRedirectMarker(logcatMark);
    if (!b.peerId.startsWith(redirect.finalPeer)) {
      throw _CampaignFailure(
        '$legLabel finalPeer=${redirect.finalPeer} does not match recipient '
        'B prefix ${b.peerPrefix}',
      );
    }
    if (redirect.statusContext != expectedStatusContext) {
      throw _CampaignFailure(
        '$legLabel statusContext=${redirect.statusContext}, want '
        '$expectedStatusContext',
      );
    }
    stdout.writeln('finalPeer=${redirect.finalPeer}');
    stdout.writeln('statusContext=${redirect.statusContext}');
    checks['${legLabel}FinalPeerIsRecipient'] = true;
    checks['${legLabel}StatusContext'] = true;

    await _screenshotA('$legLabel-conversation');
  }

  Future<void> _terminateIntroducer() async {
    // Background first so am kill is honored. Some emulator activity-manager
    // races leave the process alive, so use stop-app as the bounded fallback.
    await _adbShell(a.deviceId, ['input', 'keyevent', 'KEYCODE_HOME']);
    await Future<void>.delayed(const Duration(seconds: 1));
    await _adbShell(a.deviceId, ['am', 'kill', _appPackage]);
    if (!await _pidofEmptyWithin(const Duration(seconds: 5))) {
      await _adbShell(a.deviceId, ['cmd', 'activity', 'stop-app', _appPackage]);
    }
    if (!await _pidofEmptyWithin(const Duration(seconds: 20))) {
      final pid = await _pidofA();
      throw _CampaignFailure(
        'A process remained alive after bounded termination (pidof=$pid); '
        'the push/tap boundary would be unfaithful',
      );
    }
  }

  Future<bool> _pidofEmptyWithin(Duration timeout) async {
    final waitBudget = deadline.remaining(ceiling: timeout);
    if (waitBudget <= Duration.zero) return false;
    final requestedDeadline = DateTime.now().add(timeout);
    final sharedDeadline = DateTime.now().add(waitBudget);
    final pidDeadline = requestedDeadline.isBefore(sharedDeadline)
        ? requestedDeadline
        : sharedDeadline;
    do {
      if ((await _pidofA()).isEmpty) return true;
      final remaining = pidDeadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      await Future<void>.delayed(
        remaining < const Duration(milliseconds: 250)
            ? remaining
            : const Duration(milliseconds: 250),
      );
    } while (DateTime.now().isBefore(pidDeadline));
    return false;
  }

  Future<void> _requirePidofEmpty(String context) async {
    final pid = await _pidofA();
    if (pid.isNotEmpty) {
      throw _CampaignFailure(
        'A process unexpectedly alive $context (pidof=$pid); the push/tap '
        'boundary would be unfaithful',
      );
    }
  }

  Future<String> _pidofA() async {
    final out = await _adbShell(a.deviceId, [
      'pidof',
      _appPackage,
    ], allowFail: true);
    return out.trim();
  }

  // ---- Copy extraction -----------------------------------------------------

  Future<List<String>> _notificationTitlesOnA() async {
    final dump = await _adbShell(a.deviceId, [
      'dumpsys',
      'notification',
      '--noredact',
    ], allowFail: true);
    final titles = RegExp(
      r'android\.title=(?:String\s*\()?([^)\n]+)',
    ).allMatches(dump).map((match) => match.group(1)!.trim()).toList();
    if (titles.isNotEmpty) {
      return titles;
    }
    // Fall back to UIAutomator content text when dumpsys redacts.
    final xml = await _uiautomatorDump();
    return [
      for (final match in RegExp(r'text="([^"]+)"').allMatches(xml))
        match.group(1)!,
    ];
  }

  Future<({String title, String body})> _extractAcceptanceCopy() async {
    // Feasibility probe: prefer dumpsys literal title/body, else the bounded
    // UIAutomator XML content-text reader. The selected extractor is used for
    // BOTH acceptance legs.
    if (copyExtractor.isEmpty) {
      final dump = await _adbShell(a.deviceId, [
        'dumpsys',
        'notification',
        '--noredact',
      ], allowFail: true);
      if (dump.contains(_acceptTitle)) {
        copyExtractor = 'dumpsys';
      } else {
        copyExtractor = 'uiautomator';
      }
      stdout.writeln('COPY_EXTRACTOR_FEASIBILITY: PASS ($copyExtractor)');
      checks['copyExtractorFeasibility'] = true;
    }

    if (copyExtractor == 'dumpsys') {
      final dump = await _adbShell(a.deviceId, [
        'dumpsys',
        'notification',
        '--noredact',
      ]);
      final title = RegExp(r'android\.title=(?:String\s*\()?([^)\n]+)')
          .allMatches(dump)
          .map((match) => match.group(1)!.trim())
          .firstWhere((value) => value == _acceptTitle, orElse: () => '');
      final body = RegExp(r'android\.text=(?:String\s*\()?([^)\n]+)')
          .allMatches(dump)
          .map((match) => match.group(1)!.trim())
          .firstWhere((value) => value.contains(_acceptBody), orElse: () => '');
      if (title.isNotEmpty && body.isNotEmpty) {
        return (title: title, body: body);
      }
      // Redaction regressed mid-campaign; degrade to the bounded reader.
      copyExtractor = 'uiautomator';
    }

    await _expandShade();
    final xml = await _uiautomatorDump();
    final texts = [
      for (final match in RegExp(r'text="([^"]+)"').allMatches(xml))
        match.group(1)!,
    ];
    final title = texts.firstWhere(
      (value) => value == _acceptTitle,
      orElse: () => '',
    );
    final body = texts.firstWhere(
      (value) => value.contains(_acceptBody),
      orElse: () => '',
    );
    await _collapseShade();
    if (title.isEmpty || body.isEmpty) {
      throw _CampaignFailure(
        'could not extract acceptance copy (extractor=$copyExtractor); '
        'texts=${texts.take(20).toList()}',
      );
    }
    return (title: title, body: body);
  }

  // ---- Bounded tap ---------------------------------------------------------

  Future<void> _boundedNotificationTap(String legLabel) async {
    await _expandShade();
    final xml = await _uiautomatorDump();
    final bounds = _boundsForExactTitleNode(xml, _acceptTitle);
    if (bounds == null) {
      await _collapseShade();
      throw _CampaignFailure(
        '$legLabel: no notification node with exact title "$_acceptTitle" '
        'found in UIAutomator dump; refusing coordinate-guess taps',
      );
    }
    final centerX = (bounds.left + bounds.right) ~/ 2;
    final centerY = (bounds.top + bounds.bottom) ~/ 2;
    _log('$legLabel tapping node center ($centerX,$centerY) of $bounds');
    await _adbShell(a.deviceId, ['input', 'tap', '$centerX', '$centerY']);
  }

  Future<void> _dismissExactAcceptanceCards() async {
    final waitBudget = deadline.remaining(ceiling: const Duration(seconds: 20));
    if (waitBudget <= Duration.zero) {
      throw _CampaignFailure(
        'no shared budget remains to clear the first acceptance card',
      );
    }
    final dismissDeadline = DateTime.now().add(waitBudget);
    await _expandShade();
    try {
      for (var attempt = 0; attempt < 8; attempt += 1) {
        final xml = await _uiautomatorDump();
        final cards = exactNotificationTitleNodeBounds(xml, _acceptTitle);
        if (cards.isEmpty) {
          checks['b_acceptExactCardsDismissed'] = true;
          return;
        }
        final card = cards.first;
        final centerX = (card.left + card.right) ~/ 2;
        final centerY = (card.top + card.bottom) ~/ 2;
        _log(
          'dismissing proven first-leg acceptance card from '
          '($centerX,$centerY)',
        );
        await _adbShell(a.deviceId, [
          'input',
          'swipe',
          '$centerX',
          '$centerY',
          '1',
          '$centerY',
          '350',
        ]);
        final remaining = dismissDeadline.difference(DateTime.now());
        if (remaining <= Duration.zero) break;
        await Future<void>.delayed(
          remaining < const Duration(milliseconds: 500)
              ? remaining
              : const Duration(milliseconds: 500),
        );
      }
      throw _CampaignFailure(
        'the exact first-leg "$_acceptTitle" card remained after bounded '
        'targeted dismissal; refusing to attribute the second tap to it',
      );
    } finally {
      await _collapseShade();
    }
  }

  Future<void> _expandShade() async {
    await _adbShell(a.deviceId, ['cmd', 'statusbar', 'expand-notifications']);
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  Future<void> _collapseShade() async {
    await _adbShell(a.deviceId, [
      'cmd',
      'statusbar',
      'collapse',
    ], allowFail: true);
  }

  Future<String> _uiautomatorDump() async {
    const remotePath = '/sdcard/252_ui_dump.xml';
    await _adbShell(a.deviceId, ['uiautomator', 'dump', remotePath]);
    final xml = await _adbShell(a.deviceId, ['cat', remotePath]);
    await _adbShell(a.deviceId, ['rm', '-f', remotePath], allowFail: true);
    return xml;
  }

  ({int left, int top, int right, int bottom})? _boundsForExactTitleNode(
    String xml,
    String title,
  ) {
    final matches = exactNotificationTitleNodeBounds(xml, title);
    return matches.isEmpty ? null : matches.first;
  }

  // ---- Route markers -------------------------------------------------------

  Future<String> _logcatMark() async {
    // Timestamp mark so we only read post-tap log lines.
    final mark = (await _adbShell(a.deviceId, ['date', '+%s.%3N'])).trim();
    if (!RegExp(r'^\d{10,}\.\d{3}$').hasMatch(mark)) {
      throw _CampaignFailure('Android logcat cursor is invalid: "$mark"');
    }
    return mark;
  }

  Future<({String finalPeer, String statusContext})> _waitForRedirectMarker(
    String sinceMark,
  ) async {
    final waitBudget = deadline.remaining(ceiling: const Duration(seconds: 60));
    if (waitBudget <= Duration.zero) {
      throw _CampaignFailure(
        'timed out waiting for $_redirectEvent during ${deadline.phaseName}',
      );
    }
    final redirectDeadline = DateTime.now().add(waitBudget);
    while (DateTime.now().isBefore(redirectDeadline)) {
      final log = await _run('adb', [
        '-s',
        a.deviceId,
        'logcat',
        '-d',
        '-t',
        sinceMark,
      ], allowFail: true);
      for (final line in log.split('\n')) {
        if (!line.contains(_redirectEvent)) {
          continue;
        }
        final finalPeer = RegExp(
          r'\\?"finalPeer\\?":\\?"([^"\\]+)',
        ).firstMatch(line)?.group(1);
        final statusContext = RegExp(
          r'\\?"statusContext\\?":\\?"([^"\\]+)',
        ).firstMatch(line)?.group(1);
        if (finalPeer != null && statusContext != null) {
          return (finalPeer: finalPeer, statusContext: statusContext);
        }
      }
      final remaining = redirectDeadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      await Future<void>.delayed(
        remaining < const Duration(seconds: 2)
            ? remaining
            : const Duration(seconds: 2),
      );
    }
    throw _CampaignFailure(
      'timed out waiting for $_redirectEvent marker after tap; the tap did '
      'not reach the introducer-accept conversation redirect',
    );
  }

  Future<void> _assertNoNavigationErrors() async {
    final log = await _run('adb', [
      '-s',
      a.deviceId,
      'logcat',
      '-d',
    ], allowFail: true);
    for (final event in _navErrorEvents) {
      if (log.contains(event)) {
        throw _CampaignFailure('navigation error $event present in A logcat');
      }
    }
    checks['zeroNavigationErrors'] = true;
  }

  // ---- Timeout / late-event cleanup ----------------------------------------

  Future<void> _cleanupAfterLateEvents() {
    return _lateEventCleanup.run(() async {
      var clean = true;
      for (final party in <_Party>[a, b, c]) {
        try {
          if (party.isIos) {
            await _runCleanupCommand('xcrun', <String>[
              'simctl',
              'terminate',
              party.deviceId,
              _iosBundleId,
            ]);
            final container = await _runCleanupCommand('xcrun', <String>[
              'simctl',
              'get_app_container',
              party.deviceId,
              _iosBundleId,
              'data',
            ]);
            if (container.stdout.trim().isNotEmpty) {
              for (final name in const <String>[
                'intro_e2e_config.json',
                'intro_e2e_result.json',
              ]) {
                final file = File('${container.stdout.trim()}/Documents/$name');
                if (file.existsSync()) file.deleteSync();
              }
            }
            continue;
          }
          await _runCleanupCommand('adb', <String>[
            '-s',
            party.deviceId,
            'shell',
            'cmd',
            'activity',
            'stop-app',
            _appPackage,
          ]);
          await _runCleanupCommand('adb', <String>[
            '-s',
            party.deviceId,
            'shell',
            'run-as',
            _appPackage,
            'rm',
            '-f',
            'app_flutter/intro_e2e_config.json',
            'app_flutter/intro_e2e_result.json',
          ]);
        } on Object catch (error) {
          clean = false;
          _log(
            'best-effort late-event cleanup failed for ${party.role}: $error',
          );
        }
      }
      try {
        await _runCleanupCommand('adb', <String>[
          '-s',
          a.deviceId,
          'shell',
          'cmd',
          'statusbar',
          'collapse',
        ]);
      } on Object catch (error) {
        clean = false;
        _log('best-effort notification-shade cleanup failed: $error');
      }
      if (clean) checks['lateEventCleanup'] = true;
    });
  }

  Future<_CommandResult> _runCleanupCommand(
    String executable,
    List<String> args,
  ) {
    return _runBoundedProcess(
      executable,
      args,
      timeout: const Duration(seconds: 10),
    );
  }

  // ---- E2E config channel --------------------------------------------------

  Future<Map<String, dynamic>> _writeConfigAndAwait(
    _Party party,
    Map<String, dynamic> config,
  ) async {
    final stepId = config['stepId'] as String;
    final requiresAcceptance =
        config['introduction_action'] == 'accept_all' &&
        config['require_introducer_acceptance_custody'] == true;
    _log('writing config $stepId to ${party.role}');
    await _writeAppDocumentsFile(
      party,
      'intro_e2e_config.json',
      jsonEncode(config),
    );
    final raw = await _waitForValue(
      'result for $stepId',
      deadline.remaining(),
      () async {
        final result = await _readAppDocumentsFile(
          party,
          'intro_e2e_result.json',
        );
        if (result == null) {
          return null;
        }
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        if (decoded['stepId'] != stepId || decoded['status'] == 'running') {
          return null;
        }
        if (decoded['success'] == true &&
            requiresAcceptance &&
            !isIntroAcceptanceResult(decoded, stepId: stepId)) {
          _log(
            'ignoring non-acceptance completion for $stepId while awaiting '
            'explicit acceptance custody',
          );
          return null;
        }
        return result;
      },
    );
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    if (decoded['success'] != true) {
      throw _CampaignFailure(
        'step $stepId failed on ${party.role}: ${decoded['error']}',
      );
    }
    return decoded;
  }

  Future<String?> _readAppDocumentsFile(_Party party, String name) async {
    if (party.isIos) {
      final container = await _run('xcrun', [
        'simctl',
        'get_app_container',
        party.deviceId,
        _iosBundleId,
        'data',
      ], allowFail: true);
      final path = '${container.trim()}/Documents/$name';
      final file = File(path);
      if (container.trim().isEmpty || !file.existsSync()) {
        return null;
      }
      return file.readAsStringSync();
    }
    final out = await _run('adb', [
      '-s',
      party.deviceId,
      'shell',
      'run-as',
      _appPackage,
      'cat',
      'app_flutter/$name',
    ], allowFail: true);
    if (out.contains('No such file') || out.trim().isEmpty) {
      return null;
    }
    return out;
  }

  Future<void> _writeAppDocumentsFile(
    _Party party,
    String name,
    String content,
  ) async {
    if (party.isIos) {
      final container = await _run('xcrun', [
        'simctl',
        'get_app_container',
        party.deviceId,
        _iosBundleId,
        'data',
      ]);
      File('${container.trim()}/Documents/$name').writeAsStringSync(content);
      return;
    }
    final tmp = File(
      '${Directory.systemTemp.path}/252_cfg_${party.deviceId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}.json',
    )..writeAsStringSync(content);
    const remoteTmp = '/data/local/tmp/252_intro_e2e_config.json';
    try {
      await _run('adb', ['-s', party.deviceId, 'push', tmp.path, remoteTmp]);
      await _run('adb', [
        '-s',
        party.deviceId,
        'shell',
        'run-as',
        _appPackage,
        'mkdir',
        '-p',
        'app_flutter',
      ]);
      await _run('adb', [
        '-s',
        party.deviceId,
        'shell',
        'run-as',
        _appPackage,
        'cp',
        remoteTmp,
        'app_flutter/$name',
      ]);
      await _adbShell(party.deviceId, ['rm', '-f', remoteTmp], allowFail: true);
    } finally {
      try {
        tmp.deleteSync();
      } catch (_) {}
    }
  }

  // ---- Artifacts -----------------------------------------------------------

  Future<void> _screenshotA(String label) async {
    const remote = '/sdcard/252_shot.png';
    await _adbShell(a.deviceId, ['screencap', '-p', remote], allowFail: true);
    await _run('adb', [
      '-s',
      a.deviceId,
      'pull',
      remote,
      '${artifactDir.path}/$label.png',
    ], allowFail: true);
    await _adbShell(a.deviceId, ['rm', '-f', remote], allowFail: true);
  }

  void _writeArtifact() {
    // Redacted: peer identities are 12-char prefixes only; no QR payloads,
    // public keys, or usernames are persisted.
    final artifact = <String, Object?>{
      'testCase': scenario.testCase,
      'scenario': scenario.id,
      'status': 'passed',
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'devices': <String>[
        introducerAndroidId,
        recipientAndroidId,
        introducedDeviceId,
      ],
      'copyExtractor': copyExtractor,
      'recipientPeerPrefix': b.peerPrefix,
      'checks': checks,
    };
    File(
      '${artifactDir.path}/${scenario.id}.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(artifact));
  }

  // ---- Process helpers -----------------------------------------------------

  Future<String> _adbShell(
    String deviceId,
    List<String> command, {
    bool allowFail = false,
  }) {
    return _run('adb', [
      '-s',
      deviceId,
      'shell',
      ...command,
    ], allowFail: allowFail);
  }

  Future<String> _run(
    String executable,
    List<String> args, {
    bool allowFail = false,
  }) async {
    _log('\$ $executable ${args.join(' ')}');
    final commandBudget = deadline.remaining(
      ceiling: const Duration(seconds: 45),
    );
    if (commandBudget <= Duration.zero) {
      throw _CampaignFailure(
        'intro campaign deadline expired during ${deadline.phaseName}',
      );
    }
    final result = await _runBoundedProcess(
      executable,
      args,
      timeout: commandBudget,
    );
    if (result.exitCode != 0 && !allowFail) {
      throw _CampaignFailure(
        '$executable ${args.join(' ')} failed (${result.exitCode}): '
        '${result.stderr}',
      );
    }
    return result.stdout;
  }

  Future<_CommandResult> _runBoundedProcess(
    String executable,
    List<String> args, {
    required Duration timeout,
  }) async {
    if (timeout <= Duration.zero) {
      throw _CampaignFailure(
        '$executable ${args.join(' ')} has no remaining execution budget',
      );
    }
    late final Process process;
    try {
      process = await Process.start(executable, args);
    } on ProcessException catch (error) {
      throw _CampaignFailure(
        'could not start $executable ${args.join(' ')}: ${error.message}',
      );
    }
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    late final int code;
    try {
      code = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      await _terminateStartedProcess(process);
      final commandStdout = await stdoutFuture.timeout(
        const Duration(seconds: 3),
        onTimeout: () => '',
      );
      final commandStderr = await stderrFuture.timeout(
        const Duration(seconds: 3),
        onTimeout: () => '',
      );
      throw _CampaignFailure(
        '$executable ${args.join(' ')} exceeded its shared phase deadline '
        '(stdout=$commandStdout, stderr=$commandStderr)',
      );
    }
    final commandStdout = await stdoutFuture;
    final commandStderr = await stderrFuture;
    return _CommandResult(
      exitCode: code,
      stdout: commandStdout,
      stderr: commandStderr,
    );
  }

  Future<void> _terminateStartedProcess(Process process) async {
    final processExit = process.exitCode;
    if (!process.kill(ProcessSignal.sigterm)) {
      try {
        await processExit.timeout(const Duration(seconds: 1));
        return;
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      }
      try {
        await processExit.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        _log('command remained alive after SIGKILL');
      }
      return;
    }
    try {
      await processExit.timeout(const Duration(seconds: 3));
      return;
    } on TimeoutException {
      _log('command did not stop after SIGTERM; sending SIGKILL');
    }
    process.kill(ProcessSignal.sigkill);
    try {
      await processExit.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      _log('command remained alive after SIGKILL');
    }
  }

  Future<void> _waitFor(
    String what,
    Duration timeout,
    Future<bool> Function() probe, {
    String? onTimeoutHint,
  }) async {
    final waitBudget = deadline.remaining(ceiling: timeout);
    if (waitBudget <= Duration.zero) {
      throw _CampaignFailure(
        'timed out waiting for $what during ${deadline.phaseName}',
      );
    }
    final waitDeadline = DateTime.now().add(waitBudget);
    while (DateTime.now().isBefore(waitDeadline)) {
      if (await probe()) {
        return;
      }
      final remaining = waitDeadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      await Future<void>.delayed(
        remaining < const Duration(seconds: 2)
            ? remaining
            : const Duration(seconds: 2),
      );
    }
    throw _CampaignFailure(
      'timed out waiting for $what'
      '${onTimeoutHint == null ? '' : ' — $onTimeoutHint'}',
    );
  }

  Future<String> _waitForValue(
    String what,
    Duration timeout,
    Future<String?> Function() probe,
  ) async {
    final waitBudget = deadline.remaining(ceiling: timeout);
    if (waitBudget <= Duration.zero) {
      throw _CampaignFailure(
        'timed out waiting for $what during ${deadline.phaseName}',
      );
    }
    final waitDeadline = DateTime.now().add(waitBudget);
    while (DateTime.now().isBefore(waitDeadline)) {
      final value = await probe();
      if (value != null && value.isNotEmpty) {
        return value;
      }
      final remaining = waitDeadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      await Future<void>.delayed(
        remaining < const Duration(seconds: 2)
            ? remaining
            : const Duration(seconds: 2),
      );
    }
    throw _CampaignFailure('timed out waiting for $what');
  }

  void _log(String message) {
    if (_verbose) {
      stdout.writeln('[252] $message');
    }
  }
}

String? _valueFor(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name && i + 1 < args.length) {
      return args[i + 1];
    }
    if (arg.startsWith('$name=')) {
      return arg.substring(name.length + 1);
    }
  }
  return null;
}
