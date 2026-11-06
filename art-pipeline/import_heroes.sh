#!/usr/bin/env bash
# Re-imports every hero's accepted clips into the Godot project with its reviewed overrides.
cd "$(dirname "$0")" || exit 1
export PYTHONUTF8=1
PY=.venv/Scripts/python.exe
GAME=../omgd/game
H=work/hero
while read -r hero sets overrides; do
  dirs=$(echo "$sets" | sed "s|[^,]*|$H/$hero/&|g")
  $PY import_sprite_set.py "$dirs" "$hero" "$GAME" $overrides | cut -c1-160
done <<EOF
murakami_yoshikiyo set,set2,set-views,set-fq,set-bq move_back_side=1500:24
date_masamune set,set-views,set-fq,set-bq move_back=1500:24 move_back_side=1500:24 move_front_side=1500:24
honda_tadakatsu set,set-views,set-fq,set-bq move_back_side=1500:24
sanada_yukimura set,set-views,set-fq,set-bq move=1500:24 move_back_side=1500:24
asai_nagamasa set,set-views,set-fq,set-bq move_back_side=1500:24
inahime set,set2,set-views,set-fq,set-bq move_back_side=1500:24
tamako set,set-views,set-fq,set-bq move=1300:20 move_front=1300:20 move_back=1500:24 move_back_side=1500:24
oichi set,set-views,set-fq,set-bq move_back=1500:24
omatsu set,set2,set-views,set-fq,set-bq move_back_side=1500:24
saika_magoichi set,set-views,set-fq,set-bq move_front=1500:24 move_back=1500:24 move_back_side=1500:24
EOF
