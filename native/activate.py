#!/usr/bin/env python3
"""Use Herdr's live handoff from a shell inside the intended session."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from highlight_socket import request, HerdrSocketError


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    parser.add_argument('--rollback', action='store_true')
    args = parser.parse_args()
    sock = os.environ.get('HERDR_SOCKET_PATH')
    if os.environ.get('HERDR_ENV') != '1' or not sock:
        parser.error('run this inside the intended Herdr session')
    if 'herdr-dev' in Path(sock).parts:
        parser.error('activate from a release session; debug builds use different socket paths')
    binary = args.binary.resolve(strict=True)
    version = subprocess.check_output([str(binary), '--version'], text=True).strip()
    if version != 'herdr 0.9.1':
        parser.error('this patch and handoff helper are scoped to Herdr 0.9.1')
    if not args.rollback:
        schema = subprocess.check_output([str(binary), 'api', 'schema', '--json'], text=True)
        if 'pane.highlight.set' not in schema:
            parser.error('target binary lacks the native highlight API')
    ping = request('ping', {}, sock, 3)
    if ping.get('version') != '0.9.1' or ping.get('protocol') != 22:
        parser.error('running server must be version 0.9.1, protocol 22')
    if not (ping.get('capabilities') or {}).get('live_handoff'):
        parser.error('running server does not advertise live handoff')
    print('Switching the server while preserving terminal processes...', flush=True)
    request('server.live_handoff', {
        'import_exe': str(binary), 'expected_protocol': 22, 'expected_version': '0.9.1',
    }, sock, 30)
    deadline = time.monotonic() + 15
    while True:
        try:
            request('ping', {}, sock, 2)
            if not args.rollback:
                # A fresh owner and nonexistent terminal make this a harmless probe.
                request('pane.highlight.clear', {'terminal_id': 'capability-probe', 'owner': uuid.uuid4().hex}, sock, 2)
            break
        except HerdrSocketError:
            if time.monotonic() >= deadline:
                raise SystemExit('Server capability could not be verified; inspect Herdr before retrying.')
            time.sleep(.25)
    print('Server switched. Reconnect Herdr, then reopen Peek to use the current highlighting backend.')

if __name__ == '__main__':
    try:
        main()
    except HerdrSocketError as error:
        raise SystemExit(f'Handoff failed ({type(error).__name__}); the server was not verified.')
