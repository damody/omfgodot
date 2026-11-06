"""Find the take window that loops best, for a walk whose gait the forge could not lock.

usage: loop_window.py TAKE_DIR [MIN_FRAMES MAX_FRAMES [FIRST:LAST]]
Compares downscaled registered frames; prints the START:END (END exclusive) whose last frame leads
back into the first with the smallest jump, relative to the clip's typical frame-to-frame change.
"""
import json
import pathlib
import sys

import numpy as np
from PIL import Image

take = pathlib.Path(sys.argv[1])
low, high = (int(sys.argv[2]), int(sys.argv[3])) if len(sys.argv) > 3 else (18, 72)
# Optional FIRST:LAST bounds the search to a stretch of the take, such as frames where a prop stays visible.
first, last = (int(v) for v in sys.argv[4].split(":")) if len(sys.argv) > 4 else (0, None)
files = sorted((take / "registered" / "frames").glob("*.png"))
if not files:
    sys.exit(f"error: no registered frames under {take}")
frames = np.stack([np.asarray(Image.open(f).convert("RGBA").resize((128, 128)), dtype=np.float32) for f in files])
# Weight colour by coverage so the empty background never counts as a match.
alpha = frames[..., 3:4] / 255.0
signal = np.concatenate([frames[..., :3] * alpha, frames[..., 3:4]], axis=-1)
step = np.abs(signal[1:] - signal[:-1]).mean(axis=(1, 2, 3))
typical = float(np.median(step))
best = None
bound = min(last or len(files), len(files))
for start in range(first, bound - low):
    for length in range(low, min(high, bound - start - 1) + 1):
        end = start + length
        # The frame after the window must look like its first frame.
        jump = float(np.abs(signal[end] - signal[start]).mean())
        score = jump / typical
        if best is None or score < best[0]:
            best = (score, start, end)
print(json.dumps({"window": f"{best[1]}:{best[2]}", "jump_vs_step": round(best[0], 2), "frames": len(files),
                  "typical_step": round(typical, 3)}))
