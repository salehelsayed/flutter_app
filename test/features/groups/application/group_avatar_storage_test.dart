import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
}
