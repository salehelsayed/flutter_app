import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Read the active Android card before the tap. A background isolate can post
/// this card without adding a request to the foreground isolate's observer.
Map<String, Object?>? productionNotificationOpenNativeCard(
  String dump, {
  required String package,
  required String body,
}) {
  final active = dump.split(RegExp(r'\nRanking Config:')).first;
  final records = active
      .split(RegExp(r'\n\s*NotificationRecord\('))
      .skip(1)
      .map((text) => 'NotificationRecord($text')
      .where((text) {
        final header = text.split('\n').first;
        return RegExp(
          r'\bpkg=' + RegExp.escape(package) + r'\b',
        ).hasMatch(header);
      })
      .toList();
  String? field(String record, String name) => RegExp(
    r'^\s*android\.' + RegExp.escape(name) + r'=String \((.*)\)$',
    multiLine: true,
  ).firstMatch(record)?.group(1);
  final matches = records.where((record) => field(record, 'text') == body);
  if (matches.length != 1) return null;
  final record = matches.single;
  final header = record.split('\n').first;
  final id = int.tryParse(
    RegExp(r'\bid=(\d+)\b').firstMatch(header)?.group(1) ?? '',
  );
  final channel = RegExp(
    r'Notification\(channel=([^\s)]+)',
  ).firstMatch(header)?.group(1);
  final title = field(record, 'title');
  if (id == null || channel == null || title == null) return null;
  return {
    'package': package,
    'notificationId': id,
    'channel': channel,
    'title': title,
    'body': body,
    'matchingCardCount': matches.length,
    'captureSha256': sha256.convert(utf8.encode(dump)).toString(),
  };
}

/// Original warm/cold/same-peer route assertions, plus actual native lifecycle
/// and exact persisted-message observations from the production replacement.
List<String> validateProductionNotificationOpen(Map<String, Object?> proof) {
  final failures = <String>[];
  final raw = proof['cases'];
  if (raw is! List ||
      raw.length != 3 ||
      raw.any((value) => value is! Map) ||
      raw.cast<Map>().map((row) => row['id']).join(',') !=
          'warm-other-chat,cold-start,same-peer') {
    return ['exactly warm, cold-start and same-peer receipts are required'];
  }
  for (final row in raw.cast<Map>()) {
    final id = row['id'];
    final peer = row['senderPeerId'];
    final other = row['otherPeerId'];
    final before = row['before'];
    final after = row['after'];
    final provider = row['provider'];
    final nativeCard = row['nativeCard'];
    if (peer is! String ||
        peer.isEmpty ||
        other is! String ||
        peer == other ||
        before is! Map ||
        after is! Map ||
        row['messageId'] is! String ||
        (row['messageId'] as String).isEmpty ||
        row['sentText'] is! String ||
        (row['sentText'] as String).isEmpty ||
        row['notificationBaseline'] is! int ||
        (row['notificationBaseline'] as int) < 0) {
      failures.add('$id lacks bound peer/message observations');
      continue;
    }
    if (provider is! Map ||
        provider['receiverProfile'] != 'android.production_fcm.journey' ||
        provider['receiverPackage'] != 'com.mknoon.app' ||
        provider['receiverRole'] != 'bob' ||
        provider['nativeIngressObserved'] != true ||
        provider['probeSha256'] is! String ||
        !RegExp(
          r'^[a-f0-9]{64}$',
        ).hasMatch(provider['probeSha256'] as String) ||
        provider['send'] is! Map ||
        (provider['send'] as Map)['ok'] != true ||
        (provider['send'] as Map)['stage'] != 'fcm' ||
        (provider['send'] as Map)['operation'] != 'deliver' ||
        (provider['send'] as Map)['validateOnly'] != false ||
        (provider['send'] as Map)['httpClass'] != '2xx') {
      failures.add(
        '$id lacks accepted production FCM delivery and native ingress',
      );
    }
    if (nativeCard is! Map ||
        nativeCard['package'] != 'com.mknoon.app' ||
        nativeCard['notificationId'] is! int ||
        (nativeCard['notificationId'] as int) <= 0 ||
        nativeCard['channel'] != 'mknoon_messages' ||
        nativeCard['title'] != row['senderUsername'] ||
        nativeCard['body'] != row['sentText'] ||
        nativeCard['matchingCardCount'] != 1 ||
        nativeCard['captureSha256'] is! String ||
        !RegExp(
          r'^[a-f0-9]{64}$',
        ).hasMatch(nativeCard['captureSha256'] as String)) {
      failures.add('$id lacks one exact active Android notification card');
    }
    for (final snapshot in [before, after]) {
      for (final field in [
        'messages',
        'conversations',
        'navigationEvents',
        'flowEvents',
        'notifications',
      ]) {
        if (snapshot[field] is! List ||
            (snapshot[field] as List).any((v) => v is! Map)) {
          failures.add('$id lacks complete $field observations');
        }
      }
    }
    List<Map> maps(Map source, String name) =>
        source[name] is List && (source[name] as List).every((v) => v is Map)
        ? (source[name] as List).cast<Map>()
        : const [];
    final priorMessages = maps(
      before,
      'messages',
    ).where((m) => m['id'] == row['messageId']).toList();
    final finalMessages = maps(
      after,
      'messages',
    ).where((m) => m['id'] == row['messageId']).toList();
    bool exactMessage(List<Map> values) =>
        values.length == 1 &&
        values.single['incoming'] == true &&
        values.single['text'] == row['sentText'] &&
        values.single['contactPeerId'] == peer;
    if (!exactMessage(priorMessages) || !exactMessage(finalMessages)) {
      failures.add(
        '$id requires the exact incoming message once before and after tap',
      );
    }
    if (priorMessages.singleOrNull?['readAt'] != null ||
        finalMessages.singleOrNull?['readAt'] == null) {
      failures.add('$id must preserve unread-before/read-after distinction');
    }
    if (before['lifecycle'] != 'paused' || after['lifecycle'] != 'resumed') {
      failures.add('$id requires actual background and foreground lifecycle');
    }
    final requests = maps(before, 'notifications');
    final baseline = row['notificationBaseline'] as int;
    if (requests.length < baseline ||
        requests.length > baseline + 1 ||
        (requests.length == baseline + 1 &&
            (requests.last['kind'] != 'message' ||
                requests.last['routePayload'] != peer))) {
      failures.add(
        '$id has an invalid foreground notification request or peer payload',
      );
    }
    final routes = maps(after, 'conversations');
    final targetRoutes = routes
        .where((route) => route['peerId'] == peer)
        .toList();
    if (targetRoutes.length != 1 ||
        targetRoutes.single['onstage'] != true ||
        after['activePeerId'] != peer ||
        routes.any(
          (route) => route['peerId'] == other && route['onstage'] == true,
        )) {
      failures.add(
        '$id must show one real sender conversation above other chat',
      );
    }
    if (id == 'warm-other-chat' &&
        (!maps(before, 'conversations').any(
              (route) => route['peerId'] == other && route['onstage'] == true,
            ) ||
            !routes.any(
              (route) => route['peerId'] == other && route['onstage'] == false,
            ))) {
      failures.add(
        'warm tap must preserve the mounted other-chat route underneath',
      );
    }
    if (id == 'cold-start') {
      final parsed = maps(after, 'flowEvents')
          .where(
            (event) =>
                event['event'] == 'INITIAL_LOCAL_NOTIFICATION_ROUTE_PARSED',
          )
          .toList();
      final details = parsed.singleOrNull?['details'];
      final peerBytes = utf8.encode(peer);
      final digest = sha256.convert(peerBytes).toString();
      if (parsed.length != 1 ||
          details is! Map ||
          details['routeKind'] != 'conversation' ||
          details['peerSha256'] != digest ||
          details['payloadSha256'] != digest ||
          details['payloadUtf8Length'] != peerBytes.length ||
          details['canonicalPayloadMatched'] != true) {
        failures.add(
          'cold tap requires the exact plugin initial-payload routing event',
        );
      }
      if (row['coldProcessDeathVerified'] != true ||
          row['beforeNonce'] is! String ||
          row['afterNonce'] is! String ||
          row['beforeNonce'] == row['afterNonce'] ||
          routes.any((route) => route['peerId'] == other)) {
        failures.add(
          'cold tap requires process death, fresh invocation and rebuilt route stack',
        );
      }
    }
    if (id == 'same-peer') {
      final priorRoutes = maps(
        before,
        'conversations',
      ).where((route) => route['peerId'] == peer).toList();
      final beforePushes = maps(
        before,
        'navigationEvents',
      ).where((event) => event['operation'] == 'push').length;
      final afterPushes = maps(
        after,
        'navigationEvents',
      ).where((event) => event['operation'] == 'push').length;
      int guards(Map snapshot) => maps(snapshot, 'flowEvents')
          .where(
            (event) =>
                event['event'] ==
                'CONVERSATION_NOTIFICATION_ROUTE_ALREADY_ACTIVE',
          )
          .length;
      if (priorRoutes.length != 1 ||
          priorRoutes.single['onstage'] != true ||
          beforePushes != afterPushes ||
          guards(after) <= guards(before) ||
          priorRoutes.single['routeId'] !=
              targetRoutes.singleOrNull?['routeId']) {
        failures.add(
          'same-peer tap must fire the production guard without adding or replacing a route',
        );
      }
    }
  }
  return failures;
}
