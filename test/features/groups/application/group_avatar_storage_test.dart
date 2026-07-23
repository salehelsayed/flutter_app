import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/groups/application/group_avatar_storage.dart';
import 'package:flutter_app/features/settings/application/helpers/avatar_normalization_helper.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String docsPath;

  _FakePathProvider(this.docsPath);

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

class _AvatarDownloadBridge extends Bridge {
  _AvatarDownloadBridge(this.downloadBytes);

  final Uint8List downloadBytes;
  bool parentDirExistedBeforeWrite = false;
  final List<String> sentMessages = <String>[];
  final List<String> commandLog = <String>[];

  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    sentMessages.add(message);
    if (cmd != null) {
      commandLog.add(cmd);
    }
    if (cmd == 'media:download') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      final outputPath = payload['outputPath'] as String;
      final outputFile = File(outputPath);
      parentDirExistedBeforeWrite = await outputFile.parent.exists();
      await outputFile.writeAsBytes(downloadBytes, flush: true);
      return jsonEncode({'ok': true, 'id': payload['id']});
    }
    return jsonEncode({'ok': true});
  }
}

Future<XFile?> _writeProcessedAvatarBytes({
  required String path,
  required Uint8List processedBytes,
}) async {
  final outputPath = '${path}_processed.jpg';
  await File(outputPath).writeAsBytes(processedBytes, flush: true);
  return XFile(outputPath);
}

AvatarNormalizationHelper _makeAvatarNormalizer(Uint8List processedBytes) {
  return AvatarNormalizationHelper(
    imageProcessor: ImageProcessor(
      compressFile:
          ({
            required String path,
            required int quality,
            required bool keepExif,
            int minWidth = 1920,
            int minHeight = 1080,
          }) async {
            return _writeProcessedAvatarBytes(
              path: path,
              processedBytes: processedBytes,
            );
          },
    ),
  );
}

AvatarNormalizationHelper _makeMissingOutputAvatarNormalizer() {
  return AvatarNormalizationHelper(
    imageProcessor: ImageProcessor(
      compressFile:
          ({
            required String path,
            required int quality,
            required bool keepExif,
            int minWidth = 1920,
            int minHeight = 1080,
          }) async {
            return XFile('${path}_compressed.jpg');
          },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('group_avatar_storage_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'downloadGroupAvatar creates the group avatar directory before bridge download',
    () async {
      final bridge = _AvatarDownloadBridge(
        Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
      );
      final processedBytes = Uint8List.fromList([0xCA, 0xFE, 0xBA, 0xBE]);

      final result = await downloadGroupAvatar(
        bridge: bridge,
        groupId: 'group-1',
        blobId: 'blob-1',
        avatarNormalizer: _makeAvatarNormalizer(processedBytes),
      );

      expect(result, 'media/group_avatars/group-1.jpg');
      expect(bridge.parentDirExistedBeforeWrite, isTrue);

      final committedAvatar = File(
        p.join(tempDir.path, 'media', 'group_avatars', 'group-1.jpg'),
      );
      expect(await committedAvatar.exists(), isTrue);
      expect(await committedAvatar.readAsBytes(), processedBytes);
    },
  );

  test(
    'uploadGroupAvatar stores a multi-recipient avatar without blob encryption',
    () async {
      final localFile = File(p.join(tempDir.path, 'prepared-avatar.jpg'));
      await localFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0], flush: true);
      final bridge = _AvatarDownloadBridge(Uint8List(0));

      final result = await uploadGroupAvatar(
        bridge: bridge,
        localFilePath: localFile.path,
        groupId: 'group-1',
        allowedPeers: const ['peer-a', 'peer-b'],
        blobId: 'avatar-blob-1',
      );

      expect(result, isNotNull);
      expect(result!.id, 'avatar-blob-1');
      expect(result.mime, 'image/jpeg');
      expect(bridge.commandLog, ['media:upload']);

      final uploadMessage =
          jsonDecode(bridge.sentMessages.single) as Map<String, dynamic>;
      final payload = uploadMessage['payload'] as Map<String, dynamic>;
      expect(payload['id'], 'avatar-blob-1');
      expect(payload['to'], 'group-1');
      expect(payload['mime'], 'image/jpeg');
      expect(payload['filePath'], localFile.path);
      expect(payload['filePath'] as String, isNot(endsWith('.enc')));
      expect(payload['allowedPeers'], ['peer-a', 'peer-b']);
    },
  );

  test(
    'P269 group avatar empty ACL fails before file access or bridge upload',
    () async {
      final validAvatar = File(p.join(tempDir.path, 'valid-avatar.jpg'));
      await validAvatar.writeAsBytes(const <int>[
        0xFF,
        0xD8,
        0xFF,
        0xE0,
      ], flush: true);
      final validSourceBridge = _AvatarDownloadBridge(Uint8List(0));
      final missingSourceBridge = _AvatarDownloadBridge(Uint8List(0));
      final flowEvents = <Map<String, dynamic>>[];
      final flowLease = installScopedE2EFlowEventSink(flowEvents.add);

      GroupAvatarUpload? validSourceResult;
      GroupAvatarUpload? missingSourceResult;
      try {
        validSourceResult = await uploadGroupAvatar(
          bridge: validSourceBridge,
          localFilePath: validAvatar.path,
          groupId: 'group-1',
          allowedPeers: const <String>[],
          blobId: 'p269-empty-avatar-acl',
        );
        missingSourceResult = await uploadGroupAvatar(
          bridge: missingSourceBridge,
          localFilePath: p.join(tempDir.path, 'missing-avatar.jpg'),
          groupId: 'group-1',
          allowedPeers: const <String>[' ', '\t', '\n'],
          blobId: 'p269-blank-avatar-acl',
        );
      } finally {
        flowLease.release();
      }

      expect(validSourceResult, isNull);
      expect(missingSourceResult, isNull);
      expect(
        validSourceBridge.commandLog,
        isEmpty,
        reason: 'empty group ACL must stop before media:upload',
      );
      expect(validSourceBridge.sentMessages, isEmpty);
      expect(missingSourceBridge.commandLog, isEmpty);
      expect(missingSourceBridge.sentMessages, isEmpty);

      final rejections = flowEvents
          .where((event) => event['event'] == 'GROUP_AVATAR_UPLOAD_REJECTED')
          .toList(growable: false);
      expect(rejections, hasLength(2));
      expect(
        rejections.map(
          (event) => (event['details'] as Map<String, dynamic>)['reason'],
        ),
        everyElement('EMPTY_GROUP_MEDIA_ACL'),
        reason:
            'ACL validation must win even when the supplied source is missing',
      );
      expect(
        flowEvents.where(
          (event) => event['event'] == 'GROUP_AVATAR_UPLOAD_START',
        ),
        isEmpty,
      );
    },
  );

  test(
    'downloadGroupAvatar commits downloaded avatar when normalization output is missing',
    () async {
      final downloadedBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      final bridge = _AvatarDownloadBridge(downloadedBytes);

      final result = await downloadGroupAvatar(
        bridge: bridge,
        groupId: 'group-1',
        blobId: 'blob-1',
        avatarNormalizer: _makeMissingOutputAvatarNormalizer(),
      );

      expect(result, 'media/group_avatars/group-1.jpg');

      final committedAvatar = File(
        p.join(tempDir.path, 'media', 'group_avatars', 'group-1.jpg'),
      );
      expect(await committedAvatar.exists(), isTrue);
      expect(await committedAvatar.readAsBytes(), downloadedBytes);

      final downloadTemp = File(
        p.join(
          tempDir.path,
          'media',
          'group_avatars',
          'group-1.jpg.download.jpg',
        ),
      );
      expect(await downloadTemp.exists(), isFalse);
    },
  );

  test(
    'downloadGroupAvatar rejects fallback commit when downloaded blob is not an image',
    () async {
      final bridge = _AvatarDownloadBridge(
        Uint8List.fromList([0x01, 0x02, 0x03, 0x04]),
      );

      final result = await downloadGroupAvatar(
        bridge: bridge,
        groupId: 'group-1',
        blobId: 'blob-1',
        avatarNormalizer: _makeMissingOutputAvatarNormalizer(),
      );

      expect(result, isNull);
      final committedAvatar = File(
        p.join(tempDir.path, 'media', 'group_avatars', 'group-1.jpg'),
      );
      expect(await committedAvatar.exists(), isFalse);
    },
  );
}
