import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/features/translate_preview/gemma_preview_prompts.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';

const modelDeliveryManifestUrl =
    'https://updates.mknoon.xyz/models/gemma-translate.json';
const modelDeliveryGroup = 'mknoon_gemma_translation';
const modelDeliveryDirectory = 'gemma_translation';
const modelDeliverySpaceReserve = 2800000000 - gemmaModelBytes;

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
  insufficientSpace,
  active,
  resumeRequested,
  pauseRequested,
  userPaused,
  policyPauseRequested,
  verifying,
  failed,
  ready,
  removing,
}

final class ModelDeliveryRecord {
  const ModelDeliveryRecord({
    this.manifest,
    this.taskId,
    this.receivedBytes = 0,
    this.phase = ModelDeliveryPhase.idle,
    this.allowMobileData = false,
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
    );
  }

  final ModelDeliveryManifest? manifest;
  final String? taskId;
  final int receivedBytes;
  final ModelDeliveryPhase phase;
  final bool allowMobileData;

  ModelDeliveryRecord copyWith({
    ModelDeliveryManifest? manifest,
    String? taskId,
    bool clearTask = false,
    int? receivedBytes,
    ModelDeliveryPhase? phase,
    bool? allowMobileData,
  }) => ModelDeliveryRecord(
    manifest: manifest ?? this.manifest,
    taskId: clearTask ? null : taskId ?? this.taskId,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    phase: phase ?? this.phase,
    allowMobileData: allowMobileData ?? this.allowMobileData,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'manifest': manifest?.toJson(),
    'taskId': taskId,
    'receivedBytes': receivedBytes,
    'phase': phase.name,
    'allowMobileData': allowMobileData,
  };
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

final class ModelTransferEvent {
  const ModelTransferEvent({
    required this.taskId,
    this.status,
    this.receivedBytes,
    this.remaining,
  });

  final String taskId;
  final ModelTransferStatus? status;
  final int? receivedBytes;
  final Duration? remaining;
}

final class ModelTransferSnapshot {
  const ModelTransferSnapshot({
    required this.taskId,
    required this.status,
    required this.receivedBytes,
  });

  final String taskId;
  final ModelTransferStatus status;
  final int receivedBytes;
}

abstract interface class ModelDeliveryStorage {
  Future<ModelDeliveryRecord?> readRecord();
  Future<void> saveRecord(ModelDeliveryRecord record);
  Future<void> prepare();
  Future<int> availableBytes();
  Future<int?> modelLength();
  Future<bool> verify(ModelDeliveryManifest manifest);
  Future<String> modelPath();
  Future<void> removeOwnedModel();
}

abstract interface class ModelDeliveryNetwork {
  Future<Map<String, Object?>> fetchManifest();
  Future<bool> checkWifi();
  Stream<bool> get wifiChanges;
}

abstract interface class ModelDeliveryTransport {
  Stream<ModelTransferEvent> get events;
  Future<void> initialize(String? ownedTaskId);
  Future<ModelTransferSnapshot?> restore(String taskId);
  Future<bool> enqueue({
    required String taskId,
    required ModelDeliveryManifest manifest,
    required bool requiresWiFi,
  });
  Future<bool> pause(String taskId);
  Future<bool> resume(String taskId, {required bool requiresWiFi});
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
    int spaceReserveBytes = modelDeliverySpaceReserve,
    String Function()? newTaskId,
  }) : _storage = storage,
       _network = network,
       _transport = transport,
       _appBuild = appBuild,
       _supported = supported,
       _spaceReserveBytes = spaceReserveBytes,
       _newTaskId = newTaskId ?? _makeTaskId {
    _transferSubscription = _transport.events.listen(_receiveEvent);
    _wifiSubscription = _network.wifiChanges.listen(_receiveWifi);
  }

  final ModelDeliveryStorage _storage;
  final ModelDeliveryNetwork _network;
  final ModelDeliveryTransport _transport;
  final Future<int> Function() _appBuild;
  final int _spaceReserveBytes;
  final String Function() _newTaskId;
  final _state = ValueNotifier<ModelDeliveryState>(const ModelUnsupported());
  final _allowMobileData = ValueNotifier(false);
  late final StreamSubscription<ModelTransferEvent> _transferSubscription;
  late final StreamSubscription<bool> _wifiSubscription;
  Future<void>? _initialization;
  Future<void> _tail = Future.value();
  ModelDeliveryRecord _record = const ModelDeliveryRecord();
  bool _supported;
  bool _onWifi = false;
  bool _disposed = false;
  int _build = 0;
  int _freeBytes = 0;
  int _generation = 0;
  String? _verifiedPath;
  Duration? _remaining;
  ({String taskId, int generation})? _verification;

  @override
  ValueListenable<ModelDeliveryState> get state => _state;

  @override
  ValueListenable<bool> get allowMobileData => _allowMobileData;

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
    try {
      _record = await _storage.readRecord() ?? const ModelDeliveryRecord();
      _allowMobileData.value = _record.allowMobileData;
      _build = await _appBuild();
      _onWifi = await _network.checkWifi();
      await _storage.prepare();
      _freeBytes = await _storage.availableBytes();
      await _transport.initialize(_record.taskId);
      if (_record.phase == ModelDeliveryPhase.removing) {
        await _remove();
        return;
      }
      final id = _record.taskId;
      if (id != null) {
        final recovered = await _transport.restore(id);
        if (recovered != null) {
          _record = _record.copyWith(
            receivedBytes: _clamp(recovered.receivedBytes),
          );
          switch (recovered.status) {
            case ModelTransferStatus.complete:
              _record = _record.copyWith(phase: ModelDeliveryPhase.verifying);
            case ModelTransferStatus.paused:
              _record = _record.copyWith(phase: ModelDeliveryPhase.userPaused);
            case ModelTransferStatus.failed || ModelTransferStatus.canceled:
              _record = _record.copyWith(phase: ModelDeliveryPhase.failed);
            case ModelTransferStatus.enqueued ||
                ModelTransferStatus.running ||
                ModelTransferStatus.waitingToRetry:
              if (_record.phase == ModelDeliveryPhase.pauseRequested ||
                  _record.phase == ModelDeliveryPhase.userPaused ||
                  _record.phase == ModelDeliveryPhase.policyPauseRequested) {
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
      }
    } on Object {
      _record = _record.copyWith(phase: ModelDeliveryPhase.failed);
      _render();
    }
  }

  void setCapability(bool supported) {
    if (_disposed) return;
    _supported = supported;
    if (!supported) {
      _generation++;
      _verifiedPath = null;
      _state.value = const ModelUnsupported();
    }
    unawaited(
      _perform(() async {
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
        }
      }),
    );
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
        final onWifi = await _network.checkWifi();
        final freeBytes = await _storage.availableBytes();
        if (_disposed) return;
        _onWifi = onWifi;
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
            _record.phase == ModelDeliveryPhase.userPaused) {
          _render();
        }
      });
    } on Object {
      // An optional admission recheck keeps the last measured offer on failure.
    }
  }

  @override
  Future<void> setAllowMobileData(bool allow) =>
      _perform(() => _setAllowMobileData(allow));

  Future<void> _setAllowMobileData(bool allow) async {
    if (_record.allowMobileData == allow) return;
    _allowMobileData.value = allow;
    _record = _record.copyWith(allowMobileData: allow);
    await _persist();
    final id = _record.taskId;
    if (id != null &&
        (_record.phase == ModelDeliveryPhase.active ||
            _record.phase == ModelDeliveryPhase.resumeRequested)) {
      _record = _record.copyWith(
        phase: ModelDeliveryPhase.policyPauseRequested,
      );
      await _persist();
      if (!await _transport.pause(id)) {
        await _transport.cancel(id);
        _record = _record.copyWith(phase: ModelDeliveryPhase.failed);
        await _persist();
      }
    }
    _render();
  }

  @override
  Future<void> start({required bool allowMobileData}) {
    _generation++;
    return _perform(() async {
      await _setAllowMobileData(allowMobileData);
      await _startOrResume();
    });
  }

  @override
  Future<void> resume() {
    _generation++;
    return _perform(_startOrResume);
  }

  @override
  Future<void> retry() {
    _generation++;
    return _perform(() async {
      if (_record.phase == ModelDeliveryPhase.removing) {
        await _remove();
      } else {
        await _startOrResume();
      }
    });
  }

  Future<void> _startOrResume() async {
    if (!_supported || _record.phase == ModelDeliveryPhase.removing) return;
    if (_record.phase == ModelDeliveryPhase.ready ||
        _record.phase == ModelDeliveryPhase.active ||
        _record.phase == ModelDeliveryPhase.resumeRequested ||
        _record.phase == ModelDeliveryPhase.pauseRequested ||
        _record.phase == ModelDeliveryPhase.policyPauseRequested) {
      return;
    }
    _verifiedPath = null;
    Map<String, Object?> raw;
    try {
      raw = await _network.fetchManifest();
    } on Object {
      final cached = _record.manifest;
      if (cached == null) rethrow;
      raw = cached.toJson();
    }
    final manifest = ModelDeliveryManifest.fromJson(raw);
    final oldManifest = _record.manifest;
    final sameFile =
        oldManifest?.sha256 == manifest.sha256 &&
        oldManifest?.bytes == manifest.bytes &&
        oldManifest?.url == manifest.url;
    if (!sameFile && _record.taskId != null) {
      await _cancelOwnedTask();
      await _storage.removeOwnedModel();
      _record = _record.copyWith(clearTask: true, receivedBytes: 0);
    }
    _record = _record.copyWith(manifest: manifest);
    await _persist();
    if (!_canRun) {
      _render();
      return;
    }
    await _storage.prepare();
    _onWifi = await _network.checkWifi();
    _freeBytes = await _storage.availableBytes();
    if (await _storage.modelLength() == manifest.bytes) {
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
    if (_freeBytes < _neededBytes) {
      _record = _record.copyWith(phase: ModelDeliveryPhase.insufficientSpace);
      await _persist();
      _render();
      return;
    }
    var id = _record.taskId;
    if (id != null && _record.phase != ModelDeliveryPhase.failed) {
      _record = _record.copyWith(phase: ModelDeliveryPhase.resumeRequested);
      await _persist();
      if (await _transport.resume(id, requiresWiFi: !_record.allowMobileData)) {
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
    if (_freeBytes < _neededBytes) {
      _record = _record.copyWith(phase: ModelDeliveryPhase.insufficientSpace);
      await _persist();
      _render();
      return;
    }
    id = _newTaskId();
    _record = _record.copyWith(
      taskId: id,
      receivedBytes: 0,
      phase: ModelDeliveryPhase.active,
    );
    await _persist();
    _render();
    await _storage.prepare();
    if (!await _transport.enqueue(
      taskId: id,
      manifest: manifest,
      requiresWiFi: !_record.allowMobileData,
    )) {
      throw StateError('Translator task was not accepted');
    }
  }

  @override
  Future<void> pause() {
    _generation++;
    return _perform(() async {
      if (_record.phase == ModelDeliveryPhase.verifying) {
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
    });
  }

  @override
  Future<void> remove() {
    _generation++;
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
          _record.phase == ModelDeliveryPhase.ready) {
        return;
      }
      if (event.receivedBytes case final bytes?) {
        _record = _record.copyWith(receivedBytes: _clamp(bytes));
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
          } else {
            _record = _record.copyWith(phase: ModelDeliveryPhase.userPaused);
          }
        case ModelTransferStatus.failed || ModelTransferStatus.canceled:
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
          _render();
          return;
      }
      await _persist();
      _render();
    }),
  );

  void _receiveWifi(bool onWifi) => unawaited(
    _perform(() async {
      _onWifi = onWifi;
      _render();
    }),
  );

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
      String? path;
      try {
        await _storage.prepare();
        valid = await _storage.verify(manifest);
        if (valid) path = await _storage.modelPath();
      } on Object {
        valid = false;
      }
      await _queue(() async {
        if (_verification == verification) _verification = null;
        if (_disposed ||
            generation != _generation ||
            id != _record.taskId ||
            _record.phase != ModelDeliveryPhase.verifying ||
            !_canRun) {
          return;
        }
        if (valid && path != null) {
          _verifiedPath = path;
          _record = _record.copyWith(phase: ModelDeliveryPhase.ready);
        } else {
          await _storage.removeOwnedModel();
          await _transport.forget(id);
          _record = _record.copyWith(
            clearTask: true,
            receivedBytes: 0,
            phase: ModelDeliveryPhase.failed,
          );
        }
        await _persist();
        _render();
      }).catchError((Object _) {
        if (!_disposed && generation == _generation) {
          _record = _record.copyWith(phase: ModelDeliveryPhase.failed);
          _render();
        }
      });
    }());
  }

  int get _totalBytes => _record.manifest?.bytes ?? gemmaModelBytes;
  int get _neededBytes =>
      max(0, _totalBytes - _record.receivedBytes) + _spaceReserveBytes;
  int _clamp(int bytes) => bytes.clamp(0, _totalBytes);
  bool get _canRun =>
      _supported && (_record.manifest?.minAppBuild ?? 0) <= _build;

  void _render() {
    if (_disposed) return;
    if (!_canRun) {
      _state.value = const ModelUnsupported();
      return;
    }
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
        !_record.allowMobileData && !_onWifi
            ? ModelWaitingForWifi(
                receivedBytes: _record.receivedBytes,
                totalBytes: _totalBytes,
              )
            : ModelPaused(
                receivedBytes: _record.receivedBytes,
                totalBytes: _totalBytes,
              ),
      ModelDeliveryPhase.verifying => ModelDownloading(
        receivedBytes: _totalBytes,
        totalBytes: _totalBytes,
      ),
      ModelDeliveryPhase.failed => const ModelFailed(),
      ModelDeliveryPhase.ready => ModelReady(sizeBytes: _totalBytes),
      ModelDeliveryPhase.removing => const ModelFailed(),
      _ =>
        !_record.allowMobileData && !_onWifi
            ? ModelWaitingForWifi(
                receivedBytes: _record.receivedBytes,
                totalBytes: _totalBytes,
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
    _generation++;
    _verifiedPath = null;
    await _transferSubscription.cancel();
    await _wifiSubscription.cancel();
    await _tail;
    await _transport.dispose();
    _state.dispose();
    _allowMobileData.dispose();
  }
}
