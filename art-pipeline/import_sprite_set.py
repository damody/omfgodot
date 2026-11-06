"""Copy accepted sprite_set packages into the Godot project at game speed and write sprite.json.

usage: import_sprite_set.py SET_DIR[,SET_DIR...] CONTENT_ID GAME_DIR [SLOT=MS[:FRAMES]...]
A later set overrides an earlier one per action. Action names map to the backend's animation slots.
Grok plays everything slowly, so each clip is resampled here to the length the game shows, specks of
colour foreign to the character are repainted, and the frames are packed into one atlas per slot.
SpriteFrames cannot carry events, so the game reads them from sprite.json.
"""
import json
import pathlib
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

SLOTS = {"walk": "move", "run": "move", "hurt": "hit", "defeat": "death", "front-walk": "move_front", "back-walk": "move_back"}
# The diagonal sets hold one walk each, whatever view they were planned as.
SET_SLOTS = {"set-fq": "move_front_side", "set-bq": "move_back_side"}
# slot: (length in ms, frames). None keeps the package's length; death drops its static tail first.
GAME_LENGTH = {"idle": (2400, 24), "move": (850, 14), "move_front": (850, 14), "move_back": (850, 14),
               "move_front_side": (850, 14), "move_back_side": (850, 14), "attack": (None, 14), "cast": (None, 16), "death": (1000, 14)}
COLUMNS = 8
BINS = 24


def package_frames(manifest: pathlib.Path, data: dict) -> list:
    frames = []
    cell_w, cell_h = data["fallback"]["cellSize"]
    for page in data["fallback"]["pages"]:
        sheet = Image.open(manifest.parent / page["file"]).convert("RGBA")
        for i in range(page["frameCount"]):
            col, row = i % page["columns"], i // page["columns"]
            frames.append(sheet.crop((col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h)))
    return frames


def active_length(frames: list) -> int:
    """Frames up to where the body stops moving."""
    arrays = [np.asarray(f.convert("RGBA").resize((96, 96)), dtype=np.float32) for f in frames]
    steps = [float(np.abs(a - b).mean()) for a, b in zip(arrays, arrays[1:])]
    limit = max(steps) * 0.08
    last = max((i for i, step in enumerate(steps) if step > limit), default=len(steps) - 1)
    return min(last + 2, len(frames))


def palette_of(frames: list) -> np.ndarray:
    table = np.zeros((BINS, BINS, BINS), dtype=np.int64)
    for frame in frames:
        rgba = np.asarray(frame)
        solid = rgba[rgba[:, :, 3] > 200][:, :3].astype(np.int32) * BINS // 256
        np.add.at(table, (solid[:, 0], solid[:, 1], solid[:, 2]), 1)
    return table


def clean(frame: Image.Image, table: np.ndarray) -> tuple:
    """Repaint saturated pixels whose colour the character's rest pose never shows. Matte leftovers only."""
    rgba = np.array(frame)
    rgb = rgba[:, :, :3].astype(np.int32)
    # Near-key magenta (a muzzle flash Grok painted in the key colour) is background, not character.
    keyish = (rgb[:, :, 0] > 200) & (rgb[:, :, 2] > 170) & (rgb[:, :, 1] < 100)
    rgba[keyish] = 0
    # Specks floating free of the body (flash or spark leftovers) go too.
    labels, count = ndimage.label(ndimage.binary_dilation(rgba[:, :, 3] > 16, iterations=2))
    if count > 1:
        sizes = ndimage.sum(rgba[:, :, 3] > 16, labels, range(1, count + 1))
        keep = sizes >= 0.01 * sizes.max()
        rgba[~keep[labels - 1] & (labels > 0)] = 0
    bins = rgb * BINS // 256
    rare = table[bins[:, :, 0], bins[:, :, 1], bins[:, :, 2]] < 3
    saturated = rgb.max(axis=2) - rgb.min(axis=2) > 70
    foreign = rare & saturated & (rgba[:, :, 3] > 16)
    count = int(foreign.sum())
    if count == 0:
        return frame, 0
    grown = np.asarray(Image.fromarray((foreign * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))) > 0
    good = rgba.copy()
    good[grown] = 0
    # Premultiplied blur of the surrounding good pixels fills the holes.
    alpha = good[:, :, 3:4].astype(np.float32) / 255.0
    premul = np.concatenate([good[:, :, :3] * alpha, alpha * 255.0], axis=2).astype(np.uint8)
    blurred = np.asarray(Image.fromarray(premul, "RGBA").filter(ImageFilter.GaussianBlur(3)), dtype=np.float32)
    weight = np.maximum(blurred[:, :, 3:4] / 255.0, 1e-3)
    fill = np.clip(blurred[:, :, :3] / weight, 0, 255).astype(np.uint8)
    rgba[:, :, :3][grown] = fill[grown]
    return Image.fromarray(rgba, "RGBA"), count


set_dirs = [pathlib.Path(p) for p in sys.argv[1].split(",")]
content_id, game_dir = sys.argv[2], pathlib.Path(sys.argv[3])
# SLOT=MS[:FRAMES] overrides, such as move=1500:24 for a walk window that holds two strides.
for override in sys.argv[4:]:
    slot, _, value = override.partition("=")
    ms, _, frames = value.partition(":")
    GAME_LENGTH[slot] = (int(ms), int(frames) if frames else GAME_LENGTH[slot][1])
out = game_dir / "art" / "units" / content_id
out.mkdir(parents=True, exist_ok=True)

sources = {}
for set_dir in set_dirs:
    state = json.loads((set_dir / "set_state.json").read_text(encoding="utf-8"))
    for action, entry in state["actions"].items():
        if not entry.get("accepted") or not entry.get("output"):
            # The game animates a missing slot procedurally from idle.
            print(f"skipped {set_dir.name}/{action}: {entry.get('status')}", file=sys.stderr)
            continue
        slot = SET_SLOTS.get(set_dir.name) or SLOTS.get(action, action)
        sources[slot] = set_dir / entry["output"]["manifest"]
if "idle" not in sources:
    sys.exit("error: no accepted idle")

animations = {}
table = None
foreign_total = {}
for slot in ["idle"] + [s for s in sources if s != "idle"]:
    manifest = sources[slot]
    data = json.loads(manifest.read_text(encoding="utf-8"))
    frames = package_frames(manifest, data)
    durations = data.get("durationsMs") or [1000.0 / data["fps"]] * len(frames)
    if len(durations) != len(frames):
        sys.exit(f"error: {slot} has {len(durations)} durations for {len(frames)} frames")
    if table is None:
        table = palette_of(frames)
    usable = active_length(frames) if slot == "death" else len(frames)
    length, count = GAME_LENGTH.get(slot, (None, 16))
    source_ms = sum(durations[:usable])
    total = length or source_ms
    count = min(count, usable)
    # Events keep their share of the clip; a loop's last sample must not repeat its first.
    picks = [min(usable - 1, int(i * usable / count)) for i in range(count)] if data["loop"] else \
        [round(i * (usable - 1) / max(count - 1, 1)) for i in range(count)]
    cleaned = []
    foreign_total[slot] = 0
    for pick in picks:
        frame, foreign = clean(frames[pick], table)
        foreign_total[slot] += foreign
        cleaned.append(frame)
    cell_w, cell_h = data["fallback"]["cellSize"]
    rows = (count + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGBA", (COLUMNS * cell_w, rows * cell_h))
    for i, frame in enumerate(cleaned):
        sheet.paste(frame, ((i % COLUMNS) * cell_w, (i // COLUMNS) * cell_h))
    name = f"{slot}-atlas.png"
    sheet.save(out / name)
    events = []
    for event in data.get("events") or []:
        share = event.get("frame", 0) / max(usable - 1, 1)
        if event.get("frame", 0) < usable:
            events.append({**event, "frame": min(count - 1, round(share * (count - 1)))})
    animations[slot] = {
        "cell": [cell_w, cell_h],
        "anchor": data["encodedAnchor"],
        "loop": data["loop"],
        "durations_ms": [total / count] * count,
        "pages": [{"file": name, "first": 0, "count": count, "columns": COLUMNS}],
        "events": events,
        "body_height_px": data.get("bodyHeightPx"),
    }

# Packages anchor at the rear foot. Every clip is registered to one body point, so one measured
# shift from that anchor to the stance midpoint on the idle pose corrects all of them.
idle = animations["idle"]
sheet = Image.open(out / idle["pages"][0]["file"]).convert("RGBA")
cell_w, cell_h = idle["cell"]
alpha = np.asarray(sheet.crop((0, 0, cell_w, cell_h)))[:, :, 3]
sole = alpha[round(idle["anchor"][1] * 0.94):, :]
columns = np.nonzero((sole > 128).any(axis=0))[0]
shift = (columns[0] + columns[-1]) / 2.0 - idle["anchor"][0]
for animation in animations.values():
    animation["anchor"] = [animation["anchor"][0] + shift, animation["anchor"][1]]

for stale in out.glob("*-atlas*.png*"):
    if stale.name.split(".png")[0] + ".png" not in {a["pages"][0]["file"] for a in animations.values()}:
        stale.unlink()
(out / "sprite.json").write_text(json.dumps({"content_id": content_id, "facing": "right",
                                             "animations": animations}, indent=1), encoding="utf-8")
print(json.dumps({"status": "ok", "output": str(out), "frames": {k: len(v["durations_ms"]) for k, v in animations.items()},
                  "ms": {k: round(sum(v["durations_ms"])) for k, v in animations.items()},
                  "foreign_px": foreign_total}))
