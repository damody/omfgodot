//! `map_layout MAP_ID > layout.json`. Reads only the compiled catalog, so art always tracks gameplay.

use omoba_template_ids::{moba_map_by_name, MobaBoundsConst, MobaTeamPointConst, MobaTerrainConst};
use serde_json::{json, Value};

fn rects(items: &[MobaTerrainConst]) -> Value {
    items.iter().map(|r| json!({"id": r.id, "min": r.min, "max": r.max})).collect()
}

fn points(items: &[MobaTeamPointConst]) -> Value {
    items.iter().map(|p| json!({"team": p.team, "position": p.position})).collect()
}

fn bounds(item: Option<MobaBoundsConst>) -> Value {
    item.map_or(Value::Null, |b| json!({"min": b.min, "max": b.max}))
}

fn main() {
    let id = std::env::args().nth(1).expect("usage: map_layout MAP_ID");
    let map = moba_map_by_name(&id).unwrap_or_else(|| panic!("unknown map {id}"));
    let trees = map.trees();
    let layout = json!({
        "id": map.id,
        "bounds": bounds(map.bounds),
        "world_bounds": bounds(map.world_bounds),
        "minimap_bounds": bounds(map.minimap_bounds),
        "terrain": rects(map.terrain),
        "brushes": rects(map.brushes),
        "surfaces": map.presentation_surfaces.iter().map(|s| json!({
            "id": s.id, "kind": s.kind as i32, "width": s.width, "points": s.points,
        })).collect::<Value>(),
        "lanes": map.lanes.iter().map(|l| json!({
            "id": l.id, "team": l.team, "waypoints": l.waypoints,
        })).collect::<Value>(),
        "camps": map.jungle_camps.iter().map(|c| json!({"id": c.id, "position": c.position})).collect::<Value>(),
        "towers": map.towers.iter().map(|t| json!({
            "team": t.team, "lane": t.lane, "tier": t.tier, "position": t.position,
        })).collect::<Value>(),
        "barracks": map.barracks.iter().map(|b| json!({
            "team": b.team, "lane": b.lane, "position": b.position,
        })).collect::<Value>(),
        "general_towers": points(map.general_towers),
        "bases": points(map.bases),
        "fountains": points(map.fountains),
        "hero_spawns": points(map.hero_spawns),
        "trees": {
            "radius": trees.radius,
            "items": trees.trees.iter().map(|t| json!({
                "position": t.position, "kind": t.kind, "variant": t.variant,
            })).collect::<Value>(),
        },
    });
    println!("{}", serde_json::to_string_pretty(&layout).expect("layout serializes"));
}
