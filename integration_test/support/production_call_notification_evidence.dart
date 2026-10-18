import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import '../scripts/reaction_notification_proof_support.dart'
    show extractActiveNotificationCards;

const productionCallIncomingNotificationId = 504;
const productionCallOngoingNotificationId = 505;
const productionCallOngoingChannel = 'mknoon_calls_ongoing_v1';

String _digest(String value) => sha256.convert(utf8.encode(value)).toString();

/// Only static route kinds, positions and selected state leave the UI read.
/// The visible Bluetooth/wired labels and native endpoint IDs are excluded.
List<Map<String, Object?>> productionCallOutputPickerRows(
  String xml, {
  required String packageName,
}) {
  _boundedComplete(xml, 'Call output picker');
  final document = XmlDocument.parse(xml);
  if (document.rootElement.name.local != 'hierarchy') {
    throw const FormatException('Complete output picker hierarchy required.');
  }
  final rows = <Map<String, Object?>>[];
  for (final node in document.descendants.whereType<XmlElement>()) {
    final identifier = node.getAttribute('resource-id') ?? '';
    if (!identifier.startsWith('call-output-choice-')) continue;
    final match = RegExp(
      r'^call-output-choice-(systemDefault|earpiece|speaker|wiredHeadset|bluetooth)-(\d+)$',
    ).firstMatch(identifier);
    final selected = node.getAttribute('selected');
    final bounds = RegExp(
      r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$',
    ).firstMatch(node.getAttribute('bounds') ?? '');
    if (match == null ||
        node.getAttribute('package') != packageName ||
        !{'true', 'false'}.contains(selected) ||
        bounds == null) {
      throw const FormatException(
        'Output picker ownership or route state unreadable.',
      );
    }
    if (node.getAttribute('visible-to-user') == 'false' ||
        node.getAttribute('enabled') != 'true') {
      continue;
    }
    final left = int.parse(bounds.group(1)!);
    final top = int.parse(bounds.group(2)!);
    final right = int.parse(bounds.group(3)!);
    final bottom = int.parse(bounds.group(4)!);
    if (right <= left || bottom <= top) {
      throw const FormatException('Output picker bounds unreadable.');
    }
    rows.add({
      'index': int.parse(match.group(2)!),
      'route': match.group(1),
      'selected': selected == 'true',
      'centerX': (left + right) ~/ 2,
      'centerY': (top + bottom) ~/ 2,
    });
  }
  rows.sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));
  for (var i = 0; i < rows.length; i++) {
    if (rows[i]['index'] != i) {
      throw const FormatException(
        'Output picker rows are partial or ambiguous.',
      );
    }
  }
  return rows;
}

void _boundedComplete(String value, String boundary) {
  if (utf8.encode(value).length > 4 * 1024 * 1024) {
    throw FormatException('$boundary evidence capacity exceeded.');
  }
  if (RegExp(
    r'DUMP TIMEOUT|Error dumping service|FAILED BINDER TRANSACTION',
    caseSensitive: false,
  ).hasMatch(value)) {
    throw FormatException('$boundary diagnostic failed.');
  }
}

/// Actual native ownership and channel state. Names, peer IDs, native keys and
/// unrelated notification content never leave this parser.
List<Map<String, Object?>> productionCallNotificationSnapshot({
  required String dump,
  required String packageName,
  required int uid,
  required int sdk,
  required String peerId,
}) {
  _boundedComplete(dump, 'Call notification');
  if (!dump.contains('Current Notification Manager state:') ||
      !RegExp(r'\n\s*Ranking Config:').hasMatch(dump) ||
      uid < 0 ||
      sdk < 24 ||
      peerId.isEmpty) {
    throw const FormatException(
      'Complete call notification ownership evidence is required.',
    );
  }
  final active = dump.split(RegExp(r'\n\s*Ranking Config:')).first;
  final owned = <int, List<String>>{};
  final keys = <int, Set<String>>{};
  for (final match in RegExp(
    r'NotificationRecord\([\s\S]*?(?=\n\s*NotificationRecord\(|$)',
  ).allMatches(active)) {
    final record = match.group(0)!;
    final header = record.split('\n').first;
    final owner = RegExp(r'\bpkg=([^\s,)]+)').firstMatch(header)?.group(1);
    final id = int.tryParse(
      RegExp(r'\bid=(-?\d+)\b').firstMatch(header)?.group(1) ?? '',
    );
    final key = RegExp(
      r'\bkey=(\d+)\|([^|]+)\|(-?\d+)\|([^|\n]*)\|(\d+):',
    ).firstMatch(header);
    if (owner != packageName) {
      if (key?.group(2) == packageName && key?.group(5) == '$uid') {
        throw const FormatException('Call notification owner/key mismatch.');
      }
      continue;
    }
    if (id != productionCallIncomingNotificationId &&
        id != productionCallOngoingNotificationId) {
      continue;
    }
    if (key == null || key.group(2) != packageName || key.group(3) != '$id') {
      throw const FormatException(
        'Exact native call notification key is missing.',
      );
    }
    if (key.group(5) != '$uid') continue;
    if (key.group(1) != '${uid ~/ 100000}') {
      throw const FormatException('Call notification user mismatch.');
    }
    (owned[id!] ??= []).add(record);
    (keys[id] ??= {}).add(key.group(0)!);
  }
  final scoped =
      'Current Notification Manager state:\n${owned.values.expand((r) => r).join('\n')}\nRanking Config:\n';
  final cards = extractActiveNotificationCards(
    scoped,
    packageName: packageName,
  );
  final result = <Map<String, Object?>>[];
  for (final card in cards) {
    final id = card.id!;
    final records = owned[id]!;
    if (keys[id]!.length != 1) {
      throw const FormatException(
        'Ambiguous native call notification identity.',
      );
    }
    var quiet = false;
    int? importance;
    var expectedChannel = false;
    int? priority;
    bool? soundIsNull;
    bool? vibrationIsNull;
    if (id == productionCallOngoingNotificationId) {
      if (sdk >= 26) {
        final channels = records
            .map(
              (record) => RegExp(
                r'Notification\(channel=([^\s)]+)',
              ).firstMatch(record)?.group(1),
            )
            .toSet();
        expectedChannel =
            channels.length == 1 &&
            channels.single == productionCallOngoingChannel;
        final settings = _ongoingChannelSettings(dump, packageName, uid);
        importance = settings.$1;
        soundIsNull = settings.$2;
        vibrationIsNull = settings.$3;
        quiet =
            expectedChannel &&
            importance == 2 &&
            soundIsNull &&
            vibrationIsNull;
      } else {
        // Before channels, Notification.toString retains the actual priority,
        // effective sound/defaults and vibration fields (AOSP API 24).
        final priorities = records
            .map(
              (record) => int.tryParse(
                RegExp(
                      r'Notification\(pri=(-?\d+) ',
                    ).firstMatch(record)?.group(1) ??
                    '',
              ),
            )
            .toSet();
        priority = priorities.length == 1 ? priorities.single : null;
        soundIsNull = records.every(
          (record) => RegExp(r'\bsound=null(?:\s|\))').hasMatch(record),
        );
        vibrationIsNull = records.every(
          (record) => RegExp(r'\bvibrate=null(?:\s|\))').hasMatch(record),
        );
        quiet = priority == -1 && soundIsNull && vibrationIsNull;
      }
    }
    result.add({
      'id': id,
      'titleSha256': _digest(card.title),
      'peerIdVisible':
          card.title.contains(peerId) || card.body.contains(peerId),
      'bodyKind': card.body == 'Incoming call'
          ? 'incoming'
          : card.body == 'Call in progress'
          ? 'ongoing'
          : 'other',
      'nativeKeySha256': _digest(keys[id]!.single),
      'sdk': sdk,
      'expectedOngoingChannel': sdk >= 26 ? expectedChannel : null,
      'channelImportance': importance,
      'priority': priority,
      'soundIsNull': soundIsNull,
      'vibrationIsNull': vibrationIsNull,
      'quiet': quiet,
      'sourceDumpSha256': _digest(dump),
    });
  }
  return result;
}

(int, bool, bool) _ongoingChannelSettings(
  String dump,
  String packageName,
  int uid,
) {
  final headings = RegExp(
    r'^([ \t]*)AppSettings:[ \t]+([^\s]+)[ \t]+\(([^)]+)\)[^\n]*',
    multiLine: true,
  ).allMatches(dump).toList();
  final sections = <String>[];
  for (var i = 0; i < headings.length; i++) {
    if (headings[i].group(2) == packageName && headings[i].group(3) == '$uid') {
      sections.add(
        dump.substring(
          headings[i].end,
          i + 1 < headings.length ? headings[i + 1].start : dump.length,
        ),
      );
    }
  }
  if (sections.length != 1) {
    throw const FormatException(
      'Exact owned ongoing channel settings are missing.',
    );
  }
  final rows = RegExp(r'NotificationChannel\{[^\n]*')
      .allMatches(sections.single)
      .map((m) => m.group(0)!)
      .where((line) => line.contains("mId='$productionCallOngoingChannel'"))
      .toSet();
  if (rows.length != 1) {
    throw const FormatException(
      'Exact ongoing channel is missing or inconsistent.',
    );
  }
  final line = rows.single;
  final importance = int.tryParse(
    RegExp(r'\bmImportance=(\d+)').firstMatch(line)?.group(1) ?? '',
  );
  if (importance == null) {
    throw const FormatException('Ongoing channel importance is unreadable.');
  }
  return (
    importance,
    RegExp(r'\bmSound=null(?:,|})').hasMatch(line),
    RegExp(r'\bmVibrationEnabled=false(?:,|})').hasMatch(line),
  );
}

/// A UI hierarchy does not establish the absence of a heads-up notification.
/// Read the real SystemUI manager, requiring each complete diagnostic section.
Map<String, Object?> productionCallHeadsUpSnapshot(
  String dump, {
  required String packageName,
  required int uid,
}) {
  _boundedComplete(dump, 'Heads-up');
  final headings = RegExp(
    r'^\s*HeadsUpManager(?:Phone)? state:\s*$',
    multiLine: true,
  ).allMatches(dump).toList();
  if (headings.isEmpty) {
    throw const FormatException('Actual HeadsUpManager state is missing.');
  }
  final nativeKey = RegExp(
    r'(?:^|[={\s])(\d+)\|([A-Za-z0-9_.]+)\|(-?\d+)\|[^|\s}]*\|(\d+)(?=[\s},|]|$)',
  );
  var observed = 0;
  for (var i = 0; i < headings.length; i++) {
    final section = dump.substring(
      headings[i].end,
      i + 1 < headings.length ? headings[i + 1].start : dump.length,
    );
    final footer = RegExp(
      r'^\s*snoozed packages:\s*\d+\s*$',
      multiLine: true,
    ).firstMatch(section);
    final user = RegExp(
      r'^\s*mUser=\d+\s*$',
      multiLine: true,
    ).firstMatch(section);
    if (footer == null || user == null || user.end > footer.start) {
      throw const FormatException('Heads-up manager diagnostic is incomplete.');
    }
    for (final line
        in section
            .substring(user.end, footer.start)
            .split('\n')
            .where((line) => line.trim().isNotEmpty)) {
      final keys = nativeKey.allMatches(line).toList();
      if (keys.length != 1) {
        throw const FormatException(
          'An active heads-up entry has no readable native identity.',
        );
      }
      final key = keys.single;
      if (key.group(1) == '${uid ~/ 100000}' &&
          key.group(2) == packageName &&
          key.group(3) == '505' &&
          key.group(4) == '$uid') {
        observed++;
      }
    }
  }
  return {
    'sectionsObserved': headings.length,
    'ownedOngoingHeadsUpCount': observed,
    'sourceDumpSha256': _digest(dump),
  };
}

/// EventLogTags 2750 and 27530 are OS observations. Tag 2751 is conditional on
/// NotificationManagerService.DBG and is deliberately not used as evidence.
Map<String, Object?> productionCallNotificationEvents(
  String dump, {
  required String packageName,
  required int uid,
  List<String> afterCursor = const [],
}) {
  _boundedComplete(dump, 'Notification event log');
  final lines = dump
      .split('\n')
      .where(
        (line) =>
            RegExp(r'\bnotification_(?:enqueue|canceled)\s*:').hasMatch(line),
      )
      .toList();
  final hashes = lines.map(_digest).toList();
  var start = 0;
  if (afterCursor.isNotEmpty) {
    final matches = <int>[];
    for (var i = 0; i + afterCursor.length <= hashes.length; i++) {
      if (List.generate(
        afterCursor.length,
        (j) => hashes[i + j] == afterCursor[j],
      ).every((v) => v)) {
        matches.add(i);
      }
    }
    if (matches.length != 1) {
      throw const FormatException(
        'Current notification event cursor is missing or ambiguous.',
      );
    }
    start = matches.single + afterCursor.length;
  } else if (lines.length >= 2000) {
    throw const FormatException(
      'Notification event log has no complete initial cursor.',
    );
  }
  final events = <Map<String, Object?>>[];
  final enqueue = RegExp(
    r'\bnotification_enqueue\s*:\s*\[\s*(\d+)\s*,\s*\d+\s*,\s*' +
        RegExp.escape(packageName) +
        r'\s*,\s*(504|505)\s*,[^,]*,\s*(\d+)\s*,(.*)\]\s*$',
  );
  final canceled = RegExp(
    r'\bnotification_canceled\s*:\s*\[\s*'
    '${uid ~/ 100000}'
    r'\|'
    '${RegExp.escape(packageName)}'
    r'\|(504|505)\|[^|,]*\|'
    '$uid'
    r'\s*,',
  );
  for (var i = start; i < lines.length; i++) {
    final posted = enqueue.firstMatch(lines[i]);
    final removed = canceled.firstMatch(lines[i]);
    if (posted != null &&
        posted.group(1) == '$uid' &&
        posted.group(3) == '${uid ~/ 100000}') {
      final status = RegExp(
        r',\s*([012])(?:,\s*[01])?\s*$',
      ).firstMatch(posted.group(4)!);
      if (status == null) {
        throw const FormatException(
          'Owned notification enqueue status is unreadable.',
        );
      }
      if (status.group(1) == '2') continue;
      events.add({
        'kind': 'posted',
        'id': int.parse(posted.group(2)!),
        'eventSha256': hashes[i],
      });
    } else if (removed != null) {
      events.add({
        'kind': 'canceled',
        'id': int.parse(removed.group(1)!),
        'eventSha256': hashes[i],
      });
    }
  }
  return {
    'cursor': hashes.skip(hashes.length > 4 ? hashes.length - 4 : 0).toList(),
    'events': events,
    'sourceDumpSha256': _digest(dump),
  };
}
