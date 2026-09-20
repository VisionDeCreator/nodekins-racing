# Nodekins Racing

Original arcade kart racer built in Godot, with original art authored in Blender.
Current milestone: Phase 8b full dedicated-server racing. A separate online entry
point runs the real kart, track, three laps, items, glide and ID-based customization
with predicted local movement and server authority. Server-controlled AI fills the
four-kart grid. The existing single-player title/menu/race flow remains available.
See `docs/phase_8b.md` for direct server/client commands, protocol ownership,
disconnect behavior and latency verification. The isolated Phase 8a movement lab
is retained under `prototypes/networking`.
See `docs/phase_7.md` for audio ownership, triggers and recorded verification,
`docs/phase_6_5.md` for the profile contract, registries and customization verification,
`docs/phase_6.md` for the flow, selection catalog and verification,
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
male/female body, then Customize Character or Customize Kart. Choose parts with the
carousels and colors with palette swatches. Show Glider previews the deployed wing.
Continue to Skyline Loop (the existing Loop 01), then Start Race.
Menus support arrows/Tab, D-pad/left stick, Enter/A and mouse; Esc/B goes back.
Options provides Music, SFX and Engine sliders; 0% mutes a bus. All audio assets are
self-generated placeholders pending a human listen-through. The 3–2–1–GO countdown
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
godot --headless --fixed-fps 60 --path . res://scenes/test/CustomizationVerification.tscn -- --phase65-check
godot --headless --path . res://scenes/test/CustomizationRestartVerification.tscn -- --phase65-check
```

Run the customization verification scene without `--headless` or `--fixed-fps 60`
to capture previews, the customized kart on track, the live HUD and results in
`artifacts/phase_6_5/`. It uses actual UI input events and a QA player pilot for a
complete race. Run the restart scene as a separate process afterwards. Both use
an isolated test save, leaving the real player profile untouched.
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
| `scenes/network/` / `scripts/network/` | Full dedicated online race and client prediction/presentation adapters |
| `tools/phase_8b/verify_online.py` | Three-process full-race, item/profile/state agreement and disconnect verification |
| `docs/phase_8b.md` | Direct-connect commands, protocol, migration details and verification |
| `prototypes/networking/` | Separate headless-server / predicted-client movement laboratory |
| `tools/phase_8a/verify_networking.py` | Three-process latency, replay, smoothing and position checks |
| `docs/phase_8a.md` | Network protocol, run commands, verification and full-kart migration |
| `scenes/audio/` | Object-owned kart, track and menu audio players |
| `scripts/audio/` | Signal listeners, volume preferences, Options controls and clean shutdown |
| `assets/audio/` | 23 original placeholder WAVs and provenance/loop manifest |
| `default_bus_layout.tres` | Music, SFX, Engine and Master limiter |
| `tools/phase_7/` | Deterministic synthesis, full-flow audio verification and PCM analysis |
| `scenes/test/AudioVerification.tscn` | Full physical race with cue assertions and actual mix recording |
| `docs/phase_7.md` | Event-to-sound map, placeholder status, verification and listen-through |
| `scenes/ui/Main.tscn` | Current main scene: complete title-to-race-to-results flow |
| `scripts/ui/menu/` | Screen flow, live previews, shared theme, HUD and minimap |
| `resources/ui/default_catalog.tres` | Track entries and legacy driver defaults |
| `resources/customization/` | Shared kart/character registries, IDs, palettes and material templates |
| `scripts/customization/` | Thirteen-byte profile, validation, atomic save/load and kart assembly |
| `assets/customization/` | Original alternate kart parts, mohawk and iris tint shader |
| `source_assets/phase_6_5/customization_01.blend` | Editable Blender variant source |
| `scenes/test/CustomizationVerification.tscn` | Registry/rig/save audit, UI choices and complete race |
| `scenes/test/CustomizationRestartVerification.tscn` | Separate-process save restoration check |
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
| `resources/characters/` | Legacy named character defaults, adapted through the integer registry |
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

Phase 0 setup → movement → track/laps → AI racers → items → glide → art → UI → customization →
audio → online multiplayer → polish. Each phase ends in an in-engine verified
result before the next begins. Design and balance specifications come from the user
and their design co-pilot; provisional values must be identified.

Online multiplayer uses a dedicated client-server architecture. Customization profiles are compact,
versioned, integer ID-based data covering kart parts/colors and hair, eyes, shirt, pants, shoes,
and skin tone. Profile IDs resolve to local assets; network payloads must not contain
asset paths. Racers must see each other's profiles. Phase 8b integrates the full race; matchmaking and lobby flow remain Phase 8c. Optional split-screen does not drive the architecture.
