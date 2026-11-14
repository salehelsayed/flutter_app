// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

/// Account-owned canonical sticker metadata and portable user ordering.
///
/// Always runs regardless of the authoring/UI feature flag. File admission and
/// imports still validate actual bytes and physical ownership; these constraints
/// keep persisted values parseable and paths lexically within Documents/stickers.
/// Positions stay non-unique so a transaction can swap them through temporary ties.
Future<void> runCustomStickersMigration(Database database) async {
  await database.execute('''
    CREATE TABLE IF NOT EXISTS custom_stickers (
      id TEXT PRIMARY KEY NOT NULL
        CHECK (typeof(id) = 'text' AND length(id) > 0),
      content_sha256 TEXT NOT NULL UNIQUE
        CHECK (
          typeof(content_sha256) = 'text'
          AND length(content_sha256) = 64
          AND content_sha256 NOT GLOB '*[^0-9a-f]*'
        ),
      relative_path TEXT NOT NULL
        CHECK (
          typeof(relative_path) = 'text'
          AND substr(relative_path, 1, 9) = 'stickers/'
          AND length(relative_path) > 9
          AND substr(relative_path, -1) <> '/'
          AND instr(relative_path, char(0)) = 0
          AND instr(relative_path, char(92)) = 0
          AND instr(relative_path, '//') = 0
          AND instr('/' || relative_path || '/', '/./') = 0
          AND instr('/' || relative_path || '/', '/../') = 0
        ),
      mime TEXT NOT NULL CHECK (mime = 'image/webp'),
      size_bytes INTEGER NOT NULL
        CHECK (
          typeof(size_bytes) = 'integer'
          AND size_bytes BETWEEN 1 AND 524288
        ),
      width INTEGER NOT NULL
        CHECK (typeof(width) = 'integer' AND width BETWEEN 1 AND 512),
      height INTEGER NOT NULL
        CHECK (typeof(height) = 'integer' AND height BETWEEN 1 AND 512),
      frame_count INTEGER NOT NULL
        CHECK (
          typeof(frame_count) = 'integer'
          AND frame_count BETWEEN 1 AND 24
        ),
      duration_ms INTEGER NOT NULL
        CHECK (
          typeof(duration_ms) = 'integer'
          AND duration_ms BETWEEN 0 AND 2000
        ),
      created_at_ms INTEGER NOT NULL
        CHECK (typeof(created_at_ms) = 'integer'),
      last_used_at_ms INTEGER NOT NULL
        CHECK (typeof(last_used_at_ms) = 'integer'),
      position INTEGER NOT NULL
        CHECK (typeof(position) = 'integer' AND position >= 0),
      CHECK (
        (frame_count = 1 AND duration_ms = 0 AND size_bytes <= 262144)
        OR (frame_count > 1 AND duration_ms > 0)
      )
    )
  ''');
}
