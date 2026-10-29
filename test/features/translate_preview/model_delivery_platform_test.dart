import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/device/disk_space.dart';
import 'package:flutter_app/features/translate_preview/gemma_preview_prompts.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_core.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ModelDeliveryManifest _manifest({
  int bytes = 100,
  String? digest,
}) => ModelDeliveryManifest.fromJson({
  'model': 'gemma-4-E2B-it',
  'url':
      'https://updates.mknoon.xyz/models/gemma-4-E2B-it-${(digest ?? 'a' * 64).substring(0, 12)}.litertlm',
  'bytes': bytes,
  'sha256': digest ?? 'a' * 64,
  'minAppBuild': 129,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory destinations;
  setUp(() async {
    destinations = await Directory.systemTemp.createTemp('translator-cancel-');
  });
  tearDown(() => destinations.delete(recursive: true));
  BackgroundModelDeliveryTransport createTransport({
    required FileDownloader downloader,
    bool? isIOS,
    Duration cancellationTimeout = const Duration(seconds: 30),
    Future<String> Function(DownloadTask)? destinationPath,
  }) => BackgroundModelDeliveryTransport(
    downloader: downloader,
    isIOS: isIOS,
    cancellationTimeout: cancellationTimeout,
    cancellationSettleInterval: const Duration(milliseconds: 2),
    destinationPath:
        destinationPath ??
        (task) async => '${destinations.path}/${task.filename}',
  );

  test(
    'adapter owns only its group and disables completion notifications',
    () async {
      final downloader = _Downloader();
      final other = _ownedTask('other').copyWith(group: 'smart_downloads');
      downloader.db.records['other'] = TaskRecord(
        other,
        TaskStatus.running,
        .2,
        100,
      );
      final transport = createTransport(downloader: downloader);
      addTearDown(transport.dispose);
      await transport.initialize(null);
      expect(downloader.registeredGroup, modelDeliveryGroup);
      expect(downloader.trackedGroup, modelDeliveryGroup);
      expect(downloader.markDownloadedComplete, isFalse);
      expect(downloader.notificationGroup, modelDeliveryGroup);
      expect(downloader.completeNotification, isNull);
      expect(downloader.canceled, isEmpty);
      expect(downloader.db.records.keys, ['other']);
      await transport.enqueue(
        taskId: 'owned',
        manifest: _manifest(),
        requiresWiFi: true,
      );
      final task = downloader.enqueued.single;
      expect(task.baseDirectory, BaseDirectory.applicationSupport);
      expect(task.directory, modelDeliveryDirectory);
      expect(task.filename, gemmaModelFileName);
      expect(task.group, modelDeliveryGroup);
      expect(task.allowPause, isTrue);
      expect(task.requiresWiFi, isTrue);
      expect(task.retries, 3);
      expect(task.priority, 5);
      expect(task.transferHints, contains(TransferHint.largeFile));
      final events = <ModelTransferEvent>[];
      final subscription = transport.events.listen(events.add);
      addTearDown(subscription.cancel);
      downloader.emit(other, TaskStatus.complete);
      expect(events, isEmpty);
      downloader.emit(task, TaskStatus.running);
      expect(events.single.taskId, 'owned');
    },
  );

  test(
    'iOS unchanged policy resumes partial; changed policy requests scoped restart',
    () async {
      final downloader = _Downloader();
      final transport = createTransport(downloader: downloader, isIOS: true);
      addTearDown(transport.dispose);
      await transport.initialize(null);
      await transport.enqueue(
        taskId: 'one',
        manifest: _manifest(),
        requiresWiFi: false,
      );
      expect(await transport.resume('one', requiresWiFi: false), isTrue);
      expect(downloader.resumed.single.requiresWiFi, isFalse);
      expect(await transport.resume('one', requiresWiFi: true), isFalse);
      expect(downloader.resumed, hasLength(1));
      expect(downloader.enqueued, hasLength(1));
    },
  );

  test(
    'Android resume changes native requiresWiFi on the same partial task',
    () async {
      final downloader = _Downloader();
      final transport = createTransport(downloader: downloader, isIOS: false);
      addTearDown(transport.dispose);
      await transport.initialize(null);
      await transport.enqueue(
        taskId: 'one',
        manifest: _manifest(),
        requiresWiFi: false,
      );
      expect(await transport.resume('one', requiresWiFi: true), isTrue);
      expect(downloader.resumed.single.taskId, 'one');
      expect(downloader.resumed.single.requiresWiFi, isTrue);
    },
  );

  test(
    'cancel ACK waits for terminal callback after a racing destination move',
    () async {
      final downloader = _Downloader();
      final transport = createTransport(downloader: downloader);
      addTearDown(transport.dispose);
      await transport.initialize(null);
      await transport.enqueue(
        taskId: 'one',
        manifest: _manifest(),
        requiresWiFi: true,
      );
      final task = downloader.enqueued.single;
      final requested = Completer<void>();
      downloader.onCancel = (_) async {
        requested.complete();
        return true;
      };
      var finished = false;
      final cancel = transport.cancel('one').then((_) {
        finished = true;
      });
      await requested.future;
      expect(finished, isFalse);
      expect(downloader.db.deleted, isEmpty);
      // Native emits complete only after moving the file into the destination.
      downloader.emit(task, TaskStatus.complete);
      await cancel;
      expect(finished, isTrue);
      await transport.forget('one');
      expect(downloader.db.deleted, ['one']);
    },
  );

  test(
    'Android canceled ACK precedes the writer final action and late recreation is deleted',
    () async {
      final downloader = _Downloader();
      final destination = File('${destinations.path}/$gemmaModelFileName');
      await destination.writeAsString('first destination');
      final transport = createTransport(downloader: downloader, isIOS: false);
      addTearDown(transport.dispose);
      await transport.initialize(null);
      await transport.enqueue(
        taskId: 'one',
        manifest: _manifest(),
        requiresWiFi: true,
      );
      final task = downloader.enqueued.single;
      var acknowledged = false;
      var lateWrite = false;
      downloader.onCancel = (_) async {
        downloader.emit(task, TaskStatus.canceled);
        acknowledged = true;
        return true;
      };
      downloader.onTaskForId = (id) async {
        if (acknowledged && !lateWrite && !await destination.exists()) {
          // The worker's copy fallback recreates the file after initial cleanup.
          expect(downloader.db.deleted, isEmpty);
          expect(downloader.enqueued, hasLength(1));
          await destination.writeAsString('late worker destination');
          lateWrite = true;
        }
        return downloader.active[id];
      };
      await transport.cancel('one');
      expect(lateWrite, isTrue);
      expect(await destination.exists(), isFalse);
      await transport.forget('one');
      await transport.enqueue(
        taskId: 'two',
        manifest: _manifest(),
        requiresWiFi: true,
      );
      expect(downloader.db.deleted, ['one']);
      expect(downloader.enqueued, hasLength(2));
    },
  );

  test(
    'completion during taskForId remains observed before cancel inspection',
    () async {
      final downloader = _Downloader();
      final transport = createTransport(
        downloader: downloader,
        isIOS: true,
        cancellationTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(transport.dispose);
      await transport.initialize(null);
      await transport.enqueue(
        taskId: 'one',
        manifest: _manifest(),
        requiresWiFi: true,
      );
      final task = downloader.enqueued.single;
      var completed = false;
      downloader.onTaskForId = (_) async {
        if (!completed) {
          completed = true;
          downloader.emit(task, TaskStatus.complete);
          // SDK persistence can still lag behind its delivered status.
          downloader.db.records['one'] = TaskRecord(
            task,
            TaskStatus.running,
            0,
            100,
          );
        }
        return null;
      };
      downloader.onCancel = (_) async => true; // No second callback.
      await transport.cancel('one');
      await transport.forget('one');
      expect(completed, isTrue);
      expect(downloader.canceled, isEmpty);
      expect(downloader.db.deleted, ['one']);
    },
  );

  test(
    'native lookup retains owned task observed while the inspection awaits',
    () async {
      final downloader = _Downloader();
      final transport = createTransport(downloader: downloader, isIOS: false);
      addTearDown(transport.dispose);
      await transport.initialize(null);
      final task = _ownedTask('late');
      downloader.active['late'] = task;
      final destination = File('${destinations.path}/$gemmaModelFileName');
      await destination.writeAsString('owned destination');
      var delivered = false;
      downloader.onTaskForId = (_) async {
        if (!delivered) {
          delivered = true;
          downloader.emit(task, TaskStatus.canceled);
        }
        return null;
      };
      await transport.cancel('late');
      expect(delivered, isTrue);
      expect(await destination.exists(), isFalse);
      await transport.forget('late');
      expect(downloader.db.deleted, ['late']);
    },
  );

  test(
    'owned native task without SDK DB record is recovered and canceled',
    () async {
      final downloader = _Downloader();
      final current = _ownedTask('current');
      final stale = _ownedTask('stale');
      final unrelated = _ownedTask('other').copyWith(group: 'smart_downloads');
      downloader.active.addAll({
        'current': current,
        'stale': stale,
        'other': unrelated,
      });
      final transport = createTransport(downloader: downloader);
      addTearDown(transport.dispose);
      await transport.initialize('current');
      final recovered = await transport.restore('current');
      expect(recovered!.taskId, 'current');
      expect(recovered.status, ModelTransferStatus.enqueued);
      expect(downloader.canceled, ['stale']);
      expect(downloader.active['other'], same(unrelated));
      // Also exercise lookup fallback after initialization, without either cache.
      downloader.active['late'] = _ownedTask('late');
      await transport.cancel('late');
      await transport.cancel('current');
      expect(downloader.canceled, ['stale', 'late', 'current']);
      expect(downloader.enqueued, isEmpty);
      final wrongDirectory = _ownedTask('foreign').copyWith(directory: 'other');
      downloader.active['foreign'] = wrongDirectory;
      await transport.cancel('foreign');
      expect(downloader.active['foreign'], same(wrongDirectory));
      expect(downloader.canceled, hasLength(3));
    },
  );

  test(
    'rejected live cancel fails; terminal and absent task needs no cancel',
    () async {
      final downloader = _Downloader();
      final transport = createTransport(downloader: downloader);
      addTearDown(transport.dispose);
      await transport.initialize(null);
      await transport.enqueue(
        taskId: 'one',
        manifest: _manifest(),
        requiresWiFi: true,
      );
      downloader.onCancel = (_) async => false;
      await expectLater(transport.cancel('one'), throwsStateError);
      expect(downloader.db.deleted, isEmpty);
      final task = downloader.enqueued.single;
      downloader.emit(task, TaskStatus.complete);
      final count = downloader.canceled.length;
      await transport.cancel('one');
      expect(downloader.canceled, hasLength(count));
    },
  );

  test(
    'cancel with no terminal outcome times out without forgetting state',
    () async {
      final downloader = _Downloader();
      final transport = createTransport(
        downloader: downloader,
        cancellationTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(transport.dispose);
      await transport.initialize(null);
      await transport.enqueue(
        taskId: 'one',
        manifest: _manifest(),
        requiresWiFi: true,
      );
      downloader.onCancel = (_) async => true;
      await expectLater(
        transport.cancel('one'),
        throwsA(isA<TimeoutException>()),
      );
      expect(downloader.db.deleted, isEmpty);
      expect(downloader.db.records.containsKey('one'), isTrue);
    },
  );

  test(
    'cancel cleans a racing paused resume record before it finishes',
    () async {
      final downloader = _Downloader();
      final transport = createTransport(downloader: downloader);
      addTearDown(transport.dispose);
      await transport.initialize(null);
      await transport.enqueue(
        taskId: 'one',
        manifest: _manifest(),
        requiresWiFi: true,
      );
      final task = downloader.enqueued.single;
      var count = 0;
      downloader.onCancel = (_) async {
        downloader.emit(
          task,
          ++count == 1 ? TaskStatus.paused : TaskStatus.canceled,
        );
        return true;
      };
      await transport.cancel('one');
      expect(downloader.canceled, ['one', 'one']);
      expect(downloader.db.records['one']!.status, TaskStatus.canceled);
    },
  );

  test(
    'recovery reaps stale owned records without touching smart_downloads',
    () async {
      final downloader = _Downloader();
      final stale = _ownedTask('stale');
      final current = _ownedTask('current');
      final unrelated = _ownedTask(
        'inference',
      ).copyWith(group: 'smart_downloads');
      for (final task in [stale, current, unrelated]) {
        downloader.db.records[task.taskId] = TaskRecord(
          task,
          TaskStatus.paused,
          .5,
          100,
        );
        downloader.active[task.taskId] = task;
      }
      final transport = createTransport(downloader: downloader);
      addTearDown(transport.dispose);
      await transport.initialize('current');
      expect(downloader.canceled, ['stale']);
      expect(downloader.db.deleted, ['stale']);
      final recovered = await transport.restore('current');
      expect(recovered!.receivedBytes, 50);
      expect(recovered.status, ModelTransferStatus.paused);
      expect(downloader.db.records.containsKey('inference'), isTrue);
      expect(downloader.resumedBackground, isTrue);
    },
  );

  test(
    'storage checks exact size/hash and removes only its owned directory',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'model-delivery-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final protectedPaths = <String>[];
      var serialRemovals = 0;
      final storage = AppSupportModelDeliveryStorage(
        supportDirectory: () async => root,
        preferences: () async => prefs,
        diskSpace: DiskSpaceChannel(
          invoker: (_, arguments) async {
            expect((arguments! as Map<String, Object?>)['path'], root.path);
            return 300;
          },
        ),
        excludeFromBackup: (path) async {
          protectedPaths.add(path);
          return true;
        },
        removeModel: (delete) async {
          serialRemovals++;
          await delete();
        },
      );
      await storage.prepare();
      expect(protectedPaths.single, '${root.path}/$modelDeliveryDirectory');
      expect(await storage.availableBytes(), 300);
      final file = File(await storage.modelPath());
      final bytes = [1, 2, 3];
      await file.writeAsBytes(bytes);
      final manifest = _manifest(
        bytes: 3,
        digest: sha256.convert(bytes).toString(),
      );
      expect(await storage.verify(manifest), isTrue);
      expect(
        await storage.verify(_manifest(bytes: 4, digest: manifest.sha256)),
        isFalse,
      );
      await file.writeAsBytes([1, 2, 4]);
      expect(await storage.verify(manifest), isFalse);
      final sideLoaded = File('${root.path}/Documents/side-loaded.litertlm');
      await sideLoaded.parent.create();
      await sideLoaded.writeAsString('preserve');
      final cache = File('${root.path}/litert-cache');
      await cache.writeAsString('preserve');
      final record = ModelDeliveryRecord(
        manifest: manifest,
        allowMobileData: true,
      );
      await storage.saveRecord(record);
      expect((await storage.readRecord())!.allowMobileData, isTrue);
      await storage.removeOwnedModel();
      expect(serialRemovals, 1);
      expect(await file.exists(), isFalse);
      expect(await sideLoaded.exists(), isTrue);
      expect(await cache.exists(), isTrue);
      expect(await storage.availableBytes(), 300);
    },
  );

  test('storage refuses unconfirmed backup exclusion', () async {
    final root = await Directory.systemTemp.createTemp(
      'model-delivery-backup-',
    );
    addTearDown(() => root.delete(recursive: true));
    final storage = AppSupportModelDeliveryStorage(
      supportDirectory: () async => root,
      excludeFromBackup: (_) async => false,
      removeModel: (delete) => delete(),
    );
    await expectLater(storage.prepare(), throwsA(isA<FileSystemException>()));
  });
}

DownloadTask _ownedTask(String id) => DownloadTask(
  taskId: id,
  url: _manifest().url.toString(),
  filename: gemmaModelFileName,
  directory: modelDeliveryDirectory,
  baseDirectory: BaseDirectory.applicationSupport,
  group: modelDeliveryGroup,
  updates: Updates.statusAndProgress,
  allowPause: true,
);

class _Database extends Fake implements Database {
  final records = <String, TaskRecord>{};
  final deleted = <String>[];
  @override
  Future<List<TaskRecord>> allRecords({String? group}) async =>
      records.values.where((r) => group == null || r.group == group).toList();
  @override
  Future<TaskRecord?> recordForId(String taskId) async => records[taskId];
  @override
  Future<void> deleteRecordWithId(String taskId) async {
    deleted.add(taskId);
    records.remove(taskId);
  }
}

class _Downloader extends Fake implements FileDownloader {
  final db = _Database();
  final active = <String, Task>{};
  final enqueued = <DownloadTask>[];
  final resumed = <DownloadTask>[];
  final canceled = <String>[];
  TaskStatusCallback? statusCallback;
  String? registeredGroup;
  String? trackedGroup;
  String? notificationGroup;
  TaskNotification? completeNotification;
  bool? markDownloadedComplete;
  bool resumedBackground = false;
  Future<bool> Function(String)? onCancel;
  Future<Task?> Function(String)? onTaskForId;
  @override
  Database get database => db;
  @override
  FileDownloader registerCallbacks({
    String group = 'default',
    TaskStatusCallback? taskStatusCallback,
    TaskProgressCallback? taskProgressCallback,
    TaskNotificationTapCallback? taskNotificationTapCallback,
  }) {
    registeredGroup = group;
    statusCallback = taskStatusCallback;
    return this;
  }

  @override
  FileDownloader unregisterCallbacks({
    String group = 'default',
    Function? callback,
  }) => this;
  @override
  FileDownloader configureNotificationForGroup(
    String group, {
    TaskNotification? running,
    TaskNotification? complete,
    TaskNotification? error,
    TaskNotification? paused,
    TaskNotification? canceled,
    bool progressBar = false,
    bool tapOpensFile = false,
    String groupNotificationId = '',
  }) {
    notificationGroup = group;
    completeNotification = complete;
    return this;
  }

  @override
  Future<FileDownloader> trackTasksInGroup(
    String group, {
    bool markDownloadedComplete = true,
  }) async {
    trackedGroup = group;
    this.markDownloadedComplete = markDownloadedComplete;
    return this;
  }

  @override
  Future<void> resumeFromBackground() async {
    resumedBackground = true;
  }

  @override
  Future<bool> enqueue(Task task) async {
    enqueued.add(task as DownloadTask);
    active[task.taskId] = task;
    db.records[task.taskId] = TaskRecord(task, TaskStatus.enqueued, 0, 100);
    return true;
  }

  @override
  Future<bool> resume(Task task) async {
    resumed.add(task as DownloadTask);
    return true;
  }

  @override
  Future<Task?> taskForId(String taskId) async =>
      onTaskForId == null ? active[taskId] : await onTaskForId!(taskId);
  @override
  Future<List<Task>> allTasks({
    String group = 'default',
    bool includeTasksWaitingToRetry = true,
    bool allGroups = false,
  }) async =>
      active.values.where((task) => allGroups || task.group == group).toList();
  @override
  Future<bool> cancelTaskWithId(String taskId) async {
    canceled.add(taskId);
    final action = onCancel;
    if (action != null) return action(taskId);
    final task = active[taskId] ?? db.records[taskId]?.task;
    if (task != null) emit(task, TaskStatus.canceled);
    return true;
  }

  void emit(Task task, TaskStatus status) {
    if (status.isFinalState) active.remove(task.taskId);
    db.records[task.taskId] = TaskRecord(task, status, 0, 100);
    statusCallback?.call(TaskStatusUpdate(task, status));
  }
}
