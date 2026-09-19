# Phase 6 — UI and race flow

The default launch scene is now `scenes/ui/Main.tscn`. The original standalone
`scenes/track/Track.tscn` remains available for driving/asset verification. This
phase adds presentation and navigation; no movement, camera, glide, AI, checkpoint,
item effect, boost-pad or collision implementation was changed.

## Player flow

Title → Character Select → Track Select → Countdown → Race → Results.

- **Title:** live kart/rider display, Play, Options and Quit.
- **Options:** an explicit future-settings placeholder plus current controls and
  a Main Menu button. There are no pretend settings.
- **Character Select:** male/female defaults from Phase 5b. The preview is an
  isolated SubViewport with the actual rigged model, animated idle and slow
  turntable motion. Selecting a body immediately updates the model and outfit.
- **Track Select:** a scrollable list generated from the track catalog. Skyline
  Loop is the display name for the existing Loop 01 circuit. The route preview
  comes from its TrackRoute, with the glide gap shown dashed. Start Race loads
  the selected scene and applies the selected rider before the scene enters
  the tree and its existing countdown begins.
- **Race HUD:** ordinal position, current/total laps, timer, held item and its
  description, speed, drift/boost meter, countdown/recovery/wrong-way messages
  and a live four-racer minimap. The player's white-ringed cyan marker contrasts
  with the coral/green/gold CPU markers. The map shows accepted route progress,
  not an independently calculated race position.
- **Pause:** Resume, Choose Track and Main Menu. Pausing freezes the race and
  countdown; menus continue to animate. Leaving frees the active race and clears
  RaceManager registrations. The mouse-accessible Pause button also works.
- **Results:** all four authoritative finishing positions and times, with the
  player highlighted and the selected character's live victory pose. Race Again
  returns to track select; Main Menu returns to title. A player who finishes
  ahead of CPUs sees a waiting message until the full field finishes.

Character/track Back buttons and Esc/gamepad B preserve selections. In the race,
Esc, Enter or gamepad Start opens pause; B/Esc resumes from pause. Arrow keys,
Tab/Shift+Tab, D-pad and the left stick navigate menus; Enter/Space/gamepad A
confirm, and mouse clicks work. Explicit A/B mappings supplement the engine's
menu defaults. Race controls are unchanged (WASD/arrows, Space drift, E item,
R recovery; left stick, RT/LT, A drift, X item, Y recovery).

Enter/Start does **not** silently restart a race in the new flow. The flow adapter
disables only the standalone track's restart input handler. Its original debug
HUDs and local player name label are hidden while the new HUD is active. The
standalone track retains its original HUDs and restart behavior.

## Selection and presentation boundaries

| File | Responsibility |
| --- | --- |
| `scripts/ui/menu/game_session.gd` | Autoload storing `selected_character_id` and `selected_track_id` |
| `resources/ui/default_catalog.tres` | Driver and track entries; all asset/scene lookup stays local |
| `resources/ui/driver_entry.gd` | Stable driver ID, display text, existing default CharacterLook |
| `resources/ui/track_entry.gd` | Stable track ID, display text/features, PackedScene, route and glide metadata |
| `scripts/ui/menu/menu_flow.gd` | Navigation, focus, race scene lifecycle and presentation adapter |
| `scripts/ui/menu/driver_preview.gd` | Isolated live 3D preview using existing Blender assets |
| `scripts/ui/menu/race_overlay.gd` | Read-only live HUD |
| `scripts/ui/menu/track_map.gd` | Route drawing and live RaceManager progress markers |
| `scripts/ui/menu/ui_skin.gd` | Shared theme, typography and number/time formatting |

IDs are `char_body_male`, `char_body_female`, and `loop_01`. Selections persist
for the running session and are validated against the catalog. Disk persistence,
full part/color customization and networking remain outside this phase. Phase
6.5 can extend the selection data and the existing CharacterLook resolver without
replacing the screen flow. Additional tracks are catalog entries, not new menu
screens; their names, descriptions and feature captions come from those entries.
A playable track scene follows the existing Player/Items/rider presentation
contract in the centralized adapter.

The UI polls RaceManager's public snapshots and the actual player inventory.
It does not keep another lap counter, ranking algorithm, timer or held-item state.
Results copy `get_standings()` when `race_finished` fires, before cleanup. The
full-field finish event is deferred to the UI transition so physics signal
callbacks are not disrupted by scene removal.

The menu root and UI continue processing while paused; the loaded race is
explicitly pausable. Menu previews instantiate only visual assets and animation,
never a CharacterBody kart or race registration. Existing art is reused without
re-exporting it. Background accents are UI drawing. System fonts use Avenir Next
with DejaVu Sans/Arial/default fallbacks; no font download or plugin is required.

## Verification

Verified through Godot MCP on Godot 4.7.2 / macOS / Metal. The test scene uses
actual key, gamepad and mouse events to traverse the same buttons as a player.
Only driving is automated, by attaching the established KartAI input component
to the player slot. Both races physically complete three laps with items, pads,
ordered checkpoints and the glide gap; no checkpoint/finish state is mocked.

`scenes/test/UIFlowVerification.tscn` exercises:

- Title → Options → Back, gamepad confirm/cancel, and keyboard focus navigation.
- Both live body previews, advancing skeletal animation and selection persistence.
- Track selection, mouse Start, real locked countdown and selected rider application.
- Pause/resume during countdown and while driving; race clock and kart stay frozen.
- Every-frame HUD lap/position/item comparisons against authoritative systems.
- Two full races, correct four-row results, 24 gates and three landings per racer.
- Race Again → Track Select → change character → fresh race with an empty inventory.
- Results → Main Menu, unfinished-race exit, cleanup and all selection Back paths.

Both seeded races finish in this order:

| Position | Racer | Finish time |
| --- | --- | --- |
| 1st | CPU 2 | 00:42.87 |
| 2nd | CPU 3 | 00:47.22 |
| 3rd | Player | 00:49.82 |
| 4th | CPU 1 | 00:50.02 |

There are zero invalid gate crossings or race recoveries. Male/female selection
and pausing preserve the existing seeded race outcome. Example live HUD samples:

| Race time | Lap | Position | Held item | Last checkpoint |
| --- | --- | --- | --- | --- |
| 10.02 s | 1 / 3 | 4th / 4 | Empty | 4 |
| 20.02 s | 2 / 3 | 4th / 4 | Banana | 1 |
| 30.03 s | 2 / 3 | 3rd / 4 | Empty | 7 |
| 40.05 s | 3 / 3 | 2nd / 4 | Shell | 4 |

The final rendered Godot MCP run passed **83 checks**, including **12,686 frames**
of HUD comparisons. The documented headless command passed **74 checks** (the
nine screenshot checks are skipped), exited successfully and reported no leaked
objects. Both final import and runtime logs contain **zero errors or warnings**.

The latest headless report is `artifacts/phase_6/ui-flow-report.json`; the full
rendered MCP log is `godot-flow-final.json`. The screenshots were rendered in-engine and visually
inspected: `title-screen.png`, `character-select-male.png`,
`character-select-female.png`, `track-select.png`, `race-hud.png`,
`results-screen.png`, plus `options.png`, `countdown.png` and `pause-menu.png`.
Artifacts are local and ignored by Git.

The first verification caught missing engine-default gamepad accept/cancel
bindings; explicit project mappings fixed them. A synthetic mouse coordinate
issue in the QA harness was corrected to use viewport-local events under window
stretching. Neither issue remains in the final verification.

```sh
godot --headless --editor --path . --import --quit
godot --headless --fixed-fps 60 --path . res://scenes/test/UIFlowVerification.tscn -- --phase6-check
```

Omit `--headless` and `--fixed-fps 60` for live previews/screenshots. On this Mac,
use `/Applications/Godot.app/Contents/MacOS/Godot`. Windows/Linux execution and a
physical gamepad feel-check are not claimed by the automated macOS run.
