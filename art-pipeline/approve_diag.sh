#!/usr/bin/env bash
# Approves reviewed diagonal takes: approve_diag.sh HERO:VIEW:TAKE ... (VIEW fq or bq). Retries WinError 5.
cd "$(dirname "$0")" || exit 1
export PYTHONUTF8=1
PY=.venv/Scripts/python.exe
MASTER=forge/skills/generate2dsprite/scripts/master_still.py
for pick in "$@"; do
  IFS=: read -r name view take <<< "$pick"
  dir=work/hero/$name
  for attempt in 1 2 3 4; do
    rm -rf "$dir/master-$view"
    $PY $MASTER approve --run "$dir/gen-$view/run.json" --take "$take" --output-dir "$dir/master-$view" > /dev/null 2>&1
    [ -f "$dir/master-$view/master.json" ] && break
  done
  [ -f "$dir/master-$view/master.json" ] && echo "APPROVED $name $view t$take" || echo "APPROVE_FAIL $name $view"
done
