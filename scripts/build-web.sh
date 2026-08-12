#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"

mkdir -p "$project_root/dist"
rm -f "$project_root/dist"/index.*
"$godot_bin" \
  --headless --path "$project_root/godot_project" \
  --export-release Web "$project_root/dist/index.html"
python3 "$project_root/scripts/patch-service-worker.py" \
  "$project_root/dist/index.service.worker.js"

test -s "$project_root/dist/index.html"
test -s "$project_root/dist/index.wasm"
test -s "$project_root/dist/index.pck"
test -s "$project_root/dist/index.manifest.json"
test -s "$project_root/dist/index.service.worker.js"
grep -Fq '"display":"standalone"' "$project_root/dist/index.manifest.json"
grep -Fq '"index.wasm","index.pck"' "$project_root/dist/index.service.worker.js"
grep -Fq 'cached == null && isNavigate' "$project_root/dist/index.service.worker.js"
printf 'Built Vitruvian PWA with %s\n' "$("$godot_bin" --version | head -n 1)"
