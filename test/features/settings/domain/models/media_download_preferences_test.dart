import 'package:flutter_app/features/settings/domain/models/media_download_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const allKinds = MediaConversationKind.values;
  const allNetworks = MediaDownloadNetwork.values;
  const allTypes = kMediaDownloadPreferenceTypes;

  void expectAllEnabled(MediaDownloadPreferences prefs, {String? reason}) {
    for (final kind in allKinds) {
      for (final type in allTypes) {
        for (final network in allNetworks) {
          expect(
            prefs.isAutoDownloadEnabled(
              kind: kind,
              mediaType: type,
              network: network,
            ),
            isTrue,
            reason: reason ?? 'default must keep $kind/$type/$network enabled',
          );
        }
      }
    }
  }

  group('MediaDownloadPreferences', () {
    test('codec preserves compatible defaults and every lane matrix value',
        () {
      // HEAD-compatible defaults: a missing stored value decodes to a matrix
      // where every lane/type/network stays enabled.
      expectAllEnabled(MediaDownloadPreferences.fromStorageString(null));

      // Defaults constructor agrees with the decoded default.
      expectAllEnabled(const MediaDownloadPreferences.defaults());

      // Every single lane/type/network choice round-trips through the codec
      // independently: flip exactly one entry off, encode, decode, and the
      // decoded matrix must match entry-for-entry.
      for (final flippedKind in allKinds) {
        for (final flippedType in allTypes) {
          for (final flippedNetwork in allNetworks) {
            final customized = const MediaDownloadPreferences.defaults()
                .copyWithChoice(
              kind: flippedKind,
              mediaType: flippedType,
              network: flippedNetwork,
              enabled: false,
            );
            final decoded = MediaDownloadPreferences.fromStorageString(
              customized.toStorageString(),
            );
            for (final kind in allKinds) {
              for (final type in allTypes) {
                for (final network in allNetworks) {
                  final expected = !(kind == flippedKind &&
                      type == flippedType &&
                      network == flippedNetwork);
                  expect(
                    decoded.isAutoDownloadEnabled(
                      kind: kind,
                      mediaType: type,
                      network: network,
                    ),
                    expected,
                    reason:
                        'flipping $flippedKind/$flippedType/$flippedNetwork '
                        'must round-trip $kind/$type/$network as $expected',
                  );
                }
              }
            }
          }
        }
      }

      // A fully-disabled matrix round-trips too (no entry is silently
      // re-enabled or dropped by the codec — including the announcement lane).
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
      final decodedOff = MediaDownloadPreferences.fromStorageString(
        everythingOff.toStorageString(),
      );
      for (final kind in allKinds) {
        for (final type in allTypes) {
          for (final network in allNetworks) {
            expect(
              decodedOff.isAutoDownloadEnabled(
                kind: kind,
                mediaType: type,
                network: network,
              ),
              isFalse,
              reason: 'fully-disabled matrix must survive the round-trip for '
                  '$kind/$type/$network',
            );
          }
        }
      }

      // An unknown codec version fails safely to the enabled defaults instead
      // of trusting entries it cannot interpret.
      final unknownVersion = MediaDownloadPreferences.fromStorageString(
        '{"version":99,"lanes":{"oneToOne":{"image":{"wifi":false}}}}',
      );
      expectAllEnabled(
        unknownVersion,
        reason: 'unknown version must fail safely to enabled defaults',
      );
    });

    test('corrupt stored values decode to HEAD-compatible defaults', () {
      const corruptValues = <String>[
        '',
        'not json',
        '[]',
        '42',
        '{"version":"one"}',
        '{"lanes":{}}',
        '{"version":1,"lanes":"nope"}',
      ];
      for (final value in corruptValues) {
        expectAllEnabled(
          MediaDownloadPreferences.fromStorageString(value),
          reason: 'corrupt value $value must decode to enabled defaults',
        );
      }
    });

    test('valid payload with a missing lane defaults that lane to enabled',
        () {
      // Only the oneToOne lane is present; discussion and announcement keys
      // are absent and must decode as fully enabled.
      final decoded = MediaDownloadPreferences.fromStorageString(
        '{"version":1,"lanes":{"oneToOne":{"video":{"cellular":false}}}}',
      );
      expect(
        decoded.isAutoDownloadEnabled(
          kind: MediaConversationKind.oneToOne,
          mediaType: 'video',
          network: MediaDownloadNetwork.cellular,
        ),
        isFalse,
      );
      expect(
        decoded.isAutoDownloadEnabled(
          kind: MediaConversationKind.oneToOne,
          mediaType: 'video',
          network: MediaDownloadNetwork.wifi,
        ),
        isTrue,
      );
      for (final kind in const [
        MediaConversationKind.discussion,
        MediaConversationKind.announcement,
      ]) {
        for (final type in allTypes) {
          for (final network in allNetworks) {
            expect(
              decoded.isAutoDownloadEnabled(
                kind: kind,
                mediaType: type,
                network: network,
              ),
              isTrue,
              reason: 'omitted $kind lane must default to enabled',
            );
          }
        }
      }
    });

    test('unknown media types stay enabled so HEAD behavior is preserved', () {
      final decoded = MediaDownloadPreferences.fromStorageString(
        const MediaDownloadPreferences.defaults().toStorageString(),
      );
      expect(
        decoded.isAutoDownloadEnabled(
          kind: MediaConversationKind.oneToOne,
          mediaType: 'something_new',
          network: MediaDownloadNetwork.cellular,
        ),
        isTrue,
      );
    });

    test('equality and storage key are stable', () {
      expect(
        MediaDownloadPreferences.storageKey,
        'media_download_preferences',
      );
      final a = const MediaDownloadPreferences.defaults().copyWithChoice(
        kind: MediaConversationKind.announcement,
        mediaType: 'file',
        network: MediaDownloadNetwork.cellular,
        enabled: false,
      );
      final b = MediaDownloadPreferences.fromStorageString(
        a.toStorageString(),
      );
      expect(a, equals(b));
      expect(a, isNot(equals(const MediaDownloadPreferences.defaults())));
    });
  });
}
