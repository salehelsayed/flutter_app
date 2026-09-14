"""Socket regressions for the independent TURN diagnostic, not app media."""
import hashlib
import hmac
import socket
import struct
import threading
import unittest
from unittest.mock import patch

from integration_test.scripts.turn_path_probe import CHANNEL, COOKIE, Frames, TurnProbe, attr, run_trial, require_isolated_namespace


def stun(transaction, kind=0x103, payload=b''):
    return struct.pack('!HHI', kind, len(payload), COOKIE) + transaction + payload


class TurnPathProbeTest(unittest.TestCase):
    def pair(self, kind=socket.SOCK_DGRAM):
        a, b = socket.socketpair(type=kind)
        for s in (a, b):
            s.settimeout(1)
            self.addCleanup(s.close)
        return a, b

    def test_udp_unpadded_non_aligned_payload_does_not_wait_for_next_datagram(self):
        sender, receiver = self.pair()
        frame = struct.pack('!HH', CHANNEL, 101) + b'x' * 101
        sender.send(frame)
        parser = Frames(receiver, True)
        self.assertEqual(parser.read(), frame)
        self.assertEqual(parser.buffer, b'')

    def test_udp_optional_padding_and_next_datagram_are_separate(self):
        sender, receiver = self.pair()
        first = struct.pack('!HH', CHANNEL, 9) + b'a' * 9
        second = struct.pack('!HH', CHANNEL, 11) + b'b' * 11
        sender.send(first + bytes(3))
        sender.send(second)
        parser = Frames(receiver, True)
        self.assertEqual(parser.read(), first)
        self.assertEqual(parser.read(), second)

    def test_truncated_udp_frame_cannot_consume_next_valid_datagram(self):
        sender, receiver = self.pair()
        sender.send(struct.pack('!HH', CHANNEL, 100) + b'truncated')
        valid = struct.pack('!HH', CHANNEL, 8) + b'complete'
        sender.send(valid)
        parser = Frames(receiver, True)
        with self.assertRaisesRegex(ValueError, 'invalid_channel_datagram'):
            parser.read()
        self.assertEqual(parser.read(), valid)

    def test_stream_requires_padding_and_preserves_coalesced_stun(self):
        sender, receiver = self.pair(socket.SOCK_STREAM)
        channel = struct.pack('!HH', CHANNEL, 9) + b'a' * 9 + bytes(3)
        control = stun(bytes(12))
        sender.sendall(channel[:2])
        sender.sendall(channel[2:] + control)
        parser = Frames(receiver, False)
        self.assertEqual(parser.read(), channel)
        self.assertEqual(parser.read(), control)

    def test_control_demultiplexes_late_response_and_preserves_media(self):
        server, client = self.pair()
        current, stale = b'c' * 12, b's' * 12
        server.send(struct.pack('!HH', CHANNEL, 8) + b'content!')
        server.send(stun(stale))
        server.send(stun(current))
        probe = TurnProbe(client, transport='udp', allocation_family=4, credentials={})
        self.assertEqual(probe.request(3, authenticated=False, transaction=current), stun(current))
        self.assertEqual(probe.receive_media(), b'content!')
        self.assertEqual(probe.stale_responses, 1)

    def test_control_retry_reuses_transaction_after_one_lost_request(self):
        server, client = self.pair()
        requests = []
        def respond():
            requests.append(server.recv(65536))
            requests.append(server.recv(65536))
            server.send(stun(requests[-1][8:20]))
        thread = threading.Thread(target=respond)
        thread.start()
        probe = TurnProbe(client, transport='udp', allocation_family=4, credentials={}, timeout=1.5)
        probe.request(3, authenticated=False)
        thread.join(timeout=1)
        self.assertFalse(thread.is_alive())
        self.assertEqual(requests[0], requests[1])
        self.assertEqual(probe.control_retransmissions, 1)

    def test_authenticated_matching_response_still_requires_valid_integrity(self):
        server, client = self.pair()
        probe = TurnProbe(client, transport='udp', allocation_family=4, credentials={})
        probe.key = b'synthetic-test-key'
        prefix = stun(b'x' * 12, payload=attr(0x0d, bytes(4)))
        prefix = prefix[:2] + struct.pack('!H', len(prefix) - 20 + 24) + prefix[4:]
        valid = prefix + attr(8, hmac.new(probe.key, prefix, hashlib.sha1).digest())
        probe.verify_integrity(valid)
        with self.assertRaisesRegex(ValueError, 'response_integrity'):
            probe.verify_integrity(valid[:-1] + bytes([valid[-1] ^ 1]))

    def test_failed_allocation_close_releases_socket_without_refresh(self):
        server, client = self.pair()
        probe = TurnProbe(client, transport='udp', allocation_family=6, credentials={})
        probe.close()
        self.assertEqual(client.fileno(), -1)

    def test_bounds_and_family_are_checked_before_network_io(self):
        for override in ({'count': 10000}, {'payload_size': 1400}, {'timeout': 8},
                         {'control_family': 6}, {'transport': 'tls'}):
            args = dict(server='127.0.0.1', port=1, control_family=4,
                        allocation_family=4, transport='udp', credentials={})
            args.update(override)
            with self.assertRaises(ValueError):
                run_trial(**args)

    def test_local_fixture_requires_linux_and_only_loopback(self):
        with patch('integration_test.scripts.turn_path_probe.os.uname') as uname, \
                patch('integration_test.scripts.turn_path_probe.socket.if_nameindex') as interfaces:
            uname.return_value.sysname = 'Linux'
            interfaces.return_value = [(1, 'lo')]
            require_isolated_namespace()
            interfaces.return_value = [(1, 'lo'), (2, 'ens5')]
            with self.assertRaisesRegex(ValueError, 'fixture_requires_linux_namespace'):
                require_isolated_namespace()
            uname.return_value.sysname = 'Darwin'
            interfaces.return_value = [(1, 'lo')]
            with self.assertRaisesRegex(ValueError, 'fixture_requires_linux_namespace'):
                require_isolated_namespace()


if __name__ == '__main__':
    unittest.main()
