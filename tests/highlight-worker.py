#!/usr/bin/env python3
"""Native lease behavior using fictional terminals; no source reads or input."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('highlight', ROOT / 'scripts/viewer-highlight.py')
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)

class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.state = Path(self.tmp.name)
        (self.state/'candidates').write_text('DEMO-42\nDEMO-43\n')
        (self.state/'highlight-request').write_text('DEMO-42\n')
        self.calls = []
        self.pane = 'pane-a'
        self.terminal = 'fictional-terminal'
        self.error = None
        self.callback = None
        self.worker = h.HighlightWorker(self.state, '/fixture/socket', self.pane, self.terminal)
        self.worker.api = self.api
    def tearDown(self):
        self.tmp.cleanup()
    def api(self, method, params):
        self.calls.append((method, params))
        if method == 'pane.get':
            return {'pane': {'pane_id':params['pane_id'], 'terminal_id': self.terminal if params['pane_id']==self.pane else 'different-terminal'}}
        if method == 'workspace.list': return {'workspaces':[{'workspace_id':'w1'}]}
        if method == 'pane.list': return {'panes':[{'pane_id':self.pane, 'terminal_id':self.terminal}]}
        if method == 'pane.highlight.set':
            if self.error: raise self.error
            if self.callback: self.callback()
            return {'type':'ok'}
        if method == 'pane.highlight.clear': return {'type':'ok'}
        self.fail('worker must not read source text, send input, focus, or use graphics')
    def status(self): return (self.state/'highlight-status').read_text().strip()
    def test_native_set_and_owner_identity(self):
        self.worker.tick()
        self.assertEqual(self.status(), '')
        method, params = self.calls[-1]
        self.assertEqual(method, 'pane.highlight.set')
        self.assertEqual(params['terminal_id'], self.terminal)
        self.assertEqual(params['query'], 'DEMO-42')
        self.assertEqual(len(params['owner']), 32)
    def test_renew_is_throttled_but_selection_is_immediate(self):
        self.worker.tick(); count=len(self.calls)
        self.worker.tick(); self.assertEqual(len(self.calls),count)
        (self.state/'highlight-request').write_text('DEMO-43\n')
        self.worker.tick(); self.assertEqual(self.calls[-1][1]['query'],'DEMO-43')
        self.worker.renew_at=0;self.worker.tick()
        self.assertEqual(self.calls[-1][0],'pane.highlight.set')
    def test_clear_is_idempotent_and_owner_scoped(self):
        self.worker.tick();self.worker.clear();count=len(self.calls);self.worker.clear()
        self.assertEqual(len(self.calls),count)
        self.assertEqual(self.calls[-1],('pane.highlight.clear',{'terminal_id':self.terminal,'owner':self.worker.owner}))
    def test_worker_restart_has_different_owner(self):
        other=h.HighlightWorker(self.state,'/fixture/socket',self.pane,self.terminal)
        self.assertNotEqual(other.owner,self.worker.owner)
    def test_invalid_or_non_candidate_key_clears(self):
        self.worker.tick()
        (self.state/'highlight-request').write_text('DEMO-99\n')
        self.worker.tick();self.assertEqual(self.calls[-1][0],'pane.highlight.clear');self.assertEqual(self.status(),'')
    def test_symlink_request_is_rejected(self):
        (self.state/'highlight-request').unlink()
        (self.state/'highlight-request').symlink_to(self.state/'candidates')
        self.worker.tick();self.assertEqual(self.calls,[])
    def test_pane_move_follows_same_terminal(self):
        self.pane='pane-moved';self.worker.tick()
        self.assertEqual(self.calls[-1][1]['pane_id'],self.pane)
    def test_replacement_terminal_never_receives_highlight(self):
        self.terminal='replacement';self.worker.tick()
        self.assertFalse(any(m=='pane.highlight.set' for m,_ in self.calls))
        self.assertEqual(self.status(),'Source: highlight unavailable')
    def test_unsupported_does_not_claim_success_or_retry_graphics(self):
        self.error=h.HerdrAPIError('unknown_method','fictional')
        self.worker.tick();count=len(self.calls);self.worker.tick()
        self.assertEqual(len(self.calls),count)
        self.assertEqual(self.status(),'Source: native highlight requires Herdr update')
    def test_transient_failure_retries(self):
        self.error=h.HerdrSocketError('fictional');self.worker.tick()
        self.assertEqual(self.status(),'Source: highlight unavailable')
        self.error=None;self.worker.tick();self.assertTrue(self.worker.native_active)
    def test_selection_changed_during_set_is_cleared(self):
        self.callback=lambda:(self.state/'highlight-request').write_text('DEMO-43\n')
        self.worker.tick();self.assertEqual(self.calls[-1][0],'pane.highlight.clear')
    def test_status_and_diagnostic_never_echo_source(self):
        with self.assertRaises(ValueError): h._atomic_status(self.state,'private terminal content')
        with self.assertRaises(ValueError): h._atomic_diagnostic(self.state,'private error')

if __name__ == '__main__': unittest.main(verbosity=2)
