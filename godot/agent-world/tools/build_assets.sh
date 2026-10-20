#!/bin/bash
# Rebuild every gitignored asset under assets/ in dependency order; stops on the first failure.
# usage: build_assets.sh [--skip-selftest]   env: FONT_SRC (OFL fonts dir, default vendor/fonts), PIXEL_AVATAR / PIXEL_SCENE / PIXEL_FOLIAGE (skill overrides); names every missing dependency first
set -euo pipefail
P="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
SKILLS="$HOME/.claude/skills"
FONT_SRC="${FONT_SRC:-$P/vendor/fonts}"
FONTS=(Jersey10-Regular.ttf PixelifySans.ttf PressStart2P-Regular.ttf Silkscreen-Regular.ttf Silkscreen-Bold.ttf)
WORLDS=(magic_forest darkwood)
cd "$P"
T0=$(date +%s)
step() { echo "== $1 ($(( $(date +%s) - T0 )) s)"; }

missing=()
for c in python3 godot; do command -v "$c" >/dev/null || missing+=("command $c (not on PATH)"); done
for m in numpy PIL; do python3 -c "import $m" 2>/dev/null || missing+=("python module $m (pip install ${m/PIL/pillow})"); done
for d in "${PIXEL_AVATAR:-$SKILLS/pixel-avatar}/scripts" "${PIXEL_SCENE:-$SKILLS/pixel-scene/scripts}" \
  "${PIXEL_FOLIAGE:-$SKILLS/pixel-foliage/scripts}"; do
  [ -d "$d" ] || missing+=("skill scripts $d (fleet skill, not vendored: see vendor/README.md; or set PIXEL_AVATAR / PIXEL_SCENE / PIXEL_FOLIAGE)")
done
for f in "${FONTS[@]}" OFL.txt; do [ -s "$FONT_SRC/$f" ] || missing+=("font $FONT_SRC/$f (set FONT_SRC to the OFL fonts dir)"); done
if [ ${#missing[@]} -gt 0 ]; then
  printf 'MISSING %s\n' "${missing[@]}"
  echo "FAIL build_assets: ${#missing[@]} missing external dependencies"
  exit 1
fi

if [ "${1:-}" != "--skip-selftest" ]; then
  for s in pixel-avatar pixel-foliage pixel-scene; do
    step "selftest $s"
    bash "$SKILLS/$s/tests/selftest.sh" > /tmp/build_assets-selftest-$s.log 2>&1 \
      || { echo "FAIL selftest $s (log /tmp/build_assets-selftest-$s.log)"; exit 1; }
  done
fi

step "fonts"
mkdir -p assets/fonts
for f in "${FONTS[@]}"; do cp "$FONT_SRC/$f" assets/fonts/; done
cp "$FONT_SRC/OFL.txt" assets/fonts/OFL.txt
if ! ls .godot/imported/PixelifySans.ttf-*.fontdata >/dev/null 2>&1; then
  step "import fonts (fresh checkout)"
  godot --headless --path . --audio-driver Dummy --import > /tmp/build_assets-import.log 2>&1
fi

step "avatars"
bash tools/art/avatars/build.sh

step "title"
bash tools/art/title/build.sh

step "ui kit"
python3 tools/art/ui/build_ui.py

for w in "${WORLDS[@]}"; do
  step "world $w"
  python3 tools/worldgen/build_world.py "tools/worldgen/worlds/$w.json" --out "assets/worlds/$w"
  [ -s "assets/worlds/$w/world.json" ] || echo "WARN assets/worlds/$w/world.json (prose sidecar) missing: the menu will not list $w"
done

step "done"
echo "BUILD_ASSETS ok in $(( $(date +%s) - T0 )) s"
