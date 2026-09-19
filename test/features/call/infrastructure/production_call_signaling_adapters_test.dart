import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_control_effect_executor.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_endpoint_resolver.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_negotiation_effect_executor.dart';
import 'package:flutter_app/features/call/application/call_signaling_context_store.dart';
import 'package:flutter_app/features/call/application/call_signaling_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_mailbox_client.dart';
import 'package:flutter_app/features/call/infrastructure/p2p_call_transport.dart';
import 'package:flutter_app/features/call/infrastructure/production_call_signaling_adapters.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_test/flutter_test.dart';

const _nowMs = 2_000_000;
final _now = DateTime.fromMillisecondsSinceEpoch(_nowMs, isUtc: true);
final _callId = CallId.parse('11111111-1111-4111-8111-111111111111');
const _callHandle = '22222222-2222-4222-8222-222222222222';

void main() {
  CallNegotiationPortException failure(
    Future<void> operation,
    FakeAsync async,
  ) {
    Object? failed;
    operation.catchError((Object error) {
      failed = error;
    });
    async.flushMicrotasks();
    expect(failed, isA<CallNegotiationPortException>());
    return failed! as CallNegotiationPortException;
  }

  test(
    'fenced restart offer suppresses writes after End across every await',
    () {
      for (final boundary in ['endpoint', 'key', 'network', 'crypto']) {
        fakeAsync((async) {
          final rig = _NegotiationRetryHarness(async);
          final gate = Completer<void>();
          switch (boundary) {
            case 'endpoint':
              rig.endpointGate = gate.future;
            case 'key':
              rig.keyGate = gate.future;
            case 'network':
              rig.networkGate = gate.future;
            case 'crypto':
              rig.crypto.encryptGate = gate.future;
          }
          var current = true;
          Object? rejected;
          rig.adapter
              .sendDescription(
                callId: _callId,
                iceGeneration: 1,
                canApply: () => current,
                description: const CallSessionDescription(
                  type: CallSessionDescriptionType.offer,
                  value: 'private-sdp',
                  fingerprint: 'private-fingerprint',
                ),
              )
              .catchError((Object e) {
                rejected = e;
              });
          async.flushMicrotasks();
          current = false;
          expect(
            rig.contexts.read(_callId),
            isNotNull,
            reason: 'End authority precedes the eventual context cleanup',
          );
          gate.complete();
          async.flushMicrotasks();
          expect(
            rejected,
            isA<CallNegotiationPortException>(),
            reason: boundary,
          );
          expect(rig.mailbox.requests, isEmpty, reason: boundary);
          expect(
            rig.service.pendingTransmissionRetryCount,
            0,
            reason: boundary,
          );
          rig.service.close();
        });
      }
    },
  );

  test(
    'reconnect retry rechecks refreshed endpoint expiry after key await',
    () {
      fakeAsync((async) {
        final rig = _NegotiationRetryHarness(async);
        rig.mailbox.storeSucceeds = false;
        final first = failure(
          rig.adapter.sendIceRestart(callId: _callId, iceGeneration: 1),
          async,
        );
        rig.endpoint = _endpoint(expiresAtMs: _nowMs + 500);
        final key = Completer<void>();
        rig.keyGate = key.future;
        Object? rejected;
        first.retry!.retry(canApply: () => true).catchError((Object e) {
          rejected = e;
        });
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 600));
        rig.mailbox.storeSucceeds = true;
        key.complete();
        async.flushMicrotasks();
        expect(rejected, isA<CallNegotiationPortException>());
        expect(rig.mailbox.requests, hasLength(1));
        rig.service.close();
      });
    },
  );

  test(
    'reconnect retry preserves sealed restart and SDP bytes and metadata',
    () {
      for (final event in ['restart', 'offer', 'answer']) {
        fakeAsync((async) {
          final rig = _NegotiationRetryHarness(async);
          rig.mailbox.storeSucceeds = false;
          final failed = failure(
            event == 'restart'
                ? rig.adapter.sendIceRestart(callId: _callId, iceGeneration: 1)
                : rig.adapter.sendDescription(
                    callId: _callId,
                    iceGeneration: 1,
                    description: CallSessionDescription(
                      type: event == 'offer'
                          ? CallSessionDescriptionType.offer
                          : CallSessionDescriptionType.answer,
                      value: 'private-sdp',
                      fingerprint: 'private-fingerprint',
                    ),
                  ),
            async,
          );
          expect(
            failed.code,
            CallNegotiationPortErrorCode.transportUnavailable,
          );
          expect(failed.retry, isNotNull);
          expect(rig.service.pendingTransmissionRetryCount, 1);
          final original = rig.mailbox.requests.single;
          final sequence = rig.contexts.read(_callId)!.nextSenderSequence;
          rig.mailbox.storeSucceeds = true;
          var delivered = false;
          failed.retry!.retry(canApply: () => true).then((_) {
            delivered = true;
          });
          async.flushMicrotasks();
          expect(delivered, isTrue);
          expect(rig.mailbox.requests, hasLength(2));
          final retry = rig.mailbox.requests.last;
          expect(retry.envelopeJson, original.envelopeJson);
          expect(retry.messageId, original.messageId);
          expect(retry.expiresAtMs, original.expiresAtMs);
          expect(retry.callHandle, original.callHandle);
          expect(retry.recipientDevicePeerId, original.recipientDevicePeerId);
          expect(rig.crypto.plaintexts, hasLength(1));
          expect(rig.contexts.read(_callId)!.nextSenderSequence, sequence);
          expect(rig.service.pendingTransmissionRetryCount, 0);
          _expectRedacted('$failed');
          failed.retry!.close();
          rig.service.close();
        });
      }
    },
  );

  test(
    'reconnect retry survives the production offline authority response',
    () {
      fakeAsync((async) {
        final rig = _NegotiationRetryHarness(async);
        final bridge = _RetryAuthorityBridge();
        final authority = BridgeCallAuthorityClient(bridge: bridge);
        rig.mailbox.storeSucceeds = false;
        final first = failure(
          rig.adapter.sendIceRestart(callId: _callId, iceGeneration: 1),
          async,
        );
        final original = rig.mailbox.requests.single;
        rig.beforeEndpointLookup = () async {
          await authority.getEndpoint('remote-account');
        };
        bridge.errorCode = 'CALL_CONTROL_UNAVAILABLE';
        final unavailable = failure(
          first.retry!.retry(canApply: () => true),
          async,
        );
        expect(
          unavailable.code,
          CallNegotiationPortErrorCode.transportUnavailable,
        );
        expect(unavailable.retry, same(first.retry));
        expect(rig.service.pendingTransmissionRetryCount, 1);
        expect(rig.mailbox.requests, hasLength(1));

        bridge.errorCode = null;
        rig.mailbox.storeSucceeds = true;
        var delivered = false;
        unavailable.retry!.retry(canApply: () => true).then((_) {
          delivered = true;
        });
        async.flushMicrotasks();
        expect(delivered, isTrue);
        expect(bridge.lookups, 2);
        expect(rig.mailbox.requests, hasLength(2));
        final retry = rig.mailbox.requests.last;
        expect(retry.envelopeJson, original.envelopeJson);
        expect(retry.messageId, original.messageId);
        expect(retry.expiresAtMs, original.expiresAtMs);
        expect(rig.crypto.plaintexts, hasLength(1));
        expect(rig.service.pendingTransmissionRetryCount, 0);
        rig.service.close();
      });
    },
  );

  test('reconnect retry rejects other production authority refusal codes', () {
    for (final code in [
      'CALL_UNAUTHORIZED',
      'CALL_STALE_EPOCH',
      'CALL_CONTROL_INVALID_RESPONSE',
      'CALL_CONTROL_UNSUPPORTED',
      'ARBITRARY_UNKNOWN_CODE',
    ]) {
      fakeAsync((async) {
        final rig = _NegotiationRetryHarness(async);
        final bridge = _RetryAuthorityBridge()..errorCode = code;
        final authority = BridgeCallAuthorityClient(bridge: bridge);
        rig.mailbox.storeSucceeds = false;
        final first = failure(
          rig.adapter.sendIceRestart(callId: _callId, iceGeneration: 1),
          async,
        );
        rig.beforeEndpointLookup = () async {
          await authority.getEndpoint('remote-account');
        };
        final refused = failure(
          first.retry!.retry(canApply: () => true),
          async,
        );
        expect(
          refused.code,
          CallNegotiationPortErrorCode.signalingUnavailable,
          reason: code,
        );
        expect(refused.retry, isNull, reason: code);
        expect(rig.service.pendingTransmissionRetryCount, 0, reason: code);
        expect(rig.mailbox.requests, hasLength(1), reason: code);
        rig.service.close();
      });
    }
  });

  test(
    'reconnect candidate retry resumes remaining tail without resending accepted prefix',
    () {
      fakeAsync((async) {
        final rig = _NegotiationRetryHarness(async);
        rig.mailbox.failAtStores.addAll([2, 4]);
        final first = failure(
          rig.adapter.sendCandidates(
            callId: _callId,
            candidates: [
              for (var i = 0; i < 3; i++)
                CallIceCandidate(
                  value: 'candidate-$i',
                  iceGeneration: 1,
                  mediaId: 'audio',
                  mediaLineIndex: 0,
                ),
            ],
          ),
          async,
        );
        expect(rig.mailbox.requests, hasLength(2));
        final second = failure(first.retry!.retry(canApply: () => true), async);
        expect(second.code, CallNegotiationPortErrorCode.transportUnavailable);
        expect(second.retry, isNotNull);
        first.retry!.close();
        var delivered = false;
        second.retry!.retry(canApply: () => true).then((_) {
          delivered = true;
        });
        async.flushMicrotasks();
        expect(delivered, isTrue);
        expect(rig.mailbox.requests, hasLength(5));
        final requests = rig.mailbox.requests;
        expect(requests[1].envelopeJson, requests[2].envelopeJson);
        expect(requests[3].envelopeJson, requests[4].envelopeJson);
        expect(rig.crypto.plaintexts, hasLength(3));
        expect(rig.contexts.read(_callId)!.nextSenderSequence, 4);
        expect(rig.adapter.toDiagnosticMap()['candidateSendCount'], 3);
        expect(rig.service.pendingTransmissionRetryCount, 0);
        rig.service.close();
      });
    },
  );

  test(
    'reconnect retry fences current binding and phase after awaited authority',
    () {
      for (final invalidation in [
        'context',
        'generation',
        'phase',
        'shutdown',
        'expiry',
      ]) {
        fakeAsync((async) {
          final rig = _NegotiationRetryHarness(async);
          rig.mailbox.storeSucceeds = false;
          final first = failure(
            rig.adapter.sendIceRestart(callId: _callId, iceGeneration: 1),
            async,
          );
          final gate = Completer<void>();
          rig.endpointGate = gate.future;
          var current = true;
          Object? rejected;
          first.retry!.retry(canApply: () => current).catchError((Object e) {
            rejected = e;
          });
          async.flushMicrotasks();
          switch (invalidation) {
            case 'context':
              rig.contexts.purge(_callId);
            case 'generation':
              rig.contexts.reserveNextMetadata(_callId, iceGeneration: 2);
            case 'phase':
              current = false;
            case 'shutdown':
              rig.service.stopRetries();
            case 'expiry':
              async.elapse(const Duration(seconds: 15));
          }
          rig.mailbox.storeSucceeds = true;
          gate.complete();
          async.flushMicrotasks();
          expect(
            rejected,
            isA<CallNegotiationPortException>(),
            reason: invalidation,
          );
          expect(rig.mailbox.requests, hasLength(1), reason: invalidation);
          expect(
            rig.service.pendingTransmissionRetryCount,
            0,
            reason: invalidation,
          );
          if (invalidation == 'context') {
            expect(rig.contexts.pinnedEndpoint(_callId), isNull);
          }
          first.retry!.close();
          rig.service.close();
        });
      }
    },
  );

  test(
    'reconnect retry is bounded and current account or recipient revocation stops it',
    () {
      for (final invalidation in [
        'account',
        'recipient',
        'network',
        'attempts',
      ]) {
        fakeAsync((async) {
          final rig = _NegotiationRetryHarness(async);
          rig.mailbox.storeSucceeds = false;
          final first = failure(
            rig.adapter.sendIceRestart(callId: _callId, iceGeneration: 1),
            async,
          );
          if (invalidation == 'account') rig.accountCurrent = false;
          if (invalidation == 'recipient') {
            rig.endpoint = _endpoint(devicePeerId: 'replacement');
          }
          if (invalidation == 'network') rig.networkAllowed = false;
          if (invalidation == 'attempts') {
            late CallNegotiationPortException exhausted;
            for (var i = 0; i < 4; i++) {
              exhausted = failure(
                first.retry!.retry(canApply: () => true),
                async,
              );
            }
            expect(
              exhausted.code,
              CallNegotiationPortErrorCode.transportUnavailable,
            );
            expect(exhausted.retry, isNull);
          } else {
            failure(first.retry!.retry(canApply: () => true), async);
          }
          expect(
            rig.mailbox.requests,
            hasLength(invalidation == 'attempts' ? 5 : 1),
          );
          expect(rig.service.pendingTransmissionRetryCount, 0);
          rig.mailbox.storeSucceeds = true;
          failure(first.retry!.retry(canApply: () => true), async);
          expect(
            rig.mailbox.requests,
            hasLength(invalidation == 'attempts' ? 5 : 1),
          );
          rig.service.close();
        });
      }
    },
  );

  group('ProductionCallControlSignalingAdapter', () {
    test('prepares a fresh opaque binding with audio-only metadata', () async {
      final harness = _ServiceHarness();
      addTearDown(harness.dispose);
      final authority = _EndpointAuthority(_endpoint());
      final ids = _Ids(<String>[
        '33333333-3333-4333-8333-333333333333',
        '44444444-4444-4444-8444-444444444444',
      ]);
      final adapter = ProductionCallControlSignalingAdapter(
        signalingService: harness.service,
        contextStore: CallSignalingContextStore(),
        resolveCurrentEndpoint: authority.resolve,
        loadSenderSigningPrivateKey: _loadSigningKey,
        callHandleSource: ids.next,
      );

      final first = await adapter.prepareOutgoingInvite(_outgoingPreparing());
      final second = await adapter.prepareOutgoingInvite(_outgoingPreparing());

      expect(authority.requestedAccounts, <String>[
        'remote-account',
        'remote-account',
      ]);
      expect(first.remoteAccountPeerId, 'remote-account');
      expect(first.remoteDevicePeerId, 'remote-device');
      expect(CallId.tryParse(first.callHandle), isNotNull);
      expect(first.callHandle, isNot(_callId.value));
      expect(second.callHandle, isNot(first.callHandle));
      expect(first.nextSenderSequence, 1);
      expect(first.iceGeneration, 0);
      expect(first.invitePayload, <String, Object?>{
        'capabilities': <Object?>['audio'],
        'metadata': <String, Object?>{'media': 'audio', 'video': false},
      });
      final encoded = jsonEncode(first.invitePayload).toLowerCase();
      expect(encoded, isNot(contains('sdp')));
      expect(encoded, isNot(contains('candidate')));
      expect(encoded, isNot(contains('ice')));
    });

    test(
      're-resolves the exact endpoint for send and fails closed after rotation',
      () async {
        final harness = _ServiceHarness();
        addTearDown(harness.dispose);
        final authority = _EndpointAuthority(_endpoint());
        final adapter = ProductionCallControlSignalingAdapter(
          signalingService: harness.service,
          contextStore: CallSignalingContextStore(),
          resolveCurrentEndpoint: authority.resolve,
          loadSenderSigningPrivateKey: _loadSigningKey,
          callHandleSource: _Ids(<String>[
            '33333333-3333-4333-8333-333333333333',
          ]).next,
        );
        final prepared = await adapter.prepareOutgoingInvite(
          _outgoingPreparing(),
        );
        authority.current = _endpoint(devicePeerId: 'rotated-device');

        await expectLater(
          adapter.send(
            signal: _controlSignal(
              recipientDevicePeerId: prepared.remoteDevicePeerId,
            ),
            callHandle: prepared.callHandle,
          ),
          throwsA(
            isA<CallControlSignalingPortException>().having(
              (error) => error.code,
              'code',
              CallControlSignalingPortErrorCode.endpointMismatch,
            ),
          ),
        );

        expect(authority.calls, 2);
        expect(harness.direct.calls, 0);
        expect(harness.mailbox.stores, 0);
      },
    );

    test(
      'send uses the pinned endpoint when the directory record is gone',
      () async {
        final harness = _ServiceHarness();
        addTearDown(harness.dispose);
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));
        final authority = _EndpointAuthority(_endpoint());
        final contextStore = CallSignalingContextStore();
        final adapter = ProductionCallControlSignalingAdapter(
          signalingService: harness.service,
          contextStore: contextStore,
          resolveCurrentEndpoint: authority.resolve,
          loadSenderSigningPrivateKey: _loadSigningKey,
          callHandleSource: _Ids(<String>[
            '33333333-3333-4333-8333-333333333333',
          ]).next,
          clock: () => _now,
        );
        final prepared = await adapter.prepareOutgoingInvite(
          _outgoingPreparing(),
        );
        await adapter.send(
          signal: _controlSignal(),
          callHandle: prepared.callHandle,
        );
        expect(harness.direct.calls, 1);
        expect(
          contextStore.pinnedEndpoint(_callId)?.devicePeerId,
          'remote-device',
        );

        // The callee's directory record vanishes mid-call.
        authority.error = const CallEndpointResolutionException(
          CallEndpointResolutionCode.unavailable,
        );
        final result = await adapter.send(
          signal: _controlSignal(
            event: CallSignalType.terminate,
            senderSequence: 2,
            messageId: '70000000-0000-4000-8000-000000000002',
          ),
          callHandle: prepared.callHandle,
        );

        expect(result.directAccepted, isTrue);
        expect(authority.calls, 3);
        expect(harness.direct.calls, 2);
        expect(harness.direct.recipients.last, 'remote-device');
        expect(harness.crypto.recipientKeys.last, 'secret-remote-mlkem-key');
        final fallbacks = events
            .where((event) => event['event'] == 'CALL_ENDPOINT_PINNED_FALLBACK')
            .toList(growable: false);
        expect(fallbacks, hasLength(1));
        expect(fallbacks.single['details'], <String, Object?>{
          'reason': 'unavailable',
          'adapter': 'control',
        });
        _expectRedacted(jsonEncode(fallbacks));
      },
    );

    test(
      'invite and blocked resolutions never use the pinned endpoint',
      () async {
        final harness = _ServiceHarness();
        addTearDown(harness.dispose);
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));
        final authority = _EndpointAuthority(_endpoint());
        final contextStore = CallSignalingContextStore();
        final adapter = ProductionCallControlSignalingAdapter(
          signalingService: harness.service,
          contextStore: contextStore,
          resolveCurrentEndpoint: authority.resolve,
          loadSenderSigningPrivateKey: _loadSigningKey,
          callHandleSource: _Ids(<String>[
            '33333333-3333-4333-8333-333333333333',
          ]).next,
          clock: () => _now,
        );
        final prepared = await adapter.prepareOutgoingInvite(
          _outgoingPreparing(),
        );
        await adapter.send(
          signal: _controlSignal(),
          callHandle: prepared.callHandle,
        );
        expect(harness.direct.calls, 1);
        expect(contextStore.pinnedEndpoint(_callId), isNotNull);

        final mismatch = isA<CallControlSignalingPortException>().having(
          (error) => error.code,
          'code',
          CallControlSignalingPortErrorCode.endpointMismatch,
        );
        // (1) invite never rides a pin: a fresh record is the callee's consent.
        authority.error = const CallEndpointResolutionException(
          CallEndpointResolutionCode.unavailable,
        );
        await expectLater(
          adapter.send(
            signal: _controlSignal(
              senderSequence: 2,
              messageId: '70000000-0000-4000-8000-000000000002',
            ),
            callHandle: prepared.callHandle,
          ),
          throwsA(mismatch),
        );
        // (2) blocked always fails closed, pin or not.
        authority.error = const CallEndpointResolutionException(
          CallEndpointResolutionCode.blocked,
        );
        await expectLater(
          adapter.send(
            signal: _controlSignal(
              event: CallSignalType.terminate,
              senderSequence: 3,
              messageId: '70000000-0000-4000-8000-000000000003',
            ),
            callHandle: prepared.callHandle,
          ),
          throwsA(mismatch),
        );

        expect(harness.direct.calls, 1);
        expect(harness.mailbox.stores, 1);
        expect(
          events.where(
            (event) => event['event'] == 'CALL_ENDPOINT_PINNED_FALLBACK',
          ),
          isEmpty,
        );
      },
    );

    test('pinned endpoint is purged at terminal cleanup', () async {
      final harness = _ServiceHarness();
      addTearDown(harness.dispose);
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      addTearDown(() => debugSetFlowEventSink(null));
      final authority = _EndpointAuthority(_endpoint());
      final contextStore = CallSignalingContextStore();
      final adapter = ProductionCallControlSignalingAdapter(
        signalingService: harness.service,
        contextStore: contextStore,
        resolveCurrentEndpoint: authority.resolve,
        loadSenderSigningPrivateKey: _loadSigningKey,
        callHandleSource: _Ids(<String>[
          '33333333-3333-4333-8333-333333333333',
        ]).next,
        clock: () => _now,
      );
      final prepared = await adapter.prepareOutgoingInvite(
        _outgoingPreparing(),
      );
      await adapter.send(
        signal: _controlSignal(),
        callHandle: prepared.callHandle,
      );
      authority.error = const CallEndpointResolutionException(
        CallEndpointResolutionCode.unavailable,
      );
      await adapter.send(
        signal: _controlSignal(
          event: CallSignalType.terminate,
          senderSequence: 2,
          messageId: '70000000-0000-4000-8000-000000000002',
        ),
        callHandle: prepared.callHandle,
      );
      expect(harness.direct.calls, 2);

      // The call_signaling_context cleanup step purges the call.
      contextStore.purge(_callId);
      expect(contextStore.pinnedEndpoint(_callId), isNull);

      await expectLater(
        adapter.send(
          signal: _controlSignal(
            event: CallSignalType.terminate,
            senderSequence: 3,
            messageId: '70000000-0000-4000-8000-000000000003',
          ),
          callHandle: prepared.callHandle,
        ),
        throwsA(
          isA<CallControlSignalingPortException>().having(
            (error) => error.code,
            'code',
            CallControlSignalingPortErrorCode.endpointMismatch,
          ),
        ),
      );
      expect(harness.direct.calls, 2);
      expect(
        events.where(
          (event) => event['event'] == 'CALL_ENDPOINT_PINNED_FALLBACK',
        ),
        hasLength(1),
      );
    });

    test(
      'maps transmit receipts without recursively dispatching coordinator events',
      () async {
        final harness = _ServiceHarness(
          directResult: const CallDirectSendResult(
            outcome: CallDirectTransportOutcome.acceptedBytes,
            transportAcknowledged: true,
            route: CallDirectRoute.circuitRelay,
          ),
        );
        addTearDown(harness.dispose);
        await _prepareCoordinator(harness.coordinator);
        final before = List<String>.of(
          harness.coordinator.activeSession!.recentEventIds,
        );
        final authority = _EndpointAuthority(_endpoint());
        final adapter = ProductionCallControlSignalingAdapter(
          signalingService: harness.service,
          contextStore: CallSignalingContextStore(),
          resolveCurrentEndpoint: authority.resolve,
          loadSenderSigningPrivateKey: _loadSigningKey,
        );

        final result = await adapter.send(
          signal: _controlSignal(),
          callHandle: _callHandle,
        );

        expect(result.directAccepted, isTrue);
        expect(result.mailboxStored, isTrue);
        expect(result.directRoute, CallRouteClass.circuitRelay);
        expect(authority.calls, 1);
        expect(harness.direct.calls, 1);
        expect(harness.mailbox.stores, 1);
        expect(harness.coordinator.activeSession!.recentEventIds, before);
        expect(
          harness.coordinator.activeSession!.mailboxCustodyConfirmed,
          false,
        );
      },
    );

    test('propagates direct-first pending mailbox settlement', () async {
      final storeGate = Completer<void>();
      final harness = _ServiceHarness(mailboxStoreGate: storeGate.future);
      addTearDown(harness.dispose);
      final adapter = ProductionCallControlSignalingAdapter(
        signalingService: harness.service,
        contextStore: CallSignalingContextStore(),
        resolveCurrentEndpoint: _EndpointAuthority(_endpoint()).resolve,
        loadSenderSigningPrivateKey: _loadSigningKey,
      );

      final result = await adapter.send(
        signal: _controlSignal(),
        callHandle: _callHandle,
      );
      var mailboxSettled = false;
      final settlement = result.mailboxStoreSettled;
      unawaited(settlement.then<void>((_) => mailboxSettled = true));
      await Future<void>.delayed(Duration.zero);
      expect(result.directAccepted, isTrue);
      expect(result.mailboxStored, isFalse);
      expect(mailboxSettled, isFalse);

      storeGate.complete();
      await settlement;

      expect(mailboxSettled, isTrue);
      expect(harness.mailbox.stores, 1);
    });

    test(
      'the relay wake outcome reaches the executor result without a receipt of its own',
      () async {
        final harness = _ServiceHarness(
          directResult: const CallDirectSendResult(
            outcome: CallDirectTransportOutcome.acceptedBytes,
            transportAcknowledged: true,
            route: CallDirectRoute.circuitRelay,
          ),
        );
        addTearDown(harness.dispose);
        await _prepareCoordinator(harness.coordinator);
        final before = List<String>.of(
          harness.coordinator.activeSession!.recentEventIds,
        );
        final authority = _EndpointAuthority(_endpoint());
        final adapter = ProductionCallControlSignalingAdapter(
          signalingService: harness.service,
          contextStore: CallSignalingContextStore(),
          resolveCurrentEndpoint: authority.resolve,
          loadSenderSigningPrivateKey: _loadSigningKey,
        );
        harness.mailbox.wake = CallMailboxWakeStatus.dispatched;

        final result = await adapter.send(
          signal: _controlSignal(),
          callHandle: _callHandle,
        );

        expect(result.directAccepted, isTrue);
        expect(result.mailboxStored, isTrue);
        expect(result.wakeDispatched, isTrue);
        expect(result.directRoute, CallRouteClass.circuitRelay);
        expect(authority.calls, 1);
        expect(harness.direct.calls, 1);
        expect(harness.mailbox.stores, 1);
        expect(harness.coordinator.activeSession!.recentEventIds, before);
        expect(
          harness.coordinator.activeSession!.mailboxCustodyConfirmed,
          false,
        );
      },
    );

    test('propagates direct-first pending mailbox settlement', () async {
      final storeGate = Completer<void>();
      final harness = _ServiceHarness(mailboxStoreGate: storeGate.future);
      addTearDown(harness.dispose);
      final adapter = ProductionCallControlSignalingAdapter(
        signalingService: harness.service,
        contextStore: CallSignalingContextStore(),
        resolveCurrentEndpoint: _EndpointAuthority(_endpoint()).resolve,
        loadSenderSigningPrivateKey: _loadSigningKey,
      );

      final result = await adapter.send(
        signal: _controlSignal(),
        callHandle: _callHandle,
      );
      var mailboxSettled = false;
      final settlement = result.mailboxStoreSettled;
      unawaited(settlement.then<void>((_) => mailboxSettled = true));
      await Future<void>.delayed(Duration.zero);
      expect(result.directAccepted, isTrue);
      expect(result.mailboxStored, isFalse);
      expect(mailboxSettled, isFalse);

      storeGate.complete();
      await settlement;

      expect(mailboxSettled, isTrue);
      expect(harness.mailbox.stores, 1);
    });

    test('maps arbitrary failures to fixed-shape redacted errors', () async {
      final harness = _ServiceHarness();
      addTearDown(harness.dispose);
      final authority = _EndpointAuthority(_endpoint())
        ..error = StateError(
          'secret-peer secret-handle secret-key secret-sdp secret-candidate',
        );
      final adapter = ProductionCallControlSignalingAdapter(
        signalingService: harness.service,
        contextStore: CallSignalingContextStore(),
        resolveCurrentEndpoint: authority.resolve,
        loadSenderSigningPrivateKey: _loadSigningKey,
      );

      Object? caught;
      try {
        await adapter.send(signal: _controlSignal(), callHandle: _callHandle);
      } catch (error) {
        caught = error;
      }

      expect(caught, isA<CallControlSignalingPortException>());
      expect('$caught', 'CallControlSignalingPortException(endpointMismatch)');
      _expectRedacted('$caught $adapter');
    });
  });

  group('ProductionCallNegotiationSignalingAdapter', () {
    test(
      'uses context bindings and monotonic metadata for SDP, ICE, and restart',
      () async {
        final harness = _ServiceHarness();
        addTearDown(harness.dispose);
        final contextStore = _outgoingContext(nextSenderSequence: 7);
        final authority = _EndpointAuthority(_endpoint());
        final adapter = ProductionCallNegotiationSignalingAdapter(
          signalingService: harness.service,
          contextStore: contextStore,
          resolveCurrentEndpoint: authority.resolve,
          loadSenderSigningPrivateKey: _loadSigningKey,
          clock: () => _now,
          messageIdSource: _Ids(<String>[
            '50000000-0000-4000-8000-000000000001',
            '50000000-0000-4000-8000-000000000002',
            '50000000-0000-4000-8000-000000000003',
            '50000000-0000-4000-8000-000000000004',
            '50000000-0000-4000-8000-000000000005',
            '50000000-0000-4000-8000-000000000006',
          ]).next,
        );

        await adapter.sendDescription(
          callId: _callId,
          description: const CallSessionDescription(
            type: CallSessionDescriptionType.offer,
            value: 'secret-offer-sdp',
            fingerprint: 'secret-offer-fingerprint',
          ),
          iceGeneration: 1,
        );
        await adapter.sendDescription(
          callId: _callId,
          description: const CallSessionDescription(
            type: CallSessionDescriptionType.answer,
            value: 'secret-answer-sdp',
            fingerprint: 'secret-answer-fingerprint',
          ),
          iceGeneration: 1,
        );
        await adapter.sendCandidates(
          callId: _callId,
          candidates: const <CallIceCandidate>[
            CallIceCandidate(
              value: 'secret-candidate-one',
              mediaId: 'audio',
              mediaLineIndex: 0,
              iceGeneration: 2,
            ),
            CallIceCandidate(
              value: 'secret-candidate-two',
              mediaId: null,
              mediaLineIndex: null,
              iceGeneration: 2,
            ),
          ],
        );
        await adapter.sendIceRestart(callId: _callId, iceGeneration: 3);
        await adapter.sendDescription(
          callId: _callId,
          description: const CallSessionDescription(
            type: CallSessionDescriptionType.offer,
            value: 'secret-restart-offer-sdp',
            fingerprint: 'secret-restart-fingerprint',
          ),
          iceGeneration: 3,
        );

        final signals = harness.crypto.plaintexts
            .map(_decodeSignal)
            .toList(growable: false);
        expect(signals.map((signal) => signal.event), <CallSignalType>[
          CallSignalType.offer,
          CallSignalType.answer,
          CallSignalType.ice,
          CallSignalType.ice,
          CallSignalType.iceRestart,
          CallSignalType.offer,
        ]);
        expect(signals.map((signal) => signal.senderSequence), <int>[
          7,
          8,
          9,
          10,
          11,
          12,
        ]);
        expect(signals.map((signal) => signal.iceGeneration), <int>[
          1,
          1,
          2,
          2,
          3,
          3,
        ]);
        expect(
          signals.map((signal) => signal.expiresAtMs),
          everyElement(_nowMs + 40_000),
        );
        expect(signals[0].payload, <String, Object?>{
          'description': 'secret-offer-sdp',
          'fingerprint': 'secret-offer-fingerprint',
        });
        expect(signals[2].payload, <String, Object?>{
          'candidate': 'secret-candidate-one',
          'media_id': 'audio',
          'media_line_index': 0,
        });
        expect(signals[4].payload, isEmpty);
        expect(
          signals.every(
            (signal) =>
                signal.senderAccountPeerId == 'local-account' &&
                signal.senderDevicePeerId == 'local-device' &&
                signal.recipientAccountPeerId == 'remote-account' &&
                signal.recipientDevicePeerId == 'remote-device',
          ),
          isTrue,
        );
        expect(authority.calls, signals.length);
        expect(harness.direct.calls, signals.length);
        expect(harness.mailbox.stores, signals.length);
        expect(contextStore.read(_callId)?.nextSenderSequence, 13);
        expect(contextStore.read(_callId)?.iceGeneration, 3);
        _expectRedacted('$adapter');
      },
    );

    test('negotiation send fails closed after rotation', () async {
      final harness = _ServiceHarness();
      addTearDown(harness.dispose);
      final contextStore = _outgoingContext();
      final authority = _EndpointAuthority(_endpoint());
      final adapter = ProductionCallNegotiationSignalingAdapter(
        signalingService: harness.service,
        contextStore: contextStore,
        resolveCurrentEndpoint: authority.resolve,
        loadSenderSigningPrivateKey: _loadSigningKey,
        clock: () => _now,
        messageIdSource: _Ids(<String>[
          '50000000-0000-4000-8000-000000000011',
          '50000000-0000-4000-8000-000000000012',
        ]).next,
      );
      await adapter.sendDescription(
        callId: _callId,
        description: const CallSessionDescription(
          type: CallSessionDescriptionType.offer,
          value: 'secret-offer-sdp',
          fingerprint: 'secret-offer-fingerprint',
        ),
        iceGeneration: 0,
      );
      expect(harness.direct.calls, 1);

      authority.current = _endpoint(devicePeerId: 'rotated-device');
      await expectLater(
        adapter.sendDescription(
          callId: _callId,
          description: const CallSessionDescription(
            type: CallSessionDescriptionType.answer,
            value: 'secret-answer-sdp',
            fingerprint: 'secret-answer-fingerprint',
          ),
          iceGeneration: 0,
        ),
        throwsA(
          isA<CallNegotiationPortException>().having(
            (error) => error.code,
            'code',
            CallNegotiationPortErrorCode.signalingUnavailable,
          ),
        ),
      );
      expect(authority.calls, 2);
      expect(harness.direct.calls, 1);
    });

    test(
      'sendDescription uses the pinned endpoint when the directory record is gone',
      () async {
        final harness = _ServiceHarness();
        addTearDown(harness.dispose);
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));
        final contextStore = _outgoingContext();
        final authority = _EndpointAuthority(_endpoint());
        final adapter = ProductionCallNegotiationSignalingAdapter(
          signalingService: harness.service,
          contextStore: contextStore,
          resolveCurrentEndpoint: authority.resolve,
          loadSenderSigningPrivateKey: _loadSigningKey,
          clock: () => _now,
          messageIdSource: _Ids(<String>[
            '50000000-0000-4000-8000-000000000021',
            '50000000-0000-4000-8000-000000000022',
          ]).next,
        );
        await adapter.sendDescription(
          callId: _callId,
          description: const CallSessionDescription(
            type: CallSessionDescriptionType.offer,
            value: 'secret-offer-sdp',
            fingerprint: 'secret-offer-fingerprint',
          ),
          iceGeneration: 0,
        );
        expect(harness.direct.calls, 1);
        expect(
          contextStore.pinnedEndpoint(_callId)?.devicePeerId,
          'remote-device',
        );

        authority.error = const CallEndpointResolutionException(
          CallEndpointResolutionCode.unavailable,
        );
        await adapter.sendDescription(
          callId: _callId,
          description: const CallSessionDescription(
            type: CallSessionDescriptionType.offer,
            value: 'secret-restart-offer-sdp',
            fingerprint: 'secret-restart-fingerprint',
          ),
          iceGeneration: 1,
        );

        expect(authority.calls, 2);
        expect(harness.direct.calls, 2);
        expect(harness.direct.recipients.last, 'remote-device');
        expect(harness.crypto.recipientKeys.last, 'secret-remote-mlkem-key');
        final fallbacks = events
            .where((event) => event['event'] == 'CALL_ENDPOINT_PINNED_FALLBACK')
            .toList(growable: false);
        expect(fallbacks, hasLength(1));
        expect(fallbacks.single['details'], <String, Object?>{
          'reason': 'unavailable',
          'adapter': 'negotiation',
        });
        _expectRedacted(jsonEncode(fallbacks));
      },
    );

    test('validates explicit signal lifetime overrides', () {
      final harness = _ServiceHarness();
      addTearDown(harness.dispose);

      ProductionCallNegotiationSignalingAdapter build(Duration lifetime) =>
          ProductionCallNegotiationSignalingAdapter(
            signalingService: harness.service,
            contextStore: _outgoingContext(),
            resolveCurrentEndpoint: _EndpointAuthority(_endpoint()).resolve,
            loadSenderSigningPrivateKey: _loadSigningKey,
            signalLifetime: lifetime,
          );

      expect(() => build(Duration.zero), throwsArgumentError);
      expect(
        () => build(
          SecureCallEnvelopeCodec.maximumPostconnectLifetime +
              const Duration(milliseconds: 1),
        ),
        throwsArgumentError,
      );
      expect(
        build(
          SecureCallEnvelopeCodec.maximumPostconnectLifetime,
        ).signalLifetime,
        SecureCallEnvelopeCodec.maximumPostconnectLifetime,
      );
    });

    test('answers from the authenticated incoming binding', () async {
      final harness = _ServiceHarness();
      addTearDown(harness.dispose);
      final store = CallSignalingContextStore();
      store.captureAuthenticated(
        signal: _incomingInvite(),
        callHandle: _callHandle,
      );
      final authority = _EndpointAuthority(_endpoint());
      final adapter = ProductionCallNegotiationSignalingAdapter(
        signalingService: harness.service,
        contextStore: store,
        resolveCurrentEndpoint: authority.resolve,
        loadSenderSigningPrivateKey: _loadSigningKey,
        clock: () => _now,
        messageIdSource: _Ids(<String>[
          '60000000-0000-4000-8000-000000000001',
        ]).next,
      );

      await adapter.sendDescription(
        callId: _callId,
        description: const CallSessionDescription(
          type: CallSessionDescriptionType.answer,
          value: 'secret-answer-sdp',
          fingerprint: 'secret-answer-fingerprint',
        ),
        iceGeneration: 0,
      );

      final signal = _decodeSignal(harness.crypto.plaintexts.single);
      expect(signal.senderAccountPeerId, 'local-account');
      expect(signal.senderDevicePeerId, 'local-device');
      expect(signal.recipientAccountPeerId, 'remote-account');
      expect(signal.recipientDevicePeerId, 'remote-device');
      expect(signal.senderSequence, 1);
      expect(signal.event, CallSignalType.answer);
    });

    test(
      'fails closed before transport when the current device no longer matches',
      () async {
        final harness = _ServiceHarness();
        addTearDown(harness.dispose);
        final authority = _EndpointAuthority(
          _endpoint(devicePeerId: 'rotated-device'),
        );
        final adapter = ProductionCallNegotiationSignalingAdapter(
          signalingService: harness.service,
          contextStore: _outgoingContext(),
          resolveCurrentEndpoint: authority.resolve,
          loadSenderSigningPrivateKey: _loadSigningKey,
          clock: () => _now,
        );

        Object? caught;
        try {
          await adapter.sendDescription(
            callId: _callId,
            description: const CallSessionDescription(
              type: CallSessionDescriptionType.offer,
              value: 'secret-sdp',
              fingerprint: 'secret-fingerprint',
            ),
            iceGeneration: 0,
          );
        } catch (error) {
          caught = error;
        }

        expect(caught, isA<CallNegotiationPortException>());
        expect('$caught', 'CallNegotiationPortException(signalingUnavailable)');
        expect(harness.crypto.plaintexts, isEmpty);
        expect(harness.direct.calls, 0);
        expect(harness.mailbox.stores, 0);
        _expectRedacted('$caught $adapter');
      },
    );
  });

  test('adapters use transmit and import no ordinary chat abstractions', () {
    const path =
        'lib/features/call/infrastructure/production_call_signaling_adapters.dart';
    final source = File(path).readAsStringSync();

    expect(source, contains('_signalingService.transmit('));
    expect(source, isNot(contains('_signalingService.send(')));
    for (final forbidden in const <String>[
      'features/conversation/',
      'pending_message_retrier',
      'message_outbox',
      'PendingMessageRetrier',
      'MessageRepository',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}

CallSessionSnapshot _outgoingPreparing() => CallSessionSnapshot.active(
  callId: _callId,
  contactPeerId: 'remote-account',
  direction: CallDirection.outgoing,
  state: CallState.preparing,
  callerAccountPeerId: 'local-account',
  callerDeviceId: 'local-device',
  startedAt: _now,
  observedAt: _now,
);

CallSignal _controlSignal({
  String recipientDevicePeerId = 'remote-device',
  CallSignalType event = CallSignalType.invite,
  int senderSequence = 1,
  String messageId = '70000000-0000-4000-8000-000000000001',
}) => CallSignal.create(
  callId: _callId,
  messageId: messageId,
  event: event,
  senderAccountPeerId: 'local-account',
  senderDevicePeerId: 'local-device',
  recipientAccountPeerId: 'remote-account',
  recipientDevicePeerId: recipientDevicePeerId,
  senderSequence: senderSequence,
  iceGeneration: 0,
  createdAtMs: _nowMs,
  expiresAtMs: _nowMs + 45_000,
  payload: event == CallSignalType.terminate
      ? const <String, Object?>{'reason': 'local_hangup'}
      : const <String, Object?>{},
);

CallSignal _incomingInvite() => CallSignal.create(
  callId: _callId,
  messageId: '80000000-0000-4000-8000-000000000001',
  event: CallSignalType.invite,
  senderAccountPeerId: 'remote-account',
  senderDevicePeerId: 'remote-device',
  recipientAccountPeerId: 'local-account',
  recipientDevicePeerId: 'local-device',
  senderSequence: 4,
  iceGeneration: 0,
  createdAtMs: _nowMs,
  expiresAtMs: _nowMs + 45_000,
);

CallSignalingContextStore _outgoingContext({int nextSenderSequence = 1}) {
  final store = CallSignalingContextStore();
  store.storeOutgoing(
    callId: _callId,
    callHandle: _callHandle,
    localAccountPeerId: 'local-account',
    localDevicePeerId: 'local-device',
    remoteAccountPeerId: 'remote-account',
    remoteDevicePeerId: 'remote-device',
    nextSenderSequence: nextSenderSequence,
  );
  return store;
}

ResolvedCallEndpoint _endpoint({
  String accountPeerId = 'remote-account',
  String devicePeerId = 'remote-device',
  int expiresAtMs = _nowMs + 60_000,
}) => ResolvedCallEndpoint(
  accountPeerId: accountPeerId,
  devicePeerId: devicePeerId,
  signingPublicKey: 'secret-remote-signing-key',
  mlKemPublicKey: 'secret-remote-mlkem-key',
  deviceKeyEpoch: 2,
  preferenceEpoch: 3,
  platform: CallEndpointPlatform.android,
  expiresAtMs: expiresAtMs,
  routingHandle: '0123456789abcdef0123456789abcdef',
  wakeHandle: 'fedcba9876543210fedcba9876543210',
);

Future<String> _loadSigningKey() async => 'secret-local-signing-key';

CallSignal _decodeSignal(String plaintext) =>
    CallSignal.fromMap(Map<String, Object?>.from(jsonDecode(plaintext) as Map));

void _expectRedacted(String value) {
  for (final forbidden in const <String>[
    'secret-peer',
    'secret-handle',
    'secret-key',
    'secret-sdp',
    'secret-offer',
    'secret-answer',
    'secret-candidate',
    'local-account',
    'local-device',
    'remote-account',
    'remote-device',
    _callHandle,
  ]) {
    expect(value, isNot(contains(forbidden)), reason: forbidden);
  }
}

Future<void> _prepareCoordinator(CallCoordinator coordinator) async {
  await coordinator.dispatch(
    CallEvent(
      type: CallEventType.place,
      eventId: 'place',
      occurredAt: _now,
      callId: _callId,
      contactPeerId: 'remote-account',
      localAccountPeerId: 'local-account',
      localDeviceId: 'local-device',
    ),
  );
  await coordinator.dispatch(
    CallEvent(
      type: CallEventType.outgoingInviteReady,
      eventId: 'invite-ready',
      occurredAt: _now,
      callId: _callId,
      contactPeerId: 'remote-account',
    ),
  );
}

final class _EndpointAuthority {
  _EndpointAuthority(this.current);

  ResolvedCallEndpoint current;
  Object? error;
  final List<String> requestedAccounts = <String>[];

  int get calls => requestedAccounts.length;

  Future<ResolvedCallEndpoint> resolve(String accountPeerId) async {
    requestedAccounts.add(accountPeerId);
    final currentError = error;
    if (currentError != null) throw currentError;
    return current;
  }
}

final class _Ids {
  _Ids(this.values);

  final List<String> values;
  int _index = 0;

  CallId next() => CallId.parse(values[_index++]);
}

final class _ServiceHarness {
  _ServiceHarness({
    CallDirectSendResult directResult = const CallDirectSendResult(
      outcome: CallDirectTransportOutcome.acceptedBytes,
      transportAcknowledged: true,
      route: CallDirectRoute.direct,
    ),
    Future<void>? mailboxStoreGate,
  }) : crypto = _CaptureCrypto(),
       direct = _Direct(directResult),
       mailbox = _Mailbox(mailboxStoreGate),
       coordinator = _coordinator() {
    service = CallSignalingService(
      codec: SecureCallEnvelopeCodec(crypto: crypto, nowMs: () => _nowMs),
      directTransport: direct,
      mailboxClient: mailbox,
      coordinator: coordinator,
      networkEffectsAllowed: () => true,
    );
  }

  final _CaptureCrypto crypto;
  final _Direct direct;
  final _Mailbox mailbox;
  final CallCoordinator coordinator;
  late final CallSignalingService service;

  Future<void> dispose() => coordinator.dispose();
}

final class _CaptureCrypto implements CallEnvelopeCrypto {
  Future<void>? encryptGate;
  final List<String> plaintexts = <String>[];
  final List<String> recipientKeys = <String>[];

  @override
  Future<CallCiphertext> encrypt({
    required String recipientMlKemPublicKey,
    required String plaintext,
  }) async {
    await encryptGate;
    plaintexts.add(plaintext);
    recipientKeys.add(recipientMlKemPublicKey);
    return CallCiphertext(
      kem: base64Encode(utf8.encode('kem')),
      ciphertext: base64Encode(utf8.encode(plaintext)),
      nonce: base64Encode(utf8.encode('nonce')),
    );
  }

  @override
  Future<String> decrypt({
    required String ownMlKemSecretKey,
    required CallCiphertext ciphertext,
  }) async => utf8.decode(base64Decode(ciphertext.ciphertext));

  @override
  Future<String> sign({
    required String senderSigningPrivateKey,
    required String canonicalData,
  }) async => base64Encode(utf8.encode('signature'));

  @override
  Future<bool> verify({
    required String senderSigningPublicKey,
    required String canonicalData,
    required String signature,
  }) async => true;
}

final class _Direct implements CallDirectTransport {
  _Direct(this.result);

  final CallDirectSendResult result;
  final List<String> recipients = <String>[];
  int calls = 0;

  @override
  Future<CallDirectSendResult> send({
    required String recipientDevicePeerId,
    required String envelopeJson,
  }) async {
    calls++;
    recipients.add(recipientDevicePeerId);
    return result;
  }
}

final class _Mailbox implements CallMailboxClient {
  _Mailbox(this.storeGate);

  final Future<void>? storeGate;
  int stores = 0;
  bool storeSucceeds = true;
  final Set<int> failAtStores = {};
  final List<CallMailboxStoreRequest> requests = [];
  CallMailboxWakeStatus wake = CallMailboxWakeStatus.none;

  @override
  Future<CallMailboxStoreResult> store(CallMailboxStoreRequest request) async {
    stores++;
    requests.add(request);
    final fail = !storeSucceeds || failAtStores.contains(stores);
    await storeGate;
    if (fail) throw StateError('offline');
    return CallMailboxStoreResult(
      status: CallMailboxStoreStatus.stored,
      receiptAtMs: _nowMs,
      expiresAtMs: request.expiresAtMs,
      eventCount: 1,
      totalBytes: 100,
      pendingHandles: 1,
      wake: wake,
    );
  }

  @override
  Future<int> ack({
    required String callHandle,
    required List<String> messageIds,
  }) => throw UnimplementedError();

  @override
  Future<bool> cancel({
    required String recipientDevicePeerId,
    required String callHandle,
  }) => throw UnimplementedError();

  @override
  Future<CallMailboxRetrieveResult> retrieve({
    String? callHandle,
    int limit = 64,
  }) => throw UnimplementedError();
}

CallCoordinator _coordinator() => CallCoordinator(
  reducer: const CallReducer(),
  cleanupCoordinator: CallCleanupCoordinator(const <CallCleanupStep>[]),
  historyProjector: CallHistoryProjector(_History()),
  clock: () => _now,
  idSource: () => _callId,
);

final class _History implements CallHistoryRepository {
  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => null;

  @override
  Future<List<CallHistoryEntry>> listForContact(String peerId) async =>
      const <CallHistoryEntry>[];

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {}
}

final class _RetryAuthorityBridge implements Bridge {
  String? errorCode;
  int lookups = 0;

  @override
  Future<String> send(String message) async {
    expect(jsonDecode(message)['cmd'], 'call_endpoint_get_v1');
    lookups++;
    return jsonEncode(
      errorCode == null
          ? <String, Object?>{'ok': true, 'found': false}
          : <String, Object?>{'ok': false, 'errorCode': errorCode},
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NegotiationRetryHarness {
  _NegotiationRetryHarness(this.async) {
    service = CallSignalingService(
      codec: SecureCallEnvelopeCodec(crypto: crypto, nowMs: () => nowMs),
      nowMs: () => nowMs,
      directTransport: _Direct(
        const CallDirectSendResult(
          outcome: CallDirectTransportOutcome.failed,
          transportAcknowledged: false,
          route: CallDirectRoute.unknown,
        ),
      ),
      mailboxClient: mailbox,
      networkEffectsAllowed: () async {
        await networkGate;
        return networkAllowed;
      },
    );
    adapter = ProductionCallNegotiationSignalingAdapter(
      signalingService: service,
      contextStore: contexts,
      resolveCurrentEndpoint: (_) async {
        await endpointGate;
        await beforeEndpointLookup?.call();
        return endpoint;
      },
      loadSenderSigningPrivateKey: () async {
        await keyGate;
        if (!accountCurrent) throw StateError('account changed');
        return 'private-signer-key';
      },
      clock: () => DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true),
      messageIdSource: () =>
          CallId.parse('88888888-8888-4888-8888-88888888888${nextMessage++}'),
    );
  }
  final FakeAsync async;
  final contexts = _outgoingContext();
  final crypto = _CaptureCrypto();
  final mailbox = _Mailbox(null);
  late final CallSignalingService service;
  late final ProductionCallNegotiationSignalingAdapter adapter;
  ResolvedCallEndpoint endpoint = _endpoint();
  bool accountCurrent = true;
  bool networkAllowed = true;
  Future<void>? endpointGate;
  Future<void> Function()? beforeEndpointLookup;
  Future<void>? keyGate;
  Future<void>? networkGate;
  int nextMessage = 0;
  int get nowMs => _nowMs + async.elapsed.inMilliseconds;
}
