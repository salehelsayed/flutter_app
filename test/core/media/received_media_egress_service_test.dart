import 'dart:io';

import 'package:flutter_app/core/media/app_owned_media_path_authority.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_gateway.dart';
import 'package:flutter_app/core/media/received_media_egress_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late Directory media;
  late _Gateway gateway;
  late ReceivedMediaEgressService service;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('egress-service-');
    media = await Directory(
      p.join(temp.path, 'media', 'peer'),
    ).create(recursive: true);
    gateway = _Gateway();
    service = ReceivedMediaEgressService(
      gateway: gateway,
      resolveStoredPath: (path) async =>
          p.isAbsolute(path) ? path : p.join(temp.path, path),
      documentsDirectory: () async => temp,
    );
  });

  tearDown(() => temp.delete(recursive: true));

  test(
    'qualified selection builds one canonical bounded egress request',
    () async {
      final candidates = <ReceivedMediaEgressCandidate>[];
      for (var i = 0; i < kMaxMediaEgressItems; i++) {
        final path = p.join(media.path, '$i.jpg');
        await File(path).writeAsBytes(<int>[i]);
        candidates.add(
          ReceivedMediaEgressCandidate(
            attachmentId: 'blob_$i',
            storedPath: p.relative(path, from: temp.path),
            mime: 'image/jpeg',
          ),
        );
      }
      candidates.insert(2, candidates.first);

      final result = await service.perform(
        requestId: 'safe_request-1',
        destination: MediaEgressDestination.photos,
        selection: candidates,
      );

      expect(result.outcome, MediaEgressOutcome.saved);
      expect(gateway.requests, hasLength(1));
      expect(
        gateway.requests.single.items.map((e) => e.attachmentId),
        List.generate(kMaxMediaEgressItems, (i) => 'blob_$i'),
      );
      expect(gateway.requests.single.items.first.displayName, 'blob_0.jpg');
      expect(
        gateway.requests.single.items.first.sourcePath,
        await File(p.join(media.path, '0.jpg')).resolveSymbolicLinks(),
      );

      final overflow = await service.perform(
        requestId: 'overflow',
        destination: MediaEgressDestination.photos,
        selection: [
          ...candidates.where((e) => e.attachmentId != 'blob_0'),
          candidates.first,
          const ReceivedMediaEgressCandidate(
            attachmentId: 'extra',
            storedPath: 'media/extra.jpg',
            mime: 'image/jpeg',
          ),
        ],
      );
      expect(overflow.outcome, MediaEgressOutcome.rejected);
      expect(gateway.requests, hasLength(1));

      final conflict = await service.perform(
        requestId: 'conflict',
        destination: MediaEgressDestination.photos,
        selection: [
          candidates.first,
          ReceivedMediaEgressCandidate(
            attachmentId: candidates.first.attachmentId,
            storedPath: candidates[3].storedPath,
            mime: 'image/jpeg',
          ),
        ],
      );
      expect(
        conflict.items.single.outcome,
        MediaEgressItemOutcome.identityConflict,
      );
      expect(gateway.requests, hasLength(1));
    },
  );

  test('ownership escapes fail closed before native egress', () async {
    final valid = File(p.join(media.path, 'valid.jpg'))
      ..writeAsBytesSync([1, 2]);
    final outside = File(
      p.join(temp.parent.path, 'outside-${temp.path.hashCode}.jpg'),
    )..writeAsBytesSync([3]);
    final sibling = Directory('${temp.path}-prefix')..createSync();
    final siblingFile = File(p.join(sibling.path, 'x.jpg'))
      ..writeAsBytesSync([4]);
    final symlink = Link(p.join(media.path, 'escape.jpg'));
    var symlinkSupported = true;
    try {
      symlink.createSync(outside.path);
    } catch (_) {
      symlinkSupported = false;
    }
    final selection = <ReceivedMediaEgressCandidate>[
      ReceivedMediaEgressCandidate(
        attachmentId: 'valid',
        storedPath: valid.path,
        mime: 'image/jpeg',
      ),
      ReceivedMediaEgressCandidate(
        attachmentId: 'outside',
        storedPath: outside.path,
        mime: 'image/jpeg',
      ),
      ReceivedMediaEgressCandidate(
        attachmentId: 'prefix',
        storedPath: siblingFile.path,
        mime: 'image/jpeg',
      ),
      if (symlinkSupported)
        ReceivedMediaEgressCandidate(
          attachmentId: 'link',
          storedPath: symlink.path,
          mime: 'image/jpeg',
        ),
      const ReceivedMediaEgressCandidate(
        attachmentId: 'missing',
        storedPath: 'media/peer/missing.jpg',
        mime: 'image/jpeg',
      ),
      ReceivedMediaEgressCandidate(
        attachmentId: 'text',
        storedPath: valid.path,
        mime: 'text/plain',
      ),
    ];

    final save = await service.perform(
      requestId: 'save',
      destination: MediaEgressDestination.files,
      selection: selection,
    );
    expect(gateway.requests.single.items.map((e) => e.attachmentId), ['valid']);
    expect(save.items.first.outcome, MediaEgressItemOutcome.saved);
    expect(
      save.items.skip(1).map((e) => e.outcome),
      everyElement(isNot(MediaEgressItemOutcome.saved)),
    );

    gateway.requests.clear();
    final share = await service.perform(
      requestId: 'share',
      destination: MediaEgressDestination.share,
      selection: selection,
    );
    expect(share.outcome, MediaEgressOutcome.rejected);
    expect(share.items, isEmpty);
    expect(gateway.requests, isEmpty);
    outside.deleteSync();
    sibling.deleteSync(recursive: true);
  });

  test('a symlinked approved root is not an ownership authority', () async {
    final outsideRoot = await Directory(
      p.join(temp.parent.path, 'egress-root-${temp.path.hashCode}'),
    ).create();
    final outsideFile = File(p.join(outsideRoot.path, 'escaped.jpg'))
      ..writeAsBytesSync([7, 7]);
    await media.parent.delete(recursive: true);
    var symlinkSupported = true;
    try {
      await Link(p.join(temp.path, 'media')).create(outsideRoot.path);
    } catch (_) {
      symlinkSupported = false;
    }
    if (symlinkSupported) {
      final result = await service.perform(
        requestId: 'root_escape',
        destination: MediaEgressDestination.photos,
        selection: [
          ReceivedMediaEgressCandidate(
            attachmentId: 'escaped',
            storedPath: outsideFile.path,
            mime: 'image/jpeg',
          ),
        ],
      );
      expect(result.outcome, MediaEgressOutcome.rejected);
      expect(
        result.items.single.outcome,
        MediaEgressItemOutcome.outsideOwnedRoot,
      );
      expect(gateway.requests, isEmpty);
    }
    await outsideRoot.delete(recursive: true);
  });

  test(
    'failure busy and late completion preserve source without staging',
    () async {
      final source = File(p.join(media.path, 'stable.mp4'))
        ..writeAsBytesSync([1, 9, 2, 8]);
      gateway.response = const MediaEgressResult(
        requestId: 'stable',
        outcome: MediaEgressOutcome.busy,
        items: [],
      );
      final before = source.readAsBytesSync();
      final result = await service.perform(
        requestId: 'stable',
        destination: MediaEgressDestination.share,
        selection: [
          ReceivedMediaEgressCandidate(
            attachmentId: 'v',
            storedPath: source.path,
            mime: 'video/mp4',
          ),
        ],
      );
      expect(result.outcome, MediaEgressOutcome.busy);
      expect(source.readAsBytesSync(), before);
      expect(
        Directory(p.join(temp.path, 'share_staging')).existsSync(),
        isFalse,
      );
    },
  );

  test('native busy wins over merged structural rejects', () async {
    final source = File(p.join(media.path, 'busy.jpg'))
      ..writeAsBytesSync([4, 2]);
    gateway.response = const MediaEgressResult(
      requestId: 'busy_merge',
      outcome: MediaEgressOutcome.busy,
      items: [
        MediaEgressItemResult(
          attachmentId: 'valid',
          outcome: MediaEgressItemOutcome.busy,
        ),
      ],
    );

    final result = await service.perform(
      requestId: 'busy_merge',
      destination: MediaEgressDestination.files,
      selection: [
        ReceivedMediaEgressCandidate(
          attachmentId: 'valid',
          storedPath: source.path,
          mime: 'image/jpeg',
        ),
        const ReceivedMediaEgressCandidate(
          attachmentId: 'missing',
          storedPath: 'media/peer/missing.jpg',
          mime: 'image/jpeg',
        ),
      ],
    );

    expect(result.outcome, MediaEgressOutcome.busy);
    expect(result.items.map((item) => item.outcome), [
      MediaEgressItemOutcome.busy,
      MediaEgressItemOutcome.missingFile,
    ]);
  });

  test(
    'egress delegates canonical ownership to shared path authority',
    () async {
      final source = File(p.join(media.path, 'shared.jpg'))
        ..writeAsBytesSync([1, 2, 3]);
      final nonCanonical = p.join(media.path, '..', 'peer', 'shared.jpg');
      final canonical = await source.resolveSymbolicLinks();
      final authority = _RecordingAuthority(canonical);
      final delegated = ReceivedMediaEgressService(
        gateway: gateway,
        resolveStoredPath: (_) async => nonCanonical,
        pathAuthority: authority,
      );

      final result = await delegated.perform(
        requestId: 'shared_authority',
        destination: MediaEgressDestination.files,
        selection: const [
          ReceivedMediaEgressCandidate(
            attachmentId: 'shared',
            storedPath: 'ignored',
            mime: 'image/jpeg',
          ),
        ],
      );

      expect(result.outcome, MediaEgressOutcome.saved);
      expect(authority.candidates, [nonCanonical]);
      expect(gateway.requests.single.items.single.sourcePath, canonical);
    },
  );

  test('shared path authority exception fails closed before native', () async {
    final source = File(p.join(media.path, 'throws.jpg'))
      ..writeAsBytesSync([9]);
    final delegated = ReceivedMediaEgressService(
      gateway: gateway,
      resolveStoredPath: (_) async => source.path,
      pathAuthority: _RecordingAuthority(null, throwsError: true),
    );

    final result = await delegated.perform(
      requestId: 'authority_throws',
      destination: MediaEgressDestination.files,
      selection: const [
        ReceivedMediaEgressCandidate(
          attachmentId: 'throws',
          storedPath: 'ignored',
          mime: 'image/jpeg',
        ),
      ],
    );

    expect(result.outcome, MediaEgressOutcome.rejected);
    expect(
      result.items.single.outcome,
      MediaEgressItemOutcome.outsideOwnedRoot,
    );
    expect(gateway.requests, isEmpty);
  });
}

class _RecordingAuthority implements AppOwnedMediaPathAuthority {
  _RecordingAuthority(this.canonical, {this.throwsError = false});

  final String? canonical;
  final bool throwsError;
  final candidates = <String?>[];

  @override
  Future<String?> authorize(String? candidatePath) async {
    candidates.add(candidatePath);
    if (throwsError) throw StateError('authority unavailable');
    return canonical;
  }
}

class _Gateway implements ReceivedMediaEgressGateway {
  final requests = <MediaEgressRequest>[];
  MediaEgressResult? response;
  @override
  Future<MediaEgressResult> perform(MediaEgressRequest request) async {
    requests.add(request);
    if (response != null) return response!;
    return MediaEgressResult(
      requestId: request.requestId,
      outcome: request.destination == MediaEgressDestination.share
          ? MediaEgressOutcome.presented
          : MediaEgressOutcome.saved,
      items: request.destination == MediaEgressDestination.share
          ? const []
          : request.items
                .map(
                  (e) => MediaEgressItemResult(
                    attachmentId: e.attachmentId,
                    outcome: MediaEgressItemOutcome.saved,
                  ),
                )
                .toList(),
    );
  }
}
