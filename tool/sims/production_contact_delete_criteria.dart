import 'dart:convert';

import 'artifact_evidence.dart' show maestroFlowReceiptPassed;

Map<String, Object?> _object(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : {};

String contactDeleteLanguage(String id) => switch (id) {
  'kx0013' => 'de',
  'kx0014' => 'ar',
  _ => 'en',
};

List<String> validateProductionContactDelete(Map<String, Object?> proof) {
  final failures = <String>[];
  void require(bool condition, String reason) {
    if (!condition) failures.add(reason);
  }

  final id = proof['caseId'];
  if (!{'kx0010', 'kx0011', 'kx0012', 'kx0013', 'kx0014'}.contains(id)) {
    return ['an exact registered contact-deletion case is required'];
  }
  final language = contactDeleteLanguage(id as String);
  require(
    proof['runId'] is String &&
        (proof['runId'] as String).isNotEmpty &&
        proof['profileId'] == 'android.e2e.production' &&
        proof['childBuilds'] == 0,
    'contact case must reuse the current attested production journey build',
  );
  require(
    proof['localeRestored'] == true,
    'per-app locale must be restored and read back exactly',
  );
  final before = _object(proof['before']);
  require(
    before['contactA'] == true &&
        before['contactB'] == true &&
        before['historyA'] is List &&
        (before['historyA'] as List).length == 1 &&
        before['historyB'] is List &&
        (before['historyB'] as List).length == 1,
    'both fixture contacts need nonempty independent history baselines',
  );
  final peerA = before['peerA'], peerB = before['peerB'];
  require(
    peerA is String && peerB is String && peerA != peerB,
    'two distinct owned fixture contacts are required',
  );
  final receipts = <String>{};
  void flow(String key, String expected) {
    final path = proof[key];
    require(
      path is String &&
          receipts.add(path) &&
          maestroFlowReceiptPassed(path, proof['attemptDirectory'], expected),
      '$key needs its own actual UI receipt',
    );
  }

  final dialogFlow = id == 'kx0011'
      ? 'production_contact_orbit_dialog'
      : 'production_contact_conversation_dialog';
  flow('dialogReceipt', dialogFlow);
  final dialog = before['dialog'];
  final body = proof['expectedBody'];
  const callWords = {
    'en': 'call history',
    'de': 'Anrufverlauf',
    'ar': 'سجل المكالمات',
  };
  require(
    body is String &&
        body.contains('FixtureAlpha') &&
        body.contains(callWords[language]!),
    'expected copy must explicitly include the contact and call history',
  );
  require(
    dialog is List &&
        dialog.length == 1 &&
        _object(dialog.single)['text'] == body &&
        _object(dialog.single)['language'] == language &&
        _object(dialog.single)['direction'] ==
            (language == 'ar' ? 'rtl' : 'ltr'),
    'actual dialog text, language and direction must match the requested case',
  );
  void preserved(
    Map<String, Object?> snapshot,
    String label, {
    required bool deleted,
  }) {
    require(
      snapshot['peerA'] == peerA &&
          snapshot['peerB'] == peerB &&
          snapshot['contactA'] == !deleted &&
          snapshot['contactB'] == true &&
          jsonEncode(snapshot['historyB']) == jsonEncode(before['historyB']) &&
          (deleted
              ? snapshot['historyA'] is List &&
                    (snapshot['historyA'] as List).isEmpty
              : jsonEncode(snapshot['historyA']) ==
                    jsonEncode(before['historyA'])),
      '$label must preserve B exactly and ${deleted ? 'purge' : 'retain'} A history with its contact',
    );
  }

  if (id == 'kx0010' || id == 'kx0011') {
    require(
      proof['abortTriggerInstalled'] == true &&
          proof['abortTriggerRemoved'] == true,
      'the owned abort trigger must be installed and removed',
    );
    flow('abortedConfirmReceipt', 'production_contact_confirm');
    final aborted = _object(proof['afterAbort']);
    require(
      aborted['events'] is List &&
          (aborted['events'] as List).any(
            (event) =>
                _object(event)['event'] == 'DELETE_CONTACT_ERROR' &&
                _object(event)['fixtureAbort'] == true,
          ),
      'rollback must follow the exact triggered SQL abort, not an unrelated error',
    );
    preserved(aborted, 'failed deletion', deleted: false);
    flow('retryDialogReceipt', dialogFlow);
    flow('confirmReceipt', 'production_contact_confirm');
    preserved(
      _object(proof['afterDelete']),
      'successful deletion',
      deleted: true,
    );
    require(
      proof['verifiedProcessDeath'] == true,
      'restart needs verified owned process death',
    );
    preserved(_object(proof['afterRestart']), 'restart', deleted: true);
  } else {
    flow('cancelReceipt', 'production_contact_cancel');
    preserved(_object(proof['afterCancel']), 'cancel', deleted: false);
  }
  return failures;
}
