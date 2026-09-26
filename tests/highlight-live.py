#!/usr/bin/env python3
"""Opt-in native Herdr PTY test. Uses pyte to verify actual ANSI cell styles.

Run with HERDR_NATIVE_TEST_BIN pointing to the patched binary. Only fictional data
and isolated config/state are used. Also visually test the target terminal.
"""
import fcntl
import importlib.util
import os
from pathlib import Path
import pty
import re
import select
import shutil
import signal
import struct
import sys
import tempfile
import termios
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from highlight_socket import request

spec = importlib.util.spec_from_file_location("highlight", ROOT / "scripts/viewer-highlight.py")
highlight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(highlight)
HERDR = os.environ.get("HERDR_NATIVE_TEST_BIN") or shutil.which("herdr")
try:
    import pyte
except ImportError:
    pyte = None


@unittest.skipUnless(HERDR and pyte, "install Herdr to run the live renderer regression")
class LiveHighlightTest(unittest.TestCase):
    def test_native_cells_follow_selection_redraw_alt_screen_and_expire(self):
        with tempfile.TemporaryDirectory(prefix="peek-live-", dir="/tmp") as tmp:
            base = Path(tmp)
            config = base / "herdr"
            config.mkdir()
            (config / "config.toml").write_text(
                'onboarding = false\n[terminal]\ndefault_shell = "/bin/sh"\n'
                'shell_mode = "non_login"\n')
            debug_config = base / "herdr-dev"
            debug_config.mkdir()
            shutil.copy(config / "config.toml", debug_config / "config.toml")
            class Screen(pyte.Screen):
                def report_device_status(self, *args, **kwargs): pass
                def report_device_attributes(self, *args, **kwargs): pass
            screen = Screen(140, 40)
            stream = pyte.ByteStream(screen)
            env = {k: v for k, v in os.environ.items()
                   if not k.startswith(("HERDR_", "XDG_"))
                   and k not in {"ENV", "BASH_ENV", "ZDOTDIR"}}
            env.update(XDG_CONFIG_HOME=tmp, XDG_STATE_HOME=str(base / "state"),
                       TERM="xterm-256color", SHELL="/bin/sh")
            pid, fd = pty.fork()
            if pid == 0:
                os.execve(HERDR, [HERDR], env)
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 140, 1400, 800))
            output = bytearray()
            socket_path = str(config / "herdr.sock")
            worker = None
            direct_pid = direct_fd = None
            direct_screen = Screen(140,40)
            direct_stream = pyte.ByteStream(direct_screen)

            def api(method, params=None):
                return request(method, params or {}, socket_path, 2)

            def pump(seconds=.1):
                end = time.monotonic() + seconds
                while time.monotonic() < end:
                    ready = select.select([fd] + ([direct_fd] if direct_fd is not None else []), [], [], .03)[0]
                    for ready_fd in ready:
                        try:
                            chunk = os.read(ready_fd, 65536)
                        except OSError:
                            return
                        if not chunk:
                            return
                        output.extend(chunk)
                        (stream if ready_fd == fd else direct_stream).feed(chunk)
                        # Answer terminal geometry probes; this is a PTY fixture,
                        # not the user's outer terminal or an attached GUI app.
                        if b"\x1b[6n" in chunk:
                            os.write(ready_fd, b"\x1b[1;1R")
                        if b"\x1b[16t" in chunk:
                            os.write(ready_fd, b"\x1b[6;20;10t")

            def until(predicate, message):
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    if predicate():
                        return
                    pump()
                self.fail(message)

            def marked(key, target=None):
                target = target or screen
                for row in target.buffer.values():
                    for start in range(target.columns-len(key)+1):
                        if ''.join(row[x].data for x in range(start,start+len(key))) == key and all(row[x].bg == 'ffbf35' for x in range(start,start+len(key))):
                            return True
                return False
            try:
                until(lambda: (config/'herdr.sock').exists() or (debug_config/'herdr.sock').exists(), 'server unavailable')
                if (debug_config/'herdr.sock').exists(): socket_path=str(debug_config/'herdr.sock')
                pump(1)
                pane=api('pane.list')['panes'][0];pane_id=pane['pane_id']
                source=base/'source.py';control=base/'screen-mode'
                control.write_text('normal')
                source.write_text("import pathlib,time\np=pathlib.Path("+repr(str(control))+")\nlast=''\nwhile True:\n mode=p.read_text()\n if mode!=last:\n  print(('\\x1b[?1049h' if mode=='alternate' else '')+'\\x1b[2J\\x1b[H'+('Updated 界 ' if mode!='normal' else 'Original ' )+'DEMO-1042 and DEMO-1038',flush=True)\n  last=mode\n time.sleep(.05)\n")
                import shlex
                api('pane.send_text',{'pane_id':pane_id,'text':shlex.quote(sys.executable)+' '+shlex.quote(str(source))+'\n'})
                pump(.5)
                state=base/'worker';state.mkdir()
                (state/'candidates').write_text('DEMO-1042\nDEMO-1038\n')
                (state/'highlight-request').write_text('DEMO-1042\n')
                worker=highlight.HighlightWorker(state,socket_path,pane_id,pane['terminal_id'])
                worker.tick();until(lambda:marked('DEMO-1042'),'native ANSI highlight missing')
                direct_pid,direct_fd=pty.fork()
                if direct_pid==0:
                    os.execve(HERDR,[HERDR,'terminal','attach',pane['terminal_id']],dict(env,HERDR_SOCKET_PATH=socket_path))
                fcntl.ioctl(direct_fd,termios.TIOCSWINSZ,struct.pack('HHHH',40,140,1400,800))
                until(lambda:marked('DEMO-1042',direct_screen),'direct terminal attach lost native highlight')
                worker.renew_at=0;worker.tick()
                before=api('pane.read',{'pane_id':pane_id,'source':'visible','format':'text'})['read']['text']
                (state/'highlight-request').write_text('DEMO-1038\n');worker.tick()
                until(lambda:marked('DEMO-1038') and not marked('DEMO-1042'),'selection failed to move')
                self.assertEqual(before,api('pane.read',{'pane_id':pane_id,'source':'visible','format':'text'})['read']['text'])
                control.write_text('alternate');pump(.3);worker.renew_at=0;worker.tick()
                until(lambda:marked('DEMO-1038') and any('Updated' in row for row in screen.display),'alternate-screen redraw lost highlight')
                worker.clear();until(lambda:not marked('DEMO-1038'),'clear did not restore source colors')
                worker.tick();until(lambda:marked('DEMO-1038'),'renew did not restore highlight')
                pump(2);self.assertFalse(marked('DEMO-1038'),'lease must expire without source output')
                # Identity/ownership checks are enforced by the native API.
                from highlight_socket import HerdrAPIError
                with self.assertRaises(HerdrAPIError):
                    api('pane.highlight.set',{'pane_id':pane_id,'terminal_id':'wrong-terminal','owner':'fixture-other','query':'DEMO-1042'})
                worker.renew_at=0;worker.tick()
                with self.assertRaises(HerdrAPIError):
                    api('pane.highlight.set',{'pane_id':pane_id,'terminal_id':pane['terminal_id'],'owner':'fixture-other','query':'DEMO-1042'})
                api('pane.highlight.clear',{'terminal_id':pane['terminal_id'],'owner':'wrong-owner'})
                pump(.2);self.assertTrue(marked('DEMO-1038'))
            finally:
                if worker: worker.clear()
                if direct_pid:
                    try:os.kill(direct_pid,signal.SIGKILL)
                    except ProcessLookupError:pass
                    os.waitpid(direct_pid,0);os.close(direct_fd);direct_fd=None
                try:api('server.stop')
                except Exception:pass
                pump(.2)
                try:os.kill(pid,signal.SIGKILL)
                except ProcessLookupError:pass
                os.waitpid(pid,0);os.close(fd)

if __name__=='__main__':unittest.main(verbosity=2)
