#!/usr/bin/env python3
"""Capture the real picker offline; requires fzf, jq, pyte, and Pillow.

The viewer runs in a PTY with private temporary config and fake TWG/Herdr.
PNG cells come from its terminal output, not a recreation of its layout.
"""

import argparse
import codecs
import copy
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import struct
import tempfile
import termios
import time

import pyte
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
COLS, ROWS = 90, 24
BG, FG = "#202124", "#dedfe3"
PALETTE = dict(black="#202124", red="#e07a7a", green="#85ca9b",
               brown="#dfb661", blue="#82aee3", magenta="#ca8bbb",
               cyan="#82c6cc", white=FG, brightblack="#9299a4",
               brightred="#f49d9d", brightgreen="#a6e4b8",
               brightbrown="#f6d284", brightblue="#accdf6",
               brightmagenta="#eab1db", brightcyan="#b5edf0", brightwhite="#ffffff")
ISSUES = [
    ("DEMO-1042", "Keep filters when navigating back", "In Progress",
     "Returning from a product should restore catalog filters and scroll position.\n\n"
     "Acceptance criteria\n"
     "- Keep the selected category and price range.\n"
     "- Restore the previous scroll position.\n"
     "- Support browser Back and the catalog link.",
     "Filter state now lives in the URL. Back navigation is covered."),
    ("DEMO-1038", "Add an empty-results state", "In Review",
     "When no products match, explain why the catalog is empty.\n\n"
     "Acceptance criteria\n"
     "- Keep the active filters visible.\n"
     "- Offer a clear way to reset the filters.",
     "The empty state now includes a Reset filters action."),
    ("DEMO-1026", "Cache catalog thumbnails", "Done",
     "Reuse thumbnails when returning to the catalog.", "Verified with the sample catalog."),
    ("DEMO-1019", "Add keyboard navigation", "To Do",
     "Allow keyboard navigation between product cards.", "Use a visible focus indicator."),
]


def fixtures(base):
    config, state, bin_dir = (base / name for name in ("config", "state", "bin"))
    for path in (config, state / "cache", bin_dir):
        path.mkdir(parents=True, mode=0o700)
    # Omit PICKER_LAYOUT deliberately: these screenshots verify the default.
    (config / "config.sh").write_text(
        "JIRA_BASE='https://jira.example.test'\nJIRA_SITE='jira-example'\n"
        "JIRA_PROJECTS='DEMO'\nCACHE_TTL_MIN=10\nMAX_CANDIDATES=20\n")
    (state / "candidates").write_text("\n".join(issue[0] for issue in ISSUES) + "\n")
    metadata = []
    for key, summary, status, description, comment in ISSUES:
        issue = dict(key=key, summary=summary, status={"name": status},
                     assignee={"displayName": "Alex Example"}, updated="2026-09-08T09:30:00Z",
                     description=description, comments=[dict(author={"displayName": "Sam Sample"},
                     created="2026-09-08T10:15:00Z", body=comment)])
        (state / "cache" / f"{key}.json").write_text(json.dumps(issue))
        metadata.append(dict(input=key, ok=True, data=issue))
    (base / "metadata.json").write_text(json.dumps({"data": {"items": metadata}}))
    (bin_dir / "twg").write_text(
        '#!/bin/sh\ncase " $* " in\n'
        '  *" --fields "*) cat "$CAPTURE_FIXTURES/metadata.json"; exit 0;;\nesac\nexit 1\n')
    (bin_dir / "herdr").write_text("#!/bin/sh\nexit 1\n")
    for path in bin_dir.iterdir():
        path.chmod(0o700)
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("HERDR_", "VIEWER_", "FZF_", "TWG_"))
           and key not in ("NO_COLOR", "FORCE_COLOR", "CLICOLOR_FORCE")}
    env.update(PATH=f"{bin_dir}:{os.environ['PATH']}", TERM="xterm-256color",
               COLUMNS=str(COLS), LINES=str(ROWS), SHELL="/bin/sh",
               HERDR_PLUGIN_CONFIG_DIR=str(config), HERDR_PLUGIN_STATE_DIR=str(state),
               TWG_BIN_PATH=str(bin_dir / "twg"), HERDR_BIN_PATH=str(bin_dir / "herdr"),
               CAPTURE_FIXTURES=str(base))
    return env


def capture(env):
    pid, fd = pty.fork()
    if pid == 0:
        os.execve("/bin/sh", ["sh", str(ROOT / "scripts/viewer.sh")], env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
    screen = pyte.Screen(COLS, ROWS)
    stream = pyte.Stream(screen)
    decoder = codecs.getincrementaldecoder("utf-8")("replace")
    pending = ""

    def settle(expected):
        nonlocal pending
        deadline, last_output = time.monotonic() + 15, time.monotonic()
        while time.monotonic() < deadline:
            if select.select([fd], [], [], 0.05)[0]:
                chunk = os.read(fd, 65536)
                if not chunk:
                    raise RuntimeError("Viewer exited before capture")
                text = decoder.decode(chunk)
                pending += text
                # Respond to cursor-position queries as a terminal would.
                while "\x1b[6n" in pending:
                    pending = pending.replace("\x1b[6n", "", 1)
                    os.write(fd, f"\x1b[{screen.cursor.y + 1};{screen.cursor.x + 1}R".encode())
                pending = pending[-4:]
                stream.feed(text)
                last_output = time.monotonic()
            if expected in "\n".join(screen.display) and time.monotonic() - last_output > 0.8:
                return copy.deepcopy(screen)
        raise RuntimeError(f"Viewer did not settle on {expected!r}\n" + "\n".join(screen.display))

    try:
        initial = settle("Filter state now lives in the URL")
        positions = [next(y for y, line in enumerate(initial.display)
                          if line.startswith(("> ", "  ")) and key in line)
                     for key, *_ in ISSUES]
        assert positions == sorted(positions, reverse=True), "Newest issue is not at the bottom"
        assert "Filter >" in initial.display[-1], "Filter is not bottom anchored"
        os.write(fd, b"empty")
        filtered = settle("The empty state now includes a Reset filters action.")
        os.write(fd, b"\x1b")
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            child, status = os.waitpid(pid, os.WNOHANG)
            if child:
                assert os.waitstatus_to_exitcode(status) == 0, "Viewer failed on Esc"
                assert not list(Path(env["HERDR_PLUGIN_STATE_DIR"]).glob(".viewer.*")), "Viewer state remains"
                return initial, filtered
            if select.select([fd], [], [], 0.1)[0]:
                try:
                    os.read(fd, 65536)
                except OSError:
                    pass
        raise RuntimeError("Viewer did not exit on Esc")
    finally:
        try:
            os.killpg(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        os.close(fd)


def color(value, default):
    if value == "default":
        return default
    return PALETTE.get(value, "#" + value)


def draw_screen(draw, screen, x, y, font, bold):
    for row in range(screen.lines):
        for col in range(screen.columns):
            cell = screen.buffer[row][col]
            fg, bg = color(cell.fg, FG), color(cell.bg, BG)
            if cell.reverse:
                fg, bg = bg, fg
            px, py = x + col * 12, y + row * 27
            if bg != BG:
                draw.rectangle((px, py, px + 11, py + 26), fill=bg)
            draw.text((px, py), cell.data, font=bold if cell.bold else font, fill=fg)


def render(screen, name, title, font, bold, source=False):
    left_cols = 44 if source else 0
    gap = 32 if source else 0
    width = (screen.columns + left_cols) * 12 + 32 + gap
    image = Image.new("RGB", (width, screen.lines * 27 + 106), BG)
    draw = ImageDraw.Draw(image)
    draw.text((16, 12), title, font=font, fill=FG)
    label = "FICTIONAL DATA / OFFLINE"
    draw.text((width - 16 - draw.textlength(label, font=font), 12), label, font=font, fill=PALETTE["green"])
    draw.line((16, 47, width - 16, 47), fill="#45484e")
    offset = left_cols * 12 + gap
    if source:
        draw.text((16, 57), "Source terminal / catalog-demo", font=font, fill=PALETTE["cyan"])
        source_screen = pyte.Screen(left_cols, ROWS)
        source_stream = pyte.Stream(source_screen)
        lines = ["$ git log --oneline -4", "c4d5e6f DEMO-1019 Keyboard navigation",
                 "b3c4d5e DEMO-1026 Cache thumbnails", "a2b3c4d DEMO-1038 Empty results",
                 "f1a2b3c DEMO-1042 Preserve filters", "$ "]
        source_stream.feed(f"\x1b[{ROWS - len(lines) + 1};1H" + "\r\n".join(lines))
        draw_screen(draw, source_screen, 16, 88, font, bold)
        draw.line((offset, 57, offset, image.height - 16), fill="#45484e")
    draw.text((16 + offset, 57), "Peek for Jira / bottom layout", font=font, fill=PALETTE["green"])
    draw_screen(draw, screen, 16 + offset, 88, font, bold)
    image.save(OUT / name, optimize=True)
    print(f"Captured {name}: {image.width}x{image.height}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--font", type=Path, default=Path("/System/Library/Fonts/Menlo.ttc"))
    args = parser.parse_args()
    for command in ("fzf", "jq"):
        if not shutil.which(command):
            parser.error(f"{command} must be on PATH")
    font = ImageFont.truetype(str(args.font), 20)
    bold = ImageFont.truetype(str(args.font), 20, index=1 if args.font.suffix == ".ttc" else 0)
    with tempfile.TemporaryDirectory(prefix="peek-docs-") as directory:
        initial, filtered = capture(fixtures(Path(directory)))
    render(initial, "picker-bottom.png", "Default picker", font, bold)
    render(filtered, "filtered-bottom.png", "Filter and inspect", font, bold)
    render(initial, "workflow-bottom.png", "Peek for Jira / terminal context", font, bold, source=True)


if __name__ == "__main__":
    main()
