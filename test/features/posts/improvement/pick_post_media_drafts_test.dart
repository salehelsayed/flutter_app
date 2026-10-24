import 'package:flutter_app/features/posts/presentation/pick_post_media_drafts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/fakes/fake_media_picker.dart';

void main() {
  test('system picker cancellation leaves no attachment', () async {
    final picker = FakeMediaPicker();
    expect(await pickPostMediaDrafts(picker: picker), isEmpty);
    expect(picker.pickMultipleMediaCalls, 1);
  });

  test(
    'photo selection preserves image paths and skips incompatible video',
    () async {
      final picker = FakeMediaPicker()
        ..multipleMediaResult = [
          XFile('/tmp/a.JPG'),
          XFile('/tmp/b.png'),
          XFile('/tmp/c.mp4'),
        ];
      final drafts = await pickPostMediaDrafts(picker: picker);
      expect(drafts.map((d) => d.localFilePath), ['/tmp/a.JPG', '/tmp/b.png']);
      expect(drafts.map((d) => d.mime), ['image/jpeg', 'image/png']);
    },
  );

  test(
    'HEIF selection keeps the other selected images and excludes video',
    () async {
      final picker = FakeMediaPicker()
        ..multipleMediaResult = [
          XFile('/tmp/a.HEIF'),
          XFile('/tmp/b.jpg'),
          XFile('/tmp/c.mov'),
        ];
      final drafts = await pickPostMediaDrafts(picker: picker);
      expect(drafts.map((d) => d.localFilePath), ['/tmp/a.HEIF', '/tmp/b.jpg']);
      expect(drafts.map((d) => d.mime), ['image/heic', 'image/jpeg']);
    },
  );

  test(
    'video selection produces one existing video draft without mixed media',
    () async {
      final picker = FakeMediaPicker()
        ..multipleMediaResult = [
          XFile('/tmp/a.mov'),
          XFile('/tmp/b.mp4'),
          XFile('/tmp/c.jpg'),
        ];
      final drafts = await pickPostMediaDrafts(picker: picker);
      expect(drafts.single.localFilePath, '/tmp/a.mov');
      expect(drafts.single.kind, 'video');
      expect(drafts.single.mime, 'video/quicktime');
    },
  );
}
