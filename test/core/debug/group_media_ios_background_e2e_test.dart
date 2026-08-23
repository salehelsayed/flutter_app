import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/debug/group_media_ios_background_e2e.dart';
import 'package:flutter_app/core/debug/group_media_ios_background_e2e_main_actions.dart';
import 'package:flutter_app/core/debug/group_media_ios_background_e2e_overlay.dart';
import 'package:flutter_app/core/debug/group_media_ios_disposable_profile.dart';
import 'package:flutter_app/core/debug/group_media_ios_disposable_reset.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'P269 iOS proof overlay publishes dynamic labels as unblocked accessibility text',
    (tester) async {
      const ready = 'P269-READY-A-run-269';
      final labels = ValueNotifier<List<String>>(<String>[]);
      addTearDown(labels.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: GroupMediaIosBackgroundE2EOverlay(
            labels: labels,
            child: const Scaffold(body: Text('receiver root')),
          ),
        ),
      );
      expect(find.bySemanticsLabel(ready), findsNothing);

      labels.value = const <String>[ready];
      await tester.pump();

      final proof = find.bySemanticsLabel(ready);
      expect(proof, findsOneWidget);
      final boundary = find.byKey(
        const ValueKey<String>('p269-ios-proof-$ready'),
      );
      expect(boundary, findsOneWidget);
      final semantics = tester.getSemantics(boundary);
      expect(semantics, matchesSemantics(label: ready));
      expect(semantics.label, ready);
      expect(semantics.childrenCountInTraversalOrder, 0);
      expect(
        semantics.areUserActionsBlocked,
        isFalse,
        reason:
            'XCTest must receive the live proof label through the iOS '
            'accessibility tree',
      );
    },
  );

  test(
    'P269 physical iOS endpoint rejects local-only startup until relay send and inbox proofs are ready',
    () {
      const transportPeerId = 'transport-receiver';
      for (final state in <NodeState>[
        const NodeState(isStarted: true, peerId: transportPeerId),
        const NodeState(
          isStarted: true,
          peerId: transportPeerId,
          circuitAddresses: <String>['relay-circuit'],
          sendCapabilityReady: true,
        ),
        const NodeState(
          isStarted: true,
          peerId: transportPeerId,
          circuitAddresses: <String>['relay-circuit'],
          inboxCapabilityReady: true,
        ),
        const NodeState(
          isStarted: true,
          peerId: transportPeerId,
          sendCapabilityReady: true,
          inboxCapabilityReady: true,
        ),
      ]) {
        expect(groupMediaIosProofEndpointReady(state), isFalse);
      }

      expect(
        groupMediaIosProofEndpointReady(
          const NodeState(
            isStarted: true,
            peerId: transportPeerId,
            circuitAddresses: <String>['relay-circuit'],
            sendCapabilityReady: true,
            inboxCapabilityReady: true,
          ),
        ),
        isTrue,
      );
    },
  );

  test(
    'P269 cold relaunch identity and receive recovery use only their causal readiness axes',
    () {
      const stopped = NodeState(
        isStarted: false,
        peerId: 'transport-receiver',
        circuitAddresses: <String>['relay-circuit'],
        sendCapabilityReady: true,
        inboxCapabilityReady: true,
      );
      const started = NodeState(isStarted: true, peerId: 'transport-receiver');
      const receiveReady = NodeState(
        isStarted: true,
        peerId: 'transport-receiver',
        inboxCapabilityReady: true,
      );

      for (final requirement in GroupMediaIosProofReadiness.values) {
        expect(
          groupMediaIosProofEndpointReady(stopped, requirement: requirement),
          isFalse,
        );
      }
      expect(
        groupMediaIosProofEndpointReady(
          started,
          requirement: GroupMediaIosProofReadiness.identity,
        ),
        isTrue,
      );
      expect(
        groupMediaIosProofEndpointReady(
          started,
          requirement: GroupMediaIosProofReadiness.receiveRecovery,
        ),
        isFalse,
      );
      expect(
        groupMediaIosProofEndpointReady(
          receiveReady,
          requirement: GroupMediaIosProofReadiness.receiveRecovery,
        ),
        isTrue,
      );
      expect(
        groupMediaIosProofEndpointReady(receiveReady),
        isFalse,
        reason:
            'all non-relaunch operations retain full relay reservation and '
            'duplex capability readiness',
      );
    },
  );

  test(
    'P269 receiver observation acceptance binds the foreground process without claiming completion',
    () {
      final config = _config(
        phase: groupMediaIosReceiverObservePhase,
        role: 'receiver',
        mediaPhase: 'a',
        messageId: 'msg-a',
        attachmentId: 'blob-a',
        marker: 'P269-A-run-269',
      );

      final receipt = groupMediaIosBackgroundE2EAcceptedReceipt(
        config: config,
        currentProcessId: 4269,
      );

      expect(receipt, <String, Object?>{
        'schema': groupMediaIosBackgroundE2EResultSchema,
        'scenario': groupMediaIosBackgroundScenario,
        'stepId': 'p269-ios-$groupMediaIosReceiverObservePhase-run-269',
        'phase': groupMediaIosReceiverObservePhase,
        'role': 'receiver',
        'runId': 'run-269',
        'nonce': 'nonce-269',
        'status': 'accepted',
        'success': false,
        'processId': 4269,
        'foregroundArmComplete': true,
      });

      for (final field in const <String>[
        'mediaPhase',
        'messageId',
        'attachmentId',
      ]) {
        final incomplete = Map<String, dynamic>.from(config)..[field] = null;
        expect(
          () => groupMediaIosBackgroundE2EAcceptedReceipt(
            config: incomplete,
            currentProcessId: 4269,
          ),
          throwsFormatException,
          reason: '$field must bind the accepted foreground observer',
        );
      }
    },
  );

  test(
    'P269 observer accepts an exact durable arm before the incoming row exists',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'p269-ios-pre-send-observer-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final controller = GroupMediaIosBackgroundE2EController(
        enabled: true,
        stateDirectory: directory,
        currentProcessId: 4268,
      );
      await controller.arm(
        runId: 'run-269',
        phase: 'a',
        groupId: 'group-a',
        messageId: 'msg-a',
        attachmentId: 'blob-a',
        readinessMarker: 'P269-READY-A-run-269',
      );

      final observation = await controller.observe(
        runId: 'run-269',
        phase: 'a',
        messageId: 'msg-a',
        attachmentId: 'blob-a',
        loadCurrentAttachment: (_) async => null,
      );

      expect(observation, containsPair('durableStatus', 'absent'));
      expect(controller.uiProofLabels.value, isEmpty);
    },
  );

  test(
    'P269 foreground receipt and shared lease causally gate READY before Home',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'p269-ios-foreground-handshake-',
      );
      addTearDown(() => directory.delete(recursive: true));
      MediaAttachment? row;
      var observeReadsEnabled = false;
      var firstDurablePollObserved = false;
      var reservationHeld = false;
      var reservationReleased = false;
      var terminalObservationPublished = false;
      final acceptanceStarted = Completer<void>();
      final allowAcceptancePublication = Completer<void>();
      final controller = GroupMediaIosBackgroundE2EController(
        enabled: true,
        stateDirectory: directory,
        currentProcessId: 4269,
        onStateSnapshotRead: (_) {
          if (observeReadsEnabled) firstDurablePollObserved = true;
        },
      );
      await controller.arm(
        runId: 'run-269',
        phase: 'a',
        groupId: 'group-a',
        messageId: 'msg-a',
        attachmentId: 'blob-a',
        readinessMarker: 'P269-READY-A-run-269',
      );
      expect(
        controller.uiProofLabels.value,
        isEmpty,
        reason: 'arm alone must not authorize XCTest to press Home',
      );

      observeReadsEnabled = true;
      final action = runGroupMediaIosBackgroundE2EAction(
        config: _config(
          phase: groupMediaIosReceiverObservePhase,
          role: 'receiver',
          mediaPhase: 'a',
          messageId: 'msg-a',
          attachmentId: 'blob-a',
          marker: 'P269-A-run-269',
        ),
        controller: controller,
        loadAttachment: (_) async => row,
        exportIdentity: () async => const <String, Object?>{},
        addContact: (_, _) async {},
        setupSender: (_, _, _) async => const <String, Object?>{},
        acceptReceiver: (_) async => const <String, Object?>{},
        sendFixture: (_, _, _, _, _, _, _) async => const <String, Object?>{},
        probeDatabase: (_, _, _) async => const <String, Object?>{},
        drainGroupInbox: () async {},
        retryDownloads: () async => 0,
        reserveReceiveCriticalTask: () async {
          reservationHeld = true;
          return () async {
            expect(terminalObservationPublished, isTrue);
            reservationReleased = true;
          };
        },
        onReceiverObservationAccepted: () async {
          expect(reservationHeld, isTrue);
          expect(firstDurablePollObserved, isTrue);
          acceptanceStarted.complete();
          await allowAcceptancePublication.future;
        },
        onReceiverObservationComplete: (_) async {
          expect(reservationReleased, isFalse);
          terminalObservationPublished = true;
        },
        installedProfileId: groupMediaIosBackgroundBuildProfile,
      );

      await acceptanceStarted.future;
      expect(controller.uiProofLabels.value, isEmpty);
      expect(reservationReleased, isFalse);
      allowAcceptancePublication.complete();
      await _waitUntil(
        () => controller.uiProofLabels.value.contains('P269-READY-A-run-269'),
      );

      row = _attachment('msg-a', 'blob-a', status: 'downloading');
      await controller.onPostClaimPreCommit(
        attachment: row,
        loadCurrentAttachment: (_) async => row,
      );
      row = row.copyWith(downloadStatus: 'done');
      final result = await action;
      expect(result, containsPair('success', true));
      expect(controller.uiProofLabels.value, <String>['P269-A-run-269']);
      expect(reservationReleased, isTrue);
    },
  );

  test(
    'P269 phase B observation holds its lease until the durable post-claim barrier',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'p269-ios-phase-b-barrier-',
      );
      addTearDown(() => directory.delete(recursive: true));
      MediaAttachment? row;
      var reservationReleased = false;
      var terminalObservationPublished = false;
      var actionCompleted = false;
      final controller = GroupMediaIosBackgroundE2EController(
        enabled: true,
        stateDirectory: directory,
        currentProcessId: 4270,
      );
      await controller.arm(
        runId: 'run-269',
        phase: 'b',
        groupId: 'group-b',
        messageId: 'msg-b',
        attachmentId: 'blob-b',
        readinessMarker: 'P269-READY-B-run-269',
      );

      final action =
          runGroupMediaIosBackgroundE2EAction(
            config: _config(
              phase: groupMediaIosReceiverObservePhase,
              role: 'receiver',
              mediaPhase: 'b',
              messageId: 'msg-b',
              attachmentId: 'blob-b',
            ),
            controller: controller,
            loadAttachment: (_) async => row,
            exportIdentity: () async => const <String, Object?>{},
            addContact: (_, _) async {},
            setupSender: (_, _, _) async => const <String, Object?>{},
            acceptReceiver: (_) async => const <String, Object?>{},
            sendFixture: (_, _, _, _, _, _, _) async =>
                const <String, Object?>{},
            probeDatabase: (_, _, _) async => const <String, Object?>{},
            drainGroupInbox: () async {},
            retryDownloads: () async => 0,
            reserveReceiveCriticalTask: () async => () async {
              expect(terminalObservationPublished, isTrue);
              reservationReleased = true;
            },
            onReceiverObservationAccepted: () async {},
            onReceiverObservationComplete: (_) async {
              expect(reservationReleased, isFalse);
              terminalObservationPublished = true;
            },
            installedProfileId: groupMediaIosBackgroundBuildProfile,
          ).whenComplete(() {
            actionCompleted = true;
          });
      await _waitUntil(
        () => controller.uiProofLabels.value.contains('P269-READY-B-run-269'),
      );

      row = _attachment('msg-b', 'blob-b', status: 'downloading');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(actionCompleted, isFalse);
      expect(reservationReleased, isFalse);

      final interrupted = controller.onPostClaimPreCommit(
        attachment: row,
        loadCurrentAttachment: (_) async => row,
      );
      await _waitUntil(() => controller.holdsAutomaticRecovery);
      expect(interrupted, doesNotComplete);
      final result = await action;
      expect(result, containsPair('barrier', 'durable_post_claim_pre_commit'));
      expect(reservationReleased, isTrue);
    },
  );

  test(
    'P269 iOS durable controller records fast completion then requires fresh-process post-drain recovery',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'p269-ios-controller-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final rows = <String, MediaAttachment>{
        'blob-a': _attachment('msg-a', 'blob-a', status: 'downloading'),
        'blob-b': _attachment('msg-b', 'blob-b', status: 'downloading'),
      };
      Future<MediaAttachment?> load(String id) async => rows[id];

      final first = GroupMediaIosBackgroundE2EController(
        enabled: true,
        stateDirectory: directory,
        currentProcessId: 4101,
      );
      await first.arm(
        runId: 'run-269',
        phase: 'a',
        groupId: 'group-a',
        messageId: 'msg-a',
        attachmentId: 'blob-a',
        readinessMarker: 'P269-READY-A-run-269',
      );
      expect(first.uiProofLabels.value, isEmpty);
      await first.markObservationReady(
        runId: 'run-269',
        phase: 'a',
        messageId: 'msg-a',
        attachmentId: 'blob-a',
      );
      await first.onPostClaimPreCommit(
        attachment: rows['blob-a']!,
        loadCurrentAttachment: load,
      );
      rows['blob-a'] = rows['blob-a']!.copyWith(downloadStatus: 'done');
      final fast = await first.observe(
        runId: 'run-269',
        phase: 'a',
        messageId: 'msg-a',
        attachmentId: 'blob-a',
        loadCurrentAttachment: load,
      );
      expect(fast, containsPair('barrier', 'background_receive_started'));
      expect(fast, containsPair('durableStatus', 'done'));
      expect(fast, containsPair('downloadAttempts', 1));

      await first.arm(
        runId: 'run-269',
        phase: 'b',
        groupId: 'group-b',
        messageId: 'msg-b',
        attachmentId: 'blob-b',
        readinessMarker: 'P269-READY-B-run-269',
      );
      final interrupted = first.onPostClaimPreCommit(
        attachment: rows['blob-b']!,
        loadCurrentAttachment: load,
      );
      await _waitUntil(() => first.holdsAutomaticRecovery);
      expect(interrupted, doesNotComplete);
      final claim = await first.observe(
        runId: 'run-269',
        phase: 'b',
        messageId: 'msg-b',
        attachmentId: 'blob-b',
        loadCurrentAttachment: load,
      );
      expect(claim, containsPair('barrier', 'durable_post_claim_pre_commit'));
      expect(claim, containsPair('durableStatus', 'downloading'));

      final relaunched = GroupMediaIosBackgroundE2EController(
        enabled: true,
        stateDirectory: directory,
        currentProcessId: 4202,
      );
      expect(
        relaunched.uiProofLabels.value,
        isEmpty,
        reason: 'a READY receipt from the interrupted PID must not revive',
      );
      final release = await relaunched.releaseRecoveryAfterInboxDrain(
        runId: 'run-269',
        loadCurrentAttachment: load,
      );
      expect(release, containsPair('interruptedPid', 4101));
      expect(release, containsPair('relaunchPid', 4202));
      await relaunched.onPostClaimPreCommit(
        attachment: rows['blob-b']!,
        loadCurrentAttachment: load,
      );
      rows['blob-b'] = rows['blob-b']!.copyWith(downloadStatus: 'done');
      final recovered = await relaunched.observe(
        runId: 'run-269',
        phase: 'b',
        messageId: 'msg-b',
        attachmentId: 'blob-b',
        loadCurrentAttachment: load,
      );
      expect(recovered, containsPair('downloadAttempts', 2));
      expect(recovered, containsPair('resumeAfterDrainAttempts', 1));
      expect(recovered, containsPair('durableStatus', 'done'));
      await relaunched.publishDurableUiEffect(
        runId: 'run-269',
        phase: 'b',
        marker: 'P269-B-run-269',
        loadCurrentAttachment: load,
      );
      expect(relaunched.uiProofLabels.value, <String>['P269-B-run-269']);
    },
  );

  test(
    'P269 iOS action contract rejects extras role-profile drift and synthetic recovery',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'p269-ios-action-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final controller = GroupMediaIosBackgroundE2EController(
        enabled: true,
        stateDirectory: directory,
        currentProcessId: 100,
      );
      final identity = _config(
        phase: groupMediaIosIdentityPhase,
        role: 'receiver',
      );
      final result = await runGroupMediaIosBackgroundE2EAction(
        config: identity,
        controller: controller,
        loadAttachment: (_) async => null,
        exportIdentity: () async => <String, Object?>{
          'accountPeerId': 'account-receiver',
          'transportPeerId': 'transport-receiver',
          'qrPayload': '{"signed":true}',
          'mlKemPublicKey': 'public-material',
        },
        addContact: (_, _) async {},
        setupSender: (_, _, _) async => const <String, Object?>{},
        acceptReceiver: (_) async => const <String, Object?>{},
        sendFixture: (_, _, _, _, _, _, _) async => const <String, Object?>{},
        probeDatabase: (_, _, _) async => const <String, Object?>{},
        drainGroupInbox: () async {},
        retryDownloads: () async => 0,
        reserveReceiveCriticalTask: _reserveNoopCriticalTask,
        installedProfileId: groupMediaIosBackgroundBuildProfile,
      );
      expect(result, containsPair('success', true));
      expect(
        result['processId'],
        isA<int>().having((value) => value, 'pid', greaterThan(0)),
      );

      String? setupAccount;
      String? setupTransport;
      String? setupGroupName;
      final senderSetup = _config(
        phase: groupMediaIosSenderSetupPhase,
        role: 'sender',
        marker: 'P269-GROUP-A-run-269',
        receiverAccountPeerId: 'receiver-account',
        receiverTransportPeerId: 'receiver-transport',
      );
      await runGroupMediaIosBackgroundE2EAction(
        config: senderSetup,
        controller: controller,
        loadAttachment: (_) async => null,
        exportIdentity: () async => const <String, Object?>{},
        addContact: (_, _) async {},
        setupSender: (account, transport, groupName) async {
          setupAccount = account;
          setupTransport = transport;
          setupGroupName = groupName;
          return const <String, Object?>{'groupId': 'group-a'};
        },
        acceptReceiver: (_) async => const <String, Object?>{},
        sendFixture: (_, _, _, _, _, _, _) async => const <String, Object?>{},
        probeDatabase: (_, _, _) async => const <String, Object?>{},
        drainGroupInbox: () async {},
        retryDownloads: () async => 0,
        reserveReceiveCriticalTask: _reserveNoopCriticalTask,
        installedProfileId: groupMediaIosAndroidSenderBuildProfile,
      );
      expect(setupAccount, 'receiver-account');
      expect(setupTransport, 'receiver-transport');
      expect(setupGroupName, 'P269-GROUP-A-run-269');

      final wrongRole = Map<String, dynamic>.from(identity)
        ..['role'] = 'sender';
      await expectLater(
        runGroupMediaIosBackgroundE2EAction(
          config: wrongRole,
          controller: controller,
          loadAttachment: (_) async => null,
          exportIdentity: () async => const <String, Object?>{},
          addContact: (_, _) async {},
          setupSender: (_, _, _) async => const <String, Object?>{},
          acceptReceiver: (_) async => const <String, Object?>{},
          sendFixture: (_, _, _, _, _, _, _) async => const <String, Object?>{},
          probeDatabase: (_, _, _) async => const <String, Object?>{},
          drainGroupInbox: () async {},
          retryDownloads: () async => 0,
          reserveReceiveCriticalTask: _reserveNoopCriticalTask,
          installedProfileId: groupMediaIosBackgroundBuildProfile,
        ),
        throwsStateError,
      );

      final extra = Map<String, dynamic>.from(identity)..['synthetic'] = true;
      expect(
        () => GroupMediaIosBackgroundE2ERequest.fromConfig(extra),
        throwsFormatException,
      );

      final recovery = _config(
        phase: groupMediaIosReceiverRecoverPhase,
        role: 'receiver',
        mediaPhase: 'b',
        messageId: 'msg-b',
        attachmentId: 'blob-b',
      );
      await expectLater(
        runGroupMediaIosBackgroundE2EAction(
          config: recovery,
          controller: controller,
          loadAttachment: (_) async => null,
          exportIdentity: () async => const <String, Object?>{},
          addContact: (_, _) async {},
          setupSender: (_, _, _) async => const <String, Object?>{},
          acceptReceiver: (_) async => const <String, Object?>{},
          sendFixture: (_, _, _, _, _, _, _) async => const <String, Object?>{},
          probeDatabase: (_, _, _) async => const <String, Object?>{},
          drainGroupInbox: () async {},
          retryDownloads: () async => 0,
          reserveReceiveCriticalTask: _reserveNoopCriticalTask,
          installedProfileId: groupMediaIosBackgroundBuildProfile,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'P269 iOS state mutation is copy-on-write atomic and polling cannot erase a queued phase',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'p269-ios-state-race-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final beforeReplace = Completer<void>();
      final allowReplace = Completer<void>();
      var held = false;
      final row = _attachment('msg-b', 'blob-b', status: 'downloading');
      final controller = GroupMediaIosBackgroundE2EController(
        enabled: true,
        stateDirectory: directory,
        currentProcessId: 5101,
        beforeAtomicStateReplace: (barrier) async {
          if (!held && barrier == 'durable_post_claim_pre_commit') {
            held = true;
            beforeReplace.complete();
            await allowReplace.future;
          }
        },
      );
      await controller.arm(
        runId: 'race-269',
        phase: 'b',
        groupId: 'group-b',
        messageId: 'msg-b',
        attachmentId: 'blob-b',
        readinessMarker: 'P269-READY-B-race-269',
      );
      final interrupted = controller.onPostClaimPreCommit(
        attachment: row,
        loadCurrentAttachment: (_) async => row,
      );
      await beforeReplace.future;

      final queuedArm = controller.arm(
        runId: 'race-269',
        phase: 'a',
        groupId: 'group-a',
        messageId: 'msg-a',
        attachmentId: 'blob-a',
        readinessMarker: 'P269-READY-A-race-269',
      );
      final oldSnapshot = await controller.observe(
        runId: 'race-269',
        phase: 'b',
        messageId: 'msg-b',
        attachmentId: 'blob-b',
        loadCurrentAttachment: (_) async => row,
      );
      expect(oldSnapshot['barrier'], isNull);
      allowReplace.complete();
      await queuedArm;
      expect(interrupted, doesNotComplete);

      final fresh = GroupMediaIosBackgroundE2EController(
        enabled: true,
        stateDirectory: directory,
        currentProcessId: 5202,
      );
      final phaseB = await fresh.observe(
        runId: 'race-269',
        phase: 'b',
        messageId: 'msg-b',
        attachmentId: 'blob-b',
        loadCurrentAttachment: (_) async => row,
      );
      expect(phaseB['barrier'], 'durable_post_claim_pre_commit');
      final phaseA = await fresh.observe(
        runId: 'race-269',
        phase: 'a',
        messageId: 'msg-a',
        attachmentId: 'blob-a',
        loadCurrentAttachment: (_) async =>
            _attachment('msg-a', 'blob-a', status: 'pending'),
      );
      expect(phaseA['durableStatus'], 'pending');
      expect(
        directory.listSync().where((entry) => entry.path.contains('.pending-')),
        isEmpty,
      );
    },
  );

  test(
    'P269 iOS UI label cannot publish from a parent-only or downloading row',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'p269-ios-ui-effect-',
      );
      addTearDown(() => directory.delete(recursive: true));
      var row = _attachment('msg-a', 'blob-a', status: 'downloading');
      final controller = GroupMediaIosBackgroundE2EController(
        enabled: true,
        stateDirectory: directory,
        currentProcessId: 6101,
      );
      await controller.arm(
        runId: 'effect-269',
        phase: 'a',
        groupId: 'group-a',
        messageId: 'msg-a',
        attachmentId: 'blob-a',
        readinessMarker: 'P269-READY-A-effect-269',
      );
      expect(controller.uiProofLabels.value, isEmpty);
      await controller.markObservationReady(
        runId: 'effect-269',
        phase: 'a',
        messageId: 'msg-a',
        attachmentId: 'blob-a',
      );
      await controller.onPostClaimPreCommit(
        attachment: row,
        loadCurrentAttachment: (_) async => row,
      );
      expect(controller.uiProofLabels.value, <String>[
        'P269-READY-A-effect-269',
      ]);
      expect(
        controller.uiProofLabels.value,
        isNot(contains('P269-A-effect-269')),
        reason: 'an ordinary parent alone is not a durable UI effect',
      );
      await expectLater(
        controller.publishDurableUiEffect(
          runId: 'effect-269',
          phase: 'a',
          marker: 'P269-A-effect-269',
          loadCurrentAttachment: (_) async => row,
        ),
        throwsStateError,
      );
      row = row.copyWith(downloadStatus: 'done');
      await controller.publishDurableUiEffect(
        runId: 'effect-269',
        phase: 'a',
        marker: 'P269-A-effect-269',
        loadCurrentAttachment: (_) async => row,
      );
      expect(controller.uiProofLabels.value, <String>['P269-A-effect-269']);
    },
  );

  test('P269 iOS release file channel is exact-profile gated', () {
    expect(
      allowsGroupMediaIosIntroFileChannel(
        isDebugMode: false,
        e2eTestMode: true,
        installedProfileId: groupMediaIosBackgroundBuildProfile,
      ),
      isTrue,
    );
    for (final tuple in const <(bool, bool, String)>[
      (false, false, groupMediaIosBackgroundBuildProfile),
      (false, true, 'ios.release'),
      (false, true, groupMediaIosAndroidSenderBuildProfile),
      (true, false, groupMediaIosAndroidSenderBuildProfile),
    ]) {
      expect(
        allowsGroupMediaIosIntroFileChannel(
          isDebugMode: tuple.$1,
          e2eTestMode: tuple.$2,
          installedProfileId: tuple.$3,
        ),
        isFalse,
        reason: '$tuple',
      );
    }
  });

  test('Plan 397 signed iOS setup profile owns the intro file channel', () {
    expect(
      allowsGroupMediaIosIntroFileChannel(
        isDebugMode: false,
        e2eTestMode: true,
        installedProfileId: 'ios.device.group_reaction_notification_397',
      ),
      isTrue,
    );
    expect(
      allowsGroupMediaIosIntroFileChannel(
        isDebugMode: false,
        e2eTestMode: false,
        installedProfileId: 'ios.device.group_reaction_notification_397',
      ),
      isFalse,
    );
  });

  test(
    'P269 iOS production entry wiring exposes only the exact action and exact recovery callbacks',
    () {
      final productionSource = File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsStringSync();
      final compositionSource = File(
        'lib/debug/debug_e2e_composition_root.dart',
      ).readAsStringSync();
      final introSource = File(
        'lib/core/debug/intro_e2e_runner.dart',
      ).readAsStringSync();

      expect(
        RegExp(
          r'GroupMediaIosBackgroundE2EController\.forInstalledProfile\s*\(',
        ).allMatches(compositionSource),
        hasLength(1),
      );
      expect(
        RegExp(
          r'runGroupMediaIosBackgroundE2EAction\s*\(',
        ).allMatches(compositionSource),
        hasLength(1),
      );
      expect(
        compositionSource,
        contains('_iosBackgroundController.onPostClaimPreCommit'),
      );
      expect(
        compositionSource,
        contains('_reliabilityController.onPostClaimPreCommit'),
      );
      expect(
        compositionSource,
        matches(
          RegExp(
            r'pendingMessageRetrier\s*'
            r'\.\s*drainGroupOfflineInboxFn',
          ),
        ),
      );
      expect(
        compositionSource,
        matches(
          RegExp(
            r'pendingMessageRetrier\s*'
            r'\.\s*retryIncompleteGroupDownloadsPeriodicFn',
          ),
        ),
      );
      expect(
        compositionSource,
        matches(
          RegExp(
            r'groupMediaIosIdentityPhase\s*=>\s*'
            r'GroupMediaIosProofReadiness\.identity',
          ),
        ),
      );
      expect(
        compositionSource,
        matches(
          RegExp(
            r'groupMediaIosReceiverRecoverPhase\s*=>\s*'
            r'GroupMediaIosProofReadiness\.receiveRecovery',
          ),
        ),
      );
      expect(compositionSource, contains('requirement: readiness'));
      expect(compositionSource, contains('GroupMediaIosBackgroundE2EOverlay('));
      expect(
        compositionSource,
        matches(RegExp(r'groupMediaIosBackgroundE2EController\s*\.\s*enabled')),
      );
      expect(
        productionSource,
        contains('if (debugE2EComposition?.startsIntroPoller ?? false) {'),
      );
      expect(
        productionSource,
        contains('debugE2EComposition!.startIntroPollerAfterColdRecovery('),
      );
      expect(productionSource, contains('debugE2EOverlayBuilder:'));
      expect(
        productionSource,
        isNot(contains('GroupMediaIosBackgroundE2EOverlay(')),
      );

      final exactAction = introSource.indexOf(
        "config['transport_action'] == groupMediaIosBackgroundE2EAction",
      );
      final releaseRejection = introSource.indexOf(
        'if (!kDebugMode && !allowsPlan397SetupActions)',
        exactAction,
      );
      final genericAndroidAction = introSource.indexOf(
        "config['transport_action'] == groupMediaReliabilityE2EAction",
      );
      expect(exactAction, greaterThanOrEqualTo(0));
      expect(releaseRejection, greaterThan(exactAction));
      expect(genericAndroidAction, greaterThan(releaseRejection));
      expect(
        introSource.substring(exactAction, releaseRejection),
        contains('await _deleteConfigIfPresent()'),
      );
      final exactActionSource = introSource.substring(
        exactAction,
        releaseRejection,
      );
      final acceptanceCallback = exactActionSource.indexOf(
        'onReceiverObservationAccepted:',
      );
      final acceptedReceipt = exactActionSource.indexOf(
        'groupMediaIosBackgroundE2EAcceptedReceipt(',
      );
      final longAction = exactActionSource.indexOf('await run(');
      expect(acceptanceCallback, greaterThanOrEqualTo(0));
      expect(acceptedReceipt, greaterThanOrEqualTo(0));
      expect(longAction, greaterThanOrEqualTo(0));
      expect(longAction, lessThan(acceptanceCallback));
      expect(acceptanceCallback, lessThan(acceptedReceipt));
      expect(
        exactActionSource,
        contains("config['phase'] == groupMediaIosReceiverObservePhase"),
      );
    },
  );

  test(
    'P269 iOS sender fixture requires both active transports and a real JPEG asset',
    () {
      expect(
        isExactGroupMediaIosBackgroundTransportAcl(
          allowedPeers: const <String>[
            'sender-transport',
            'receiver-transport',
          ],
          senderAccountPeerId: 'sender-account',
          senderTransportPeerId: 'sender-transport',
          receiverAccountPeerId: 'receiver-account',
          receiverTransportPeerId: 'receiver-transport',
        ),
        isTrue,
      );
      for (final invalid in const <List<String>>[
        <String>['receiver-transport'],
        <String>['sender-transport', 'receiver-account'],
        <String>['sender-account', 'receiver-transport'],
        <String>['receiver-transport', 'receiver-transport'],
        <String>[
          'sender-transport',
          'receiver-transport',
          'receiver-transport',
        ],
      ]) {
        expect(
          isExactGroupMediaIosBackgroundTransportAcl(
            allowedPeers: invalid,
            senderAccountPeerId: 'sender-account',
            senderTransportPeerId: 'sender-transport',
            receiverAccountPeerId: 'receiver-account',
            receiverTransportPeerId: 'receiver-transport',
          ),
          isFalse,
          reason: '$invalid',
        );
      }
      final source = File(
        'lib/core/debug/group_media_ios_background_e2e_main_actions.dart',
      ).readAsStringSync();
      expect(
        source,
        contains('integration_test/fixtures/received_media_egress_fixture.jpg'),
      );
      expect(source, contains('rootBundle.load'));
      expect(source, isNot(contains('0xff, 0xd8, 0xff, 0xe0')));
    },
  );

  test(
    'P269 dedicated iOS reset is pre-open allowlisted idempotent and preserves outside sentinels',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'p269-ios-disposable-reset-',
      );
      addTearDown(() => root.delete(recursive: true));
      final documents = Directory('${root.path}/documents')..createSync();
      final databases = Directory('${root.path}/databases')..createSync();
      final support = Directory('${root.path}/support')..createSync();
      final outsideDocument = File('${documents.path}/outside-sentinel')
        ..writeAsStringSync('preserve');
      final outsideDatabase = File('${databases.path}/outside-sentinel')
        ..writeAsStringSync('preserve');
      final outsideSupport = File('${support.path}/outside-sentinel')
        ..writeAsStringSync('preserve');
      final ownedDatabaseNames = <String>[
        for (final base in const <String>[
          'identity.db',
          'identity.db.rekey-tmp',
          'identity.db.pre-raw.bak',
        ])
          for (final suffix in const <String>['', '-wal', '-shm', '-journal'])
            '$base$suffix',
      ];
      for (final name in ownedDatabaseNames) {
        File('${databases.path}/$name').writeAsStringSync('disposable');
      }
      const ownedDocumentFiles = <String>[
        'auto_setup.json',
        'intro_e2e_config.json',
        'intro_e2e_result.json',
        'intro_e2e_result.json.tmp',
        'intro_e2e_identity.json',
        'group_media_reliability_state.json',
        'group_media_ios_background_state.json',
      ];
      for (final name in ownedDocumentFiles) {
        File('${documents.path}/$name').writeAsStringSync('disposable');
      }
      const ownedDocumentDirectories = <String>[
        'p269-group-media-ios-fixtures',
        'p269-group-media-fixtures',
        'media',
        'pending_uploads',
        'local_media',
        'post_media',
      ];
      for (final name in ownedDocumentDirectories) {
        final directory = Directory('${documents.path}/$name')..createSync();
        File('${directory.path}/owned').writeAsStringSync('disposable');
      }
      final bootstrap = Directory(
        '${support.path}/$groupMediaIosReceiverBootstrapDirectory',
      )..createSync();
      File('${bootstrap.path}/request.json').writeAsStringSync('disposable');
      final notificationSupportDirectories = <Directory>[
        Directory('${support.path}/NotificationConversationIds')..createSync(),
        Directory('${support.path}/ReactionNotificationClaims')..createSync(),
      ];
      for (final directory in notificationSupportDirectories) {
        File('${directory.path}/owned').writeAsStringSync('disposable');
      }
      final request =
          File('${documents.path}/$groupMediaIosDisposableResetRequestFile')
            ..writeAsStringSync(
              jsonEncode(<String, Object?>{
                'schema': groupMediaIosDisposableResetRequestSchema,
                'run_id': 'run-269-reset',
                'nonce': 'nonce-269-reset',
                'phase': 'pre',
                'contains_secrets': false,
              }),
            );
      var deleteAllCalls = 0;

      final handled = await runGroupMediaIosDisposableResetIfRequested(
        documentsDirectory: documents,
        databasesDirectory: databases,
        applicationSupportDirectory: support,
        installedProfileId: groupMediaIosDisposableBuildProfile,
        installedBundleId: groupMediaIosDisposableBundleId,
        deleteDefaultSecureStorage: () async => deleteAllCalls++,
        readDefaultSecureStorage: () async => const <String, String>{},
        currentProcessId: 26920,
      );

      expect(handled, isTrue);
      expect(deleteAllCalls, 1);
      expect(request.existsSync(), isFalse);
      expect(outsideDocument.readAsStringSync(), 'preserve');
      expect(outsideDatabase.readAsStringSync(), 'preserve');
      expect(outsideSupport.readAsStringSync(), 'preserve');
      for (final name in ownedDatabaseNames) {
        expect(File('${databases.path}/$name').existsSync(), isFalse);
      }
      for (final name in ownedDocumentFiles) {
        expect(File('${documents.path}/$name').existsSync(), isFalse);
      }
      expect(bootstrap.existsSync(), isFalse);
      for (final directory in notificationSupportDirectories) {
        expect(directory.existsSync(), isFalse);
      }
      for (final name in ownedDocumentDirectories) {
        expect(Directory('${documents.path}/$name').existsSync(), isFalse);
      }
      final receipt =
          jsonDecode(
                File(
                  '${documents.path}/$groupMediaIosDisposableResetReceiptFile',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(receipt, <String, Object?>{
        'schema': groupMediaIosDisposableResetReceiptSchema,
        'run_id': 'run-269-reset',
        'nonce': 'nonce-269-reset',
        'phase': 'pre',
        'process_id': 26920,
        'bundle_id': groupMediaIosDisposableBundleId,
        'profile': groupMediaIosDisposableBuildProfile,
        'keychain_empty': true,
        'database_absent': true,
        'allowlisted_files_absent': true,
        'contains_secrets': false,
      });
      expect(
        await runGroupMediaIosDisposableResetIfRequested(
          documentsDirectory: documents,
          databasesDirectory: databases,
          applicationSupportDirectory: support,
          installedProfileId: groupMediaIosDisposableBuildProfile,
          installedBundleId: groupMediaIosDisposableBundleId,
          deleteDefaultSecureStorage: () async => deleteAllCalls++,
          readDefaultSecureStorage: () async => const <String, String>{},
        ),
        isFalse,
      );
      expect(deleteAllCalls, 1);
    },
  );

  test(
    'P269 dedicated iOS reset rejects production profile and bundle',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'p269-ios-reset-reject-',
      );
      addTearDown(() => root.delete(recursive: true));
      final documents = Directory('${root.path}/documents')..createSync();
      final databases = Directory('${root.path}/databases')..createSync();
      final support = Directory('${root.path}/support')..createSync();
      File(
        '${documents.path}/$groupMediaIosDisposableResetRequestFile',
      ).writeAsStringSync(
        jsonEncode(<String, Object?>{
          'schema': groupMediaIosDisposableResetRequestSchema,
          'run_id': 'run-269-reset',
          'nonce': 'nonce-269-reset',
          'phase': 'post',
          'contains_secrets': false,
        }),
      );
      var destructiveCalls = 0;

      await expectLater(
        runGroupMediaIosDisposableResetIfRequested(
          documentsDirectory: documents,
          databasesDirectory: databases,
          applicationSupportDirectory: support,
          installedProfileId: 'ios.device.production',
          installedBundleId: 'com.mknoon.app',
          deleteDefaultSecureStorage: () async => destructiveCalls++,
          readDefaultSecureStorage: () async => const <String, String>{},
        ),
        throwsStateError,
      );
      expect(destructiveCalls, 0);
    },
  );

  test(
    'P269 dedicated iOS reset retains an active token across interruption and retries exactly',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'p269-ios-reset-interruption-',
      );
      addTearDown(() => root.delete(recursive: true));
      final documents = Directory('${root.path}/documents')..createSync();
      final databases = Directory('${root.path}/databases')..createSync();
      final support = Directory('${root.path}/support')..createSync();
      final staged =
          File('${documents.path}/$groupMediaIosDisposableResetRequestFile')
            ..writeAsStringSync(
              jsonEncode(<String, Object?>{
                'schema': groupMediaIosDisposableResetRequestSchema,
                'run_id': 'run-269-interrupted',
                'nonce': 'nonce-269-interrupted',
                'phase': 'post',
                'contains_secrets': false,
              }),
            );
      var attempts = 0;

      await expectLater(
        runGroupMediaIosDisposableResetIfRequested(
          documentsDirectory: documents,
          databasesDirectory: databases,
          applicationSupportDirectory: support,
          installedProfileId: groupMediaIosDisposableBuildProfile,
          installedBundleId: groupMediaIosDisposableBundleId,
          deleteDefaultSecureStorage: () async {
            attempts += 1;
            throw StateError('injected interruption');
          },
          readDefaultSecureStorage: () async => const <String, String>{},
        ),
        throwsStateError,
      );
      final active = File(
        '${documents.path}/$groupMediaIosDisposableResetActiveRequestFile',
      );
      expect(staged.existsSync(), isFalse);
      expect(active.existsSync(), isTrue);
      expect(
        File(
          '${documents.path}/$groupMediaIosDisposableResetReceiptFile',
        ).existsSync(),
        isFalse,
      );

      expect(
        await runGroupMediaIosDisposableResetIfRequested(
          documentsDirectory: documents,
          databasesDirectory: databases,
          applicationSupportDirectory: support,
          installedProfileId: groupMediaIosDisposableBuildProfile,
          installedBundleId: groupMediaIosDisposableBundleId,
          deleteDefaultSecureStorage: () async => attempts += 1,
          readDefaultSecureStorage: () async => const <String, String>{},
          currentProcessId: 26921,
        ),
        isTrue,
      );
      expect(attempts, 2);
      expect(active.existsSync(), isFalse);
      final receipt =
          jsonDecode(
                File(
                  '${documents.path}/$groupMediaIosDisposableResetReceiptFile',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(receipt['process_id'], 26921);
      expect(receipt['phase'], 'post');
    },
  );

  test(
    'P269 pending reset receipt cannot become final while its active token exists',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'p269-ios-reset-publish-boundary-',
      );
      addTearDown(() => root.delete(recursive: true));
      final documents = Directory('${root.path}/documents')..createSync();
      final databases = Directory('${root.path}/databases')..createSync();
      final support = Directory('${root.path}/support')..createSync();
      _writeDisposableResetRequest(
        documents,
        runId: 'run-269-boundary',
        nonce: 'nonce-269-boundary',
        phase: 'pre',
      );
      final active = File(
        '${documents.path}/$groupMediaIosDisposableResetActiveRequestFile',
      );
      final finalReceipt = File(
        '${documents.path}/$groupMediaIosDisposableResetReceiptFile',
      );
      final pendingReceipt = File('${finalReceipt.path}.tmp');
      final reachedPublishBoundary = Completer<void>();
      final releasePublishBoundary = Completer<void>();

      final execution = runGroupMediaIosDisposableResetIfRequested(
        documentsDirectory: documents,
        databasesDirectory: databases,
        applicationSupportDirectory: support,
        installedProfileId: groupMediaIosDisposableBuildProfile,
        installedBundleId: groupMediaIosDisposableBundleId,
        deleteDefaultSecureStorage: () async {},
        readDefaultSecureStorage: () async => const <String, String>{},
        currentProcessId: 26922,
        beforeFinalResetReceiptPublish: () async {
          reachedPublishBoundary.complete();
          await releasePublishBoundary.future;
        },
      );

      await reachedPublishBoundary.future.timeout(const Duration(seconds: 2));
      expect(active.existsSync(), isTrue);
      expect(pendingReceipt.existsSync(), isTrue);
      expect(finalReceipt.existsSync(), isFalse);
      expect(
        _readJsonObject(pendingReceipt),
        containsPair('nonce', 'nonce-269-boundary'),
      );

      releasePublishBoundary.complete();
      expect(await execution, isTrue);
      expect(active.existsSync(), isFalse);
      expect(pendingReceipt.existsSync(), isFalse);
      expect(finalReceipt.existsSync(), isTrue);
    },
  );

  test(
    'P269 torn writing receipt is discarded and recovery preserves staged A plus B ordering',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'p269-ios-reset-writing-recovery-',
      );
      addTearDown(() => root.delete(recursive: true));
      final documents = Directory('${root.path}/documents')..createSync();
      final databases = Directory('${root.path}/databases')..createSync();
      final support = Directory('${root.path}/support')..createSync();
      _writeDisposableResetRequest(
        documents,
        runId: 'run-269-writing-recovery',
        nonce: 'nonce-269-writing-a',
        phase: 'pre',
      );
      final staged = File(
        '${documents.path}/$groupMediaIosDisposableResetRequestFile',
      );
      final active = File(
        '${documents.path}/$groupMediaIosDisposableResetActiveRequestFile',
      );
      final finalReceipt = File(
        '${documents.path}/$groupMediaIosDisposableResetReceiptFile',
      );
      final pendingReceipt = File('${finalReceipt.path}.tmp');
      final writingReceipt = File('${finalReceipt.path}.writing');
      var secureDeleteCalls = 0;

      await expectLater(
        runGroupMediaIosDisposableResetIfRequested(
          documentsDirectory: documents,
          databasesDirectory: databases,
          applicationSupportDirectory: support,
          installedProfileId: groupMediaIosDisposableBuildProfile,
          installedBundleId: groupMediaIosDisposableBundleId,
          deleteDefaultSecureStorage: () async => secureDeleteCalls += 1,
          readDefaultSecureStorage: () async => const <String, String>{},
          currentProcessId: 26925,
          beforePendingResetReceiptCommit: () async {
            expect(
              _readJsonObject(writingReceipt)['nonce'],
              'nonce-269-writing-a',
            );
            _writeDisposableResetRequest(
              documents,
              runId: 'run-269-writing-recovery',
              nonce: 'nonce-269-writing-b',
              phase: 'post',
            );
            writingReceipt.writeAsStringSync('{"schema":');
            throw StateError('injected crash during receipt publication');
          },
        ),
        throwsStateError,
      );

      expect(secureDeleteCalls, 1);
      expect(active.existsSync(), isTrue);
      expect(_readJsonObject(active)['nonce'], 'nonce-269-writing-a');
      expect(staged.existsSync(), isTrue);
      expect(_readJsonObject(staged)['nonce'], 'nonce-269-writing-b');
      expect(writingReceipt.readAsStringSync(), '{"schema":');
      expect(pendingReceipt.existsSync(), isFalse);
      expect(finalReceipt.existsSync(), isFalse);

      final finalizedNonces = <String>[];
      final handled = await runGroupMediaIosDisposableResetIfRequested(
        documentsDirectory: documents,
        databasesDirectory: databases,
        applicationSupportDirectory: support,
        installedProfileId: groupMediaIosDisposableBuildProfile,
        installedBundleId: groupMediaIosDisposableBundleId,
        deleteDefaultSecureStorage: () async => secureDeleteCalls += 1,
        readDefaultSecureStorage: () async => const <String, String>{},
        currentProcessId: 26926,
        beforeFinalResetReceiptPublish: () async {
          final pending = _readJsonObject(pendingReceipt);
          final activeRequest = _readJsonObject(active);
          expect(activeRequest['run_id'], pending['run_id']);
          expect(activeRequest['nonce'], pending['nonce']);
          expect(activeRequest['phase'], pending['phase']);
          finalizedNonces.add(pending['nonce']! as String);
        },
      );

      expect(handled, isTrue);
      expect(secureDeleteCalls, 3);
      expect(finalizedNonces, <String>[
        'nonce-269-writing-a',
        'nonce-269-writing-b',
      ]);
      expect(staged.existsSync(), isFalse);
      expect(active.existsSync(), isFalse);
      expect(writingReceipt.existsSync(), isFalse);
      expect(pendingReceipt.existsSync(), isFalse);
      expect(
        _readJsonObject(finalReceipt),
        containsPair('nonce', 'nonce-269-writing-b'),
      );
    },
  );

  test(
    'P269 reset recovery drains active request A and a newly staged request B sequentially',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'p269-ios-reset-sequential-',
      );
      addTearDown(() => root.delete(recursive: true));
      final documents = Directory('${root.path}/documents')..createSync();
      final databases = Directory('${root.path}/databases')..createSync();
      final support = Directory('${root.path}/support')..createSync();
      _writeDisposableResetRequest(
        documents,
        runId: 'run-269-sequential',
        nonce: 'nonce-269-a',
        phase: 'pre',
      );
      final staged = File(
        '${documents.path}/$groupMediaIosDisposableResetRequestFile',
      );
      final active = File(
        '${documents.path}/$groupMediaIosDisposableResetActiveRequestFile',
      );
      final finalReceipt = File(
        '${documents.path}/$groupMediaIosDisposableResetReceiptFile',
      );
      final pendingReceipt = File('${finalReceipt.path}.tmp');
      var secureDeleteCalls = 0;

      await expectLater(
        runGroupMediaIosDisposableResetIfRequested(
          documentsDirectory: documents,
          databasesDirectory: databases,
          applicationSupportDirectory: support,
          installedProfileId: groupMediaIosDisposableBuildProfile,
          installedBundleId: groupMediaIosDisposableBundleId,
          deleteDefaultSecureStorage: () async => secureDeleteCalls += 1,
          readDefaultSecureStorage: () async => const <String, String>{},
          currentProcessId: 26923,
          beforeFinalResetReceiptPublish: () async {
            expect(_readJsonObject(pendingReceipt)['nonce'], 'nonce-269-a');
            expect(_readJsonObject(active)['nonce'], 'nonce-269-a');
            expect(finalReceipt.existsSync(), isFalse);
            _writeDisposableResetRequest(
              documents,
              runId: 'run-269-sequential',
              nonce: 'nonce-269-b',
              phase: 'post',
            );
            throw StateError('injected crash before active retirement');
          },
        ),
        throwsStateError,
      );
      expect(secureDeleteCalls, 1);
      expect(staged.existsSync(), isTrue);
      expect(active.existsSync(), isTrue);
      expect(pendingReceipt.existsSync(), isTrue);
      expect(finalReceipt.existsSync(), isFalse);

      final recoveredNonces = <String>[];
      final handled = await runGroupMediaIosDisposableResetIfRequested(
        documentsDirectory: documents,
        databasesDirectory: databases,
        applicationSupportDirectory: support,
        installedProfileId: groupMediaIosDisposableBuildProfile,
        installedBundleId: groupMediaIosDisposableBundleId,
        deleteDefaultSecureStorage: () async => secureDeleteCalls += 1,
        readDefaultSecureStorage: () async => const <String, String>{},
        currentProcessId: 26924,
        beforeFinalResetReceiptPublish: () async {
          final pending = _readJsonObject(pendingReceipt);
          final activeRequest = _readJsonObject(active);
          expect(activeRequest['run_id'], pending['run_id']);
          expect(activeRequest['nonce'], pending['nonce']);
          expect(activeRequest['phase'], pending['phase']);
          expect(finalReceipt.existsSync(), isFalse);
          recoveredNonces.add(pending['nonce']! as String);
        },
      );

      expect(handled, isTrue);
      expect(secureDeleteCalls, 2);
      expect(recoveredNonces, <String>['nonce-269-a', 'nonce-269-b']);
      expect(staged.existsSync(), isFalse);
      expect(active.existsSync(), isFalse);
      expect(pendingReceipt.existsSync(), isFalse);
      expect(_readJsonObject(finalReceipt), <String, Object?>{
        'schema': groupMediaIosDisposableResetReceiptSchema,
        'run_id': 'run-269-sequential',
        'nonce': 'nonce-269-b',
        'phase': 'post',
        'process_id': 26924,
        'bundle_id': groupMediaIosDisposableBundleId,
        'profile': groupMediaIosDisposableBuildProfile,
        'keychain_empty': true,
        'database_absent': true,
        'allowlisted_files_absent': true,
        'contains_secrets': false,
      });
    },
  );

  test(
    'P269 reset rejects symlink directory and pipe protocol tokens before mutation',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'p269-ios-reset-token-types-',
      );
      addTearDown(() => root.delete(recursive: true));
      final outside = File('${root.path}/outside-sentinel')
        ..writeAsStringSync('preserve');
      var destructiveCalls = 0;

      Future<void> expectRejected(Directory documents) async {
        final databases = Directory('${documents.path}-databases')
          ..createSync();
        final support = Directory('${documents.path}-support')..createSync();
        await expectLater(
          runGroupMediaIosDisposableResetIfRequested(
            documentsDirectory: documents,
            databasesDirectory: databases,
            applicationSupportDirectory: support,
            installedProfileId: groupMediaIosDisposableBuildProfile,
            installedBundleId: groupMediaIosDisposableBundleId,
            deleteDefaultSecureStorage: () async => destructiveCalls += 1,
            readDefaultSecureStorage: () async => const <String, String>{},
          ),
          throwsFormatException,
        );
      }

      final symlinkDocuments = Directory('${root.path}/symlink')..createSync();
      _writeDisposableResetRequest(
        symlinkDocuments,
        runId: 'run-269-symlink',
        nonce: 'nonce-269-symlink',
        phase: 'pre',
      );
      Link(
        '${symlinkDocuments.path}/$groupMediaIosDisposableResetActiveRequestFile',
      ).createSync(outside.path);
      await expectRejected(symlinkDocuments);

      final directoryDocuments = Directory('${root.path}/directory')
        ..createSync();
      Directory(
        '${directoryDocuments.path}/$groupMediaIosDisposableResetReceiptFile',
      ).createSync();
      await expectRejected(directoryDocuments);

      if (Platform.isMacOS || Platform.isLinux) {
        final pipeDocuments = Directory('${root.path}/pipe')..createSync();
        final pipePath =
            '${pipeDocuments.path}/$groupMediaIosDisposableResetReceiptFile.tmp';
        final mkfifo = await Process.run('mkfifo', <String>[pipePath]);
        expect(mkfifo.exitCode, 0);
        await expectRejected(pipeDocuments);
      }

      final writingDocuments = Directory('${root.path}/writing-directory')
        ..createSync();
      Directory(
        '${writingDocuments.path}/$groupMediaIosDisposableResetReceiptFile.writing',
      ).createSync();
      await expectRejected(writingDocuments);

      expect(destructiveCalls, 0);
      expect(outside.readAsStringSync(), 'preserve');
    },
  );

  test(
    'P269 reset rejects links nested below an owned directory and preserves outside sentinels',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'p269-ios-reset-owned-link-',
      );
      addTearDown(() => root.delete(recursive: true));
      final documents = Directory('${root.path}/documents')..createSync();
      final databases = Directory('${root.path}/databases')..createSync();
      final support = Directory('${root.path}/support')..createSync();
      final outside = File('${root.path}/outside-sentinel')
        ..writeAsStringSync('preserve');
      final media = Directory('${documents.path}/media')..createSync();
      final ownedFile = File('${media.path}/owned')
        ..writeAsStringSync('disposable');
      final nestedLink = Link('${media.path}/outside-link')
        ..createSync(outside.path);
      final request = _writeDisposableResetRequest(
        documents,
        runId: 'run-269-owned-link',
        nonce: 'nonce-269-owned-link',
        phase: 'post',
      );
      var destructiveCalls = 0;

      await expectLater(
        runGroupMediaIosDisposableResetIfRequested(
          documentsDirectory: documents,
          databasesDirectory: databases,
          applicationSupportDirectory: support,
          installedProfileId: groupMediaIosDisposableBuildProfile,
          installedBundleId: groupMediaIosDisposableBundleId,
          deleteDefaultSecureStorage: () async => destructiveCalls += 1,
          readDefaultSecureStorage: () async => const <String, String>{},
        ),
        throwsFormatException,
      );

      expect(destructiveCalls, 0);
      expect(request.existsSync(), isTrue);
      expect(ownedFile.readAsStringSync(), 'disposable');
      expect(nestedLink.existsSync(), isTrue);
      expect(outside.readAsStringSync(), 'preserve');
    },
  );

  test(
    'P269 dedicated iOS reset bootstrap precedes Firebase SQLCipher and shared namespaces',
    () {
      final mainSource = File('lib/main.dart').readAsStringSync();
      final productionSource = File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsStringSync();
      final compositionSource = File(
        'lib/debug/debug_e2e_composition_root.dart',
      ).readAsStringSync();
      expect(
        mainSource,
        contains(
          'runApplicationBootstrap(\n'
          '    bootstrapFactory: ProductionApplicationBootstrap.new,',
        ),
        reason: 'the public entrypoint must delegate before composition starts',
      );
      final reset = productionSource.indexOf(
        'DebugE2ECompositionRoot.runDisposableResetIfRequested(',
      );
      expect(reset, greaterThanOrEqualTo(0));
      for (final boundary in <String>[
        "StartupTiming.instance.mark('app_start')",
        'ShareIntentService()',
        'FirebaseReadiness(',
        'openEncryptedDatabase(',
        'FlutterSecureKeyStore(appleAccessGroup:',
      ]) {
        expect(
          reset,
          lessThan(productionSource.indexOf(boundary)),
          reason: 'reset must precede $boundary',
        );
      }
      expect(
        compositionSource,
        contains('isGroupMediaIosDisposableProfile && !Platform.isIOS'),
      );
      expect(
        compositionSource,
        contains('isGroupMediaAndroidDisposableProfile && !Platform.isAndroid'),
      );
      expect(
        compositionSource,
        contains('runGroupMediaIosDisposableResetIfRequested('),
      );
      expect(
        compositionSource,
        contains(
          "import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;",
        ),
      );
      expect(
        compositionSource,
        contains(
          'final resetDatabasesPathProbe = sqlcipher.getDatabasesPath();',
        ),
      );
      final nativeSource = File(
        'ios/Runner/IosReceiverBootstrapHandoff.swift',
      ).readAsStringSync();
      expect(
        nativeSource,
        contains(
          'static let relativeDirectory = '
          '"$groupMediaIosReceiverBootstrapDirectory"',
        ),
      );
    },
  );
}

MediaAttachment _attachment(
  String messageId,
  String id, {
  required String status,
}) => MediaAttachment(
  id: id,
  messageId: messageId,
  mime: 'image/jpeg',
  size: 8,
  mediaType: 'image',
  downloadStatus: status,
  ownerLane: MediaOwnerLane.group,
  createdAt: '2026-07-22T00:00:00.000Z',
);

Map<String, dynamic> _config({
  required String phase,
  required String role,
  String? mediaPhase,
  String? groupId,
  String? messageId,
  String? attachmentId,
  String? marker,
  String? receiverAccountPeerId,
  String? receiverTransportPeerId,
}) => <String, dynamic>{
  'schema': groupMediaIosBackgroundE2ECommandSchema,
  'transport_action': groupMediaIosBackgroundE2EAction,
  'scenario': groupMediaIosBackgroundScenario,
  'stepId': 'p269-ios-$phase-run-269',
  'phase': phase,
  'role': role,
  'runId': 'run-269',
  'nonce': 'nonce-269',
  'mediaPhase': mediaPhase,
  'groupId': groupId,
  'messageId': messageId,
  'attachmentId': attachmentId,
  'marker': marker,
  'receiverAccountPeerId': receiverAccountPeerId,
  'receiverTransportPeerId': receiverTransportPeerId,
  'peerQrPayload': null,
  'peerMlKemPublicKey': null,
};

Future<void> _waitUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('condition did not become true');
}

Future<Future<void> Function()> _reserveNoopCriticalTask() async => () async {};

File _writeDisposableResetRequest(
  Directory documents, {
  required String runId,
  required String nonce,
  required String phase,
}) =>
    File('${documents.path}/$groupMediaIosDisposableResetRequestFile')
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{
          'schema': groupMediaIosDisposableResetRequestSchema,
          'run_id': runId,
          'nonce': nonce,
          'phase': phase,
          'contains_secrets': false,
        }),
      );

Map<String, Object?> _readJsonObject(File file) {
  final decoded = jsonDecode(file.readAsStringSync());
  return (decoded as Map).map<String, Object?>(
    (key, value) => MapEntry('$key', value),
  );
}
