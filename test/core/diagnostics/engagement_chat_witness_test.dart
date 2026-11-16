import 'dart:convert';

import 'package:flutter_app/core/diagnostics/engagement_chat_witness.dart';
import 'package:flutter_test/flutter_test.dart';

const EngagementChatScope _scope = (
  profileBinding:
      'v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  consentEpoch: 7,
  week: '2026-W47',
);
const EngagementChatScope _otherProfile = (
  profileBinding:
      'v1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  consentEpoch: 7,
  week: '2026-W47',
);
const EngagementChatScope _otherEpoch = (
  profileBinding:
      'v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  consentEpoch: 8,
  week: '2026-W47',
);
const EngagementChatScope _otherWeek = (
  profileBinding:
      'v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  consentEpoch: 7,
  week: '2026-W48',
);
const _contact = 'peer-a';
const _message = 'message-a';
const _generation = 'generation-a';
const _snapshotByteLimit = 256 * 1024;

const _orders = <String, List<String>>{
  'E2W-001 admission delivery incoming qualifies once': ['a', 'd', 'i'],
  'E2W-002 admission incoming delivery qualifies once': ['a', 'i', 'd'],
  'E2W-003 delivery admission incoming qualifies once': ['d', 'a', 'i'],
  'E2W-004 delivery incoming admission qualifies once': ['d', 'i', 'a'],
  'E2W-005 incoming admission delivery qualifies responder': ['i', 'a', 'd'],
  'E2W-006 incoming delivery admission qualifies responder': ['i', 'd', 'a'],
};

EngagementChatCapture _capture(EngagementChatWitness witness) {
  final capture = witness.captureOwner();
  expect(capture, isNotNull);
  return capture!;
}

EngagementChatIntent _reserve(
  EngagementChatWitness witness,
  EngagementChatCapture capture, {
  String contact = _contact,
  String message = _message,
  String generation = _generation,
}) {
  final intent = witness.reserve(
    capture,
    contactAccount: contact,
    messageId: message,
    generationId: generation,
  );
  expect(intent, isNotNull);
  return intent!;
}

void _deliver(
  EngagementChatWitness witness,
  EngagementChatCapture capture, {
  String contact = _contact,
  String message = _message,
  String generation = _generation,
}) {
  witness.delivered(
    capture,
    contactAccount: contact,
    messageId: message,
    generationId: generation,
  );
}

void _qualify(
  EngagementChatWitness witness,
  EngagementChatCapture capture, {
  String contact = _contact,
  String message = _message,
}) {
  final intent = _reserve(
    witness,
    capture,
    contact: contact,
    message: message,
  );
  witness.admitted(intent);
  _deliver(witness, capture, contact: contact, message: message);
  witness.incoming(capture, contactAccount: contact);
}

Map<String, dynamic> _snapshot(EngagementChatWitness witness) =>
    jsonDecode(utf8.decode(witness.encodeSnapshot())) as Map<String, dynamic>;

List<Map<String, dynamic>> _contacts(EngagementChatWitness witness) =>
    (_snapshot(witness)['contacts'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

Map<String, Object?> _ref({
  String message = _message,
  String generation = _generation,
}) => <String, Object?>{'message': message, 'generation': generation};

Map<String, Object?> _contactRecord({
  String account = _contact,
  bool incoming = false,
  bool delivered = false,
  List<Map<String, Object?>> outgoing = const [],
}) => <String, Object?>{
  'account': account,
  'incomingSeen': incoming,
  'deliveredOutgoingSeen': delivered,
  'outgoing': outgoing,
};

Map<String, Object?> _fixture({
  EngagementChatScope scope = _scope,
  String phase = 'collecting',
  List<Map<String, Object?>> contacts = const [],
}) => <String, Object?>{
  'version': 1,
  'scope': <String, Object?>{
    'profileBinding': scope.profileBinding,
    'consentEpoch': scope.consentEpoch,
    'week': scope.week,
  },
  'phase': phase,
  'contacts': contacts,
};

List<int> _encode(Object? value) => utf8.encode(jsonEncode(value));

void _expectRejectedWithoutMutation(
  EngagementChatWitness witness,
  EngagementChatCapture capture,
  List<int> bytes,
) {
  final before = witness.encodeSnapshot();
  expect(witness.restoreSnapshot(capture, bytes), isFalse);
  expect(witness.encodeSnapshot(), orderedEquals(before));
}

void _assertSuccessorFence(EngagementChatScope successorScope) {
  final witness = EngagementChatWitness(scope: _scope);
  final oldCapture = _capture(witness);
  final oldIntent = _reserve(witness, oldCapture);
  witness.reset(successorScope);
  final current = _capture(witness);
  final currentIntent = _reserve(witness, current);
  witness.admitted(currentIntent);
  witness.admitted(oldIntent);
  witness.cancel(oldIntent);
  _deliver(witness, oldCapture);
  witness.incoming(oldCapture, contactAccount: _contact);
  expect(witness.phase, EngagementChatPhase.collecting);
  expect(
    witness.reserve(
      oldCapture,
      contactAccount: 'peer-stale',
      messageId: 'message-stale',
      generationId: 'generation-stale',
    ),
    isNull,
  );
  witness.incoming(current, contactAccount: _contact);
  _deliver(witness, current);
  expect(witness.phase, EngagementChatPhase.qualifiedPending);
}

void main() {
  for (final order in _orders.entries) {
    test(order.key, () {
      final witness = EngagementChatWitness(scope: _scope);
      final capture = _capture(witness);
      final intent = _reserve(witness, capture);
      for (var index = 0; index < order.value.length; index++) {
        switch (order.value[index]) {
          case 'a':
            witness.admitted(intent);
            break;
          case 'd':
            _deliver(witness, capture);
            break;
          case 'i':
            witness.incoming(capture, contactAccount: _contact);
            break;
        }
        expect(
          witness.phase,
          index == 2
              ? EngagementChatPhase.qualifiedPending
              : EngagementChatPhase.collecting,
          reason: order.key,
        );
      }
    });
  }

  test('E2W-007 silence and incoming alone do not qualify', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    expect(witness.phase, EngagementChatPhase.collecting);
    witness.incoming(capture, contactAccount: _contact);
    expect(witness.phase, EngagementChatPhase.collecting);
  });

  test('E2W-008 admitted outgoing and incoming need delivery', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    witness.admitted(_reserve(witness, capture));
    witness.incoming(capture, contactAccount: _contact);
    expect(witness.phase, EngagementChatPhase.collecting);
  });

  test('E2W-009 admitted delivery without incoming does not qualify', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    witness.admitted(_reserve(witness, capture));
    _deliver(witness, capture);
    expect(witness.phase, EngagementChatPhase.collecting);
  });

  test('E2W-010 unreserved receipt and incoming do not qualify', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    _deliver(witness, capture);
    expect(_contacts(witness), isEmpty);
    witness.incoming(capture, contactAccount: _contact);
    expect(witness.phase, EngagementChatPhase.collecting);
  });

  test('E2W-011 orphan receipt gives no credit to a later send', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    _deliver(witness, capture);
    witness.incoming(capture, contactAccount: _contact);
    final later = _reserve(witness, capture, message: 'message-later');
    witness.admitted(later);
    expect(witness.phase, EngagementChatPhase.collecting);
    _deliver(witness, capture);
    expect(witness.phase, EngagementChatPhase.collecting);
    _deliver(witness, capture, message: 'message-later');
    expect(witness.phase, EngagementChatPhase.qualifiedPending);
  });

  test('E2W-012 delivery must match contact message and generation', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    witness.admitted(_reserve(witness, capture));
    witness.incoming(capture, contactAccount: _contact);
    _deliver(witness, capture, contact: 'peer-foreign');
    _deliver(witness, capture, message: 'message-foreign');
    _deliver(witness, capture, generation: 'generation-stale');
    expect(witness.phase, EngagementChatPhase.collecting);
    _deliver(witness, capture);
    expect(witness.phase, EngagementChatPhase.qualifiedPending);
  });

  test('E2W-013 evidence from different contacts never joins', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    witness.admitted(_reserve(witness, capture));
    _deliver(witness, capture);
    witness.incoming(capture, contactAccount: 'peer-other');
    expect(witness.phase, EngagementChatPhase.collecting);
    witness.incoming(capture, contactAccount: _contact);
    expect(witness.phase, EngagementChatPhase.qualifiedPending);
  });

  test('E2W-014 cancel unadmitted intent removes its early receipt', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    final cancelled = _reserve(witness, capture);
    _deliver(witness, capture);
    witness.incoming(capture, contactAccount: _contact);
    witness.cancel(cancelled);
    final replacement = _reserve(witness, capture);
    witness.admitted(cancelled);
    witness.admitted(replacement);
    expect(witness.phase, EngagementChatPhase.collecting);
    _deliver(witness, capture);
    expect(witness.phase, EngagementChatPhase.qualifiedPending);
  });

  test('E2W-015 cancel cannot erase admitted offline custody', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    final intent = _reserve(witness, capture);
    witness.admitted(intent);
    witness.cancel(intent);
    witness.incoming(capture, contactAccount: _contact);
    _deliver(witness, capture);
    expect(witness.phase, EngagementChatPhase.qualifiedPending);
  });

  test('E2W-016 admitted delivery releases exact references', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    final first = _reserve(witness, capture);
    final second = _reserve(witness, capture, message: 'message-second');
    witness.admitted(first);
    witness.admitted(second);
    _deliver(witness, capture);
    final contacts = _contacts(witness);
    expect(contacts, hasLength(1));
    expect(contacts.single['deliveredOutgoingSeen'], isTrue);
    expect(contacts.single['outgoing'], isEmpty);
    witness.incoming(capture, contactAccount: _contact);
    expect(witness.phase, EngagementChatPhase.qualifiedPending);
  });

  test('E2W-017 qualification clears every private witness', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    witness.admitted(
      _reserve(witness, capture, contact: 'peer-other', message: 'other'),
    );
    _reserve(witness, capture, contact: 'peer-reserved', message: 'reserved');
    _qualify(witness, capture);
    expect(witness.phase, EngagementChatPhase.qualifiedPending);
    expect(_snapshot(witness)['phase'], 'qualified_pending');
    expect(_contacts(witness), isEmpty);
    expect(utf8.decode(witness.encodeSnapshot()), isNot(contains('peer-')));
    expect(utf8.decode(witness.encodeSnapshot()), isNot(contains('message-')));
  });

  test('E2W-018 pending remains until local durable retention', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    _qualify(witness, capture);
    expect(witness.phase, EngagementChatPhase.qualifiedPending);
    witness.confirmRetained(capture);
    expect(witness.phase, EngagementChatPhase.qualifiedRetained);
    expect(_snapshot(witness)['phase'], 'qualified_retained');
    expect(_contacts(witness), isEmpty);
  });

  test('E2W-019 early and old-owner retention acks have no effect', () {
    final witness = EngagementChatWitness(scope: _scope);
    final oldCapture = _capture(witness);
    witness.confirmRetained(oldCapture);
    expect(witness.phase, EngagementChatPhase.collecting);
    witness.reset(_scope);
    final current = _capture(witness);
    _qualify(witness, current);
    witness.confirmRetained(oldCapture);
    expect(witness.phase, EngagementChatPhase.qualifiedPending);
    witness.confirmRetained(current);
    expect(witness.phase, EngagementChatPhase.qualifiedRetained);
  });

  test('E2W-020 profile replacement rejects old callback captures', () {
    _assertSuccessorFence(_otherProfile);
  });

  test('E2W-021 epoch replacement rejects old callback captures', () {
    _assertSuccessorFence(_otherEpoch);
  });

  test('E2W-022 same-scope runtime replacement rejects old captures', () {
    _assertSuccessorFence(_scope);
  });

  test('E2W-023 another reducer cannot use a captured owner', () {
    final first = EngagementChatWitness(scope: _scope);
    final oldCapture = _capture(first);
    final successor = EngagementChatWitness(scope: _scope);
    expect(
      successor.reserve(
        oldCapture,
        contactAccount: _contact,
        messageId: _message,
        generationId: _generation,
      ),
      isNull,
    );
    _qualify(successor, _capture(successor));
    expect(successor.phase, EngagementChatPhase.qualifiedPending);
  });

  test('E2W-024 revoke then new epoch never backfills old facts', () {
    final witness = EngagementChatWitness(scope: _scope);
    final oldCapture = _capture(witness);
    final oldIntent = _reserve(witness, oldCapture);
    witness.admitted(oldIntent);
    witness.incoming(oldCapture, contactAccount: _contact);
    witness.revoke();
    expect(witness.captureOwner(), isNull);
    expect(_contacts(witness), isEmpty);
    witness.reset(_otherEpoch);
    final current = _capture(witness);
    _deliver(witness, oldCapture);
    witness.admitted(oldIntent);
    witness.incoming(current, contactAccount: _contact);
    expect(witness.phase, EngagementChatPhase.collecting);
    witness.admitted(_reserve(witness, current, message: 'fresh'));
    _deliver(witness, current, message: 'fresh');
    expect(witness.phase, EngagementChatPhase.qualifiedPending);
  });

  test('E2W-025 old-week facts are never retimed into a new week', () {
    _assertSuccessorFence(_otherWeek);
  });

  test('E2W-026 matching admitted witnesses survive restart', () {
    final first = EngagementChatWitness(scope: _scope);
    final capture = _capture(first);
    first.admitted(_reserve(first, capture));
    first.incoming(capture, contactAccount: _contact);
    final restored = EngagementChatWitness(scope: _scope);
    final current = _capture(restored);
    expect(restored.restoreSnapshot(current, first.encodeSnapshot()), isTrue);
    expect(restored.phase, EngagementChatPhase.collecting);
    _deliver(restored, current);
    expect(restored.phase, EngagementChatPhase.qualifiedPending);
  });

  test('E2W-027 runtime intent and early delivery never restore', () {
    final first = EngagementChatWitness(scope: _scope);
    final capture = _capture(first);
    _reserve(first, capture);
    _deliver(first, capture);
    first.incoming(capture, contactAccount: _contact);
    final contacts = _contacts(first);
    expect(contacts, hasLength(1));
    expect(contacts.single['incomingSeen'], isTrue);
    expect(contacts.single['deliveredOutgoingSeen'], isFalse);
    expect(contacts.single['outgoing'], isEmpty);
    final restored = EngagementChatWitness(scope: _scope);
    final current = _capture(restored);
    expect(restored.restoreSnapshot(current, first.encodeSnapshot()), isTrue);
    _deliver(restored, current);
    restored.admitted(_reserve(restored, current));
    expect(restored.phase, EngagementChatPhase.collecting);
    _deliver(restored, current);
    expect(restored.phase, EngagementChatPhase.qualifiedPending);
  });

  test('E2W-028 pending tombstone restores without private facts', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    expect(
      witness.restoreSnapshot(
        capture,
        _encode(_fixture(phase: 'qualified_pending')),
      ),
      isTrue,
    );
    expect(witness.phase, EngagementChatPhase.qualifiedPending);
    expect(_contacts(witness), isEmpty);
    witness.confirmRetained(capture);
    expect(witness.phase, EngagementChatPhase.qualifiedRetained);
  });

  test('E2W-029 retained tombstone prevents recollecting after restart', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    expect(
      witness.restoreSnapshot(
        capture,
        _encode(_fixture(phase: 'qualified_retained')),
      ),
      isTrue,
    );
    final ignored = witness.reserve(
      capture,
      contactAccount: 'peer-fresh',
      messageId: 'fresh',
      generationId: _generation,
    );
    if (ignored != null) {
      witness.admitted(ignored);
    }
    _deliver(witness, capture, contact: 'peer-fresh', message: 'fresh');
    witness.incoming(capture, contactAccount: 'peer-fresh');
    expect(witness.phase, EngagementChatPhase.qualifiedRetained);
    expect(_contacts(witness), isEmpty);
  });

  test('E2W-030 old capture cannot restore over a successor', () {
    final witness = EngagementChatWitness(scope: _scope);
    final oldCapture = _capture(witness);
    witness.reset(_otherEpoch);
    final current = _capture(witness);
    witness.incoming(current, contactAccount: 'peer-current');
    _expectRejectedWithoutMutation(
      witness,
      oldCapture,
      _encode(_fixture(phase: 'qualified_pending')),
    );
    expect(
      (_snapshot(witness)['scope'] as Map<String, dynamic>)['consentEpoch'],
      _otherEpoch.consentEpoch,
    );
  });

  test('E2W-031 contact overflow preserves the first 64 witnesses', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    for (var index = 0; index < 64; index++) {
      witness.incoming(capture, contactAccount: 'peer-$index');
    }
    final before = witness.encodeSnapshot();
    witness.incoming(capture, contactAccount: 'peer-overflow');
    expect(witness.encodeSnapshot(), orderedEquals(before));
    final contacts = _contacts(witness);
    expect(contacts, hasLength(64));
    expect(contacts.map((row) => row['account']), contains('peer-0'));
    expect(contacts.map((row) => row['account']), isNot(contains('peer-overflow')));
    witness.admitted(
      _reserve(witness, capture, contact: 'peer-0', message: 'capacity-control'),
    );
    _deliver(witness, capture, contact: 'peer-0', message: 'capacity-control');
    expect(witness.phase, EngagementChatPhase.qualifiedPending);
  });

  test('E2W-032 combined reservations and admitted refs stop at 256', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    final intents = <EngagementChatIntent>[];
    for (var index = 0; index < 256; index++) {
      intents.add(_reserve(witness, capture, message: 'message-$index'));
    }
    witness.admitted(intents.first);
    expect(
      witness.reserve(
        capture,
        contactAccount: 'peer-other',
        messageId: 'overflow',
        generationId: _generation,
      ),
      isNull,
    );
    _deliver(witness, capture, message: 'message-0');
    witness.admitted(intents.last);
    final contacts = _contacts(witness);
    expect(contacts, hasLength(1));
    expect(contacts.single['deliveredOutgoingSeen'], isTrue);
    expect(contacts.single['outgoing'], isEmpty);
    _reserve(witness, capture, contact: 'peer-other', message: 'released');
  });

  test('E2W-033 exactly 256 UTF8 bytes remain admissible', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    final boundary = List.filled(128, 'é').join();
    expect(utf8.encode(boundary), hasLength(256));
    witness.admitted(
      _reserve(
        witness,
        capture,
        contact: boundary,
        message: boundary,
        generation: boundary,
      ),
    );
    final contacts = _contacts(witness);
    expect(contacts, hasLength(1));
    expect(contacts.single['account'], boundary);
    final refs = contacts.single['outgoing'] as List<dynamic>;
    expect(refs, hasLength(1));
    expect((refs.single as Map<String, dynamic>)['message'], boundary);
    expect((refs.single as Map<String, dynamic>)['generation'], boundary);
  });

  test('E2W-034 empty and oversized UTF8 identifiers are refused', () {
    final oversized = List.filled(129, 'é').join();
    for (final invalid in ['', oversized]) {
      for (final field in ['contact', 'message', 'generation']) {
        final witness = EngagementChatWitness(scope: _scope);
        final capture = _capture(witness);
        expect(
          witness.reserve(
            capture,
            contactAccount: field == 'contact' ? invalid : _contact,
            messageId: field == 'message' ? invalid : _message,
            generationId: field == 'generation' ? invalid : _generation,
          ),
          isNull,
        );
        witness.incoming(capture, contactAccount: invalid);
        expect(_contacts(witness), isEmpty);
      }
    }
  });

  test('E2W-035 actual encoded snapshot bytes bound new facts', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    final escapedPrefix = List.filled(251, '"').join();
    final generation = List.filled(256, String.fromCharCode(92)).join();
    final messages = <String>[];
    for (var index = 0; index < 256; index++) {
      final message = escapedPrefix + index.toString().padLeft(5, '0');
      messages.add(message);
      final intent = witness.reserve(
        capture,
        contactAccount: _contact,
        messageId: message,
        generationId: generation,
      );
      if (intent != null) {
        witness.admitted(intent);
      }
      expect(
        witness.encodeSnapshot().length,
        lessThanOrEqualTo(_snapshotByteLimit),
      );
    }
    final contacts = _contacts(witness);
    expect(contacts, hasLength(1));
    final refs = (contacts.single['outgoing'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(refs, isNotEmpty);
    expect(refs.length, lessThan(256));
    expect(
      refs.map((row) => row['message']),
      orderedEquals(messages.take(refs.length)),
    );
  });

  test('E2W-036 malformed and unknown schemas preserve current state', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    witness.incoming(capture, contactAccount: 'peer-current');
    final badVersion = _fixture()..['version'] = 2;
    final unknownTop = _fixture()..['extra'] = true;
    final unknownScope = _fixture();
    (unknownScope['scope'] as Map<String, Object?>)['extra'] = true;
    final unknownContact = _fixture(
      contacts: [_contactRecord(incoming: true)..['extra'] = true],
    );
    final unknownRef = _fixture(
      contacts: [
        _contactRecord(outgoing: [_ref()..['extra'] = true]),
      ],
    );
    for (final bytes in <List<int>>[
      [0xc3, 0x28],
      utf8.encode('{'),
      _encode(null),
      _encode([]),
      _encode(badVersion),
      _encode(unknownTop),
      _encode(unknownScope),
      _encode(unknownContact),
      _encode(unknownRef),
    ]) {
      _expectRejectedWithoutMutation(witness, capture, bytes);
    }
  });

  test('E2W-037 restored scope never changes the current owner', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    witness.incoming(capture, contactAccount: 'peer-current');
    for (final foreign in [_otherProfile, _otherEpoch, _otherWeek]) {
      _expectRejectedWithoutMutation(
        witness,
        capture,
        _encode(_fixture(scope: foreign, phase: 'qualified_pending')),
      );
    }
    final scope = _snapshot(witness)['scope'] as Map<String, dynamic>;
    expect(scope['profileBinding'], _scope.profileBinding);
    expect(scope['consentEpoch'], _scope.consentEpoch);
    expect(scope['week'], _scope.week);
  });

  test('E2W-038 duplicate contacts and exact references are rejected', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    for (final fixture in [
      _fixture(
        contacts: [
          _contactRecord(incoming: true),
          _contactRecord(outgoing: [_ref()]),
        ],
      ),
      _fixture(
        contacts: [
          _contactRecord(outgoing: [_ref(), _ref()]),
        ],
      ),
    ]) {
      _expectRejectedWithoutMutation(witness, capture, _encode(fixture));
    }
  });

  test('E2W-039 restored contact and reference counts are bounded', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    final tooManyContacts = _fixture(
      contacts: [
        for (var index = 0; index < 65; index++)
          _contactRecord(account: 'peer-$index', incoming: true),
      ],
    );
    final tooManyRefs = _fixture(
      contacts: [
        _contactRecord(
          outgoing: [
            for (var index = 0; index < 257; index++)
              _ref(message: 'message-$index'),
          ],
        ),
      ],
    );
    for (final fixture in [tooManyContacts, tooManyRefs]) {
      _expectRejectedWithoutMutation(witness, capture, _encode(fixture));
    }
  });

  test('E2W-040 incoherent phases and contact states are rejected', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    for (final fixture in [
      _fixture(phase: 'unknown'),
      _fixture(
        phase: 'qualified_pending',
        contacts: [_contactRecord(incoming: true)],
      ),
      _fixture(
        phase: 'qualified_retained',
        contacts: [_contactRecord(outgoing: [_ref()])],
      ),
      _fixture(contacts: [_contactRecord(incoming: true, delivered: true)]),
      _fixture(
        contacts: [
          _contactRecord(delivered: true, outgoing: [_ref()]),
        ],
      ),
    ]) {
      _expectRejectedWithoutMutation(witness, capture, _encode(fixture));
    }
  });

  test('E2W-041 actual input byte cap applies before JSON acceptance', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    final valid = _encode(_fixture());
    final oversized = [
      ...valid,
      ...List.filled(_snapshotByteLimit + 1 - valid.length, 32),
    ];
    expect(oversized, hasLength(_snapshotByteLimit + 1));
    _expectRejectedWithoutMutation(witness, capture, oversized);
  });

  test('E2W-042 retained week never recollects duplicate evidence', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    _qualify(witness, capture);
    witness.confirmRetained(capture);
    final retained = witness.encodeSnapshot();
    _deliver(witness, capture);
    witness.incoming(capture, contactAccount: _contact);
    final ignored = witness.reserve(
      capture,
      contactAccount: 'peer-new',
      messageId: 'message-new',
      generationId: _generation,
    );
    if (ignored != null) {
      witness.admitted(ignored);
    }
    _deliver(witness, capture, contact: 'peer-new', message: 'message-new');
    witness.incoming(capture, contactAccount: 'peer-new');
    witness.confirmRetained(capture);
    expect(witness.phase, EngagementChatPhase.qualifiedRetained);
    expect(witness.encodeSnapshot(), orderedEquals(retained));
    expect(_contacts(witness), isEmpty);
  });

  test('E2W-043 cancelled intent cannot confirm its replacement', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    final cancelled = _reserve(witness, capture);
    witness.cancel(cancelled);
    final replacement = _reserve(witness, capture);
    witness.incoming(capture, contactAccount: _contact);
    _deliver(witness, capture);
    witness.admitted(cancelled);
    expect(witness.phase, EngagementChatPhase.collecting);
    witness.admitted(replacement);
    expect(witness.phase, EngagementChatPhase.qualifiedPending);
  });

  test('E2W-044 strict codec rejects malformed field types', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    witness.incoming(capture, contactAccount: 'peer-current');
    final badVersion = _fixture()..['version'] = '1';
    final badPhase = _fixture()..['phase'] = 1;
    final badContacts = _fixture()..['contacts'] = <String, Object?>{};
    final badEpoch = _fixture();
    (badEpoch['scope'] as Map<String, Object?>)['consentEpoch'] = '7';
    final badWeek = _fixture();
    (badWeek['scope'] as Map<String, Object?>)['week'] = 47;
    final badBinding = _fixture();
    (badBinding['scope'] as Map<String, Object?>)['profileBinding'] = null;
    for (final fixture in [
      badVersion,
      badPhase,
      badContacts,
      badEpoch,
      badWeek,
      badBinding,
      _fixture(contacts: [_contactRecord()..['account'] = 3]),
      _fixture(contacts: [_contactRecord()..['incomingSeen'] = 1]),
      _fixture(contacts: [_contactRecord()..['deliveredOutgoingSeen'] = 'yes']),
      _fixture(contacts: [_contactRecord()..['outgoing'] = false]),
      _fixture(
        contacts: [
          _contactRecord(outgoing: [_ref()..['message'] = 9]),
        ],
      ),
      _fixture(
        contacts: [
          _contactRecord(outgoing: [_ref()..['generation'] = true]),
        ],
      ),
    ]) {
      _expectRejectedWithoutMutation(witness, capture, _encode(fixture));
    }
  });

  test('E2W-045 restored identifiers obey the same UTF8 bound', () {
    final witness = EngagementChatWitness(scope: _scope);
    final capture = _capture(witness);
    for (final invalid in ['', List.filled(129, 'é').join()]) {
      for (final fixture in [
        _fixture(contacts: [_contactRecord(account: invalid, incoming: true)]),
        _fixture(
          contacts: [
            _contactRecord(outgoing: [_ref(message: invalid)]),
          ],
        ),
        _fixture(
          contacts: [
            _contactRecord(outgoing: [_ref(generation: invalid)]),
          ],
        ),
      ]) {
        _expectRejectedWithoutMutation(witness, capture, _encode(fixture));
      }
    }
  });
}
