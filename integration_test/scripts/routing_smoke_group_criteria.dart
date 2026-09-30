class GroupSmokeCriterion {
  const GroupSmokeCriterion(this.ok, this.detail);

  final bool ok;
  final String detail;
}

GroupSmokeCriterion evaluateG2(Map<String, dynamic> bob) {
  final count = _intValue(bob['count']) ?? 0;
  return GroupSmokeCriterion(count == 5, 'Bob received $count/5; requires 5/5');
}

GroupSmokeCriterion evaluateG4(Map<String, dynamic> bob) {
  final received = _hasReceipt(bob);
  final e2eMs = _intValue(bob['e2eMs']);
  return GroupSmokeCriterion(
    received,
    'Bob e2e=${received ? '${e2eMs}ms' : 'missing'}; requires recovered receipt',
  );
}

GroupSmokeCriterion evaluateG5(
  Map<String, dynamic> alice,
  Map<String, dynamic> bob,
) => _evaluateLifecycle(alice, bob, aliceUsesBooleanReceipt: false);

GroupSmokeCriterion _evaluateLifecycle(
  Map<String, dynamic> alice,
  Map<String, dynamic> bob, {
  required bool aliceUsesBooleanReceipt,
}) {
  final aliceTimeline = _mapList(alice['timeline']);
  final bobTimeline = _mapList(bob['timeline']);
  final failures = <String>[];

  if (aliceTimeline.length < 9) {
    failures.add('Alice timeline=${aliceTimeline.length}/9');
  }
  if (bobTimeline.length < 9) {
    failures.add('Bob timeline=${bobTimeline.length}/9');
  }

  for (final entry in bobTimeline) {
    final n = entry['n'] ?? '?';
    final role = entry['role']?.toString() ?? '';
    if (entry['pending'] == true) {
      failures.add('Bob msg$n pending');
      continue;
    }
    if (role.startsWith('recv') && !_hasReceipt(entry)) {
      failures.add('Bob msg$n missing receipt');
    }
    if (role == 'send' && !_isSuccessfulSend(entry)) {
      failures.add('Bob msg$n send failed');
    }
  }

  for (final entry in aliceTimeline) {
    final n = entry['n'] ?? '?';
    final label = entry['label']?.toString() ?? '';
    if (label == 'recv') {
      final received = entry['received'];
      final receiptPresent = aliceUsesBooleanReceipt
          ? received == true
          : received is Map && _hasReceipt(Map<String, dynamic>.from(received));
      if (!receiptPresent) {
        failures.add('Alice msg$n missing Bob receipt');
      }
    } else if (!_isSuccessfulSend(entry)) {
      failures.add('Alice msg$n send failed');
    }
  }

  if (failures.isEmpty) {
    return GroupSmokeCriterion(
      true,
      'Alice timeline=${aliceTimeline.length} Bob timeline=${bobTimeline.length}; all receiver entries resolved',
    );
  }

  return GroupSmokeCriterion(false, failures.join('; '));
}

GroupSmokeCriterion evaluateG7(
  Map<String, dynamic> alice,
  Map<String, dynamic> bob,
) {
  final rotationMs = _intValue(alice['rotationMs']);
  final pre = bob['preRotation'];
  final post = bob['postRotation'];
  final preReceived = pre is Map && _hasReceipt(Map<String, dynamic>.from(pre));
  final postReceived =
      post is Map && _hasReceipt(Map<String, dynamic>.from(post));
  final bothReceived =
      bob['bothReceived'] == true && preReceived && postReceived;
  return GroupSmokeCriterion(
    rotationMs != null && rotationMs >= 0 && bothReceived,
    'rotation=${rotationMs ?? 'missing'}ms preRx=$preReceived postRx=$postReceived; requires both receipts',
  );
}

GroupSmokeCriterion evaluateG8(
  Map<String, dynamic> alice,
  Map<String, dynamic> bob,
) {
  final sendOk = _isSuccessfulSend(alice);
  final received = _hasReceipt(bob);
  final e2eMs = _intValue(bob['e2eMs']);
  return GroupSmokeCriterion(
    sendOk && received,
    'send=${alice['sendMs'] ?? '-'}ms outcome=${alice['outcome'] ?? '-'} '
    'e2e=${received ? '${e2eMs}ms' : 'missing'}; requires Bob receipt',
  );
}

bool _hasReceipt(Map<String, dynamic> entry) {
  final e2eMs = _intValue(entry['e2eMs']);
  return e2eMs != null && e2eMs >= 0;
}

bool _isSuccessfulSend(Map<String, dynamic> entry) {
  final outcome = entry['outcome']?.toString();
  return outcome == 'success' || outcome == 'successNoPeers';
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList(growable: false);
}

GroupSmokeCriterion evaluateS3(
  Map<String, dynamic> alice,
  Map<String, dynamic> bob,
) {
  return GroupSmokeCriterion(
    _isSuccessfulSend(alice) &&
        alice['sendPath'] == 'inbox' &&
        _hasReceipt(bob),
    'offline inbox requires successful custody and Bob receipt; e2e=${bob['e2eMs']}',
  );
}

GroupSmokeCriterion evaluateS8(
  Map<String, dynamic> alice,
  Map<String, dynamic> bob,
) {
  final result = _evaluateLifecycle(alice, bob, aliceUsesBooleanReceipt: true);
  bool complete(Object? raw) {
    final entries = _mapList(raw);
    return entries.length == 10 &&
        entries
            .map((e) => e['n'])
            .toSet()
            .containsAll(List.generate(10, (i) => i + 1));
  }

  return GroupSmokeCriterion(
    result.ok && complete(alice['timeline']) && complete(bob['timeline']),
    result.detail,
  );
}

GroupSmokeCriterion evaluateS9(
  Map<String, dynamic> alice,
  Map<String, dynamic> bob,
) {
  final sends = _mapList(alice['timings']);
  final receipts = _mapList(bob['timings']);
  return GroupSmokeCriterion(
    sends.length == 5 &&
        sends.every(_isSuccessfulSend) &&
        bob['count'] == 5 &&
        receipts.length == 5 &&
        receipts.every(_hasReceipt),
    'batch inbox requires all five successful sends and receiver receipts; received=${bob['count']}',
  );
}

GroupSmokeCriterion evaluateS10(
  Map<String, dynamic> alice,
  Map<String, dynamic> bob,
) {
  return GroupSmokeCriterion(
    _isSuccessfulSend(alice) &&
        bob['received'] == true &&
        bob['deleted'] == true,
    'deletion outcome=${alice['outcome']} receiverDeleted=${bob['deleted']}',
  );
}

GroupSmokeCriterion evaluateS11(Map<String, dynamic> alice) {
  final timing = alice['voiceTiming'];
  return GroupSmokeCriterion(
    alice['error'] == null && timing is Map && timing['outcome'] == 'success',
    'voice send outcome=${timing is Map ? timing['outcome'] : 'missing'}',
  );
}
