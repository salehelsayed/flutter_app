import 'dart:io';

import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PrivateMediaPolicy', () {
    test('missing policy preserves ordinary legacy media behavior', () {
      final policy = PrivateMediaPolicy.fromJson(null);

      expect(policy.version, 0);
      expect(policy.mode, PrivateMediaMode.ordinary);
      expect(policy.durationSeconds, isNull);
      expect(policy.isPrivate, isFalse);
      expect(policy.isUnsupported, isFalse);
      expect(policy.initialState, PrivateMediaLifecycleState.none);
      expect(policy.toJson(), isNull);
    });

    test('all four v1 modes and approved disappearing durations validate', () {
      for (final mode in const ['ordinary', 'protected', 'view_once']) {
        final policy = PrivateMediaPolicy.fromJson({
          'version': 1,
          'mode': mode,
        });
        expect(policy.version, 1);
        expect(policy.mode.wireValue, mode);
        expect(policy.durationSeconds, isNull);
        expect(policy.isUnsupported, isFalse);
      }

      for (final duration in PrivateMediaPolicy.allowedDurationsSeconds) {
        final policy = PrivateMediaPolicy.fromJson({
          'version': 1,
          'mode': 'disappearing',
          'durationSeconds': duration,
        });
        expect(policy.mode, PrivateMediaMode.disappearing);
        expect(policy.durationSeconds, duration);
        expect(policy.initialState, PrivateMediaLifecycleState.available);
        expect(policy.toJson(), {
          'version': 1,
          'mode': 'disappearing',
          'durationSeconds': duration,
        });
      }
    });

    test(
      'private eligibility is typed and independent of presentation code',
      () {
        const eligibleImage = PrivateMediaEligibility(
          attachmentCount: 1,
          attachmentKind: PrivateMediaAttachmentKind.image,
        );
        const eligibleGif = PrivateMediaEligibility(
          attachmentCount: 1,
          attachmentKind: PrivateMediaAttachmentKind.gif,
        );
        const eligibleVideo = PrivateMediaEligibility(
          attachmentCount: 1,
          attachmentKind: PrivateMediaAttachmentKind.video,
        );
        const ineligible = <PrivateMediaEligibility>[
          PrivateMediaEligibility(
            attachmentCount: 0,
            attachmentKind: PrivateMediaAttachmentKind.image,
          ),
          PrivateMediaEligibility(
            attachmentCount: 2,
            attachmentKind: PrivateMediaAttachmentKind.image,
          ),
          PrivateMediaEligibility(
            attachmentCount: 1,
            attachmentKind: PrivateMediaAttachmentKind.audio,
          ),
          PrivateMediaEligibility(
            attachmentCount: 1,
            attachmentKind: PrivateMediaAttachmentKind.file,
          ),
          PrivateMediaEligibility(
            attachmentCount: 1,
            attachmentKind: PrivateMediaAttachmentKind.image,
            hasTextOrCaption: true,
          ),
          PrivateMediaEligibility(
            attachmentCount: 1,
            attachmentKind: PrivateMediaAttachmentKind.video,
            isEdit: true,
          ),
          PrivateMediaEligibility(
            attachmentCount: 1,
            attachmentKind: PrivateMediaAttachmentKind.video,
            isForward: true,
          ),
        ];

        final protected = PrivateMediaPolicy.fromJson({
          'version': 1,
          'mode': 'protected',
        });
        for (final eligibility in [eligibleImage, eligibleGif, eligibleVideo]) {
          expect(protected.validatedFor(eligibility).isUnsupported, isFalse);
        }
        for (final eligibility in ineligible) {
          expect(protected.validatedFor(eligibility).isUnsupported, isTrue);
        }

        final source = File(
          'lib/core/media/private_media_policy.dart',
        ).readAsStringSync();
        expect(source, isNot(contains('/presentation/')));
        expect(source, isNot(contains('package:flutter/')));
      },
    );

    test(
      'new private selection permits image and video while compatibility validation preserves GIF',
      () {
        const attachmentCounts = <int>[0, 1, 2];
        const flags = <bool>[false, true];
        const protected = PrivateMediaPolicy.protected();

        for (final attachmentCount in attachmentCounts) {
          for (final attachmentKind in PrivateMediaAttachmentKind.values) {
            for (final hasTextOrCaption in flags) {
              for (final isEdit in flags) {
                for (final isForward in flags) {
                  final eligibility = PrivateMediaEligibility(
                    attachmentCount: attachmentCount,
                    attachmentKind: attachmentKind,
                    hasTextOrCaption: hasTextOrCaption,
                    isEdit: isEdit,
                    isForward: isForward,
                  );
                  final hasEligibleShape =
                      attachmentCount == 1 &&
                      !hasTextOrCaption &&
                      !isEdit &&
                      !isForward;
                  final expectedNewSelection =
                      hasEligibleShape &&
                      (attachmentKind == PrivateMediaAttachmentKind.image ||
                          attachmentKind == PrivateMediaAttachmentKind.video);
                  final expectedCompatibility =
                      hasEligibleShape &&
                      (attachmentKind == PrivateMediaAttachmentKind.image ||
                          attachmentKind == PrivateMediaAttachmentKind.gif ||
                          attachmentKind == PrivateMediaAttachmentKind.video);
                  final reason =
                      'count=$attachmentCount kind=${attachmentKind.name} '
                      'caption=$hasTextOrCaption edit=$isEdit '
                      'forward=$isForward';

                  expect(
                    eligibility.allowsNewPrivateMedia,
                    expectedNewSelection,
                    reason: reason,
                  );
                  expect(
                    eligibility.allowsPrivateMedia,
                    expectedCompatibility,
                    reason: 'compatibility: $reason',
                  );
                  expect(
                    protected.validatedFor(eligibility).isUnsupported,
                    !expectedCompatibility,
                    reason: 'legacy validation: $reason',
                  );
                }
              }
            }
          }
        }
      },
    );

    test('unknown and malformed policy fails closed as typed unsupported', () {
      final invalid = <Object?>[
        'protected',
        <String, Object?>{},
        {'version': 2, 'mode': 'protected'},
        {'version': -1, 'mode': 'protected'},
        {'version': 1, 'mode': 'future_mode'},
        {'version': 1, 'mode': 'protected', 'durationSeconds': 3600},
        {'version': 1, 'mode': 'view_once', 'durationSeconds': 3600},
        {'version': 1, 'mode': 'disappearing'},
        {'version': 1, 'mode': 'disappearing', 'durationSeconds': 60},
        {'version': 1, 'mode': 'disappearing', 'durationSeconds': '3600'},
      ];

      for (final raw in invalid) {
        final policy = PrivateMediaPolicy.fromJson(raw);
        expect(policy.mode, PrivateMediaMode.unsupported, reason: '$raw');
        expect(policy.isUnsupported, isTrue, reason: '$raw');
        expect(
          policy.initialState,
          PrivateMediaLifecycleState.unsupported,
          reason: '$raw',
        );
        expect(policy.toJson(), isNull, reason: '$raw');
      }
    });

    test('unknown additive v1 fields are ignored', () {
      final policy = PrivateMediaPolicy.fromJson({
        'version': 1,
        'mode': 'disappearing',
        'durationSeconds': 86400,
        'futureHint': 'ignored',
        'nested': {'also': 'ignored'},
      });

      expect(policy.isUnsupported, isFalse);
      expect(policy.toJson(), {
        'version': 1,
        'mode': 'disappearing',
        'durationSeconds': 86400,
      });
    });

    test('lifecycle vocabulary is exact and unknown values fail closed', () {
      expect(
        PrivateMediaLifecycleState.values.map((state) => state.wireValue),
        const [
          'none',
          'available',
          'opening',
          'viewing',
          'consumed',
          'expired',
          'unsupported',
        ],
      );
      expect(
        PrivateMediaLifecycleState.fromWireValue('viewing'),
        PrivateMediaLifecycleState.viewing,
      );
      expect(
        PrivateMediaLifecycleState.fromWireValue('future_state'),
        PrivateMediaLifecycleState.unsupported,
      );
    });

    test(
      'TC-355-04f private media identity requires coherent MIME and mediaType',
      () {
        // Coherent producer identities keep their exact kind.
        expect(
          privateMediaAttachmentKindForMediaIdentity(
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
          PrivateMediaAttachmentKind.image,
        );
        expect(
          privateMediaAttachmentKindForMediaIdentity(
            mime: 'video/mp4',
            mediaType: 'video',
          ),
          PrivateMediaAttachmentKind.video,
        );
        expect(
          privateMediaAttachmentKindForMediaIdentity(
            mime: 'audio/aac',
            mediaType: 'audio',
          ),
          PrivateMediaAttachmentKind.audio,
        );
        expect(
          privateMediaAttachmentKindForMediaIdentity(
            mime: 'application/pdf',
            mediaType: 'file',
          ),
          PrivateMediaAttachmentKind.file,
        );

        // The one intentional divergence: the app's own convention persists
        // media_type 'image' for an animated GIF, and GIF must stay separable
        // so the producer matrix keeps refusing it.
        expect(
          privateMediaAttachmentKindForMediaIdentity(
            mime: 'image/gif',
            mediaType: 'image',
          ),
          PrivateMediaAttachmentKind.gif,
        );
        expect(
          privateMediaAttachmentKindForMediaIdentity(
            mime: 'image/gif',
            mediaType: 'gif',
          ),
          PrivateMediaAttachmentKind.gif,
        );

        // Crossed identities must fail closed instead of being admitted by
        // whichever side the OR happened to read first.
        for (final crossed in const <(String, String)>[
          ('video/mp4', 'image'),
          ('image/png', 'video'),
          ('image/png', 'gif'),
          ('image/gif', 'video'),
          ('audio/aac', 'image'),
          ('application/pdf', 'image'),
          ('image/jpeg', 'file'),
          ('video/quicktime', 'audio'),
          ('', 'image'),
          ('image/png', ''),
          ('image/png', 'document'),
        ]) {
          expect(
            privateMediaAttachmentKindForMediaIdentity(
              mime: crossed.$1,
              mediaType: crossed.$2,
            ),
            PrivateMediaAttachmentKind.unknown,
            reason: 'crossed identity ${crossed.$1} + ${crossed.$2}',
          );
        }

        // Case normalization stays intact.
        expect(
          privateMediaAttachmentKindForMediaIdentity(
            mime: 'IMAGE/PNG',
            mediaType: 'Image',
          ),
          PrivateMediaAttachmentKind.image,
        );

        // The producer matrix inherits the tightened identity: a crossed pair
        // can no longer be admitted as a valid Protected or View-Once initial.
        expect(
          privateMediaInitialProducerMatrixAllows(
            policyVersion: 1,
            mode: PrivateMediaMode.protected,
            mime: 'video/mp4',
            mediaType: 'image',
          ),
          isFalse,
        );
        expect(
          privateMediaInitialProducerMatrixAllows(
            policyVersion: 1,
            mode: PrivateMediaMode.viewOnce,
            mime: 'video/mp4',
            mediaType: 'image',
          ),
          isFalse,
        );
        // Valid producer shapes remain admitted.
        expect(
          privateMediaInitialProducerMatrixAllows(
            policyVersion: 1,
            mode: PrivateMediaMode.protected,
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
          isTrue,
        );
        expect(
          privateMediaInitialProducerMatrixAllows(
            policyVersion: 1,
            mode: PrivateMediaMode.protected,
            mime: 'video/mp4',
            mediaType: 'video',
          ),
          isTrue,
        );
        expect(
          privateMediaInitialProducerMatrixAllows(
            policyVersion: 1,
            mode: PrivateMediaMode.viewOnce,
            mime: 'image/png',
            mediaType: 'image',
          ),
          isTrue,
        );
        // GIF stays refused through the preserved exception.
        expect(
          privateMediaInitialProducerMatrixAllows(
            policyVersion: 1,
            mode: PrivateMediaMode.protected,
            mime: 'image/gif',
            mediaType: 'image',
          ),
          isFalse,
        );
        // The database-identity form refuses the same crossed pair.
        expect(
          privateMediaInitialProducerMatrixAllowsDatabaseIdentity(
            policyVersion: 1,
            mode: 'protected',
            durationSeconds: null,
            mime: 'video/mp4',
            mediaType: 'image',
          ),
          isFalse,
        );
        expect(
          privateMediaInitialProducerMatrixAllowsDatabaseIdentity(
            policyVersion: 1,
            mode: 'protected',
            durationSeconds: null,
            mime: 'video/mp4',
            mediaType: 'video',
          ),
          isTrue,
        );
      },
    );
  });
}
