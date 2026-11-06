# omfgodot

Godot 4.7 2.5D frontend for omoba. It is meant to sit in an omoba checkout at `omoba/omfgodot` (a submodule) and
holds only the frontend: the backend crates, `omfue/bridge` and the launch libraries come from omoba itself.

- `omgd/game` — the Godot project: match view, HUD, units, fog, and the imported hero art (`art/units/<hero>`).
- `omgd/om_godot` — GDExtension over omoba's `omfue/bridge` (`cargo build --release`; the launcher copies the DLL
  into `omgd/game/bin`).
- `omgd/tools/map_layout` — map layout tool (uses omoba's `omoba-template-ids`).
- `art-pipeline` — scripts and briefs that turn Grok stills and videos into sprite sets and import them
  (`import_heroes.sh`). The raw takes (`work/`), the Python venv and the vendored `forge/` skills are not tracked.
- `scripts/run_moba_role_gd.lua`, `run_gd.bat` — start a backend match and the Godot client; they load omoba's
  `scripts/` libraries and `tools/lua`. Set `GODOT4` to the Godot 4.7 executable.
- `PLAN.md` — the plan and progress table.

Ten heroes have idle, attack, cast, death and five walk views (side, front, back and both diagonals, mirrored for left).
