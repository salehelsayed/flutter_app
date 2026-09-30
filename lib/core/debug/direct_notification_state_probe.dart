import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../database/db_write_transaction.dart';

const directNotificationStateProbeAction = 'direct_notification_state_observe';
const directNotificationStateProbeRequestSchema =
    'mknoon.direct-notification-state-request.v1';
const directNotificationStateProbeResultSchema =
    'mknoon.direct-notification-state-result.v1';

/// Passive observations on the existing installed-app file channel. No
/// transport, notification, navigation, or read-state mutation occurs here.
Future<Map<String, Object?>> runDirectNotificationStateProbe({
  required Database database,
  required Map<String, Object?> config,
}) async {
  String token(String key, {int maximum = 160}) {
    final value = config[key];
    if (value is! String ||
        value.isEmpty ||
        value.length > maximum ||
        !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)) {
      throw FormatException('Invalid direct notification observation $key');
    }
    return value;
  }

  final runId = token('runId', maximum: 80);
  final nonce = token('nonce', maximum: 128);
  final stepId = token('stepId', maximum: 180);
  final peerId = token('contactPeerId');
  final scenario = token('scenario', maximum: 80);
  final phase = token('phase', maximum: 32);
  final markers = config['markers'];
  final unreadScenario = scenario == 'android_message_unread_lifecycle';
  if (config['schema'] != directNotificationStateProbeRequestSchema ||
      config['transport_action'] != directNotificationStateProbeAction ||
      !<String>{
        'android_message_unread_lifecycle',
        'android_physical_recipient',
        'ios_physical_recipient',
      }.contains(scenario) ||
      stepId != 'direct-observe-$runId-$phase' ||
      !(unreadScenario
              ? <String>{'before', 'first', 'dismissed', 'second', 'read'}
              : <String>{'before', 'delivered', 'read'})
          .contains(phase) ||
      markers is! List ||
      markers.length != (unreadScenario ? 2 : 1) ||
      markers.any(
        (value) =>
            value is! String ||
            value.length > 160 ||
            !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value) ||
            !value.startsWith('TC256-$runId-'),
      ) ||
      markers.toSet().length != markers.length) {
    throw const FormatException('Direct notification observation rejected');
  }

  String digest(String value) => sha256.convert(utf8.encode(value)).toString();
  return dbWriteTransaction(database, (transaction) async {
    final totals = (await transaction.rawQuery(
      'SELECT COUNT(*) AS message_count, '
      'COALESCE(SUM(CASE WHEN is_incoming = 1 AND read_at IS NULL '
      'AND hidden_at IS NULL THEN 1 ELSE 0 END), 0) AS unread_count '
      'FROM messages WHERE contact_peer_id = ?',
      <Object?>[peerId],
    )).single;
    final observed = <Map<String, Object?>>[];
    for (final marker in markers.cast<String>()) {
      final rows = await transaction.query(
        'messages',
        columns: <String>['id', 'is_incoming', 'read_at', 'hidden_at'],
        where: 'contact_peer_id = ? AND text = ?',
        whereArgs: <Object?>[peerId, marker],
      );
      if (rows.length > 1) {
        throw StateError('Duplicate run-bound direct message');
      }
      if (rows.isEmpty) {
        observed.add(<String, Object?>{
          'markerSha256': digest(marker),
          'rows': 0,
        });
        continue;
      }
      final row = rows.single;
      final id = row['id'] as String;
      final reactions = await transaction.query(
        'message_reactions',
        columns: <String>['id'],
        where: 'message_id = ?',
        whereArgs: <Object?>[id],
      );
      observed.add(<String, Object?>{
        'markerSha256': digest(marker),
        'rows': 1,
        'messageIdSha256': digest(id),
        'incoming': row['is_incoming'] == 1,
        'read': row['read_at'] != null,
        'hidden': row['hidden_at'] != null,
        'reactionRows': reactions.length,
      });
    }
    return <String, Object?>{
      'schema': directNotificationStateProbeResultSchema,
      'transport_action': directNotificationStateProbeAction,
      'runId': runId,
      'nonce': nonce,
      'stepId': stepId,
      'scenario': scenario,
      'phase': phase,
      'status': 'complete',
      'success': true,
      'observedAt': DateTime.now().toUtc().toIso8601String(),
      'contactPeerIdSha256': digest(peerId),
      'messageCount': totals['message_count'],
      'unreadCount': totals['unread_count'],
      'messages': observed,
    };
  }, exclusive: false);
}
