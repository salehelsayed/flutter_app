import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_core.dart';
import 'package:flutter_test/flutter_test.dart';

final _manifest = ModelDeliveryManifest.fromJson({
  'model': 'gemma-4-E2B-it',
  'url':
      'https://updates.mknoon.xyz/models/gemma-4-E2B-it-${'a' * 12}.litertlm',
  'bytes': 100,
  'sha256': 'a' * 64,
  'minAppBuild': 129,
});

void main() {
  test(
    'unsupported capability never enqueues; consent alone is not opt-in',
    () async {
      final h = await _Harness.create(supported: false);
      addTearDown(h.dispose);
      await h.controller.start(allowMobileData: true);
      expect(h.controller.state.value, isA<ModelUnsupported>());
      expect(h.network.fetches, 0);
      expect(h.transport.enqueues, isEmpty);
      h.controller.setCapability(true);
      await h.flush();
      expect(h.controller.state.value, isA<ModelNotDownloaded>());
      expect(h.controller.allowMobileData.value, isTrue);
      expect(h.storage.record!.allowMobileData, isTrue);
      expect(h.transport.enqueues, isEmpty);
    },
  );

  test(
    'initial admission is low space and read-only refresh sees freed bytes',
    () async {
      final h = await _Harness.create(freeBytes: 50);
      addTearDown(h.dispose);
      final low = h.controller.state.value as ModelNotEnoughSpace;
      expect(low.neededBytes, 120);
      expect(low.freeBytes, 50);
      h.storage.freeBytes = 200;
      await h.controller.refresh();
      expect(h.controller.state.value, isA<ModelNotDownloaded>());
      expect(h.transport.enqueues, isEmpty);
      h.storage.freeBytes = 10;
      await h.controller.refresh();
      expect(h.controller.state.value, isA<ModelNotEnoughSpace>());
      final prior = h.controller.state.value;
      h.network.wifi = false;
      h.storage.failFreeMeasurement = true;
      await h.controller.refresh();
      expect(h.controller.state.value, same(prior));
      expect(h.transport.enqueues, isEmpty);
    },
  );

  test(
    'default Wi-Fi waiting retains progress and native Wi-Fi enforcement',
    () async {
      final h = await _Harness.create(wifi: false);
      addTearDown(h.dispose);
      await h.controller.start(allowMobileData: false);
      expect(h.transport.enqueues.single.requiresWiFi, isTrue);
      expect(h.controller.state.value, isA<ModelWaitingForWifi>());
      await h.event(ModelTransferStatus.running, bytes: 35);
      expect(
        (h.controller.state.value as ModelWaitingForWifi).receivedBytes,
        35,
      );
      h.network.changeWifi(true);
      await h.flush();
      expect((h.controller.state.value as ModelDownloading).receivedBytes, 35);
      h.storage.freeBytes = 0;
      await h.controller.refresh();
      expect(h.controller.state.value, isA<ModelDownloading>());
    },
  );

  test(
    'mobile opt-in is persisted without starting on initialization or toggle',
    () async {
      final h = await _Harness.create(wifi: false);
      addTearDown(h.dispose);
      await h.controller.setAllowMobileData(true);
      expect(h.transport.enqueues, isEmpty);
      await h.controller.start(allowMobileData: true);
      expect(h.transport.enqueues.single.requiresWiFi, isFalse);
      expect(h.controller.state.value, isA<ModelDownloading>());
      final restored = await _Harness.create(
        record: h.storage.record,
        wifi: false,
      );
      addTearDown(restored.dispose);
      expect(restored.controller.allowMobileData.value, isTrue);
      expect(restored.transport.enqueues, isEmpty);
      expect(restored.transport.resumes, isEmpty);
    },
  );

  test(
    'pause and resume acknowledgements wait for their native callbacks',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      await h.controller.start(allowMobileData: false);
      await h.event(ModelTransferStatus.running, bytes: 40);
      await h.controller.pause();
      expect(h.transport.pauses, [h.id]);
      expect(h.controller.state.value, isA<ModelDownloading>());
      await h.event(ModelTransferStatus.paused, bytes: 40);
      expect((h.controller.state.value as ModelPaused).receivedBytes, 40);
      await h.controller.resume();
      expect(h.transport.resumes.single.requiresWiFi, isTrue);
      expect(h.controller.state.value, isA<ModelPaused>());
      await h.event(ModelTransferStatus.running, bytes: 45);
      expect((h.controller.state.value as ModelDownloading).receivedBytes, 45);
    },
  );

  test(
    'revoking mobile consent during delayed resume reconfigures before running',
    () async {
      final h = await _Harness.create(wifi: false);
      addTearDown(h.dispose);
      await h.controller.start(allowMobileData: true);
      await h.event(ModelTransferStatus.running, bytes: 40);
      await h.controller.pause();
      await h.event(ModelTransferStatus.paused, bytes: 40);
      await h.controller.resume();
      expect(h.transport.resumes.single.requiresWiFi, isFalse);
      expect(h.controller.state.value, isA<ModelPaused>());
      await h.controller.setAllowMobileData(false);
      expect(h.transport.pauses, [h.id, h.id]);
      // The old resume acknowledgement arrives after consent was revoked.
      await h.event(ModelTransferStatus.running, bytes: 41);
      await h.event(ModelTransferStatus.paused, bytes: 41);
      expect(h.transport.resumes.last.requiresWiFi, isTrue);
      expect(h.controller.allowMobileData.value, isFalse);
      expect(h.controller.state.value, isA<ModelWaitingForWifi>());
    },
  );

  test(
    'revoking active mobile consent pauses before aligned native resume',
    () async {
      final h = await _Harness.create(wifi: false);
      addTearDown(h.dispose);
      await h.controller.start(allowMobileData: true);
      await h.event(ModelTransferStatus.running, bytes: 30);
      await h.controller.setAllowMobileData(false);
      expect(h.transport.pauses, [h.id]);
      expect(h.transport.resumes, isEmpty);
      await h.event(ModelTransferStatus.paused, bytes: 30);
      expect(h.transport.resumes.single.requiresWiFi, isTrue);
      expect(h.controller.state.value, isA<ModelWaitingForWifi>());
      await h.event(ModelTransferStatus.running);
      await h.controller.pause();
      await h.event(ModelTransferStatus.paused);
      final resumeCount = h.transport.resumes.length;
      await h.controller.setAllowMobileData(true);
      expect(h.controller.state.value, isA<ModelPaused>());
      expect(h.transport.resumes, hasLength(resumeCount));
    },
  );

  test(
    'policy resume rejection restarts only owned task and rechecks full space',
    () async {
      final h = await _Harness.create(wifi: false);
      addTearDown(h.dispose);
      await h.controller.start(allowMobileData: true);
      final oldId = h.id;
      await h.event(ModelTransferStatus.running, bytes: 80);
      h.storage.freeBytes =
          60; // enough for partial, insufficient for a fresh file
      h.transport.resumeAccepted = false;
      await h.controller.setAllowMobileData(false);
      await h.event(ModelTransferStatus.paused, bytes: 80);
      expect(h.transport.cancels, [oldId]);
      expect(h.transport.forgets, [oldId]);
      expect(h.storage.removals, 1);
      expect(h.transport.enqueues, hasLength(1));
      expect(
        (h.controller.state.value as ModelNotEnoughSpace).neededBytes,
        120,
      );
      h.storage.freeBytes = 200;
      await h.controller.retry();
      expect(h.transport.enqueues, hasLength(2));
      expect(h.transport.enqueues.last.requiresWiFi, isTrue);
      expect(h.id, isNot(oldId));
    },
  );

  test(
    'silent native retries preserve progress; exhausted failure is retryable',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      await h.controller.start(allowMobileData: false);
      final oldId = h.id;
      await h.event(ModelTransferStatus.waitingToRetry, bytes: 30);
      expect((h.controller.state.value as ModelDownloading).receivedBytes, 30);
      await h.event(ModelTransferStatus.failed);
      expect(h.controller.state.value, isA<ModelFailed>());
      await h.controller.retry();
      expect(h.transport.cancels, [oldId]);
      expect(h.transport.enqueues, hasLength(2));
      expect(h.id, isNot(oldId));
    },
  );

  test(
    'cold start reuses a verified unchanged file without another full hash',
    () async {
      final first = await _Harness.create();
      await first.controller.start(allowMobileData: false);
      final firstReady = _nextState<ModelReady>(first.controller.state);
      await first.event(ModelTransferStatus.complete);
      await firstReady;
      expect(first.storage.verifications, 1);
      final storage = first.storage;
      final taskId = first.id;
      await first.dispose();

      final network = _Network();
      final transport = _Transport()
        ..restored = ModelTransferSnapshot(
          taskId: taskId,
          status: ModelTransferStatus.complete,
          receivedBytes: 100,
        );
      final controller = PersistentModelDeliveryController(
        storage: storage,
        network: network,
        transport: transport,
        appBuild: () async => 129,
        supported: true,
        spaceReserveBytes: 20,
      );
      final restarted = _Harness(controller, storage, network, transport);
      addTearDown(restarted.dispose);
      await controller.initialize();
      await _nextState<ModelReady>(controller.state);
      expect(await controller.verifiedModelPath(), '/owned/gemma.litertlm');
      expect(storage.verifications, 1);
      expect(transport.enqueues, isEmpty);
      expect(transport.resumes, isEmpty);
    },
  );

  test(
    'completion stays downloading until size/checksum verification succeeds',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      await h.controller.start(allowMobileData: false);
      h.storage.verification = Completer<bool>();
      await h.event(ModelTransferStatus.complete);
      expect((h.controller.state.value as ModelDownloading).receivedBytes, 100);
      await expectLater(h.controller.verifiedModelPath(), throwsStateError);
      final ready = _nextState<ModelReady>(h.controller.state);
      h.storage.verification!.complete(true);
      await ready;
      expect(await h.controller.verifiedModelPath(), '/owned/gemma.litertlm');
      final prior = h.controller.state.value;
      h.storage.freeBytes = 0;
      await h.controller.refresh();
      expect(h.controller.state.value, same(prior));
    },
  );

  test(
    'restoring capability reverifies Ready before restoring its path',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      await h.controller.start(allowMobileData: false);
      final initialReady = _nextState<ModelReady>(h.controller.state);
      await h.event(ModelTransferStatus.complete);
      await initialReady;
      expect(await h.controller.verifiedModelPath(), '/owned/gemma.litertlm');
      h.controller.setCapability(false);
      await h.flush();
      expect(h.controller.state.value, isA<ModelUnsupported>());
      await expectLater(h.controller.verifiedModelPath(), throwsStateError);
      h.storage.verification = Completer<bool>();
      h.controller.setCapability(true);
      await h.flush();
      expect(h.controller.state.value, isA<ModelDownloading>());
      await expectLater(h.controller.verifiedModelPath(), throwsStateError);
      final ready = _nextState<ModelReady>(h.controller.state);
      h.storage.verification!.complete(true);
      await ready;
      expect(h.storage.verifications, 2);
      expect(await h.controller.verifiedModelPath(), '/owned/gemma.litertlm');
      expect(h.transport.enqueues, hasLength(1));
    },
  );

  test(
    'checksum mismatch removes owned file and cannot become Ready',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      await h.controller.start(allowMobileData: false);
      h.storage.valid = false;
      final failed = _nextState<ModelFailed>(h.controller.state);
      await h.event(ModelTransferStatus.complete);
      await failed;
      expect(h.storage.removals, 1);
      expect(h.transport.forgets, [h.transport.enqueues.single.taskId]);
      await expectLater(h.controller.verifiedModelPath(), throwsStateError);
    },
  );

  test(
    'backup exclusion failure blocks both enqueue and restored readiness',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.storage.failPrepare = true;
      await h.controller.start(allowMobileData: false);
      expect(h.controller.state.value, isA<ModelFailed>());
      expect(h.transport.enqueues, isEmpty);
      final restored = await _Harness.create(
        record: ModelDeliveryRecord(
          manifest: _manifest,
          taskId: 'old',
          phase: ModelDeliveryPhase.ready,
        ),
        restoredStatus: ModelTransferStatus.complete,
        failPrepare: true,
      );
      addTearDown(restored.dispose);
      expect(restored.controller.state.value, isA<ModelFailed>());
      expect(restored.storage.verifications, 0);
    },
  );

  test(
    'offline cached manifest and DB partial survive restart without auto resume',
    () async {
      final h = await _Harness.create(
        record: ModelDeliveryRecord(
          manifest: _manifest,
          taskId: 'old',
          phase: ModelDeliveryPhase.active,
        ),
        restoredStatus: ModelTransferStatus.paused,
        restoredBytes: 80,
        freeBytes: 50,
      );
      addTearDown(h.dispose);
      expect((h.controller.state.value as ModelPaused).receivedBytes, 80);
      expect(h.transport.enqueues, isEmpty);
      expect(h.transport.resumes, isEmpty);
      h.network.failFetch = true;
      await h.controller.resume();
      expect(h.transport.resumes.single.taskId, 'old');
      expect(h.transport.enqueues, isEmpty);
      await h.event(ModelTransferStatus.running, bytes: 80);
      expect(h.controller.state.value, isA<ModelDownloading>());
    },
  );

  test(
    'a persisted native complete is reverified rather than trusted',
    () async {
      final verification = Completer<bool>();
      final h = await _Harness.create(
        record: ModelDeliveryRecord(
          manifest: _manifest,
          taskId: 'old',
          phase: ModelDeliveryPhase.ready,
        ),
        restoredStatus: ModelTransferStatus.complete,
        verification: verification,
      );
      addTearDown(h.dispose);
      expect(h.controller.state.value, isA<ModelDownloading>());
      await expectLater(h.controller.verifiedModelPath(), throwsStateError);
      final failed = _nextState<ModelFailed>(h.controller.state);
      verification.complete(false);
      await failed;
      expect(h.storage.removals, 1);
    },
  );

  test(
    'remove invalidates hash and stale callbacks; resolver never joins owner queue',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      await h.controller.start(allowMobileData: false);
      final oldId = h.id;
      h.storage.verification = Completer<bool>();
      await h.event(ModelTransferStatus.complete);
      h.storage.onRemove = () async {
        await expectLater(h.controller.verifiedModelPath(), throwsStateError);
      };
      await h.controller.remove();
      expect(h.controller.state.value, isA<ModelNotDownloaded>());
      expect(h.transport.cancels, [oldId]);
      expect(h.transport.forgets, [oldId]);
      h.storage.verification!.complete(true);
      await h.flush();
      expect(h.controller.state.value, isA<ModelNotDownloaded>());
      await h.controller.start(allowMobileData: false);
      final newId = h.id;
      await h.event(ModelTransferStatus.complete, taskId: oldId);
      expect(h.id, newId);
      expect(h.controller.state.value, isA<ModelDownloading>());
      expect(h.storage.verifications, 1);
    },
  );

  test(
    'pause during verification prevents late Ready and explicit resume reverifies',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      await h.controller.start(allowMobileData: false);
      h.storage.verification = Completer<bool>();
      await h.event(ModelTransferStatus.complete);
      await h.controller.pause();
      expect(h.controller.state.value, isA<ModelPaused>());
      h.storage.verification!.complete(true);
      await h.flush();
      expect(h.controller.state.value, isA<ModelPaused>());
      h.storage.length = 100;
      h.storage.verification = null;
      final ready = _nextState<ModelReady>(h.controller.state);
      await h.controller.resume();
      await ready;
      expect(h.transport.enqueues, hasLength(1));
    },
  );

  test(
    'failed cancellation retains removing record and never deletes bytes',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      await h.controller.start(allowMobileData: false);
      h.transport.failCancel = true;
      await h.controller.remove();
      expect(h.controller.state.value, isA<ModelFailed>());
      expect(h.storage.record!.phase, ModelDeliveryPhase.removing);
      expect(h.storage.removals, 0);
      expect(h.transport.forgets, isEmpty);
      h.transport.failCancel = false;
      await h.controller.retry();
      expect(h.storage.removals, 1);
      expect(h.controller.state.value, isA<ModelNotDownloaded>());
    },
  );

  test(
    'persisted removal finishes only the owned task during recovery',
    () async {
      final h = await _Harness.create(
        record: ModelDeliveryRecord(
          manifest: _manifest,
          taskId: 'old',
          phase: ModelDeliveryPhase.removing,
        ),
      );
      addTearDown(h.dispose);
      expect(h.transport.cancels, ['old']);
      expect(h.storage.removals, 1);
      expect(h.controller.state.value, isA<ModelNotDownloaded>());
      expect(h.transport.enqueues, isEmpty);
    },
  );

  test('wrong model, insecure URL and invalid digest cannot enqueue', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    for (final change in <Map<String, Object?>>[
      {'model': 'other'},
      {'url': 'http://updates.mknoon.xyz/model'},
      {'sha256': 'invalid'},
      {'bytes': -1},
    ]) {
      h.network.manifest = {..._manifest.toJson(), ...change};
      await h.controller.start(allowMobileData: false);
      expect(h.controller.state.value, isA<ModelFailed>());
    }
    expect(h.transport.enqueues, isEmpty);
  });

  test(
    'manifest build floor projects Unsupported without a native task',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.network.manifest = {..._manifest.toJson(), 'minAppBuild': 130};
      await h.controller.start(allowMobileData: false);
      expect(h.controller.state.value, isA<ModelUnsupported>());
      expect(h.transport.enqueues, isEmpty);
    },
  );

  test(
    'persistent record round trips consent, manifest and partial identity',
    () {
      final record = ModelDeliveryRecord(
        manifest: _manifest,
        taskId: 'one',
        receivedBytes: 42,
        phase: ModelDeliveryPhase.userPaused,
        allowMobileData: true,
      );
      final restored = ModelDeliveryRecord.fromJson(record.toJson());
      expect(restored.taskId, 'one');
      expect(restored.receivedBytes, 42);
      expect(restored.phase, ModelDeliveryPhase.userPaused);
      expect(restored.manifest!.sha256, _manifest.sha256);
      expect(restored.allowMobileData, isTrue);
    },
  );
}

Future<T> _nextState<T extends ModelDeliveryState>(
  ValueListenable<ModelDeliveryState> state,
) {
  if (state.value is T) return Future.value(state.value as T);
  final completer = Completer<T>();
  void listener() {
    if (state.value is T && !completer.isCompleted) {
      state.removeListener(listener);
      completer.complete(state.value as T);
    }
  }

  state.addListener(listener);
  return completer.future.timeout(
    const Duration(seconds: 3),
    onTimeout: () {
      state.removeListener(listener);
      throw StateError('Expected $T, got ${state.value.runtimeType}');
    },
  );
}

class _Harness {
  _Harness(this.controller, this.storage, this.network, this.transport);
  final PersistentModelDeliveryController controller;
  final _Storage storage;
  final _Network network;
  final _Transport transport;

  static Future<_Harness> create({
    bool supported = true,
    bool wifi = true,
    int freeBytes = 1000,
    ModelDeliveryRecord? record,
    ModelTransferStatus? restoredStatus,
    int restoredBytes = 0,
    bool failPrepare = false,
    Completer<bool>? verification,
  }) async {
    final storage = _Storage()
      ..record = record ?? ModelDeliveryRecord(manifest: _manifest)
      ..freeBytes = freeBytes
      ..failPrepare = failPrepare
      ..verification = verification;
    final network = _Network()..wifi = wifi;
    final transport = _Transport();
    if (restoredStatus != null) {
      transport.restored = ModelTransferSnapshot(
        taskId: record!.taskId!,
        status: restoredStatus,
        receivedBytes: restoredBytes,
      );
    }
    var next = 0;
    final controller = PersistentModelDeliveryController(
      storage: storage,
      network: network,
      transport: transport,
      appBuild: () async => 129,
      supported: supported,
      spaceReserveBytes: 20,
      newTaskId: () => 'task-${++next}',
    );
    await controller.initialize();
    return _Harness(controller, storage, network, transport);
  }

  String get id => storage.record!.taskId!;
  Future<void> flush() =>
      controller.setAllowMobileData(controller.allowMobileData.value);
  Future<void> event(
    ModelTransferStatus status, {
    int? bytes,
    String? taskId,
  }) async {
    transport.eventsController.add(
      ModelTransferEvent(
        taskId: taskId ?? id,
        status: status,
        receivedBytes: bytes,
      ),
    );
    await flush();
  }

  Future<void> dispose() async {
    await controller.dispose();
    await network.changes.close();
  }
}

class _Storage implements ModelDeliveryStorage {
  ModelDeliveryRecord? record;
  int freeBytes = 1000;
  int? length;
  bool valid = true;
  bool failPrepare = false;
  bool failFreeMeasurement = false;
  int removals = 0;
  int verifications = 0;
  Completer<bool>? verification;
  Future<void> Function()? onRemove;
  @override
  Future<ModelDeliveryRecord?> readRecord() async => record;
  @override
  Future<void> saveRecord(ModelDeliveryRecord value) async {
    record = value;
  }

  @override
  Future<void> prepare() async {
    if (failPrepare) throw StateError('backup failure');
  }

  @override
  Future<int> availableBytes() async {
    if (failFreeMeasurement) throw StateError('measurement failure');
    return freeBytes;
  }

  @override
  Future<int?> modelLength() async => length;
  @override
  Future<bool> verify(ModelDeliveryManifest manifest) async {
    verifications++;
    return verification?.future ?? valid;
  }

  @override
  Future<String> modelPath() async => '/owned/gemma.litertlm';
  @override
  Future<void> removeOwnedModel() async {
    await onRemove?.call();
    removals++;
    length = null;
  }
}

class _Network implements ModelDeliveryNetwork {
  bool wifi = true;
  bool failFetch = false;
  int fetches = 0;
  Map<String, Object?> manifest = _manifest.toJson();
  final changes = StreamController<bool>.broadcast(sync: true);
  @override
  Stream<bool> get wifiChanges => changes.stream;
  @override
  Future<bool> checkWifi() async => wifi;
  @override
  Future<Map<String, Object?>> fetchManifest() async {
    fetches++;
    if (failFetch) throw StateError('offline');
    return manifest;
  }

  void changeWifi(bool value) {
    wifi = value;
    changes.add(value);
  }
}

class _Transport implements ModelDeliveryTransport {
  final eventsController = StreamController<ModelTransferEvent>.broadcast(
    sync: true,
  );
  final enqueues = <({String taskId, bool requiresWiFi})>[];
  final resumes = <({String taskId, bool requiresWiFi})>[];
  final pauses = <String>[];
  final cancels = <String>[];
  final forgets = <String>[];
  bool resumeAccepted = true;
  bool failCancel = false;
  ModelTransferSnapshot? restored;
  @override
  Stream<ModelTransferEvent> get events => eventsController.stream;
  @override
  Future<void> initialize(String? ownedTaskId) async {}
  @override
  Future<ModelTransferSnapshot?> restore(String taskId) async => restored;
  @override
  Future<bool> enqueue({
    required String taskId,
    required ModelDeliveryManifest manifest,
    required bool requiresWiFi,
  }) async {
    enqueues.add((taskId: taskId, requiresWiFi: requiresWiFi));
    return true;
  }

  @override
  Future<bool> pause(String taskId) async {
    pauses.add(taskId);
    return true;
  }

  @override
  Future<bool> resume(String taskId, {required bool requiresWiFi}) async {
    resumes.add((taskId: taskId, requiresWiFi: requiresWiFi));
    return resumeAccepted;
  }

  @override
  Future<void> cancel(String taskId) async {
    cancels.add(taskId);
    if (failCancel) throw StateError('cancellation rejected');
  }

  @override
  Future<void> forget(String taskId) async {
    forgets.add(taskId);
  }

  @override
  Future<void> dispose() => eventsController.close();
}
