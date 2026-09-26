"""Small synchronous client for Herdr's newline-delimited JSON socket API.

This module deliberately uses only the Python standard library. It opens one
Unix-domain socket connection per request, which is suitable for the short
request/response methods used by the Jira Peek highlight worker. Long-lived
event subscriptions use different connection
lifecycles and are not handled here.
"""

from __future__ import annotations

import errno
import json
import socket
import uuid
from typing import Any, Mapping


MAX_RESPONSE_BYTES = 32 * 1024 * 1024
_READ_CHUNK_BYTES = 64 * 1024


class HerdrSocketError(Exception):
    """Base class for errors raised by this module."""


class SocketPathMissingError(HerdrSocketError):
    """The configured Herdr socket path does not exist."""


class SocketTransportError(HerdrSocketError):
    """The Unix socket could not be reached or used."""


class RequestTimeoutError(SocketTransportError):
    """The socket operation exceeded its timeout."""


class ResponseTooLargeError(HerdrSocketError):
    """The server response exceeded the client's configured safety limit."""


class ProtocolError(HerdrSocketError):
    """The server returned an invalid or incomplete JSON protocol response."""


class HerdrAPIError(HerdrSocketError):
    """Herdr returned a structured API error response."""

    def __init__(self, code: str, message: str):
        self.code = code
        self.message = message
        # Keep exception text concise and avoid echoing arbitrary response data.
        super().__init__(f"Herdr API error: {code}")


def request(
    method: str,
    params: Mapping[str, Any] | None,
    socket_path: str,
    timeout: float,
) -> Any:
    """Call one Herdr raw socket method and return its ``result`` value.

    Raises a typed :class:`HerdrSocketError` subclass for transport, protocol,
    timeout, or server-reported API failures. ``method`` and ``params`` are
    serialized as JSON; this function does not log request or response data.
    """
    if not isinstance(method, str) or not method:
        raise ValueError("method must be a non-empty string")
    if params is None:
        params = {}
    if not isinstance(params, Mapping):
        raise TypeError("params must be a mapping or None")
    if not isinstance(socket_path, str) or not socket_path:
        raise ValueError("socket_path must be a non-empty string")
    if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or timeout <= 0:
        raise ValueError("timeout must be a positive number")

    request_id = uuid.uuid4().hex
    payload = {
        "id": request_id,
        "method": method,
        "params": dict(params),
    }
    try:
        encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8") + b"\n"
    except (TypeError, ValueError, UnicodeError) as exc:
        raise ValueError("request parameters must be JSON-serializable") from exc

    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        client.settimeout(float(timeout))
        try:
            client.connect(socket_path)
        except FileNotFoundError as exc:
            raise SocketPathMissingError("Herdr socket path does not exist") from exc
        except socket.timeout as exc:
            raise RequestTimeoutError("timed out connecting to Herdr socket") from exc
        except OSError as exc:
            if exc.errno == errno.ENOENT:
                raise SocketPathMissingError("Herdr socket path does not exist") from exc
            raise SocketTransportError("could not connect to Herdr socket") from exc

        try:
            client.sendall(encoded)
            response_bytes = _read_line(client)
        except socket.timeout as exc:
            raise RequestTimeoutError("timed out waiting for Herdr response") from exc
        except OSError as exc:
            raise SocketTransportError("socket I/O failed while requesting Herdr") from exc
    finally:
        client.close()

    return _parse_response(response_bytes, request_id)


def _read_line(client: socket.socket) -> bytes:
    """Read exactly the first JSON line, enforcing a bounded response size."""
    chunks: list[bytes] = []
    total = 0
    while True:
        # Read one byte beyond the remaining limit so oversized unterminated
        # messages are detected before they can grow the buffer indefinitely.
        remaining = MAX_RESPONSE_BYTES - total
        chunk = client.recv(min(_READ_CHUNK_BYTES, remaining + 1))
        if not chunk:
            if not chunks:
                raise ProtocolError("Herdr closed the socket without a response")
            raise ProtocolError("Herdr response ended before its newline delimiter")
        newline = chunk.find(b"\n")
        content = chunk if newline < 0 else chunk[:newline]
        total += len(content)
        if total > MAX_RESPONSE_BYTES:
            raise ResponseTooLargeError("Herdr response exceeded the size limit")
        chunks.append(content)
        if newline >= 0:
            return b"".join(chunks)


def _parse_response(response_bytes: bytes, request_id: str) -> Any:
    """Validate one standard Herdr request/response envelope."""
    try:
        response_text = response_bytes.decode("utf-8")
        response = json.loads(response_text)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ProtocolError("Herdr returned malformed JSON") from exc

    if not isinstance(response, dict):
        raise ProtocolError("Herdr response must be a JSON object")
    if response.get("id") != request_id:
        raise ProtocolError("Herdr response id did not match request")

    has_result = "result" in response
    has_error = "error" in response
    if has_result == has_error:
        raise ProtocolError("Herdr response must contain exactly one of result or error")

    if has_error:
        error = response["error"]
        if not isinstance(error, dict):
            raise ProtocolError("Herdr error response must be an object")
        code = error.get("code")
        message = error.get("message")
        if not isinstance(code, str) or not code or not isinstance(message, str):
            raise ProtocolError("Herdr error response is missing code or message")
        raise HerdrAPIError(code, message)

    return response["result"]
