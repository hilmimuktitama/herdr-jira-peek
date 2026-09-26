#!/usr/bin/env python3
"""Lease a native Herdr text decoration for the selected source-terminal key.

Matching happens inside Herdr on every rendered frame, including alternate-screen
coding agents. No terminal reads, input, graphics protocol, or geometry polling.
"""
from __future__ import annotations

import os
import re
import signal
import sys
import tempfile
import time
import uuid
from pathlib import Path
from typing import Any

from highlight_socket import HerdrAPIError, HerdrSocketError, request

POLL_SECONDS = 0.2
REQUEST_TIMEOUT = 0.8
KEY_RE = re.compile(r"[A-Z][A-Z0-9_]*-[0-9]+\Z")
UNSUPPORTED_NATIVE_CODES = frozenset({"unknown_method", "method_not_found", "invalid_request"})
DIAGNOSTIC_CODES = frozenset({"worker:unavailable"})

class HighlightUnavailable(Exception):
    """Source identity or native acknowledgement cannot be verified."""

def _object(value: Any, name: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise HighlightUnavailable(f"invalid {name}")
    return value


def _atomic_status(state: Path, value: str) -> None:
    """Publish only a fixed, content-free UI phrase in ephemeral viewer state."""
    if value and value not in {
        "Source: native highlight requires Herdr update",
        "Source: highlight unavailable",
    }:
        raise ValueError("unsupported highlight status")
    target = state / "highlight-status"
    if target.exists():
        try:
            if target.read_text(encoding="ascii") == (value + "\n" if value else ""):
                return
        except (OSError, UnicodeError):
            pass
    fd, temporary = tempfile.mkstemp(prefix=".highlight-status.", dir=state)
    try:
        with os.fdopen(fd, "w", encoding="ascii") as output:
            if value:
                output.write(value + "\n")
        os.replace(temporary, target)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def _atomic_diagnostic(state: Path, value: str) -> None:
    """Store a fixed code only; never include exception or source content."""
    if value and value not in DIAGNOSTIC_CODES:
        raise ValueError("unsupported highlight diagnostic")
    target = state / "highlight-diagnostic"
    if target.exists():
        try:
            if target.read_text(encoding="ascii") == (value + "\n" if value else ""):
                return
        except (OSError, UnicodeError):
            pass
    fd, temporary = tempfile.mkstemp(prefix=".highlight-diagnostic.", dir=state)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="ascii") as output:
            if value:
                output.write(value + "\n")
        os.replace(temporary, target)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def _selected_key(state: Path) -> str:
    path = state / "highlight-request"
    try:
        if path.is_symlink() or path.stat().st_size > 128:
            return ""
        key = path.read_text(encoding="ascii").rstrip("\n")
        if not KEY_RE.fullmatch(key):
            return ""
        candidates = (state / "candidates").read_text(encoding="ascii")
        return key if key in candidates.splitlines() else ""
    except (OSError, UnicodeError):
        return ""


class HighlightWorker:
    def __init__(self, state: Path, socket_path: str, pane_id: str, terminal_id: str):
        self.state = state
        self.socket_path = socket_path
        self.pane_id = pane_id
        self.terminal_id = terminal_id
        self.owner = uuid.uuid4().hex
        self.owner_pid = os.getppid()
        self.stop = False
        self.native_active = False
        self.native_unsupported = False
        self.renew_at = 0.0
        self.native_key = ""
        self.last_status: str | None = None
        self.last_diagnostic: str | None = None

    def api(self, method: str, params: dict[str, Any]) -> Any:
        return request(method, params, self.socket_path, REQUEST_TIMEOUT)

    def status(self, value: str) -> None:
        if value != self.last_status:
            _atomic_status(self.state, value)
            self.last_status = value

    def diagnostic(self, value: str) -> None:
        if value != self.last_diagnostic:
            _atomic_diagnostic(self.state, value)
            self.last_diagnostic = value

    def _pane(self, pane_id: str) -> dict[str, Any]:
        result = _object(self.api("pane.get", {"pane_id": pane_id}), "pane.get result")
        return _object(result.get("pane"), "pane.get pane")

    def resolve_pane(self) -> tuple[str, dict[str, Any]]:
        """Follow the stable source terminal, never a reused or focused pane ID."""
        try:
            pane = self._pane(self.pane_id)
            if pane.get("terminal_id") == self.terminal_id:
                return self.pane_id, pane
        except HerdrSocketError:
            pass
        workspaces = _object(self.api("workspace.list", {}), "workspace list").get("workspaces")
        if not isinstance(workspaces, list):
            raise HighlightUnavailable("workspace list unavailable")
        found: list[str] = []
        for workspace in workspaces:
            workspace_id = _object(workspace, "workspace").get("workspace_id")
            if not isinstance(workspace_id, str) or not workspace_id:
                raise HighlightUnavailable("invalid workspace id")
            panes = _object(self.api("pane.list", {"workspace_id": workspace_id}), "pane list").get("panes")
            if not isinstance(panes, list):
                raise HighlightUnavailable("pane list unavailable")
            for pane in panes:
                pane = _object(pane, "listed pane")
                if pane.get("terminal_id") == self.terminal_id:
                    candidate = pane.get("pane_id")
                    if not isinstance(candidate, str) or not candidate:
                        raise HighlightUnavailable("invalid resolved pane id")
                    found.append(candidate)
        if len(found) != 1:
            raise HighlightUnavailable("source terminal not uniquely available")
        self.pane_id = found[0]
        pane = self._pane(self.pane_id)
        if pane.get("terminal_id") != self.terminal_id:
            raise HighlightUnavailable("source terminal changed during resolution")
        return self.pane_id, pane

    def clear(self) -> None:
        if self.native_active:
            try:
                self.api("pane.highlight.clear", {
                    "terminal_id": self.terminal_id, "owner": self.owner,
                })
            except (HerdrSocketError, OSError):
                pass  # Server lease expires even if the clear cannot reach it.
        self.native_active = False
        self.native_key = ""
        self.renew_at = 0.0

    def tick(self) -> None:
        key = _selected_key(self.state)
        if not key:
            self.clear()
            self.status("")
            self.diagnostic("")
            return
        if self.native_unsupported:
            self.status("Source: native highlight requires Herdr update")
            return
        if key == self.native_key and time.monotonic() < self.renew_at:
            return
        try:
            pane_id, _pane = self.resolve_pane()
            if _selected_key(self.state) != key:
                return
            result = self.api("pane.highlight.set", {
                "pane_id": pane_id, "terminal_id": self.terminal_id,
                "owner": self.owner, "query": key,
            })
            if not isinstance(result, dict) or result.get("type") != "ok":
                raise HighlightUnavailable("invalid native acknowledgement")
            self.native_active = True
            self.native_key = key
            self.renew_at = time.monotonic() + 0.5
            if _selected_key(self.state) != key:
                self.clear()
                return
            self.status("")
            self.diagnostic("")
        except (HerdrSocketError, HighlightUnavailable, OSError) as error:
            self.clear()
            if isinstance(error, HerdrAPIError) and error.code in UNSUPPORTED_NATIVE_CODES:
                self.native_unsupported = True
                self.status("Source: native highlight requires Herdr update")
            else:
                self.status("Source: highlight unavailable")
            self.diagnostic("worker:unavailable")

    def run(self) -> None:
        try:
            while not self.stop and self.state.is_dir() and os.getppid() == self.owner_pid:
                self.tick()
                time.sleep(POLL_SECONDS)
        finally:
            self.clear()


def main() -> int:
    state_value = os.environ.get("VIEWER_STATE_DIR", "")
    socket_path = os.environ.get("HERDR_SOCKET_PATH", "")
    pane_id = os.environ.get("HERDR_VIEWER_SOURCE_PANE", "")
    terminal_id = os.environ.get("HERDR_VIEWER_SOURCE_TERMINAL", "")
    if not all((state_value, socket_path, pane_id, terminal_id)):
        return 2
    state = Path(state_value)
    if not state.is_dir():
        return 2
    worker = HighlightWorker(state, socket_path, pane_id, terminal_id)

    def stop(_number: int, _frame: Any) -> None:
        worker.stop = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    worker.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
