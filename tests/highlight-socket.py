#!/usr/bin/env python3
"""Focused offline tests for scripts/highlight_socket.py."""

from __future__ import annotations

import json
import os
import socket
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import highlight_socket as herdr_socket  # noqa: E402


class FakeHerdrSocket:
    """One-request Unix socket server with fully fictional payloads."""

    def __init__(self, reply, *, delay=0, raw_reply=None):
        self.temp_dir = tempfile.TemporaryDirectory(prefix="peek-socket-test-")
        self.path = os.path.join(self.temp_dir.name, "herdr.sock")
        self.reply = reply
        self.delay = delay
        self.raw_reply = raw_reply
        self.request = None
        self.error = None
        self.ready = threading.Event()
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()
        if not self.ready.wait(2):
            raise RuntimeError("fake server did not start")

    def _serve(self):
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            listener.bind(self.path)
            listener.listen(1)
            self.ready.set()
            connection, _ = listener.accept()
            with connection:
                data = bytearray()
                while b"\n" not in data:
                    chunk = connection.recv(4096)
                    if not chunk:
                        raise AssertionError("client closed before sending request")
                    data.extend(chunk)
                self.request = json.loads(bytes(data).split(b"\n", 1)[0])
                if self.delay:
                    time.sleep(self.delay)
                if self.raw_reply is not None:
                    connection.sendall(self.raw_reply)
                else:
                    response = self.reply(self.request)
                    connection.sendall(json.dumps(response).encode("utf-8") + b"\n")
        except (BrokenPipeError, ConnectionResetError):
            # Expected when the client times out or rejects an oversized line.
            pass
        except Exception as exc:  # Surface thread errors in the test thread.
            self.error = exc
            self.ready.set()
        finally:
            listener.close()

    def close(self):
        self.thread.join(timeout=2)
        self.temp_dir.cleanup()
        if self.error:
            raise self.error


class HighlightSocketTests(unittest.TestCase):
    def run_request(self, server, method="pane.graphics.info", params=None, timeout=1):
        try:
            return herdr_socket.request(method, params, server.path, timeout)
        finally:
            server.close()

    def test_success_returns_result_and_sends_ndjson_request(self):
        server = FakeHerdrSocket(lambda req: {
            "id": req["id"],
            "result": {"type": "pane_graphics_info", "pane_visible": True},
        })
        result = self.run_request(server, params={"pane_id": "w-fictional:p1"})
        self.assertEqual(result, {"type": "pane_graphics_info", "pane_visible": True})
        self.assertEqual(server.request["method"], "pane.graphics.info")
        self.assertEqual(server.request["params"], {"pane_id": "w-fictional:p1"})
        self.assertTrue(server.request["id"])

    def test_server_error_is_typed_and_message_is_available_as_attribute(self):
        server = FakeHerdrSocket(lambda req: {
            "id": req["id"],
            "error": {"code": "feature_disabled", "message": "graphics disabled"},
        })
        with self.assertRaises(herdr_socket.HerdrAPIError) as caught:
            self.run_request(server)
        self.assertEqual(caught.exception.code, "feature_disabled")
        self.assertEqual(caught.exception.message, "graphics disabled")

    def test_missing_socket_has_specific_error(self):
        with tempfile.TemporaryDirectory(prefix="peek-missing-socket-") as directory:
            missing = os.path.join(directory, "absent.sock")
            with self.assertRaises(herdr_socket.SocketPathMissingError):
                herdr_socket.request("pane.get", {}, missing, 0.2)

    def test_malformed_response_is_protocol_error(self):
        server = FakeHerdrSocket(None, raw_reply=b"{not-json}\n")
        with self.assertRaises(herdr_socket.ProtocolError):
            self.run_request(server)

    def test_truncated_response_is_protocol_error(self):
        server = FakeHerdrSocket(None, raw_reply=b'{"id":"fictional"}')
        with self.assertRaises(herdr_socket.ProtocolError):
            self.run_request(server)

    def test_mismatched_response_id_is_rejected(self):
        server = FakeHerdrSocket(lambda req: {"id": "other-id", "result": {}})
        with self.assertRaises(herdr_socket.ProtocolError):
            self.run_request(server)

    def test_timeout_is_typed(self):
        server = FakeHerdrSocket(lambda req: {"id": req["id"], "result": {}}, delay=0.15)
        with self.assertRaises(herdr_socket.RequestTimeoutError):
            self.run_request(server, timeout=0.03)
        server.close()

    def test_oversized_response_is_rejected(self):
        server = FakeHerdrSocket(None, raw_reply=b"x" * (herdr_socket.MAX_RESPONSE_BYTES + 1) + b"\n")
        with self.assertRaises(herdr_socket.ResponseTooLargeError):
            self.run_request(server)

if __name__ == "__main__":
    unittest.main(verbosity=2)
