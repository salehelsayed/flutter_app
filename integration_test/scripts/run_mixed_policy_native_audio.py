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
import ipaddress
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import select
import secrets
import shlex
import struct
import subprocess
import threading
import time

PACKAGE = 'com.mknoon.sims.mixedpolicy'
ROOT = Path(__file__).resolve().parents[2]


def endpoints_pass(endpoints, *, relay_only, transport, rejection=None):
    policies = ['relayOnly'] if relay_only else ['all', 'relayOnly']
    cases = {f'{a}-{b}-{caller}' for a in policies for b in policies for caller in [0, 1]}
    expected = {(case, generation) for case in cases for generation in [0, 1]}
    if len(endpoints) != 2:
        return False
    for side, endpoint in enumerate(endpoints):
        if not endpoint or endpoint.get('passed') is not True or endpoint.get('closedCalls') != len(cases):
            return False
        phases = endpoint.get('phases', [])
        if rejection:
            controls = endpoint.get('negativeControls', [])
            if phases or len(controls) != len(cases) or not all(
                    n.get('rejected') is True and n.get('reason') == rejection for n in controls):
                return False
            continue
        if len(phases) != len(expected) or {(p.get('case'), p.get('generation')) for p in phases} != expected:
            return False
        for phase in phases:
            policy = phase['case'].split('-')[side]
            if (phase.get('policy') != policy or phase.get('bidirectionalRtpAdvanced') is not True or
                    phase.get('secureTransportReady') is not True):
                return False
            if policy == 'relayOnly' and not all(phase.get(k) is True for k in (
                    'localUsesTurn', 'relatedAddressesSanitized', 'sdpAndCandidatePrivacyChecked')):
                return False
            if phase.get('localUsesTurn') and phase.get('localRelayProtocol') != transport:
                return False
    return True


def emulator_turn_socket_families(pid, port):
    # lsof observes the emulator's actual host-side network sockets. It never
    # exposes addresses in receipts. The emulator's DNS fixture separately
    # restricts the native resolver; a candidate family is not used here.
    processes = subprocess.check_output(['ps', '-axo', 'pid=,ppid=,comm='],
                                        text=True, timeout=5)
    rows = [line.strip().split(None, 2) for line in processes.splitlines()]
    if not any(len(row) == 3 and row[0] == str(pid) and
               Path(row[2]).name.startswith('qemu-system-') for row in rows):
        raise RuntimeError('Socket attribution requires the owned QEMU process')
    # Recent Android emulators route Wi-Fi through their netsimd child, rather
    # than a socket in QEMU itself. Include only that exact parent's child.
    owners = [str(pid)] + [row[0] for row in rows if len(row) == 3 and
                          row[1] == str(pid) and Path(row[2]).name == 'netsimd']
    result = subprocess.run(['lsof', '-nP', '-a', '-p', ','.join(owners),
                             f'-iTCP:{port}', '-sTCP:ESTABLISHED', '-Fn'],
                            text=True, capture_output=True, timeout=5)
    families = set()
    for line in result.stdout.splitlines():
        if line.startswith('n') and '->' in line:
            remote = line.split('->', 1)[1].rsplit(':', 1)[0].strip('[]')
            address = ipaddress.ip_address(remote)
            families.add('unknown' if getattr(address, 'ipv4_mapped', None)
                         else f'ipv{address.version}')
    return families


def emulator_turn_packet_families(pid, capture, port):
    """Require recent bidirectional RTP ChannelData in an owned guest capture.

    UDP sockets in QEMU can be unconnected, so lsof cannot identify their
    destination. Never substitute a TCP socket or DNS answer as UDP evidence.
    The operator must use fresh disposable guest data when capturing its LAN.
    """
    command = shlex.split(subprocess.check_output(
        ['ps', '-p', str(pid), '-o', 'command='], text=True, timeout=5).strip())
    if (not command or not Path(command[0]).name.startswith('qemu-system-') or
            '-tcpdump' not in command or command.index('-tcpdump') + 1 >= len(command) or
            command[command.index('-tcpdump') + 1] != str(capture.resolve())):
        raise RuntimeError('Packet attribution requires the owned QEMU capture')
    metadata = capture.stat()
    if metadata.st_size > 20 * 1024 * 1024:
        raise RuntimeError('Owned packet capture exceeded its evidence bound')
    if time.time() - metadata.st_mtime > 10:
        return set()
    data = capture.read_bytes()
    if len(data) < 24:
        return set()
    formats = {b'\xd4\xc3\xb2\xa1': ('<', 1_000_000), b'\xa1\xb2\xc3\xd4': ('>', 1_000_000),
               b'\x4d\x3c\xb2\xa1': ('<', 1_000_000_000), b'\xa1\xb2\x3c\x4d': ('>', 1_000_000_000)}
    if data[:4] not in formats:
        raise RuntimeError('Unsupported emulator capture format')
    endian, resolution = formats[data[:4]]
    if struct.unpack_from(endian + 'I', data, 20)[0] != 1:
        raise RuntimeError('Expected emulator Ethernet capture')
    # QEMU's packet timestamps can have a different epoch offset from the host.
    # Use recency within that capture, with host file freshness checked above;
    # do not subtract a guest packet timestamp from host wall-clock time.
    offset = 24; latest = None; media = []
    while offset + 16 <= len(data):
        seconds, fraction, size, _ = struct.unpack_from(endian + 'IIII', data, offset)
        offset += 16
        if offset + size > len(data):
            break  # The emulator may still be writing the last record.
        packet = data[offset:offset + size]; offset += size
        stamp = seconds + fraction / resolution
        latest = stamp if latest is None else max(latest, stamp)
        if len(packet) < 14:
            continue
        kind = struct.unpack_from('!H', packet, 12)[0]; start = 14
        if kind in (0x8100, 0x88a8) and len(packet) >= 18:
            kind = struct.unpack_from('!H', packet, 16)[0]; start = 18
        if kind == 0x0800 and len(packet) >= start + 20:
            if packet[start + 9] != 17 or struct.unpack_from('!H', packet, start + 6)[0] & 0x1fff:
                continue
            header = (packet[start] & 15) * 4
            if header < 20: continue
            udp = start + header; family = 'ipv4'
        elif kind == 0x86dd and len(packet) >= start + 40 and packet[start + 6] == 17:
            udp = start + 40; family = 'ipv6'
        else:
            continue
        if len(packet) < udp + 8: continue
        source, destination, length, _ = struct.unpack_from('!HHHH', packet, udp)
        payload = packet[udp + 8:udp + length]
        if len(payload) < 16 or len(payload) != length - 8: continue
        channel, body_size = struct.unpack_from('!HH', payload)
        if not (0x4000 <= channel <= 0x7fff and body_size >= 12 and
                len(payload) >= 4 + body_size and payload[4] & 0xc0 == 0x80):
            continue
        media.append((stamp, source, destination, family))
    sent = {family for stamp, source, destination, family in media
            if destination == port and stamp >= latest - 10}
    received = {family for stamp, source, destination, family in media
                if source == port and stamp >= latest - 10}
    return sent if sent and sent == received else set()


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
    parser.add_argument('--relay-only', action='store_true',
                        help='Isolate the requested TURN transport in both directions, including restart and a subsequent call')
    parser.add_argument('--tls-url', help='Explicit isolated turns: URL; no alternate ICE server is supplied')
    parser.add_argument('--expect-tls-rejection', choices=['hostname', 'untrusted'])
    parser.add_argument('--tls-reverse-port', type=int,
                        help='Owned USB port for an isolated untrusted-certificate negative control only')
    parser.add_argument('--emulator-turn-family', choices=['ipv4', 'ipv6'],
                        help='Require the prepared emulator DNS isolation and independently observed TURN socket family')
    parser.add_argument('--emulator-process-id', type=int,
                        help='Owned emulator PID for native socket attribution through its virtual network')
    parser.add_argument('--emulator-packet-capture', type=Path,
                        help='Owned QEMU -tcpdump path with fresh disposable guest data; required for UDP family evidence')
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
    if (args.tls_url or args.expect_tls_rejection) and (args.turn_transport != 'tls' or not args.relay_only):
        parser.error('TLS isolation and negative controls require TLS and relay-only')
    if args.tls_url and not re.fullmatch(r'turns:(?:[A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\]):[0-9]{1,5}\?transport=tcp', args.tls_url):
        parser.error('TLS fixture must supply one explicit turns: TCP service')
    if args.tls_reverse_port and (args.expect_tls_rejection != 'untrusted' or
                                  args.tls_url != f'turns:127.0.0.1:{args.tls_reverse_port}?transport=tcp' or
                                  not 1024 <= args.tls_reverse_port <= 65535):
        parser.error('USB TLS forwarding is restricted to the loopback untrusted-certificate control')
    if args.emulator_turn_family and (not args.emulator_process_id or not args.relay_only or
                                      args.turn_transport not in ('tls', 'udp') or args.tls_url or
                                      args.expect_tls_rejection or not args.credential_command):
        parser.error('Family proof requires isolated TLS/UDP media, deployed credentials, the advertised hostname and an owned emulator PID')
    if args.emulator_turn_family and args.turn_transport == 'udp' and not args.emulator_packet_capture:
        parser.error('UDP family proof requires an owned emulator packet capture')
    if args.emulator_packet_capture and (not args.emulator_turn_family or args.turn_transport != 'udp'):
        parser.error('The emulator packet capture is only used for explicit UDP family proof')
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
        if args.tls_reverse_port:
            required_ports.add(f'tcp:{args.tls_reverse_port}')
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
    emulator_socket_families = set()
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
            return {'turn': args.tls_url or urls[0], 'username': bundle['username'],
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
                        return self.respond({'side': side, 'perCallCredentials': True,
                                             'relayOnly': args.relay_only,
                                             'expectedRelayProtocol': args.turn_transport,
                                             'requiredTurnDnsFamily': args.emulator_turn_family if side == 1 else None,
                                             'turnHostname': args.turn_ip,
                                             'expectedTlsRejection': args.expect_tls_rejection})
                    return self.respond({
                        'side': side,
                        'relayOnly': args.relay_only,
                        'expectedRelayProtocol': args.turn_transport,
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
                    if side == 1 and args.emulator_turn_family:
                        families = (emulator_turn_packet_families(
                            args.emulator_process_id, args.emulator_packet_capture, 3478)
                            if args.turn_transport == 'udp' else
                            emulator_turn_socket_families(args.emulator_process_id, 5349))
                        (args.output / f'socket-family-{side}-{value["case"]}-{value["generation"]}.json').write_text(
                            json.dumps({'observed': sorted(families), 'required': args.emulator_turn_family}) + '\n')
                        if families != {args.emulator_turn_family}:
                            return self.respond({'error': 'TURN socket family not established'}, 503)
                        emulator_socket_families.update(families)
                        value['emulatorToTurnPacketFamily' if args.turn_transport == 'udp' else
                              'emulatorToTurnSocketFamily'] = args.emulator_turn_family
                        value['socketObservationBoundary'] = ('owned guest capture, bidirectional RTP ChannelData'
                            if args.turn_transport == 'udp' else 'emulator virtual network egress, owned process')
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
            if args.tls_reverse_port:
                subprocess.run(['adb', '-s', device, 'reverse',
                                f'tcp:{args.tls_reverse_port}', f'tcp:{args.tls_reverse_port}'],
                               check=True, capture_output=True)
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
        passed &= endpoints_pass(endpoints, relay_only=args.relay_only,
                                 transport=args.turn_transport, rejection=args.expect_tls_rejection)
        if args.credential_command:
            passed &= credential_requests == (4 if args.relay_only else 16)
            passed &= all(p.get('localRelayProtocol') == args.turn_transport
                          for e in endpoints if e for p in e.get('phases', [])
                          if p.get('localUsesTurn'))
        if args.emulator_turn_family:
            passed &= emulator_socket_families == {args.emulator_turn_family}
        result = {
            'passed': bool(passed), 'devices': devices,
            'apkSha256': hashlib.sha256(args.apk.read_bytes()).hexdigest(),
            'driverExitCodes': [p.returncode for p in drivers],
            'turnTransport': args.turn_transport,
            'relayOnly': args.relay_only,
            'expectedTlsRejection': args.expect_tls_rejection,
            'clientToTurnFamily': 'unknown',
            'emulatorToTurnSocketFamilies': sorted(emulator_socket_families) if args.turn_transport != 'udp' else [],
            'emulatorToTurnPacketFamilies': sorted(emulator_socket_families) if args.turn_transport == 'udp' else [],
            'emulatorRequiredTurnDnsFamily': args.emulator_turn_family,
            'audibleAudio': 'unobserved',
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
            if args.tls_reverse_port:
                subprocess.run(['adb', '-s', device, 'reverse', '--remove',
                                f'tcp:{args.tls_reverse_port}'], capture_output=True)
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
