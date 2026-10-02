import 'dart:io';
import 'dart:typed_data';

/// Reads the finalized movie clock from an AAC/M4A file without decoding it.
/// Recording wall time can include scheduling stalls and encoder shutdown;
/// the container clock describes the audio that is actually present.
Future<int?> readM4aDurationMs(String path) async {
  RandomAccessFile? file;
  try {
    file = await File(path).open();
    final length = await file.length();
    return await _scan(file, 0, length, 0);
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } finally {
    await file?.close();
  }
}

Future<int?> _scan(RandomAccessFile file, int start, int end, int depth) async {
  var offset = start;
  var atoms = 0;
  while (offset + 8 <= end && atoms++ < 4096) {
    await file.setPosition(offset);
    final bytes = await file.read(8);
    if (bytes.length != 8) return null;
    var size = ByteData.sublistView(bytes).getUint32(0);
    final type = String.fromCharCodes(bytes.sublist(4));
    var headerSize = 8;
    if (size == 1) {
      final extended = await file.read(8);
      if (extended.length != 8) return null;
      size = ByteData.sublistView(extended).getUint64(0);
      headerSize = 16;
    } else if (size == 0) {
      size = end - offset;
    }
    if (size < headerSize || size > end - offset) return null;
    if (type == 'moov' && depth == 0) {
      final duration = await _scan(file, offset + headerSize, offset + size, 1);
      if (duration != null) return duration;
    } else if (type == 'mvhd' && depth == 1) {
      final payload = await file.read((size - headerSize).clamp(0, 32));
      if (payload.length < 20) return null;
      final data = ByteData.sublistView(payload);
      final version = payload[0];
      final int timeScale;
      final int ticks;
      if (version == 0) {
        timeScale = data.getUint32(12);
        ticks = data.getUint32(16);
        if (ticks == 0xffffffff) return null;
      } else if (version == 1 && payload.length >= 32) {
        timeScale = data.getUint32(20);
        ticks = data.getUint64(24);
        if (ticks == 0xffffffffffffffff) return null;
      } else {
        return null;
      }
      if (timeScale == 0 || ticks <= 0) return null;
      final milliseconds = (ticks * 1000 / timeScale).round();
      return milliseconds > 0 ? milliseconds : null;
    }
    offset += size;
  }
  return null;
}
