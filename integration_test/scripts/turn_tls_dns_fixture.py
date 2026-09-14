#!/usr/bin/env python3
"""Loopback-published DNS for an owned emulator's TURN family isolation.

Run in a disposable container, publishing UDP 1053 to host loopback only (the
verified host uses [::1]:53), then start the owned emulator with -dns-server ::1
-no-snapshot. Disable emulator Wi-Fi/private DNS for a single virtual network;
save and restore those settings. No host or production DNS is edited. The
calling harness checks the native resolver and actual TURN egress sockets.
"""

import argparse
import ipaddress
import json
import signal
import socket
import struct


def answer(packet, hostname, address):
    if len(packet) < 12 or struct.unpack('!H', packet[4:6])[0] != 1:
        raise ValueError('Exactly one uncompressed DNS question required')
    offset, labels = 12, []
    while offset < len(packet) and packet[offset]:
        size = packet[offset]
        if size > 63 or offset + size + 1 > len(packet):
            raise ValueError('Invalid DNS name')
        labels.append(packet[offset + 1:offset + size + 1].decode('ascii'))
        offset += size + 1
    offset += 1
    if offset + 4 > len(packet):
        raise ValueError('Truncated DNS question')
    query_type, query_class = struct.unpack('!HH', packet[offset:offset + 4])
    name = '.'.join(labels).lower()
    kind = 1 if address.version == 4 else 28
    matches = name == hostname.lower() and query_type == kind and query_class == 1
    question = packet[12:offset + 4]
    # NODATA for the disallowed family, NXDOMAIN for unrelated names. This is
    # intentionally an isolated fixture, not a general purpose recursive DNS.
    flags = 0x8180 if name == hostname.lower() else 0x8183
    header = packet[:2] + struct.pack('!HHHHH', flags, 1, int(matches), 0, 0)
    result = header + question
    if matches:
        result += b'\xc0\x0c' + struct.pack('!HHIH', kind, 1, 1, len(address.packed)) + address.packed
    return result, matches


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--hostname', required=True)
    parser.add_argument('--address', required=True, type=ipaddress.ip_address)
    args = parser.parse_args()
    counts = {'answered': 0, 'noAnswer': 0, 'malformed': 0, 'family': f'ipv{args.address.version}'}
    server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    server.bind(('0.0.0.0', 1053))  # Container port; publish on host loopback only.
    server.settimeout(0.5)
    stopping = False

    def stop(*_):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    print('DNS fixture ready', flush=True)
    while not stopping:
        try:
            packet, client = server.recvfrom(4096)
            response, matches = answer(packet, args.hostname, args.address)
            counts['answered' if matches else 'noAnswer'] += 1
            server.sendto(response, client)
        except socket.timeout:
            pass
        except (ValueError, UnicodeError):
            counts['malformed'] += 1
    server.close()
    print(json.dumps(counts), flush=True)


if __name__ == '__main__':
    main()
