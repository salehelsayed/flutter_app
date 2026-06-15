import 'package:flutter/services.dart';
import 'package:flutter_app/core/device/disk_space.dart';
import 'package:flutter_app/features/account_migration/application/migration_storage_preflight.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_file_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DiskSpaceChannel (P0-6)', () {
    test('returns available bytes from the platform invoker', () async {
      final channel = DiskSpaceChannel(
        invoker: (method, arguments) async {
          expect(method, 'getAvailableBytes');
          expect(arguments, {'path': '/data/docs'});
          return 123456789;
        },
      );

      expect(await channel.getAvailableBytes('/data/docs'), 123456789);
    });

    test('speaks the real mknoon/disk_space method channel contract', () async {
      final recordedCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(DiskSpaceChannel.channelName),
            (call) async {
              recordedCalls.add(call);
              return 42;
            },
          );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(DiskSpaceChannel.channelName),
              null,
            );
      });

      final channel = DiskSpaceChannel();
      expect(await channel.getAvailableBytes('/docs'), 42);
      expect(recordedCalls.single.method, 'getAvailableBytes');
      expect(recordedCalls.single.arguments, {'path': '/docs'});
    });

    test('null or negative platform answers are an error, not a zero', () async {
      final nullChannel = DiskSpaceChannel(invoker: (_, _) async => null);
      expect(
        () => nullChannel.getAvailableBytes('/docs'),
        throwsA(isA<StateError>()),
      );

      final negativeChannel = DiskSpaceChannel(invoker: (_, _) async => -1);
      expect(
        () => negativeChannel.getAvailableBytes('/docs'),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'provider failure surfaces as a typed storageUnavailable preflight '
      'block, never a crash',
      () async {
        final channel = DiskSpaceChannel(
          invoker: (_, _) async => throw MissingPluginException(),
        );
        final preflight = MigrationStoragePreflight(
          availableBytesProvider: () => channel.getAvailableBytes('/docs'),
        );

        final result = await preflight.evaluate(
          manifest: MigrationFileManifest(
            items: [
              MigrationFileManifestItem(
                kind: MigrationFileManifestItemKind.chatMedia,
                criticality: MigrationFileCriticality.critical,
                relativePath: 'media/a.jpg',
                sizeBytes: 10,
                sha256: 'a' * 64,
                sourceTable: 'media_attachments',
                sourceId: 'blob',
              ),
            ],
          ),
        );

        expect(result.isAccepted, isFalse);
        expect(
          result.reason,
          MigrationStoragePreflightReason.storageUnavailable,
        );
      },
    );
  });
}
