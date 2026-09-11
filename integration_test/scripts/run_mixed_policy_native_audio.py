#!/usr/bin/env python3
"""Run the optional audio_peer_connection proof on a pinned Android pair.

Build the existing integration_test/audio_peer_connection_proof_test.dart with
MIXED_POLICY_BROKER=http://127.0.0.1:48765, androidApplicationId set to
com.mknoon.sims.mixedpolicy, and disableGoogleServicesForDisposableProof=true.
Uses the repository's Docker coturn lock, an IPv4 address reachable by both
devices, and an APK. TCP control may be forwarded over USB with --turn-transport.
Uses disposable media only; no application account or production relay is used.
"""

import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import threading
import time

PACKAGE = 'com.mknoon.sims.mixedpolicy'
ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--physical', required=True)
    parser.add_argument('--emulator', required=True)
    parser.add_argument('--flutter', required=True, type=Path)
    parser.add_argument('--apk', required=True, type=Path)
    parser.add_argument('--turn-ip', required=True)
    parser.add_argument('--turn-transport', choices=['udp', 'tcp'], default='tcp')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    args.output.mkdir(parents=True, exist_ok=False)
    devices = [args.physical, args.emulator]
    live = subprocess.check_output(['adb', 'devices'], text=True)
    assert all(f'{d}\tdevice' in live for d in devices)
    assert not args.physical.startswith('emulator-')
    assert args.emulator.startswith('emulator-')
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
        if args.turn_transport == 'tcp':
            required_ports.add('tcp:34791')
        if any(required_ports.intersection(line.split()[1:2])
               for line in reverse.splitlines()):
            raise RuntimeError('Proof reverse port already exists; preserve it')

    messages = {}
    condition = threading.Condition()
    credential = secrets.token_hex(24)
    container = 'mknoon-mixed-policy-' + secrets.token_hex(6)
    turn_lock = json.loads((ROOT / 'tool/call_audio_oracle/coturn.lock.json').read_text())
    turn_image = turn_lock['image'].split(':')[0] + '@' + turn_lock['digest']
    servers, processes, logs, installed, reversed_devices = [], [], [], [], []

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
                if self.path == '/config':
                    return self.respond({
                        'side': side,
                        'stun': f'stun:{args.turn_ip}:34791' if args.turn_transport == 'udp' else None,
                        'turn': (f'turn:{args.turn_ip}:34791?transport=udp'
                                 if args.turn_transport == 'udp'
                                 else 'turn:127.0.0.1:34791?transport=tcp'),
                        'username': 'mixed-policy-proof', 'credential': credential,
                    })
                with condition:
                    ready = condition.wait_for(
                        lambda: (1 - side, self.path) in messages, timeout=55)
                    value = messages.get((1 - side, self.path), {})
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
            if args.turn_transport == 'tcp':
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
            if turn.poll() is not None or time.monotonic() > deadline:
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
        result = {
            'passed': bool(passed), 'devices': devices,
            'apkSha256': hashlib.sha256(args.apk.read_bytes()).hexdigest(),
            'driverExitCodes': [p.returncode for p in drivers],
            'turnTransport': args.turn_transport,
            'coturnImage': turn_image,
            'endpoints': endpoints,
            'scope': 'native media wrapper interoperability and signaling address privacy; local test broker',
        }
        (args.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        print('PASS' if passed else 'FAIL', flush=True)
        return 0 if passed else 1
    finally:
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
        subprocess.run(['docker', 'rm', '--force', container], capture_output=True)
        for device in installed:
            subprocess.run(['adb', '-s', device, 'uninstall', PACKAGE], capture_output=True)
        for device in reversed_devices:
            subprocess.run(['adb', '-s', device, 'reverse', '--remove', 'tcp:48765'],
                           capture_output=True)
            if args.turn_transport == 'tcp':
                subprocess.run(['adb', '-s', device, 'reverse', '--remove', 'tcp:34791'],
                               capture_output=True)
        for log in logs:
            log.close()
        (args.output / 'turn.conf').unlink(missing_ok=True)


if __name__ == '__main__':
    raise SystemExit(main())
