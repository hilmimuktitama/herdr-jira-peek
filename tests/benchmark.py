#!/usr/bin/env python3
"""Optional helper benchmark using synthetic tickets and no Jira connection.

Each sample includes process startup. These are helper timings, not key-to-screen
latency. Varying cache size exposes per-ticket work in navigation callbacks.
"""

import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile
import time


def measure(command, env, key_file):
    samples = []
    for sample in range(11):
        # Force an actual selection change, even on repeated invocations.
        key_file.write_text("ABC-999\n")
        started = time.perf_counter()
        subprocess.run(
            command, env=env, stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE, check=True,
        )
        elapsed = (time.perf_counter() - started) * 1000
        if sample:  # Exclude the initial warmup.
            samples.append(elapsed)
    return {
        "median_ms": round(statistics.median(samples), 1),
        "max_ms": round(max(samples), 1),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument(
        "--legacy-focus", action="store_true",
        help="Compare a checkout using open-browser.sh --select",
    )
    args = parser.parse_args()
    scripts = args.root.resolve() / "scripts"
    results = []
    with tempfile.TemporaryDirectory(prefix="peek-bench-") as temporary:
        base = Path(temporary)
        for directory in ("config", "state/cache", "viewer/rows", "viewer/failed",
                          "state/sources/source-source-terminal"):
            (base / directory).mkdir(parents=True, exist_ok=True)
        fake_twg = base / "twg"
        fake_twg.write_text("#!/bin/sh\nexit 97\n")
        fake_twg.chmod(0o700)
        (base / "config/config.sh").write_text(
            'JIRA_BASE="https://jira.example.test"\nJIRA_SITE="jira-example"\n'
            'JIRA_PROJECTS="ABC"\nCACHE_TTL_MIN=10\nMAX_CANDIDATES=20\n'
        )
        key_file = base / "state/sources/source-source-terminal/key"
        env = {
            **os.environ,
            "HERDR_PLUGIN_CONFIG_DIR": str(base / "config"),
            "HERDR_PLUGIN_STATE_DIR": str(base / "state"),
            "VIEWER_STATE_DIR": str(base / "viewer"),
            "VIEWER_KEY_FILE": str(key_file),
            "HERDR_SOCKET_PATH": "",
            "HERDR_VIEWER_SOURCE_TERMINAL": "source-terminal",
            "FZF_PREVIEW_COLUMNS": "96", "FZF_COLUMNS": "100", "FZF_LINES": "40",
            "VIEWER_HAS_FOOTER": "1", "VIEWER_MODERN_FOOTER": "1", "NO_COLOR": "1",
            "DIR": str(scripts), "TWG_BIN_PATH": str(fake_twg),
        }
        focus = ["open-browser.sh", "--select"] if args.legacy_focus else ["viewer-ui.sh", "focus"]
        commands = {
            "select": ["sh", str(scripts / focus[0]), focus[1], "ABC-1"],
            "preview": ["sh", str(scripts / "viewer-preview.sh"), "ABC-1"],
            "dismiss": ["sh", str(scripts / "viewer-ui.sh"), "dismiss-message"],
            "footer": ["sh", str(scripts / "viewer-rows.sh"), "footer"],
        }
        for count in (1, 20, 100):
            (base / "viewer/candidates").write_text(
                "".join(f"ABC-{i}\n" for i in range(1, count + 1))
            )
            for i in range(1, count + 1):
                (base / f"state/cache/ABC-{i}.json").write_text(json.dumps({
                    "key": f"ABC-{i}", "summary": "Cached ticket",
                    "description": "A small description.\n" * 20,
                    "status": {"name": "Done"},
                }))
                (base / f"viewer/rows/ABC-{i}").write_text(f"ABC-{i}\tDone\tCached ticket\n")
            for name, command in commands.items():
                results.append({
                    "cached_issues": count, "operation": name,
                    **measure(command, env, key_file),
                })
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
