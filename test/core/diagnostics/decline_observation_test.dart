import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/decline_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/contact_request/domain/repositories/fake_contact_request_repository.dart';

const _privateRequest = ContactRequestModel(
  peerId: 'PRIVATE_DECLINE_PEER',
  publicKey: 'PRIVATE_DECLINE_PUBLIC_KEY',
  rendezvous: 'PRIVATE_DECLINE_ROUTE',
  username: 'PRIVATE_DECLINE_NAME',
  signature: 'PRIVATE_DECLINE_SIGNATURE',
  receivedAt: '2026-01-01T00:00:00.000Z',
  status: ContactRequestStatus.pending,
  mlKemPublicKey: 'PRIVATE_DECLINE_MLKEM',
);

final class _DecisionRepository extends FakeContactRequestRepository {
  ContactRequestDecisionResult? forced;
  bool throwWrite = false;
  Completer<void>? writeGate;

  @override
  Future<ContactRequestDecisionResult> decideRequest({
    required ContactRequestModel expectedRequest,
    required bool accept,
    bool existingContactOnly = false,
    Future<void> Function()? beforeMarkAccepted,
  }) async {
    await writeGate?.future;
    if (throwWrite) throw StateError('PRIVATE_DECLINE_WRITE_ERROR');
    if (forced case final result?) {
      return result;
    }
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
  late _DecisionRepository repository;
  late List<Map<String, Object?>> uploaded;
  late bool previousFlow;

  setUp(() async {
    previousFlow = flowEventLoggingEnabled;
    flowEventLoggingEnabled = false;
    directory = await Directory.systemTemp.createTemp('decline-observation-');
    uploaded = [];
    diagnostics = await AppDiagnostics.installForTesting(
      directory: directory,
      upload: (events) async {
        uploaded.addAll(events);
        return events.map((event) => event['eventId']! as String).toSet();
      },
    );
    repository = _DecisionRepository()..seed([_privateRequest]);
  });

  tearDown(() async {
    flowEventLoggingEnabled = previousFlow;
    await diagnostics.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<List<Map<String, dynamic>>> observations() async {
    final preview = await diagnostics.exportPreview();
    for (final privateValue in [
      _privateRequest.peerId,
      _privateRequest.publicKey,
      _privateRequest.rendezvous,
      _privateRequest.username,
      _privateRequest.signature,
      _privateRequest.mlKemPublicKey!,
      'PRIVATE_DECLINE_WRITE_ERROR',
      'PRIVATE_OBSERVER_ERROR',
    ]) {
      expect(preview, isNot(contains(privateValue)));
    }
    final events = (jsonDecode(preview) as Map)['events'] as List;
    final records = events
        .cast<Map<String, dynamic>>()
        .where((event) => event['feature'] == 'contact_request')
        .toList();
    for (final event in records) {
      expect(event.containsKey('traceId'), isFalse);
      expect(event.containsKey('attemptId'), isFalse);
      expect((event['values'] as Map).containsKey('requestAction'), isFalse);
    }
    return records;
  }

  Future<DeclineContactRequestResult> decline() => declineContactRequest(
    requestRepo: repository,
    peerId: _privateRequest.peerId,
  );

  Future<Map<String, dynamic>> decisionObservation() async {
    final records = await observations();
    expect(records, hasLength(1));
    return records.single;
  }

  test(
    'decline records a private commit only after the durable decision',
    () async {
      repository.writeGate = Completer<void>();
      final pending = decline();
      await Future<void>.delayed(Duration.zero);
      expect(await observations(), isEmpty);
      expect(repository.updateStatusCallCount, 0);
      repository.writeGate!.complete();
      expect(await pending, DeclineContactRequestResult.success);
      expect(repository.lastUpdateStatus, ContactRequestStatus.declined);
      final event = await decisionObservation();
      expect(event['stage'], 'commit');
      expect(event['outcome'], 'ok');
      expect(event['reason'], 'none');
      expect(event['values'], {
        'requestSource': 'local_action',
        'consentClass': 'declined',
        'requestDisposition': 'committed',
      });
      await diagnostics.flush();
      final wire = uploaded.singleWhere(
        (e) => e['eventId'] == event['eventId'],
      );
      expect(wire['feature'], 'contact_request');
      expect(wire['values'], event['values']);
      expect((await observations()).single['values'], event['values']);
    },
  );

  for (final decision in [
    ContactRequestDecisionResult.notFound,
    ContactRequestDecisionResult.notPending,
    ContactRequestDecisionResult.updateStatusError,
  ]) {
    test(
      'decline observes $decision without inventing committed consent',
      () async {
        repository.forced = decision;
        final failed =
            decision == ContactRequestDecisionResult.updateStatusError;
        expect(
          await decline(),
          failed
              ? DeclineContactRequestResult.updateError
              : decision == ContactRequestDecisionResult.notFound
              ? DeclineContactRequestResult.notFound
              : DeclineContactRequestResult.notPending,
        );
        expect(repository.updateStatusCallCount, 0);
        final event = await decisionObservation();
        expect(event['stage'], 'commit');
        expect(event['outcome'], failed ? 'failed' : 'rejected');
        expect(event['reason'], 'unknown');
        expect(event['values'], {
          'requestSource': 'local_action',
          'consentClass': 'unknown',
          'requestDisposition': failed ? 'failed' : 'ignored',
        });
      },
    );
  }

  test('a missing lookup is a noncommit without a write', () async {
    repository.seed([]);
    expect(await decline(), DeclineContactRequestResult.notFound);
    expect(repository.updateStatusCallCount, 0);
    final event = await decisionObservation();
    expect(event['stage'], 'commit');
    expect(event['outcome'], 'rejected');
    expect(event['reason'], 'unknown');
    expect((event['values'] as Map)['consentClass'], 'unknown');
    expect((event['values'] as Map)['requestDisposition'], 'ignored');
  });

  test('decline observes a thrown write without changing its result', () async {
    repository.throwWrite = true;
    expect(await decline(), DeclineContactRequestResult.updateError);
    expect(repository.updateStatusCallCount, 0);
    final event = await decisionObservation();
    expect(event['stage'], 'commit');
    expect(event['outcome'], 'failed');
    expect(event['reason'], 'unknown');
    expect((event['values'] as Map)['consentClass'], 'unknown');
  });

  test('opted-out observation cannot change the decline decision', () async {
    await diagnostics.setEnabled(false);
    expect(await decline(), DeclineContactRequestResult.success);
    expect(repository.lastUpdateStatus, ContactRequestStatus.declined);
    expect(await observations(), isEmpty);
  });

  test('unavailable observer cannot change the decline decision', () async {
    var writeAttempts = 0;
    diagnostics = await AppDiagnostics.installForTesting(
      directory: directory,
      persist: (_, _) async {
        writeAttempts++;
        throw StateError('PRIVATE_OBSERVER_ERROR');
      },
    );
    expect(writeAttempts, greaterThan(0));
    expect(
      diagnostics.record(feature: 'runtime', stage: 'snapshot', outcome: 'ok'),
      isFalse,
    );
    expect(await decline(), DeclineContactRequestResult.success);
    expect(repository.lastUpdateStatus, ContactRequestStatus.declined);
    await observations();
  });
}
