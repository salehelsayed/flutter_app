import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

const String backgroundStorageLivenessJournalDirectoryName =
    'BackgroundStorageLiveness';
const String _backgroundStorageLivenessFilePrefix = 'terminal-v1-';
const String _backgroundStorageLivenessFileExtension = '.json';
const String _backgroundStorageLivenessTemporaryPrefix = '.terminal-v1-tmp-';
const String backgroundStorageG21MeasurementFilePrefix = 'g21-measurement-v1-';
const String _backgroundStorageG21MeasurementTemporaryPrefix =
    '.g21-measurement-v1-tmp-';
const Duration _backgroundStorageLivenessTemporaryRetention = Duration(
  hours: 1,
);

@visibleForTesting
const int backgroundStorageLivenessJournalMaxEntries = 32;

@visibleForTesting
const Duration backgroundStorageLivenessJournalMaxCallerImpact = Duration(
  milliseconds: 200,
);

int _validatedBackgroundStorageJournalMaxEntries(int value) {
  if (value < 1 || value > backgroundStorageLivenessJournalMaxEntries) {
    throw RangeError.range(
      value,
      1,
      backgroundStorageLivenessJournalMaxEntries,
      'maxEntries',
    );
  }
  return value;
}

/// Coarse, identifier-free message families accepted by the journal.
enum BackgroundStorageMessageKind {
  directMessage('direct_message'),
  directReaction('direct_reaction'),
  groupMessage('group_message'),
  groupReaction('group_reaction'),
  unknown('unknown');

  const BackgroundStorageMessageKind(this.wireName);
  final String wireName;
}

/// Only storage phases that can produce a terminal liveness outcome belong
/// here. Values are fixed rather than caller-provided strings so an identifier
/// cannot accidentally be persisted in the phase field.
enum BackgroundStorageLivenessPhase {
  directStaging('direct_staging'),
  displayEligibility('display_eligibility'),
  localState('local_state'),
  pendingOverlay('pending_overlay'),
  postShowValidation('post_show_validation'),
  recentGate('recent_gate'),
  encryptedOpen('encrypted_open');

  const BackgroundStorageLivenessPhase(this.wireName);
  final String wireName;
}

/// The exact storage phase a deadline was applied to.
///
/// This is a SIBLING of [BackgroundStorageLivenessPhase], not a replacement.
/// That enum deliberately collapses several phases onto one coarse family —
/// `preview_resolution` and `durable_effect_authority` both land on
/// [BackgroundStorageLivenessPhase.localState] — which makes two different
/// terminal exits indistinguishable in a record. This enum keeps them apart
/// while preserving the same privacy rule: the values are fixed, so a caller
/// cannot persist an identifier through the phase surface. Anything outside
/// the domain degrades to [unknown] rather than being written verbatim.
enum BackgroundStorageDeadlinePhaseName {
  directPostShowValidation('direct_post_show_validation'),
  directStage('direct_stage'),
  displayEligibility('display_eligibility'),
  durableEffectAuthority('durable_effect_authority'),
  groupPostShowValidation('group_post_show_validation'),
  pendingOverlay('pending_overlay'),
  previewResolution('preview_resolution'),
  recentBackgroundMark('recent_background_mark'),
  recentBackgroundRead('recent_background_read'),
  recentRemoteMark('recent_remote_mark'),
  resolvedStage('resolved_stage'),
  unknown('unknown');

  const BackgroundStorageDeadlinePhaseName(this.wireName);
  final String wireName;

  /// Validates a raw phase identifier against the closed domain. An
  /// unrecognised value can only ever become [unknown]; it is never persisted.
  static BackgroundStorageDeadlinePhaseName fromWireName(String value) {
    for (final candidate in values) {
      if (candidate.wireName == value) return candidate;
    }
    return unknown;
  }
}

enum BackgroundStorageTerminalOutcome {
  storageDeferred('storage_deferred'),
  notificationSuppressed('notification_suppressed'),
  shownStateUnknown('shown_state_unknown');

  const BackgroundStorageTerminalOutcome(this.wireName);
  final String wireName;
}

enum BackgroundStorageElapsedBucket {
  underTwoSeconds('under_2s'),
  twoToEightSeconds('2s_to_8s'),
  eightSecondsOrMore('8s_or_more');

  const BackgroundStorageElapsedBucket(this.wireName);
  final String wireName;
}

enum BackgroundStorageBuildMode {
  debug('debug'),
  profile('profile'),
  release('release');

  const BackgroundStorageBuildMode(this.wireName);
  final String wireName;
}

enum BackgroundStorageEngineRole {
  flutterfireBackground('flutterfire_background'),
  foregroundRecovery('foreground_recovery');

  const BackgroundStorageEngineRole(this.wireName);
  final String wireName;
}

/// The only terminal outcomes emitted by the Plan-393 first-wake timing probe.
///
/// This remains a closed domain because the receipt is copied directly from
/// app-private storage by the device harness. No caller text or notification
/// identifier is allowed to enter that artifact.
enum BackgroundStorageG21TerminalOutcome {
  shown('shown'),
  policySuppressed('policy_suppressed');

  const BackgroundStorageG21TerminalOutcome(this.wireName);
  final String wireName;
}

BackgroundStorageElapsedBucket bucketBackgroundStorageElapsed(
  Duration elapsed,
) {
  if (elapsed < const Duration(seconds: 2)) {
    return BackgroundStorageElapsedBucket.underTwoSeconds;
  }
  if (elapsed < const Duration(seconds: 8)) {
    return BackgroundStorageElapsedBucket.twoToEightSeconds;
  }
  return BackgroundStorageElapsedBucket.eightSecondsOrMore;
}

typedef BackgroundStorageJournalDirectoryResolver =
    Future<Directory> Function();
typedef BackgroundStorageJournalAtomicWriter =
    Future<void> Function({
      required File temporary,
      required File target,
      required String contents,
    });
typedef BackgroundStorageJournalPruner =
    Future<void> Function(Directory directory, int maxEntries);

/// A rare-event, app-private breadcrumb journal for terminal storage stalls.
///
/// Each retained event owns one of 32 complete slot files, published with one
/// atomic rename from a per-operation unique temporary. There is intentionally
/// no shared journal lock: observability must never become a second reason for
/// a Firebase background callback to remain queued.
class BackgroundStorageLivenessJournal {
  BackgroundStorageLivenessJournal({
    required BackgroundStorageJournalDirectoryResolver directoryResolver,
    DateTime Function()? now,
    int Function()? randomNonce,
    BackgroundStorageJournalAtomicWriter? atomicWriter,
    BackgroundStorageJournalPruner? pruner,
    int maxEntries = backgroundStorageLivenessJournalMaxEntries,
    this.maxCallerImpact = backgroundStorageLivenessJournalMaxCallerImpact,
    BackgroundStorageBuildMode? buildMode,
  }) : maxEntries = _validatedBackgroundStorageJournalMaxEntries(maxEntries),
       _directoryResolver = directoryResolver,
       _now = now ?? DateTime.now,
       _randomNonce = randomNonce ?? _secureNonceSource(),
       _instanceNonce = _secureInstanceNonce(),
       _atomicWriter = atomicWriter ?? _writeAtomically,
       _pruner = pruner ?? _pruneOldest,
       _buildMode = buildMode ?? _compiledBuildMode;

  factory BackgroundStorageLivenessJournal.mobileDefault() {
    return BackgroundStorageLivenessJournal(
      directoryResolver: () async {
        final support = await getApplicationSupportDirectory();
        return Directory(
          '${support.path}${Platform.pathSeparator}'
          '$backgroundStorageLivenessJournalDirectoryName',
        );
      },
    );
  }

  final BackgroundStorageJournalDirectoryResolver _directoryResolver;
  final DateTime Function() _now;
  final int Function() _randomNonce;
  final int _instanceNonce;
  final BackgroundStorageJournalAtomicWriter _atomicWriter;
  final BackgroundStorageJournalPruner _pruner;
  final BackgroundStorageBuildMode _buildMode;
  final int maxEntries;
  final Duration maxCallerImpact;
  int _sequence = 0;

  /// Writes the successful, identifier-free Plan-393 first-wake measurement.
  ///
  /// Production never calls this method: its sole caller is guarded by the
  /// compile-time `MKNOON_NOTIFICATION_G21_MEASUREMENT` flag. The unique file
  /// name gives the capture harness an inventory cursor without introducing a
  /// shared lock or letting a stale receipt satisfy a later run.
  Future<void> recordG21Measurement({
    required BackgroundStorageMessageKind kind,
    required Duration aggregateElapsedAtEligibilityStart,
    required Duration remainingAtEligibilityStart,
    required Duration eligibilityElapsed,
    required Duration nativeEntryTail,
    required BackgroundStorageG21TerminalOutcome terminalOutcome,
  }) async {
    final operation = Future<void>.sync(
      () => _persistG21Measurement(
        kind: kind,
        aggregateElapsedAtEligibilityStart: aggregateElapsedAtEligibilityStart,
        remainingAtEligibilityStart: remainingAtEligibilityStart,
        eligibilityElapsed: eligibilityElapsed,
        nativeEntryTail: nativeEntryTail,
        terminalOutcome: terminalOutcome,
      ),
    );
    try {
      await operation.timeout(maxCallerImpact);
    } on Object {
      // The measurement is observability only and cannot retain the FCM
      // callback or alter its presentation outcome.
    }
  }

  Future<void> _persistG21Measurement({
    required BackgroundStorageMessageKind kind,
    required Duration aggregateElapsedAtEligibilityStart,
    required Duration remainingAtEligibilityStart,
    required Duration eligibilityElapsed,
    required Duration nativeEntryTail,
    required BackgroundStorageG21TerminalOutcome terminalOutcome,
  }) async {
    final directory = await _directoryResolver();
    await directory.create(recursive: true);
    final sequence = _sequence++;
    final nonce = _randomNonce() & 0x7fffffff;
    final now = _now();
    final stem =
        '$backgroundStorageG21MeasurementFilePrefix'
        '${now.microsecondsSinceEpoch}-'
        '${nonce.toRadixString(16).padLeft(8, '0')}-'
        '${_instanceNonce.toRadixString(16).padLeft(8, '0')}-'
        '$sequence';
    final target = File(
      '${directory.path}${Platform.pathSeparator}'
      '$stem$_backgroundStorageLivenessFileExtension',
    );
    final temporary = File(
      '${directory.path}${Platform.pathSeparator}'
      '$_backgroundStorageG21MeasurementTemporaryPrefix$stem.tmp',
    );
    final record = <String, String>{
      'schema': 'mknoon.plan393.g21-measurement.v1',
      'kind': kind.wireName,
      'measurementMode': 'raw_aggregate_remainder',
      'aggregateElapsedAtEligibilityStartMs': aggregateElapsedAtEligibilityStart
          .inMilliseconds
          .toString(),
      'remainingAtEligibilityStartMs': remainingAtEligibilityStart
          .inMilliseconds
          .toString(),
      'eligibilityElapsedMs': eligibilityElapsed.inMilliseconds.toString(),
      'nativeEntryTailMs': nativeEntryTail.inMilliseconds.toString(),
      'terminalOutcome': terminalOutcome.wireName,
      'buildMode': _buildMode.wireName,
      'engineRole': BackgroundStorageEngineRole.flutterfireBackground.wireName,
    };
    await _atomicWriter(
      temporary: temporary,
      target: target,
      contents: jsonEncode(record),
    );
    await _pruneG21Measurements(directory, maxEntries);
  }

  /// Records only a terminal, redacted outcome. Failures and the 200 ms bound
  /// are swallowed by design; callers must continue releasing their queue.
  Future<void> recordTerminal({
    required BackgroundStorageMessageKind kind,
    required BackgroundStorageLivenessPhase phase,
    required BackgroundStorageDeadlinePhaseName phaseName,
    required BackgroundStorageTerminalOutcome outcome,
    required Duration elapsed,
    required Duration phaseElapsed,
    required Duration budget,
    BackgroundStorageEngineRole engineRole =
        BackgroundStorageEngineRole.flutterfireBackground,
  }) async {
    final operation = Future<void>.sync(
      () => _persistTerminal(
        kind: kind,
        phase: phase,
        phaseName: phaseName,
        outcome: outcome,
        elapsed: elapsed,
        phaseElapsed: phaseElapsed,
        budget: budget,
        engineRole: engineRole,
      ),
    );
    try {
      await operation.timeout(maxCallerImpact);
    } on Object {
      // Best effort only. Future.timeout keeps listening to the underlying
      // operation, so a late failure is also consumed without an unhandled
      // asynchronous error.
    }
  }

  Future<void> _persistTerminal({
    required BackgroundStorageMessageKind kind,
    required BackgroundStorageLivenessPhase phase,
    required BackgroundStorageDeadlinePhaseName phaseName,
    required BackgroundStorageTerminalOutcome outcome,
    required Duration elapsed,
    required Duration phaseElapsed,
    required Duration budget,
    required BackgroundStorageEngineRole engineRole,
  }) async {
    final directory = await _directoryResolver();
    await directory.create(recursive: true);

    final sequence = _sequence++;
    final nonce = _randomNonce() & 0x7fffffff;
    final now = _now();
    await _pruneAbandonedTemporaries(directory, now);
    final slot = await _selectPublicationSlot(
      directory,
      start: (nonce + sequence) % maxEntries,
      slotCount: maxEntries,
    );
    final slotLabel = slot.toString().padLeft(2, '0');
    final stem =
        '$_backgroundStorageLivenessTemporaryPrefix'
        's$slotLabel-'
        '${now.microsecondsSinceEpoch}-'
        '${nonce.toRadixString(16).padLeft(8, '0')}-'
        '${_instanceNonce.toRadixString(16).padLeft(8, '0')}-'
        '$sequence';
    final target = File(
      '${directory.path}${Platform.pathSeparator}'
      '$_backgroundStorageLivenessFilePrefix'
      's$slotLabel$_backgroundStorageLivenessFileExtension',
    );
    final temporary = File(
      '${directory.path}${Platform.pathSeparator}'
      '$stem.tmp',
    );
    // Exact milliseconds ride ALONGSIDE the bucket, never instead of it: the
    // bucket is what existing readers already key off. Values stay decimal
    // strings so the record type is still <String, String>.
    final record = <String, String>{
      'kind': kind.wireName,
      'phase': phase.wireName,
      'phaseName': phaseName.wireName,
      'outcome': outcome.wireName,
      'elapsedBucket': bucketBackgroundStorageElapsed(elapsed).wireName,
      'elapsedMs': elapsed.inMilliseconds.toString(),
      'phaseElapsedMs': phaseElapsed.inMilliseconds.toString(),
      'budgetMs': budget.inMilliseconds.toString(),
      'buildMode': _buildMode.wireName,
      'engineRole': engineRole.wireName,
    };

    try {
      await _atomicWriter(
        temporary: temporary,
        target: target,
        contents: jsonEncode(record),
      );
    } catch (_) {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on FileSystemException {
        // Keep the publication failure; the bounded stale-temp pass can clean
        // residue later without touching the last complete slot record.
      }
      rethrow;
    }
    await _pruner(directory, maxEntries);
  }

  static Future<int> _selectPublicationSlot(
    Directory directory, {
    required int start,
    required int slotCount,
  }) async {
    final occupied = <int, DateTime>{};
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      final match = RegExp(r'^terminal-v1-s(\d{2})\.json$').firstMatch(name);
      if (match == null) continue;
      final slot = int.tryParse(match.group(1)!);
      if (slot == null || slot < 0 || slot >= slotCount) continue;
      try {
        occupied[slot] = await entity.lastModified();
      } on FileSystemException {
        occupied[slot] = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      }
    }

    for (var offset = 0; offset < slotCount; offset += 1) {
      final slot = (start + offset) % slotCount;
      if (!occupied.containsKey(slot)) return slot;
    }

    final byAge = occupied.entries.toList()
      ..sort((left, right) {
        final byTime = left.value.compareTo(right.value);
        return byTime != 0 ? byTime : left.key.compareTo(right.key);
      });
    return byAge.first.key;
  }

  static Future<void> _pruneAbandonedTemporaries(
    Directory directory,
    DateTime now,
  ) async {
    var inspected = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (inspected >= backgroundStorageLivenessJournalMaxEntries) return;
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (!name.startsWith(_backgroundStorageLivenessTemporaryPrefix) ||
          !name.endsWith('.tmp')) {
        continue;
      }
      inspected += 1;
      try {
        final modified = await entity.lastModified();
        if (now.difference(modified) <
            _backgroundStorageLivenessTemporaryRetention) {
          continue;
        }
        await entity.delete();
      } on FileSystemException {
        // Another writer or cleanup pass may own this best-effort residue.
      }
    }
  }

  static int Function() _secureNonceSource() {
    final random = Random.secure();
    return () => random.nextInt(0x7fffffff);
  }

  static int _secureInstanceNonce() {
    return Random.secure().nextInt(0x7fffffff);
  }

  static Future<void> _writeAtomically({
    required File temporary,
    required File target,
    required String contents,
  }) async {
    try {
      await temporary.writeAsString(contents, flush: true);
      await temporary.rename(target.path);
    } catch (_) {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {
        // Keep the original write/publication failure.
      }
      rethrow;
    }
  }

  static Future<void> _pruneOldest(Directory directory, int maxEntries) async {
    final files = await directory
        .list(followLinks: false)
        .where((entity) {
          if (entity is! File) return false;
          final name = entity.path.split(Platform.pathSeparator).last;
          return name.startsWith(_backgroundStorageLivenessFilePrefix) &&
              name.endsWith(_backgroundStorageLivenessFileExtension);
        })
        .cast<File>()
        .toList();
    if (files.length <= maxEntries) return;

    final dated = <({File file, DateTime modified})>[];
    for (final file in files) {
      try {
        dated.add((file: file, modified: await file.lastModified()));
      } on FileSystemException {
        // Another lock-free writer may already have pruned it.
      }
    }
    dated.sort((left, right) {
      final byTime = left.modified.compareTo(right.modified);
      return byTime != 0 ? byTime : left.file.path.compareTo(right.file.path);
    });
    final overflow = dated.length - maxEntries;
    for (var index = 0; index < overflow; index += 1) {
      try {
        await dated[index].file.delete();
      } on FileSystemException {
        // Lock-free concurrent pruning can legitimately win this delete.
      }
    }
  }

  static Future<void> _pruneG21Measurements(
    Directory directory,
    int maxEntries,
  ) async {
    final files = await directory
        .list(followLinks: false)
        .where((entity) {
          if (entity is! File) return false;
          final name = entity.path.split(Platform.pathSeparator).last;
          return name.startsWith(backgroundStorageG21MeasurementFilePrefix) &&
              name.endsWith(_backgroundStorageLivenessFileExtension);
        })
        .cast<File>()
        .toList();
    if (files.length <= maxEntries) return;
    files.sort((left, right) => left.path.compareTo(right.path));
    for (final file in files.take(files.length - maxEntries)) {
      try {
        await file.delete();
      } on FileSystemException {
        // Another lock-free measurement writer may already have pruned it.
      }
    }
  }
}

BackgroundStorageBuildMode get _compiledBuildMode {
  if (kReleaseMode) return BackgroundStorageBuildMode.release;
  if (kProfileMode) return BackgroundStorageBuildMode.profile;
  return BackgroundStorageBuildMode.debug;
}
