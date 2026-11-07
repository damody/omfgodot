//! Godot face of om_bridge. All wire decoding and fail-closed validation stay in the bridge;
//! this crate only copies a leased frame into Godot types before releasing the lease.

use std::collections::{HashMap, HashSet};
use std::ffi::c_char;
use std::ptr;

use godot::prelude::*;
use om_bridge::{
    om_abi_version, om_acquire_latest_frame, om_acquire_runtime_catalog, om_last_error,
    om_mark_frame_consumed, om_poll_session_status, om_release_frame, om_release_runtime_catalog,
    om_runtime_create, om_runtime_destroy, om_runtime_start, om_runtime_stop, om_submit_input,
    OmAbilityEventKind, OmCatalogLease, OM_ABILITY_EVENT_FLAG_CUE, OmEntityRef, OmFrameLease, OmInputCommand, OmInputCommandKind,
    OmInputSubmitResult, OmInputTargetKind, OmRuntime, OmRuntimeConfig, OmSessionStatus, OmStatus,
    OmStringRef, OmStringView, OmVec2, OM_ABI_VERSION, OM_INPUT_FLAG_QUEUED,
    OM_RUNTIME_FLAG_PRESENTATION_IPC,
};

struct OmGodotExtension;

#[gdextension]
unsafe impl ExtensionLibrary for OmGodotExtension {}

fn view(text: &str) -> OmStringView {
    OmStringView { data: text.as_ptr() as *const c_char, len: text.len() }
}

/// One presentation-IPC session. Field layout of the unit rows is `UNIT_STRIDE` floats.
#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct OmSession {
    runtime: Option<*mut OmRuntime>,
    player_id: u32,
    last_sequence: u64,
    tick: u64,
    ids: PackedInt64Array,
    units: PackedFloat32Array,
    terrain: PackedFloat32Array,
    routes: Array<PackedVector2Array>,
    phase: i64,
    winner_team: i64,
    elapsed_seconds: f64,
    owner_hero: i64,
    generations: HashMap<u64, u32>,
    abilities: Array<VarDictionary>,
    ability_catalog: HashMap<u32, AbilityInfo>,
    unit_catalog: HashMap<(u32, u32), String>,
    hud: VarDictionary,
    fog_cells: PackedByteArray,
    fog_info: VarDictionary,
    items: Array<VarDictionary>,
    casts: Vec<i64>,
    seen_casts: HashSet<u64>,
}

#[derive(Clone)]
struct AbilityInfo {
    id: String,
    name: String,
    target_type: String,
    cast_range: f32,
}

unsafe fn table_string(table: *const c_char, table_len: usize, reference: OmStringRef) -> String {
    let (start, end) = (reference.offset as usize, reference.offset as usize + reference.len as usize);
    if table.is_null() || end > table_len {
        return String::new();
    }
    let bytes = std::slice::from_raw_parts(table as *const u8, table_len);
    String::from_utf8_lossy(&bytes[start..end]).into_owned()
}

unsafe fn rows<'a, T>(data: *const T, count: u32) -> &'a [T] {
    if count == 0 || data.is_null() {
        &[]
    } else {
        std::slice::from_raw_parts(data, count as usize)
    }
}

#[godot_api]
impl OmSession {
    /// x, y, facing_rad, hp, max_hp, kind, team_id, relation_flags, catalog_id, entity_flags,
    /// locomotion_state, action_state, action_progress, catalog_kind.
    #[constant]
    pub const UNIT_STRIDE: i32 = 14;

    #[func]
    pub fn abi_version() -> i64 {
        i64::from(om_abi_version())
    }

    /// Connects to `omoba-client-runtime --presentation-bind`. Returns false with `last_error` set.
    #[func]
    pub fn start(&mut self, presentation_address: GString, player_id: i64, team_id: i64) -> bool {
        if self.runtime.is_some() {
            return false;
        }
        let address = presentation_address.to_string();
        let config = OmRuntimeConfig {
            struct_size: std::mem::size_of::<OmRuntimeConfig>() as u32,
            abi_version: OM_ABI_VERSION,
            server_address: view(&address),
            player_name: view("godot"),
            player_id: player_id as u32,
            script_dll_path: view(""),
            content_root: view(""),
            story_id: view(""),
            world_units_to_cm: 1.0,
            flags: OM_RUNTIME_FLAG_PRESENTATION_IPC,
            team_id: team_id as u32,
        };
        let mut runtime = ptr::null_mut();
        unsafe {
            if om_runtime_create(&config, &mut runtime) != OmStatus::Ok {
                return false;
            }
            if om_runtime_start(runtime) != OmStatus::Ok {
                om_runtime_destroy(runtime);
                return false;
            }
        }
        self.runtime = Some(runtime);
        self.player_id = player_id as u32;
        true
    }

    #[func]
    pub fn stop(&mut self) {
        if let Some(runtime) = self.runtime.take() {
            unsafe {
                om_runtime_stop(runtime);
                om_runtime_destroy(runtime);
            }
        }
    }

    /// Latest-wins. True when a newer frame was copied into `unit_ids` and `unit_rows`.
    #[func]
    pub fn poll_frame(&mut self) -> bool {
        let Some(runtime) = self.runtime else { return false };
        let mut lease = OmFrameLease {
            struct_size: std::mem::size_of::<OmFrameLease>() as u32,
            slot_index: u32::MAX,
            sequence: 0,
            frame: ptr::null(),
        };
        unsafe {
            if om_acquire_latest_frame(runtime, &mut lease) != OmStatus::Ok {
                return false;
            }
            let fresh = lease.sequence != self.last_sequence;
            if fresh {
                let frame = &*lease.frame;
                self.last_sequence = lease.sequence;
                self.tick = frame.tick;
                let entities = rows(frame.entities, frame.entity_count);
                let animations = rows(frame.animation_states, frame.animation_state_count);
                // A frame without entities that is not a snapshot only carries events: the units stay,
                // minus the ones it removes (as the UE world bridge reads it). Taking it as the full list
                // emptied the world for a frame and rebuilt every unit on the next one.
                if entities.is_empty() && frame.presentation_snapshot == 0 {
                    self.forget_removed(rows(frame.removed_entities, frame.removed_entity_count));
                } else {
                    self.ids = entities.iter().map(|row| row.entity.entity_id as i64).collect();
                    self.generations = entities.iter().map(|row| (row.entity.entity_id, row.entity.entity_gen)).collect();
                    self.units = entities
                        .iter()
                        .flat_map(|row| {
                            let animation = animations.iter().find(|state| state.entity.entity_id == row.entity.entity_id);
                            [
                                row.position.x,
                                row.position.y,
                                row.facing_rad,
                                row.hp,
                                row.max_hp,
                                row.kind as i32 as f32,
                                row.team_id as f32,
                                row.relation_flags as f32,
                                row.catalog_id as f32,
                                row.flags as f32,
                                animation.map_or(0.0, |state| state.locomotion_state as i32 as f32),
                                animation.map_or(0.0, |state| state.action_state as i32 as f32),
                                animation.map_or(0.0, |state| state.phase_progress),
                                row.catalog_kind as f32,
                            ]
                        })
                        .collect();
                }
                // Accumulates until `take_casts`: rendered ticks can be slower than frames.
                // A frame repeats recent events; each cast counts once, by its cue instance. Pure
                // presentation cues ride the same list and are not casts.
                for event in rows(frame.ability_events, frame.ability_event_count) {
                    if event.kind == OmAbilityEventKind::AbilityCast && event.flags & OM_ABILITY_EVENT_FLAG_CUE == 0
                        && self.seen_casts.insert(event.cue_instance_id) {
                        self.casts.push(event.caster.entity_id as i64);
                    }
                }
                if self.seen_casts.len() > 8192 {
                    self.seen_casts.clear();
                }
                // The compiled map is public and immutable: keep the first copy.
                let terrain = rows(frame.terrain_rects, frame.terrain_rect_count);
                if self.terrain.is_empty() && !terrain.is_empty() {
                    self.terrain = terrain.iter().flat_map(|rect| [rect.min.x, rect.min.y, rect.max.x, rect.max.y]).collect();
                }
                let routes = rows(frame.map_routes, frame.map_route_count);
                if self.routes.is_empty() && !routes.is_empty() {
                    let points = rows(frame.map_route_points, frame.map_route_point_count);
                    for route in routes {
                        let start = route.point_start_index as usize;
                        let end = (start + route.point_count as usize).min(points.len());
                        let line: PackedVector2Array = points[start.min(end)..end]
                            .iter()
                            .map(|point| Vector2::new(point.position.x, point.position.y))
                            .collect();
                        self.routes.push(&line);
                    }
                }
                if let Some(hud) = frame.moba_hud.as_ref() {
                    self.phase = i64::from(hud.phase);
                    self.winner_team = i64::from(hud.winner_team);
                    self.elapsed_seconds = f64::from(hud.elapsed_seconds);
                    self.owner_hero = if hud.has_hero != 0 { hud.hero.entity_id as i64 } else { 0 };
                    self.refresh_catalog(runtime);
                    let mut abilities = Array::new();
                    for (slot, ability) in hud.abilities.iter().enumerate() {
                        let info = self.ability_catalog.get(&ability.catalog_id);
                        let mut row = VarDictionary::new();
                        row.set("slot", slot as i64);
                        row.set("catalog_id", i64::from(ability.catalog_id));
                        row.set("level", i64::from(ability.level));
                        row.set("cooldown", ability.cooldown_seconds);
                        row.set("cost_state", i64::from(ability.mana_cost_state));
                        row.set("name", info.map_or("", |i| i.name.as_str()));
                        row.set("ability_id", info.map_or("", |i| i.id.as_str()));
                        row.set("target_type", info.map_or("", |i| i.target_type.as_str()));
                        row.set("cast_range", info.map_or(0.0, |i| i.cast_range));
                        abilities.push(&row);
                    }
                    self.abilities = abilities;
                    let mut summary = VarDictionary::new();
                    summary.set("has_hero", hud.has_hero != 0);
                    summary.set("hp", hud.hp);
                    summary.set("max_hp", hud.max_hp);
                    summary.set("level", i64::from(hud.level));
                    summary.set("skill_points", i64::from(hud.skill_points));
                    summary.set("respawn", hud.respawn_remaining_seconds);
                    summary.set("recall", hud.recall_remaining_seconds);
                    summary.set("mana_supported", hud.mana_supported != 0);
                    summary.set("mana", hud.mana);
                    summary.set("max_mana", hud.max_mana);
                    if let Some(economy) = frame.owner_economy.as_ref() {
                        summary.set("gold", i64::from(economy.gold));
                        let mut items = Array::new();
                        for (slot, item) in economy.slots.iter().enumerate() {
                            let mut row = VarDictionary::new();
                            row.set("slot", slot as i64);
                            row.set("catalog_id", i64::from(item.catalog_id));
                            row.set("cooldown", item.cooldown_seconds);
                            row.set("name", table_string(frame.string_table, frame.string_table_len, item.display_name).as_str());
                            items.push(&row);
                        }
                        self.items = items;
                    }
                    self.hud = summary;
                }
                if let Some(fog) = frame.fog_grid.as_ref() {
                    self.fog_cells = rows(fog.cells, fog.cell_count).iter().copied().collect();
                    let mut info = VarDictionary::new();
                    info.set("origin_x", fog.origin_x_raw as f64 / 1024.0);
                    info.set("origin_y", fog.origin_y_raw as f64 / 1024.0);
                    info.set("cell_size", fog.cell_size_raw as f64 / 1024.0);
                    info.set("columns", i64::from(fog.columns));
                    info.set("rows", i64::from(fog.rows));
                    info.set("sample_tick", fog.sample_tick as i64);
                    self.fog_info = info;
                } else {
                    // Absence means unavailable, never full visibility.
                    self.fog_info = VarDictionary::new();
                }
                om_mark_frame_consumed(runtime, lease);
            }
            om_release_frame(runtime, lease);
            fresh
        }
    }

    #[func]
    pub fn tick(&self) -> i64 {
        self.tick as i64
    }

    #[func]
    pub fn unit_ids(&self) -> PackedInt64Array {
        self.ids.clone()
    }

    #[func]
    pub fn unit_rows(&self) -> PackedFloat32Array {
        self.units.clone()
    }

    /// Entity ids that started an ability cast since the previous call.
    #[func]
    pub fn take_casts(&mut self) -> PackedInt64Array {
        let casts = self.casts.iter().copied().collect();
        self.casts.clear();
        casts
    }

    /// 0 move, 1 attack-move, 2 attack unit, 3 stop, 4 hold, 5 recall.
    #[func]
    pub fn submit_order(&mut self, order: i64, target: i64, x: f32, y: f32, queued: bool) -> bool {
        let kind = match order {
            0 => OmInputCommandKind::InputMove,
            1 => OmInputCommandKind::InputAttackMove,
            2 => OmInputCommandKind::InputAttackTarget,
            3 => OmInputCommandKind::InputStop,
            4 => OmInputCommandKind::InputHoldPosition,
            5 => OmInputCommandKind::InputRecall,
            _ => return false,
        };
        let mut command = self.command(kind);
        command.world_point = OmVec2 { x, y };
        if order == 2 {
            command.target_entity = self.entity_ref(target);
        }
        if queued {
            command.flags = OM_INPUT_FLAG_QUEUED;
        }
        self.submit(&command)
    }

    /// Casts ability `slot` with `target_type` "none", "point" or "unit".
    #[func]
    pub fn submit_cast(&mut self, slot: i64, target_type: GString, target: i64, x: f32, y: f32) -> bool {
        let mut command = self.command(OmInputCommandKind::InputCastAbility);
        command.ability_slot = slot as u32;
        match target_type.to_string().as_str() {
            "point" => {
                command.target_kind = OmInputTargetKind::InputTargetPoint;
                command.world_point = OmVec2 { x, y };
            }
            "unit" => {
                command.target_kind = OmInputTargetKind::InputTargetEntity;
                command.target_entity = self.entity_ref(target);
            }
            _ => {}
        }
        self.submit(&command)
    }

    #[func]
    pub fn submit_upgrade(&mut self, slot: i64) -> bool {
        let mut command = self.command(OmInputCommandKind::InputUpgradeAbility);
        command.ability_slot = slot as u32;
        self.submit(&command)
    }

    /// One row per ability slot: slot, catalog_id, level, cooldown, cost_state, name, target_type, cast_range.
    #[func]
    pub fn ability_rows(&self) -> Array<VarDictionary> {
        self.abilities.clone()
    }

    /// has_hero, hp, max_hp, level, skill_points, respawn. Empty until the HUD is available.
    #[func]
    pub fn hud_summary(&self) -> VarDictionary {
        self.hud.clone()
    }

    /// Six rows of slot, catalog_id, cooldown, name.
    #[func]
    pub fn item_rows(&self) -> Array<VarDictionary> {
        self.items.clone()
    }

    /// Team-private grid, row-major: 0 unseen, 1 explored, 2 visible.
    #[func]
    pub fn fog_cells(&self) -> PackedByteArray {
        self.fog_cells.clone()
    }

    /// origin_x, origin_y, cell_size, columns, rows, sample_tick. Empty when unavailable.
    #[func]
    pub fn fog_info(&self) -> VarDictionary {
        self.fog_info.clone()
    }

    /// The catalog content id of a unit row, empty when unknown.
    #[func]
    pub fn content_id(&self, catalog_kind: i64, catalog_id: i64) -> GString {
        self.unit_catalog.get(&(catalog_kind as u32, catalog_id as u32)).map_or_else(GString::new, |id| GString::from(id.as_str()))
    }

    /// Wall and block rectangles as min_x, min_y, max_x, max_y rows, in world units.
    #[func]
    pub fn terrain_rects(&self) -> PackedFloat32Array {
        self.terrain.clone()
    }

    #[func]
    pub fn lane_routes(&self) -> Array<PackedVector2Array> {
        self.routes.clone()
    }

    /// 0 warmup, 1 playing, 2 finished.
    #[func]
    pub fn match_phase(&self) -> i64 {
        self.phase
    }

    /// 0 means none or draw.
    #[func]
    pub fn winner_team(&self) -> i64 {
        self.winner_team
    }

    #[func]
    pub fn elapsed_seconds(&self) -> f64 {
        self.elapsed_seconds
    }

    /// The player's live hero id, 0 when there is none.
    #[func]
    pub fn owner_hero(&self) -> i64 {
        self.owner_hero
    }

    /// `RuntimeSessionState.State` value, or -1 before a session exists.
    #[func]
    pub fn session_state(&self) -> i64 {
        let Some(runtime) = self.runtime else { return -1 };
        let mut status = OmSessionStatus {
            struct_size: std::mem::size_of::<OmSessionStatus>() as u32,
            abi_version: OM_ABI_VERSION,
            session_state: 0,
            terminated: false,
            safe_reason: OmStringView { data: ptr::null(), len: 0 },
        };
        unsafe {
            if om_poll_session_status(runtime, &mut status) != OmStatus::Ok {
                return -1;
            }
        }
        i64::from(status.session_state)
    }

    #[func]
    pub fn last_error(&self) -> GString {
        let error = unsafe { om_last_error() };
        if error.data.is_null() || error.len == 0 {
            return GString::new();
        }
        let bytes = unsafe { std::slice::from_raw_parts(error.data as *const u8, error.len) };
        GString::from(String::from_utf8_lossy(bytes).as_ref())
    }
}

impl OmSession {
    /// Drops the listed entities from the kept unit rows.
    fn forget_removed(&mut self, removed: &[OmEntityRef]) {
        if removed.is_empty() {
            return;
        }
        let stride = Self::UNIT_STRIDE as usize;
        let units = self.units.as_slice();
        let mut ids = PackedInt64Array::new();
        let mut kept = PackedFloat32Array::new();
        for (index, id) in self.ids.as_slice().iter().enumerate() {
            if removed.iter().any(|entity| entity.entity_id as i64 == *id) {
                self.generations.remove(&(*id as u64));
                continue;
            }
            ids.push(*id);
            kept.extend_array(&PackedFloat32Array::from(&units[index * stride..(index + 1) * stride]));
        }
        self.ids = ids;
        self.units = kept;
    }

    fn command(&self, kind: OmInputCommandKind) -> OmInputCommand {
        // Every field defaults to zero: kind and target_kind have zero variants, the rest are plain data.
        let mut command: OmInputCommand = unsafe { std::mem::zeroed() };
        command.struct_size = std::mem::size_of::<OmInputCommand>() as u32;
        command.abi_version = OM_ABI_VERSION;
        command.kind = kind;
        command.player_id = self.player_id;
        command
    }

    fn entity_ref(&self, id: i64) -> OmEntityRef {
        let entity_id = id as u64;
        OmEntityRef { entity_id, entity_gen: self.generations.get(&entity_id).copied().unwrap_or(0) }
    }

    fn submit(&mut self, command: &OmInputCommand) -> bool {
        let Some(runtime) = self.runtime else { return false };
        let mut result: OmInputSubmitResult = unsafe { std::mem::zeroed() };
        result.status = OmStatus::InvalidArgument;
        let status = unsafe { om_submit_input(runtime, command, &mut result) };
        status == OmStatus::Ok && result.accepted
    }

    fn refresh_catalog(&mut self, runtime: *mut OmRuntime) {
        if !self.ability_catalog.is_empty() {
            return;
        }
        let mut lease = OmCatalogLease { struct_size: std::mem::size_of::<OmCatalogLease>() as u32, generation: 0, catalog: ptr::null() };
        unsafe {
            if om_acquire_runtime_catalog(runtime, &mut lease) != OmStatus::Ok || lease.catalog.is_null() {
                return;
            }
            let catalog = &*lease.catalog;
            for entry in rows(catalog.units, catalog.unit_count) {
                let id = table_string(catalog.string_table, catalog.string_table_len, entry.content_id);
                self.unit_catalog.insert((entry.catalog.kind as i32 as u32, entry.catalog.id), id);
            }
            for entry in rows(catalog.abilities, catalog.ability_count) {
                let text = |reference| table_string(catalog.string_table, catalog.string_table_len, reference);
                self.ability_catalog.insert(entry.catalog.id, AbilityInfo {
                    id: text(entry.ability_id),
                    name: text(entry.display_name),
                    target_type: text(entry.target_type),
                    cast_range: entry.cast_range,
                });
            }
            om_release_runtime_catalog(runtime, lease);
        }
    }
}

impl Drop for OmSession {
    fn drop(&mut self) {
        self.stop();
    }
}
