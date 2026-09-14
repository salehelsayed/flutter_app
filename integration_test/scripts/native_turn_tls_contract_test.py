#!/usr/bin/env python3
"""Host refusal controls for native proof acceptance and isolated DNS."""

import copy
import ipaddress
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

if not __package__:
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from integration_test.scripts.run_mixed_policy_native_audio import endpoints_pass, emulator_turn_socket_families, emulator_turn_packet_families
from integration_test.scripts.turn_tls_dns_fixture import answer


class NativeTurnTlsContractTest(unittest.TestCase):
    def endpoints(self):
        phases = []
        for caller in [0, 1]:
            for generation in [0, 1]:
                phases.append({'case': f'relayOnly-relayOnly-{caller}', 'generation': generation,
                               'policy': 'relayOnly', 'bidirectionalRtpAdvanced': True,
                               'secureTransportReady': True, 'localUsesTurn': True,
                               'localRelayProtocol': 'tls', 'relatedAddressesSanitized': True,
                               'sdpAndCandidatePrivacyChecked': True})
        return [{'passed': True, 'closedCalls': 2, 'phases': copy.deepcopy(phases)} for _ in [0, 1]]

    def accepted(self, endpoints):
        return endpoints_pass(endpoints, relay_only=True, transport='tls')

    def test_requires_both_receipts_exact_cases_restart_media_and_hangup(self):
        self.assertTrue(self.accepted(self.endpoints()))
        for mutation in ('missing', 'device-failed', 'duplicate', 'no-restart', 'no-media', 'no-hangup'):
            with self.subTest(mutation=mutation):
                endpoints = self.endpoints()
                if mutation == 'missing': endpoints[1] = None
                if mutation == 'device-failed': endpoints[1]['passed'] = False
                if mutation == 'duplicate': endpoints[1]['phases'][-1] = endpoints[1]['phases'][0]
                if mutation == 'no-restart': endpoints[1]['phases'].pop()
                if mutation == 'no-media': endpoints[1]['phases'][0]['bidirectionalRtpAdvanced'] = False
                if mutation == 'no-hangup': endpoints[1]['closedCalls'] = 1
                self.assertFalse(self.accepted(endpoints))

    def test_generic_tcp_dtls_or_remote_relay_cannot_certify_tls(self):
        for field, value in [('localRelayProtocol', None), ('localRelayProtocol', 'tcp'),
                             ('localRelayProtocol', 'turnTcpTls'), ('localUsesTurn', False),
                             ('policy', 'all'), ('sdpAndCandidatePrivacyChecked', False)]:
            with self.subTest(field=field, value=value):
                endpoints = self.endpoints()
                endpoints[0]['phases'][0][field] = value
                self.assertFalse(self.accepted(endpoints))

    def test_negative_requires_specific_rejections_on_both_endpoints_and_no_media(self):
        endpoints = [{'passed': True, 'closedCalls': 2, 'phases': [], 'negativeControls': [
            {'rejected': True, 'reason': 'hostname'} for _ in [0, 1]]} for _ in [0, 1]]
        self.assertTrue(endpoints_pass(endpoints, relay_only=True, transport='tls', rejection='hostname'))
        endpoints[1]['negativeControls'][0]['reason'] = 'timeout'
        self.assertFalse(endpoints_pass(endpoints, relay_only=True, transport='tls', rejection='hostname'))

    def test_dns_cannot_return_an_alternate_connection_family(self):
        for version in [4, 6]:
            address = ipaddress.ip_address('192.0.2.10' if version == 4 else '2001:db8::10')
            for query_type in [1, 28]:
                packet = b'\x71\x23' + struct.pack('!HHHHH', 0x0100, 1, 0, 0, 0)
                packet += b'\x04turn\x07invalid\x00' + struct.pack('!HH', query_type, 1)
                response, matched = answer(packet, 'turn.invalid', address)
                self.assertEqual(matched, query_type == (1 if version == 4 else 28))
                self.assertEqual(struct.unpack('!H', response[6:8])[0], int(matched))
                if matched: self.assertTrue(response.endswith(address.packed))

    @patch('integration_test.scripts.run_mixed_policy_native_audio.subprocess.check_output')
    @patch('integration_test.scripts.run_mixed_policy_native_audio.subprocess.run')
    def test_socket_family_uses_the_remote_socket_not_local_or_candidate_addresses(self, run, processes):
        processes.return_value = '123 1 /sdk/qemu-system-aarch64\n124 123 /sdk/netsimd\n125 999 /sdk/netsimd\n'
        run.return_value.stdout = ('p123\nft1\nn192.0.2.4:12000->[2001:db8::3]:5349\n')
        self.assertEqual(emulator_turn_socket_families(123, 5349), {'ipv6'})
        self.assertIn('123,124', run.call_args.args[0])
        run.return_value.stdout += 'nn127.0.0.1:12001->192.0.2.5:5349\n'
        self.assertEqual(emulator_turn_socket_families(123, 5349), {'ipv4', 'ipv6'})
        run.return_value.stdout = ''
        self.assertEqual(emulator_turn_socket_families(123, 5349), set())
        processes.return_value = '123 1 /unrelated/process\n'
        with self.assertRaises(RuntimeError): emulator_turn_socket_families(123, 5349)

    def packet_capture(self, records):
        data = struct.pack('<IHHIIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1)
        for family, outgoing, stamp, media, port in records:
            payload = struct.pack('!HH', 0x4001, 12) + b'\x80' + bytes(11) if media else bytes(20)
            udp = struct.pack('!HHHH', 43000 if outgoing else port, port if outgoing else 43000,
                              8 + len(payload), 0) + payload
            ip = bytearray(20 if family == 4 else 40)
            ip[0] = 0x45 if family == 4 else 0x60
            ip[9 if family == 4 else 6] = 17
            packet = bytes(12) + struct.pack('!H', 0x0800 if family == 4 else 0x86dd) + ip + udp
            data += struct.pack('<IIII', stamp, 0, len(packet), len(packet)) + packet
        return data

    @patch('integration_test.scripts.run_mixed_policy_native_audio.time.time', return_value=200)
    @patch('integration_test.scripts.run_mixed_policy_native_audio.subprocess.check_output')
    def test_udp_packet_proof_requires_recent_bidirectional_media_at_turn_port(self, command, clock):
        with tempfile.TemporaryDirectory() as directory:
            capture = Path(directory) / 'owned.pcap'
            command.return_value = f'/sdk/qemu-system-aarch64 -tcpdump {capture.resolve()}'
            good = [(4, True, 199, True, 3478), (4, False, 199, True, 3478)]
            capture.write_bytes(self.packet_capture(good))
            self.assertEqual(emulator_turn_packet_families(123, capture, 3478), {'ipv4'})
            for bad in (good[:1], [(4, True, 100, True, 3478), (4, False, 100, True, 3478),
                                  (4, True, 199, False, 3478)],
                        [(4, True, 199, False, 3478), (4, False, 199, False, 3478)],
                        [(4, True, 199, True, 5353), (4, False, 199, True, 5353)]):
                capture.write_bytes(self.packet_capture(bad))
                self.assertEqual(emulator_turn_packet_families(123, capture, 3478), set())
            # A different QEMU timestamp epoch does not invalidate fresh media.
            capture.write_bytes(self.packet_capture([(4, True, 10, True, 3478), (4, False, 10, True, 3478)]))
            os.utime(capture, (200, 200))
            self.assertEqual(emulator_turn_packet_families(123, capture, 3478), {'ipv4'})
            os.utime(capture, (100, 100))
            self.assertEqual(emulator_turn_packet_families(123, capture, 3478), set())

    @patch('integration_test.scripts.run_mixed_policy_native_audio.time.time', return_value=200)
    @patch('integration_test.scripts.run_mixed_policy_native_audio.subprocess.check_output')
    def test_udp_packet_proof_preserves_mixed_family_and_owner_ambiguity(self, command, clock):
        with tempfile.TemporaryDirectory() as directory:
            capture = Path(directory) / 'owned.pcap'
            command.return_value = f'/sdk/qemu-system-aarch64 -tcpdump {capture.resolve()}'
            records = [(family, outgoing, 199, True, 3478) for family in (4,6) for outgoing in (True,False)]
            capture.write_bytes(self.packet_capture(records))
            self.assertEqual(emulator_turn_packet_families(123, capture, 3478), {'ipv4', 'ipv6'})
            command.return_value = '/sdk/qemu-system-aarch64 -tcpdump /different/owner.pcap'
            with self.assertRaises(RuntimeError): emulator_turn_packet_families(123, capture, 3478)
            command.return_value = '/sdk/qemu-system-aarch64 -tcpdump'
            with self.assertRaises(RuntimeError): emulator_turn_packet_families(123, capture, 3478)


if __name__ == '__main__':
    unittest.main()
