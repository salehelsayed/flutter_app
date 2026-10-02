import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_app/core/media/m4a_duration.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _atom(String type, List<int> body) {
  final bytes = Uint8List(body.length + 8);
  ByteData.sublistView(bytes).setUint32(0, bytes.length);
  bytes.setRange(4, 8, type.codeUnits);
  bytes.setRange(8, bytes.length, body);
  return bytes;
}

void main() {
  late Directory directory;
  setUp(
    () async => directory = await Directory.systemTemp.createTemp('m4a-clock-'),
  );
  tearDown(() async => directory.delete(recursive: true));
  for (final version in [0, 1]) {
    test(
      'reads finalized version $version duration past the audio data',
      () async {
        final header = Uint8List(version == 0 ? 20 : 32);
        header[0] = version;
        final data = ByteData.sublistView(header);
        data.setUint32(version == 0 ? 12 : 20, 44100);
        if (version == 0) {
          data.setUint32(16, 44100 * 36);
        } else {
          data.setUint64(24, 44100 * 36);
        }
        final file = File('${directory.path}/voice.m4a');
        await file.writeAsBytes([
          ..._atom('ftyp', [0, 0, 0, 0]),
          ..._atom('mdat', List.filled(128, 1)),
          ..._atom('moov', _atom('mvhd', header)),
        ]);
        expect(await readM4aDurationMs(file.path), 36000);
      },
    );
  }
  test(
    'rejects truncated atoms, zero clocks and unfinished durations',
    () async {
      final file = File('${directory.path}/voice.m4a');
      final header = Uint8List(20);
      final data = ByteData.sublistView(header);
      for (final payload in [
        [0, 0, 0, 100, ...'moov'.codeUnits],
        _atom('moov', _atom('mvhd', header)),
      ]) {
        await file.writeAsBytes(payload);
        expect(await readM4aDurationMs(file.path), isNull);
      }
      data.setUint32(12, 44100);
      data.setUint32(16, 0xffffffff);
      await file.writeAsBytes(_atom('moov', _atom('mvhd', header)));
      expect(await readM4aDurationMs(file.path), isNull);
    },
  );
}
