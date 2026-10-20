#!/bin/bash
# Magic Forest NEXT #3 check: render lake, plateau, bluff and Moss Gate stills, then the day-water and readability probes.
# usage: mf_check.sh OUTDIR
set -u
[ $# -eq 1 ] || { echo "usage: mf_check.sh OUTDIR"; exit 2; }
P="$(cd "$(dirname "$0")/../.." && pwd)"
OUT=$1 W=res://assets/worlds/magic_forest D=$P/assets/worlds/magic_forest
mkdir -p "$OUT"
for v in "lake 2170,884" "plateau 400,1085" "bluff 3166,560" "mossgate 960,330"; do
  set -- $v
  bash "$P/tools/render/run.sh" still res://tools/worldgen/preview.tscn "$OUT/$1.png" 90 -- --world $W --at "$2" --zoom 2 | tail -1
done
python3 "$P/tools/render/water_probe.py" "$OUT/lake.png" "$D/scene.json" "$D/art/built.json" --at 2170,884 --zoom 2; a=$?
python3 "$P/tools/render/mf_read_probe.py" "$D/scene.json" --plateau "$OUT/plateau.png@400,1085,2" --gate "$OUT/mossgate.png@960,330,2"; b=$?
[ $a -eq 0 ] && [ $b -eq 0 ] && echo "MFCHECK pass" && exit 0
echo "MFCHECK FAIL"; exit 1
