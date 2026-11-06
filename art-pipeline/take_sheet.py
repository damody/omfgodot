"""Contact sheet of a take's registered frames on grey, for review before the forge's own review exists.

usage: take_sheet.py TAKE_DIR OUT.png [START END [COUNT]]
"""
import pathlib
import sys

from PIL import Image, ImageDraw

take, out = pathlib.Path(sys.argv[1]), sys.argv[2]
files = sorted((take / "registered" / "frames").glob("*.png")) or sorted((take / "keyed").rglob("*.png"))
start = int(sys.argv[3]) if len(sys.argv) > 3 else 0
end = int(sys.argv[4]) if len(sys.argv) > 4 else len(files)
count = int(sys.argv[5]) if len(sys.argv) > 5 else 16
picks = [start + round(i * (end - 1 - start) / max(count - 1, 1)) for i in range(count)]
first = Image.open(files[0])
scale = 200 / first.height
cell = (round(first.width * scale), 200)
columns = 8
sheet = Image.new("RGB", (cell[0] * columns, (cell[1] + 14) * ((count + columns - 1) // columns)), (118, 118, 118))
draw = ImageDraw.Draw(sheet)
for i, pick in enumerate(picks):
    frame = Image.open(files[pick]).convert("RGBA").resize(cell)
    x, y = (i % columns) * cell[0], (i // columns) * (cell[1] + 14)
    sheet.paste(frame, (x, y), frame)
    draw.text((x + 4, y + cell[1]), f"#{pick}", fill=(255, 255, 255))
sheet.save(out)
print(out)
