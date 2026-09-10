## What

One or two sentences on what changes.

## Why

Link the issue, or say what was broken or missing.

## Checklist

- [ ] One change per pull request
- [ ] `npm test` and `python3 -m unittest discover -s tests -p "*_test.py"` pass, with a test added or updated for every `Model.js`, `Icons.js`, or helper change
- [ ] `qmllint -I /usr/share/omarchy/shell -I . *.qml components/*.qml` is clean
- [ ] Checked by hand in a running Omarchy shell, after `omarchy restart shell`
- [ ] Nothing blocks the shell: no filesystem work outside the helper
- [ ] `README.md` updated if behaviour, settings, keys, or IPC changed, and `PROTOCOL.md` if the helper contract changed
- [ ] No code comments, no em dashes
- [ ] Commit messages are a single line
