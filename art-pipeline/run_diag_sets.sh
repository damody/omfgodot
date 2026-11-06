#!/usr/bin/env bash
# Diagonal walk cycles from each hero's approved diagonal masters: set-fq (front diagonal, planned as a side view)
# and set-bq (back diagonal, planned as a back view). Resumable.
cd "$(dirname "$0")" || exit 1
export PYTHONUTF8=1 PATH="$(dirname "$(find /c/nobu/tools/ffmpeg -name ffmpeg.exe)"):$PATH"
PY=.venv/Scripts/python.exe
SET=forge/skills/video2dsprite/scripts/sprite_set.py
for name in "$@"; do
  dir=work/hero/$name
  for diag in fq bq; do
    out=$dir/set-$diag
    view=side; [ "$diag" = bq ] && view=back
    if [ ! -d "$out" ]; then
      $PY $SET plan --master "$dir/master-$diag/master.json" --views $view \
        --output-dir "$out" --actions walk --max-takes 4 --jobs 2 > "$dir/plan-$diag.log" 2>&1 \
        && $PY briefs/hero_motion.py "$out/set_plan.json" "$name" >> "$dir/plan-$diag.log" 2>&1 \
        || { echo "PLAN_FAIL $name $diag: $(tail -1 "$dir/plan-$diag.log" | cut -c1-300)"; continue; }
    fi
    for attempt in 1 2 3 4 5 6; do
      $PY $SET run --plan "$out/set_plan.json" > "$dir/run-$diag.log" 2>&1 && break
      tail -1 "$dir/run-$diag.log" | grep -q 'WinError 5' || break
    done
    $PY $SET review --plan "$out/set_plan.json" > /dev/null 2>&1
    echo "DIAGSET $name $diag: $(tail -1 "$dir/run-$diag.log" | cut -c1-400)"
  done
done
echo DIAG_SETS_DONE
