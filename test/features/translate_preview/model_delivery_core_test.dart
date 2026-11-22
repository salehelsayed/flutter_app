import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/features/translate_preview/gemma_preview_service.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_core.dart';
import 'package:flutter_app/features/translate_preview/private_translator_sheet.dart';
import 'package:flutter_app/features/translate_preview/translation_capability.dart';
import 'package:flutter_app/features/translate_preview/wav_16k_mono.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

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

  test('readiness pause resumes the same owned partial task', () {
    fakeAsync((clock) {
      late _Harness h;
      unawaited(
        _Harness.create(canRecoverUnexpectedPauses: true).then((harness) async {
          h = harness;
          await h.controller.start(allowMobileData: false);
          await h.event(ModelTransferStatus.running, bytes: 40);
          await h.event(ModelTransferStatus.paused);
        }),
      );
      clock.flushMicrotasks();
      try {
        final id = h.id;
        clock.elapse(const Duration(milliseconds: 4999));
        expect(h.transport.resumes, isEmpty);
        clock.elapse(const Duration(milliseconds: 1));
        expect(h.transport.resumes, [(taskId: id, requiresWiFi: true)]);
        expect(h.transport.enqueues, hasLength(1));
        expect(h.transport.cancels, isEmpty);
        expect(h.transport.forgets, isEmpty);
        expect(h.storage.record!.receivedBytes, 40);
      } finally {
        unawaited(h.dispose());
        clock.flushMicrotasks();
      }
    });
  });

  test('rejected readiness resume retains the partial and backs off', () {
    fakeAsync((clock) {
      late _Harness h;
      unawaited(
        _Harness.create(canRecoverUnexpectedPauses: true).then((harness) async {
          h = harness;
          await h.controller.start(allowMobileData: false);
          await h.event(ModelTransferStatus.running, bytes: 40);
          h.network.failFetch = true;
          h.transport.resumeAccepted = false;
          await h.event(ModelTransferStatus.paused);
        }),
      );
      clock.flushMicrotasks();
      try {
        final id = h.id;
        const delaysInSeconds = [5, 15, 45, 135, 405, 600, 600];
        for (final (index, seconds) in delaysInSeconds.indexed) {
          clock.elapse(Duration(milliseconds: seconds * 1000 - 1));
          expect(h.transport.resumes, hasLength(index));
          clock.elapse(const Duration(milliseconds: 1));
          expect(h.transport.resumes, hasLength(index + 1));
          expect(h.transport.resumes.last, (taskId: id, requiresWiFi: true));
          expect(h.id, id);
          expect(h.storage.record!.receivedBytes, 40);
          expect(h.storage.removals, 0);
        }
        expect(h.network.fetches, 1);
        expect(h.transport.enqueues, hasLength(1));
        expect(h.transport.cancels, isEmpty);
        expect(h.transport.forgets, isEmpty);
      } finally {
        unawaited(h.dispose());
        clock.flushMicrotasks();
      }
    });
  });

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
      expect(h.controller.state.value, isA<ModelChecking>());
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
        expect(h.controller.state.value, isA<ModelChecking>());
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
      expect(h.controller.state.value, isA<ModelChecking>());
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
    'completion shows Checking until size/checksum verification succeeds',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      await h.controller.start(allowMobileData: false);
      h.storage.verification = Completer<bool>();
      await h.event(ModelTransferStatus.complete);
      expect(h.controller.state.value, isA<ModelChecking>());
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
      final damagedTask = h.id;
      h.storage.valid = false;
      final refetching = _nextState<ModelIntegrityRepair>(h.controller.state);
      await h.event(ModelTransferStatus.complete);
      await refetching;
      await h.flush();
      expect(h.storage.removals, 1);
      expect(h.transport.forgets, [damagedTask]);
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
      expect(h.controller.state.value, isA<ModelChecking>());
      await expectLater(h.controller.verifiedModelPath(), throwsStateError);
      final refetching = _nextState<ModelIntegrityRepair>(h.controller.state);
      verification.complete(false);
      await refetching;
      await h.flush();
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
    'manifest build floor requires an update without a native task',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.network.manifest = {..._manifest.toJson(), 'minAppBuild': 130};
      await h.controller.start(allowMobileData: false);
      expect(h.controller.state.value, isA<ModelUpdateRequired>());
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

  group('BL60 committed background notices', () {
    const bound = Duration(seconds: 3);

    ({Future<void> started, VoidCallback release}) holdRecordWrite(
      _Storage storage,
      ModelDeliveryPhase phase,
    ) {
      final started = Completer<void>();
      final proceed = Completer<void>();
      storage.beforeSaveRecord = (record) async {
        if (record.phase != phase || started.isCompleted) return;
        started.complete();
        await proceed.future.timeout(bound);
      };

      void release() {
        if (!proceed.isCompleted) proceed.complete();
      }

      addTearDown(release);
      return (started: started.future, release: release);
    }

    test('verified Ready publishes once after its record commits', () async {
      final notices = <(ModelDeliveryState, ModelDeliveryRecord?)>[];
      _Storage? storage;
      final h = await _Harness.create(
        publishBackgroundStatus: (state) async =>
            notices.add((state, storage?.record)),
      ).timeout(bound);
      storage = h.storage;
      addTearDown(() => h.dispose().timeout(bound));

      final checking = Completer<bool>();
      final checkingStarted = Completer<void>();
      h.storage
        ..verification = checking
        ..verificationStarted = checkingStarted;
      addTearDown(() {
        if (!checking.isCompleted) checking.complete(false);
      });
      final write = holdRecordWrite(h.storage, ModelDeliveryPhase.ready);

      await h.controller.start(allowMobileData: false).timeout(bound);
      final taskId = h.id;
      await h.event(ModelTransferStatus.complete).timeout(bound);
      await checkingStarted.future.timeout(bound);
      expect(notices, isEmpty, reason: 'transport complete is still checking');

      checking.complete(true);
      await write.started.timeout(bound);
      expect(h.storage.record!.phase, ModelDeliveryPhase.verifying);
      expect(
        notices,
        isEmpty,
        reason: 'the verified record is still being saved',
      );
      write.release();
      await h.flush().timeout(bound);

      expect(
        notices,
        hasLength(1),
        reason:
            'the committed verified record publishes exactly one Ready notice',
      );
      final (state, record) = notices.single;
      expect(
        state,
        isA<ModelReady>().having((s) => s.sizeBytes, 'sizeBytes', 100),
      );
      expect(record?.phase, ModelDeliveryPhase.ready);
      expect(record?.taskId, taskId);
      expect(record?.verification?.expectedSha256, _manifest.sha256);
      expect(record?.verification?.identity, _fileIdentity());

      await h.event(ModelTransferStatus.complete).timeout(bound);
      await h.controller.refresh().timeout(bound);
      expect(notices, hasLength(1));
    });

    test(
      'acknowledged Pause publishes once after owned progress commits',
      () async {
        final notices = <(ModelDeliveryState, ModelDeliveryRecord?)>[];
        _Storage? storage;
        final h = await _Harness.create(
          publishBackgroundStatus: (state) async =>
              notices.add((state, storage?.record)),
        ).timeout(bound);
        storage = h.storage;
        addTearDown(() => h.dispose().timeout(bound));

        await h.controller.start(allowMobileData: false).timeout(bound);
        final taskId = h.id;
        await h.event(ModelTransferStatus.running, bytes: 42).timeout(bound);
        await h.controller.pause().timeout(bound);
        expect(h.transport.pauses, [taskId]);
        expect(h.storage.record!.phase, ModelDeliveryPhase.pauseRequested);
        expect(
          notices,
          isEmpty,
          reason: 'a pause request awaits acknowledgement',
        );

        final write = holdRecordWrite(h.storage, ModelDeliveryPhase.userPaused);
        final acknowledgement = h.event(ModelTransferStatus.paused, bytes: 42);
        await write.started.timeout(bound);
        expect(h.storage.record!.phase, ModelDeliveryPhase.pauseRequested);
        expect(
          notices,
          isEmpty,
          reason: 'the acknowledged pause is still being saved',
        );
        write.release();
        await acknowledgement.timeout(bound);

        expect(
          notices,
          hasLength(1),
          reason:
              'the committed pause publishes exactly one owned progress notice',
        );
        final (state, record) = notices.single;
        expect(
          state,
          isA<ModelPaused>().having((s) => s.percent, 'percent', 42),
        );
        expect(record?.phase, ModelDeliveryPhase.userPaused);
        expect(record?.taskId, taskId);
        expect(record?.receivedBytes, 42);

        await h.event(ModelTransferStatus.paused, bytes: 42).timeout(bound);
        h.transport.eventsController.add(
          ModelTransferEvent(taskId: taskId, receivedBytes: 43),
        );
        await h.flush().timeout(bound);
        expect(notices, hasLength(1));
      },
    );
  });

  group('BL15 transcription tail', () {
    Uint8List samples(List<int> values) {
      final data = ByteData(values.length * 2);
      for (var i = 0; i < values.length; i++) {
        data.setInt16(i * 2, values[i], Endian.little);
      }
      return data.buffer.asUint8List();
    }

    List<int> tone(int frames, int amplitude) =>
        List<int>.generate(frames, (i) => i.isEven ? amplitude : -amplitude);

    Future<({String text, Uint8List wav})> transcribe(
      Uint8List pcm, {
      int rate = 16000,
      int channels = 1,
      bool simulateTailHallucination = false,
    }) async {
      final h = await _Harness.create(record: _verifiedRecord())
          .timeout(const Duration(seconds: 3));
      addTearDown(() => h.dispose().timeout(const Duration(seconds: 3)));
      const channel = MethodChannel('mknoon/gemma_preview');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'decodePcm') {
          return {'pcm': pcm, 'sampleRate': rate, 'channels': channels};
        }
        expect(call.method, 'memory');
        return <String, Object?>{};
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      Uint8List? captured;
      var queries = 0;
      final service = GemmaPreviewService.forTesting(
        controller: h.controller,
        loadModel: () async => _AudioInputModel(
          (message) {
            queries++;
            captured = Uint8List.fromList(message.audioBytes!);
          },
          () async {
            final data = ByteData.sublistView(captured!);
            var quietSamples = 0;
            // The fake recognizer models the reported suffix failure from
            // a long low-noise tail; it does not implement the RMS trimmer.
            for (var offset = captured!.length - 2; offset >= 44; offset -= 2) {
              if (data.getInt16(offset, Endian.little).abs() > 64) break;
              quietSamples++;
            }
            const phrase = 'Our group dinner moves to Friday evening.';
            return simulateTailHallucination && quietSamples >= 16000
                ? '$phrase Thank you for watching.'
                : phrase;
          },
        ),
      );
      final text = await service
          .transcribe('/fixture.wav')
          .timeout(const Duration(seconds: 3));
      expect(queries, 1);
      expect(h.storage.safety!.inferenceInProgress, isFalse);
      expect(h.controller.state.value, isA<ModelReady>());
      return (text: text, wav: captured!);
    }

    test('recorded speech plus nonzero low noise reaches the model without an invented suffix', () async {
      final fixture = File(
        'test/features/translate_preview/bl15_dinner_low_noise.wav',
      ).readAsBytesSync();
      final pcm = Uint8List.sublistView(fixture, 44);
      final result = await transcribe(pcm, simulateTailHallucination: true);
      expect(result.text, 'Our group dinner moves to Friday evening.');
      const originalSpeechBytes = 42389 * 2;
      expect(
        result.wav.sublist(44, 44 + originalSpeechBytes),
        orderedEquals(pcm.sublist(0, originalSpeechBytes)),
      );
      expect(result.wav.length, lessThan(44 + (42389 + 4800) * 2));
      final header = ByteData.sublistView(result.wav);
      expect(header.getUint32(4, Endian.little), result.wav.length - 8);
      expect(header.getUint32(40, Endian.little), result.wav.length - 44);
      expect(fixture.length, 44 + (42389 + 48000) * 2);
    });

    test('keeps leading quiet, internal pauses and a soft final word above the floor', () async {
      final prefix = <int>[
        ...tone(6400, 32),
        ...tone(6400, 3000),
        ...tone(19200, 32),
        ...tone(6400, 200),
      ];
      final pcm = samples([...prefix, ...tone(48000, 32)]);
      final result = await transcribe(pcm);
      expect(
        result.wav.sublist(44, 44 + prefix.length * 2),
        orderedEquals(pcm.sublist(0, prefix.length * 2)),
      );
      expect(result.wav.length, lessThan(44 + (prefix.length + 4800) * 2));
    });

    test(
      'trims a sustained low-noise tail after 48k stereo normalization',
      () async {
        final source = <int>[...tone(48000, 3000), ...tone(144000, 32)];
        final pcm = samples([
          for (final sample in source) ...[sample, sample],
        ]);
        final result = await transcribe(pcm, rate: 48000, channels: 2);
        final normalized = wav16kMono(pcm, sampleRate: 48000, channels: 2);
        final header = ByteData.sublistView(result.wav);
        expect(header.getUint32(24, Endian.little), 16000);
        expect(header.getUint16(22, Endian.little), 1);
        expect(header.getUint16(34, Endian.little), 16);
        expect(
          result.wav.sublist(44, 44 + 16000 * 2),
          orderedEquals(normalized.sublist(44, 44 + 16000 * 2)),
        );
        expect(result.wav.length, lessThan(44 + 20800 * 2));
      },
    );

    test('preserves a short quiet tail below the minimum run', () async {
      final pcm = samples([...tone(16000, 3000), ...tone(6400, 32)]);
      final result = await transcribe(pcm);
      expect(
        result.wav,
        orderedEquals(wav16kMono(pcm, sampleRate: 16000, channels: 1)),
      );
    });

    test('requires the full600ms quiet run before trimming', () async {
      final before = samples([...tone(16000, 3000), ...tone(9599, 32)]);
      final unchanged = await transcribe(before);
      expect(unchanged.wav, orderedEquals(
          wav16kMono(before, sampleRate: 16000, channels: 1)));
      final atBoundary = samples([...tone(16000, 3000), ...tone(9600, 32)]);
      final trimmed = await transcribe(atBoundary);
      expect(trimmed.wav.length, lessThan(44 + atBoundary.length));
      expect(trimmed.wav.sublist(44, 44 + 16000 * 2),
          orderedEquals(atBoundary.sublist(0, 16000 * 2)));
    });

    test('preserves a tail above the quiet floor', () async {
      final pcm = samples([...tone(16000, 3000), ...tone(48000, 200)]);
      final result = await transcribe(pcm);
      expect(
        result.wav,
        orderedEquals(wav16kMono(pcm, sampleRate: 16000, channels: 1)),
      );
    });

    for (final input in ['low-noise', 'digital-silence', 'one-sample']) {
      test('preserves $input without a confident active window', () async {
        final pcm = samples(
          input == 'low-noise'
              ? tone(48000, 32)
              : List<int>.filled(input == 'one-sample' ? 1 : 48000, 0),
        );
        final result = await transcribe(pcm);
        expect(
          result.wav,
          orderedEquals(wav16kMono(pcm, sampleRate: 16000, channels: 1)),
        );
      });
    }
  });

  group('BL15 debug fixture hook', () {
    const fixtureName = 'bl15_dinner_low_noise.wav';
    const configuredName = String.fromEnvironment('BL15_REPLAY_WAV');

    Future<
      ({
        GemmaPreviewService service,
        Directory documents,
        File recording,
        _Bl15Documents paths,
        List<String> decodedPaths,
        List<Uint8List> modelInputs,
      })
    >
    prepare({bool installFixture = true, bool modelFails = false}) async {
      final documents = Directory.systemTemp.createTempSync('bl15-hook-');
      final previous = PathProviderPlatform.instance;
      final paths = _Bl15Documents(documents.path);
      PathProviderPlatform.instance = paths;
      addTearDown(() {
        PathProviderPlatform.instance = previous;
        documents.deleteSync(recursive: true);
      });
      final fixture = File('test/features/translate_preview/$fixtureName')
          .readAsBytesSync();
      if (installFixture) {
        final target = File('${documents.path}/bl15/$fixtureName');
        target.parent.createSync(recursive: true);
        target.writeAsBytesSync(fixture);
      }
      final recording = File('${documents.path}/recording.aac')
        ..writeAsBytesSync([1, 2, 3]);
      final h = await _Harness.create(record: _verifiedRecord())
          .timeout(const Duration(seconds: 3));
      addTearDown(() => h.dispose().timeout(const Duration(seconds: 3)));
      final decodedPaths = <String>[];
      final modelInputs = <Uint8List>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('mknoon/gemma_preview');
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'decodePcm') {
          decodedPaths.add((call.arguments as Map)['path'] as String);
          return {
            'pcm': Uint8List.sublistView(fixture, 44),
            'sampleRate': 16000,
            'channels': 1,
          };
        }
        expect(call.method, 'memory');
        return <String, Object?>{};
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final service = GemmaPreviewService.forTesting(
        controller: h.controller,
        loadModel: () async => _AudioInputModel(
          (message) => modelInputs.add(Uint8List.fromList(message.audioBytes!)),
          () async {
            if (modelFails) throw StateError('fixture model failure');
            return '  Our group dinner moves to Friday evening.  ';
          },
        ),
      );
      return (
        service: service,
        documents: documents,
        recording: recording,
        paths: paths,
        decodedPaths: decodedPaths,
        modelInputs: modelInputs,
      );
    }

    if (configuredName.isEmpty) {
      test(
        'without a define preserves the original input and writes no receipt',
        () async {
          final h = await prepare().timeout(const Duration(seconds: 3));
          final text = await h.service
              .transcribe(h.recording.path)
              .timeout(const Duration(seconds: 3));
          expect(text, 'Our group dinner moves to Friday evening.');
          expect(h.decodedPaths, [h.recording.path]);
          expect(h.paths.requests, 0);
          expect(
            Directory('${h.documents.path}/bl15/receipts').existsSync(),
            isFalse,
          );
          expect(h.recording.readAsBytesSync(), [1, 2, 3]);
        },
      );
    } else {
      test('uses the configured local WAV and records exact model input and raw text', () async {
        expect(configuredName, fixtureName);
        final h = await prepare().timeout(const Duration(seconds: 3));
        final text = await h.service
            .transcribe(h.recording.path)
            .timeout(const Duration(seconds: 3));
        expect(text, 'Our group dinner moves to Friday evening.');
        expect(h.modelInputs, hasLength(1));
        expect(h.decodedPaths, ['${h.documents.path}/bl15/$fixtureName']);
        final runs = Directory('${h.documents.path}/bl15/receipts')
            .listSync()
            .whereType<Directory>()
            .toList();
        expect(runs, hasLength(1));
        final receipt = jsonDecode(
          File('${runs.single.path}/receipt.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        expect(
          receipt['fixtureSha256'],
          'a4034826b2f26d27b82e54885cba38ede382962633966283c902dc5d7628adf9',
        );
        expect(receipt['normalizedFrames'], 90389);
        expect(receipt['modelInputFrames'], inInclusiveRange(42389, 47188));
        expect(receipt['modelInputBytes'], h.modelInputs.single.length);
        expect(receipt['retainedPcmIsPrefix'], isTrue);
        expect(
          receipt['rawText'],
          '  Our group dinner moves to Friday evening.  ',
        );
        expect(receipt['phase'], 'response');
        expect(
          File('${runs.single.path}/model-input.wav').readAsBytesSync(),
          orderedEquals(h.modelInputs.single),
        );
        final original = File('${runs.single.path}/normalized.wav')
            .readAsBytesSync();
        expect(
          h.modelInputs.single.sublist(44),
          orderedEquals(original.sublist(44, h.modelInputs.single.length)),
        );
        expect(h.recording.readAsBytesSync(), [1, 2, 3]);
      });

      test(
        'a missing fixture fails before decoding or model queries',
        () async {
          final h = await prepare(installFixture: false)
              .timeout(const Duration(seconds: 3));
          await expectLater(
            h.service
                .transcribe(h.recording.path)
                .timeout(const Duration(seconds: 3)),
            throwsA(isA<FileSystemException>()),
          );
          expect(h.decodedPaths, isEmpty);
          expect(h.modelInputs, isEmpty);
          expect(h.recording.readAsBytesSync(), [1, 2, 3]);
        },
      );

      test('model failure retains a prepared receipt without a successful response', () async {
        final h = await prepare(modelFails: true)
            .timeout(const Duration(seconds: 3));
        await expectLater(
          h.service
              .transcribe(h.recording.path)
              .timeout(const Duration(seconds: 3)),
          throwsA(isA<StateError>()),
        );
        expect(h.modelInputs, hasLength(1));
        final receipts = Directory('${h.documents.path}/bl15/receipts');
        expect(receipts.existsSync(), isTrue);
        final run = receipts.listSync().whereType<Directory>().single;
        final receipt = jsonDecode(
          File('${run.path}/receipt.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        expect(receipt['phase'], 'prepared');
        expect(receipt.containsKey('rawText'), isFalse);
        expect(
          File('${run.path}/model-input.wav').readAsBytesSync(),
          orderedEquals(h.modelInputs.single),
        );
      });
    }
  });

  group('BL60 translator download sheet states', () {
    const bound = Duration(seconds: 3);

    void testSheet(
      String description,
      Future<void> Function(WidgetTester tester, _Harness h) body, {
      Future<_Harness> Function()? create,
    }) {
      testWidgets(description, (tester) async {
        final h = await (create ?? _Harness.create)().timeout(bound);
        try {
          await body(tester, h);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink()).timeout(bound);
          final verification = h.storage.verification;
          if (verification != null && !verification.isCompleted) {
            verification.complete(true);
          }
          await h.dispose().timeout(bound);
        }
      });
    }

    Future<void> pumpSheet(
      WidgetTester tester,
      ModelDeliveryController controller,
    ) => tester
        .pumpWidget(
          MaterialApp(
            title: 'mknoon',
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: PrivateTranslatorSheet(controller: controller),
            ),
          ),
        )
        .timeout(bound);

    testSheet('checking hides Pause while verification is pending', (
      tester,
      h,
    ) async {
      final started = Completer<void>();
      h.storage
        ..verification = Completer<bool>()
        ..verificationStarted = started;

      await h.controller.start(allowMobileData: false).timeout(bound);
      await h.event(ModelTransferStatus.complete).timeout(bound);
      await started.future.timeout(bound);
      await pumpSheet(tester, h.controller);

      expect(
        find.text('Checking the download'),
        findsOneWidget,
        reason:
            'the sheet shows download checking while the checksum is pending',
      );
      expect(find.text('Pause'), findsNothing);
    });

    testSheet(
      'the first offline download tap explains the wait without enqueuing',
      (tester, h) async {
        h.network.offline = true;

        await pumpSheet(tester, h.controller);
        await tester.tap(find.text('Download when on Wi-Fi')).timeout(bound);
        await h.flush().timeout(bound);
        await tester.pump().timeout(bound);

        expect(h.transport.enqueues, isEmpty);
        expect(h.network.fetches, 0);
        expect(
          find.text("You're offline"),
          findsOneWidget,
          reason: 'the sheet explains offline on the first download request',
        );
        await tester.tap(find.text('Cancel')).timeout(bound);
        await h.flush().timeout(bound);
        h.network.changeWifi(true);
        await h.flush().timeout(bound);
        expect(h.transport.enqueues, isEmpty);

        h.network.changeWifi(false, offline: true);
        await h.flush().timeout(bound);
        await tester.pump().timeout(bound);
        await tester.tap(find.text('Download when on Wi-Fi')).timeout(bound);
        await h.flush().timeout(bound);
        h.network.changeWifi(false);
        await h.flush().timeout(bound);
        expect(h.transport.enqueues, isEmpty);
        h.network.changeWifi(true);
        await h.flush().timeout(bound);
        expect(h.transport.enqueues, [(taskId: h.id, requiresWiFi: true)]);
      },
      create: () => _Harness.create(
        wifi: false,
        freeBytes: 3000000000,
        record: const ModelDeliveryRecord(),
      ),
    );

    testSheet('a newer required build offers Update without enqueuing', (
      tester,
      h,
    ) async {
      h.network.manifest = {..._manifest.toJson(), 'minAppBuild': 130};

      await pumpSheet(tester, h.controller);
      await tester.tap(find.text('Download on Wi-Fi')).timeout(bound);
      await h.flush().timeout(bound);
      await tester.pump().timeout(bound);

      expect(h.network.fetches, 1);
      expect(h.transport.enqueues, isEmpty);
      expect(
        find.text('Update mknoon to use the translator'),
        findsOneWidget,
        reason:
            'the sheet offers a branded update when the manifest requires a newer build',
      );
      expect(find.text('Update'), findsOneWidget);
    });

    testSheet('connection loss keeps progress and resumes the owned task', (
      tester,
      h,
    ) async {
      await h.controller.start(allowMobileData: false).timeout(bound);
      final taskId = h.id;
      await h.event(ModelTransferStatus.running, bytes: 42).timeout(bound);

      h.transport.checkpoints[taskId] = const ModelResumeCheckpoint(
        retainedBytes: 42,
      );
      h.network.changeWifi(false, offline: true);
      await h.event(ModelTransferStatus.paused).timeout(bound);
      await pumpSheet(tester, h.controller);

      expect(h.transport.pauses, isEmpty);
      expect(h.transport.resumes, isEmpty);
      expect(
        find.text('Waiting for a connection'),
        findsOneWidget,
        reason:
            'an interrupted download explains that it is waiting for a connection',
      );
      expect(
        find.text(
          "Your download is safe at 42%. It continues by itself when you're "
          'back online.',
        ),
        findsOneWidget,
      );
      expect(find.text('Pause'), findsOneWidget);

      h.network.changeWifi(true);
      await h.flush().timeout(bound);
      await tester.pump(const Duration(seconds: 5)).timeout(bound);
      await h.flush().timeout(bound);

      expect(h.transport.resumes, [(taskId: taskId, requiresWiFi: true)]);
      expect(h.transport.enqueues, [(taskId: taskId, requiresWiFi: true)]);
      expect(h.transport.cancels, isEmpty);
      expect(h.transport.forgets, isEmpty);
      expect(h.storage.record!.receivedBytes, 42);
    });

    testSheet('a checksum mismatch automatically refetches only once', (
      tester,
      h,
    ) async {
      await h.controller.start(allowMobileData: false).timeout(bound);
      final rejected = h.id;
      h.storage.valid = false;
      await pumpSheet(tester, h.controller);

      Future<void> finishWithBadChecksum() async {
        final requestedRemoval = Completer<void>();
        h.storage.onRemove = () async => requestedRemoval.complete();
        await h.event(ModelTransferStatus.complete).timeout(bound);
        await requestedRemoval.future.timeout(bound);
        await h.flush().timeout(bound);
        await tester.pump().timeout(bound);
      }

      await finishWithBadChecksum().timeout(bound);
      expect(
        h.transport.enqueues,
        hasLength(2),
        reason:
            'the first failed checksum requests one replacement automatically',
      );
      final replacement = h.transport.enqueues.last;
      expect(replacement.taskId, isNot(rejected));
      expect(replacement.requiresWiFi, isTrue);
      expect(h.storage.removals, 1);
      expect(h.transport.forgets, [rejected]);
      expect(find.text('The file was damaged'), findsOneWidget);
      expect(
        find.text("We're downloading the file again. Nothing for you to do."),
        findsOneWidget,
      );
      await expectLater(
        h.controller.verifiedModelPath().timeout(bound),
        throwsStateError,
      ).timeout(bound);

      await finishWithBadChecksum().timeout(bound);
      expect(h.transport.enqueues, hasLength(2));
      expect(h.storage.removals, 2);
      expect(h.transport.forgets, [rejected, replacement.taskId]);
      expect(find.text('Try again to download a new copy.'), findsOneWidget);
      await expectLater(
        h.controller.verifiedModelPath().timeout(bound),
        throwsStateError,
      ).timeout(bound);
    });
  });
}

class _Bl15Documents extends PathProviderPlatform {
  _Bl15Documents(this.path);
  final String path;
  var requests = 0;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    requests++;
    return path;
  }
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
    bool canRecoverUnexpectedPauses = false,
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
    Future<void> Function(ModelDeliveryState)? publishBackgroundStatus,
  }) async {
    final storage = _Storage()
      ..record = record ?? ModelDeliveryRecord(manifest: _manifest)
      ..safety = safety
      ..freeBytes = freeBytes
      ..failPrepare = failPrepare
      ..verification = verification;
    if (identity != null) storage.identity = identity;
    final network = _Network()..wifi = wifi;
    final transport = _Transport()
      ..canRecoverUnexpectedPauses = canRecoverUnexpectedPauses;
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
      publishBackgroundStatus: publishBackgroundStatus,
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
  Future<void> Function(ModelDeliveryRecord)? beforeSaveRecord;
  @override
  Future<ModelDeliveryRecord?> readRecord() async => record;
  @override
  Future<void> saveRecord(ModelDeliveryRecord value) async {
    if (beforeSaveRecord case final beforeSave?) await beforeSave(value);
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
  bool offline = false;
  bool failFetch = false;
  int fetches = 0;
  Map<String, Object?> manifest = _manifest.toJson();
  final changes = StreamController<ModelDeliveryConnection>.broadcast(
    sync: true,
  );
  ModelDeliveryConnection get _connection => offline
      ? ModelDeliveryConnection.offline
      : wifi
      ? ModelDeliveryConnection.wifi
      : ModelDeliveryConnection.other;
  @override
  Stream<ModelDeliveryConnection> get connectionChanges => changes.stream;
  @override
  Future<ModelDeliveryConnection> checkConnection() async => _connection;
  @override
  Future<Map<String, Object?>> fetchManifest() async {
    fetches++;
    if (failFetch) throw StateError('offline');
    return manifest;
  }

  void changeWifi(bool value, {bool offline = false}) {
    wifi = value;
    this.offline = offline;
    changes.add(_connection);
  }
}

class _Transport implements ModelDeliveryTransport {
  @override
  bool canRecoverUnexpectedPauses = false;

  final eventsController = StreamController<ModelTransferEvent>.broadcast(
    sync: true,
  );
  final enqueues = <({String taskId, bool requiresWiFi})>[];
  final resumes = <({String taskId, bool requiresWiFi})>[];
  final pauses = <String>[];
  final cancels = <String>[];
  final forgets = <String>[];
  final ownedTasks = <String>{};
  final checkpoints = <String, ModelResumeCheckpoint>{};
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
  Future<ModelResumeCheckpoint?> checkpoint(String taskId) async =>
      checkpoints[taskId];
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
  Future<bool> resume(
    String taskId, {
    required bool requiresWiFi,
    bool allowZeroByteRestart = true,
  }) async {
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
    checkpoints.remove(taskId);
  }

  @override
  Future<void> dispose() => eventsController.close();
}

class _AudioInputModel extends _MemoryModel {
  _AudioInputModel(this.capture, super.reply);
  final void Function(Message) capture;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #createSession) {
      return Future<InferenceModelSession>.value(
        _AudioInputSession(reply, capture),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

class _AudioInputSession extends _MemorySession {
  _AudioInputSession(super.reply, this.capture);
  final void Function(Message) capture;

  @override
  Future<void> addQueryChunk(Message message) async => capture(message);
}
