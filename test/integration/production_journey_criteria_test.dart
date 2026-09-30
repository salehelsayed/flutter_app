import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_foreground_push_criteria.dart';

void main() {
  Map<String, Object?> proof() {
    Map<String, Object?> message(String id) => {
      'id': id,
      'text': 'text-$id',
      'incoming': true,
    };
    Map<String, Object?> request(String id) => {
      'kind': 'message',
      'routePayload': 'group:g|message:$id',
    };
    return {
      'cases': [
        {
          'id': 'S1',
          'groupId': 'g',
          'messageId': 'm1',
          'sentText': 'text-m1',
          'notificationBaseline': 0,
          'before': {'messages': []},
          'after': {
            'messages': [message('m1')],
            'notifications': [request('m1')],
          },
        },
        {
          'id': 'S2',
          'groupId': 'g',
          'messageId': 'm2',
          'sentText': 'text-m2',
          'notificationBaseline': 1,
          'before': {
            'messages': [message('m2')],
          },
          'after': {
            'messages': [message('m1'), message('m2')],
            'notifications': [request('m1'), request('m2')],
          },
        },
        {
          'id': 'S3',
          'outcome': {
            'result': 'notificationNeededAfterDrainFailure',
            'drainAttempts': 1,
            'fallbackShown': false,
          },
          'notificationsBefore': [request('m1'), request('m2')],
          'notificationsAfter': [request('m1'), request('m2')],
        },
      ],
    };
  }

  test('all original foreground push assertions are required', () {
    expect(validateProductionForegroundPush(proof()), isEmpty);
  });
  final mutations = <String, void Function(List<dynamic>)>{
    'S1 not missed live': (rows) =>
        rows[0]['before']['messages'] = rows[0]['after']['messages'],
    'S1 wrong text': (rows) =>
        rows[0]['after']['messages'][0]['text'] = 'other',
    'S1 duplicate row': (rows) =>
        rows[0]['after']['messages'].add(rows[0]['after']['messages'][0]),
    'S1 absent notification': (rows) =>
        rows[0]['after']['notifications'].clear(),
    'S1 wrong route': (rows) =>
        rows[0]['after']['notifications'][0]['routePayload'] = 'group:other',
    'S2 absent live': (rows) => rows[1]['before']['messages'].clear(),
    'S2 duplicate notification': (rows) => rows[1]['after']['notifications']
        .add(rows[1]['after']['notifications'][1]),
    'S2 wrong live text': (rows) =>
        rows[1]['before']['messages'][0]['text'] = 'other',
    'S3 wrong result': (rows) =>
        rows[2]['outcome']['result'] = 'notificationNeeded',
    'S3 drain skipped': (rows) => rows[2]['outcome']['drainAttempts'] = 0,
    'S3 repeated drain': (rows) => rows[2]['outcome']['drainAttempts'] = 2,
    'S3 fallback displayed': (rows) =>
        rows[2]['outcome']['fallbackShown'] = true,
    'S3 generic request': (rows) =>
        rows[2]['notificationsAfter'].add({'kind': 'generic'}),
    'missing case': (rows) => rows.removeLast(),
    'duplicate case': (rows) => rows[2] = rows[1],
  };
  for (final mutation in mutations.entries) {
    test('oracle fails when ${mutation.key}', () {
      final candidate = (jsonDecode(jsonEncode(proof())) as Map)
          .cast<String, Object?>();
      mutation.value(candidate['cases'] as List);
      expect(validateProductionForegroundPush(candidate), isNotEmpty);
    });
  }
}
