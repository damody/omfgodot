#!/usr/bin/env bash
# Front-diagonal and back-diagonal masters (three-quarter views facing right) for the named heroes. Resumable.
# The left diagonals are the mirror image, like the side view.
cd "$(dirname "$0")" || exit 1
export PYTHONUTF8=1 PATH="$(dirname "$(find /c/nobu/tools/ffmpeg -name ffmpeg.exe)"):$PATH"
PY=.venv/Scripts/python.exe
MASTER=forge/skills/generate2dsprite/scripts/master_still.py
for name in "$@"; do
  dir=work/hero/$name
  [ -f "$dir/view-spec.json" ] || $PY -c "import json,sys; d=json.load(open(sys.argv[1],encoding='utf-8')); d.pop('style_ref',None); open(sys.argv[2],'w',encoding='utf-8').write(json.dumps(d))" briefs/$name.json "$dir/view-spec.json"
  for view in fq bq; do
    out=$dir/gen-$view
    [ -f "$out/.done" ] && continue
    rm -rf "$out"
    if [ "$view" = fq ]; then
      words="three-quarter front view seen from a slightly raised camera: the body turned halfway between facing the camera and facing RIGHT, both eyes and the chest visible, walking toward the lower right"
    else
      words="three-quarter back view seen from a slightly raised camera: the back of the head and the back of the armour toward the camera, the body turned a little to the RIGHT so the right shoulder and a sliver of the right cheek show, walking away toward the upper right"
    fi
    # A right facing pulls the face toward the viewer, so the back diagonal is a back view turned right.
    # The side reference drags a back diagonal round to the front, so it starts from the approved back view.
    facing=right; ref=$dir/master/master.png; what="the same hero seen from the side"
    if [ "$view" = bq ]; then facing=back; ref=$dir/master-back/master.png; what="the same hero seen from behind"; fi
    # FQ_FROM_FRONT=1 for a hero whose side still is already half turned: start from the front view instead.
    if [ "$view" = fq ] && [ -n "$FQ_FROM_FRONT" ]; then ref=$dir/master-front/master.png; what="the same hero seen from the front"; fi
    if $PY $MASTER generate --spec "$dir/view-spec.json" --facing $facing --view "$words" \
        --identity-ref "$ref" --identity-ref-what "$what" \
        --identity-copy "face, hair, armour, costume, colours, weapon and proportions" \
        --takes 2 --output-dir "$out" > "$dir/gen-$view.log" 2>&1; then
      touch "$out/.done"; echo "DIAG_OK $name $view"
    else
      echo "DIAG_FAIL $name $view: $(tail -1 "$dir/gen-$view.log" | cut -c1-300)"
    fi
  done
done
echo DIAG_DONE
