#!/usr/bin/env python3
"""Offline proof of the task-local sandbox socket adapter."""
import importlib.util
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest

SOURCE = Path(__file__).with_name("sandbox-relay.py")
spec = importlib.util.spec_from_file_location("sandbox_relay", SOURCE)
relay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(relay)


class RelayChecks(unittest.TestCase):
    def test_rejects_unimplemented_modes(self):
        for args in [["--version"], ["-", "PROXY:host:target:22"], ["TCP4-LISTEN:0,fork,reuseaddr,backlog=4096", "UNIX-CONNECT:/tmp/s"],
                     ["UNIX-LISTEN:/tmp/a,fork,reuseaddr", "TCP:remote:80,keepalive,keepidle=10,keepintvl=5,keepcnt=3"]]:
            with self.subTest(args=args), self.assertRaises(ValueError):
                relay.endpoints(args)

    def test_both_native_modes_roundtrip_and_half_close(self):
        with tempfile.TemporaryDirectory(prefix="harbor-relay-") as folder:
            unix = str(Path(folder) / "bridge.sock")
            with socket.socket() as target:
                target.bind(("127.0.0.1", 0)); target.listen()
                target_port = target.getsockname()[1]
                def echo():
                    for _ in range(2):
                        conn, _ = target.accept()
                        with conn:
                            data = bytearray()
                            while chunk := conn.recv(4096):
                                data.extend(chunk)
                            conn.sendall(bytes(data))
                worker = threading.Thread(target=echo, daemon=True); worker.start()
                outer = subprocess.Popen([sys.executable, str(SOURCE), f"UNIX-LISTEN:{unix},fork,reuseaddr",
                                          f"TCP:localhost:{target_port},keepalive,keepidle=10,keepintvl=5,keepcnt=3"], stderr=subprocess.PIPE)
                try:
                    deadline = time.monotonic() + 3
                    while not Path(unix).exists() and time.monotonic() < deadline:
                        time.sleep(.01)
                    with socket.socket() as choose:
                        choose.bind(("127.0.0.1", 0)); bridge_port = choose.getsockname()[1]
                    inner = subprocess.Popen([sys.executable, str(SOURCE), f"TCP4-LISTEN:{bridge_port},fork,reuseaddr,backlog=4096",
                                              f"UNIX-CONNECT:{unix}"], stderr=subprocess.PIPE)
                    try:
                        deadline = time.monotonic() + 3
                        while time.monotonic() < deadline:
                            with socket.socket() as choose:
                                try:
                                    choose.bind(("127.0.0.1", bridge_port))
                                except OSError:
                                    break
                            time.sleep(.01)
                        for payload in [b"harbor relay ready", b"a second connection"]:
                            with socket.create_connection(("127.0.0.1", bridge_port), timeout=3) as client:
                                client.sendall(payload); client.shutdown(socket.SHUT_WR)
                                self.assertEqual(client.recv(4096), payload)
                        worker.join(3); self.assertFalse(worker.is_alive())
                    finally:
                        inner.terminate(); inner.communicate(timeout=3)
                finally:
                    outer.terminate(); outer.communicate(timeout=3)


if __name__ == "__main__":
    unittest.main()
