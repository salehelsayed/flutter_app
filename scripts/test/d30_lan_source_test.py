"""The D30 LAN source serves one client and stops at its byte or time cap."""

import json
import os
import pathlib
import socket
import sys
import tempfile
import threading
import time
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "docker-ws"))
import d30_lan_source as source


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


class LanSourceTest(unittest.TestCase):
    def setUp(self):
        self.dir = pathlib.Path(tempfile.mkdtemp())
        self.file = self.dir / "synthetic.bin"
        self.file.write_bytes(os.urandom(1024 * 1024))
        self.log = self.dir / "log.jsonl"

    def run_server(self, **caps):
        port = free_port()
        result = {}
        thread = threading.Thread(target=lambda: result.setdefault(
            "rc", source.serve(str(self.file), port, str(self.log), "127.0.0.1", **caps)))
        thread.start()
        time.sleep(0.3)
        return port, thread, result

    def events(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def drain(self, port):
        received = 0
        with socket.create_connection(("127.0.0.1", port)) as client:
            while True:
                block = client.recv(65536)
                if not block:
                    return received
                received += len(block)

    def test_byte_cap_stops_the_transfer_exactly(self):
        port, thread, result = self.run_server(cap_bytes=300 * 1024)
        self.assertEqual(self.drain(port), 300 * 1024)
        thread.join(5)
        end = self.events()[-1]
        self.assertEqual((end["event"], end["bytes"], end["reason"]), ("end", 300 * 1024, "byte_cap"))
        self.assertEqual(result["rc"], 0)

    def test_whole_file_ends_with_file_end(self):
        port, thread, _ = self.run_server()
        self.assertEqual(self.drain(port), 1024 * 1024)
        thread.join(5)
        self.assertEqual(self.events()[-1]["reason"], "file_end")

    def test_only_one_client_is_served(self):
        port, thread, _ = self.run_server()
        self.drain(port)
        thread.join(5)
        with self.assertRaises(OSError):
            socket.create_connection(("127.0.0.1", port), timeout=1)

    def test_time_cap_stops_the_transfer(self):
        port, thread, _ = self.run_server(cap_seconds=0)
        self.assertEqual(self.drain(port), 0)
        thread.join(5)
        self.assertEqual(self.events()[-1]["reason"], "time_cap")

    def test_rate_cap_paces_the_transfer(self):
        port, thread, _ = self.run_server(rate_bits_per_second=8 * 1024 * 1024)
        started = time.monotonic()
        self.assertEqual(self.drain(port), 1024 * 1024)
        elapsed = time.monotonic() - started
        thread.join(5)
        self.assertGreaterEqual(elapsed, 0.9)
        self.assertLess(elapsed, 2.0)
        self.assertEqual(self.events()[-1]["reason"], "file_end")

    def test_rate_flag_is_parsed_in_megabits(self):
        self.assertEqual(source.rate_from_argv(["x", "f", "1", "l", "--rate-mbit", "50"]), 50_000_000)
        self.assertIsNone(source.rate_from_argv(["x", "f", "1", "l"]))

    def test_no_client_exits_with_3(self):
        port = free_port()
        rc = source.serve(str(self.file), port, str(self.log), "127.0.0.1", accept_timeout=0.5)
        self.assertEqual(rc, 3)
        self.assertEqual(self.events()[-1]["event"], "no_client")


if __name__ == "__main__":
    unittest.main()
