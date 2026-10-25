import 'dart:typed_data';

import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:image/image.dart' as image;

/// Decodable PNG at the actual image send cap minus one byte. Padding after
/// IEND keeps the image tiny to decode while transferring/hash-checking every
/// byte at the production boundary. No reduced test-only cap is substituted.
Uint8List nearLimitPngBytes() {
  final encoded = image.encodePng(image.Image(width: 2, height: 2));
  final bytes = Uint8List(kGroupMediaImageLimitBytes - 1);
  bytes.setRange(0, encoded.length, encoded);
  bytes[bytes.length - 1] = 0x5a;
  return bytes;
}
