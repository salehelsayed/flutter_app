import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart'
    show isExactV2DirectChatInitialEnvelope;
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/diagnostics/active_identity_reporter.dart';
import 'package:flutter_app/core/diagnostics/engagement_chat_checkpoint_store.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/direct_media_custody_intent.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../groups/application/b6_daily_activity_test_support.dart'
    show B6ActivityBridge, b6Binding, b6OtherBinding;
import 'send_chat_message_use_case_test.dart' show FakeP2PService;

const _budget = Duration(seconds: 3);
const _account = 'my-peer';
const _contact = 'target-peer';
const _message = 'b15-strict-media-parent';
const _attachment = 'b15-strict-media-attachment';
const _authoredAt = '2026-11-19T00:00:00.000Z';
typedef _Observation = ({
  ActiveIdentityReporter? reporter,
  ActiveIdentityReporterCapture? capture,
});

Future<T> _within<T>(Future<T> future) => future.timeout(_budget);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _StrictMediaHarness h;
  setUp(() async => h = await _within(_StrictMediaHarness.create()));

  test('B15SMW-001 strict initial APPLIED envelope persists weekly admission', () async {
    final original = h.capture();
    final prepared = await h.prepare();
    final sent = await h.send(prepared.attachments, original);
    expect(sent.$1, SendChatMessageResult.nodeNotRunning);
    await h.expectApplied(prepared.attachments, dailyMarks: 1);
    final snapshot = await h.checkpoint();
    expect(snapshot, isNotNull,
      reason: 'real typed strict initial admission must persist its private weekly tuple');
    final witness = snapshot!;
    expect(witness['phase'], 'collecting');
    expect(witness['scope'], {
      'profileBinding': b6Binding, 'consentEpoch': 7, 'week': '2026-W47',
    });
    expect(witness['contacts'], [{
      'account': _contact,
      'incomingSeen': false,
      'deliveredOutgoingSeen': false,
      'outgoing': [{'message': _message, 'generation': _message}],
    }]);
  });

  test('B15SMW-002 crossed parent refuses real final stage without activity', () async {
    final original = h.capture();
    final prepared = await h.prepare();
    h.beforeFinalStage = () async {
      await _within(h.fixture.db.update('messages', {'text': 'crossed'},
        where: 'id = ?', whereArgs: [_message]));
    };
    final sent = await h.send(prepared.attachments, original);
    expect(sent.$1, SendChatMessageResult.sendFailed);
    expect(h.stages.single.outcome, OutgoingOrdinaryMutationOutcome.refused);
    expect(h.stages.single.custodyRow, isNull);
    expect(await _within(h.fixture.db.query('direct_inbox_custody_outbox')), isEmpty);
    expect((await _within(h.fixture.messageRepo.getMessage(_message)))!
      .directMediaCustodyIntentId, h.parent.directMediaCustodyIntentId);
    await h.expectNoActivity();
  });

  test('B15SMW-003 retained envelope retry after OFF ON cannot remint admission', () async {
    final original = h.capture();
    final prepared = await h.prepare();
    await h.send(prepared.attachments, original);
    await h.expectApplied(prepared.attachments, dailyMarks: 1);
    await _within(h.reporter.observeConsent((enabled: false, consentEpoch: 8)));
    await _within(h.reporter.observeConsent((enabled: true, consentEpoch: 9)));
    final retried = await h.send(prepared.attachments, h.capture());
    expect(retried.$1, SendChatMessageResult.nodeNotRunning);
    expect(h.stages, hasLength(1), reason: 'immutable custody replays without another initial stage');
    await _within(h.reporter.flush());
    expect(h.bridge.marks, hasLength(1));
    await h.expectNoWeeklyTuple();
    h.expectNoEgress();
  });

  test('B15SMW-004 present null captured OFF stays authoritative after ON', () async {
    await _within(h.reporter.observeConsent((enabled: false, consentEpoch: 8)));
    final original = h.capture();
    expect(original.capture, isNull);
    await _within(h.reporter.observeConsent((enabled: true, consentEpoch: 9)));
    final prepared = await h.prepare();
    await h.send(prepared.attachments, original);
    await h.expectApplied(prepared.attachments, dailyMarks: 0);
    await h.expectNoWeeklyTuple();
  });

  for (final fence in ['profile', 'epoch', 'OFF']) {
    final id = {'profile': '005', 'epoch': '006', 'OFF': '007'}[fence];
    test('B15SMW-$id $fence fence during real initial stage rejects old capture', () async {
      final original = h.capture();
      final prepared = await h.prepare();
      h.beforeFinalStage = () async {
        if (fence == 'profile') {
          h.reporter.observeIdentity(accountPeerId: _account,
            rootPrivateKeyBase64: base64Encode(List<int>.filled(64, 17)),
            profileBinding: b6OtherBinding);
          await _within(h.reporter.flush());
        } else {
          await _within(h.reporter.observeConsent((enabled: fence != 'OFF', consentEpoch: 8)));
        }
      };
      await h.send(prepared.attachments, original);
      await h.expectApplied(prepared.attachments, dailyMarks: 0);
      await h.expectNoWeeklyTuple();
    });
  }
}

class _StrictMediaHarness {
  _StrictMediaHarness(this.root, this.fixture, this.store, this.bridge,
    this.reporter, this.parent, this.pending) {
    coordinator = PreparedDirectMediaBlobCustodyCoordinator(
      repository: fixture.repo,
      artifactStore: DirectMediaBlobArtifactStore(documentsDirectoryProvider: () async => root),
      // Synthetic artifact/STORE ports preserve real ownership and SQL paths;
      // these cases do not prove encryption, relay storage or delivery.
      prepareArtifact: ({required bridge, required localFilePath}) async {
        final file = File('${root.path}/fixture-ciphertext')
          ..writeAsBytesSync(List<int>.generate(80, (i) => i));
        return EncryptedMediaArtifact(encryptedPath: file.path,
          keyBase64: base64Encode(List<int>.filled(32, 1)),
          nonce: base64Encode(List<int>.filled(12, 2)),
          scheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          contentHash: sha256.convert(file.readAsBytesSync()).toString(), plaintextSize: 64);
      },
      strictUpload: ({required bridge, required attachmentId, required recipientPeerId,
        required ciphertextPath, required contentHash, required ciphertextSize}) async => {
        'ok': true, 'id': attachmentId, 'storeStatus': 'stored',
        'custodyKind': kDirectMediaBlobCustodyKind,
        'custodyContract': kDirectMediaBlobCustodyContract,
        'contentHash': contentHash, 'size': ciphertextSize, 'mime': kDirectMediaBlobTransportMime,
        'expiresAtMs': DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
        'custodyRelayPeerId': 'fixture-relay',
      },
    );
  }

  final Directory root;
  final MediaRepositoryRealDbFixture fixture;
  final EngagementChatCheckpointStore store;
  final B6ActivityBridge bridge;
  final ActiveIdentityReporter reporter;
  final ConversationMessage parent;
  final MediaAttachment pending;
  final p2p = _StoppedStrictMediaP2P();
  final stages = <DirectMediaInboxCustodyDbStageResult>[];
  late final PreparedDirectMediaBlobCustodyCoordinator coordinator;
  Future<void> Function()? beforeFinalStage;

  static Future<_StrictMediaHarness> create() async {
    final root = Directory.systemTemp.createTempSync('b15-strict-media-weekly-');
    addTearDown(() => _within(root.delete(recursive: true)));
    late _StrictMediaHarness h;
    final fixture = await _within(MediaRepositoryRealDbFixture.create(
      dbStageOutgoingDirectMediaInboxCustodyAround: (stage) async {
        final before = h.beforeFinalStage;
        if (before != null) await _within(before());
        final result = await _within(stage());
        h.stages.add(result);
        return result;
      },
    ));
    addTearDown(() => _within(fixture.dispose()));
    await _within(fixture.db.insert('contacts', {
      'peer_id': _contact, 'public_key': 'contact-signing', 'rendezvous': 'test',
      'username': 'Target', 'signature': 'signature', 'scanned_at': _authoredAt,
      'ml_kem_public_key': 'recipient-mlkem',
    }));
    final path = MediaFilePathConvention.relativePathForPendingUpload(
      messageId: _message, attachmentId: _attachment, mime: 'image/jpeg');
    final source = File('${root.path}/$path');
    source.parent.createSync(recursive: true);
    source.writeAsBytesSync(List<int>.filled(64, 7));
    final parent = ConversationMessage(id: _message, contactPeerId: _contact,
      senderPeerId: _account, text: '', timestamp: _authoredAt, status: 'sending',
      isIncoming: false, createdAt: _authoredAt,
      directMediaCustodyIntentId: computeDirectMediaCustodyIntentId(
        messageId: _message, attachmentIds: [_attachment]));
    final pending = MediaAttachment(id: _attachment, messageId: _message,
      mime: 'image/jpeg', size: 64, mediaType: 'image', localPath: path,
      downloadStatus: 'upload_pending', createdAt: _authoredAt, ownerLane: MediaOwnerLane.direct);
    await _within(fixture.messageRepo.saveMessage(parent));
    await _within(fixture.repo.saveAttachment(pending, owner: MediaOwnerLane.direct));
    final store = await _within(EngagementChatCheckpointStore.open('${root.path}/chat'));
    addTearDown(() => _within(store.close()));
    final bridge = B6ActivityBridge();
    bridge.responses['message.encrypt'] = {
      'ok': true, 'kem': 'fixture-kem', 'ciphertext': 'fixture-cipher', 'nonce': 'fixture-nonce',
    };
    final now = DateTime.now().millisecondsSinceEpoch;
    bridge.activityAnswer = (request, revision) async {
      if (request['op'] != 'weeklyProjection' && request['op'] != 'markWeekly') {
        return B6ActivityBridge.reply(request, revision);
      }
      // Controlled native calendar response, not a Dart/Go calendar proof.
      return jsonEncode({'ok': true, 'data': {
        'revision': revision, 'consentEpoch': request['consentEpoch'],
        if (request['op'] == 'markWeekly') 'accepted': true,
        if (request['op'] == 'weeklyProjection') 'weekly': {
          'week': '2026-W47',
          'startUnixMillis': now - const Duration(days: 1).inMilliseconds,
          'endUnixMillis': now + const Duration(days: 6).inMilliseconds,
          'kinds': <String>[], 'acknowledged': <Object>[],
        },
      }});
    };
    final reporter = ActiveIdentityReporter(statePath: '${root.path}/daily.json', chatWitnessStore: store);
    addTearDown(() => _within(reporter.dispose()));
    reporter.attachBridge(bridge);
    reporter.observeIdentity(accountPeerId: _account,
      rootPrivateKeyBase64: base64Encode(List<int>.filled(64, 17)), profileBinding: b6Binding);
    await _within(reporter.observeConsent((enabled: true, consentEpoch: 7)));
    final capture = reporter.captureOwner(expectedAccountPeerId: _account);
    expect(capture, isNotNull);
    final interval = await _within(reporter.weeklyProjectionCaptured(capture!));
    expect(interval?.week, '2026-W47', reason: 'the real reporter accepts the fixture calendar port');
    h = _StrictMediaHarness(root, fixture, store, bridge, reporter, parent, pending);
    return h;
  }

  _Observation capture() =>
    (reporter: reporter, capture: reporter.captureOwner(expectedAccountPeerId: _account));

  Future<PreparedDirectMediaBlobUploadResult> prepare() async {
    // Ordinary first preparation gets no activity capture. The original owner
    // remains with the caller until the fresh INITIAL envelope is staged.
    final prepared = await _within(coordinator.prepareAndUploadFresh(
      bridge: bridge, identityPeerId: _account, recipientPeerId: _contact,
      expectedParent: parent,
      sources: [PreparedDirectMediaBlobSource(attachment: pending,
        plaintextPath: '${root.path}/${pending.localPath}')],
    ));
    expect(prepared.isComplete, isTrue);
    expect(prepared.hasDurableAuthority, isTrue);
    expect(prepared.attachments.single.downloadStatus, 'done');
    final rows = await _within(fixture.repo.loadDirectMediaBlobCustodyForMessage(_message));
    expect(rows.single.state, DirectMediaBlobCustodyState.outgoingStored);
    expect(rows.single.inboxCustodyIncarnationId, isNull);
    expect(prepared.attachments.single.blobCustody?.contentHash, rows.single.contentHash);
    await _within(reporter.flush());
    expect(bridge.marks, isEmpty, reason: 'ordinary preparation is not the activity boundary');
    expect(await _within(fixture.db.query('direct_inbox_custody_outbox')), isEmpty);
    await expectNoWeeklyTuple();
    return prepared;
  }

  Future<(SendChatMessageResult, ConversationMessage?)> send(
    List<MediaAttachment> attachments, _Observation original,
  ) => _within(sendChatMessage(
    p2pService: p2p, messageRepo: fixture.messageRepo, mediaAttachmentRepo: fixture.repo,
    targetPeerId: _contact, text: '', senderPeerId: _account, senderUsername: 'Me',
    messageId: _message, timestamp: _authoredAt, bridge: bridge,
    recipientMlKemPublicKey: 'recipient-mlkem', mediaAttachments: attachments,
    activityReporter: reporter, capturedActivity: original,
  ));

  Future<void> expectApplied(List<MediaAttachment> attachments, {required int dailyMarks}) async {
    final applied = stages.single;
    expect(applied.outcome, OutgoingOrdinaryMutationOutcome.applied);
    expect(applied.hasExactMutableProjection, isTrue);
    expect(applied.messageRow!['id'], _message);
    expect(applied.messageRow!['direct_media_custody_intent_id'], isNull);
    expect(applied.attachmentRows.single['id'], _attachment);
    expect(applied.attachmentRows.single['message_id'], _message);
    expect(applied.attachmentRows.single['download_status'], 'done');
    expect(applied.attachmentRows.single['content_hash'], attachments.single.contentHash);
    final custody = applied.custodyRow!;
    expect(custody['message_id'], _message);
    expect(custody['recipient_peer_id'], _contact);
    expect(custody['incarnation_id'], parent.directMediaCustodyIntentId);
    final commitment = attachments.single.blobCustody!;
    expect(custody['media_blob_manifest_hash'], computeDirectMediaBlobManifestHash([
      DirectMediaBlobManifestProjection(attachmentId: _attachment, commitment: commitment),
    ]));
    expect(custody['media_blob_expires_at_ms'], commitment.expiresAtMs);
    expect(isExactV2DirectChatInitialEnvelope(custody['wire_envelope'] as String,
      messageId: _message, senderPeerId: _account), isTrue);
    expect(custody['wire_envelope'], applied.messageRow!['wire_envelope']);
    final current = (await _within(fixture.messageRepo.getMessage(_message)))!;
    expect(current.directMediaCustodyIntentId, isNull);
    expect(current.status, 'failed', reason: 'stopped-node custody stays truthful');
    final persisted = await _within(fixture.db.query('direct_inbox_custody_outbox'));
    expect(persisted, [custody]);
    expect(await _within(fixture.db.query('media_attachments',
      where: 'message_id = ? AND owner_lane = ?', whereArgs: [_message, 'direct'])),
      applied.attachmentRows);
    final blob = (await _within(fixture.repo.loadDirectMediaBlobCustodyForMessage(_message))).single;
    expect(blob.inboxCustodyIncarnationId, custody['incarnation_id']);
    expect(blob.state, DirectMediaBlobCustodyState.outgoingStored);
    await _within(reporter.flush());
    expect(bridge.marks, hasLength(dailyMarks));
    expectNoEgress();
  }

  void expectNoEgress() {
    expect(p2p.sendCallCount, 0);
    expect(p2p.storeInInboxCallCount, 0);
    expect(p2p.ackCustodyStoreCallCount, 0);
    expect(p2p.expiryStoreCalls, 0);
    expect(bridge.requests.where((request) => request['op'] == 'markWeekly'), isEmpty,
      reason: 'authoring alone supplies neither delivery nor incoming qualification');
  }

  Future<Map<String, dynamic>?> checkpoint() async {
    final file = File(store.checkpointPath);
    if (!await _within(file.exists())) return null;
    return jsonDecode(await _within(file.readAsString())) as Map<String, dynamic>;
  }

  Future<void> expectNoWeeklyTuple() async {
    final snapshot = await checkpoint();
    expect(snapshot?['contacts'] ?? <Object>[], isEmpty);
  }

  Future<void> expectNoActivity() async {
    await _within(reporter.flush());
    expect(bridge.marks, isEmpty);
    await expectNoWeeklyTuple();
    expectNoEgress();
  }
}

class _StoppedStrictMediaP2P extends FakeP2PService implements MediaExpiryBoundedInboxStore {
  _StoppedStrictMediaP2P() : super(currentState: const NodeState(isStarted: false, peerId: _account));
  int expiryStoreCalls = 0;
  @override
  Future<InboxStoreOutcome> storeInMediaExpiryBoundedInboxDetailed(String toPeerId, String message,
    {required int custodyExpiresAtOrBeforeMs, int? timeoutMs}) async {
    expiryStoreCalls++;
    return const InboxStoreOutcome(status: InboxStoreStatus.failed);
  }
}
