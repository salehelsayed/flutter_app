import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_private_media_criteria.dart';

Map<String, dynamic> fixture() {
  const run = 'private-test';
  final proof = <String, dynamic>{
    'runId': run,
    'peers': {'alice': 'a', 'bob': 'b'},
    for (final key in [
      'protectedWindow',
      'senderBeforeWindow',
      'senderViewingWindow',
      'senderAfterWindow',
    ])
      key: {
        'role': key == 'protectedWindow' ? 'bob' : 'alice',
        'package': 'com.mknoon.sims.connectivity',
        'ownedWindowCount': 1,
        'secure': key == 'protectedWindow' || key == 'senderViewingWindow',
        'visible': true,
      },
    'recipientBeforeNonce': 'recipient-old',
    'recipientAfterNonce': 'recipient-new',
    'beforeNonce': 'old',
    'afterNonce': 'new',
    'claims': {'remoteRevocation': false, 'accountWideConsumption': false},
  };
  for (final stage in [
    'projection',
    'deleted',
    'incomingViewing',
    'incomingConsumed',
    'incomingColdConsumed',
    'incomingRefused',
    'available',
    'viewing',
    'consumed',
    'coldConsumed',
    'refused',
  ]) {
    final bob =
        stage == 'projection' ||
        stage == 'deleted' ||
        stage.startsWith('incoming');
    final names = bob
        ? ['outgoing', 'incoming', 'terminal', 'protected_thumbnail']
        : ['sender_pending'];
    final rows = <Map<String, dynamic>>[];
    final visuals = <Map<String, dynamic>>[];
    for (final name in names) {
      final id = 'private-$run-$name';
      final removed = name == 'terminal' && stage != 'projection';
      final clean = name == 'incoming'
          ? [
              'incomingConsumed',
              'incomingColdConsumed',
              'incomingRefused',
            ].contains(stage)
          : ['consumed', 'coldConsumed', 'refused'].contains(stage);
      final viewing = stage == 'viewing' || stage == 'incomingViewing';
      rows.add({
        'id': id,
        'name': name,
        'storageOwner': name == 'incoming' || name == 'terminal'
            ? 'canonical_incoming'
            : 'pending_upload',
        'sql': [
          {
            'id': id,
            'is_incoming': name == 'incoming' || name == 'terminal' ? 1 : 0,
            'private_media_policy_version': 1,
            'private_media_mode':
                {'outgoing', 'protected_thumbnail'}.contains(name)
                ? 'protected'
                : 'view_once',
            'private_media_state': name == 'terminal' || clean
                ? 'consumed'
                : viewing && (name == 'incoming' || name == 'sender_pending')
                ? 'viewing'
                : 'available',
            'hidden_at': removed ? 'time' : null,
            'deleted_at': null,
          },
        ],
        'attachments': clean
            ? []
            : [
                {
                  'id': '$id-attachment',
                  'message_id': id,
                  'owner_lane': 'direct',
                  'download_status': name == 'sender_pending'
                      ? 'upload_pending'
                      : 'done',
                  'exactOwnedPath': true,
                  'size': 68,
                },
              ],
        'repositoryAttachmentCount': clean ? 0 : 1,
        'fileExists': !clean && name != 'outgoing',
        'fileSha256': 'hash',
        'fixtureSha256': 'hash',
      });
      final key = name == 'protected_thumbnail'
          ? 'private-media-thumbnail-tile'
          : name == 'terminal'
          ? 'private-terminal-view-once-consumed-summary'
          : 'private-media-card-visual';
      visuals.add({
        'id': id,
        'rows': removed ? 0 : 1,
        'letterCards': 1,
        'slots': 1,
        'decoratedBodies': 1,
        'slotsInsideBodies': 1,
        'slotSizes': [
          {'width': 100, 'height': 150},
        ],
        'imageWidgets': name == 'protected_thumbnail' ? 2 : 0,
        'decorationImages': 0,
        'actions': [
          {'key': key, 'width': 100, 'height': name == 'outgoing' ? 88 : 150},
        ],
      });
    }
    proof[stage] = {
      'runId': run,
      'role': bob ? 'bob' : 'alice',
      'peerId': bob ? 'a' : 'b',
      'lifecycle': 'resumed',
      'rows': rows,
      'projection': {
        'conversations': stage == 'viewing' || stage == 'incomingViewing'
            ? 0
            : 1,
        'viewers': stage == 'viewing' || stage == 'incomingViewing' ? 1 : 0,
        'rows': visuals,
      },
      'committed': [
        for (final state in ['opening', 'viewing', 'consumed'])
          {
            'messageId': 'private-$run-${bob ? 'incoming' : 'sender_pending'}',
            'state': state,
            'source': 'production-repository-committed-change',
            'observedAtMicros':
                ['opening', 'viewing', 'consumed'].indexOf(state) + 1,
          },
      ],
    };
  }
  // Decode gives every nested container a JSON-like dynamic value type, so
  // negative probes exercise the oracle rather than Dart collection casts.
  return jsonDecode(jsonEncode(proof)) as Map<String, dynamic>;
}

void main() {
  test(
    'native private window observation rejects another application SECURE flag',
    () {
      const owned =
          '  Window #8 Window{abc u0 com.mknoon.sims.connectivity/com.mknoon.app.MainActivity}:\n    fl=LAYOUT_IN_SCREEN\n    mHasSurface=true\n    isOnScreen=true\n';
      const foreign =
          '  Window #9 Window{xyz u0 other/Activity}:\n    fl=SECURE\n    mHasSurface=true\n    isOnScreen=true\n';
      expect(observeProductionPrivateWindow(owned + foreign)['secure'], false);
      expect(
        observeProductionPrivateWindow(
          owned.replaceFirst('fl=', 'fl=SECURE ') + foreign,
        )['secure'],
        true,
      );
      expect(observeProductionPrivateWindow(owned + owned)['secure'], false);
      expect(observeProductionPrivateWindow(foreign)['ownedWindowCount'], 0);
    },
  );

  test(
    'accepts bound production projection, committed lifecycle and cold refusal',
    () {
      expect(validateProductionPrivateMedia(fixture()), isEmpty);
    },
  );
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'recipient stage missing': (p) => p.remove('incomingConsumed'),
    'recipient wrong storage root': (p) =>
        p['deleted']['rows'][1]['storageOwner'] = 'pending_upload',
    'recipient corrupt bytes': (p) =>
        p['deleted']['rows'][1]['fileSha256'] = 'bad',
    'recipient wrong attachment path': (p) =>
        p['deleted']['rows'][1]['attachments'][0]['exactOwnedPath'] = false,
    'recipient not viewing': (p) =>
        p['incomingViewing']['rows'][1]['sql'][0]['private_media_state'] =
            'available',
    'recipient no viewer': (p) =>
        p['incomingViewing']['projection']['viewers'] = 0,
    'recipient file retained': (p) =>
        p['incomingConsumed']['rows'][1]['fileExists'] = true,
    'recipient attachment retained': (p) =>
        p['incomingConsumed']['rows'][1]['attachments'] = [{}],
    'recipient mutation omitted': (p) =>
        p['incomingConsumed']['committed'].removeAt(0),
    'recipient cold state lost': (p) =>
        p['incomingColdConsumed']['rows'][1]['sql'][0]['private_media_state'] =
            'available',
    'recipient consumed reopened': (p) =>
        p['incomingRefused']['projection']['viewers'] = 1,
    'recipient stale process': (p) =>
        p['recipientAfterNonce'] = p['recipientBeforeNonce'],
    'sender guard missing': (p) => p['senderViewingWindow']['secure'] = false,
    'sender guard not released': (p) => p['senderAfterWindow']['secure'] = true,
    'sender guard preexisting': (p) => p['senderBeforeWindow']['secure'] = true,
    'sender foreign guard role': (p) =>
        p['senderViewingWindow']['role'] = 'bob',
    'unavailable outgoing open action': (p) =>
        p['projection']['projection']['rows'][0]['actions'].add({
          'key': 'private-media-open',
          'width': 100,
          'height': 40,
        }),
    'missing native window protection': (p) =>
        p['protectedWindow']['secure'] = false,
    'foreign native window': (p) => p['protectedWindow']['package'] = 'foreign',
    'ambiguous native windows': (p) =>
        p['protectedWindow']['ownedWindowCount'] = 2,
    'fallback bytes unexpectedly present': (p) =>
        p['projection']['rows'][0]['fileExists'] = true,
    'protected thumbnail bytes missing': (p) =>
        p['projection']['rows'][3]['fileExists'] = false,
    'protected thumbnail not rendered': (p) =>
        p['projection']['projection']['rows'][3]['imageWidgets'] = 0,
    'same peer identities': (p) => p['peers']['bob'] = 'a',
    'foreign run': (p) => p['projection']['runId'] = 'foreign',
    'wrong role': (p) => p['available']['role'] = 'bob',
    'wrong conversation peer': (p) => p['deleted']['peerId'] = 'other',
    'background observation': (p) => p['viewing']['lifecycle'] = 'paused',
    'duplicate fixture': (p) =>
        p['projection']['rows'].add(p['projection']['rows'][0]),
    'missing SQL authority': (p) => p['available']['rows'][0]['sql'] = [],
    'incoming sender row': (p) =>
        p['available']['rows'][0]['sql'][0]['is_incoming'] = 1,
    'protected sender lease': (p) =>
        p['available']['rows'][0]['sql'][0]['private_media_mode'] = 'protected',
    'uncommitted viewing': (p) =>
        p['viewing']['rows'][0]['sql'][0]['private_media_state'] = 'opening',
    'missing viewer': (p) => p['viewing']['projection']['viewers'] = 0,
    'duplicate viewer': (p) => p['viewing']['projection']['viewers'] = 2,
    'missing conversation': (p) =>
        p['projection']['projection']['conversations'] = 0,
    'missing letter card': (p) =>
        p['projection']['projection']['rows'][0]['letterCards'] = 0,
    'slot outside body': (p) =>
        p['projection']['projection']['rows'][0]['slotsInsideBodies'] = 0,
    'zero slot dimensions': (p) =>
        p['projection']['projection']['rows'][0]['slotSizes'][0]['width'] = 0,
    'placeholder image leak': (p) =>
        p['projection']['projection']['rows'][1]['imageWidgets'] = 1,
    'decoration image leak': (p) =>
        p['projection']['projection']['rows'][1]['decorationImages'] = 1,
    'invisible outgoing action': (p) =>
        p['projection']['projection']['rows'][0]['actions'][0]['width'] = 0,
    'wrong incoming height': (p) =>
        p['projection']['projection']['rows'][1]['actions'][0]['height'] = 149,
    'retired incoming button': (p) =>
        p['projection']['projection']['rows'][1]['actions'].add({
          'key': 'private-media-open',
        }),
    'inline terminal delete': (p) =>
        p['projection']['projection']['rows'][2]['actions'].add({
          'key': 'private-action-deleteForMe',
        }),
    'wrong delete target': (p) =>
        p['deleted']['rows'][0]['sql'][0]['hidden_at'] = 'now',
    'terminal not hidden': (p) =>
        p['deleted']['rows'][2]['sql'][0]['hidden_at'] = null,
    'deleted terminal still rendered': (p) =>
        p['deleted']['projection']['rows'][2]['rows'] = 1,
    'foreign file': (p) =>
        p['available']['rows'][0]['attachments'][0]['exactOwnedPath'] = false,
    'wrong attachment lane': (p) =>
        p['available']['rows'][0]['attachments'][0]['owner_lane'] = 'group',
    'missing pending bytes': (p) =>
        p['available']['rows'][0]['fileExists'] = false,
    'corrupt pending bytes': (p) =>
        p['available']['rows'][0]['fileSha256'] = 'bad',
    'consumed SQL attachments retained': (p) =>
        p['consumed']['rows'][0]['attachments'] = [{}],
    'consumed repository mirror retained': (p) =>
        p['consumed']['rows'][0]['repositoryAttachmentCount'] = 1,
    'consumed file retained': (p) =>
        p['consumed']['rows'][0]['fileExists'] = true,
    'opening event omitted': (p) => p['consumed']['committed'].removeAt(0),
    'synthetic mutation source': (p) =>
        p['consumed']['committed'][0]['source'] = 'synthetic',
    'foreign mutation identity': (p) =>
        p['consumed']['committed'][0]['messageId'] = 'other',
    'mutation time reversal': (p) =>
        p['consumed']['committed'][1]['observedAtMicros'] = 0,
    'same cold nonce': (p) => p['afterNonce'] = 'old',
    'cold persisted state lost': (p) =>
        p['coldConsumed']['rows'][0]['sql'][0]['private_media_state'] =
            'available',
    'consumed reopened': (p) => p['refused']['projection']['viewers'] = 1,
    'remote revocation overclaim': (p) =>
        p['claims']['remoteRevocation'] = true,
    'missing stage': (p) => p.remove('refused'),
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = fixture();
      entry.value(proof);
      expect(validateProductionPrivateMedia(proof), isNotEmpty);
    });
  }
  test(
    'repeated committed available events do not invent lifecycle transitions',
    () {
      final proof = fixture();
      proof['consumed']['committed'].insert(0, {
        'messageId': 'private-private-test-sender_pending',
        'state': 'available',
        'source': 'production-repository-committed-change',
        'observedAtMicros': 0,
      });
      expect(validateProductionPrivateMedia(proof), isEmpty);
    },
  );
}
