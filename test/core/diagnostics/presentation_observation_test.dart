import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../bridge/fake_bridge.dart';
import '../../features/contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../features/contacts/domain/repositories/fake_contact_repository.dart';

const _request = ContactRequestModel(
  peerId: 'PRIVATE_PRESENTATION_PEER',
  publicKey: 'PRIVATE_PRESENTATION_KEY',
  rendezvous: 'PRIVATE_PRESENTATION_ROUTE',
  username: 'PRIVATE_PRESENTATION_NAME',
  signature: 'PRIVATE_PRESENTATION_SIGNATURE',
  receivedAt: '2026-01-01T00:00:00.000Z',
  status: ContactRequestStatus.pending,
);

final class _GatedRequests extends FakeContactRequestRepository {
  Completer<void>? gate;
  Completer<void>? entered;
  var decisionCalls = 0;

  @override
  Future<ContactRequestDecisionResult> decideRequest({
    required ContactRequestModel expectedRequest,
    required bool accept,
    bool existingContactOnly = false,
    Future<void> Function()? beforeMarkAccepted,
  }) async {
    decisionCalls++;
    if (entered case final signal? when !signal.isCompleted) signal.complete();
    await gate?.future;
    return super.decideRequest(
      expectedRequest: expectedRequest,
      accept: accept,
      existingContactOnly: existingContactOnly,
      beforeMarkAccepted: beforeMarkAccepted,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppDiagnostics diagnostics;
  late _GatedRequests requests;
  late ContactRequestListener listener;
  late Set<String> suppressed;
  late bool previousFlow;

  setUp(() async {
    previousFlow = flowEventLoggingEnabled;
    flowEventLoggingEnabled = false;
    directory = await Directory.systemTemp.createTemp('presentation-observer-');
    diagnostics = await AppDiagnostics.installForTesting(directory: directory);
    requests = _GatedRequests()
      ..contactRepository = FakeContactRepository()
      ..seed([_request]);
    suppressed = {};
    listener = ContactRequestListener(
      contactRequestStream: const Stream<ChatMessage>.empty(),
      requestRepo: requests,
      contactRepo: requests.contactRepository!,
      bridge: FakeBridge(),
      getOwnPeerId: () => 'PRIVATE_PRESENTATION_LOCAL',
      shouldSuppressPresentationForPeerId: suppressed.contains,
    );
  });

  tearDown(() async {
    listener.dispose();
    await diagnostics.dispose();
    await directory.delete(recursive: true);
    flowEventLoggingEnabled = previousFlow;
  });

  Future<List<Map<String, dynamic>>> observations({
    String consent = 'unknown',
  }) async {
    final preview = await diagnostics.exportPreview();
    for (final secret in [
      _request.peerId,
      _request.publicKey,
      _request.username,
      _request.signature,
      _request.rendezvous,
      'PRIVATE_PRESENTATION_SECOND',
      'PRIVATE_PRESENTATION_OBSERVER_ERROR',
    ]) {
      expect(preview, isNot(contains(secret)));
    }
    final records = ((jsonDecode(preview) as Map)['events'] as List)
        .cast<Map<String, dynamic>>()
        .where(
          (event) =>
              event['feature'] == 'contact_request' &&
              event['stage'] == 'present' &&
              const ['ok', 'rejected'].contains(event['outcome']),
        )
        .toList();
    for (final event in records) {
      expect(event.containsKey('traceId'), isFalse);
      expect(event.containsKey('attemptId'), isFalse);
      expect((event['values'] as Map)['consentClass'], consent);
      expect((event['values'] as Map).containsKey('requestAction'), isFalse);
    }
    return records;
  }

  Future<void> expectOneRejection({
    String? source,
    String consent = 'unknown',
  }) async {
    final records = await observations(consent: consent);
    expect(records, hasLength(1));
    expect(records.single['outcome'], 'rejected');
    expect(records.single['values'], {
      'requestDisposition': 'ignored',
      'consentClass': consent,
      if (source != null) 'requestSource': source,
    });
  }

  test(
    'early stored-replay suppression is observed without a dialog',
    () async {
      suppressed.add(_request.peerId);
      final delivered = <ContactRequestModel>[];
      final subscription = listener.requestStream.listen(delivered.add);
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);
      expect(delivered, isEmpty);
      await expectOneRejection(source: 'stored_replay');
      expect(
        (await requests.getRequest(_request.peerId))!.status,
        ContactRequestStatus.pending,
      );
    },
  );

  test(
    'final queued suppression is observed before the decision read',
    () async {
      suppressed.add(_request.peerId);
      var presented = 0;
      await listener.presentRequest(_request, () async => presented++);
      expect(presented, 0);
      expect(requests.decisionCalls, 0);
      await expectOneRejection();
    },
  );

  test('suppression after the pending read is observed exactly once', () async {
    requests.gate = Completer<void>();
    requests.entered = Completer<void>();
    var presented = 0;
    final pending = listener.presentRequest(_request, () async => presented++);
    await requests.entered!.future;
    suppressed.add(_request.peerId);
    requests.gate!.complete();
    await pending;
    expect(presented, 0);
    expect(requests.decisionCalls, 1);
    await expectOneRejection();
  });

  test(
    'settled accepted consent is observed from the existing decision',
    () async {
      (requests.contactRepository! as FakeContactRepository).seed([
        ContactModel(
          peerId: _request.peerId,
          publicKey: _request.publicKey,
          rendezvous: _request.rendezvous,
          username: _request.username,
          signature: _request.signature,
          scannedAt: _request.receivedAt,
        ),
      ]);
      var presented = 0;
      await listener.presentRequest(_request, () async => presented++);
      expect(presented, 0);
      expect(
        (await requests.getRequest(_request.peerId))!.status,
        ContactRequestStatus.accepted,
      );
      await expectOneRejection(consent: 'active');
    },
  );

  test(
    'queued joins add no outcome and callbacks alone prove no route',
    () async {
      final second = _request.copyWith(peerId: 'PRIVATE_PRESENTATION_SECOND');
      requests.seed([_request, second]);
      final hold = Completer<void>();
      final entered = Completer<void>();
      var firstPresented = 0;
      var secondPresented = 0;
      final first = listener.presentRequest(_request, () async {
        firstPresented++;
        entered.complete();
        await hold.future;
      });
      await entered.future;
      expect(await observations(), isEmpty);
      final next = listener.presentRequest(
        second,
        () async => secondPresented++,
      );
      final joined = listener.presentRequest(
        second,
        () async => secondPresented++,
      );
      suppressed.add(second.peerId);
      hold.complete();
      await Future.wait([first, next, joined]);
      expect(firstPresented, 1);
      expect(secondPresented, 0);
      await expectOneRejection();
    },
  );

  for (final unavailable in [false, true]) {
    test(
      'suppression decisions survive observer ${unavailable ? 'failure' : 'opt-out'}',
      () async {
        if (unavailable) {
          var writeAttempts = 0;
          diagnostics = await AppDiagnostics.installForTesting(
            directory: directory,
            persist: (_, _) async {
              writeAttempts++;
              throw StateError('PRIVATE_PRESENTATION_OBSERVER_ERROR');
            },
          );
          expect(writeAttempts, greaterThan(0));
          expect(
            diagnostics.record(
              feature: 'runtime',
              stage: 'snapshot',
              outcome: 'ok',
            ),
            isFalse,
          );
        } else {
          await diagnostics.setEnabled(false);
        }
        suppressed.add(_request.peerId);
        var presented = 0;
        await listener.presentRequest(_request, () async => presented++);
        expect(presented, 0);
        expect(requests.decisionCalls, 0);
        expect(await observations(), isEmpty);
      },
    );
  }
}
