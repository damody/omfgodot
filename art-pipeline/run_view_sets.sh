#!/usr/bin/env bash
# Front and back walk cycles from each hero's approved view masters. Resumable.
cd "$(dirname "$0")" || exit 1
export PYTHONUTF8=1 PATH="$(dirname "$(find /c/nobu/tools/ffmpeg -name ffmpeg.exe)"):$PATH"
PY=.venv/Scripts/python.exe
SET=forge/skills/video2dsprite/scripts/sprite_set.py
for name in "$@"; do
  dir=work/hero/$name
  if [ ! -d "$dir/set-views" ]; then
    $PY $SET plan --master "$dir/master/master.json" --views front,back \
      --view-master "front=$dir/master-front/master.json" --view-master "back=$dir/master-back/master.json" \
      --output-dir "$dir/set-views" --actions walk --max-takes 4 --jobs 2 > "$dir/plan-views.log" 2>&1 \
      && $PY briefs/hero_motion.py "$dir/set-views/set_plan.json" "$name" >> "$dir/plan-views.log" 2>&1 \
      || { echo "PLAN_FAIL $name: $(tail -1 "$dir/plan-views.log" | cut -c1-300)"; continue; }
  fi
  for attempt in 1 2 3 4 5 6; do
    $PY $SET run --plan "$dir/set-views/set_plan.json" > "$dir/run-views.log" 2>&1 && break
    tail -1 "$dir/run-views.log" | grep -q 'WinError 5' || break
  done
  $PY $SET review --plan "$dir/set-views/set_plan.json" > /dev/null 2>&1
  echo "VIEWSET $name: $(tail -1 "$dir/run-views.log" | cut -c1-400)"
done
echo VIEW_SETS_DONE
