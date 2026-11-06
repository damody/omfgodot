#!/usr/bin/env bash
# Loop window and review sheet for every registered take of one diagonal walk: diag_candidates.sh HERO fq|bq OUT_DIR
cd "$(dirname "$0")" || exit 1
PY=.venv/Scripts/python.exe
hero=$1 diag=$2 out=$3
action=walk; [ "$diag" = bq ] && action=back-walk
mkdir -p "$out"
for take in work/hero/$hero/set-$diag/actions/$action/takes/t*; do
  found=$($PY loop_window.py "$take" 24 60 2>/dev/null) || continue
  window=$(echo "$found" | $PY -c "import json,sys; print(json.load(sys.stdin)['window'])")
  sheet=$out/$hero-$diag-$(basename "$take").png
  $PY take_sheet.py "$take" "$sheet" "${window%:*}" "${window#*:}" 16 > /dev/null
  echo "$(basename "$take") $found $sheet"
done
