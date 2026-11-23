import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/features/translate_preview/gemma_preview_prompts.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_core.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_platform.dart';
import 'package:flutter_test/flutter_test.dart';

const _bound = Duration(seconds: 3);
const _offset = 2 * 1024 * 1024;
const _eTag = '"fixture"';
const _group = 'bl60_managed_resume';

typedef _Enqueue = ({String id, List<Object?> arguments});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'managed recovery retains the checkpoint without changing SDK defaults',
    () async {
      // Select the real Android Dart adapter. Only the platform boundaries below
      // are faked, so no worker, URL request, or device is needed.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final directory = Directory.systemTemp.createTempSync(
        'bl60-managed-resume-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final storage = _ProbeStorage();
      final enqueues = <_Enqueue>[];
      final enqueueEvents = StreamController<_Enqueue>.broadcast(sync: true);
      addTearDown(enqueueEvents.close);
      final paused = <String>[];
      final policyUpdates = <List<Object?>>[];
      var policyUpdateResult = 'applied';
      var resumeAccepted = true;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const native = MethodChannel('com.bbflight.background_downloader');
      final translator = DownloadTask(
        taskId: 'queued-translator-mobile',
        group: modelDeliveryGroup,
        baseDirectory: BaseDirectory.applicationSupport,
        directory: modelDeliveryDirectory,
        filename: gemmaModelFileName,
        url: 'https://model.invalid/model.bin',
        retries: 0,
        allowPause: true,
        options: TaskOptions(appManagedRecovery: true),
      );
      final translatorJson = jsonEncode(translator.toJson());
      final cancellationCalls = <String>[];
      Future<void> deliverTranslatorStatus(TaskStatus status) => messenger
          .handlePlatformMessage(
            'com.bbflight.background_downloader.background',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('statusUpdate', [translatorJson, status.index]),
            ),
            null,
          )
          .timeout(_bound);
      messenger.setMockMethodCallHandler(native, (call) async {
        if (call.method == 'taskForId') {
          expect(call.arguments, translator.taskId);
          return translatorJson;
        }
        if (call.method == 'cancelTasksWithIds') {
          expect(call.arguments, [translator.taskId]);
          cancellationCalls.add(call.method);
          // Android's legacy method posts canceled before a rejected stop.
          await deliverTranslatorStatus(TaskStatus.canceled);
          return false;
        }
        if (call.method == 'cancelTaskWithConfirmation') {
          expect(call.arguments, translator.taskId);
          cancellationCalls.add(call.method);
          return false;
        }
        if (call.method == 'updateQueuedManagedDownload') {
          policyUpdates.add(List<Object?>.of(call.arguments as List));
          return policyUpdateResult;
        }
        if (call.method == 'pause') {
          paused.add(call.arguments as String);
          return true;
        }
        expect(call.method, 'enqueue');
        final arguments = List<Object?>.of(call.arguments as List);
        final task =
            jsonDecode(arguments.first as String) as Map<String, dynamic>;
        final attempt = (id: task['taskId'] as String, arguments: arguments);
        expect(task['retries'], 0);
        expect(task['retriesRemaining'], 0);
        enqueues.add(attempt);
        enqueueEvents.add(attempt);
        return arguments.length == 2 || resumeAccepted;
      });
      final connectivity = Completer<MockStreamHandlerEventSink>();
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => ['wifi'],
      );
      messenger.setMockStreamHandler(
        const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
        MockStreamHandler.inline(
          onListen: (_, events) {
            connectivity.complete(events);
          },
        ),
      );

      final downloader = FileDownloader(persistentStorage: storage);
      expect(await downloader.ready.timeout(_bound), isTrue);
      final connectivityEvents = await connectivity.future.timeout(_bound);
      // ignore: invalid_use_of_visible_for_testing_member
      final sdk = downloader.downloaderForTesting;
      final statuses = <String, TaskStatusUpdate>{};
      downloader.registerCallbacks(
        group: _group,
        taskStatusCallback: (update) => statuses[update.task.taskId] = update,
      );
      addTearDown(() => downloader.unregisterCallbacks(group: _group));

      Future<({DownloadTask task, File partial})> seed(
        String id, {
        bool? managed,
      }) async {
        final task = DownloadTask(
          taskId: id,
          group: _group,
          url: 'https://model.invalid/model.bin',
          filename: 'model.bin',
          retries: 0,
          allowPause: true,
          requiresWiFi: true,
          updates: Updates.status,
          options: managed == null
              ? null
              : TaskOptions(appManagedRecovery: managed),
        );
        final partial = File('${directory.path}/$id.part');
        final file = partial.openSync(mode: FileMode.write);
        try {
          file.truncateSync(_offset);
        } finally {
          file.closeSync();
        }
        expect(await downloader.enqueue(task).timeout(_bound), isTrue);
        expect(await downloader.pause(task).timeout(_bound), isTrue);
        expect(paused.last, id);
        // Fixture for a checkpoint the native worker had already returned.
        await storage.storeResumeData(
          ResumeData(task, partial.path, _offset, _eTag),
        );
        sdk.processStatusUpdate(TaskStatusUpdate(task, TaskStatus.paused));
        expect(statuses[id]?.status, TaskStatus.paused);
        expect(await downloader.taskCanResume(task).timeout(_bound), isTrue);
        expect(await downloader.resume(task).timeout(_bound), isTrue);
        expect(enqueues.last.id, id);
        expect(enqueues.last.arguments.skip(2), [partial.path, _offset, _eTag]);
        return (task: task, partial: partial);
      }

      final managed = await seed('managed', managed: true).timeout(_bound);
      final defaultTask = await seed('default').timeout(_bound);
      final explicitFalse = await seed(
        'explicit-false',
        managed: false,
      ).timeout(_bound);

      final savedCheckpoint = (await storage
          .retrieveResumeData(managed.task.taskId)
          .timeout(_bound))!;
      final rebound = managed.task.copyWith(requiresWiFi: false);
      final enqueuesBeforePolicyUpdate = enqueues.length;
      for (final result in ManagedQueuePolicyUpdate.values) {
        policyUpdateResult = result.name;
        expect(
          await downloader
              .updateQueuedManagedDownload(rebound, savedCheckpoint)
              .timeout(_bound),
          result,
        );
      }
      expect(enqueues, hasLength(enqueuesBeforePolicyUpdate));
      expect(policyUpdates, hasLength(ManagedQueuePolicyUpdate.values.length));
      for (final arguments in policyUpdates) {
        final task = jsonDecode(arguments.first as String) as Map;
        expect(task, {...managed.task.toJson(), 'requiresWiFi': false});
        expect(arguments.skip(1), [null, managed.partial.path, _offset, _eTag]);
      }
      expect(
        await downloader
            .updateQueuedManagedDownload(defaultTask.task, savedCheckpoint)
            .timeout(_bound),
        ManagedQueuePolicyUpdate.unavailable,
      );
      expect(policyUpdates, hasLength(ManagedQueuePolicyUpdate.values.length));

      for (final control in [defaultTask, explicitFalse]) {
        expect(downloader.isConnected, isTrue);
        sdk.processStatusUpdate(
          TaskStatusUpdate(
            control.task,
            TaskStatus.failed,
            TaskConnectionException('lost'),
          ),
        );
        final id = control.task.taskId;
        expect(statuses[id]?.status, TaskStatus.failed);
        expect(await storage.retrieveResumeData(id), isNull);
        expect(await downloader.resume(control.task).timeout(_bound), isFalse);
        await storage.storeResumeData(
          ResumeData(control.task, control.partial.path, _offset, _eTag),
        );
      }

      sdk.processStatusUpdate(
        TaskStatusUpdate(
          managed.task,
          TaskStatus.failed,
          TaskException.fromTypeString('TaskStorageFullException', 'disk full'),
        ),
      );
      final managedId = managed.task.taskId;
      expect(statuses[managedId]?.exception, isA<TaskStorageFullException>());
      expect(await downloader.resumeCheckpoint(managed.task).timeout(_bound), (
        offset: _offset,
      ));

      connectivityEvents.success(['none']);
      final clock = Stopwatch()..start();
      while (downloader.isConnected && clock.elapsed < _bound) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(downloader.isConnected, isFalse);
      for (final transfer in [managed, defaultTask, explicitFalse]) {
        sdk.processStatusUpdate(
          TaskStatusUpdate(
            transfer.task,
            TaskStatus.failed,
            TaskConnectionException('offline'),
          ),
        );
        expect(
          statuses[transfer.task.taskId]?.status,
          transfer == managed ? TaskStatus.failed : TaskStatus.waitingToRetry,
        );
      }

      resumeAccepted = false;
      final beforeReconnect = enqueues.length;
      final ordinaryIds = {defaultTask.task.taskId, explicitFalse.task.taskId};
      final ordinaryFreshStarts = <String>{};
      final ordinaryReconnect = enqueueEvents.stream
          .firstWhere((entry) {
            if (ordinaryIds.contains(entry.id) && entry.arguments.length == 2) {
              ordinaryFreshStarts.add(entry.id);
            }
            return ordinaryFreshStarts.length == ordinaryIds.length;
          })
          .timeout(_bound);
      connectivityEvents.success(['wifi']);
      await ordinaryReconnect;
      final reconnect = enqueues.skip(beforeReconnect).toList();
      expect(reconnect.map((entry) => entry.id).toSet(), ordinaryIds);
      for (final control in [defaultTask, explicitFalse]) {
        final attempts = reconnect.where(
          (entry) => entry.id == control.task.taskId,
        );
        expect(attempts.map((entry) => entry.arguments.length), [5, 2]);
        expect(attempts.first.arguments.skip(2), [
          control.partial.path,
          _offset,
          _eTag,
        ]);
      }

      resumeAccepted = true;
      expect(await downloader.resume(managed.task).timeout(_bound), isTrue);
      expect(enqueues.last.id, managedId);
      expect(enqueues.last.arguments.skip(2), [
        managed.partial.path,
        _offset,
        _eTag,
      ]);
      final beforeInvalid = enqueues.length;
      managed.partial.deleteSync();
      expect(
        await downloader.resumeCheckpoint(managed.task).timeout(_bound),
        isNull,
      );
      expect(await downloader.resume(managed.task).timeout(_bound), isFalse);
      expect(enqueues.length, beforeInvalid);

      final transport = BackgroundModelDeliveryTransport(
        downloader: downloader,
        resumeStorage: storage,
        partialDirectories: () async => [directory],
        isIOS: false,
      );
      addTearDown(() => transport.dispose().timeout(_bound));
      final partial = File(
        '${directory.path}/com.bbflight.background_downloader-60',
      );
      final writer = partial.openSync(mode: FileMode.write);
      try {
        writer.truncateSync(_offset);
      } finally {
        writer.closeSync();
      }
      await storage
          .storeResumeData(ResumeData(translator, partial.path, _offset, _eTag))
          .timeout(_bound);
      expect(
        (await transport.checkpoint(translator.taskId).timeout(_bound))
            ?.retainedBytes,
        _offset,
      );
      await expectLater(
        transport
            .cancel(translator.taskId, requireConfirmedStop: true)
            .timeout(_bound),
        throwsStateError,
      );
      expect(cancellationCalls, hasLength(1));
      expect(partial.lengthSync(), _offset);
      expect(
        (await transport.checkpoint(translator.taskId).timeout(_bound))
            ?.retainedBytes,
        _offset,
        reason: 'Rejected cancellation must preserve SDK resume metadata.',
      );
      expect(cancellationCalls, ['cancelTaskWithConfirmation']);
      expect(
        await transport
            .resume(
              translator.taskId,
              requiresWiFi: true,
              allowZeroByteRestart: false,
            )
            .timeout(_bound),
        isTrue,
      );
      expect(enqueues.last.id, translator.taskId);
      expect(enqueues.last.arguments.skip(2), [partial.path, _offset, _eTag]);
    },
  );
}

// This storage honors all SDK deletions. The SDK owns the retention policy.
final class _ProbeStorage implements PersistentStorage {
  final _records = <String, TaskRecord>{};
  final _checkpoints = <String, ResumeData>{};
  final _paused = <String, Task>{};

  @override
  Future<void> initialize() async {}

  @override
  (String, int) get currentDatabaseVersion => ('probe', 1);

  @override
  Future<(String, int)> get storedDatabaseVersion async =>
      currentDatabaseVersion;

  @override
  Future<void> storeTaskRecord(TaskRecord record) async {
    _records[record.taskId] = record;
  }

  @override
  Future<TaskRecord?> retrieveTaskRecord(String taskId) async =>
      _records[taskId];

  @override
  Future<List<TaskRecord>> retrieveAllTaskRecords() async =>
      _records.values.toList();

  @override
  Future<void> removeTaskRecord(String? taskId) async {
    if (taskId == null) {
      _records.clear();
    } else {
      _records.remove(taskId);
    }
  }

  @override
  Future<void> storeResumeData(ResumeData data) async {
    _checkpoints[data.taskId] = data;
  }

  @override
  Future<ResumeData?> retrieveResumeData(String taskId) async =>
      _checkpoints[taskId];

  @override
  Future<List<ResumeData>> retrieveAllResumeData() async =>
      _checkpoints.values.toList();

  @override
  Future<void> removeResumeData(String? taskId) async {
    if (taskId == null) {
      _checkpoints.clear();
    } else {
      _checkpoints.remove(taskId);
    }
  }

  @override
  Future<void> storePausedTask(Task task) async {
    _paused[task.taskId] = task;
  }

  @override
  Future<Task?> retrievePausedTask(String taskId) async => _paused[taskId];

  @override
  Future<List<Task>> retrieveAllPausedTasks() async => _paused.values.toList();

  @override
  Future<void> removePausedTask(String? taskId) async {
    if (taskId == null) {
      _paused.clear();
    } else {
      _paused.remove(taskId);
    }
  }
}
