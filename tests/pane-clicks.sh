#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_root=${OMARCHY_PATH:-/usr/share/omarchy}/shell
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
for module in Commons Ui services; do
  ln -s "$shell_root/$module" "$stage/$module"
done
ln -s "$repo_root" "$stage/FilePlugin"
cp "$repo_root/tests/pane-clicks.qml" "$stage/shell.qml"
if ! QT_QPA_PLATFORM=offscreen qs -p "$stage/shell.qml" --no-color > "$stage/output.log" 2>&1; then
  cat "$stage/output.log"
  exit 1
fi
if ! rg -q 'OMAFILE_PANE_CLICKS_PASSED' "$stage/output.log"; then
  cat "$stage/output.log"
  exit 1
fi
printf 'Pane header sorting, row selection, drag selection and grid selection: passed\n'
