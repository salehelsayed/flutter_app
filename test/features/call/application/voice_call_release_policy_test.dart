import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/features/call/application/voice_call_feature_flags.dart';
import 'package:flutter_test/flutter_test.dart';

const _testerVideoAuthorization =
    'Owner 2026-11-13: "I give the go to switch video on for testers". '
    'Store video activation remains a separate owner gate.';

/// Release define keys that would turn video calling on.
List<String> releaseDefinesEnablingVideo(Map<Object?, Object?> defines) => [
  for (final key in defines.keys)
    if (key == 'VIDEO_CALL_V2_ENABLED') '$key',
];

void main() {
  test('release offers privacy mode without forcing it for normal calls', () {
    final defines =
        jsonDecode(
              File(
                'tool/build/voice_call_release_defines.json',
              ).readAsStringSync(),
            )
            as Map;
    expect(defines['VOICE_CALL_ALWAYS_RELAY_ENABLED'], 'true');
    expect(defines['VOICE_CALL_FORCE_RELAY_ENABLED'], 'false');
    expect(defines['VOICE_CALL_STUN_URLS'], 'stun:mknoun.xyz:3478');
    // The same operator-owned endpoint is configured by the relay deployment.
    expect(
      File('docker-ws/deploy_relay_v1100.sh').readAsStringSync(),
      contains('turn:mknoun.xyz:3478?transport=udp'),
    );
  });

  test(
    'compile-time flags and approved STUN follow the selected build defines',
    () {
      final flags = productionVoiceCallFeatureFlags();
      expect(
        flags['voice_call_always_relay_enabled'],
        const bool.fromEnvironment('VOICE_CALL_ALWAYS_RELAY_ENABLED'),
      );
      expect(
        flags['voice_call_force_relay_enabled'],
        const bool.fromEnvironment('VOICE_CALL_FORCE_RELAY_ENABLED'),
      );
      const stun = String.fromEnvironment('VOICE_CALL_STUN_URLS');
      final servers = productionVoiceCallStunServers();
      expect(servers.expand((s) => s.urls), stun.isEmpty ? isEmpty : [stun]);
      for (final server in servers) {
        expect(server.containsTurnUrl, false);
        expect(server.credential, isNull);
        expect(server.expiresAt.isAfter(DateTime.now()), true);
      }
    },
  );

  // VC-GATE-GUARD: the 11-13 owner go is tester-only. Store builds keep the
  // existing release defines; tester builds must explicitly select their file.
  test('VC-GATE-GUARD a defines file that sets the video gate is caught', () {
    final fixture = <String, String>{
      'VOICE_CALL_CAPABILITY_V1': 'true',
      'VIDEO_CALL_V2_ENABLED': 'true',
    };
    expect(releaseDefinesEnablingVideo(fixture), ['VIDEO_CALL_V2_ENABLED']);
  });

  test('VC-GATE-GUARD store release stays off after the tester-only go', () {
    final defines =
        jsonDecode(
              File(
                'tool/build/voice_call_release_defines.json',
              ).readAsStringSync(),
            )
            as Map;
    expect(
      releaseDefinesEnablingVideo(defines),
      isEmpty,
      reason: _testerVideoAuthorization,
    );
    expect(defaultVoiceCallFeatureFlags()['video_call_v2_enabled'], isFalse);
    expect(
      productionVoiceCallFeatureFlags()['video_call_v2_enabled'],
      const bool.fromEnvironment('VIDEO_CALL_V2_ENABLED'),
    );
  });

  test('VC-GATE-GUARD tester defines enable only video under the 11-13 go', () {
    final testerFile = File('tool/build/voice_call_tester_defines.json');
    expect(testerFile.existsSync(), isTrue, reason: _testerVideoAuthorization);
    final testerDefines = jsonDecode(testerFile.readAsStringSync()) as Map;
    final releaseDefines =
        jsonDecode(
              File(
                'tool/build/voice_call_release_defines.json',
              ).readAsStringSync(),
            )
            as Map;
    expect(
      testerDefines['VIDEO_CALL_V2_ENABLED'],
      'true',
      reason: _testerVideoAuthorization,
    );
    expect(releaseDefinesEnablingVideo(testerDefines), [
      'VIDEO_CALL_V2_ENABLED',
    ]);
    expect(
      Map<Object?, Object?>.of(testerDefines)..remove('VIDEO_CALL_V2_ENABLED'),
      releaseDefines,
      reason:
          'Tester video preserves every existing voice, native, privacy '
          'and STUN define.',
    );
  });
}
