@Tags(['device'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/app_owned_media_path_authority.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/picture_in_picture_gateway.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_picture_in_picture_controller.dart';
import 'package:flutter_app/shared/widgets/media/media_video_resume_controller.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'support/received_video_picture_in_picture_fixture_seed.dart';

const _proofPlatform = String.fromEnvironment('PIP_PROOF_PLATFORM');
const _proofScenario = String.fromEnvironment('PIP_PROOF_SCENARIO');
const _proofPackage = String.fromEnvironment('PIP_PROOF_PACKAGE');
final _proofSessionId = 'plan243-${_proofScenario.replaceAll('-', '_')}';
const _allowedScenarios = <String>{
  'return',
  'close',
  'process-recreation',
  'completion',
  'engine-detach',
  'interruption',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'shared Android video-only PiP lifecycle, completion, engine detach, and interruption',
    (tester) async {
      expect(_proofPlatform, 'android');
      expect(_allowedScenarios, contains(_proofScenario));

      final fixture = await waitForReceivedVideoPictureInPictureFixture();
      if (_proofScenario == 'process-recreation' &&
          await _isProcessRelaunchPhase()) {
        debugPrint(
          '[PIP_PROOF] PROCESS_RECREATION_EMPTY fixture=verified '
          'nativeReplay=false scenario=process-recreation '
          'session=$_proofSessionId package=$_proofPackage',
        );
        return;
      }

      final startPositionMs = _proofScenario == 'completion' ? 69000 : 4000;
      const attachment = 'plan243-proof-video';
      final protectedItem = MediaViewerItem(
        attachmentId: 'plan243-protected-unowned-video',
        messageId: 'plan243-protected-unowned-message',
        kind: MediaViewerKind.video,
        mime: 'video/mp4',
        localPath: fixture.path,
        sizeBytes: receivedVideoPictureInPictureFixtureBytes,
        durationMs: receivedVideoPictureInPictureFixtureDurationMs,
        canEnterPictureInPicture: true,
        protection: const MediaViewerProtection(isProtected: true),
      );
      final protectedGateway = _ProofPictureInPictureGateway(
        PictureInPictureChannelGateway.platform(),
      );
      final protectedResumeStore = _ProofResumeStore(
        item: protectedItem,
        initialPositionMs: 0,
      );
      MediaPictureInPictureController? protectedController;
      var protectedAuthorizationLoads = 0;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FullScreenTypedMediaViewer(
            items: <MediaViewerItem>[protectedItem],
            resumeStore: protectedResumeStore,
            pictureInPictureControllerFactory:
                ({required reloadCurrent, required restorePlayback}) {
                  return protectedController = MediaPictureInPictureController(
                    gateway: protectedGateway,
                    pathAuthority: IoAppOwnedMediaPathAuthority(),
                    reloadCurrent: reloadCurrent,
                    resumeStore: protectedResumeStore,
                    restorePlayback: restorePlayback,
                    sessionIdFactory: () => 'plan243-protected-negative',
                  );
                },
            loadPictureInPictureAuthorization: (current) async {
              protectedAuthorizationLoads++;
              return MediaPictureInPictureAuthorization(
                item: current,
                generation: 243,
                policyState: MediaPictureInPicturePolicyState.protected,
                isIncoming: true,
                isTransferComplete: true,
                routeActive: true,
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byKey(const ValueKey('media_action_picture_in_picture')),
        findsNothing,
        reason:
            'The production viewer must keep PiP absent for a protected, '
            'unowned video.',
      );
      expect(protectedAuthorizationLoads, 0);
      expect(protectedGateway.capabilityCalls, 0);
      expect(protectedGateway.startCalls, 0);
      expect(protectedGateway.activateCalls, 0);
      expect(protectedGateway.stopCalls, 0);
      debugPrint(
        '[PIP_PROOF] PROTECTED_NEGATIVE control=absent gatewayStart=false '
        'nativeOwner=false scenario=$_proofScenario',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await protectedController?.dispose();

      final item = MediaViewerItem(
        attachmentId: attachment,
        messageId: 'plan243-incoming-message',
        kind: MediaViewerKind.video,
        mime: 'video/mp4',
        owner: MediaOwnerLane.direct,
        localPath: fixture.path,
        sizeBytes: receivedVideoPictureInPictureFixtureBytes,
        durationMs: receivedVideoPictureInPictureFixtureDurationMs,
        canEnterPictureInPicture: true,
      );
      final authorization = MediaPictureInPictureAuthorization(
        item: item,
        generation: 243,
        policyState: MediaPictureInPicturePolicyState.ordinary,
        isIncoming: true,
        isTransferComplete: true,
        routeActive: true,
      );
      final resumeStore = _ProofResumeStore(
        item: item,
        initialPositionMs: startPositionMs,
      );
      final gateway = _ProofPictureInPictureGateway(
        PictureInPictureChannelGateway.platform(),
      );
      final ledger = _PictureInPictureEventLedger(gateway.events);
      MediaPictureInPictureController? controller;
      addTearDown(() async {
        await controller?.dispose();
        await ledger.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FullScreenTypedMediaViewer(
            items: <MediaViewerItem>[item],
            resumeStore: resumeStore,
            pictureInPictureControllerFactory:
                ({required reloadCurrent, required restorePlayback}) {
                  return controller = MediaPictureInPictureController(
                    gateway: gateway,
                    pathAuthority: IoAppOwnedMediaPathAuthority(),
                    reloadCurrent: reloadCurrent,
                    resumeStore: resumeStore,
                    restorePlayback: restorePlayback,
                    sessionIdFactory: () => _proofSessionId,
                  );
                },
            loadPictureInPictureAuthorization: (current) async {
              if (current.owner != item.owner ||
                  current.messageId != item.messageId ||
                  current.attachmentId != item.attachmentId ||
                  current.localPath != item.localPath) {
                return null;
              }
              return authorization;
            },
          ),
        ),
      );
      await _pumpUntilPictureInPictureReady(tester);
      final action = find.byKey(
        const ValueKey('media_action_picture_in_picture'),
      );
      expect(action, findsOneWidget);
      expect(
        tester.widget<IconButton>(action).onPressed,
        isNotNull,
        reason: 'The production viewer must own one enabled explicit PiP tap.',
      );
      final preHandoffUi = await _waitForFlutterPlaybackUi(
        tester,
        playing: true,
        checkpointMs: startPositionMs,
      );
      await _resetHostCaptureAck('flutter-owner-ready');
      debugPrint(
        '[PIP_PROOF] FLUTTER_OWNER_READY scenario=$_proofScenario '
        'controls=true timeVisible=true playing=true '
        'positionMs=${preHandoffUi.positionMs}',
      );
      await _waitForHostCaptureAck('flutter-owner-ready');
      await tester.tap(action);
      await tester.pump();

      final ready = await ledger.waitFor(PictureInPictureState.nativeReady);
      expect(ready.attachment, attachment);
      expect(ready.positionMs, greaterThanOrEqualTo(startPositionMs));
      expect(ready.durationMs, receivedVideoPictureInPictureFixtureDurationMs);
      final active = await ledger.waitFor(PictureInPictureState.active);
      expect(active.positionMs, greaterThanOrEqualTo(startPositionMs));
      debugPrint(
        '[PIP_PROOF] ACTIVE scenario=$_proofScenario '
        'attachmentPrefix=plan243 durationMs=${active.durationMs} '
        'productionViewer=true incoming=true videoOnly=true',
      );

      if (_proofScenario == 'process-recreation') {
        await _markProcessRecreationPhase();
        debugPrint('[PIP_PROOF] PROCESS_RECREATION_KILL_READY');
        await Future<void>.delayed(const Duration(minutes: 10));
        fail('The host did not terminate the process-recreation phase.');
      }

      final terminal = await ledger.waitForTerminal(
        timeout: const Duration(minutes: 5),
      );
      await controller!.drain();
      switch (_proofScenario) {
        case 'return':
          expect(terminal.state, PictureInPictureState.restoring);
          expect(terminal.reason, PictureInPictureTerminalReason.systemReturn);
          expect(terminal.positionMs, greaterThan(startPositionMs));
        case 'close':
          expect(terminal.state, PictureInPictureState.stopped);
          expect(terminal.reason, PictureInPictureTerminalReason.systemClose);
          expect(terminal.positionMs, greaterThan(startPositionMs));
        case 'completion':
          expect(terminal.state, PictureInPictureState.completed);
          expect(terminal.reason, PictureInPictureTerminalReason.completed);
          expect(terminal.positionMs, 0);
        case 'engine-detach':
          expect(terminal.state, PictureInPictureState.stopped);
          expect(
            terminal.reason,
            PictureInPictureTerminalReason.flutterEngineDetached,
          );
        case 'interruption':
          expect(terminal.state, PictureInPictureState.stopped);
          expect(terminal.reason, PictureInPictureTerminalReason.interrupted);
        case 'process-recreation':
          fail('Process recreation must terminate before terminal waiting.');
      }
      expect(
        resumeStore.positionMs,
        _proofScenario == 'completion'
            ? 0
            : greaterThanOrEqualTo(startPositionMs),
      );
      if (_proofScenario == 'return' || _proofScenario == 'close') {
        final shouldPlay = _proofScenario == 'return';
        final restoredUi = await _waitForFlutterPlaybackUi(
          tester,
          playing: shouldPlay,
          checkpointMs: terminal.positionMs,
        );
        expect(resumeStore.positionMs, terminal.positionMs);
        await _resetHostCaptureAck('flutter-owner-restored');
        debugPrint(
          '[PIP_PROOF] FLUTTER_OWNER_RESTORED scenario=$_proofScenario '
          'controls=true timeVisible=true playing=$shouldPlay '
          'checkpointMs=${terminal.positionMs} '
          'displayPositionMs=${restoredUi.positionMs}',
        );
        await _waitForHostCaptureAck('flutter-owner-restored');
      }
      debugPrint(
        '[PIP_PROOF] TERMINAL scenario=$_proofScenario '
        'state=${terminal.state.name} reason=${terminal.reason?.name} '
        'positionMs=${terminal.positionMs}',
      );
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

Future<({String label, int positionMs})> _waitForFlutterPlaybackUi(
  WidgetTester tester, {
  required bool playing,
  required int checkpointMs,
}) async {
  final controls = find.byKey(const ValueKey('media_controls_play_pause'));
  final time = find.byKey(const ValueKey('media_controls_time'));
  final expectedIcon = playing ? Icons.pause_rounded : Icons.play_arrow_rounded;
  for (var attempt = 0; attempt < 300; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (controls.evaluate().length != 1 || time.evaluate().length != 1) {
      continue;
    }
    if (find
            .descendant(of: controls, matching: find.byIcon(expectedIcon))
            .evaluate()
            .length !=
        1) {
      continue;
    }
    final label = tester.widget<Text>(time).data;
    final positionMs = _proofPositionMs(label);
    if (label == null || positionMs == null) continue;
    final matchesCheckpoint = playing
        ? positionMs >= (checkpointMs ~/ 1000) * 1000
        : (positionMs - checkpointMs).abs() < 1000;
    if (matchesCheckpoint) return (label: label, positionMs: positionMs);
  }
  throw StateError(
    'Flutter playback controls did not settle to playing=$playing at '
    'checkpointMs=$checkpointMs.',
  );
}

int? _proofPositionMs(String? label) {
  if (label == null) return null;
  final elapsed = label.split(' / ').firstOrNull;
  if (elapsed == null) return null;
  final fields = elapsed.split(':').map(int.tryParse).toList(growable: false);
  if (fields.any((field) => field == null) ||
      (fields.length != 2 && fields.length != 3)) {
    return null;
  }
  final values = fields.cast<int>();
  final seconds = values.length == 2
      ? values[0] * 60 + values[1]
      : values[0] * 3600 + values[1] * 60 + values[2];
  return seconds * 1000;
}

Future<File> _hostCaptureAck(String phase) async {
  final documents = await getApplicationDocumentsDirectory();
  return File(
    p.join(documents.path, 'media', 'plan243-proof', '.$phase-captured-v1'),
  );
}

Future<void> _resetHostCaptureAck(String phase) async {
  final marker = await _hostCaptureAck(phase);
  if (marker.existsSync()) await marker.delete();
}

Future<void> _waitForHostCaptureAck(String phase) async {
  final marker = await _hostCaptureAck(phase);
  for (var attempt = 0; attempt < 1200; attempt++) {
    if (marker.existsSync()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Host did not acknowledge the $phase ownership capture.');
}

Future<void> _pumpUntilPictureInPictureReady(WidgetTester tester) async {
  final action = find.byKey(const ValueKey('media_action_picture_in_picture'));
  for (var attempt = 0; attempt < 300; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (action.evaluate().length == 1 &&
        tester.widget<IconButton>(action).onPressed != null) {
      return;
    }
  }
  throw StateError(
    'Production viewer PiP action did not become enabled before timeout.',
  );
}

Future<File> _processPhaseMarker() async {
  final documents = await getApplicationDocumentsDirectory();
  return File(
    p.join(
      documents.path,
      'media',
      'plan243-proof',
      '.process-recreation-phase-v1',
    ),
  );
}

Future<bool> _isProcessRelaunchPhase() async {
  final marker = await _processPhaseMarker();
  if (!marker.existsSync()) return false;
  final value = await marker.readAsString();
  if (value != 'active-native-owner-v1') {
    throw StateError('Process-recreation phase marker was malformed.');
  }
  await marker.delete();
  return true;
}

Future<void> _markProcessRecreationPhase() async {
  final marker = await _processPhaseMarker();
  await marker.writeAsString('active-native-owner-v1', flush: true);
}

class _PictureInPictureEventLedger {
  _PictureInPictureEventLedger(Stream<PictureInPictureEvent> events) {
    _subscription = events.listen(
      (event) {
        _events.add(event);
        for (final waiter in List<_EventWaiter>.of(_waiters)) {
          if (!waiter.completer.isCompleted && waiter.matches(event)) {
            waiter.completer.complete(event);
            _waiters.remove(waiter);
          }
        }
      },
      onError: (Object error, StackTrace stack) {
        for (final waiter in List<_EventWaiter>.of(_waiters)) {
          if (!waiter.completer.isCompleted) {
            waiter.completer.completeError(error, stack);
          }
        }
        _waiters.clear();
      },
    );
  }

  final List<PictureInPictureEvent> _events = <PictureInPictureEvent>[];
  final List<_EventWaiter> _waiters = <_EventWaiter>[];
  late final StreamSubscription<PictureInPictureEvent> _subscription;

  Future<PictureInPictureEvent> waitFor(
    PictureInPictureState state, {
    Duration timeout = const Duration(seconds: 30),
  }) => _waitWhere((event) => event.state == state, timeout: timeout);

  Future<PictureInPictureEvent> waitForTerminal({required Duration timeout}) =>
      _waitWhere((event) => event.isTerminal, timeout: timeout);

  Future<PictureInPictureEvent> _waitWhere(
    bool Function(PictureInPictureEvent) matches, {
    required Duration timeout,
  }) async {
    for (final event in _events) {
      if (matches(event)) return event;
    }
    final waiter = _EventWaiter(matches);
    _waiters.add(waiter);
    return waiter.completer.future.timeout(timeout);
  }

  Future<void> dispose() async {
    for (final waiter in _waiters) {
      if (!waiter.completer.isCompleted) {
        waiter.completer.completeError(
          StateError('PiP proof event ledger was disposed.'),
        );
      }
    }
    _waiters.clear();
    await _subscription.cancel();
  }
}

class _EventWaiter {
  _EventWaiter(this.matches);

  final bool Function(PictureInPictureEvent) matches;
  final Completer<PictureInPictureEvent> completer =
      Completer<PictureInPictureEvent>();
}

class _ProofResumeStore implements MediaViewerResumeStore {
  _ProofResumeStore({required this.item, required int initialPositionMs})
    : positionMs = initialPositionMs;

  final MediaViewerItem item;
  int positionMs;

  bool _matches(MediaViewerItem candidate) =>
      candidate.owner == item.owner &&
      candidate.messageId == item.messageId &&
      candidate.attachmentId == item.attachmentId;

  @override
  Future<int?> readResumePosition(MediaViewerItem candidate) async {
    if (!_matches(candidate)) {
      throw StateError('PiP proof resume read escaped the current video row.');
    }
    return positionMs;
  }

  @override
  Future<void> writeResumePosition(
    MediaViewerItem candidate,
    int nextPositionMs,
  ) async {
    if (!_matches(candidate) || nextPositionMs < 0) {
      throw StateError('PiP proof resume write escaped the current video row.');
    }
    positionMs = nextPositionMs;
  }
}

class _ProofPictureInPictureGateway implements PictureInPictureGateway {
  _ProofPictureInPictureGateway(this._delegate);

  final PictureInPictureGateway _delegate;
  int capabilityCalls = 0;
  int startCalls = 0;
  int activateCalls = 0;
  int stopCalls = 0;

  @override
  Stream<PictureInPictureEvent> get events => _delegate.events;

  @override
  Future<PictureInPictureCapability> capability() {
    capabilityCalls++;
    return _delegate.capability();
  }

  @override
  Future<PictureInPictureStartOutcome> start(PictureInPictureRequest request) {
    startCalls++;
    return _delegate.start(request);
  }

  @override
  Future<PictureInPictureCommandResult> activate(
    String session,
    String attachment,
  ) {
    activateCalls++;
    return _delegate.activate(session, attachment);
  }

  @override
  Future<PictureInPictureCommandResult> stop(
    String session,
    String attachment,
  ) {
    stopCalls++;
    return _delegate.stop(session, attachment);
  }

  @override
  Future<void> dispose() => _delegate.dispose();
}
