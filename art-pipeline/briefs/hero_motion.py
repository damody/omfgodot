"""Replace the generic attack and cast motions of a hero's set_plan.json with weapon-specific ones.

usage: hero_motion.py SET_PLAN HERO
"""
import json
import math
import pathlib
import sys

END = " Then returns to the exact same ready stance as the start and holds still. Only once, no spinning, no jumping, no leaving the frame. The feet stay planted."
BOW = ("starts in {pos} ready stance, raises the bow level, pulls the string straight back to the cheek, holds for a beat, "
       "releases so the string snaps forward with the bow arm steady, then lowers the bow. No arrow ever flies off: "
       "the string is released empty and nothing detaches from the character." + END)
BOW_CAST = ("starts in {pos} ready stance, lifts the bow high overhead in one hand with the other arm sweeping outward, "
            "holds that pose for a beat, then lowers the bow." + END)
MOTIONS = {
    "murakami_yoshikiyo": (
        "starts in {pos} ready stance, heaves the axe up over one shoulder with both hands, then swings it down in ONE heavy chop {toward}, the blade stopping low in front for a moment." + END,
        "starts in {pos} ready stance, lifts the axe overhead in both hands, then slams the axe head straight down onto the ground in front, leaning into the blow." + END),
    "date_masamune": (
        "starts in {pos} ready stance, pulls the katana back to the hip, then cuts in ONE fast horizontal slash {toward} at chest height, holding the follow-through for a moment." + END,
        "starts in {pos} ready stance, raises the katana upright before the face with both hands, then thrusts the free hand forward {toward} and holds it for a beat." + END),
    "honda_tadakatsu": (
        "starts in {pos} ready stance, swings the long spear down to level with both hands, then drives it in ONE straight powerful thrust {toward}, holding the extended thrust for a moment." + END,
        "starts in {pos} ready stance, lifts the long spear a little, then stamps its butt hard onto the ground while standing tall with the chest out, holding for a beat." + END),
    "sanada_yukimura": (
        "starts in {pos} ready stance, draws the spear back along the body, then drives it in ONE fast straight thrust {toward}, holding the extended thrust for a moment." + END,
        "starts in {pos} ready stance, raises the spear high overhead in one hand like a rallying signal with the free fist clenched, holding for a beat." + END),
    "asai_nagamasa": (
        "starts in {pos} ready stance, brings the long sword back low behind the body, then sweeps it in ONE wide rising slash {toward}, holding the follow-through high for a moment." + END,
        "starts in {pos} ready stance, lifts the long sword to a high two-handed guard above the head, then brings it straight down in one clean vertical cut, holding low for a beat." + END),
    "inahime": (BOW, BOW_CAST),
    "tamako": (BOW, BOW_CAST),
    "oichi": (
        "starts in {pos} ready stance, tilts the ringed staff forward {toward} with a small sharp push of the arm so its rings swing, holding it extended for a moment." + END,
        "starts in {pos} ready stance, raises the ringed staff high with one arm and lifts the free hand upward in prayer, face turned up slightly, holding for a beat." + END),
    "omatsu": (
        "starts in {pos} ready stance, draws the open fan back beside the shoulder, then sweeps it in ONE fast flat arc {toward}, holding the follow-through for a moment." + END,
        "starts in {pos} ready stance, lifts the open fan up in front of the chest, then extends the free hand forward {toward} with fingers spread, holding for a beat." + END),
    "saika_magoichi": (
        "starts in {pos} ready stance, brings the long rifle up to the shoulder and aims level {toward}, holds for a beat, then the whole upper body jolts back once with recoil, then lowers the rifle." + END,
        "starts in {pos} ready stance, lifts the rifle upright beside the head with one hand and brings the other hand to the belt pouch, holding for a beat." + END),
}

path, hero = pathlib.Path(sys.argv[1]), sys.argv[2]
plan = json.loads(path.read_text(encoding="utf-8"))
attack, cast = MOTIONS[hero]
pronoun = plan.get("pronoun") or "they"
pos = {"he": "his", "she": "her"}.get(pronoun, "their")
WALK_CLAUSE = ("The hands keep the weapon in one fixed carrying position against the body for the whole cycle: "
               "it never swings, lifts or changes angle. Only the legs and hips move, at one steady marching pace.")
SHRINK = 0.76
# A drawn longbow is taller than the archer: give it more room.
SHRINK_BY_HERO = {"inahime": 0.64, "tamako": 0.64}


def shrink(place: dict) -> None:
    """Same transform as sprite_set.placement, smaller: a raised weapon stays inside the frame."""
    width, height = place["canvas"]
    side = height  # masters are square
    ax, ay = place["anchor"]
    x0, y0, x1, y1 = place["subjectBox"]
    offset = (place["root"][0] - place["scale"] * ax, place["root"][1] - place["scale"] * ay)
    box = [(x0 - offset[0]) / place["scale"], (y0 - offset[1]) / place["scale"],
           (x1 - offset[0]) / place["scale"], (y1 - offset[1]) / place["scale"]]
    scale = SHRINK_BY_HERO.get(hero, SHRINK)
    offset = (place["root"][0] - scale * ax, place["root"][1] - scale * ay)
    place["scale"] = scale
    place["subjectBox"] = [round(offset[0] + scale * box[0], 2), round(offset[1] + scale * box[1], 2),
                           round(offset[0] + scale * box[2], 2), round(offset[1] + scale * box[3], 2)]
    place["padding"] = [max(0, math.ceil(offset[0] / scale)), max(0, math.ceil(offset[1] / scale)),
                        max(0, math.ceil((width - offset[0]) / scale - side)),
                        max(0, math.ceil((height - offset[1]) / scale - side))]
    place["headroom"] = round(place["subjectBox"][1] / height, 4)


# A speck of key spill in one frame fails packaging; import_sprite_set.py repaints such specks.
plan["package"]["allowKeyResidue"] = True
# The game reads only the PNG atlas; video transports refuse a clip with uneven frame times.
plan["package"]["formats"] = ["png"]
for entry in plan["actions"]:
    if entry["action"] == "walk" and WALK_CLAUSE not in entry["negatives"]:
        entry["negatives"] = (WALK_CLAUSE + " " + entry["negatives"]).strip()
        entry["prompt"] = entry["prompt"].replace("Constant character size.", WALK_CLAUSE + " Constant character size.", 1)
    if entry["action"] in ("attack", "cast") and entry["placement"]["scale"] == 1.0:
        shrink(entry["placement"])
    if entry["action"] == "defeat":
        # Grok plays a fall in 3-5 s. Keep such a clip and compress it to game length.
        entry["gates"]["timing"]["maxSeconds"] = 6.0
        entry["timing"] = {"mode": "auto", "durationMs": 1100, "keys": {"peak": {"at": 0.6}}}
    new = {"attack": attack, "cast": cast}.get(entry["action"])
    if new is None:
        continue
    new = new.replace("{pos}", pos).replace("{toward}", "to the RIGHT")
    # The plan stores both the template and the composed prompt.
    old = entry["motion"].replace("{pos}", pos).replace("{toward}", "to the RIGHT")
    if old in entry["prompt"]:
        entry["prompt"] = entry["prompt"].replace(old, new)
    else:
        sys.exit(f"error: cannot place the {entry['action']} motion in its prompt")
    entry["motion"] = new
path.write_text(json.dumps(plan, indent=2, ensure_ascii=False), encoding="utf-8")
