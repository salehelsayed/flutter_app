import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/scripts/run_production_contact_delete.dart'
    show parseContactFixtureLocales;
import '../../../tool/sims/production_contact_delete_criteria.dart';

// Synthetic oracle inputs, never live device/UI evidence.
void main() {
  late Directory attempt;
  late Map<String, Object?> proof;
  const body =
      'This will permanently remove FixtureAlpha, your messages and your call history with them. This cannot be undone.';
  Map<String, Object?> snapshot({bool deleted = false}) => {
    'peerA': 'fixture-a',
    'peerB': 'fixture-b',
    'contactA': !deleted,
    'contactB': true,
    'historyA': [
      if (!deleted) {'call_id': 'owned-a-call', 'read_at': 'fixture-read'},
    ],
    'historyB': [
      {'call_id': 'owned-b-call', 'read_at': null},
    ],
    'dialog': [
      {'text': body, 'direction': 'ltr', 'language': 'en'},
    ],
  };
  String receipt(String label, String name) {
    final file = File('${attempt.path}/$label/result.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({
        'status': 'PASS',
        'exit_status': 0,
        'flows': [name],
      }),
    );
    return file.path;
  }

  setUp(() async {
    attempt = await Directory.systemTemp.createTemp('se47-oracle-');
    proof = {
      'caseId': 'kx0010',
      'runId': 'fixture-run',
      'profileId': 'android.e2e.production',
      'childBuilds': 0,
      'attemptDirectory': attempt.path,
      'localeRestored': true,
      'expectedBody': body,
      'before': snapshot(),
      'abortTriggerInstalled': true,
      'abortTriggerRemoved': true,
      'afterAbort': snapshot()
        ..['events'] = [
          {'event': 'DELETE_CONTACT_ERROR', 'fixtureAbort': true},
        ],
      'afterDelete': snapshot(deleted: true),
      'afterRestart': snapshot(deleted: true),
      'verifiedProcessDeath': true,
      'dialogReceipt': receipt(
        'dialog',
        'production_contact_conversation_dialog',
      ),
      'abortedConfirmReceipt': receipt('abort', 'production_contact_confirm'),
      'retryDialogReceipt': receipt(
        'retry',
        'production_contact_conversation_dialog',
      ),
      'confirmReceipt': receipt('confirm', 'production_contact_confirm'),
    };
  });
  tearDown(() => attempt.delete(recursive: true));

  test(
    'atomic failure, successful purge and durable B preservation can close',
    () {
      expect(validateProductionContactDelete(proof), isEmpty);
    },
  );
  test(
    'deleting call history before a failed contact transaction cannot close',
    () {
      (proof['afterAbort'] as Map)['historyA'] = [];
      expect(validateProductionContactDelete(proof), isNotEmpty);
    },
  );
  test('an unrelated failure cannot prove the SQL rollback boundary', () {
    (proof['afterAbort'] as Map)['events'] = [
      {'event': 'DELETE_CONTACT_ERROR', 'fixtureAbort': false},
    ];
    expect(validateProductionContactDelete(proof), isNotEmpty);
  });
  test(
    'leftover A history or changed B history after restart cannot close',
    () {
      (proof['afterDelete'] as Map)['historyA'] =
          (proof['before'] as Map)['historyA'];
      expect(validateProductionContactDelete(proof), isNotEmpty);
      (proof['afterDelete'] as Map)['historyA'] = [];
      (proof['afterRestart'] as Map)['historyB'] = [];
      expect(validateProductionContactDelete(proof), isNotEmpty);
    },
  );
  test('restoration and real process death are required', () {
    proof['localeRestored'] = false;
    expect(validateProductionContactDelete(proof), isNotEmpty);
    proof['localeRestored'] = true;
    proof['verifiedProcessDeath'] = false;
    expect(validateProductionContactDelete(proof), isNotEmpty);
  });
  test(
    'Arabic dialog must actually be localized and RTL; Cancel keeps both histories',
    () {
      proof['caseId'] = 'kx0014';
      const arabicBody =
          'سيؤدي هذا إلى إزالة FixtureAlpha والرسائل وسجل المكالمات بينكما نهائيًا. لا يمكن التراجع عن ذلك.';
      proof['expectedBody'] = arabicBody;
      (proof['before'] as Map)['dialog'] = [
        {'text': arabicBody, 'language': 'ar', 'direction': 'rtl'},
      ];
      proof['cancelReceipt'] = receipt('cancel', 'production_contact_cancel');
      proof['afterCancel'] = snapshot();
      expect(validateProductionContactDelete(proof), isEmpty);
      ((proof['before'] as Map)['dialog'] as List).single['direction'] = 'ltr';
      expect(validateProductionContactDelete(proof), isNotEmpty);
    },
  );
  test(
    'locale readback binds package/user and preserves an empty default list',
    () {
      expect(
        parseContactFixtureLocales(
          'Locales for fixture.app for user 0 are []',
          'fixture.app',
          0,
        ),
        '',
      );
      expect(
        parseContactFixtureLocales(
          'Locales for fixture.app for user 0 are [de-DE,en]',
          'fixture.app',
          0,
        ),
        'de-DE,en',
      );
      for (final text in [
        'Locales for other.app for user 0 are [en]',
        'Locales for fixture.app for user 10 are [en]',
        'Unknown package fixture.app for userId 0',
      ]) {
        expect(
          () => parseContactFixtureLocales(text, 'fixture.app', 0),
          throwsFormatException,
        );
      }
    },
  );
}
