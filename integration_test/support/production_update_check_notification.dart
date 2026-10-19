import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/features/update_check/infrastructure/update_check_fixture_contract.dart';

import '../scripts/reaction_notification_proof_support.dart'
    show extractActiveNotificationCards;

/// Maestro cannot inspect the app's OS-held PendingIntent or channel settings.
/// Reuse the suite's active-card parser and read only the pinned app's two IDs.
/// Raw dumps and native tokens are not included in the returned evidence.
List<Map<String, Object?>> parseProductionUpdateCheckNotifications({
  required String notificationDump,
  required String pendingIntentDump,
  required String packageName,
  required int uid,
  required int sdk,
}) {
  const capacity = 4 * 1024 * 1024;
  if (notificationDump.length > capacity ||
      pendingIntentDump.length > capacity) {
    throw const FormatException(
      'Update notification evidence capacity exceeded.',
    );
  }
  if (!notificationDump.contains('Current Notification Manager state:') ||
      !RegExp(r'\n\s*Ranking Config:').hasMatch(notificationDump) ||
      RegExp(
        r'DUMP TIMEOUT|Error dumping service|FAILED BINDER TRANSACTION',
      ).hasMatch(notificationDump)) {
    throw const FormatException('A complete notification dump is required.');
  }
  final ids = {
    updateCheckFixtureSoftNotificationId,
    updateCheckFixtureHardNotificationId,
  };
  final cards = extractActiveNotificationCards(
    notificationDump,
    packageName: packageName,
  ).where((card) => ids.contains(card.id)).toList();
  if (cards.isEmpty) return [];
  final importance = sdk >= 26
      ? _channelImportance(notificationDump, packageName, uid)
      : null;
  final records =
      RegExp(r'NotificationRecord\([\s\S]*?(?=\n\s*NotificationRecord\(|$)')
          .allMatches(
            notificationDump.split(RegExp(r'\n\s*Ranking Config:')).first,
          )
          .map((match) => match.group(0)!)
          .toList();
  final result = <Map<String, Object?>>[];
  for (final card in cards) {
    final key = RegExp(
      r'\bkey='
      '${uid ~/ 100000}'
      r'\|'
      '${RegExp.escape(packageName)}'
      r'\|'
      '${card.id}'
      r'\|[^\n|]*\|'
      '$uid'
      r':',
    );
    final owned = records
        .where((record) => key.hasMatch(record.split('\n').first))
        .toList();
    if (owned.isEmpty) {
      throw const FormatException('Owned notification identity is missing.');
    }
    final channels = <String>{};
    final tokens = <String>{};
    for (final record in owned) {
      final channel = RegExp(
        r'Notification\(channel=([^\s)]+)',
      ).firstMatch(record)?.group(1);
      final token = RegExp(
        r'contentIntent=PendingIntent\{[^\n]*?PendingIntentRecord\{([0-9a-fA-F]+)\b',
      ).firstMatch(record)?.group(1);
      if (channel != null) channels.add(channel);
      if (token != null) tokens.add(token);
    }
    if (tokens.length != 1 || sdk >= 26 && channels.length != 1) {
      throw const FormatException(
        'Exact channel and PendingIntent binding are required.',
      );
    }
    final token = tokens.single;
    // AOSP PendingIntentRecord.dump uses toShortString(false, ...), retaining
    // the full request URI. Its package-grouped dump prefixes records with #N:;
    // retain legacy bare/asterisk headers and bind only this active card token.
    final headers = RegExp(
      r'^[ \t]*(?:\*[ \t]*|#[0-9]+:[ \t]*)?PendingIntentRecord\{([0-9a-fA-F]+)\b[^\n]*',
      multiLine: true,
    ).allMatches(pendingIntentDump).toList();
    final blocks = <String>[];
    for (var i = 0; i < headers.length; i++) {
      if (headers[i].group(1) == token) {
        blocks.add(
          pendingIntentDump.substring(
            headers[i].start,
            i + 1 < headers.length
                ? headers[i + 1].start
                : pendingIntentDump.length,
          ),
        );
      }
    }
    if (blocks.length != 1) {
      throw const FormatException('Current pending activity is missing.');
    }
    final block = blocks.single;
    final request =
        RegExp(r'\brequestIntent=([^\n]+)').firstMatch(block)?.group(1) ?? '';
    final uri = RegExp(r'\bdat=([^\s}]+)').firstMatch(request)?.group(1);
    final owner = RegExp(r'\bpackageName=([^\s]+)').firstMatch(block)?.group(1);
    final actualUid = int.tryParse(
      RegExp(r'\buid=(\d+)').firstMatch(block)?.group(1) ?? '',
    );
    final code = int.tryParse(
      RegExp(r'\brequestCode=(\d+)').firstMatch(block)?.group(1) ?? '',
    );
    if (owner != packageName ||
        actualUid != uid ||
        code != card.id ||
        !request.contains('act=android.intent.action.VIEW') ||
        block.contains('canceled=true') ||
        uri == null) {
      throw const FormatException(
        'Notification action does not match its owned live intent.',
      );
    }
    result.add({
      'id': card.id,
      'channelId': sdk >= 26 ? channels.single : null,
      'channelImportance': importance,
      'sdk': sdk,
      'route': uri,
      'bodySha256': sha256.convert(utf8.encode(card.body)).toString(),
      'pendingIntentSha256': sha256.convert(utf8.encode(token)).toString(),
    });
  }
  return result;
}

int _channelImportance(String dump, String packageName, int uid) {
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
    throw const FormatException('Owned channel settings are missing.');
  }
  final importance = <int>{};
  for (final channel in RegExp(
    r'NotificationChannel\{[^\n]*',
  ).allMatches(sections.single)) {
    final text = channel.group(0)!;
    if (!text.contains("mId='$updateCheckFixtureChannelId'")) continue;
    final value = int.tryParse(
      RegExp(r'\bmImportance=(\d+)').firstMatch(text)?.group(1) ?? '',
    );
    if (value != null) importance.add(value);
  }
  if (importance.length != 1) {
    throw const FormatException('Exact live channel importance is missing.');
  }
  return importance.single;
}
