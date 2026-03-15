import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_envelope.dart';

void main() {
  test('parses a renderable original snapshot from post_pass', () {
    final envelope = PostPassEnvelope.fromJson(
      jsonEncode(_postPassJson()),
    );

    expect(envelope, isNotNull);
    expect(envelope!.postId, 'post-1');
    expect(envelope.passId, 'pass-1');
    expect(envelope.passerPeerId, 'peer-james');
    expect(envelope.originalSnapshot.authorPeerId, 'peer-sarah');
    expect(envelope.originalSnapshot.audience.kind, PostAudienceKind.peopleNearby);
    expect(envelope.originalSnapshot.audience.radiusM, 2000);
    expect(envelope.toPostModel().visibleAt, '2026-03-15T11:15:00.000Z');
  });

  test('rejects post_pass when the original snapshot is not renderable', () {
    final json = _postPassJson();
    final payload = json['payload'] as Map<String, Object?>;
    payload.remove('original_snapshot');

    final envelope = PostPassEnvelope.fromJson(jsonEncode(json));

    expect(envelope, isNull);
  });

  test('rejects post_pass when the original snapshot audience is pick_people', () {
    final json = _postPassJson();
    final payload = json['payload'] as Map<String, Object?>;
    final snapshot = payload['original_snapshot'] as Map<String, Object?>;
    snapshot['audience'] = <String, Object?>{
      'kind': 'pick_people',
      'scope_label': 'Shared with you',
    };

    final envelope = PostPassEnvelope.fromJson(jsonEncode(json));

    expect(envelope, isNull);
  });
}

Map<String, Object?> _postPassJson() {
  return <String, Object?>{
    'type': 'post_pass',
    'version': '1',
    'event_id': 'evt-pass-1',
    'created_at': '2026-03-15T11:15:00.000Z',
    'sender_peer_id': 'peer-james',
    'payload': <String, Object?>{
      'pass_id': 'pass-1',
      'post_id': 'post-1',
      'passed_at': '2026-03-15T11:15:00.000Z',
      'passer_peer_id': 'peer-james',
      'passer_username': 'James',
      'original_snapshot': <String, Object?>{
        'post_id': 'post-1',
        'author_peer_id': 'peer-sarah',
        'author_username': 'Sarah',
        'post_created_at': '2026-03-15T10:15:30.000Z',
        'audience': <String, Object?>{
          'kind': 'people_nearby',
          'radius_m': 2000,
          'scope_label': 'Shared nearby',
        },
        'text': 'Lost dog near Neckar bridge.',
        'media_kind': 'none',
        'media': const <Object?>[],
        'keep_available': false,
        'expires_at': '2026-03-18T10:15:30.000Z',
      },
    },
  };
}
