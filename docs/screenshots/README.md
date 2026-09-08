# Screenshot captures

Only entirely fictional data may appear in public screenshots. Never substitute
real issues, identities, tenant URLs, or source terminal output into these
fixtures, even with identifiers renamed or blurred.

The current default is shown in `workflow-bottom.png`, `picker-bottom.png`, and
`filtered-bottom.png`. These PNGs render terminal cells captured from the real
`scripts/viewer.sh` running in a 90-column, 24-row PTY. No layout setting is
provided, so the capture exercises the default bottom view.

`capture.py` uses temporary configuration, cached fictional `DEMO` issues, and
fake TWG and Herdr commands. It never connects to Jira or captures a work session.
The workflow image places a fictional source log beside the captured picker;
its outer labels and divider are an offline composition, not Herdr app chrome.

To regenerate from the repository root on macOS, use a Python environment with
`pyte` and `Pillow` installed, and ensure `fzf` and `jq` are on PATH:

```sh
python3 docs/screenshots/capture.py
```

The default font is macOS Menlo. Use `--font /path/to/monospace.ttf` to supply
another font. The script checks issue ordering, the bottom filter position, and
clean exit through Esc. Review every resulting PNG for readability before
updating the README. Screenshots may vary with the installed fzf version.

The older `picker.png`, `filtered.png`, `wide.png`, and `workflow.png` show the
optional top layout. `reader.png` shows the full issue reader, which is shared
by both layouts. All examples use fictional issues and identities.
