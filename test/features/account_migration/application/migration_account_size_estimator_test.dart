import 'package:flutter_app/features/account_migration/application/migration_account_size_estimator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AccountMigrationAccountSizeEstimator (P0-1)', () {
    test('sums database, media-root, and secure-value estimate buckets', () async {
      final io = _FakeSizeScanIo(
        lengthsByAbsolutePath: {'/docs/identity.db': 5 * 1024 * 1024},
        filesByRoot: {
          p.join('/docs', 'media'): const [
            _F('a.jpg', 3 * 1024 * 1024),
            _F('b.mp4', 8 * 1024 * 1024),
          ],
          p.join('/docs', 'local_media'): const [_F('c.jpg', 1024)],
          p.join('/docs', 'post_media'): const [_F('post.jpg', 4096)],
          p.join('/docs', 'pending_uploads'): const [_F('d.bin', 2048)],
        },
      );
      final estimator = AccountMigrationAccountSizeEstimator(
        databasePath: '/docs/identity.db',
        documentsRootPath: '/docs',
        io: io,
      );

      final estimate = await estimator();

      expect(estimate.databaseBytes, 5 * 1024 * 1024);
      expect(estimate.mediaBytes, 11 * 1024 * 1024 + 1024 + 4096 + 2048);
      expect(estimate.secureBytes, migrationSecureValuesEstimateBytes);
      expect(
        estimate.totalBytes,
        estimate.databaseBytes + estimate.mediaBytes + estimate.secureBytes,
      );
    });

    test(
      'never reads file contents or hashes: exactly one length call plus one '
      'size-only scan per media root, even with many files',
      () async {
        final manyFiles = [
          for (var i = 0; i < 1000; i++) _F('blob-$i.jpg', 1000),
        ];
        final io = _FakeSizeScanIo(
          lengthsByAbsolutePath: {'/docs/identity.db': 42},
          filesByRoot: {p.join('/docs', 'media'): manyFiles},
        );
        final estimator = AccountMigrationAccountSizeEstimator(
          databasePath: '/docs/identity.db',
          documentsRootPath: '/docs',
          io: io,
        );

        final estimate = await estimator();

        expect(estimate.mediaBytes, 1000 * 1000);
        // The IO seam exposes no content-read or hash surface at all; the
        // call log proves the estimator stays on the size-only scan path:
        // one DB length probe + one recursive size listing per media root.
        expect(
          io.calls,
          unorderedEquals([
            'length:/docs/identity.db',
            for (final root in migrationMediaRootDirectories)
              'list:${p.join('/docs', root)}',
          ]),
        );
      },
    );

    test('missing database file and empty media roots estimate to zero', () async {
      final io = _FakeSizeScanIo(
        lengthsByAbsolutePath: const {},
        filesByRoot: const {},
      );
      final estimator = AccountMigrationAccountSizeEstimator(
        databasePath: '/docs/missing.db',
        documentsRootPath: '/docs',
        io: io,
      );

      final estimate = await estimator();

      expect(estimate.databaseBytes, 0);
      expect(estimate.mediaBytes, 0);
      expect(estimate.totalBytes, migrationSecureValuesEstimateBytes);
    });
  });

  group('AccountMigrationSizePolicy (P0-1)', () {
    test('production cap matches the measured Pixel ceiling', () {
      // P0-7 Pixel benchmark on the v2 path (2026-06-11): 10,000 MB moved in
      // 55.2 min with a flat ~138 MB RSS delta (200/500/1000/2000 MB passes
      // behind it). The cap equals the largest measured passing run; the
      // receiver storage preflight stays the hard disk gate.
      const policy = AccountMigrationSizePolicy.production();
      expect(policy.maxAccountBytes, 10000 * 1024 * 1024);
    });

    test(
      'receiver insufficient-space copy tells the user the exact shortfall',
      () {
        // A 10 GB account needs ~20 GB free on the new phone (2x staging
        // amplification) — the user must see the concrete numbers, not a
        // vague "free some space".
        final message = accountMigrationReceiverStorageInsufficientMessage(
          requiredBytes: 20000 * 1024 * 1024,
          availableBytes: 3500 * 1024 * 1024,
        );
        expect(message, contains('20000 MB'));
        expect(message, contains('3500 MB'));
        expect(message, contains('16500 MB'));
        expect(message, contains('new phone'));
      },
    );

    test(
      'receiver insufficient-space copy falls back to generic wording when '
      'the receiver sent no numbers',
      () {
        final message = accountMigrationReceiverStorageInsufficientMessage();
        expect(message, contains('not have enough free space'));
        expect(message, isNot(contains(' MB')));
      },
    );

    test('cap-blocked copy formats sizes in whole MB', () {
      expect(
        accountMigrationSizeCapBlockedMessage(
          totalBytes: 250 * 1024 * 1024,
          maxAccountBytes: 200 * 1024 * 1024,
        ),
        'This account is too large to move (250 MB of 200 MB max)',
      );
      expect(
        accountMigrationSizeCapBlockedMessage(
          totalBytes: 200 * 1024 * 1024 + 1,
          maxAccountBytes: 200 * 1024 * 1024,
        ),
        'This account is too large to move (201 MB of 200 MB max)',
        reason: 'partial megabytes round up so the copy never claims X of X',
      );
    });
  });
}

class _F {
  final String name;
  final int sizeBytes;

  const _F(this.name, this.sizeBytes);
}

class _FakeSizeScanIo implements MigrationSizeScanIo {
  final Map<String, int> lengthsByAbsolutePath;
  final Map<String, List<_F>> filesByRoot;
  final calls = <String>[];

  _FakeSizeScanIo({
    required this.lengthsByAbsolutePath,
    required this.filesByRoot,
  });

  @override
  Future<int?> fileLength(String absolutePath) async {
    calls.add('length:$absolutePath');
    return lengthsByAbsolutePath[absolutePath];
  }

  @override
  Stream<MigrationScannedFile> listFilesRecursively(
    String rootAbsolutePath,
  ) async* {
    calls.add('list:$rootAbsolutePath');
    for (final file in filesByRoot[rootAbsolutePath] ?? const <_F>[]) {
      yield MigrationScannedFile(
        absolutePath: p.join(rootAbsolutePath, file.name),
        sizeBytes: file.sizeBytes,
      );
    }
  }
}
