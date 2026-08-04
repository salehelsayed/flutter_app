import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/core/notifications/dropped_push_recovery_bridge.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

const _probeChannel = MethodChannel('mknoon/canonical_runtime_h0_probe');
const _goChannel = MethodChannel('com.mknoon/go_bridge');
const _queueInversionDatabaseName = 'sqlcipher_queue_inversion.db';
const _queueInversionRawPassword =
    "x'3343343343343343343343343343343343343343343343343343343343343334'";

Future<void> runAndroidCanonicalRuntimeH0Probe(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  final phase = arguments.isEmpty ? 'recovery' : arguments.first;
  if (phase == 'queue-inversion-writer') {
    await _runSqlCipherQueueInversionWriter();
    return;
  }
  if (phase == 'queue-inversion-reader') {
    await _runSqlCipherQueueInversionReader();
    return;
  }
  if (phase == 'queue-inversion-sentinel') {
    await _runSqlCipherQueueInversionSentinel();
    return;
  }
  if (phase == 'firebase-read-only') {
    await _runFlutterFireReadOnlyPeer();
    return;
  }
  if (phase.startsWith('contender-')) {
    await _runCanonicalRuntimeContender(phase);
    return;
  }

  final trace = <String>[];
  DroppedPushRecoveryBridge? droppedPushBridge;
  try {
    final secureKeyStore = FlutterSecureKeyStore();
    droppedPushBridge = DroppedPushRecoveryBridge();
    final leaseGateway = _TracingLeaseGateway(
      delegate: MethodChannelCanonicalRuntimeLeaseGateway(),
      trace: trace,
    );
    final bindingCoordinator = CanonicalRuntimeBindingCoordinator(
      secureKeyStore: secureKeyStore,
      leaseGateway: leaseGateway,
      droppedPushBindingPublisher: droppedPushBridge,
    );
    final startupBinding = await bindingCoordinator.loadStartupBinding();
    final session = CanonicalWritableRuntimeSession(gateway: leaseGateway);

    final database = await session.acquireThenOpen(
      binding: startupBinding.leaseBinding,
      openDatabase: () async {
        trace.add('database.open.begin');
        final opened = await openEncryptedDatabase(
          secureKeyStore: secureKeyStore,
          dbName: 'identity.db',
          version: currentIdentityDatabaseVersion,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        );
        trace.add('database.opened');
        await _probeChannel.invokeMethod<void>('databaseOpened');
        return opened;
      },
      closeDatabaseOnRuntimeAttachFailure: (opened) async {
        trace.add('database.close.attach_failure.begin');
        await opened.close();
        trace.add('database.close.attach_failure.done');
        await _probeChannel.invokeMethod<void>('databaseClosed');
        return true;
      },
    );
    trace.add('database.ready');

    final cipherRows = await database.rawQuery('PRAGMA cipher_version');
    final quickCheckRows = await database.rawQuery('PRAGMA quick_check');
    await database.execute(
      'CREATE TEMP TABLE IF NOT EXISTS canonical_runtime_h0_probe '
      '(phase TEXT NOT NULL)',
    );
    await database.insert('canonical_runtime_h0_probe', {'phase': phase});
    final identity = await dbLoadIdentityRow(database);
    if (identity == null) {
      await bindingCoordinator.retireAccount();
    } else {
      await bindingCoordinator.publishAccount(identity['peer_id'] as String);
    }

    final goStatus = await _goChannel.invokeMethod<Object?>('nodeStatus');
    trace.add('go.node_status');

    CanonicalRuntimeLeaseState? retainedCloseFailureState;
    if (phase == 'recovery-handoff') {
      trace.add('contention.active.begin');
      final activeContention = await _probeChannel
          .invokeMapMethod<String, Object?>('readyForActiveContention');
      if (activeContention?['passed'] != true) {
        throw StateError('active-owner contention proof failed');
      }
      trace.add('contention.active.passed');

      try {
        await session.drainCloseRelease(
          stopRuntime: () async {
            if (!await leaseGateway.quiesceRuntime()) {
              throw StateError('Go runtime did not quiesce');
            }
          },
          closeDatabase: () async {
            trace.add('database.close.injected_failure');
            throw StateError(
              'injected SQLCipher close acknowledgement failure',
            );
          },
        );
        throw StateError('injected close failure unexpectedly released owner');
      } on StateError catch (error) {
        if (!error.toString().contains('injected SQLCipher')) rethrow;
      }
      final retained = await leaseGateway.status();
      retainedCloseFailureState = retained.state;
      if (retained.state != CanonicalRuntimeLeaseState.draining ||
          !database.isOpen ||
          !session.hasWritableLease) {
        throw StateError(
          'close failure did not retain DRAINING owner and open SQLCipher',
        );
      }
      trace.add('contention.close_failure.begin');
      final closeFailureContention = await _probeChannel
          .invokeMapMethod<String, Object?>('readyForCloseFailureContention');
      if (closeFailureContention?['passed'] != true) {
        throw StateError('close-failure contention proof failed');
      }
      trace.add('contention.close_failure.passed');
    }

    await session.drainCloseRelease(
      stopRuntime: () async {
        if (!await leaseGateway.quiesceRuntime()) {
          throw StateError('Go runtime did not quiesce');
        }
      },
      closeDatabase: () async {
        trace.add('database.close.begin');
        await database.close();
        trace.add('database.close.done');
        await _probeChannel.invokeMethod<void>('databaseClosed');
      },
    );
    final finalLease = await leaseGateway.status();

    await _probeChannel.invokeMethod<void>('complete', <String, Object?>{
      'phase': phase,
      'entrypoint': 'androidCanonicalRuntimeH0ProbeMain',
      'trace': trace,
      'cipherVersion': cipherRows.isEmpty
          ? null
          : cipherRows.first.values.first?.toString(),
      'quickCheck': quickCheckRows.isEmpty
          ? null
          : quickCheckRows.first.values.first?.toString(),
      'goStatus': goStatus?.toString(),
      'databaseClosedBeforeCompletion': !database.isOpen,
      'finalLeaseState': finalLease.state.name,
      'finalLeaseGeneration': finalLease.generation,
      'maximumConcurrentWritableOwners':
          finalLease.maximumConcurrentWritableOwners,
      'closeFailureRetainedState': retainedCloseFailureState?.name,
      'recoveryWorkActivated': false,
    });
  } catch (error, stackTrace) {
    await _probeChannel.invokeMethod<void>('failed', <String, Object?>{
      'phase': phase,
      'entrypoint': 'androidCanonicalRuntimeH0ProbeMain',
      'trace': trace,
      'errorType': error.runtimeType.toString(),
      'error': error.toString(),
      'stack': stackTrace.toString(),
    });
  } finally {
    droppedPushBridge?.dispose();
  }
}

/// Deterministic writer half of the Android process-static SQLCipher FIFO RED.
///
/// The reader connection is opened before this method is allowed to execute
/// `BEGIN EXCLUSIVE`. After the native side observes that BEGIN has completed,
/// it releases the reader to enqueue a real query. The writer continuation is
/// released only after the reader has created that query Future and posted the
/// `queueReaderQueryPosted` control message.
Future<void> _runSqlCipherQueueInversionWriter() async {
  Database? database;
  var transactionOpen = false;
  try {
    final databasePath = await getDatabasesPath();
    database = await openDatabase(
      '$databasePath/$_queueInversionDatabaseName',
      password: _queueInversionRawPassword,
      singleInstance: false,
    );
    final cipherRows = await database.rawQuery('PRAGMA cipher_version');
    final journalRows = await database.rawQuery('PRAGMA journal_mode = DELETE');
    await database.execute(
      'CREATE TABLE IF NOT EXISTS queue_inversion_probe '
      '(id INTEGER PRIMARY KEY AUTOINCREMENT, value TEXT NOT NULL)',
    );
    await _probeChannel
        .invokeMethod<void>('queueWriterDatabaseOpened', <String, Object?>{
          'cipherVersion': _firstPragmaValue(cipherRows),
          'journalMode': _firstPragmaValue(journalRows),
        });

    await database.execute('BEGIN EXCLUSIVE');
    transactionOpen = true;
    await _probeChannel.invokeMethod<void>('queueWriterBeginExclusive');

    // On upstream 3.4.0 this statement is posted behind the reader query that
    // is blocked on our transaction. An engine-owned worker lets it run.
    await database.execute(
      'INSERT INTO queue_inversion_probe(value) VALUES (?)',
      <Object?>['writer-resumed'],
    );
    await database.execute('COMMIT');
    transactionOpen = false;
    await _probeChannel.invokeMethod<void>('queueWriterCommit');
    await database.close();
    await _probeChannel.invokeMethod<void>('queueWriterClosed');
  } catch (error, stackTrace) {
    if (transactionOpen && database != null && database.isOpen) {
      try {
        await database.execute('ROLLBACK').timeout(const Duration(seconds: 1));
      } catch (_) {
        // A wedged upstream native FIFO cannot service rollback. The host first
        // preserves the terminal artifact and then uninstalls this disposable
        // application, which is the RED cleanup boundary.
      }
    }
    if (database != null && database.isOpen) {
      try {
        await database.close().timeout(const Duration(seconds: 1));
      } catch (_) {
        // See the rollback note above.
      }
    }
    await _probeChannel
        .invokeMethod<void>('queueWriterFailed', <String, Object?>{
          'errorType': error.runtimeType.toString(),
          'error': error.toString(),
          'stack': stackTrace.toString(),
        });
  }
}

/// Reader half of the deterministic queue-inversion fixture.
Future<void> _runSqlCipherQueueInversionReader() async {
  Database? database;
  try {
    // Prewarm this isolate in parallel with the writer, but do not touch the
    // disposable database until native has observed the writer's create/open.
    await _probeChannel.invokeMethod<void>('queueReaderReady');
    final databasePath = await getDatabasesPath();
    database = await openDatabase(
      '$databasePath/$_queueInversionDatabaseName',
      password: _queueInversionRawPassword,
      readOnly: true,
      singleInstance: false,
    );
    final cipherRows = await database.rawQuery('PRAGMA cipher_version');
    await _probeChannel.invokeMethod<void>(
      'queueReaderDatabaseOpened',
      <String, Object?>{'cipherVersion': _firstPragmaValue(cipherRows)},
    );

    // Do not await here. Creating this Future submits the query over the
    // sqflite method channel. The following control message is posted only
    // after that submission, and native code releases the writer continuation
    // only after receiving the control message.
    final queryFuture = database.rawQuery(
      'SELECT COUNT(*) AS count FROM queue_inversion_probe',
    );
    await _probeChannel.invokeMethod<void>('queueReaderQueryPosted');
    final rows = await queryFuture;
    await _probeChannel.invokeMethod<void>(
      'queueReaderQueryResult',
      <String, Object?>{
        'rowCount': rows.length,
        'count': rows.isEmpty ? null : rows.first['count'],
      },
    );
    await database.close();
    await _probeChannel.invokeMethod<void>('queueReaderClosed');
  } catch (error, stackTrace) {
    if (database != null && database.isOpen) {
      try {
        await database.close().timeout(const Duration(seconds: 1));
      } catch (_) {
        // Expected to be impossible to service while the upstream FIFO is
        // wedged. Disposable-package cleanup owns that RED path.
      }
    }
    await _probeChannel
        .invokeMethod<void>('queueReaderFailed', <String, Object?>{
          'errorType': error.runtimeType.toString(),
          'error': error.toString(),
          'stack': stackTrace.toString(),
        });
  }
}

Object? _firstPragmaValue(List<Map<String, Object?>> rows) =>
    rows.isEmpty || rows.first.values.isEmpty ? null : rows.first.values.first;

/// Fresh-engine liveness sentinel run only after the writer and reader close.
Future<void> _runSqlCipherQueueInversionSentinel() async {
  Database? database;
  try {
    final databasePath = await getDatabasesPath();
    database = await openDatabase(
      '$databasePath/$_queueInversionDatabaseName',
      password: _queueInversionRawPassword,
      singleInstance: false,
    );
    await _probeChannel.invokeMethod<void>('queueSentinelDatabaseOpened');
    await database.insert('queue_inversion_probe', <String, Object?>{
      'value': 'fresh-engine-sentinel',
    });
    final rows = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM queue_inversion_probe '
      'WHERE value = ?',
      <Object?>['fresh-engine-sentinel'],
    );
    final count = rows.isEmpty ? null : rows.first['count'];
    if (count != 1) {
      throw StateError('fresh-engine sentinel row count was $count');
    }
    await _probeChannel.invokeMethod<void>(
      'queueSentinelVerified',
      <String, Object?>{'count': count},
    );
    await database.close();
    await _probeChannel.invokeMethod<void>('queueSentinelClosed');
  } catch (error, stackTrace) {
    if (database != null && database.isOpen) {
      try {
        await database.close().timeout(const Duration(seconds: 1));
      } catch (_) {
        // Host cleanup owns any wedged disposable-package handle.
      }
    }
    await _probeChannel
        .invokeMethod<void>('queueSentinelFailed', <String, Object?>{
          'errorType': error.runtimeType.toString(),
          'error': error.toString(),
          'stack': stackTrace.toString(),
        });
  }
}

Future<void> _runFlutterFireReadOnlyPeer() async {
  const phase = 'firebase-read-only';
  final trace = <String>[];
  Database? database;
  try {
    final secureKeyStore = FlutterSecureKeyStore();
    final key = await secureKeyStore.read('db_encryption_key');
    if (key == null || key.trim().isEmpty) {
      throw StateError('read-only peer found no SQLCipher key');
    }
    final databasePath = await getDatabasesPath();
    database = await openEncryptedDatabaseReadOnlyTolerant(
      path: '$databasePath/identity.db',
      storedKey: key,
    );
    trace.add('read_only_database.opened');
    final cipherRows = await database.rawQuery('PRAGMA cipher_version');
    final quickCheckRows = await database.rawQuery('PRAGMA quick_check');
    await database.rawQuery('SELECT count(*) FROM sqlite_master');
    await _probeChannel.invokeMethod<void>('readOnlyDatabaseOpened');
    trace.add('read_only_database.close.begin');
    await database.close();
    trace.add('read_only_database.close.done');
    await _probeChannel.invokeMethod<void>('readOnlyDatabaseClosed');
    await _probeChannel.invokeMethod<void>('complete', <String, Object?>{
      'phase': phase,
      'entrypoint': 'androidCanonicalRuntimeH0ProbeMain',
      'trace': trace,
      'readOnlyDatabaseOpened': true,
      'databaseClosedBeforeCompletion': !database.isOpen,
      'cipherVersion': cipherRows.isEmpty
          ? null
          : cipherRows.first.values.first?.toString(),
      'quickCheck': quickCheckRows.isEmpty
          ? null
          : quickCheckRows.first.values.first?.toString(),
      'writableLeaseAcquired': false,
      'goBridgeAttached': false,
      'recoveryWorkActivated': false,
    });
  } catch (error, stackTrace) {
    await _probeChannel.invokeMethod<void>('failed', <String, Object?>{
      'phase': phase,
      'entrypoint': 'androidCanonicalRuntimeH0ProbeMain',
      'trace': trace,
      'errorType': error.runtimeType.toString(),
      'error': error.toString(),
      'stack': stackTrace.toString(),
      'databaseClosedBeforeCompletion': database == null || !database.isOpen,
    });
  }
}

Future<void> _runCanonicalRuntimeContender(String phase) async {
  final trace = <String>[];
  DroppedPushRecoveryBridge? droppedPushBridge;
  try {
    final secureKeyStore = FlutterSecureKeyStore();
    droppedPushBridge = DroppedPushRecoveryBridge();
    final leaseGateway = _TracingLeaseGateway(
      delegate: MethodChannelCanonicalRuntimeLeaseGateway(),
      trace: trace,
    );
    final bindingCoordinator = CanonicalRuntimeBindingCoordinator(
      secureKeyStore: secureKeyStore,
      leaseGateway: leaseGateway,
      droppedPushBindingPublisher: droppedPushBridge,
    );
    final startupBinding = await bindingCoordinator.loadStartupBinding();
    var leaseRejected = false;
    try {
      await leaseGateway.acquire(startupBinding.leaseBinding);
      trace.add('lease.unexpectedly_acquired');
      if (await leaseGateway.beginDrain()) {
        await leaseGateway.release(databaseClosed: true);
      }
    } on PlatformException catch (error) {
      if (error.code != 'lease_unavailable') rethrow;
      leaseRejected = true;
      trace.add('lease.rejected');
    }
    final observedLease = await leaseGateway.status();
    await _probeChannel.invokeMethod<void>('complete', <String, Object?>{
      'phase': phase,
      'entrypoint': 'androidCanonicalRuntimeH0ProbeMain',
      'trace': trace,
      'leaseRejected': leaseRejected,
      'databaseOpened': false,
      'observedLeaseState': observedLease.state.name,
      'observedLeaseGeneration': observedLease.generation,
      'recoveryWorkActivated': false,
    });
  } catch (error, stackTrace) {
    await _probeChannel.invokeMethod<void>('failed', <String, Object?>{
      'phase': phase,
      'entrypoint': 'androidCanonicalRuntimeH0ProbeMain',
      'trace': trace,
      'errorType': error.runtimeType.toString(),
      'error': error.toString(),
      'stack': stackTrace.toString(),
    });
  } finally {
    droppedPushBridge?.dispose();
  }
}

final class _TracingLeaseGateway implements CanonicalRuntimeLeaseGateway {
  _TracingLeaseGateway({required this.delegate, required this.trace});

  final CanonicalRuntimeLeaseGateway delegate;
  final List<String> trace;

  @override
  Future<CanonicalRuntimeLeaseSnapshot> acquire(String binding) async {
    trace.add('lease.acquire');
    return delegate.acquire(binding);
  }

  @override
  Future<bool> attachRuntime() async {
    trace.add('runtime.attach');
    return delegate.attachRuntime();
  }

  @override
  Future<bool> beginDrain() async {
    trace.add('lease.begin_drain');
    return delegate.beginDrain();
  }

  @override
  Future<bool> quiesceRuntime() async {
    trace.add('runtime.quiesce');
    return delegate.quiesceRuntime();
  }

  @override
  Future<CanonicalRuntimeLeaseSnapshot> rebind(String binding) async {
    trace.add('lease.rebind');
    return delegate.rebind(binding);
  }

  @override
  Future<bool> release({required bool databaseClosed}) async {
    trace.add('lease.release:$databaseClosed');
    return delegate.release(databaseClosed: databaseClosed);
  }

  @override
  Future<CanonicalRuntimeLeaseSnapshot> status() => delegate.status();
}
