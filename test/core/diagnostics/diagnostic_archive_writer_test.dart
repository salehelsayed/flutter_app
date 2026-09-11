import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_app/core/diagnostics/diagnostic_archive_writer.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> event(String id, [String trace = 'original']) => {
  'eventId': id,
  'traceId': trace,
  'values': <String, Object?>{'count': 1},
};

Map<String, Object?>? validateTestEvent(Object? raw) {
  if (raw is! Map ||
      raw['eventId'] is! String ||
      raw.keys.any((key) => !['eventId', 'traceId', 'values'].contains(key))) {
    return null;
  }
  return Map<String, Object?>.from(raw);
}

void main() {
  group('DiagnosticJsonByteCounter', () {
    final encoder = JsonUtf8Encoder();

    void expectExact(DiagnosticJsonByteCounter counter, Object? value) {
      final actual = counter.count(value);
      expect(actual, encoder.convert(value).length);
      expect(actual, utf8.encode(jsonEncode(value)).length);
    }

    test('matches all single UTF-16 units and JSON control escapes', () {
      final counter = DiagnosticJsonByteCounter();
      for (var unit = 0; unit <= 0xffff; unit++) {
        expectExact(counter, String.fromCharCode(unit));
      }
      expectExact(counter, String.fromCharCodes(List.generate(32, (i) => i)));
      expectExact(counter, 'مرحبا 日本語 👋 "\\/\u2028\u2029');
    });

    test(
      'matches paired and unpaired surrogates in mixed strings and keys',
      () {
        final counter = DiagnosticJsonByteCounter();
        for (final units in [
          [0xd800],
          [0xdc00],
          [0xd800, 0xdc00],
          [0xdbff, 0xdfff],
          [0xd800, 0xd800, 0xdc00],
          [0xd800, 0xdc00, 0xdc00],
          [0xdc00, 0xd800],
          [0xd800, 0x22, 0xdc00, 0x5c],
        ]) {
          final text = String.fromCharCodes(units);
          expectExact(counter, {text: 'prefix${text}suffix'});
        }
        final random = Random(4096);
        for (var sample = 0; sample < 1000; sample++) {
          final text = String.fromCharCodes(
            List.generate(random.nextInt(80), (_) => random.nextInt(0x10000)),
          );
          expectExact(counter, {
            text: [text, '\n$text'],
          });
        }
      },
    );

    test('matches decimal widths including signed 64-bit boundaries', () {
      final counter = DiagnosticJsonByteCounter();
      for (final value in [
        0,
        -9223372036854775808,
        -9223372036854775807,
        9223372036854775807,
        9007199254740991,
        9007199254740992,
        9007199254740993,
      ]) {
        expectExact(counter, value);
      }
      var power = 1;
      for (var exponent = 0; exponent <= 18; exponent++) {
        for (final value in [power - 1, power, power + 1]) {
          expectExact(counter, value);
          expectExact(counter, -value);
        }
        if (exponent < 18) power *= 10;
      }
    });

    test('matches finite doubles including negative zero and exponents', () {
      final counter = DiagnosticJsonByteCounter();
      for (final value in [
        0.0,
        -0.0,
        1.0,
        -1.25,
        double.minPositive,
        -double.minPositive,
        double.maxFinite,
        -double.maxFinite,
        1e-7,
        1e-6,
        1e20,
        1e21,
        3.141592653589793,
      ]) {
        expectExact(counter, value);
      }
    });

    test('recounts mutable nested values and permits shared containers', () {
      final counter = DiagnosticJsonByteCounter(cachedStrings: ['eventId']);
      final shared = <Object?>[null, true, false, 9];
      final values = <String, Object?>{'shared': shared};
      final row = <String, Object?>{
        'eventId': 'a',
        'values': values,
        'alias': shared,
        'empty': <Object?>[],
        'map': <String, Object?>{},
      };
      expectExact(counter, row);
      shared.add({'escaped\nkey': 'longer 👋'});
      values['shared'] = {'other': -10000};
      row['eventId'] = 'replacement identifier';
      expectExact(counter, row);
      shared.clear();
      values.clear();
      expectExact(counter, row);
    });

    test('caches only supplied strings despite changing runtime IDs', () {
      final supplied = ['eventId', 'values', 'مرحبا', 'eventId', '\n'];
      final counter = DiagnosticJsonByteCounter(cachedStrings: supplied);
      expect(counter.cachedStringCount, 4);
      supplied.add('added-later');
      for (var index = 0; index < 1000; index++) {
        expectExact(counter, {
          'eventId': 'runtime-id-$index',
          'values': {'مرحبا': '\n', 'runtime-key-$index': index},
        });
      }
      expect(counter.cachedStringCount, 4);
    });

    test(
      'rejects unsupported JSON and cycles without poisoning later counts',
      () {
        final counter = DiagnosticJsonByteCounter();
        final list = <Object?>[];
        list.add(list);
        final map = <String, Object?>{};
        map['self'] = map;
        for (final cyclic in [list, map]) {
          expect(() => counter.count(cyclic), throwsA(isA<JsonCyclicError>()));
        }
        for (final unsupported in [
          double.nan,
          double.infinity,
          double.negativeInfinity,
          Object(),
          {1: 'invalid key'},
          [Object()],
        ]) {
          expect(
            () => counter.count(unsupported),
            throwsA(isA<JsonUnsupportedObjectError>()),
          );
        }
        expectExact(counter, {
          'healthy': [true, 123],
        });
      },
    );
  });

  late Directory directory;
  late File file;
  late DiagnosticArchiveWriter writer;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('diagnostic-archive-');
    file = File('${directory.path}/state.json');
    writer = DiagnosticArchiveWriter(file.path);
  });
  tearDown(() async {
    await writer.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<Map<String, dynamic>> read() async =>
      jsonDecode(await file.readAsString()) as Map<String, dynamic>;

  test(
    'metadata deltas preserve fields and update ordered collection entries',
    () async {
      writer.stageEvent(event('a'));
      await writer.persist({
        'enabled': true,
        'epoch': 1,
        'bindings': {'update': 1, 'keep': 2, 'remove': 3, 'readd': 4},
        'uploaded': ['a', 'b', 'c'],
      });
      await writer.persist(
        {'epoch': 2, 'note': '日本語 👋'},
        metadataDelta: const DiagnosticArchiveMetadataDelta(
          mapRemovals: {
            'bindings': ['remove', 'readd'],
          },
          mapUpserts: {
            'bindings': {
              'update': {'trace': 'مرحبا', 'time': 12},
              'readd': null,
              'new\\key': [true, false, 'line\n'],
            },
          },
          setRemovals: {
            'uploaded': ['b', 'c'],
          },
          setAdditions: {
            'uploaded': ['c', 'd', 'a', 'd'],
          },
        ),
      );
      final expected = {
        'enabled': true,
        'epoch': 2,
        'bindings': {
          'update': {'trace': 'مرحبا', 'time': 12},
          'keep': 2,
          'readd': null,
          'new\\key': [true, false, 'line\n'],
        },
        'uploaded': ['a', 'c', 'd'],
        'note': '日本語 👋',
        'events': [event('a')],
      };
      expect(await file.readAsBytes(), utf8.encode(jsonEncode(expected)));
      await writer.persist(
        {},
        metadataDelta: const DiagnosticArchiveMetadataDelta(),
      );
      expect(await file.readAsBytes(), utf8.encode(jsonEncode(expected)));
    },
  );

  test(
    'metadata deltas synchronously snapshot every input and preserve FIFO',
    () async {
      final first = writer.persist({
        'bindings': {'remove': 0},
        'uploaded': ['old'],
      });
      final binding = <String, Object?>{'trace': 'original', 'time': 1};
      final upserts = <String, Map<String, Object?>>{
        'bindings': {'a': binding},
      };
      final removals = <String, List<String>>{
        'bindings': ['remove'],
      };
      final additions = <String, List<String>>{
        'uploaded': ['a'],
      };
      final setRemovals = <String, List<String>>{
        'uploaded': ['old'],
      };
      final metadata = <String, Object?>{
        'status': ['accepted'],
      };
      final second = writer.persist(
        metadata,
        metadataDelta: DiagnosticArchiveMetadataDelta(
          mapUpserts: upserts,
          mapRemovals: removals,
          setAdditions: additions,
          setRemovals: setRemovals,
        ),
      );
      binding['trace'] = 'mutated';
      upserts['bindings']!.clear();
      removals['bindings']!.clear();
      additions['uploaded']!.add('mutated');
      setRemovals['uploaded']!.clear();
      (metadata['status'] as List).add('mutated');
      final third = writer.persist(
        {'generation': 3},
        metadataDelta: const DiagnosticArchiveMetadataDelta(
          mapUpserts: {
            'bindings': {'b': 2},
          },
          setAdditions: {
            'uploaded': ['b'],
          },
        ),
      );
      await Future.wait([first, second, third]);
      expect(await read(), {
        'bindings': {
          'a': {'trace': 'original', 'time': 1},
          'b': 2,
        },
        'uploaded': ['a', 'b'],
        'status': ['accepted'],
        'generation': 3,
        'events': [],
      });
    },
  );

  test(
    'full metadata reset beats queued deltas and preserves arbitrary lists',
    () async {
      writer.stageEvent(event('old'));
      final first = writer.persist({
        'bindings': {'old': 1},
        'uploaded': ['old'],
        'obsolete': true,
      });
      final patch = writer.persist(
        {'epoch': 1},
        metadataDelta: const DiagnosticArchiveMetadataDelta(
          mapUpserts: {
            'bindings': {'pending': 2},
          },
          setAdditions: {
            'uploaded': ['pending'],
          },
        ),
      );
      writer.clearEvents();
      final replacement = <String, Object?>{
        'enabled': false,
        'duplicates': ['same', 'same'],
        'mixed': [
          1,
          null,
          {
            'list': [true, false],
          },
        ],
      };
      final reset = writer.persist(replacement);
      await Future.wait([first, patch, reset]);
      await writer.persist(
        {},
        metadataDelta: const DiagnosticArchiveMetadataDelta(),
      );
      expect(
        await file.readAsBytes(),
        utf8.encode(jsonEncode({...replacement, 'events': []})),
      );
    },
  );

  test(
    'metadata deltas and rows survive failed writes then full reset',
    () async {
      writer.stageEvent(event('a'));
      await writer.persist({
        'bindings': {'a': 1},
        'uploaded': ['a'],
        'epoch': 1,
      });
      await directory.delete(recursive: true);
      writer.stageEvent(event('b'));
      await expectLater(
        writer.persist(
          {'epoch': 2},
          metadataDelta: const DiagnosticArchiveMetadataDelta(
            mapUpserts: {
              'bindings': {'b': 2},
            },
            mapRemovals: {
              'bindings': ['a'],
            },
            setAdditions: {
              'uploaded': ['b'],
            },
            setRemovals: {
              'uploaded': ['a'],
            },
          ),
        ),
        throwsStateError,
      );
      await directory.create();
      await writer.persist({
        'epoch': 3,
      }, metadataDelta: const DiagnosticArchiveMetadataDelta());
      expect(await read(), {
        'bindings': {'b': 2},
        'uploaded': ['b'],
        'epoch': 3,
        'events': [event('a'), event('b')],
      });
      await directory.delete(recursive: true);
      await expectLater(
        writer.persist(
          {},
          metadataDelta: const DiagnosticArchiveMetadataDelta(
            setAdditions: {
              'uploaded': ['failed'],
            },
          ),
        ),
        throwsStateError,
      );
      writer.clearEvents();
      await directory.create();
      await writer.persist({'enabled': false});
      await writer.persist(
        {},
        metadataDelta: const DiagnosticArchiveMetadataDelta(),
      );
      expect(await read(), {'enabled': false, 'events': []});
    },
  );

  test(
    'first full metadata is authoritative over unvalidated saved metadata',
    () async {
      await file.writeAsString(
        jsonEncode({
          'private': 'discard',
          'bindings': {'raw': 'discard'},
          'uploaded': ['raw'],
          'events': [],
        }),
      );
      await writer.persist({'safe': true});
      await writer.persist(
        {},
        metadataDelta: const DiagnosticArchiveMetadataDelta(
          mapUpserts: {
            'bindings': {'new': 1},
          },
          setAdditions: {
            'uploaded': ['new'],
          },
        ),
      );
      expect(await read(), {
        'safe': true,
        'bindings': {'new': 1},
        'uploaded': ['new'],
        'events': [],
      });
    },
  );

  test(
    'metadata delta rejects event history and conflicting collection types',
    () async {
      writer.stageEvent(event('pending'));
      for (final delta in [
        const DiagnosticArchiveMetadataDelta(
          mapUpserts: {
            'events': {'bad': 1},
          },
        ),
        const DiagnosticArchiveMetadataDelta(
          setRemovals: {
            'events': ['bad'],
          },
        ),
        const DiagnosticArchiveMetadataDelta(
          mapRemovals: {
            'field': ['a'],
          },
          setAdditions: {
            'field': ['b'],
          },
        ),
      ]) {
        await expectLater(
          writer.persist({}, metadataDelta: delta),
          throwsArgumentError,
        );
      }
      await writer.persist({'safe': true});
      expect(await read(), {
        'safe': true,
        'events': [event('pending')],
      });
    },
  );

  test(
    'metadata set delta rejects non-unique and non-string saved lists',
    () async {
      for (final invalid in <Object?>[
        ['a', 'a'],
        ['a', 1],
        'a',
      ]) {
        await writer.dispose();
        writer = DiagnosticArchiveWriter(file.path);
        await writer.persist({'uploaded': invalid});
        final before = await file.readAsBytes();
        await expectLater(
          writer.persist(
            {},
            metadataDelta: const DiagnosticArchiveMetadataDelta(
              setAdditions: {
                'uploaded': ['b'],
              },
            ),
          ),
          throwsStateError,
        );
        expect(await file.readAsBytes(), before);
        expect(await File('${file.path}.tmp').exists(), isFalse);
      }
    },
  );

  test(
    'metadata map delta rejects scalar fields without changing durable state',
    () async {
      await writer.persist({'bindings': 'invalid'});
      final before = await file.readAsBytes();
      await expectLater(
        writer.persist(
          {},
          metadataDelta: const DiagnosticArchiveMetadataDelta(
            mapUpserts: {
              'bindings': {'a': 1},
            },
          ),
        ),
        throwsStateError,
      );
      expect(await file.readAsBytes(), before);
    },
  );

  test(
    'metadata delta cannot initialize itself from unvalidated disk fields',
    () async {
      await file.writeAsString('{"uploaded":["private"],"events":[]}');
      final before = await file.readAsBytes();
      await expectLater(
        writer.persist(
          {},
          metadataDelta: const DiagnosticArchiveMetadataDelta(
            setAdditions: {
              'uploaded': ['new'],
            },
          ),
        ),
        throwsStateError,
      );
      expect(await file.readAsBytes(), before);
    },
  );

  test(
    'cached fragments preserve exact JSON bytes and multilingual escaping',
    () async {
      const text = 'مرحبا 👋 日本語 "quoted" \\ slash\nline\t\u0000';
      final first = {
        ...event('a'),
        'values': {
          'text': text,
          'list': [true, null, 3],
        },
      };
      final second = event('b');
      writer.stageEvent(first);
      writer.stageEvent(second);
      await writer.persist({'label': text});
      expect(
        await file.readAsBytes(),
        utf8.encode(
          jsonEncode({
            'label': text,
            'events': [first, second],
          }),
        ),
      );
      await writer.persist({});
      expect(
        await file.readAsBytes(),
        utf8.encode(
          jsonEncode({
            'events': [first, second],
          }),
        ),
      );
      writer.removeEvent('a');
      final replacement = {
        ...event('b'),
        'values': {'text': '$text$text'},
      };
      writer.stageEvent(replacement);
      await writer.persist({'version': 2});
      expect(
        await file.readAsBytes(),
        utf8.encode(
          jsonEncode({
            'version': 2,
            'events': [replacement],
          }),
        ),
      );
    },
  );

  test(
    'streamed archives preserve exact bytes across buffer boundaries',
    () async {
      for (final length in [65535, 65536, 65537, 131072]) {
        final row = <String, Object?>{...event('boundary'), 'payload': ''};
        final archive = <String, Object?>{
          'events': [row],
        };
        final overhead = utf8.encode(jsonEncode(archive)).length;
        row['payload'] = 'a' * (length - overhead);
        writer.clearEvents();
        writer.stageEvent(row);
        await writer.persist({});
        final expected = utf8.encode(jsonEncode(archive));
        expect(expected.length, length);
        expect(await file.readAsBytes(), expected);
      }
    },
  );

  test(
    'streams many small rows and fragments larger than the reusable buffer',
    () async {
      final rows = List.generate(2000, (index) => event('small-$index'));
      rows.insert(1000, {
        ...event('large'),
        'values': {'text': 'مرحبا 👋 "\\\n' * 10000},
      });
      final metadata = <String, Object?>{'label': '日本語\n' * 10000};
      for (final row in rows) {
        writer.stageEvent(row);
      }
      await writer.persist(metadata);
      expect(
        await file.readAsBytes(),
        utf8.encode(jsonEncode({...metadata, 'events': rows})),
      );
      writer.clearEvents();
      await writer.persist({});
      expect(await file.readAsString(), '{"events":[]}');
    },
  );

  test(
    'failed rename cleans streamed temporary output and retains rows for retry',
    () async {
      writer.stageEvent(event('old'));
      await writer.persist({'version': 1});
      await file.delete();
      final obstruction = await Directory(file.path).create();
      final replacement = <String, Object?>{
        ...event('old', 'rebound'),
        'values': {'text': '👋' * 50000},
      };
      writer.stageEvent(replacement);
      await expectLater(writer.persist({'version': 2}), throwsStateError);
      expect(await obstruction.exists(), isTrue);
      expect(await File('${file.path}.tmp').exists(), isFalse);
      await obstruction.delete();
      await writer.persist({'version': 3});
      expect(
        await file.readAsBytes(),
        utf8.encode(
          jsonEncode({
            'version': 3,
            'events': [replacement],
          }),
        ),
      );
      expect(await File('${file.path}.tmp').exists(), isFalse);
    },
  );

  test(
    'retry preserves changed cached bytes and removal without resending rows',
    () async {
      writer.stageEvent({
        ...event('a'),
        'values': {'text': 'large القديمة 👋'},
      });
      writer.stageEvent(event('removed'));
      await writer.persist({'version': 1});
      await directory.delete(recursive: true);
      final replacement = event('a', 'new');
      writer.stageEvent(replacement);
      writer.removeEvent('removed');
      await expectLater(writer.persist({'version': 2}), throwsStateError);
      await directory.create();
      await writer.persist({'version': 3});
      expect(
        await file.readAsBytes(),
        utf8.encode(
          jsonEncode({
            'version': 3,
            'events': [replacement],
          }),
        ),
      );
    },
  );

  test('storage teardown cannot recreate the diagnostic directory', () async {
    writer.stageEvent(event('a'));
    await writer.persist({'version': 1});
    await directory.delete(recursive: true);
    writer.stageEvent(event('b'));
    await expectLater(writer.persist({'version': 2}), throwsStateError);
    expect(await directory.exists(), isFalse);
    await writer.dispose();
  });

  test(
    'an existing metadata-only archive starts with no retained events',
    () async {
      await file.writeAsString(jsonEncode({'version': 1, 'enabled': true}));
      writer.initializeRetainedEvents([]);
      writer.stageEvent(event('new'));
      await writer.persist({'version': 1, 'enabled': true});
      expect(await read(), {
        'version': 1,
        'enabled': true,
        'events': [event('new')],
      });
    },
  );

  test(
    'later commit recovers merged rows after an ordinary sink failure',
    () async {
      writer.stageEvent(event('durable'));
      await writer.persist({'version': 1});
      await directory.delete(recursive: true);
      writer.stageEvent(event('failed-write'));
      await expectLater(writer.persist({'version': 2}), throwsStateError);
      await directory.create();
      writer.stageEvent(event('new'));
      await writer.persist({'version': 3});
      expect(await read(), {
        'version': 3,
        'events': [event('durable'), event('failed-write'), event('new')],
      });
    },
  );

  test(
    'clear after a failed write erases both durable and pending rows',
    () async {
      writer.stageEvent(event('durable'));
      await writer.persist({'enabled': true});
      await directory.delete(recursive: true);
      writer.stageEvent(event('failed-write'));
      await expectLater(writer.persist({'enabled': true}), throwsStateError);
      writer.clearEvents();
      await directory.create();
      await writer.persist({'enabled': false});
      expect(await read(), {'enabled': false, 'events': []});
    },
  );

  test(
    'invalid startup archive fails pending writes and closes the worker',
    () async {
      await file.writeAsString('invalid JSON');
      writer.stageEvent(event('a'));
      final failed = writer.persist({'version': 1});
      final queued = writer.persist({'version': 2});
      await expectLater(failed, throwsStateError);
      await expectLater(queued, throwsStateError);
      await writer.dispose();
      expect(await file.readAsString(), 'invalid JSON');
    },
  );

  test('persists detached rows and metadata atomically', () async {
    final row = event('a');
    final bindings = <String, Object?>{'a': 'original'};
    writer.stageEvent(row);
    (row['values'] as Map)['count'] = 99;
    row['traceId'] = 'mutated';
    final pending = writer.persist({'version': 1, 'bindings': bindings});
    bindings['a'] = 'mutated';
    await pending;
    final state = await read();
    expect(state['bindings'], {'a': 'original'});
    expect(state['events'], [event('a')]);
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });

  test(
    'loads only retained rows privately and upserts changed traces',
    () async {
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'events': [event('a'), event('expired')],
        }),
      );
      writer.initializeRetainedEvents(['a']);
      writer.stageEvent(event('new'));
      await writer.persist({'version': 2});
      expect((await read())['events'], [event('a'), event('new')]);
      writer.stageEvent(event('a', 'rebound'));
      await writer.persist({'version': 3});
      expect((await read())['events'], [event('a', 'rebound'), event('new')]);
    },
  );

  test(
    'metadata-only commits preserve worker history and replace metadata',
    () async {
      writer.stageEvent(event('a'));
      await writer.persist({'version': 1, 'obsolete': true});
      await writer.persist({'version': 2});
      expect(await read(), {
        'version': 2,
        'events': [event('a')],
      });
    },
  );

  test(
    'invalid duplicate cannot replace first valid retained row on restart',
    () async {
      await writer.dispose();
      writer = DiagnosticArchiveWriter(
        file.path,
        validateEvent: validateTestEvent,
      );
      await file.writeAsString(
        jsonEncode({
          'events': [
            {...event('a'), 'privateField': 'must not survive'},
            event('a', 'first-safe'),
            event('a', 'later-safe'),
            {...event('a'), 'privateField': 'must not replace safe row'},
          ],
        }),
      );
      writer.initializeRetainedEvents(['a']);
      await writer.persist({'version': 1});
      expect((await read())['events'], [event('a', 'first-safe')]);
    },
  );

  test(
    'eviction before first send does not retain removed staged rows',
    () async {
      for (var index = 0; index < 10000; index++) {
        writer.stageEvent(event('$index'));
        writer.removeEvent('$index');
      }
      writer.stageEvent(event('retained'));
      await writer.persist({'version': 1});
      expect((await read())['events'], [event('retained')]);
    },
  );

  test(
    'removal during initial in-flight write wins on the next commit',
    () async {
      writer.stageEvent(event('a'));
      final first = writer.persist({'generation': 1});
      writer.removeEvent('a');
      final second = writer.persist({'generation': 2});
      await Future.wait([first, second]);
      expect(await read(), {'generation': 2, 'events': []});
    },
  );

  test(
    'clear after an in-flight commit cannot resurrect old consent data',
    () async {
      writer.stageEvent(event('old'));
      final old = writer.persist({'enabled': true, 'consentEpoch': 1});
      writer.clearEvents();
      final cleared = writer.persist({'enabled': false, 'consentEpoch': 2});
      await Future.wait([old, cleared]);
      expect(await read(), {'enabled': false, 'consentEpoch': 2, 'events': []});
      writer.stageEvent(event('new'));
      await writer.persist({'enabled': true, 'consentEpoch': 3});
      expect((await read())['events'], [event('new')]);
    },
  );

  test(
    'clear beats already persisted history and new unsent upserts',
    () async {
      writer.stageEvent(event('old'));
      await writer.persist({'version': 1});
      writer.stageEvent(event('unsent'));
      writer.clearEvents();
      writer.stageEvent(event('fresh'));
      await writer.persist({'version': 2});
      expect((await read())['events'], [event('fresh')]);
    },
  );

  test(
    'sink failure completes queued futures and leaves old archive intact',
    () async {
      writer.stageEvent(event('durable'));
      await writer.persist({'version': 1});
      // A directory at the atomic staging path makes writing fail deterministically.
      await Directory('${file.path}.tmp').create();
      writer.stageEvent(event('failed'));
      final failed = writer.persist({'version': 2});
      final queued = writer.persist({'version': 3});
      await expectLater(failed, throwsStateError);
      await expectLater(queued, throwsStateError);
      await writer.dispose();
      expect(await read(), {
        'version': 1,
        'events': [event('durable')],
      });
    },
  );

  test(
    'clear can replace an unreadable old archive without loading it',
    () async {
      await file.writeAsString('invalid JSON');
      writer.clearEvents();
      await writer.persist({'enabled': false});
      expect(await read(), {'enabled': false, 'events': []});
    },
  );

  test(
    'dispose drains accepted writes and rejects subsequent persistence',
    () async {
      writer.stageEvent(event('a'));
      final pending = writer.persist({'version': 1});
      final disposing = writer.dispose();
      await Future.wait([pending, disposing]);
      expect((await read())['events'], [event('a')]);
      await expectLater(writer.persist({'version': 2}), throwsStateError);
      await writer.dispose();
    },
  );

  test(
    'full event histories cannot accidentally enter the metadata channel',
    () async {
      await expectLater(
        writer.persist({
          'events': [event('a')],
        }),
        throwsArgumentError,
      );
      writer.stageEvent(event('b'));
      await writer.persist({'version': 1});
      expect((await read())['events'], [event('b')]);
    },
  );
}
