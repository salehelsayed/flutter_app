#!/usr/bin/env python3
"""Run the optional audio_peer_connection proof on a pinned Android pair.

Build the existing integration_test/audio_peer_connection_proof_test.dart with
MIXED_POLICY_BROKER=http://127.0.0.1:48765, androidApplicationId set to
com.mknoon.sims.mixedpolicy, and disableGoogleServicesForDisposableProof=true.
Uses the repository's Docker coturn lock, an IPv4 address reachable by both
devices, and an APK. TCP control may be forwarded over USB with --turn-transport.
Uses disposable media only. The default is a local coturn fixture. An explicitly
supplied credential client enables native media tests against its deployed TURN
authority; it must issue fresh validated credentials for each call.
"""

import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import select
import secrets
import subprocess
import threading
import time

PACKAGE = 'com.mknoon.sims.mixedpolicy'
ROOT = Path(__file__).resolve().parents[2]


def forward_rules(device):
    output = subprocess.check_output(
        ['adb', '-s', device, 'forward', '--list'], text=True, timeout=10)
    return {tuple(line.split()) for line in output.splitlines()
            if len(line.split()) == 3}


def cleanup_driver_forwards(devices, output, original_forwards):
    # flutter drive can leave its VM-service forward after it exits. Match the
    # owned driver's actual port and device, preserving all pre-existing rules.
    current = forward_rules(devices[0])
    owned = set()
    for side, device in enumerate(devices):
        log = output / f'device-{side}.log'
        if not log.exists():
            continue
        ports = set(re.findall(
            r'VMServiceFlutterDriver: Connecting to Flutter application at '
            r'http://127\.0\.0\.1:(\d+)/', log.read_text(errors='replace')))
        owned.update(rule for rule in current - original_forwards
                     if rule[0] == device and rule[1] in
                     {f'tcp:{port}' for port in ports})
    for device, local, _ in sorted(owned):
        subprocess.run(['adb', '-s', device, 'forward', '--remove', local],
                       check=True, capture_output=True, timeout=10)
    remaining = owned & forward_rules(devices[0])
    (output / 'forward-cleanup.json').write_text(json.dumps({
        'removed': sorted(owned - remaining),
        'remaining': sorted(remaining),
        'verified': not remaining,
    }, indent=2) + '\n')
    if remaining:
        raise RuntimeError('Owned Flutter driver forward cleanup was not verified')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--physical', required=True)
    parser.add_argument('--emulator', required=True)
    parser.add_argument('--flutter', required=True, type=Path)
    parser.add_argument('--apk', required=True, type=Path)
    parser.add_argument('--turn-ip', required=True)
    parser.add_argument('--turn-transport', choices=['udp', 'tcp', 'tls'], default='tcp')
    parser.add_argument('--credential-command', type=Path,
                        help='Executable JSON-line client: ready receipt, then side 0/1 requests yielding validated TURN bundles')
    parser.add_argument('--fallback-probe', action='store_true',
                        help='Admit an unreachable IPv6 candidate; configure unavailable TURN/UDP alongside TURN/TCP')
    parser.add_argument('--lose-wifi-after-first-media', action='store_true',
                        help='Remove physical Wi-Fi after the first all/all media proof, then restore its original setting')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if args.turn_transport == 'tls' and not args.credential_command:
        parser.error('TLS requires an explicitly supplied deployed credential client')
    if args.credential_command and (args.fallback_probe or args.lose_wifi_after_first_media):
        parser.error('Local fixture faults cannot be combined with deployed credentials')
    if (args.fallback_probe or args.lose_wifi_after_first_media) and args.turn_transport != 'tcp':
        parser.error('fallback and Wi-Fi loss require the USB TURN/TCP path')
    os.umask(0o077)
    args.output.mkdir(parents=True, exist_ok=False)
    devices = [args.physical, args.emulator]
    live = subprocess.check_output(['adb', 'devices'], text=True)
    assert all(f'{d}\tdevice' in live for d in devices)
    assert not args.physical.startswith('emulator-')
    assert args.emulator.startswith('emulator-')
    original_forwards = forward_rules(devices[0])
    sdk = next(line.split('=', 1)[1] for line in
               (ROOT / 'android/local.properties').read_text().splitlines()
               if line.startswith('sdk.dir='))
    aapt = sorted((Path(sdk) / 'build-tools').glob('*/aapt'))[-1]
    badging = subprocess.check_output([str(aapt), 'dump', 'badging', str(args.apk)], text=True)
    if re.search(r"package: name='([^']+)'", badging).group(1) != PACKAGE:
        raise RuntimeError('APK must use the disposable proof package')
    for device in devices:
        installed = subprocess.run(
            ['adb', '-s', device, 'shell', 'pm', 'path', PACKAGE],
            text=True, capture_output=True)
        if installed.stdout.strip():
            raise RuntimeError('Disposable proof package already exists; preserve it')
        reverse = subprocess.check_output(
            ['adb', '-s', device, 'reverse', '--list'], text=True)
        required_ports = {'tcp:48765'}
        if args.turn_transport == 'tcp' and not args.credential_command:
            required_ports.add('tcp:34791')
        if any(required_ports.intersection(line.split()[1:2])
               for line in reverse.splitlines()):
            raise RuntimeError('Proof reverse port already exists; preserve it')

    messages = {}
    condition = threading.Condition()
    credential = secrets.token_hex(24)
    redactions = {credential}
    credential_lock = threading.Lock()
    credential_requests = 0
    credential_failures = []
    next_credential_at = [0.0, 0.0]
    credential_client = None
    turn = None
    container = 'mknoon-mixed-policy-' + secrets.token_hex(6)
    turn_lock = json.loads((ROOT / 'tool/call_audio_oracle/coturn.lock.json').read_text())
    turn_image = turn_lock['image'].split(':')[0] + '@' + turn_lock['digest']
    servers, processes, logs, installed, reversed_devices = [], [], [], [], []
    wifi_before = None
    wifi_changed = False
    if args.lose_wifi_after_first_media:
        wifi_before = subprocess.check_output(
            ['adb', '-s', args.physical, 'shell', 'settings', 'get', 'global', 'wifi_on'],
            text=True).strip()
        if wifi_before != '1':
            raise RuntimeError('Wi-Fi loss proof requires initially enabled physical Wi-Fi')

    def read_credential_response():
        if not select.select([credential_client.stdout], [], [], 15)[0]:
            raise RuntimeError('Credential client response deadline')
        response = json.loads(credential_client.stdout.readline())
        if not isinstance(response, dict):
            raise RuntimeError('Credential client rejected the request')
        return response

    def call_credentials(side):
        nonlocal credential_requests
        with credential_lock:
            # The deployed authority allows six requests per subject/minute.
            # Space distinct test calls before peer creation; never alter a
            # call's setup/recovery deadline or reuse a prior call's bundle.
            time.sleep(max(0, next_credential_at[side] - time.monotonic()))
            credential_client.stdin.write(f'{side}\n')
            credential_client.stdin.flush()
            bundle = read_credential_response()
            next_credential_at[side] = time.monotonic() + 11
            if bundle.get('error'):
                code = bundle.get('code')
                credential_failures.append({
                    'side': side,
                    'code': code if isinstance(code, str) and
                    re.fullmatch(r'[A-Z_]{1,80}', code) else 'REQUEST_REJECTED',
                })
                raise RuntimeError('Credential client rejected the request')
            if (bundle.get('schema') != 'turn_credentials' or bundle.get('version') != 1
                    or not isinstance(bundle.get('expiresAtMs'), int)
                    or bundle['expiresAtMs'] <= time.time() * 1000 + 30000
                    or not all(isinstance(bundle.get(k), str) and bundle[k]
                               for k in ['username', 'password'])):
                raise RuntimeError('Fresh validated TURN credentials are required')
            prefix = 'turns:' if args.turn_transport == 'tls' else 'turn:'
            suffix = '?transport=udp' if args.turn_transport == 'udp' else '?transport=tcp'
            urls = [u for u in bundle.get('urls', []) if isinstance(u, str)
                    and u.startswith(prefix) and u.endswith(suffix) and '@' not in u]
            if not urls:
                raise RuntimeError('Requested transport was not advertised by the credential authority')
            redactions.update([bundle['username'], bundle['password']])
            credential_requests += 1
            return {'turn': urls[0], 'username': bundle['username'],
                    'credential': bundle['password'], 'expiresAtMs': bundle['expiresAtMs']}

    def handler(side):
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *unused):
                pass

            def respond(self, value, status=200):
                body = json.dumps(value).encode()
                self.send_response(status)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self):
                nonlocal wifi_changed
                if self.path.startswith('/credentials/') and args.credential_command:
                    try:
                        return self.respond(call_credentials(side))
                    except Exception:
                        return self.respond({'error': 'credential_request_failed'}, 503)
                if self.path == '/config':
                    if args.credential_command:
                        return self.respond({'side': side, 'perCallCredentials': True})
                    return self.respond({
                        'side': side,
                        'stun': f'stun:{args.turn_ip}:34791' if args.turn_transport == 'udp' else None,
                        'turn': (f'turn:{args.turn_ip}:34791?transport=udp'
                                 if args.turn_transport == 'udp'
                                 else 'turn:127.0.0.1:34791?transport=tcp'),
                        'username': 'mixed-policy-proof', 'credential': credential,
                        'brokenIpv6Candidate': args.fallback_probe,
                        # The available physical device's resolver suppresses
                        # AAAA for this fixture; the emulator returns both.
                        # Keep the hostname family proof on that explicit side.
                        'turnHostnameProbe': args.fallback_probe and side == 1,
                        'unavailableTurnUdp': 'turn:127.0.0.1:34792?transport=udp' if args.fallback_probe else None,
                    })
                with condition:
                    ready = condition.wait_for(
                        lambda: (1 - side, self.path) in messages, timeout=55)
                    value = messages.get((1 - side, self.path), {})
                    if (ready and args.lose_wifi_after_first_media and
                            self.path == '/all-all-0/0/verified' and not wifi_changed):
                        # Both endpoints have established their initial selected
                        # path and RTP before changing this one discovered device.
                        wifi_changed = True
                        subprocess.run(['adb', '-s', args.physical, 'shell',
                                        'svc', 'wifi', 'disable'], check=True,
                                       capture_output=True, timeout=10)
                self.respond(value, 200 if ready else 408)

            def do_POST(self):
                length = int(self.headers['Content-Length'])
                if length > 128 * 1024:
                    return self.respond({}, 413)
                value = json.loads(self.rfile.read(length))
                with condition:
                    messages[side, self.path] = value
                    condition.notify_all()
                if self.path.endswith('/verified'):
                    (args.output / f'phase-{side}-{value["case"]}-{value["generation"]}.json').write_text(
                        json.dumps(value, indent=2) + '\n')
                    print(f"side={side} {value['case']} generation={value['generation']} "
                          f"local={value['localCandidateType']} remote={value['remoteCandidateType']} "
                          'RTP=advanced', flush=True)
                self.respond({})
        return Handler

    try:
        turn_log = open(args.output / 'turn.log', 'w')
        logs.append(turn_log)
        # Reuse the existing audio harness's pinned coturn dependency and
        # external-address mapping. Credentials never enter proof summaries.
        turn_config = args.output / 'turn.conf'
        turn_config.write_text('\n'.join([
            f'external-ip={args.turn_ip}',
            # Keep the fixed relay range below macOS's ephemeral client ports.
            # A host UDP socket can otherwise occupy a published port before
            # Docker binds it (observed at UDP 49391).
            'listening-port=34791', 'min-port=40000', 'max-port=40100',
            'realm=mixed-policy-proof', 'lt-cred-mech',
            f'user=mixed-policy-proof:{credential}',
            'no-tls', 'no-multicast-peers',
            'pidfile=/tmp/mixed-policy-turn.pid',
            'no-software-attribute', 'simple-log', 'log-file=stdout',
        ]))
        if args.credential_command:
            credential_client = subprocess.Popen(
                [str(args.credential_command.resolve())], cwd=ROOT,
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=turn_log,
                text=True, bufsize=1)
            processes.append(credential_client)
            if read_credential_response().get('ready') is not True:
                raise RuntimeError('Credential client startup failed')
        else:
            turn = subprocess.Popen([
                'docker', 'run', '--rm', '--name', container,
                '-p', '34791:34791/tcp', '-p', '34791:34791/udp',
                '-p', '40000-40100:40000-40100/udp',
                '--mount', f'type=bind,src={turn_config.resolve()},dst=/etc/mixed-policy.conf,readonly',
                turn_image, '-c', '/etc/mixed-policy.conf',
            ], stdout=turn_log, stderr=subprocess.STDOUT)
            processes.append(turn)
        for side, device in enumerate(devices):
            server = ThreadingHTTPServer(('127.0.0.1', 48765 + side), handler(side))
            servers.append(server)
            threading.Thread(target=server.serve_forever, daemon=True).start()
            subprocess.run(['adb', '-s', device, 'reverse', 'tcp:48765',
                            f'tcp:{48765 + side}'], check=True, capture_output=True)
            reversed_devices.append(device)
            if args.turn_transport == 'tcp' and not args.credential_command:
                subprocess.run(['adb', '-s', device, 'reverse', 'tcp:34791',
                                'tcp:34791'], check=True, capture_output=True)
            subprocess.run(['adb', '-s', device, 'install', '-r', '-g', str(args.apk)],
                           check=True, capture_output=True)
            installed.append(device)
            subprocess.run(['adb', '-s', device, 'shell', 'input', 'keyevent',
                            'KEYCODE_WAKEUP'], check=True, capture_output=True)
        drivers = []
        for side, device in enumerate(devices):
            log = open(args.output / f'device-{side}.log', 'w')
            logs.append(log)
            driver = subprocess.Popen([
                str(args.flutter), 'drive', '--no-pub', '-d', device,
                '--use-application-binary', str(args.apk),
                '--driver', 'test_driver/integration_test.dart',
                '--target', 'integration_test/audio_peer_connection_proof_test.dart',
                '--no-dds',
            ], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
            drivers.append(driver)
            processes.append(driver)
        deadline = time.monotonic() + 900
        while any(p.poll() is None for p in drivers):
            if ((turn is not None and turn.poll() is not None)
                    or (credential_client is not None and credential_client.poll() is not None)
                    or time.monotonic() > deadline):
                raise RuntimeError('Native proof process deadline or TURN failure')
            time.sleep(1)
        passed = all(p.returncode == 0 for p in drivers)
        # Some flutter drive/plugin combinations exit zero after a failed
        # integration test. Require the endpoint receipt and inspect test output.
        passed &= all('Some tests failed' not in
                      (args.output / f'device-{side}.log').read_text()
                      for side in [0, 1])
        endpoints = [messages.get((side, '/result')) for side in [0, 1]]
        passed &= all(e and e.get('passed') and len(e['phases']) == 16 for e in endpoints)
        if args.credential_command:
            passed &= credential_requests == 16
            passed &= all(p.get('localRelayProtocol') == args.turn_transport
                          for e in endpoints if e for p in e.get('phases', [])
                          if p.get('localUsesTurn'))
        result = {
            'passed': bool(passed), 'devices': devices,
            'apkSha256': hashlib.sha256(args.apk.read_bytes()).hexdigest(),
            'driverExitCodes': [p.returncode for p in drivers],
            'turnTransport': args.turn_transport,
            'fallbackProbe': args.fallback_probe,
            'physicalWifiRemovedAfterMedia': wifi_changed,
            'coturnImage': None if args.credential_command else turn_image,
            'deployedTurnAuthority': args.credential_command is not None,
            'freshCredentialRequests': credential_requests,
            'credentialFailures': credential_failures,
            'endpoints': endpoints,
            'scope': 'native media wrapper interoperability and signaling address privacy; local test broker',
        }
        (args.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        print('PASS' if passed else 'FAIL', flush=True)
        return 0 if passed else 1
    finally:
        if credential_client is not None and credential_client.poll() is None:
            credential_client.stdin.close()
            try:
                credential_client.wait(timeout=10)
            except subprocess.TimeoutExpired:
                pass  # The owned-process cleanup below remains bounded.
        if wifi_changed:
            restored = subprocess.run(['adb', '-s', args.physical, 'shell',
                                       'svc', 'wifi', 'enable'], capture_output=True)
            wifi_after = subprocess.run(
                ['adb', '-s', args.physical, 'shell', 'settings', 'get', 'global', 'wifi_on'],
                text=True, capture_output=True)
            (args.output / 'wifi-restoration.json').write_text(json.dumps({
                'original': wifi_before, 'restored': wifi_after.stdout.strip(),
                'commandSucceeded': restored.returncode == 0,
            }) + '\n')
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        for server in servers:
            server.shutdown()
            server.server_close()
        if not args.credential_command:
            subprocess.run(['docker', 'rm', '--force', container], capture_output=True)
        for device in installed:
            subprocess.run(['adb', '-s', device, 'uninstall', PACKAGE], capture_output=True)
        for device in reversed_devices:
            subprocess.run(['adb', '-s', device, 'reverse', '--remove', 'tcp:48765'],
                           capture_output=True)
            if args.turn_transport == 'tcp' and not args.credential_command:
                subprocess.run(['adb', '-s', device, 'reverse', '--remove', 'tcp:34791'],
                               capture_output=True)
        for log in logs:
            log.close()
        for name in ['turn.log', 'device-0.log', 'device-1.log']:
            path = args.output / name
            if path.exists():
                content = path.read_text(errors='replace')
                for private in redactions:
                    content = content.replace(private, '<redacted-turn-credential>')
                path.write_text(content)
        (args.output / 'turn.conf').unlink(missing_ok=True)
        cleanup_driver_forwards(devices, args.output, original_forwards)
        if wifi_changed and (restored.returncode != 0 or wifi_after.stdout.strip() != wifi_before):
            raise RuntimeError('Physical Wi-Fi restoration was not verified')


if __name__ == '__main__':
    raise SystemExit(main())
