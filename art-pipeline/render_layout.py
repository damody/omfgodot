"""Draw a map_layout JSON as a flat guide image and a collision overlay for review.

usage: render_layout.py LAYOUT.json OUT.png [--size 1536] [--over ART.png]
Writes the transform beside OUT as OUT.json (world = origin + pixel * world_per_px, y up).
"""
import argparse
import json

from PIL import Image, ImageDraw

parser = argparse.ArgumentParser()
parser.add_argument("layout")
parser.add_argument("out")
parser.add_argument("--size", type=int, default=1536)
parser.add_argument("--over")
parser.add_argument("--no-walls", action="store_true", help="leave out walls: the game builds them as 3D geometry")
args = parser.parse_args()

layout = json.load(open(args.layout, encoding="utf-8"))
xs, ys = [], []
for rect in layout["terrain"] + layout["brushes"]:
    xs += [rect["min"][0], rect["max"][0]]
    ys += [rect["min"][1], rect["max"][1]]
for lane in layout["lanes"]:
    xs += [p[0] for p in lane["waypoints"]]
    ys += [p[1] for p in lane["waypoints"]]
bounds = layout["bounds"] or {"min": [min(xs), min(ys)], "max": [max(xs), max(ys)]}
x0, y0 = bounds["min"]
x1, y1 = bounds["max"]
scale = args.size / max(x1 - x0, y1 - y0)
width, height = round((x1 - x0) * scale), round((y1 - y0) * scale)


def px(point):
    return ((point[0] - x0) * scale, (y1 - point[1]) * scale)


def box(rect):
    ax, ay = px(rect["min"])
    bx, by = px(rect["max"])
    return [min(ax, bx), min(ay, by), max(ax, bx), max(ay, by)]


if args.over:
    image = Image.open(args.over).convert("RGB").resize((width, height))
    overlay = True
else:
    image = Image.new("RGB", (width, height), (96, 138, 72))
    overlay = False
draw = ImageDraw.Draw(image, "RGBA")

if not overlay:
    for surface in layout["surfaces"]:
        if surface["kind"] == 1:
            draw.line([px(p) for p in surface["points"]], fill=(60, 120, 190, 255), width=max(2, round(surface["width"] * scale)))
        elif surface["kind"] == 2 and len(surface["points"]) >= 2:
            a, b = px(surface["points"][0]), px(surface["points"][1])
            draw.rectangle([min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1])], fill=(58, 96, 52, 255))
    for lane in layout["lanes"]:
        draw.line([px(p) for p in lane["waypoints"]], fill=(186, 160, 112, 255), width=max(6, round(300 * scale)))

wall = (255, 0, 0, 110) if overlay else (70, 66, 62, 255)
brush = (255, 255, 0, 70) if overlay else (34, 78, 40, 255)
for rect in [] if args.no_walls else layout["terrain"]:
    draw.rectangle(box(rect), fill=wall)
for rect in layout["brushes"]:
    draw.rectangle(box(rect), fill=brush)
radius = layout["trees"]["radius"] * scale
for tree in layout["trees"]["items"]:
    x, y = px(tree["position"])
    draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=wall)
if overlay:
    for lane in layout["lanes"]:
        draw.line([px(p) for p in lane["waypoints"]], fill=(0, 255, 255, 200), width=2)

image.save(args.out)
json.dump({"origin": [x0, y1], "world_per_px": 1 / scale, "size": [width, height]},
          open(args.out.rsplit(".", 1)[0] + ".json", "w"))
print(json.dumps({"status": "ok", "size": [width, height], "terrain": len(layout["terrain"]),
                  "brushes": len(layout["brushes"]), "trees": len(layout["trees"]["items"]),
                  "lanes": len(layout["lanes"])}))
