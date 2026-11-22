import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

const _maxSide = 512;
const _maxRgbaBytes = _maxSide * _maxSide * 4;
const _riffHeaderBytes = 12;
const _chunkHeaderBytes = 8;
const _minimumAlphaBytes = 2;
const _minimumVp8Bytes = 10;
const _minimumFrameBytes =
    _riffHeaderBytes +
    2 * _chunkHeaderBytes +
    _minimumAlphaBytes +
    _minimumVp8Bytes;
const _extendedHeaderBytes = 18;
const _maxIccBytes = 4096;
const _colorProfileOverhead =
    _extendedHeaderBytes + _chunkHeaderBytes + _maxIccBytes;

// Values from Android NDK bitmap.h and data_space.h.
const _rgba8888 = 1;
const _straightAlpha = 2;
const _sRgb = 142671872;
const _webpLossy = 3;

final class _AndroidBitmapInfo extends Struct {
  @Uint32()
  external int width;

  @Uint32()
  external int height;

  @Uint32()
  external int stride;

  @Int32()
  external int format;

  @Uint32()
  external int flags;
}

typedef _WriteNative = Bool Function(Pointer<Void>, Pointer<Uint8>, Size);
typedef _CompressNative =
    Int32 Function(
      Pointer<_AndroidBitmapInfo>,
      Int32,
      Pointer<Uint8>,
      Int32,
      Int32,
      Pointer<Void>,
      Pointer<NativeFunction<_WriteNative>>,
    );
typedef _CompressDart =
    int Function(
      Pointer<_AndroidBitmapInfo>,
      int,
      Pointer<Uint8>,
      int,
      int,
      Pointer<Void>,
      Pointer<NativeFunction<_WriteNative>>,
    );

typedef AndroidStickerWebPResult = ({Uint8List? bytes, bool exceedsLimit});

/// Encodes straight RGBA circle frames with lossy RGB and lossless alpha.
/// The caller owns a separate native staging buffer per worker and keeps it
/// alive until that worker exits.
final class AndroidStickerWebPEncoder {
  AndroidStickerWebPEncoder._(this._compress, int stagingAddress)
    : _pixels = Pointer<Uint8>.fromAddress(stagingAddress),
      _info = Pointer<_AndroidBitmapInfo>.fromAddress(
        stagingAddress + _maxRgbaBytes,
      );

  final _CompressDart _compress;
  final Pointer<Uint8> _pixels;
  final Pointer<_AndroidBitmapInfo> _info;

  static int get stagingByteLength =>
      _maxRgbaBytes + sizeOf<_AndroidBitmapInfo>();

  static AndroidStickerWebPEncoder? tryCreate(int stagingAddress) {
    if (!Platform.isAndroid || stagingAddress == 0 || stagingAddress % 4 != 0) {
      return null;
    }
    try {
      final compress = DynamicLibrary.open('libjnigraphics.so')
          .lookupFunction<_CompressNative, _CompressDart>(
            'AndroidBitmap_compress',
          );
      return AndroidStickerWebPEncoder._(compress, stagingAddress);
    } on ArgumentError {
      // AndroidBitmap_compress is available from API 30.
      return null;
    }
  }

  /// Successful bytes contain a RIFF prefix followed by the ALPH and VP8
  /// chunks for ANMF assembly. Standalone images also need a VP8X chunk.
  /// Null lets the Dart encoder handle a failed or unsupported native result.
  AndroidStickerWebPResult? encode(
    Uint8List rgba,
    int side, {
    required int byteLimit,
    required int quality,
  }) {
    if (side < 1 ||
        side > _maxSide ||
        rgba.length != side * side * 4 ||
        byteLimit < 0 ||
        byteLimit > _maxRgbaBytes ||
        quality < 0 ||
        quality > 100) {
      return null;
    }
    _pixels.asTypedList(rgba.length).setAll(0, rgba);
    _info.ref
      ..width = side
      ..height = side
      ..stride = side * 4
      ..format = _rgba8888
      ..flags = _straightAlpha;

    final prefixLimit = byteLimit < _minimumFrameBytes
        ? _minimumFrameBytes
        : byteLimit;
    final output = _NativeOutput(prefixLimit + _colorProfileOverhead);
    _activeOutput = output;
    final int status;
    try {
      status = _compress(
        _info,
        _sRgb,
        _pixels,
        _webpLossy,
        quality,
        nullptr,
        _writeCallback,
      );
    } finally {
      _activeOutput = null;
    }
    if (status != 0 && !output.truncated) return null;
    return _canonicalFrame(
      output.bytes.takeBytes(),
      side: side,
      byteLimit: byteLimit,
      truncated: output.truncated,
    );
  }
}

final class _NativeOutput {
  _NativeOutput(this.limit);

  final int limit;
  final bytes = BytesBuilder();
  bool truncated = false;
}

// Android invokes the writer synchronously on the current isolate's thread.
// Native chunk storage is valid only for the callback, so the builder copies it.
_NativeOutput? _activeOutput;
final _writeCallback = Pointer.fromFunction<_WriteNative>(_writeNative, false);

bool _writeNative(Pointer<Void> _, Pointer<Uint8> data, int length) {
  final output = _activeOutput;
  if (output == null || length < 0) return false;
  if (length == 0) return true;
  if (data == nullptr) return false;
  final available = output.limit - output.bytes.length;
  final count = length < available ? length : available;
  if (count > 0) output.bytes.add(data.asTypedList(count));
  if (length <= available) return true;
  output.truncated = true;
  return false;
}

// These tags are read in ASCII (big-endian) order. RIFF lengths are little-endian.
const _riffTag = 0x52494646;
const _webpTag = 0x57454250;
const _extendedTag = 0x56503858; // VP8X
const _colorProfileTag = 0x49434350; // ICCP
const _alphaTag = 0x414c5048; // ALPH
const _lossyTag = 0x56503820; // VP8 plus trailing space

AndroidStickerWebPResult? _canonicalFrame(
  Uint8List encoded, {
  required int side,
  required int byteLimit,
  required bool truncated,
}) {
  if (encoded.length < _extendedHeaderBytes + _minimumFrameBytes) {
    return null;
  }
  final header = ByteData.sublistView(encoded);
  final riffLength = header.getUint32(4, Endian.little) + 8;
  if (header.getUint32(0) != _riffTag ||
      header.getUint32(8) != _webpTag ||
      (truncated
          ? riffLength <= encoded.length
          : riffLength != encoded.length)) {
    return null;
  }

  final flags = header.getUint32(20);
  if (header.getUint32(12) != _extendedTag ||
      header.getUint32(16, Endian.little) != 10 ||
      (flags != 0x10000000 && flags != 0x30000000) ||
      _uint24(header, 24) + 1 != side ||
      _uint24(header, 27) + 1 != side) {
    return null;
  }

  var alphaOffset = _riffHeaderBytes + _extendedHeaderBytes;
  // Skia may include a generated sRGB profile. The supplied pixels use sRGB,
  // which is also the default for our stored WebP animation.
  if (flags == 0x30000000) {
    if (header.getUint32(alphaOffset) != _colorProfileTag) return null;
    final size = header.getUint32(alphaOffset + 4, Endian.little);
    if (size < 128 || size > _maxIccBytes) return null;
    final start = alphaOffset + _chunkHeaderBytes;
    alphaOffset = start + size + (size & 1);
    if (alphaOffset > encoded.length ||
        header.getUint32(start) != size ||
        header.getUint32(start + 36) != 0x61637370 ||
        (size.isOdd && encoded[alphaOffset - 1] != 0)) {
      return null;
    }
  }

  final alphaStart = alphaOffset + _chunkHeaderBytes;
  if (encoded.length < alphaStart + _minimumAlphaBytes ||
      header.getUint32(alphaOffset) != _alphaTag) {
    return null;
  }
  final alphaLength = header.getUint32(alphaOffset + 4, Endian.little);
  final alphaFlags = encoded[alphaStart];
  final alphaCompression = alphaFlags & 3;
  final vp8Offset = alphaStart + alphaLength + (alphaLength & 1);
  if (alphaLength < _minimumAlphaBytes ||
      alphaFlags & 0xf0 != 0 ||
      alphaCompression > 1 ||
      (alphaCompression == 0 && alphaLength != 1 + side * side) ||
      vp8Offset + _chunkHeaderBytes + _minimumVp8Bytes > riffLength) {
    return null;
  }

  final vp8Start = vp8Offset + _chunkHeaderBytes;
  final finalLength = _riffHeaderBytes + riffLength - alphaOffset;
  if (encoded.length < vp8Start + _minimumVp8Bytes) {
    return truncated && finalLength > byteLimit
        ? (bytes: null, exceedsLimit: true)
        : null;
  }
  if (header.getUint32(vp8Offset) != _lossyTag ||
      (alphaLength.isOdd && encoded[vp8Offset - 1] != 0)) {
    return null;
  }
  final vp8Length = header.getUint32(vp8Offset + 4, Endian.little);
  if (vp8Length < _minimumVp8Bytes ||
      vp8Start + vp8Length + (vp8Length & 1) != riffLength ||
      encoded[vp8Start] & 1 != 0 ||
      encoded[vp8Start + 3] != 0x9d ||
      encoded[vp8Start + 4] != 0x01 ||
      encoded[vp8Start + 5] != 0x2a ||
      header.getUint16(vp8Start + 6, Endian.little) != side ||
      header.getUint16(vp8Start + 8, Endian.little) != side ||
      (!truncated && vp8Length.isOdd && encoded.last != 0)) {
    return null;
  }

  if (finalLength > byteLimit) return (bytes: null, exceedsLimit: true);
  if (truncated) return null;
  final frame = Uint8List(finalLength)
    ..setRange(0, _riffHeaderBytes, encoded)
    ..setRange(_riffHeaderBytes, finalLength, encoded, alphaOffset);
  ByteData.sublistView(frame).setUint32(4, finalLength - 8, Endian.little);
  return (bytes: frame, exceedsLimit: false);
}

int _uint24(ByteData data, int offset) =>
    data.getUint8(offset) |
    (data.getUint8(offset + 1) << 8) |
    (data.getUint8(offset + 2) << 16);
