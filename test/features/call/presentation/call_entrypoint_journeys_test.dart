import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/app/bootstrap/call_signaling_composition.dart';
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_history_access.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_redial_controller.dart';
import 'package:flutter_app/features/call/application/outgoing_call_capability.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/presentation/screens/calls_page.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/fake_just_audio.dart';
import '../../../shared/fakes/fake_mic_permission_gateway.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

final _local = TestEd25519Identity.fromSeedByte(101);
final _selected = TestEd25519Identity.fromSeedByte(102);
final _other = TestEd25519Identity.fromSeedByte(103);
final _pastCall = CallId.parse('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
final _otherPastCall = CallId.parse('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
final _now = DateTime.utc(2026, 10, 30, 12);

enum _Entry { chatHeader, historyRow }

enum _Situation { eligible, blocked, noEligibleEndpoint, alreadyCalling }

void main() {
  for (final entry in _Entry.values) {
    for (final situation in _Situation.values) {
      testWidgets(
        'CALL-001/VC-005 ${entry.name} ${situation.name} selects the exact current contact through common canonical admission without a second call',
        (tester) async {
          installFakeJustAudioPlatform();
          final contacts = InMemoryContactRepository();
          final selected = _contact(
            _selected,
            'Selected contact',
          ).copyWith(isBlocked: situation == _Situation.blocked);
          await contacts.addContact(selected);
          await contacts.addContact(_contact(_other, 'Other contact'));
          final history = _History();
          var serial = 0;
          final coordinator = CallCoordinator(
            reducer: const CallReducer(),
            cleanupCoordinator: CallCleanupCoordinator(const []),
            historyProjector: CallHistoryProjector(history),
            clock: () => _now,
            idSource: () => CallId.parse(
              'cccccccc-cccc-4ccc-8ccc-${(++serial).toString().padLeft(12, '0')}',
            ),
          );
          final graph = _EndpointGraph(coordinator)
            ..endpointEligible = situation != _Situation.noEligibleEndpoint;
          final calls = CallSignalingComposition(
            featureFlags: const {
              'voice_call_capability_v1': true,
              'voice_call_outgoing_enabled': true,
              'voice_call_incoming_enabled': true,
              'voice_call_turn_enabled': true,
            },
            platform: CallEndpointPlatform.android,
            awaitReadiness: () async {},
            buildGraph: () async => graph,
            requestOutgoingMicrophonePermission: () async =>
                MicPermissionStatus.granted,
            isForeground: () => true,
          );
          final p2p = FakeP2PService();
          final messages = InMemoryMessageRepository();
          final listener = ChatMessageListener(
            chatMessageStream: const Stream.empty(),
            messageRepo: messages,
            contactRepo: contacts,
          );
          try {
            await calls.start();
            expect(calls.isStarted, isTrue);
            CallSessionSnapshot? existing;
            if (situation == _Situation.alreadyCalling) {
              await coordinator.placeCall(
                contactPeerId: _other.peerId,
                localAccountPeerId: _local.peerId,
                localDeviceId: 'test-local-device',
              );
              existing = coordinator.activeSession;
              expect(existing, isNotNull);
            }
            final identity = FakeIdentityRepository()
              ..seed(
                FakeIdentityRepository.makeIdentity(
                  peerId: _local.peerId,
                  publicKey: _local.publicKey,
                  privateKey: _local.privateKey,
                ),
              );
            final home = entry == _Entry.chatHeader
                ? ConversationWired(
                    contact: selected,
                    identityRepo: identity,
                    messageRepo: messages,
                    chatMessageListener: listener,
                    p2pService: p2p,
                    contactRepo: contacts,
                    outgoingCallCapability: calls,
                    micPermissionGateway: FakeMicPermissionGateway(),
                  )
                : CallsPage(
                    browser: history,
                    changes: const Stream.empty(),
                    history: history,
                    redial: CallRedialController(
                      capability: () => calls,
                      contactAllowed: (id) async {
                        final current = await contacts.getContact(id);
                        return current != null && !current.isBlocked;
                      },
                    ),
                  );
            await tester.pumpWidget(
              MaterialApp(
                locale: const Locale('en'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: home,
              ),
            );
            await _frames(tester);
            final action = entry == _Entry.chatHeader
                ? find.byIcon(Icons.call_outlined)
                : find.descendant(
                    of: find.byKey(ValueKey('history-${_pastCall.value}')),
                    matching: find.byTooltip('Call back'),
                  );
            expect(action, findsOneWidget);
            await tester.tap(action);
            await _frames(tester);

            if (situation == _Situation.eligible) {
              final admitted = coordinator.activeSession!;
              expect(admitted.contactPeerId, _selected.peerId);
              expect(admitted.direction, CallDirection.outgoing);
              expect(admitted.isTerminal, isFalse);
              expect(admitted.callId, isNot(anyOf(_pastCall, _otherPastCall)));
              expect(graph.admittedPeers, [_selected.peerId]);
              // A second real user tap may be presentation-blocked or reach
              // the common owner; neither may create a replacement call.
              if (action.evaluate().isNotEmpty &&
                  action.hitTestable().evaluate().isNotEmpty) {
                await tester.tap(action);
                await _frames(tester);
              }
              expect(coordinator.activeSession?.callId, admitted.callId);
              expect(graph.admittedPeers, [_selected.peerId]);
            } else {
              expect(graph.admittedPeers, isEmpty);
              expect(coordinator.activeSession?.callId, existing?.callId);
              if (existing != null) {
                expect(coordinator.activeSession?.contactPeerId, _other.peerId);
                expect(coordinator.activeSession?.state, existing.state);
              }
              if (entry == _Entry.chatHeader &&
                  situation == _Situation.alreadyCalling) {
                expect(
                  find.text("Couldn't start voice call. Please try again."),
                  findsOneWidget,
                );
              } else {
                expect(
                  find.textContaining('Voice calling is unavailable'),
                  findsOneWidget,
                );
              }
            }
            expect(graph.endpointProbes, everyElement(_selected.peerId));
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            listener.dispose();
            p2p.dispose();
            await calls.shutdown();
            await coordinator.dispose();
          }
        },
      );
    }
  }
}

// The process composition, request fencing, redial guards and coordinator are
// real. This leaf substitutes authenticated endpoint/media/signaling readiness;
// it cannot establish native audio, signed endpoint validation or relay reach.
class _EndpointGraph implements CallSignalingGraphLifecycle {
  _EndpointGraph(this.coordinator);
  final CallCoordinator coordinator;
  bool endpointEligible = true;
  final endpointProbes = <String>[];
  final admittedPeers = <String>[];
  @override
  Future<bool> start() async => true;
  @override
  Future<void> onResume() async {}
  @override
  Future<bool> advertiseCapability() async => true;
  @override
  Future<void> shutdown() async {}
  @override
  Future<bool> isOutgoingCallAvailableFor(String peerId) async {
    endpointProbes.add(peerId);
    return endpointEligible;
  }

  @override
  Future<OutgoingCallStartResult> startOutgoingCall(
    String peerId, {
    OutgoingCallStartRequest? request,
  }) async {
    request?.checkPending();
    final result = await coordinator.placeCall(
      contactPeerId: peerId,
      localAccountPeerId: _local.peerId,
      localDeviceId: 'test-local-device',
      canPlace: () => request?.isCanceled != true,
      onApplied: (reduction) {
        if (reduction.decision == CallEventDecision.applied) {
          request?.admit();
          admittedPeers.add(peerId);
        }
      },
    );
    return result.decision == CallEventDecision.applied
        ? OutgoingCallStartResult.started
        : OutgoingCallStartResult.unavailable;
  }
}

class _History
    implements CallHistoryBrowser, CallHistoryAccess, CallHistoryRepository {
  final terminal = <CallId, CallHistoryEntry>{};
  late final rows = [
    _row(_otherPastCall, _other.peerId, 'Other contact'),
    _row(_pastCall, _selected.peerId, 'Selected contact'),
  ];
  @override
  Future<CallHistoryPage> browse({
    bool missedOnly = false,
    String search = '',
    CallHistoryCursor? cursor,
    int pageSize = 50,
  }) async => CallHistoryPage(rows: rows, total: 2, missed: 2);
  @override
  Future<CallHistoryEntry?> findCall(CallId id) async =>
      rows.where((row) => row.entry.callId == id).firstOrNull?.entry;
  @override
  Future<List<CallHistoryEntry>> recentCallsForContact(String id) async => rows
      .where((row) => row.entry.contactAccountPeerId == id)
      .map((row) => row.entry)
      .toList();
  @override
  Future<CallHistoryEntry?> getByCallId(CallId id) async => terminal[id];
  @override
  Future<List<CallHistoryEntry>> listForContact(String id) async =>
      terminal.values.where((row) => row.contactAccountPeerId == id).toList();
  @override
  Future<void> upsertTerminal(CallHistoryEntry row) async {
    terminal.putIfAbsent(row.callId, () => row);
  }
}

CallHistoryListRow _row(CallId id, String peer, String name) =>
    CallHistoryListRow(
      CallHistoryEntry(
        callId: id,
        contactAccountPeerId: peer,
        direction: CallDirection.incoming,
        terminalReason: CallEndReason.noAnswer,
        status: CallHistoryStatus.missed,
        startedAt: _now.subtract(const Duration(days: 1)),
        endedAt: _now.subtract(const Duration(days: 1)),
        transportRoute: null,
        createdAt: _now.subtract(const Duration(days: 1)),
        updatedAt: _now.subtract(const Duration(days: 1)),
      ),
      name,
    );

ContactModel _contact(TestEd25519Identity identity, String name) =>
    ContactModel(
      peerId: identity.peerId,
      publicKey: identity.publicKey,
      username: name,
      rendezvous: 'test-only-rendezvous',
      signature: 'test-only-signature',
      scannedAt: _now.toIso8601String(),
    );

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
