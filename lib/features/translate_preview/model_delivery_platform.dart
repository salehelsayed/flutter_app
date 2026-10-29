import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:background_downloader/background_downloader.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/device/disk_space.dart';
import 'package:flutter_app/features/translate_preview/gemma_preview_prompts.dart';
import 'package:flutter_app/features/translate_preview/gemma_preview_service.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_core.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

PersistentModelDeliveryController createProductionModelDeliveryController() {
  final service = GemmaPreviewService.instance;
  final controller = PersistentModelDeliveryController(
    storage: AppSupportModelDeliveryStorage(
      removeModel: service.removeDownloadedModel,
    ),
    network: HttpModelDeliveryNetwork(),
    transport: BackgroundModelDeliveryTransport(),
    appBuild: () async =>
        int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0,
  );
  service.setDownloadedModelPathResolver(controller.verifiedModelPath);
  unawaited(controller.initialize());
  return controller;
}

final class HttpModelDeliveryNetwork implements ModelDeliveryNetwork {
  HttpModelDeliveryNetwork({HttpClient? client, Connectivity? connectivity})
    : _client = client ?? HttpClient(),
      _connectivity = connectivity ?? Connectivity();

  final HttpClient _client;
  final Connectivity _connectivity;

  @override
  Future<Map<String, Object?>> fetchManifest() async {
    final request = await _client
        .getUrl(Uri.parse(modelDeliveryManifestUrl))
        .timeout(const Duration(seconds: 15));
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('Translator manifest request failed');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      if (bytes.length + chunk.length > 16384) {
        throw const FormatException('Translator manifest is too large');
      }
      bytes.add(chunk);
    }
    final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Translator manifest is not an object');
    }
    return Map<String, Object?>.from(decoded);
  }

  @override
  Future<bool> checkWifi() async => (await _connectivity.checkConnectivity())
      .contains(ConnectivityResult.wifi);

  @override
  Stream<bool> get wifiChanges => _connectivity.onConnectivityChanged
      .map((results) => results.contains(ConnectivityResult.wifi))
      .distinct();
}

final class AppSupportModelDeliveryStorage implements ModelDeliveryStorage {
  AppSupportModelDeliveryStorage({
    required Future<void> Function(Future<void> Function()) removeModel,
    Future<Directory> Function()? supportDirectory,
    DiskSpaceChannel? diskSpace,
    Future<SharedPreferences> Function()? preferences,
    Future<bool> Function(String)? excludeFromBackup,
  }) : _removeModel = removeModel,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _diskSpace = diskSpace ?? DiskSpaceChannel(),
       _preferences = preferences ?? SharedPreferences.getInstance,
       _excludeFromBackup = excludeFromBackup ?? _nativeExcludeFromBackup;

  static const recordKey = 'mknoon.translator.model_delivery.v1';
  static const _channel = MethodChannel('mknoon/gemma_preview');
  final Future<void> Function(Future<void> Function()) _removeModel;
  final Future<Directory> Function() _supportDirectory;
  final DiskSpaceChannel _diskSpace;
  final Future<SharedPreferences> Function() _preferences;
  final Future<bool> Function(String) _excludeFromBackup;

  static Future<bool> _nativeExcludeFromBackup(String path) async {
    if (!Platform.isIOS) return true;
    return await _channel.invokeMethod<bool>('excludeFromBackup', {
          'path': path,
        }) ==
        true;
  }

  Future<Directory> _directory() async =>
      Directory('${(await _supportDirectory()).path}/$modelDeliveryDirectory');

  @override
  Future<ModelDeliveryRecord?> readRecord() async {
    final text = (await _preferences()).getString(recordKey);
    if (text == null) return null;
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return null;
      return ModelDeliveryRecord.fromJson(Map<String, Object?>.from(json));
    } on Object {
      return null;
    }
  }

  @override
  Future<void> saveRecord(ModelDeliveryRecord record) async {
    final saved = await (await _preferences()).setString(
      recordKey,
      jsonEncode(record.toJson()),
    );
    if (!saved) throw FileSystemException('Translator state was not saved');
  }

  @override
  Future<void> prepare() async {
    final directory = await _directory();
    await directory.create(recursive: true);
    if (!await _excludeFromBackup(directory.path)) {
      throw FileSystemException(
        'Translator backup exclusion was not confirmed',
      );
    }
  }

  @override
  Future<int> availableBytes() async =>
      _diskSpace.getAvailableBytes((await _supportDirectory()).path);

  @override
  Future<String> modelPath() async =>
      '${(await _directory()).path}/$gemmaModelFileName';

  @override
  Future<int?> modelLength() async {
    final model = File(await modelPath());
    return await model.exists() ? model.length() : null;
  }

  @override
  Future<bool> verify(ModelDeliveryManifest manifest) async => compute(
    _verifyModelFile,
    (path: await modelPath(), bytes: manifest.bytes, sha256: manifest.sha256),
  );

  @override
  Future<void> removeOwnedModel() => _removeModel(() async {
    final directory = await _directory();
    if (await directory.exists()) await directory.delete(recursive: true);
  });
}

Future<bool> _verifyModelFile(
  ({String path, int bytes, String sha256}) expected,
) async {
  final model = File(expected.path);
  if (!await model.exists() || await model.length() != expected.bytes) {
    return false;
  }
  final digest = await sha256.bind(model.openRead()).first;
  return digest.toString() == expected.sha256;
}

final class BackgroundModelDeliveryTransport implements ModelDeliveryTransport {
  BackgroundModelDeliveryTransport({
    FileDownloader? downloader,
    bool? isIOS,
    Duration cancellationTimeout = const Duration(seconds: 30),
  }) : _downloader = downloader ?? FileDownloader(),
       _isIOS = isIOS ?? Platform.isIOS,
       _cancellationTimeout = cancellationTimeout;

  final FileDownloader _downloader;
  final bool _isIOS;
  final Duration _cancellationTimeout;
  final _events = StreamController<ModelTransferEvent>.broadcast(sync: true);
  final _tasks = <String, DownloadTask>{};
  final _sizes = <String, int>{};
  final _cancellations = <String, Completer<TaskStatus>>{};

  @override
  Stream<ModelTransferEvent> get events => _events.stream;

  bool _owns(Task task) =>
      task is DownloadTask &&
      task.group == modelDeliveryGroup &&
      task.baseDirectory == BaseDirectory.applicationSupport &&
      task.directory == modelDeliveryDirectory &&
      task.filename == gemmaModelFileName;

  @override
  Future<void> initialize(String? ownedTaskId) async {
    _downloader.registerCallbacks(
      group: modelDeliveryGroup,
      taskStatusCallback: _onStatus,
      taskProgressCallback: _onProgress,
    );
    _downloader.configureNotificationForGroup(
      modelDeliveryGroup,
      running: TaskNotification('mknoon', '{progress}%'),
      progressBar: true,
    );
    await _downloader.trackTasksInGroup(
      modelDeliveryGroup,
      markDownloadedComplete: false,
    );
    final records = await _downloader.database.allRecords(
      group: modelDeliveryGroup,
    );
    for (final record in records) {
      if (!_owns(record.task)) continue;
      _tasks[record.taskId] = record.task as DownloadTask;
      if (record.taskId != ownedTaskId) {
        await cancel(record.taskId);
        await forget(record.taskId);
      } else {
        _tasks[record.taskId] = record.task as DownloadTask;
        _sizes[record.taskId] = record.expectedFileSize > 0
            ? record.expectedFileSize
            : gemmaModelBytes;
      }
    }
    await _downloader.resumeFromBackground();
  }

  @override
  Future<ModelTransferSnapshot?> restore(String taskId) async {
    final record = await _downloader.database.recordForId(taskId);
    if (record == null || !_owns(record.task)) return null;
    _tasks[taskId] = record.task as DownloadTask;
    final total = record.expectedFileSize > 0
        ? record.expectedFileSize
        : _sizes[taskId] ?? gemmaModelBytes;
    return ModelTransferSnapshot(
      taskId: taskId,
      status: _status(record.status),
      receivedBytes: record.progress < 0
          ? 0
          : (record.progress.clamp(0, 1) * total).round(),
    );
  }

  @override
  Future<bool> enqueue({
    required String taskId,
    required ModelDeliveryManifest manifest,
    required bool requiresWiFi,
  }) async {
    final task = DownloadTask(
      taskId: taskId,
      url: manifest.url.toString(),
      filename: gemmaModelFileName,
      directory: modelDeliveryDirectory,
      baseDirectory: BaseDirectory.applicationSupport,
      group: modelDeliveryGroup,
      updates: Updates.statusAndProgress,
      requiresWiFi: requiresWiFi,
      allowPause: true,
      priority: 5,
      retries: 3,
      transferHints: {TransferHint.largeFile},
      headers: {'Accept-Encoding': 'identity'},
    );
    _tasks[taskId] = task;
    _sizes[taskId] = manifest.bytes;
    final accepted = await _downloader.enqueue(task);
    if (!accepted) {
      _tasks.remove(taskId);
      _sizes.remove(taskId);
    }
    return accepted;
  }

  Future<DownloadTask?> _task(String id) async {
    final remembered = _tasks[id];
    if (remembered != null) return remembered;
    final record = await _downloader.database.recordForId(id);
    if (record == null || !_owns(record.task)) return null;
    return _tasks[id] = record.task as DownloadTask;
  }

  @override
  Future<bool> pause(String taskId) async {
    final task = await _task(taskId);
    return task != null && await _downloader.pause(task);
  }

  @override
  Future<bool> resume(String taskId, {required bool requiresWiFi}) async {
    final task = await _task(taskId);
    if (task == null) return false;
    // iOS resumes from opaque resumeData, which retains the old request policy.
    // Returning false asks the owner to cancel and create a fresh scoped task.
    if (_isIOS && task.requiresWiFi != requiresWiFi) return false;
    final resumed = task.copyWith(requiresWiFi: requiresWiFi);
    _tasks[taskId] = resumed;
    return _downloader.resume(resumed);
  }

  @override
  Future<void> cancel(String taskId) async {
    final task = await _task(taskId);
    if (task == null) return;
    final record = await _downloader.database.recordForId(taskId);
    if (await _downloader.taskForId(taskId) == null &&
        record != null &&
        record.status.isFinalState) {
      return;
    }
    // ACK is not quiescence: iOS can still move the finished file after cancel.
    // Resolve here, outside the controller queue, before that owner deletes it.
    for (var attempt = 0; attempt < 2; attempt++) {
      final settled = Completer<TaskStatus>();
      _cancellations[taskId] = settled;
      try {
        final accepted = await _downloader.cancelTaskWithId(taskId);
        if (!accepted && !settled.isCompleted) {
          final current = await _downloader.database.recordForId(taskId);
          if (await _downloader.taskForId(taskId) == null &&
              current != null &&
              current.status.isFinalState) {
            return;
          }
          throw StateError('Translator cancellation was not accepted');
        }
        final status = await settled.future.timeout(_cancellationTimeout);
        if (status != TaskStatus.paused) return;
        // A racing pause can leave resume data; cancel that settled paused task
        // once more so the SDK clears its own staging state.
      } finally {
        if (identical(_cancellations[taskId], settled)) {
          _cancellations.remove(taskId);
        }
      }
    }
    throw StateError('Translator cancellation did not settle');
  }

  @override
  Future<void> forget(String taskId) async {
    if (await _task(taskId) != null) {
      await _downloader.database.deleteRecordWithId(taskId);
    }
    _tasks.remove(taskId);
    _sizes.remove(taskId);
  }

  void _onStatus(TaskStatusUpdate update) {
    if (!_owns(update.task) || _events.isClosed) return;
    final cancellation = _cancellations[update.task.taskId];
    if (cancellation != null &&
        !cancellation.isCompleted &&
        (update.status.isFinalState || update.status == TaskStatus.paused)) {
      cancellation.complete(update.status);
    }
    _events.add(
      ModelTransferEvent(
        taskId: update.task.taskId,
        status: _status(update.status),
      ),
    );
  }

  void _onProgress(TaskProgressUpdate update) {
    if (!_owns(update.task) || _events.isClosed || update.progress < 0) return;
    final total = update.expectedFileSize > 0
        ? update.expectedFileSize
        : _sizes[update.task.taskId] ?? gemmaModelBytes;
    _events.add(
      ModelTransferEvent(
        taskId: update.task.taskId,
        receivedBytes: min(total, (update.progress * total).round()),
        remaining: update.hasTimeRemaining ? update.timeRemaining : null,
      ),
    );
  }

  ModelTransferStatus _status(TaskStatus status) => switch (status) {
    TaskStatus.enqueued => ModelTransferStatus.enqueued,
    TaskStatus.running => ModelTransferStatus.running,
    TaskStatus.waitingToRetry => ModelTransferStatus.waitingToRetry,
    TaskStatus.paused => ModelTransferStatus.paused,
    TaskStatus.complete => ModelTransferStatus.complete,
    TaskStatus.failed || TaskStatus.notFound => ModelTransferStatus.failed,
    TaskStatus.canceled => ModelTransferStatus.canceled,
  };

  @override
  Future<void> dispose() async {
    _downloader.unregisterCallbacks(group: modelDeliveryGroup);
    await _events.close();
  }
}
