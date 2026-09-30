import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_notification_sound_criteria.dart';

String digest(String value) => sha256.convert(utf8.encode(value)).toString();

void mainOriginalOsInputContract() {
  test('original OS verifier receives effective shownCalls flags', () {
    final input = productionSoundOriginalOsInput(
      [
        {'requestedSilent': false, 'silent': false},
        {'requestedSilent': false, 'silent': true},
      ],
      priorRecordIds: [42],
    );
    expect(input, {
      'shownCalls': [
        {'silent': false},
        {'silent': true},
      ],
      'priorRecordIds': [42],
    });
    expect(input.containsKey('silentFlags'), isFalse);
  });
}

Map<String, Object?> fixture() {
  final cases = <Map<String, Object?>>[];
  final messages = <Map<String, Object?>>[];
  final notifications = <Map<String, Object?>>[];
  final groups = {
    'chat': {'id': 'discussion', 'name': 'Discussion'},
    'announcement': {'id': 'announcement', 'name': 'Announcement'},
  };
  for (final id in [
    for (var n = 1; n <= 16; n++) ...['S$n', if (n == 15) 'S15_control'],
  ]) {
    final number = int.tryParse(id.substring(1));
    final lane = {'S2', 'S8', 'S9', 'S10', 'S15', 'S15_control'}.contains(id)
        ? 'chat'
        : {'S3', 'S11', 'S12', 'S13'}.contains(id)
        ? 'announcement'
        : 'direct';
    final conversation = lane == 'direct' ? 'alice' : groups[lane]!['id']!;
    final contact = lane == 'direct' ? 'alice' : 'group:$conversation';
    final suppress = id == 'S4' || id == 'S15';
    Map<String, Object?> snapshot() => {
      'lifecycle': id == 'S16' ? 'paused' : 'resumed',
      'activePeerId': id == 'S4' ? 'alice' : null,
      'activeGroupId': id == 'S15' ? 'group:discussion' : null,
      'notifications': List.of(notifications),
      'messages': List.of(messages),
      'locales': ['en'],
    };
    final before = snapshot();
    final ids = <String>[];
    Map<String, Object?>? first;
    for (var i = 0; i < (id == 'S14' ? 2 : 1); i++) {
      final media = number != null && number >= 5 && number <= 13;
      final messageId = media
          ? 'notification-run-${id.toLowerCase()}-message'
          : '$id-$i';
      ids.add(messageId);
      final text = media
          ? ''
          : id == 'S14' && i == 0
          ? 'S14: first message audible'
          : productionSoundText[id]!;
      final type = media ? ['image', 'video', 'audio'][(number - 5) % 3] : null;
      messages.add({
        'id': messageId,
        'lane': lane,
        'conversationId': conversation,
        'text': text,
        if (id == 'S16') 'transport': 'direct',
        'incoming': true,
        'attachments': [
          if (media)
            {
              'id': 'notification-run-${id.toLowerCase()}',
              'messageId': messageId,
              'mediaType': type,
              'mime': type == 'image' ? 'image/jpeg' : '$type/mp4',
              'size': 4096,
              'contentHash': '${number - 4}' * 64,
              'encryptionScheme': 'blob_aes_256_gcm_v1',
            },
        ],
      });
      if (!suppress && id != 'S16') {
        final body = media
            ? ['Photo', 'Video', 'Voice message'][(number - 5) % 3]
            : text;
        notifications.add({
          'kind': 'message',
          'contactPeerId': contact,
          'routePayload': lane == 'direct'
              ? 'alice'
              : 'group:$conversation|message:$messageId',
          'titleSha256': digest(
            lane == 'direct' ? 'Alice' : groups[lane]!['name']!,
          ),
          'bodySha256': digest(lane == 'direct' ? body : 'Alice: $body'),
          'notificationId':
              ['direct', 'chat', 'announcement'].indexOf(lane) + 10,
          'requestedSilent': id == 'S14' && i == 1,
          'silent': id == 'S14' && i == 1,
          'observedAtMicros': (number ?? 15) * 20000000 + i * 1000000,
        });
      }
      if (id == 'S14' && i == 0) first = snapshot();
    }
    cases.add({
      'id': id,
      'messageIds': ids,
      'before': before,
      'after': snapshot(),
      'first': ?first,
      if (first != null)
        'firstOsReceipt': {
          'exitCode': 0,
          'captureSha256': 'b' * 64,
          'bodySha256': digest('S14: first message audible'),
        },
      if (suppress) 'suppressionWindowMs': 6000,
      if (id == 'S16') 'receiverConnectedBeforeSend': true,
      if (id == 'S16')
        'backgroundNative': {
          'markerFound': true,
          'shownCount': 1,
          'shownPath': 'durable',
          'shownDurable': true,
          'shownProducer': 'direct_message',
          'shownDisposition': 'osPosted',
          'shownSilent': false,
          'liveShownCount': 0,
          'suppressedCount': 1,
          'suppressionReason': 'message_event_already_claimed',
          'firstAudibleCardObserved': true,
          'nativeId': 10,
          'firstBodySha256': digest(productionSoundText['S16']!),
          'settledBodySha256': digest(productionSoundText['S16']!),
          'firstTitleSha256': digest('Alice'),
          'settledTitleSha256': digest('Alice'),
          'firstCaptureSha256': 'd' * 64,
          'settledCaptureSha256': 'e' * 64,
          'logSha256': 'f' * 64,
        },
      if (id == 'S16')
        'provider': {
          'receiverProfile': 'android.production_fcm.journey',
          'receiverPackage': 'com.mknoon.app',
          'receiverRole': 'bob',
          'nativeIngressObserved': true,
          'probeSha256': 'c' * 64,
          'send': {
            'ok': true,
            'stage': 'fcm',
            'operation': 'deliver',
            'validateOnly': false,
            'httpClass': '2xx',
          },
        },
      'osReceipt': {
        'exitCode': 0,
        'captureSha256': 'a' * 64,
        'stdout':
            'os-capture-verdict scenario=${id == 'S15_control' ? 'S2' : id} disposition=audibleStrict result=pass reason=ok records=${suppress ? 0 : 1}\n',
      },
    });
  }
  return jsonDecode(
        jsonEncode({
          'runId': 'run',
          'sender': {'peerId': 'alice', 'username': 'Alice'},
          'groups': groups,
          'cases': cases,
        }),
      )
      as Map<String, Object?>;
}

Map row(Map proof, String id) =>
    (proof['cases'] as List).cast<Map>().singleWhere((r) => r['id'] == id);
Map lastCall(Map proof, String id) =>
    ((row(proof, id)['after'] as Map)['notifications'] as List).last as Map;

Map<String, Object?> addS16SilentReconcile(Map proof) {
  final call = <String, Object?>{
    'kind': 'message',
    'contactPeerId': 'alice',
    'routePayload': 'alice',
    'titleSha256': digest('Alice'),
    'bodySha256': digest(productionSoundText['S16']!),
    'notificationId': 10,
    'requestedSilent': true,
    'silent': true,
    'observedAtMicros': 330000001,
  };
  ((row(proof, 'S16')['after'] as Map)['notifications'] as List).add(call);
  return call;
}

Map<String, Object?> makeS16LivePublication(Map proof) {
  final call = addS16SilentReconcile(proof);
  call['requestedSilent'] = false;
  call['silent'] = false;
  final native = row(proof, 'S16')['backgroundNative'] as Map;
  native['shownPath'] = 'live';
  native['shownCount'] = 0;
  native['shownSilent'] = null;
  native['liveShownCount'] = 1;
  native['liveShownDurable'] = true;
  native['liveShownProducer'] = 'direct_message';
  native['liveShownDisposition'] = 'osPosted';
  native['liveShownSilent'] = false;
  return call;
}

void main() {
  mainOriginalOsInputContract();
  test('first native capture requires one exact active package/card/body', () {
    const first =
        'NotificationRecord(pkg=com.example.sound id=10)\n'
        '  android.title=String (Alice)\n'
        '  android.text=String (S14: first message audible)\n';
    expect(
      productionSoundNativeBody(first, 'com.example.sound', 10),
      productionSoundFirstText,
    );
    expect(
      productionSoundNativeText(first, 'com.example.sound', 10, 'title'),
      'Alice',
    );
    expect(productionSoundNativeBody(first, 'com.example.other', 10), isNull);
    expect(productionSoundNativeBody(first, 'com.example.sound', 11), isNull);
    expect(
      productionSoundNativeBody('$first\n$first', 'com.example.sound', 10),
      isNull,
    );
    expect(
      productionSoundNativeBody(
        '\nRanking Config:\n$first',
        'com.example.sound',
        10,
      ),
      isNull,
    );
    expect(
      productionSoundNativeBody(
        first.replaceFirst(
          'first message audible',
          'second message silent update',
        ),
        'com.example.sound',
        10,
      ),
      isNot(productionSoundFirstText),
    );
  });
  test('first audible native card rejects a later silent update', () {
    const audible =
        'NotificationRecord(pkg=com.example.sound id=10: '
        'Notification(channel=mknoon_messages flags=ONLY_ALERT_ONCE))\n'
        '  android.text=String (S1: notification sound 1:1)\n';
    expect(
      productionSoundFirstAudibleNativeId(
        audible,
        'com.example.sound',
        productionSoundText['S1']!,
      ),
      10,
    );
    expect(
      productionSoundFirstAudibleNativeId(
        audible.replaceFirst('ONLY_ALERT_ONCE', 'ONLY_ALERT_ONCE|SILENT'),
        'com.example.sound',
        productionSoundText['S1']!,
      ),
      isNull,
    );
  });
  test('S16 background log is bound to marker and actual post decisions', () {
    const marker = 'S16-start-unique';
    const log =
        'old [FLOW] {"event":"PUSH_BACKGROUND_NOTIFICATION_SHOWN"}\n'
        'Wave2Sound: S16-start-unique\n'
        'I/flutter: [FLOW] {"event":"PUSH_BACKGROUND_NOTIFICATION_SHOWN",'
        '"details":{"durable":true,"producer":"direct_message",'
        '"disposition":"osPosted","silent":false}}\n'
        'I/flutter: [FLOW] {"event":"PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED",'
        '"details":{"reason":"message_event_already_claimed"}}\n';
    final evidence = productionSoundS16BackgroundEvidence(log, marker);
    expect(evidence['markerFound'], true);
    expect(evidence['shownCount'], 1);
    expect(evidence['shownPath'], 'durable');
    expect(evidence['shownSilent'], false);
    expect(evidence['suppressedCount'], 1);
    expect(
      productionSoundS16BackgroundEvidence(
        log,
        'S16-start-other',
      )['markerFound'],
      false,
    );
  });
  test('S16 legacy background post retains audible native proof', () {
    const log =
        'Wave2Sound: S16-start-legacy\n'
        'I/flutter: [FLOW] {"event":"PUSH_BACKGROUND_NOTIFICATION_SHOWN",'
        '"details":{"messageId":"fcm-id","payload":"peer",'
        '"silent":false}}\n'
        'I/flutter: [FLOW] {"event":"PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED",'
        '"details":{"reason":"message_event_already_claimed"}}\n';
    final evidence = productionSoundS16BackgroundEvidence(
      log,
      'S16-start-legacy',
    );
    expect(evidence['shownPath'], 'legacy');
    final proof = fixture();
    (row(proof, 'S16')['backgroundNative'] as Map).addAll(evidence);
    expect(validateProductionNotificationSound(proof), isEmpty);
  });
  test('S16 live direct post retains one exact audible native card', () {
    const log =
        'Wave2Sound: S16-start-live\n'
        'I/flutter: [FLOW] {"event":"NOTIFICATION_SHOWN",'
        '"details":{"durable":true,"producer":"direct_message",'
        '"disposition":"osPosted","silent":false}}\n'
        'I/flutter: [FLOW] {"event":"PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED",'
        '"details":{"reason":"message_event_already_claimed"}}\n';
    final evidence = productionSoundS16BackgroundEvidence(
      log,
      'S16-start-live',
    );
    expect(evidence['shownPath'], 'live');
    final proof = fixture();
    makeS16LivePublication(proof);
    (row(proof, 'S16')['backgroundNative'] as Map).addAll(evidence);
    expect(validateProductionNotificationSound(proof), isEmpty);
  });
  test('complete original sound cases and group control pass', () {
    expect(validateProductionNotificationSound(fixture()), isEmpty);
  });
  test('S16 permits one exact silent same-card reconciliation', () {
    final proof = fixture();
    addS16SilentReconcile(proof);
    expect(validateProductionNotificationSound(proof), isEmpty);
  });
  final mutations = <String, void Function(Map)>{
    'late native first capture': (p) =>
        (row(p, 'S14')['firstOsReceipt'] as Map)['bodySha256'] = digest(
          'S14: second message silent update',
        ),
    'missing case': (p) => (p['cases'] as List).removeAt(4),
    'duplicate case': (p) => (p['cases'] as List).add(row(p, 'S1')),
    'OS failure': (p) => (row(p, 'S1')['osReceipt'] as Map)['exitCode'] = 1,
    'OS skipped receipt': (p) =>
        (row(p, 'S1')['osReceipt'] as Map)['stdout'] = 'SKIP',
    'unbound OS capture': (p) =>
        (row(p, 'S1')['osReceipt'] as Map)['captureSha256'] = null,
    'wrong route': (p) =>
        lastCall(p, 'S2')['routePayload'] = 'group:other|message:other',
    'wrong body': (p) => lastCall(p, 'S3')['bodySha256'] = digest('wrong'),
    'wrong title': (p) => lastCall(p, 'S8')['titleSha256'] = digest('wrong'),
    'wrong contact': (p) => lastCall(p, 'S5')['contactPeerId'] = 'bob',
    'tone forced audible': (p) => lastCall(p, 'S14')['requestedSilent'] = false,
    'native tone forced audible': (p) => lastCall(p, 'S14')['silent'] = false,
    'late tone': (p) => lastCall(p, 'S14')['observedAtMicros'] = 290000001,
    'new card on update': (p) => lastCall(p, 'S14')['notificationId'] = 99,
    'missed first card': (p) => row(p, 'S14')['first'] = row(p, 'S14')['after'],
    'wrong lifecycle': (p) =>
        (row(p, 'S16')['before'] as Map)['lifecycle'] = 'resumed',
    'dead receiver': (p) =>
        row(p, 'S16')['receiverConnectedBeforeSend'] = false,
    'S16 recovered inbox instead of live bridge': (p) {
      final messages = (row(p, 'S16')['after'] as Map)['messages'] as List;
      (messages.last as Map)['transport'] = 'inbox';
    },
    'S16 provider ingress missing': (p) =>
        (row(p, 'S16')['provider'] as Map)['nativeIngressObserved'] = false,
    'S16 missing background post': (p) =>
        (row(p, 'S16')['backgroundNative'] as Map)['shownCount'] = 0,
    'S16 unbound background path': (p) =>
        (row(p, 'S16')['backgroundNative'] as Map)['shownPath'] = null,
    'S16 duplicate background post': (p) =>
        (row(p, 'S16')['backgroundNative'] as Map)['shownCount'] = 2,
    'S16 silent background post': (p) =>
        (row(p, 'S16')['backgroundNative'] as Map)['shownSilent'] = true,
    'S16 wrong native body': (p) =>
        (row(p, 'S16')['backgroundNative'] as Map)['firstBodySha256'] = digest(
          'wrong',
        ),
    'S16 changed native card': (p) =>
        (row(p, 'S16')['backgroundNative'] as Map)['nativeId'] = 99,
    'S16 absent provider dedupe': (p) =>
        (row(p, 'S16')['backgroundNative'] as Map)['suppressedCount'] = 0,
    'S16 foreground duplicate': (p) {
      final calls = (row(p, 'S16')['after'] as Map)['notifications'] as List;
      calls.add(lastCall(p, 'S14'));
    },
    'S16 audible live repeat': (p) =>
        addS16SilentReconcile(p)['silent'] = false,
    'S16 changed live card ID': (p) =>
        addS16SilentReconcile(p)['notificationId'] = 99,
    'S16 changed live copy': (p) =>
        addS16SilentReconcile(p)['bodySha256'] = digest('wrong'),
    'S16 second live request': (p) {
      final call = addS16SilentReconcile(p);
      ((row(p, 'S16')['after'] as Map)['notifications'] as List).add(call);
    },
    'S16 live post without observed request': (p) {
      makeS16LivePublication(p);
      ((row(p, 'S16')['after'] as Map)['notifications'] as List).removeLast();
    },
    'S16 live post forced silent': (p) =>
        makeS16LivePublication(p)['silent'] = true,
    'S16 live post with second background card': (p) {
      makeS16LivePublication(p);
      (row(p, 'S16')['backgroundNative'] as Map)['shownCount'] = 1;
    },
    'suppression without active chat': (p) =>
        (row(p, 'S4')['after'] as Map)['activePeerId'] = null,
    'short suppression': (p) => row(p, 'S15')['suppressionWindowMs'] = 5999,
    'missing real message': (p) =>
        ((row(p, 'S15')['after'] as Map)['messages'] as List).clear(),
    'duplicate row': (p) {
      final rows = (row(p, 'S6')['after'] as Map)['messages'] as List;
      rows.add(rows.last);
    },
    'wrong descriptor encryption': (p) {
      final message =
          ((row(p, 'S7')['after'] as Map)['messages'] as List).last as Map;
      ((message['attachments'] as List).single as Map)['encryptionScheme'] =
          'plaintext';
    },
    'incomplete locales': (p) =>
        (row(p, 'S10')['after'] as Map)['locales'] = null,
    'duplicate publication': (p) {
      final calls = (row(p, 'S9')['after'] as Map)['notifications'] as List;
      calls.add(calls.last);
    },
  };
  for (final mutation in mutations.entries) {
    test('rejects ${mutation.key}', () {
      final proof = fixture();
      mutation.value(proof);
      expect(validateProductionNotificationSound(proof), isNotEmpty);
    });
  }
}
