# Nodekins Racing

Original arcade kart racer built in Godot, with original art authored in Blender.
Current milestone: Phase 6 UI/UX. Launch into Title → Character Select → Track Select
→ Countdown → Race → Results, with keyboard/gamepad/mouse navigation, live character
previews, a race HUD/minimap, pause/exit controls and replay flow. Full customization
remains deferred to Phase 6.5.
See `docs/phase_6.md` for the flow, selection catalog and verification,
`docs/phase_5c.md` for kit exports, snapping conventions and race verification,
`docs/phase_5b.md` for character assets, poses and validation,
`docs/phase_5a.md` for kart assets, sockets and materials,
`docs/phase_4_5.md` for glide tuning, `docs/phase_4.md` for items,
`docs/phase_3.md` for CPU logic, and `docs/phase_2.md` for race rules.

## Current scope

Windows, macOS, and Linux only. Keyboard and gamepad, with gamepad as the reference
for handling tuning. One analog-friendly controller consumes both input sources. Mobile exports, mobile asset budgets, and touch controls are out of scope;
adding them would require a separate decision.

The project uses Godot **4.7.2**, GDScript, Forward+, and the existing Jolt physics setting.
Godot 4.3+ was the requested engine family; use 4.7.2 for this tested baseline and matching
export templates. Older versions have not been validated.

## Run

Open `project.godot` in Godot and press **F5** for the title screen. Choose Play, a
male/female default, and Skyline Loop (the existing Loop 01), then Start Race.
Menus support arrows/Tab, D-pad/left stick, Enter/A and mouse; Esc/B goes back.
Options is a placeholder. The 3–2–1–GO countdown
locks all four karts; pass CP1–CP7 and start/finish in order for three laps.
Esc/Enter/gamepad Start pauses; Resume, Choose Track and Main Menu are available.
Results show the full field, with Race Again and Main Menu buttons. The flat Phase 1 driving lab remains at `scenes/test/TestPlane.tscn`.
Keyboard: WASD/arrows, Space to drift, R for checkpoint recovery. Gamepad: left stick, right trigger
to accelerate, left trigger to brake, south face button to drift, north face button to reset.
Press **E / gamepad west face button** to use the held item. Cyan boxes refill after four seconds.
Hold drift while steering; release after charging cyan/amber/violet for a mini-turbo.
Cross the lime chevron pads before the tunnel for a two-second boost; they preserve your held item.
Drive up the marked launch ramp at speed to glide automatically across the 16 m gap. Steering
allows gentle airborne corrections; landing retracts the wing automatically. Banana
stays in the item slot until landing; Boost and Shell can be used in the air.
The HUD shows lap, ordinal position, timer, held item, speed, mini-turbo charge and
a live circuit minimap. CPU paint/markers are coral, green, and gold.
The standalone `scenes/track/Track.tscn` still provides the old diagnostic HUD and
Enter/Start restart for development checks.

For a repeatable check from the repository root (`godot` must be on PATH):

```sh
godot --headless --editor --path . --import --quit
godot --headless --fixed-fps 60 --path . res://scenes/test/UIFlowVerification.tscn -- --phase6-check
```

Run the UI verification scene without `--headless` or `--fixed-fps 60` to capture
all menu screens, the live HUD and results in `artifacts/phase_6/`. It navigates
through actual UI input events and drives two complete races with a QA player pilot.
The normal main scene always leaves driving under human control.
Historical verification scenes remain under `scenes/test/`.
On this Mac the engine executable is `/Applications/Godot.app/Contents/MacOS/Godot`.

## Desktop exports

Install the official export templates matching the engine version. The three presets in
`export_presets.cfg` produce Windows x86_64, Linux x86_64, and universal macOS builds.
ASTC import is enabled because Godot requires it for Apple Silicon macOS exports.

```sh
mkdir -p builds/windows builds/macos builds/linux
touch builds/.gdignore
godot --headless --path . --export-debug "Windows Desktop"
godot --headless --path . --export-debug "macOS"
godot --headless --path . --export-debug "Linux"
```

Builds go into `builds/`, which is ignored by Git. Windows and Linux builds include a
separate `.pck`; keep it alongside the executable. macOS uses ad-hoc signing for local
development. Distribution signing and notarization are not part of Phase 0.
`com.nodekins.racing` is a provisional bundle identifier, not a registered ownership claim.

## Project files

| Location | Purpose |
| --- | --- |
| `scenes/ui/Main.tscn` | Current main scene: complete title-to-race-to-results flow |
| `scripts/ui/menu/` | Screen flow, live previews, shared theme, HUD and minimap |
| `resources/ui/default_catalog.tres` | ID-based driver/track entries for selection |
| `scenes/test/UIFlowVerification.tscn` | UI input navigation, two full races, HUD/results/cleanup checks |
| `scenes/track/Track.tscn` | Standalone race scene: player + three CPUs, three laps |
| `assets/track_kit/*.glb` | Fourteen original Blender track/environment assets |
| `assets/track_kit/catalog.json` | Dimensions, exit sockets, triangle counts and axis convention |
| `scenes/track/Loop01Art.tscn` | Modular visual cover for the unchanged gameplay geometry |
| `scenes/track/BoostPad.tscn` | Reusable trigger using the existing Boost item effect |
| `source_assets/phase_5c/track_kit_01.blend` | Versioned editable track-kit source |
| `scenes/test/TrackArtVerification.tscn` | Pre-art geometry, seam and deterministic race comparison |
| `scenes/test/BoostPadVerification.tscn` | Full race with pads, crossing/lock/boost stacking checks |
| `assets/characters/*.glb` | Two compatible body rigs and one shared appearance-part library |
| `resources/characters/` | Compact ID-based looks and male/female defaults |
| `scenes/characters/` | Reusable character assembler and visual-only kart rider |
| `source_assets/phase_5b/characters_01.blend` | Versioned editable character source |
| `scenes/test/CharacterGallery.tscn` | Default outfits, idle/victory and shared-rig verification |
| `scenes/test/CharacterVerification.tscn` | Full race with riders and close evidence screenshots |
| `assets/karts/kart_01.glb` | Blender kart: chassis, four shared wheels, spoiler, deployed glider |
| `assets/karts/kart_paint.gdshader` | Chassis grayscale mask, per-kart paint, drift/hit feedback |
| `source_assets/phase_5a/kart_01.blend` | Versioned editable Blender source |
| `tools/phase_5a/kart_import.gd` | Built-in import hook for vertex colors and toon materials |
| `scenes/test/KartArtVerification.tscn` | Art structure checks, close screenshots, and full glide race |
| `scripts/glide/` | Shared flight state and automatic launch trigger |
| `resources/tracks/test_glide.tres` | Ramp/gap geometry and safe checkpoint recovery |
| `scenes/test/GlideVerification.tscn` | Four-kart glide race, air control, landing, and item checks |
| `scenes/items/ItemBox.tscn` | Rotating pickup with respawn cooldown |
| `resources/items/*.tres` | Automatically discovered item definitions and effect parameters |
| `scripts/items/` | Inventory, weighted rolls, shared effects, deployed actors, and item HUD |
| `scenes/test/ItemVerification.tscn` | Full item race, collisions, input, and lifecycle checks |
| `scripts/ai/kart_ai.gd` | Shared-input CPU driver and progress watchdog |
| `resources/ai/default_ai.tres` | Tunable path, drift, rubber-band, and recovery decisions |
| `scenes/test/AIGridVerification.tscn` | Full-grid race and AI acceptance checks |
| `scripts/race/race_manager.gd` | RaceManager autoload, shared queries and signals |
| `resources/tracks/oval.tres` | Track centerline and ordered checkpoint locations |
| `scenes/test/RaceVerification.tscn` | Full-race, fault, and multi-kart acceptance checks |
| `scenes/test/TestPlane.tscn` | Retained Phase 1 manual driving lab |
| `scenes/kart/Kart.tscn` | Reusable CharacterBody3D kart and components |
| `scenes/test/Verification.tscn` | Automated in-engine acceptance drive |
| `scenes/phase_0/connection_check.tscn` | Retained Blender pipeline check |
| `tools/phase_0/connection_check.gd` | Startup diagnostics only |
| `resources/handling/default_handling.tres` | Editable starting handling values and curves |
| `resources/handling/kart_handling.gd` | Data-only Resource schema |
| `assets/phase_0/pipeline_test.glb` | Blender MCP test export consumed by Godot |
| `source_assets/phase_0/pipeline_test.blend` | Versioned source snapshot; excluded from Godot import |
| `docs/phase_0.md` | Historical setup verification |
| `docs/phase_1.md` | Phase 1 movement implementation and tuning handoff |
| `docs/phase_2.md` | Track/race implementation and verification |
| `docs/phase_3.md` | AI implementation, tuning, and verification |
| `docs/phase_4.md` | Item implementation and verification |
| `docs/phase_4_5.md` | Glide implementation, tuning, and verification |
| `docs/phase_5b.md` | Character exports, shared skeleton, sockets, outfits and validation |
| `docs/phase_5a.md` | Modular kart source, coordinate convention, attachment rig, and validation |
| `docs/phase_5c.md` | Modular track kit, working boost pads and verification |
| `docs/phase_6.md` | UI flow, selection state, HUD and verification |

The Phase 0 pipeline source is
`/Users/shane/Gaming/Assets/nodekins-racing/phase_0/pipeline_test.blend`.
Keep that source, the repository snapshot, and the GLB in sync when re-exporting.
The current kart source is `/Users/shane/Gaming/Assets/nodekins-racing/phase_5a/kart_01.blend`;
its matching snapshot lives under `source_assets/phase_5a`.
The character source is `/Users/shane/Gaming/Assets/nodekins-racing/phase_5b/characters_01.blend`;
its matching snapshot lives under `source_assets/phase_5b`.
The track-kit source is `/Users/shane/Gaming/Assets/nodekins-racing/phase_5c/track_kit_01.blend`;
its matching snapshot lives under `source_assets/phase_5c`.
Future production assets must be made and exported using Blender MCP. Gameplay is proven
with gray-box geometry before the art phase.

## Build order and design intent

Phase 0 setup → movement → track/laps → AI racers → items → glide → art → UI → audio →
customization → online multiplayer → polish. Each phase ends in an in-engine verified
result before the next begins. Design and balance specifications come from the user
and their design co-pilot; provisional values must be identified.

Future multiplayer is client-server online racing. Customization profiles will be compact,
versioned, ID-based data covering kart parts/colors and hair, eyes, shirt, pants, shoes,
and skin tone. Profile IDs resolve to local assets; network payloads must not contain
asset paths. Racers must see each other's profiles. Networking and customization
implementation are deferred to their phases. Optional split-screen does not drive the architecture.
