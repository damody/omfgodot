#!/usr/bin/env bash
# Hero masters through the Grok CLI: three takes each, then stop for a human choice. Resumable.
cd "$(dirname "$0")" || exit 1
export PYTHONUTF8=1 PATH="$(dirname "$(find /c/nobu/tools/ffmpeg -name ffmpeg.exe)"):$PATH"
PY=.venv/Scripts/python.exe
MASTER=forge/skills/generate2dsprite/scripts/master_still.py
$PY briefs/make_heroes.py
for name in murakami_yoshikiyo date_masamune honda_tadakatsu sanada_yukimura asai_nagamasa inahime tamako oichi omatsu; do
  dir=work/hero/$name
  mkdir -p "$dir"
  [ -f "$dir/gen/.done" ] && continue
  rm -rf "$dir/gen"
  if $PY $MASTER generate --spec briefs/$name.json --takes 3 --output-dir "$dir/gen" > "$dir/gen.log" 2>&1; then
    touch "$dir/gen/.done"; echo "GEN_OK $name"
  else
    echo "GEN_FAIL $name: $(tail -1 "$dir/gen.log" | cut -c1-300)"
  fi
done
echo HERO_MASTERS_DONE
