import 'package:flutter_app/app/bootstrap/production_headless_call_admission.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/application/incoming_call_pre_presentation_admission.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
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

  // Device 2026-09-05 17:15Z: the iPhone's third call to the locked Pixel was
  // refused by the relay with CALL_RECIPIENT_CAPACITY ("Couldn't start voice
  // call"). The relay keeps a call handle in the recipient's pending index
  // (two slots) until every row is acknowledged or expires 40 s later. Both
  // earlier calls had been retrieved headlessly, presented and then ended
  // natively by the caller's terminate, but never acknowledged, so both slots
  // were still taken. An ended call has no foreground owner left to adopt it.
  test(
    'a terminal page acknowledges its authenticated rows before close',
    () async {
      final order = <String>[];
      final mailbox = _Mailbox(<CallMailboxEvent>[
        _event(
          messageId: '44444444-4444-4444-8444-444444444444',
          expiresAtMs: 1_800_000_045_000,
        ),
        _event(
          messageId: '55555555-5555-4555-8555-555555555555',
          expiresAtMs: 1_800_000_051_000,
        ),
      ], onAck: () => order.add('ack'));
      final session = MailboxProductionHeadlessCallAdmissionSession(
        mailboxClient: mailbox,
        authenticateEvent: _bindingAuthenticator(<int>[]),
        closeResources: () async {
          order.add('close');
          return _Session.safeCleanup;
        },
      );

      expect(
        await session.evaluate(invocation),
        HeadlessCallAdmissionDisposition.terminal,
      );
      expect(await session.close(), _Session.safeCleanup);
      expect(mailbox.ackedHandles, <String>[invocation.callId]);
      expect(mailbox.ackedMessageIds, <List<String>>[
        <String>[
          '44444444-4444-4444-8444-444444444444',
          '55555555-5555-4555-8555-555555555555',
        ],
      ]);
      expect(order, <String>['ack', 'close']);
    },
  );

  test('a terminal page acknowledges only the rows it authenticated', () async {
    final mailbox = _Mailbox(<CallMailboxEvent>[
      _event(
        messageId: '44444444-4444-4444-8444-444444444444',
        expiresAtMs: 1_800_000_045_000,
      ),
      _event(
        messageId: '55555555-5555-4555-8555-555555555555',
        expiresAtMs: 1_800_000_051_000,
      ),
      _event(
        messageId: '66666666-6666-4666-8666-666666666666',
        expiresAtMs: 1_800_000_053_000,
      ),
    ]);
    final session = MailboxProductionHeadlessCallAdmissionSession(
      mailboxClient: mailbox,
      authenticateEvent: ({required invocation, required event}) async {
        if (event.messageId == '66666666-6666-4666-8666-666666666666') {
          throw const IncomingCallPrePresentationAdmissionException(
            IncomingCallPrePresentationAdmissionFailureCode.deferred,
          );
        }
        return HeadlessAuthenticatedMailboxEvent(
          event: event.messageId == '44444444-4444-4444-8444-444444444444'
              ? CallSignalType.invite
              : CallSignalType.terminate,
          rollbackReplay: () {},
        );
      },
      closeResources: () async => _Session.safeCleanup,
    );

    expect(
      await session.evaluate(invocation),
      HeadlessCallAdmissionDisposition.terminal,
    );
    expect(mailbox.ackedMessageIds, <List<String>>[
      <String>[
        '44444444-4444-4444-8444-444444444444',
        '55555555-5555-4555-8555-555555555555',
      ],
    ]);
  });

  test(
    'an acknowledgement failure never changes the terminal verdict',
    () async {
      final mailbox = _Mailbox(<CallMailboxEvent>[
        _event(
          messageId: '44444444-4444-4444-8444-444444444444',
          expiresAtMs: 1_800_000_045_000,
        ),
        _event(
          messageId: '55555555-5555-4555-8555-555555555555',
          expiresAtMs: 1_800_000_051_000,
        ),
      ])..ackFailure = StateError('relay unreachable');
      var closeCalls = 0;
      final session = MailboxProductionHeadlessCallAdmissionSession(
        mailboxClient: mailbox,
        authenticateEvent: _bindingAuthenticator(<int>[]),
        closeResources: () async {
          closeCalls++;
          return _Session.safeCleanup;
        },
      );

      expect(
        await session.evaluate(invocation),
        HeadlessCallAdmissionDisposition.terminal,
      );
      expect(await session.close(), _Session.safeCleanup);
      expect(closeCalls, 1);
    },
  );

  test(
    'every non-terminal verdict leaves the rows for foreground adoption',
    () async {
      final admittedMailbox = _Mailbox(<CallMailboxEvent>[_event()]);
      final admitted = MailboxProductionHeadlessCallAdmissionSession(
        mailboxClient: admittedMailbox,
        authenticateEvent: _bindingAuthenticator(<int>[]),
        closeResources: () async => _Session.safeCleanup,
      );
      expect(
        await admitted.evaluate(invocation),
        HeadlessCallAdmissionDisposition.admitted,
      );

      final staleMailbox = _Mailbox(<CallMailboxEvent>[
        _event(expiresAtMs: 1_800_000_045_000),
      ]);
      final stale = MailboxProductionHeadlessCallAdmissionSession(
        mailboxClient: staleMailbox,
        authenticateEvent: _bindingAuthenticator(<int>[]),
        closeResources: () async => _Session.safeCleanup,
      );
      expect(
        await stale.evaluate(
          HeadlessCallAdmissionInvocation(
            nonce: invocation.nonce,
            callId: invocation.callId,
            wakeHandle: invocation.wakeHandle,
            expiresAtMs: 1_800_000_051_000,
          ),
        ),
        HeadlessCallAdmissionDisposition.emptyOrAlreadyAcked,
      );

      final rejectedMailbox = _Mailbox(<CallMailboxEvent>[_event()]);
      final rejected = MailboxProductionHeadlessCallAdmissionSession(
        mailboxClient: rejectedMailbox,
        authenticateEvent: ({required invocation, required event}) async {
          throw const IncomingCallPrePresentationAdmissionException(
            IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
          );
        },
        closeResources: () async => _Session.safeCleanup,
      );
      expect(
        await rejected.evaluate(invocation),
        HeadlessCallAdmissionDisposition.permanentReject,
      );

      final deferredMailbox = _Mailbox(<CallMailboxEvent>[_event()]);
      final deferred = MailboxProductionHeadlessCallAdmissionSession(
        mailboxClient: deferredMailbox,
        authenticateEvent: ({required invocation, required event}) async {
          throw const IncomingCallPrePresentationAdmissionException(
            IncomingCallPrePresentationAdmissionFailureCode.deferred,
          );
        },
        closeResources: () async => _Session.safeCleanup,
      );
      expect(
        await deferred.evaluate(invocation),
        HeadlessCallAdmissionDisposition.deferred,
      );

      for (final mailbox in <_Mailbox>[
        admittedMailbox,
        staleMailbox,
        rejectedMailbox,
        deferredMailbox,
      ]) {
        expect(mailbox.ackedHandles, isEmpty);
      }
    },
  );

  // Device 2026-09-05 17:44Z (captures fresh-260905194144): the Pixel's app
  // was killed, the call was presented headlessly and declined from the
  // notification at 19:44:14; nothing reached the iPhone, which rang back
  // until its own cancel five seconds later. A native decline without a Dart
  // owner now schedules a decline-reply run: the same headless session
  // authenticates the invite row again, sends the caller one `reject`, and
  // acknowledges the rows of the ended call.
  group('decline reply mode', () {
    final declineInvocation = HeadlessCallAdmissionInvocation(
      nonce: invocation.nonce,
      callId: invocation.callId,
      wakeHandle: invocation.wakeHandle,
      expiresAtMs: invocation.expiresAtMs,
      mode: HeadlessCallAdmissionMode.declineReply,
    );

    test('rejects the caller from the authenticated invite and acks', () async {
      final order = <String>[];
      final replied = <CallSignal>[];
      final repliedHandles = <String>[];
      final mailbox = _Mailbox(<CallMailboxEvent>[
        _event(messageId: '44444444-4444-4444-8444-444444444444'),
      ], onAck: () => order.add('ack'));
      final session = MailboxProductionHeadlessCallAdmissionSession(
        mailboxClient: mailbox,
        authenticateEvent: _signalAuthenticator(),
        declineReplySender: (invite, callHandle) async {
          order.add('reply');
          replied.add(invite);
          repliedHandles.add(callHandle);
          return true;
        },
        closeResources: () async {
          order.add('close');
          return _Session.safeCleanup;
        },
      );

      expect(
        await session.evaluate(declineInvocation),
        HeadlessCallAdmissionDisposition.terminal,
      );
      expect(await session.close(), _Session.safeCleanup);
      expect(replied.map((signal) => signal.messageId), <String>[
        '44444444-4444-4444-8444-444444444444',
      ]);
      expect(replied.single.event, CallSignalType.invite);
      // The reply rides the mailbox handle the rows were retrieved under,
      // never the call id inside the envelope (device 2026-09-05 18:23Z).
      expect(repliedHandles, <String>[invocation.callId]);
      expect(mailbox.ackedHandles, <String>[invocation.callId]);
      expect(mailbox.ackedMessageIds, <List<String>>[
        <String>['44444444-4444-4444-8444-444444444444'],
      ]);
      expect(order, <String>['reply', 'ack', 'close']);
      expect(mailbox.retrievedHandles, <String>[invocation.callId]);
    });

    test('an already ended call is acknowledged without a reply', () async {
      var replies = 0;
      final mailbox = _Mailbox(<CallMailboxEvent>[
        _event(
          messageId: '44444444-4444-4444-8444-444444444444',
          expiresAtMs: 1_800_000_045_000,
        ),
        _event(
          messageId: '55555555-5555-4555-8555-555555555555',
          expiresAtMs: 1_800_000_051_000,
        ),
      ]);
      final session = MailboxProductionHeadlessCallAdmissionSession(
        mailboxClient: mailbox,
        authenticateEvent: _signalAuthenticator(),
        declineReplySender: (_, _) async {
          replies++;
          return true;
        },
        closeResources: () async => _Session.safeCleanup,
      );

      expect(
        await session.evaluate(declineInvocation),
        HeadlessCallAdmissionDisposition.terminal,
      );
      expect(replies, 0);
      expect(mailbox.ackedMessageIds, <List<String>>[
        <String>[
          '44444444-4444-4444-8444-444444444444',
          '55555555-5555-4555-8555-555555555555',
        ],
      ]);
    });

    test(
      'a reply that reaches no custody leaves the rows and defers',
      () async {
        for (final sender in <HeadlessDeclineReplySender>[
          (_, _) async => false,
          (_, _) async => throw StateError('relay unreachable'),
        ]) {
          final mailbox = _Mailbox(<CallMailboxEvent>[_event()]);
          final session = MailboxProductionHeadlessCallAdmissionSession(
            mailboxClient: mailbox,
            authenticateEvent: _signalAuthenticator(),
            declineReplySender: sender,
            closeResources: () async => _Session.safeCleanup,
          );

          expect(
            await session.evaluate(declineInvocation),
            HeadlessCallAdmissionDisposition.deferred,
          );
          expect(mailbox.ackedHandles, isEmpty);
        }
      },
    );

    test(
      'without a sender or an authenticated invite nothing is sent',
      () async {
        var replies = 0;
        final noSender = MailboxProductionHeadlessCallAdmissionSession(
          mailboxClient: _Mailbox(<CallMailboxEvent>[_event()]),
          authenticateEvent: _signalAuthenticator(),
          closeResources: () async => _Session.safeCleanup,
        );
        expect(
          await noSender.evaluate(declineInvocation),
          HeadlessCallAdmissionDisposition.deferred,
        );

        final rejected = MailboxProductionHeadlessCallAdmissionSession(
          mailboxClient: _Mailbox(<CallMailboxEvent>[_event()]),
          authenticateEvent: ({required invocation, required event}) async {
            throw const IncomingCallPrePresentationAdmissionException(
              IncomingCallPrePresentationAdmissionFailureCode.permanentReject,
            );
          },
          declineReplySender: (_, _) async {
            replies++;
            return true;
          },
          closeResources: () async => _Session.safeCleanup,
        );
        expect(
          await rejected.evaluate(declineInvocation),
          HeadlessCallAdmissionDisposition.permanentReject,
        );

        final deferred = MailboxProductionHeadlessCallAdmissionSession(
          mailboxClient: _Mailbox(<CallMailboxEvent>[_event()]),
          authenticateEvent: ({required invocation, required event}) async {
            throw const IncomingCallPrePresentationAdmissionException(
              IncomingCallPrePresentationAdmissionFailureCode.deferred,
            );
          },
          declineReplySender: (_, _) async {
            replies++;
            return true;
          },
          closeResources: () async => _Session.safeCleanup,
        );
        expect(
          await deferred.evaluate(declineInvocation),
          HeadlessCallAdmissionDisposition.deferred,
        );

        final empty = MailboxProductionHeadlessCallAdmissionSession(
          mailboxClient: _Mailbox(const <CallMailboxEvent>[]),
          authenticateEvent: _signalAuthenticator(),
          declineReplySender: (_, _) async {
            replies++;
            return true;
          },
          closeResources: () async => _Session.safeCleanup,
        );
        expect(
          await empty.evaluate(declineInvocation),
          HeadlessCallAdmissionDisposition.emptyOrAlreadyAcked,
        );
        expect(replies, 0);
      },
    );

    test('an admission run never replies even when a sender exists', () async {
      var replies = 0;
      final mailbox = _Mailbox(<CallMailboxEvent>[_event()]);
      final session = MailboxProductionHeadlessCallAdmissionSession(
        mailboxClient: mailbox,
        authenticateEvent: _signalAuthenticator(),
        declineReplySender: (_, _) async {
          replies++;
          return true;
        },
        closeResources: () async => _Session.safeCleanup,
      );

      expect(
        await session.evaluate(invocation),
        HeadlessCallAdmissionDisposition.admitted,
      );
      expect(replies, 0);
      expect(mailbox.ackedHandles, isEmpty);
    });

    test('the runner hands the decline reply mode to the session', () async {
      final session = _Session(HeadlessCallAdmissionDisposition.terminal);
      final report = await ProductionHeadlessCallAdmissionRunner(
        backend: _Backend(session),
        nowMs: () => 1_800_000_000_000,
      ).run(invocation: declineInvocation, isStopRequested: () => false);

      expect(
        session.lastInvocation?.mode,
        HeadlessCallAdmissionMode.declineReply,
      );
      expect(report.disposition, HeadlessCallAdmissionDisposition.terminal);
      expect(report.requiredPersistenceComplete, isTrue);
    });
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

  group('406 killed-app call history', () {
    test('TC-406-30 a call the caller ended while the app was dead is '
        'recorded as cancelled', () async {
      final recorder = _HistoryRecorder();
      final session = MailboxProductionHeadlessCallAdmissionSession(
        mailboxClient: _Mailbox(<CallMailboxEvent>[
          _event(messageId: '44444444-4444-4444-8444-444444444444'),
          _event(messageId: '55555555-5555-4555-8555-555555555555'),
        ]),
        authenticateEvent: _signalAuthenticator(),
        historyRecorder: recorder.record,
        closeResources: () async => _Session.safeCleanup,
      );

      expect(
        await session.evaluate(invocation),
        HeadlessCallAdmissionDisposition.terminal,
      );

      expect(
        recorder.calls,
        hasLength(1),
        reason:
            'no coordinator ever runs for a killed-app call, so this is the '
            'only chance to write the row',
      );
      final recorded = recorder.calls.single;
      expect(recorded.reason, CallEndReason.callerCancelled);
      expect(recorded.terminal.event, CallSignalType.terminate);
      expect(recorded.invite?.event, CallSignalType.invite);
      expect(recorded.terminal.senderAccountPeerId, 'caller-account');
    });

    test('TC-406-31 an admitted call records nothing: the foreground owner '
        'still projects it', () async {
      final recorder = _HistoryRecorder();
      final session = MailboxProductionHeadlessCallAdmissionSession(
        mailboxClient: _Mailbox(<CallMailboxEvent>[
          _event(messageId: '44444444-4444-4444-8444-444444444444'),
        ]),
        authenticateEvent: _signalAuthenticator(),
        historyRecorder: recorder.record,
        closeResources: () async => _Session.safeCleanup,
      );

      expect(
        await session.evaluate(invocation),
        HeadlessCallAdmissionDisposition.admitted,
      );
      expect(recorder.calls, isEmpty);
    });

    test('TC-406-32 a failing recorder never changes the disposition', () async {
      final recorder = _HistoryRecorder()..error = StateError('db closed');
      final session = MailboxProductionHeadlessCallAdmissionSession(
        mailboxClient: _Mailbox(<CallMailboxEvent>[
          _event(messageId: '44444444-4444-4444-8444-444444444444'),
          _event(messageId: '55555555-5555-4555-8555-555555555555'),
        ]),
        authenticateEvent: _signalAuthenticator(),
        historyRecorder: recorder.record,
        closeResources: () async => _Session.safeCleanup,
      );

      expect(
        await session.evaluate(invocation),
        HeadlessCallAdmissionDisposition.terminal,
        reason:
            'releasing the relay slot is custody work; a history write is not',
      );
    });
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

/// Authenticates every row against its own expiry and hands the session the
/// decoded signal: the 4444… row is the invite, every other row a terminate.
/// 406: records what the headless session asked to be projected.
final class _HistoryRecorder {
  final calls =
      <({CallSignal terminal, CallSignal? invite, CallEndReason reason})>[];
  Object? error;

  Future<void> record({
    required CallSignal terminal,
    required CallEndReason reason,
    CallSignal? invite,
  }) async {
    calls.add((terminal: terminal, invite: invite, reason: reason));
    if (error != null) throw error!;
  }
}

AuthenticateHeadlessMailboxEvent _signalAuthenticator() =>
    ({required invocation, required event}) async {
      final type = event.messageId == '44444444-4444-4444-8444-444444444444'
          ? CallSignalType.invite
          : CallSignalType.terminate;
      return HeadlessAuthenticatedMailboxEvent(
        event: type,
        rollbackReplay: () {},
        signal: CallSignal.create(
          callId: CallId.parse(invocation.callId),
          messageId: event.messageId,
          event: type,
          senderAccountPeerId: 'caller-account',
          senderDevicePeerId: 'caller-device',
          recipientAccountPeerId: 'local-account',
          recipientDevicePeerId: 'local-device',
          senderSequence: type == CallSignalType.invite ? 1 : 2,
          iceGeneration: 0,
          createdAtMs: 1_800_000_000_000,
          expiresAtMs: event.expiresAtMs,
          payload: type == CallSignalType.invite
              ? const <String, Object?>{
                  'capabilities': <Object?>['audio'],
                  'metadata': <String, Object?>{
                    'media': 'audio',
                    'video': false,
                  },
                }
              : const <String, Object?>{'reason': 'local_hangup'},
        ),
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
  _Mailbox(this.events, {this.hasMore = false, this.onAck});

  final List<CallMailboxEvent> events;
  final bool hasMore;
  final List<String?> retrievedHandles = <String?>[];
  final List<String> ackedHandles = <String>[];
  final List<List<String>> ackedMessageIds = <List<String>>[];
  final void Function()? onAck;
  Object? ackFailure;

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
  }) async {
    final failure = ackFailure;
    if (failure != null) throw failure;
    ackedHandles.add(callHandle);
    ackedMessageIds.add(List<String>.unmodifiable(messageIds));
    onAck?.call();
    return messageIds.length;
  }

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
  HeadlessCallAdmissionInvocation? lastInvocation;

  @override
  Future<HeadlessCallAdmissionDisposition> evaluate(
    HeadlessCallAdmissionInvocation invocation,
  ) async {
    evaluateCalls++;
    lastInvocation = invocation;
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
