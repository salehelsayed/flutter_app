#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("fdc_s6_parse.py")
SPEC = importlib.util.spec_from_file_location("fdc_s6_parse", SCRIPT)
FDC = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(FDC)


def flow(event, details):
    return f"[FLOW] {json.dumps({'event': event, 'details': details})}\n"


class FdcS6ParserTest(unittest.TestCase):
    def write_trial(self, directory, name, lines):
        path = Path(directory) / name
        path.write_text("".join(lines), encoding="utf-8")
        return str(path)

    def test_trial_local_discovery_does_not_reclassify_older_logs(self):
        with tempfile.TemporaryDirectory() as directory:
            old = self.write_trial(
                directory,
                "old.log",
                [
                    flow(
                        "P2P_LAN_PEER_FOUND_REQUEST",
                        {"peer": "peer-a", "lanPrivateIp": False},
                    ),
                    flow(
                        "MSG_RECEIVED_TRANSPORT",
                        {"from": "peer-a", "transport": "direct"},
                    ),
                    flow(
                        "CHAT_MSG_DOUBLE_DELIVERY",
                        {"id": "old-msg", "kept": "direct", "dropped": "inbox"},
                    ),
                ],
            )
            current = self.write_trial(
                directory,
                "current.log",
                [
                    flow(
                        "P2P_LAN_PEER_FOUND_REQUEST",
                        {"peer": "peer-a", "lanPrivateIp": True},
                    ),
                    flow(
                        "MSG_RECEIVED_TRANSPORT",
                        {"from": "peer-a", "transport": "direct"},
                    ),
                ],
            )

            classified = FDC.classify_paths([old, current])

            self.assertEqual(classified["n"], 2)
            self.assertEqual(classified["lan_wins"], 1)
            self.assertEqual(len(classified["double_deliveries"]), 1)

    def test_stored_event_is_the_logical_denominator_and_kept_outcome(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_trial(
                directory,
                "parallel.log",
                [
                    flow(
                        "P2P_LAN_PEER_FOUND_REQUEST",
                        {"peer": "peer-a", "lanPrivateIp": True},
                    ),
                    flow(
                        "MSG_RECEIVED_TRANSPORT",
                        {"from": "peer-a", "transport": "direct"},
                    ),
                    flow(
                        "MSG_RECEIVED_TRANSPORT",
                        {"from": "peer-a", "transport": "wifi"},
                    ),
                    flow(
                        "CHAT_MSG_RECEIVE_STORED",
                        {"id": "msg-0001", "from": "peer-a", "transport": "direct"},
                    ),
                    flow(
                        "CHAT_MSG_DOUBLE_DELIVERY",
                        {"id": "msg-0001", "kept": "direct", "dropped": "wifi"},
                    ),
                    flow(
                        "CHAT_MSG_RECEIVE_STORED",
                        {"id": "msg-0002", "from": "peer-a", "transport": "inbox"},
                    ),
                ],
            )

            classified = FDC.classify_paths([path])

            self.assertEqual(classified["n"], 2)
            self.assertEqual(classified["n_legs"], 2)
            self.assertEqual(classified["lan_wins"], 1)
            self.assertEqual(classified["ws_wins"], 0)
            self.assertEqual(classified["failures"], 1)
            self.assertEqual(classified["bonsoir_fed_sends"], 2)
            self.assertEqual(len(classified["double_deliveries"]), 1)

    def test_wilson_rejects_an_impossible_tally(self):
        with self.assertRaisesRegex(ValueError, "successes must be between"):
            FDC.wilson_lb(2, 1)


if __name__ == "__main__":
    unittest.main()
