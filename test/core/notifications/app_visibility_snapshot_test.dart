import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'TC-371-01 v1 codec and fresh exact predicate fail toward notification',
    () async {
      final fixture =
          jsonDecode(
                await File(
                  'test/shared/fixtures/app_visibility_snapshot_v1.json',
                ).readAsString(),
              )
              as Map<String, Object?>;
      expect(fixture['schemaVersion'], appVisibilitySnapshotSchemaVersion);
      expect(fixture['digestDomain'], appVisibilityDigestDomain);
      expect(fixture['freshnessWindowMs'], appVisibilityFreshnessWindowMs);
      expect(fixture['heartbeatIntervalMs'], appVisibilityHeartbeatIntervalMs);
      expect(appVisibilityFreshnessWindow, const Duration(seconds: 90));
      expect(appVisibilityHeartbeatInterval, const Duration(seconds: 60));

      final digestVectors = (fixture['digestVectors'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(digestVectors, hasLength(5));
      for (final vector in digestVectors) {
        final lane = AppVisibilityConversationLane.tryParse(vector['lane']);
        expect(lane, isNotNull, reason: vector['name'] as String);
        final identity = AppVisibilityConversationIdentity.tryParse(
          lane: lane!,
          value: vector['input'] as String,
        );
        expect(identity, isNotNull, reason: vector['name'] as String);
        expect(
          identity!.normalizedId,
          vector['normalizedId'],
          reason: vector['name'] as String,
        );
        expect(identity.lane.laneByte, vector['laneByte']);
        expect(_hex(identity.preimage), vector['preimageHex']);
        expect(identity.digest, vector['digest']);
      }
      final groupOwner = digestVectors.singleWhere(
        (vector) => vector['name'] == 'group_owner',
      );
      final groupAnchor = digestVectors.singleWhere(
        (vector) => vector['name'] == 'group_message_anchor',
      );
      expect(groupAnchor['digest'], groupOwner['digest']);
      expect(groupAnchor['preimageHex'], groupOwner['preimageHex']);

      final invalidConversations =
          (fixture['invalidConversationVectors'] as List<Object?>)
              .cast<Map<String, Object?>>();
      for (final vector in invalidConversations) {
        final lane = AppVisibilityConversationLane.tryParse(vector['lane'])!;
        expect(
          AppVisibilityConversationIdentity.tryParse(
            lane: lane,
            value: vector['input'] as String,
          ),
          isNull,
          reason: vector['name'] as String,
        );
      }

      final predicateVectors = (fixture['predicateVectors'] as List<Object?>)
          .cast<Map<String, Object?>>();
      for (final vector in predicateVectors) {
        final snapshot = AppVisibilitySnapshotCodec.tryDecodePlatform(
          vector['snapshot'],
        );
        expect(snapshot, isNotNull, reason: vector['name'] as String);
        final encoded = AppVisibilitySnapshotCodec.encode(snapshot!);
        expect(
          AppVisibilitySnapshotCodec.tryDecode(encoded)?.toJson(),
          snapshot.toJson(),
          reason: vector['name'] as String,
        );
        expect(
          maySuppressAppVisibilityNotification(
            snapshot: snapshot,
            currentMonotonicMs: vector['currentMonotonicMs'] as int,
            currentBootSession: vector['currentBootSession'] as String,
            expectedConversationDigest:
                vector['expectedConversationDigest'] as String,
          ),
          vector['maySuppress'],
          reason: vector['name'] as String,
        );
      }

      final invalidSnapshots =
          (fixture['invalidSnapshotVectors'] as List<Object?>)
              .cast<Map<String, Object?>>();
      for (final vector in invalidSnapshots) {
        expect(
          AppVisibilitySnapshotCodec.tryDecodePlatform(vector['snapshot']),
          isNull,
          reason: vector['name'] as String,
        );
      }

      final validMap = Map<String, Object?>.from(
        predicateVectors.first['snapshot']! as Map,
      );
      expect(AppVisibilitySnapshotCodec.tryDecode('{truncated'), isNull);
      expect(AppVisibilitySnapshotCodec.tryDecode('null'), isNull);
      expect(isCanonicalAppVisibilityBootSession('unavailable'), isFalse);
      expect(
        AppVisibilitySnapshotCodec.tryDecodePlatform(
          Map<String, Object?>.from(validMap)..remove('revision'),
        ),
        isNull,
      );
      expect(
        AppVisibilitySnapshotCodec.tryDecodePlatform(
          Map<String, Object?>.from(validMap)..['unexpected'] = true,
        ),
        isNull,
      );
      expect(
        AppVisibilitySnapshotCodec.tryDecodePlatform(
          Map<String, Object?>.from(validMap)..['updatedMonotonicMs'] = 1.0,
        ),
        isNull,
      );

      final validSnapshot = AppVisibilitySnapshotCodec.tryDecodePlatform(
        validMap,
      )!;
      const directDigest =
          'f763fe7fb5062aff9fa31df44c20cd900c3484a4600de4b941ecd1ca8e940ad2';
      expect(
        maySuppressAppVisibilityNotification(
          snapshot: null,
          currentMonotonicMs: 1001,
          currentBootSession: 'test:boot-42',
          expectedConversationDigest: directDigest,
        ),
        isFalse,
      );
      for (final invalidNow in <int>[-1, appVisibilityMaxSignedInt64 + 1]) {
        expect(
          maySuppressAppVisibilityNotification(
            snapshot: validSnapshot,
            currentMonotonicMs: invalidNow,
            currentBootSession: 'test:boot-42',
            expectedConversationDigest: directDigest,
          ),
          isFalse,
        );
      }
      for (final invalidDigest in <String>[
        '',
        directDigest.toUpperCase(),
        '${directDigest}0',
      ]) {
        expect(
          maySuppressAppVisibilityNotification(
            snapshot: validSnapshot,
            currentMonotonicMs: 1001,
            currentBootSession: 'test:boot-42',
            expectedConversationDigest: invalidDigest,
          ),
          isFalse,
        );
      }
      for (final malformedUnicode in <String>[
        String.fromCharCode(0xd800),
        String.fromCharCode(0xdc00),
      ]) {
        expect(
          AppVisibilityConversationIdentity.tryParse(
            lane: AppVisibilityConversationLane.direct,
            value: malformedUnicode,
          ),
          isNull,
        );
        expect(isCanonicalAppVisibilityBootSession(malformedUnicode), isFalse);
      }
      expect(
        isCurrentForegroundAppVisibilitySnapshot(
          snapshot: validSnapshot,
          currentMonotonicMs: 1001,
          currentBootSession: 'test:boot-42',
        ),
        isTrue,
      );
      expect(
        isCurrentForegroundAppVisibilitySnapshot(
          snapshot: validSnapshot,
          currentMonotonicMs: 91000,
          currentBootSession: 'test:boot-42',
        ),
        isFalse,
        reason: 'the 90-second boundary is strictly stale',
      );

      expect(
        () => const AppVisibilitySnapshotV1(
          schemaVersion: appVisibilitySnapshotSchemaVersion,
          revision: appVisibilityMaxSignedInt64 + 1,
          lifecycleGeneration: 1,
          lifecycle: AppVisibilityLifecycle.foregroundActive,
          visibleConversationDigest: directDigest,
          updatedMonotonicMs: 0,
          bootSession: 'test:boot-42',
        ).toJson(),
        throwsFormatException,
        reason: 'revision overflow cannot be rewritten as v1',
      );
    },
  );
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
