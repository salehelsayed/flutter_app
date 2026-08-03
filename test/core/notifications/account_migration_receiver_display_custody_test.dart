import 'dart:async';

import 'package:flutter_app/app/application_root.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'transferred display custody retries only after projection rebuild',
    () async {
      final projectionEntered = Completer<void>();
      final releaseProjection = Completer<void>();
      final order = <String>[];

      final activation = activateAccountMigrationReceiverNotificationState(
        beginCanonicalNotificationRecovery: () => order.add('recovery:begin'),
        invalidateIdentityCache: () => order.add('invalidate'),
        rebuildRecipientProjection: () async {
          order.add('projection:start');
          projectionEntered.complete();
          await releaseProjection.future;
          order.add('projection:done');
        },
        endCanonicalNotificationRecovery:
            ({required canonicalStateComplete}) async {
              order.add('recovery:end:$canonicalStateComplete');
              if (canonicalStateComplete) order.add('custody:retry');
            },
      );

      await projectionEntered.future;
      expect(order, <String>[
        'recovery:begin',
        'invalidate',
        'projection:start',
      ]);

      releaseProjection.complete();
      await activation;
      expect(order, <String>[
        'recovery:begin',
        'invalidate',
        'projection:start',
        'projection:done',
        'recovery:end:true',
        'custody:retry',
      ]);
    },
  );

  test(
    'projection failure retains transferred custody without retrying',
    () async {
      var retries = 0;
      bool? endedWithCanonicalState;

      await expectLater(
        activateAccountMigrationReceiverNotificationState(
          beginCanonicalNotificationRecovery: () {},
          invalidateIdentityCache: () {},
          rebuildRecipientProjection: () async {
            throw StateError('projection failed');
          },
          endCanonicalNotificationRecovery:
              ({required canonicalStateComplete}) async {
                endedWithCanonicalState = canonicalStateComplete;
                if (canonicalStateComplete) retries += 1;
              },
        ),
        throwsStateError,
      );

      expect(retries, 0);
      expect(endedWithCanonicalState, isFalse);
    },
  );
}
