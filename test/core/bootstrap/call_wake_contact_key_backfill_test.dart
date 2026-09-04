import 'dart:async';
import 'dart:io';

import 'package:flutter_app/app/bootstrap/call_wake_contact_key_backfill.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/domain/issued_call_wake_handle_store.dart';
import 'package:flutter_app/features/call/domain/received_call_wake_handle_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<Map<String, dynamic>> events;
  late bool previousFlowEventLoggingEnabled;

  setUp(() {
    previousFlowEventLoggingEnabled = flowEventLoggingEnabled;
    flowEventLoggingEnabled = false;
    events = <Map<String, dynamic>>[];
    debugSetFlowEventSink(
      (payload) => events.add(Map<String, dynamic>.from(payload)),
    );
  });

  tearDown(() {
    debugSetFlowEventSink(null);
    flowEventLoggingEnabled = previousFlowEventLoggingEnabled;
  });

  Map<String, dynamic> resumeBackfillDetails() {
    final matching = events
        .where((event) => event['event'] == 'CALL_WAKE_RESUME_RECONCILE_RESULT')
        .toList(growable: false);
    expect(matching, hasLength(1));
    return Map<String, dynamic>.from(
      matching.single['details'] as Map<dynamic, dynamic>,
    );
  }

  test(
    'resume recovery drains call signaling before reconciling pending grants',
    () async {
      final order = <String>[];

      final completed = await resumeCallSignalingAndBackfillCallWake(
        resumeCallSignaling: () async {
          order.add('resume');
        },
        reconcileCallWakeEligibility: () async {
          order.add('reconcile');
        },
        hasPendingCallWakeDistribution: () async {
          order.add('pending');
          return true;
        },
        retryCallWakeDistribution:
            ({required trigger, required requireFresh}) async {
              order.add('retry:$trigger:fresh=$requireFresh');
              return 1;
            },
      );

      expect(completed, isTrue);
      expect(order, <String>[
        'resume',
        'reconcile',
        'pending',
        'retry:$callWakeResumeReconcileTrigger:fresh=true',
      ]);
      expect(resumeBackfillDetails(), <String, dynamic>{
        'resumeCompleted': true,
        'reconciliationCompleted': true,
        'pendingCheckCompleted': true,
        'pendingDistribution': true,
        'retryAttempted': true,
        'retryCompleted': true,
        'sentCount': 1,
        'completed': true,
      });
    },
  );

  test(
    'resume failure is contained without stranding pending grant recovery',
    () async {
      final order = <String>[];

      final completed = await resumeCallSignalingAndBackfillCallWake(
        resumeCallSignaling: () async {
          order.add('resume');
          throw StateError('mailbox unavailable');
        },
        reconcileCallWakeEligibility: () async {
          order.add('reconcile');
        },
        hasPendingCallWakeDistribution: () async {
          order.add('pending');
          return true;
        },
        retryCallWakeDistribution:
            ({required trigger, required requireFresh}) async {
              order.add('retry:$trigger');
              return 1;
            },
      );

      expect(completed, isFalse);
      expect(order, <String>[
        'resume',
        'reconcile',
        'pending',
        'retry:$callWakeResumeReconcileTrigger',
      ]);
      expect(resumeBackfillDetails(), <String, dynamic>{
        'resumeCompleted': false,
        'reconciliationCompleted': true,
        'pendingCheckCompleted': true,
        'pendingDistribution': true,
        'retryAttempted': true,
        'retryCompleted': true,
        'sentCount': 1,
        'completed': false,
      });
    },
  );

  test(
    'resume recovery reports when reconciliation finds no pending grant',
    () async {
      final completed = await resumeCallSignalingAndBackfillCallWake(
        resumeCallSignaling: () async {},
        reconcileCallWakeEligibility: () async {},
        hasPendingCallWakeDistribution: () async => false,
        retryCallWakeDistribution:
            ({required trigger, required requireFresh}) async {
              fail('retry must not run without a pending distribution');
            },
      );

      expect(completed, isTrue);
      expect(resumeBackfillDetails(), <String, dynamic>{
        'resumeCompleted': true,
        'reconciliationCompleted': true,
        'pendingCheckCompleted': true,
        'pendingDistribution': false,
        'retryAttempted': false,
        'retryCompleted': false,
        'sentCount': 0,
        'completed': true,
      });
    },
  );

  test('resume recovery reports a contained retry failure', () async {
    final completed = await resumeCallSignalingAndBackfillCallWake(
      resumeCallSignaling: () async {},
      reconcileCallWakeEligibility: () async {},
      hasPendingCallWakeDistribution: () async => true,
      retryCallWakeDistribution:
          ({required trigger, required requireFresh}) async {
            throw StateError('offline');
          },
    );

    expect(completed, isFalse);
    expect(resumeBackfillDetails(), <String, dynamic>{
      'resumeCompleted': true,
      'reconciliationCompleted': true,
      'pendingCheckCompleted': true,
      'pendingDistribution': true,
      'retryAttempted': true,
      'retryCompleted': false,
      'sentCount': 0,
      'completed': false,
    });
  });

  test(
    'reconciles call eligibility before retrying pending distribution',
    () async {
      final order = <String>[];

      final completed = await backfillCallWakeAfterContactKeyUpdate(
        reconcileCallWakeEligibility: () async {
          order.add('reconcile');
        },
        hasPendingCallWakeDistribution: () async {
          order.add('pending');
          return true;
        },
        retryCallWakeDistribution:
            ({required trigger, required requireFresh}) async {
              order.add('retry:$trigger:fresh=$requireFresh');
              return 1;
            },
      );

      expect(completed, isTrue);
      expect(order, <String>[
        'reconcile',
        'pending',
        'retry:$callWakeContactKeyUpdatedTrigger:fresh=false',
      ]);
    },
  );

  test('does not retry when reconciliation fails', () async {
    var retried = false;

    final completed = await backfillCallWakeAfterContactKeyUpdate(
      reconcileCallWakeEligibility: () async {
        throw StateError('unavailable');
      },
      hasPendingCallWakeDistribution: () async {
        throw StateError('must not inspect pending state');
      },
      retryCallWakeDistribution:
          ({required trigger, required requireFresh}) async {
            retried = true;
            return 0;
          },
    );

    expect(completed, isFalse);
    expect(retried, isFalse);
  });

  test(
    'contains retry failures for the fire-and-forget stream listener',
    () async {
      final completed = await backfillCallWakeAfterContactKeyUpdate(
        reconcileCallWakeEligibility: () async {},
        hasPendingCallWakeDistribution: () async => true,
        retryCallWakeDistribution:
            ({required trigger, required requireFresh}) async {
              throw StateError('offline');
            },
      );

      expect(completed, isFalse);
    },
  );

  test(
    'does not retry when reconciliation produced no pending grant',
    () async {
      var retried = false;

      final completed = await backfillCallWakeAfterContactKeyUpdate(
        reconcileCallWakeEligibility: () async {},
        hasPendingCallWakeDistribution: () async => false,
        retryCallWakeDistribution:
            ({required trigger, required requireFresh}) async {
              retried = true;
              return 0;
            },
      );

      expect(completed, isTrue);
      expect(retried, isFalse);
    },
  );

  test(
    'outgoing wake preflight reuses an exactly distributed current grant',
    () async {
      final events = <String>[];
      final store = _MemoryIssuedCallWakeHandleStore(
        events: events,
        record: _issuedRecord(
          distributionPending: false,
          distributionReceiptVersion:
              CallIssuedWakeHandleRecord.currentDistributionReceiptVersion,
        ),
      );

      final ready = await ensureOutgoingCallWakeAuthorityReady(
        contactAccountPeerId: _contactAccountPeerId,
        issuedCallWakeHandleStore: store,
        nowMs: () {
          events.add('now');
          return _validNowMs;
        },
        retryCallWakeDistribution:
            ({required trigger, required requireFresh}) async {
              fail('an exactly distributed grant must remain callable offline');
            },
      );

      expect(ready, isTrue);
      expect(events, <String>['read:$_contactAccountPeerId', 'now']);
    },
  );

  test('outgoing wake preflight defaults cover slow rendezvous startup', () {
    final retryWindow =
        outgoingCallWakeDistributionRetryDelay *
        (outgoingCallWakeDistributionMaxAttempts - 1);

    expect(retryWindow, greaterThanOrEqualTo(const Duration(seconds: 30)));
    expect(retryWindow, lessThanOrEqualTo(const Duration(seconds: 45)));
  });

  test(
    'outgoing wake preflight repairs an unproven legacy distributed grant',
    () async {
      final legacy = _issuedRecord(distributionPending: false);
      final store = _MemoryIssuedCallWakeHandleStore(record: legacy);

      final ready = await ensureOutgoingCallWakeAuthorityReady(
        contactAccountPeerId: _contactAccountPeerId,
        issuedCallWakeHandleStore: store,
        nowMs: () => _validNowMs,
        retryCallWakeDistribution:
            ({required trigger, required requireFresh}) async {
              expect(trigger, callWakeOutgoingPreflightTrigger);
              expect(requireFresh, isTrue);
              store.record = legacy.copyWith(
                distributionPending: false,
                distributionReceiptVersion: CallIssuedWakeHandleRecord
                    .currentDistributionReceiptVersion,
              );
              return 1;
            },
      );

      expect(ready, isTrue);
      expect(store.readCount, 2);
    },
  );

  test(
    'outgoing wake preflight freshly retries pending grant then verifies it',
    () async {
      final events = <String>[];
      final pending = _issuedRecord();
      final store = _MemoryIssuedCallWakeHandleStore(
        events: events,
        record: pending,
      );

      final ready = await ensureOutgoingCallWakeAuthorityReady(
        contactAccountPeerId: _contactAccountPeerId,
        issuedCallWakeHandleStore: store,
        nowMs: () {
          events.add('now');
          return _validNowMs;
        },
        retryCallWakeDistribution:
            ({required trigger, required requireFresh}) async {
              events.add('retry:$trigger:fresh=$requireFresh');
              store.record = pending.copyWith(
                distributionPending: false,
                distributionReceiptVersion: CallIssuedWakeHandleRecord
                    .currentDistributionReceiptVersion,
              );
              return 1;
            },
      );

      expect(ready, isTrue);
      expect(events, <String>[
        'read:$_contactAccountPeerId',
        'now',
        'now',
        'retry:$callWakeOutgoingPreflightTrigger:fresh=true',
        'read:$_contactAccountPeerId',
        'now',
      ]);
    },
  );

  test(
    'outgoing wake preflight eventually succeeds after transient failures',
    () async {
      final events = <String>[];
      final pending = _issuedRecord();
      final store = _MemoryIssuedCallWakeHandleStore(
        events: events,
        record: pending,
      );
      var retryCount = 0;

      final ready = await ensureOutgoingCallWakeAuthorityReady(
        contactAccountPeerId: _contactAccountPeerId,
        issuedCallWakeHandleStore: store,
        nowMs: () => _validNowMs,
        maxAttempts: 3,
        retryDelay: Duration.zero,
        delay: (duration) async {
          events.add('delay:${duration.inMilliseconds}');
        },
        retryCallWakeDistribution:
            ({required trigger, required requireFresh}) async {
              retryCount++;
              events.add('retry:$retryCount');
              if (retryCount == 1) {
                return 0;
              }
              if (retryCount == 2) {
                throw StateError('temporarily offline');
              }
              store.record = pending.copyWith(
                distributionPending: false,
                distributionReceiptVersion: CallIssuedWakeHandleRecord
                    .currentDistributionReceiptVersion,
              );
              return 1;
            },
      );

      expect(ready, isTrue);
      expect(retryCount, 3);
      expect(store.readCount, 6);
      expect(events.where((event) => event == 'delay:0'), hasLength(2));
    },
  );

  test(
    'outgoing wake preflight retries an acknowledgement until its receipt is durable',
    () async {
      final pending = _issuedRecord();
      final store = _MemoryIssuedCallWakeHandleStore(record: pending);
      var retryCount = 0;
      var delayCount = 0;

      final ready = await ensureOutgoingCallWakeAuthorityReady(
        contactAccountPeerId: _contactAccountPeerId,
        issuedCallWakeHandleStore: store,
        nowMs: () => _validNowMs,
        maxAttempts: 2,
        retryDelay: Duration.zero,
        delay: (_) async {
          delayCount++;
        },
        retryCallWakeDistribution:
            ({required trigger, required requireFresh}) async {
              retryCount++;
              if (retryCount == 2) {
                store.record = pending.copyWith(
                  distributionPending: false,
                  distributionReceiptVersion: CallIssuedWakeHandleRecord
                      .currentDistributionReceiptVersion,
                );
              }
              return 1;
            },
      );

      expect(ready, isTrue);
      expect(retryCount, 2);
      expect(delayCount, 1);
      expect(store.readCount, 4);
    },
  );

  test('outgoing wake preflight exhausts its bounded retry budget', () async {
    const maxAttempts = 3;
    final store = _MemoryIssuedCallWakeHandleStore(record: _issuedRecord());
    var retryCount = 0;
    var delayCount = 0;

    final ready = await ensureOutgoingCallWakeAuthorityReady(
      contactAccountPeerId: _contactAccountPeerId,
      issuedCallWakeHandleStore: store,
      nowMs: () => _validNowMs,
      maxAttempts: maxAttempts,
      retryDelay: Duration.zero,
      delay: (_) async {
        delayCount++;
      },
      retryCallWakeDistribution:
          ({required trigger, required requireFresh}) async {
            retryCount++;
            return 0;
          },
    );

    expect(ready, isFalse);
    expect(retryCount, maxAttempts);
    expect(delayCount, maxAttempts - 1);
    expect(store.readCount, maxAttempts * 2);
  });

  test(
    'outgoing wake preflight rejects a grant that remains pending',
    () async {
      final store = _MemoryIssuedCallWakeHandleStore(record: _issuedRecord());

      final ready = await ensureOutgoingCallWakeAuthorityReady(
        contactAccountPeerId: _contactAccountPeerId,
        issuedCallWakeHandleStore: store,
        nowMs: () => _validNowMs,
        maxAttempts: 3,
        retryDelay: Duration.zero,
        retryCallWakeDistribution:
            ({required trigger, required requireFresh}) async => 0,
      );

      expect(ready, isFalse);
      expect(store.readCount, 6);
    },
  );

  test(
    'outgoing wake preflight rejects false state without receipt witness',
    () async {
      final pending = _issuedRecord();
      final store = _MemoryIssuedCallWakeHandleStore(record: pending);

      final ready = await ensureOutgoingCallWakeAuthorityReady(
        contactAccountPeerId: _contactAccountPeerId,
        issuedCallWakeHandleStore: store,
        nowMs: () => _validNowMs,
        maxAttempts: 1,
        retryCallWakeDistribution:
            ({required trigger, required requireFresh}) async {
              store.record = pending.copyWith(distributionPending: false);
              return 1;
            },
      );

      expect(ready, isFalse);
      expect(store.readCount, 2);
    },
  );

  test('outgoing wake preflight rejects rotation during retry', () async {
    final store = _MemoryIssuedCallWakeHandleStore(record: _issuedRecord());

    final ready = await ensureOutgoingCallWakeAuthorityReady(
      contactAccountPeerId: _contactAccountPeerId,
      issuedCallWakeHandleStore: store,
      nowMs: () => _validNowMs,
      retryCallWakeDistribution:
          ({required trigger, required requireFresh}) async {
            store.record = _issuedRecord(
              generation: 2,
              distributionPending: false,
              distributionReceiptVersion:
                  CallIssuedWakeHandleRecord.currentDistributionReceiptVersion,
            );
            return 1;
          },
    );

    expect(ready, isFalse);
  });

  test('outgoing wake preflight rejects expiry during retry', () async {
    var nowMs = _validNowMs;
    final pending = _issuedRecord(expiresAtMs: _validNowMs + 1);
    final store = _MemoryIssuedCallWakeHandleStore(record: pending);

    final ready = await ensureOutgoingCallWakeAuthorityReady(
      contactAccountPeerId: _contactAccountPeerId,
      issuedCallWakeHandleStore: store,
      nowMs: () => nowMs,
      retryCallWakeDistribution:
          ({required trigger, required requireFresh}) async {
            store.record = pending.copyWith(
              distributionPending: false,
              distributionReceiptVersion:
                  CallIssuedWakeHandleRecord.currentDistributionReceiptVersion,
            );
            nowMs = pending.grant.expiresAtMs;
            return 1;
          },
    );

    expect(ready, isFalse);
  });

  test('outgoing wake preflight contains retry exceptions', () async {
    final store = _MemoryIssuedCallWakeHandleStore(record: _issuedRecord());
    var retryCount = 0;

    final ready = await ensureOutgoingCallWakeAuthorityReady(
      contactAccountPeerId: _contactAccountPeerId,
      issuedCallWakeHandleStore: store,
      nowMs: () => _validNowMs,
      maxAttempts: 3,
      retryDelay: Duration.zero,
      retryCallWakeDistribution:
          ({required trigger, required requireFresh}) async {
            retryCount++;
            throw StateError('offline');
          },
    );

    expect(ready, isFalse);
    expect(retryCount, 3);
    expect(store.readCount, 6);
  });

  test(
    'received wake recovery reuses a current grant without sending',
    () async {
      final store = _MemoryReceivedCallWakeHandleStore(
        grants: <String, CallWakeHandleGrant>{
          _contactAccountPeerId: _receivedGrant(),
        },
      );
      var recoveryCount = 0;
      final coordinator = ReceivedCallWakeHandleRecoveryCoordinator(
        receivedCallWakeHandleStore: store,
        nowMs: () => _validNowMs,
        requestRecovery: ({required contactAccountPeerId}) async {
          recoveryCount++;
        },
      );

      final ready = await coordinator.ensureCurrentGrantFor(
        _contactAccountPeerId,
      );

      expect(ready, isTrue);
      expect(recoveryCount, 0);
      expect(store.readCountFor(_contactAccountPeerId), 1);
    },
  );

  test(
    'received wake recovery requests missing expired and not-yet-valid grants',
    () async {
      final cases = <CallWakeHandleGrant?>[
        null,
        _receivedGrant(expiresAtMs: _validNowMs),
        _receivedGrant(
          issuedAtMs: _validNowMs + 1,
          expiresAtMs: _validNowMs + 10_000,
        ),
      ];

      for (final grant in cases) {
        final store = _MemoryReceivedCallWakeHandleStore(
          grants: grant == null
              ? null
              : <String, CallWakeHandleGrant>{_contactAccountPeerId: grant},
        );
        var recoveryCount = 0;
        final coordinator = ReceivedCallWakeHandleRecoveryCoordinator(
          receivedCallWakeHandleStore: store,
          nowMs: () => _validNowMs,
          requestRecovery: ({required contactAccountPeerId}) async {
            expect(contactAccountPeerId, _contactAccountPeerId);
            recoveryCount++;
          },
        );

        expect(
          await coordinator.ensureCurrentGrantFor(_contactAccountPeerId),
          isFalse,
          reason: 'grant: $grant',
        );
        expect(recoveryCount, 1, reason: 'grant: $grant');
      }
    },
  );

  test(
    'received wake recovery coalesces concurrent work per contact',
    () async {
      final store = _MemoryReceivedCallWakeHandleStore();
      final recoveryStarted = Completer<void>();
      final releaseRecovery = Completer<void>();
      var recoveryCount = 0;
      final coordinator = ReceivedCallWakeHandleRecoveryCoordinator(
        receivedCallWakeHandleStore: store,
        nowMs: () => _validNowMs,
        requestRecovery: ({required contactAccountPeerId}) async {
          recoveryCount++;
          recoveryStarted.complete();
          await releaseRecovery.future;
          store.grants[contactAccountPeerId] = _receivedGrant();
        },
      );

      final first = coordinator.ensureCurrentGrantFor(_contactAccountPeerId);
      await recoveryStarted.future;
      final second = coordinator.ensureCurrentGrantFor(_contactAccountPeerId);
      await Future<void>.delayed(Duration.zero);

      expect(recoveryCount, 1);
      releaseRecovery.complete();
      expect(await Future.wait<bool>(<Future<bool>>[first, second]), <bool>[
        true,
        true,
      ]);
    },
  );

  test('received wake recovery keeps different contacts independent', () async {
    final store = _MemoryReceivedCallWakeHandleStore();
    final releaseRecovery = Completer<void>();
    final requestedContacts = <String>[];
    final coordinator = ReceivedCallWakeHandleRecoveryCoordinator(
      receivedCallWakeHandleStore: store,
      nowMs: () => _validNowMs,
      requestRecovery: ({required contactAccountPeerId}) async {
        requestedContacts.add(contactAccountPeerId);
        await releaseRecovery.future;
      },
    );

    final first = coordinator.ensureCurrentGrantFor(_contactAccountPeerId);
    final second = coordinator.ensureCurrentGrantFor('contactAccount2');
    while (requestedContacts.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(
      requestedContacts,
      containsAll(<String>[_contactAccountPeerId, 'contactAccount2']),
    );
    releaseRecovery.complete();
    expect(await Future.wait<bool>(<Future<bool>>[first, second]), <bool>[
      false,
      false,
    ]);
  });

  test(
    'received wake recovery contains failure and a later call retries',
    () async {
      final store = _MemoryReceivedCallWakeHandleStore();
      var recoveryCount = 0;
      final coordinator = ReceivedCallWakeHandleRecoveryCoordinator(
        receivedCallWakeHandleStore: store,
        nowMs: () => _validNowMs,
        requestRecovery: ({required contactAccountPeerId}) async {
          recoveryCount++;
          if (recoveryCount == 1) {
            throw StateError('offline');
          }
          store.grants[contactAccountPeerId] = _receivedGrant();
        },
      );

      expect(
        await coordinator.ensureCurrentGrantFor(_contactAccountPeerId),
        isFalse,
      );
      expect(
        await coordinator.ensureCurrentGrantFor(_contactAccountPeerId),
        isTrue,
      );
      expect(recoveryCount, 2);
    },
  );

  test(
    'outgoing wake preflight rejects missing revoked expired or misbound grants',
    () async {
      final cases = <CallIssuedWakeHandleRecord?>[
        null,
        _issuedRecord(revokePending: true),
        _issuedRecord(expiresAtMs: _validNowMs),
        _issuedRecord(contactAccountPeerId: 'differentContactAccount'),
      ];

      for (final record in cases) {
        var retried = false;
        final ready = await ensureOutgoingCallWakeAuthorityReady(
          contactAccountPeerId: _contactAccountPeerId,
          issuedCallWakeHandleStore: _MemoryIssuedCallWakeHandleStore(
            record: record,
          ),
          nowMs: () => _validNowMs,
          retryCallWakeDistribution:
              ({required trigger, required requireFresh}) async {
                retried = true;
                return 1;
              },
        );

        expect(ready, isFalse, reason: 'record: $record');
        expect(retried, isFalse, reason: 'record: $record');
      }
    },
  );

  test('production installs the key-update backfill before listener start', () {
    final source = File(
      'lib/app/bootstrap/production_application_bootstrap.dart',
    ).readAsStringSync();
    final install = source.indexOf("'contact_key_update_forwarder_install'");
    final listenerStart = source.indexOf("'contact_request_listener_start'");

    expect(install, greaterThanOrEqualTo(0));
    expect(listenerStart, greaterThan(install));
    final wiring = source.substring(install, listenerStart);
    expect(wiring, contains('backfillCallWakeAfterContactKeyUpdate('));
    expect(
      wiring,
      contains('callSignalingComposition.onContactEligibilityChanged'),
    );
    expect(wiring, contains('hasPendingCallWakeDistribution:'));
    expect(wiring, contains('keyExchangeRetrier.retryNow'));
  });

  test('production refreshes callability after a received grant is stored', () {
    final source = File(
      'lib/app/bootstrap/production_application_bootstrap.dart',
    ).readAsStringSync();
    final listener = source.indexOf('ContactRequestListener(');
    final presentationGate = source.indexOf(
      'shouldSuppressPresentationForPeerId:',
      listener,
    );

    expect(listener, greaterThanOrEqualTo(0));
    expect(presentationGate, greaterThan(listener));
    final wiring = source.substring(listener, presentationGate);
    expect(wiring, contains('onCallWakeHandleStored:'));
    expect(
      wiring,
      contains('callSignalingComposition.refreshOutgoingCallAvailability'),
    );
  });

  test('production reciprocal recovery requires an exact wake receipt', () {
    final source = File(
      'lib/app/bootstrap/production_application_bootstrap.dart',
    ).readAsStringSync();
    final recovery = source.indexOf(
      'requestReciprocalCallWakeRecovery:',
    );
    final nextOwner = source.indexOf(
      'shouldSuppressPresentationForPeerId:',
      recovery,
    );

    expect(recovery, greaterThanOrEqualTo(0));
    expect(nextOwner, greaterThan(recovery));
    final wiring = source.substring(recovery, nextOwner);
    expect(wiring, contains('ContactRequestSendIntent.newRequest'));
    expect(wiring, contains('resolveCallWakeHandle:'));
    expect(wiring, contains('requireExactCallWakeReceipt: true'));
  });

  test('production outgoing call requires an exact direct wake receipt', () {
    final source = File(
      'lib/app/bootstrap/production_application_bootstrap.dart',
    ).readAsStringSync();
    final composition = source.indexOf(
      'createProductionCallSignalingComposition(',
    );
    final nextOwner = source.indexOf(
      'notifyCallWakeEligibilityChanged =',
      composition,
    );

    expect(composition, greaterThanOrEqualTo(0));
    expect(nextOwner, greaterThan(composition));
    final wiring = source.substring(composition, nextOwner);
    expect(wiring, contains('ensureOutgoingCallWakeAuthority:'));
    expect(wiring, contains('ensureOutgoingCallWakeAuthorityReady('));
    expect(wiring, contains('requireExactCallWakeReceipt: true'));
    expect(wiring, contains('issuedCallWakeHandleStore:'));
  });
}

const _contactAccountPeerId = 'contactAccount1';
const _recipientDevicePeerId = 'recipientDevice1';
const _validNowMs = 2_000_000;

CallWakeHandleGrant _receivedGrant({
  int issuedAtMs = _validNowMs - 10_000,
  int expiresAtMs = _validNowMs + 10_000,
}) => CallWakeHandleGrant(
  handle: 'f' * 32,
  recipientDevicePeerId: _recipientDevicePeerId,
  deviceKeyEpoch: 1,
  generation: 1,
  issuedAtMs: issuedAtMs,
  expiresAtMs: expiresAtMs,
);

CallIssuedWakeHandleRecord _issuedRecord({
  String contactAccountPeerId = _contactAccountPeerId,
  int generation = 1,
  int expiresAtMs = _validNowMs + 10_000,
  bool revokePending = false,
  bool distributionPending = true,
  int? distributionReceiptVersion,
}) => CallIssuedWakeHandleRecord(
  contactAccountPeerId: contactAccountPeerId,
  grant: CallWakeHandleGrant(
    handle: generation.toRadixString(16).padLeft(32, '0'),
    recipientDevicePeerId: _recipientDevicePeerId,
    deviceKeyEpoch: 1,
    generation: generation,
    issuedAtMs: _validNowMs - 10_000,
    expiresAtMs: expiresAtMs,
  ),
  authorizedSenderDevicePeerIds: const <String>{'senderDevice1'},
  revokePending: revokePending,
  distributionPending: distributionPending,
  distributionReceiptVersion: distributionReceiptVersion,
);

final class _MemoryIssuedCallWakeHandleStore
    implements IssuedCallWakeHandleStore {
  _MemoryIssuedCallWakeHandleStore({this.events, this.record});

  final List<String>? events;
  CallIssuedWakeHandleRecord? record;
  int readCount = 0;

  @override
  Future<void> clear() async => record = null;

  @override
  Future<List<CallIssuedWakeHandleRecord>> readAll() async => record == null
      ? const <CallIssuedWakeHandleRecord>[]
      : <CallIssuedWakeHandleRecord>[record!];

  @override
  Future<CallIssuedWakeHandleRecord?> readForContact(
    String contactAccountPeerId,
  ) async {
    readCount++;
    events?.add('read:$contactAccountPeerId');
    return record;
  }

  @override
  Future<void> removeForContact(String contactAccountPeerId) async {
    record = null;
  }

  @override
  Future<void> write(CallIssuedWakeHandleRecord record) async {
    this.record = record;
  }
}

final class _MemoryReceivedCallWakeHandleStore
    implements ReceivedCallWakeHandleStore {
  _MemoryReceivedCallWakeHandleStore({Map<String, CallWakeHandleGrant>? grants})
    : grants = grants ?? <String, CallWakeHandleGrant>{};

  final Map<String, CallWakeHandleGrant> grants;
  final Map<String, int> _readCounts = <String, int>{};

  int readCountFor(String issuerAccountPeerId) =>
      _readCounts[issuerAccountPeerId] ?? 0;

  @override
  Future<void> clear() async => grants.clear();

  @override
  Future<CallWakeHandleGrant?> readForIssuer(String issuerAccountPeerId) async {
    _readCounts.update(
      issuerAccountPeerId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return grants[issuerAccountPeerId];
  }

  @override
  Future<void> removeForIssuer(String issuerAccountPeerId) async {
    grants.remove(issuerAccountPeerId);
  }

  @override
  Future<bool> storeIfStrictlyNewer({
    required String issuerAccountPeerId,
    required CallWakeHandleGrant grant,
    required int nowMs,
  }) async {
    grants[issuerAccountPeerId] = grant;
    return true;
  }
}
