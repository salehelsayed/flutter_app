import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/core/device/disk_space.dart';
import 'package:flutter_app/features/translate_preview/gemma_preview_prompts.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_core.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
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
    PersistentStorage? resumeStorage,
    Future<List<Directory>> Function()? partialDirectories,
    bool? isIOS,
    Duration cancellationTimeout = const Duration(seconds: 30),
    Future<String> Function(DownloadTask)? destinationPath,
  }) => BackgroundModelDeliveryTransport(
    downloader: downloader,
    resumeStorage: resumeStorage ?? _ResumeStorage(),
    partialDirectories: partialDirectories ?? () async => [destinations],
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
    'native reconnect waits for origin readiness and retains its partial offset',
    () async {
      final downloader = _Downloader();
      final transport = createTransport(downloader: downloader, isIOS: false);
      addTearDown(transport.dispose);
      await transport.initialize(null);
      await transport.enqueue(
        taskId: 'one',
        manifest: _manifest(),
        requiresWiFi: true,
      );
      final task = Task.createFromJson(downloader.enqueued.single.toJson());
      final partial = File('${destinations.path}/resume-partial');
      await partial.writeAsBytes(List.filled(80, 1));
      final origin = _RecoveringOrigin();
      var nativeEntries = 0;

      // The pinned runner enters resume before DNS is ready, loses the partial
      // on the failed attempt, then retries against the now-missing path.
      Future<int> nativeAttempt() async {
        final gate = await task.options?.beforeTaskStartCallBack?.call(task);
        if (gate != null) return -1;
        nativeEntries++;
        if (!origin.ready) {
          partial.deleteSync();
          origin.ready = true;
          return nativeAttempt();
        }
        return partial.existsSync() ? partial.lengthSync() : 0;
      }

      fakeAsync((clock) {
        int? resumedOffset;
        Object? error;
        HttpOverrides.runZoned(
          nativeAttempt,
          createHttpClient: (_) => _OriginClient(origin),
        ).then<void>(
          (offset) {
            resumedOffset = offset;
          },
          onError: (Object e) {
            error = e;
          },
        );
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 25));
        expect(error, isNull);
        expect(resumedOffset, 80);
        expect(partial.existsSync(), isTrue);
        expect(nativeEntries, 1);
        expect(origin.probes, greaterThanOrEqualTo(2));
      });
    },
  );

  test(
    'unready origin exhausts the full budget and pauses without native entry',
    () async {
      final downloader = _Downloader();
      final transport = createTransport(downloader: downloader, isIOS: false);
      addTearDown(transport.dispose);
      await transport.initialize(null);
      await transport.enqueue(
        taskId: 'one',
        manifest: _manifest(),
        requiresWiFi: true,
      );
      final task = downloader.enqueued.single;
      final partial = File('${destinations.path}/retained-partial');
      await partial.writeAsBytes(List.filled(80, 1));
      final origin = _RecoveringOrigin(recoverOnProbe: false);
      fakeAsync((clock) {
        var completed = false;
        TaskStatusUpdate? result;
        HttpOverrides.runZoned(
          () async => task.options?.beforeTaskStartCallBack?.call(task),
          createHttpClient: (_) => _OriginClient(origin),
        ).then((value) {
          result = value;
          completed = true;
        });
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 19));
        expect(completed, isFalse);
        expect(partial.lengthSync(), 80);
        clock.elapse(const Duration(seconds: 1));
        expect(completed, isTrue);
        expect(result?.status, TaskStatus.paused);
        expect(result?.task.taskId, task.taskId);
        expect(partial.lengthSync(), 80);
        expect(origin.closedClients, origin.probes);
      });
    },
  );

  test('unexpected IO setup errors pause instead of failing open', () async {
    final downloader = _Downloader();
    final transport = createTransport(downloader: downloader, isIOS: false);
    addTearDown(transport.dispose);
    await transport.initialize(null);
    await transport.enqueue(
      taskId: 'one',
      manifest: _manifest(),
      requiresWiFi: true,
    );
    final task = downloader.enqueued.single;
    final result = await HttpOverrides.runZoned(
      () async => task.options?.beforeTaskStartCallBack?.call(task),
      createHttpClient: (_) => throw StateError('IO setup failed'),
    );
    expect(result?.status, TaskStatus.paused);
  });

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
      expect(
        downloader.enqueued.single.options?.beforeTaskStartCallBack,
        isNull,
      );
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
    'legacy restored Android partial gains the gate on explicit resume',
    () async {
      final downloader = _Downloader();
      final task = _ownedTask('legacy');
      downloader.db.records[task.taskId] = TaskRecord(
        task,
        TaskStatus.paused,
        .8,
        100,
      );
      final transport = createTransport(downloader: downloader, isIOS: false);
      addTearDown(transport.dispose);
      await transport.initialize(task.taskId);
      expect(await transport.resume(task.taskId, requiresWiFi: true), isTrue);
      final resumed = downloader.resumed.single;
      expect(resumed.taskId, task.taskId);
      expect(resumed.requiresWiFi, isTrue);
      final origin = _RecoveringOrigin()..ready = true;
      final result = await HttpOverrides.runZoned(
        () async => resumed.options?.beforeTaskStartCallBack?.call(resumed),
        createHttpClient: (_) => _OriginClient(origin),
      );
      expect(result, isNull);
      expect(origin.probes, 1);
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
    'metadata-only cancellation removes only its mapped Android partial',
    () async {
      final downloader = _Downloader();
      final storage = _ResumeStorage();
      final task = _ownedTask('one');
      final partial = File(
        '${destinations.path}/com.bbflight.background_downloader-123',
      );
      final unrelated = File(
        '${destinations.path}/com.bbflight.background_downloader456',
      );
      await partial.writeAsBytes(List.filled(80, 1));
      await unrelated.writeAsString('another task');
      storage.records[task.taskId] = ResumeData(task, partial.path, 80);
      downloader.db.records[task.taskId] = TaskRecord(
        task,
        TaskStatus.paused,
        .8,
        100,
      );
      downloader.active[task.taskId] = task;
      final transport = createTransport(
        downloader: downloader,
        isIOS: false,
        resumeStorage: storage,
      );
      addTearDown(transport.dispose);
      await transport.initialize(task.taskId);
      downloader.onCancel = (id) async {
        storage.records.remove(id); // SDK clears metadata but leaves the file.
        downloader.emit(task, TaskStatus.canceled);
        return true;
      };
      await transport.cancel(task.taskId);
      await transport.forget(task.taskId);
      expect(await partial.exists(), isFalse);
      expect(await unrelated.readAsString(), 'another task');
    },
  );

  test(
    'Android canceled ACK precedes a mapped partial writer and recreation settles',
    () async {
      final downloader = _Downloader();
      final storage = _ResumeStorage();
      final task = _ownedTask('one');
      final partial = File(
        '${destinations.path}/com.bbflight.background_downloader321',
      );
      await partial.writeAsString('first partial');
      storage.records[task.taskId] = ResumeData(task, partial.path, 13);
      downloader.db.records[task.taskId] = TaskRecord(
        task,
        TaskStatus.running,
        .5,
        100,
      );
      downloader.active[task.taskId] = task;
      final transport = createTransport(
        downloader: downloader,
        resumeStorage: storage,
        isIOS: false,
      );
      addTearDown(transport.dispose);
      await transport.initialize(task.taskId);
      var acknowledged = false;
      var recreated = false;
      downloader.onCancel = (_) async {
        storage.records.clear();
        downloader.emit(task, TaskStatus.canceled);
        acknowledged = true;
        return true;
      };
      downloader.onTaskForId = (id) async {
        if (acknowledged && !recreated && !await partial.exists()) {
          expect(downloader.db.deleted, isEmpty);
          await partial.writeAsString('late partial writer');
          recreated = true;
        }
        return downloader.active[id];
      };
      await transport.cancel(task.taskId);
      expect(recreated, isTrue);
      expect(await partial.exists(), isFalse);
      await transport.forget(task.taskId);
      expect(downloader.db.deleted, [task.taskId]);
    },
  );

  test(
    'forget waits for an in-flight status snapshot before dropping ownership',
    () async {
      final downloader = _Downloader();
      final storage = _ResumeStorage();
      final transport = createTransport(
        downloader: downloader,
        resumeStorage: storage,
        isIOS: false,
      );
      addTearDown(transport.dispose);
      await transport.initialize(null);
      await transport.enqueue(
        taskId: 'one',
        manifest: _manifest(),
        requiresWiFi: true,
      );
      final task = downloader.enqueued.single;
      final partial = File(
        '${destinations.path}/com.bbflight.background_downloader654',
      );
      await partial.writeAsString('mapped partial');
      final started = Completer<void>();
      final snapshot = Completer<ResumeData?>();
      storage.onRetrieve = (_) {
        started.complete();
        return snapshot.future;
      };
      downloader.emit(task, TaskStatus.complete);
      await started.future;
      var forgotten = false;
      final forget = transport.forget(task.taskId).then((_) {
        forgotten = true;
      });
      await Future<void>.delayed(
        Duration.zero,
      ); // Drain already-queued microtasks.
      expect(forgotten, isFalse);
      expect(downloader.db.deleted, isEmpty);
      snapshot.complete(ResumeData(task, partial.path, 13));
      await forget;
      expect(forgotten, isTrue);
      expect(downloader.db.deleted, [task.taskId]);
    },
  );

  test(
    'remembered mapped partial survives SDK metadata loss until cleanup',
    () async {
      final downloader = _Downloader();
      final storage = _ResumeStorage();
      final task = _ownedTask('one');
      final partial = File(
        '${destinations.path}/com.bbflight.background_downloader123',
      );
      await partial.writeAsBytes(List.filled(80, 1));
      storage.records[task.taskId] = ResumeData(task, partial.path, 80);
      downloader.db.records[task.taskId] = TaskRecord(
        task,
        TaskStatus.waitingToRetry,
        -4,
        100,
      );
      final transport = createTransport(
        downloader: downloader,
        isIOS: false,
        resumeStorage: storage,
      );
      addTearDown(transport.dispose);
      await transport.initialize(task.taskId);
      storage.records.clear();
      downloader.emit(task, TaskStatus.failed);
      await transport.cancel(task.taskId);
      expect(await partial.exists(), isFalse);
    },
  );

  test(
    'cleanup rejects foreign tasks, outside roots, unsafe names and symlinks',
    () async {
      final outside = await Directory.systemTemp.createTemp(
        'translator-foreign-',
      );
      addTearDown(() => outside.delete(recursive: true));
      final downloader = _Downloader();
      final storage = _ResumeStorage();
      final task = _ownedTask('one');
      final foreign = File(
        '${outside.path}/com.bbflight.background_downloader123',
      );
      final plain = File('${destinations.path}/keep-me');
      final wrongTask = File(
        '${destinations.path}/com.bbflight.background_downloader456',
      );
      final link = Link(
        '${destinations.path}/com.bbflight.background_downloader789',
      );
      await foreign.writeAsString('outside');
      await plain.writeAsString('plain');
      await wrongTask.writeAsString('foreign task');
      await link.create(foreign.path);
      final transport = createTransport(
        downloader: downloader,
        isIOS: false,
        resumeStorage: storage,
      );
      addTearDown(transport.dispose);
      await transport.initialize(null);
      for (final resume in [
        ResumeData(task, foreign.path, 7),
        ResumeData(task, plain.path, 5),
        ResumeData(task.copyWith(group: 'smart_downloads'), wrongTask.path, 12),
        ResumeData(task.copyWith(taskId: 'other'), wrongTask.path, 12),
        ResumeData(task, link.path, 7),
      ]) {
        storage.records[task.taskId] = resume;
        downloader.db.records[task.taskId] = TaskRecord(
          task,
          TaskStatus.paused,
          .5,
          100,
        );
        downloader.active[task.taskId] = task;
        await transport.cancel(task.taskId);
        await transport.forget(task.taskId);
      }
      expect(await foreign.readAsString(), 'outside');
      expect(await plain.readAsString(), 'plain');
      expect(await wrongTask.readAsString(), 'foreign task');
      expect(await link.exists(), isTrue);
    },
  );

  test(
    'persisted file identity skips adapter hashing after restart and rejects changed bytes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      var hashes = 0;
      final storage = AppSupportModelDeliveryStorage(
        supportDirectory: () async => destinations,
        preferences: () async => preferences,
        diskSpace: DiskSpaceChannel(invoker: (_, _) async => 1000),
        excludeFromBackup: (_) async => true,
        removeModel: (delete) => delete(),
        hashFile: (path, expected) async {
          hashes++;
          final bytes = await File(path).readAsBytes();
          return bytes.length == expected.bytes &&
              sha256.convert(bytes).toString() == expected.sha256;
        },
      );
      await storage.prepare();
      final file = File(await storage.modelPath());
      final bytes = [1, 2, 3];
      await file.writeAsBytes(bytes);
      final manifest = _manifest(
        bytes: bytes.length,
        digest: sha256.convert(bytes).toString(),
      );
      await storage.saveRecord(
        ModelDeliveryRecord(
          manifest: manifest,
          taskId: 'one',
          phase: ModelDeliveryPhase.ready,
        ),
      );
      final active = <PersistentModelDeliveryController>[];
      addTearDown(() async {
        for (final controller in active) {
          await controller.dispose();
        }
      });
      PersistentModelDeliveryController controller() {
        final downloader = _Downloader();
        final task = _ownedTask('one').copyWith(url: manifest.url.toString());
        downloader.db.records[task.taskId] = TaskRecord(
          task,
          TaskStatus.complete,
          1,
          bytes.length,
        );
        final result = PersistentModelDeliveryController(
          storage: storage,
          network: _StorageTestNetwork(manifest),
          transport: createTransport(downloader: downloader, isIOS: true),
          appBuild: () async => 129,
          supported: true,
          spaceReserveBytes: 20,
        );
        active.add(result);
        return result;
      }

      final first = controller();
      await first.initialize();
      await _waitForState<ModelReady>(first);
      expect(hashes, 1);
      expect(
        (await storage.readRecord())!.verification!.identity.sizeBytes,
        bytes.length,
      );
      await first.dispose();
      active.remove(first);
      final restarted = controller();
      final states = <ModelDeliveryState>[];
      restarted.state.addListener(() => states.add(restarted.state.value));
      await restarted.initialize();
      expect(restarted.state.value, isA<ModelReady>());
      expect(states.whereType<ModelDownloading>(), isEmpty);
      expect(hashes, 1);
      await restarted.dispose();
      active.remove(restarted);
      await file.writeAsBytes([1, 2, 4]);
      await file.setLastModified(DateTime.fromMillisecondsSinceEpoch(1000));
      final changed = controller();
      await changed.initialize();
      await _waitForState<ModelNotDownloaded>(changed);
      expect(hashes, 2);
      expect(await file.exists(), isFalse);
      expect((await storage.readRecord())!.verification, isNull);
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
  Future<bool> get ready async => true;
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

class _RecoveringOrigin {
  _RecoveringOrigin({this.recoverOnProbe = true});
  final bool recoverOnProbe;
  bool ready = false;
  int probes = 0;
  int closedClients = 0;
}

class _OriginClient extends Fake implements HttpClient {
  _OriginClient(this.origin);
  final _RecoveringOrigin origin;
  @override
  Future<HttpClientRequest> headUrl(Uri url) async {
    expect(url.scheme, 'https');
    expect(url.host, 'updates.mknoon.xyz');
    return _OriginRequest(origin);
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    expect(method, 'HEAD');
    return headUrl(url);
  }

  @override
  void close({bool force = false}) {
    expect(force, isTrue);
    origin.closedClients++;
  }
}

class _OriginRequest extends Fake implements HttpClientRequest {
  _OriginRequest(this.origin);
  final _RecoveringOrigin origin;
  @override
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() async {
    expect(followRedirects, isFalse);
    origin.probes++;
    if (!origin.ready) {
      origin.ready = origin.recoverOnProbe;
      throw const SocketException('Host lookup not ready');
    }
    return _OriginResponse();
  }
}

class _OriginResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;
  @override
  Future<E> drain<E>([E? futureValue]) =>
      const Stream<List<int>>.empty().drain<E>(futureValue);
}

class _ResumeStorage extends Fake implements PersistentStorage {
  final records = <String, ResumeData>{};
  Future<ResumeData?> Function(String)? onRetrieve;
  @override
  Future<void> initialize() async {}
  @override
  Future<ResumeData?> retrieveResumeData(String taskId) async =>
      onRetrieve == null ? records[taskId] : await onRetrieve!(taskId);
}

Future<void> _waitForState<T extends ModelDeliveryState>(
  PersistentModelDeliveryController controller,
) {
  if (controller.state.value is T) return Future<void>.value();
  final complete = Completer<void>();
  void changed() {
    if (controller.state.value is T) {
      controller.state.removeListener(changed);
      complete.complete();
    }
  }

  controller.state.addListener(changed);
  return complete.future.timeout(const Duration(seconds: 3));
}

class _StorageTestNetwork implements ModelDeliveryNetwork {
  _StorageTestNetwork(this.manifest);
  final ModelDeliveryManifest manifest;
  @override
  Future<Map<String, Object?>> fetchManifest() async => manifest.toJson();
  @override
  Future<bool> checkWifi() async => true;
  @override
  Stream<bool> get wifiChanges => const Stream<bool>.empty();
}
