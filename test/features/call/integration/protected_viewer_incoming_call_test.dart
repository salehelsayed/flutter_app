import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/foreground_call_capability.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/presentation/foreground_call_overlay.dart';
import 'package:flutter_app/features/call/presentation/screens/active_call_screen.dart';
import 'package:flutter_app/features/call/presentation/screens/incoming_call_screen.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_viewer_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_private_media_viewer.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/fake_mic_permission_gateway.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

final _peer = TestEd25519Identity.fromSeedByte(104);
final _caller = TestEd25519Identity.fromSeedByte(105);
final _otherCaller = TestEd25519Identity.fromSeedByte(106);
final _firstCall = CallId.parse('11111111-1111-4111-8111-111111111111');
final _busyCall = CallId.parse('22222222-2222-4222-8222-222222222222');
final _nextCall = CallId.parse('33333333-3333-4333-8333-333333333333');
final _lateBusyCall = CallId.parse('44444444-4444-4444-8444-444444444444');
final _now = DateTime.utc(2026, 10, 30, 12);

void main() {
  for (final mode in [PrivateMediaMode.protected, PrivateMediaMode.viewOnce]) {
    testWidgets(
      'CALL-004/VC-016/VC-018 ${mode.name} real viewer stays protected under incoming call; capture closes it without replacing the busy call and cleanup permits the next accepted call',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.physicalSize = const Size(900, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        try {
          await tester.runAsync(() async {
            final root = await Directory.systemTemp.createTemp('viewer-call-');
            final previousPaths = PathProviderPlatform.instance;
            final previousCache = MediaFileManager.cachedDocumentsDir;
            PathProviderPlatform.instance = _Documents(root.path);
            MediaFileManager.cacheDocumentsDir(root.path);
            final db = await MediaRepositoryRealDbFixture.create(
              databasePath: '${root.path}/identity.db',
              databaseFactoryOverride: databaseFactoryFfiNoIsolate,
            );
            final nativeEvents = StreamController<Object?>.broadcast(
              sync: true,
            );
            final protectionCalls = <String>[];
            final protection = PrivateMediaProtectionCoordinator(
              nativeEvents: nativeEvents.stream,
              invokeMethod: (method, arguments) async {
                if (method == 'exit') {
                  expect(
                    find.byType(DirectPrivateMediaViewer),
                    findsNothing,
                    reason:
                        'native protection may release only after the byte-bearing route is removed',
                  );
                }
                protectionCalls.add(method);
                return {'ok': true, 'protectionActive': method == 'enter'};
              },
            );
            final files = MediaFileManager();
            final viewer = DirectPrivateMediaViewerController(
              loadCurrentRows: (identity) async {
                final attachments = await db.repo.getAttachmentsForMessage(
                  identity.messageId,
                  owner: MediaOwnerLane.direct,
                );
                return DirectPrivateMediaCurrentRows(
                  parent: await db.messageRepo.getMessage(identity.messageId),
                  attachment: attachments
                      .where((row) => row.id == identity.attachmentId)
                      .firstOrNull,
                );
              },
              lifecycleEngine: PrivateMediaLifecycleEngine(
                adapter: DirectPrivateMediaLifecycle(
                  messageRepository: db.messageRepo,
                  mediaAttachmentRepository: db.repo,
                  mediaFileManager: files,
                ),
                lifecycleLock: db.repo.lifecycleLock,
                nowMs: () => _now.millisecondsSinceEpoch,
              ),
              protectionCoordinator: protection,
            );
            final calls = _CallSurface();
            DirectPrivateMediaViewerGrant? grant;
            try {
              const messageId = 'private-call-parent';
              const attachmentId = 'private-call-image';
              final relativePath = 'media/${_peer.peerId}/$attachmentId.png';
              final image = File('${root.path}/$relativePath');
              await image.parent.create(recursive: true);
              await image.writeAsBytes(
                base64Decode(
                  'iVBORw0KGgoAAAANSUhEUgAAAEAAAAAgCAIAAAAt/+nTAAAATklEQVR4nO3PUQkAIBTAwNfAfmY3jCH8OITBAtxm7fN1wwUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjx2AV3NKJdv7voVAAAAAElFTkSuQmCC',
                ),
                flush: true,
              );
              await db.seedDirectParent(messageId, contactPeerId: _peer.peerId);
              await db.db.update(
                'messages',
                {
                  'private_media_policy_version': 1,
                  'private_media_mode': mode.wireValue,
                  'private_media_state': 'available',
                  'private_media_received_at_ms':
                      _now.millisecondsSinceEpoch - 1000,
                  'private_media_clock_high_water_ms':
                      _now.millisecondsSinceEpoch - 1000,
                },
                where: 'id = ?',
                whereArgs: [messageId],
              );
              await db.repo.saveAttachment(
                MediaAttachment(
                  id: attachmentId,
                  messageId: messageId,
                  mime: 'image/png',
                  size: image.lengthSync(),
                  mediaType: 'image',
                  localPath: relativePath,
                  downloadStatus: 'done',
                  createdAt: _now.toIso8601String(),
                  ownerLane: MediaOwnerLane.direct,
                ),
                owner: MediaOwnerLane.direct,
              );
              final navigator = GlobalKey<NavigatorState>();
              await tester.pumpWidget(
                MaterialApp(
                  navigatorKey: navigator,
                  locale: const Locale('en'),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  builder: (_, child) => ForegroundCallOverlay(
                    capability: calls,
                    micPermission: FakeMicPermissionGateway(),
                    loadContactDisplayName: (_) async => 'Incoming caller',
                    now: () => _now,
                    child: child!,
                  ),
                  home: Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () async {
                          final prepared = await viewer.prepareResult(
                            const DirectPrivateMediaViewerIdentity(
                              messageId: messageId,
                              attachmentId: attachmentId,
                            ),
                            const DirectPrivateMediaAlwaysValidContinuityGuard(),
                          );
                          expect(prepared.isGranted, isTrue);
                          grant = prepared.grant!;
                          await navigator.currentState!.push<void>(
                            MaterialPageRoute(
                              builder: (_) => DirectPrivateMediaViewer(
                                grant: grant!,
                                controller: viewer,
                                capturePlatformOverride: TargetPlatform.android,
                              ),
                            ),
                          );
                        },
                        child: const Text('Open received private image'),
                      ),
                    ),
                  ),
                ),
              );
              await tester.tap(find.text('Open received private image'));
              await _until(tester, () => grant?.firstFrameRecorded == true);
              expect(
                find.semantics.byPredicate(
                  (node) => node.identifier == 'conversation.private.viewer',
                ),
                findsOneWidget,
              );
              expect(protectionCalls, ['enter']);
              expect(grant!.settled, isFalse);

              await calls.receive(_firstCall, _caller.peerId);
              await _until(
                tester,
                () => find.byType(IncomingCallScreen).evaluate().isNotEmpty,
              );
              expect(calls.coordinator.activeSession?.state, CallState.ringing);
              expect(
                find.semantics.byPredicate(
                  (node) => node.identifier == 'conversation.private.viewer',
                ),
                findsNothing,
              );
              expect(
                find.byType(DirectPrivateMediaViewer),
                findsOneWidget,
                reason: 'the retained viewer still owns its protection grant',
              );
              final screen = find.byType(IncomingCallScreen);
              final cover = tester.widget<Scaffold>(
                find
                    .ancestor(of: screen, matching: find.byType(Scaffold))
                    .first,
              );
              expect(
                cover.backgroundColor?.a,
                1,
                reason:
                    'the real incoming screen must cover private pixels opaquely',
              );
              expect(
                tester.getRect(screen),
                tester.getRect(find.byType(ForegroundCallOverlay)),
              );
              expect(protectionCalls, ['enter']);
              expect(grant!.protectionReleased, isFalse);
              expect(
                calls.preparedMediaCallIds,
                isEmpty,
                reason: 'ringing never authorizes microphone capture',
              );
              final beforeBusy = calls.coordinator.activeSession!;
              final busy = await calls.receive(_busyCall, _otherCaller.peerId);
              expect(busy.reason, CallReductionReason.busy);
              expect(busy.decision, CallEventDecision.rejected);
              expect(
                calls.coordinator.activeSession?.callId,
                beforeBusy.callId,
              );
              expect(calls.coordinator.activeSession?.state, beforeBusy.state);
              expect(calls.preparedMediaCallIds, isEmpty);

              // A legitimate native protection event reaches the actual viewer
              // subscription while the independent call overlay is still modal.
              nativeEvents.add({'event': 'captureStarted'});
              await tester.pump();
              expect(
                find.byKey(const ValueKey('private-media-cover')),
                findsOneWidget,
              );
              await _until(tester, () => grant!.protectionReleased);
              expect(grant!.settled, isTrue);
              expect(protectionCalls, ['enter', 'exit']);
              expect(find.byType(DirectPrivateMediaViewer), findsNothing);
              expect(calls.coordinator.activeSession?.callId, _firstCall);
              expect(calls.coordinator.activeSession?.state, CallState.ringing);
              final parent = (await db.messageRepo.getMessage(messageId))!;
              expect(
                parent.privateMediaState,
                mode == PrivateMediaMode.viewOnce
                    ? PrivateMediaLifecycleState.consumed
                    : PrivateMediaLifecycleState.available,
              );
              if (mode == PrivateMediaMode.viewOnce) {
                expect(
                  await db.repo.getAttachmentsForMessage(
                    messageId,
                    owner: MediaOwnerLane.direct,
                  ),
                  isEmpty,
                );
                expect(await image.exists(), isFalse);
              } else {
                expect(await image.exists(), isTrue);
              }

              await tester.tap(find.byTooltip('Decline'));
              await _until(
                tester,
                () =>
                    find.byTooltip('Dismiss call status').evaluate().isNotEmpty,
              );
              expect(calls.coordinator.activeSession, isNull);
              await tester.tap(find.byTooltip('Dismiss call status'));
              await _frames(tester);
              expect(
                find.text('Open received private image').hitTestable(),
                findsOneWidget,
              );
              await calls.receive(_nextCall, _caller.peerId);
              await _until(
                tester,
                () => find.byType(IncomingCallScreen).evaluate().isNotEmpty,
              );
              await tester.tap(find.byTooltip('Answer'));
              await _until(
                tester,
                () => find.byType(ActiveCallScreen).evaluate().isNotEmpty,
              );
              expect(calls.coordinator.activeSession?.callId, _nextCall);
              expect(
                calls.coordinator.activeSession?.state,
                CallState.connected,
              );
              expect(calls.preparedMediaCallIds, [_nextCall]);
              expect(protectionCalls, ['enter', 'exit']);
              final connected = calls.coordinator.activeSession!;
              expect(
                (await calls.receive(
                  _lateBusyCall,
                  _otherCaller.peerId,
                )).reason,
                CallReductionReason.busy,
              );
              expect(calls.coordinator.activeSession?.callId, connected.callId);
              expect(
                calls.coordinator.activeSession?.state,
                CallState.connected,
              );
              expect(
                calls.coordinator.activeSession?.acceptedAt,
                connected.acceptedAt,
              );
              expect(calls.preparedMediaCallIds, [_nextCall]);
              await tester.tap(find.byTooltip('End call'));
              await _frames(tester);
              expect(calls.coordinator.activeSession, isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              await _frames(tester);
              await viewer.dispose();
              await calls.close();
              await nativeEvents.close();
              await db.dispose();
              PathProviderPlatform.instance = previousPaths;
              MediaFileManager.debugResetDocumentsDirCache();
              if (previousCache != null) {
                MediaFileManager.cacheDocumentsDir(previousCache);
              }
              await root.delete(recursive: true);
            }
          });
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}

// Only signaling validation, native capture and media readiness are modeled.
// Canonical transitions/actions, the modal overlay and private route/SQL/file
// lifecycle are production owners. No native secure-surface/audio proof.
class _CallSurface implements ForegroundCallCapability, CallEffectExecutor {
  _CallSurface() {
    coordinator = CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator: CallCleanupCoordinator(const []),
      historyProjector: CallHistoryProjector(_History()),
      effectExecutor: this,
      clock: () => _now,
      idSource: () => _nextCall,
    );
    _subscription = coordinator.snapshots.listen((session) {
      _current = ForegroundCallProjection(
        session: session,
        audio: CallAudioControlState.idle,
      );
      _changes.add(_current);
    });
  }
  late final CallCoordinator coordinator;
  late final StreamSubscription<CallSessionSnapshot> _subscription;
  final _changes = StreamController<ForegroundCallProjection?>.broadcast(
    sync: true,
  );
  ForegroundCallProjection? _current;
  final preparedMediaCallIds = <CallId>[];
  @override
  ForegroundCallProjection? get current => _current;
  @override
  Stream<ForegroundCallProjection?> get changes => _changes.stream;
  Future<CallReduction> receive(CallId id, String peer) => coordinator.dispatch(
    CallEvent(
      type: CallEventType.remoteInvite,
      eventId: 'incoming-${id.value}',
      occurredAt: _now,
      callId: id,
      contactPeerId: peer,
      localAccountPeerId: 'test-local-account',
      localDeviceId: 'test-local-device',
      remoteAccountPeerId: peer,
      remoteDeviceId: 'test-remote-device',
    ),
  );
  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    final type = switch (effect.type) {
      CallEffectType.validateIncomingInvite => CallEventType.incomingValidated,
      CallEffectType.presentIncomingCall => CallEventType.systemUiPresented,
      CallEffectType.prepareAcceptedMedia => CallEventType.negotiationReady,
      CallEffectType.startNegotiation => CallEventType.mediaConnected,
      _ => null,
    };
    if (effect.type == CallEffectType.prepareAcceptedMedia) {
      preparedMediaCallIds.add(snapshot.callId!);
    }
    return type == null
        ? null
        : CallEvent(
            type: type,
            eventId: '${type.name}-${snapshot.callId!.value}',
            occurredAt: _now,
            callId: snapshot.callId,
          );
  }

  Future<ForegroundCallActionResult> _act(CallId id, CallEventType type) async {
    final reduction = await coordinator.dispatch(
      CallEvent(
        type: type,
        eventId: 'user-${type.name}-${id.value}',
        occurredAt: _now,
        callId: id,
      ),
    );
    return reduction.decision == CallEventDecision.applied
        ? ForegroundCallActionResult.applied
        : ForegroundCallActionResult.unavailable;
  }

  @override
  Future<ForegroundCallActionResult> answer(CallId id) =>
      _act(id, CallEventType.answer);
  @override
  Future<ForegroundCallActionResult> decline(CallId id) =>
      _act(id, CallEventType.decline);
  @override
  Future<ForegroundCallActionResult> cancel(CallId id) =>
      _act(id, CallEventType.cancel);
  @override
  Future<ForegroundCallActionResult> end(CallId id) =>
      _act(id, CallEventType.end);
  @override
  Future<ForegroundCallActionResult> setMuted(CallId id, bool muted) async =>
      ForegroundCallActionResult.unavailable;
  @override
  Future<ForegroundCallActionResult> setSpeakerEnabled(
    CallId id,
    bool enabled,
  ) async => ForegroundCallActionResult.unavailable;
  Future<void> close() async {
    await coordinator.dispose();
    await _subscription.cancel();
    await _changes.close();
  }
}

class _History implements CallHistoryRepository {
  final _rows = <CallId, CallHistoryEntry>{};
  @override
  Future<CallHistoryEntry?> getByCallId(CallId id) async => _rows[id];
  @override
  Future<List<CallHistoryEntry>> listForContact(String peer) async =>
      _rows.values.where((row) => row.contactAccountPeerId == peer).toList();
  @override
  Future<void> upsertTerminal(CallHistoryEntry row) async {
    _rows.putIfAbsent(row.callId, () => row);
  }
}

class _Documents extends PathProviderPlatform {
  _Documents(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 250 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    ready(),
    isTrue,
    reason: 'the joined viewer/call lifecycle must settle',
  );
  await _frames(tester);
}
