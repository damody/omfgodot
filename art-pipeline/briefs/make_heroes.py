"""Write the master specs for the nine heroes next to this file; saika_magoichi.json is the style anchor."""
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
# name: pronoun, subject, identity, pose, recap, opaque parts
HEROES = {
    "murakami_yoshikiyo": ("he", "a huge Sengoku-era Japanese warlord with a great battle axe, full body",
        "massive broad-shouldered older man with a thick black beard and bare muscular arms, a low round iron kabuto helmet, heavy earth-brown lamellar chest armor with bronze plates, wide bronze shoulder guards, dark trousers tied at the shin, armored boots; an oversized two-handed ono battle axe with a wide bronze blade, held low in both hands",
        "heavy planted stance, feet wide apart and flat on the ground, axe head resting low in front",
        "huge bearded Sengoku warlord in earth-brown and bronze armor with a round iron helmet, carrying an oversized bronze battle axe",
        "beard, helmet, armor, axe"),
    "date_masamune": ("he", "a one-eyed Sengoku-era Japanese samurai lord with a katana, full body",
        "lean young man wearing a black round eyepatch over the right eye; black lacquered armor with gold trim; a black kabuto helmet with one tall thin golden crescent moon crest; a short deep-blue battle coat with a high collar; black trousers, armored shin guards; a single curved katana held in the right hand, blade pointing low and forward",
        "alert forward-leaning stance, feet apart and flat on the ground, katana held low",
        "one-eyed Sengoku lord in black and gold armor with a tall golden crescent helmet crest and a deep-blue coat, holding a katana",
        "helmet, crest, eyepatch, armor, katana"),
    "honda_tadakatsu": ("he", "a towering Sengoku-era Japanese spear general, full body",
        "tall stern man in matte black lacquered armor; a black kabuto helmet with two large branching deer antlers; a sash of large wooden prayer beads across the chest from shoulder to hip; dark grey trousers, black shin guards; a very long straight yari spear with a narrow steel blade, held upright in the right hand with its butt on the ground",
        "upright unshakable stance, feet apart and flat on the ground, spear standing vertical",
        "tall Sengoku general in black armor with a large deer-antler helmet and a prayer-bead sash, holding a very long straight spear upright",
        "antlers, helmet, armor, prayer beads, spear"),
    "sanada_yukimura": ("he", "a young Sengoku-era Japanese spear warrior in crimson armor, full body",
        "athletic young man entirely in bright crimson-red lacquered armor with gold edging; a crimson kabuto helmet with two short curved golden horns; a long crimson scarf trailing behind; white trousers tied at the shin, crimson shin guards; a cross-bladed jumonji yari spear with a three-pronged steel head, held diagonally forward in both hands",
        "dynamic ready stance, feet apart and flat on the ground, spear angled forward",
        "young Sengoku warrior in bright crimson and gold armor with short golden horns and a crimson scarf, holding a cross-bladed spear forward",
        "helmet, horns, armor, scarf, spear"),
    "asai_nagamasa": ("he", "a noble young Sengoku-era Japanese swordsman, full body",
        "slender handsome young man with a tied black ponytail and no helmet; polished silver-white lamellar armor with teal lacing; a teal sleeveless jinbaori surcoat over the armor; pale grey hakama trousers, white tabi socks and sandals; one very long odachi greatsword with a plain steel blade, held low in both hands with the tip behind him",
        "calm iaido-like stance, feet apart and flat on the ground, long sword trailing low",
        "slender young Sengoku swordsman with a black ponytail, silver-white armor with teal lacing and a teal surcoat, holding a very long greatsword low",
        "hair, armor, surcoat, sword"),
    "inahime": ("she", "a Sengoku-era Japanese warrior woman archer, full body",
        "agile adult woman with a very long high black ponytail; a forest-green short kimono under a light dark-leather chest guard with a violet cord; violet arm guards, dark green hakama trousers tied at the shin, straw sandals; a very tall black asymmetric yumi bow held in the left hand, a green-fletched quiver on the back",
        "composed stance, feet apart and flat on the ground, bow held low and upright",
        "agile Sengoku archer woman with a long high black ponytail, forest-green kimono, dark leather guard with violet cords, holding a very tall black bow",
        "hair, chest guard, bow, quiver"),
    "tamako": ("she", "a Sengoku-era Japanese noble woman archer, full body",
        "graceful young woman with a chin-length straight black bob and a thin golden hair ornament; a midnight-blue short kimono with a scattered pattern of small golden stars, a golden obi sash; pale cream hakama trousers, white tabi socks and sandals; a tall pale ivory-white yumi bow with golden tips held in the left hand, a white-fletched quiver at the hip",
        "elegant stance, feet apart and flat on the ground, bow held low and upright",
        "graceful Sengoku noble archer with a black bob, midnight-blue kimono with small golden stars and a golden sash, holding a tall ivory-white bow",
        "hair, kimono, sash, bow"),
    "oichi": ("she", "a Sengoku-era Japanese noble priestess of light, full body",
        "serene adult woman with very long straight black hair falling to the waist and a small golden crown-like headpiece; layered white and soft rose-pink uchikake robes with pale gold trim reaching the ankles; a golden shakujo staff with hanging rings held upright in the right hand; a thin golden chain wound loosely around the left forearm",
        "serene upright stance, feet together and flat on the ground under the robe hem, staff vertical",
        "serene Sengoku noblewoman with very long black hair and a small gold headpiece, layered white and rose-pink robes, holding a golden ringed staff with a gold chain on her forearm",
        "hair, headpiece, robes, staff"),
    "omatsu": ("she", "a Sengoku-era Japanese noble ice sorceress, full body",
        "poised adult woman with black hair in a tall formal updo held by icy-blue crystal hairpins; a pale ice-blue and white layered kimono with a pattern of large white snowflake flowers, a deep navy obi sash; hem reaching the ankles, white tabi socks and sandals; one open silver-blue tessen war fan held out low in the right hand",
        "poised stance, feet apart and flat on the ground under the kimono hem, open fan held low",
        "poised Sengoku noblewoman with a black updo and icy crystal pins, pale ice-blue and white snowflake kimono with a navy sash, holding an open silver-blue war fan",
        "hair, hairpins, kimono, sash, fan"),
}
for name, (pronoun, subject, identity, pose, recap, opaque) in HEROES.items():
    (HERE / f"{name}.json").write_text(json.dumps({
        "schema": "generate2dsprite.master_spec.v1", "name": name, "subject": subject, "identity": identity,
        "pose": pose, "recap": recap, "facing": "right", "view": VIEW, "class": "hero", "finish": "hd",
        "genre": "for a top-down fantasy MOBA game", "pronoun": pronoun, "opaque_parts": opaque, "extra": EXTRA,
        "style_ref": STYLE, "extra_bans": ["no smoke", "no magic effects", "no ground shadow"],
    }, indent=1), encoding="utf-8")
