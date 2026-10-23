import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/production_direct_actions_criteria.dart';

const _run = 'direct-actions-fixture';

Map<String, Object?> _proof() {
  final texts = directActionsTexts(_run);
  final patterns = directActionsPatterns(_run);
  final peers = {'alice': 'alice-account', 'bob': 'bob-account'};
  final ui = <String, Object?>{};
  void receipt(String label, String name, Map<String, String> values) {
    ui[label] = {
      'path': 'flow-$label.json',
      'flow': name,
      'values': values,
      'receipt': {
        'status': 'PASS',
        'exit_status': 0,
        'flows': [name],
      },
    };
  }

  Map<String, String> send(String key) => {
    'MESSAGE': texts[key]!,
    'MESSAGE_PATTERN': RegExp.escape(texts[key]!),
  };
  receipt('send-parent', 'production_direct_send', send('parent'));
  receipt('send-deletion-target', 'production_direct_send', send('deleted'));
  receipt('reply-bob', 'production_catalog_quote_reply', {
    'PARENT_PATTERN': RegExp.escape(texts['parent']!),
    ...send('reply'),
  });
  for (final action in ['add', 'remove']) {
    receipt('reaction-$action', 'production_direct_reaction_toggle', {
      'MESSAGE_ID': 'parent-id',
    });
  }
  receipt('edit-bob', 'production_direct_edit', {
    'MESSAGE_ID': 'reply-id',
    'EDITED_MESSAGE': texts['edited']!,
    'EDITED_PATTERN': RegExp.escape(texts['edited']!),
  });
  receipt('delete-alice', 'production_direct_delete', {
    'MESSAGE_PATTERN': RegExp.escape(texts['deleted']!),
  });
  for (final role in ['alice', 'bob']) {
    for (final prefix in ['open', 'reopen']) {
      receipt('$prefix-$role', 'production_direct_open', {
        'PEER_ID': peers[role == 'alice' ? 'bob' : 'alice']!,
      });
    }
    void visible(String label, String yes, String no) => receipt(
      label,
      'production_direct_assert_action',
      {'VISIBLE_PATTERN': yes, 'ABSENT_PATTERN': no},
    );
    visible('quote-$role', patterns['quote']!, 'NEVER_PRESENT_SENTINEL_$_run');
    receipt(
      'reaction-added-$role',
      'production_direct_assert_reaction_present',
      {'MESSAGE_ID': 'parent-id'},
    );
    receipt(
      'reaction-removed-$role',
      'production_direct_assert_reaction_absent',
      {'MESSAGE_ID': 'parent-id'},
    );
    visible(
      'edited-$role',
      patterns['editedQuote']!,
      RegExp.escape(texts['reply']!),
    );
    for (final phase in ['deleted', 'restarted']) {
      visible('$phase-$role', patterns['editedQuote']!, patterns['deleted']!);
      visible(
        '$phase-placeholder-$role',
        'This message was deleted',
        patterns['deleted']!,
      );
      receipt(
        '$phase-reaction-removed-$role',
        'production_direct_assert_reaction_absent',
        {'MESSAGE_ID': 'parent-id'},
      );
    }
  }
  Map<String, Object?> snapshot(String role, String phase) {
    final deleted = phase == 'deleted' || phase == 'restarted';
    const tombstoneAt = '2026-10-23T14:00:10.000Z';
    final other = peers[role == 'alice' ? 'bob' : 'alice'];
    return {
      'observedRunId': _run,
      'observedRole': role,
      'observedNonce': '$role-${phase == 'restarted' ? 'second' : 'first'}',
      'messages': <Map<String, Object?>>[
        for (final key in ['parent', 'reply', 'deleted'])
          {
            'id': '$key-id',
            'text': deleted && key == 'deleted'
                ? ''
                : texts[key == 'reply' && phase != 'quoted' ? 'edited' : key],
            'timestamp':
                '2026-10-23T14:00:0${key == 'parent'
                    ? 1
                    : key == 'reply'
                    ? 2
                    : 3}.000Z',
            'lane': 'direct',
            'conversationId': other,
            'incoming': key == 'reply' ? role == 'alice' : role == 'bob',
            'deletedAt': key == 'deleted' && deleted ? tombstoneAt : null,
          },
      ],
      'tombstones': [
        if (deleted)
          {
            'id': 'deleted-id',
            'contactPeerId': other,
            'deletedAt': tombstoneAt,
          },
      ],
    };
  }

  return {
    'runId': _run,
    'runtimeScenario': directActionsRuntime,
    'emulatorPair': true,
    'peers': peers,
    'ui': ui,
    'nonces': {
      for (final role in ['alice', 'bob'])
        role: ['$role-first', '$role-second'],
    },
    'ownedKills': {
      for (final role in ['alice', 'bob']) role: {'verifiedUidKill': true},
    },
    'phases': {
      for (final phase in ['quoted', 'edited', 'deleted', 'restarted'])
        phase: {
          for (final role in ['alice', 'bob']) role: snapshot(role, phase),
        },
    },
  };
}

Map _phase(Map proof, String phase, String role) =>
    (proof['phases'] as Map)[phase][role] as Map;

void main() {
  test(
    'complete rendered actions and same-ID restart evidence satisfy DC-006',
    () {
      expect(validateProductionDirectActions(_proof()), isEmpty);
    },
  );
  test('delete-only routing proof cannot replace receiver quote rendering', () {
    final proof = _proof();
    (proof['ui'] as Map).remove('quote-bob');
    expect(validateProductionDirectActions(proof), isNotEmpty);
  });
  test('reaction on another row is not evidence for this parent', () {
    final proof = _proof();
    (((proof['ui'] as Map)['reaction-add'] as Map)['values']
            as Map)['MESSAGE_ID'] =
        'reply-id';
    expect(validateProductionDirectActions(proof), isNotEmpty);
  });
  test('retaining only optimistic sender reaction removal is insufficient', () {
    final proof = _proof();
    ((((proof['ui'] as Map)['reaction-removed-bob'] as Map)['receipt'])
            as Map)['status'] =
        'FAIL';
    expect(validateProductionDirectActions(proof), isNotEmpty);
  });
  test(
    'receiver reaction observation must belong to the actual parent row',
    () {
      final proof = _proof();
      (((proof['ui'] as Map)['reaction-added-bob'] as Map)['values']
              as Map)['MESSAGE_ID'] =
          'reply-id';
      expect(validateProductionDirectActions(proof), isNotEmpty);
    },
  );
  test('reaction removal must remain absent after the receiver restart', () {
    final proof = _proof();
    (proof['ui'] as Map).remove('restarted-reaction-removed-bob');
    expect(validateProductionDirectActions(proof), isNotEmpty);
  });
  test('an edit under a replacement logical identity is rejected', () {
    final proof = _proof();
    ((_phase(proof, 'edited', 'alice')['messages'] as List)[1] as Map)['id'] =
        'replacement-id';
    expect(validateProductionDirectActions(proof), isNotEmpty);
  });
  test(
    'matching edited text without an edited quote UI receipt is incomplete',
    () {
      final proof = _proof();
      (proof['ui'] as Map).remove('edited-alice');
      expect(validateProductionDirectActions(proof), isNotEmpty);
    },
  );
  test(
    'receiver deletion needs the same committed tombstone, not just hidden text',
    () {
      final proof = _proof();
      _phase(proof, 'deleted', 'bob')['tombstones'] = <Map<String, Object?>>[];
      expect(validateProductionDirectActions(proof), isNotEmpty);
    },
  );
  test(
    'a duplicate row after replay fails despite complete expected texts',
    () {
      final proof = _proof();
      final rows = _phase(proof, 'restarted', 'bob')['messages'] as List;
      rows.add(Map<String, Object?>.from(rows.first as Map));
      expect(validateProductionDirectActions(proof), isNotEmpty);
    },
  );
  test('deleted-row resurrection and stale replay invocation are rejected', () {
    final proof = _proof();
    ((_phase(proof, 'restarted', 'bob')['messages'] as List)[2]
            as Map)['deletedAt'] =
        null;
    expect(validateProductionDirectActions(proof), isNotEmpty);
    final stale = _proof();
    _phase(stale, 'restarted', 'bob')['observedNonce'] = 'bob-first';
    expect(validateProductionDirectActions(stale), isNotEmpty);
  });
}
