import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/production_group_local_media_delete_criteria.dart';

const _roles = ['alice', 'bob', 'charlie'];
const _run = 'local-media-delete-fixture';

Map<String, Object?> _proof() {
  final peers = {for (final role in _roles) role: '$role-account'};
  final texts = groupLocalMediaDeleteTexts(_run);
  Map<String, Object?> row(String key, String role) => {
    'messageId': 'logical-$key',
    'groupId': 'fixture-group',
    'text': texts[key]!.text,
    'senderPeerId': peers[texts[key]!.role],
    'isIncoming': role != texts[key]!.role,
    'status': 'sent',
    'timestamp': DateTime.utc(2026, 10, 23)
        .add(Duration(seconds: texts.keys.toList().indexOf(key)))
        .toIso8601String(),
    'keyEpoch': 1,
    'mediaAttachmentCount': texts[key]!.media ? 1 : 0,
  };
  Map<String, Object?> snapshot(String phase, String role) => {
    'runId': _run,
    'role': role,
    'scenario': 'de002',
    'peerId': peers[role],
    'groupId': 'fixture-group',
    'groupConfigStateHash': 'fixture-config',
    'keyEpoch': 1,
    'lastMembershipEventAt': '2026-10-23T00:00:00.000Z',
    'lifecycle': 'resumed',
    'invocationNonce': '$role-${phase == 'afterRestart' ? 'second' : 'first'}',
    'memberPeerIds': peers.values.toList(),
    'configMemberPeerIds': peers.values.toList(),
    'watched': {
      for (final key in texts.keys)
        key: [
          if (!(phase != 'beforeDelete' && role == 'bob' && key == 'target'))
            row(key, role),
        ],
    },
  };
  return {
    'runId': _run,
    'runtimeScenario': groupLocalMediaDeleteRuntime,
    'emulatorTriple': true,
    'peers': peers,
    'fixtureSha256': 'a' * 64,
    'initialNonces': {for (final role in _roles) role: '$role-first'},
    'finalNonces': {for (final role in _roles) role: '$role-second'},
    'ownedKills': {
      for (final role in _roles) role: {'verifiedUidKill': true},
    },
    for (final phase in ['beforeDelete', 'afterDelete', 'afterRestart'])
      phase: {for (final role in _roles) role: snapshot(phase, role)},
    'flows': [
      'create',
      'accept-bob',
      'accept-charlie',
      'send-target',
      'send-marker',
      'send-preserved',
      for (final role in _roles) ...[
        'before-target-$role',
        'before-preserved-$role',
      ],
      'delete-target-bob',
      for (final phase in ['afterDelete', 'afterRestart']) ...[
        if (phase == 'afterRestart')
          for (final role in _roles) 'open-afterRestart-$role',
        for (final role in _roles) ...[
          if (role != 'bob') '$phase-target-$role',
          '$phase-preserved-$role',
          if (role == 'bob') '$phase-absent-bob',
        ],
      ],
    ],
  };
}

Map _snapshot(Map proof, String phase, String role) =>
    (proof[phase] as Map)[role] as Map;
List _rows(Map proof, String phase, String role, String key) =>
    (_snapshot(proof, phase, role)['watched'] as Map)[key] as List;

void main() {
  test(
    'local received-image deletion preserves both other copies and unrelated content',
    () {
      expect(validateProductionGroupLocalMediaDelete(_proof()), isEmpty);
    },
  );
  test('a target still present locally after confirmation is rejected', () {
    final p = _proof();
    _rows(p, 'afterDelete', 'bob', 'target').add(
      Map<String, Object?>.from(
        _rows(p, 'beforeDelete', 'bob', 'target').single as Map,
      ),
    );
    expect(validateProductionGroupLocalMediaDelete(p), isNotEmpty);
  });
  test('a locally deleted target must not return after relaunch', () {
    final p = _proof();
    _rows(p, 'afterRestart', 'bob', 'target').add(
      Map<String, Object?>.from(
        _rows(p, 'beforeDelete', 'bob', 'target').single as Map,
      ),
    );
    expect(validateProductionGroupLocalMediaDelete(p), isNotEmpty);
  });
  test(
    'remote deletion at either other member violates delete-for-me locality',
    () {
      for (final role in ['alice', 'charlie']) {
        final p = _proof();
        _rows(p, 'afterRestart', role, 'target').clear();
        expect(
          validateProductionGroupLocalMediaDelete(p),
          isNotEmpty,
          reason: role,
        );
      }
    },
  );
  test(
    'preserved text and second image must remain after both deletion and restart',
    () {
      for (final phase in ['afterDelete', 'afterRestart']) {
        for (final key in ['marker', 'preserved']) {
          final p = _proof();
          _rows(p, phase, 'bob', key).clear();
          expect(
            validateProductionGroupLocalMediaDelete(p),
            isNotEmpty,
            reason: '$phase/$key',
          );
        }
      }
    },
  );
  test('a present caption without its media attachment cannot pass', () {
    final p = _proof();
    (_rows(p, 'afterRestart', 'bob', 'preserved').single
            as Map)['mediaAttachmentCount'] =
        0;
    expect(validateProductionGroupLocalMediaDelete(p), isNotEmpty);
  });
  test('replacement, duplicate and changed-source rows are rejected', () {
    for (final entry in <String, Object?>{
      'messageId': 'replacement',
      'senderPeerId': 'another-author',
      'isIncoming': false,
      'timestamp': '2026-10-24T00:00:00Z',
      'keyEpoch': 2,
    }.entries) {
      final p = _proof();
      (_rows(p, 'afterRestart', 'bob', 'preserved').single as Map)[entry.key] =
          entry.value;
      expect(
        validateProductionGroupLocalMediaDelete(p),
        isNotEmpty,
        reason: entry.key,
      );
    }
    final duplicate = _proof();
    final rows = _rows(duplicate, 'afterDelete', 'charlie', 'target');
    rows.add(Map<String, Object?>.from(rows.single as Map));
    expect(validateProductionGroupLocalMediaDelete(duplicate), isNotEmpty);
  });
  test(
    'the target must be an actually received image before local deletion',
    () {
      for (final entry in <String, Object?>{
        'isIncoming': false,
        'mediaAttachmentCount': 0,
      }.entries) {
        final p = _proof();
        (_rows(p, 'beforeDelete', 'bob', 'target').single as Map)[entry.key] =
            entry.value;
        expect(
          validateProductionGroupLocalMediaDelete(p),
          isNotEmpty,
          reason: entry.key,
        );
      }
    },
  );
  test(
    'same text under another group or altered membership/configuration fails',
    () {
      for (final entry in <String, Object?>{
        'groupId': 'other-group',
        'groupConfigStateHash': 'other-config',
        'memberPeerIds': ['alice-account', 'bob-account'],
        'configMemberPeerIds': ['alice-account', 'bob-account'],
        'keyEpoch': 2,
      }.entries) {
        final p = _proof();
        _snapshot(p, 'afterRestart', 'bob')[entry.key] = entry.value;
        expect(
          validateProductionGroupLocalMediaDelete(p),
          isNotEmpty,
          reason: entry.key,
        );
      }
    },
  );
  test(
    'stale process observations and missing verified deaths cannot prove persistence',
    () {
      final stale = _proof();
      _snapshot(stale, 'afterRestart', 'bob')['invocationNonce'] = 'bob-first';
      expect(validateProductionGroupLocalMediaDelete(stale), isNotEmpty);
      final alive = _proof();
      ((alive['ownedKills'] as Map)['charlie'] as Map)['verifiedUidKill'] =
          false;
      expect(validateProductionGroupLocalMediaDelete(alive), isNotEmpty);
      final old = _proof();
      (old['finalNonces'] as Map)['bob'] = 'bob-first';
      expect(validateProductionGroupLocalMediaDelete(old), isNotEmpty);
    },
  );
  test(
    'missing actual confirmation or preserved-media viewer receipt fails',
    () {
      for (final label in ['delete-target-bob', 'afterRestart-preserved-bob']) {
        final p = _proof();
        (p['flows'] as List).remove(label);
        expect(
          validateProductionGroupLocalMediaDelete(p),
          isNotEmpty,
          reason: label,
        );
      }
    },
  );
  test('selector anchors cannot claim a different real message order', () {
    final p = _proof();
    final target = _rows(p, 'beforeDelete', 'alice', 'target').single as Map;
    final marker = _rows(p, 'beforeDelete', 'alice', 'marker').single as Map;
    marker['timestamp'] = target['timestamp'];
    expect(validateProductionGroupLocalMediaDelete(p), isNotEmpty);
  });
}
