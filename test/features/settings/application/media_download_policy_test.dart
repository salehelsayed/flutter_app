import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/settings/application/media_download_policy.dart';
import 'package:flutter_app/features/settings/domain/models/media_download_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const allKinds = MediaConversationKind.values;
  const allNetworks = MediaDownloadNetwork.values;
  const allTypes = kMediaDownloadPreferenceTypes;

  MediaOwnerLane ownerFor(MediaConversationKind kind) =>
      kind == MediaConversationKind.oneToOne
          ? MediaOwnerLane.direct
          : MediaOwnerLane.group;

  group('MediaDownloadPolicy', () {
    test(
        'policy decides all lane type and network combinations without '
        'transport side effects', () {
      // Table check: for every lane/type/network cell, disabling exactly that
      // cell denies exactly that automatic download and nothing else.
      // Announcement and discussion are distinct product kinds even though
      // both use the group storage owner.
      for (final flippedKind in allKinds) {
        for (final flippedType in allTypes) {
          for (final flippedNetwork in allNetworks) {
            final prefs = const MediaDownloadPreferences.defaults()
                .copyWithChoice(
              kind: flippedKind,
              mediaType: flippedType,
              network: flippedNetwork,
              enabled: false,
            );
            for (final kind in allKinds) {
              for (final type in allTypes) {
                for (final network in allNetworks) {
                  final expected = !(kind == flippedKind &&
                      type == flippedType &&
                      network == flippedNetwork);
                  expect(
                    MediaDownloadPolicy.shouldAutoDownload(
                      preferences: prefs,
                      conversationKind: kind,
                      storageOwner: ownerFor(kind),
                      mediaType: type,
                      network: network,
                    ),
                    expected,
                    reason: 'disabled $flippedKind/$flippedType/'
                        '$flippedNetwork must deny exactly that cell; '
                        'checked $kind/$type/$network',
                  );
                }
              }
            }
          }
        }
      }

      // Announcement is not the discussion lane: with announcements disabled
      // and discussions enabled the same group-owned attachment splits by
      // product kind.
      final announcementOff = const MediaDownloadPreferences.defaults()
          .copyWithChoice(
        kind: MediaConversationKind.announcement,
        mediaType: 'image',
        network: MediaDownloadNetwork.wifi,
        enabled: false,
      );
      expect(
        MediaDownloadPolicy.shouldAutoDownload(
          preferences: announcementOff,
          conversationKind: MediaConversationKind.announcement,
          storageOwner: MediaOwnerLane.group,
          mediaType: 'image',
          network: MediaDownloadNetwork.wifi,
        ),
        isFalse,
      );
      expect(
        MediaDownloadPolicy.shouldAutoDownload(
          preferences: announcementOff,
          conversationKind: MediaConversationKind.discussion,
          storageOwner: MediaOwnerLane.group,
          mediaType: 'image',
          network: MediaDownloadNetwork.wifi,
        ),
        isTrue,
      );
    });

    test('unresolved storage owner is rejected before any policy decision',
        () {
      for (final userInitiated in const [false, true]) {
        expect(
          () => MediaDownloadPolicy.shouldAutoDownload(
            preferences: const MediaDownloadPreferences.defaults(),
            conversationKind: MediaConversationKind.oneToOne,
            storageOwner: null,
            mediaType: 'image',
            network: MediaDownloadNetwork.wifi,
            userInitiated: userInitiated,
          ),
          throwsA(isA<MediaAttachmentOwnerViolation>()),
          reason: 'unresolved rows must fail closed '
              '(userInitiated=$userInitiated)',
        );
      }
    });

    test('product kind must agree with the storage owner', () {
      // oneToOne media is never group-owned.
      expect(
        () => MediaDownloadPolicy.shouldAutoDownload(
          preferences: const MediaDownloadPreferences.defaults(),
          conversationKind: MediaConversationKind.oneToOne,
          storageOwner: MediaOwnerLane.group,
          mediaType: 'image',
          network: MediaDownloadNetwork.wifi,
        ),
        throwsArgumentError,
      );
      // Discussions and announcements are group-owned, never direct.
      for (final kind in const [
        MediaConversationKind.discussion,
        MediaConversationKind.announcement,
      ]) {
        expect(
          () => MediaDownloadPolicy.shouldAutoDownload(
            preferences: const MediaDownloadPreferences.defaults(),
            conversationKind: kind,
            storageOwner: MediaOwnerLane.direct,
            mediaType: 'image',
            network: MediaDownloadNetwork.wifi,
          ),
          throwsArgumentError,
          reason: '$kind media is stored under the group owner lane',
        );
      }
    });

    test('manual action bypasses only the auto preference', () {
      var everythingOff = const MediaDownloadPreferences.defaults();
      for (final kind in allKinds) {
        for (final type in allTypes) {
          for (final network in allNetworks) {
            everythingOff = everythingOff.copyWithChoice(
              kind: kind,
              mediaType: type,
              network: network,
              enabled: false,
            );
          }
        }
      }
      // Explicit user action downloads even with every auto toggle off.
      for (final kind in allKinds) {
        expect(
          MediaDownloadPolicy.shouldAutoDownload(
            preferences: everythingOff,
            conversationKind: kind,
            storageOwner: ownerFor(kind),
            mediaType: 'video',
            network: MediaDownloadNetwork.cellular,
            userInitiated: true,
          ),
          isTrue,
          reason: 'manual retry in $kind must bypass the auto preference',
        );
      }
      // ...but manual never bypasses protection.
      expect(
        MediaDownloadPolicy.shouldAutoDownload(
          preferences: const MediaDownloadPreferences.defaults(),
          conversationKind: MediaConversationKind.oneToOne,
          storageOwner: MediaOwnerLane.direct,
          mediaType: 'image',
          network: MediaDownloadNetwork.wifi,
          userInitiated: true,
          isProtected: true,
        ),
        isFalse,
      );
      // ...and manual never bypasses the integrity quarantine.
      expect(
        MediaDownloadPolicy.shouldAutoDownload(
          preferences: const MediaDownloadPreferences.defaults(),
          conversationKind: MediaConversationKind.discussion,
          storageOwner: MediaOwnerLane.group,
          mediaType: 'image',
          network: MediaDownloadNetwork.wifi,
          userInitiated: true,
          downloadStatus: kMediaDownloadStatusIntegrityFailed,
        ),
        isFalse,
      );
    });

    test('protected media is never auto-downloaded', () {
      expect(
        MediaDownloadPolicy.shouldAutoDownload(
          preferences: const MediaDownloadPreferences.defaults(),
          conversationKind: MediaConversationKind.oneToOne,
          storageOwner: MediaOwnerLane.direct,
          mediaType: 'image',
          network: MediaDownloadNetwork.wifi,
          isProtected: true,
        ),
        isFalse,
      );
    });

    test('evicted media never auto-downloads but accepts an explicit retry',
        () {
      for (final kind in allKinds) {
        expect(
          MediaDownloadPolicy.shouldAutoDownload(
            preferences: const MediaDownloadPreferences.defaults(),
            conversationKind: kind,
            storageOwner: ownerFor(kind),
            mediaType: 'image',
            network: MediaDownloadNetwork.wifi,
            downloadStatus: kMediaDownloadStatusEvicted,
          ),
          isFalse,
          reason: 'evicted media in $kind must not auto-download even with '
              'every preference enabled',
        );
        expect(
          MediaDownloadPolicy.shouldAutoDownload(
            preferences: const MediaDownloadPreferences.defaults(),
            conversationKind: kind,
            storageOwner: ownerFor(kind),
            mediaType: 'image',
            network: MediaDownloadNetwork.wifi,
            downloadStatus: kMediaDownloadStatusEvicted,
            userInitiated: true,
          ),
          isTrue,
          reason: 'explicit retry of evicted media in $kind is '
              'user-authoritative',
        );
      }
    });

    test('terminal and completed states are not automatic work', () {
      for (final status in const [
        kMediaDownloadStatusDone,
        kMediaDownloadStatusDownloadFailed,
        kMediaDownloadStatusIntegrityFailed,
        kMediaDownloadStatusUploadPending,
        kMediaDownloadStatusUploadFailed,
        kMediaDownloadStatusUploadCancelled,
      ]) {
        expect(
          MediaDownloadPolicy.shouldAutoDownload(
            preferences: const MediaDownloadPreferences.defaults(),
            conversationKind: MediaConversationKind.oneToOne,
            storageOwner: MediaOwnerLane.direct,
            mediaType: 'image',
            network: MediaDownloadNetwork.wifi,
            downloadStatus: status,
          ),
          isFalse,
          reason: '$status must not trigger an automatic transfer',
        );
      }
      // Completed and outgoing states stay out of scope even for the manual
      // received-media retry affordance.
      for (final status in const [
        kMediaDownloadStatusDone,
        kMediaDownloadStatusUploadPending,
        kMediaDownloadStatusUploadFailed,
        kMediaDownloadStatusUploadCancelled,
      ]) {
        expect(
          MediaDownloadPolicy.shouldAutoDownload(
            preferences: const MediaDownloadPreferences.defaults(),
            conversationKind: MediaConversationKind.oneToOne,
            storageOwner: MediaOwnerLane.direct,
            mediaType: 'image',
            network: MediaDownloadNetwork.wifi,
            downloadStatus: status,
            userInitiated: true,
          ),
          isFalse,
          reason: '$status has nothing for a received-media retry to do',
        );
      }
      // Terminal relay unavailability may still be explicitly retried: it
      // settles truthfully (done or terminal again) under the caller's
      // integrity checks.
      expect(
        MediaDownloadPolicy.shouldAutoDownload(
          preferences: const MediaDownloadPreferences.defaults(),
          conversationKind: MediaConversationKind.oneToOne,
          storageOwner: MediaOwnerLane.direct,
          mediaType: 'image',
          network: MediaDownloadNetwork.wifi,
          downloadStatus: kMediaDownloadStatusDownloadFailed,
          userInitiated: true,
        ),
        isTrue,
      );
    });

    test('retryable transient failures follow the auto preference', () {
      final cellularOff = const MediaDownloadPreferences.defaults()
          .copyWithChoice(
        kind: MediaConversationKind.oneToOne,
        mediaType: 'file',
        network: MediaDownloadNetwork.cellular,
        enabled: false,
      );
      expect(
        MediaDownloadPolicy.shouldAutoDownload(
          preferences: cellularOff,
          conversationKind: MediaConversationKind.oneToOne,
          storageOwner: MediaOwnerLane.direct,
          mediaType: 'file',
          network: MediaDownloadNetwork.cellular,
          downloadStatus: kMediaDownloadStatusFailed,
        ),
        isFalse,
      );
      expect(
        MediaDownloadPolicy.shouldAutoDownload(
          preferences: cellularOff,
          conversationKind: MediaConversationKind.oneToOne,
          storageOwner: MediaOwnerLane.direct,
          mediaType: 'file',
          network: MediaDownloadNetwork.wifi,
          downloadStatus: kMediaDownloadStatusFailed,
        ),
        isTrue,
      );
    });
  });
}
