#!/usr/bin/env python3
"""Bounded TURN socket probe; no live-audio retransmission or app verdict.

Extends the retained independent framed TURN probe with UDP datagram boundaries,
transaction demultiplexing and paced sequence observations at both client sockets.
Call run_trial with fresh credentials from the existing validated credential client.
All addresses/credentials stay in memory; the returned receipt contains coarse
families, sequence numbers and monotonic times only.
"""
from collections import deque
import argparse
import datetime
import hashlib
import hmac
import ipaddress
import json
import os
from pathlib import Path
import select
import secrets
import signal
import socket
import ssl
import struct
import subprocess
import time

COOKIE = 0x2112A442
CHANNEL = 0x4001


class TurnRejected(Exception):
    def __init__(self, method, response):
        value = attrs(response).get(9, b'')
        self.method = method
        self.code = value[2] * 100 + value[3] if len(value) >= 4 else None
        super().__init__('turn_request_rejected')


def attr(kind, value):
    return struct.pack('!HH', kind, len(value)) + value + bytes(-len(value) % 4)


def attrs(frame):
    result = {}
    offset = 20
    while offset < len(frame):
        if offset + 4 > len(frame):
            raise ValueError('truncated_attribute')
        kind, size = struct.unpack_from('!HH', frame, offset)
        end = offset + 4 + size
        if end > len(frame) or kind in result:
            raise ValueError('invalid_attribute')
        result[kind] = frame[offset + 4:end]
        offset = end + (-size % 4)
    if offset != len(frame):
        raise ValueError('truncated_padding')
    return result


class Frames:
    def __init__(self, sock, datagram):
        self.sock, self.datagram, self.buffer = sock, datagram, b''

    def read(self):
        if self.datagram:
            packet = self.sock.recv(65536)
            # UDP ChannelData padding is optional. Never combine datagrams to
            # satisfy the mandatory stream padding used for TCP/TLS.
            if len(packet) < 4:
                raise ValueError('short_datagram')
            kind, size = struct.unpack_from('!HH', packet)
            if 0x4000 <= kind <= 0x7fff:
                end = 4 + size
                if not end <= len(packet) <= end + (-size % 4):
                    raise ValueError('invalid_channel_datagram')
                return packet[:end]
            self.validate_stun(packet)
            return packet
        while True:
            if len(self.buffer) >= 4:
                kind, size = struct.unpack_from('!HH', self.buffer)
                length = 4 + size + (-size % 4) if 0x4000 <= kind <= 0x7fff else 20 + size
                if len(self.buffer) >= length:
                    frame, self.buffer = self.buffer[:length], self.buffer[length:]
                    if not 0x4000 <= kind <= 0x7fff:
                        self.validate_stun(frame)
                    return frame
            chunk = self.sock.recv(65536)
            if not chunk:
                raise EOFError('closed_before_complete_frame')
            self.buffer += chunk

    @staticmethod
    def validate_stun(frame):
        if (len(frame) < 20 or frame[0] & 0xc0 or
                struct.unpack_from('!I', frame, 4)[0] != COOKIE or
                struct.unpack_from('!H', frame, 2)[0] != len(frame) - 20):
            raise ValueError('invalid_stun_frame')


class TurnProbe:
    def __init__(self, sock, *, transport, allocation_family, credentials, timeout=7):
        self.sock, self.transport = sock, transport
        self.family, self.credentials, self.timeout = allocation_family, credentials, timeout
        self.frames = Frames(sock, transport == 'udp')
        self.realm = self.nonce = b''
        self.key = None
        self.allocated = False
        self.media = deque(maxlen=256)
        self.stale_responses = 0
        self.control_retransmissions = 0

    def request(self, method, payload=b'', *, authenticated=True, transaction=None):
        transaction = transaction or os.urandom(12)
        if authenticated:
            payload += attr(6, self.credentials['username'].encode()) + attr(0x14, self.realm) + attr(0x15, self.nonce)
        packet = struct.pack('!HHI', method, len(payload) + (24 if authenticated else 0), COOKIE) + transaction + payload
        if authenticated:
            packet += attr(8, hmac.new(self.key, packet, hashlib.sha1).digest())
        deadline = time.monotonic() + self.timeout
        interval = .5
        self.sock.sendall(packet)
        retry_at = time.monotonic() + interval
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError('control_deadline')
            until_retry = max(.001, retry_at - time.monotonic())
            self.sock.settimeout(min(remaining, until_retry) if self.transport == 'udp' else remaining)
            try:
                response = self.frames.read()
            except TimeoutError:
                if self.transport == 'udp' and time.monotonic() < deadline:
                    self.sock.sendall(packet)
                    self.control_retransmissions += 1
                    interval *= 2
                    retry_at = time.monotonic() + interval
                    continue
                raise
            kind = struct.unpack_from('!H', response)[0]
            if 0x4000 <= kind <= 0x7fff:
                if len(self.media) == self.media.maxlen:
                    raise ValueError('media_queue_limit')
                self.media.append(response)
                continue
            if response[8:20] != transaction:
                self.stale_responses += 1
                continue
            if authenticated:
                self.verify_integrity(response)
            return response

    def verify_integrity(self, response):
        offset = 20
        while offset + 4 <= len(response):
            kind, size = struct.unpack_from('!HH', response, offset)
            if kind == 8:
                prefix = bytearray(response[:offset])
                struct.pack_into('!H', prefix, 2, offset + 4)
                expected = hmac.new(self.key, prefix, hashlib.sha1).digest()
                if size != 20 or not hmac.compare_digest(expected, response[offset + 4:offset + 24]):
                    raise ValueError('response_integrity')
                return
            offset += 4 + size + (-size % 4)
        raise ValueError('missing_response_integrity')

    def allocate(self):
        payload = attr(0x19, b'\x11\0\0\0') + attr(0x17, bytes([1 if self.family == 4 else 2, 0, 0, 0]))
        response = self.request(3, payload, authenticated=False)
        challenge = attrs(response)
        if struct.unpack_from('!H', response)[0] != 0x113:
            raise ValueError('allocation_challenge')
        self.realm, self.nonce = challenge[0x14], challenge[0x15]
        self.key = hashlib.md5(self.credentials['username'].encode() + b':' + self.realm + b':' + self.credentials['password'].encode()).digest()
        response = self.request(3, payload)
        if struct.unpack_from('!H', response)[0] != 0x103:
            raise TurnRejected('allocation', response)
        self.allocated = True
        address = attrs(response)[0x16]
        mask = struct.pack('!I', COOKIE) + response[8:20]
        self.relay = (ipaddress.ip_address(bytes(b ^ mask[i] for i, b in enumerate(address[4:]))), struct.unpack_from('!H', address, 2)[0] ^ (COOKIE >> 16))
        if self.relay[0].version != self.family:
            raise ValueError('allocation_family')

    def peer_address(self, peer, transaction):
        address, port = peer.relay
        mask = struct.pack('!I', COOKIE) + transaction
        return bytes([0, 1 if address.version == 4 else 2]) + struct.pack('!H', port ^ (COOKIE >> 16)) + bytes(b ^ mask[i] for i, b in enumerate(address.packed))

    def permit_and_bind(self, peer):
        for method in (8, 9):
            transaction = os.urandom(12)
            payload = attr(0x12, self.peer_address(peer, transaction))
            if method == 9:
                payload = attr(0x0c, struct.pack('!HH', CHANNEL, 0)) + payload
            response = self.request(method, payload, transaction=transaction)
            if struct.unpack_from('!H', response)[0] != 0x100 + method:
                raise TurnRejected('permission' if method == 8 else 'channel', response)

    def send_media(self, payload):
        packet = struct.pack('!HH', CHANNEL, len(payload)) + payload
        if self.transport != 'udp':
            packet += bytes(-len(payload) % 4)
        self.sock.sendall(packet)

    def receive_media(self):
        while True:
            frame = self.media.popleft() if self.media else self.frames.read()
            kind, size = struct.unpack_from('!HH', frame)
            if kind == CHANNEL:
                return frame[4:4 + size]
            if 0x4000 <= kind <= 0x7fff:
                raise ValueError('unexpected_channel')
            self.stale_responses += 1

    def close(self):
        try:
            if self.allocated:
                response = self.request(4, attr(0x0d, bytes(4)))
                if struct.unpack_from('!H', response)[0] != 0x104 or attrs(response).get(0x0d) != bytes(4):
                    raise ValueError('cleanup_rejected')
                self.allocated = False
        finally:
            self.sock.close()


def run_trial(*, server, port, control_family, allocation_family, transport,
              credentials, interface=None, hostname=None, count=50,
              payload_size=100, interval=.02, timeout=7):
    if not 1 <= count <= 250 or not 8 <= payload_size <= 1200 or not 0 <= interval <= .2 or not 0 < timeout <= 7:
        raise ValueError('probe_bounds')
    if (control_family not in (4, 6) or allocation_family not in (4, 6) or
            transport not in ('udp', 'tcp', 'tls') or
            ipaddress.ip_address(server).version != control_family or
            (transport == 'tls' and not hostname)):
        raise ValueError('explicit_family_and_tls_hostname_required')
    row = dict(connectionFamily=f'ipv{control_family}', allocationFamily=f'ipv{allocation_family}', transport=transport,
               payloadBytes=payload_size, payloadsPerDirection=count, intervalMs=interval * 1000,
               deadlineSeconds=timeout, observations=[], endpoints=[], cleanup=[],
               actualAllocationFamilies=[], hostnameVerified=transport == 'tls')
    peers = []
    stage = 'allocation'
    try:
        for _ in range(2):
            sock = socket.socket(socket.AF_INET6 if control_family == 6 else socket.AF_INET,
                                 socket.SOCK_DGRAM if transport == 'udp' else socket.SOCK_STREAM)
            try:
                sock.settimeout(timeout)
                if interface:
                    if os.uname().sysname != 'Darwin':
                        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, interface.encode() + b'\0')
                    else:
                        level, option = (socket.IPPROTO_IP, 25) if control_family == 4 else (socket.IPPROTO_IPV6, 125)
                        sock.setsockopt(level, option, socket.if_nametoindex(interface))
                sock.connect((server, port))
                if transport == 'tls':
                    sock = ssl.create_default_context().wrap_socket(sock, server_hostname=hostname)
                probe = TurnProbe(sock, transport=transport, allocation_family=allocation_family, credentials=credentials, timeout=timeout)
            except BaseException:
                sock.close()
                raise
            peers.append(probe)
            probe.allocate()
            row['actualAllocationFamilies'].append(f'ipv{probe.relay[0].version}')
        stage = 'permission'
        for side, peer in enumerate(peers):
            peer.permit_and_bind(peers[1 - side])
        stage = 'data'
        received = [[], []]
        start = time.monotonic()
        finish = start + count * interval + timeout
        sequence = 0
        def payload(side, seq):
            return struct.pack('!II', side, seq) + b'SYNTHETIC-TURN-PROBE'.ljust(payload_size - 8, b'.')[:payload_size - 8]
        while time.monotonic() < finish:
            now = time.monotonic()
            if sequence < count and now >= start + sequence * interval:
                for side, peer in enumerate(peers):
                    peer.send_media(payload(side, sequence))
                    row['observations'].append(dict(side=side, operation='send_complete', sequence=sequence, monotonicNs=time.monotonic_ns()))
                sequence += 1
            next_send = start + sequence * interval if sequence < count else finish
            ready, _, _ = select.select([p.sock for p in peers], [], [], max(0, min(.02, next_send - time.monotonic())))
            for side, peer in enumerate(peers):
                if peer.sock not in ready and not peer.media and not peer.frames.buffer:
                    continue
                peer.sock.settimeout(max(.001, finish - time.monotonic()))
                data = peer.receive_media()
                sender, seq = struct.unpack_from('!II', data)
                if sender != 1 - side or seq >= count or data != payload(sender, seq):
                    raise ValueError('returned_bytes_mismatch')
                received[side].append(seq)
                row['observations'].append(dict(side=side, operation='receive', sequence=seq, monotonicNs=time.monotonic_ns()))
            if sequence == count and all(len(set(r)) == count for r in received):
                break
        for side, seen in enumerate(received):
            row['endpoints'].append(dict(side=side, sent=sequence, received=len(seen), unique=len(set(seen)),
                missing=sorted(set(range(sequence)) - set(seen)), duplicates=len(seen) - len(set(seen)),
                reordered=sum(b < a for a, b in zip(seen, seen[1:])),
                staleResponses=peers[side].stale_responses, controlRetransmissions=peers[side].control_retransmissions))
        row['status'] = 'PASS' if all(e['unique'] == count and not e['duplicates'] for e in row['endpoints']) else 'FAIL'
        if row['status'] == 'FAIL':
            row['failedStage'] = 'data_loss'
    except Exception as error:
        row.update(status='FAIL', failedStage=stage, errorType=type(error).__name__)
        if isinstance(error, TurnRejected):
            row['turnErrorCode'] = error.code
    finally:
        for peer in peers:
            try:
                peer.close()
                row['cleanup'].append(True)
            except Exception:
                row['cleanup'].append(False)
        if row.get('status') == 'PASS' and (len(row['cleanup']) != 2 or not all(row['cleanup'])):
            row.update(status='FAIL', failedStage='cleanup')
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--local-fixture', action='store_true',
                        help='Run the fixed coturn controls inside an already isolated Linux network namespace')
    parser.add_argument('--turn-server', type=Path, help='Exact coturn binary for --local-fixture')
    parser.add_argument('--server', help='Explicit discovered numeric endpoint')
    parser.add_argument('--port', type=int, default=3478)
    parser.add_argument('--control-family', type=int, choices=(4, 6))
    parser.add_argument('--allocation-family', type=int, choices=(4, 6))
    parser.add_argument('--transport', choices=('udp', 'tcp', 'tls'))
    parser.add_argument('--hostname', help='Required verified hostname for TLS')
    parser.add_argument('--interface', help='Pin the host socket interface')
    parser.add_argument('--credential-command', type=Path,
                        help='Existing JSON-line validated credential client; no authority secret')
    parser.add_argument('--trials', type=int, choices=(1, 2, 3), default=3)
    parser.add_argument('--payload-size', type=int, choices=(100, 101), default=100)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.local_fixture:
        if not args.turn_server or args.server or args.credential_command:
            parser.error('--local-fixture requires --turn-server and excludes external endpoints/credentials')
    elif not all((args.server, args.control_family, args.allocation_family,
                  args.transport, args.credential_command)):
        parser.error('Explicit server, families, transport and credential client are required')
    # A terminated diagnostic must still close sockets, release allocations and
    # stop its disposable credential client. This does not install a watchdog
    # or alter any host/relay firewall.
    def interrupted(*unused):
        raise KeyboardInterrupt
    previous_handler = signal.signal(signal.SIGTERM, interrupted)
    os.umask(0o077)
    if args.local_fixture:
        try:
            return run_isolated_fixture(args.output, args.turn_server)
        finally:
            signal.signal(signal.SIGTERM, previous_handler)
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output / 'plan.json').write_text(json.dumps({
        'trials': args.trials, 'transport': args.transport,
        'controlFamily': args.control_family, 'allocationFamily': args.allocation_family,
        'payloadBytes': args.payload_size, 'perDirection': 50, 'intervalMs': 20,
        'drainSeconds': 7, 'mediaRetransmission': False,
        'credentialClientSha256': hashlib.sha256(args.credential_command.read_bytes()).hexdigest(),
        'probeSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'startedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }, indent=2) + '\n')
    process = None
    rows = []
    def read_bundle():
        if not select.select([process.stdout], [], [], 20)[0]:
            raise TimeoutError('credential_client_deadline')
        return json.loads(process.stdout.readline())
    try:
        process = subprocess.Popen([str(args.credential_command.resolve())], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        if read_bundle().get('ready') is not True:
            raise ValueError('credential_client_start')
        for index in range(args.trials):
            if index:
                time.sleep(11)  # outside any call/probe deadline
            process.stdin.write(f'{index % 2}\n')
            process.stdin.flush()
            credentials = read_bundle()
            if (credentials.get('schema') != 'turn_credentials' or credentials.get('version') != 1 or
                    credentials.get('expiresAtMs', 0) < time.time() * 1000 + 30000):
                row = {'status': 'BLOCKED', 'failedStage': 'credentials'}
                if credentials.get('code') in ('REQUEST_REJECTED', 'TURN_CREDENTIALS_RATE_LIMITED',
                                                'TURN_CREDENTIALS_UNAVAILABLE', 'RATE_LIMITED'):
                    row['credentialErrorCode'] = credentials['code']
            else:
                row = run_trial(server=args.server, port=args.port, control_family=args.control_family,
                                allocation_family=args.allocation_family, transport=args.transport,
                                credentials=credentials, interface=args.interface, hostname=args.hostname,
                                payload_size=args.payload_size)
            credentials = {}
            row['trial'] = index + 1
            rows.append(row)
            (args.output / 'results.json').write_text(json.dumps(rows, indent=2) + '\n')
            print(json.dumps({k: v for k, v in row.items() if k != 'observations'}), flush=True)
    finally:
        if process is not None:
            process.stdin.close()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
        signal.signal(signal.SIGTERM, previous_handler)
    return 0 if len(rows) == args.trials and all(r['status'] == 'PASS' for r in rows) else 1


def require_isolated_namespace():
    if os.uname().sysname != 'Linux' or {name for _, name in socket.if_nameindex()} != {'lo'}:
        raise ValueError('fixture_requires_linux_namespace_with_only_loopback')


def run_isolated_fixture(output, binary):
    # Refuse a host or routable namespace before changing even loopback state.
    # unshare/timeout belong to the operator command; no host firewall changes.
    require_isolated_namespace()
    output.mkdir(parents=True, exist_ok=False)
    subprocess.run(['ip', 'link', 'set', 'lo', 'up'], check=True, timeout=5)
    conditions = [('udp', 4, 4, 100), ('udp', 6, 4, 100), ('udp', 6, 6, 100),
                  ('tcp', 4, 4, 100), ('udp', 4, 4, 101)]
    (output / 'plan.json').write_text(json.dumps({
        'repeats': 3, 'conditions': conditions, 'intervalMs': 20,
        'perDirection': 50, 'externalRoute': False,
        'scope': 'TURN component only; no device access-network or app journey',
        'probeSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'serverSha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
        'serverVersion': subprocess.check_output([str(binary), '--version'], text=True, timeout=5).strip(),
    }, indent=2) + '\n')
    secret = secrets.token_hex(24)
    config = output / 'turn.conf'
    config.write_text('\n'.join([
        'listening-ip=127.0.0.1', 'listening-ip=::1', 'relay-ip=127.0.0.1',
        'relay-ip=::1', 'listening-port=34971', 'min-port=41000', 'max-port=41060',
        'realm=network-gap-fixture', 'lt-cred-mech', f'user=disposable:{secret}',
        'no-tls', 'no-dtls', 'no-cli', 'allow-loopback-peers', 'no-multicast-peers',
        'no-software-attribute', 'relay-threads=1', f'pidfile={output}/turn.pid',
        'simple-log', 'log-file=stdout',
    ]) + '\n')
    process = None
    rows = []
    try:
        with (output / 'turn.private.log').open('w') as log:
            process = subprocess.Popen([str(binary), '-c', str(config)], stdout=log, stderr=subprocess.STDOUT)
        time.sleep(.5)
        if process.poll() is not None:
            raise RuntimeError('fixture_start')
        for repeat in range(3):
            for transport, control, allocation, size in conditions:
                row = run_trial(server='127.0.0.1' if control == 4 else '::1', port=34971,
                                control_family=control, allocation_family=allocation, transport=transport,
                                credentials={'username': 'disposable', 'password': secret}, payload_size=size)
                row['repeat'] = repeat + 1
                rows.append(row)
                (output / 'results.json').write_text(json.dumps(rows, indent=2) + '\n')
    finally:
        if process is not None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
        config.unlink(missing_ok=True)
        (output / 'cleanup.json').write_text(json.dumps({
            'serverStopped': process is None or process.poll() is not None,
            'credentialConfigRemoved': not config.exists(), 'hostNetworkChanged': False,
        }, indent=2) + '\n')
    print(json.dumps({'trials': len(rows), 'passed': sum(r['status'] == 'PASS' for r in rows)}))
    return 0 if len(rows) == 15 and all(r['status'] == 'PASS' for r in rows) else 1


if __name__ == '__main__':
    raise SystemExit(main())
