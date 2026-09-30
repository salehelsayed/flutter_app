import 'dart:convert';
import 'package:crypto/crypto.dart';

const productionSoundText = <String, String>{
  'S1': 'S1: notification sound 1:1',
  'S2': 'S2: notification sound discussion',
  'S3': 'S3: notification sound announcement',
  'S4': 'S4: should be suppressed',
  'S14': 'S14: second message silent update',
  'S15': 'S15: suppressed while viewing group',
  'S15_control': 'S15: control after tracker cleared',
  'S16': 'S16: receiver connected',
};
const productionSoundFirstText = 'S14: first message audible';

/// Input shape consumed by the preserved sound OS verifier. Its parser reads
/// shownCalls[*].silent, so retain the effective publication decision here.
Map<String, Object?> productionSoundOriginalOsInput(
  List<Map> calls, {
  List<int> priorRecordIds = const [],
}) => {
  'shownCalls': [
    for (final call in calls) {'silent': call['silent'] == true},
  ],
  'priorRecordIds': priorRecordIds,
};

String productionSoundLane(String id) => switch (id) {
  'S2' || 'S8' || 'S9' || 'S10' || 'S15' || 'S15_control' => 'chat',
  'S3' || 'S11' || 'S12' || 'S13' => 'announcement',
  _ => 'direct',
};

String _hash(String value) => sha256.convert(utf8.encode(value)).toString();

/// Bind the fast S14 phase-one capture to its exact active package/card/copy.
/// A capture taken after message two cannot certify the intermediate card.
String? productionSoundNativeText(
  String dump,
  String package,
  int id,
  String field,
) {
  final active = dump.split(RegExp(r'\nRanking Config:')).first;
  final records =
      RegExp(r'NotificationRecord\([\s\S]*?(?=\n\s*NotificationRecord\(|$)')
          .allMatches(active)
          .map((m) => m.group(0)!)
          .where(
            (r) =>
                RegExp(r'\bpkg=' + RegExp.escape(package) + r'\b').hasMatch(r),
          )
          .toList();
  if (records.length != 1 ||
      !RegExp(
        r'\bid='
        '$id'
        r'\b',
      ).hasMatch(records.single)) {
    return null;
  }
  final value = RegExp(
    '^\\s*android\\.${RegExp.escape(field)}=(.+)\$',
    multiLine: true,
  ).firstMatch(records.single)?.group(1)?.trim();
  if (value == null) return null;
  return RegExp(r'^[A-Za-z]*String \((.*)\)$').firstMatch(value)?.group(1) ??
      value;
}

String? productionSoundNativeBody(String dump, String package, int id) =>
    productionSoundNativeText(dump, package, id, 'text');

/// Bind S16's actual live or background publication to a run-specific marker.
/// A background-isolate post is invisible to the foreground request observer.
Map<String, Object?> productionSoundS16BackgroundEvidence(
  String log,
  String marker,
) {
  final start = log.indexOf(marker);
  if (start < 0) return {'markerFound': false};
  final events = <Map>[];
  for (final line in log.substring(start + marker.length).split('\n')) {
    final prefix = line.indexOf('[FLOW] ');
    if (prefix < 0) continue;
    try {
      final event = jsonDecode(line.substring(prefix + 7));
      if (event is Map) events.add(event);
    } on FormatException {
      continue;
    }
  }
  final shown = events
      .where((event) => event['event'] == 'PUSH_BACKGROUND_NOTIFICATION_SHOWN')
      .toList();
  final liveShown = events
      .where((event) => event['event'] == 'NOTIFICATION_SHOWN')
      .toList();
  final suppressed = events
      .where(
        (event) => event['event'] == 'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED',
      )
      .toList();
  final shownDetails = shown.length == 1 ? shown.single['details'] : null;
  final liveDetails = liveShown.length == 1
      ? liveShown.single['details']
      : null;
  final suppressedDetails = suppressed.length == 1
      ? suppressed.single['details']
      : null;
  return {
    'markerFound': true,
    'shownCount': shown.length,
    'shownPath': shown.isEmpty && liveShown.length == 1
        ? 'live'
        : shownDetails is Map && shownDetails['durable'] == true
        ? 'durable'
        : shownDetails is Map &&
              shownDetails['messageId'] is String &&
              (shownDetails['messageId'] as String).isNotEmpty &&
              shownDetails['payload'] is String &&
              (shownDetails['payload'] as String).isNotEmpty
        ? 'legacy'
        : null,
    'shownDurable': shownDetails is Map ? shownDetails['durable'] : null,
    'shownProducer': shownDetails is Map ? shownDetails['producer'] : null,
    'shownDisposition': shownDetails is Map
        ? shownDetails['disposition']
        : null,
    'shownSilent': shownDetails is Map ? shownDetails['silent'] : null,
    'liveShownCount': liveShown.length,
    'liveShownDurable': liveDetails is Map ? liveDetails['durable'] : null,
    'liveShownProducer': liveDetails is Map ? liveDetails['producer'] : null,
    'liveShownDisposition': liveDetails is Map
        ? liveDetails['disposition']
        : null,
    'liveShownSilent': liveDetails is Map ? liveDetails['silent'] : null,
    'suppressedCount': suppressed.length,
    'suppressionReason': suppressedDetails is Map
        ? suppressedDetails['reason']
        : null,
  };
}

/// Locate the first audible active card before a later same-ID silent update.
/// The original OS oracle still validates the captured dump and exact ID.
int? productionSoundFirstAudibleNativeId(
  String dump,
  String package,
  String body,
) {
  final active = dump.split(RegExp(r'\nRanking Config:')).first;
  final records =
      RegExp(
        r'NotificationRecord\([\s\S]*?(?=\n\s*NotificationRecord\(|$)',
      ).allMatches(active).map((m) => m.group(0)!).where((record) {
        if (!RegExp(
              r'\bpkg=' + RegExp.escape(package) + r'\b',
            ).hasMatch(record) ||
            !record.contains('channel=mknoon_messages ') ||
            !record.contains('android.text=String ($body)')) {
          return false;
        }
        final flags = RegExp(
          r'\bflags=([A-Z_0-9|]+)',
        ).firstMatch(record)?.group(1);
        return flags != null && !flags.split('|').contains('SILENT');
      }).toList();
  if (records.length != 1) return null;
  return int.tryParse(
    RegExp(r'\bid=(\d+)\b').firstMatch(records.single)?.group(1) ?? '',
  );
}

List<Map> _maps(Object? value) => value is List && value.every((v) => v is Map)
    ? value.cast<Map>()
    : const [];

/// Independent case oracle. The retained original OS disposition CLI also runs
/// on every native capture; neither a command acknowledgement nor UI receipt
/// can substitute for persistence, request copy, silence, and timing evidence.
List<String> validateProductionNotificationSound(Map<String, Object?> proof) {
  final failures = <String>[];
  final cases = _maps(proof['cases']);
  final ids = [
    for (var i = 1; i <= 16; i++) ...['S$i', if (i == 15) 'S15_control'],
  ];
  if (cases.map((c) => c['id']).join(',') != ids.join(',')) {
    return ['S1–S16 and the S15 control require exact ordered receipts'];
  }
  final sender = proof['sender'];
  final groups = proof['groups'];
  if (sender is! Map ||
      sender['peerId'] is! String ||
      sender['username'] is! String ||
      groups is! Map ||
      groups['chat'] is! Map ||
      groups['announcement'] is! Map ||
      proof['runId'] is! String) {
    return ['sound proof lacks exact production fixture identities'];
  }
  final stableIds = <String, int>{};
  for (final row in cases) {
    final id = row['id'] as String;
    final lane = productionSoundLane(id);
    final group = lane == 'direct' ? null : groups[lane] as Map;
    final conversation = group?['id'] ?? sender['peerId'];
    final contact = lane == 'direct' ? conversation : 'group:$conversation';
    final before = row['before'];
    final after = row['after'];
    final messageIds = row['messageIds'];
    final suppressed = id == 'S4' || id == 'S15';
    final count = id == 'S14' ? 2 : 1;
    if (before is! Map ||
        after is! Map ||
        messageIds is! List ||
        messageIds.length != count ||
        messageIds.toSet().length != count ||
        messageIds.any((v) => v is! String || v.isEmpty)) {
      failures.add('$id lacks complete bound observations');
      continue;
    }
    final baseline = _maps(before['notifications']);
    final all = _maps(after['notifications']);
    if (before['notifications'] is! List ||
        after['notifications'] is! List ||
        (id == 'S16'
            ? all.length != baseline.length && all.length != baseline.length + 1
            : all.length != baseline.length + (suppressed ? 0 : count)) ||
        jsonEncode(all.take(baseline.length).toList()) !=
            jsonEncode(baseline)) {
      failures.add('$id notification count or preserved prefix differs');
      continue;
    }
    final calls = all.skip(baseline.length).toList();
    final requests = calls.map((c) => c['requestedSilent']).toList();
    if (requests.any((v) => v is! bool) ||
        (!suppressed &&
            id != 'S16' &&
            (id == 'S14'
                ? jsonEncode(requests) != '[false,true]'
                : !RegExp(r'^S([5-9]|1[0-3])$').hasMatch(id) &&
                      requests.single != false))) {
      failures.add('$id upstream tone decisions differ');
    }
    for (final snapshot in [before, after]) {
      if (snapshot['lifecycle'] != (id == 'S16' ? 'paused' : 'resumed') ||
          (suppressed
              ? snapshot[lane == 'direct' ? 'activePeerId' : 'activeGroupId'] !=
                    contact
              : snapshot['activePeerId'] == sender['peerId'] ||
                    snapshot['activeGroupId'] == contact)) {
        failures.add('$id lacks the actual required visibility state');
      }
    }
    if (suppressed &&
        (row['suppressionWindowMs'] is! int ||
            (row['suppressionWindowMs'] as int) < 6000)) {
      failures.add('$id suppression window did not settle for six seconds');
    }
    if (id == 'S16' && row['receiverConnectedBeforeSend'] != true) {
      failures.add('S16 requires the background receiver to remain connected');
    }
    if (id == 'S16') {
      final provider = row['provider'];
      final send = provider is Map ? provider['send'] : null;
      if (provider is! Map ||
          provider['receiverProfile'] != 'android.production_fcm.journey' ||
          provider['receiverPackage'] != 'com.mknoon.app' ||
          provider['receiverRole'] != 'bob' ||
          provider['nativeIngressObserved'] != true ||
          provider['probeSha256'] is! String ||
          !RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch(provider['probeSha256'] as String) ||
          send is! Map ||
          send['ok'] != true ||
          send['stage'] != 'fcm' ||
          send['operation'] != 'deliver' ||
          send['validateOnly'] != false ||
          send['httpClass'] != '2xx') {
        failures.add('S16 requires accepted FCM delivery and native ingress');
      }
      final native = row['backgroundNative'];
      final livePath = native is Map && native['shownPath'] == 'live';
      final backgroundPath =
          native is Map &&
          (native['shownPath'] == 'legacy' ||
              native['shownPath'] == 'durable' &&
                  native['shownDurable'] == true &&
                  native['shownProducer'] == 'direct_message' &&
                  native['shownDisposition'] == 'osPosted');
      if (native is! Map ||
          native['markerFound'] != true ||
          !(livePath &&
                  native['shownCount'] == 0 &&
                  native['liveShownCount'] == 1 &&
                  native['liveShownDurable'] == true &&
                  native['liveShownProducer'] == 'direct_message' &&
                  native['liveShownDisposition'] == 'osPosted' &&
                  native['liveShownSilent'] == false ||
              backgroundPath &&
                  native['shownCount'] == 1 &&
                  native['shownSilent'] == false &&
                  (native['liveShownCount'] == 0 ||
                      native['liveShownCount'] == 1 &&
                          native['liveShownSilent'] == true)) ||
          native['suppressedCount'] != 1 ||
          native['suppressionReason'] != 'message_event_already_claimed' ||
          native['firstAudibleCardObserved'] != true ||
          native['nativeId'] is! int ||
          native['nativeId'] != stableIds['direct'] ||
          native['firstBodySha256'] != _hash(productionSoundText['S16']!) ||
          native['settledBodySha256'] != _hash(productionSoundText['S16']!) ||
          native['firstTitleSha256'] != _hash('${sender['username']}') ||
          native['settledTitleSha256'] != _hash('${sender['username']}') ||
          native['firstCaptureSha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(native['firstCaptureSha256']) ||
          native['settledCaptureSha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(native['settledCaptureSha256']) ||
          native['logSha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(native['logSha256'])) {
        failures.add('S16 lacks exact audible native publication');
      }
      if (livePath && calls.length != 1) {
        failures.add('S16 live publication requires one observed request');
      }
      if (calls.length == 1) {
        final call = calls.single;
        final expectedSilent = !livePath;
        if (call['kind'] != 'message' ||
            call['contactPeerId'] != sender['peerId'] ||
            call['routePayload'] != sender['peerId'] ||
            call['titleSha256'] != _hash('${sender['username']}') ||
            call['bodySha256'] != _hash(productionSoundText['S16']!) ||
            call['notificationId'] != native?['nativeId'] ||
            call['requestedSilent'] != expectedSilent ||
            call['silent'] != expectedSilent ||
            call['observedAtMicros'] is! int) {
          failures.add(
            'S16 observed request must match its native card and tone',
          );
        }
      }
    }
    final number = int.tryParse(id.substring(1));
    final media = number != null && number >= 5 && number <= 13;
    String? mediaLabel;
    if (media) {
      final locales = after['locales'];
      if (locales is! List || locales.any((v) => v is! String)) {
        failures.add('$id lacks actual device locale');
      } else {
        final language = locales.cast<String>().firstWhere(
          (l) => ['ar', 'de', 'en'].contains(l),
          orElse: () => 'en',
        );
        mediaLabel = const {
          'en': ['Photo', 'Video', 'Voice message'],
          'de': ['Foto', 'Video', 'Sprachnachricht'],
          'ar': ['صورة', 'فيديو', 'رسالة صوتية'],
        }[language]![(number - 5) % 3];
      }
    }
    for (var index = 0; index < count; index++) {
      final messageId = messageIds[index];
      final text = media
          ? ''
          : id == 'S14' && index == 0
          ? productionSoundFirstText
          : productionSoundText[id]!;
      final matches = _maps(
        after['messages'],
      ).where((m) => m['id'] == messageId).toList();
      if (_maps(before['messages']).any((m) => m['id'] == messageId) ||
          matches.length != 1 ||
          matches.single['text'] != text ||
          matches.single['incoming'] != true ||
          matches.single['lane'] != lane ||
          matches.single['conversationId'] != conversation) {
        failures.add('$id exact newly received message missing or duplicated');
      }
      if (id == 'S16' &&
          !{'direct', 'relay'}.contains(matches.singleOrNull?['transport'])) {
        failures.add('S16 must arrive through the live connected bridge');
      }
      if (media) {
        final expectedId = 'notification-${proof['runId']}-${id.toLowerCase()}';
        final attachments = _maps(matches.singleOrNull?['attachments']);
        final type = ['image', 'video', 'audio'][(number - 5) % 3];
        if (messageId != '$expectedId-message' ||
            attachments.length != 1 ||
            attachments.single['id'] != expectedId ||
            attachments.single['messageId'] != messageId ||
            attachments.single['mediaType'] != type ||
            attachments.single['size'] != 4096 ||
            attachments.single['mime'] !=
                (type == 'image' ? 'image/jpeg' : '$type/mp4') ||
            attachments.single['contentHash'] != '${number - 4}' * 64 ||
            attachments.single['encryptionScheme'] != 'blob_aes_256_gcm_v1') {
          failures.add('$id encrypted descriptor persistence differs');
        }
      }
      if (suppressed) continue;
      if (id == 'S16') continue;
      final call = calls[index];
      final body = media ? mediaLabel ?? '' : text;
      final title = lane == 'direct' ? sender['username'] : group!['name'];
      final payload = lane == 'direct'
          ? conversation
          : 'group:$conversation|message:$messageId';
      if (call['kind'] != 'message' ||
          call['contactPeerId'] != contact ||
          call['routePayload'] != payload ||
          call['titleSha256'] != _hash('$title') ||
          call['bodySha256'] !=
              _hash(lane == 'direct' ? body : '${sender['username']}: $body') ||
          call['notificationId'] is! int ||
          call['observedAtMicros'] is! int ||
          call['silent'] is! bool) {
        failures.add('$id exact native publication identity or copy differs');
      } else {
        final nativeId = call['notificationId'] as int;
        if (stableIds.containsKey(lane) && stableIds[lane] != nativeId) {
          failures.add('$id conversation card ID changed');
        }
        stableIds[lane] = nativeId;
      }
    }
    if (id == 'S14') {
      final first = row['first'];
      final firstOs = row['firstOsReceipt'];
      final times = calls.map((c) => c['observedAtMicros']).toList();
      final firstCalls = first is Map ? _maps(first['notifications']) : <Map>[];
      if (firstOs is! Map ||
          firstOs['exitCode'] != 0 ||
          firstOs['bodySha256'] != _hash(productionSoundFirstText) ||
          firstOs['captureSha256'] is! String ||
          !RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch(firstOs['captureSha256'] as String) ||
          firstCalls.length != baseline.length + 1 ||
          jsonEncode(firstCalls) !=
              jsonEncode(all.take(baseline.length + 1).toList()) ||
          times.any((v) => v is! int) ||
          (times.last as int) <= (times.first as int) ||
          (times.last as int) - (times.first as int) >= 10000000 ||
          calls.first['silent'] != false ||
          calls.last['silent'] != true ||
          calls.first['notificationId'] != calls.last['notificationId']) {
        failures.add(
          'S14 requires an observed audible card then same-ID silent update inside ten seconds',
        );
      }
    }
    final os = row['osReceipt'];
    final osId = id == 'S15_control' ? 'S2' : id;
    if (os is! Map ||
        os['exitCode'] != 0 ||
        os['captureSha256'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(os['captureSha256'] as String) ||
        os['stdout'] is! String ||
        !RegExp(
          '^os-capture-verdict scenario=$osId disposition=[a-zA-Z]+ result=pass reason=.* records=[0-9]+\$',
          multiLine: true,
        ).hasMatch(os['stdout'] as String)) {
      failures.add('$id lacks a passing original OS disposition receipt');
    }
  }
  return failures;
}
