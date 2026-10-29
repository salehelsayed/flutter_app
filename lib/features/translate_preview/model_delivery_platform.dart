import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:background_downloader/background_downloader.dart';
import 'package:clock/clock.dart';
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
    Future<bool> Function(String, ModelDeliveryManifest)? hashFile,
  }) : _removeModel = removeModel,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _diskSpace = diskSpace ?? DiskSpaceChannel(),
       _preferences = preferences ?? SharedPreferences.getInstance,
       _excludeFromBackup = excludeFromBackup ?? _nativeExcludeFromBackup,
       _hashFile = hashFile;

  static const recordKey = 'mknoon.translator.model_delivery.v1';
  static const _channel = MethodChannel('mknoon/gemma_preview');
  final Future<void> Function(Future<void> Function()) _removeModel;
  final Future<Directory> Function() _supportDirectory;
  final DiskSpaceChannel _diskSpace;
  final Future<SharedPreferences> Function() _preferences;
  final Future<bool> Function(String) _excludeFromBackup;
  final Future<bool> Function(String, ModelDeliveryManifest)? _hashFile;

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
  Future<ModelDeliveryFileIdentity?> modelIdentity() async {
    final file = File(await modelPath());
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) return null;
    return ModelDeliveryFileIdentity(
      canonicalPath: await file.resolveSymbolicLinks(),
      sizeBytes: stat.size,
      modifiedMicros: stat.modified.microsecondsSinceEpoch,
      changedMicros: stat.changed.microsecondsSinceEpoch,
    );
  }

  @override
  Future<bool> verify(ModelDeliveryManifest manifest) async {
    final path = await modelPath();
    return _hashFile?.call(path, manifest) ??
        compute(_verifyModelFile, (
          path: path,
          bytes: manifest.bytes,
          sha256: manifest.sha256,
        ));
  }

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

// The native resume runner can discard its partial on an early DNS failure.
// This runs in the SDK headless engine, so it must not call Flutter plugins.
@pragma('vm:entry-point')
Future<TaskStatusUpdate?> _beforeAndroidModelDeliveryStart(Task task) async {
  try {
    final uri = Uri.parse(task.url);
    if (uri.scheme != 'https' || uri.host != 'updates.mknoon.xyz') {
      return TaskStatusUpdate(task, TaskStatus.paused);
    }
    final deadline = clock.now().add(const Duration(seconds: 20));
    while (clock.now().isBefore(deadline)) {
      final remaining = deadline.difference(clock.now());
      final timeout = remaining < const Duration(seconds: 4)
          ? remaining
          : const Duration(seconds: 4);
      final client = HttpClient();
      try {
        final ready = await (() async {
          final request = await client.headUrl(uri);
          request.followRedirects = false;
          final response = await request.close();
          await response.drain<void>();
          return response.statusCode >= 200 && response.statusCode < 300;
        })().timeout(timeout);
        if (ready) return null;
      } on Object {
        // Wi-Fi availability can precede usable DNS/TLS/origin connectivity.
      } finally {
        client.close(force: true);
      }
      final wait = deadline.difference(clock.now());
      if (wait > Duration.zero) {
        await Future<void>.delayed(
          wait < const Duration(seconds: 1) ? wait : const Duration(seconds: 1),
        );
      }
    }
  } on Object {
    // The SDK treats a thrown hook as permission to continue. Fail closed.
  }
  return TaskStatusUpdate(task, TaskStatus.paused);
}

final class BackgroundModelDeliveryTransport implements ModelDeliveryTransport {
  BackgroundModelDeliveryTransport({
    FileDownloader? downloader,
    PersistentStorage? resumeStorage,
    Future<List<Directory>> Function()? partialDirectories,
    bool? isIOS,
    Duration cancellationTimeout = const Duration(seconds: 30),
    Duration cancellationSettleInterval = const Duration(seconds: 1),
    Future<String> Function(DownloadTask)? destinationPath,
  }) : _downloader = downloader ?? FileDownloader(),
       _resumeStorage = resumeStorage ?? LocalStorePersistentStorage(),
       _partialDirectories = partialDirectories ?? _androidPartialDirectories,
       _isIOS = isIOS ?? Platform.isIOS,
       _useAndroidGate = isIOS == null ? Platform.isAndroid : !isIOS,
       _cancellationTimeout = cancellationTimeout,
       _cancellationSettleInterval = cancellationSettleInterval,
       _destinationPath = destinationPath ?? ((task) => task.filePath());

  final FileDownloader _downloader;
  final PersistentStorage _resumeStorage;
  final Future<List<Directory>> Function() _partialDirectories;
  final bool _isIOS;
  final bool _useAndroidGate;
  final Duration _cancellationTimeout;
  final Duration _cancellationSettleInterval;
  final Future<String> Function(DownloadTask) _destinationPath;
  final _events = StreamController<ModelTransferEvent>.broadcast(sync: true);
  final _tasks = <String, DownloadTask>{};
  final _sizes = <String, int>{};
  final _cancellations = <String, Completer<TaskStatus>>{};
  final _settledStatuses = <String, TaskStatus>{};
  final _partialPaths = <String, Set<String>>{};
  final _partialCaptures = <String, Future<void>>{};
  Future<List<String>>? _partialRoots;

  static Future<List<Directory>> _androidPartialDirectories() async => [
    await getApplicationSupportDirectory(),
    await getTemporaryDirectory(),
  ];

  Future<String?> _safePartialPath(String path) async {
    final file = File(path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    final canonical = await file.resolveSymbolicLinks();
    final resolved = File(canonical);
    if (!RegExp(
      r'^com\.bbflight\.background_downloader-?\d+$',
    ).hasMatch(resolved.uri.pathSegments.last)) {
      return null;
    }
    final roots = await (_partialRoots ??= (() async => [
      for (final directory in await _partialDirectories())
        await directory.resolveSymbolicLinks(),
    ])());
    return roots.contains(resolved.parent.path) ? canonical : null;
  }

  Future<void> _rememberPartial(DownloadTask task) async {
    if (!_useAndroidGate || !_owns(task)) return;
    await _downloader.ready;
    await _resumeStorage.initialize();
    final resume = await _resumeStorage.retrieveResumeData(task.taskId);
    if (resume == null || resume.taskId != task.taskId || !_owns(resume.task)) {
      return;
    }
    final path = await _safePartialPath(resume.tempFilepath);
    if (path != null) {
      (_partialPaths[task.taskId] ??= <String>{}).add(path);
    }
  }

  Future<void> _awaitPartialCaptures(String taskId) async {
    while (true) {
      final pending = _partialCaptures[taskId];
      if (pending == null) return;
      await pending;
      if (identical(_partialCaptures[taskId], pending)) {
        _partialCaptures.remove(taskId);
      }
    }
  }

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
      _sizes[record.taskId] = record.expectedFileSize > 0
          ? record.expectedFileSize
          : gemmaModelBytes;
    }
    // Native acceptance may survive a crash before the SDK database write.
    for (final task in await _downloader.allTasks(group: modelDeliveryGroup)) {
      if (_owns(task)) _tasks[task.taskId] = task as DownloadTask;
    }
    for (final id in _tasks.keys.toList()) {
      await _rememberPartial(_tasks[id]!);
      if (id == ownedTaskId) continue;
      await cancel(id);
      await forget(id);
    }
    await _downloader.resumeFromBackground();
  }

  @override
  Future<ModelTransferSnapshot?> restore(String taskId) async {
    final record = await _downloader.database.recordForId(taskId);
    if (record == null) {
      if (await _task(taskId) == null) return null;
      final status = _settledStatuses[taskId];
      return ModelTransferSnapshot(
        taskId: taskId,
        status: status == null ? ModelTransferStatus.enqueued : _status(status),
        receivedBytes: status == TaskStatus.complete
            ? _sizes[taskId] ?? gemmaModelBytes
            : 0,
      );
    }
    if (!_owns(record.task)) return null;
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
      options: _useAndroidGate
          ? TaskOptions(beforeTaskStart: _beforeAndroidModelDeliveryStart)
          : null,
    );
    _tasks[taskId] = task;
    _settledStatuses.remove(taskId);
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
    final task = record?.task ?? await _downloader.taskForId(id) ?? _tasks[id];
    if (task == null || !_owns(task)) return null;
    return _tasks[id] = task as DownloadTask;
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
    await _rememberPartial(task);
    final resumed = task.copyWith(
      requiresWiFi: requiresWiFi,
      options:
          task.options ??
          (_useAndroidGate
              ? TaskOptions(beforeTaskStart: _beforeAndroidModelDeliveryStart)
              : null),
    );
    _settledStatuses.remove(taskId);
    _tasks[taskId] = resumed;
    return _downloader.resume(resumed);
  }

  @override
  Future<void> cancel(String taskId) async {
    var settled = Completer<TaskStatus>();
    // Observe before even looking up the task: an inspection can race completion.
    _cancellations[taskId] = settled;
    try {
      final task = await _task(taskId);
      if (task == null) return;
      // Cancellation clears SDK resume metadata, sometimes without its file.
      await _rememberPartial(task);
      for (var attempt = 0; attempt < 2; attempt++) {
        final native = await _downloader.taskForId(taskId);
        final record = await _downloader.database.recordForId(taskId);
        var status = _settledStatuses[taskId] ?? record?.status;
        if (native == null && status != null && status.isFinalState) {
          await _settleCanceledWriter(task, status);
          return;
        }
        final accepted = await _downloader.cancelTaskWithId(taskId);
        final current = await _downloader.database.recordForId(taskId);
        final absent = await _downloader.taskForId(taskId) == null;
        status = _settledStatuses[taskId] ?? current?.status;
        if (!accepted &&
            !settled.isCompleted &&
            !(absent && status != null && status.isFinalState)) {
          throw StateError('Translator cancellation was not accepted');
        }
        if (!(absent && status != null && status.isFinalState)) {
          status = await settled.future.timeout(_cancellationTimeout);
        }
        if (status != TaskStatus.paused) {
          await _settleCanceledWriter(task, status);
          return;
        }
        // A racing pause can leave resume data; cancel that settled paused task
        // once more so the SDK clears its own staging state.
        _settledStatuses.remove(taskId);
        settled = Completer<TaskStatus>();
        _cancellations[taskId] = settled;
      }
      throw StateError('Translator cancellation did not settle');
    } finally {
      if (identical(_cancellations[taskId], settled)) {
        _cancellations.remove(taskId);
      }
    }
  }

  Future<void> _settleCanceledWriter(
    DownloadTask task,
    TaskStatus status,
  ) async {
    await _awaitPartialCaptures(task.taskId);
    if (_isIOS) return;
    // WorkManager cancel/"canceled" does not join its synchronous file writer.
    // The pinned SDK exposes no join. Use the bounded filesystem-settle fallback:
    // remove stable owned files, then require two quiet absent samples.
    // A late recreation resets settlement and is deleted again before returning.
    final destination = status == TaskStatus.complete
        ? null
        : await _destinationPath(task);
    if (destination == null && (_partialPaths[task.taskId]?.isEmpty ?? true)) {
      return;
    }
    final watch = Stopwatch()..start();
    final previous = <String, FileStat>{};
    var absentSamples = 0;
    while (watch.elapsed < _cancellationTimeout) {
      await Future<void>.delayed(_cancellationSettleInterval);
      if (await _downloader.taskForId(task.taskId) != null) {
        absentSamples = 0;
        previous.clear();
        continue;
      }
      await _awaitPartialCaptures(task.taskId);
      final paths = <String>{
        ?destination,
        ...(_partialPaths[task.taskId] ?? <String>{}),
      };
      var allAbsent = true;
      for (final path in paths) {
        final file = File(path);
        final stat = await file.stat();
        if (stat.type == FileSystemEntityType.notFound) {
          previous.remove(path);
        } else {
          allAbsent = false;
          if (previous[path]?.size == stat.size &&
              previous[path]?.modified == stat.modified) {
            if (path != destination && await _safePartialPath(path) != path) {
              throw FileSystemException('Translator partial ownership changed');
            }
            await file.delete();
            previous.remove(path);
          } else {
            previous[path] = stat;
          }
        }
      }
      await _awaitPartialCaptures(task.taskId);
      if (!paths.containsAll(_partialPaths[task.taskId] ?? <String>{})) {
        allAbsent = false;
      }
      absentSamples = allAbsent ? absentSamples + 1 : 0;
      if (absentSamples >= 2) return;
    }
    throw TimeoutException('Translator destination did not settle');
  }

  @override
  Future<void> forget(String taskId) async {
    await _awaitPartialCaptures(taskId);
    if (await _task(taskId) != null) {
      await _downloader.database.deleteRecordWithId(taskId);
    }
    await _awaitPartialCaptures(taskId);
    _tasks.remove(taskId);
    _sizes.remove(taskId);
    _settledStatuses.remove(taskId);
    _partialPaths.remove(taskId);
  }

  void _onStatus(TaskStatusUpdate update) {
    if (!_owns(update.task) || _events.isClosed) return;
    _tasks[update.task.taskId] = update.task as DownloadTask;
    final capture = _rememberPartial(update.task as DownloadTask).catchError((
      Object _,
    ) {
      // Remove retries the snapshot synchronously before canceling its task.
    });
    _partialCaptures[update.task.taskId] =
        (_partialCaptures[update.task.taskId] ?? Future<void>.value()).then(
          (_) => capture,
        );
    if (update.status.isFinalState || update.status == TaskStatus.paused) {
      _settledStatuses[update.task.taskId] = update.status;
    }
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
