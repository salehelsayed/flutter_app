import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GroupPrivateMediaPolicy', () {
    test(
      'GPL-02 legacy absence is ordinary and explicit invalid policy is durable unsupported',
      () {
        expect(
          GroupPrivateMediaPolicy.fromWireExtras(const {}),
          const GroupPrivateMediaPolicy.ordinary(),
        );
        expect(
          GroupPrivateMediaPolicy.fromWireExtras(const {'mediaId': 'legacy'}),
          const GroupPrivateMediaPolicy.ordinary(),
        );

        final valid = <Map<String, Object?>>[
          const {
            'mediaPolicyVersion': 1,
            'mediaLifecycle': 'standard',
            'mediaDurationSeconds': null,
            'mediaProtected': true,
          },
          const {
            'mediaPolicyVersion': 1,
            'mediaLifecycle': 'viewOnce',
            'mediaDurationSeconds': null,
            'mediaProtected': true,
          },
          const {
            'mediaPolicyVersion': 1,
            'mediaLifecycle': 'disappearing',
            'mediaDurationSeconds': 3600,
            'mediaProtected': true,
          },
        ];
        expect(
          GroupPrivateMediaPolicy.fromWireExtras(valid[0]),
          const GroupPrivateMediaPolicy.protected(),
        );
        expect(
          GroupPrivateMediaPolicy.fromWireExtras(valid[1]),
          const GroupPrivateMediaPolicy.viewOnce(),
        );
        expect(
          GroupPrivateMediaPolicy.fromWireExtras(valid[2]),
          GroupPrivateMediaPolicy.disappearing(3600),
        );
        for (final raw in valid) {
          final policy = GroupPrivateMediaPolicy.fromWireExtras(raw);
          final emitted = policy.toWireExtras()!;
          expect(emitted.keys, {
            'mediaPolicyVersion',
            'mediaLifecycle',
            'mediaDurationSeconds',
            'mediaProtected',
          });
          expect(emitted.containsKey('mediaDurationSeconds'), isTrue);
        }

        const eligible = GroupPrivateMediaEligibility(
          attachmentCount: 1,
          attachmentKind: GroupPrivateMediaAttachmentKind.image,
        );
        const ineligible = GroupPrivateMediaEligibility(
          attachmentCount: 1,
          attachmentKind: GroupPrivateMediaAttachmentKind.image,
          hasTextOrCaption: true,
        );
        expect(
          GroupPrivateMediaPolicy.fromWireExtras(
            valid[1],
            eligibility: eligible,
          ),
          const GroupPrivateMediaPolicy.viewOnce(),
        );
        expect(
          GroupPrivateMediaPolicy.fromWireExtras(
            valid[1],
            eligibility: ineligible,
          ).isUnsupported,
          isTrue,
        );
        expect(
          const GroupPrivateMediaPolicy.protected()
              .validatedFor(
                const GroupPrivateMediaEligibility(
                  attachmentCount: 1,
                  attachmentKind: GroupPrivateMediaAttachmentKind.video,
                ),
              )
              .isPrivate,
          isTrue,
        );
        expect(
          const GroupPrivateMediaPolicy.protected()
              .validatedFor(
                const GroupPrivateMediaEligibility(
                  attachmentCount: 1,
                  attachmentKind: GroupPrivateMediaAttachmentKind.gif,
                ),
              )
              .isUnsupported,
          isTrue,
        );

        final invalid = <Map<String, Object?>>[
          const {'mediaPolicyVersion': 1},
          const {
            'mediaPolicyVersion': 1,
            'mediaLifecycle': 'standard',
            'mediaProtected': true,
          },
          const {
            'mediaPolicyVersion': null,
            'mediaLifecycle': 'standard',
            'mediaDurationSeconds': null,
            'mediaProtected': true,
          },
          const {
            'mediaPolicyVersion': 1.0,
            'mediaLifecycle': 'standard',
            'mediaDurationSeconds': null,
            'mediaProtected': true,
          },
          const {
            'mediaPolicyVersion': '1',
            'mediaLifecycle': 'standard',
            'mediaDurationSeconds': null,
            'mediaProtected': true,
          },
          const {
            'mediaPolicyVersion': 1,
            'mediaLifecycle': null,
            'mediaDurationSeconds': null,
            'mediaProtected': true,
          },
          const {
            'mediaPolicyVersion': 1,
            'mediaLifecycle': 'future',
            'mediaDurationSeconds': null,
            'mediaProtected': true,
          },
          const {
            'mediaPolicyVersion': 1,
            'mediaLifecycle': 'standard',
            'mediaDurationSeconds': 3600,
            'mediaProtected': true,
          },
          const {
            'mediaPolicyVersion': 1,
            'mediaLifecycle': 'viewOnce',
            'mediaDurationSeconds': null,
            'mediaProtected': false,
          },
          const {
            'mediaPolicyVersion': 1,
            'mediaLifecycle': 'disappearing',
            'mediaDurationSeconds': null,
            'mediaProtected': true,
          },
          const {
            'mediaPolicyVersion': 1,
            'mediaLifecycle': 'disappearing',
            'mediaDurationSeconds': 60,
            'mediaProtected': true,
          },
          const {
            'mediaPolicyVersion': 1,
            'mediaLifecycle': 'disappearing',
            'mediaDurationSeconds': 3600.0,
            'mediaProtected': true,
          },
          const {
            'mediaPolicyVersion': 1,
            'mediaLifecycle': 'disappearing',
            'mediaDurationSeconds': 3600,
            'mediaProtected': 1,
          },
        ];
        for (final raw in invalid) {
          final policy = GroupPrivateMediaPolicy.fromWireExtras(raw);
          expect(policy.isUnsupported, isTrue, reason: '$raw');
          expect(policy.toDatabaseMap(), {
            'media_policy_version': policy.version,
            'media_lifecycle': 'unsupported',
            'media_duration_seconds': null,
            'media_protected': 1,
          });
          expect(policy.toWireExtras(), isNull);
        }

        final future = GroupPrivateMediaPolicy.fromWireExtras(const {
          'mediaPolicyVersion': 7,
          'mediaLifecycle': 'future',
          'mediaDurationSeconds': null,
          'mediaProtected': true,
        });
        expect(
          future,
          const GroupPrivateMediaPolicy.unsupported(sourceVersion: 7),
        );
        expect(
          const GroupPrivateMediaPolicy.unsupported(
            sourceVersion: -1,
          ).toDatabaseMap(),
          const {
            'media_policy_version': 0,
            'media_lifecycle': 'unsupported',
            'media_duration_seconds': null,
            'media_protected': 1,
          },
        );
        final partialFuture = GroupPrivateMediaPolicy.fromWireExtras(const {
          'mediaPolicyVersion': 7,
        });
        expect(
          partialFuture,
          const GroupPrivateMediaPolicy.unsupported(sourceVersion: 7),
        );
        final invalidVersion = GroupPrivateMediaPolicy.fromWireExtras(const {
          'mediaPolicyVersion': -1,
          'mediaLifecycle': 'standard',
          'mediaDurationSeconds': null,
          'mediaProtected': true,
        });
        expect(
          invalidVersion,
          const GroupPrivateMediaPolicy.unsupported(sourceVersion: 0),
        );
        expect(
          GroupPrivateMediaPolicy.fromDatabase(
            version: null,
            lifecycle: null,
            durationSeconds: null,
            protected: null,
          ),
          const GroupPrivateMediaPolicy.ordinary(),
        );
        expect(
          GroupPrivateMediaPolicy.fromDatabase(
            version: 0,
            lifecycle: 'standard',
            durationSeconds: null,
            protected: 0,
          ),
          const GroupPrivateMediaPolicy.ordinary(),
        );
        expect(
          GroupPrivateMediaPolicy.fromDatabase(
            version: 1,
            lifecycle: 'view_once',
            durationSeconds: null,
            protected: 1,
          ),
          const GroupPrivateMediaPolicy.viewOnce(),
        );
        for (final malformed in const [
          (0, 'standard', null, 1),
          (1.0, 'standard', null, 1),
          (1, 'standard', null, true),
          (1, 'view_once', 3600, 1),
          (1, 'disappearing', 60, 1),
          (2, 'standard', null, 1),
        ]) {
          expect(
            GroupPrivateMediaPolicy.fromDatabase(
              version: malformed.$1,
              lifecycle: malformed.$2,
              durationSeconds: malformed.$3,
              protected: malformed.$4,
            ).isUnsupported,
            isTrue,
            reason: '$malformed',
          );
        }
      },
    );

    test('constructors enforce the supported duration set', () {
      for (final duration in GroupPrivateMediaPolicy.allowedDurationsSeconds) {
        expect(
          GroupPrivateMediaPolicy.disappearing(duration).isPrivate,
          isTrue,
        );
      }
      expect(GroupPrivateMediaPolicy.disappearing(60).isUnsupported, isTrue);
    });
  });
}
