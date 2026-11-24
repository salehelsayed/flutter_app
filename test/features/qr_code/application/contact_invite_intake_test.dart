import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_app/features/qr_code/application/contact_invite_intake.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('mknoon/contact_invites');
const _codec = StandardMethodCodec();
const _limit = Duration(seconds: 2);
const _prefix = 'https://invite.mknoon.xyz/i/v1#';

final _coldUrl = _testInvite('Mira');
final _warmUrl = _testInvite('Noor');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    _messenger.setMockMethodCallHandler(_channel, null);
    _channel.setMethodCallHandler(null);
  });

  test('cold intake keeps the exact raw URL with no listener', () async {
    final calls = <MethodCall>[];
    _messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return calls.length == 1 ? _link(_coldUrl) : null;
    });
    final intake = ContactInviteIntake(channel: _channel);
    addTearDown(intake.dispose);

    await intake.start().timeout(_limit);

    expect(calls.map((call) => call.method), ['takePending']);
    expect(calls.single.arguments, isNull);
    expect(
      intake.takePending(),
      isA<OpenContactInvite>().having(
        (entry) => entry.rawUrl,
        'rawUrl',
        _coldUrl,
      ),
    );
    expect(intake.takePending(), isNull);
  });

  test('listens before the first take and coalesces wakes during it', () async {
    final firstRead = Completer<void>();
    final coldReply = Completer<Object?>();
    late Future<void> wakeReplies;
    addTearDown(() {
      if (!coldReply.isCompleted) coldReply.complete(null);
    });
    var reads = 0;
    var inFlight = 0;
    _messenger.setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'takePending');
      reads++;
      inFlight++;
      try {
        expect(inFlight, 1, reason: 'each native take must finish first');
        if (reads == 1) {
          // Dispatch these before returning the first pending native response.
          // The receiver must already be listening when it starts that read.
          wakeReplies = Future.wait<void>([
            _nativeCall(const MethodCall('inviteAvailable')),
            _nativeCall(const MethodCall('inviteAvailable')),
          ]).then<void>((_) {});
          firstRead.complete();
          return await coldReply.future.timeout(_limit);
        }
        return reads == 2 ? _link(_warmUrl) : null;
      } finally {
        inFlight--;
      }
    });
    final intake = ContactInviteIntake(channel: _channel);
    addTearDown(intake.dispose);
    final opened = <String>[];
    final warmDelivered = Completer<void>();
    intake.addListener(() {
      final entry = intake.takePending();
      if (entry is OpenContactInvite) {
        opened.add(entry.rawUrl);
        if (entry.rawUrl == _warmUrl && !warmDelivered.isCompleted) {
          warmDelivered.complete();
        }
      }
    });

    final started = intake.start();
    await Future.any([firstRead.future, started]).timeout(_limit);
    expect(firstRead.isCompleted, isTrue, reason: 'start must take cold input');
    await wakeReplies.timeout(_limit);
    expect(reads, 1);
    expect(opened, isEmpty);

    coldReply.complete(_link(_coldUrl));
    await started.timeout(_limit);
    await warmDelivered.future.timeout(_limit);

    expect(reads, 2);
    expect(opened, [_coldUrl, _warmUrl]);
    expect(intake.takePending(), isNull);
  });

  test('the native paste hint is a separate entry without a URL', () async {
    _messenger.setMockMethodCallHandler(_channel, (_) async {
      return <String, Object?>{'kind': 'paste'};
    });
    final intake = ContactInviteIntake(channel: _channel);
    addTearDown(intake.dispose);

    await intake.start().timeout(_limit);

    expect(intake.takePending(), isA<PasteContactInvite>());
    expect(intake.takePending(), isNull);
  });

  test('rejects invalid native responses and wakes carrying data', () async {
    final invalidResponses = <String, Object?>{
      'non-map': _coldUrl,
      'unknown kind': {'kind': 'open', 'url': _coldUrl},
      'missing URL': {'kind': 'link'},
      'wrong URL type': {'kind': 'link', 'url': 7},
      'extra link key': {'kind': 'link', 'url': _coldUrl, 'other': true},
      'paste with URL': {'kind': 'paste', 'url': _coldUrl},
      'oversized URL': _link('${_prefix}${List.filled(5000, 'A').join()}'),
    };
    for (final response in invalidResponses.entries) {
      var reads = 0;
      _messenger.setMockMethodCallHandler(_channel, (_) async {
        reads++;
        return reads == 1 ? response.value : _link(_warmUrl);
      });
      final intake = ContactInviteIntake(channel: _channel);
      var notifications = 0;
      intake.addListener(() => notifications++);
      try {
        await intake.start().timeout(_limit);
        expect(reads, 1, reason: response.key);
        expect(intake.takePending(), isNull, reason: response.key);
        expect(notifications, 0, reason: response.key);

        await _nativeCall(const MethodCall('unknown'));
        await _nativeCall(MethodCall('inviteAvailable', _link(_coldUrl)));
        await pumpEventQueue(times: 2).timeout(_limit);
        expect(reads, 1, reason: 'only a payload-free wake is accepted');
        expect(intake.takePending(), isNull);
        expect(notifications, 0);
      } finally {
        intake.dispose();
      }
    }
  });

  test('an unavailable native channel leaves intake empty', () async {
    final intake = ContactInviteIntake(channel: _channel);
    addTearDown(intake.dispose);
    var notifications = 0;
    intake.addListener(() => notifications++);

    await intake.start().timeout(_limit);

    expect(intake.takePending(), isNull);
    expect(notifications, 0);
  });

  test('disposal drops a held reply and subsequent wakes', () async {
    final firstRead = Completer<void>();
    final coldReply = Completer<Object?>();
    var reads = 0;
    _messenger.setMockMethodCallHandler(_channel, (_) async {
      reads++;
      if (reads == 1) {
        firstRead.complete();
        return await coldReply.future.timeout(_limit);
      }
      return _link(_warmUrl);
    });
    final intake = ContactInviteIntake(channel: _channel);
    var disposed = false;
    addTearDown(() {
      if (!disposed) intake.dispose();
      if (!coldReply.isCompleted) coldReply.complete(null);
    });
    var notifications = 0;
    intake.addListener(() => notifications++);

    final started = intake.start();
    await Future.any([firstRead.future, started]).timeout(_limit);
    expect(firstRead.isCompleted, isTrue, reason: 'start must take cold input');
    intake.dispose();
    disposed = true;
    coldReply.complete(_link(_coldUrl));
    await started.timeout(_limit);
    await _nativeCall(const MethodCall('inviteAvailable'));
    await pumpEventQueue(times: 2).timeout(_limit);

    expect(reads, 1);
    expect(notifications, 0);
  });
}

Map<String, Object?> _link(String url) => {'kind': 'link', 'url': url};

Future<void> _nativeCall(MethodCall call) async {
  await _messenger
      .handlePlatformMessage(_channel.name, _codec.encodeMethodCall(call), null)
      .timeout(_limit);
}

String _testInvite(String name) {
  final payload = jsonEncode({
    'ns': '12D3KooWFixture',
    'pk': 'fixture-public-key',
    'rv': '/dns4/relay.example/tcp/443',
    'sig': 'fixture-signature',
    'ts': '2026-11-24T00:00:00.000Z',
    'un': name,
  });
  final fragment = base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
  return '$_prefix$fragment';
}
