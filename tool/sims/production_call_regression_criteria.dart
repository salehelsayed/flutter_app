import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../integration_test/support/android_production_audio_call_evidence.dart';
import '../../integration_test/support/production_call_in_app_identity.dart';
import 'artifact_evidence.dart';

Map<String, Object?> _object(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : {};
List<Map<String, Object?>> _objects(Object? value) =>
    value is List ? value.map(_object).toList() : [];
bool _hash(Object? value) =>
    value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
String _digest(String value) => sha256.convert(utf8.encode(value)).toString();

List<String> validateProductionCallRegression(Map<String, Object?> proof) {
  final failures = <String>[];
  void check(bool condition, String failure) {
    if (!condition) failures.add(failure);
  }

  final id = proof['caseId'];
  check(
    {
      'kx0001',
      'kx0002',
      'kx0003',
      'kx0015',
      'kx0016',
      'kx0017',
      'kx0029',
      'kx0030',
    }.contains(id),
    'unregistered call regression',
  );
  final actor = {'kx0001', 'kx0002', 'kx0029', 'kx0030'}.contains(id)
      ? 'caller'
      : 'callee';
  check(proof['actor'] == actor, 'wrong call endpoint');
  final physicalCaller = proof['physicalCaller'] == true;
  check(
    !physicalCaller || id == 'kx0029',
    'physical caller topology is reserved for kx0029',
  );
  final root = proof['attemptDirectory'];
  Map<String, Object?> baseline = {};
  try {
    final evidence = SimsArtifactEvidence.fromJson(proof['baselineEvidence']);
    final file = File(evidence.path);
    final expected = proof['emulatorPair'] == true
        ? 'validateAndroidProductionAudioCallEmulatorArtifact'
        : androidProductionAudioCallArtifactValidatorId;
    final owned =
        root is String &&
        FileSystemEntity.typeSync(file.path, followLinks: false) ==
            FileSystemEntityType.file &&
        file.resolveSymbolicLinksSync().startsWith(
          '${Directory(root).resolveSymbolicLinksSync()}${Platform.pathSeparator}',
        ) &&
        file.lengthSync() <= 4 * 1024 * 1024;
    if (owned &&
        auditSimsArtifactEvidence(
          evidence: evidence,
          expectedValidatorIds: [expected],
        ).isValid) {
      final body = _object(jsonDecode(file.readAsStringSync()));
      if (validateAndroidProductionAudioCallDurableArtifact(
        body,
        emulatorPair: proof['emulatorPair'] == true,
        physicalCaller: physicalCaller,
      ).ok) {
        baseline = _object(body['runtimeProof']);
      }
    }
  } on Object {
    /* A missing current control remains a failed assertion. */
  }
  check(
    baseline.isNotEmpty,
    'current authenticated audio control/restoration missing',
  );
  final endpoints = _object(baseline['endpoints']);
  final actorIdentity = _object(endpoints[actor])['identitySha256'];
  final otherIdentity = _object(
    endpoints[actor == 'caller' ? 'callee' : 'caller'],
  )['identitySha256'];
  check(
    _hash(otherIdentity) && proof['otherPeerSha256'] == otherIdentity,
    'actual authenticated counterparty binding missing',
  );
  final invocations = _objects(proof['invocations']);
  check(
    invocations.length == 2 &&
        invocations.every(
          (p) =>
              p['scenarioId'] == id &&
              p['profileId'] == 'android.e2e.production_call_local' &&
              p['role'] == 'alice' &&
              p['runId'] == proof['runId'] &&
              p['nonce'] is String &&
              (p['nonce'] as String).isNotEmpty,
        ) &&
        invocations
            .map((p) => _object(p['values'])['actor'])
            .toSet()
            .containsAll({'caller', 'callee'}) &&
        invocations.map((p) => p['nonce']).toSet().length == 2,
    'fresh two-peer current-call observers missing',
  );
  if (id == 'kx0030') {
    final privacy = _object(proof['privacy']);
    check(
      privacy['before'] is bool &&
          privacy['afterToggle'] is bool &&
          privacy['afterToggle'] != privacy['before'] &&
          privacy['restored'] == privacy['before'],
      'actual saved preference toggle/readback/restoration missing',
    );
    check(
      maestroFlowReceiptPassed(
            privacy['copyReceipt'],
            root,
            'production_call_privacy_open',
          ) &&
          maestroFlowReceiptPassed(
            privacy['toggleReceipt'],
            root,
            'production_call_privacy_toggle',
          ) &&
          maestroFlowReceiptPassed(
            privacy['restoreReceipt'],
            root,
            'production_call_privacy_toggle',
          ),
      'actual truthful audio/signaling privacy copy and UI toggle missing',
    );
    return failures;
  }
  final observations = _object(proof['observations']);
  Map<String, Object?> observation(String label) =>
      _object(observations[label]);
  bool activePair(Map<String, Object?> value, {required bool connected}) {
    final current = _object(value['current']);
    final other = _object(value['otherCurrent']);
    return [current, other].every(
          (c) =>
              c['sourceBound'] == true &&
              c['connectionReadSucceeded'] == true &&
              c['inCall'] == true &&
              _hash(c['callSha256']),
        ) &&
        current['callSha256'] == other['callSha256'] &&
        current['contactSha256'] == otherIdentity &&
        other['contactSha256'] == actorIdentity &&
        current['direction'] == (actor == 'caller' ? 'outgoing' : 'incoming') &&
        other['direction'] == (actor == 'caller' ? 'incoming' : 'outgoing') &&
        (!connected ||
            [current, other].every(
              (c) =>
                  c['state'] == 'connected' &&
                  c['connectionPresent'] == true &&
                  c['localAudioEnabled'] == true,
            ));
  }

  Map<String, Object?>? card(String label, int id) {
    final rows = _objects(
      observation(label)['cards'],
    ).where((c) => c['id'] == id).toList();
    return rows.length == 1 ? rows.single : null;
  }

  bool named(Map<String, Object?>? value, String kind) =>
      value != null &&
      value['peerIdVisible'] == false &&
      value['titleSha256'] == proof['expectedNameSha256'] &&
      value['bodyKind'] == kind &&
      _hash(value['nativeKeySha256']) &&
      _hash(value['sourceDumpSha256']);
  bool quiet(String label) {
    final value = card(label, 505);
    return value != null &&
        value['peerIdVisible'] == false &&
        value['bodyKind'] == 'ongoing' &&
        _hash(value['nativeKeySha256']) &&
        _hash(value['titleSha256']) &&
        _hash(value['sourceDumpSha256']) &&
        value['quiet'] == true &&
        value['soundIsNull'] == true &&
        value['vibrationIsNull'] == true &&
        value['sdk'] is int &&
        ((value['sdk'] as int) >= 26
            ? value['channelImportance'] == 2 &&
                  value['expectedOngoingChannel'] == true
            : value['priority'] == -1 && value['channelImportance'] == null) &&
        !_objects(observation(label)['cards']).any((c) => c['id'] == 504);
  }

  final connected = observation('connected');
  check(
    activePair(connected, connected: true),
    'actual connected call pair missing',
  );
  if (id == 'kx0001') {
    final captured = _object(proof['wireDeadlines']);
    final wires = _objects(captured['encodedInvites']);
    final timers = _objects(captured['timers']);
    final call = _object(connected['current'])['callSha256'];
    final invite = timers.where((t) => t['kind'] == 'inviteExpiry').toList();
    final noAnswer = timers.where((t) => t['kind'] == 'noAnswer').toList();
    final readable =
        wires.length == 1 &&
        invite.length == 1 &&
        noAnswer.length == 1 &&
        timers.length == 2 &&
        [
          'createdAtMs',
          'expiresAtMs',
          'wireExpiresAtMs',
        ].every((k) => wires.single[k] is int) &&
        timers.every(
          (t) => [
            'scheduledAtMs',
            'requestedDelayMs',
            'effectiveDelayMs',
            'deadlineMs',
            'callStartedAtMs',
          ].every((k) => t[k] is int),
        );
    check(readable, 'actual signed wire and scheduled timer metadata missing');
    if (!readable) return failures;
    final wire = wires.single;
    final delivery = invite.single;
    final unanswered = noAnswer.single;
    check(
      wire['callSha256'] == call &&
          timers.every((t) => t['callSha256'] == call) &&
          _hash(wire['wireSha256']) &&
          _hash(wire['messageSha256']) &&
          wire['signaturePresent'] == true,
      'signed invite and scheduled timers do not bind the current call',
    );
    check(
      (wire['expiresAtMs'] as int) - (wire['createdAtMs'] as int) == 40000 &&
          wire['wireExpiresAtMs'] == wire['expiresAtMs'],
      'actual signed invite TTL differs from current forty-second contract',
    );
    check(
      timers.every(
            (t) =>
                (t['effectiveDelayMs'] as int) >= 0 &&
                (t['deadlineMs'] as int) ==
                    (t['scheduledAtMs'] as int) +
                        (t['effectiveDelayMs'] as int) &&
                (t['scheduledAtMs'] as int) >= (t['callStartedAtMs'] as int),
          ) &&
          delivery['callStartedAtMs'] == unanswered['callStartedAtMs'] &&
          delivery['requestedDelayMs'] == 45000 &&
          (delivery['deadlineMs'] as int) ==
              (delivery['callStartedAtMs'] as int) + 45000 &&
          unanswered['requestedDelayMs'] == 30000 &&
          unanswered['effectiveDelayMs'] == 30000,
      'actual delivery/no-answer deadlines changed their source-defined origins',
    );
    final gap =
        (delivery['deadlineMs'] as int) - (wire['wireExpiresAtMs'] as int);
    check(
      proof['wireDeliveryGapMs'] == gap &&
          proof['wireOutlivesDeliveryDeadline'] == (gap < 0),
      'exact wire-versus-delivery comparison replaced by assumed headroom',
    );
    return failures;
  }
  if (id == 'kx0029') {
    const kinds = {
      'systemDefault',
      'earpiece',
      'speaker',
      'wiredHeadset',
      'bluetooth',
    };
    final inventory = _object(proof['pickerInventory']);
    final provider = _object(inventory['provider']);
    final rows = _objects(inventory['rows']);
    final outputs = _objects(provider['outputs']);
    bool coarseRows(List<Map<String, Object?>> values) =>
        values.isNotEmpty &&
        values.asMap().entries.every(
          (entry) =>
              entry.value.keys.toSet().difference({
                'index',
                'route',
                'selected',
              }).isEmpty &&
              entry.value['index'] == entry.key &&
              kinds.contains(entry.value['route']) &&
              entry.value['selected'] is bool,
        ) &&
        values.where((value) => value['selected'] == true).length == 1;
    final call = _object(connected['current'])['callSha256'];
    check(
      provider['callSha256'] == call &&
          provider['audioActive'] == true &&
          _hash(inventory['sourceUiSha256']) &&
          coarseRows(rows) &&
          coarseRows(outputs) &&
          jsonEncode(rows) == jsonEncode(outputs),
      'visible picker differs from actual available private-free inventory',
    );
    final speaker = _object(proof['speakerSelected']);
    final released = _object(proof['speakerReleased']);
    final supported = speaker['supportedRoutes'] is List
        ? speaker['supportedRoutes'] as List
        : const [];
    final fallback = [
      'systemDefault',
      'wiredHeadset',
      'bluetooth',
      'earpiece',
    ].where(supported.contains).firstOrNull;
    check(
      speaker['callSha256'] == call &&
          speaker['audioActive'] == true &&
          speaker['selectedRoute'] == 'speaker' &&
          coarseRows(_objects(speaker['outputs'])) &&
          _objects(
            speaker['outputs'],
          ).any((r) => r['route'] == 'speaker' && r['selected'] == true),
      'actual available speaker was not selected',
    );
    check(
      fallback != null &&
          proof['expectedSpeakerRelease'] == fallback &&
          released['callSha256'] == call &&
          released['audioActive'] == true &&
          released['selectedRoute'] == fallback &&
          coarseRows(_objects(released['outputs'])) &&
          !_objects(
            released['outputs'],
          ).any((r) => r['route'] == 'speaker' && r['selected'] == true),
      'speaker release did not recover the source-defined available route',
    );
    final absent = {
      'wiredHeadset',
      'bluetooth',
    }.where((kind) => !outputs.any((r) => r['route'] == kind)).toSet();
    check(
      proof['unavailableHardware'] is List &&
          (proof['unavailableHardware'] as List)
              .toSet()
              .difference(absent)
              .isEmpty &&
          absent
              .difference((proof['unavailableHardware'] as List).toSet())
              .isEmpty,
      'unavailable hardware status disagrees with actual inventory',
    );
    return failures;
  }
  check(quiet('connected'), 'quiet owned ongoing card missing');
  if (id != 'kx0002') {
    check(
      activePair(observation('incoming'), connected: false),
      'actual incoming call pair missing',
    );
    check(
      named(card('incoming', 504), 'incoming'),
      'authenticated readable incoming name missing',
    );
    check(
      _object(observation('incoming')['current'])['callSha256'] ==
          _object(connected['current'])['callSha256'],
      'call changed between incoming and ongoing',
    );
    final name = _object(proof['contactName']);
    check(
      name['contactSha256'] == otherIdentity &&
          name['blocked'] == false &&
          _hash(name['displayNameSha256']) &&
          (id == 'kx0017'
              ? name['readableName'] == false &&
                    name['displayNameSha256'] == otherIdentity &&
                    proof['expectedNameSha256'] == _digest('MKnoon caller')
              : name['readableName'] == true &&
                    proof['expectedNameSha256'] == name['displayNameSha256']),
      'authenticated stored display-name contract missing',
    );
  }
  if (id == 'kx0016' || id == 'kx0017') {
    check(
      named(card('connected', 505), 'ongoing'),
      'readable ongoing name was not retained',
    );
    failures.addAll(
      validateProductionCallInAppIdentity(
        proof,
        actorIdentity: '$actorIdentity',
        otherIdentity: '$otherIdentity',
      ),
    );
  }
  if (id == 'kx0017') {
    final fixture = _object(proof['peerIdUsernameFixture']);
    check(
      fixture['peerSha256'] == otherIdentity &&
          fixture['afterUsernameEqualsPeerId'] == true &&
          _hash(fixture['beforeOtherColumnsSha256']) &&
          fixture['beforeOtherColumnsSha256'] ==
              fixture['afterOtherColumnsSha256'],
      'peer-ID username fixture changed authority or the wrong contact',
    );
  }
  if (id == 'kx0002' || id == 'kx0003') {
    final original = _object(connected['current'])['callSha256'];
    for (final label in ['after-minimize', 'after-home', 'after-return']) {
      final current = observation(label);
      check(
        activePair(current, connected: true) &&
            _object(current['current'])['callSha256'] == original,
        'current call changed at $label',
      );
      check(quiet(label), 'ongoing notification changed at $label');
      check(
        card(label, 505)?['nativeKeySha256'] ==
            card('connected', 505)?['nativeKeySha256'],
        'ongoing native identity changed at $label',
      );
    }
    check(
      maestroFlowReceiptPassed(
            proof['minimizeReceipt'],
            root,
            'production_call_minimize',
          ) &&
          maestroFlowReceiptPassed(
            proof['returnReceipt'],
            root,
            'production_call_return',
          ),
      'actual first-minimize/return flow missing',
    );
    final foreground = _object(proof['notificationForegroundReceipt']);
    check(
      foreground['ownedCallSurface'] == true &&
          _hash(foreground['sourceUiSha256']),
      'notification tap did not foreground the owned call surface',
    );
    final hun = _objects(proof['headsUpSamples']);
    check(
      hun.length >= 3 &&
          hun.every(
            (s) =>
                s['sectionsObserved'] is int &&
                (s['sectionsObserved'] as int) > 0 &&
                s['ownedOngoingHeadsUpCount'] == 0 &&
                _hash(s['sourceDumpSha256']),
          ),
      'actual ongoing heads-up observation missing or alerting',
    );
  }
  if (id == 'kx0003') {
    final marker = _object(proof['incomingEventMarker']);
    final cursor = marker['cursor'];
    final events = _objects(_object(proof['handoverEvents'])['events']);
    final ongoing = events.indexWhere(
      (e) => e['kind'] == 'posted' && e['id'] == 505,
    );
    final canceled = events.indexWhere(
      (e) => e['kind'] == 'canceled' && e['id'] == 504,
    );
    check(
      cursor is List &&
          cursor.isNotEmpty &&
          cursor.every(_hash) &&
          _objects(
            marker['events'],
          ).any((e) => e['kind'] == 'posted' && e['id'] == 504) &&
          _hash(marker['sourceDumpSha256']) &&
          _hash(_object(proof['handoverEvents'])['sourceDumpSha256']) &&
          ongoing >= 0 &&
          canceled > ongoing &&
          events.every((e) => _hash(e['eventSha256'])),
      'actual ongoing-before-ringing-cancel OS order missing',
    );
  }
  return failures;
}
