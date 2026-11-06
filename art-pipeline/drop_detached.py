"""Erase pieces detached from the character (a flying arrow, a spark) in a take's keyed frames.

usage: drop_detached.py TAKE_DIR [MAX_SHARE]
Keeps the largest opaque component and anything touching it; erases every other component smaller
than MAX_SHARE (default 0.06) of the body. Originals go to keyed/frames-clean.orig once.
"""
import pathlib
import shutil
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

take = pathlib.Path(sys.argv[1])
max_share = float(sys.argv[2]) if len(sys.argv) > 2 else 0.06
clean = take / "keyed" / "frames-clean"
backup = take / "keyed" / "frames-clean.orig"
if not backup.exists():
    shutil.copytree(clean, backup)
erased_frames = 0
for path in sorted(backup.glob("clean_*.png")):
    rgba = np.array(Image.open(path).convert("RGBA"))
    solid = rgba[:, :, 3] > 16
    # Bridge one-pixel gaps (a thin string or haft) before deciding what is attached.
    labels, count = ndimage.label(ndimage.binary_dilation(solid, iterations=3))
    if count > 1:
        sizes = ndimage.sum(solid, labels, range(1, count + 1))
        body = int(np.argmax(sizes)) + 1
        drop = np.zeros_like(solid)
        for index, size in enumerate(sizes, start=1):
            if index != body and size < max_share * sizes[body - 1]:
                drop |= labels == index
        if drop.any():
            rgba[drop & solid] = 0
            erased_frames += 1
    Image.fromarray(rgba, "RGBA").save(clean / path.name)
print(f"erased detached pieces in {erased_frames} frames of {take}")
