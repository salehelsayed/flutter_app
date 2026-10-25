import 'package:flutter_app/features/posts/application/post_media_draft.dart';
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

  test('unsupported files are left out and reported', () async {
    final picker = FakeMediaPicker()
      ..multipleMediaResult = [
        XFile('/tmp/a.gif'),
        XFile('/tmp/b.webm'),
        XFile('/tmp/c.jpg'),
        XFile('/tmp/d.3gp'),
      ];
    final pick = await pickPostMedia(picker: picker);
    expect(pick.drafts.map((d) => d.localFilePath), ['/tmp/c.jpg']);
    expect(pick.leftOut, isTrue);
    expect(
      (await pickPostMediaDrafts(picker: picker)).map((d) => d.localFilePath),
      ['/tmp/c.jpg'],
    );
  });

  test('an all-unsupported pick attaches nothing', () async {
    final picker = FakeMediaPicker()
      ..multipleMediaResult = [XFile('/tmp/a.mkv')];
    final pick = await pickPostMedia(picker: picker);
    expect(pick.drafts, isEmpty);
    expect(pick.leftOut, isTrue);
  });

  group('combinePostMedia', () {
    const one = PostMediaDraft(localFilePath: '/tmp/1.jpg', mime: 'image/jpeg');
    const two = PostMediaDraft(localFilePath: '/tmp/2.png', mime: 'image/png');
    const clip = PostMediaDraft(localFilePath: '/tmp/v.mp4', mime: 'video/mp4');
    const clip2 = PostMediaDraft(
      localFilePath: '/tmp/w.mov',
      mime: 'video/quicktime',
    );
    const voice = PostMediaDraft(
      localFilePath: '/tmp/n.m4a',
      mime: 'audio/mp4',
    );

    List<String> paths(PostMediaPick pick) =>
        pick.drafts.map((d) => d.localFilePath).toList();

    test('photos added to photos are appended', () {
      final pick = combinePostMedia(const [one], const [two]);
      expect(paths(pick), ['/tmp/1.jpg', '/tmp/2.png']);
      expect(pick.leftOut, isFalse);
    });

    test('photo and video in one pick keeps the photos and reports it', () {
      final pick = combinePostMedia(const [], const [one, clip, two]);
      expect(paths(pick), ['/tmp/1.jpg', '/tmp/2.png']);
      expect(pick.leftOut, isTrue);
    });

    test('two videos keep the first and report it', () {
      final pick = combinePostMedia(const [], const [clip, clip2]);
      expect(paths(pick), ['/tmp/v.mp4']);
      expect(pick.leftOut, isTrue);
    });

    test('a different kind replaces the current media', () {
      expect(paths(combinePostMedia(const [one, two], const [clip])), [
        '/tmp/v.mp4',
      ]);
      expect(paths(combinePostMedia(const [voice], const [one])), [
        '/tmp/1.jpg',
      ]);
      expect(paths(combinePostMedia(const [clip], const [clip2])), [
        '/tmp/w.mov',
      ]);
    });
  });
}
