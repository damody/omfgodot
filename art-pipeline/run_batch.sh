#!/usr/bin/env bash
# Generates the shared cast through the Grok CLI. Resumable: finished folders are skipped.
cd "$(dirname "$0")" || exit 1
export PYTHONUTF8=1 PATH="$(dirname "$(find /c/nobu/tools/ffmpeg -name ffmpeg.exe)"):$PATH"
PY=.venv/Scripts/python.exe
MASTER=forge/skills/generate2dsprite/scripts/master_still.py
SET=forge/skills/video2dsprite/scripts/sprite_set.py
$PY briefs/make_batch.py
for name in tower barracks base lane_melee lane_caster lane_siege lane_cavalry; do
  dir=work/$name
  [ -d "$dir/master" ] && continue
  rm -rf "$dir/gen"
  $PY $MASTER generate --spec briefs/$name.json --takes 1 --output-dir "$dir/gen" 2>&1 | tail -1 | cut -c1-200
  $PY $MASTER approve --run "$dir/gen" --take 1 --output-dir "$dir/master" 2>&1 | tail -1 | cut -c1-200
done
echo MASTERS_DONE
one_set() {
  name=$1; dir=work/$name
  [ -d "$dir/set" ] || $PY $SET plan --master "$dir/master/master.json" --output-dir "$dir/set" --actions idle,walk,attack --target-height 160 --fps 12 2>&1 | tail -1 | cut -c1-160
  for attempt in 1 2 3 4; do
    $PY $SET run --plan "$dir/set/set_plan.json" > "$dir/run.log" 2>&1 && break
    tail -1 "$dir/run.log" | grep -q 'WinError 5' || break
  done
  echo "SET $name: $(tail -1 "$dir/run.log" | cut -c1-500)"
}
for name in lane_melee lane_caster lane_siege lane_cavalry; do one_set "$name"; done
echo BATCH_DONE
