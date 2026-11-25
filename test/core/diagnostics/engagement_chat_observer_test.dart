import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/diagnostics/engagement_chat_checkpoint_store.dart';
import 'package:flutter_app/core/diagnostics/engagement_chat_observer.dart';
import 'package:flutter_app/core/diagnostics/engagement_chat_witness.dart';
import 'package:flutter_test/flutter_test.dart';

const _wait = Duration(seconds: 2);
const _signalWait = Duration(seconds: 1);
const EngagementChatObserverOwner _ownerA = (
  accountPeerId: 'own-a',
  profileBinding:
      'v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  consentEpoch: 7,
);
const EngagementChatObserverOwner _ownerB = (
  accountPeerId: 'own-b',
  profileBinding:
      'v1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  consentEpoch: 8,
);
// Controlled Go-port intervals, not a Dart calendar implementation.
const EngagementChatWeekInterval _week = (
  week: '2026-W47',
  startMilliseconds: 0,
  endMilliseconds: 2000000,
);
const EngagementChatWeekInterval _nextWeek = (
  week: '2026-W48',
  startMilliseconds: 2000000,
  endMilliseconds: 4000000,
);
const _contact = 'peer-private';
const _message = 'message-private';
const _generation = 'generation-private';

Future<T> _within<T>(Future<T> future) => future.timeout(_wait);

final class _Barrier {
  final entered = Completer<void>();
  final released = Completer<void>();

  Future<void> hold() {
    if (!entered.isCompleted) {
      entered.complete();
    }
    return released.future.timeout(_wait);
  }

  void open() {
    if (!released.isCompleted) {
      released.complete();
    }
  }
}

Future<void> _entered(_Barrier barrier) async {
  final arrived = await barrier.entered.future
      .then((_) => true)
      .timeout(_signalWait, onTimeout: () => false);
  expect(arrived, isTrue, reason: 'the owned observer operation must start');
}

Future<void> _drain(EngagementChatObserver observer) async {
  Object? failure;
  final completed = await Future<void>.sync(observer.flush)
      .then<bool>(
        (_) => true,
        onError: (Object error, StackTrace _) {
          failure = error;
          return false;
        },
      )
      .timeout(_wait, onTimeout: () => false);
  expect(
    completed,
    isTrue,
    reason: failure == null
        ? 'accepted observer work must settle within its bound'
        : 'optional observer work must contain its failure: $failure',
  );
}

EngagementChatObserverCapture _capture(
  EngagementChatObserver observer, [
  EngagementChatObserverOwner owner = _ownerA,
]) {
  final capture = observer.captureOwner(
    expectedAccountPeerId: owner.accountPeerId,
  );
  expect(capture, isNotNull);
  return capture!;
}

EngagementChatObserverIntent _reserve(
  EngagementChatObserver observer,
  EngagementChatObserverCapture capture, {
  String contact = _contact,
  String message = _message,
}) {
  final intent = observer.reserve(
    capture,
    contactAccount: contact,
    messageId: message,
    generationId: _generation,
  );
  expect(intent, isNotNull);
  return intent!;
}

void _deliver(
  EngagementChatObserver observer,
  EngagementChatObserverCapture capture, {
  String contact = _contact,
  String message = _message,
}) {
  observer.delivered(
    capture,
    contactAccount: contact,
    messageId: message,
    generationId: _generation,
  );
}

void _facts(
  EngagementChatObserver observer,
  EngagementChatObserverCapture capture, {
  String contact = _contact,
  String message = _message,
}) {
  final intent = _reserve(
    observer,
    capture,
    contact: contact,
    message: message,
  );
  observer.admitted(intent);
  _deliver(observer, capture, contact: contact, message: message);
  observer.incoming(capture, contactAccount: contact);
}

Future<Map<String, dynamic>> _checkpoint(
  EngagementChatCheckpointStore store,
) async {
  final file = File(store.checkpointPath);
  expect(await _within(file.exists()), isTrue);
  return jsonDecode(await _within(file.readAsString()))
      as Map<String, dynamic>;
}

void main() {
  late Directory directory;
  var now = 1000;
  final stores = <EngagementChatCheckpointStore>[];
  final observers = <EngagementChatObserver>[];
  final barriers = <_Barrier>[];
  final calendars = <Completer<EngagementChatWeekInterval?>>[];
  final retentions = <Map<String, Object?>>[];

  Future<EngagementChatCheckpointStore> open({
    EngagementChatBeforeCommit? beforeCommit,
    EngagementChatRename? rename,
  }) async {
    final store = await _within(
      EngagementChatCheckpointStore.open(
        directory.path,
        beforeCommit: beforeCommit,
        rename: rename,
      ),
    );
    stores.add(store);
    return store;
  }

  Future<EngagementChatObserver> make({
    EngagementChatCheckpointStore? store,
    EngagementChatWeekLookup? lookup,
    EngagementChatLocalRetention? retain,
    EngagementChatObserverOwner owner = _ownerA,
    Duration? deadline,
    Duration? checkpointRetryDelay,
  }) async {
    final checkpoint = store ?? await open();
    final observer = EngagementChatObserver(
      store: checkpoint,
      lookupWeek:
          lookup ??
          ((EngagementChatObserverCapture _) =>
              Future<EngagementChatWeekInterval?>.value(_week)),
      retainChat:
          retain ??
          ((EngagementChatObserverCapture capture, String week) {
            retentions.add({
              'account': capture.owner.accountPeerId,
              'binding': capture.owner.profileBinding,
              'epoch': capture.owner.consentEpoch,
              'week': week,
            });
            return Future.value(true);
          }),
      nowMilliseconds: () => now,
      deadline: deadline ?? const Duration(seconds: 1),
      checkpointRetryDelay:
          checkpointRetryDelay ?? const Duration(milliseconds: 10),
    );
    observers.add(observer);
    observer.replaceOwner(owner);
    return observer;
  }

  _Barrier barrier() {
    final result = _Barrier();
    barriers.add(result);
    return result;
  }

  Completer<EngagementChatWeekInterval?> calendar() {
    final result = Completer<EngagementChatWeekInterval?>();
    calendars.add(result);
    return result;
  }

  setUp(() async {
    now = 1000;
    directory = await _within(
      Directory.systemTemp.createTemp('engagement-chat-observer-'),
    );
  });

  tearDown(() async {
    for (final pending in calendars) {
      if (!pending.isCompleted) {
        pending.complete(null);
      }
    }
    for (final gate in barriers) {
      gate.open();
    }
    for (final observer in observers) {
      await _within(observer.dispose());
    }
    for (final store in stores) {
      await _within(store.close());
    }
    observers.clear();
    stores.clear();
    barriers.clear();
    calendars.clear();
    retentions.clear();
    if (await _within(directory.exists())) {
      await _within(directory.delete(recursive: true));
    }
  });

  test('E2O-001 initialization and wrong-account capture do not mark', () async {
    final observer = await make();
    expect(
      observer.captureOwner(expectedAccountPeerId: 'own-foreign'),
      isNull,
    );
    await _drain(observer);
    expect(observer.phase, EngagementChatPhase.collecting);
    expect(retentions, isEmpty);
  });

  test('E2O-002 pre-await owner A cannot attribute a completion to B', () async {
    final observer = await make();
    final authoring = barrier();
    Future<bool> delayedProducer() async {
      final captured = observer.captureOwner(
        expectedAccountPeerId: _ownerA.accountPeerId,
      );
      if (captured == null) {
        return false;
      }
      await _within(authoring.hold());
      final stale = observer.reserve(
        captured,
        contactAccount: _contact,
        messageId: _message,
        generationId: _generation,
      );
      if (stale != null) {
        return false;
      }
      _deliver(observer, captured);
      observer.incoming(captured, contactAccount: _contact);
      return true;
    }

    final producer = delayedProducer().then<bool>(
      (accepted) => accepted,
      onError: (Object _, StackTrace _) => false,
    );
    await _entered(authoring);
    observer.replaceOwner(_ownerB);
    authoring.open();
    expect(await _within(producer), isTrue);
    final current = _capture(observer, _ownerB);
    _facts(observer, current, message: 'fresh-b');
    await _drain(observer);
    expect(observer.phase, EngagementChatPhase.qualifiedRetained);
    expect(retentions, hasLength(1));
    expect(retentions.single['account'], _ownerB.accountPeerId);
    expect(retentions.single['epoch'], _ownerB.consentEpoch);
  });

  test('E2O-003 checkpoint pending precedes coarse ack and retained checkpoint', () async {
    final transitions = <String>[];
    final store = await open(
      beforeCommit: (temporaryPath) async {
        final raw = jsonDecode(
          await _within(File(temporaryPath).readAsString()),
        ) as Map<String, dynamic>;
        if (raw['phase'] == 'qualified_pending') {
          transitions.add('pending');
        }
        if (raw['phase'] == 'qualified_retained') {
          transitions.add('retained');
        }
      },
    );
    final observer = await make(
      store: store,
      retain: (capture, week) async {
        final raw = await _within(_checkpoint(store));
        expect(raw['phase'], 'qualified_pending');
        expect(raw['contacts'], isEmpty);
        expect(capture.owner, _ownerA);
        expect(week, _week.week);
        transitions.add('coarse-local-retention');
        return true;
      },
    );
    _facts(observer, _capture(observer));
    await _drain(observer);
    expect(observer.phase, EngagementChatPhase.qualifiedRetained);
    expect(transitions.indexOf('pending'), greaterThanOrEqualTo(0));
    expect(
      transitions.indexOf('coarse-local-retention'),
      greaterThan(transitions.indexOf('pending')),
    );
    expect(
      transitions.lastIndexOf('retained'),
      greaterThan(transitions.indexOf('coarse-local-retention')),
    );
    final raw = await _within(_checkpoint(store));
    expect(raw['phase'], 'qualified_retained');
    final text = jsonEncode(raw);
    expect(text, isNot(contains(_contact)));
    expect(text, isNot(contains(_message)));
    expect(text, isNot(contains(_generation)));
  });

  test('E2O-004 held calendar preserves known intent and early receipt order', () async {
    final pendingCalendar = calendar();
    final observer = await make(lookup: (_) => pendingCalendar.future);
    final capture = _capture(observer);
    final intent = _reserve(observer, capture);
    _deliver(observer, capture);
    observer.incoming(capture, contactAccount: _contact);
    observer.admitted(intent);
    observer.cancel(intent);
    pendingCalendar.complete(_week);
    await _drain(observer);
    expect(observer.phase, EngagementChatPhase.qualifiedRetained);
    expect(retentions, hasLength(1));
  });

  test('E2O-005 orphan and cancelled intent cannot credit a replacement', () async {
    final observer = await make();
    final capture = _capture(observer);
    _deliver(observer, capture);
    final cancelled = _reserve(observer, capture);
    _deliver(observer, capture);
    observer.cancel(cancelled);
    final replacement = _reserve(observer, capture);
    observer.incoming(capture, contactAccount: _contact);
    observer.admitted(cancelled);
    observer.admitted(replacement);
    await _drain(observer);
    expect(observer.phase, EngagementChatPhase.collecting);
    expect(retentions, isEmpty);
    _deliver(observer, capture);
    await _drain(observer);
    expect(observer.phase, EngagementChatPhase.qualifiedRetained);
    expect(retentions, hasLength(1));
  });

  test('E2O-006 delayed calendar never relabels old-week fact times', () async {
    now = _week.endMilliseconds - 1;
    final pendingCalendar = calendar();
    final observer = await make(lookup: (_) => pendingCalendar.future);
    final capture = _capture(observer);
    _facts(observer, capture);
    now = _nextWeek.startMilliseconds + 1;
    pendingCalendar.complete(_nextWeek);
    await _drain(observer);
    expect(observer.phase, EngagementChatPhase.collecting);
    expect(retentions, isEmpty);
    _facts(observer, capture, message: 'fresh-next-week');
    await _drain(observer);
    expect(observer.phase, EngagementChatPhase.qualifiedRetained);
    expect(retentions, hasLength(1));
    expect(retentions.single['week'], _nextWeek.week);
  });

  test('E2O-007 normal slow authoring does not expire its owner capture', () async {
    final observer = await make();
    final capture = _capture(observer);
    now += 20 * 60 * 1000;
    _facts(observer, capture, message: 'media-after-preparation');
    await _drain(observer);
    expect(observer.phase, EngagementChatPhase.qualifiedRetained);
    expect(retentions, hasLength(1));
  });

  test('E2O-008 unfinished fact admission stops at 64 without losing the first', () async {
    final pendingCalendar = calendar();
    final observer = await make(lookup: (_) => pendingCalendar.future);
    final capture = _capture(observer);
    final intents = <EngagementChatObserverIntent>[];
    // The 64 accepted unfinished facts include an in-flight calendar wait.
    for (var index = 0; index < 64; index++) {
      intents.add(_reserve(observer, capture, message: 'queued-$index'));
    }
    expect(
      observer.reserve(
        capture,
        contactAccount: _contact,
        messageId: 'overflow',
        generationId: _generation,
      ),
      isNull,
    );
    pendingCalendar.complete(_week);
    await _drain(observer);
    observer.admitted(intents.first);
    _deliver(observer, capture, message: 'queued-0');
    observer.incoming(capture, contactAccount: _contact);
    await _drain(observer);
    expect(observer.phase, EngagementChatPhase.qualifiedRetained);
    expect(retentions, hasLength(1));
  });

  test('E2O-009 pending coarse work survives unarm and restart without messages', () async {
    final store = await open();
    final observer = await make(
      store: store,
      retain: (_, _) => Future.value(false),
    );
    _facts(observer, _capture(observer));
    await _drain(observer);
    expect(observer.phase, EngagementChatPhase.qualifiedPending);
    final raw = await _within(_checkpoint(store));
    expect(raw['phase'], 'qualified_pending');
    expect(raw['contacts'], isEmpty);
    final before = await _within(File(store.checkpointPath).readAsBytes());
    observer.replaceOwner(null);
    await _drain(observer);
    expect(
      await _within(File(store.checkpointPath).readAsBytes()),
      orderedEquals(before),
    );
    await _within(observer.dispose());
    final restored = await make(store: store);
    await _drain(restored);
    expect(restored.phase, EngagementChatPhase.qualifiedRetained);
    expect(retentions, hasLength(1));
    expect((await _within(_checkpoint(store)))['contacts'], isEmpty);
  });

  test('E2O-010 held private write cannot acknowledge or overwrite successor', () async {
    final gate = barrier();
    final store = await open(
      beforeCommit: (temporaryPath) async {
        final raw = jsonDecode(
          await _within(File(temporaryPath).readAsString()),
        ) as Map<String, dynamic>;
        final scope = raw['scope'] as Map<String, dynamic>;
        if (raw['phase'] == 'qualified_pending' &&
            scope['profileBinding'] == _ownerA.profileBinding) {
          await _within(gate.hold());
        }
      },
    );
    final observer = await make(store: store);
    Future<String> admittedCommunication() async {
      final capture = _capture(observer);
      _facts(observer, capture, contact: 'peer-a-secret');
      return 'durably-admitted';
    }

    expect(await _within(admittedCommunication()), 'durably-admitted');
    await _entered(gate);
    observer.replaceOwner(_ownerB);
    _facts(
      observer,
      _capture(observer, _ownerB),
      contact: 'peer-b-secret',
      message: 'message-b',
    );
    gate.open();
    await _drain(observer);
    expect(observer.phase, EngagementChatPhase.qualifiedRetained);
    expect(retentions, hasLength(1));
    expect(retentions.single['account'], _ownerB.accountPeerId);
    final raw = await _within(_checkpoint(store));
    expect(
      (raw['scope'] as Map<String, dynamic>)['profileBinding'],
      _ownerB.profileBinding,
    );
    expect(raw['phase'], 'qualified_retained');
    expect(raw['contacts'], isEmpty);
  });

  test('E2O-011 calendar file and coarse-port failures stay optional', () async {
    final calendarFailure = await make(
      lookup: (_) async => throw StateError('controlled calendar failure'),
    );
    _facts(calendarFailure, _capture(calendarFailure));
    await _drain(calendarFailure);
    expect(calendarFailure.phase, EngagementChatPhase.collecting);
    expect(retentions, isEmpty);
    await _within(calendarFailure.dispose());
    await _within(calendarFailure.store.close());

    var renameCalls = 0;
    final failingStore = await open(
      rename: (_, _) async {
        renameCalls++;
        throw const FileSystemException('controlled checkpoint failure');
      },
    );
    final fileFailure = await make(store: failingStore);
    final fileCapture = _capture(fileFailure);
    _facts(fileFailure, fileCapture);
    await _drain(fileFailure);
    expect(renameCalls, greaterThan(0));
    expect(fileFailure.phase, isNot(EngagementChatPhase.qualifiedRetained));
    expect(retentions, isEmpty);
    await _within(fileFailure.dispose());
    await _within(failingStore.close());

    final goodStore = await open();
    final coarseFailure = await make(
      store: goodStore,
      retain: (_, _) async =>
          throw StateError('controlled coarse retention failure'),
    );
    _facts(coarseFailure, _capture(coarseFailure));
    await _drain(coarseFailure);
    expect(coarseFailure.phase, EngagementChatPhase.qualifiedPending);
    expect(
      (await _within(_checkpoint(goodStore)))['phase'],
      'qualified_pending',
    );
  });

  test('E2O-013 a checkpoint write past its deadline is retried in the same '
      'worker, so the week survives a restart', () async {
    var commits = 0;
    final store = await open(
      beforeCommit: (_) async {
        commits++;
        if (commits == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      },
    );
    final observer = await make(
      store: store,
      deadline: const Duration(milliseconds: 100),
      checkpointRetryDelay: const Duration(milliseconds: 400),
    );
    _facts(observer, _capture(observer));
    await _drain(observer);

    expect(retentions, hasLength(1));
    expect(retentions.single['week'], _week.week);
    expect((await _within(_checkpoint(store)))['phase'], 'qualified_retained');

    await _within(observer.dispose());
    final restarted = await make(store: store);
    await _drain(restarted);
    expect(restarted.phase, EngagementChatPhase.qualifiedRetained);
    expect(retentions, hasLength(1));
  });

  test('E2O-014 facts that meet a failed week lookup wait for the next '
      'worker start instead of being dropped', () async {
    var calendarUp = false;
    final observer = await make(
      lookup: (_) => Future<EngagementChatWeekInterval?>.value(
        calendarUp ? _week : null,
      ),
    );
    _facts(observer, _capture(observer));
    await _drain(observer);
    expect(retentions, isEmpty);

    calendarUp = true;
    await _drain(observer);

    expect(retentions, hasLength(1));
    expect(retentions.single['week'], _week.week);
  });

  test('E2O-012 revoke removes private witnesses before a new epoch', () async {
    final store = await open();
    final seeded = EngagementChatWitness(
      scope: (
        profileBinding: _ownerA.profileBinding,
        consentEpoch: _ownerA.consentEpoch,
        week: _week.week,
      ),
    );
    final seededCapture = seeded.captureOwner()!;
    final intent = seeded.reserve(
      seededCapture,
      contactAccount: _contact,
      messageId: _message,
      generationId: _generation,
    );
    expect(intent, isNotNull);
    seeded.admitted(intent!);
    seeded.incoming(seededCapture, contactAccount: _contact);
    await _within(
      File(store.checkpointPath).writeAsBytes(
        seeded.encodeSnapshot(),
        flush: true,
      ),
    );
    final observer = await make(store: store);
    await _drain(observer);
    final oldCapture = _capture(observer);
    observer.revoke();
    expect(
      observer.captureOwner(expectedAccountPeerId: _ownerA.accountPeerId),
      isNull,
    );
    await _drain(observer);
    expect(await _within(File(store.checkpointPath).exists()), isFalse);
    final rearmed = (
      accountPeerId: _ownerA.accountPeerId,
      profileBinding: _ownerA.profileBinding,
      consentEpoch: _ownerA.consentEpoch + 1,
    );
    observer.replaceOwner(rearmed);
    final current = _capture(observer, rearmed);
    _deliver(observer, oldCapture);
    observer.incoming(current, contactAccount: _contact);
    await _drain(observer);
    expect(observer.phase, EngagementChatPhase.collecting);
    expect(retentions, isEmpty);
    final fresh = _reserve(observer, current, message: 'fresh-after-on');
    observer.admitted(fresh);
    _deliver(observer, current, message: 'fresh-after-on');
    await _drain(observer);
    expect(observer.phase, EngagementChatPhase.qualifiedRetained);
    expect(retentions, hasLength(1));
  });
}
