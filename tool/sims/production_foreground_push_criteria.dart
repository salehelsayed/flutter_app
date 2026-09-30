/// Independent oracle over production-instance observations. Counts are derived
/// from captured rows and requests, never from a producer's `passed` boolean.
List<String> validateProductionForegroundPush(Map<String, Object?> proof) {
  final failures = <String>[];
  final rows = proof['cases'];
  if (rows is! List || rows.length != 3 || rows.any((row) => row is! Map)) {
    return ['exactly S1, S2 and S3 receipts are required'];
  }
  final cases = rows.cast<Map>();
  if (cases.map((row) => row['id']).join(',') != 'S1,S2,S3') {
    return ['missing, duplicate or out-of-order scenario receipts'];
  }
  for (final scenario in cases.take(2)) {
    final id = scenario['id'];
    final messageId = scenario['messageId'];
    final text = scenario['sentText'];
    final group = scenario['groupId'];
    final before = scenario['before'];
    final after = scenario['after'];
    final baseline = scenario['notificationBaseline'];
    if (messageId is! String ||
        messageId.isEmpty ||
        text is! String ||
        text.isEmpty ||
        group is! String ||
        group.isEmpty ||
        before is! Map ||
        after is! Map ||
        baseline is! int ||
        baseline < 0) {
      failures.add('$id lacks exact message and snapshot identities');
      continue;
    }
    List<Map>? matching(Object? snapshot) {
      if (snapshot is! Map || snapshot['messages'] is! List) return null;
      final messages = snapshot['messages'] as List;
      if (messages.any((message) => message is! Map)) return null;
      return messages
          .cast<Map>()
          .where(
            (message) =>
                message['id'] == messageId && message['incoming'] == true,
          )
          .toList();
    }

    final prior = matching(before);
    final current = matching(after);
    if (prior == null || prior.length != (id == 'S1' ? 0 : 1)) {
      failures.add('$id live delivery precondition is not established');
    }
    if (id == 'S2' && prior?.singleOrNull?['text'] != text) {
      failures.add('S2 live text differs from sender');
    }
    if (current == null ||
        current.length != 1 ||
        current.single['text'] != text) {
      failures.add('$id requires the exact received text exactly once');
    }
    final requests = after['notifications'];
    if (requests is! List ||
        requests.length != baseline + 1 ||
        requests.last is! Map ||
        (requests.last as Map)['kind'] != 'message' ||
        (requests.last as Map)['routePayload'] !=
            'group:$group|message:$messageId') {
      failures.add(
        '$id requires one notification request with the exact route',
      );
    }
  }
  final s3 = cases.last;
  final outcome = s3['outcome'];
  final before = s3['notificationsBefore'];
  final after = s3['notificationsAfter'];
  if (outcome is! Map ||
      outcome['result'] != 'notificationNeededAfterDrainFailure' ||
      outcome['drainAttempts'] != 1 ||
      outcome['fallbackShown'] != false) {
    failures.add(
      'S3 requires one failed drain and suppressed production fallback',
    );
  }
  if (before is! List ||
      after is! List ||
      after.length != before.length ||
      after.any((request) => request is! Map)) {
    failures.add('S3 must publish zero additional notification requests');
  }
  return failures;
}
