import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../features/call/domain/call_session_snapshot.dart';

/// Observation of an already-open canonical database. Never opens or writes it.
/// The only native caller is the debug-source DUMP-protected receiver.
final class DebugCallEvidenceObserver {
  DebugCallEvidenceObserver({
    required this.database,
    required this.accountPeerId,
    required this.readSession,
    required this.readNativeHandle,
    required this.readAccount,
    required this.isCurrent,
    required this.nowMs,
  });

  final Database database;
  final String accountPeerId;
  final CallSessionSnapshot? Function() readSession;
  final String? Function(CallSessionSnapshot) readNativeHandle;
  final Future<String?> Function() readAccount;
  final bool Function() isCurrent;
  final int Function() nowMs;
  bool _disposed = false;
  bool _busy = false;

  static const channel = MethodChannel('mknoon/debug_call_evidence');
  static DebugCallEvidenceObserver? _installed;

  static void install(DebugCallEvidenceObserver observer) {
    if (!kDebugMode) return;
    _installed?._disposed = true;
    _installed = observer;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'snapshot' || call.arguments is! Map) {
        return const {'status': 'rejected'};
      }
      return observer.snapshot(
        Map<String, Object?>.from(call.arguments as Map),
      );
    });
  }

  static void uninstall(DebugCallEvidenceObserver? expected) {
    if (!kDebugMode || expected == null) return;
    expected._disposed = true;
    if (!identical(_installed, expected)) return;
    _installed = null;
    channel.setMethodCallHandler(null);
  }

  Future<Map<String, Object?>> snapshot(Map<String, Object?> request) async {
    if (!kDebugMode || _busy || _disposed) {
      return const {'status': 'unavailable'};
    }
    _busy = true;
    try {
      final nonce = request['nonce'];
      final operation = request['operation'];
      final keys = switch (operation) {
        'baseline' => {'nonce', 'operation'},
        'current' => {'nonce', 'operation', '_nativeCallId'},
        'lookup' => {
          'nonce',
          'operation',
          'callBindingSha256',
          'accountBindingSha256',
          'sinceMs',
          'untilMs',
        },
        _ => <String>{},
      };
      if (keys.isEmpty ||
          request.length != keys.length ||
          !request.keys.every(keys.contains) ||
          nonce is! String ||
          !RegExp(r'^[0-9a-f]{16,64}$').hasMatch(nonce)) {
        return const {'status': 'rejected'};
      }
      bool current() => !_disposed && database.isOpen && isCurrent();
      if (!current()) return const {'status': 'unavailable'};
      final account = await readAccount();
      if (!current() ||
          account == null ||
          account.isEmpty ||
          account != accountPeerId) {
        return const {'status': 'unavailable'};
      }
      final accountHash = _hash('$nonce:account:$account');
      final observed = nowMs();
      final session = readSession();
      String? callId;
      String? nativeHash;
      if (operation == 'current') {
        final handle = session == null ? null : readNativeHandle(session);
        final native = request['_nativeCallId'];
        if (session == null ||
            session.isTerminal ||
            session.callId == null ||
            handle == null ||
            handle != native) {
          return const {'status': 'unavailable'};
        }
        callId = session.callId!.value;
        nativeHash = _hash('$nonce:$handle');
      } else if (session != null && !session.isTerminal) {
        return const {'status': 'unavailable'};
      }
      if (operation == 'lookup') {
        final expected = request['callBindingSha256'];
        final since = request['sinceMs'];
        final until = request['untilMs'];
        if (expected is! String ||
            !_digest.hasMatch(expected) ||
            request['accountBindingSha256'] != accountHash ||
            since is! int ||
            until is! int ||
            since <= 0 ||
            until < since ||
            until - since > 600000 ||
            until > observed ||
            observed - since > 1800000) {
          return const {'status': 'rejected'};
        }
        final rows = await database.query(
          'call_history',
          columns: ['call_id'],
          where: 'started_at >= ? AND started_at <= ?',
          whereArgs: [
            DateTime.fromMillisecondsSinceEpoch(
              since,
              isUtc: true,
            ).toIso8601String(),
            DateTime.fromMillisecondsSinceEpoch(
              until,
              isUtc: true,
            ).toIso8601String(),
          ],
          limit: 129,
        );
        if (!current() || rows.length > 128) {
          return const {'status': 'unavailable'};
        }
        final matches = rows
            .where(
              (r) =>
                  r['call_id'] is String &&
                  _hash('$nonce:call:${r['call_id']}') == expected,
            )
            .toList();
        if (matches.length != 1) return const {'status': 'unavailable'};
        callId = matches.single['call_id']! as String;
      }
      final countRows = await database.rawQuery(
        'SELECT COUNT(*) AS total FROM call_history',
      );
      if (!current() ||
          countRows.length != 1 ||
          countRows.single['total'] is! int) {
        return const {'status': 'unavailable'};
      }
      final rows = callId == null
          ? <Map<String, Object?>>[]
          : await database.query(
              'call_history',
              where: 'call_id = ?',
              whereArgs: [callId],
              limit: 2,
            );
      if (!current() || rows.length > 1) return const {'status': 'unavailable'};
      final afterCount = await database.rawQuery(
        'SELECT COUNT(*) AS total FROM call_history',
      );
      if (!current() ||
          afterCount.length != 1 ||
          afterCount.single['total'] != countRows.single['total']) {
        return const {'status': 'unavailable'};
      }
      final afterAccount = await readAccount();
      if (!current() ||
          afterAccount != account ||
          (operation != 'current' && readSession()?.isTerminal == false) ||
          operation == 'current' &&
              (readSession()?.isTerminal != false ||
                  readSession()?.callId?.value != callId ||
                  readNativeHandle(session!) != request['_nativeCallId'])) {
        return const {'status': 'unavailable'};
      }
      final row = rows.singleOrNull;
      // read_at is user viewing state; the durable terminal projection excludes it.
      final stable = row == null
          ? null
          : (Map<String, Object?>.from(row)..remove('read_at'));
      final ordered = stable == null
          ? null
          : {for (final key in stable.keys.toList()..sort()) key: stable[key]};
      return {
        'schema': 'mknoon.debug-call-history.v1',
        'status': 'snapshot',
        'nonce': nonce,
        'operation': operation,
        'observedAtMs': observed,
        'accountBindingSha256': accountHash,
        'totalRows': countRows.single['total'],
        if (callId != null) 'callBindingSha256': _hash('$nonce:call:$callId'),
        'nativeCallBindingSha256': ?nativeHash,
        if (callId != null) 'matchingRows': rows.length,
        if (ordered != null)
          'rowBindingSha256': _hash('$nonce:row:${jsonEncode(ordered)}'),
        if (session?.startedAt != null && operation == 'current')
          'startedAtMs': session!.startedAt!.millisecondsSinceEpoch,
      };
    } catch (_) {
      return const {'status': 'unavailable'};
    } finally {
      _busy = false;
    }
  }
}

final _digest = RegExp(r'^[0-9a-f]{64}$');
String _hash(String value) => sha256.convert(utf8.encode(value)).toString();
