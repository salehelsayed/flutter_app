import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:image/image.dart' as image;

import '../../../integration_test/support/media_content_oracle.dart';
import '../../../tool/sims/production_journey_gap_criteria.dart';

Map<String, Object?> _base(String journey) => {
  'schema': 'mknoon.production-journey-gap.v1',
  'journeyId': journey,
  'runId': 'fixture-run',
  'candidateSource': 'a' * 40,
  'executionStatus': 'complete',
  'targets': {
    'alice': {
      'deviceId': 'physical-fixture',
      'platform': 'android',
      'artifactSha256': 'b' * 64,
    },
    'bob': {
      'deviceId': 'emulator-5554',
      'platform': 'android',
      'artifactSha256': 'b' * 64,
    },
    'charlie': {
      'deviceId': 'emulator-5556',
      'platform': 'android',
      'artifactSha256': 'b' * 64,
    },
  },
  'evidence': [
    {'path': 'mcp.json', 'sha256': 'c' * 64, 'kind': 'mcp-transcript'},
  ],
  'observations': <String, Object?>{'cleanupRestored': true},
};

Map<String, Object?> _media(String suffix, {String owner = 'group'}) => {
  'owner': owner,
  'groupId': 'group-fixture',
  'messageId': 'message-$suffix',
  'attachmentId': 'attachment-$suffix',
  'caption': 'draft عربي\nfixture',
  'marker': 'card-$suffix',
  'capture': 'native_camera',
  'senderReceiptFile': 'sender-$suffix.json',
  'senderReceiptSha256': 'd' * 64,
  'recipients': [
    {
      'role': 'bob',
      'messageId': 'message-$suffix',
      'attachmentId': 'attachment-$suffix',
      'messageCount': 1,
      'attachmentCount': 1,
      'messageCountAfterReopen': 1,
      'attachmentCountAfterReopen': 1,
      'caption': 'draft عربي\nfixture',
      'downloadStatus': 'done',
      'fullFile': 'full-$suffix.jpg',
      'duplicateObservationMs': 10000,
      'nativeOpen': {
        'backend': 'Android ImageDecoder',
        'fullViewerOpened': true,
        'marker': 'card-$suffix',
        'orientationCorrect': true,
        'decodedWidth': 128,
        'decodedHeight': 96,
      },
    },
  ],
};

Map<String, Object?> _complete(String journey) {
  final receipt = _base(journey);
  final observations = receipt['observations']! as Map<String, Object?>;
  switch (journey) {
    case 'CONTACT-001':
      observations.addAll({
        'before': {
          'contactCount': 0,
          'requestCount': 0,
          'requestSendAttempts': 0,
        },
        'cancelled': {
          'outcome': 'cancelled',
          'contactCount': 0,
          'requestCount': 0,
          'requestSendAttempts': 0,
        },
        'denied': {
          'outcome': 'permission_denied',
          'contactCount': 0,
          'requestCount': 0,
          'requestSendAttempts': 0,
        },
        'granted': {
          'entry': 'contact_scan',
          'input': 'optical_camera',
          'permission': 'granted',
          'authenticatedRequest': true,
          'contactCount': 1,
          'requestCount': 1,
          'requestSendAttempts': 1,
        },
        'reopened': {
          'contactCount': 1,
          'requestCount': 1,
          'requestSendAttempts': 1,
        },
        'duplicateObservationMs': 10000,
      });
    case 'MEDIA-010':
      observations['cases'] = [
        for (final access in ['camera', 'photos'])
          {
            'access': access,
            'status': 'complete',
            'permissionBefore': 'denied',
            'permissionAfter': 'granted',
            'draftBefore': 'draft عربي',
            'draftAfterDeny': 'draft عربي',
            'sendsBefore': 0,
            'sendsAfterDeny': 0,
            'attachmentsAfterDeny': 0,
            'visibleDenial': true,
            'falseSuccessAfterDeny': false,
            'stagedAfterRetry': 1,
            'sendTaps': 1,
            'receiverMessages': 1,
            'receiverAttachments': 1,
            'receiverMessagesAfterReopen': 1,
            'receivedCaption': 'draft عربي',
          },
      ];
    case 'MEDIA-035':
      observations['group'] = {
        'groupId': 'group-fixture',
        'memberRoles': ['alice', 'bob'],
        'senderRole': 'alice',
        'removedRole': 'charlie',
      };
      observations['media'] = [
        for (final quality in ['Original', 'Compressed'])
          {
            ..._media(quality),
            'quality': quality,
            'removed': {
              'role': 'charlie',
              'messageCount': 0,
              'attachmentCount': 0,
              'downloadAttempts': 0,
              'observationMs': 10000,
            },
          },
      ];
    case 'VC-023':
      receipt['targets'] = {
        'subject': {
          'deviceId': 'emulator-5554',
          'platform': 'android',
          'artifactSha256': 'b' * 64,
          'forceRelayBuild': false,
        },
        'peer': {
          'deviceId': 'physical-fixture',
          'platform': 'android',
          'artifactSha256': 'b' * 64,
        },
      };
      observations.addAll({
        'savedAlwaysRelay': true,
        'startedAt': '2026-10-26T08:00:00Z',
        'turnFault': {
          'scope': 'subject_emulator_only',
          'deviceId': 'emulator-5554',
          'rootAvailable': true,
          'rulesInstalled': true,
          'matchedTurnPackets': 1,
          'signalingStillReachable': true,
          'rulesRemoved': true,
          'originalRulesRestored': true,
          'hetznerChanged': false,
        },
        for (final phase in ['beforeOutage', 'afterRestore'])
          phase: {
            'callId': 'call-$phase',
            'state': 'connected',
            'nativePolicy': 'relay',
            'selectedLocalCandidateType': 'relay',
            'nativeReleased': true,
            'peers': [
              for (final role in ['subject', 'peer'])
                {
                  'role': role,
                  'start': {'packetsSent': 1, 'packetsReceived': 1},
                  'end': {'packetsSent': 100, 'packetsReceived': 100},
                },
            ],
          },
        'outage': {
          'callId': 'call-outage',
          'state': 'failed',
          'nativePolicy': 'relay',
          'selectedDirectPairs': 0,
          'connectedObserved': false,
          'terminalWithinOriginalDeadline': true,
          'nativeReleased': true,
        },
      });
    case 'MEDIA-018':
      observations['cuts'] = [
        for (final direction in ['upload', 'download'])
          {
            ..._media(direction, owner: 'direct'),
            'direction': direction,
            'durableRowPresent': true,
            'rowStatusAtCut': direction == 'upload'
                ? 'uploading'
                : 'downloading',
            'verifiedProcessAbsent': true,
            'nonceBefore': 'before',
            'nonceAfter': 'after',
            'partialFileBytes': 32,
            for (final phase in ['gateBeforeKill', 'gateAfterKill'])
              phase: {
                'gateId': 'gate-$direction',
                'direction': direction,
                'bound': true,
                'held': true,
                'released': false,
                'timedOut': false,
                'attachmentSha256': sha256
                    .convert(utf8.encode('attachment-$direction'))
                    .toString(),
                'bytesTransferred': 32,
                'totalBytes': 4096,
              },
          },
      ];
  }
  return receipt;
}

void main() {
  for (final journey in productionJourneyGapIds) {
    test(
      '$journey accepts complete structural receipts without claiming device execution',
      () {
        expect(
          validateProductionJourneyGapReceipt(_complete(journey)),
          isEmpty,
        );
      },
    );
    test('$journey rejects an unrun template and missing raw evidence', () {
      final receipt = _complete(journey)..['executionStatus'] = 'not_run';
      expect(
        validateProductionJourneyGapReceipt(receipt),
        contains('execution incomplete'),
      );
      receipt['executionStatus'] = 'complete';
      receipt['evidence'] = [];
      expect(
        validateProductionJourneyGapReceipt(receipt),
        contains('raw MCP evidence'),
      );
    });
  }
  final regressions = <String, (String, void Function(Map))>{
    'scanner cancellation sent a request': (
      'CONTACT-001',
      (o) => (o['cancelled'] as Map)['requestSendAttempts'] = 1,
    ),
    'scanner denial added a contact': (
      'CONTACT-001',
      (o) => (o['denied'] as Map)['contactCount'] = 1,
    ),
    'paste is not an optical scan': (
      'CONTACT-001',
      (o) => (o['granted'] as Map)['input'] = 'paste',
    ),
    'camera denial lost the draft': (
      'MEDIA-010',
      (o) => ((o['cases'] as List).first as Map)['draftAfterDeny'] = '',
    ),
    'camera denial reported success': (
      'MEDIA-010',
      (o) =>
          ((o['cases'] as List).first as Map)['falseSuccessAfterDeny'] = true,
    ),
    'camera retry sent twice': (
      'MEDIA-010',
      (o) => ((o['cases'] as List).first as Map)['receiverMessages'] = 2,
    ),
    'group member was omitted': (
      'MEDIA-035',
      (o) => (o['group'] as Map)['memberRoles'] = ['alice', 'bob', 'charlie'],
    ),
    'removed member got an image': (
      'MEDIA-035',
      (o) =>
          (((o['media'] as List).first as Map)['removed']
                  as Map)['messageCount'] =
              1,
    ),
    'thumbnail is not the native full image': (
      'MEDIA-035',
      (o) =>
          (((((o['media'] as List).first as Map)['recipients'] as List).first
                      as Map)['nativeOpen']
                  as Map)['fullViewerOpened'] =
              false,
    ),
    'TURN block did not affect packets': (
      'VC-023',
      (o) => (o['turnFault'] as Map)['matchedTurnPackets'] = 0,
    ),
    'TURN outage selected direct': (
      'VC-023',
      (o) => (o['outage'] as Map)['selectedDirectPairs'] = 1,
    ),
    'connected label without RTP': (
      'VC-023',
      (o) =>
          (((o['beforeOutage'] as Map)['peers'] as List).first as Map)['end'] =
              {'packetsSent': 1, 'packetsReceived': 1},
    ),
    'TURN rule was not restored': (
      'VC-023',
      (o) => (o['turnFault'] as Map)['originalRulesRestored'] = false,
    ),
    'call before 08:30 CET is rejected': (
      'VC-023',
      (o) => o['startedAt'] = '2026-10-26T07:29:59Z',
    ),
    'call without a timezone is incomplete': (
      'VC-023',
      (o) => o['startedAt'] = '2026-10-26T09:00:00',
    ),
    'restart after completed upload is not the cut': (
      'MEDIA-018',
      (o) => ((o['cuts'] as List).first as Map)['rowStatusAtCut'] = 'sent',
    ),
    'gate released before verified death': (
      'MEDIA-018',
      (o) =>
          (((o['cuts'] as List).first as Map)['gateAfterKill']
                  as Map)['released'] =
              true,
    ),
    'a different gate cannot witness the same cut': (
      'MEDIA-018',
      (o) =>
          (((o['cuts'] as List).first as Map)['gateAfterKill']
                  as Map)['gateId'] =
              'other-gate',
    ),
    'zero-byte progress is not a download cut': (
      'MEDIA-018',
      (o) => ((o['cuts'] as List).last as Map)['partialFileBytes'] = 0,
    ),
  };
  for (final entry in regressions.entries) {
    test(entry.key, () {
      final receipt = _complete(entry.value.$1);
      entry.value.$2(receipt['observations']! as Map);
      expect(validateProductionJourneyGapReceipt(receipt), isNotEmpty);
    });
  }
  test('forced-relay build cannot prove the user setting', () {
    final receipt = _complete('VC-023');
    ((receipt['targets'] as Map)['subject'] as Map)['forceRelayBuild'] = true;
    expect(validateProductionJourneyGapReceipt(receipt), isNotEmpty);
  });
  test(
    'CLI leaves an unrun template NOT RUN and never operates a device',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'journey-gap-cli-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final receipt = File('${directory.path}/case.json');
      await receipt.writeAsString(
        jsonEncode({'journeyId': 'CONTACT-001', 'executionStatus': 'not_run'}),
      );
      final result = await Process.run('dart', [
        'run',
        'integration_test/scripts/evaluate_production_journey_gap_receipt.dart',
        '--source',
        'a' * 40,
        '--receipt',
        receipt.path,
        '--output',
        '${directory.path}/verdict.json',
      ]);
      expect(result.exitCode, 3, reason: '${result.stderr}');
      final verdict =
          jsonDecode(
                await File('${directory.path}/verdict.json').readAsString(),
              )
              as Map;
      expect(verdict['status'], 'NOT RUN');
      expect(verdict['nativeExecutedByThisCommand'], false);
    },
  );
  test('CLI rejects tampered raw evidence', () async {
    final directory = await Directory.systemTemp.createTemp(
      'journey-gap-tamper-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final receipt = _complete('CONTACT-001');
    await File(
      '${directory.path}/mcp.json',
    ).writeAsString('synthetic host fixture only');
    await File(
      '${directory.path}/case.json',
    ).writeAsString(jsonEncode(receipt));
    final result = await Process.run('dart', [
      'run',
      'integration_test/scripts/evaluate_production_journey_gap_receipt.dart',
      '--source',
      'a' * 40,
      '--receipt',
      '${directory.path}/case.json',
      '--output',
      '${directory.path}/verdict.json',
    ]);
    expect(result.exitCode, 1, reason: '${result.stderr}');
    final verdict =
        jsonDecode(await File('${directory.path}/verdict.json').readAsString())
            as Map;
    expect(verdict['failures'], contains('raw evidence digest mismatch'));
    expect(verdict['nativeExecutedByThisCommand'], false);
  });
  test(
    'CLI checks processed-source bytes and keeps absent byte proof NOT RUN',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'journey-gap-bytes-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final receipt = _complete('MEDIA-035');
      final raw = utf8.encode(
        'synthetic host MCP fixture; no native execution',
      );
      await File('${directory.path}/mcp.json').writeAsBytes(raw);
      ((receipt['evidence'] as List).single as Map)['sha256'] = sha256
          .convert(raw)
          .toString();
      Object? canonical(Object? value) {
        if (value is Map) {
          final keys = value.keys.cast<String>().toList()..sort();
          return {for (final key in keys) key: canonical(value[key])};
        }
        if (value is List) return value.map(canonical).toList();
        return value;
      }

      final media = (receipt['observations'] as Map)['media'] as List;
      final fullFiles = <String, List<int>>{};
      for (final item in media.cast<Map>()) {
        final pixels = image.Image(width: 128, height: 96);
        pixels.setPixelRgba(
          0,
          0,
          item['quality'] == 'Original' ? 255 : 128,
          0,
          0,
          255,
        );
        final plain = image.encodePng(pixels);
        final cipher = [...plain, ...List.filled(16, 0)];
        final sender = {
          'schema': 1,
          'identity_sha256': MediaWireIdentity(
            runId: 'fixture-run',
            owner: MediaOwnerLane.group,
            messageId: item['messageId'] as String,
            attachmentId: item['attachmentId'] as String,
          ).digest,
          'mime': 'image/png',
          'source': {
            'boundary': EncryptedMediaSourceCapture.boundary,
            'plaintext': {
              'bytes': plain.length,
              'sha256': sha256.convert(plain).toString(),
            },
            'ciphertext': {
              'bytes': cipher.length,
              'sha256': sha256.convert(cipher).toString(),
            },
            'runtime_platform': 'android',
          },
        };
        item['senderReceiptSha256'] = sha256
            .convert(utf8.encode(jsonEncode(canonical(sender))))
            .toString();
        await File(
          '${directory.path}/${item['senderReceiptFile']}',
        ).writeAsString(jsonEncode(sender));
        final recipient = (item['recipients'] as List).single as Map;
        await File(
          '${directory.path}/${recipient['fullFile']}',
        ).writeAsBytes(plain);
        fullFiles[recipient['fullFile'] as String] = plain;
      }
      Future<Map> evaluate(
        String label,
        int expectedExit, {
        String? source,
      }) async {
        await File(
          '${directory.path}/case.json',
        ).writeAsString(jsonEncode(receipt));
        final path = '${directory.path}/$label.json';
        final result = await Process.run('dart', [
          'run',
          'integration_test/scripts/evaluate_production_journey_gap_receipt.dart',
          '--source',
          source ?? 'a' * 40,
          '--receipt',
          '${directory.path}/case.json',
          '--output',
          path,
        ]);
        expect(
          result.exitCode,
          expectedExit,
          reason: '${result.stderr}\n${result.stdout}',
        );
        return jsonDecode(await File(path).readAsString()) as Map;
      }

      final matched = await evaluate('matched', 0);
      expect(matched['status'], 'PASS_RECORDED');
      final wrongSource = await evaluate('wrong-source', 1, source: 'c' * 40);
      expect(wrongSource['failures'], contains('candidate source mismatch'));
      expect(
        (matched['mediaFiles'] as List).every(
          (v) => v['processedSendByteEquality'] == 'PASS',
        ),
        true,
      );
      expect(matched['nativeExecutedByThisCommand'], false);
      final first = ((media.first as Map)['recipients'] as List).single as Map;
      await File(
        '${directory.path}/${first['fullFile']}',
      ).writeAsString('truncated');
      final mismatch = await evaluate('mismatch', 1);
      expect(mismatch['failures'], isNotEmpty);
      for (final entry in fullFiles.entries) {
        await File('${directory.path}/${entry.key}').writeAsBytes(entry.value);
      }
      for (final item in media.cast<Map>()) {
        item.remove('senderReceiptFile');
        item.remove('senderReceiptSha256');
      }
      final withoutCapture = await evaluate('without-encryption-capture', 0);
      expect(
        (withoutCapture['mediaFiles'] as List).every(
          (v) => v['processedSendByteEquality'] == 'NOT RUN',
        ),
        true,
      );
    },
  );
  test(
    'unavailable live targets are N/A with hashed discovery, not a pass',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'journey-gap-na-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final discovery = utf8.encode('[]\n');
      await File('${directory.path}/devices.json').writeAsBytes(discovery);
      await File('${directory.path}/case.json').writeAsString(
        jsonEncode({
          'schema': 'mknoon.production-journey-gap.v1',
          'journeyId': 'VC-023',
          'candidateSource': 'a' * 40,
          'runId': 'availability-fixture',
          'executionStatus': 'target_unavailable',
          'reason': 'target_unavailable_by_project_policy',
          'evidence': [
            {
              'path': 'devices.json',
              'kind': 'device-discovery',
              'sha256': sha256.convert(discovery).toString(),
            },
          ],
        }),
      );
      final result = await Process.run('dart', [
        'run',
        'integration_test/scripts/evaluate_production_journey_gap_receipt.dart',
        '--source',
        'a' * 40,
        '--receipt',
        '${directory.path}/case.json',
        '--output',
        '${directory.path}/verdict.json',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final verdict =
          jsonDecode(
                await File('${directory.path}/verdict.json').readAsString(),
              )
              as Map;
      expect(verdict['status'], 'N/A_TARGET_UNAVAILABLE');
      expect(verdict['nativeExecutedByThisCommand'], false);
    },
  );
}
