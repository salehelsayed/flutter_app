import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/app/bootstrap/call_signaling_composition.dart';
import 'package:flutter_app/app/bootstrap/production_call_signaling_graph.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/call/diagnostics/call_diagnostics.dart';
import 'package:flutter_app/core/database/migrations/112_direct_linked_device_addressing.dart';
import 'package:flutter_app/core/database/migrations/117_call_history.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_signaling_service.dart';
import 'package:flutter_app/features/call/application/call_signaling_context_store.dart';
import 'package:flutter_app/features/call/domain/call_signal_v2.dart';
import 'package:flutter_app/features/call/infrastructure/call_mailbox_client.dart';
import 'package:flutter_app/features/call/infrastructure/p2p_call_transport.dart';
import 'package:flutter_app/features/call/infrastructure/production_call_v2_signaling_adapter.dart';
import 'package:flutter_app/features/call/infrastructure/platform_call_picture_in_picture_bridge.dart';
import 'package:flutter_app/features/call/infrastructure/platform_call_video_quality_environment_source.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/application/voice_call_feature_flags.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/ios_call_lifecycle_adapter.dart';
import 'package:flutter_app/features/call/infrastructure/ios_voip_token_coordinator.dart';
import 'package:flutter_app/features/call/infrastructure/issued_call_wake_handle_store_impl.dart';
import 'package:flutter_app/features/call/infrastructure/received_call_wake_handle_store_impl.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../secure_storage/fake_secure_key_store.dart';

/// Plan 400 B: an iOS graph must never tear down a live call over a failed
/// capability re-advertisement or a relay-rejected VoIP token, and an idle
/// transient rollback keeps the VoIP token (a client CAS revoke is what
/// poisons the relay's refresh-epoch high-water).
final _callA = CallId.parse('11111111-1111-4111-8111-111111111111');
final _activeAt = DateTime.fromMillisecondsSinceEpoch(2_000_000, isUtc: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (inviteDuringSigning, coldBackground) in [
    (false, false),
    (true, false),
    (false, true),
  ]) {
    test(
      coldBackground
          ? 'BL54 cold background wake receives a terminal before initial advertisement'
          : 'BL54 cold iOS wake preserves the endpoint until the admitted call ends '
                '(invite during signing: $inviteDuringSigning)',
      () async {
        const deadline = Duration(seconds: 3);
        const nowMs = 2_000_000;
        const remote = 'remote-account';
        const local = 'local-account';
        const handle = '66666666-6666-4666-8666-666666666666';
        const wakeHandle = 'fedcba9876543210fedcba9876543210';
        const previousEndpoint = <String, Object?>{
          'preferenceEpoch': nowMs - 1000,
          'routingHandle': '0123456789abcdef0123456789abcdef',
        };
        var relayEndpoint = previousEndpoint;
        final firstPublication = Completer<void>();
        var foreground = !coldBackground;
        final fixture = await _createFixture(
          videoEnabled: true,
          isForeground: () => foreground,
        ).timeout(deadline);
        final invite = CallSignalV2.fromMap({
          'schema': CallSignalV2.schema,
          'call_id': _callA.value,
          'message_id': '33333333-3333-4333-8333-000000000001',
          'event': 'invite',
          'sender_account_peer_id': remote,
          'sender_device_peer_id': remote,
          'recipient_account_peer_id': local,
          'recipient_device_peer_id': local,
          'sender_sequence': 1,
          'ice_generation': 0,
          'created_at_ms': nowMs,
          'expires_at_ms': nowMs + 45000,
          'payload': {
            'media': 'video',
            'camera': 'off',
            'capabilities': ['audio', 'video'],
          },
        }, videoEnabled: true);
        final crypto = _LiveVideoCrypto();
        final envelope =
            await SecureCallEnvelopeCodec(
                  crypto: crypto,
                  nowMs: () => nowMs,
                  videoEnabled: true,
                )
                .encodeV2(
                  signal: invite,
                  callHandle: handle,
                  recipientMlKemPublicKey: 'local-mlkem-public-key',
                  senderSigningPrivateKey: 'remote-private-key',
                )
                .timeout(deadline);
        final responses = fixture.bridge.responseHandlers;
        responses['payload.verify'] = (_) async => {'ok': true, 'valid': true};
        responses['message.decrypt'] = (_) async => {
          'ok': true,
          'plaintext': jsonEncode(invite.toMap()),
        };
        responses['message.encrypt'] = (_) async => {
          'ok': true,
          'kem': 'a2Vt',
          'ciphertext': 'Y2lwaGVy',
          'nonce': 'bm9uY2U=',
        };
        responses['call_store_v1'] = (request) async => {
          'ok': true,
          'storeStatus': 'stored',
          'receiptAtMs': nowMs,
          'expiresAtMs': (request['payload'] as Map)['expiresAtMs'],
          'eventCount': 1,
          'totalBytes': 100,
          'pendingHandles': 1,
        };
        responses['call_ack_v1'] = (_) async => {'ok': true, 'acked': 1};
        responses['call_endpoint_set_v1'] = (request) async {
          relayEndpoint = Map<String, Object?>.from(request['payload'] as Map);
          if (!firstPublication.isCompleted) firstPublication.complete();
          return {'ok': true};
        };

        var inviteAvailable = !inviteDuringSigning;
        var terminalPending = coldBackground;
        responses['call_retrieve_v1'] = (_) async {
          final events = <Map<String, Object?>>[];
          if (inviteAvailable) {
            inviteAvailable = false;
            final graph = fixture.graphs.single;
            final roster = await graph.trustedRosterProvider.loadForContact(
              remote,
            );
            final device = roster.devices.single;
            await graph.receivedCallWakeHandleStore.storeIfStrictlyNewer(
              issuerAccountPeerId: remote,
              grant: CallWakeHandleGrant(
                handle: wakeHandle,
                recipientDevicePeerId: device.devicePeerId,
                deviceKeyEpoch: device.deviceKeyEpoch,
                generation: 1,
                issuedAtMs: nowMs - 1000,
                expiresAtMs: nowMs + 60000,
              ),
              nowMs: nowMs,
            );
            final endpoint = CallEndpointRecord(
              accountPeerId: remote,
              devicePeerId: device.devicePeerId,
              capabilities: const {'voice_call_v1', 'video_call_v2'},
              platform: CallEndpointPlatform.android,
              expiresAtMs: nowMs + 60000,
              preferenceEpoch: 1,
              deviceKeyEpoch: device.deviceKeyEpoch,
              routingHandle: wakeHandle,
            );
            responses['call_endpoint_get_v1'] = (_) async => {
              'ok': true,
              'found': true,
              'canonicalRecord': base64Encode(
                utf8.encode(endpoint.canonicalRecordJson),
              ),
              'endpoint': {
                ...endpoint.toCanonicalMap(),
                'signature': 'c2lnbmF0dXJl',
              },
            };
            events.add({
              'callHandle': handle,
              'messageId': invite.messageId,
              'senderPeerId': device.devicePeerId,
              'recipientDevicePeerId': local,
              'envelope': envelope,
              'receiptAtMs': nowMs,
              'expiresAtMs': invite.expiresAtMs,
            });
          } else if (terminalPending) {
            terminalPending = false;
            final graph = fixture.graphs.single;
            expect(graph.coordinator.activeSession?.state, CallState.ringing);
            await _endCall(graph).timeout(deadline);
          }
          return {
            'ok': true,
            'events': events,
            'receiptAtMs': nowMs,
            'expiresAtMs': invite.expiresAtMs,
            'hasMore': coldBackground && events.isNotEmpty,
          };
        };
        if (inviteDuringSigning) {
          var releaseInviteOnSign = true;
          responses['payload.sign'] = (request) async {
            final data = (request['payload'] as Map)['data'] as String;
            if (releaseInviteOnSign &&
                data.startsWith('{"schema":"${CallEndpointRecord.schema}"')) {
              releaseInviteOnSign = false;
              inviteAvailable = true;
              await fixture.graphs.single.runtime.onResume().timeout(deadline);
            }
            return {'ok': true, 'signature': 'c2lnbmF0dXJl'};
          };
        }

        await fixture.composition.onCallWake().timeout(deadline);
        final graph = fixture.graphs.single;
        expect(fixture.composition.isStarted, isTrue);
        expect(graph.runtime.isStarted, isTrue);
        if (coldBackground) {
          expect(terminalPending, isFalse);
          expect(graph.coordinator.lastSnapshot?.isTerminal, isTrue);
          expect(fixture.composition.isOutgoingCallAvailable, isFalse);
          expect(fixture.tokenSet.calls, 0);
          expect(
            fixture.bridge.commands,
            isNot(contains('call_wake_handle_set_v1')),
          );
          expect(relayEndpoint, same(previousEndpoint));
          expect(
            fixture.lifecycleMethods,
            isNot(contains('disableCapability')),
          );
          expect(fixture.lifecycleMethods, isNot(contains('failClosed')));

          foreground = true;
          expect(
            await fixture.composition.onResume().timeout(deadline),
            isTrue,
          );
          expect(fixture.composition.isOutgoingCallAvailable, isTrue);
          expect(fixture.tokenSet.calls, 1);
        } else {
          expect(graph.coordinator.activeSession?.callId, _callA);
          expect(graph.coordinator.activeSession?.state, CallState.ringing);
          expect(graph.videoContexts?.admittedV2Endpoint(_callA), isNotNull);
          expect(fixture.bridge.commands, contains('call_ack_v1'));
          expect(fixture.tokenSet.calls, greaterThan(0));
          expect(fixture.bridge.commands, contains('call_wake_handle_set_v1'));
          expect(relayEndpoint, same(previousEndpoint));
          expect(
            fixture.bridge.commands,
            isNot(contains('call_endpoint_set_v1')),
          );

          await _endCall(graph).timeout(deadline);
        }
        await firstPublication.future.timeout(deadline);
        expect(
          fixture.bridge.commands.where((cmd) => cmd == 'call_endpoint_set_v1'),
          hasLength(1),
        );
        expect(relayEndpoint['preferenceEpoch'], nowMs);
        expect(
          relayEndpoint['routingHandle'],
          isNot(previousEndpoint['routingHandle']),
        );
      },
    );
  }
  for (final event in ['terminate', 'media_request', 'camera_state']) {
    test(
      'BL16 live resume preserves admitted authority for $event transport',
      () async {
        const deadline = Duration(seconds: 3);
        var nowMs = 2_000_000;
        final fixture = await _createFixture(
          nowMs: () => nowMs,
          videoEnabled: true,
        ).timeout(deadline);
        await fixture.composition.start().timeout(deadline);
        final graph = fixture.graphs.single;
        final transport = _LiveVideoTransport(
          bridge: fixture.bridge,
          nowMs: () => nowMs,
        );
        addTearDown(transport.close);
        // The remote caller binds the actual published endpoint at admission.
        // A successful first write excludes a broken crypto/transport fixture.
        await transport.send('camera_state', sequence: 2).timeout(deadline);
        expect(transport.direct.envelopes, hasLength(1));
        expect(transport.mailbox.requests, hasLength(1));

        await _ringIncoming(graph).timeout(deadline);
        nowMs += 1000;
        await fixture.composition.onResume().timeout(deadline);
        expect(graph.coordinator.activeSession?.isTerminal, isFalse);

        // Resume must not invalidate an otherwise unchanged, still-live call.
        // This exercises the strict production adapter, not an epoch assertion.
        await transport.send(event, sequence: 3).timeout(deadline);
        expect(transport.direct.envelopes, hasLength(2));
        expect(transport.mailbox.requests, hasLength(2));
      },
    );
  }
  for (final progress in [
    'no-ack',
    'ringing',
    'answer-before-ringing',
    'incoming',
  ]) {
    test(
      'CALL-INCIDENT terminal export records $progress ringing evidence',
      () async {
        final diagnostics = await CallDiagnostics.installForTesting();
        addTearDown(() async {
          await diagnostics.setEnabled(false);
          await diagnostics.dispose();
        });
        final fixture = await _createFixture();
        await fixture.composition.start();
        final source = fixture.graphs.single;
        // Keep the real reducer and graph observer, while excluding unrelated
        // microphone/transport effects from this diagnostic producer proof.
        final coordinator = CallCoordinator(
          reducer: const CallReducer(),
          cleanupCoordinator: CallCleanupCoordinator(const <CallCleanupStep>[]),
          historyProjector: source.coordinator.historyProjector,
          clock: () => _activeAt,
          idSource: () => _callA,
        );
        final graph = ProductionCallSignalingGraph(
          runtime: source.runtime,
          coordinator: coordinator,
          signalingService: source.signalingService,
          endpointResolver: source.endpointResolver,
          trustedRosterProvider: source.trustedRosterProvider,
          authorityClient: source.authorityClient,
          wakeAuthorizationCoordinator: source.wakeAuthorizationCoordinator,
          issuedCallWakeHandleStore: source.issuedCallWakeHandleStore,
          receivedCallWakeHandleStore: source.receivedCallWakeHandleStore,
          loadWakeEligibleContacts: source.loadWakeEligibleContacts,
          localDeviceKeyEpoch: source.localDeviceKeyEpoch,
          localIdentity: source.localIdentity,
          platform: source.platform,
          mediaOwner: source.mediaOwner,
          networkEffectsAllowed: () => true,
          nowMs: () => _activeAt.millisecondsSinceEpoch,
        );
        addTearDown(() async {
          await coordinator.dispose();
          await graph.shutdown();
        });
        var sequence = 0;
        Future<void> dispatch(
          CallEventType type,
          int elapsedMs, {
          CallEndReason? endReason,
        }) async {
          await coordinator.dispatch(
            CallEvent(
              type: type,
              eventId: 'incident-${sequence++}',
              occurredAt: _activeAt.add(Duration(milliseconds: elapsedMs)),
              callId: _callA,
              contactPeerId: 'remote-account',
              localAccountPeerId: 'local-account',
              localDeviceId: 'local-account',
              remoteAccountPeerId: 'remote-account',
              remoteDeviceId: 'remote-device',
              endReason: endReason,
            ),
          );
        }

        if (progress == 'incoming') {
          await _ringIncoming(graph);
        } else {
          await dispatch(CallEventType.place, 0);
          await dispatch(CallEventType.outgoingInviteReady, 100);
          await dispatch(CallEventType.wakeRequested, 200);
          if (progress == 'ringing') {
            await dispatch(CallEventType.remoteRinging, 1200);
            await dispatch(CallEventType.remoteRinging, 1600);
            expect(
              coordinator.activeSession?.ringingAt,
              _activeAt.add(const Duration(milliseconds: 1200)),
            );
          } else if (progress == 'answer-before-ringing') {
            await dispatch(CallEventType.remoteAccept, 1000);
            await dispatch(CallEventType.remoteRinging, 1200);
            expect(coordinator.activeSession?.acceptedAt, isNotNull);
            expect(coordinator.activeSession?.ringingAt, isNull);
          }
        }
        final traceId = diagnostics.traceForCall(callId: _callA.value);
        expect(traceId, isNotNull);
        await dispatch(
          CallEventType.remoteTerminate,
          2000,
          endReason: CallEndReason.noAnswer,
        );
        final exported = await diagnostics.exportPreview();
        final events = (jsonDecode(exported)['events'] as List).cast<Map>();
        final terminal = events
            .where(
              (event) =>
                  event['traceId'] == traceId &&
                  event['stage'] == 'terminal' &&
                  event['action'] == 'finish',
            )
            .single;
        final values = terminal['values'] as Map;
        if (progress == 'incoming') {
          expect(values.containsKey('remoteRingingObserved'), isFalse);
        } else {
          expect(values['remoteRingingObserved'], progress == 'ringing');
        }
        if (progress == 'ringing') {
          expect(values['timeToRemoteRingingMs'], 1200);
        } else {
          expect(values.containsKey('timeToRemoteRingingMs'), isFalse);
        }
        expect(terminal['reason'], 'no_answer');
        expect(
          terminal['outcome'],
          progress == 'answer-before-ringing'
              ? 'answered_without_verified_media'
              : 'no_answer',
        );
        for (final privateValue in [
          'remote-account',
          'remote-device',
          'local-account',
          _callA.value,
          'remote-public-key',
          'remote-mlkem-public-key',
          'Remote contact',
        ]) {
          expect(exported, isNot(contains(privateValue)));
        }
      },
    );
  }

  test(
    'production cleanup remains correlated after terminal summary commits',
    () async {
      final diagnostics = await CallDiagnostics.installForTesting();
      addTearDown(() async {
        await diagnostics.setEnabled(false);
        await diagnostics.dispose();
      });
      final fixture = await _createFixture();
      await fixture.composition.start();
      final graph = fixture.graphs.single;
      await _ringIncoming(graph);
      final traceId = diagnostics.traceForCall(callId: _callA.value);
      expect(traceId, isNotNull);
      await _endCall(graph);
      await _settle();
      final events = await diagnostics.eventsForTesting();
      expect(
        events.any(
          (event) =>
              event['traceId'] == traceId &&
              event['stage'] == 'cleanup' &&
              event['outcome'] == 'ok',
        ),
        isTrue,
      );
      expect(jsonEncode(events), isNot(contains('remote-account')));
      expect(jsonEncode(events), isNot(contains(_callA.value)));
    },
  );

  tearDown(() => debugSetFlowEventSink(null));

  test(
    'published authority resolves after idle days without a new exchange',
    () async {
      const issuedAtMs = 2_000_000;
      var nowMs = issuedAtMs;
      final fixture = await _createFixture(nowMs: () => nowMs);
      await fixture.composition.start();
      final graph = fixture.graphs.single;
      final issued = (await graph.issuedCallWakeHandleStore.readForContact(
        'remote-account',
      ))!;
      expect(
        await graph.markCallWakeHandleDistributed(
          'remote-account',
          issued.grant,
        ),
        isTrue,
      );
      final payload = Map<String, dynamic>.from(
        fixture.bridge.requests.lastWhere(
              (request) => request['cmd'] == 'call_endpoint_set_v1',
            )['payload']
            as Map,
      );
      final signature = payload.remove('signature') as String;
      final record = CallEndpointRecord.fromMap(<String, dynamic>{
        ...payload,
        'schema': CallEndpointRecord.schema,
        'version': CallEndpointRecord.version,
      });
      final signed = SignedCallEndpointRecord(
        record: record,
        signature: signature,
        canonicalRecordBase64: base64Encode(
          utf8.encode(record.canonicalRecordJson),
        ),
      );
      final resolver = CallEndpointResolver(
        nowMs: () => nowMs,
        verifyEndpointSignature: (endpoint, publicKey) async =>
            endpoint.signature == 'c2lnbmF0dXJl' &&
            endpoint.canonicalRecordJson == record.canonicalRecordJson &&
            publicKey == 'local-public-key',
      );
      Future<ResolvedCallEndpoint> resolve({bool blocked = false}) =>
          resolver.resolve(
            contactAccountPeerId: record.accountPeerId,
            contactAccepted: true,
            contactBlocked: blocked,
            trustedDevices: <TrustedCallDeviceAuthority>[
              TrustedCallDeviceAuthority(
                accountPeerId: record.accountPeerId,
                devicePeerId: record.devicePeerId,
                linked: true,
                deviceKeyEpoch: record.deviceKeyEpoch,
                signingPublicKey: 'local-public-key',
                mlKemPublicKey: 'local-mlkem-public-key',
              ),
            ],
            relayCapabilities: <SignedCallEndpointRecord>[signed],
            wakeHandleGrant: issued.grant,
          );
      await _settle();
      final commandsBeforeIdle = List<String>.of(fixture.bridge.commands);
      for (final idle in const <Duration>[
        Duration(hours: 7),
        Duration(hours: 25),
        Duration(days: 29),
      ]) {
        nowMs = issuedAtMs + idle.inMilliseconds;
        final endpoint = await resolve();
        expect(endpoint.wakeHandle, issued.grant.handle);
        expect(
          endpoint.expiresAtMs,
          issuedAtMs + const Duration(days: 30).inMilliseconds,
        );
        final persisted = await graph.issuedCallWakeHandleStore.readForContact(
          'remote-account',
        );
        expect(persisted?.hasCurrentDistributionReceipt, isTrue);
        expect(persisted?.distributionPending, isFalse);
      }
      await expectLater(
        resolve(blocked: true),
        throwsA(
          isA<CallEndpointResolutionException>().having(
            (error) => error.code,
            'code',
            CallEndpointResolutionCode.blocked,
          ),
        ),
      );
      nowMs = issuedAtMs + const Duration(days: 30).inMilliseconds;
      await expectLater(
        resolve(),
        throwsA(
          isA<CallEndpointResolutionException>().having(
            (error) => error.code,
            'code',
            CallEndpointResolutionCode.stale,
          ),
        ),
      );
      expect(issued.grant.isValidAt(nowMs), isFalse);
      expect(fixture.bridge.commands, commandsBeforeIdle);
    },
  );

  test(
    'failed advertisement during a live call revokes nothing and ends no CallKit call',
    () async {
      final fixture = await _createFixture();
      await fixture.composition.start();
      expect(fixture.composition.isStarted, isTrue);
      final graph = fixture.graphs.single;
      await _ringIncoming(graph);
      final session = graph.coordinator.activeSession!;
      final commandsBefore = fixture.bridge.commands.length;
      fixture.tokenSet.reject = true;

      await fixture.composition.onResume();

      expect(fixture.composition.isStarted, isTrue);
      expect(
        fixture.bridge.commands.sublist(commandsBefore),
        isNot(contains('call_endpoint_revoke_v1')),
      );
      expect(
        fixture.bridge.commands.sublist(commandsBefore),
        isNot(contains('call_token_revoke_v1')),
      );
      expect(fixture.lifecycleMethods, isNot(contains('failClosed')));
      expect(identical(graph.coordinator.activeSession, session), isTrue);
      expect(session.isTerminal, isFalse);
      expect(
        _details(fixture.flowEvents, 'CALL_CAPABILITY_ADVERTISEMENT_RESULT'),
        anyElement(
          equals(<String, Object?>{
            'stage': 'voip_token',
            'outcome': 'deferred_live_call',
          }),
        ),
      );
      expect(
        _details(fixture.flowEvents, 'CALL_SIGNALING_RESUME_RESULT').last,
        containsPair('outcome', 'advertisement_deferred'),
      );
    },
  );

  test(
    'backgrounding during a failed refresh retains the native call',
    () async {
      final fixture = await _createFixture();
      await fixture.composition.start();
      final graph = fixture.graphs.single;
      await _ringIncoming(graph);
      final session = graph.coordinator.activeSession!;
      final refreshEntered = Completer<void>();
      final refreshResponse = Completer<Map<String, Object?>>();
      fixture.bridge.responseHandlers['call_endpoint_set_v1'] = (_) {
        refreshEntered.complete();
        return refreshResponse.future;
      };

      final refresh = fixture.composition.onContactEligibilityChanged();
      await refreshEntered.future;
      await fixture.composition.onBackgrounded();
      expect(fixture.composition.current, isNull);
      refreshResponse.complete(const <String, Object?>{'ok': false});
      await refresh;

      expect(fixture.composition.isStarted, isTrue);
      expect(graph.coordinator.activeSession, same(session));
      expect(graph.current?.session, same(session));
      expect(session.isTerminal, isFalse);
      expect(fixture.composition.current, isNull);
      expect(fixture.lifecycleMethods, isNot(contains('failClosed')));
      expect(
        fixture.bridge.commands,
        isNot(contains('call_endpoint_revoke_v1')),
      );
      expect(
        _details(fixture.flowEvents, 'CALL_SIGNALING_RECONCILE_RESULT').last,
        containsPair('outcome', 'advertisement_deferred'),
      );
    },
  );

  test(
    'background native call keeps polling without another session event',
    () async {
      final fixture = await _createFixture();
      await fixture.composition.start();
      final graph = fixture.graphs.single;
      await _ringIncoming(graph);
      await fixture.composition.onBackgrounded();
      final polled = Completer<void>();
      fixture.bridge.responseHandlers['call_retrieve_v1'] = (_) async {
        if (!polled.isCompleted) polled.complete();
        return const <String, Object?>{
          'ok': true,
          'events': <Object?>[],
          'receiptAtMs': 1,
          'expiresAtMs': 1,
          'hasMore': false,
        };
      };

      // No resume, wake, media callback, or additional coordinator event can
      // restart the timer: this must be the poll retained across backgrounding.
      await polled.future.timeout(const Duration(seconds: 5));

      expect(fixture.composition.current, isNull);
      expect(graph.coordinator.activeSession?.isTerminal, isFalse);
    },
  );

  test(
    'token authority invalidation during a live call defers withdrawal until the call ends',
    () async {
      final fixture = await _createFixture();
      await fixture.composition.start();
      final graph = fixture.graphs.single;
      await _ringIncoming(graph);
      fixture.tokenSet.reject = true;

      await fixture.composition.onResume();
      await _settle();

      // Deferred at both the graph (no rollback) and the composition (no
      // withdrawal) while the session is live.
      expect(fixture.composition.isStarted, isTrue);
      expect(
        fixture.bridge.commands,
        isNot(contains('call_endpoint_revoke_v1')),
      );
      expect(fixture.bridge.commands, isNot(contains('call_token_revoke_v1')));
      expect(fixture.lifecycleMethods, isNot(contains('failClosed')));
      expect(graph.coordinator.activeSession?.isTerminal, isFalse);

      await _endCall(graph);
      await _until(() => !fixture.composition.isStarted);
      await _until(() => fixture.lifecycleMethods.contains('detach'));

      expect(
        fixture.bridge.commands.where(
          (command) => command == 'call_endpoint_revoke_v1',
        ),
        hasLength(1),
      );
      expect(fixture.bridge.commands, isNot(contains('call_token_revoke_v1')));
      expect(
        fixture.lifecycleMethods.where((method) => method == 'failClosed'),
        hasLength(1),
      );
    },
  );

  test(
    'BL54 warm background terminal waits for foreground to refresh the endpoint',
    () async {
      const deadline = Duration(seconds: 3);
      var foreground = true;
      final fixture = await _createFixture(
        videoEnabled: true,
        isForeground: () => foreground,
      ).timeout(deadline);
      await fixture.composition.start().timeout(deadline);
      final graph = fixture.graphs.single;
      await _ringIncoming(graph).timeout(deadline);
      await fixture.composition.onResume().timeout(deadline);
      expect(
        _details(
          fixture.flowEvents,
          'CALL_CAPABILITY_ADVERTISEMENT_RESULT',
        ).last,
        containsPair('outcome', 'deferred_live_call'),
      );

      final tokenSets = fixture.tokenSet.calls;
      int count(String command) => fixture.bridge.commands
          .where((candidate) => candidate == command)
          .length;
      final wakeSets = count('call_wake_handle_set_v1');
      final endpointSets = count('call_endpoint_set_v1');
      foreground = false;
      await fixture.composition.onBackgrounded().timeout(deadline);
      await _endCall(graph).timeout(deadline);
      await _settle().timeout(deadline);

      expect(fixture.composition.isStarted, isTrue);
      expect(graph.runtime.isStarted, isTrue);
      expect(fixture.tokenSet.calls, tokenSets);
      expect(count('call_wake_handle_set_v1'), wakeSets);
      expect(count('call_endpoint_set_v1'), endpointSets);
      expect(fixture.lifecycleMethods, isNot(contains('disableCapability')));
      expect(fixture.lifecycleMethods, isNot(contains('failClosed')));

      foreground = true;
      expect(await fixture.composition.onResume().timeout(deadline), isTrue);
      expect(fixture.tokenSet.calls, tokenSets + 1);
      expect(count('call_wake_handle_set_v1'), wakeSets + 1);
      expect(count('call_endpoint_set_v1'), endpointSets + 1);
    },
  );

  test(
    'deferred advertisement is retried once at the terminal snapshot',
    () async {
      final fixture = await _createFixture();
      await fixture.composition.start();
      final graph = fixture.graphs.single;
      await _ringIncoming(graph);
      fixture.tokenSet.reject = true;
      await fixture.composition.onResume();
      expect(fixture.composition.isStarted, isTrue);
      final tokenSetsBeforeTerminal = fixture.tokenSet.calls;
      final endpointSetsBeforeTerminal = fixture.bridge.commands
          .where((command) => command == 'call_endpoint_set_v1')
          .length;
      fixture.tokenSet.reject = false;

      await _endCall(graph);
      await _until(
        () =>
            fixture.bridge.commands
                .where((command) => command == 'call_endpoint_set_v1')
                .length ==
            endpointSetsBeforeTerminal + 1,
      );
      await _settle();

      expect(fixture.tokenSet.calls, tokenSetsBeforeTerminal + 1);
      expect(fixture.composition.isStarted, isTrue);
      expect(
        fixture.bridge.commands,
        isNot(contains('call_endpoint_revoke_v1')),
      );
      expect(fixture.bridge.commands, isNot(contains('call_token_revoke_v1')));
      expect(fixture.lifecycleMethods, isNot(contains('failClosed')));
      expect(
        _details(
          fixture.flowEvents,
          'CALL_CAPABILITY_ADVERTISEMENT_RESULT',
        ).last,
        <String, Object?>{'stage': 'ready', 'outcome': 'ready'},
      );
    },
  );

  test('idle advertisement failure revokes the endpoint only', () async {
    final fixture = await _createFixture();
    await fixture.composition.start();
    expect(fixture.composition.isStarted, isTrue);
    fixture.tokenSet.reject = true;

    await fixture.composition.onResume();
    await _until(() => fixture.lifecycleMethods.contains('detach'));

    expect(fixture.composition.isStarted, isFalse);
    expect(
      fixture.bridge.commands.where(
        (command) => command == 'call_endpoint_revoke_v1',
      ),
      hasLength(1),
    );
    expect(fixture.bridge.commands, isNot(contains('call_token_revoke_v1')));
    expect(
      fixture.lifecycleMethods.where((method) => method == 'failClosed'),
      hasLength(1),
    );
    final advertisements = _details(
      fixture.flowEvents,
      'CALL_CAPABILITY_ADVERTISEMENT_RESULT',
    );
    expect(
      advertisements,
      anyElement(
        equals(<String, Object?>{
          'stage': 'voip_token',
          'outcome': 'unavailable',
        }),
      ),
    );
    expect(
      advertisements.any(
        (details) => details['outcome'] == 'deferred_live_call',
      ),
      isFalse,
    );
  });

  test(
    'overlapping refreshes cannot publish an older endpoint after a newer one',
    () async {
      var nowMs = 2_000_000;
      final fixture = await _createFixture(nowMs: () => nowMs);
      await fixture.composition.start();
      final firstSignEntered = Completer<void>();
      final firstSignature = Completer<Map<String, Object?>>();
      var signatureCount = 0;
      fixture.bridge.responseHandlers['payload.sign'] = (_) async {
        if (++signatureCount == 1) {
          firstSignEntered.complete();
          return firstSignature.future;
        }
        return const <String, Object?>{'ok': true, 'signature': 'c2lnbmF0dXJl'};
      };
      final publishedEpochs = <int>[];
      var relayEpoch = nowMs;
      fixture.bridge.responseHandlers['call_endpoint_set_v1'] =
          (request) async {
            final payload = request['payload']! as Map<String, dynamic>;
            final epoch = payload['preferenceEpoch']! as int;
            publishedEpochs.add(epoch);
            if (epoch < relayEpoch) {
              return const <String, Object?>{
                'ok': false,
                'errorCode': 'CALL_STALE_EPOCH',
              };
            }
            relayEpoch = epoch;
            return const <String, Object?>{'ok': true};
          };

      nowMs++;
      final contactRefresh = fixture.composition.onContactEligibilityChanged();
      await firstSignEntered.future;
      nowMs++;
      final resumeRefresh = fixture.composition.onResume();
      // Let the independent resume lane run while the first signature is held.
      await _settle();
      firstSignature.complete(const <String, Object?>{
        'ok': true,
        'signature': 'c2lnbmF0dXJl',
      });
      await Future.wait(<Future<void>>[contactRefresh, resumeRefresh]);

      expect(publishedEpochs, orderedEquals(<int>[2_000_001, 2_000_002]));
      expect(fixture.composition.isStarted, isTrue);
      expect(
        fixture.bridge.commands,
        isNot(contains('call_endpoint_revoke_v1')),
      );
      expect(fixture.bridge.commands, isNot(contains('call_token_revoke_v1')));
      expect(fixture.lifecycleMethods, isNot(contains('failClosed')));
    },
  );

  test(
    'shutdown prevents a delayed signature from republishing an endpoint',
    () async {
      final fixture = await _createFixture();
      await fixture.composition.start();
      final graph = fixture.graphs.single;
      final signEntered = Completer<void>();
      final signature = Completer<Map<String, Object?>>();
      fixture.bridge.responseHandlers['payload.sign'] = (_) {
        signEntered.complete();
        return signature.future;
      };
      final endpointSetsBefore = fixture.bridge.commands
          .where((command) => command == 'call_endpoint_set_v1')
          .length;

      final refresh = graph.advertiseCapability();
      await signEntered.future;
      final shutdown = fixture.composition.shutdown();
      await _settle();
      signature.complete(const <String, Object?>{
        'ok': true,
        'signature': 'c2lnbmF0dXJl',
      });

      expect(await refresh, isFalse);
      await shutdown;
      expect(
        fixture.bridge.commands.where(
          (command) => command == 'call_endpoint_set_v1',
        ),
        hasLength(endpointSetsBefore),
      );
      expect(await graph.advertiseCapability(), isFalse);
      expect(fixture.bridge.commands, contains('call_endpoint_revoke_v1'));
    },
  );

  // Beta report: after a call, every later call failed until the app was
  // restarted. One relay outage both fails the advertisement (which withdraws
  // the graph) and the endpoint revoke inside that withdrawal. The revoke is
  // relay housekeeping, not a native release, so the next tap must rebuild.
  test(
    'a failed relay revoke during withdrawal does not disable calling',
    () async {
      final fixture = await _createFixture();
      await fixture.composition.start();
      expect(fixture.composition.isOutgoingCallAvailable, isTrue);

      var relayDown = true;
      fixture.tokenSet.reject = true;
      for (final command in [
        'call_endpoint_revoke_v1',
        'call_token_revoke_v1',
      ]) {
        fixture.bridge.responseHandlers[command] = (_) async => relayDown
            ? const <String, Object?>{
                'ok': false,
                'errorCode': 'CALL_CONTROL_UNAVAILABLE',
              }
            : const <String, Object?>{'ok': true, 'revoked': true};
      }
      await fixture.composition.onResume();
      await _until(() => fixture.lifecycleMethods.contains('detach'));
      expect(fixture.composition.isOutgoingCallAvailable, isFalse);

      relayDown = false;
      fixture.tokenSet.reject = false;
      expect(await fixture.composition.recoverOutgoingCallReadiness(), isTrue);
      expect(fixture.graphs, hasLength(2));
      expect(fixture.composition.isOutgoingCallAvailable, isTrue);
    },
  );

  test(
    'a failed native release during withdrawal still blocks rebuild',
    () async {
      final fixture = await _createFixture(
        failingLifecycleMethods: const <String>{'failClosed'},
      );
      await fixture.composition.start();
      expect(fixture.composition.isOutgoingCallAvailable, isTrue);

      fixture.tokenSet.reject = true;
      await fixture.composition.onResume();
      await _until(() => fixture.lifecycleMethods.contains('detach'));

      fixture.tokenSet.reject = false;
      expect(await fixture.composition.recoverOutgoingCallReadiness(), isFalse);
      expect(fixture.graphs, hasLength(1));
    },
  );

  test('shutdown revokes an endpoint publication already in flight', () async {
    final fixture = await _createFixture();
    await fixture.composition.start();
    final graph = fixture.graphs.single;
    final publishEntered = Completer<void>();
    final publishResponse = Completer<void>();
    var relayHasEndpoint = true;
    fixture.bridge.responseHandlers['call_endpoint_set_v1'] = (_) async {
      publishEntered.complete();
      await publishResponse.future;
      relayHasEndpoint = true;
      return const <String, Object?>{'ok': true};
    };
    fixture.bridge.responseHandlers['call_endpoint_revoke_v1'] = (_) async {
      relayHasEndpoint = false;
      return const <String, Object?>{'ok': true, 'revoked': true};
    };

    final refresh = graph.advertiseCapability();
    await publishEntered.future;
    final shutdown = fixture.composition.shutdown();
    await _settle();
    publishResponse.complete();

    expect(await refresh, isFalse);
    await shutdown;
    expect(relayHasEndpoint, isFalse);
    expect(fixture.lifecycleMethods, contains('detach'));
  });

  test(
    'relay stale epoch advances the native epoch and keeps the graph callable',
    () async {
      final fixture = await _createFixture();
      await fixture.composition.start();
      expect(fixture.composition.isStarted, isTrue);
      fixture.tokenSet.reject = true;
      fixture.tokenSet.advanceTo = 1_900_000_000;

      await fixture.composition.onResume();

      expect(fixture.composition.isStarted, isTrue);
      expect(fixture.tokenSet.advanceCalls, 1);
      final tokenSets = fixture.bridge.requests
          .where((request) => request['cmd'] == 'call_token_set_v1')
          .map(
            (request) =>
                (request['payload'] as Map<String, dynamic>)['refreshEpoch'],
          )
          .toList(growable: false);
      expect(tokenSets, <Object?>[41, 41, 1_900_000_000]);
      expect(fixture.bridge.commands, isNot(contains('call_token_revoke_v1')));
      expect(
        fixture.bridge.commands,
        isNot(contains('call_endpoint_revoke_v1')),
      );
      expect(fixture.lifecycleMethods, isNot(contains('failClosed')));
      expect(
        _details(fixture.flowEvents, 'CALL_VOIP_TOKEN_EPOCH_ADVANCE_RESULT'),
        <Map<String, Object?>>[
          <String, Object?>{'outcome': 'advanced'},
        ],
      );
      expect(
        _details(
          fixture.flowEvents,
          'CALL_CAPABILITY_ADVERTISEMENT_RESULT',
        ).last,
        <String, Object?>{'stage': 'ready', 'outcome': 'ready'},
      );
      expect(
        _details(fixture.flowEvents, 'CALL_SIGNALING_RESUME_RESULT').last,
        containsPair('outcome', 'ready'),
      );
    },
  );

  test('a call wake drains the production call mailbox', () async {
    final fixture = await _createFixture();
    await fixture.composition.start();
    expect(fixture.composition.isStarted, isTrue);
    int retrieves() => fixture.bridge.commands
        .where((command) => command == 'call_retrieve_v1')
        .length;
    final before = retrieves();

    await fixture.composition.onCallWake();

    expect(retrieves(), before + 1);
    expect(fixture.composition.isStarted, isTrue);
    expect(
      _details(fixture.flowEvents, 'CALL_SIGNALING_WAKE_RESULT').last,
      containsPair('outcome', 'drained'),
    );
  });

  test('a relay recovery drains the production call mailbox once', () async {
    final fixture = await _createFixture();
    await fixture.composition.start();
    int retrieves() => fixture.bridge.commands
        .where((command) => command == 'call_retrieve_v1')
        .length;
    final before = retrieves();

    // The node lost its relay link (the app was suspended) and recovered.
    fixture.p2p.states.add(
      const NodeState(
        peerId: 'local-account',
        isStarted: true,
        relayState: 'recovering',
        healthyRelayCount: 0,
      ),
    );
    fixture.p2p.states.add(
      const NodeState(
        peerId: 'local-account',
        isStarted: true,
        relayState: 'healthy',
        healthyRelayCount: 1,
      ),
    );
    fixture.p2p.states.add(
      const NodeState(
        peerId: 'local-account',
        isStarted: true,
        relayState: 'healthy',
        healthyRelayCount: 1,
      ),
    );
    await _settle();

    expect(retrieves(), before + 1);
  });

  test('shutdown revokes endpoint and token', () async {
    final fixture = await _createFixture();
    await fixture.composition.start();
    expect(fixture.composition.isStarted, isTrue);

    final service = fixture.graphs.single.signalingService;
    await fixture.composition.shutdown();
    final writesAfterShutdown = fixture.bridge.commands.length;
    await expectLater(
      service.transmit(
        signal: CallSignal.create(
          callId: _callA,
          messageId: '55555555-5555-4555-8555-555555555555',
          event: CallSignalType.terminate,
          senderAccountPeerId: 'local-account',
          senderDevicePeerId: 'local-device',
          recipientAccountPeerId: 'remote-account',
          recipientDevicePeerId: 'remote-device',
          senderSequence: 2,
          iceGeneration: 0,
          createdAtMs: 2_000_000,
          expiresAtMs: 2_040_000,
          payload: const {'reason': 'caller_cancelled'},
        ),
        callHandle: '33333333-3333-4333-8333-333333333333',
        endpoint: const ResolvedCallEndpoint(
          accountPeerId: 'remote-account',
          devicePeerId: 'remote-device',
          signingPublicKey: 'remote-public-key',
          mlKemPublicKey: 'remote-kem',
          deviceKeyEpoch: 1,
          preferenceEpoch: 1,
          platform: CallEndpointPlatform.ios,
          expiresAtMs: 2_060_000,
          routingHandle: '0123456789abcdef0123456789abcdef',
          wakeHandle: 'fedcba9876543210fedcba9876543210',
        ),
        senderSigningPrivateKey: 'local-private-key',
        authorizeTerminalRetry: () async => true,
      ),
      throwsA(
        isA<CallSignalingException>().having(
          (e) => e.code,
          'closed graph',
          CallSignalingErrorCode.migrationPaused,
        ),
      ),
    );
    expect(fixture.bridge.commands.length, writesAfterShutdown);
    expect(service.pendingTerminalRetryCount, 0);

    expect(
      fixture.bridge.commands.where(
        (command) => command == 'call_endpoint_revoke_v1',
      ),
      hasLength(1),
    );
    final tokenRevokes = fixture.bridge.requests
        .where((request) => request['cmd'] == 'call_token_revoke_v1')
        .map((request) => request['payload'] as Map<String, dynamic>)
        .toList(growable: false);
    expect(tokenRevokes, <Map<String, Object?>>[
      <String, Object?>{'tokenKind': 'ios_voip', 'expectedRefreshEpoch': 41},
    ]);
  });

  test(
    'advertisement failure with a terminal session performs the idle rollback',
    () async {
      final fixture = await _createFixture();
      await fixture.composition.start();
      final graph = fixture.graphs.single;
      await _ringIncoming(graph);
      await _endCall(graph);
      await _settle();
      expect(graph.coordinator.activeSession?.isTerminal ?? true, isTrue);
      fixture.tokenSet.reject = true;

      await fixture.composition.onResume();
      await _until(() => fixture.lifecycleMethods.contains('detach'));

      expect(fixture.composition.isStarted, isFalse);
      expect(
        fixture.bridge.commands.where(
          (command) => command == 'call_endpoint_revoke_v1',
        ),
        hasLength(1),
      );
      expect(fixture.bridge.commands, isNot(contains('call_token_revoke_v1')));
      final advertisements = _details(
        fixture.flowEvents,
        'CALL_CAPABILITY_ADVERTISEMENT_RESULT',
      );
      expect(advertisements.last, <String, Object?>{
        'stage': 'voip_token',
        'outcome': 'unavailable',
      });
      expect(
        advertisements.any(
          (details) => details['outcome'] == 'deferred_live_call',
        ),
        isFalse,
      );
    },
  );
}

List<Map<String, dynamic>> _details(
  List<Map<String, dynamic>> events,
  String event,
) => events
    .where((entry) => entry['event'] == event)
    .map((entry) => Map<String, dynamic>.from(entry['details'] as Map))
    .toList(growable: false);

Future<void> _ringIncoming(ProductionCallSignalingGraph graph) async {
  await graph.coordinator.dispatch(
    CallEvent(
      type: CallEventType.remoteInvite,
      eventId: 'live-guard-remote-invite',
      occurredAt: _activeAt,
      callId: _callA,
      contactPeerId: 'remote-account',
      localAccountPeerId: 'local-account',
      localDeviceId: 'local-account',
      remoteAccountPeerId: 'remote-account',
      remoteDeviceId: 'remote-device',
      expiresAt: _activeAt.add(const Duration(seconds: 45)),
      transportRoute: CallRouteClass.direct,
    ),
  );
  await graph.coordinator.dispatch(
    CallEvent(
      type: CallEventType.incomingValidated,
      eventId: 'live-guard-incoming-validated',
      occurredAt: _activeAt,
      callId: _callA,
      contactPeerId: 'remote-account',
    ),
  );
  expect(graph.coordinator.activeSession?.callId, _callA);
  expect(graph.coordinator.activeSession?.isTerminal, isFalse);
}

Future<void> _endCall(ProductionCallSignalingGraph graph) =>
    graph.coordinator.dispatch(
      CallEvent(
        type: CallEventType.remoteTerminate,
        eventId: 'live-guard-remote-terminate',
        occurredAt: _activeAt.add(const Duration(seconds: 1)),
        callId: _callA,
        contactPeerId: 'remote-account',
      ),
    );

Future<void> _settle() async {
  for (var turn = 0; turn < 8; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _until(bool Function() predicate) async {
  for (var attempt = 0; attempt < 200 && !predicate(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(predicate(), isTrue);
}

final class _TokenSetScript {
  bool reject = false;
  int calls = 0;

  /// When set, the fake native answers `advanceRefreshEpoch` with this epoch
  /// and the relay accepts it (the rejection above applies to epoch 41 only).
  int? advanceTo;
  int advanceCalls = 0;
}

final class _Fixture {
  const _Fixture({
    required this.composition,
    required this.bridge,
    required this.lifecycleMethods,
    required this.graphs,
    required this.flowEvents,
    required this.tokenSet,
    required this.p2p,
  });

  final CallSignalingComposition composition;
  final _Bridge bridge;
  final List<String> lifecycleMethods;
  final List<ProductionCallSignalingGraph> graphs;
  final List<Map<String, dynamic>> flowEvents;
  final _TokenSetScript tokenSet;
  final _P2P p2p;
}

Future<_Fixture> _createFixture({
  int Function()? nowMs,
  bool Function()? isForeground,
  bool videoEnabled = false,
  Set<String> failingLifecycleMethods = const <String>{},
}) async {
  databaseFactory = databaseFactoryFfi;
  final database = await openDatabase(
    inMemoryDatabasePath,
    version: 1,
    onCreate: (db, _) async {
      await db.execute(
        'CREATE TABLE contacts('
        'peer_id TEXT PRIMARY KEY, username TEXT, public_key TEXT, '
        'ml_kem_public_key TEXT, is_blocked INTEGER)',
      );
      await runDirectLinkedDeviceAddressingMigration(db);
      await runCallHistoryMigration(db);
      await db.insert('contacts', <String, Object?>{
        'peer_id': 'remote-account',
        'username': 'Remote contact',
        'public_key': 'remote-public-key',
        'ml_kem_public_key': 'remote-mlkem-public-key',
        'is_blocked': 0,
      });
    },
  );
  final tokenSet = _TokenSetScript();
  final bridge = _Bridge();
  bridge.responseHandlers['call_token_set_v1'] = (request) async {
    tokenSet.calls++;
    final epoch = (request['payload']! as Map<String, dynamic>)['refreshEpoch'];
    if (tokenSet.reject && epoch == 41) {
      return const <String, Object?>{
        'ok': false,
        'errorCode': 'CALL_STALE_EPOCH',
      };
    }
    return <String, Object?>{
      'ok': true,
      'generation': 3,
      'refreshEpoch':
          (request['payload']! as Map<String, dynamic>)['refreshEpoch'],
    };
  };
  final p2p = _P2P();
  final router = IncomingMessageRouter(p2pService: p2p)..start();
  final lifecycleMethods = <String>[];
  final tokenEvents = StreamController<Object?>.broadcast(sync: true);
  final graphs = <ProductionCallSignalingGraph>[];
  final flowEvents = <Map<String, dynamic>>[];
  debugSetFlowEventSink(flowEvents.add);
  final identity = IdentityModel(
    peerId: 'local-account',
    publicKey: 'local-public-key',
    privateKey: 'local-private-key',
    mnemonic12: 'unused fixture words',
    mlKemPublicKey: 'local-mlkem-public-key',
    mlKemSecretKey: 'local-mlkem-secret-key',
    createdAt: '2026-08-30T00:00:00.000Z',
    updatedAt: '2026-08-30T00:00:00.000Z',
  );
  final secureKeyStore = FakeSecureKeyStore();
  final composition = createProductionCallSignalingComposition(
    secureKeyStore: FakeSecureKeyStore(),
    featureFlags: <String, bool>{
      ...defaultVoiceCallFeatureFlags(),
      'video_call_v2_enabled': videoEnabled,
      'voice_call_capability_v1': true,
      'voice_call_outgoing_enabled': true,
      'voice_call_incoming_enabled': true,
      'voice_call_turn_enabled': true,
      'voice_call_android_native_enabled': false,
      'voice_call_ios_native_enabled': true,
    },
    platform: CallEndpointPlatform.ios,
    database: database,
    bridge: bridge,
    p2pService: p2p,
    messageRouter: router,
    loadIdentity: () async => identity,
    networkEffectsAllowed: () => true,
    isVoiceNoteRecording: () => false,
    issuedCallWakeHandleStore: IssuedCallWakeHandleStoreImpl(
      secureKeyStore: secureKeyStore,
    ),
    receivedCallWakeHandleStore: ReceivedCallWakeHandleStoreImpl(
      secureKeyStore: secureKeyStore,
    ),
    iosCallLifecycleAdapterFactory:
        ({
          required coordinator,
          required resolveAuthenticatedHandle,
          required clock,
        }) => IosCallLifecycleAdapter(
          invokeMethod: (method, arguments) async {
            lifecycleMethods.add(method);
            if (failingLifecycleMethods.contains(method)) return false;
            if (method == 'attach') {
              return const <String, Object?>{
                'version': 1,
                'descriptor': null,
                'events': <Object?>[],
                'nativeCallId': null,
                'highestSequence': 0,
              };
            }
            return true;
          },
          nativeEvents: const Stream<Object?>.empty(),
          coordinator: coordinator,
          resolveAuthenticatedHandle: resolveAuthenticatedHandle,
          clock: clock,
        ),
    iosVoipTokenCoordinatorFactory:
        ({
          required authorityClient,
          required clock,
          required publicationAllowed,
        }) => IosVoipTokenCoordinator(
          invokeMethod: (method, arguments) async {
            var epoch = 41;
            if (method == 'advanceRefreshEpoch') {
              tokenSet.advanceCalls++;
              final advanceTo = tokenSet.advanceTo;
              if (advanceTo == null) {
                throw StateError('epoch advance unavailable');
              }
              epoch = advanceTo;
            }
            return <String, Object?>{
              'version': 1,
              'token': List<String>.filled(64, 'c').join(),
              'environment': 'development',
              'topic': 'com.mknoon.app.voip',
              'capabilityVersion': 1,
              'refreshEpoch': epoch,
              'invalidated': false,
            };
          },
          nativeEvents: tokenEvents.stream,
          authorityClient: authorityClient,
          clock: clock,
          publicationAllowed: publicationAllowed,
        ),
    // These optional native sources are outside this signaling-only proof.
    qualityEnvironmentSourceFactory: () =>
        PlatformCallVideoQualityEnvironmentSource(),
    pictureInPictureBridgeFactory: () =>
        PlatformCallPictureInPictureBridge(),
    isForeground: isForeground ?? () => true,
    nowMs: nowMs ?? () => 2_000_000,
    onGraphBuilt: graphs.add,
  );
  addTearDown(() async {
    debugSetFlowEventSink(null);
    await composition.shutdown();
    router.dispose();
    await p2p.messages.close();
    await p2p.states.close();
    await tokenEvents.close();
    await database.close();
  });
  return _Fixture(
    composition: composition,
    bridge: bridge,
    lifecycleMethods: lifecycleMethods,
    graphs: graphs,
    flowEvents: flowEvents,
    tokenSet: tokenSet,
    p2p: p2p,
  );
}

final class _Bridge implements Bridge {
  final List<String> commands = <String>[];
  final List<Map<String, dynamic>> requests = <Map<String, dynamic>>[];
  final Map<String, Future<Map<String, Object?>> Function(Map<String, dynamic>)>
  responseHandlers =
      <String, Future<Map<String, Object?>> Function(Map<String, dynamic>)>{};

  @override
  bool get isInitialized => true;

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    requests.add(request);
    final command = request['cmd']! as String;
    commands.add(command);
    final handler = responseHandlers[command];
    if (handler != null) return jsonEncode(await handler(request));
    return jsonEncode(switch (command) {
      'payload.sign' => const <String, Object?>{
        'ok': true,
        'signature': 'c2lnbmF0dXJl',
      },
      'call_endpoint_set_v1' => const <String, Object?>{'ok': true},
      'call_endpoint_revoke_v1' => const <String, Object?>{
        'ok': true,
        'revoked': true,
      },
      'call_wake_handle_set_v1' => const <String, Object?>{'ok': true},
      'call_wake_handle_revoke_v1' => const <String, Object?>{
        'ok': true,
        'revoked': true,
      },
      'call_token_revoke_v1' => const <String, Object?>{
        'ok': true,
        'revoked': true,
      },
      'call_retrieve_v1' => const <String, Object?>{
        'ok': true,
        'events': <Object?>[],
        'receiptAtMs': 1,
        'expiresAtMs': 1,
        'hasMore': false,
      },
      _ => const <String, Object?>{'ok': false},
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _P2P implements P2PService {
  final StreamController<ChatMessage> messages =
      StreamController<ChatMessage>.broadcast();
  final StreamController<NodeState> states =
      StreamController<NodeState>.broadcast(sync: true);

  @override
  NodeState get currentState =>
      const NodeState(peerId: 'local-account', isStarted: true);

  @override
  Stream<ChatMessage> get messageStream => messages.stream;

  @override
  Stream<NodeState> get stateStream => states.stream;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async => const SendMessageResult(sent: false, acked: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}


// A caller observes the peer graph's actual signed endpoint publications, while
// fake crypto and transports keep this proof independent of network/native I/O.
final class _LiveVideoTransport {
  _LiveVideoTransport({required this.bridge, required this.nowMs}) {
    admitted = endpoint;
    contexts.storeOutgoingV2(
      invite: signal('invite', sequence: 1),
      callHandle: _handle,
      admittedEndpoint: admitted,
    );
  }

  static const _handle = '66666666-6666-4666-8666-666666666666';
  final _Bridge bridge;
  final int Function() nowMs;
  final contexts = CallSignalingContextStore(videoEnabled: true);
  final direct = _LiveVideoDirect();
  final mailbox = _LiveVideoMailbox();
  late final ResolvedCallEndpoint admitted;
  late final service = CallSignalingService(
    codec: SecureCallEnvelopeCodec(
      crypto: _LiveVideoCrypto(),
      nowMs: nowMs,
      videoEnabled: true,
    ),
    directTransport: direct,
    mailboxClient: mailbox,
    networkEffectsAllowed: () => true,
    nowMs: nowMs,
  );
  late final adapter = ProductionCallV2SignalingAdapter(
    signalingService: service,
    contextStore: contexts,
    resolveCurrentEndpoint: (_) async => endpoint,
    loadSenderSigningPrivateKey: () async => 'remote-private-key',
    nowMs: nowMs,
    videoEnabled: true,
  );

  ResolvedCallEndpoint get endpoint {
    final request = bridge.requests.lastWhere(
      (request) => request['cmd'] == 'call_endpoint_set_v1',
    );
    final record = request['payload']! as Map<String, dynamic>;
    return ResolvedCallEndpoint(
      accountPeerId: record['accountPeerId']! as String,
      devicePeerId: record['devicePeerId']! as String,
      signingPublicKey: 'local-public-key',
      mlKemPublicKey: 'local-mlkem-public-key',
      deviceKeyEpoch: record['deviceKeyEpoch']! as int,
      preferenceEpoch: record['preferenceEpoch']! as int,
      platform: CallEndpointPlatform.parse(record['platform']! as String),
      expiresAtMs: record['expiresAtMs']! as int,
      routingHandle: record['routingHandle']! as String,
      wakeHandle: '0123456789abcdef0123456789abcdef',
      capabilities: Set<String>.from(record['capabilities']! as List),
    );
  }

  CallSignalV2 signal(String event, {required int sequence}) =>
      CallSignalV2.fromMap({
        'schema': CallSignalV2.schema,
        'call_id': _callA.value,
        'message_id':
            '33333333-3333-4333-8333-${sequence.toString().padLeft(12, '0')}',
        'event': event,
        'sender_account_peer_id': 'remote-account',
        'sender_device_peer_id': 'remote-device',
        'recipient_account_peer_id': 'local-account',
        'recipient_device_peer_id': 'local-account',
        'sender_sequence': sequence,
        'ice_generation': 0,
        'created_at_ms': nowMs(),
        'expires_at_ms': nowMs() + 45000,
        'payload': switch (event) {
          'invite' => {
            'media': 'video',
            'camera': 'off',
            'capabilities': ['audio', 'video'],
          },
          'terminate' => {'reason': 'local_hangup'},
          'media_request' => {
            'switch_id': '55555555-5555-4555-8555-555555555555',
            'base_revision': 0,
            'target_media': 'audio',
            'camera': 'off',
          },
          _ => {'media_revision': 0, 'state': 'paused'},
        },
      }, videoEnabled: true);

  Future<void> send(String event, {required int sequence}) async {
    final prepared = await adapter.prepare(
      signal: signal(event, sequence: sequence),
      callHandle: _handle,
      admittedEndpoint: admitted,
      canApply: () => true,
    );
    expect((await prepared.transmit(canApply: () => true)).delivered, isTrue);
  }

  void close() {
    adapter.close();
    service.close();
  }
}

final class _LiveVideoDirect implements CallDirectTransport {
  final envelopes = <String>[];

  @override
  Future<CallDirectSendResult> send({
    required String recipientDevicePeerId,
    required String envelopeJson,
  }) async {
    envelopes.add(envelopeJson);
    return const CallDirectSendResult(
      outcome: CallDirectTransportOutcome.acceptedBytes,
      transportAcknowledged: true,
      route: CallDirectRoute.direct,
    );
  }
}

final class _LiveVideoMailbox implements CallMailboxClient {
  final requests = <CallMailboxStoreRequest>[];

  @override
  Future<CallMailboxStoreResult> store(CallMailboxStoreRequest request) async {
    requests.add(request);
    return CallMailboxStoreResult(
      status: CallMailboxStoreStatus.stored,
      receiptAtMs: 2_000_000,
      expiresAtMs: request.expiresAtMs,
      eventCount: 1,
      totalBytes: 100,
      pendingHandles: 1,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _LiveVideoCrypto implements CallEnvelopeCrypto {
  @override
  Future<CallCiphertext> encrypt({
    required String recipientMlKemPublicKey,
    required String plaintext,
  }) async => CallCiphertext(
    kem: base64Encode(utf8.encode('fixture-kem')),
    ciphertext: base64Encode(utf8.encode(plaintext)),
    nonce: base64Encode(utf8.encode('fixture-nonce')),
  );

  @override
  Future<String> sign({
    required String senderSigningPrivateKey,
    required String canonicalData,
  }) async => base64Encode(utf8.encode(canonicalData));

  @override
  Future<String> decrypt({
    required String ownMlKemSecretKey,
    required CallCiphertext ciphertext,
  }) => throw UnimplementedError();

  @override
  Future<bool> verify({
    required String senderSigningPublicKey,
    required String canonicalData,
    required String signature,
  }) async => true;
}
