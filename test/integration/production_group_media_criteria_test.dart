import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_media_criteria.dart';

Map<String, dynamic> _pass(String name) => {
  'pass': name,
  'rows': {
    'runId': 'run',
    'role': 'bob',
    'groupId': 'report89-run',
    'groupPresent': true,
    'lifecycle': 'resumed',
    'attachments': [
      for (final (id, type) in [
        ('i-video', 'video'),
        ('i-voice', 'audio'),
        ('o-video', 'video'),
        ('o-voice', 'audio'),
      ])
        {
          'id': id,
          'mediaType': type,
          'downloadStatus': 'done',
          'fileExists': true,
        },
    ],
    'tree': {
      'scopedToConversation': 1,
      'videoThumbnailOverlays': 2,
      'audioPlayerWidgets': 2,
      'playingAudioPlayers': 0,
      'videoPlayers': 0,
      'incomingText': 1,
      'outgoingText': 1,
      'durationLabels': 2,
      'videoLoadErrors': 0,
    },
  },
  'voice': {'playingObserved': true, 'seenAtMs': 400},
  'viewer': {
    'tree': {'videoPlayers': 1, 'videoLoadErrors': 0},
  },
};

Map<String, dynamic> fixture() => {
  'runId': 'run',
  'groupId': 'report89-run',
  'peers': {'alice': 'a', 'bob': 'b'},
  'passes': [_pass('initial'), _pass('reopened')],
  'flows': [
    for (final p in productionMediaPasses) ...[
      '$p-open',
      '$p-play-voice',
      '$p-open-video',
      '$p-viewer-back',
    ],
  ],
  'cases': [
    {'id': 'NEW_MEMBER_MEDIA', 'status': 'PASS'},
  ],
};

Map<String, dynamic> _copy(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;

void main() {
  test('both passes render and play the new member media', () {
    expect(validateProductionGroupMedia(fixture()), isEmpty);
  });

  Map pass(Map p, int i) => (p['passes'] as List)[i] as Map;
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'one thumbnail missing': (p) =>
        pass(p, 0)['rows']['tree']['videoThumbnailOverlays'] = 1,
    'one voice player missing': (p) =>
        pass(p, 1)['rows']['tree']['audioPlayerWidgets'] = 1,
    'duration unknown': (p) =>
        pass(p, 0)['rows']['tree']['durationLabels'] = 0,
    'incoming text missing': (p) =>
        pass(p, 1)['rows']['tree']['incomingText'] = 0,
    'voice never played': (p) =>
        pass(p, 0)['voice']['playingObserved'] = false,
    'video load error': (p) =>
        pass(p, 1)['viewer']['tree']['videoLoadErrors'] = 1,
    'video viewer never opened': (p) =>
        pass(p, 0)['viewer']['tree']['videoPlayers'] = 0,
    'attachment file lost': (p) =>
        ((pass(p, 1)['rows']['attachments'] as List)[2] as Map)['fileExists'] =
            false,
    'group missing': (p) => pass(p, 0)['rows']['groupPresent'] = false,
    'counted outside the conversation': (p) =>
        pass(p, 0)['rows']['tree']['scopedToConversation'] = 0,
    'background lifecycle': (p) => pass(p, 1)['rows']['lifecycle'] = 'paused',
    'reopen pass missing': (p) => (p['passes'] as List).removeLast(),
    'foreign group': (p) => p['groupId'] = 'report89-other',
    'skipped flow': (p) => (p['flows'] as List).remove('reopened-play-voice'),
    'missing case': (p) => (p['cases'] as List).clear(),
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = _copy(fixture());
      entry.value(proof);
      expect(validateProductionGroupMedia(proof), isNotEmpty);
    });
  }
}
