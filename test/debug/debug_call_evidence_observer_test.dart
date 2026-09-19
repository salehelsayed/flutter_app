import 'dart:async';
import 'dart:io';

import 'package:flutter_app/debug/debug_call_evidence_observer.dart';
import 'package:flutter_app/core/database/migrations/117_call_history.dart';
import 'package:flutter_app/features/call/data/call_history_repository_impl.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  const nonce = '1234567890abcdef';
  const call = '66666666-6666-4666-8666-666666666666';
  const native = '77777777-7777-4777-8777-777777777777';
  final start = DateTime.utc(2026, 9, 18, 12);
  late Directory dir;
  late Database db;
  CallSessionSnapshot? session;
  String? account;
  bool current = true;
  late Future<String?> Function() accountReader;
  DebugCallEvidenceObserver observer() => DebugCallEvidenceObserver(
    database: db,
    accountPeerId: 'private-account',
    readSession: () => session,
    readNativeHandle: (_) => native,
    readAccount: () => accountReader(),
    isCurrent: () => current,
    nowMs: () => start.add(const Duration(minutes: 2)).millisecondsSinceEpoch,
  );
  Map<String, Object?> req(String op) => {'nonce': nonce, 'operation': op};
  void connect() {
    session = CallSessionSnapshot.active(
      callId: CallId.parse(call),
      contactPeerId: 'private-contact',
      direction: CallDirection.outgoing,
      state: CallState.connected,
      callerAccountPeerId: 'private-account',
      callerDeviceId: 'private-device',
      startedAt: start,
      connectedAt: start,
    );
  }

  Future<void> terminal() async {
    session = null;
    await CallHistoryRepositoryImpl(db).upsertTerminal(
      CallHistoryEntry(
        callId: CallId.parse(call),
        contactAccountPeerId: 'private-contact',
        direction: CallDirection.outgoing,
        terminalReason: CallEndReason.localHangup,
        status: CallHistoryStatus.completed,
        startedAt: start,
        connectedAt: start,
        endedAt: start.add(const Duration(seconds: 20)),
        transportRoute: null,
        createdAt: start,
        updatedAt: start,
      ),
    );
  }

  Map<String, Object?> lookup(Map<String, Object?> live) => {
    ...req('lookup'),
    'callBindingSha256': live['callBindingSha256'],
    'accountBindingSha256': live['accountBindingSha256'],
    'sinceMs': start
        .subtract(const Duration(seconds: 1))
        .millisecondsSinceEpoch,
    'untilMs': start.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
  };
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('call-evidence-');
    db = await openDatabase(
      '${dir.path}/history.db',
      singleInstance: false,
      version: 1,
      onCreate: (db, _) => runCallHistoryMigration(db),
    );
    session = null;
    account = 'private-account';
    current = true;
    accountReader = () async => account;
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });
  test(
    'real SQLite exact row survives close/reopen with no extra history writes',
    () async {
      final first = observer();
      final baseline = await first.snapshot(req('baseline'));
      expect(baseline['totalRows'], 0);
      connect();
      final live = await first.snapshot({
        ...req('current'),
        '_nativeCallId': native,
      });
      expect(live['status'], 'snapshot');
      expect(live['matchingRows'], 0);
      await terminal();
      final before = await first.snapshot(lookup(live));
      expect(before['matchingRows'], 1);
      expect(before['totalRows'], 1);
      final bytes = await db.query('call_history');
      await db.close();
      db = await openDatabase('${dir.path}/history.db', singleInstance: false);
      final after = await observer().snapshot(lookup(live));
      expect(after['rowBindingSha256'], before['rowBindingSha256']);
      expect(after['callBindingSha256'], live['callBindingSha256']);
      expect(after['totalRows'], 1);
      expect(await db.query('call_history'), bytes);
      final text = '$baseline$live$before$after';
      for (final secret in [
        call,
        native,
        'private-contact',
        'private-account',
      ]) {
        expect(text, isNot(contains(secret)));
      }
    },
  );
  test(
    'account switched before observation cannot be attributed to an old graph',
    () async {
      account = 'successor-account';
      expect(
        (await observer().snapshot(req('baseline')))['status'],
        'unavailable',
      );
    },
  );

  test('wrong native identity cannot join canonical call', () async {
    connect();
    expect(
      (await observer().snapshot({
        ...req('current'),
        '_nativeCallId': call,
      }))['status'],
      'unavailable',
    );
  });
  test('stale graph after awaited identity read cannot expose a row', () async {
    final held = Completer<String?>();
    accountReader = () => held.future;
    final pending = observer().snapshot(req('baseline'));
    await Future<void>.delayed(Duration.zero);
    current = false;
    held.complete(account);
    expect((await pending)['status'], 'unavailable');
  });
  test(
    'account cutover on final awaited check suppresses even correct row',
    () async {
      var reads = 0;
      accountReader = () async => ++reads == 1 ? account : 'successor-account';
      expect(
        (await observer().snapshot(req('baseline')))['status'],
        'unavailable',
      );
    },
  );
  test('unknown request fields and wrong nonce never query', () async {
    for (final r in [
      {...req('baseline'), 'sql': 'DELETE'},
      {...req('baseline'), 'nonce': '../private'},
    ]) {
      expect((await observer().snapshot(r))['status'], 'rejected');
    }
    expect(await db.query('call_history'), isEmpty);
  });
  test(
    'lookup needs exact account, nonce binding and bounded time window',
    () async {
      connect();
      final live = await observer().snapshot({
        ...req('current'),
        '_nativeCallId': native,
      });
      await terminal();
      final request = lookup(live);
      for (final r in [
        {...request, 'accountBindingSha256': 'a' * 64},
        {
          ...request,
          'untilMs': start.add(const Duration(days: 1)).millisecondsSinceEpoch,
        },
      ]) {
        expect((await observer().snapshot(r))['status'], 'rejected');
      }
      expect(
        (await observer().snapshot({
          ...request,
          'callBindingSha256': 'a' * 64,
        }))['status'],
        'unavailable',
      );
    },
  );
  test(
    'baseline and retrospective reads refuse a currently live unrelated call',
    () async {
      connect();
      expect(
        (await observer().snapshot(req('baseline')))['status'],
        'unavailable',
      );
    },
  );
  test('concurrent requests cannot interleave two custody proofs', () async {
    final held = Completer<String?>();
    accountReader = () => held.future;
    final source = observer();
    final pending = source.snapshot(req('baseline'));
    expect((await source.snapshot(req('baseline')))['status'], 'unavailable');
    held.complete(account);
    expect((await pending)['status'], 'snapshot');
  });
  test(
    'SQLite query-only mode still permits the observer and remains enabled',
    () async {
      await db.execute('PRAGMA query_only = ON');
      final result = await observer().snapshot(req('baseline'));
      expect(result['status'], 'snapshot');
      expect((await db.rawQuery('PRAGMA query_only')).single.values.single, 1);
      await db.execute('PRAGMA query_only = OFF');
    },
  );

  test('bounded history scan refuses more than 128 candidate rows', () async {
    connect();
    final live = await observer().snapshot({
      ...req('current'),
      '_nativeCallId': native,
    });
    await terminal();
    final original = (await db.query('call_history')).single;
    for (var i = 0; i < 128; i++) {
      await db.insert('call_history', {
        ...original,
        'call_id': '99999999-9999-4999-8999-${i.toString().padLeft(12, '0')}',
      });
    }
    final result = await observer().snapshot(lookup(live));
    expect(result['status'], 'unavailable');
    expect(
      (await db.rawQuery('SELECT COUNT(*) AS n FROM call_history')).single['n'],
      129,
    );
  });

  test(
    'an additional terminal history row is counted instead of hidden by exact match',
    () async {
      connect();
      final live = await observer().snapshot({
        ...req('current'),
        '_nativeCallId': native,
      });
      await terminal();
      final original = (await db.query('call_history')).single;
      await db.insert('call_history', {
        ...original,
        'call_id': '88888888-8888-4888-8888-888888888888',
      });
      final result = await observer().snapshot(lookup(live));
      expect(result['matchingRows'], 1);
      expect(result['totalRows'], 2);
    },
  );
  test(
    'release and profile paths cannot install or invoke debug evidence authority',
    () {
      final dart = File(
        'lib/debug/debug_call_evidence_observer.dart',
      ).readAsStringSync();
      expect(dart, contains('if (!kDebugMode) return;'));
      expect(dart, contains('if (!kDebugMode || _busy || _disposed)'));
      final bootstrap = File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsStringSync();
      final install = bootstrap.indexOf(
        'final observer = DebugCallEvidenceObserver(',
      );
      expect(
        bootstrap.substring(install - 90, install),
        contains('if (kDebugMode && Platform.isAndroid)'),
      );
      final native = File(
        'android/app/src/main/kotlin/com/mknoon/app/call/MknoonCallAndroidRuntime.kt',
      ).readAsStringSync();
      final hook = native.substring(
        native.indexOf('private fun observeDebugLifecycle('),
      );
      expect(
        hook.indexOf('if (!com.mknoon.app.BuildConfig.DEBUG) return'),
        lessThan(hook.indexOf('Class.forName(')),
      );
      for (final sourceSet in ['main', 'profile', 'release']) {
        for (final name in [
          'DebugCallAudioOracleReceiver',
          'DebugCallHistorySnapshot',
          'DebugCallLifecycleObservation',
        ]) {
          expect(
            File(
              'android/app/src/$sourceSet/kotlin/com/mknoon/app/call/$name.kt',
            ).existsSync(),
            isFalse,
          );
        }
      }
      final manifest = File(
        'android/app/src/debug/AndroidManifest.xml',
      ).readAsStringSync();
      final receiver = RegExp(
        r'<receiver[^>]*DebugCallAudioOracleReceiver[^>]*>',
        dotAll: true,
      ).firstMatch(manifest)!.group(0)!;
      expect(receiver, contains('android.permission.DUMP'));
    },
  );
  test(
    'successor canonical call during the final read invalidates baseline history proof',
    () async {
      final finalRead = Completer<String?>();
      var reads = 0;
      accountReader = () async =>
          ++reads == 1 ? account : await finalRead.future;
      final pending = observer().snapshot(req('baseline'));
      while (reads < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      connect();
      finalRead.complete(account);
      expect((await pending)['status'], 'unavailable');
    },
  );

  test('a retired bootstrap cannot uninstall its successor observer', () async {
    final old = observer();
    final replacement = observer();
    DebugCallEvidenceObserver.install(old);
    DebugCallEvidenceObserver.install(replacement);
    DebugCallEvidenceObserver.uninstall(old);
    expect((await replacement.snapshot(req('baseline')))['status'], 'snapshot');
    expect((await old.snapshot(req('baseline')))['status'], 'unavailable');
    DebugCallEvidenceObserver.uninstall(replacement);
    expect(
      (await replacement.snapshot(req('baseline')))['status'],
      'unavailable',
    );
  });
  test(
    'same call terminal during final identity read cannot certify a live current owner',
    () async {
      connect();
      final finalRead = Completer<String?>();
      var reads = 0;
      accountReader = () async =>
          ++reads == 1 ? account : await finalRead.future;
      final pending = observer().snapshot({
        ...req('current'),
        '_nativeCallId': native,
      });
      while (reads < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      session = session!.copyWith(
        state: CallState.ended,
        endedAt: start.add(const Duration(seconds: 20)),
        endReason: CallEndReason.localHangup,
      );
      finalRead.complete(account);
      expect((await pending)['status'], 'unavailable');
    },
  );
}
