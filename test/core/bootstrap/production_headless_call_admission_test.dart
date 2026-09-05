import 'package:flutter_app/app/bootstrap/production_headless_call_admission.dart';
import 'package:flutter_app/features/call/application/incoming_call_pre_presentation_admission.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/infrastructure/call_mailbox_client.dart';
import 'package:flutter_app/features/call/infrastructure/headless_call_admission_entrypoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const invocation = HeadlessCallAdmissionInvocation(
    nonce: '11111111-1111-4111-8111-111111111111',
    callId: '22222222-2222-4222-8222-222222222222',
    wakeHandle: '33333333333343338333333333333333',
    expiresAtMs: 1_800_000_045_000,
  );

  test(
    'authenticated invite reports admitted only after proven teardown',
    () async {
      final session = _Session(HeadlessCallAdmissionDisposition.admitted);
      final backend = _Backend(session);
      final report = await ProductionHeadlessCallAdmissionRunner(
        backend: backend,
        nowMs: () => 1_800_000_000_000,
      ).run(invocation: invocation, isStopRequested: () => false);

      expect(session.evaluateCalls, 1);
      expect(session.closeCalls, 1);
      expect(report.disposition, HeadlessCallAdmissionDisposition.admitted);
      expect(report.requiredPersistenceComplete, isTrue);
      expect(report.databaseClosed, isTrue);
      expect(report.leaseReleased, isTrue);
    },
  );

  test(
    'empty handle and permanent rejection are durable no-ring outcomes',
    () async {
      for (final disposition in <HeadlessCallAdmissionDisposition>[
        HeadlessCallAdmissionDisposition.emptyOrAlreadyAcked,
        HeadlessCallAdmissionDisposition.permanentReject,
      ]) {
        final report = await ProductionHeadlessCallAdmissionRunner(
          backend: _Backend(_Session(disposition)),
          nowMs: () => 1_800_000_000_000,
        ).run(invocation: invocation, isStopRequested: () => false);
        expect(report.disposition, disposition);
        expect(report.requiredPersistenceComplete, isTrue);
        expect(report.databaseClosed, isTrue);
        expect(report.leaseReleased, isTrue);
      }
    },
  );

  test('defer stop expiry and teardown uncertainty never admit', () async {
    final deferred = await ProductionHeadlessCallAdmissionRunner(
      backend: _Backend(_Session(HeadlessCallAdmissionDisposition.deferred)),
      nowMs: () => 1_800_000_000_000,
    ).run(invocation: invocation, isStopRequested: () => false);
    expect(deferred.disposition, HeadlessCallAdmissionDisposition.deferred);
    expect(deferred.requiredPersistenceComplete, isFalse);

    final stoppedBackend = _Backend(
      _Session(HeadlessCallAdmissionDisposition.admitted),
    );
    final stopped = await ProductionHeadlessCallAdmissionRunner(
      backend: stoppedBackend,
      nowMs: () => 1_800_000_000_000,
    ).run(invocation: invocation, isStopRequested: () => true);
    expect(stopped.disposition, HeadlessCallAdmissionDisposition.deferred);
    expect(stoppedBackend.acquireCalls, 0);

    final expiredBackend = _Backend(
      _Session(HeadlessCallAdmissionDisposition.admitted),
    );
    final expired = await ProductionHeadlessCallAdmissionRunner(
      backend: expiredBackend,
      nowMs: () => invocation.expiresAtMs,
    ).run(invocation: invocation, isStopRequested: () => false);
    expect(expired.disposition, HeadlessCallAdmissionDisposition.deferred);
    expect(expiredBackend.acquireCalls, 0);

    final unsafeSession = _Session(
      HeadlessCallAdmissionDisposition.admitted,
      cleanup: const HeadlessCallAdmissionCleanup(
        databaseClosed: true,
        leaseReleased: false,
      ),
    );
    final unsafe = await ProductionHeadlessCallAdmissionRunner(
      backend: _Backend(unsafeSession),
      nowMs: () => 1_800_000_000_000,
    ).run(invocation: invocation, isStopRequested: () => false);
    expect(unsafe.disposition, HeadlessCallAdmissionDisposition.deferred);
    expect(unsafe.requiredPersistenceComplete, isFalse);
    expect(unsafe.databaseClosed, isTrue);
    expect(unsafe.leaseReleased, isFalse);
  });

  test('acquisition or evaluation failure uses emergency cleanup', () async {
    final backend = _Backend(
      _Session(
        HeadlessCallAdmissionDisposition.admitted,
        evaluateError: StateError('redacted'),
      ),
    );
    final report = await ProductionHeadlessCallAdmissionRunner(
      backend: backend,
      nowMs: () => 1_800_000_000_000,
    ).run(invocation: invocation, isStopRequested: () => false);

    expect(backend.emergencyCalls, 1);
    expect(report.disposition, HeadlessCallAdmissionDisposition.deferred);
    expect(report.requiredPersistenceComplete, isFalse);
  });

  test('expiry reached during authentication dominates admission', () async {
    var clockReads = 0;
    final session = _Session(HeadlessCallAdmissionDisposition.admitted);
    final report = await ProductionHeadlessCallAdmissionRunner(
      backend: _Backend(session),
      nowMs: () =>
          clockReads++ == 0 ? 1_800_000_000_000 : invocation.expiresAtMs,
    ).run(invocation: invocation, isStopRequested: () => false);

    expect(session.closeCalls, 1);
    expect(report.disposition, HeadlessCallAdmissionDisposition.deferred);
    expect(report.requiredPersistenceComplete, isFalse);
  });

  test(
    'mailbox session retrieves c not h and terminal dominates invite',
    () async {
      final mailbox = _Mailbox(<CallMailboxEvent>[
        _event(messageId: '44444444-4444-4444-8444-444444444444'),
        _event(messageId: '55555555-5555-4555-8555-555555555555'),
      ]);
      final rolledBack = <CallSignalType>[];
      var authenticationIndex = 0;
      var closeCalls = 0;
      final session = MailboxProductionHeadlessCallAdmissionSession(
        mailboxClient: mailbox,
        authenticateEvent: ({required invocation, required event}) async {
          final type = authenticationIndex++ == 0
              ? CallSignalType.invite
              : CallSignalType.terminate;
          return HeadlessAuthenticatedMailboxEvent(
            event: type,
            rollbackReplay: () => rolledBack.add(type),
          );
        },
        closeResources: () async {
          closeCalls++;
          return _Session.safeCleanup;
        },
      );

      expect(
        await session.evaluate(invocation),
        HeadlessCallAdmissionDisposition.terminal,
      );
      expect(mailbox.retrievedHandles, <String>[invocation.callId]);
      expect(mailbox.retrievedHandles, isNot(contains(invocation.wakeHandle)));
      expect(rolledBack, const <CallSignalType>[
        CallSignalType.terminate,
        CallSignalType.invite,
      ]);
      expect(await session.close(), _Session.safeCleanup);
      expect(await session.close(), _Session.safeCleanup);
      expect(closeCalls, 1);
    },
  );

  // A page may hold rows from several wakes: the caller's terminate is stored
  // behind an invite the callee never acknowledged (headless admission
  // presents without acking). The wake binds only the row it was issued for;
  // every other row of the call authenticates against its own expiry, and an
  // authenticated terminate ends the ringing call (device 2026-09-05 15:50Z:
  // the Pixel rang on for 34 s after the caller hung up).
  test(
    'a terminate wake ends a call whose invite row came with an earlier wake',
    () async {
      const inviteExpiry = 1_800_000_045_000;
      const terminateExpiry = 1_800_000_051_000;
      final terminateWake = HeadlessCallAdmissionInvocation(
        nonce: invocation.nonce,
        callId: invocation.callId,
        wakeHandle: invocation.wakeHandle,
        expiresAtMs: terminateExpiry,
      );
      final boundExpiries = <int>[];
      final session = MailboxProductionHeadlessCallAdmissionSession(
        mailboxClient: _Mailbox(<CallMailboxEvent>[
          _event(
            messageId: '44444444-4444-4444-8444-444444444444',
            expiresAtMs: inviteExpiry,
          ),
          _event(
            messageId: '55555555-5555-4555-8555-555555555555',
            expiresAtMs: terminateExpiry,
          ),
        ]),
        authenticateEvent: _bindingAuthenticator(boundExpiries),
        closeResources: () async => _Session.safeCleanup,
      );

      expect(
        await session.evaluate(terminateWake),
        HeadlessCallAdmissionDisposition.terminal,
      );
      expect(boundExpiries, <int>[inviteExpiry, terminateExpiry]);
    },
  );

  test(
    'a stale wake whose own row is gone never re-rings an older invite',
    () async {
      final staleWake = HeadlessCallAdmissionInvocation(
        nonce: invocation.nonce,
        callId: invocation.callId,
        wakeHandle: invocation.wakeHandle,
        expiresAtMs: 1_800_000_051_000,
      );
      final boundExpiries = <int>[];
      final session = MailboxProductionHeadlessCallAdmissionSession(
        mailboxClient: _Mailbox(<CallMailboxEvent>[
          _event(expiresAtMs: 1_800_000_045_000),
        ]),
        authenticateEvent: _bindingAuthenticator(boundExpiries),
        closeResources: () async => _Session.safeCleanup,
      );

      expect(
        await session.evaluate(staleWake),
        HeadlessCallAdmissionDisposition.emptyOrAlreadyAcked,
      );
      expect(boundExpiries, <int>[1_800_000_045_000]);
    },
  );

  test('a terminate stored after the invite wake still dominates it', () async {
    final boundExpiries = <int>[];
    final session = MailboxProductionHeadlessCallAdmissionSession(
      mailboxClient: _Mailbox(<CallMailboxEvent>[
        _event(
          messageId: '44444444-4444-4444-8444-444444444444',
          expiresAtMs: 1_800_000_045_000,
        ),
        _event(
          messageId: '55555555-5555-4555-8555-555555555555',
          expiresAtMs: 1_800_000_051_000,
        ),
      ]),
      authenticateEvent: _bindingAuthenticator(boundExpiries),
      closeResources: () async => _Session.safeCleanup,
    );

    expect(
      await session.evaluate(invocation),
      HeadlessCallAdmissionDisposition.terminal,
    );
    expect(boundExpiries, <int>[1_800_000_045_000, 1_800_000_051_000]);
  });

  test('a companion row that cannot be judged yet defers the page', () async {
    final session = MailboxProductionHeadlessCallAdmissionSession(
      mailboxClient: _Mailbox(<CallMailboxEvent>[
        _event(
          messageId: '44444444-4444-4444-8444-444444444444',
          expiresAtMs: 1_800_000_045_000,
        ),
        _event(
          messageId: '55555555-5555-4555-8555-555555555555',
          expiresAtMs: 1_800_000_051_000,
        ),
      ]),
      authenticateEvent: ({required invocation, required event}) async {
        if (event.expiresAtMs != 1_800_000_045_000) {
          throw const IncomingCallPrePresentationAdmissionException(
            IncomingCallPrePresentationAdmissionFailureCode.deferred,
          );
        }
        return HeadlessAuthenticatedMailboxEvent(
          event: CallSignalType.invite,
          rollbackReplay: () {},
        );
      },
      closeResources: () async => _Session.safeCleanup,
    );

    expect(
      await session.evaluate(invocation),
      HeadlessCallAdmissionDisposition.deferred,
      reason: 'the unjudged row may be the terminate; never ring past it',
    );
  });

  test('mailbox empty and incomplete or transient pages never ring', () async {
    final empty = MailboxProductionHeadlessCallAdmissionSession(
      mailboxClient: _Mailbox(const <CallMailboxEvent>[]),
      authenticateEvent: ({required invocation, required event}) =>
          throw StateError('must not authenticate'),
      closeResources: () async => _Session.safeCleanup,
    );
    expect(
      await empty.evaluate(invocation),
      HeadlessCallAdmissionDisposition.emptyOrAlreadyAcked,
    );

    final incomplete = MailboxProductionHeadlessCallAdmissionSession(
      mailboxClient: _Mailbox(<CallMailboxEvent>[_event()], hasMore: true),
      authenticateEvent: ({required invocation, required event}) =>
          throw StateError('must not authenticate incomplete custody'),
      closeResources: () async => _Session.safeCleanup,
    );
    expect(
      await incomplete.evaluate(invocation),
      HeadlessCallAdmissionDisposition.deferred,
    );

    final transient = MailboxProductionHeadlessCallAdmissionSession(
      mailboxClient: _Mailbox(<CallMailboxEvent>[_event()]),
      authenticateEvent: ({required invocation, required event}) async =>
          throw const IncomingCallPrePresentationAdmissionException(
            IncomingCallPrePresentationAdmissionFailureCode.deferred,
          ),
      closeResources: () async => _Session.safeCleanup,
    );
    expect(
      await transient.evaluate(invocation),
      HeadlessCallAdmissionDisposition.deferred,
    );
  });
}

/// Mirrors the production admission's wake binding: a row is authenticated
/// only against a wake whose expiry equals the row's. Records each binding.
AuthenticateHeadlessMailboxEvent _bindingAuthenticator(
  List<int> boundExpiries,
) => ({required invocation, required event}) async {
  boundExpiries.add(invocation.expiresAtMs);
  if (invocation.expiresAtMs != event.expiresAtMs) {
    throw const IncomingCallPrePresentationAdmissionException(
      IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
    );
  }
  return HeadlessAuthenticatedMailboxEvent(
    event: event.messageId == '44444444-4444-4444-8444-444444444444'
        ? CallSignalType.invite
        : CallSignalType.terminate,
    rollbackReplay: () {},
  );
};

CallMailboxEvent _event({
  String messageId = '44444444-4444-4444-8444-444444444444',
  int expiresAtMs = 1_800_000_045_000,
}) => CallMailboxEvent(
  callHandle: '22222222-2222-4222-8222-222222222222',
  messageId: messageId,
  authenticatedSenderDevicePeerId: 'opaque-sender',
  recipientDevicePeerId: 'opaque-recipient',
  envelopeJson: 'opaque-envelope',
  receiptAtMs: 1_800_000_000_001,
  expiresAtMs: expiresAtMs,
);

final class _Mailbox implements CallMailboxClient {
  _Mailbox(this.events, {this.hasMore = false});

  final List<CallMailboxEvent> events;
  final bool hasMore;
  final List<String?> retrievedHandles = <String?>[];

  @override
  Future<CallMailboxRetrieveResult> retrieve({
    String? callHandle,
    int limit = 64,
  }) async {
    retrievedHandles.add(callHandle);
    return CallMailboxRetrieveResult(
      events: events,
      receiptAtMs: 1_800_000_000_001,
      expiresAtMs: 1_800_000_045_000,
      hasMore: hasMore,
    );
  }

  @override
  Future<int> ack({
    required String callHandle,
    required List<String> messageIds,
  }) => throw StateError('headless admission must not ack');

  @override
  Future<bool> cancel({
    required String recipientDevicePeerId,
    required String callHandle,
  }) => throw StateError('headless admission must not cancel');

  @override
  Future<CallMailboxStoreResult> store(CallMailboxStoreRequest request) =>
      throw StateError('headless admission must not store');
}

final class _Backend implements ProductionHeadlessCallAdmissionBackend {
  _Backend(this.session);

  final ProductionHeadlessCallAdmissionSession? session;
  int acquireCalls = 0;
  int emergencyCalls = 0;

  @override
  Future<ProductionHeadlessCallAdmissionSession?> acquire(
    HeadlessCallAdmissionInvocation invocation,
  ) async {
    acquireCalls++;
    return session;
  }

  @override
  Future<HeadlessCallAdmissionCleanup> emergencyCleanup() async {
    emergencyCalls++;
    return const HeadlessCallAdmissionCleanup(
      databaseClosed: true,
      leaseReleased: true,
    );
  }
}

final class _Session implements ProductionHeadlessCallAdmissionSession {
  _Session(this.disposition, {this.cleanup = safeCleanup, this.evaluateError});

  static const safeCleanup = HeadlessCallAdmissionCleanup(
    databaseClosed: true,
    leaseReleased: true,
  );

  final HeadlessCallAdmissionDisposition disposition;
  final HeadlessCallAdmissionCleanup cleanup;
  final Object? evaluateError;
  int evaluateCalls = 0;
  int closeCalls = 0;

  @override
  Future<HeadlessCallAdmissionDisposition> evaluate(
    HeadlessCallAdmissionInvocation invocation,
  ) async {
    evaluateCalls++;
    final error = evaluateError;
    if (error != null) throw error;
    return disposition;
  }

  @override
  Future<HeadlessCallAdmissionCleanup> close() async {
    closeCalls++;
    return cleanup;
  }
}
