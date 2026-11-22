import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/features/translate_preview/gemma_preview_prompts.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';

const modelDeliveryManifestUrl =
    'https://updates.mknoon.xyz/models/gemma-translate.json';
const modelDeliveryGroup = 'mknoon_gemma_translation';
const modelDeliveryDirectory = 'gemma_translation';
const modelDeliverySpaceReserve = 2800000000 - gemmaModelBytes;

enum ModelBlockedReason { totalRam, resourceExhausted, interrupted }

/// Local inference safety, deliberately separate from download preferences.
final class ModelSafetyRecord {
  const ModelSafetyRecord({
    this.blockedReason,
    this.inferenceInProgress = false,
    this.consecutiveInterruptions = 0,
    this.noticePending = false,
  });

  final ModelBlockedReason? blockedReason;
  final bool inferenceInProgress;
  final int consecutiveInterruptions;
  final bool noticePending;

  factory ModelSafetyRecord.fromJson(Map<String, Object?> json) {
    final reason = json['blockedReason'];
    final inProgress = json['inferenceInProgress'];
    final count = json['consecutiveInterruptions'];
    final notice = json['noticePending'];
    final matches = ModelBlockedReason.values.where(
      (value) => value.name == reason,
    );
    if ((reason != null && matches.isEmpty) ||
        inProgress is! bool ||
        count is! int ||
        count < 0 ||
        notice is! bool) {
      throw const FormatException('Invalid translator safety state');
    }
    return ModelSafetyRecord(
      blockedReason: reason == null ? null : matches.single,
      inferenceInProgress: inProgress,
      consecutiveInterruptions: count,
      noticePending: notice,
    );
  }

  Map<String, Object?> toJson() => {
    'blockedReason': blockedReason?.name,
    'inferenceInProgress': inferenceInProgress,
    'consecutiveInterruptions': consecutiveInterruptions,
    'noticePending': noticePending,
  };
}

final class ModelDeliveryManifest {
  const ModelDeliveryManifest({
    required this.url,
    required this.bytes,
    required this.sha256,
    required this.minAppBuild,
  });

  factory ModelDeliveryManifest.fromJson(Map<String, Object?> json) {
    final model = json['model'];
    final url = json['url'];
    final bytes = json['bytes'];
    final sha256 = json['sha256'];
    final minAppBuild = json['minAppBuild'];
    if (model != 'gemma-4-E2B-it' ||
        url is! String ||
        bytes is! int ||
        bytes <= 0 ||
        sha256 is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256) ||
        minAppBuild is! int ||
        minAppBuild < 0) {
      throw const FormatException('Invalid translator manifest');
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'updates.mknoon.xyz' ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path !=
            '/models/gemma-4-E2B-it-${sha256.substring(0, 12).toLowerCase()}.litertlm') {
      throw const FormatException('Invalid translator model URL');
    }
    return ModelDeliveryManifest(
      url: uri,
      bytes: bytes,
      sha256: sha256.toLowerCase(),
      minAppBuild: minAppBuild,
    );
  }

  final Uri url;
  final int bytes;
  final String sha256;
  final int minAppBuild;

  Map<String, Object?> toJson() => {
    'model': 'gemma-4-E2B-it',
    'url': url.toString(),
    'bytes': bytes,
    'sha256': sha256,
    'minAppBuild': minAppBuild,
  };
}

enum ModelDeliveryPhase {
  idle,
  awaitingConnection,
  insufficientSpace,
  active,
  waitingToRetry,
  waitingForConnection,
  serverRetry,
  transferNeedsSpace,
  storageWriteFailed,
  restartRequired,
  resumeRequested,
  pauseRequested,
  userPaused,
  policyPauseRequested,
  verifying,
  integrityRepairPending,
  integrityFailed,
  failed,
  ready,
  removing,
}

final class ModelDeliveryFileIdentity {
  const ModelDeliveryFileIdentity({
    required this.canonicalPath,
    required this.sizeBytes,
    required this.modifiedMicros,
    required this.changedMicros,
  });

  final String canonicalPath;
  final int sizeBytes;
  final int modifiedMicros;
  final int changedMicros;

  @override
  bool operator ==(Object other) =>
      other is ModelDeliveryFileIdentity &&
      canonicalPath == other.canonicalPath &&
      sizeBytes == other.sizeBytes &&
      modifiedMicros == other.modifiedMicros &&
      changedMicros == other.changedMicros;
  @override
  int get hashCode =>
      Object.hash(canonicalPath, sizeBytes, modifiedMicros, changedMicros);

  Map<String, Object?> toJson() => {
    'canonicalPath': canonicalPath,
    'sizeBytes': sizeBytes,
    'modifiedMicros': modifiedMicros,
    'changedMicros': changedMicros,
  };
}

final class ModelDeliveryVerification {
  const ModelDeliveryVerification({
    required this.expectedSha256,
    required this.identity,
  });
  final String expectedSha256;
  final ModelDeliveryFileIdentity identity;

  static ModelDeliveryVerification? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final sha = json['expectedSha256'];
    final file = json['identity'];
    if (sha is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha) ||
        file is! Map<String, Object?>) {
      return null;
    }
    final path = file['canonicalPath'];
    final size = file['sizeBytes'];
    final modified = file['modifiedMicros'];
    final changed = file['changedMicros'];
    if (path is! String ||
        path.isEmpty ||
        size is! int ||
        size < 0 ||
        modified is! int ||
        changed is! int) {
      return null;
    }
    return ModelDeliveryVerification(
      expectedSha256: sha,
      identity: ModelDeliveryFileIdentity(
        canonicalPath: path,
        sizeBytes: size,
        modifiedMicros: modified,
        changedMicros: changed,
      ),
    );
  }

  bool matches(
    ModelDeliveryManifest manifest,
    ModelDeliveryFileIdentity? file,
  ) =>
      expectedSha256 == manifest.sha256 &&
      identity == file &&
      identity.sizeBytes == manifest.bytes;

  Map<String, Object?> toJson() => {
    'expectedSha256': expectedSha256,
    'identity': identity.toJson(),
  };
}

final class ModelDeliveryRecord {
  const ModelDeliveryRecord({
    this.manifest,
    this.taskId,
    this.receivedBytes = 0,
    this.phase = ModelDeliveryPhase.idle,
    this.allowMobileData = false,
    this.verification,
    this.integrityRepairAttempted = false,
    this.recovery,
  });

  factory ModelDeliveryRecord.fromJson(Map<String, Object?> json) {
    final manifest = json['manifest'];
    final taskId = json['taskId'];
    final receivedBytes = json['receivedBytes'];
    final phase = json['phase'];
    final allow = json['allowMobileData'];
    if (json['version'] != 1 ||
        (manifest != null && manifest is! Map<String, Object?>) ||
        (taskId != null && taskId is! String) ||
        receivedBytes is! int ||
        receivedBytes < 0 ||
        phase is! String ||
        allow is! bool) {
      throw const FormatException('Invalid translator record');
    }
    return ModelDeliveryRecord(
      manifest: manifest == null
          ? null
          : ModelDeliveryManifest.fromJson(manifest as Map<String, Object?>),
      taskId: taskId as String?,
      receivedBytes: receivedBytes,
      phase: ModelDeliveryPhase.values.byName(phase),
      allowMobileData: allow,
      verification: ModelDeliveryVerification.tryFromJson(json['verification']),
      integrityRepairAttempted: json['integrityRepairAttempted'] == true,
      recovery: ModelTransferRecovery.tryFromJson(json['recovery']),
    );
  }

  final ModelDeliveryManifest? manifest;
  final String? taskId;
  final int receivedBytes;
  final ModelDeliveryPhase phase;
  final bool allowMobileData;
  final ModelDeliveryVerification? verification;
  final bool integrityRepairAttempted;
  final ModelTransferRecovery? recovery;

  ModelDeliveryRecord copyWith({
    ModelDeliveryManifest? manifest,
    String? taskId,
    bool clearTask = false,
    int? receivedBytes,
    ModelDeliveryPhase? phase,
    bool? allowMobileData,
    ModelDeliveryVerification? verification,
    bool clearVerification = false,
    bool? integrityRepairAttempted,
    ModelTransferRecovery? recovery,
    bool clearRecovery = false,
  }) => ModelDeliveryRecord(
    manifest: manifest ?? this.manifest,
    taskId: clearTask ? null : taskId ?? this.taskId,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    phase: phase ?? this.phase,
    allowMobileData: allowMobileData ?? this.allowMobileData,
    verification: clearTask || clearVerification
        ? null
        : verification ?? this.verification,
    integrityRepairAttempted:
        integrityRepairAttempted ?? this.integrityRepairAttempted,
    recovery: clearRecovery
        ? null
        : recovery ?? (clearTask ? null : this.recovery),
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'manifest': manifest?.toJson(),
    'taskId': taskId,
    'receivedBytes': receivedBytes,
    'phase': phase.name,
    'allowMobileData': allowMobileData,
    'verification': verification?.toJson(),
    if (integrityRepairAttempted) 'integrityRepairAttempted': true,
    if (recovery != null) 'recovery': recovery!.toJson(),
  };
}

final class ModelResumeCheckpoint {
  const ModelResumeCheckpoint({required this.retainedBytes});

  /// iOS exposes an opaque resume token and no trusted byte offset.
  final int? retainedBytes;
}

final class ModelTransferRecovery {
  const ModelTransferRecovery({
    this.checkpoint,
    this.restartsFromZero = false,
    this.serverAttempts = 0,
    this.retryAt,
  });

  final ModelResumeCheckpoint? checkpoint;
  final bool restartsFromZero;
  final int serverAttempts;
  final DateTime? retryAt;

  static ModelTransferRecovery? tryFromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final bytes = json['retainedBytes'];
    final hasCheckpoint = json['hasCheckpoint'] == true;
    final attempts = json['serverAttempts'];
    final at = json['retryAt'];
    return ModelTransferRecovery(
      checkpoint: hasCheckpoint && (bytes == null || bytes is int && bytes > 0)
          ? ModelResumeCheckpoint(retainedBytes: bytes as int?)
          : null,
      restartsFromZero: json['restartsFromZero'] == true,
      serverAttempts: attempts is int ? max(0, attempts) : 0,
      retryAt: at is String ? DateTime.tryParse(at) : null,
    );
  }

  Map<String, Object?> toJson() => {
    'hasCheckpoint': checkpoint != null,
    'retainedBytes': checkpoint?.retainedBytes,
    'restartsFromZero': restartsFromZero,
    'serverAttempts': serverAttempts,
    'retryAt': retryAt?.toIso8601String(),
  };
}

enum ModelTransferFailure {
  connection,
  server,
  storageFull,
  storageWrite,
  invalidCheckpoint,
}

enum ModelTransferStatus {
  enqueued,
  running,
  waitingToRetry,
  paused,
  complete,
  failed,
  canceled,
}

enum ModelQueuedPolicyUpdate { applied, running, unavailable }

final class ModelTransferEvent {
  const ModelTransferEvent({
    required this.taskId,
    this.status,
    this.receivedBytes,
    this.remaining,
    this.failure,
  });

  final String taskId;
  final ModelTransferStatus? status;
  final int? receivedBytes;
  final Duration? remaining;
  final ModelTransferFailure? failure;
}

final class ModelTransferSnapshot {
  const ModelTransferSnapshot({
    required this.taskId,
    required this.status,
    required this.receivedBytes,
    this.failure,
    this.requiresWiFi,
  });

  final String taskId;
  final ModelTransferStatus status;
  final int receivedBytes;
  final ModelTransferFailure? failure;
  final bool? requiresWiFi;
}

abstract interface class ModelDeliveryStorage {
  Future<ModelDeliveryRecord?> readRecord();
  Future<void> saveRecord(ModelDeliveryRecord record);
  Future<ModelSafetyRecord?> readSafety();
  Future<void> saveSafety(ModelSafetyRecord record);
  Future<void> prepare();
  Future<int> availableBytes();
  Future<int?> modelLength();
  Future<ModelDeliveryFileIdentity?> modelIdentity();
  Future<bool> verify(ModelDeliveryManifest manifest);
  Future<String> modelPath();
  Future<void> removeOwnedModel();
}

enum ModelDeliveryConnection { offline, wifi, other }

abstract interface class ModelDeliveryNetwork {
  Future<Map<String, Object?>> fetchManifest();
  Future<ModelDeliveryConnection> checkConnection();
  Stream<ModelDeliveryConnection> get connectionChanges;
}

abstract interface class ModelDeliveryTransport {
  bool get canRecoverUnexpectedPauses;
  Stream<ModelTransferEvent> get events;
  Future<void> initialize(String? ownedTaskId);
  Future<ModelTransferSnapshot?> restore(String taskId);
  Future<ModelResumeCheckpoint?> checkpoint(String taskId);
  Future<ModelQueuedPolicyUpdate> updateQueuedPolicy(
    String taskId, {
    required bool requiresWiFi,
  });
  Future<bool> enqueue({
    required String taskId,
    required ModelDeliveryManifest manifest,
    required bool requiresWiFi,
  });
  Future<bool> pause(String taskId);
  Future<bool> resume(
    String taskId, {
    required bool requiresWiFi,
    bool allowZeroByteRestart = true,
  });
  Future<void> cancel(String taskId);
  Future<void> forget(String taskId);
  Future<void> dispose();
}

final class PersistentModelDeliveryController extends ModelDeliveryController {
  PersistentModelDeliveryController({
    required ModelDeliveryStorage storage,
    required ModelDeliveryNetwork network,
    required ModelDeliveryTransport transport,
    required Future<int> Function() appBuild,
    bool supported = false,
    Future<bool> Function()? readAvailableMemory,
    Future<({bool supported, bool insufficientMemory})> Function()?
    readCapability,
    int spaceReserveBytes = modelDeliverySpaceReserve,
    String Function()? newTaskId,
    Future<void> Function(ModelDeliveryState)? publishBackgroundStatus,
    Future<void> Function()? clearBackgroundStatus,
  }) : _storage = storage,
       _network = network,
       _transport = transport,
       _appBuild = appBuild,
       _supported = ValueNotifier(supported),
       _readAvailableMemory = readAvailableMemory ?? (() async => false),
       _readCapability = readCapability,
       _spaceReserveBytes = spaceReserveBytes,
       _publishBackgroundStatus = publishBackgroundStatus,
       _clearBackgroundStatus = clearBackgroundStatus,
       _newTaskId = newTaskId ?? _makeTaskId {
    _transferSubscription = _transport.events.listen(_receiveEvent);
    _connectionSubscription = _network.connectionChanges.listen(
      _receiveConnection,
    );
  }

  final ModelDeliveryStorage _storage;
  final ModelDeliveryNetwork _network;
  final ModelDeliveryTransport _transport;
  final Future<int> Function() _appBuild;
  final Future<bool> Function() _readAvailableMemory;
  final Future<({bool supported, bool insufficientMemory})> Function()?
  _readCapability;
  final int _spaceReserveBytes;
  final Future<void> Function(ModelDeliveryState)? _publishBackgroundStatus;
  final Future<void> Function()? _clearBackgroundStatus;
  final String Function() _newTaskId;
  final _state = ValueNotifier<ModelDeliveryState>(const ModelUnsupported());
  final _allowMobileData = ValueNotifier(false);
  final _memoryNoticePending = ValueNotifier(false);
  late final StreamSubscription<ModelTransferEvent> _transferSubscription;
  late final StreamSubscription<ModelDeliveryConnection>
  _connectionSubscription;
  Future<void>? _initialization;
  Future<void> _tail = Future.value();
  // Remove owns _tail while awaiting Gemma's queue. Inference safety must never
  // join it while Gemma owns that queue, or the two operations deadlock.
  Future<void> _safetyTail = Future.value();
  ModelSafetyRecord _safety = const ModelSafetyRecord();
  bool _inferenceActive = false;
  ModelDeliveryRecord _record = const ModelDeliveryRecord();
  final ValueNotifier<bool> _supported;
  ModelDeliveryConnection _connection = ModelDeliveryConnection.offline;
  bool _disposed = false;
  int _build = 0;
  int _freeBytes = 0;
  int _generation = 0;
  String? _verifiedPath;
  Duration? _remaining;
  bool _queuedRequiresWifi = false;
  String? _previouslyReadyTaskId;
  ({String taskId, int generation})? _verification;
  Timer? _recoveryTimer;
  int _recoveryDelaySeconds = 5;
  static const _serverRetrySeconds = [5, 15, 45];

  @override
  ValueListenable<ModelDeliveryState> get state => _state;

  @override
  ValueListenable<bool> get deviceSupported => _supported;

  @override
  ValueListenable<bool> get allowMobileData => _allowMobileData;

  @override
  ValueListenable<bool> get memoryNoticePending => _memoryNoticePending;

  static String _makeTaskId() =>
      'gemma_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 31)}';

  Future<void> initialize() async {
    final existing = _initialization;
    if (existing != null) {
      await existing;
      return;
    }
    final initial = _initialize();
    _initialization = initial;
    await initial;
  }

  Future<void> _initialize() async {
    final generation = _generation;
    try {
      _record = await _storage.readRecord() ?? const ModelDeliveryRecord();
      _allowMobileData.value = _record.allowMobileData;
      _build = await _appBuild();
      await _storage.prepare();
      _safety = await _storage.readSafety() ?? const ModelSafetyRecord();
      if (_safety.inferenceInProgress) {
        final count = _safety.consecutiveInterruptions + 1;
        final newlyBlocked = count >= 2 && _safety.blockedReason == null;
        await _saveSafety(
          ModelSafetyRecord(
            blockedReason: newlyBlocked
                ? ModelBlockedReason.interrupted
                : _safety.blockedReason,
            consecutiveInterruptions: count,
            noticePending: _safety.noticePending || newlyBlocked,
          ),
        );
      } else {
        _memoryNoticePending.value = _safety.noticePending;
      }
      _connection = await _network.checkConnection();
      _freeBytes = await _storage.availableBytes();
      await _transport.initialize(_record.taskId);
      if (_record.phase == ModelDeliveryPhase.removing) {
        await _remove();
        return;
      }
      if (_record.phase == ModelDeliveryPhase.integrityRepairPending) {
        _render();
        await _continueIntegrityRepair();
        return;
      }
      if (_hasManagedRecovery) {
        await _restoreManagedCheckpoint();
        _render();
        return;
      }
      final manifest = _record.manifest;
      if (_record.phase == ModelDeliveryPhase.ready && manifest != null) {
        _previouslyReadyTaskId = _record.taskId;
        final identity = await _storage.modelIdentity();
        if (generation == _generation &&
            (_record.verification?.matches(manifest, identity) ?? false)) {
          _verifiedPath = identity!.canonicalPath;
          _render();
          return;
        }
        _record = _record.copyWith(phase: ModelDeliveryPhase.verifying);
        _render();
        if (_canRun) _beginVerification();
        return;
      }
      final id = _record.taskId;
      if (id != null) {
        final recovered = await _transport.restore(id);
        if (recovered != null) {
          _queuedRequiresWifi =
              recovered.status == ModelTransferStatus.enqueued &&
              recovered.requiresWiFi == true;
          if (recovered.failure case final failure?) {
            if (_record.phase != ModelDeliveryPhase.userPaused &&
                _record.phase != ModelDeliveryPhase.pauseRequested) {
              await _recoverFromFailure(failure);
              await _persist();
              _render();
              return;
            }
          }
          final retryPausedTask =
              recovered.status == ModelTransferStatus.paused &&
              _shouldRecoverUnexpectedPause;
          _record = _record.copyWith(
            receivedBytes: _clamp(
              retryPausedTask ||
                      recovered.status == ModelTransferStatus.failed ||
                      recovered.status == ModelTransferStatus.enqueued
                  ? max(_record.receivedBytes, recovered.receivedBytes)
                  : recovered.receivedBytes,
            ),
          );
          switch (recovered.status) {
            case ModelTransferStatus.complete:
              _record = _record.copyWith(phase: ModelDeliveryPhase.verifying);
            case ModelTransferStatus.paused:
              _record = _record.copyWith(
                phase: retryPausedTask
                    ? ModelDeliveryPhase.waitingToRetry
                    : ModelDeliveryPhase.userPaused,
              );
            case ModelTransferStatus.failed:
              if (_record.phase != ModelDeliveryPhase.userPaused &&
                  _record.phase != ModelDeliveryPhase.pauseRequested) {
                await _recoverFromFailure(null);
                await _persist();
              }
            case ModelTransferStatus.canceled:
              _record = _record.copyWith(phase: ModelDeliveryPhase.failed);
            case ModelTransferStatus.enqueued ||
                ModelTransferStatus.running ||
                ModelTransferStatus.waitingToRetry:
              if (_record.phase == ModelDeliveryPhase.policyPauseRequested) {
                await _applyTransferPolicy(
                  id,
                  ModelDeliveryPhase.active,
                  restored: recovered,
                );
              } else if (_record.phase == ModelDeliveryPhase.pauseRequested ||
                  _record.phase == ModelDeliveryPhase.userPaused) {
                await _transport.pause(id);
              } else {
                _record = _record.copyWith(phase: ModelDeliveryPhase.active);
              }
          }
        } else if (_record.phase != ModelDeliveryPhase.idle &&
            _record.manifest != null &&
            await _storage.modelLength() == _totalBytes) {
          _record = _record.copyWith(phase: ModelDeliveryPhase.verifying);
        } else {
          _record = _record.copyWith(phase: ModelDeliveryPhase.userPaused);
        }
      }
      _render();
      if (_canRun && _record.phase == ModelDeliveryPhase.verifying) {
        _beginVerification();
      } else if (_canStartPending) {
        await _startOrResume();
      }
    } on Object {
      _record = _record.copyWith(phase: ModelDeliveryPhase.failed);
      _render();
    }
  }

  void setCapability(bool supported, {bool insufficientMemory = false}) {
    if (_disposed) return;
    _supported.value = supported;
    if (!supported) {
      _generation++;
      _cancelRecoveryTimer();
      _verifiedPath = null;
      _state.value = const ModelUnsupported();
    }
    unawaited(
      _perform(() async {
        if (insufficientMemory) {
          await _safetyQueue(() async {
            if (_safety.blockedReason == null) {
              await _saveSafety(
                ModelSafetyRecord(
                  blockedReason: ModelBlockedReason.totalRam,
                  inferenceInProgress: _safety.inferenceInProgress,
                  consecutiveInterruptions: _safety.consecutiveInterruptions,
                  noticePending: true,
                ),
              );
            }
          });
        }
        if (!supported && _record.phase == ModelDeliveryPhase.ready) {
          _record = _record.copyWith(phase: ModelDeliveryPhase.verifying);
          await _persist();
        }
        if (!supported && _record.phase == ModelDeliveryPhase.active) {
          final id = _record.taskId;
          if (id != null) await _transport.pause(id);
          _record = _record.copyWith(phase: ModelDeliveryPhase.userPaused);
          await _persist();
        }
        _render();
        if (_canRun && _record.phase == ModelDeliveryPhase.verifying) {
          _beginVerification();
        } else if (_record.phase == ModelDeliveryPhase.integrityRepairPending) {
          await _continueIntegrityRepair();
        } else if (_canStartPending) {
          await _startOrResume();
        }
      }),
    );
  }

  Future<void> beginInference({bool modelAlreadyLoaded = false}) async {
    await initialize();
    await _safetyQueue(() async {
      if (_safety.blockedReason != null) {
        throw const TranslatorMemoryUnsupported();
      }
      if (_disposed ||
          !_canRun ||
          _state.value is! ModelReady ||
          _verifiedPath == null) {
        throw StateError('Translator model is not ready');
      }
      final generation = _generation;
      if (!modelAlreadyLoaded) {
        bool available;
        try {
          available = await _readAvailableMemory();
        } on Object {
          available = false;
        }
        if (!available) throw const TranslatorMemoryTemporarilyUnavailable();
      }
      if (_disposed ||
          generation != _generation ||
          !_canRun ||
          _verifiedPath == null) {
        throw StateError('Translator model is no longer ready');
      }
      await _saveSafety(
        ModelSafetyRecord(
          inferenceInProgress: true,
          consecutiveInterruptions: _safety.consecutiveInterruptions,
          noticePending: _safety.noticePending,
        ),
      );
      _inferenceActive = true;
    });
  }

  /// Called only after session/error cleanup. Every completed attempt breaks
  /// the interruption streak; a refusal before beginInference does not.
  Future<void> finishInference({
    required bool succeeded,
    bool resourceExhausted = false,
  }) => _safetyQueue(() async {
    final completed = ModelSafetyRecord(
      blockedReason: resourceExhausted
          ? ModelBlockedReason.resourceExhausted
          : _safety.blockedReason,
      consecutiveInterruptions: succeeded || !resourceExhausted
          ? 0
          : _safety.consecutiveInterruptions,
      noticePending: _safety.noticePending || resourceExhausted,
    );
    if (resourceExhausted) {
      // Refuse queued allocations even if persisting the block fails.
      _safety = completed;
      if (!_disposed) _memoryNoticePending.value = true;
      _render();
    }
    try {
      await _saveSafety(completed);
    } finally {
      _inferenceActive = false;
      _render();
    }
  });

  @override
  Future<bool> consumeMemoryNotice() async {
    await initialize();
    var consumed = false;
    await _safetyQueue(() async {
      if (!_safety.noticePending) return;
      await _saveSafety(
        ModelSafetyRecord(
          blockedReason: _safety.blockedReason,
          inferenceInProgress: _safety.inferenceInProgress,
          consecutiveInterruptions: _safety.consecutiveInterruptions,
        ),
      );
      consumed = true;
    });
    return consumed;
  }

  @override
  Future<void> retryMemorySafety() async {
    await initialize();
    var temporary = false;
    await _safetyQueue(() async {
      if (_disposed || _inferenceActive) return;
      await _saveSafety(const ModelSafetyRecord());
      final facts =
          await _readCapability?.call() ??
          (supported: _supported.value, insufficientMemory: false);
      _supported.value = facts.supported;
      if (facts.insufficientMemory) {
        await _saveSafety(
          const ModelSafetyRecord(
            blockedReason: ModelBlockedReason.totalRam,
            noticePending: true,
          ),
        );
      } else if (_supported.value) {
        try {
          temporary = !await _readAvailableMemory();
        } on Object {
          temporary = true;
        }
      }
      _render();
      if (_canRun && _record.phase == ModelDeliveryPhase.verifying) {
        _beginVerification();
      }
    });
    if (temporary) throw const TranslatorMemoryTemporarilyUnavailable();
  }

  Future<void> _saveSafety(ModelSafetyRecord value) async {
    await _storage.saveSafety(value);
    _safety = value;
    if (!_disposed) _memoryNoticePending.value = value.noticePending;
  }

  Future<void> _safetyQueue(Future<void> Function() action) {
    final run = _safetyTail.then((_) => action());
    _safetyTail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  // This snapshot must not queue behind Remove, which waits for Gemma's queue.
  Future<String> verifiedModelPath() async {
    final path = _verifiedPath;
    if (!_canRun || _state.value is! ModelReady || path == null) {
      throw StateError('Translator model is not ready');
    }
    return path;
  }

  @override
  Future<void> refresh() async {
    try {
      await initialize();
      await _queue(() async {
        final connection = await _network.checkConnection();
        final freeBytes = await _storage.availableBytes();
        if (_disposed) return;
        _connection = connection;
        _freeBytes = freeBytes;
        if (_record.phase == ModelDeliveryPhase.insufficientSpace &&
            _freeBytes >= _neededBytes) {
          _record = _record.copyWith(
            phase: _record.taskId == null
                ? ModelDeliveryPhase.idle
                : ModelDeliveryPhase.userPaused,
          );
        }
        if (_record.phase == ModelDeliveryPhase.idle ||
            _record.phase == ModelDeliveryPhase.insufficientSpace ||
            _record.phase == ModelDeliveryPhase.userPaused ||
            _record.phase == ModelDeliveryPhase.transferNeedsSpace) {
          _render();
        }
      });
    } on Object {
      // An optional admission recheck keeps the last measured offer on failure.
    }
  }

  @override
  Future<void> setAllowMobileData(bool allow) => _perform(() async {
    await _setAllowMobileData(allow);
    if (_canStartPending) await _startOrResume();
  });

  Future<void> _setAllowMobileData(bool allow) async {
    if (_record.allowMobileData == allow) return;
    final id = _record.taskId;
    final previousPhase = _record.phase;
    final active =
        id != null &&
        (previousPhase == ModelDeliveryPhase.active ||
            previousPhase == ModelDeliveryPhase.resumeRequested);
    if (active && !allow) {
      final transfer = await _transport.restore(id);
      if (transfer != null && transfer.status == ModelTransferStatus.enqueued) {
        await _revokeQueuedMobileData(id, previousPhase, transfer);
        _render();
        return;
      }
    }
    _allowMobileData.value = allow;
    _record = _record.copyWith(
      allowMobileData: allow,
      phase: active ? ModelDeliveryPhase.policyPauseRequested : previousPhase,
    );
    await _persist();
    if (active) await _applyTransferPolicy(id, previousPhase);
    _render();
  }

  Future<void> _applyTransferPolicy(
    String id,
    ModelDeliveryPhase previousPhase, {
    ModelTransferSnapshot? restored,
  }) async {
    final allow = _record.allowMobileData;
    final transfer = restored ?? await _transport.restore(id);
    var hasProgress =
        _record.receivedBytes > 0 || _record.recovery?.checkpoint != null;
    if (transfer != null && transfer.status == ModelTransferStatus.enqueued) {
      if (!allow) {
        await _revokeQueuedMobileData(id, previousPhase, transfer);
        return;
      }
      final checkpoint = await _transport.checkpoint(id);
      hasProgress = hasProgress || checkpoint != null;
      if (!hasProgress) {
        // A constrained queued worker cannot consume a pause request yet.
        await _cancelOwnedTask();
        await _storage.removeOwnedModel();
        _record = _record.copyWith(
          clearTask: true,
          receivedBytes: 0,
          phase: ModelDeliveryPhase.idle,
        );
        await _persist();
        await _startOrResume();
        return;
      }
      final reconfigured = transfer.requiresWiFi == false
          ? ModelQueuedPolicyUpdate.applied
          : checkpoint == null
          ? ModelQueuedPolicyUpdate.unavailable
          : await _transport.updateQueuedPolicy(id, requiresWiFi: false);
      if (reconfigured == ModelQueuedPolicyUpdate.applied ||
          reconfigured == ModelQueuedPolicyUpdate.unavailable) {
        _queuedRequiresWifi =
            reconfigured == ModelQueuedPolicyUpdate.unavailable;
        _record = _record.copyWith(
          phase: previousPhase,
          receivedBytes: checkpoint?.retainedBytes,
        );
        await _persist();
        return;
      }
    }
    if (await _transport.pause(id)) return;
    if (hasProgress && allow) {
      _queuedRequiresWifi = true;
      _record = _record.copyWith(phase: previousPhase);
    } else {
      await _transport.cancel(id);
      _record = _record.copyWith(
        phase: hasProgress
            ? ModelDeliveryPhase.restartRequired
            : ModelDeliveryPhase.failed,
        recovery: hasProgress
            ? const ModelTransferRecovery(restartsFromZero: true)
            : null,
      );
    }
    await _persist();
  }

  Future<void> _revokeQueuedMobileData(
    String id,
    ModelDeliveryPhase previousPhase,
    ModelTransferSnapshot transfer,
  ) async {
    final checkpoint = await _transport.checkpoint(id);
    final hasProgress =
        checkpoint != null ||
        _record.receivedBytes > 0 ||
        _record.recovery?.checkpoint != null;
    final nowWifiOnly =
        transfer.requiresWiFi == true ||
        checkpoint != null &&
            await _transport.updateQueuedPolicy(id, requiresWiFi: true) ==
                ModelQueuedPolicyUpdate.applied;
    if (nowWifiOnly) {
      _queuedRequiresWifi = true;
      _record = _record.copyWith(
        phase: previousPhase,
        receivedBytes: checkpoint?.retainedBytes,
      );
    } else if (hasProgress) {
      // A native pause request is volatile while the job is still queued.
      await _transport.cancel(id);
      _record = _record.copyWith(
        phase: ModelDeliveryPhase.restartRequired,
        recovery: const ModelTransferRecovery(restartsFromZero: true),
      );
    } else {
      await _cancelOwnedTask();
      await _storage.removeOwnedModel();
      _record = _record.copyWith(
        clearTask: true,
        receivedBytes: 0,
        phase: ModelDeliveryPhase.idle,
      );
    }
    _record = _record.copyWith(allowMobileData: false);
    await _persist();
    _allowMobileData.value = false;
    if (_record.phase == ModelDeliveryPhase.idle) await _startOrResume();
  }

  @override
  Future<void> start({required bool allowMobileData}) {
    _generation++;
    _resetRecoveryDelay();
    return _perform(() async {
      await _setAllowMobileData(allowMobileData);
      await _startOrResume();
    });
  }

  @override
  Future<void> cancelPendingStart() {
    if (_state.value is ModelAwaitingConnection) _generation++;
    return _perform(() async {
      if (_record.phase != ModelDeliveryPhase.awaitingConnection) return;
      _record = _record.copyWith(phase: ModelDeliveryPhase.idle);
      await _persist();
      _render();
    });
  }

  @override
  Future<void> resume() {
    _generation++;
    _resetRecoveryDelay();
    return _perform(_startOrResume);
  }

  @override
  Future<void> retry() {
    _generation++;
    _resetRecoveryDelay();
    return _perform(() async {
      if (_record.phase == ModelDeliveryPhase.removing) {
        await _remove();
      } else {
        if (_record.phase == ModelDeliveryPhase.integrityFailed) {
          _record = _record.copyWith(
            phase: ModelDeliveryPhase.idle,
            integrityRepairAttempted: false,
          );
          await _persist();
        }
        if (_record.phase == ModelDeliveryPhase.serverRetry &&
            _record.recovery?.retryAt == null) {
          final recovery = _record.recovery;
          _record = _record.copyWith(
            recovery: ModelTransferRecovery(
              checkpoint: recovery?.checkpoint,
              restartsFromZero: recovery?.restartsFromZero ?? false,
            ),
          );
          await _persist();
        }
        await _startOrResume(manualRetry: true);
      }
    });
  }

  Future<void> _startOrResume({
    int? recoveryGeneration,
    bool useCachedManifest = false,
    bool manualRetry = false,
  }) async {
    if (!_canRun || _record.phase == ModelDeliveryPhase.removing) return;
    if (_record.phase == ModelDeliveryPhase.ready ||
        _record.phase == ModelDeliveryPhase.active ||
        _record.phase == ModelDeliveryPhase.resumeRequested ||
        _record.phase == ModelDeliveryPhase.pauseRequested ||
        _record.phase == ModelDeliveryPhase.policyPauseRequested) {
      return;
    }
    _verifiedPath = null;
    final recovering = recoveryGeneration != null;
    final managedRecovery = _hasManagedRecovery;
    final needsFreshStart = _record.recovery?.restartsFromZero ?? false;
    if (needsFreshStart && !manualRetry) return;
    final pending = _record.phase == ModelDeliveryPhase.awaitingConnection;
    final generation = _generation;
    if (!recovering) {
      _connection = await _network.checkConnection();
      if (await _deferOfflineStart()) return;
      if (pending && !_canStartPending) {
        _render();
        return;
      }
    }
    final cached = _record.manifest;
    var manifest = cached;
    if (!recovering && !useCachedManifest && !managedRecovery) {
      Map<String, Object?> raw;
      try {
        raw = await _network.fetchManifest();
      } on Object {
        if (cached == null) {
          _connection = await _network.checkConnection();
          if (await _deferOfflineStart()) return;
          rethrow;
        }
        raw = cached.toJson();
      }
      manifest = ModelDeliveryManifest.fromJson(raw);
      final sameFile =
          cached?.sha256 == manifest.sha256 &&
          cached?.bytes == manifest.bytes &&
          cached?.url == manifest.url;
      if (!sameFile) {
        if (_record.taskId != null) {
          if (_record.receivedBytes > 0 ||
              _record.recovery?.checkpoint != null) {
            _record = _record.copyWith(
              manifest: manifest,
              phase: ModelDeliveryPhase.restartRequired,
              recovery: const ModelTransferRecovery(restartsFromZero: true),
              integrityRepairAttempted: false,
            );
            await _persist();
            _render();
            return;
          }
          await _cancelOwnedTask();
          await _storage.removeOwnedModel();
          _record = _record.copyWith(clearTask: true, receivedBytes: 0);
        }
        _record = _record.copyWith(integrityRepairAttempted: false);
      }
      _record = _record.copyWith(manifest: manifest);
      await _persist();
    }
    if (manifest == null || !_canRun) {
      _render();
      return;
    }
    await _storage.prepare();
    _connection = await _network.checkConnection();
    _freeBytes = await _storage.availableBytes();
    final hasCompleteFile = await _storage.modelLength() == manifest.bytes;
    if (recovering &&
        (recoveryGeneration != _generation || !_canRecoverTransfer)) {
      _render();
      return;
    }
    if (pending && (generation != _generation || !_canStartPending)) {
      _render();
      return;
    }
    if (hasCompleteFile && !needsFreshStart) {
      _record = _record.copyWith(
        taskId: _record.taskId ?? _newTaskId(),
        receivedBytes: manifest.bytes,
        phase: ModelDeliveryPhase.verifying,
      );
      await _persist();
      _render();
      _beginVerification();
      return;
    }
    if (!recovering && await _deferOfflineStart()) return;
    final transferNeedsSpace =
        _record.phase == ModelDeliveryPhase.transferNeedsSpace;
    final requiredBytes = managedRecovery
        ? _neededBytesForRecovery
        : _neededBytes;
    if (requiredBytes != null && _freeBytes < requiredBytes) {
      if (!transferNeedsSpace) {
        _record = _record.copyWith(
          phase: managedRecovery
              ? ModelDeliveryPhase.transferNeedsSpace
              : ModelDeliveryPhase.insufficientSpace,
        );
      }
      await _persist();
      _render();
      return;
    }
    var id = _record.taskId;
    final resumeCheckpoint = _record.recovery?.checkpoint;
    if (id != null &&
        (needsFreshStart || managedRecovery && resumeCheckpoint == null)) {
      await _cancelOwnedTask();
      await _storage.removeOwnedModel();
      _record = _record.copyWith(
        clearTask: true,
        receivedBytes: 0,
        recovery: ModelTransferRecovery(
          serverAttempts: _record.recovery?.serverAttempts ?? 0,
        ),
      );
      id = null;
    }
    if (id != null &&
        (_record.phase != ModelDeliveryPhase.failed ||
            resumeCheckpoint != null)) {
      if (!recovering || managedRecovery) {
        _record = _record.copyWith(phase: ModelDeliveryPhase.resumeRequested);
        await _persist();
      }
      final accepted = await _transport.resume(
        id,
        requiresWiFi: !_record.allowMobileData,
        allowZeroByteRestart:
            resumeCheckpoint == null && _record.receivedBytes == 0,
      );
      if ((recovering || managedRecovery) && accepted) {
        _record = _record.copyWith(phase: ModelDeliveryPhase.active);
        await _persist();
      }
      if (accepted || recovering && !managedRecovery) {
        if (accepted) _queuedRequiresWifi = !_record.allowMobileData;
        _render();
        if (accepted) _runNotice(_clearBackgroundStatus);
        return;
      }
      if (resumeCheckpoint != null || _record.receivedBytes > 0) {
        _record = _record.copyWith(
          phase: ModelDeliveryPhase.restartRequired,
          recovery: const ModelTransferRecovery(restartsFromZero: true),
        );
        await _persist();
        _render();
        return;
      }
      await _transport.cancel(id);
      await _transport.forget(id);
      await _storage.removeOwnedModel();
      _record = _record.copyWith(clearTask: true, receivedBytes: 0);
    } else if (id != null) {
      await _cancelOwnedTask();
      await _storage.removeOwnedModel();
      _record = _record.copyWith(clearTask: true, receivedBytes: 0);
    }
    _freeBytes = await _storage.availableBytes();
    if (pending && generation != _generation) return;
    if (_freeBytes < _neededBytes) {
      _record = _record.copyWith(phase: ModelDeliveryPhase.insufficientSpace);
      await _persist();
      _render();
      return;
    }
    await _storage.prepare();
    if (pending && generation != _generation) return;
    id = _newTaskId();
    _record = _record.copyWith(
      taskId: id,
      receivedBytes: 0,
      phase: ModelDeliveryPhase.active,
    );
    await _persist();
    if (pending && generation != _generation) {
      _record = _record.copyWith(
        clearTask: true,
        phase: ModelDeliveryPhase.awaitingConnection,
      );
      await _persist();
      return;
    }
    _queuedRequiresWifi = !_record.allowMobileData;
    _render();
    if (!await _transport.enqueue(
      taskId: id,
      manifest: manifest,
      requiresWiFi: !_record.allowMobileData,
    )) {
      throw StateError('Translator task was not accepted');
    }
    _runNotice(_clearBackgroundStatus);
  }

  Future<bool> _deferOfflineStart() async {
    if (_record.taskId != null ||
        _connection != ModelDeliveryConnection.offline) {
      return false;
    }
    if (_record.phase != ModelDeliveryPhase.awaitingConnection) {
      _record = _record.copyWith(phase: ModelDeliveryPhase.awaitingConnection);
      await _persist();
    }
    _render();
    return true;
  }

  @override
  Future<void> pause() {
    _generation++;
    _cancelRecoveryTimer();
    return _perform(() async {
      final previousPhase = _record.phase;
      if (_record.phase == ModelDeliveryPhase.verifying ||
          _record.phase == ModelDeliveryPhase.waitingToRetry ||
          _record.phase == ModelDeliveryPhase.waitingForConnection ||
          _record.phase == ModelDeliveryPhase.serverRetry &&
              !_connectionEligible) {
        _record = _record.copyWith(phase: ModelDeliveryPhase.userPaused);
      } else if (_record.phase == ModelDeliveryPhase.active ||
          _record.phase == ModelDeliveryPhase.policyPauseRequested) {
        final id = _record.taskId;
        if (id == null) return;
        _record = _record.copyWith(phase: ModelDeliveryPhase.pauseRequested);
        await _persist();
        if (!await _transport.pause(id)) {
          _record = _record.copyWith(phase: ModelDeliveryPhase.active);
        }
      } else {
        return;
      }
      await _persist();
      _render();
      await _publishStablePause(previousPhase);
    });
  }

  @override
  Future<void> remove() {
    _generation++;
    _cancelRecoveryTimer();
    _verifiedPath = null;
    return _perform(_remove);
  }

  Future<void> _remove() async {
    _record = _record.copyWith(phase: ModelDeliveryPhase.removing);
    await _persist();
    await _cancelOwnedTask();
    await _storage.removeOwnedModel();
    _record = ModelDeliveryRecord(
      manifest: _record.manifest,
      allowMobileData: _record.allowMobileData,
    );
    _freeBytes = await _storage.availableBytes();
    await _persist();
    _render();
    _runNotice(_clearBackgroundStatus);
  }

  Future<void> _cancelOwnedTask() async {
    final id = _record.taskId;
    if (id != null) {
      await _transport.cancel(id);
      await _transport.forget(id);
    }
  }

  void _receiveEvent(ModelTransferEvent event) => unawaited(
    _perform(() async {
      if (event.taskId != _record.taskId ||
          _record.phase == ModelDeliveryPhase.removing ||
          _record.phase == ModelDeliveryPhase.idle ||
          _record.phase == ModelDeliveryPhase.ready ||
          _record.phase == ModelDeliveryPhase.userPaused &&
              event.status == null ||
          _hasManagedRecovery) {
        return;
      }
      final previousPhase = _record.phase;
      if (event.status == ModelTransferStatus.running) {
        _queuedRequiresWifi = false;
      }
      if (event.receivedBytes case final bytes?) {
        final received = _clamp(bytes);
        if (received > _record.receivedBytes) _resetRecoveryDelay();
        _record = _record.copyWith(receivedBytes: received);
        _remaining = event.remaining;
      }
      switch (event.status) {
        case ModelTransferStatus.complete:
          if (_record.phase == ModelDeliveryPhase.userPaused ||
              _record.phase == ModelDeliveryPhase.pauseRequested) {
            _record = _record.copyWith(
              receivedBytes: _totalBytes,
              phase: ModelDeliveryPhase.userPaused,
            );
          } else if (_record.phase != ModelDeliveryPhase.failed) {
            _record = _record.copyWith(
              receivedBytes: _totalBytes,
              phase: ModelDeliveryPhase.verifying,
            );
            await _persist();
            _render();
            _beginVerification();
            return;
          }
        case ModelTransferStatus.paused:
          if (_record.phase == ModelDeliveryPhase.verifying) return;
          if (_record.phase == ModelDeliveryPhase.policyPauseRequested) {
            _record = _record.copyWith(phase: ModelDeliveryPhase.userPaused);
            await _persist();
            await _startOrResume();
          } else if (_record.phase != ModelDeliveryPhase.userPaused &&
              _record.phase != ModelDeliveryPhase.pauseRequested &&
              _connection == ModelDeliveryConnection.offline) {
            await _recoverFromFailure(ModelTransferFailure.connection);
          } else if (_shouldRecoverUnexpectedPause) {
            _record = _record.copyWith(
              phase: ModelDeliveryPhase.waitingToRetry,
            );
            _remaining = null;
          } else {
            _record = _record.copyWith(phase: ModelDeliveryPhase.userPaused);
          }
        case ModelTransferStatus.failed:
          if (_record.phase == ModelDeliveryPhase.verifying) return;
          if (_record.phase == ModelDeliveryPhase.userPaused ||
              _record.phase == ModelDeliveryPhase.pauseRequested) {
            _record = _record.copyWith(phase: ModelDeliveryPhase.userPaused);
          } else {
            await _recoverFromFailure(event.failure);
          }
        case ModelTransferStatus.canceled:
          _record = _record.copyWith(phase: ModelDeliveryPhase.failed);
        case ModelTransferStatus.running ||
            ModelTransferStatus.enqueued ||
            ModelTransferStatus.waitingToRetry:
          if (_record.phase != ModelDeliveryPhase.userPaused &&
              _record.phase != ModelDeliveryPhase.pauseRequested &&
              _record.phase != ModelDeliveryPhase.policyPauseRequested &&
              _record.phase != ModelDeliveryPhase.failed &&
              _record.phase != ModelDeliveryPhase.ready &&
              _record.phase != ModelDeliveryPhase.verifying) {
            _record = _record.copyWith(phase: ModelDeliveryPhase.active);
          }
        case null:
          if (event.receivedBytes != null) await _persist();
          _render();
          return;
      }
      await _persist();
      _render();
      await _publishStablePause(previousPhase);
    }),
  );

  Future<void> _publishStablePause(ModelDeliveryPhase previousPhase) async {
    final publish = _publishBackgroundStatus;
    if (publish == null || _record.phase == previousPhase) return;
    final stable = switch (_record.phase) {
      ModelDeliveryPhase.userPaused ||
      ModelDeliveryPhase.transferNeedsSpace ||
      ModelDeliveryPhase.storageWriteFailed ||
      ModelDeliveryPhase.restartRequired => true,
      ModelDeliveryPhase.waitingForConnection => !_connectionEligible,
      ModelDeliveryPhase.serverRetry => _record.recovery?.retryAt == null,
      _ => false,
    };
    if (!stable) return;
    var status = _state.value;
    if (status case final ModelPaused paused) {
      final id = _record.taskId;
      final generation = _generation;
      int? confirmed;
      try {
        if (id != null) {
          confirmed = (await _transport.checkpoint(id))?.retainedBytes;
        }
      } on Object {
        // The pause itself has already committed.
      }
      if (_disposed || generation != _generation || _state.value != status) {
        return;
      }
      status = ModelPaused(
        receivedBytes: paused.receivedBytes,
        totalBytes: paused.totalBytes,
        confirmedReceivedBytes: confirmed,
      );
    }
    _runNotice(() => publish(status));
  }

  void _runNotice(Future<void> Function()? action) {
    if (action == null || _disposed) return;
    unawaited(Future<void>.sync(action).catchError((Object _) {}));
  }

  Future<void> _recoverFromFailure(ModelTransferFailure? failure) async {
    final id = _record.taskId;
    if (id == null || _record.manifest == null) return;
    var checkpoint = failure == ModelTransferFailure.invalidCheckpoint
        ? null
        : await _transport.checkpoint(id);
    if (checkpoint?.retainedBytes case final int bytes
        when bytes >= _totalBytes) {
      checkpoint = null;
    }
    final losingProgress =
        checkpoint == null &&
            (_record.receivedBytes > 0 ||
                _record.recovery?.checkpoint != null) ||
        failure == ModelTransferFailure.invalidCheckpoint;
    var attempts = _record.recovery?.serverAttempts ?? 0;
    DateTime? retryAt;
    if (failure == ModelTransferFailure.server &&
        !losingProgress &&
        attempts < _serverRetrySeconds.length) {
      retryAt = clock.now().toUtc().add(
        Duration(seconds: _serverRetrySeconds[attempts]),
      );
      attempts++;
    }
    _remaining = null;
    _record = _record.copyWith(
      receivedBytes: checkpoint?.retainedBytes,
      recovery: ModelTransferRecovery(
        checkpoint: checkpoint,
        restartsFromZero: losingProgress,
        serverAttempts: attempts,
        retryAt: retryAt,
      ),
    );
    if (failure == ModelTransferFailure.storageFull ||
        failure == ModelTransferFailure.storageWrite) {
      _freeBytes = await _storage.availableBytes();
    }
    final required = _neededBytesForRecovery;
    final phase = switch (failure) {
      ModelTransferFailure.connection =>
        losingProgress
            ? ModelDeliveryPhase.restartRequired
            : ModelDeliveryPhase.waitingForConnection,
      ModelTransferFailure.server => ModelDeliveryPhase.serverRetry,
      ModelTransferFailure.storageFull => ModelDeliveryPhase.transferNeedsSpace,
      ModelTransferFailure.storageWrite =>
        required != null && required > _freeBytes
            ? ModelDeliveryPhase.transferNeedsSpace
            : ModelDeliveryPhase.storageWriteFailed,
      ModelTransferFailure.invalidCheckpoint =>
        ModelDeliveryPhase.restartRequired,
      null =>
        losingProgress
            ? ModelDeliveryPhase.restartRequired
            : ModelDeliveryPhase.failed,
    };
    _record = _record.copyWith(phase: phase);
  }

  Future<void> _restoreManagedCheckpoint() async {
    final id = _record.taskId;
    final recovery = _record.recovery;
    if (id == null || recovery?.checkpoint == null) return;
    final checkpoint = await _transport.checkpoint(id);
    if (checkpoint != null &&
        checkpoint.retainedBytes == recovery!.checkpoint?.retainedBytes) {
      return;
    }
    _record = _record.copyWith(
      phase:
          checkpoint == null &&
              (_record.phase == ModelDeliveryPhase.waitingForConnection ||
                  _record.phase == ModelDeliveryPhase.failed)
          ? ModelDeliveryPhase.restartRequired
          : _record.phase,
      receivedBytes: checkpoint?.retainedBytes,
      recovery: ModelTransferRecovery(
        checkpoint: checkpoint,
        restartsFromZero: checkpoint == null,
        serverAttempts: recovery!.serverAttempts,
        retryAt: checkpoint == null ? null : recovery.retryAt,
      ),
    );
    await _persist();
  }

  void _receiveConnection(ModelDeliveryConnection connection) {
    final generation = _generation;
    unawaited(
      _perform(() async {
        final wasEligible = _connectionEligible;
        final wifiReturned =
            connection == ModelDeliveryConnection.wifi && !_onWifi;
        _connection = connection;
        if (generation == _generation && _canStartPending) {
          await _startOrResume();
          return;
        }
        final returned = wifiReturned || !wasEligible && _connectionEligible;
        if (returned && _record.phase != ModelDeliveryPhase.serverRetry) {
          _resetRecoveryDelay();
          final id = _record.taskId;
          if (id != null && _canRecoverTransfer) {
            await _recoverTransfer(id, _generation);
            return;
          }
        }
        _render();
      }),
    );
  }

  bool get _shouldRecoverUnexpectedPause =>
      _transport.canRecoverUnexpectedPauses &&
      _record.manifest != null &&
      (_record.phase == ModelDeliveryPhase.active ||
          _record.phase == ModelDeliveryPhase.resumeRequested ||
          _record.phase == ModelDeliveryPhase.waitingToRetry);

  bool get _canRecoverTransfer =>
      !_disposed &&
      _canRun &&
      _record.manifest != null &&
      _connectionEligible &&
      switch (_record.phase) {
        ModelDeliveryPhase.waitingToRetry =>
          _transport.canRecoverUnexpectedPauses,
        ModelDeliveryPhase.waitingForConnection => true,
        ModelDeliveryPhase.serverRetry => _record.recovery?.retryAt != null,
        _ => false,
      };

  bool get _hasManagedRecovery => switch (_record.phase) {
    ModelDeliveryPhase.waitingForConnection ||
    ModelDeliveryPhase.serverRetry ||
    ModelDeliveryPhase.transferNeedsSpace ||
    ModelDeliveryPhase.storageWriteFailed ||
    ModelDeliveryPhase.restartRequired => true,
    ModelDeliveryPhase.failed => _record.recovery?.checkpoint != null,
    _ => false,
  };

  void _cancelRecoveryTimer() {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
  }

  void _resetRecoveryDelay() {
    _recoveryDelaySeconds = 5;
    _cancelRecoveryTimer();
  }

  void _updateRecoveryTimer() {
    if (!_canRecoverTransfer) {
      _cancelRecoveryTimer();
      return;
    }
    final id = _record.taskId;
    if (_recoveryTimer != null || id == null) return;
    final generation = _generation;
    final deadline = _record.phase == ModelDeliveryPhase.serverRetry
        ? _record.recovery?.retryAt
        : null;
    final delay =
        deadline?.difference(clock.now()) ??
        Duration(seconds: _recoveryDelaySeconds);
    _recoveryTimer = Timer(delay, () {
      _recoveryTimer = null;
      unawaited(_perform(() => _recoverTransfer(id, generation)));
    });
  }

  Future<void> _recoverTransfer(String id, int generation) async {
    if (generation != _generation ||
        id != _record.taskId ||
        !_canRecoverTransfer) {
      return;
    }
    _recoveryDelaySeconds = min(600, _recoveryDelaySeconds * 3);
    await _startOrResume(recoveryGeneration: generation);
  }

  void _beginVerification() {
    final manifest = _record.manifest;
    final id = _record.taskId;
    if (manifest == null || id == null || !_canRun) return;
    final generation = _generation;
    final verification = (taskId: id, generation: generation);
    if (_verification == verification) return;
    _verification = verification;
    unawaited(() async {
      var valid = false;
      var damaged = false;
      ModelDeliveryFileIdentity? verifiedIdentity;
      try {
        await _storage.prepare();
        final before = await _storage.modelIdentity();
        if (before != null) {
          valid =
              (_record.verification?.matches(manifest, before) ?? false) ||
              await _storage.verify(manifest);
          final after = await _storage.modelIdentity();
          final stable = before.sizeBytes == manifest.bytes && before == after;
          damaged = stable && !valid;
          valid = stable && valid;
          if (valid) verifiedIdentity = after;
        }
      } on Object {
        valid = false;
      }
      final verified = verifiedIdentity;
      await _queue(() async {
        if (_verification == verification) _verification = null;
        if (_disposed ||
            generation != _generation ||
            id != _record.taskId ||
            _record.phase != ModelDeliveryPhase.verifying ||
            !_canRun) {
          return;
        }
        if (valid && verified != null) {
          _verifiedPath = verified.canonicalPath;
          _record = _record.copyWith(
            phase: ModelDeliveryPhase.ready,
            integrityRepairAttempted: false,
            verification: ModelDeliveryVerification(
              expectedSha256: manifest.sha256,
              identity: verified,
            ),
          );
        } else if (damaged && !_record.integrityRepairAttempted) {
          _record = _record.copyWith(
            phase: ModelDeliveryPhase.integrityRepairPending,
            integrityRepairAttempted: true,
            clearVerification: true,
          );
          await _persist();
          _render();
          await _continueIntegrityRepair();
          return;
        } else {
          await _storage.removeOwnedModel();
          await _transport.forget(id);
          _record = _record.copyWith(
            clearTask: true,
            receivedBytes: 0,
            phase: damaged
                ? ModelDeliveryPhase.integrityFailed
                : ModelDeliveryPhase.idle,
          );
          _freeBytes = await _storage.availableBytes();
        }
        await _persist();
        _render();
        if (_state.value case final ModelReady ready
            when id != _previouslyReadyTaskId) {
          final publish = _publishBackgroundStatus;
          if (publish != null) _runNotice(() => publish(ready));
        }
      }).catchError((Object _) {
        if (!_disposed && generation == _generation) {
          _record = _record.copyWith(phase: ModelDeliveryPhase.failed);
          _render();
        }
      });
    }());
  }

  Future<void> _continueIntegrityRepair() async {
    if (!_canRun) return;
    final id = _record.taskId;
    if (id != null) {
      await _storage.removeOwnedModel();
      await _transport.forget(id);
      _record = _record.copyWith(clearTask: true, receivedBytes: 0);
      await _persist();
    }
    await _startOrResume(useCachedManifest: true);
  }

  int get _totalBytes => _record.manifest?.bytes ?? gemmaModelBytes;
  int get _neededBytes =>
      max(0, _totalBytes - _record.receivedBytes) + _spaceReserveBytes;
  int? get _neededBytesForRecovery {
    final checkpoint = _record.recovery?.checkpoint;
    if (checkpoint != null && checkpoint.retainedBytes == null) return null;
    return max(0, _totalBytes - (checkpoint?.retainedBytes ?? 0)) +
        _spaceReserveBytes;
  }

  int _clamp(int bytes) => bytes.clamp(0, _totalBytes);
  bool get _onWifi => _connection == ModelDeliveryConnection.wifi;
  bool get _waitingForWifi =>
      (!_record.allowMobileData || _queuedRequiresWifi) && !_onWifi;
  bool get _connectionEligible =>
      _onWifi ||
      _record.allowMobileData && _connection == ModelDeliveryConnection.other;
  bool get _canStartPending =>
      _canRun &&
      _record.phase == ModelDeliveryPhase.awaitingConnection &&
      _connectionEligible;
  bool get _eligibleDevice => _supported.value && _safety.blockedReason == null;
  bool get _requiresUpdate => (_record.manifest?.minAppBuild ?? 0) > _build;
  bool get _canRun => _eligibleDevice && !_requiresUpdate;

  void _render() {
    if (_disposed) return;
    _updateRecoveryTimer();
    if (!_eligibleDevice) {
      _state.value = const ModelUnsupported();
      return;
    }
    if (_requiresUpdate) {
      _state.value = const ModelUpdateRequired();
      return;
    }
    final recovery = _record.recovery;
    final kept = recovery?.checkpoint?.retainedBytes;
    final required = _neededBytesForRecovery;
    _state.value = switch (_record.phase) {
      ModelDeliveryPhase.idle =>
        _freeBytes < _neededBytes
            ? ModelNotEnoughSpace(
                totalBytes: _totalBytes,
                neededBytes: _neededBytes,
                freeBytes: _freeBytes,
              )
            : ModelNotDownloaded(
                totalBytes: _totalBytes,
                freeBytes: _freeBytes,
                onWifi: _onWifi,
              ),
      ModelDeliveryPhase.awaitingConnection => ModelAwaitingConnection(
        allowMobileData: _record.allowMobileData,
      ),
      ModelDeliveryPhase.insufficientSpace => ModelNotEnoughSpace(
        totalBytes: _totalBytes,
        neededBytes: _neededBytes,
        freeBytes: _freeBytes,
      ),
      ModelDeliveryPhase.userPaused => ModelPaused(
        receivedBytes: _record.receivedBytes,
        totalBytes: _totalBytes,
      ),
      ModelDeliveryPhase.resumeRequested =>
        _waitingForWifi
            ? ModelWaitingForWifi(
                receivedBytes: _record.receivedBytes,
                totalBytes: _totalBytes,
                canUseMobileData: !_record.allowMobileData,
              )
            : ModelPaused(
                receivedBytes: _record.receivedBytes,
                totalBytes: _totalBytes,
              ),
      ModelDeliveryPhase.waitingForConnection || ModelDeliveryPhase.serverRetry
          when _connection == ModelDeliveryConnection.other &&
              !_record.allowMobileData &&
              !(recovery?.restartsFromZero ?? false) =>
        ModelWaitingForWifi(receivedBytes: kept ?? 0, totalBytes: _totalBytes),
      ModelDeliveryPhase.waitingForConnection => ModelWaitingForConnection(
        retainedBytes: kept,
        totalBytes: _totalBytes,
      ),
      ModelDeliveryPhase.serverRetry
          when !_connectionEligible && recovery?.retryAt != null =>
        ModelWaitingForConnection(retainedBytes: kept, totalBytes: _totalBytes),
      ModelDeliveryPhase.serverRetry => ModelServerRetry(
        retainedBytes: kept,
        totalBytes: _totalBytes,
        retryAt: recovery?.retryAt,
        restartsFromZero: recovery?.restartsFromZero ?? false,
      ),
      ModelDeliveryPhase.transferNeedsSpace => ModelDownloadNeedsSpace(
        retainedBytes: kept,
        totalBytes: _totalBytes,
        additionalBytes: required != null && required > _freeBytes
            ? required - _freeBytes
            : null,
        restartsFromZero: recovery?.restartsFromZero ?? false,
      ),
      ModelDeliveryPhase.storageWriteFailed => ModelStorageWriteFailed(
        restartsFromZero: recovery?.restartsFromZero ?? false,
      ),
      ModelDeliveryPhase.restartRequired => const ModelRestartRequired(),
      ModelDeliveryPhase.verifying => const ModelChecking(),
      ModelDeliveryPhase.integrityRepairPending => const ModelIntegrityRepair(
        needsManualRetry: false,
      ),
      ModelDeliveryPhase.integrityFailed => const ModelIntegrityRepair(
        needsManualRetry: true,
      ),
      ModelDeliveryPhase.failed => const ModelFailed(),
      ModelDeliveryPhase.ready => ModelReady(sizeBytes: _totalBytes),
      ModelDeliveryPhase.removing => const ModelFailed(),
      _ =>
        _waitingForWifi
            ? ModelWaitingForWifi(
                receivedBytes: _record.receivedBytes,
                totalBytes: _totalBytes,
                canUseMobileData: !_record.allowMobileData,
              )
            : _record.integrityRepairAttempted
            ? ModelIntegrityRepair(
                needsManualRetry: false,
                canPause: _record.phase == ModelDeliveryPhase.active,
              )
            : ModelDownloading(
                receivedBytes: _record.receivedBytes,
                totalBytes: _totalBytes,
                remaining: _remaining,
              ),
    };
  }

  Future<void> _persist() => _storage.saveRecord(_record);

  Future<void> _perform(Future<void> Function() action) async {
    if (_disposed) return;
    await initialize();
    return _queue(() async {
      if (_disposed) return;
      try {
        await action();
      } on Object {
        if (_record.phase != ModelDeliveryPhase.removing) {
          _record = _record.copyWith(phase: ModelDeliveryPhase.failed);
        }
        try {
          await _persist();
        } on Object {
          // A storage failure must still leave the UI out of Ready.
        }
        _verifiedPath = null;
        _render();
      }
    });
  }

  Future<void> _queue(Future<void> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> dispose() async {
    _disposed = true;
    _cancelRecoveryTimer();
    _generation++;
    _verifiedPath = null;
    await _transferSubscription.cancel();
    await _connectionSubscription.cancel();
    await _tail;
    await _safetyTail;
    await _transport.dispose();
    _state.dispose();
    _supported.dispose();
    _allowMobileData.dispose();
    _memoryNoticePending.dispose();
  }
}
