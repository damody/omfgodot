"""Write the master specs for the shared match cast next to this file."""
import json
import pathlib

HERE = pathlib.Path(__file__).parent
STYLE = {
    "path": "../work/saika/master/master.png",
    "what": "an approved hero sprite from the same game",
    "do_not_copy": "his face, armor colours or rifle",
}
EXTRA = "Painterly hand-illustrated game sprite: bold readable silhouette at small size, clean dark outline, simple cel shading with one warm light from the upper left."
VIEW = "side view (profile to three-quarter), seen from a slightly raised camera"
UNITS = {
    "lane_melee": ("a Sengoku-era Japanese foot soldier with a spear, full body",
                   "stocky ashigaru footman in a plain dark iron jingasa hat, simple dull-iron chest plate over a faded grey-brown tunic, tied shin guards, straw sandals, holding a long yari spear angled forward in both hands",
                   "ready stance, feet apart and flat on the ground"),
    "lane_caster": ("a Sengoku-era Japanese archer, full body",
                    "lean ashigaru archer in a plain jingasa hat, light dull-iron chest plate over a faded grey-brown tunic, tied shin guards, straw sandals, a tall asymmetric yumi bow in the left hand and a quiver at the hip",
                    "relaxed stance with the bow held low, feet apart and flat on the ground"),
    "lane_siege": ("a small Sengoku-era Japanese wheeled bronze cannon pushed by one soldier, full body",
                   "low wooden two-wheel gun carriage with a short bronze cannon barrel pointing forward, one ashigaru in a plain jingasa hat standing behind it with both hands on the carriage",
                   "stationary, wheels and feet on the ground"),
    "lane_cavalry": ("a Sengoku-era Japanese mounted samurai on horseback, full body",
                     "armored rider in dull-iron lamellar with a plain kabuto helmet on a sturdy dark bay horse with simple tack, holding a short spear upright",
                     "horse standing with all four hooves flat on the ground"),
}
PROPS = {
    "tower": ("a Sengoku-era Japanese wooden watchtower, full structure",
              "square timber yagura watchtower on a low cut-stone base, tiled dark grey roof, wooden railing around the top platform, plain unpainted wood, no flags"),
    "barracks": ("a Sengoku-era Japanese barracks hall, full structure",
                 "low wide timber hall on a stone footing with a dark tiled roof and a wide open doorway, plain unpainted wood, no flags"),
    "base": ("a Sengoku-era Japanese castle keep, full structure",
             "compact three-tier castle keep with white plaster walls, dark curved tiled roofs and a heavy cut-stone base, no flags"),
}
for name, (subject, identity, pose) in UNITS.items():
    (HERE / f"{name}.json").write_text(json.dumps({
        "schema": "generate2dsprite.master_spec.v1", "name": name, "subject": subject, "identity": identity,
        "pose": pose, "facing": "right", "view": VIEW, "class": "mob", "finish": "hd",
        "genre": "for a top-down fantasy MOBA game", "pronoun": "they", "extra": EXTRA, "style_ref": STYLE,
        "extra_bans": ["no smoke", "no ground shadow"],
    }, indent=1), encoding="utf-8")
for name, (subject, identity) in PROPS.items():
    (HERE / f"{name}.json").write_text(json.dumps({
        "schema": "generate2dsprite.master_spec.v1", "name": name, "subject": subject, "identity": identity,
        "facing": "none", "view": "three-quarter view from a raised camera", "class": "prop", "finish": "hd",
        "genre": "for a top-down fantasy MOBA game", "extra": EXTRA, "style_ref": STYLE,
        "extra_bans": ["no characters", "no ground", "no ground shadow"],
    }, indent=1), encoding="utf-8")
