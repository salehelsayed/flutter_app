import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

void main() {
  const testAttachment = MediaAttachment(
    id: 'blob-uuid-001',
    messageId: 'msg-uuid-001',
    mime: 'image/jpeg',
    size: 245000,
    mediaType: 'image',
    width: 1920,
    height: 1080,
    durationMs: null,
    localPath: '/path/to/file.jpg',
    downloadStatus: 'done',
    createdAt: '2026-02-20T10:00:00.000Z',
  );

  group('MediaAttachment', () {
    group('fromMap / toMap round-trip', () {
      test('round-trips correctly with all fields', () {
        final map = testAttachment.toMap();
        final restored = MediaAttachment.fromMap(map);

        expect(restored.id, testAttachment.id);
        expect(restored.messageId, testAttachment.messageId);
        expect(restored.mime, testAttachment.mime);
        expect(restored.size, testAttachment.size);
        expect(restored.mediaType, testAttachment.mediaType);
        expect(restored.width, testAttachment.width);
        expect(restored.height, testAttachment.height);
        expect(restored.durationMs, testAttachment.durationMs);
        expect(restored.localPath, testAttachment.localPath);
        expect(restored.downloadStatus, testAttachment.downloadStatus);
        expect(restored.createdAt, testAttachment.createdAt);
      });

      test('toMap produces correct snake_case keys', () {
        final map = testAttachment.toMap();

        expect(map['id'], 'blob-uuid-001');
        expect(map['message_id'], 'msg-uuid-001');
        expect(map['mime'], 'image/jpeg');
        expect(map['size'], 245000);
        expect(map['media_type'], 'image');
        expect(map['width'], 1920);
        expect(map['height'], 1080);
        expect(map['duration_ms'], isNull);
        expect(map['local_path'], '/path/to/file.jpg');
        expect(map['download_status'], 'done');
        expect(map['created_at'], '2026-02-20T10:00:00.000Z');
      });

      test('round-trips with null optional fields', () {
        const minimal = MediaAttachment(
          id: 'blob-002',
          messageId: 'msg-002',
          mime: 'application/pdf',
          size: 100,
          mediaType: 'file',
          downloadStatus: 'pending',
          createdAt: '2026-02-20T11:00:00.000Z',
        );
        final map = minimal.toMap();
        final restored = MediaAttachment.fromMap(map);

        expect(restored.width, isNull);
        expect(restored.height, isNull);
        expect(restored.durationMs, isNull);
        expect(restored.localPath, isNull);
      });

      test('fromMap defaults size to 0 when null', () {
        final map = testAttachment.toMap();
        map['size'] = null;
        final restored = MediaAttachment.fromMap(map);
        expect(restored.size, 0);
      });

      test('fromMap defaults downloadStatus to pending when null', () {
        final map = testAttachment.toMap();
        map['download_status'] = null;
        final restored = MediaAttachment.fromMap(map);
        expect(restored.downloadStatus, 'pending');
      });
    });

    group('fromJson / toJson round-trip', () {
      test('toJson produces camelCase keys without DB-only fields', () {
        final json = testAttachment.toJson();

        expect(json['id'], 'blob-uuid-001');
        expect(json['mime'], 'image/jpeg');
        expect(json['size'], 245000);
        expect(json['mediaType'], 'image');
        expect(json['width'], 1920);
        expect(json['height'], 1080);
        // toJson excludes DB-only fields
        expect(json.containsKey('messageId'), isFalse);
        expect(json.containsKey('localPath'), isFalse);
        expect(json.containsKey('downloadStatus'), isFalse);
        expect(json.containsKey('createdAt'), isFalse);
      });

      test('toJson omits null optional fields', () {
        const noOptionals = MediaAttachment(
          id: 'blob-003',
          messageId: 'msg-003',
          mime: 'audio/mp3',
          size: 500,
          mediaType: 'audio',
          downloadStatus: 'pending',
          createdAt: '2026-02-20T12:00:00.000Z',
        );
        final json = noOptionals.toJson();

        expect(json.containsKey('width'), isFalse);
        expect(json.containsKey('height'), isFalse);
        expect(json.containsKey('durationMs'), isFalse);
      });

      test('fromJson parses wire format correctly', () {
        final json = {
          'id': 'blob-wire-001',
          'mime': 'video/mp4',
          'size': 5000000,
          'mediaType': 'video',
          'width': 1280,
          'height': 720,
          'durationMs': 30000,
        };
        final restored = MediaAttachment.fromJson(json);

        expect(restored.id, 'blob-wire-001');
        expect(restored.mime, 'video/mp4');
        expect(restored.size, 5000000);
        expect(restored.mediaType, 'video');
        expect(restored.width, 1280);
        expect(restored.height, 720);
        expect(restored.durationMs, 30000);
        // fromJson sets these to defaults
        expect(restored.messageId, '');
        expect(restored.localPath, isNull);
        expect(restored.downloadStatus, 'pending');
        expect(restored.createdAt, isNotEmpty);
      });

      test('fromJson infers mediaType from mime when not provided', () {
        final json = {
          'id': 'blob-infer',
          'mime': 'image/png',
          'size': 1000,
        };
        final restored = MediaAttachment.fromJson(json);
        expect(restored.mediaType, 'image');
      });

      test('fromJson defaults mime to application/octet-stream when null', () {
        final json = {
          'id': 'blob-no-mime',
          'size': 100,
        };
        final restored = MediaAttachment.fromJson(json);
        expect(restored.mime, 'application/octet-stream');
        expect(restored.mediaType, 'file');
      });

      test('round-trip: toJson then fromJson preserves wire fields', () {
        final json = testAttachment.toJson();
        final restored = MediaAttachment.fromJson(json);

        expect(restored.id, testAttachment.id);
        expect(restored.mime, testAttachment.mime);
        expect(restored.size, testAttachment.size);
        expect(restored.mediaType, testAttachment.mediaType);
        expect(restored.width, testAttachment.width);
        expect(restored.height, testAttachment.height);
      });
    });

    group('mediaTypeFromMime', () {
      test('returns image for image/* types', () {
        expect(MediaAttachment.mediaTypeFromMime('image/jpeg'), 'image');
        expect(MediaAttachment.mediaTypeFromMime('image/png'), 'image');
        expect(MediaAttachment.mediaTypeFromMime('image/gif'), 'image');
        expect(MediaAttachment.mediaTypeFromMime('image/webp'), 'image');
      });

      test('returns video for video/* types', () {
        expect(MediaAttachment.mediaTypeFromMime('video/mp4'), 'video');
        expect(MediaAttachment.mediaTypeFromMime('video/quicktime'), 'video');
      });

      test('returns audio for audio/* types', () {
        expect(MediaAttachment.mediaTypeFromMime('audio/mpeg'), 'audio');
        expect(MediaAttachment.mediaTypeFromMime('audio/mp3'), 'audio');
        expect(MediaAttachment.mediaTypeFromMime('audio/ogg'), 'audio');
      });

      test('returns file for unknown mime types', () {
        expect(MediaAttachment.mediaTypeFromMime('application/pdf'), 'file');
        expect(MediaAttachment.mediaTypeFromMime('text/plain'), 'file');
        expect(MediaAttachment.mediaTypeFromMime('application/octet-stream'), 'file');
      });
    });

    group('copyWith', () {
      test('creates a copy with updated fields', () {
        final updated = testAttachment.copyWith(
          downloadStatus: 'failed',
          localPath: '/new/path.jpg',
        );

        expect(updated.downloadStatus, 'failed');
        expect(updated.localPath, '/new/path.jpg');
        expect(updated.id, testAttachment.id);
        expect(updated.mime, testAttachment.mime);
      });

      test('creates identical copy when no args passed', () {
        final copy = testAttachment.copyWith();

        expect(copy.id, testAttachment.id);
        expect(copy.messageId, testAttachment.messageId);
        expect(copy.mime, testAttachment.mime);
        expect(copy.size, testAttachment.size);
        expect(copy.mediaType, testAttachment.mediaType);
        expect(copy.width, testAttachment.width);
        expect(copy.height, testAttachment.height);
        expect(copy.durationMs, testAttachment.durationMs);
        expect(copy.localPath, testAttachment.localPath);
        expect(copy.downloadStatus, testAttachment.downloadStatus);
        expect(copy.createdAt, testAttachment.createdAt);
      });

      test('can update messageId for post-upload assignment', () {
        const uploaded = MediaAttachment(
          id: 'blob-upload',
          messageId: '',
          mime: 'image/jpeg',
          size: 1000,
          mediaType: 'image',
          downloadStatus: 'done',
          createdAt: '2026-02-20T10:00:00.000Z',
        );
        final assigned = uploaded.copyWith(messageId: 'msg-final-001');
        expect(assigned.messageId, 'msg-final-001');
        expect(assigned.id, 'blob-upload');
      });
    });

    group('equality', () {
      test('two attachments with same id are equal', () {
        final other = MediaAttachment(
          id: 'blob-uuid-001',
          messageId: 'different-msg',
          mime: 'video/mp4',
          size: 999,
          mediaType: 'video',
          downloadStatus: 'pending',
          createdAt: '2026-01-01T00:00:00.000Z',
        );

        expect(testAttachment, equals(other));
        expect(testAttachment.hashCode, equals(other.hashCode));
      });

      test('two attachments with different ids are not equal', () {
        final other = testAttachment.copyWith(id: 'blob-uuid-002');
        expect(testAttachment, isNot(equals(other)));
      });
    });

    test('toString contains id and mime', () {
      final str = testAttachment.toString();
      expect(str, contains('blob-uui'));
      expect(str, contains('image/jpeg'));
      expect(str, contains('245000'));
    });

    // --- Waveform field tests ---

    group('waveform', () {
      const waveformData = [0.1, 0.5, 0.8, 0.3, 0.6];

      const withWaveform = MediaAttachment(
        id: 'blob-wf-001',
        messageId: 'msg-wf-001',
        mime: 'audio/mp4',
        size: 12000,
        mediaType: 'audio',
        durationMs: 3000,
        downloadStatus: 'done',
        createdAt: '2026-02-26T10:00:00.000Z',
        waveform: waveformData,
      );

      test('waveform defaults to null', () {
        expect(testAttachment.waveform, isNull);
      });

      test('waveform field stores data', () {
        expect(withWaveform.waveform, waveformData);
      });

      group('toJson / fromJson', () {
        test('toJson includes waveform when non-null', () {
          final json = withWaveform.toJson();
          expect(json['waveform'], waveformData);
        });

        test('toJson omits waveform when null', () {
          final json = testAttachment.toJson();
          expect(json.containsKey('waveform'), isFalse);
        });

        test('fromJson parses waveform list', () {
          final json = {
            'id': 'blob-wf-parse',
            'mime': 'audio/mp4',
            'size': 5000,
            'waveform': [0.2, 0.4, 0.6],
          };
          final restored = MediaAttachment.fromJson(json);
          expect(restored.waveform, [0.2, 0.4, 0.6]);
        });

        test('fromJson defaults waveform to null when absent', () {
          final json = {
            'id': 'blob-no-wf',
            'mime': 'audio/mp4',
            'size': 1000,
          };
          final restored = MediaAttachment.fromJson(json);
          expect(restored.waveform, isNull);
        });

        test('round-trip: toJson then fromJson preserves waveform', () {
          final json = withWaveform.toJson();
          final restored = MediaAttachment.fromJson(json);
          expect(restored.waveform, waveformData);
        });
      });

      group('toMap / fromMap', () {
        test('toMap serializes waveform as JSON string', () {
          final map = withWaveform.toMap();
          expect(map['waveform'], '[0.1,0.5,0.8,0.3,0.6]');
        });

        test('toMap stores null waveform as null', () {
          final map = testAttachment.toMap();
          expect(map['waveform'], isNull);
        });

        test('fromMap deserializes waveform from JSON string', () {
          final map = withWaveform.toMap();
          final restored = MediaAttachment.fromMap(map);
          expect(restored.waveform, hasLength(5));
          expect(restored.waveform![0], closeTo(0.1, 0.001));
          expect(restored.waveform![2], closeTo(0.8, 0.001));
        });

        test('fromMap returns null waveform when column is null', () {
          final map = testAttachment.toMap();
          final restored = MediaAttachment.fromMap(map);
          expect(restored.waveform, isNull);
        });
      });

      group('copyWith', () {
        test('can set waveform on attachment that had none', () {
          final updated = testAttachment.copyWith(
            waveform: [0.1, 0.2, 0.3],
          );
          expect(updated.waveform, [0.1, 0.2, 0.3]);
        });

        test('can clear waveform to null', () {
          final cleared = withWaveform.copyWith(clearWaveform: true);
          expect(cleared.waveform, isNull);
        });

        test('preserves waveform when not specified in copyWith', () {
          final copy = withWaveform.copyWith(downloadStatus: 'pending');
          expect(copy.waveform, waveformData);
          expect(copy.downloadStatus, 'pending');
        });
      });
    });
  });
}
