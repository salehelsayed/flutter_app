import 'package:flutter_app/features/call/application/call_negotiation_material_store.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_test/flutter_test.dart';

final _callA = CallId.parse('11111111-1111-4111-8111-111111111111');
final _callB = CallId.parse('22222222-2222-4222-8222-222222222222');

CallNegotiationMaterial _material({
  CallId? callId,
  String eventId = 'offer-event',
  CallNegotiationMaterialType type = CallNegotiationMaterialType.offer,
  int iceGeneration = 0,
  Map<String, Object?> payload = const <String, Object?>{
    'description': 'secret-sdp',
    'fingerprint': 'secret-fingerprint',
  },
}) => CallNegotiationMaterial(
  callId: callId ?? _callA,
  eventId: eventId,
  type: type,
  iceGeneration: iceGeneration,
  payload: payload,
);

void main() {
  group('VC2-03 negotiation material store', () {
    test('retains authenticated payload and generation until one take', () {
      final store = CallNegotiationMaterialStore();
      final material = _material();

      expect(
        store.store(material),
        CallNegotiationMaterialStoreDecision.stored,
      );
      final taken = store.take(_callA, material.eventId);

      expect(taken?.type, CallNegotiationMaterialType.offer);
      expect(taken?.iceGeneration, 0);
      expect(taken?.payload, <String, Object?>{
        'description': 'secret-sdp',
        'fingerprint': 'secret-fingerprint',
      });
      expect(store.take(_callA, material.eventId), isNull);
      expect(store.entryCountFor(_callA), 0);
    });

    test('rejects per-call and call-count overflow without eviction', () {
      final store = CallNegotiationMaterialStore(
        maxCalls: 1,
        maxEntriesPerCall: 2,
      );
      expect(
        store.store(_material(eventId: 'offer-1')),
        CallNegotiationMaterialStoreDecision.stored,
      );
      expect(
        store.store(
          _material(
            eventId: 'ice-1',
            type: CallNegotiationMaterialType.ice,
            payload: const <String, Object?>{'candidate': 'candidate-1'},
          ),
        ),
        CallNegotiationMaterialStoreDecision.stored,
      );

      expect(
        store.store(
          _material(
            eventId: 'ice-overflow',
            type: CallNegotiationMaterialType.ice,
            payload: const <String, Object?>{'candidate': 'candidate-2'},
          ),
        ),
        CallNegotiationMaterialStoreDecision.capacityExceeded,
      );
      expect(
        store.store(_material(callId: _callB, eventId: 'other-call')),
        CallNegotiationMaterialStoreDecision.capacityExceeded,
      );
      expect(store.entryCountFor(_callA), 2);
      expect(store.entryCountFor(_callB), 0);
    });

    test('rejects stale generations after committed material is consumed', () {
      final store = CallNegotiationMaterialStore();
      final restart = _material(
        eventId: 'restart-2',
        type: CallNegotiationMaterialType.iceRestart,
        iceGeneration: 2,
        payload: const <String, Object?>{},
      );
      expect(store.store(restart), CallNegotiationMaterialStoreDecision.stored);
      expect(store.take(_callA, restart.eventId), same(restart));

      expect(
        store.store(
          _material(
            eventId: 'stale-ice',
            type: CallNegotiationMaterialType.ice,
            iceGeneration: 1,
            payload: const <String, Object?>{'candidate': 'stale'},
          ),
        ),
        CallNegotiationMaterialStoreDecision.staleGeneration,
      );
      expect(store.entryCountFor(_callA), 0);
    });

    test(
      'rejected staged generation rolls back without poisoning the call',
      () {
        final store = CallNegotiationMaterialStore();
        final rejected = _material(
          eventId: 'rejected-generation',
          iceGeneration: 5,
        );
        expect(
          store.store(rejected),
          CallNegotiationMaterialStoreDecision.stored,
        );
        expect(store.purgeEvent(_callA, rejected.eventId), isTrue);

        expect(
          store.store(_material(eventId: 'accepted-generation')),
          CallNegotiationMaterialStoreDecision.stored,
        );
      },
    );

    test('purges terminal calls and keeps diagnostics payload-free', () {
      final store = CallNegotiationMaterialStore();
      final material = _material();
      store.store(material);

      expect(material.toString(), isNot(contains('secret-sdp')));
      expect(material.toString(), isNot(contains('secret-fingerprint')));
      expect(material.toDiagnosticMap().keys, isNot(contains('payload')));

      store.purgeCall(_callA);
      expect(store.entryCountFor(_callA), 0);
      expect(store.callCount, 0);
    });
  });
}
