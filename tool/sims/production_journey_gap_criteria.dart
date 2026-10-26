import 'dart:convert';

import 'package:crypto/crypto.dart';

const productionJourneyGapIds = [
  'CONTACT-001',
  'MEDIA-010',
  'MEDIA-035',
  'VC-023',
  'MEDIA-018',
];

Map<String, Object?> journeyGapMap(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : {};
List<Map<String, Object?>> journeyGapRows(Object? value) =>
    value is List ? value.whereType<Map>().map(journeyGapMap).toList() : [];

/// Evaluates observations supplied by the MCP execution owner. This function
/// does not operate a device or attest that an external observation happened.
/// File hashes and the existing sent-media oracle are checked by the CLI.
List<String> validateProductionJourneyGapReceipt(Map<String, Object?> receipt) {
  final failures = <String>[];
  void require(bool value, String detail) {
    if (!value) failures.add(detail);
  }

  bool nonempty(Object? value) => value is String && value.trim().isNotEmpty;
  bool digest(Object? value, int length) =>
      value is String && RegExp('^[a-f0-9]{$length}\$').hasMatch(value);
  final journey = receipt['journeyId'];
  final run = receipt['runId'];
  final targets = journeyGapMap(receipt['targets']);
  final observations = journeyGapMap(receipt['observations']);
  require(receipt['schema'] == 'mknoon.production-journey-gap.v1', 'schema');
  require(productionJourneyGapIds.contains(journey), 'supported journey');
  require(nonempty(run), 'exact run identity');
  require(digest(receipt['candidateSource'], 40), 'exact candidate source');
  require(receipt['executionStatus'] == 'complete', 'execution incomplete');
  require(
    targets.length >= 2 &&
        targets.values.every((value) {
          final target = journeyGapMap(value);
          return nonempty(target['deviceId']) &&
              ['android', 'ios'].contains(target['platform']) &&
              digest(target['artifactSha256'], 64);
        }) &&
        targets.values
                .map((t) => journeyGapMap(t)['deviceId'])
                .toSet()
                .length ==
            targets.length,
    'distinct pinned targets and exact installed artifacts',
  );
  require(journeyGapRows(receipt['evidence']).isNotEmpty, 'raw MCP evidence');
  require(observations['cleanupRestored'] == true, 'owned state restoration');

  switch (journey) {
    case 'CONTACT-001':
      final before = journeyGapMap(observations['before']);
      final keys = ['contactCount', 'requestCount', 'requestSendAttempts'];
      require(
        keys.every((key) => before[key] is int && (before[key]! as int) >= 0),
        'measured contact/request/egress baseline',
      );
      for (final phase in ['cancelled', 'denied']) {
        final value = journeyGapMap(observations[phase]);
        require(
          value['outcome'] ==
                  (phase == 'cancelled' ? 'cancelled' : 'permission_denied') &&
              keys.every((key) => value[key] == before[key]),
          '$phase must leave contacts, requests and network attempts unchanged',
        );
      }
      final granted = journeyGapMap(observations['granted']);
      require(
        granted['entry'] == 'contact_scan' &&
            granted['input'] == 'optical_camera' &&
            granted['permission'] == 'granted' &&
            granted['authenticatedRequest'] == true,
        'grant must use the real scanner and a valid authenticated request',
      );
      for (final phase in ['granted', 'reopened']) {
        final value = journeyGapMap(observations[phase]);
        require(
          keys
              .take(2)
              .every(
                (key) =>
                    before[key] is int &&
                    value[key] == (before[key]! as int) + 1,
              ),
          '$phase must have exactly one added contact and request',
        );
      }
      require(
        granted['requestSendAttempts'] is int &&
            before['requestSendAttempts'] is int &&
            (granted['requestSendAttempts']! as int) >
                (before['requestSendAttempts']! as int) &&
            journeyGapMap(observations['reopened'])['requestSendAttempts'] ==
                granted['requestSendAttempts'],
        'real request egress, with no additional dispatch after reopen',
      );
      require(
        (observations['duplicateObservationMs'] as num? ?? 0) >= 10000,
        'post-reopen duplicate observation',
      );
    case 'MEDIA-010':
      final cases = journeyGapRows(observations['cases']);
      require(
        cases.length == 2 &&
            cases.map((c) => c['access']).toSet().containsAll({
              'camera',
              'photos',
            }),
        'camera and photo-library permission cases',
      );
      for (final value in cases) {
        final access = value['access'];
        if (access == 'photos' && value['status'] == 'N/A') {
          require(
            value['reason'] ==
                    'system_picker_has_no_photo_permission_boundary' &&
                nonempty(value['draftBefore']) &&
                value['sendsBefore'] is int &&
                value['draftAfterCancel'] == value['draftBefore'] &&
                value['sendsAfterCancel'] == value['sendsBefore'],
            'photo system-picker N/A needs actual cancellation/draft evidence',
          );
          continue;
        }
        require(
          value['status'] == 'complete' &&
              value['permissionBefore'] == 'denied' &&
              value['permissionAfter'] == 'granted' &&
              nonempty(value['draftBefore']) &&
              value['draftAfterDeny'] == value['draftBefore'] &&
              value['sendsBefore'] is int &&
              value['sendsAfterDeny'] == value['sendsBefore'] &&
              value['attachmentsAfterDeny'] == 0 &&
              value['visibleDenial'] == true &&
              value['falseSuccessAfterDeny'] == false &&
              value['stagedAfterRetry'] == 1 &&
              value['sendTaps'] == 1 &&
              value['receiverMessages'] == 1 &&
              value['receiverAttachments'] == 1 &&
              value['receiverMessagesAfterReopen'] == 1 &&
              value['receivedCaption'] == value['draftBefore'],
          '$access denial/grant must preserve the draft and send exactly once',
        );
      }
    case 'MEDIA-035':
      final group = journeyGapMap(observations['group']);
      final members = group['memberRoles'] is List
          ? (group['memberRoles']! as List).cast<Object?>()
          : <Object?>[];
      final sender = group['senderRole'];
      final removed = group['removedRole'];
      require(
        nonempty(group['groupId']) &&
            members.length >= 2 &&
            members.toSet().length == members.length &&
            members.contains(sender) &&
            targets.containsKey(removed) &&
            !members.contains(removed) &&
            members.every(targets.containsKey),
        'exact current membership plus a separate removed member',
      );
      final media = journeyGapRows(observations['media']);
      require(
        media.length == 2 &&
            media.map((m) => m['messageId']).toSet().length == 2 &&
            media.map((m) => m['attachmentId']).toSet().length == 2 &&
            media.map((m) => m['quality']).toSet().containsAll({
              'Original',
              'Compressed',
            }),
        'separate Original and Compressed camera captures',
      );
      for (final value in media) {
        final recipients = journeyGapRows(value['recipients']);
        require(
          value['owner'] == 'group' &&
              value['groupId'] == group['groupId'] &&
              value['capture'] == 'native_camera' &&
              nonempty(value['caption']) &&
              recipients.length == members.length - 1 &&
              recipients.map((r) => r['role']).toSet().length ==
                  recipients.length &&
              recipients.every(
                (r) => members.contains(r['role']) && r['role'] != sender,
              ),
          'camera output must reach every entitled recipient independently',
        );
        _requireMedia(value, require);
        final excluded = journeyGapMap(value['removed']);
        require(
          excluded['role'] == removed &&
              excluded['messageCount'] == 0 &&
              excluded['attachmentCount'] == 0 &&
              excluded['downloadAttempts'] == 0 &&
              (excluded['observationMs'] as num? ?? 0) >= 10000,
          'removed member must receive no message, attachment or download',
        );
      }
    case 'VC-023':
      final subject = journeyGapMap(targets['subject']);
      require(
        subject['platform'] == 'android' &&
            '${subject['deviceId']}'.startsWith('emulator-') &&
            subject['forceRelayBuild'] == false &&
            observations['savedAlwaysRelay'] == true,
        'actual saved toggle on an Android emulator, without forced-relay build',
      );
      final fault = journeyGapMap(observations['turnFault']);
      require(
        fault['scope'] == 'subject_emulator_only' &&
            fault['deviceId'] == subject['deviceId'] &&
            fault['rootAvailable'] == true &&
            fault['rulesInstalled'] == true &&
            fault['matchedTurnPackets'] is int &&
            (fault['matchedTurnPackets']! as int) > 0 &&
            fault['signalingStillReachable'] == true &&
            fault['rulesRemoved'] == true &&
            fault['originalRulesRestored'] == true &&
            fault['hetznerChanged'] == false,
        'TURN fault must be effective, emulator-only and fully restored',
      );
      final calls = <Object?>[];
      for (final phase in ['beforeOutage', 'afterRestore']) {
        final value = journeyGapMap(observations[phase]);
        calls.add(value['callId']);
        final peers = journeyGapRows(value['peers']);
        require(
          nonempty(value['callId']) &&
              value['state'] == 'connected' &&
              value['nativePolicy'] == 'relay' &&
              value['selectedLocalCandidateType'] == 'relay' &&
              peers.length == 2 &&
              peers.map((p) => p['role']).toSet().containsAll({
                'subject',
                'peer',
              }) &&
              peers.every((peer) {
                final start = journeyGapMap(peer['start']);
                final end = journeyGapMap(peer['end']);
                return ['packetsSent', 'packetsReceived'].every(
                  (key) =>
                      start[key] is int &&
                      end[key] is int &&
                      (end[key]! as int) > (start[key]! as int),
                );
              }) &&
              value['nativeReleased'] == true,
          '$phase requires a real selected relay pair and both peers RTP progress',
        );
      }
      final outage = journeyGapMap(observations['outage']);
      calls.add(outage['callId']);
      require(
        calls.every(nonempty) &&
            calls.toSet().length == 3 &&
            outage['state'] == 'failed' &&
            outage['nativePolicy'] == 'relay' &&
            outage['selectedDirectPairs'] == 0 &&
            outage['connectedObserved'] == false &&
            outage['terminalWithinOriginalDeadline'] == true &&
            outage['nativeReleased'] == true,
        'TURN outage must fail without direct fallback, on a distinct call',
      );
      final started = DateTime.tryParse(
        '${observations['startedAt']}',
      )?.toUtc().add(const Duration(hours: 1));
      require(
        RegExp(
              r'(Z|[+-]\d\d:\d\d)$',
            ).hasMatch('${observations['startedAt']}') &&
            started != null &&
            started.hour * 60 + started.minute >= 8 * 60 + 30,
        'calls may start only after 08:30 CET',
      );
    case 'MEDIA-018':
      final senderRole = observations['senderRole'];
      final receiverRole = observations['receiverRole'];
      require(
        nonempty(senderRole) &&
            nonempty(receiverRole) &&
            senderRole != receiverRole &&
            targets.containsKey(senderRole) &&
            targets.containsKey(receiverRole),
        'bound distinct sender and receiver roles',
      );
      final cuts = journeyGapRows(observations['cuts']);
      require(
        cuts.length == 2 &&
            cuts.map((c) => c['direction']).toSet().containsAll({
              'upload',
              'download',
            }),
        'both sender-upload and receiver-download cuts',
      );
      for (final cut in cuts) {
        final id = cut['attachmentId'];
        final identityHash = sha256.convert(utf8.encode('$id')).toString();
        final actorRole = cut['direction'] == 'upload'
            ? senderRole
            : receiverRole;
        final actor = journeyGapMap(targets[actorRole]);
        final proof = journeyGapMap(cut['processCut']);
        final before = journeyGapMap(proof['gateBeforeKill']);
        final after = journeyGapMap(proof['gateAfterKill']);
        require(
          cut['actorRole'] == actorRole &&
              targets.containsKey(actorRole) &&
              nonempty(actor['packageName']) &&
              proof['schema'] == 'mknoon.media-transfer-cut.v1' &&
              proof['status'] == 'PASS' &&
              proof['deviceId'] == actor['deviceId'] &&
              proof['packageName'] == actor['packageName'] &&
              proof['gateId'] == before['gateId'],
          '${cut['direction']}: process cut must match the intended actor',
        );
        final recipients = journeyGapRows(cut['recipients']);
        require(
          recipients.isNotEmpty &&
              recipients.every(
                (recipient) =>
                    recipient['role'] == receiverRole &&
                    targets.containsKey(recipient['role']),
              ),
          '${cut['direction']}: recipient must be the bound receiver',
        );
        require(
          nonempty(id) &&
              nonempty(cut['messageId']) &&
              cut['durableRowPresent'] == true &&
              [
                'upload_pending',
                'uploading',
                'downloading',
                'retrying',
              ].contains(cut['rowStatusAtCut']) &&
              proof['verifiedProcessAbsent'] == true &&
              nonempty(cut['nonceBefore']) &&
              nonempty(cut['nonceAfter']) &&
              cut['nonceBefore'] != cut['nonceAfter'] &&
              nonempty(before['gateId']) &&
              after['gateId'] == before['gateId'] &&
              before['totalBytes'] == after['totalBytes'] &&
              [before, after].every(
                (gate) =>
                    gate['bound'] == true &&
                    gate['held'] == true &&
                    gate['released'] == false &&
                    gate['timedOut'] == false &&
                    gate['attachmentSha256'] == identityHash &&
                    gate['direction'] == cut['direction'] &&
                    gate['bytesTransferred'] is int &&
                    gate['totalBytes'] is int &&
                    (gate['bytesTransferred']! as int) > 0 &&
                    (gate['bytesTransferred']! as int) <
                        (gate['totalBytes']! as int),
              ),
          '${cut['direction']}: require a held partial transfer through verified death',
        );
        if (cut['direction'] == 'download') {
          require(
            cut['partialFileBytes'] is int &&
                (cut['partialFileBytes']! as int) > 0 &&
                after['totalBytes'] is int &&
                (cut['partialFileBytes']! as int) <
                    (after['totalBytes']! as int),
            'receiver partial file must precede completion',
          );
        }
        _requireMedia(cut, require);
      }
  }
  return failures;
}

void _requireMedia(
  Map<String, Object?> media,
  void Function(bool, String) require,
) {
  final label = '${media['messageId']}';
  require(
    media['messageId'] is String &&
        (media['messageId']! as String).isNotEmpty &&
        media['attachmentId'] is String &&
        (media['attachmentId']! as String).isNotEmpty &&
        ['direct', 'group'].contains(media['owner']),
    '$label: exact media identity and owner',
  );
  final recipients = journeyGapRows(media['recipients']);
  require(recipients.isNotEmpty, '$label: recipient proof');
  for (final recipient in recipients) {
    final native = journeyGapMap(recipient['nativeOpen']);
    require(
      recipient['messageId'] == media['messageId'] &&
          recipient['attachmentId'] == media['attachmentId'] &&
          recipient['messageCount'] == 1 &&
          recipient['attachmentCount'] == 1 &&
          recipient['messageCountAfterReopen'] == 1 &&
          recipient['attachmentCountAfterReopen'] == 1 &&
          recipient['caption'] == media['caption'] &&
          recipient['downloadStatus'] == 'done' &&
          recipient['fullFile'] is String &&
          native['backend'] is String &&
          (native['backend']! as String).isNotEmpty &&
          native['fullViewerOpened'] == true &&
          native['marker'] == media['marker'] &&
          media['marker'] is String &&
          (media['marker']! as String).isNotEmpty &&
          native['orientationCorrect'] == true &&
          native['decodedWidth'] is int &&
          (native['decodedWidth']! as int) > 0 &&
          native['decodedHeight'] is int &&
          (native['decodedHeight']! as int) > 0 &&
          (recipient['duplicateObservationMs'] as num? ?? 0) >= 10000,
      '$label/${recipient['role']}: full native content/caption and exact-once reopen',
    );
    if (media['mediaType'] == 'video') {
      require(
        native['durationMs'] is int &&
            (native['durationMs']! as int) > 0 &&
            native['startPositionMs'] is int &&
            native['endPositionMs'] is int &&
            (native['startPositionMs']! as int) >= 0 &&
            (native['endPositionMs']! as int) -
                    (native['startPositionMs']! as int) >=
                250 &&
            (native['endPositionMs']! as int) <=
                (native['durationMs']! as int) &&
            native['markerAndEndObserved'] == true,
        '$label/${recipient['role']}: actual native video playback through content and end',
      );
    }
  }
}
