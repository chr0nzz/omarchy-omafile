#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_root=${OMARCHY_PATH:-/usr/share/omarchy}/shell
if ! command -v qs > /dev/null || [[ ! -d $shell_root/Commons ]]; then
  printf 'pane-clicks needs Quickshell (qs) and the Omarchy shell in %s\n' "$shell_root" >&2
  exit 1
fi
stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT
for module in Commons Ui services; do
  ln -s "$shell_root/$module" "$stage/$module"
done
ln -s "$repo_root" "$stage/FilePlugin"
cp "$repo_root/tests/browser-flows.qml" "$stage/shell.qml"
python3 -I - "$stage/tone.wav" <<'EOF'
import math, struct, sys, wave
with wave.open(sys.argv[1], "wb") as out:
    out.setnchannels(1)
    out.setsampwidth(2)
    out.setframerate(8000)
    out.writeframes(b"".join(struct.pack("<h", int(8000 * math.sin(i / 8000 * 2 * math.pi * 440))) for i in range(8000 * 20)))
EOF
status=0
OMAFILE_TEST_TONE="$stage/tone.wav" QT_QPA_PLATFORM=offscreen timeout -k 5 180 qs -p "$stage/shell.qml" --no-color > "$stage/output.log" 2>&1 || status=$?
if (( status == 124 || status == 137 )); then
  printf 'OMAFILE_BROWSER_FLOWS_TIMEOUT\n' >> "$stage/output.log"
fi
if (( status != 0 )); then
  cat "$stage/output.log"
  exit 1
fi
if ! grep -q 'OMAFILE_BROWSER_FLOWS_PASSED' "$stage/output.log" || grep -q 'FAILED_IN ' "$stage/output.log"; then
  cat "$stage/output.log"
  exit 1
fi
printf 'Browser flows: passed\n'
