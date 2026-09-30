import '../../integration_test/scripts/group_multi_party_device_criteria.dart';

/// Texts of catalog `private_online_remove`, identical to the original harness.
Map<String, String> productionOnlineRemoveTexts(String run) => {
  'st006BobDuringRotation': 'ST-006 Bob during rotation $run',
  'aliceAfterCharlieRemove': 'GM-004 Alice after Charlie removal $run',
  'bobAfterCharlieRemove': 'GM-004 Bob after Charlie removal $run',
};

const productionOnlineRemoveFlows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'remove-charlie-start',
  'bob-send-during-rotation',
  'remove-charlie-verify',
  'bob-send-after-removal',
];

/// Checks the production intermediate stages, then builds the original role
/// verdicts from those observations and runs the unchanged original oracle.
List<String> validateProductionGroupOnlineRemove(Map<String, Object?> proof) {
  final failures = <String>[];
  void require(bool ok, String detail) {
    if (!ok) failures.add(detail);
  }

  try {
    final run = proof['runId'] as String;
    final peers = proof['peers'] as Map;
    final alice = peers['alice'] as String;
    final bob = peers['bob'] as String;
    final charlie = peers['charlie'] as String;
    require(
      run.isNotEmpty && {alice, bob, charlie}.length == 3,
      'run and three distinct peers required',
    );
    final flows = proof['flows'] as List;
    require(
      flows.join(',') == productionOnlineRemoveFlows.join(','),
      'exact ordered UI flows',
    );
    Map stage(String name, String role) {
      final s = proof[name] as Map;
      require(
        s['runId'] == run &&
            s['role'] == role &&
            s['peerId'] == peers[role] &&
            s['scenario'] == 'private_online_remove',
        '$name: observation identity',
      );
      return s;
    }

    Map? watched(Map s, String key) {
      final rows = ((s['watched'] as Map?)?[key] as List?) ?? const [];
      return rows.length == 1 ? rows.single as Map : null;
    }

    int count(Map s, String key) =>
        (((s['watched'] as Map?)?[key] as List?) ?? const []).length;

    final charlieBefore = stage('charlieBefore', 'charlie');
    final bobExcluded = stage('bobExcluded', 'bob');
    final charlieRemoved = stage('charlieRemoved', 'charlie');
    final st006SentStage = stage('st006Sent', 'bob');
    final st006ReceivedStage = stage('st006Received', 'alice');
    final bobRotated = stage('bobRotated', 'bob');
    final bobReceivedStage = stage('bobReceivedAlice', 'bob');
    final bobSentStage = stage('bobSentAfter', 'bob');
    final aliceReceivedStage = stage('aliceReceivedBob', 'alice');
    final charlieLeak = stage('charlieLeak', 'charlie');
    final charlieFinal = stage('charlieFinal', 'charlie');
    final aliceFinal = stage('aliceFinal', 'alice');
    final bobFinal = stage('bobFinal', 'bob');
    final groupId = aliceFinal['groupId'] as String;
    final rotated = aliceFinal['keyEpoch'] as int;

    final held = proof['rotationHeld'] as Map;
    final heldAtReceive = proof['rotationAtSt006Receive'] as Map;
    require(
      held['held'] == true && held['released'] == false && held['keyEpoch'] == 1,
      'rotation held before Bob publishes, still at epoch 1',
    );
    require(
      heldAtReceive['held'] == true && heldAtReceive['released'] == false,
      'Alice received Bob during the held rotation',
    );
    require(
      charlieBefore['selfMember'] == true && charlieBefore['relayReady'] == true,
      'Charlie online and a current member before removal',
    );
    require(
      !(bobExcluded['memberPeerIds'] as List).contains(charlie) &&
          charlieRemoved['selfMember'] == false,
      'removal observed by Bob and Charlie before Bob publishes',
    );
    final order = proof['order'] as Map;
    require(
      (order['bobRotatedAtMs'] as int) < (order['aliceSendStartMs'] as int),
      'KE-007: Bob held the rotated key before Alice first sent',
    );

    final aliceSent = proof['aliceSent'] as Map;
    final upload = aliceSent['upload'] as Map;
    final st006Sent = watched(st006SentStage, 'st006BobDuringRotation');
    final st006Received = watched(
      st006ReceivedStage,
      'st006BobDuringRotation',
    );
    final bobReceived = watched(bobReceivedStage, 'aliceAfterCharlieRemove');
    final bobSentRow = watched(bobSentStage, 'bobAfterCharlieRemove');
    final aliceReceived = watched(aliceReceivedStage, 'bobAfterCharlieRemove');
    require(
      st006Sent?['isIncoming'] == false &&
          st006Received?['isIncoming'] == true &&
          bobReceived?['isIncoming'] == true &&
          bobSentRow?['isIncoming'] == false &&
          aliceReceived?['isIncoming'] == true,
      'exact single sent and received rows',
    );
    final bobMedia = (proof['bobMedia'] as Map)['media'] as List;
    final download = proof['charlieDownload'] as Map;
    final rejected = proof['charlieRejected'] as Map;

    bool excludes(Map s) => !(s['memberPeerIds'] as List).contains(charlie);
    Map<String, Object?> receivedEntry(String key, Map row, int persisted) => {
      'key': key,
      'messageId': row['messageId'],
      'groupId': row['groupId'],
      'text': row['text'],
      'senderPeerId': row['senderPeerId'],
      if (row['senderUsername'] != null) 'senderUsername': row['senderUsername'],
      'timestamp': row['timestamp'],
      'keyEpoch': row['keyEpoch'],
      'isIncoming': row['isIncoming'],
      'persistedCount': persisted,
    };
    Map<String, Object?> base(Map s, String role) => {
      'scenario': 'private_online_remove',
      'role': role,
      'runId': run,
      'deviceId': s['transportPeerId'],
      'peerId': s['peerId'],
      'transportPeerId': s['transportPeerId'],
      'groupId': s['groupId'],
      if (s['topicName'] != null) 'topicName': s['topicName'],
      'keyEpoch': s['keyEpoch'],
      'relayLifecycleProof': true,
      'memberPeerIds': s['memberPeerIds'],
      'activeMemberPeerIds': s['memberPeerIds'],
      if (s['groupConfigStateHash'] != null)
        'groupConfigStateHash': s['groupConfigStateHash'],
    };

    final aliceReceivedCount = count(aliceReceivedStage, 'bobAfterCharlieRemove');
    final aliceVerdict = {
      ...base(aliceFinal, 'alice'),
      'sentMessages': [
        {...aliceSent}..remove('upload'),
      ],
      'receivedMessages': [
        if (aliceReceived != null)
          receivedEntry('bobAfterCharlieRemove', aliceReceived, aliceReceivedCount),
      ],
      'persistedMessageCounts': {'bobAfterCharlieRemove': aliceReceivedCount},
      'gm004RemovalProof': {
        'charlieOnlineBeforeRemoval': true,
        'removedCharlie': true,
        'removedPeerId': charlie,
        'memberListExcludesCharlie': excludes(aliceFinal),
        'rotatedEpoch': rotated,
      },
      'ml005OnlineRemovalProof': {
        'rowId': 'ML-005',
        'charlieOnlineBeforeRemoval': charlieBefore['relayReady'] == true,
        'removedCharlie': excludes(aliceFinal),
        'removedPeerId': charlie,
        'memberListExcludesCharlie': excludes(aliceFinal),
        'receivedBobAfterRemoval': aliceReceived != null,
        'rotatedEpoch': rotated,
      },
      'ke006RemovalKeyRotationProof': {
        'rowId': 'KE-006',
        'removedCharlie': excludes(aliceFinal),
        'removedPeerId': charlie,
        'memberListExcludesCharlie': excludes(aliceFinal),
        'rotatedKeyGenerated': rotated > 1,
        'rotatedEpoch': rotated,
        'distributedRotatedKeyToBob': bobRotated['keyEpoch'] == rotated,
        'sentPostRemovalAtRotatedEpoch': aliceSent['keyEpoch'] == rotated,
        'receivedBobAfterRemoval': aliceReceived != null,
      },
      'ke007FirstPostRotationProof': {
        'rowId': 'KE-007',
        'rotatedKeyGenerated': rotated > 1,
        'rotatedEpoch': rotated,
        'waitedForBobRotatedKeyBeforeFirstPostRemovalSend':
            (order['bobRotatedAtMs'] as int) <
            (order['aliceSendStartMs'] as int),
        'sentFirstPostRemovalAtRotatedEpoch': aliceSent['keyEpoch'] == rotated,
        'firstPostRemovalEpoch': aliceSent['keyEpoch'],
        'receivedBobAfterRemoval': aliceReceived != null,
      },
      'st006RotationBoundaryPublishProof': {
        'rowId': 'ST-006',
        'removedCharlie': excludes(aliceFinal),
        'removedPeerId': charlie,
        'memberListExcludesCharlie': excludes(aliceFinal),
        'rotatedEpoch': rotated,
        'receivedBobDuringRotation':
            st006Received != null && heldAtReceive['held'] == true,
        'bobDuringRotationEpoch': st006Received?['keyEpoch'],
        'bobDuringRotationPersistedCount': count(
          st006ReceivedStage,
          'st006BobDuringRotation',
        ),
        'sentAlicePostRotationAtRotatedEpoch': aliceSent['keyEpoch'] == rotated,
        'alicePostRotationEpoch': aliceSent['keyEpoch'],
        'receivedBobAfterRotation': aliceReceived != null,
      },
      'pl006RemovedMediaProof': {
        'rowId': 'PL-006',
        'removedCharlie': excludes(aliceFinal),
        'removedPeerId': charlie,
        'memberListExcludesCharlie': excludes(aliceFinal),
        'mediaUploadedAfterRemoval': upload['blobId'] != null,
        'mediaBlobId': upload['blobId'],
        'uploadAllowedPeers': upload['allowedPeers'],
        'uploadAllowedPeersExcludeRemoved':
            upload['uploadAllowedPeersExcludeRemoved'] == true,
        'uploadAllowedPeersIncludeActive':
            upload['uploadAllowedPeersIncludeActive'] == true,
        'uploadAllowedPeersCount': upload['uploadAllowedPeersCount'],
        'sentPostRemovalMediaAtRotatedEpoch': aliceSent['keyEpoch'] == rotated,
        'bobReceiptSignalObserved': bobReceived != null,
      },
    };

    final bobStatus = bobSentRow?['status'];
    final bobSent = {
      'key': 'bobAfterCharlieRemove',
      'messageId': bobSentRow?['messageId'],
      'text': bobSentRow?['text'],
      'outcome': ['sent', 'delivered'].contains(bobStatus)
          ? 'success'
          : 'status:$bobStatus',
      'senderPeerId': bobSentRow?['senderPeerId'],
      'keyEpoch': bobSentRow?['keyEpoch'],
      'accepted': ['sent', 'delivered'].contains(bobStatus),
    };
    final bobReceivedCount = count(bobReceivedStage, 'aliceAfterCharlieRemove');
    final bobHasRotated = bobFinal['keyEpoch'] == rotated;
    final bobVerdict = {
      ...base(bobFinal, 'bob'),
      'sentMessages': [bobSent],
      'receivedMessages': [
        if (bobReceived != null)
          receivedEntry('aliceAfterCharlieRemove', bobReceived, bobReceivedCount),
      ],
      'persistedMessageCounts': {'aliceAfterCharlieRemove': bobReceivedCount},
      'gm004RemovalProof': {
        'memberListExcludesCharlie': excludes(bobFinal),
        'hasRotatedEpoch': bobHasRotated,
        'rotatedEpoch': rotated,
      },
      'ml005OnlineRemovalProof': {
        'rowId': 'ML-005',
        'memberListExcludesCharlie': excludes(bobFinal),
        'hasRotatedEpoch': bobHasRotated,
        'rotatedEpoch': rotated,
        'receivedAliceAfterRemoval': bobReceived != null,
        'sentPostRemovalAccepted': bobSent['outcome'] == 'success',
      },
      'ke006RemovalKeyRotationProof': {
        'rowId': 'KE-006',
        'memberListExcludesCharlie': excludes(bobFinal),
        'receivedRotatedKey': bobRotated['keyEpoch'] == rotated,
        'hasRotatedEpoch': bobHasRotated,
        'rotatedEpoch': rotated,
        'receivedAliceAfterRemoval': bobReceived != null,
        'sentPostRemovalAtRotatedEpoch': bobSent['keyEpoch'] == rotated,
      },
      'ke007FirstPostRotationProof': {
        'rowId': 'KE-007',
        'receivedRotatedKeyBeforeFirstPostRemovalMessage':
            (order['bobRotatedAtMs'] as int) <
            (order['aliceSendStartMs'] as int),
        'hasRotatedEpochBeforeFirstPostRemovalMessage':
            bobRotated['keyEpoch'] == rotated,
        'rotatedEpoch': rotated,
        'receivedAliceAfterRemoval': bobReceived != null,
        'receivedAliceAfterRemovalAtRotatedEpoch':
            bobReceived?['keyEpoch'] == rotated,
        'aliceMessageEpoch': bobReceived?['keyEpoch'],
        'sentPostRemovalAtRotatedEpoch': bobSent['keyEpoch'] == rotated,
      },
      'st006RotationBoundaryPublishProof': {
        'rowId': 'ST-006',
        'memberListExcludesCharlie': excludes(bobFinal),
        'sentDuringRotationBeforeRotatedKey':
            st006Sent != null && (st006Sent['keyEpoch'] as int) < rotated,
        'bobDuringRotationEpoch': st006Sent?['keyEpoch'],
        'rotatedEpoch': rotated,
        'receivedRotatedKeyBeforeAlicePostRotation':
            (order['bobRotatedAtMs'] as int) <
            (order['aliceSendStartMs'] as int),
        'receivedAlicePostRotation': bobReceived != null,
        'receivedAlicePostRotationAtRotatedEpoch':
            bobReceived?['keyEpoch'] == rotated,
        'alicePostRotationEpoch': bobReceived?['keyEpoch'],
        'sentPostRotationAtRotatedEpoch': bobSent['keyEpoch'] == rotated,
      },
      'pl006RemovedMediaProof': {
        'rowId': 'PL-006',
        'memberListExcludesCharlie': excludes(bobFinal),
        'removedPeerId': charlie,
        'receivedAliceAfterRemoval': bobReceived != null,
        'receivedAliceAfterRemovalAtRotatedEpoch':
            bobReceived?['keyEpoch'] == rotated,
        'bobReceivedMediaDescriptor': bobMedia.length == 1,
        'bobMediaDownloaded':
            bobMedia.length == 1 &&
            (bobMedia.single as Map)['downloadStatus'] == 'done',
        'mediaCount': bobMedia.length,
        'mediaBlobId': bobMedia.isEmpty ? null : (bobMedia.first as Map)['id'],
      },
    };

    final aliceLeak = count(charlieLeak, 'aliceAfterCharlieRemove');
    final bobLeak = count(charlieLeak, 'bobAfterCharlieRemove');
    final st006Leak = count(charlieLeak, 'st006BobDuringRotation');
    final charlieEpoch = (charlieFinal['keyEpoch'] as int?) ?? 0;
    final groupPresent = charlieFinal['groupPresent'] == true;
    final selfPresent = charlieFinal['selfMember'] == true;
    final mediaRows = ((charlieLeak['media'] as List?) ?? const []).length;
    final charlieVerdict = {
      ...base(charlieFinal, 'charlie'),
      'groupId': groupId,
      'keyEpoch': charlieEpoch,
      'sentMessages': [rejected],
      'receivedMessages': const [],
      'persistedMessageCounts': const {},
      'gm004RemovalProof': {
        'onlineBeforeRemoval': true,
        'currentMemberBeforeRemoval': charlieBefore['selfMember'] == true,
        'groupPresentAfterRemoval': groupPresent,
        'selfMemberPresentAfterRemoval': selfPresent,
        'hasRotatedEpoch': charlieEpoch >= rotated,
        'rotatedEpoch': charlieEpoch,
        'postRemovalSendOutcome': rejected['outcome'],
        'postRemovalPublishAccepted': rejected['accepted'] == true,
        'receivedAliceAfterRemoval': aliceLeak > 0,
        'receivedBobAfterRemoval': bobLeak > 0,
        'postRemovalPlaintextCount': aliceLeak + bobLeak,
      },
      'ml005OnlineRemovalProof': {
        'rowId': 'ML-005',
        'onlineBeforeRemoval': charlieBefore['relayReady'] == true,
        'currentMemberBeforeRemoval': charlieBefore['selfMember'] == true,
        'groupPresentAfterRemoval': groupPresent,
        'selfMemberPresentAfterRemoval': selfPresent,
        'hasRotatedEpoch': charlieEpoch >= rotated,
        'rotatedEpoch': charlieEpoch,
        'postRemovalSendOutcome': rejected['outcome'],
        'postRemovalPublishAccepted': rejected['accepted'] == true,
        'receivedAliceAfterRemoval': aliceLeak > 0,
        'receivedBobAfterRemoval': bobLeak > 0,
        'postRemovalPlaintextCount': aliceLeak + bobLeak,
      },
      'ke006RemovalKeyRotationProof': {
        'rowId': 'KE-006',
        'onlineBeforeRemoval': charlieBefore['relayReady'] == true,
        'currentMemberBeforeRemoval': charlieBefore['selfMember'] == true,
        'excludedFromRotatedKeyDistribution': charlieEpoch < rotated,
        'hasRotatedEpoch': charlieEpoch >= rotated,
        'excludedRotatedEpoch': rotated,
        'retainedEpochAfterRemoval': charlieEpoch,
        'postRemovalPublishAccepted': rejected['accepted'] == true,
        'receivedAliceAfterRemoval': aliceLeak > 0,
        'receivedBobAfterRemoval': bobLeak > 0,
        'postRemovalPlaintextCount': aliceLeak + bobLeak,
      },
      'st006RotationBoundaryPublishProof': {
        'rowId': 'ST-006',
        'onlineBeforeRemoval': charlieBefore['relayReady'] == true,
        'currentMemberBeforeRemoval': charlieBefore['selfMember'] == true,
        'groupPresentAfterRemoval': groupPresent,
        'selfMemberPresentAfterRemoval': selfPresent,
        'hasRotatedEpoch': charlieEpoch >= rotated,
        'excludedRotatedEpoch': rotated,
        'retainedEpochAfterRemoval': charlieEpoch,
        'postRemovalPublishAccepted': rejected['accepted'] == true,
        'receivedBobDuringRotation': st006Leak > 0,
        'receivedAlicePostRotation': aliceLeak > 0,
        'postRemovalPlaintextCount': aliceLeak + st006Leak,
      },
      'pl006RemovedMediaProof': {
        'rowId': 'PL-006',
        'onlineBeforeRemoval': charlieBefore['relayReady'] == true,
        'currentMemberBeforeRemoval': charlieBefore['selfMember'] == true,
        'groupPresentAfterRemoval': groupPresent,
        'selfMemberPresentAfterRemoval': selfPresent,
        'mediaBlobId': upload['blobId'],
        'directDownloadAttempted': true,
        'directDownloadDenied': download['directDownloadDenied'] == true,
        'directDownloadOk': download['ok'] == true,
        'directDownloadError': download['errorMessage'],
        'directDownloadOutputBytes': download['outputBytes'],
        'noDirectDownloadPlaintext': download['noDirectDownloadPlaintext'] == true,
        'noPostRemovalMessage': aliceLeak == 0 && bobLeak == 0 && st006Leak == 0,
        'postRemovalPlaintextCount': aliceLeak + bobLeak + st006Leak,
        'mediaRowsAfterRemoval': mediaRows,
        'replayMediaRowsAbsent': mediaRows == 0,
        'pendingDownloadsAfterRemoval': charlieLeak['pendingDownloads'],
      },
    };
    if (failures.isEmpty) {
      final original = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_online_remove',
        relayAddresses: proof['relayAddresses'] as String,
        verdicts: [aliceVerdict, bobVerdict, charlieVerdict]
            .map(Map<String, dynamic>.from)
            .toList(),
      );
      if (!original.ok) failures.add(original.detail);
    }
  } catch (error) {
    failures.add('malformed online-remove proof: ${error.runtimeType} $error');
  }
  return failures;
}
