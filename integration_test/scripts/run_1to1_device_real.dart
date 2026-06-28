#!/usr/bin/env dart
//
// FDC-16 / CV-07 — 1:1 device-real scenario orchestrator.
//
// Enumerates the Fast-Direct-Connection 1:1 DEVICE-PROOF campaign (FDC-16
// Closure Gate Register, "device-proof" rows). It is the 1:1 sibling of
// integration_test/scripts/run_group_multi_party_device_real.dart and is wired
// into scripts/check_reliability_simulation_discovery.sh (classify_path →
// expand_1to1_device_real) so EVERY scenario below is discoverable and gets a
// stable `/sims 1to1 --only N` slot.
//
// `--list-scenarios` prints one bare scenario id per line (the contract the
// discovery expander parses). This path runs under bare `dart` with no Flutter
// binding. The dispatch path is DEFERRED-NOT-WAIVED: these rows close on a real
// 2-device same-WiFi rig + real relay + APNs, which is out of scope here; the
// orchestrator prints the per-scenario device recipe and the blocking CV/TC and
// exits 0 without pretending to have proven anything (FDC-16 Scope Guard: do not
// flip a flag or issue a verdict ahead of its device proof).
//
// Usage:
//   dart run integration_test/scripts/run_1to1_device_real.dart \
//     --scenario all|<id> -d <iosUdid,androidSerial> [--list-scenarios]
//
// Scenario → CV row → TC → proof mode (the `--only N` slot is the 1-based index
// of the scenario id in `--scenario all --list-scenarios` output):
//
//   fdc11_lan_direct_d1                       CV-08 ⭐KEYSTONE  manual-two-phone
//   fdc12_dcutr_relay_to_direct_upgrade       CV-11  TC-12-12   sim (+ proof test)
//   fdc12_dcutr_symmetric_cgnat_negative      CV-12  TC-12-13   sim (+ proof test)
//   fdc07_cold_circuit_reserve_dispatch       CV-23  TC-07-05   sim
//   fdc07_early_mdns_lan_opportunistic        CV-24  TC-07-06   sim
//   fdc04_warm_open_local                      CV-25  TC-04-15   sim
//   fdc04_network_change_rewarm                CV-26  —          device
//   fdc04_cold_notif_tap_noop                  CV-27  TC-04-05   device
//   fdc09_ios_visible_wake                     CV-15  TC-09-20   device + relay
//   fdc09_presence_set_background_pre_suspend  CV-16  TC-09-21   device + relay
//   fdc09_wake_gate_noncontact_blocked         CV-20  TC-09-23   device + relay (gated CV-19)
//   fdc08_presence_get_smoke                   CV-21  LR1        live-relay
//   fdc13_transport_upgraded_badge             CV-30  —          device
//   fdc14_badge_online_direct                  CV-32  —          device
//   fdc15_lan_media_d1                         CV-34  —          manual-two-phone
//   fdc06_pause_flush_open_send                CV-29  T8         device (gated plan 170)

import 'dart:io';

class _Scenario {
  const _Scenario(this.id, this.cv, this.tc, this.mode, this.summary);

  final String id;
  final String cv;
  final String tc;
  final String mode;
  final String summary;
}

const List<_Scenario> _scenarios = <_Scenario>[
  _Scenario('fdc11_lan_direct_d1', 'CV-08', 'FDC-11 D1', 'manual-two-phone',
      'two phones same WiFi take a libp2p LAN-direct leg, both OS (KEYSTONE)'),
  _Scenario('fdc12_dcutr_relay_to_direct_upgrade', 'CV-11', 'TC-12-12', 'sim',
      'relay conn upgrades to direct via DCUtR; badge flips to direct'),
  _Scenario('fdc12_dcutr_symmetric_cgnat_negative', 'CV-12', 'TC-12-13', 'sim',
      'symmetric-CGNAT pair stays on relay; no false direct badge'),
  _Scenario('fdc07_cold_circuit_reserve_dispatch', 'CV-23', 'TC-07-05', 'sim',
      'cold T_circuit <= 3s with reserve_dispatch observation'),
  _Scenario('fdc07_early_mdns_lan_opportunistic', 'CV-24', 'TC-07-06', 'sim',
      'early-hoisted mDNS yields an opportunistic LAN leg before drain'),
  _Scenario('fdc04_warm_open_local', 'CV-25', 'TC-04-15', 'sim',
      'eager warmPeer keeps the send on the local leg, not the warmed conn'),
  _Scenario('fdc04_network_change_rewarm', 'CV-26', '-', 'device',
      'a network change re-fires warmPeer for the active peer'),
  _Scenario('fdc04_cold_notif_tap_noop', 'CV-27', 'TC-04-05', 'device',
      'cold notification-tap warm is a PS-3 no-op (no duplicate dial)'),
  _Scenario('fdc09_ios_visible_wake', 'CV-15', 'TC-09-20', 'device+relay',
      'iOS push wakes visibly (not silent-throttled) for a 1:1 send'),
  _Scenario('fdc09_presence_set_background_pre_suspend', 'CV-16', 'TC-09-21',
      'device+relay', 'presence_set{background} lands before suspend'),
  _Scenario('fdc09_wake_gate_noncontact_blocked', 'CV-20', 'TC-09-23',
      'device+relay', 'a non-contact cannot wake (wake-gate e2e; gated CV-19)'),
  _Scenario('fdc08_presence_get_smoke', 'CV-21', 'LR1', 'live-relay',
      'presence_get smoke against a live relay'),
  _Scenario('fdc13_transport_upgraded_badge', 'CV-30', '-', 'device',
      'a real-wire transport:upgraded event drives the badge'),
  _Scenario('fdc14_badge_online_direct', 'CV-32', '-', 'device',
      'the presence badge reaches onlineDirect on a real LAN pair'),
  _Scenario('fdc15_lan_media_d1', 'CV-34', '-', 'manual-two-phone',
      '1:1 media flows over /mknoon/media-lan/1.0.0 on a real LAN pair'),
  _Scenario('fdc06_pause_flush_open_send', 'CV-29', 'T8', 'device',
      'an open-send-lock survives pause-flush and delivers (gated plan 170)'),
];

bool _parseListScenarios(List<String> args) => args.contains('--list-scenarios');

String _parseScenario(List<String> args) {
  var scenario = 'all';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--scenario' && i + 1 < args.length) {
      scenario = args[i + 1].trim().toLowerCase();
      i++;
    } else if (args[i].startsWith('--scenario=')) {
      scenario = args[i].substring('--scenario='.length).trim().toLowerCase();
    }
  }
  return scenario;
}

List<String> _parseDevices(List<String> args) {
  final devices = <String>[];
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--device' || args[i] == '-d') && i + 1 < args.length) {
      devices.addAll(args[i + 1]
          .split(',')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty));
      i++;
    }
  }
  return devices;
}

List<_Scenario> _scenariosToRun(String scenario) {
  if (scenario == 'all') return _scenarios;
  final match = _scenarios.where((s) => s.id == scenario).toList();
  if (match.isEmpty) {
    throw ArgumentError(
      'Unknown --scenario "$scenario". Expected one of: '
      '${_scenarios.map((s) => s.id).join(', ')}, or all',
    );
  }
  return match;
}

Future<void> main(List<String> args) async {
  final scenario = _parseScenario(args);
  final listScenarios = _parseListScenarios(args);
  final devices = _parseDevices(args);
  final usage =
      'Usage: dart run integration_test/scripts/run_1to1_device_real.dart '
      '--scenario ${_scenarios.map((s) => s.id).join('|')}|all '
      '-d <iosUdid,androidSerial> [--list-scenarios]';

  if (listScenarios) {
    try {
      for (final s in _scenariosToRun(scenario)) {
        stdout.writeln(s.id);
      }
    } on ArgumentError catch (error) {
      stderr.writeln(error.message);
      stderr.writeln(usage);
      exit(64);
    }
    return;
  }

  List<_Scenario> toRun;
  try {
    toRun = _scenariosToRun(scenario);
  } on ArgumentError catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(usage);
    exit(64);
  }

  stdout.writeln('FDC-16 / CV-07 — 1:1 device-real campaign');
  stdout.writeln(
      'Devices: ${devices.isEmpty ? '(none supplied — pass -d <ios,android>)' : devices.join(', ')}');
  stdout.writeln('');
  for (final s in toRun) {
    stdout.writeln('• ${s.id}  [${s.cv} / ${s.tc} / ${s.mode}]');
    stdout.writeln('    ${s.summary}');
  }
  stdout.writeln('');
  stdout.writeln(
      'DEFERRED-NOT-WAIVED: these rows close on a real 2-device same-WiFi rig + '
      'real relay + APNs (FDC-16 P4.1). This orchestrator enumerates and slots '
      'the campaign; it does NOT run it here. Provision the rig, then drive each '
      'scenario per its CV row (`/sims 1to1 --only N` for the sim rows; manual '
      'two-phone for the keystone/media rows).');
}
