import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/diagnostics/active_identity_reporter.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/direct_media_custody_intent.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import 'send_chat_message_use_case_test.dart' show FakeP2PService;

const _budget = Duration(seconds: 3);
const _account = 'my-peer';
const _contact = 'target-peer';
const _message = 'u2-voice-parent';
const _attachment = 'u2-voice-attachment';
const _authoredAt = '2026-11-17T00:00:00.000Z';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _VoiceActivityHarness h;
  setUp(() async => h = await _VoiceActivityHarness.create().timeout(_budget));
  tearDown(() async => h.close().timeout(_budget));

  test('B14U2D-001 strict APPLIED preparation marks before retained offline upload', () async {
    final result = await h.send().timeout(_budget);
    expect(result.$1, SendVoiceMessageResult.uploadQueued);
    expect(h.bridge.marks, hasLength(1));
    expect(h.uploadSawMarks, 1);
    expect(h.uploadSawRows, 1);
    expect((await h.rows().timeout(_budget)).single.state, DirectMediaBlobCustodyState.outgoingPrepared);
  });

  test('B14U2D-002 strict completion and final envelope commit do not double mark', () async {
    h.uploadCompletes = true;
    await h.send().timeout(_budget);
    expect(h.bridge.marks, hasLength(1));
    expect((await h.fixture.messageRepo.getMessage(_message).timeout(_budget))!.directMediaCustodyIntentId, isNull);
    expect(await h.fixture.db.query('direct_inbox_custody_outbox').timeout(_budget), hasLength(1));
  });

  test('B14U2D-003 retained strict reopen never creates a later epoch activity', () async {
    await h.send().timeout(_budget);
    await h.reporter.observeConsent((enabled: true, consentEpoch: 8)).timeout(_budget);
    final second = await h.send(fresh: false).timeout(_budget);
    expect(second.$1, SendVoiceMessageResult.uploadQueued);
    expect(h.prepareCalls, 1, reason: 'reopen uses the original encrypted owner');
    expect(h.bridge.marks, hasLength(1));
  });

  test('B14U2D-004 idempotent strict fresh-entry survivor cannot create another mark', () async {
    await h.send().timeout(_budget);
    final result = await h.coordinator.prepareAndUploadFresh(
      bridge: h.bridge, identityPeerId: _account, recipientPeerId: _contact,
      expectedParent: h.parent, sources: h.sources,
      capturedActivity: h.capture(),
    ).timeout(_budget);
    expect(result.hasDurableAuthority, isTrue);
    expect(h.bridge.marks, hasLength(1));
    expect(await h.rows().timeout(_budget), hasLength(1));
  });

  test('B14U2D-005 crossed parent refuses strict publication without activity', () async {
    h.beforePrepare = () async {
      await h.fixture.db.update('messages', {'text': 'crossed'}, where: 'id = ?', whereArgs: [_message]).timeout(_budget);
    };
    final result = await h.send().timeout(_budget);
    expect(result.$1, SendVoiceMessageResult.sendFailed);
    expect(await h.rows().timeout(_budget), isEmpty);
    expect(h.bridge.marks, isEmpty);
  });

  test('B14U2D-006 encryption refusal cannot count strict preparation start', () async {
    h.beforePrepare = () async => throw StateError('encryption refused');
    final result = await h.send().timeout(_budget);
    expect(result.$1, SendVoiceMessageResult.sendFailed);
    expect(await h.rows().timeout(_budget), isEmpty);
    expect(h.bridge.marks, isEmpty);
  });

  test('B14U2D-007 present-null OFF observation cannot reacquire during strict admission', () async {
    await h.reporter.observeConsent((enabled: false, consentEpoch: 8)).timeout(_budget);
    final original = h.capture();
    expect(original.capture, isNull);
    await h.reporter.observeConsent((enabled: true, consentEpoch: 9)).timeout(_budget);
    final result = await h.send(capturedActivity: original).timeout(_budget);
    expect(result.$1, SendVoiceMessageResult.uploadQueued);
    expect(await h.rows().timeout(_budget), hasLength(1));
    expect(h.bridge.marks, isEmpty);
  });

  for (final (id, turnover) in [('B14U2D-008', 'profile'), ('B14U2D-009', 'epoch')]) {
    test('$id strict preparation $turnover turnover fences the original capture', () async {
      h.beforePrepare = () async {
        if (turnover == 'profile') {
          h.reporter.observeIdentity(accountPeerId: _account,
            rootPrivateKeyBase64: base64Encode(List<int>.filled(64, 17)),
            profileBinding: 'v1:${'b' * 64}');
        }
        await h.reporter.observeConsent((enabled: true, consentEpoch: turnover == 'profile' ? 7 : 8)).timeout(_budget);
      };
      expect((await h.send().timeout(_budget)).$1, SendVoiceMessageResult.uploadQueued);
      expect(await h.rows().timeout(_budget), hasLength(1));
      expect(h.bridge.marks, isEmpty);
    });
  }

  for (final (id, mode) in [('B14U2D-010', 'throw'), ('B14U2D-011', 'block')]) {
    test('$id optional reporter $mode cannot fail or delay durable voice admission', () async {
      h.bridge.throwOnMark = mode == 'throw';
      if (mode == 'block') h.bridge.markBlock = Completer<void>();
      final result = await h.send().timeout(_budget);
      expect(result.$1, SendVoiceMessageResult.uploadQueued);
      expect(await h.rows().timeout(_budget), hasLength(1));
      expect(h.bridge.marks, hasLength(1));
      if (mode == 'block') expect(h.bridge.markBlock!.isCompleted, isFalse);
    });
  }

  test('B14U2D-012 linked APPLIED voice generation marks once for two durable targets', () async {
    await h.seedLinked().timeout(_budget);
    final result = await h.send().timeout(_budget);
    expect(result.$1, SendVoiceMessageResult.uploadQueued);
    expect(h.uploadSawRows, 2);
    expect((await h.rows().timeout(_budget)).map((row) => row.recipientPeerId).toSet(), {_contact, 'linked-peer'});
    expect(h.bridge.marks, hasLength(1));
  });

  test('B14U2D-013 linked idempotent survivor never repeats the fresh activity', () async {
    await h.seedLinked().timeout(_budget);
    await h.send().timeout(_budget);
    final snapshot = (await h.fixture.repo.readDirectContactFanoutSnapshotForMedia(_contact).timeout(_budget))!;
    final result = await h.coordinator.prepareAndUploadFreshFanout(
      bridge: h.bridge, identityPeerId: _account, contactAccountPeerId: _contact,
      snapshot: snapshot, expectedParent: h.parent, sources: h.sources,
      capturedActivity: h.capture(),
    ).timeout(_budget);
    expect(result.hasDurableAuthority, isTrue);
    expect(await h.rows().timeout(_budget), hasLength(2));
    expect(h.bridge.marks, hasLength(1));
  });

  for (final (id, disposition, expectedCount) in [
    ('B14U2D-014', UploadMediaDisposition.connectivityRetryable, 0),
    ('B14U2D-015', UploadMediaDisposition.boundedRetryable, 1),
  ]) {
    test('$id fresh legacy retry APPLIED admits offline voice without inventing retry counts', () async {
      h.failureDisposition = disposition;
      final result = await h.send(strict: false).timeout(_budget);
      expect(result.$1, SendVoiceMessageResult.uploadQueued);
      final pending = (await h.fixture.repo.getAttachmentsForMessage(_message, owner: MediaOwnerLane.direct).timeout(_budget)).single;
      expect(pending.uploadRetryCount ?? 0, expectedCount);
      expect(pending.downloadStatus, 'upload_pending');
      expect(h.bridge.marks, hasLength(1));
      expect(await h.rows().timeout(_budget), isEmpty);
    });
  }

  test('B14U2D-016 OFF-created manual retry rearm reset cannot make an existing voice fresh', () async {
    await h.reporter.observeConsent((enabled: false, consentEpoch: 8)).timeout(_budget);
    await h.send(strict: false).timeout(_budget);
    await h.fixture.db.update('messages', {'status': 'failed'}, where: 'id = ?', whereArgs: [_message]).timeout(_budget);
    await h.fixture.db.update('media_attachments', {'download_status': 'upload_failed', 'upload_retry_count': kMaxUploadRetries},
      where: 'id = ?', whereArgs: [_attachment]).timeout(_budget);
    final rearmed = await dbRearmDirectUploadRetryForManualRetry(h.fixture.db, messageId: _message,
      attachments: [ManualUploadRetryAttachmentExpectation(attachmentId: _attachment,
        storedLocalPath: h.pending.localPath!, downloadStatus: 'upload_failed', uploadRetryCount: kMaxUploadRetries)],
    ).timeout(_budget);
    expect(rearmed, isTrue);
    await h.reporter.observeConsent((enabled: true, consentEpoch: 9)).timeout(_budget);
    h.failureDisposition = UploadMediaDisposition.boundedRetryable;
    expect((await h.send(strict: false, fresh: false).timeout(_budget)).$1, SendVoiceMessageResult.uploadQueued);
    final pending = (await h.fixture.repo.getAttachmentsForMessage(_message, owner: MediaOwnerLane.direct).timeout(_budget)).single;
    expect(pending.uploadRetryCount, 1, reason: 'a count1 result still has no fresh-authoring authority');
    expect(h.bridge.marks, isEmpty);
  });

  for (final (id, initiallyEnabled) in [('B14U2D-017', false), ('B14U2D-018', true)]) {
    test('$id retained legacy later finalization cannot backfill or duplicate activity', () async {
      if (!initiallyEnabled) await h.reporter.observeConsent((enabled: false, consentEpoch: 8)).timeout(_budget);
      await h.send(strict: false).timeout(_budget);
      expect(h.bridge.marks, initiallyEnabled ? hasLength(1) : isEmpty);
      await h.reporter.observeConsent((enabled: true, consentEpoch: 9)).timeout(_budget);
      h.uploadCompletes = true;
      final finalized = await h.send(strict: false, fresh: false).timeout(_budget);
      expect(finalized.$1, SendVoiceMessageResult.sendFailed,
        reason: 'the stopped node affects transport after durable custody admission');
      expect((await h.fixture.messageRepo.getMessage(_message).timeout(_budget))!.directMediaCustodyIntentId, isNull);
      expect(await h.fixture.db.query('direct_inbox_custody_outbox').timeout(_budget), hasLength(1));
      expect(h.bridge.marks, initiallyEnabled ? hasLength(1) : isEmpty);
    });
  }

  test('B14U2D-019 crossed legacy failure projection cannot admit activity', () async {
    h.beforeLegacyUpload = () async {
      await h.fixture.db.update('messages', {'text': 'crossed'}, where: 'id = ?', whereArgs: [_message]).timeout(_budget);
    };
    expect((await h.send(strict: false).timeout(_budget)).$1, SendVoiceMessageResult.uploadFailed);
    expect(h.bridge.marks, isEmpty);
  });

  test('B14U2D-020 terminal encryption failure is not retained communication admission', () async {
    h.failureDisposition = UploadMediaDisposition.terminal;
    h.failureStage = UploadMediaStage.encryption;
    expect((await h.send(strict: false).timeout(_budget)).$1, SendVoiceMessageResult.uploadFailed);
    expect(h.bridge.marks, isEmpty);
    final pending = (await h.fixture.repo.getAttachmentsForMessage(_message, owner: MediaOwnerLane.direct).timeout(_budget)).single;
    expect(pending.downloadStatus, 'upload_failed');
  });

  test('B14U2D-021 legacy present-null observation stays excluded after enabling', () async {
    await h.reporter.observeConsent((enabled: false, consentEpoch: 8)).timeout(_budget);
    final original = h.capture();
    await h.reporter.observeConsent((enabled: true, consentEpoch: 9)).timeout(_budget);
    expect((await h.send(strict: false, capturedActivity: original).timeout(_budget)).$1, SendVoiceMessageResult.uploadQueued);
    expect(h.bridge.marks, isEmpty);
  });

  test('B14U2D-022 consent turnover during legacy upload fences the original admission capture', () async {
    h.beforeLegacyUpload = () => h.reporter.observeConsent((enabled: true, consentEpoch: 8)).timeout(_budget);
    expect((await h.send(strict: false).timeout(_budget)).$1, SendVoiceMessageResult.uploadQueued);
    expect(h.bridge.marks, isEmpty);
  });

  for (final (id, linked) in [('B14U2D-023', false), ('B14U2D-024', true)]) {
    test('$id committed ${linked ? 'linked' : 'single'} hydration exception preserves admission and ciphertext', () async {
      if (linked) await h.seedLinked().timeout(_budget);
      h.keyStore.failHydration = true;
      final result = await h.send().timeout(_budget);
      expect(result.$1, SendVoiceMessageResult.uploadQueued);
      expect(h.keyStore.failedHydrations, greaterThan(0));
      expect(await h.rows().timeout(_budget), hasLength(linked ? 2 : 1));
      expect(h.bridge.marks, hasLength(1));
      expect(h.uploadSawRows, isNull, reason: 'authority-only is not an upload projection');
      expect(await h.ownedArtifactsPresent().timeout(_budget), isTrue);
    });
  }

  for (final (id, linked) in [('B14U2D-025', false), ('B14U2D-026', true)]) {
    test('$id idempotent ${linked ? 'linked' : 'single'} hydration exception retains authority without new activity', () async {
      if (linked) await h.seedLinked().timeout(_budget);
      await h.send().timeout(_budget);
      h.uploadSawRows = null;
      h.keyStore.failHydration = true;
      if (linked) {
        final snapshot = (await h.fixture.repo.readDirectContactFanoutSnapshotForMedia(_contact).timeout(_budget))!;
        final result = await h.coordinator.prepareAndUploadFreshFanout(
          bridge: h.bridge, identityPeerId: _account, contactAccountPeerId: _contact,
          snapshot: snapshot, expectedParent: h.parent, sources: h.sources,
          capturedActivity: h.capture(),
        ).timeout(_budget);
        expect(result.state, PreparedDirectMediaBlobUploadState.retained);
      } else {
        final result = await h.coordinator.prepareAndUploadFresh(
          bridge: h.bridge, identityPeerId: _account, recipientPeerId: _contact,
          expectedParent: h.parent, sources: h.sources, capturedActivity: h.capture(),
        ).timeout(_budget);
        expect(result.state, PreparedDirectMediaBlobUploadState.retained);
      }
      expect(h.keyStore.failedHydrations, greaterThan(0));
      expect(h.bridge.marks, hasLength(1));
      expect(h.uploadSawRows, isNull);
      expect(await h.ownedArtifactsPresent().timeout(_budget), isTrue);
    });
  }

  test('B14U2D-027 authority-only admission can later finalize without another activity', () async {
    h.keyStore.failHydration = true;
    await h.send().timeout(_budget);
    expect(h.bridge.marks, hasLength(1));
    h.keyStore.failHydration = false;
    h.uploadCompletes = true;
    await h.send(fresh: false).timeout(_budget);
    expect(h.prepareCalls, 1, reason: 'the admitted encrypted generation must be reused');
    expect((await h.fixture.messageRepo.getMessage(_message).timeout(_budget))!.directMediaCustodyIntentId, isNull);
    expect(h.bridge.marks, hasLength(1));
  });

  test('B14U2D-028 precommit secure-key write failure does not invent durable authority', () async {
    h.keyStore.failWrites = true;
    expect((await h.send().timeout(_budget)).$1, SendVoiceMessageResult.sendFailed);
    expect(await h.rows().timeout(_budget), isEmpty);
    expect(h.bridge.marks, isEmpty);
  });

  for (final (id, linked) in [('B14U2D-029', false), ('B14U2D-030', true)]) {
    test('$id committed ${linked ? 'linked' : 'single'} missing hydrated key retains authority without upload', () async {
      if (linked) await h.seedLinked().timeout(_budget);
      h.keyStore.missingHydration = true;
      expect((await h.send().timeout(_budget)).$1, SendVoiceMessageResult.uploadQueued);
      expect(h.keyStore.failedHydrations, greaterThan(0));
      expect(h.bridge.marks, hasLength(1));
      expect(h.uploadSawRows, isNull);
      expect(await h.ownedArtifactsPresent().timeout(_budget), isTrue);
    });
  }

  for (final (id, linked) in [('B14U2D-031', false), ('B14U2D-032', true)]) {
    test('$id ${linked ? 'linked' : 'single'} reopen retains idempotent authority when hydration fails', () async {
      if (linked) await h.seedLinked().timeout(_budget);
      await h.send().timeout(_budget);
      final parent = (await h.fixture.messageRepo.getMessage(_message).timeout(_budget))!;
      final attachments = await h.fixture.repo.getAttachmentsForMessage(_message, owner: MediaOwnerLane.direct).timeout(_budget);
      h.keyStore.failHydration = true;
      h.uploadSawRows = null;
      if (linked) {
        final snapshot = (await h.fixture.repo.readDirectContactFanoutSnapshotForMedia(_contact).timeout(_budget))!;
        final result = await h.coordinator.reopenAndUploadFanout(
          bridge: h.bridge, identityPeerId: _account, contactAccountPeerId: _contact,
          snapshot: snapshot, expectedParent: parent, expectedAttachments: attachments,
        ).timeout(_budget);
        expect(result.state, PreparedDirectMediaBlobUploadState.retained);
      } else {
        final result = await h.coordinator.reopenAndUpload(
          bridge: h.bridge, identityPeerId: _account, recipientPeerId: _contact,
          expectedParent: parent, expectedAttachments: attachments,
        ).timeout(_budget);
        expect(result.state, PreparedDirectMediaBlobUploadState.retained);
      }
      expect(h.keyStore.failedHydrations, greaterThan(0));
      expect(h.prepareCalls, 1);
      expect(h.uploadSawRows, isNull);
      expect(h.bridge.marks, hasLength(1));
      expect(await h.ownedArtifactsPresent().timeout(_budget), isTrue);
    });
  }
}

class _VoiceActivityHarness {
  _VoiceActivityHarness(this.root, this.fixture, this.bridge, this.reporter, this.parent, this.pending, this.recording) {
    coordinator = PreparedDirectMediaBlobCustodyCoordinator(
      repository: fixture.repo,
      artifactStore: DirectMediaBlobArtifactStore(documentsDirectoryProvider: () async => root),
      prepareArtifact: ({required bridge, required localFilePath}) async {
        prepareCalls++;
        await beforePrepare?.call();
        final file = File('${root.path}/encrypted-$prepareCalls')..writeAsBytesSync(List<int>.generate(80, (i) => i));
        return EncryptedMediaArtifact(encryptedPath: file.path,
          keyBase64: base64Encode(List<int>.filled(32, 1)), nonce: base64Encode(List<int>.filled(12, 2)),
          scheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          contentHash: sha256.convert(file.readAsBytesSync()).toString(), plaintextSize: recording.sizeBytes);
      },
      strictUpload: ({required bridge, required attachmentId, required recipientPeerId,
        required ciphertextPath, required contentHash, required ciphertextSize}) async {
        uploadSawMarks = this.bridge.marks.length;
        uploadSawRows = (await rows().timeout(_budget)).length;
        if (!uploadCompletes) return {'ok': false, 'errorCode': 'NOT_CONNECTED'};
        return {'ok': true, 'id': attachmentId, 'storeStatus': 'stored',
          'custodyKind': kDirectMediaBlobCustodyKind, 'custodyContract': kDirectMediaBlobCustodyContract,
          'contentHash': contentHash, 'size': ciphertextSize, 'mime': kDirectMediaBlobTransportMime,
          'expiresAtMs': DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
          'custodyRelayPeerId': 'u2-test-relay'};
      },
    );
  }
  final Directory root;
  final MediaRepositoryRealDbFixture fixture;
  final _VoiceActivityBridge bridge;
  final ActiveIdentityReporter reporter;
  final ConversationMessage parent;
  final MediaAttachment pending;
  final AudioRecording recording;
  late final PreparedDirectMediaBlobCustodyCoordinator coordinator;
  Future<void> Function()? beforePrepare;
  Future<void> Function()? beforeLegacyUpload;
  bool uploadCompletes = false;
  int prepareCalls = 0;
  int? uploadSawMarks;
  int? uploadSawRows;
  UploadMediaDisposition failureDisposition = UploadMediaDisposition.connectivityRetryable;
  UploadMediaStage failureStage = UploadMediaStage.transport;

  static Future<_VoiceActivityHarness> create() async {
    final root = Directory.systemTemp.createTempSync('u2-voice-activity-');
    final keyStore = _HydrationFailingVoiceKeyStore();
    final fixture = await MediaRepositoryRealDbFixture.create(secureKeyStore: keyStore).timeout(_budget);
    keyStore.hasCommittedRows = () async => (await fixture.repo.loadDirectMediaBlobCustodyForMessage(_message).timeout(_budget)).isNotEmpty;
    await fixture.db.insert('contacts', {'peer_id': _contact, 'public_key': 'contact-signing',
      'rendezvous': 'test', 'username': 'Target', 'signature': 'signature',
      'scanned_at': _authoredAt, 'ml_kem_public_key': 'recipient-mlkem'}).timeout(_budget);
    final path = MediaFilePathConvention.relativePathForPendingUpload(
      messageId: _message, attachmentId: _attachment, mime: 'audio/mp4');
    final file = File('${root.path}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(List<int>.filled(64, 7));
    final recording = AudioRecording(filePath: file.path, durationMs: 1200, sizeBytes: 64);
    final parent = ConversationMessage(id: _message, contactPeerId: _contact, senderPeerId: _account,
      text: '', timestamp: _authoredAt, status: 'sending', isIncoming: false, createdAt: _authoredAt,
      directMediaCustodyIntentId: computeDirectMediaCustodyIntentId(messageId: _message, attachmentIds: [_attachment]));
    final pending = MediaAttachment(id: _attachment, messageId: _message, mime: 'audio/mp4', size: 64,
      mediaType: 'audio', durationMs: 1200, localPath: path, downloadStatus: 'upload_pending',
      createdAt: _authoredAt, ownerLane: MediaOwnerLane.direct);
    await fixture.messageRepo.saveMessage(parent).timeout(_budget);
    await fixture.repo.saveAttachment(pending, owner: MediaOwnerLane.direct).timeout(_budget);
    final bridge = _VoiceActivityBridge();
    final reporter = ActiveIdentityReporter(statePath: '/unused/u2-voice.json');
    reporter.attachBridge(bridge);
    reporter.observeIdentity(accountPeerId: _account,
      rootPrivateKeyBase64: base64Encode(List<int>.filled(64, 17)), profileBinding: 'v1:${'a' * 64}');
    await reporter.observeConsent((enabled: true, consentEpoch: 7)).timeout(_budget);
    return _VoiceActivityHarness(root, fixture, bridge, reporter, parent, pending, recording);
  }

  ({ActiveIdentityReporter? reporter, ActiveIdentityReporterCapture? capture}) capture() =>
      (reporter: reporter, capture: reporter.captureOwner(expectedAccountPeerId: _account));
  List<PreparedDirectMediaBlobSource> get sources =>
      [PreparedDirectMediaBlobSource(attachment: pending, plaintextPath: recording.filePath)];
  Future<List<DirectMediaBlobCustodyRow>> rows() => fixture.repo.loadDirectMediaBlobCustodyForMessage(_message);
  _HydrationFailingVoiceKeyStore get keyStore => fixture.secureKeyStore as _HydrationFailingVoiceKeyStore;
  Future<bool> ownedArtifactsPresent() async {
    final store = DirectMediaBlobArtifactStore(documentsDirectoryProvider: () async => root);
    for (final row in await rows().timeout(_budget)) {
      final artifact = await store.verifyOwnedArtifact(identityPeerId: _account,
        relativePath: row.ciphertextRelativePath!, expectedContentHash: row.contentHash,
        expectedCiphertextSize: row.ciphertextSize).timeout(_budget);
      if (artifact == null) return false;
    }
    return true;
  }

  Future<(SendVoiceMessageResult, ConversationMessage?)> send({
    bool strict = true, bool fresh = true,
    ({ActiveIdentityReporter? reporter, ActiveIdentityReporterCapture? capture})? capturedActivity,
  }) => sendVoiceMessage(
    p2pService: _VoiceCustodyP2PService(), messageRepo: fixture.messageRepo,
    targetPeerId: _contact, senderPeerId: _account, senderUsername: 'Me', recording: recording,
    bridge: bridge, activityReporter: reporter, capturedActivity: capturedActivity ?? capture(),
    recipientMlKemPublicKey: 'recipient-mlkem', mediaAttachmentRepo: fixture.repo,
    messageId: _message, preassignedMessageIdIsFresh: fresh, timestamp: _authoredAt,
    blobId: _attachment, directMediaBlobCustodyClientEnabled: strict,
    directMediaBlobCustodyCoordinator: coordinator,
    uploadMediaFn: ({required bridge, required localFilePath, required mime, required recipientPeerId,
      mediaFileManager, width, height, durationMs, waveform, allowedPeers, blobId,
      deleteSourceWhenDone = false, preparedArtifact}) async {
      await beforeLegacyUpload?.call();
      if (!uploadCompletes) {
        return UploadMediaFailed(stage: failureStage,
          disposition: failureDisposition, errorCode: 'U2_TEST_FAILURE');
      }
      final completedRelativePath = MediaFilePathConvention.relativePathForAttachment(
        contactPeerId: recipientPeerId, blobId: blobId!, mime: mime);
      final completedFile = File('${root.path}/$completedRelativePath');
      await completedFile.parent.create(recursive: true).timeout(_budget);
      await File(localFilePath).copy(completedFile.path).timeout(_budget);
      return UploadMediaSucceeded(MediaAttachment(id: blobId, messageId: '', mime: mime,
        size: recording.sizeBytes, mediaType: 'audio', durationMs: recording.durationMs,
        localPath: completedRelativePath, downloadStatus: 'done', createdAt: _authoredAt,
        contentHash: 'a' * 64, encryptionKeyBase64: base64Encode(List<int>.filled(32, 1)),
        encryptionNonce: base64Encode(List<int>.filled(12, 2)),
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1));
    },
  );

  Future<void> seedLinked() async {
    await fixture.db.insert('direct_contact_device_roster_metadata', {
      'contact_account_peer_id': _contact, 'roster_initialized': 1,
      'legacy_target_state': 'active', 'initialized_at': _authoredAt,
      'legacy_revoked_at': null, 'updated_at': _authoredAt}).timeout(_budget);
    await fixture.db.insert('direct_contact_device_bindings', {
      'contact_account_peer_id': _contact, 'device_id': 'u2-linked',
      'verified_account_signing_public_key': 'contact-signing', 'transport_peer_id': 'linked-peer',
      'transport_public_key': 'linked-signing', 'device_ml_kem_public_key': 'linked-mlkem',
      'binding_fingerprint': '9' * 64, 'state': 'active',
      'staged_at': _authoredAt, 'decided_at': _authoredAt}).timeout(_budget);
  }
  Future<void> close() async {
    final blocked = bridge.markBlock;
    if (blocked != null && !blocked.isCompleted) blocked.complete();
    await reporter.dispose().timeout(_budget);
    await fixture.dispose().timeout(_budget);
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

class _VoiceActivityBridge extends FakeBridge {
  _VoiceActivityBridge() : super(initialResponses: {
    'message.encrypt': {'ok': true, 'kem': 'test-kem', 'ciphertext': 'test-cipher', 'nonce': 'test-nonce'},
  });
  final marks = <Map<String, dynamic>>[];
  Completer<void>? markBlock;
  bool throwOnMark = false;
  int revision = 0;
  @override
  bool get isInitialized => true;
  @override
  Future<String> send(String message) async {
    final envelope = jsonDecode(message) as Map<String, dynamic>;
    if (envelope['cmd'] != 'active_identity_reporter_v1') return super.send(message);
    final payload = Map<String, dynamic>.from(envelope['payload'] as Map);
    final op = payload['op'];
    if (op == 'mark') {
      marks.add(payload);
      if (throwOnMark) throw StateError('optional reporter unavailable');
      await markBlock?.future;
    }
    return jsonEncode({'ok': true, 'data': {
      'revision': op == 'configure' ? ++revision : payload['revision'],
      'consentEpoch': payload['consentEpoch'],
      if (op == 'configure') 'configured': payload['enabled'] == true && payload['profileBinding'] != '',
      if (op == 'mark') 'accepted': true,
      if (op == 'flush') 'queued': true,
    }});
  }
}

class _VoiceCustodyP2PService extends FakeP2PService implements MediaExpiryBoundedInboxStore {
  _VoiceCustodyP2PService() : super(currentState: const NodeState(isStarted: false, peerId: _account));
  @override
  Future<InboxStoreOutcome> storeInMediaExpiryBoundedInboxDetailed(String toPeerId, String message,
    {required int custodyExpiresAtOrBeforeMs, int? timeoutMs}) async =>
      const InboxStoreOutcome(status: InboxStoreStatus.failed);
}

class _HydrationFailingVoiceKeyStore extends RecordingSecureKeyStore {
  bool failHydration = false;
  bool missingHydration = false;
  bool failWrites = false;
  int failedHydrations = 0;
  Future<bool> Function()? hasCommittedRows;
  @override
  Future<String?> read(String key) async {
    if ((failHydration || missingHydration) && await hasCommittedRows!.call().timeout(_budget)) {
      failedHydrations++;
      if (missingHydration) return null;
      throw StateError('postcommit key hydration unavailable');
    }
    return super.read(key);
  }
  @override
  Future<void> write(String key, String value) {
    if (failWrites) throw StateError('precommit key write unavailable');
    return super.write(key, value);
  }
}
