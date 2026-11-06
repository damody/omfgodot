"""One line per action of each hero set: status, chosen take, and every take's failure.

usage: set_status.py [--set NAME] [HERO...]
"""
import json
import pathlib
import sys

root = pathlib.Path(__file__).parent / "work" / "hero"
args = sys.argv[1:]
SET = "set"
if args[:1] == ["--set"]:
    SET, args = args[1], args[2:]
for hero in args or sorted(p.name for p in root.iterdir()):
    path = root / hero / SET / "set_state.json"
    if not path.exists():
        print(f"{hero}: no set")
        continue
    state = json.loads(path.read_text(encoding="utf-8"))
    print(f"{hero}:")
    for action, entry in state["actions"].items():
        takes = [f"t{t['take']}:{t['status']}:{','.join(t.get('failures') or [])}" for t in entry.get("takes", [])]
        print(f"  {action:7} {entry.get('status')} chosen={entry.get('chosen')} accepted={entry.get('accepted')} {' '.join(takes)}")
