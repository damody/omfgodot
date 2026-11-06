"""Loop windows and review sheets for every take of a hero's front and back walks.

usage: view_candidates.py HERO OUT_DIR
Prints one line per take (action, take, window, seam) and writes OUT_DIR/<hero>-<action>-<take>.png.
"""
import json
import pathlib
import subprocess
import sys

here = pathlib.Path(__file__).parent
hero, out = sys.argv[1], pathlib.Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
actions = here / "work" / "hero" / hero / "set-views" / "actions"
for action in ("front-walk", "back-walk"):
    for take in sorted((actions / action / "takes").glob("t*")):
        if not (take / "registered" / "frames").is_dir():
            continue
        found = json.loads(subprocess.run([sys.executable, str(here / "loop_window.py"), str(take), "24", "60"],
                                          capture_output=True, text=True, check=True).stdout)
        start, end = found["window"].split(":")
        sheet = out / f"{hero}-{action}-{take.name}.png"
        subprocess.run([sys.executable, str(here / "take_sheet.py"), str(take), str(sheet), start, end, "16"],
                       capture_output=True, check=True)
        print(action, take.name, found["window"], found["jump_vs_step"], sheet)
