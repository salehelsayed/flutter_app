import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';

import '../../tool/sims/production_notification_open_criteria.dart';

Map<String, Object?> _proof() {
  Map<String, Object?> snapshot(String id, {required bool after}) {
    final warm = id == 'warm-other-chat';
    return {
      'messages': [
        {
          'id': 'message-$id',
          'contactPeerId': 'bob',
          'incoming': true,
          'text': 'text-$id',
          'readAt': after ? '2026-09-27T16:00:00Z' : null,
        },
      ],
      'conversations': [
        if (warm) {'peerId': 'other', 'onstage': !after, 'routeId': 1},
        if (!warm || after) {'peerId': 'bob', 'onstage': true, 'routeId': 2},
      ],
      'activePeerId': warm && !after ? 'other' : 'bob',
      'lifecycle': after ? 'resumed' : 'paused',
      'navigationEvents': [
        {'operation': 'push', 'routeId': 2},
      ],
      'flowEvents': [
        if (after && id == 'cold-start')
          {
            'event': 'INITIAL_LOCAL_NOTIFICATION_ROUTE_PARSED',
            'details': {
              'routeKind': 'conversation',
              'peerSha256': sha256.convert(utf8.encode('bob')).toString(),
              'payloadSha256': sha256.convert(utf8.encode('bob')).toString(),
              'payloadUtf8Length': 3,
              'canonicalPayloadMatched': true,
            },
          },
        if (after && id == 'same-peer')
          {'event': 'CONVERSATION_NOTIFICATION_ROUTE_ALREADY_ACTIVE'},
      ],
      'notifications': [
        {'kind': 'message', 'routePayload': 'bob'},
      ],
    };
  }

  return {
    'cases': [
      for (final id in ['warm-other-chat', 'cold-start', 'same-peer'])
        {
          'id': id,
          'senderPeerId': 'bob',
          'otherPeerId': 'other',
          'messageId': 'message-$id',
          'sentText': 'text-$id',
          'senderUsername': 'Alice',
          'notificationBaseline': 0,
          'nativeCard': {
            'package': 'com.mknoon.app',
            'notificationId': 41,
            'channel': 'mknoon_messages',
            'title': 'Alice',
            'body': 'text-$id',
            'matchingCardCount': 1,
            'captureSha256': 'b' * 64,
          },
          'provider': {
            'receiverProfile': 'android.production_fcm.journey',
            'receiverPackage': 'com.mknoon.app',
            'receiverRole': 'bob',
            'nativeIngressObserved': true,
            'probeSha256': 'a' * 64,
            'send': {
              'ok': true,
              'stage': 'fcm',
              'operation': 'deliver',
              'validateOnly': false,
              'httpClass': '2xx',
            },
          },
          'before': snapshot(id, after: false),
          'after': snapshot(id, after: true),
          if (id == 'cold-start') ...{
            'coldProcessDeathVerified': true,
            'beforeNonce': 'old',
            'afterNonce': 'new',
          },
        },
    ],
  };
}

void main() {
  test('accepts complete warm, cold and same-peer production observations', () {
    expect(validateProductionNotificationOpen(_proof()), isEmpty);
  });
  test('accepts a headless native card without a foreground request', () {
    final proof = _proof();
    for (final row in (proof['cases'] as List).cast<Map>()) {
      ((row['before'] as Map)['notifications'] as List).clear();
    }
    expect(validateProductionNotificationOpen(proof), isEmpty);
  });
  test('finds the exact app card in an Android notification dump', () {
    const dump = '''
  Enqueued Notification List:
    NotificationRecord(0x1: pkg=com.other user=UserHandle{0} id=8 tag=null: Notification(channel=other))
    NotificationRecord(0x2: pkg=com.mknoon.app user=UserHandle{0} id=41 tag=null: Notification(channel=mknoon_messages))
      notification=
            extras={
                android.title=String (Alice)
                android.text=String (text-warm-other-chat)
            }
Ranking Config:
''';
    final card = productionNotificationOpenNativeCard(
      dump,
      package: 'com.mknoon.app',
      body: 'text-warm-other-chat',
    );
    expect(card?['notificationId'], 41);
    expect(card?['title'], 'Alice');
    expect(card?['channel'], 'mknoon_messages');
    expect(
      productionNotificationOpenNativeCard(
        dump,
        package: 'com.mknoon.app',
        body: 'other text',
      ),
      isNull,
    );
    expect(
      productionNotificationOpenNativeCard(
        dump.replaceFirst('Ranking Config:', '''
    NotificationRecord(0x3: pkg=com.mknoon.app user=UserHandle{0} id=42 tag=null: Notification(channel=mknoon_messages))
      notification=
            extras={
                android.title=String (Alice)
                android.text=String (text-warm-other-chat)
            }
Ranking Config:'''),
        package: 'com.mknoon.app',
        body: 'text-warm-other-chat',
      ),
      isNull,
    );
  });
  final mutations = <String, void Function(List<dynamic>)>{
    'missing case': (rows) => rows.removeLast(),
    'duplicate case': (rows) => rows[1] = rows[0],
    'wrong message text': (rows) =>
        rows[0]['after']['messages'][0]['text'] = 'different',
    'duplicate row': (rows) =>
        rows[0]['after']['messages'].add(rows[0]['after']['messages'][0]),
    'wrong peer payload': (rows) =>
        rows[0]['before']['notifications'][0]['routePayload'] = 'other',
    'missing native card': (rows) => rows[0].remove('nativeCard'),
    'wrong native body': (rows) => rows[0]['nativeCard']['body'] = 'other',
    'wrong native title': (rows) => rows[0]['nativeCard']['title'] = 'other',
    'wrong native package': (rows) =>
        rows[0]['nativeCard']['package'] = 'com.other',
    'wrong native channel': (rows) =>
        rows[0]['nativeCard']['channel'] = 'other',
    'duplicate native card': (rows) =>
        rows[0]['nativeCard']['matchingCardCount'] = 2,
    'provider acceptance missing': (rows) =>
        rows[0]['provider']['send']['ok'] = false,
    'native ingress missing': (rows) =>
        rows[0]['provider']['nativeIngressObserved'] = false,
    'duplicate request': (rows) => rows[0]['before']['notifications'].add({
      'kind': 'message',
      'routePayload': 'bob',
    }),
    'read before tap': (rows) =>
        rows[0]['before']['messages'][0]['readAt'] = 'already-read',
    'unread after tap': (rows) =>
        rows[0]['after']['messages'][0]['readAt'] = null,
    'simulated background only': (rows) =>
        rows[0]['before']['lifecycle'] = 'resumed',
    'wrong foreground route': (rows) =>
        rows[0]['after']['conversations'][1]['onstage'] = false,
    'old chat still visible': (rows) =>
        rows[0]['after']['conversations'][0]['onstage'] = true,
    'old route destroyed': (rows) =>
        rows[0]['after']['conversations'].removeAt(0),
    'cold process not killed': (rows) =>
        rows[1]['coldProcessDeathVerified'] = false,
    'cold nonce reused': (rows) => rows[1]['afterNonce'] = 'old',
    'cold process restarted without initial notification payload': (rows) =>
        rows[1]['after']['flowEvents'].clear(),
    'cold initial payload belongs to another peer': (rows) =>
        rows[1]['after']['flowEvents'][0]['details']['peerSha256'] = 'wrong',
    'duplicate cold initial payload receipt': (rows) =>
        rows[1]['after']['flowEvents'].add(rows[1]['after']['flowEvents'][0]),
    'cold old route survived': (rows) => rows[1]['after']['conversations'].add({
      'peerId': 'other',
      'onstage': false,
    }),
    'same-peer extra push': (rows) =>
        rows[2]['after']['navigationEvents'].add({'operation': 'push'}),
    'same-peer guard absent': (rows) => rows[2]['after']['flowEvents'].clear(),
    'same-peer route replaced': (rows) =>
        rows[2]['after']['conversations'][0]['routeId'] = 9,
    'same-peer duplicate route': (rows) => rows[2]['after']['conversations']
        .add({'peerId': 'bob', 'onstage': false}),
    'navigation observation omitted': (rows) =>
        rows[2]['before'].remove('navigationEvents'),
    'malformed observation': (rows) =>
        rows[2]['after']['flowEvents'] = ['producer-pass'],
  };
  for (final mutation in mutations.entries) {
    test('rejects ${mutation.key}', () {
      final proof = jsonDecode(jsonEncode(_proof())) as Map<String, dynamic>;
      mutation.value(proof['cases'] as List);
      expect(validateProductionNotificationOpen(proof), isNotEmpty);
    });
  }
}
