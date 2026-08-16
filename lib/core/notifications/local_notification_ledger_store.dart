import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_app/core/notifications/bounded_posix_flock.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';

typedef LocalNotificationLedgerMutation =
    LocalNotificationLedgerEnvelopeV1? Function(
      LocalNotificationLedgerEnvelopeV1 current,
    );

typedef LocalNotificationLedgerPublicationHook =
    Future<void> Function(File prepared, File target);

typedef LocalNotificationLedgerDirectorySyncHook =
    Future<void> Function(File target);

/// Atomic private-file owner for the local notification effect ledger.
///
/// Public methods acquire the exact stable-ID registry coordination lock once.
/// Production supplies the `NotificationConversationIds` directory, so the
/// shared lock is exactly `NotificationConversationIds/.coordination.lock`.
/// Lock-held variants never acquire flock and exist only for composition by a
/// caller that already owns [coordinationLockFile]. Calling a public method
/// from a lock-held callback is forbidden because BSD flock is not reentrant.
final class LocalNotificationLedgerStore {
  LocalNotificationLedgerStore({
    required this.directory,
    DateTime Function()? nowUtc,
    LocalNotificationLedgerPublicationHook? beforeRename,
    LocalNotificationLedgerDirectorySyncHook? afterRenameBeforeDirectorySync,
    this.maxRecords = localNotificationLedgerMaxRecords,
    this.settledRetention = const Duration(days: 7),
  }) : _nowUtc = nowUtc ?? _systemNowUtc,
       _beforeRename = beforeRename,
       _afterRenameBeforeDirectorySync = afterRenameBeforeDirectorySync {
    if (maxRecords < 1 || maxRecords > localNotificationLedgerMaxRecords) {
      throw ArgumentError.value(maxRecords, 'maxRecords');
    }
    if (settledRetention <= Duration.zero) {
      throw ArgumentError.value(settledRetention, 'settledRetention');
    }
  }

  static const String fileName = 'local_notification_ledger_v1.json';
  static const String coordinationLockFileName = '.coordination.lock';

  final Directory directory;
  final int maxRecords;
  final Duration settledRetention;
  final DateTime Function() _nowUtc;
  final LocalNotificationLedgerPublicationHook? _beforeRename;
  final LocalNotificationLedgerDirectorySyncHook?
  _afterRenameBeforeDirectorySync;

  File get ledgerFile =>
      File('${directory.path}${Platform.pathSeparator}$fileName');

  File get coordinationLockFile => File(
    '${directory.path}${Platform.pathSeparator}$coordinationLockFileName',
  );

  Future<LocalNotificationLedgerEnvelopeV1?> read({
    required String currentOpaqueBinding,
  }) =>
      _withLock(() => readLockHeld(currentOpaqueBinding: currentOpaqueBinding));

  /// Reads without acquiring flock. The caller must already own the exact
  /// [coordinationLockFile]. Missing, malformed, future or binding-mismatched
  /// bytes grant no authority and return null without changing disk state.
  Future<LocalNotificationLedgerEnvelopeV1?> readLockHeld({
    required String currentOpaqueBinding,
  }) async {
    if (!isCanonicalLocalNotificationOpaqueBinding(currentOpaqueBinding)) {
      return null;
    }
    final loaded = await _load();
    final envelope = loaded.envelope;
    if (loaded.kind != _LedgerLoadKind.valid ||
        envelope == null ||
        envelope.opaqueBinding != currentOpaqueBinding) {
      return null;
    }
    return envelope;
  }

  Future<LocalNotificationLedgerEnvelopeV1?> initializeOrRebind({
    required String currentOpaqueBinding,
  }) => _withLock(
    () =>
        initializeOrRebindLockHeld(currentOpaqueBinding: currentOpaqueBinding),
  );

  /// Initializes or intentionally replaces an old-binding ledger while the
  /// caller owns [coordinationLockFile]. A supported malformed v1 file is
  /// quarantined before rebuild. Future-schema and I/O-uncertain bytes remain
  /// byte-identical and return null.
  Future<LocalNotificationLedgerEnvelopeV1?> initializeOrRebindLockHeld({
    required String currentOpaqueBinding,
  }) async {
    if (!isCanonicalLocalNotificationOpaqueBinding(currentOpaqueBinding)) {
      return null;
    }
    final loaded = await _load();
    switch (loaded.kind) {
      case _LedgerLoadKind.valid:
        if (loaded.envelope!.opaqueBinding == currentOpaqueBinding) {
          final current = loaded.envelope!;
          if (!current.claimsSuspended) return current;
          if (current.storeRevision == localNotificationLedgerMaxSignedInt64) {
            return null;
          }
          // This is the privileged post-secure-commit/startup reactivation
          // path. A crash after suspending but before changing the canonical
          // binding must not strand the still-current account permanently.
          final resumed = current.copyWith(
            storeRevision: current.storeRevision + 1,
            claimsSuspended: false,
          );
          return await _publish(resumed) ? resumed : null;
        }
      case _LedgerLoadKind.missing:
        break;
      case _LedgerLoadKind.supportedMalformed:
        if (!await _quarantineSupportedV1()) return null;
      case _LedgerLoadKind.futureSchema:
      case _LedgerLoadKind.ioFailure:
        return null;
    }
    final empty = LocalNotificationLedgerEnvelopeV1(
      storeRevision: 1,
      opaqueBinding: currentOpaqueBinding,
      claimsSuspended: false,
      records: const <String, LocalNotificationRecordV1>{},
    );
    return await _publish(empty) ? empty : null;
  }

  Future<LocalNotificationLedgerEnvelopeV1?> suspendClaims({
    required String currentOpaqueBinding,
  }) => _withLock(
    () => suspendClaimsLockHeld(currentOpaqueBinding: currentOpaqueBinding),
  );

  /// Suspends new claims without acquiring flock. The exact coordination lock
  /// must already be held by the caller.
  Future<LocalNotificationLedgerEnvelopeV1?> suspendClaimsLockHeld({
    required String currentOpaqueBinding,
  }) async {
    final current = await readLockHeld(
      currentOpaqueBinding: currentOpaqueBinding,
    );
    if (current == null) return null;
    if (current.claimsSuspended) return current;
    if (current.storeRevision == localNotificationLedgerMaxSignedInt64) {
      return null;
    }
    final suspended = current.copyWith(
      storeRevision: current.storeRevision + 1,
      claimsSuspended: true,
    );
    return await _publish(suspended) ? suspended : null;
  }

  Future<LocalNotificationLedgerEnvelopeV1?> mutate({
    required String currentOpaqueBinding,
    required LocalNotificationLedgerMutation mutation,
  }) => _withLock(
    () => mutateLockHeld(
      currentOpaqueBinding: currentOpaqueBinding,
      mutation: mutation,
    ),
  );

  /// Runs one synchronous CAS transform without acquiring flock. The caller
  /// must already own [coordinationLockFile]. Returning null from [mutation]
  /// aborts without writing. The store revision must advance exactly once.
  Future<LocalNotificationLedgerEnvelopeV1?> mutateLockHeld({
    required String currentOpaqueBinding,
    required LocalNotificationLedgerMutation mutation,
  }) async {
    final current = await readLockHeld(
      currentOpaqueBinding: currentOpaqueBinding,
    );
    if (current == null ||
        current.storeRevision == localNotificationLedgerMaxSignedInt64) {
      return null;
    }
    final candidate = mutation(current);
    if (candidate == null ||
        candidate.opaqueBinding != currentOpaqueBinding ||
        candidate.storeRevision != current.storeRevision + 1) {
      return null;
    }

    final records = <String, LocalNotificationRecordV1>{};
    for (final entry in candidate.records.entries) {
      if (entry.key != entry.value.eventCorrelation || !entry.value.isValid) {
        return null;
      }
      if (!_isExpiredSettled(entry.value)) records[entry.key] = entry.value;
    }
    if (records.length > maxRecords) return null;
    final bounded = candidate.copyWith(records: records);
    if (!bounded.isValid) return null;
    return await _publish(bounded) ? bounded : null;
  }

  Future<T?> _withLock<T>(Future<T?> Function() action) async {
    try {
      return await BoundedPosixFlock.withExclusive(
        coordinationLockFile,
        action,
      );
    } on BoundedPosixFlockUnavailableException {
      return null;
    } on BoundedPosixFlockReentrantException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  bool _isExpiredSettled(LocalNotificationRecordV1 record) {
    if (record.effectPhase != LocalNotificationEffectPhase.settled) {
      return false;
    }
    final settled = DateTime.parse(record.settledAtUtc!).toUtc();
    final cutoff = _nowUtc().toUtc().subtract(settledRetention);
    return !settled.isAfter(cutoff);
  }

  Future<_LedgerLoad> _load() async {
    late final FileSystemEntityType type;
    try {
      type = await FileSystemEntity.type(ledgerFile.path, followLinks: false);
    } on FileSystemException {
      return const _LedgerLoad(_LedgerLoadKind.ioFailure);
    }
    if (type == FileSystemEntityType.notFound) {
      return const _LedgerLoad(_LedgerLoadKind.missing);
    }
    if (type != FileSystemEntityType.file) {
      return const _LedgerLoad(_LedgerLoadKind.ioFailure);
    }
    late final String encoded;
    try {
      encoded = await ledgerFile.readAsString();
    } on FileSystemException {
      return const _LedgerLoad(_LedgerLoadKind.ioFailure);
    }
    Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on Object {
      return const _LedgerLoad(_LedgerLoadKind.supportedMalformed);
    }
    if (decoded is Map &&
        decoded['schemaVersion'] is int &&
        (decoded['schemaVersion']! as int) >
            localNotificationLedgerSchemaVersion) {
      return const _LedgerLoad(_LedgerLoadKind.futureSchema);
    }
    final envelope = LocalNotificationLedgerCodecV1.tryDecodePlatform(decoded);
    return envelope == null
        ? const _LedgerLoad(_LedgerLoadKind.supportedMalformed)
        : _LedgerLoad(_LedgerLoadKind.valid, envelope);
  }

  Future<bool> _quarantineSupportedV1() async {
    if (!await ledgerFile.exists()) return true;
    final suffix = _randomSuffix();
    final quarantine = File('${ledgerFile.path}.corrupt-$suffix');
    try {
      await ledgerFile.rename(quarantine.path);
      BoundedPosixFlock.syncDirectory(directory);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<bool> _publish(LocalNotificationLedgerEnvelopeV1 envelope) async {
    if (!envelope.isValid) return false;
    try {
      await directory.create(recursive: true);
      final targetType = await FileSystemEntity.type(
        ledgerFile.path,
        followLinks: false,
      );
      if (targetType != FileSystemEntityType.notFound &&
          targetType != FileSystemEntityType.file) {
        return false;
      }
      final temporary = File(
        '${directory.path}${Platform.pathSeparator}.$fileName-${_randomSuffix()}.tmp',
      );
      try {
        await temporary.writeAsString(
          LocalNotificationLedgerCodecV1.encode(envelope),
          flush: true,
        );
        await _beforeRename?.call(temporary, ledgerFile);
        await temporary.rename(ledgerFile.path);
        await _afterRenameBeforeDirectorySync?.call(ledgerFile);
        BoundedPosixFlock.syncDirectory(directory);
        return true;
      } finally {
        try {
          if (await temporary.exists()) await temporary.delete();
        } on FileSystemException {
          // Hidden complete temp files grant no authority and are ignored.
        }
      }
    } on FileSystemException {
      return false;
    }
  }

  String _randomSuffix() {
    final random = Random.secure();
    return List<int>.generate(
      12,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  static DateTime _systemNowUtc() => DateTime.now().toUtc();
}

bool isCanonicalLocalNotificationOpaqueBinding(Object? value) =>
    value is String && RegExp(r'^v1:[0-9a-f]{64}$').hasMatch(value);

enum _LedgerLoadKind {
  missing,
  valid,
  supportedMalformed,
  futureSchema,
  ioFailure,
}

final class _LedgerLoad {
  const _LedgerLoad(this.kind, [this.envelope]);

  final _LedgerLoadKind kind;
  final LocalNotificationLedgerEnvelopeV1? envelope;
}
