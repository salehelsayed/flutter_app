#!/usr/bin/env python3
"""Independent TLS TURN probe with buffered STUN/ChannelData framing."""
import ast
import base64
import collections
import datetime
import hashlib
import hmac
import ipaddress
import json
import os
from pathlib import Path
import socket
import ssl
import struct
import subprocess
import time

ROOT = Path('/Volumes/CrucialX9/flutter_app')
HERE = Path('/tmp/beta-call-review-20260908')
remote = next(ast.literal_eval(node.value) for node in ast.parse((HERE/'turn_tls_controlled_probe.py').read_text()).body
              if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == 'REMOTE' for target in node.targets))
credentials = json.loads(subprocess.check_output(['ssh', '-i', str(ROOT/'se.pem'), '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15',
    'ubuntu@13.60.15.36', 'sudo python3 -'], input=remote, text=True))
COOKIE = 0x2112A442

def attr(kind, value):
    return struct.pack('!HH', kind, len(value)) + value + b'\x00' * (-len(value) % 4)

def attrs(frame):
    result = {}
    offset = 20
    while offset + 4 <= len(frame):
        kind, size = struct.unpack_from('!HH', frame, offset)
        result[kind] = frame[offset+4:offset+4+size]
        offset += 4 + size + (-size % 4)
    return result

class TurnTLS:
    def __init__(self, family):
        address = '13.60.15.36' if family == 4 else '2a05:d016:c4d:7100:ec85:94ed:b90d:e20'
        transport = socket.socket(socket.AF_INET if family == 4 else socket.AF_INET6, socket.SOCK_STREAM)
        transport.settimeout(5)
        transport.connect((address, 5349))
        self.sock = ssl.create_default_context().wrap_socket(transport, server_hostname='mknoun.xyz')
        self.buffer = b''
        self.read_sizes = []
        self.key = None
        self.realm = self.nonce = b''
        self.family = family
        self.tls_version = self.sock.version()

    def frame(self):
        while True:
            if len(self.buffer) >= 4:
                kind, size = struct.unpack_from('!HH', self.buffer)
                length = 4 + size + (-size % 4) if 0x4000 <= kind <= 0x7FFF else 20 + size
                if len(self.buffer) >= length:
                    frame, self.buffer = self.buffer[:length], self.buffer[length:]
                    return frame
            chunk = self.sock.recv(65536)
            if not chunk:
                raise RuntimeError('TLS stream closed before a complete frame')
            self.read_sizes.append(len(chunk))
            self.buffer += chunk

    def request(self, method, payload=b'', authenticated=True, transaction=None):
        transaction = transaction or os.urandom(12)
        if authenticated:
            payload += attr(0x0006, credentials['username'].encode()) + attr(0x0014, self.realm) + attr(0x0015, self.nonce)
        header = struct.pack('!HHI', method, len(payload) + (24 if authenticated else 0), COOKIE) + transaction
        packet = header + payload
        if authenticated:
            packet += attr(0x0008, hmac.new(self.key, packet, hashlib.sha1).digest())
        self.sock.sendall(packet)
        response = self.frame()
        if response[8:20] != transaction:
            raise RuntimeError('Unexpected STUN transaction')
        return response

    def allocate(self):
        payload = attr(0x0019, b'\x11\x00\x00\x00') + attr(0x0017, bytes([1 if self.family == 4 else 2, 0, 0, 0]))
        response = self.request(0x0003, payload, False)
        challenge = attrs(response)
        if struct.unpack_from('!H', response)[0] != 0x0113 or 0x0014 not in challenge or 0x0015 not in challenge:
            raise RuntimeError('Expected authenticated allocation challenge')
        self.realm, self.nonce = challenge[0x0014], challenge[0x0015]
        self.key = hashlib.md5(credentials['username'].encode()+b':'+self.realm+b':'+credentials['password'].encode()).digest()
        response = self.request(0x0003, payload)
        if struct.unpack_from('!H', response)[0] != 0x0103:
            raise RuntimeError('Authenticated allocation rejected')
        address = attrs(response)[0x0016]
        port = struct.unpack_from('!H', address, 2)[0] ^ (COOKIE >> 16)
        mask = struct.pack('!I', COOKIE) + response[8:20]
        packed = bytes(value ^ mask[i] for i, value in enumerate(address[4:]))
        self.relay = (ipaddress.ip_address(packed), port)

    def bind(self, peer):
        transaction = os.urandom(12)
        address, port = peer.relay
        mask = struct.pack('!I', COOKIE) + transaction
        xor_address = bytes(value ^ mask[i] for i, value in enumerate(address.packed))
        encoded = bytes([0, 1 if address.version == 4 else 2]) + struct.pack('!H', port ^ (COOKIE >> 16)) + xor_address
        response = self.request(0x0009, attr(0x000C, struct.pack('!HH', 0x4001, 0)) + attr(0x0012, encoded), transaction=transaction)
        if struct.unpack_from('!H', response)[0] != 0x0109:
            raise RuntimeError('Channel binding rejected')

    def close(self):
        try:
            if self.key:
                self.request(0x0004, attr(0x000D, struct.pack('!I', 0)))
        finally:
            self.sock.close()

def probe(family, interval):
    peers = []
    result = {'family': 'IPv'+str(family), 'transport': 'TLS', 'intervalMs': interval, 'messagesPerEndpoint': 50,
              'hostnameVerified': True, 'startedAt': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    try:
        for _ in range(2):
            peer = TurnTLS(family)
            peers.append(peer)
            peer.allocate()
        peers[0].bind(peers[1])
        peers[1].bind(peers[0])
        for peer in peers: peer.read_sizes.clear()
        expected = [set(), set()]
        for sequence in range(50):
            for sender, peer in enumerate(peers):
                payload = struct.pack('!II', sender, sequence) + b'SYNTHETIC-TURN-PROBE'.ljust(92, b'.')
                expected[1-sender].add(payload)
                peer.sock.sendall(struct.pack('!HH', 0x4001, len(payload))+payload)
            if interval: time.sleep(interval / 1000)
        receives = []
        for index, peer in enumerate(peers):
            seen = set()
            for _ in range(50):
                frame = peer.frame()
                channel, size = struct.unpack_from('!HH', frame)
                if channel != 0x4001 or size != 100:
                    raise RuntimeError('Unexpected channel or synthetic payload length')
                seen.add(frame[4:4+size])
            receives.append({'receivedFrames': 50, 'uniquePayloads': len(seen), 'payloadsMatchExactly': seen == expected[index],
                'TLSReadChunkHistogram': dict(collections.Counter(peer.read_sizes)), 'remainingBufferedBytes': len(peer.buffer)})
        result.update({'sent': 100, 'received': sum(x['receivedFrames'] for x in receives), 'endpoints': receives,
                       'tlsVersions': [p.tls_version for p in peers], 'strictPass': all(x['payloadsMatchExactly'] for x in receives)})
    except Exception as error:
        result.update({'strictPass': False, 'errorType': type(error).__name__})
    finally:
        for peer in peers:
            try: peer.close()
            except Exception: pass
    result['finishedAt'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    return result

results = []
for family, interval in [(4, 0), (6, 0), (4, 20), (6, 20)]:
    result = probe(family, interval)
    results.append(result)
    print(json.dumps(result), flush=True)
report = {'probe': 'Independent Python TLS TURN client with buffered frame boundaries and exact synthetic-payload validation',
    'results': results, 'limits': 'A bounded synthetic relay test, not an audio call. No tokens, raw endpoints, payload bytes or provider response bodies are persisted.'}
(HERE/'turn-tls-framed-independent.json').write_text(json.dumps(report, indent=2)+'\n')
