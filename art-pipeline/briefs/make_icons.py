"""Ability icons the source game never had, drawn by Grok in the style of an existing icon.

usage: make_icons.py GAME_DIR
Resumable: an id whose art/icons/<id>.png exists is skipped. Each image is saved square at 128 px.
"""
import json
import pathlib
import subprocess
import sys

from PIL import Image

HERE = pathlib.Path(__file__).parent
PIPE = HERE.parent
ROUTE = PIPE / "forge" / "skills" / "generate2dmedia" / "scripts" / "route_media.py"
STYLE_REF = "b29_ground_slam"
ICONS = {
    "a07_unscathed": "a black lacquered samurai breastplate with a prayer-bead sash, wrapped in a protective golden aura that turns incoming blue magic sparks into green healing light; no axe and no weapon of any kind",
    "a02_venom_arrow": "a green arrowhead dripping glowing poison, a small scorpion silhouette curled around the shaft",
    "a02_wind_prayer": "a woman's praying hands wrapped in a swirling green wind full of leaves",
    "a02_wind_drift": "a tall black longbow inside a swirling pale green wind barrier",
    "a02_shadow_meld": "an archer's silhouette dissolving into dark violet mist and drifting leaves",
    "c15_scatter_shot": "many glowing golden arrows falling from a starry night sky onto a circle on the ground",
    "c15_burst_arrow": "a burning arrow flying forward and leaving a long line of fire behind it",
    "c15_precise_light": "a bright golden star shining on the tip of an ivory arrow",
    "c15_hundred_arrows": "ten golden arrows converging from all sides on one point under a burst of starlight",
    "a34_frost_bolt": "a sharp ice crystal bolt streaking forward, frost spreading where it hits",
    "a34_iceberg_strike": "a huge iceberg slamming into the ground and shattering into ice shards",
    "a34_frost_breath": "a cone of freezing wind and snowflakes blown out of an open silver-blue folding fan",
    "a34_rapid_cooling": "an hourglass made of ice with snowflakes falling through it",
}

game = pathlib.Path(sys.argv[1])
icons = game / "art" / "icons"
reference = icons / f"{STYLE_REF}.png"
work = PIPE / "work" / "icons"
for ident, subject in ICONS.items():
    out = icons / f"{ident}.png"
    if out.exists():
        continue
    job = work / ident
    if job.exists():
        for old in job.glob("*"):
            old.unlink()
        job.rmdir()
    work.mkdir(parents=True, exist_ok=True)
    prompt = work / f"{ident}.txt"
    prompt.write_text(
        "A square 1024x1024 ability icon for a Sengoku-era fantasy MOBA game, painted in the same style, "
        "palette depth and lighting as the reference icon: " + subject + ". One clear central subject that reads at "
        "48 px, strong contrast against a dark painted background, the art fills the whole square. "
        "No text, no letters, no frame, no border, no rounded corners, no UI.", encoding="utf-8")
    result = subprocess.run([sys.executable, str(ROUTE), "image", "--prompt-file", str(prompt), "--reference",
                             str(reference), "--out-dir", str(job), "--route", "grok-cli"],
                            capture_output=True, text=True, encoding="utf-8")
    try:
        artifact = json.loads(result.stdout.strip().splitlines()[-1])["artifact"]
    except (IndexError, KeyError, json.JSONDecodeError):
        print(f"FAIL {ident}: {(result.stderr or result.stdout)[-300:]}")
        continue
    image = Image.open(artifact).convert("RGB")
    side = min(image.size)
    left, top = (image.width - side) // 2, (image.height - side) // 2
    image.crop((left, top, left + side, top + side)).resize((128, 128), Image.LANCZOS).save(out)
    print(f"OK {ident}")
