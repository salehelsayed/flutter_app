import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/update_check/domain/update_store_urls.dart';
import 'package:flutter_app/features/update_check/infrastructure/update_check_fixture_contract.dart';

import '../../../integration_test/scripts/run_production_update_check.dart'
    as driver;
import '../../../integration_test/support/production_update_check_notification.dart';
import '../../../tool/sims/production_update_check_criteria.dart';

// Oracle counterexamples only. These temporary receipts are synthetic inputs,
// not Maestro execution or device evidence.
void main() {
  late Directory directory;
  late Map<String, Object?> proof;
  late List<int> soft, hard;

  String receipt(String label, String flow) {
    final file = File('${directory.path}/$label/result.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({
        'status': 'PASS',
        'exit_status': 0,
        'flows': [flow],
      }),
    );
    return file.path;
  }

  Map<String, Object?> phase(
    String label,
    List<int> sent,
    List<int> accepted,
    String kind,
    int sequence,
    int index,
  ) {
    final after = 1000000 + index * 21601000;
    return {
      'label': label,
      'envelope': base64Encode(sent),
      'checkAfterMs': after,
      'snapshot': {
        'platform': 'android',
        'kind': kind,
        'sequence': sequence,
        'rank': 1,
        'clockMs': after + 1000,
        'lastCheckAtMs': after + 500,
        'acceptedEnvelopeSha256': sha256.convert(accepted).toString(),
      },
      'flowReceipt': receipt(
        label,
        kind == 'hard' ? 'production_update_hard' : 'production_update_soft',
      ),
    };
  }

  List<Map<String, Object?>> phases() =>
      (proof['phases'] as List).cast<Map<String, Object?>>();

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('se41-oracle-');
    soft = driver.signedUpdateFixture(
      installedBuild: 110,
      sequence: 1,
      hard: false,
    );
    hard = driver.signedUpdateFixture(
      installedBuild: 110,
      sequence: 2,
      hard: true,
    );
    proof = {
      'caseId': 'kx0022',
      'runId': 'fixture-run',
      'profileId': 'android.e2e.production_call_local',
      'childBuilds': 0,
      'attemptDirectory': directory.path,
      'phases': [
        phase('baseline_soft', soft, soft, 'soft', 1, 0),
        phase(
          'tampered_hard',
          driver.tamperUpdateFixtureSignature(hard),
          soft,
          'soft',
          1,
          1,
        ),
        phase('valid_hard', hard, hard, 'hard', 2, 2),
      ],
    };
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'tampered forced payload is ineffective; repairing only its signature forces',
    () {
      expect(validateProductionUpdateCheck(proof), isEmpty);
    },
  );

  test('a valid hard envelope cannot masquerade as the bad-signature leg', () {
    phases()[1]['envelope'] = base64Encode(hard);
    expect(validateProductionUpdateCheck(proof), isNotEmpty);
  });

  test(
    'tampering a harmless payload cannot stand in for tampering the forced one',
    () {
      phases()[1]['envelope'] = base64Encode(
        driver.tamperUpdateFixtureSignature(soft),
      );
      expect(validateProductionUpdateCheck(proof), isNotEmpty);
    },
  );

  test(
    'an unchanged earlier check cannot prove a bad manifest was processed',
    () {
      final snapshot = phases()[1]['snapshot'] as Map;
      snapshot['lastCheckAtMs'] = 1000500;
      expect(validateProductionUpdateCheck(proof), isNotEmpty);
    },
  );

  test('decision must match the exact persisted accepted envelope', () {
    (phases()[1]['snapshot'] as Map)['acceptedEnvelopeSha256'] = sha256
        .convert(utf8.encode('different envelope'))
        .toString();
    expect(validateProductionUpdateCheck(proof), isNotEmpty);
  });

  test('a previous UI receipt cannot prove both soft observations', () {
    phases()[1]['flowReceipt'] = phases()[0]['flowReceipt'];
    expect(validateProductionUpdateCheck(proof), isNotEmpty);
  });

  test('successful UI receipt must name the expected flow', () {
    final path = phases()[1]['flowReceipt'] as String;
    File(path).writeAsStringSync(
      jsonEncode({
        'status': 'PASS',
        'exit_status': 0,
        'flows': ['production_update_hard'],
      }),
    );
    expect(validateProductionUpdateCheck(proof), isNotEmpty);
  });

  test('another attempt cannot supply a successful receipt', () async {
    final outside = await Directory.systemTemp.createTemp(
      'se41-other-attempt-',
    );
    try {
      final file = File('${outside.path}/result.json')
        ..writeAsStringSync(
          jsonEncode({
            'status': 'PASS',
            'exit_status': 0,
            'flows': ['production_update_soft'],
          }),
        );
      phases()[1]['flowReceipt'] = file.path;
      expect(validateProductionUpdateCheck(proof), isNotEmpty);
    } finally {
      await outside.delete(recursive: true);
    }
  });

  test(
    'a host platform or another build profile cannot count as this device case',
    () {
      (phases()[0]['snapshot'] as Map)['platform'] = 'macos';
      expect(validateProductionUpdateCheck(proof), isNotEmpty);
      (phases()[0]['snapshot'] as Map)['platform'] = 'android';
      proof['profileId'] = 'android.e2e.production';
      expect(validateProductionUpdateCheck(proof), isNotEmpty);
    },
  );

  Map<String, Object?> nativeProof(String id) {
    Map<String, Object?> posted(bool hardPhase) {
      final bytes = hardPhase ? hard : soft;
      return {
        'label': hardPhase ? 'hard_replaces_soft' : 'eligible_soft',
        'envelope': base64Encode(bytes),
        'checkAfterMs': 1000,
        'result': {'outcome': 'notified', 'checked': true},
        'snapshot': {
          'platform': 'android',
          'installedBuild': 110,
          'rank': 1,
          'sequence': hardPhase ? 2 : 1,
          'acceptedEnvelopeSha256': sha256.convert(bytes).toString(),
          'notifiedSoftLatestBuild': 130,
          if (hardPhase) 'notifiedHardMinBuild': 111,
          'hardReminderCount': hardPhase ? 1 : 0,
          'lastCheckAtMs': 1500,
          'clockMs': 2000,
        },
        'cards': [
          {
            'id': hardPhase ? 41002 : 41001,
            'sdk': 35,
            'channelId': updateCheckFixtureChannelId,
            'channelImportance': 3,
            'route': updateStoreUrlAndroid,
            'bodySha256': sha256
                .convert(utf8.encode('synthetic body'))
                .toString(),
            'pendingIntentSha256': sha256
                .convert(utf8.encode('synthetic token'))
                .toString(),
          },
        ],
      };
    }

    return {
      'caseId': id,
      'runId': 'native-fixture-run',
      'profileId': 'android.e2e.production_call_local',
      'childBuilds': 0,
      'attemptDirectory': directory.path,
      'androidSdk': 35,
      'baselineSnapshot': {'installedBuild': 110, 'inCall': false},
      'baselineCards': <Object?>[],
      'stateModeRestored': true,
      'backgroundReceipt': receipt('native-home', 'production_background'),
      'nativeChecks': [
        if (id == 'kx0025') ...[
          {
            'label': 'unreadable_state',
            'result': {'outcome': 'stateUnavailable', 'checked': false},
            'cards': [],
          },
          {
            'label': 'expired_budget',
            'result': {'outcome': 'aborted', 'checked': false},
            'cards': [],
          },
        ],
        posted(false),
        if (id == 'kx0027') posted(true),
      ],
    };
  }

  test(
    'native budget/unreadable controls and eligible DEFAULT card are distinct',
    () {
      expect(validateProductionUpdateCheck(nativeProof('kx0025')), isEmpty);
    },
  );
  test('native replacement leaves only the distinct hard card', () {
    final value = nativeProof('kx0027');
    expect(validateProductionUpdateCheck(value), isEmpty);
    final checks = value['nativeChecks'] as List;
    (checks.last['cards'] as List).add((checks.first['cards'] as List).single);
    expect(validateProductionUpdateCheck(value), isNotEmpty);
  });
  test(
    'native publication cannot pass with denial, wrong route/channel or cached state',
    () {
      final mutations = <void Function(Map<String, Object?>, Map)>[
        (_, leg) =>
            leg['result'] = {'outcome': 'notPermitted', 'checked': true},
        (_, leg) => (leg['cards'] as List).single['route'] =
            'https://example.invalid/store',
        (_, leg) => (leg['cards'] as List).single['channelImportance'] = 2,
        (_, leg) => (leg['snapshot'] as Map)['lastCheckAtMs'] = 999,
        (_, leg) => (leg['snapshot'] as Map)['acceptedEnvelopeSha256'] = sha256
            .convert(soft)
            .toString(),
        (_, leg) => leg['envelope'] = base64Encode(
          driver.tamperUpdateFixtureSignature(hard),
        ),
        (p, _) => p['profileId'] = 'android.e2e.production',
      ];
      for (var i = 0; i < mutations.length; i++) {
        final value = nativeProof('kx0027');
        mutations[i](value, (value['nativeChecks'] as List).last as Map);
        expect(
          validateProductionUpdateCheck(value),
          isNotEmpty,
          reason: 'counterexample $i',
        );
      }
    },
  );
  test(
    'native suppression needs an empty card set and successful exact restoration',
    () {
      final value = nativeProof('kx0025');
      value['stateModeRestored'] = false;
      expect(validateProductionUpdateCheck(value), isNotEmpty);
      value['stateModeRestored'] = true;
      final checks = value['nativeChecks'] as List;
      checks.first['cards'] = checks.last['cards'];
      expect(validateProductionUpdateCheck(value), isNotEmpty);
    },
  );

  group('owned native notification parser', () {
    const packageName = 'fixture.update.app';
    const uid = 10123;
    String notification({String channel = updateCheckFixtureChannelId}) =>
        '''
Current Notification Manager state:
  Notification List:
    NotificationRecord(0x111: pkg=$packageName user=UserHandle{0} id=41001 tag=mknoon_app_update uid=$uid key=0|$packageName|41001|mknoon_app_update|$uid: Notification(channel=$channel))
      contentIntent=PendingIntent{bbb: PendingIntentRecord{aaa $packageName startActivity}}
      android.title=String (Mknoon update)
      android.text=String (Update available)
Ranking Config:
      AppSettings: $packageName ($uid)
        NotificationChannel{mId='$updateCheckFixtureChannelId', mImportance=3}
''';
    const intent =
        '''
  * PendingIntentRecord{aaa $packageName startActivity}
    uid=$uid packageName=$packageName type=startActivity
    requestCode=41001 requestResolvedType=null
    requestIntent=act=android.intent.action.VIEW dat=$updateStoreUrlAndroid flg=0x10000000
    sent=false canceled=false
''';
    List<Map<String, Object?>> parse(
      String dump, [
      String action = intent,
      int sdk = 35,
    ]) => parseProductionUpdateCheckNotifications(
      notificationDump: dump,
      pendingIntentDump: action,
      packageName: packageName,
      uid: uid,
      sdk: sdk,
    );

    String indexedIntent(String token, int index) => intent.replaceFirst(
      '  * PendingIntentRecord{aaa',
      '    #$index: PendingIntentRecord{$token',
    );

    test(
      'SDK37 indexed headers bind only the exact token between other records',
      () {
        final dump =
            'ACTIVITY MANAGER PENDING INTENTS (dumpsys activity intents)\n'
            '  * $packageName: 3 items\n'
            '${indexedIntent('aaab', 0).replaceAll('requestCode=41001', 'requestCode=41002')}'
            '${indexedIntent('aaa', 1)}'
            '${indexedIntent('bbb', 2).replaceAll('canceled=false', 'canceled=true')}';
        final card = parse(notification(), dump, 37).single;
        expect(card['id'], 41001);
        expect(card['sdk'], 37);
        expect(card['route'], updateStoreUrlAndroid);
        expect(
          card['pendingIntentSha256'],
          sha256.convert(utf8.encode('aaa')).toString(),
        );
      },
    );

    test('SDK37 indexed binding rejects wrong and duplicate exact tokens', () {
      for (final dump in [
        indexedIntent('bbb', 0),
        indexedIntent('aaab', 0),
        '${indexedIntent('aaa', 0)}${indexedIntent('aaa', 1)}',
        '${indexedIntent('aaa', 0)}$intent',
        indexedIntent('aaa', 0).replaceFirst('#0:', '#other:'),
      ]) {
        expect(() => parse(notification(), dump, 37), throwsFormatException);
      }
    });

    test(
      'indexed records cannot borrow request fields from the next block',
      () {
        final incomplete =
            '    #0: PendingIntentRecord{aaa $packageName startActivity}\n';
        expect(
          () => parse(
            notification(),
            '$incomplete${indexedIntent('bbb', 1)}',
            37,
          ),
          throwsFormatException,
        );
      },
    );

    test(
      'binds active card to its exact current request and channel owner',
      () {
        final card = parse(notification()).single;
        expect(card['id'], 41001);
        expect(card['channelImportance'], 3);
        expect(card['route'], updateStoreUrlAndroid);
        expect(jsonEncode(card), isNot(contains('PendingIntentRecord')));
      },
    );
    test('a complete empty dump proves absence, a truncated one cannot', () {
      expect(
        parse('Current Notification Manager state:\nRanking Config:\n'),
        isEmpty,
      );
      expect(
        () => parse('Current Notification Manager state:\n'),
        throwsFormatException,
      );
      expect(
        () => parse('${notification()}\nDUMP TIMEOUT'),
        throwsFormatException,
      );
    });
    test(
      'rejects foreign UID, stale token, canceled intent and mismatched request',
      () {
        for (final action in [
          intent.replaceAll('uid=$uid', 'uid=10124'),
          intent.replaceAll('Record{aaa', 'Record{aab'),
          intent.replaceAll('canceled=false', 'canceled=true'),
          intent.replaceAll('requestCode=41001', 'requestCode=41002'),
          intent.replaceAll(
            'act=android.intent.action.VIEW',
            'act=android.intent.action.MAIN',
          ),
        ]) {
          expect(() => parse(notification(), action), throwsFormatException);
        }
        expect(
          () => parse(notification().replaceAll('($uid)', '(10124)')),
          throwsFormatException,
        );
      },
    );
    test('evidence capacity failure cannot masquerade as no cards', () {
      final oversized = List.filled(4 * 1024 * 1024 + 1, 'x').join();
      expect(() => parse(oversized), throwsFormatException);
    });
  });
}
