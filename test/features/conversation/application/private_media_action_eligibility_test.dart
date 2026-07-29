import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/application/private_media_action_eligibility.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const irreversible = <DirectPrivateMediaAction>{
    DirectPrivateMediaAction.saveToPhotos,
    DirectPrivateMediaAction.saveToFiles,
    DirectPrivateMediaAction.externalShare,
    DirectPrivateMediaAction.internalForward,
    DirectPrivateMediaAction.bookmark,
    DirectPrivateMediaAction.sharedMedia,
    DirectPrivateMediaAction.pictureInPicture,
  };

  ConversationMessage parent({
    PrivateMediaPolicy policy = const PrivateMediaPolicy.ordinary(),
    PrivateMediaLifecycleState state = PrivateMediaLifecycleState.none,
    String? hiddenAt,
    String? deletedAt,
    String text = 'SECRET caption.jpg',
  }) {
    return ConversationMessage(
      id: 'message-1',
      contactPeerId: 'peer-contact',
      senderPeerId: 'peer-contact',
      text: text,
      timestamp: '2026-07-11T10:00:00.000Z',
      status: 'delivered',
      isIncoming: true,
      createdAt: '2026-07-11T10:00:00.000Z',
      hiddenAt: hiddenAt,
      deletedAt: deletedAt,
      privateMediaPolicy: policy,
      privateMediaState: state,
      privateMediaExpiresAtMs: policy.isPrivate ? 1_800_000_000_000 : null,
      privateMediaTerminalAtMs: state.isTerminal ? 1_800_000_000_100 : null,
    );
  }

  MediaAttachment attachment({
    String id = 'attachment-1',
    String messageId = 'message-1',
    MediaOwnerLane? owner = MediaOwnerLane.direct,
    String status = 'done',
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: 'video/SECRET-mime',
      size: 99,
      mediaType: 'video',
      localPath: '/tmp/SECRET-private-path.mp4',
      downloadStatus: status,
      createdAt: '2026-07-11T10:00:00.000Z',
      encryptionKeyBase64: 'SECRET-key',
      encryptionNonce: 'SECRET-nonce',
      ownerLane: owner,
    );
  }

  DirectPrivateMediaActionDecision decide(
    ConversationMessage? message, {
    MediaAttachment? current,
  }) {
    return DirectPrivateMediaActionEligibility.evaluate(
      parent: message,
      attachment: current ?? attachment(),
      expectedMessageId: 'message-1',
      expectedAttachmentId: 'attachment-1',
    );
  }

  test('ordinary current direct media preserves every existing capability', () {
    final decision = decide(parent());

    expect(decision.reason, DirectPrivateMediaEligibilityReason.ordinary);
    for (final action in DirectPrivateMediaAction.values) {
      expect(decision.allows(action), isTrue, reason: action.name);
    }
    expect(decision.requiresPrivacyMinimizedPresentation, isFalse);
    expect(decision.safeReplyText, 'SECRET caption.jpg');
    expect(decision.safeInfo, isNull);
  });

  test('versioned ordinary policy is corrupt and fails every capability', () {
    final versionedOrdinary = PrivateMediaPolicy.fromJson(const {
      'version': 1,
      'mode': 'ordinary',
    });
    expect(versionedOrdinary.mode, PrivateMediaMode.ordinary);
    expect(versionedOrdinary.version, 1);

    final decision = decide(parent(policy: versionedOrdinary));

    expect(
      decision.reason,
      DirectPrivateMediaEligibilityReason.corruptPolicyState,
    );
    for (final action in DirectPrivateMediaAction.values) {
      expect(decision.allows(action), isFalse, reason: action.name);
    }
    expect(decision.canEnterPictureInPicture, isFalse);
  });

  test('every private mode and live lifecycle denies all egress surfaces', () {
    final privatePolicies = <PrivateMediaPolicy>[
      const PrivateMediaPolicy.protected(),
      const PrivateMediaPolicy.viewOnce(),
      PrivateMediaPolicy.disappearing(3600),
    ];
    const liveStates = <PrivateMediaLifecycleState>[
      PrivateMediaLifecycleState.available,
      PrivateMediaLifecycleState.opening,
      PrivateMediaLifecycleState.viewing,
    ];

    for (final policy in privatePolicies) {
      for (final state in liveStates) {
        final decision = decide(parent(policy: policy, state: state));
        expect(
          decision.reason,
          DirectPrivateMediaEligibilityReason.privateAvailable,
          reason: '${policy.mode.name}/${state.name}',
        );
        for (final action in irreversible) {
          expect(
            decision.allows(action),
            isFalse,
            reason: '${policy.mode.name}/${state.name}/${action.name}',
          );
        }
        expect(decision.allows(DirectPrivateMediaAction.openInApp), isTrue);
        expect(
          decision.allows(DirectPrivateMediaAction.explicitDownload),
          state == PrivateMediaLifecycleState.available,
        );
        expect(decision.allows(DirectPrivateMediaAction.reply), isTrue);
        expect(decision.allows(DirectPrivateMediaAction.info), isTrue);
        expect(decision.allows(DirectPrivateMediaAction.deleteForMe), isTrue);
        expect(decision.safeReplyText, 'Private media');
      }
    }
  });

  test('terminal and unsupported policy never exposes bytes or redownload', () {
    final cases = <ConversationMessage>[
      for (final policy in <PrivateMediaPolicy>[
        const PrivateMediaPolicy.protected(),
        const PrivateMediaPolicy.viewOnce(),
        PrivateMediaPolicy.disappearing(3600),
      ])
        for (final state in const <PrivateMediaLifecycleState>[
          PrivateMediaLifecycleState.consumed,
          PrivateMediaLifecycleState.expired,
        ])
          parent(policy: policy, state: state),
      parent(
        policy: const PrivateMediaPolicy.unsupported(sourceVersion: 77),
        state: PrivateMediaLifecycleState.unsupported,
      ),
    ];

    for (final message in cases) {
      final decision = decide(message);
      expect(
        decision.reason,
        message.privateMediaPolicy.isUnsupported
            ? DirectPrivateMediaEligibilityReason.unsupported
            : DirectPrivateMediaEligibilityReason.privateTerminal,
      );
      expect(decision.allows(DirectPrivateMediaAction.openInApp), isFalse);
      expect(
        decision.allows(DirectPrivateMediaAction.explicitDownload),
        isFalse,
      );
      for (final action in irreversible) {
        expect(decision.allows(action), isFalse, reason: action.name);
      }
      expect(decision.allows(DirectPrivateMediaAction.reply), isTrue);
      expect(decision.allows(DirectPrivateMediaAction.info), isTrue);
      expect(decision.allows(DirectPrivateMediaAction.deleteForMe), isTrue);
    }
  });

  test(
    'missing attachment outgoing parent and mismatched parent fail closed',
    () {
      final missingAttachment = DirectPrivateMediaActionEligibility.evaluate(
        parent: parent(),
        attachment: null,
        expectedMessageId: 'message-1',
        expectedAttachmentId: 'attachment-1',
      );
      final outgoing = DirectPrivateMediaActionEligibility.evaluate(
        parent: parent().copyWith(isIncoming: false),
        attachment: attachment(),
        expectedMessageId: 'message-1',
        expectedAttachmentId: 'attachment-1',
      );
      final mismatchedParent = DirectPrivateMediaActionEligibility.evaluate(
        parent: parent(),
        attachment: attachment(),
        expectedMessageId: 'different-message',
        expectedAttachmentId: 'attachment-1',
      );

      expect(
        missingAttachment.reason,
        DirectPrivateMediaEligibilityReason.attachmentMissing,
      );
      expect(
        outgoing.reason,
        DirectPrivateMediaEligibilityReason.parentNotIncoming,
      );
      expect(
        mismatchedParent.reason,
        DirectPrivateMediaEligibilityReason.staleIdentity,
      );
      for (final decision in [missingAttachment, outgoing, mismatchedParent]) {
        for (final action in DirectPrivateMediaAction.values) {
          expect(decision.allows(action), isFalse, reason: action.name);
        }
      }
    },
  );

  test('every invalid private policy and lifecycle pairing fails closed', () {
    final policies = <PrivateMediaPolicy>[
      const PrivateMediaPolicy.protected(),
      const PrivateMediaPolicy.viewOnce(),
      PrivateMediaPolicy.disappearing(3600),
    ];
    for (final policy in policies) {
      for (final invalidState in const [
        PrivateMediaLifecycleState.none,
        PrivateMediaLifecycleState.unsupported,
      ]) {
        final decision = decide(parent(policy: policy, state: invalidState));
        expect(
          decision.reason,
          DirectPrivateMediaEligibilityReason.corruptPolicyState,
          reason: '${policy.mode.name}/${invalidState.name}',
        );
        for (final action in DirectPrivateMediaAction.values) {
          expect(decision.allows(action), isFalse, reason: action.name);
        }
      }
    }
  });

  test(
    'generic reply, typed info, and diagnostics cannot carry private data',
    () {
      final decision = decide(
        parent(
          policy: PrivateMediaPolicy.disappearing(3600),
          state: PrivateMediaLifecycleState.available,
        ),
      );

      expect(decision.requiresPrivacyMinimizedPresentation, isTrue);
      expect(decision.safeReplyText, 'Private media');
      expect(decision.safeInfo, isNotNull);
      expect(decision.safeInfo!.mode, PrivateMediaMode.disappearing);
      expect(decision.safeInfo!.state, PrivateMediaLifecycleState.available);
      expect(decision.safeInfo!.expiresAtMs, 1_800_000_000_000);

      final rendered = <String>[
        decision.safeReplyText,
        decision.diagnosticCode,
        decision.safeInfo.toString(),
      ].join('|');
      for (final secret in <String>[
        'SECRET caption.jpg',
        'SECRET-private-path',
        'SECRET-mime',
        'SECRET-key',
        'SECRET-nonce',
        '3600',
      ]) {
        expect(rendered, isNot(contains(secret)), reason: secret);
      }
    },
  );

  test('hidden, deleted, corrupt, and integrity-failed rows fail closed', () {
    final cases = <DirectPrivateMediaActionDecision>[
      decide(parent(hiddenAt: '2026-07-11T10:01:00.000Z')),
      decide(parent(deletedAt: '2026-07-11T10:01:00.000Z')),
      decide(
        parent(
          policy: const PrivateMediaPolicy.protected(),
          state: PrivateMediaLifecycleState.none,
        ),
      ),
      decide(parent().copyWith(privateMediaExpiresAtMs: 1_800_000_000_000)),
      decide(parent(), current: attachment(status: 'integrity_failed')),
    ];

    expect(
      cases.map((decision) => decision.reason),
      <DirectPrivateMediaEligibilityReason>[
        DirectPrivateMediaEligibilityReason.parentHidden,
        DirectPrivateMediaEligibilityReason.parentDeleted,
        DirectPrivateMediaEligibilityReason.corruptPolicyState,
        DirectPrivateMediaEligibilityReason.corruptPolicyState,
        DirectPrivateMediaEligibilityReason.integrityFailed,
      ],
    );
    for (final decision in cases) {
      expect(decision.allows(DirectPrivateMediaAction.openInApp), isFalse);
      expect(
        decision.allows(DirectPrivateMediaAction.explicitDownload),
        isFalse,
      );
      for (final action in irreversible) {
        expect(decision.allows(action), isFalse, reason: action.name);
      }
    }
  });

  test('protected rows with local bytes still deny every egress surface', () {
    // Plan 301 renders protected photo pixels in the bubble; the matrix keys
    // on mode/state — never on byte presence — so a downloaded thumbnail or
    // full local file must change NOTHING about egress.
    final withBytes = attachment(status: 'done');
    expect(withBytes.localPath, isNotNull);

    for (final direction in const [true, false]) {
      final message = ConversationMessage(
        id: 'message-1',
        contactPeerId: 'peer-contact',
        senderPeerId: direction ? 'peer-contact' : 'peer-own',
        text: '',
        timestamp: '2026-07-11T10:00:00.000Z',
        status: 'delivered',
        isIncoming: direction,
        createdAt: '2026-07-11T10:00:00.000Z',
        privateMediaPolicy: const PrivateMediaPolicy.protected(),
        privateMediaState: PrivateMediaLifecycleState.available,
      );
      final decision = DirectPrivateMediaActionEligibility.evaluate(
        parent: message,
        attachment: withBytes,
        expectedMessageId: 'message-1',
        expectedAttachmentId: 'attachment-1',
        requiredDirection: null,
      );
      expect(
        decision.reason,
        DirectPrivateMediaEligibilityReason.privateAvailable,
        reason: 'incoming=$direction',
      );
      for (final action in irreversible) {
        expect(
          decision.allows(action),
          isFalse,
          reason: 'incoming=$direction/${action.name} must stay denied with '
              'local bytes present',
        );
      }
      expect(decision.allows(DirectPrivateMediaAction.openInApp), isTrue);
    }
  });
}
