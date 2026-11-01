import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/features/translate_preview/gemma_preview_service.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_core.dart';
import 'package:flutter_app/features/translate_preview/translation_capability.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:flutter_test/flutter_test.dart';

final _manifest = ModelDeliveryManifest.fromJson({
  'model': 'gemma-4-E2B-it',
  'url':
      'https://updates.mknoon.xyz/models/gemma-4-E2B-it-${'a' * 12}.litertlm',
  'bytes': 100,
  'sha256': 'a' * 64,
  'minAppBuild': 129,
});

ModelDeliveryFileIdentity _fileIdentity({
  int size = 100,
  int modified = 1,
  int changed = 1,
}) => ModelDeliveryFileIdentity(
  canonicalPath: '/owned/gemma.litertlm',
  sizeBytes: size,
  modifiedMicros: modified,
  changedMicros: changed,
);

ModelDeliveryRecord _verifiedRecord() => ModelDeliveryRecord(
  manifest: _manifest,
  taskId: 'verified',
  phase: ModelDeliveryPhase.ready,
  receivedBytes: 100,
  verification: ModelDeliveryVerification(
    expectedSha256: _manifest.sha256,
    identity: _fileIdentity(),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
    'mobile consent switch replaces a never-started Wi-Fi task without waiting for pause',
    () async {
      final h = await _Harness.create(wifi: false);
      addTearDown(h.dispose);
      await h.controller.start(allowMobileData: false);
      await h.event(ModelTransferStatus.enqueued, bytes: 0);
      final oldId = h.id;
      expect(h.controller.state.value, isA<ModelWaitingForWifi>());
      await h.controller.setAllowMobileData(true);
      expect(h.transport.enqueues, hasLength(2));
      expect(h.transport.enqueues.last.requiresWiFi, isFalse);
      expect(h.transport.cancels, [oldId]);
      expect(h.transport.forgets, [oldId]);
      expect(h.transport.pauses, isEmpty);
      expect(h.transport.peakOwnedTasks, 1);
      expect(h.transport.ownedTasks, {h.id});
      expect(h.id, isNot(oldId));
      await h.event(ModelTransferStatus.paused, taskId: oldId);
      expect(h.controller.state.value, isA<ModelDownloading>());
    },
  );

  test(
    'explicit mobile start replaces a never-started Wi-Fi task without waiting for pause',
    () async {
      final h = await _Harness.create(wifi: false);
      addTearDown(h.dispose);
      await h.controller.start(allowMobileData: false);
      await h.event(ModelTransferStatus.enqueued, bytes: 0);
      final oldId = h.id;
      await h.controller.start(allowMobileData: true);
      expect(h.transport.enqueues, hasLength(2));
      expect(h.transport.enqueues.last.requiresWiFi, isFalse);
      expect(h.transport.cancels, [oldId]);
      expect(h.transport.forgets, [oldId]);
      expect(h.transport.pauses, isEmpty);
      expect(h.transport.peakOwnedTasks, 1);
      expect(h.transport.ownedTasks, {h.id});
      expect(h.id, isNot(oldId));
      expect(h.controller.state.value, isA<ModelDownloading>());
    },
  );

  test(
    'queued mobile replacement waits for owned cancellation settlement',
    () async {
      final h = await _Harness.create(wifi: false);
      addTearDown(h.dispose);
      await h.controller.start(allowMobileData: false);
      await h.event(ModelTransferStatus.enqueued, bytes: 0);
      final oldId = h.id;
      h.transport.cancellationStarted = Completer<void>();
      h.transport.cancellation = Completer<void>();
      final replace = h.controller.setAllowMobileData(true);
      await h.transport.cancellationStarted!.future;
      expect(h.transport.enqueues, hasLength(1));
      expect(h.transport.ownedTasks, {oldId});
      expect(h.transport.forgets, isEmpty);
      expect(h.storage.removals, 0);
      h.transport.cancellation!.complete();
      await replace;
      expect(h.transport.enqueues, hasLength(2));
      expect(h.transport.enqueues.last.requiresWiFi, isFalse);
      expect(h.transport.peakOwnedTasks, 1);
      expect(h.transport.ownedTasks, {h.id});
      expect(h.id, isNot(oldId));
    },
  );

  test(
    'queued mobile replacement cannot enqueue when owned cancellation fails',
    () async {
      final h = await _Harness.create(wifi: false);
      addTearDown(h.dispose);
      await h.controller.start(allowMobileData: false);
      await h.event(ModelTransferStatus.enqueued, bytes: 0);
      final oldId = h.id;
      h.transport.failCancel = true;
      await h.controller.setAllowMobileData(true);
      expect(h.controller.state.value, isA<ModelFailed>());
      expect(h.transport.enqueues, hasLength(1));
      expect(h.transport.ownedTasks, {oldId});
      expect(h.transport.forgets, isEmpty);
      expect(h.storage.removals, 0);
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
      storage.record = ModelDeliveryRecord.fromJson(storage.record!.toJson());
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
      final states = <ModelDeliveryState>[];
      controller.state.addListener(() => states.add(controller.state.value));
      await controller.initialize();
      expect(controller.state.value, isA<ModelReady>());
      expect(states.whereType<ModelDownloading>(), isEmpty);
      expect(await controller.verifiedModelPath(), '/owned/gemma.litertlm');
      expect(storage.verifications, 1);
      expect(transport.enqueues, isEmpty);
      expect(transport.resumes, isEmpty);
    },
  );

  test(
    'legacy Ready record is verified once before a cache stamp is saved',
    () async {
      final verification = Completer<bool>();
      final h = await _Harness.create(
        record: _verifiedRecord().copyWith(clearVerification: true),
        verification: verification,
      );
      addTearDown(h.dispose);
      expect(h.controller.state.value, isA<ModelDownloading>());
      final ready = _nextState<ModelReady>(h.controller.state);
      verification.complete(true);
      await ready;
      expect(h.storage.verifications, 1);
      expect(h.storage.record!.verification!.identity, _fileIdentity());
    },
  );

  for (final identity in [
    _fileIdentity(modified: 2),
    _fileIdentity(changed: 2),
  ]) {
    test(
      'changed file identity ${identity.modifiedMicros}/${identity.changedMicros} forces a fresh hash',
      () async {
        final verification = Completer<bool>();
        final h = await _Harness.create(
          record: _verifiedRecord(),
          identity: identity,
          verification: verification,
        );
        addTearDown(h.dispose);
        expect(h.controller.state.value, isA<ModelDownloading>());
        final ready = _nextState<ModelReady>(h.controller.state);
        verification.complete(true);
        await ready;
        expect(h.storage.verifications, 1);
        expect(h.storage.record!.verification!.identity, identity);
      },
    );
  }

  test(
    'changed file size is reverified and removed rather than restored as Ready',
    () async {
      final h = await _Harness.create(
        record: _verifiedRecord(),
        identity: _fileIdentity(size: 99),
      );
      addTearDown(h.dispose);
      await _nextState<ModelNotDownloaded>(h.controller.state);
      expect(h.storage.verifications, 1);
      expect(h.storage.removals, 1);
      expect(h.storage.record!.verification, isNull);
      expect(h.storage.record!.taskId, isNull);
    },
  );

  test(
    'manifest digest change invalidates a matching file identity stamp',
    () async {
      final verification = Completer<bool>();
      final record = _verifiedRecord().copyWith(
        verification: ModelDeliveryVerification(
          expectedSha256: 'b' * 64,
          identity: _fileIdentity(),
        ),
      );
      final h = await _Harness.create(
        record: record,
        verification: verification,
      );
      addTearDown(h.dispose);
      expect(h.controller.state.value, isA<ModelDownloading>());
      final ready = _nextState<ModelReady>(h.controller.state);
      verification.complete(true);
      await ready;
      expect(h.storage.verifications, 1);
      expect(h.storage.record!.verification!.expectedSha256, _manifest.sha256);
    },
  );

  test(
    'file changed during a successful hash cannot publish a stale verification',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      await h.controller.start(allowMobileData: false);
      h.storage.verification = Completer<bool>();
      h.storage.verificationStarted = Completer<void>();
      final offer = _nextState<ModelNotDownloaded>(h.controller.state);
      await h.event(ModelTransferStatus.complete);
      await h.storage.verificationStarted!.future;
      h.storage.identity = _fileIdentity(changed: 2);
      h.storage.verification!.complete(true);
      await offer;
      expect(h.storage.removals, 1);
      expect(h.storage.record!.verification, isNull);
      await expectLater(h.controller.verifiedModelPath(), throwsStateError);
    },
  );

  test(
    'malformed optional verification stamp preserves task manifest and consent',
    () {
      final original = _verifiedRecord().copyWith(allowMobileData: true);
      for (final malformed in <Object?>[
        null,
        7,
        {'expectedSha256': 'invalid'},
        {
          'expectedSha256': _manifest.sha256,
          'identity': {..._fileIdentity().toJson(), 'sizeBytes': '100'},
        },
      ]) {
        final restored = ModelDeliveryRecord.fromJson({
          ...original.toJson(),
          'verification': malformed,
        });
        expect(restored.verification, isNull);
        expect(restored.taskId, original.taskId);
        expect(restored.manifest!.sha256, _manifest.sha256);
        expect(restored.allowMobileData, isTrue);
        expect(restored.phase, ModelDeliveryPhase.ready);
      }
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
    'restoring capability reuses an unchanged verified file and restores its path',
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
      final ready = _nextState<ModelReady>(h.controller.state);
      h.controller.setCapability(true);
      await h.flush();
      await ready;
      expect(h.storage.verifications, 1);
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
      final offer = _nextState<ModelNotDownloaded>(h.controller.state);
      await h.event(ModelTransferStatus.complete);
      await offer;
      expect(h.storage.removals, 1);
      expect(h.transport.forgets, [h.transport.enqueues.single.taskId]);
      expect(h.storage.record!.verification, isNull);
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
      final offer = _nextState<ModelNotDownloaded>(h.controller.state);
      verification.complete(false);
      await offer;
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

  group('inference memory safety', () {
    test('safety record round trips independent of download metadata', () {
      for (final reason in ModelBlockedReason.values) {
        final restored = ModelSafetyRecord.fromJson(
          ModelSafetyRecord(
            blockedReason: reason,
            inferenceInProgress: true,
            consecutiveInterruptions: 2,
            noticePending: true,
          ).toJson(),
        );
        expect(restored.blockedReason, reason);
        expect(restored.inferenceInProgress, isTrue);
        expect(restored.consecutiveInterruptions, 2);
        expect(restored.noticePending, isTrue);
      }
    });

    test(
      'first interrupted startup clears marker silently and permits manual inference',
      () async {
        final h = await _Harness.create(
          record: _verifiedRecord(),
          safety: const ModelSafetyRecord(inferenceInProgress: true),
        );
        addTearDown(h.dispose);
        expect(h.storage.safety!.inferenceInProgress, isFalse);
        expect(h.storage.safety!.consecutiveInterruptions, 1);
        expect(h.storage.safety!.blockedReason, isNull);
        expect(h.storage.safety!.noticePending, isFalse);
        expect(h.controller.state.value, isA<ModelReady>());
        expect(await h.controller.consumeMemoryNotice(), isFalse);
        expect(h.transport.enqueues, isEmpty);
        await h.controller.beginInference();
        expect(h.storage.safety!.inferenceInProgress, isTrue);
        await h.controller.finishInference(succeeded: true);
        expect(h.storage.safety!.consecutiveInterruptions, 0);
      },
    );

    test(
      'second consecutive interrupted startup blocks and consumes exactly one durable notice',
      () async {
        final h = await _Harness.create(
          record: _verifiedRecord(),
          safety: const ModelSafetyRecord(
            inferenceInProgress: true,
            consecutiveInterruptions: 1,
          ),
        );
        addTearDown(h.dispose);
        expect(h.storage.safety!.inferenceInProgress, isFalse);
        expect(h.storage.safety!.consecutiveInterruptions, 2);
        expect(h.storage.safety!.blockedReason, ModelBlockedReason.interrupted);
        expect(h.storage.safety!.noticePending, isTrue);
        expect(h.controller.state.value, isA<ModelUnsupported>());
        await expectLater(
          h.controller.beginInference(),
          throwsA(isA<TranslatorMemoryUnsupported>()),
        );
        expect(
          await Future.wait([
            h.controller.consumeMemoryNotice(),
            h.controller.consumeMemoryNotice(),
          ]),
          [true, false],
        );
        expect(h.storage.safety!.noticePending, isFalse);

        final restarted = await _Harness.create(
          record: _verifiedRecord(),
          safety: h.storage.safety,
        );
        addTearDown(restarted.dispose);
        expect(restarted.storage.safety!.consecutiveInterruptions, 2);
        expect(restarted.controller.state.value, isA<ModelUnsupported>());
        expect(await restarted.controller.consumeMemoryNotice(), isFalse);
      },
    );

    test(
      'every completed inference attempt clears marker and breaks the interruption streak',
      () async {
        final h = await _Harness.create(
          record: _verifiedRecord(),
          safety: const ModelSafetyRecord(consecutiveInterruptions: 1),
        );
        addTearDown(h.dispose);
        await h.controller.beginInference();
        await h.controller.finishInference(succeeded: false);
        expect(h.storage.safety!.inferenceInProgress, isFalse);
        expect(h.storage.safety!.consecutiveInterruptions, 0);
        expect(h.storage.safety!.blockedReason, isNull);
        expect(h.storage.safety!.noticePending, isFalse);
        await h.controller.beginInference();
        await h.controller.finishInference(succeeded: true);
        expect(h.storage.safety!.inferenceInProgress, isFalse);
        expect(h.storage.safety!.consecutiveInterruptions, 0);
      },
    );

    test(
      'temporary headroom rejection keeps Ready and manual retry can recover',
      () async {
        var available = false;
        final h = await _Harness.create(
          record: _verifiedRecord(),
          safety: const ModelSafetyRecord(consecutiveInterruptions: 1),
          readAvailableMemory: () async => available,
        );
        addTearDown(h.dispose);
        await expectLater(
          h.controller.beginInference(),
          throwsA(isA<TranslatorMemoryTemporarilyUnavailable>()),
        );
        expect(h.controller.state.value, isA<ModelReady>());
        expect(h.storage.safety?.blockedReason, isNull);
        expect(h.storage.safety?.inferenceInProgress ?? false, isFalse);
        expect(h.storage.safety!.consecutiveInterruptions, 1);
        expect(await h.controller.consumeMemoryNotice(), isFalse);
        available = true;
        await h.controller.beginInference();
        await h.controller.finishInference(succeeded: true);
        expect(h.controller.state.value, isA<ModelReady>());
      },
    );

    test(
      'Settings retry clears all safety, rechecks facts and restores without starting a download',
      () async {
        var capabilityReads = 0;
        var memoryReads = 0;
        final h = await _Harness.create(
          record: _verifiedRecord(),
          safety: const ModelSafetyRecord(
            blockedReason: ModelBlockedReason.interrupted,
            inferenceInProgress: true,
            consecutiveInterruptions: 2,
            noticePending: true,
          ),
          readCapability: () async {
            capabilityReads++;
            return (supported: true, insufficientMemory: false);
          },
          readAvailableMemory: () async {
            memoryReads++;
            return true;
          },
        );
        addTearDown(h.dispose);
        capabilityReads = 0;
        memoryReads = 0;
        await h.controller.retryMemorySafety();
        expect(capabilityReads, 1);
        expect(memoryReads, 1);
        expect(h.storage.safety!.blockedReason, isNull);
        expect(h.storage.safety!.inferenceInProgress, isFalse);
        expect(h.storage.safety!.consecutiveInterruptions, 0);
        expect(h.storage.safety!.noticePending, isFalse);
        expect(h.controller.state.value, isA<ModelReady>());
        expect(h.network.fetches, 0);
        expect(h.transport.enqueues, isEmpty);
      },
    );

    test(
      'Settings retry with temporary low RAM stays recoverable and does not allocate',
      () async {
        final h = await _Harness.create(
          record: _verifiedRecord(),
          safety: const ModelSafetyRecord(
            blockedReason: ModelBlockedReason.resourceExhausted,
            consecutiveInterruptions: 2,
            noticePending: true,
          ),
          readAvailableMemory: () async => false,
        );
        addTearDown(h.dispose);
        await expectLater(
          h.controller.retryMemorySafety(),
          throwsA(isA<TranslatorMemoryTemporarilyUnavailable>()),
        );
        expect(h.storage.safety!.blockedReason, isNull);
        expect(h.storage.safety!.consecutiveInterruptions, 0);
        expect(h.storage.safety!.noticePending, isFalse);
        expect(h.controller.state.value, isA<ModelReady>());
        expect(h.transport.enqueues, isEmpty);
      },
    );

    test(
      'Settings retry without a model restores the offer without downloading',
      () async {
        final h = await _Harness.create(
          safety: const ModelSafetyRecord(
            blockedReason: ModelBlockedReason.interrupted,
            consecutiveInterruptions: 2,
          ),
        );
        addTearDown(h.dispose);
        await h.controller.retryMemorySafety();
        expect(h.controller.state.value, isA<ModelNotDownloaded>());
        expect(h.network.fetches, 0);
        expect(h.transport.enqueues, isEmpty);
      },
    );

    test(
      'Settings retry leaves API or ABI incompatibility generic after clearing prior memory safety',
      () async {
        final h = await _Harness.create(
          record: _verifiedRecord(),
          safety: const ModelSafetyRecord(
            blockedReason: ModelBlockedReason.interrupted,
            consecutiveInterruptions: 2,
            noticePending: true,
          ),
          readCapability: () async =>
              (supported: false, insufficientMemory: false),
        );
        addTearDown(h.dispose);
        await h.controller.retryMemorySafety();
        expect(h.controller.state.value, isA<ModelUnsupported>());
        expect(h.storage.safety!.blockedReason, isNull);
        expect(h.storage.safety!.consecutiveInterruptions, 0);
        expect(await h.controller.consumeMemoryNotice(), isFalse);
        expect(h.transport.enqueues, isEmpty);
      },
    );

    test(
      'known total-RAM shortage has a memory reason; API or ABI rejection stays generic',
      () async {
        final known = await _Harness.create(record: _verifiedRecord());
        addTearDown(known.dispose);
        known.controller.setCapability(false, insufficientMemory: true);
        await known.flush();
        expect(
          known.storage.safety!.blockedReason,
          ModelBlockedReason.totalRam,
        );
        expect(known.storage.safety!.noticePending, isTrue);
        final generic = await _Harness.create(supported: false);
        addTearDown(generic.dispose);
        expect(generic.controller.state.value, isA<ModelUnsupported>());
        expect(generic.storage.safety?.blockedReason, isNull);
        expect(await generic.controller.consumeMemoryNotice(), isFalse);
      },
    );

    test('ordinary model removal preserves memory safety', () async {
      final h = await _Harness.create(
        record: _verifiedRecord(),
        safety: const ModelSafetyRecord(
          blockedReason: ModelBlockedReason.resourceExhausted,
          consecutiveInterruptions: 1,
          noticePending: true,
        ),
      );
      addTearDown(h.dispose);
      await h.controller.remove();
      expect(h.storage.removals, 1);
      expect(
        h.storage.safety!.blockedReason,
        ModelBlockedReason.resourceExhausted,
      );
      expect(h.storage.safety!.consecutiveInterruptions, 1);
      expect(h.storage.safety!.noticePending, isTrue);
      expect(h.controller.state.value, isA<ModelUnsupported>());
    });

    test(
      'Gemma waits for durable marker before load and clears it after full success',
      () async {
        final h = await _Harness.create(
          record: _verifiedRecord(),
          safety: const ModelSafetyRecord(consecutiveInterruptions: 1),
        );
        addTearDown(h.dispose);
        final saved = h.storage.safetySaveStarted = Completer<void>();
        final flush = h.storage.safetySaveGate = Completer<void>();
        final reply = Completer<String>();
        final loadStarted = Completer<void>();
        var loads = 0;
        final service = GemmaPreviewService.forTesting(
          controller: h.controller,
          loadModel: () async {
            loads++;
            loadStarted.complete();
            expect(h.storage.safety!.inferenceInProgress, isTrue);
            return _MemoryModel(() => reply.future);
          },
        );
        final run = service.translate('مرحبا', languageName: 'English');
        await saved.future;
        expect(loads, 0);
        h.storage.safetySaveGate = null;
        flush.complete();
        await loadStarted.future;
        expect(loads, 1);
        expect(h.storage.safety!.inferenceInProgress, isTrue);
        reply.complete('Hello');
        expect(await run, 'Hello');
        expect(h.storage.safety!.inferenceInProgress, isFalse);
        expect(h.storage.safety!.consecutiveInterruptions, 0);
      },
    );

    test('failed durable marker prevents every model allocation', () async {
      final h = await _Harness.create(
        record: _verifiedRecord(),
        safety: const ModelSafetyRecord(consecutiveInterruptions: 1),
      );
      addTearDown(h.dispose);
      h.storage.failSafetySave = true;
      var loads = 0;
      final service = GemmaPreviewService.forTesting(
        controller: h.controller,
        loadModel: () async {
          loads++;
          return _MemoryModel(() async => 'Hello');
        },
      );
      await expectLater(
        service.translate('مرحبا', languageName: 'English'),
        throwsA(isA<Object>()),
      );
      expect(loads, 0);
      expect(h.storage.safety!.consecutiveInterruptions, 1);
    });

    test(
      'Settings retry cannot erase an actually active inference marker',
      () async {
        final h = await _Harness.create(record: _verifiedRecord());
        addTearDown(h.dispose);
        await h.controller.beginInference();
        // Either a no-op or an explicit rejection is valid while a run owns it.
        await h.controller.retryMemorySafety().then<void>(
          (_) {},
          onError: (Object _) {},
        );
        expect(h.storage.safety!.inferenceInProgress, isTrue);
        await h.controller.finishInference(succeeded: true);
        expect(h.storage.safety!.inferenceInProgress, isFalse);
      },
    );

    test(
      'Remove waiting for Gemma cannot deadlock inference safety completion',
      () async {
        final h = await _Harness.create(record: _verifiedRecord());
        addTearDown(h.dispose);
        final started = Completer<void>();
        final reply = Completer<String>();
        final removeEntered = Completer<void>();
        final service = GemmaPreviewService.forTesting(
          controller: h.controller,
          loadModel: () async => _MemoryModel(() {
            started.complete();
            return reply.future;
          }),
        );
        final run = service.translate('مرحبا', languageName: 'English');
        await started.future;
        h.storage.onRemove = () async {
          removeEntered.complete();
          // Production remove waits on Gemma's serial queue in the same order.
          await run;
        };
        final removal = h.controller.remove();
        await removeEntered.future;
        reply.complete('Hello');
        expect(await run.timeout(const Duration(seconds: 3)), 'Hello');
        await removal.timeout(const Duration(seconds: 3));
        expect(h.storage.safety!.inferenceInProgress, isFalse);
        expect(h.storage.removals, 1);
        expect(h.controller.state.value, isA<ModelNotDownloaded>());
      },
    );

    for (final facts in <({String name, Map<String, Object?> facts})>[
      (
        name: 'low available RAM',
        facts: {'availableBytes': 1, 'lowMemory': false},
      ),
      (
        name: 'Android lowMemory',
        facts: {'availableBytes': 8 * (1 << 30), 'lowMemory': true},
      ),
      (
        name: 'malformed snapshot',
        facts: {'availableBytes': 'unknown', 'lowMemory': false},
      ),
    ]) {
      for (final transcribe in [false, true]) {
        test(
          '${facts.name} prevents cold ${transcribe ? 'transcribe' : 'translate'} allocation',
          () async {
            const channel = MethodChannel('mknoon/gemma_preview');
            final messenger = TestDefaultBinaryMessengerBinding
                .instance
                .defaultBinaryMessenger;
            messenger.setMockMethodCallHandler(channel, (call) async {
              expect(call.method, 'memory');
              return facts.facts;
            });
            addTearDown(
              () => messenger.setMockMethodCallHandler(channel, null),
            );
            final h = await _Harness.create(
              record: _verifiedRecord(),
              readAvailableMemory: () => readTranslationMemoryAvailability(
                platform: TranslationPlatform.android,
              ),
            );
            addTearDown(h.dispose);
            var loads = 0;
            final service = GemmaPreviewService.forTesting(
              controller: h.controller,
              loadModel: () async {
                loads++;
                return _MemoryModel(() async => 'unused');
              },
            );
            await expectLater(
              transcribe
                  ? service.transcribe('/voice.m4a')
                  : service.translate('مرحبا', languageName: 'English'),
              throwsA(isA<TranslatorMemoryTemporarilyUnavailable>()),
            );
            expect(loads, 0);
            expect(h.controller.state.value, isA<ModelReady>());
            expect(h.storage.safety?.inferenceInProgress ?? false, isFalse);
            expect(h.storage.safety?.blockedReason, isNull);
          },
        );
      }
    }

    test(
      'warm cached Transcribe skips headroom admission but marks and completes every queued run',
      () async {
        var available = true;
        var reads = 0;
        final h = await _Harness.create(
          record: _verifiedRecord(),
          readAvailableMemory: () async {
            reads++;
            return available;
          },
        );
        addTearDown(h.dispose);
        const channel = MethodChannel('mknoon/gemma_preview');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'decodePcm') {
            return {'pcm': Uint8List(2), 'sampleRate': 16000, 'channels': 1};
          }
          expect(call.method, 'memory');
          return <String, Object?>{};
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final reply = Completer<String>();
        final started = Completer<void>();
        var loads = 0;
        final service = GemmaPreviewService.forTesting(
          controller: h.controller,
          loadModel: () async {
            loads++;
            return _MemoryModel(() {
              expect(h.storage.safety!.inferenceInProgress, isTrue);
              if (!started.isCompleted) {
                started.complete();
                return reply.future;
              }
              return Future.value('Transcript');
            });
          },
        );
        final first = service.translate('مرحبا', languageName: 'English');
        await started.future;
        final second = service.transcribe('/voice.m4a');
        final completed = expectLater(second, completion('Transcript'));
        available = false;
        reply.complete('Hello');
        expect(await first, 'Hello');
        await completed;
        expect(reads, 1);
        expect(loads, 1);
        expect(h.controller.state.value, isA<ModelReady>());
        expect(h.storage.safety!.inferenceInProgress, isFalse);
        expect(h.storage.safety!.blockedReason, isNull);
        expect(
          h.storage.safetyWrites.map((record) => record.inferenceInProgress),
          [true, false, true, false],
        );
      },
    );

    test(
      'a failed load makes the next queued request cold and rechecks available memory',
      () async {
        var available = true;
        var reads = 0;
        final h = await _Harness.create(
          record: _verifiedRecord(),
          readAvailableMemory: () async {
            reads++;
            return available;
          },
        );
        addTearDown(h.dispose);
        final loadStarted = Completer<void>();
        final failLoad = Completer<void>();
        var loads = 0;
        final failure = StateError('ordinary load failure');
        final service = GemmaPreviewService.forTesting(
          controller: h.controller,
          loadModel: () async {
            loads++;
            loadStarted.complete();
            await failLoad.future;
            throw failure;
          },
        );
        final first = service.translate('مرحبا', languageName: 'English');
        final firstFailed = expectLater(first, throwsA(same(failure)));
        await loadStarted.future;
        final second = service.translate('مرحبا', languageName: 'English');
        final secondRefused = expectLater(
          second,
          throwsA(isA<TranslatorMemoryTemporarilyUnavailable>()),
        );
        available = false;
        failLoad.complete();
        await firstFailed;
        await secondRefused;
        expect(loads, 1);
        expect(reads, 2);
        expect(h.storage.safety!.inferenceInProgress, isFalse);
        expect(h.storage.safety!.blockedReason, isNull);
      },
    );

    for (final wrapped in [false, true]) {
      test(
        'typed load resource exhaustion blocks immediately (wrapped=$wrapped)',
        () async {
          final h = await _Harness.create(record: _verifiedRecord());
          addTearDown(h.dispose);
          const native = LiteRtLmEngineCreateException(
            'load refused',
            nativeCode: 8,
          );
          final Object error = wrapped
              ? BackendInitException(
                  attempts: [
                    BackendInitAttemptFailure(
                      backend: PreferredBackend.cpu,
                      error: native,
                      stackTrace: StackTrace.empty,
                    ),
                  ],
                )
              : native;
          var loads = 0;
          var failLoad = true;
          final service = GemmaPreviewService.forTesting(
            controller: h.controller,
            loadModel: () async {
              loads++;
              if (failLoad) throw error;
              return _MemoryModel(() async => 'Hello');
            },
          );
          await expectLater(
            service.translate('مرحبا', languageName: 'English'),
            throwsA(isA<TranslatorMemoryUnsupported>()),
          );
          expect(h.controller.state.value, isA<ModelUnsupported>());
          expect(
            h.storage.safety!.blockedReason,
            ModelBlockedReason.resourceExhausted,
          );
          expect(h.storage.safety!.inferenceInProgress, isFalse);
          expect(h.storage.safety!.noticePending, isTrue);
          expect(await h.controller.consumeMemoryNotice(), isTrue);
          expect(await h.controller.consumeMemoryNotice(), isFalse);
          await expectLater(
            service.translate('مرحبا', languageName: 'English'),
            throwsA(isA<TranslatorMemoryUnsupported>()),
          );
          expect(loads, 1);
          failLoad = false;
          await h.controller.retryMemorySafety();
          expect(loads, 1, reason: 'Settings retry must never auto-load');
          expect(
            await service.translate('مرحبا', languageName: 'English'),
            'Hello',
          );
          expect(loads, 2);
        },
      );
    }

    for (final error in <Object>[
      StateError('out of memory OOM RESOURCE_EXHAUSTED code: 8'),
      const LiteRtLmEngineCreateException('out of memory', nativeCode: 13),
    ]) {
      test(
        'untyped or non-resource load errors do not become sticky (${error.runtimeType})',
        () async {
          final h = await _Harness.create(record: _verifiedRecord());
          addTearDown(h.dispose);
          final service = GemmaPreviewService.forTesting(
            controller: h.controller,
            loadModel: () async => throw error,
          );
          await expectLater(
            service.translate('مرحبا', languageName: 'English'),
            throwsA(same(error)),
          );
          expect(h.storage.safety!.inferenceInProgress, isFalse);
          expect(h.storage.safety!.blockedReason, isNull);
          expect(h.storage.safety!.noticePending, isFalse);
          expect(h.controller.state.value, isA<ModelReady>());
        },
      );
    }

    for (final responseError in <Object>[
      StateError('generation failed'),
      const LiteRtLmEngineCreateException(
        'typed error during response, not load',
        nativeCode: 8,
      ),
    ]) {
      test(
        'a completed model response failure resets the interruption streak without classifying load exhaustion (${responseError.runtimeType})',
        () async {
          final h = await _Harness.create(
            record: _verifiedRecord(),
            safety: const ModelSafetyRecord(consecutiveInterruptions: 1),
          );
          addTearDown(h.dispose);
          final service = GemmaPreviewService.forTesting(
            controller: h.controller,
            loadModel: () async =>
                _MemoryModel(() async => throw responseError),
          );
          await expectLater(
            service.translate('مرحبا', languageName: 'English'),
            throwsA(same(responseError)),
          );
          expect(h.storage.safety!.inferenceInProgress, isFalse);
          expect(h.storage.safety!.consecutiveInterruptions, 0);
          expect(h.storage.safety!.blockedReason, isNull);
          expect(h.storage.safety!.noticePending, isFalse);
        },
      );
    }
  });
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
    ModelDeliveryFileIdentity? identity,
    ModelSafetyRecord? safety,
    Future<bool> Function()? readAvailableMemory,
    Future<({bool supported, bool insufficientMemory})> Function()?
    readCapability,
  }) async {
    final storage = _Storage()
      ..record = record ?? ModelDeliveryRecord(manifest: _manifest)
      ..safety = safety
      ..freeBytes = freeBytes
      ..failPrepare = failPrepare
      ..verification = verification;
    if (identity != null) storage.identity = identity;
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
      readAvailableMemory: readAvailableMemory ?? () async => true,
      readCapability:
          readCapability ??
          () async => (supported: supported, insufficientMemory: false),
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
    transport.restored = ModelTransferSnapshot(
      taskId: taskId ?? id,
      status: status,
      receivedBytes: bytes ?? storage.record!.receivedBytes,
    );
    if (status == ModelTransferStatus.complete &&
        (taskId == null || taskId == storage.record?.taskId)) {
      storage.identity ??= _fileIdentity();
    }
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
  ModelSafetyRecord? safety;
  final safetyWrites = <ModelSafetyRecord>[];
  bool failSafetySave = false;
  Completer<void>? safetySaveStarted;
  Completer<void>? safetySaveGate;
  int freeBytes = 1000;
  int? length;
  ModelDeliveryFileIdentity? identity = _fileIdentity();
  bool valid = true;
  bool failPrepare = false;
  bool failFreeMeasurement = false;
  int removals = 0;
  int verifications = 0;
  Completer<bool>? verification;
  Completer<void>? verificationStarted;
  Future<void> Function()? onRemove;
  @override
  Future<ModelDeliveryRecord?> readRecord() async => record;
  @override
  Future<void> saveRecord(ModelDeliveryRecord value) async {
    record = value;
  }

  @override
  Future<ModelSafetyRecord?> readSafety() async => safety;

  @override
  Future<void> saveSafety(ModelSafetyRecord value) async {
    if (failSafetySave) throw StateError('safety was not saved');
    final started = safetySaveStarted;
    if (started != null && !started.isCompleted) started.complete();
    await safetySaveGate?.future;
    safety = value;
    safetyWrites.add(value);
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
  Future<ModelDeliveryFileIdentity?> modelIdentity() async => identity;
  @override
  Future<bool> verify(ModelDeliveryManifest manifest) async {
    verifications++;
    verificationStarted?.complete();
    return verification?.future ?? valid;
  }

  @override
  Future<String> modelPath() async => '/owned/gemma.litertlm';
  @override
  Future<void> removeOwnedModel() async {
    await onRemove?.call();
    removals++;
    length = null;
    identity = null;
  }
}

class _MemoryModel extends Fake implements InferenceModel {
  _MemoryModel(this.reply);
  final Future<String> Function() reply;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #createSession) {
      return Future<InferenceModelSession>.value(_MemorySession(reply));
    }
    if (invocation.memberName == #close) return Future<void>.value();
    return super.noSuchMethod(invocation);
  }
}

class _MemorySession extends Fake implements InferenceModelSession {
  _MemorySession(this.reply);
  final Future<String> Function() reply;

  @override
  Future<String> getResponse() => reply();

  @override
  Future<void> addQueryChunk(Message message) async {}

  @override
  Future<void> close() async {}
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
  final ownedTasks = <String>{};
  int peakOwnedTasks = 0;
  bool resumeAccepted = true;
  bool failCancel = false;
  Completer<void>? cancellationStarted;
  Completer<void>? cancellation;
  ModelTransferSnapshot? restored;
  @override
  Stream<ModelTransferEvent> get events => eventsController.stream;
  @override
  Future<void> initialize(String? ownedTaskId) async {}
  @override
  Future<ModelTransferSnapshot?> restore(String taskId) async =>
      restored?.taskId == taskId ? restored : null;
  @override
  Future<bool> enqueue({
    required String taskId,
    required ModelDeliveryManifest manifest,
    required bool requiresWiFi,
  }) async {
    enqueues.add((taskId: taskId, requiresWiFi: requiresWiFi));
    ownedTasks.add(taskId);
    if (ownedTasks.length > peakOwnedTasks) peakOwnedTasks = ownedTasks.length;
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
    cancellationStarted?.complete();
    await cancellation?.future;
    ownedTasks.remove(taskId);
  }

  @override
  Future<void> forget(String taskId) async {
    forgets.add(taskId);
  }

  @override
  Future<void> dispose() => eventsController.close();
}
