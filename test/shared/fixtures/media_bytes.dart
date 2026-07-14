import 'package:crypto/crypto.dart';

/// Minimal byte prefixes for media fixtures that exercise MIME validation.
const validJpegFixtureBytes = <int>[0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10];
const validPngFixtureBytes = <int>[
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
];
const validGifFixtureBytes = <int>[0x47, 0x49, 0x46, 0x38, 0x39, 0x61];
const validMp4FixtureBytes = <int>[
  0x00,
  0x00,
  0x00,
  0x0c,
  0x66,
  0x74,
  0x79,
  0x70,
  0x69,
  0x73,
  0x6f,
  0x6d,
];

List<int> validMediaFixtureBytesForMime(String mime) => switch (mime) {
  'image/jpeg' => validJpegFixtureBytes,
  'image/png' => validPngFixtureBytes,
  'image/gif' => validGifFixtureBytes,
  'video/mp4' || 'audio/mp4' => validMp4FixtureBytes,
  _ => throw ArgumentError.value(mime, 'mime', 'unsupported media fixture'),
};

List<int> validMediaFixtureBytesForPath(String path) {
  final lower = path.toLowerCase();
  final normalized = lower.endsWith('.enc')
      ? lower.substring(0, lower.length - '.enc'.length)
      : lower;
  if (normalized.endsWith('.jpg') || normalized.endsWith('.jpeg')) {
    return validJpegFixtureBytes;
  }
  if (normalized.endsWith('.png')) return validPngFixtureBytes;
  if (normalized.endsWith('.gif')) return validGifFixtureBytes;
  if (normalized.endsWith('.mp4') || normalized.endsWith('.m4a')) {
    return validMp4FixtureBytes;
  }
  throw ArgumentError.value(path, 'path', 'unsupported media fixture');
}

String validMediaFixtureHashForMime(String mime) =>
    sha256.convert(validMediaFixtureBytesForMime(mime)).toString();
