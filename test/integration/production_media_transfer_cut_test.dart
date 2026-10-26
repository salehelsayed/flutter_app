import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/cut_production_media_transfer.dart';

void main() {
  for (final scenario in [
    'held',
    'not-held',
    'wrong-attachment',
    'process-still-alive',
  ]) {
    test(
      'media transfer cut $scenario preserves causal proof and owned cleanup',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'media-cut-host-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        var released = false;
        final state = <String, Object?>{
          'schema': 'mknoon.media-transfer-checkpoint.v1',
          'gateId': 'fixture-run',
          'direction': 'download',
          'bound': true,
          'attachmentSha256': sha256
              .convert(
                utf8.encode(
                  scenario == 'wrong-attachment' ? 'other' : 'attachment',
                ),
              )
              .toString(),
          'held': scenario != 'not-held',
          'released': false,
          'timedOut': false,
          'bytesTransferred': 32,
          'totalBytes': 4096,
        };
        server.listen((request) async {
          expect(request.uri.path, '/owned-run/transfer-checkpoint');
          if (request.method == 'POST') {
            final body = jsonDecode(await utf8.decodeStream(request));
            expect(body, {'op': 'release', 'gateId': 'fixture-run'});
            released = true;
            state['released'] = true;
            state['held'] = false;
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(state));
          await request.response.close();
        });
        final commands = <List<String>>[];
        var pidReads = 0;
        Future<ProcessResult> process(String name, List<String> args) async {
          commands.add([name, ...args]);
          if (args.contains('pidof')) {
            pidReads++;
            final alive = pidReads == 1 || scenario == 'process-still-alive';
            return ProcessResult(1, alive ? 0 : 1, alive ? '1234\n' : '', '');
          }
          return ProcessResult(1, 0, '', '');
        }

        final output = File('${directory.path}/cut.json');
        final operation = cutProductionMediaTransfer(
          fixtureProbe: Uri.parse('http://127.0.0.1:${server.port}/owned-run'),
          gateId: 'fixture-run',
          attachmentId: 'attachment',
          deviceId: 'emulator-5554',
          packageName: 'com.mknoon.sims',
          output: output,
          wait: const Duration(seconds: 1),
          process: process,
        );
        if (scenario == 'held') {
          final proof = await operation;
          expect(proof['status'], 'PASS');
          expect(proof['verifiedProcessAbsent'], true);
          expect((proof['gateBeforeKill'] as Map)['held'], true);
          expect((proof['gateAfterKill'] as Map)['held'], true);
        } else {
          await expectLater(operation, throwsStateError);
          final proof = jsonDecode(await output.readAsString()) as Map;
          expect(proof['status'], 'FAIL');
          expect(proof['failure'], isNotEmpty);
        }
        expect(released, true);
        if (scenario == 'not-held' || scenario == 'wrong-attachment') {
          expect(
            commands,
            isEmpty,
            reason: 'no causal checkpoint means no device operation',
          );
        } else {
          expect(commands, [
            ['adb', '-s', 'emulator-5554', 'shell', 'pidof', 'com.mknoon.sims'],
            [
              'adb',
              '-s',
              'emulator-5554',
              'shell',
              'am',
              'force-stop',
              'com.mknoon.sims',
            ],
            ['adb', '-s', 'emulator-5554', 'shell', 'pidof', 'com.mknoon.sims'],
          ]);
        }
      },
    );
  }
  test(
    'media cut rejects a public relay before any network or device action',
    () async {
      var called = false;
      await expectLater(
        cutProductionMediaTransfer(
          fixtureProbe: Uri.parse('http://203.0.113.1:8080/probe'),
          gateId: 'run',
          attachmentId: 'attachment',
          deviceId: 'emulator-5554',
          packageName: 'com.mknoon.sims',
          output: File('unused.json'),
          process: (_, _) async {
            called = true;
            return ProcessResult(1, 0, '', '');
          },
        ),
        throwsFormatException,
      );
      expect(called, false);
    },
  );
}
