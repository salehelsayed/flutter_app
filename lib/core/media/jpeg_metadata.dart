import 'dart:typed_data';

/// Removes JPEG metadata without decoding or re-encoding the primary image.
///
/// Only ICC_PROFILE APP2 segments and a newly built, orientation-only EXIF IFD
/// survive from APPn. ICC colour data is intentionally retained unchanged.
/// Returns null for malformed containers or unsupported JPEG coding/colour
/// variants, so the caller can use its existing native metadata-removing encoder.
Uint8List? stripJpegMetadata(Uint8List source) {
  if (source.length < 4 || source[0] != 0xff || source[1] != 0xd8) {
    return null;
  }
  final retained = <Uint8List>[];
  final frameComponents = <int>{};
  final iccSequences = <int>{};
  int? iccCount;
  int? orientation;
  var offset = 2;
  var inScan = false;
  var sawScan = false;
  var sawQuantization = false;
  var sawHuffman = false;

  while (offset < source.length) {
    if (inScan) {
      final start = offset;
      // Stuffed FF00 and restart markers belong to the original coded scan.
      // Every other marker ends this entropy segment, including APPn between
      // progressive scans. Do not blindly copy everything after the first SOS.
      while (offset < source.length) {
        if (source[offset] != 0xff) {
          offset++;
          continue;
        }
        var codeAt = offset + 1;
        while (codeAt < source.length && source[codeAt] == 0xff) {
          codeAt++;
        }
        if (codeAt == source.length) return null;
        final code = source[codeAt];
        if (code == 0 || (code >= 0xd0 && code <= 0xd7)) {
          offset = codeAt + 1;
          continue;
        }
        break;
      }
      if (offset == start || offset == source.length) return null;
      retained.add(Uint8List.sublistView(source, start, offset));
      inScan = false;
    }

    final markerAt = offset;
    if (source[offset++] != 0xff) return null;
    while (offset < source.length && source[offset] == 0xff) {
      offset++;
    }
    if (offset == source.length) return null;
    final marker = source[offset++];
    if (marker == 0xd9) {
      if (!sawScan || frameComponents.isEmpty) return null;
      if (iccCount != null && iccSequences.length != iccCount) return null;
      retained.add(Uint8List.sublistView(source, markerAt, offset));
      final output = BytesBuilder(copy: false)..add(const [0xff, 0xd8]);
      if (orientation != null && orientation != 1) {
        output.add(_orientationSegment(orientation));
      }
      for (final bytes in retained) {
        output.add(bytes);
      }
      // The primary EOI is the boundary: no old trailers or auxiliary images.
      return output.takeBytes();
    }

    if (offset + 2 > source.length) return null;
    final length = (source[offset] << 8) | source[offset + 1];
    if (length < 2 || length > source.length - offset) return null;
    final payloadAt = offset + 2;
    final end = offset + length;
    var keep = true;

    if (marker >= 0xe0 && marker <= 0xef) {
      keep = false;
      if (marker == 0xe1 &&
          !sawScan &&
          _startsWith(source, payloadAt, end, _exifSignature)) {
        final value = _readOrientation(
          Uint8List.sublistView(source, payloadAt + 6, end),
        );
        if (value == null || (orientation != null && value != orientation)) {
          return null;
        }
        orientation = value;
      } else if (marker == 0xe2 &&
          _startsWith(source, payloadAt, end, _iccSignature)) {
        if (end - payloadAt < 14) return null;
        final sequence = source[payloadAt + 12];
        final count = source[payloadAt + 13];
        if (sequence == 0 ||
            sequence > count ||
            (iccCount != null && count != iccCount) ||
            !iccSequences.add(sequence)) {
          return null;
        }
        iccCount = count;
        keep = true;
      } else if (marker == 0xee &&
          _startsWith(source, payloadAt, end, _adobeSignature)) {
        // Adobe's APP14 transform can determine RGB/YCbCr interpretation.
        // Removing it is not a safe metadata-only operation for that variant.
        return null;
      }
    } else if (marker == 0xfe) {
      keep = false;
    } else if (marker == 0xc0 || marker == 0xc2) {
      if (frameComponents.isNotEmpty || end - payloadAt < 6) return null;
      final count = source[payloadAt + 5];
      if (source[payloadAt] != 8 ||
          (count != 1 && count != 3) ||
          end - payloadAt != 6 + 3 * count ||
          (source[payloadAt + 1] == 0 && source[payloadAt + 2] == 0) ||
          (source[payloadAt + 3] == 0 && source[payloadAt + 4] == 0)) {
        return null;
      }
      for (var i = 0; i < count; i++) {
        if (!frameComponents.add(source[payloadAt + 6 + 3 * i])) return null;
      }
    } else if (marker == 0xda) {
      if (frameComponents.isEmpty ||
          !sawQuantization ||
          !sawHuffman ||
          end - payloadAt < 4) {
        return null;
      }
      final count = source[payloadAt];
      if (count == 0 ||
          count > frameComponents.length ||
          end - payloadAt != 4 + 2 * count) {
        return null;
      }
      final components = <int>{};
      for (var i = 0; i < count; i++) {
        final id = source[payloadAt + 1 + 2 * i];
        if (!frameComponents.contains(id) || !components.add(id)) return null;
      }
      sawScan = true;
      inScan = true;
    } else if (marker == 0xdb || marker == 0xc4) {
      if (length == 2) return null;
      if (marker == 0xdb) sawQuantization = true;
      if (marker == 0xc4) sawHuffman = true;
    } else if (marker == 0xdd) {
      if (length != 4) return null;
    } else {
      // Includes standalone/repeated SOI, arithmetic/lossless/CMYK, DNL and
      // JPEG extension variants. No opaque marker payload is copied through.
      return null;
    }
    if (keep) retained.add(Uint8List.sublistView(source, markerAt, end));
    offset = end;
  }
  return null;
}

const _exifSignature = [0x45, 0x78, 0x69, 0x66, 0, 0];
const _iccSignature = [
  0x49,
  0x43,
  0x43,
  0x5f,
  0x50,
  0x52,
  0x4f,
  0x46,
  0x49,
  0x4c,
  0x45,
  0,
];
const _adobeSignature = [0x41, 0x64, 0x6f, 0x62, 0x65];

bool _startsWith(Uint8List bytes, int start, int end, List<int> prefix) {
  if (end - start < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[start + i] != prefix[i]) return false;
  }
  return true;
}

// Read only the display orientation in bounded IFD0 entries. Never follow GPS,
// MakerNote, sub-IFD or thumbnail pointers into the source metadata.
int? _readOrientation(Uint8List tiff) {
  if (tiff.length < 8) return null;
  final Endian endian;
  if (tiff[0] == 0x49 && tiff[1] == 0x49) {
    endian = Endian.little;
  } else if (tiff[0] == 0x4d && tiff[1] == 0x4d) {
    endian = Endian.big;
  } else {
    return null;
  }
  final data = ByteData.sublistView(tiff);
  if (data.getUint16(2, endian) != 42) return null;
  final ifd = data.getUint32(4, endian);
  if (ifd < 8 || ifd > tiff.length - 2) return null;
  final count = data.getUint16(ifd, endian);
  if (ifd + 2 + count * 12 + 4 > tiff.length) return null;
  int? orientation;
  for (var i = 0; i < count; i++) {
    final entry = ifd + 2 + i * 12;
    if (data.getUint16(entry, endian) != 0x0112) continue;
    if (data.getUint16(entry + 2, endian) != 3 ||
        data.getUint32(entry + 4, endian) != 1) {
      return null;
    }
    final value = data.getUint16(entry + 8, endian);
    if (value < 1 ||
        value > 8 ||
        (orientation != null && orientation != value)) {
      return null;
    }
    orientation = value;
  }
  return orientation ?? 1;
}

Uint8List _orientationSegment(int orientation) => Uint8List.fromList([
  0xff, 0xe1, 0, 34,
  ..._exifSignature,
  0x4d, 0x4d, 0, 42, 0, 0, 0, 8,
  0, 1, // One IFD0 entry.
  1, 0x12, 0, 3, 0, 0, 0, 1, 0, orientation, 0, 0,
  0, 0, 0, 0, // No next IFD or embedded thumbnail.
]);
