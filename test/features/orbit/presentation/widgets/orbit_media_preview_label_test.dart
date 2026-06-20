import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/media_preview_descriptor.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_media_preview_label.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart';
import 'package:flutter_app/l10n/app_localizations_en.dart';

MediaAttachment _att(String mediaType, String mime) => MediaAttachment(
  id: 'b-$mediaType-$mime',
  messageId: 'm1',
  mime: mime,
  size: 1000,
  mediaType: mediaType,
  downloadStatus: 'done',
  createdAt: '2026-03-01T00:00:00.000Z',
);

void main() {
  final l10n = AppLocalizationsEn();

  group('orbitMediaPreviewLabel', () {
    test('voice note', () {
      final label = orbitMediaPreviewLabel(
        l10n: l10n,
        media: const MediaPreviewDescriptor(type: 'audio', count: 1),
      );
      expect(label, 'Voice message');
    });

    test('single vs multiple photos', () {
      expect(
        orbitMediaPreviewLabel(
          l10n: l10n,
          media: const MediaPreviewDescriptor(type: 'image', count: 1),
        ),
        'Photo',
      );
      expect(
        orbitMediaPreviewLabel(
          l10n: l10n,
          media: const MediaPreviewDescriptor(type: 'image', count: 3),
        ),
        '3 photos',
      );
    });

    test('GIF is distinct from photo', () {
      expect(
        orbitMediaPreviewLabel(
          l10n: l10n,
          media: const MediaPreviewDescriptor(
            type: 'image',
            count: 1,
            isGif: true,
          ),
        ),
        'GIF',
      );
    });

    test('video / file / mixed', () {
      expect(
        orbitMediaPreviewLabel(
          l10n: l10n,
          media: const MediaPreviewDescriptor(type: 'video', count: 1),
        ),
        'Video',
      );
      expect(
        orbitMediaPreviewLabel(
          l10n: l10n,
          media: const MediaPreviewDescriptor(type: 'file', count: 2),
        ),
        '2 files',
      );
      expect(
        orbitMediaPreviewLabel(
          l10n: l10n,
          media: const MediaPreviewDescriptor(
            type: null,
            count: 2,
            isMixed: true,
          ),
        ),
        '2 attachments',
      );
    });

    test('caption wins over media label', () {
      final label = orbitMediaPreviewLabel(
        l10n: l10n,
        caption: 'See attached',
        media: const MediaPreviewDescriptor(type: 'image', count: 1),
      );
      expect(label, 'See attached');
    });

    test('deleted latest shows the deleted placeholder', () {
      final label = orbitMediaPreviewLabel(
        l10n: l10n,
        caption: '',
        media: const MediaPreviewDescriptor(type: 'image', count: 1),
        isDeleted: true,
      );
      expect(label, l10n.conversation_message_deleted);
    });

    test('no caption and no media -> empty (no preview line)', () {
      expect(orbitMediaPreviewLabel(l10n: l10n), '');
    });

    // INV-4: for a single-type latest message the orbit label uses the SAME
    // word as the shipped notification body — counts are the only addition.
    group('vocabulary matches notificationBodyForMessage (INV-4)', () {
      final cases = <List<MediaAttachment>>[
        [_att('audio', 'audio/mp4')],
        [_att('image', 'image/jpeg')],
        [_att('image', 'image/gif')],
        [_att('video', 'video/mp4')],
        [_att('file', 'application/pdf')],
      ];
      for (final media in cases) {
        test('${media.single.mediaType}/${media.single.mime}', () {
          final descriptor = MediaPreviewDescriptor.fromAttachments(media);
          final orbit = orbitMediaPreviewLabel(l10n: l10n, media: descriptor);
          final notification = notificationBodyForMessage('', media);
          expect(orbit, notification);
        });
      }
    });
  });
}
