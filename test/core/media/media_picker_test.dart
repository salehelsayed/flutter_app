import 'package:flutter/services.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// Replaces only the plugin's platform port. The app's SystemMediaPicker and
/// ImagePicker adapter still execute, including their null/empty conversion.
class _PlatformPicker extends ImagePickerPlatform {
  final calls = <String>[];
  XFile? cameraResult;
  List<XFile> galleryResult = [];
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    calls.add('image-${source.name}');
    return cameraResult;
  }

  @override
  Future<XFile?> getVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async {
    calls.add('video-${source.name}');
    return null;
  }

  @override
  Future<List<XFile>> getMedia({required MediaOptions options}) async {
    expect(options.allowMultiple, isTrue);
    calls.add('gallery');
    return galleryResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'MEDIA-009 system adapter carries native cancellation then fresh results without cached picks',
    () async {
      final previous = ImagePickerPlatform.instance;
      final platform = _PlatformPicker();
      ImagePickerPlatform.instance = platform;
      addTearDown(() => ImagePickerPlatform.instance = previous);
      final picker = SystemMediaPicker();
      expect(await picker.pickImage(source: ImageSource.camera), isNull);
      expect(await picker.pickVideo(source: ImageSource.camera), isNull);
      expect(await picker.pickMultipleMedia(), isEmpty);
      platform.cameraResult = XFile('/fixture/fresh.png');
      platform.galleryResult = [
        XFile('/fixture/fresh.png'),
        XFile('/fixture/second.png'),
      ];
      expect(
        (await picker.pickImage(source: ImageSource.camera))!.path,
        '/fixture/fresh.png',
      );
      expect((await picker.pickMultipleMedia()).map((f) => f.path), [
        '/fixture/fresh.png',
        '/fixture/second.png',
      ]);
      platform.cameraResult = null;
      platform.galleryResult = [];
      expect(await picker.pickImage(source: ImageSource.camera), isNull);
      expect(await picker.pickMultipleMedia(), isEmpty);
      expect(platform.calls, [
        'image-camera',
        'video-camera',
        'gallery',
        'image-camera',
        'gallery',
        'image-camera',
        'gallery',
      ]);
    },
  );

  test(
    'MEDIA-009/MEDIA-013 native document cancel and pathless entries cannot become a stale selected file',
    () async {
      const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Object? nativeResult;
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        expect(call.method, 'custom');
        final options = call.arguments as Map;
        expect(options['allowMultipleSelection'], isTrue);
        expect(options['allowedExtensions'], ['pdf']);
        return nativeResult;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final picker = SystemMediaPicker();
      expect(await picker.pickDocuments(), isEmpty);
      nativeResult = [
        {'path': null, 'name': 'unavailable.pdf', 'size': 40},
        {'path': '/fixture/fresh.pdf', 'name': 'fresh.pdf', 'size': 400},
      ];
      final selected = await picker.pickDocuments();
      expect(selected.map((f) => (f.path, f.name)), [
        ('/fixture/fresh.pdf', 'fresh.pdf'),
      ]);
      nativeResult = null;
      expect(await picker.pickDocuments(), isEmpty);
      expect(calls, 3);
    },
  );
}
