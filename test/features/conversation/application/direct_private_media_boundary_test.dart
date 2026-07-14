import 'dart:io';

import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_service.dart';
import 'package:flutter_app/features/conversation/application/build_received_media_forward.dart';
import 'package:flutter_app/features/conversation/application/private_media_action_eligibility.dart';
import 'package:flutter_app/features/conversation/application/received_media_action_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/repositories/fake_media_attachment_repository.dart';

class _RecordingEgressService extends ReceivedMediaEgressService {
  int calls = 0;

  @override
  Future<MediaEgressResult> perform({
    required String requestId,
    required MediaEgressDestination destination,
    required List<ReceivedMediaEgressCandidate> selection,
  }) async {
    calls++;
    return MediaEgressResult(
      requestId: requestId,
      outcome: MediaEgressOutcome.saved,
      items: const [],
    );
  }
}

class _WrongOwnerRepository extends FakeMediaAttachmentRepository {
  _WrongOwnerRepository(this.row);

  final MediaAttachment row;

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => [row];
}

void main() {
  late Directory tempDir;
  late String path;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('direct_private_boundary_');
    path = '${tempDir.path}/private.jpg';
    File(path).writeAsBytesSync(const [1, 2, 3]);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  ConversationMessage parent({
    String id = 'message-1',
    PrivateMediaPolicy policy = const PrivateMediaPolicy.ordinary(),
    PrivateMediaLifecycleState state = PrivateMediaLifecycleState.none,
    bool incoming = true,
    String? hiddenAt,
    String? deletedAt,
  }) {
    return ConversationMessage(
      id: id,
      contactPeerId: 'peer-contact',
      senderPeerId: 'peer-contact',
      text: 'SECRET caption',
      timestamp: '2026-07-11T10:00:00.000Z',
      status: 'delivered',
      isIncoming: incoming,
      createdAt: '2026-07-11T10:00:00.000Z',
      hiddenAt: hiddenAt,
      deletedAt: deletedAt,
      privateMediaPolicy: policy,
      privateMediaState: state,
      privateMediaExpiresAtMs: policy.isPrivate ? 1_800_000_000_000 : null,
      privateMediaTerminalAtMs: state.isTerminal ? 1_800_000_000_100 : null,
    );
  }

  MediaAttachment row({
    String id = 'attachment-1',
    String messageId = 'message-1',
    MediaOwnerLane? owner = MediaOwnerLane.direct,
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: 'image/jpeg',
      size: 3,
      mediaType: 'image',
      localPath: path,
      downloadStatus: 'done',
      createdAt: '2026-07-11T10:00:00.000Z',
      ownerLane: owner,
    );
  }

  test('missing, wrong-owner, and stale identities fail every capability', () {
    final cases = <DirectPrivateMediaActionDecision>[
      DirectPrivateMediaActionEligibility.evaluate(
        parent: null,
        attachment: row(),
        expectedMessageId: 'message-1',
        expectedAttachmentId: 'attachment-1',
      ),
      DirectPrivateMediaActionEligibility.evaluate(
        parent: parent(),
        attachment: row(owner: MediaOwnerLane.group),
        expectedMessageId: 'message-1',
        expectedAttachmentId: 'attachment-1',
      ),
      DirectPrivateMediaActionEligibility.evaluate(
        parent: parent(),
        attachment: row(messageId: 'same-id-group-parent'),
        expectedMessageId: 'message-1',
        expectedAttachmentId: 'attachment-1',
      ),
      DirectPrivateMediaActionEligibility.evaluate(
        parent: parent(),
        attachment: row(id: 'stale-attachment'),
        expectedMessageId: 'message-1',
        expectedAttachmentId: 'attachment-1',
      ),
    ];

    expect(
      cases.map((decision) => decision.reason),
      <DirectPrivateMediaEligibilityReason>[
        DirectPrivateMediaEligibilityReason.parentMissing,
        DirectPrivateMediaEligibilityReason.wrongOwner,
        DirectPrivateMediaEligibilityReason.staleIdentity,
        DirectPrivateMediaEligibilityReason.staleIdentity,
      ],
    );
    for (final decision in cases) {
      for (final action in DirectPrivateMediaAction.values) {
        expect(decision.allows(action), isFalse, reason: action.name);
      }
      expect(decision.canEnterPictureInPicture, isFalse);
    }
  });

  test(
    'default egress authority re-reads a private parent and makes zero call',
    () async {
      final repo = FakeMediaAttachmentRepository()..seed([row()]);
      final service = _RecordingEgressService();
      var current = parent();
      final controller = ReceivedMediaActionController(
        loadParentMessage: (_) async => current,
        mediaAttachmentRepo: repo,
        egressService: service,
        resolveStoredPath: (storedPath) => storedPath,
      );

      current = parent(
        policy: const PrivateMediaPolicy.viewOnce(),
        state: PrivateMediaLifecycleState.available,
      );
      final result = await controller.performEgress(
        identity: const DirectReceivedMediaActionIdentity(
          messageId: 'message-1',
          attachmentId: 'attachment-1',
        ),
        destination: MediaEgressDestination.share,
      );

      expect(result.denial, DirectMediaEgressDenial.protected);
      expect(service.calls, 0);
    },
  );

  test(
    'direct lookup re-verifies owner even when repository violates scope',
    () async {
      final service = _RecordingEgressService();
      final controller = ReceivedMediaActionController(
        loadParentMessage: (_) async => parent(),
        mediaAttachmentRepo: _WrongOwnerRepository(
          row(owner: MediaOwnerLane.group),
        ),
        egressService: service,
        resolveStoredPath: (storedPath) => storedPath,
      );

      final result = await controller.performEgress(
        identity: const DirectReceivedMediaActionIdentity(
          messageId: 'message-1',
          attachmentId: 'attachment-1',
        ),
        destination: MediaEgressDestination.files,
      );

      expect(result.denial, DirectMediaEgressDenial.wrongOwner);
      expect(service.calls, 0);
    },
  );

  test(
    'exact identity and central policy cannot be bypassed by permissive seams',
    () async {
      Future<DirectReceivedMediaEgressOutcome> perform({
        required ConversationMessage? currentParent,
        required MediaAttachment currentRow,
      }) async {
        final service = _RecordingEgressService();
        final controller = ReceivedMediaActionController(
          loadParentMessage: (_) async => currentParent,
          mediaAttachmentRepo: _WrongOwnerRepository(currentRow),
          egressService: service,
          qualifier: (_, _) async => DirectMediaLaneQualification.eligible,
          resolveStoredPath: (storedPath) => storedPath,
        );
        final outcome = await controller.performEgress(
          identity: const DirectReceivedMediaActionIdentity(
            messageId: 'message-1',
            attachmentId: 'attachment-1',
          ),
          destination: MediaEgressDestination.files,
        );
        expect(service.calls, 0);
        return outcome;
      }

      expect(
        (await perform(
          currentParent: parent(id: 'wrong-parent'),
          currentRow: row(),
        )).denial,
        DirectMediaEgressDenial.staleIdentity,
      );
      expect(
        (await perform(
          currentParent: parent(),
          currentRow: row(messageId: 'wrong-message'),
        )).denial,
        DirectMediaEgressDenial.staleIdentity,
      );
      expect(
        (await perform(
          currentParent: parent(
            policy: const PrivateMediaPolicy.protected(),
            state: PrivateMediaLifecycleState.available,
          ),
          currentRow: row(),
        )).denial,
        DirectMediaEgressDenial.protected,
      );
      expect(
        (await perform(
          currentParent: parent(
            policy: const PrivateMediaPolicy.viewOnce(),
            state: PrivateMediaLifecycleState.expired,
          ),
          currentRow: row(),
        )).denial,
        DirectMediaEgressDenial.expired,
      );
      expect(
        (await perform(
          currentParent: parent(hiddenAt: '2026-07-11T10:01:00.000Z'),
          currentRow: row(),
        )).denial,
        DirectMediaEgressDenial.policyUnavailable,
      );
      expect(
        (await perform(
          currentParent: parent(
            policy: PrivateMediaPolicy.fromJson(const {
              'version': 1,
              'mode': 'ordinary',
            }),
          ),
          currentRow: row(),
        )).denial,
        DirectMediaEgressDenial.policyUnavailable,
      );
    },
  );

  test(
    'Info requires an exact live row except after terminal private cleanup',
    () async {
      final emptyRepo = FakeMediaAttachmentRepository();
      final service = _RecordingEgressService();
      var currentParent = parent(
        policy: const PrivateMediaPolicy.protected(),
        state: PrivateMediaLifecycleState.available,
      );
      final controller = ReceivedMediaActionController(
        loadParentMessage: (_) async => currentParent,
        mediaAttachmentRepo: emptyRepo,
        egressService: service,
      );
      const identity = DirectReceivedMediaActionIdentity(
        messageId: 'message-1',
        attachmentId: 'attachment-1',
      );

      expect(await controller.loadInfo(identity), isNull);

      currentParent = parent(
        policy: const PrivateMediaPolicy.viewOnce(),
        state: PrivateMediaLifecycleState.consumed,
      );
      final terminal = await controller.loadInfo(identity);
      expect(terminal, isNotNull);
      expect(terminal!.isPrivacyMinimized, isTrue);
      expect(terminal.mime, isEmpty);
      expect(terminal.mediaType, isEmpty);
      expect(terminal.sizeBytes, 0);
      expect(terminal.width, isNull);
      expect(terminal.height, isNull);
      expect(terminal.durationMs, isNull);
      expect(terminal.privateInfo!.state, PrivateMediaLifecycleState.consumed);

      emptyRepo.seed([row()]);
      currentParent = parent();
      final ordinary = await controller.loadInfo(identity);
      expect(ordinary, isNotNull);
      expect(ordinary!.isPrivacyMinimized, isFalse);
      expect(ordinary.mime, 'image/jpeg');
      expect(ordinary.mediaType, 'image');
      expect(ordinary.sizeBytes, 3);
    },
  );

  test('Forward re-reads the parent before token or file work', () async {
    final repo = FakeMediaAttachmentRepository()..seed([row()]);
    var tokenCalls = 0;
    var fileProbeCalls = 0;
    final builder = BuildReceivedMediaForward(
      loadParentMessage: (_) async => parent(
        policy: const PrivateMediaPolicy.protected(),
        state: PrivateMediaLifecycleState.available,
      ),
      mediaAttachmentRepository: repo,
      operationTokenFactory: () {
        tokenCalls++;
        return 'operation-token';
      },
      validateCanonicalPlaintext:
          ({required attachment, required ownerScopeId}) async {
            fileProbeCalls++;
            return CanonicalGroupMediaPlaintextValidationResult.valid(
              attachment.localPath!,
            );
          },
    );

    final result = await builder.build(parent: parent());

    expect(result.denial, DirectMediaForwardDenial.privateMediaRestricted);
    expect(tokenCalls, 0);
    expect(fileProbeCalls, 0);
    expect(repo.getAttachmentsForMessageCallCount, 0);
  });

  test(
    'Forward denies every private terminal unsupported hidden or missing parent before side effects',
    () async {
      final cases = <ConversationMessage?>[
        null,
        parent(
          policy: const PrivateMediaPolicy.protected(),
          state: PrivateMediaLifecycleState.available,
        ),
        parent(
          policy: const PrivateMediaPolicy.viewOnce(),
          state: PrivateMediaLifecycleState.consumed,
        ),
        parent(
          policy: const PrivateMediaPolicy.unsupported(sourceVersion: 77),
          state: PrivateMediaLifecycleState.unsupported,
        ),
        parent(hiddenAt: '2026-07-11T10:02:00.000Z'),
      ];

      for (final currentParent in cases) {
        final repo = FakeMediaAttachmentRepository()..seed([row()]);
        var tokenCalls = 0;
        var fileProbeCalls = 0;
        final result = await BuildReceivedMediaForward(
          loadParentMessage: (_) async => currentParent,
          mediaAttachmentRepository: repo,
          operationTokenFactory: () {
            tokenCalls++;
            return 'must-not-mint';
          },
          validateCanonicalPlaintext:
              ({required attachment, required ownerScopeId}) async {
                fileProbeCalls++;
                return CanonicalGroupMediaPlaintextValidationResult.valid(
                  attachment.localPath!,
                );
              },
        ).build(parent: parent());

        expect(result.draft, isNull);
        expect(tokenCalls, 0);
        expect(fileProbeCalls, 0);
        expect(repo.getAttachmentsForMessageCallCount, 0);
      }
    },
  );

  test('typed PiP input is false for every unresolved or private state', () {
    final messages = <ConversationMessage?>[
      null,
      parent(
        policy: const PrivateMediaPolicy.protected(),
        state: PrivateMediaLifecycleState.available,
      ),
      parent(
        policy: const PrivateMediaPolicy.viewOnce(),
        state: PrivateMediaLifecycleState.consumed,
      ),
      parent(
        policy: const PrivateMediaPolicy.unsupported(sourceVersion: 99),
        state: PrivateMediaLifecycleState.unsupported,
      ),
    ];

    for (final message in messages) {
      final decision = DirectPrivateMediaActionEligibility.evaluate(
        parent: message,
        attachment: row(),
        expectedMessageId: 'message-1',
        expectedAttachmentId: 'attachment-1',
      );
      expect(decision.canEnterPictureInPicture, isFalse);
    }
  });
}
