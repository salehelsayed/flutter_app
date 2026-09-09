import 'package:flutter_app/features/call/application/call_wake_authorization_coordinator.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/domain/issued_call_wake_handle_store.dart';
import 'package:flutter_app/features/call/infrastructure/call_authority_client.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const nowMs = 1750000000000;
  const localDevice = 'localDevice1';

  CallWakeEligibleContact contact({
    String account = 'contactAccount1',
    String displayName = 'Alice',
    Iterable<String> devices = const <String>['senderDevice1'],
  }) => CallWakeEligibleContact(
    contactAccountPeerId: account,
    displayName: displayName,
    authorizedSenderDevicePeerIds: devices,
  );

  CallWakeHandleGrant grant({
    String handle = '0123456789abcdef0123456789abcdef',
    String recipient = localDevice,
    int epoch = 1,
    int generation = 1,
    int issuedAt = nowMs,
    int expiresAt = nowMs + Duration.millisecondsPerDay,
  }) => CallWakeHandleGrant(
    handle: handle,
    recipientDevicePeerId: recipient,
    deviceKeyEpoch: epoch,
    generation: generation,
    issuedAtMs: issuedAt,
    expiresAtMs: expiresAt,
  );

  test('persists before native publication and relay registration', () async {
    final events = <String>[];
    final store = _MemoryIssuedStore(events: events);
    final effects = _Effects(events);
    final coordinator = _coordinator(
      store: store,
      effects: effects,
      nowMs: nowMs,
      handles: <String>['0123456789abcdef0123456789abcdef'],
    );

    expect(
      await coordinator.reconcile(
        eligibleContacts: <CallWakeEligibleContact>[
          contact(devices: const <String>['senderDevice1', 'senderDevice2']),
        ],
        localRecipientDevicePeerId: localDevice,
        localDeviceKeyEpoch: 1,
      ),
      isTrue,
    );

    expect(events, <String>[
      'store:write:active:senderDevice1,senderDevice2',
      'native:publish:Alice',
      'relay:set:senderDevice1',
      'relay:set:senderDevice2',
    ]);
    final record = await store.readForContact('contactAccount1');
    expect(record, isNotNull);
    expect(record!.grant.handle, '0123456789abcdef0123456789abcdef');
    expect(effects.setRecords, hasLength(2));
    expect(
      effects.setRecords.every(
        (candidate) =>
            candidate.wakeHandle == record.grant.handle &&
            candidate.expiresAtMs == record.grant.expiresAtMs,
      ),
      isTrue,
    );
  });

  test('native failure fails closed before any relay registration', () async {
    final diagnostics = <Map<String, dynamic>>[];
    debugSetFlowEventSink(diagnostics.add);
    addTearDown(() => debugSetFlowEventSink(null));
    final events = <String>[];
    final store = _MemoryIssuedStore(events: events);
    final effects = _Effects(events)..failNativePublish = true;
    final coordinator = _coordinator(
      store: store,
      effects: effects,
      nowMs: nowMs,
    );

    expect(
      await coordinator.reconcile(
        eligibleContacts: <CallWakeEligibleContact>[contact()],
        localRecipientDevicePeerId: localDevice,
        localDeviceKeyEpoch: 1,
      ),
      isFalse,
    );
    expect(events, <String>[
      'store:write:active:senderDevice1',
      'native:publish:Alice',
    ]);
    expect(effects.setRecords, isEmpty);
    expect(
      (await store.readForContact('contactAccount1'))?.revokePending,
      isFalse,
    );
    expect(
      diagnostics
          .where((event) => event['event'] == 'CALL_WAKE_RECONCILE_FAILURE')
          .map((event) => event['details'])
          .toList(growable: false),
      <Object?>[
        <String, Object?>{'stage': 'native_publish'},
      ],
    );
  });

  test('relay registration rejection reports identifier-free stage', () async {
    final diagnostics = <Map<String, dynamic>>[];
    debugSetFlowEventSink(diagnostics.add);
    addTearDown(() => debugSetFlowEventSink(null));
    final events = <String>[];
    final store = _MemoryIssuedStore(events: events);
    final effects = _Effects(events)..failRelaySets.add('senderDevice1');
    final coordinator = _coordinator(
      store: store,
      effects: effects,
      nowMs: nowMs,
    );

    expect(
      await coordinator.reconcile(
        eligibleContacts: <CallWakeEligibleContact>[contact()],
        localRecipientDevicePeerId: localDevice,
        localDeviceKeyEpoch: 1,
      ),
      isFalse,
    );
    expect(
      diagnostics
          .where((event) => event['event'] == 'CALL_WAKE_RECONCILE_FAILURE')
          .map((event) => event['details'])
          .toList(growable: false),
      <Object?>[
        <String, Object?>{'stage': 'relay_set_rejected'},
      ],
    );
  });

  test(
    'removed contact is tombstoned before revoke and retried after restart',
    () async {
      final events = <String>[];
      final store = _MemoryIssuedStore(events: events);
      await store.write(
        CallIssuedWakeHandleRecord(
          contactAccountPeerId: 'contactAccount1',
          grant: grant(),
          authorizedSenderDevicePeerIds: const <String>[
            'senderDevice1',
            'senderDevice2',
          ],
          distributionPending: false,
        ),
      );
      events.clear();

      final firstEffects = _Effects(events)
        ..failRelayRevokes.add('senderDevice2');
      final first = _coordinator(
        store: store,
        effects: firstEffects,
        nowMs: nowMs,
      );
      expect(
        await first.reconcile(
          eligibleContacts: const <CallWakeEligibleContact>[],
          localRecipientDevicePeerId: localDevice,
          localDeviceKeyEpoch: 1,
        ),
        isFalse,
      );
      expect(events, <String>[
        'store:write:tombstone:senderDevice1,senderDevice2',
        'relay:revoke:senderDevice1',
        'store:write:tombstone:senderDevice2',
        'relay:revoke:senderDevice2',
      ]);
      final tombstone = await store.readForContact('contactAccount1');
      expect(tombstone?.revokePending, isTrue);
      expect(tombstone?.authorizedSenderDevicePeerIds, <String>{
        'senderDevice2',
      });

      events.clear();
      final restarted = _coordinator(
        store: store,
        effects: _Effects(events),
        nowMs: nowMs,
      );
      expect(
        await restarted.reconcile(
          eligibleContacts: const <CallWakeEligibleContact>[],
          localRecipientDevicePeerId: localDevice,
          localDeviceKeyEpoch: 1,
        ),
        isTrue,
      );
      expect(events, <String>[
        'relay:revoke:senderDevice2',
        'store:write:tombstone:',
        'native:revoke',
        'store:remove:contactAccount1',
      ]);
      expect(await store.readForContact('contactAccount1'), isNull);
    },
  );

  test(
    'local device/key rotation revokes old grant before publishing new grant',
    () async {
      final events = <String>[];
      final store = _MemoryIssuedStore(events: events);
      final oldGrant = grant(epoch: 9, generation: 41);
      await store.write(
        CallIssuedWakeHandleRecord(
          contactAccountPeerId: 'contactAccount1',
          grant: oldGrant,
          authorizedSenderDevicePeerIds: const <String>['senderDevice1'],
          distributionPending: false,
          distributionReceiptVersion:
              CallIssuedWakeHandleRecord.currentDistributionReceiptVersion,
        ),
      );
      events.clear();
      final coordinator = _coordinator(
        store: store,
        effects: _Effects(events),
        nowMs: nowMs,
        handles: <String>['fedcba9876543210fedcba9876543210'],
      );

      expect(
        await coordinator.reconcile(
          eligibleContacts: <CallWakeEligibleContact>[contact()],
          localRecipientDevicePeerId: 'localDevice2',
          localDeviceKeyEpoch: 2,
        ),
        isTrue,
      );
      expect(events, <String>[
        'store:write:tombstone:senderDevice1',
        'relay:revoke:senderDevice1',
        'store:write:tombstone:',
        'native:revoke',
        'store:write:active:senderDevice1',
        'native:publish:Alice',
        'relay:set:senderDevice1',
      ]);
      final rotated = await store.readForContact('contactAccount1');
      expect(rotated!.grant.handle, isNot(oldGrant.handle));
      expect(rotated.grant.recipientDevicePeerId, 'localDevice2');
      expect(rotated.grant.deviceKeyEpoch, 2);
      expect(rotated.grant.generation, 42);
      expect(rotated.grant.isStrictlyNewerThan(oldGrant), isTrue);
      expect(rotated.distributionPending, isTrue);
      expect(rotated.distributionReceiptVersion, isNull);
      expect(rotated.hasCurrentDistributionReceipt, isFalse);
    },
  );

  test(
    'rotates a valid grant that cannot span preconnect plus postconnect',
    () async {
      final requiredRemainingMs =
          CallSignal.maximumPreconnectLifetimeMs +
          SecureCallEnvelopeCodec.maximumPostconnectLifetime.inMilliseconds;
      expect(
        CallWakeAuthorizationCoordinator.minimumRemainingGrantLifetime,
        Duration(milliseconds: requiredRemainingMs),
      );

      final events = <String>[];
      final store = _MemoryIssuedStore(events: events);
      final oldGrant = grant(
        generation: 41,
        expiresAt: nowMs + requiredRemainingMs - 1,
      );
      expect(oldGrant.isValidAt(nowMs), isTrue);
      await store.write(
        CallIssuedWakeHandleRecord(
          contactAccountPeerId: 'contactAccount1',
          grant: oldGrant,
          authorizedSenderDevicePeerIds: const <String>['senderDevice1'],
          distributionPending: false,
        ),
      );
      events.clear();
      final coordinator = _coordinator(
        store: store,
        effects: _Effects(events),
        nowMs: nowMs,
        handles: <String>['fedcba9876543210fedcba9876543210'],
      );

      expect(
        await coordinator.reconcile(
          eligibleContacts: <CallWakeEligibleContact>[contact()],
          localRecipientDevicePeerId: localDevice,
          localDeviceKeyEpoch: 1,
        ),
        isTrue,
      );

      final rotated = await store.readForContact('contactAccount1');
      expect(rotated, isNotNull);
      expect(rotated!.grant.handle, isNot(oldGrant.handle));
      expect(rotated.grant.generation, 42);
      expect(rotated.grant.expiresAtMs, nowMs + Duration.millisecondsPerDay);
      expect(rotated.distributionPending, isTrue);
      expect(events, <String>[
        'store:write:tombstone:senderDevice1',
        'relay:revoke:senderDevice1',
        'store:write:tombstone:',
        'native:revoke',
        'store:write:active:senderDevice1',
        'native:publish:Alice',
        'relay:set:senderDevice1',
      ]);
    },
  );

  test('keeps a grant with exactly the required remaining lifetime', () async {
    final events = <String>[];
    final store = _MemoryIssuedStore(events: events);
    final current = grant(
      expiresAt:
          nowMs +
          CallWakeAuthorizationCoordinator
              .minimumRemainingGrantLifetime
              .inMilliseconds,
    );
    await store.write(
      CallIssuedWakeHandleRecord(
        contactAccountPeerId: 'contactAccount1',
        grant: current,
        authorizedSenderDevicePeerIds: const <String>['senderDevice1'],
        distributionPending: false,
      ),
    );
    events.clear();
    final coordinator = _coordinator(
      store: store,
      effects: _Effects(events),
      nowMs: nowMs,
      handles: <String>['fedcba9876543210fedcba9876543210'],
    );

    expect(
      await coordinator.reconcile(
        eligibleContacts: <CallWakeEligibleContact>[contact()],
        localRecipientDevicePeerId: localDevice,
        localDeviceKeyEpoch: 1,
      ),
      isTrue,
    );

    final unchanged = await store.readForContact('contactAccount1');
    expect(unchanged?.grant, current);
    expect(unchanged?.distributionPending, isFalse);
    expect(events, <String>['native:publish:Alice', 'relay:set:senderDevice1']);
  });

  test('rejects a configured lifetime shorter than call setup headroom', () {
    final events = <String>[];
    expect(
      () => _coordinator(
        store: _MemoryIssuedStore(events: events),
        effects: _Effects(events),
        nowMs: nowMs,
        grantLifetime:
            CallWakeAuthorizationCoordinator.minimumRemainingGrantLifetime -
            const Duration(milliseconds: 1),
      ),
      throwsArgumentError,
    );
  });

  test(
    'grant resolution tombstones a still-valid near-expiry binding',
    () async {
      final events = <String>[];
      final store = _MemoryIssuedStore(events: events);
      final nearExpiry = grant(
        expiresAt:
            nowMs +
            CallWakeAuthorizationCoordinator
                .minimumRemainingGrantLifetime
                .inMilliseconds -
            1,
      );
      store.seed(
        CallIssuedWakeHandleRecord(
          contactAccountPeerId: 'contactAccount1',
          grant: nearExpiry,
          authorizedSenderDevicePeerIds: const <String>['senderDevice1'],
          distributionPending: false,
        ),
      );
      final coordinator = _coordinator(
        store: store,
        effects: _Effects(events),
        nowMs: nowMs,
      );

      expect(
        await coordinator.resolveOrIssueGrantForContact(
          contact: contact(),
          localRecipientDevicePeerId: localDevice,
          localDeviceKeyEpoch: 1,
        ),
        isNull,
      );
      expect(
        (await store.readForContact('contactAccount1'))?.revokePending,
        isTrue,
      );
      expect(events, <String>['store:write:tombstone:senderDevice1']);
    },
  );

  test(
    'device authority delta revokes removed before registering added',
    () async {
      final events = <String>[];
      final store = _MemoryIssuedStore(events: events);
      await store.write(
        CallIssuedWakeHandleRecord(
          contactAccountPeerId: 'contactAccount1',
          grant: grant(),
          authorizedSenderDevicePeerIds: const <String>[
            'senderDevice1',
            'senderDevice2',
          ],
          distributionPending: false,
        ),
      );
      events.clear();
      final coordinator = _coordinator(
        store: store,
        effects: _Effects(events),
        nowMs: nowMs,
      );

      expect(
        await coordinator.reconcile(
          eligibleContacts: <CallWakeEligibleContact>[
            contact(devices: const <String>['senderDevice2', 'senderDevice3']),
          ],
          localRecipientDevicePeerId: localDevice,
          localDeviceKeyEpoch: 1,
        ),
        isTrue,
      );
      expect(events, <String>[
        'relay:revoke:senderDevice1',
        'store:write:active:senderDevice2',
        'store:write:active:senderDevice2,senderDevice3',
        'native:publish:Alice',
        'relay:set:senderDevice2',
        'relay:set:senderDevice3',
      ]);
      expect(
        (await store.readForContact(
          'contactAccount1',
        ))?.authorizedSenderDevicePeerIds,
        <String>{'senderDevice2', 'senderDevice3'},
      );
    },
  );

  test(
    'partial device removal checkpoints progress and retries only remainder',
    () async {
      final events = <String>[];
      final store = _MemoryIssuedStore(events: events);
      await store.write(
        CallIssuedWakeHandleRecord(
          contactAccountPeerId: 'contactAccount1',
          grant: grant(),
          authorizedSenderDevicePeerIds: const <String>[
            'senderDevice1',
            'senderDevice2',
            'senderDevice4',
          ],
        ),
      );
      events.clear();
      final effects = _Effects(events)..failRelayRevokes.add('senderDevice2');
      final coordinator = _coordinator(
        store: store,
        effects: effects,
        nowMs: nowMs,
      );

      expect(
        await coordinator.reconcile(
          eligibleContacts: <CallWakeEligibleContact>[
            contact(devices: const <String>['senderDevice3']),
          ],
          localRecipientDevicePeerId: localDevice,
          localDeviceKeyEpoch: 1,
        ),
        isFalse,
      );
      expect(effects.setRecords, isEmpty);
      expect(events, <String>[
        'relay:revoke:senderDevice1',
        'store:write:active:senderDevice2,senderDevice4',
        'relay:revoke:senderDevice2',
        'relay:revoke:senderDevice4',
        'store:write:active:senderDevice2',
      ]);
      expect(
        (await store.readForContact(
          'contactAccount1',
        ))?.authorizedSenderDevicePeerIds,
        <String>{'senderDevice2'},
      );

      events.clear();
      final restarted = _coordinator(
        store: store,
        effects: _Effects(events),
        nowMs: nowMs,
      );
      expect(
        await restarted.reconcile(
          eligibleContacts: <CallWakeEligibleContact>[
            contact(devices: const <String>['senderDevice3']),
          ],
          localRecipientDevicePeerId: localDevice,
          localDeviceKeyEpoch: 1,
        ),
        isTrue,
      );
      expect(events, <String>[
        'relay:revoke:senderDevice2',
        'store:write:active:',
        'store:write:active:senderDevice3',
        'native:publish:Alice',
        'relay:set:senderDevice3',
      ]);
      expect(
        (await store.readForContact(
          'contactAccount1',
        ))?.authorizedSenderDevicePeerIds,
        <String>{'senderDevice3'},
      );
    },
  );

  test(
    'concurrent grant resolution issues and persists exactly once',
    () async {
      final events = <String>[];
      final store = _MemoryIssuedStore(events: events);
      var generated = 0;
      final effects = _Effects(events);
      final coordinator = CallWakeAuthorizationCoordinator(
        store: store,
        setWakeHandle: effects.setWakeHandle,
        revokeWakeHandle: effects.revokeWakeHandle,
        publishNativeContact: effects.publishNativeContact,
        revokeNativeContact: effects.revokeNativeContact,
        generateHandle: () {
          generated++;
          return '0123456789abcdef0123456789abcdef';
        },
        nowMs: () => nowMs,
        grantLifetime: const Duration(days: 1),
      );

      final results = await Future.wait<CallWakeHandleGrant?>(
        List<Future<CallWakeHandleGrant?>>.generate(
          8,
          (_) => coordinator.resolveOrIssueGrantForContact(
            contact: contact(),
            localRecipientDevicePeerId: localDevice,
            localDeviceKeyEpoch: 1,
          ),
        ),
      );
      expect(generated, 1);
      expect(results.toSet(), hasLength(1));
      expect(store.writeCount, 1);
    },
  );

  test(
    'late stale distribution acknowledgement cannot clear newer grant',
    () async {
      final events = <String>[];
      final store = _MemoryIssuedStore(events: events);
      final oldGrant = grant();
      final newGrant = grant(
        handle: 'fedcba9876543210fedcba9876543210',
        epoch: 2,
        generation: 1,
      );
      await store.write(
        CallIssuedWakeHandleRecord(
          contactAccountPeerId: 'contactAccount1',
          grant: newGrant,
          authorizedSenderDevicePeerIds: const <String>['senderDevice1'],
        ),
      );
      final coordinator = _coordinator(
        store: store,
        effects: _Effects(events),
        nowMs: nowMs,
      );

      expect(
        await coordinator.markDistributed(
          contactAccountPeerId: 'contactAccount1',
          grant: oldGrant,
        ),
        isFalse,
      );
      expect(
        (await store.readForContact('contactAccount1'))?.distributionPending,
        isTrue,
      );
      expect(
        await coordinator.markDistributed(
          contactAccountPeerId: 'contactAccount1',
          grant: newGrant,
        ),
        isTrue,
      );
      expect(
        (await store.readForContact('contactAccount1'))?.distributionPending,
        isFalse,
      );
      final proven = await store.readForContact('contactAccount1');
      expect(
        proven?.distributionReceiptVersion,
        CallIssuedWakeHandleRecord.currentDistributionReceiptVersion,
      );
      expect(proven?.hasCurrentDistributionReceipt, isTrue);
    },
  );

  test(
    'rearms an unproven legacy distributed grant exactly once across restart',
    () async {
      final events = <String>[];
      final store = _MemoryIssuedStore(events: events);
      await store.write(
        CallIssuedWakeHandleRecord(
          contactAccountPeerId: 'contactAccount1',
          grant: grant(),
          authorizedSenderDevicePeerIds: const <String>['senderDevice1'],
          distributionPending: false,
        ),
      );
      events.clear();
      final coordinator = _coordinator(
        store: store,
        effects: _Effects(events),
        nowMs: nowMs,
      );

      expect(await coordinator.rearmCurrentGrantDistribution(), isTrue);
      expect(
        (await store.readForContact('contactAccount1'))?.distributionPending,
        isTrue,
      );
      expect(
        (await store.readForContact(
          'contactAccount1',
        ))?.hasCurrentDistributionReceipt,
        isFalse,
      );

      final restarted = _coordinator(
        store: store,
        effects: _Effects(events),
        nowMs: nowMs,
      );
      expect(await restarted.rearmCurrentGrantDistribution(), isTrue);
      expect(events, <String>['store:write:active:senderDevice1']);
    },
  );

  test('restart preserves a receipt-proven distributed grant', () async {
    final events = <String>[];
    final store = _MemoryIssuedStore(events: events);
    store.seed(
      CallIssuedWakeHandleRecord(
        contactAccountPeerId: 'contactAccount1',
        grant: grant(),
        authorizedSenderDevicePeerIds: const <String>['senderDevice1'],
        distributionPending: false,
        distributionReceiptVersion:
            CallIssuedWakeHandleRecord.currentDistributionReceiptVersion,
      ),
    );

    for (var restart = 0; restart < 2; restart++) {
      final coordinator = _coordinator(
        store: store,
        effects: _Effects(events),
        nowMs: nowMs,
      );
      expect(await coordinator.rearmCurrentGrantDistribution(), isTrue);
    }

    final preserved = await store.readForContact('contactAccount1');
    expect(preserved?.distributionPending, isFalse);
    expect(preserved?.hasCurrentDistributionReceipt, isTrue);
    expect(events, isEmpty);
  });

  test(
    'default grant survives idle days with its exact distribution receipt',
    () async {
      final events = <String>[];
      final store = _MemoryIssuedStore(events: events);
      final effects = _Effects(events);
      var currentMs = nowMs;
      final coordinator = CallWakeAuthorizationCoordinator(
        store: store,
        setWakeHandle: effects.setWakeHandle,
        revokeWakeHandle: effects.revokeWakeHandle,
        publishNativeContact: effects.publishNativeContact,
        revokeNativeContact: effects.revokeNativeContact,
        generateHandle: () => '0123456789abcdef0123456789abcdef',
        nowMs: () => currentMs,
      );
      addTearDown(coordinator.close);
      final issued = (await coordinator.resolveOrIssueGrantForContact(
        contact: contact(),
        localRecipientDevicePeerId: localDevice,
        localDeviceKeyEpoch: 1,
      ))!;
      expect(
        await coordinator.markDistributed(
          contactAccountPeerId: 'contactAccount1',
          grant: issued,
        ),
        isTrue,
      );
      events.clear();
      currentMs += const Duration(days: 2).inMilliseconds;
      expect(
        await coordinator.resolveOrIssueGrantForContact(
          contact: contact(),
          localRecipientDevicePeerId: localDevice,
          localDeviceKeyEpoch: 1,
        ),
        issued,
      );
      final retained = await store.readForContact('contactAccount1');
      expect(retained?.hasCurrentDistributionReceipt, isTrue);
      expect(retained?.distributionPending, isFalse);
      expect(events, isEmpty);
      currentMs = nowMs + const Duration(days: 30).inMilliseconds;
      expect(issued.isValidAt(currentMs - 1), isTrue);
      expect(issued.isValidAt(currentMs), isFalse);
      expect(
        await coordinator.resolveOrIssueGrantForContact(
          contact: contact(),
          localRecipientDevicePeerId: localDevice,
          localDeviceKeyEpoch: 1,
        ),
        isNull,
      );
    },
  );

  test(
    'longer default preserves a usable legacy signed grant and receipt',
    () async {
      final events = <String>[];
      final store = _MemoryIssuedStore(events: events);
      final effects = _Effects(events);
      final legacy = grant();
      store.seed(
        CallIssuedWakeHandleRecord(
          contactAccountPeerId: 'contactAccount1',
          grant: legacy,
          authorizedSenderDevicePeerIds: const <String>['senderDevice1'],
          distributionPending: false,
          distributionReceiptVersion:
              CallIssuedWakeHandleRecord.currentDistributionReceiptVersion,
        ),
      );
      final coordinator = CallWakeAuthorizationCoordinator(
        store: store,
        setWakeHandle: effects.setWakeHandle,
        revokeWakeHandle: effects.revokeWakeHandle,
        publishNativeContact: effects.publishNativeContact,
        revokeNativeContact: effects.revokeNativeContact,
        generateHandle: () => 'fedcba9876543210fedcba9876543210',
        nowMs: () => nowMs + const Duration(hours: 23).inMilliseconds,
      );
      addTearDown(coordinator.close);
      expect(await coordinator.rearmCurrentGrantDistribution(), isTrue);
      expect(
        await coordinator.reconcile(
          eligibleContacts: <CallWakeEligibleContact>[contact()],
          localRecipientDevicePeerId: localDevice,
          localDeviceKeyEpoch: 1,
        ),
        isTrue,
      );
      final retained = await store.readForContact('contactAccount1');
      expect(retained?.grant, legacy);
      expect(retained?.hasCurrentDistributionReceipt, isTrue);
      expect(retained?.distributionPending, isFalse);
      expect(events, <String>[
        'native:publish:Alice',
        'relay:set:senderDevice1',
      ]);
      expect(effects.setRecords.single.expiresAtMs, legacy.expiresAtMs);
    },
  );

  test('closed coordinator does not report rearm completion', () async {
    final coordinator = _coordinator(
      store: _MemoryIssuedStore(events: <String>[]),
      effects: _Effects(<String>[]),
      nowMs: nowMs,
    );

    await coordinator.close();

    expect(await coordinator.rearmCurrentGrantDistribution(), isFalse);
  });

  test('failed rearm persistence remains retryable', () async {
    final events = <String>[];
    final store = _MemoryIssuedStore(events: events);
    await store.write(
      CallIssuedWakeHandleRecord(
        contactAccountPeerId: 'contactAccount1',
        grant: grant(),
        authorizedSenderDevicePeerIds: const <String>['senderDevice1'],
        distributionPending: false,
      ),
    );
    events.clear();
    final coordinator = _coordinator(
      store: store,
      effects: _Effects(events),
      nowMs: nowMs,
    );
    store.failNextWrite = true;

    expect(await coordinator.rearmCurrentGrantDistribution(), isFalse);
    expect(
      (await store.readForContact('contactAccount1'))?.distributionPending,
      isFalse,
    );
    expect(await coordinator.rearmCurrentGrantDistribution(), isTrue);
    expect(
      (await store.readForContact('contactAccount1'))?.distributionPending,
      isTrue,
    );
  });

  test('eligible contact cap fails without persistence or effects', () async {
    final events = <String>[];
    final store = _MemoryIssuedStore(events: events);
    final coordinator = _coordinator(
      store: store,
      effects: _Effects(events),
      nowMs: nowMs,
    );
    final contacts = List<CallWakeEligibleContact>.generate(
      CallWakeAuthorizationCoordinator.maxEligibleContacts + 1,
      (index) => contact(account: 'contactAccount${index + 1}'),
    );

    expect(
      await coordinator.reconcile(
        eligibleContacts: contacts,
        localRecipientDevicePeerId: localDevice,
        localDeviceKeyEpoch: 1,
      ),
      isFalse,
    );
    expect(events, isEmpty);
    expect(await store.readAll(), isEmpty);
  });

  test('grant resolution refuses a 513th durable contact', () async {
    final events = <String>[];
    final store = _MemoryIssuedStore(events: events);
    for (
      var index = 0;
      index < CallWakeAuthorizationCoordinator.maxEligibleContacts;
      index++
    ) {
      final ordinal = index + 1;
      store.seed(
        CallIssuedWakeHandleRecord(
          contactAccountPeerId: 'existingContact$ordinal',
          grant: grant(handle: ordinal.toRadixString(16).padLeft(32, '0')),
          authorizedSenderDevicePeerIds: const <String>[],
        ),
      );
    }
    final coordinator = _coordinator(
      store: store,
      effects: _Effects(events),
      nowMs: nowMs,
    );

    expect(
      await coordinator.resolveOrIssueGrantForContact(
        contact: contact(account: 'contactAccount513'),
        localRecipientDevicePeerId: localDevice,
        localDeviceKeyEpoch: 1,
      ),
      isNull,
    );
    expect(events, isEmpty);
    expect(await store.readAll(), hasLength(512));
  });

  test('UUIDv4 generator is canonicalized to the grant 32-hex form', () async {
    final events = <String>[];
    final store = _MemoryIssuedStore(events: events);
    final coordinator = _coordinator(
      store: store,
      effects: _Effects(events),
      nowMs: nowMs,
      handles: <String>['12345678-1234-4abc-8def-1234567890ab'],
    );

    final issued = await coordinator.resolveOrIssueGrantForContact(
      contact: contact(),
      localRecipientDevicePeerId: localDevice,
      localDeviceKeyEpoch: 1,
    );
    expect(issued?.handle, '1234567812344abc8def1234567890ab');
  });

  test(
    'close waits for the lane without revoking valid durable grants',
    () async {
      final events = <String>[];
      final store = _MemoryIssuedStore(events: events);
      await store.write(
        CallIssuedWakeHandleRecord(
          contactAccountPeerId: 'contactAccount1',
          grant: grant(),
          authorizedSenderDevicePeerIds: const <String>['senderDevice1'],
        ),
      );
      events.clear();
      final effects = _Effects(events);
      final coordinator = _coordinator(
        store: store,
        effects: effects,
        nowMs: nowMs,
      );

      await coordinator.close();
      expect(events, isEmpty);
      expect(await store.readForContact('contactAccount1'), isNotNull);
      expect(
        await coordinator.reconcile(
          eligibleContacts: <CallWakeEligibleContact>[contact()],
          localRecipientDevicePeerId: localDevice,
          localDeviceKeyEpoch: 1,
        ),
        isFalse,
      );
    },
  );
}

CallWakeAuthorizationCoordinator _coordinator({
  required _MemoryIssuedStore store,
  required _Effects effects,
  required int nowMs,
  List<String>? handles,
  Duration grantLifetime = const Duration(days: 1),
}) {
  final generated = List<String>.of(
    handles ?? const <String>['0123456789abcdef0123456789abcdef'],
  );
  var fallback = 1;
  return CallWakeAuthorizationCoordinator(
    store: store,
    setWakeHandle: effects.setWakeHandle,
    revokeWakeHandle: effects.revokeWakeHandle,
    publishNativeContact: effects.publishNativeContact,
    revokeNativeContact: effects.revokeNativeContact,
    generateHandle: () {
      if (generated.isNotEmpty) return generated.removeAt(0);
      final value = fallback++;
      return value.toRadixString(16).padLeft(32, '0');
    },
    nowMs: () => nowMs,
    grantLifetime: grantLifetime,
  );
}

final class _MemoryIssuedStore implements IssuedCallWakeHandleStore {
  _MemoryIssuedStore({required this.events});

  final List<String> events;
  final Map<String, CallIssuedWakeHandleRecord> _records =
      <String, CallIssuedWakeHandleRecord>{};
  int writeCount = 0;
  bool failNextWrite = false;

  void seed(CallIssuedWakeHandleRecord record) {
    _records[record.contactAccountPeerId] = record;
  }

  @override
  Future<void> clear() async => _records.clear();

  @override
  Future<List<CallIssuedWakeHandleRecord>> readAll() async =>
      _records.values.toList(growable: false);

  @override
  Future<CallIssuedWakeHandleRecord?> readForContact(
    String contactAccountPeerId,
  ) async => _records[contactAccountPeerId];

  @override
  Future<void> removeForContact(String contactAccountPeerId) async {
    events.add('store:remove:$contactAccountPeerId');
    _records.remove(contactAccountPeerId);
  }

  @override
  Future<void> write(CallIssuedWakeHandleRecord record) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('write failed');
    }
    writeCount++;
    final devices = record.authorizedSenderDevicePeerIds.toList()..sort();
    events.add(
      'store:write:${record.revokePending ? 'tombstone' : 'active'}:'
      '${devices.join(',')}',
    );
    _records[record.contactAccountPeerId] = record;
  }
}

final class _Effects {
  _Effects(this.events);

  final List<String> events;
  final List<CallWakeHandleRecord> setRecords = <CallWakeHandleRecord>[];
  final Set<String> failRelaySets = <String>{};
  final Set<String> failRelayRevokes = <String>{};
  bool failNativePublish = false;
  bool failNativeRevoke = false;

  Future<void> publishNativeContact({
    required String wakeHandle,
    required String displayName,
  }) async {
    events.add('native:publish:$displayName');
    if (failNativePublish) throw StateError('native publish failed');
  }

  Future<void> revokeNativeContact(String wakeHandle) async {
    events.add('native:revoke');
    if (failNativeRevoke) throw StateError('native revoke failed');
  }

  Future<bool> setWakeHandle(CallWakeHandleRecord record) async {
    events.add('relay:set:${record.authorizedSenderPeerId}');
    setRecords.add(record);
    return !failRelaySets.contains(record.authorizedSenderPeerId);
  }

  Future<bool> revokeWakeHandle({
    required String authorizedSenderPeerId,
  }) async {
    events.add('relay:revoke:$authorizedSenderPeerId');
    return !failRelayRevokes.contains(authorizedSenderPeerId);
  }
}
