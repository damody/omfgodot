#!/usr/bin/env bash
# Front and back masters for the named heroes, drawn from each approved side master. Resumable.
cd "$(dirname "$0")" || exit 1
export PYTHONUTF8=1 PATH="$(dirname "$(find /c/nobu/tools/ffmpeg -name ffmpeg.exe)"):$PATH"
PY=.venv/Scripts/python.exe
MASTER=forge/skills/generate2dsprite/scripts/master_still.py
for name in "$@"; do
  dir=work/hero/$name
  # Grok takes one reference: the side master already carries the style, so drop the style ref.
  $PY -c "import json,sys; d=json.load(open(sys.argv[1],encoding='utf-8')); d.pop('style_ref',None); open(sys.argv[2],'w',encoding='utf-8').write(json.dumps(d))" briefs/$name.json "$dir/view-spec.json"
  for view in front back; do
    out=$dir/gen-$view
    [ -f "$out/.done" ] && continue
    rm -rf "$out"
    if [ "$view" = front ]; then words="front view, facing the camera, seen from a slightly raised camera"
    else words="back view, facing away from the camera, seen from a slightly raised camera"; fi
    if $PY $MASTER generate --spec "$dir/view-spec.json" --facing $view --view "$words" \
        --identity-ref "$dir/master/master.png" --identity-ref-what "the same hero seen from the side" \
        --identity-copy "face, hair, armour, costume, colours, weapon and proportions" \
        --takes 2 --output-dir "$out" > "$dir/gen-$view.log" 2>&1; then
      touch "$out/.done"; echo "VIEW_OK $name $view"
    else
      echo "VIEW_FAIL $name $view: $(tail -1 "$dir/gen-$view.log" | cut -c1-300)"
    fi
  done
done
echo VIEWS_DONE
