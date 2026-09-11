import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/features/call/application/voice_call_feature_flags.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
