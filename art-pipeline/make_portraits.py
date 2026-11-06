"""Head-and-shoulders portraits for the HUD, cropped from each hero's approved master.

usage: make_portraits.py GAME_DIR
Writes art/units/<hero>/portrait.png (256 px square) for every work/hero/<hero>/master/master_rgba.png.
"""
import pathlib
import sys

import numpy as np
from PIL import Image

game = pathlib.Path(sys.argv[1])
for master in sorted((pathlib.Path(__file__).parent / "work" / "hero").glob("*/master/master_rgba.png")):
    hero = master.parent.parent.name
    image = Image.open(master).convert("RGBA")
    alpha = np.asarray(image)[:, :, 3] > 128
    rows = np.nonzero(alpha.any(axis=1))[0]
    top, bottom = rows[0], rows[-1]
    height = bottom - top
    side = int(height * 0.40)
    # Find the head as the first rows wider than a weapon shaft or a crest tip, then centre on their mass.
    widths = alpha.sum(axis=1)
    head_row = top + int(np.argmax(widths[top:] > height * 0.07))
    rows_mass = alpha[head_row:head_row + int(height * 0.12)]
    center = int(np.average(np.nonzero(rows_mass)[1]))
    y0 = max(0, head_row - side // 8)
    box = (center - side // 2, y0, center + side // 2, y0 + side)
    portrait = Image.new("RGBA", (side, side))
    portrait.paste(image.crop(box), (0, 0))
    out = game / "art" / "units" / hero / "portrait.png"
    portrait.resize((256, 256), Image.LANCZOS).save(out)
    print(out)
