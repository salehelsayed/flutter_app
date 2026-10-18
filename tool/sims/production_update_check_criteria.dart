import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/features/update_check/domain/update_check_models.dart';
import 'package:flutter_app/features/update_check/domain/update_store_urls.dart';
import 'package:flutter_app/features/update_check/domain/version_file_verifier.dart';
import 'package:flutter_app/features/update_check/infrastructure/update_check_fixture_contract.dart';

import '../../integration_test/support/update_check_test_keys.dart';
import 'artifact_evidence.dart' show maestroFlowReceiptPassed;

const updateCheckForegroundPhases = <String, List<(String, String, int)>>{
  'kx0020': [('soft', 'soft', 1)],
  'kx0021': [('hard', 'hard', 1)],
  'kx0022': [
    ('baseline_soft', 'soft', 1),
    ('tampered_hard', 'soft', 1),
    ('valid_hard', 'hard', 2),
  ],
  'kx0023': [
    ('newer_hard', 'hard', 2),
    ('stale_soft', 'hard', 2),
    ('latest_soft', 'soft', 3),
  ],
  'kx0024': [
    ('old_issued', 'soft', 2),
    ('older_sequence', 'soft', 2),
    ('newer_sequence', 'hard', 3),
  ],
  'kx0026': [('soft', 'soft', 1), ('hard', 'hard', 2)],
  'kx0028': [('testflight_hard', 'hard', 1)],
};

Map<String, Object?> _object(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : {};

List<String> validateProductionUpdateCheck(Map<String, Object?> proof) {
  final failures = <String>[];
  void require(bool condition, String reason) {
    if (!condition) failures.add(reason);
  }

  final id = proof['caseId'];
  final expected = updateCheckForegroundPhases[id];
  final native = id == 'kx0025' || id == 'kx0027';
  if (expected == null && !native) {
    return ['a complete registered SE41 case is required'];
  }
  final platform = id == 'kx0028' ? UpdatePlatform.ios : UpdatePlatform.android;
  require(
    proof['runId'] is String && (proof['runId'] as String).isNotEmpty,
    'current run identity is required',
  );
  require(
    proof['profileId'] ==
        (platform == UpdatePlatform.ios
            ? 'ios.simulator.app'
            : 'android.e2e.production_call_local'),
    'case must use its approved existing build profile',
  );
  require(
    proof['childBuilds'] == 0,
    'scenario must reuse the centrally prepared app',
  );
  if (native) return [...failures, ..._validateNative(proof)];
  final phases = proof['phases'];
  if (phases is! List || phases.length != expected!.length) {
    return [...failures, 'all exact ordered case phases are required'];
  }
  final verifier = VersionFileVerifier([
    TrustedVersionKey(
      keyId: updateCheckFixtureKeyId,
      rank: 1,
      publicKey: testOnlyK1.verifyKey,
    ),
  ]);
  final usedReceipts = <String>{};
  String? acceptedHash;
  String? tamperedPayloadHash;
  int? lastClock;
  for (var i = 0; i < phases.length; i++) {
    final phase = _object(phases[i]);
    final (label, kind, sequence) = expected[i];
    require(
      phase['label'] == label,
      '$label must appear in its exact position',
    );
    final encoded = phase['envelope'];
    if (encoded is! String ||
        encoded.length > ((maxVersionFileBytes + 2) ~/ 3) * 4) {
      failures.add('$label lacks a bounded signed TEST envelope');
      continue;
    }
    List<int> bytes;
    VersionFileCheck checked;
    try {
      bytes = base64Decode(encoded);
      checked = verifier.verify(
        bytes,
        highestAcceptedRank: 0,
        requiredPlatforms: {platform},
      );
    } on Object {
      failures.add('$label has malformed envelope encoding');
      continue;
    }
    final tampered = label == 'tampered_hard';
    require(
      tampered
          ? checked.rejection == VersionFileRejection.badSignature
          : checked.isAccepted,
      '$label must exercise the intended signature boundary',
    );
    if (tampered) {
      try {
        final envelope = _object(jsonDecode(utf8.decode(bytes)));
        tamperedPayloadHash = sha256
            .convert(base64Decode(envelope['payload'] as String))
            .toString();
      } on Object {
        failures.add('tampered hard payload must remain structurally intact');
      }
    }
    if (label == 'valid_hard') {
      final file = checked.file;
      require(
        file != null &&
            tamperedPayloadHash != null &&
            sha256.convert(file.payloadBytes).toString() == tamperedPayloadHash,
        'repairing only the signature must make the same hard payload effective',
      );
    }
    final stale = label == 'stale_soft' || label == 'older_sequence';
    if (!tampered && !stale && checked.isAccepted) {
      acceptedHash = sha256.convert(bytes).toString();
    }
    if (label == 'old_issued' || label == 'newer_sequence') {
      require(
        checked.file?.payload.issuedAt == 1,
        '$label must use informational old issuedAt, without adding expiry',
      );
    }
    final snapshot = _object(phase['snapshot']);
    require(
      snapshot['platform'] == platform.name,
      '$label must observe the actual selected mobile platform',
    );
    require(
      snapshot['kind'] == kind &&
          snapshot['sequence'] == sequence &&
          snapshot['rank'] == 1 &&
          acceptedHash != null &&
          snapshot['acceptedEnvelopeSha256'] == acceptedHash,
      '$label must observe the exact accepted decision and envelope',
    );
    final clock = snapshot['clockMs'];
    final checkedAt = snapshot['lastCheckAtMs'];
    final after = phase['checkAfterMs'];
    require(
      clock is int &&
          checkedAt is int &&
          after is int &&
          checkedAt >= after &&
          checkedAt <= clock &&
          (lastClock == null || checkedAt - lastClock >= 21601000),
      '$label needs a completed new check, not an unchanged cached decision',
    );
    if (checkedAt is int) lastClock = checkedAt;
    final flow = kind == 'hard'
        ? 'production_update_hard'
        : 'production_update_soft';
    final receipt = phase['flowReceipt'];
    require(
      receipt is String &&
          usedReceipts.add(receipt) &&
          maestroFlowReceiptPassed(receipt, proof['attemptDirectory'], flow),
      '$label needs its own successful UI assertion receipt',
    );
  }
  if (id == 'kx0020') {
    require(
      maestroFlowReceiptPassed(
        proof['navigationReceipt'],
        proof['attemptDirectory'],
        'production_update_soft_navigation',
      ),
      'soft notice must retain Back/navigation',
    );
  }
  if (id == 'kx0028') {
    require(
      maestroFlowReceiptPassed(
            proof['storeTapReceipt'],
            proof['attemptDirectory'],
            'production_update_open_store',
          ) &&
          _object(proof['storeTarget'])['url'] == updateStoreUrlIos,
      'the real update action must select the built-in TestFlight target',
    );
  }
  return failures;
}

List<String> _validateNative(Map<String, Object?> proof) {
  final failures = <String>[];
  void require(bool condition, String reason) {
    if (!condition) failures.add(reason);
  }

  final baseline = _object(proof['baselineSnapshot']);
  final build = baseline['installedBuild'];
  final sdk = proof['androidSdk'];
  require(
    build is int && build >= 0,
    'native case needs the actual installed build',
  );
  require(
    sdk is int && sdk >= 24,
    'native case needs the actual supported Android SDK',
  );
  require(
    baseline['inCall'] == false,
    'native baseline must observe no active call',
  );
  require(
    proof['baselineCards'] is List && (proof['baselineCards'] as List).isEmpty,
    'a clean native-card baseline is required',
  );
  require(
    maestroFlowReceiptPassed(
      proof['backgroundReceipt'],
      proof['attemptDirectory'],
      'production_background',
    ),
    'the pinned app must actually enter the background',
  );
  final budgetCase = proof['caseId'] == 'kx0025';
  final labels = budgetCase
      ? ['unreadable_state', 'expired_budget', 'eligible_soft']
      : ['eligible_soft', 'hard_replaces_soft'];
  final checks = proof['nativeChecks'];
  if (checks is! List || checks.length != labels.length) {
    return [...failures, 'all ordered native checks are required'];
  }
  if (budgetCase) {
    require(
      proof['stateModeRestored'] == true,
      'the unreadable-state probe must restore the exact original file mode',
    );
  }
  final verifier = VersionFileVerifier([
    TrustedVersionKey(
      keyId: updateCheckFixtureKeyId,
      rank: 1,
      publicKey: testOnlyK1.verifyKey,
    ),
  ]);
  for (var i = 0; i < labels.length; i++) {
    final label = labels[i];
    final check = _object(checks[i]);
    require(
      check['label'] == label,
      '$label must appear in its exact position',
    );
    final result = _object(check['result']);
    final cards = check['cards'];
    final negative = label == 'expired_budget' || label == 'unreadable_state';
    if (negative) {
      require(
        result['outcome'] ==
                (label == 'expired_budget' ? 'aborted' : 'stateUnavailable') &&
            result['checked'] == false &&
            cards is List &&
            cards.isEmpty,
        '$label must not check or post a card',
      );
      continue;
    }
    require(
      result['outcome'] == 'notified' && result['checked'] == true,
      '$label must perform the real check and native publication',
    );
    final hard = label == 'hard_replaces_soft';
    final snapshot = _object(check['snapshot']);
    final encoded = check['envelope'];
    if (encoded is! String ||
        encoded.length > ((maxVersionFileBytes + 2) ~/ 3) * 4) {
      failures.add('$label needs a bounded signed TEST envelope');
      continue;
    }
    try {
      final bytes = base64Decode(encoded);
      final checked = verifier.verify(
        bytes,
        highestAcceptedRank: 0,
        requiredPlatforms: {UpdatePlatform.android},
      );
      final payload = checked.file?.payload;
      final policy = payload?.platforms[UpdatePlatform.android];
      require(
        checked.isAccepted &&
            payload?.sequence == (hard ? 2 : 1) &&
            build is int &&
            policy?.latestBuild == build + 20 &&
            policy?.minBuild == build + (hard ? 1 : 0),
        '$label must exercise the exact soft or hard signed policy',
      );
      require(
        snapshot['platform'] == 'android' &&
            snapshot['installedBuild'] == build &&
            snapshot['rank'] == 1 &&
            snapshot['sequence'] == (hard ? 2 : 1) &&
            snapshot['acceptedEnvelopeSha256'] ==
                sha256.convert(bytes).toString(),
        '$label must persist the exact verified envelope',
      );
      require(
        build is int &&
            (hard
                ? snapshot['notifiedHardMinBuild'] == build + 1 &&
                      snapshot['hardReminderCount'] == 1
                : snapshot['notifiedSoftLatestBuild'] == build + 20),
        '$label must persist its notification dedupe state',
      );
    } on Object {
      failures.add('$label has malformed envelope evidence');
    }
    final after = check['checkAfterMs'];
    final at = snapshot['lastCheckAtMs'];
    final clock = snapshot['clockMs'];
    require(
      after is int && at is int && clock is int && at >= after && at <= clock,
      '$label must finish a new check',
    );
    if (cards is! List || cards.length != 1) {
      failures.add('$label must leave exactly one current update card');
      continue;
    }
    final card = _object(cards.single);
    require(
      card['id'] ==
              (hard
                  ? updateCheckFixtureHardNotificationId
                  : updateCheckFixtureSoftNotificationId) &&
          card['sdk'] == sdk &&
          card['route'] == updateStoreUrlAndroid &&
          (sdk is int && sdk >= 26
              ? card['channelId'] == updateCheckFixtureChannelId &&
                    card['channelImportance'] == 3
              : card['channelId'] == null && card['channelImportance'] == null),
      '$label must bind its owned native card, DEFAULT channel and built-in Play action',
    );
    for (final name in ['bodySha256', 'pendingIntentSha256']) {
      require(
        card[name] is String &&
            RegExp(r'^[0-9a-f]{64}$').hasMatch(card[name] as String),
        '$label needs redacted native $name evidence',
      );
    }
  }
  return failures;
}
