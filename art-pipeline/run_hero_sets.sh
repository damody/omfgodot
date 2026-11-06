#!/usr/bin/env bash
# One sprite set per named hero through the Grok CLI, one hero at a time. Resumable.
cd "$(dirname "$0")" || exit 1
export PYTHONUTF8=1 PATH="$(dirname "$(find /c/nobu/tools/ffmpeg -name ffmpeg.exe)"):$PATH"
PY=.venv/Scripts/python.exe
SET=forge/skills/video2dsprite/scripts/sprite_set.py
for name in "$@"; do
  dir=work/hero/$name
  if [ ! -d "$dir/set" ]; then
    $PY $SET plan --master "$dir/master/master.json" --output-dir "$dir/set" --actions idle,walk,attack,cast,defeat --max-takes 4 --jobs 2 > "$dir/plan.log" 2>&1 \
      && $PY briefs/hero_motion.py "$dir/set/set_plan.json" "$name" >> "$dir/plan.log" 2>&1 \
      || { echo "PLAN_FAIL $name: $(tail -1 "$dir/plan.log" | cut -c1-300)"; continue; }
  fi
  for attempt in 1 2 3 4 5 6; do
    $PY $SET run --plan "$dir/set/set_plan.json" > "$dir/run.log" 2>&1 && break
    tail -1 "$dir/run.log" | grep -q 'WinError 5' || break
  done
  $PY $SET review --plan "$dir/set/set_plan.json" > "$dir/review.log" 2>&1
  echo "SET $name: $(tail -1 "$dir/run.log" | cut -c1-600)"
done
echo HERO_SETS_DONE
