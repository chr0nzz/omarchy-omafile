# Contributing

## Setup

```bash
git clone https://github.com/chr0nzz/omarchy-omafile.git
cd omarchy-omafile
omarchy plugin add "$PWD" --enable
```

The plugin directory must be a real directory under `~/.config/omarchy/plugins/`, never a symlink, or the shell will not reload it.

The panel is declared `keepLoaded`, so QML changes do **not** hot reload. Run `omarchy restart shell` after every edit. `quickshell list --all` prints the instance id and `quickshell log -i <instance> -t 100` shows QML errors.

## Layout

| File | Role |
| --- | --- |
| `Service.qml` | One per session: settings, the helper process, transfers, bookmarks, drives, IPC |
| `BarWidget.qml` | The bar icon and its transfer ring |
| `Popup.qml` | The bar popup: places, drives, transfers, trash |
| `Window.qml` | Host that puts the browser in a window or a popup surface |
| `components/Browser.qml` | The whole file manager: toolbar, tabs, panes, dialogs, keys |
| `components/PaneView.qml` | One directory pane, list and grid, selection and search |
| `components/PathBar.qml` | Address bar, breadcrumbs, inline editing, the filter |
| `components/SidebarPlaces.qml` | Places, bookmarks, drives, network |
| `components/TabStrip.qml`, `TransferBar.qml`, `PlaceRow.qml` | Small pieces |
| `bin/omafile-helper` | Python 3 daemon, standard library only. Every filesystem operation happens here |
| `bin/omafile-filemanager1` | Optional D-Bus service for Show in folder. Needs PyGObject, and is feature detected |
| `Model.js` | Pure logic: decoding, sorting, filtering, formatting, paths |
| `Icons.js` | Glyph tables |
| `PROTOCOL.md` | The contract between the shell and the helper |
| `tests/` | Node tests for the JS modules, unittest for the helper |

## Tests

```bash
npm test
python3 -m unittest discover -s tests -p "*_test.py"
```

Node 22 or newer and Python 3.11 or newer, nothing else. Anything that can live in `Model.js` should, with a test next to it. Add or update a test for every change to `Model.js`, `Icons.js`, or the helper. QML changes are checked by hand in a running shell.

Lint the QML before pushing:

```bash
qmllint -I /usr/share/omarchy/shell -I . *.qml components/*.qml
```

## Style

- No code comments, in any language. Name things so they explain themselves.
- No em dashes anywhere: code, docs, commit messages. Use a comma, a hyphen, or a full stop.
- Match the shell: build on `Button`, `TextField`, `Toggle`, `ConfirmDialog`, and `KeyboardPanel`, and take colours, spacing, and fonts from `qs.Commons`. Never hardcode a colour, a size, or a font.
- The shell is one process for the whole desktop. Nothing may block it. Every filesystem call belongs in the helper, and the helper must answer on a worker thread.
- The helper is Python standard library only. No third party imports, no `sudo`, no `pkexec`, no `shell=True`. The one exception is `bin/omafile-filemanager1`, which needs PyGObject for D-Bus. It is optional, feature detected, and never on the path of a normal file operation.
- Paths go to the helper as JSON on standard input, never in argv and never through a shell.
- Keep docs short. Prefer a table to a paragraph. Describe what a thing does, not why.

## Things that will bite you

- Cancelling a request does not stop results already in flight. Guard async callbacks with a generation counter.
- A list that crosses a `ListView` model boundary becomes a QVariantList, so `Array.isArray` is false. Iterate by `.length`.
- `Item.visible` reports effective visibility. A container whose `visible` reads its children latches hidden.
- Large directories: keep rows in the helper's raw array form and decode only visible delegates. Building tens of thousands of objects in QML freezes the desktop.

## Pull requests

- One change per pull request.
- Commit messages are a single line.
- Update `README.md` when behaviour, settings, keys, or IPC change, and `PROTOCOL.md` when the helper contract changes.
- Bump `version` in `manifest.json` and `package.json` only when asked in review.
- Security issues go through [SECURITY.md](SECURITY.md), not a pull request.

## Releases

1. Bump `version` in `manifest.json` and `package.json`, commit, push.
2. Tag and push the tag:

```bash
git tag -a v0.2.0 -m "v0.2.0"
git push origin v0.2.0
```

The release workflow checks the tag against `manifest.json` and `package.json`, runs both test suites, creates the GitHub release, and opens a marketplace **verification** issue for the tagged commit. That last step needs a `MARKETPLACE_TOKEN` repository secret, a classic personal access token with the `public_repo` scope.

Verification is for a plugin that is already listed. The first listing is a different form, and it is a one time manual step: run the **Submit to marketplace** workflow from the Actions tab. See [Marketplace](#marketplace).

## Marketplace

| Step | When | How |
| --- | --- | --- |
| Initial submission | Once, before the plugin is listed | Run the Submit to marketplace workflow by hand and type the plugin id to confirm. It opens a `[Plugin]:` issue with the category, tags, and checklist |
| Update verification | Every release after that | Automatic on a `v*` tag. Opens a `[Verify]:` issue naming the exact commit |
| Revalidation | Every push to `main` while an initial submission is open and unapproved | Automatic. Points the submission at the new head so review never lands on a stale commit |

All three touch `omacom/omarchy-plugin-marketplace`. A maintainer reviews the request. Approval binds to one exact commit, and it is a listing check, not a security audit.

Approval can take days, and any commit pushed in the meantime leaves the validated snapshot behind. The revalidation workflow handles that: on every push to `main` it looks for an open initial submission that is not approved yet, compares the last validated commit against the new head, and edits the issue only when they differ. An already current submission is left alone, so review is never spammed.

It deliberately ignores `[Verify]:` update requests. Those name one exact release commit, and later commits on `main` belong to the next release, not to the one under review.

By contributing you agree that your work is released under the [MIT License](LICENSE).
