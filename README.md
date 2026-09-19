# Nodekins Racing

Original arcade kart racer built in Godot, with original art authored in Blender.
Current milestone: Phase 0 setup and pipeline verification. There is no driving gameplay yet.

## Current scope

Windows, macOS, and Linux only. Keyboard and gamepad, with gamepad as the reference
for handling tuning. One analog-friendly controller will consume both input sources
in Phase 1. Mobile exports, mobile asset budgets, and touch controls are out of scope;
adding them would require a separate decision.

The project uses Godot **4.7.2**, GDScript, Forward+, and the existing Jolt physics setting.
Godot 4.3+ was the requested engine family; use 4.7.2 for this tested baseline and matching
export templates. Older versions have not been validated.

## Run

Open `project.godot` in Godot and press **F5**. The Phase 0 scene displays the Blender
test mesh and a PASS message. The output log records its dimensions, material, and handling
resource load. This is a pipeline check, not the Phase 1 driving prototype.

For a repeatable check from the repository root (`godot` must be on PATH):

```sh
godot --headless --path . --import
godot --headless --path . -- --phase0-check
```

To save a rendered diagnostic, run without `--headless` and pass
`--phase0-screenshot=/absolute/path/to/check.png` after `--`. The parent directory must exist.
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
| `scenes/phase_0/connection_check.tscn` | Main scene, originally created through Godot MCP |
| `tools/phase_0/connection_check.gd` | Startup diagnostics only |
| `resources/handling/default_handling.tres` | Editable starting handling values and curves |
| `resources/handling/kart_handling.gd` | Data-only Resource schema |
| `assets/phase_0/pipeline_test.glb` | Blender MCP test export consumed by Godot |
| `source_assets/phase_0/pipeline_test.blend` | Versioned source snapshot; excluded from Godot import |
| `docs/phase_0.md` | Verification results and next-phase constraints |

The editable asset workspace copy is
`/Users/shane/Gaming/Assets/nodekins-racing/phase_0/pipeline_test.blend`.
Keep that source, the repository snapshot, and the GLB in sync when re-exporting.
Future production assets must be made and exported using Blender MCP. Gameplay is proven
with gray-box geometry before the art phase.

## Build order and design intent

Phase 0 setup → movement → track/laps → AI racers → items → art → UI → audio →
customization → online multiplayer → polish. Each phase ends in an in-engine verified
result before the next begins. Design and balance specifications come from the user
and their design co-pilot; provisional values must be identified.

Future multiplayer is client-server online racing. Customization profiles will be compact,
versioned, ID-based data covering kart parts/colors and hair, eyes, shirt, pants, shoes,
and skin tone. Profile IDs resolve to local assets; network payloads must not contain
asset paths. Racers must see each other's profiles. Networking and customization
implementation are deferred to their phases. Optional split-screen does not drive the architecture.
