# Phase 5c — modular track and environment art

Original geometry authored and exported through Blender MCP in Blender 5.2;
imported and raced through Godot MCP in Godot 4.7.2. No downloaded assets,
textures or external Godot plugins are used. Desktop targets remain Windows,
macOS and Linux.

## Exported kit

All exports are glTF 2.0 binary files in `assets/track_kit/`. The editable master is
`/Users/shane/Gaming/Assets/nodekins-racing/phase_5c/track_kit_01.blend`, with a
byte-identical versioned snapshot at `source_assets/phase_5c/track_kit_01.blend`.
The source retains the previous character, kart and connection-check scenes.
`Nodekins_Track_Kit` contains the kit; the ramp is initially visible and other
modules are hidden at their authored origins to avoid overlapping in the studio.

| Export basename | Triangles | Dimensions / purpose |
| --- | ---: | --- |
| `track_straight_01` | 430 | 14 m wide, 4 m long |
| `track_curve_45_01` | 1,580 | 14 m wide, 32 m centerline radius |
| `track_curve_90_01` | 3,080 | Same radius and width |
| `track_hill_01` | 266 | 12 m run, 1.4 m rise |
| `track_tunnel_01` | 1,438 | 12 m long; road, side panels, roof and ribs |
| `track_arch_01` | 1,356 | Start/finish checkerboard arch and stripe |
| `track_barrier_01` | 156 | 4 m rail, 0.5 m wide |
| `track_ramp_01` | 300 | Exact existing 12 m run / 1.4 m rise |
| `prop_itembox` | 408 | Beveled cyan crystal with cream star markings |
| `prop_boostpad` | 192 | Flush 4 × 6 m lime chevrons |
| `prop_banner_01` | 116 | Orange signage with abstract cream glyphs |
| `prop_deco_01` | 176 | Faceted rocks and small plants |
| `prop_deco_02` | 440 | Strapped crate cluster |
| `environment_island_01` | 156 | Non-colliding infield island |

Total library geometry is **10,094 triangles** before placement/instancing.
Flat normals and a simple vertex-color palette produce the toon style. The
built-in `kit_import.gd` hook enables vertex colors and toon diffuse shading,
disables specular highlights, and strips asset prefixes from local node names.
The palette uses slate road, cyan/cream rails, orange landmarks and lime boost
pads. No normal maps or baked lighting are needed.

## Scale and connection contract

One Blender unit is one metre. Blender **+Y forward / +Z up** exports to Godot
**−Z forward / +Y up**, matching the kart and characters. All mesh object
transforms are identity. Each module's origin and `socket_in` are at its entrance
center on the ground/road surface; `socket_out` gives the next connection pose.
Freestanding props use a ground-level anchor, and the boost pad uses the center
of its leading edge. Socket offsets are intentional, not unapplied mesh scale.

Road width is 14 m, straights and standalone barriers use a 4 m grid, and tunnel
and slope modules span three grid units. Curves follow the existing route's
7.5-degree polygon subdivisions. A 90-degree curve exits at (−32, 0, −32) with
90-degree yaw. A 45-degree curve exits at (−9.372583, 0, −22.627417) with 45-degree
yaw; snap by its socket, not by rounding that endpoint to the straight grid.
Two 45-degree modules make the same grid-aligned turn as one 90-degree module.
`catalog.json` records every exit and triangle count.

The slope/ramp exits at (0, 1.4, −12). On Loop 01, the ramp enters at
**(32, 4, 16)** and ends at **(32, 5.4, 4)**; the landing starts at **(32, 4, −12)**.
The 16 m horizontal gap and 1.4 m drop remain unchanged. Art was authored to
these values, with no scene rescaling. The reusable hill is exported but is not
placed on this otherwise flat loop, since adding a hill would alter its layout.

Mesh compression and generated LODs are disabled for these small assets to retain
the authored edge coordinates. All 33 ordinary road connections close within
0.1 mm, including actual imported mesh corners across the full road width.
The launch-to-landing gap is the sole intentionally open connection.

## Scene integration and preserved gameplay

`Loop01Art.tscn` places 34 road modules: straights, two 90-degree curves, four
45-degree curves, one tunnel and the ramp. It also instances the arch, 51 shared
standalone rail segments, banners, six rock clusters, five crate clusters and
the infield island. Curves and the tunnel carry their own modular rails.
The original open recovery edge remains open.

`track_art.gd` hides the old gray-box meshes and debug checkpoint labels. All
original collision shapes stay active, with the same dimensions, transforms,
layers and masks. Imported artwork adds no collision bodies. Tunnel structure
and decorative objects sit outside the driving envelope; they do not introduce
new gameplay obstacles. The original route, eight checkpoint indices, launch
trigger, lap logic, item pickup volumes and recovery rules remain unchanged.

`ItemBox.tscn` replaces only the visual child. All twelve boxes share one imported
mesh and retain the original pickup script, rotation, trigger and four-second
respawn cooldown. The sky/fog colors are adjusted to suit the track palette.
Kart movement, input, stats, camera, glide, AI, RaceManager and existing item
effect scripts are unchanged. No public kart or RaceManager interface changed.

## Explicitly approved addition: working boost pads

The pre-art project had Boost items and mini-turbos but no boost-pad trigger.
The user explicitly chose to add working pads using the existing Boost effect.
Three pads now span the west straight before the tunnel, at x = −27.75, −32 and
−36.25, with entrances at z = −30. Each is a reusable `BoostPad.tscn` instance.

`TrackBoostPad` invokes the existing `BoostItemEffect.activate()` with the existing
`boost.tres`: **1.5× for 2 seconds**. It never writes velocity or consumes the
held item. Only grounded racers able to act during the racing phase can trigger
a pad. One activation is allowed per crossing; leaving rearms it, and parking
does not refresh the boost forever. Restart clears crossing state.

Existing boost rules keep the stronger multiplier and longer remaining duration.
A 1.6× mini-turbo remains 1.6× when it crosses a pad; boosts do not multiply.
A kart straddling neighboring pads can log both crossings in one tick, but their
shared effect still uses these same maximum rules. Every activation logs its
pad, racer, active multiplier, duration and held item in the existing item log.
The three pads add exactly three Areas and three trigger shapes; all 252 original
collision shapes and 21 original Areas remain identical to the saved baseline.

## Verification and reproduction

Two seeded four-kart, three-lap races separate the visual swap from the new pad
gameplay. The QA scenes pilot the player slot; the normal main scene uses human
input. Both exercise physical travel, ordered checkpoints, items and the glide
gap, followed by isolated recovery/air-control checks. They are not teleport-based
lap simulations.

`TrackArtVerification.tscn` disables the newly added pads and compares the full
geometry snapshot with `tools/phase_5c/physics_baseline.json`. It checks module
seams, road edge vertices, ramp coordinates, shared item mesh instances and
finish times against the pre-art race within one physics tick.

`BoostPadVerification.tscn` enables the pads, checks the original geometry is
unchanged apart from those three new triggers, and verifies countdown locking,
repeat crossings, actual speed increase, inventory preservation, stationary
expiry, stronger-turbo preservation and restart cleanup.

The rendered art-only race passed **57 checks**, with all finish times exactly
matching the pre-art baseline: CPU 2 **45.32 s**, Player **47.97 s**, CPU 3
**48.53 s**, CPU 1 **54.68 s**. Maximum socket seam error was **0.0038 mm**.

The final pad-enabled run passed **59 checks**, finishing CPU 2 **42.87 s**, CPU 3 **47.22 s**, Player
**49.82 s**, CPU 1 **50.02 s**. Pads change the timing of item encounters, so
they do not necessarily shorten every individual finish time. Each race had
24 ordered gate passes per kart, twelve successful airborne checkpoint passes,
twelve launches/landings, correct standings throughout and zero race recoveries.

Concrete pad examples from the full race: CPU 3 crossed WestCenter at **8.57 s**
while holding Banana and kept its 1.6× mini-turbo; CPU 1 crossed WestOuter at
**9.13 s** for 1.5×; Player crossed WestCenter at **24.85 s** while already at
1.6×. The isolated crossing test also measured speed above 25 m/s through the
normal kart boost pipeline.

Final Blender exports, Godot imports and MCP runtime logs contain no warnings or
errors. During development, a malformed decorative leaf was rebuilt as a closed
prism; the geometry comparison was corrected for JSON integer/float types; mesh
compression was disabled to prevent sub-millimetre edge shifts; and tunnel roof
panels were given thickness to preserve both interior and exterior faces.
These issues were resolved before handoff. This is automated race and visual
verification; a human handling/art review remains useful.

Evidence lives locally in `artifacts/phase_5c/` (ignored by Git):

- `track-overhead-with-pads.png`: complete final layout.
- `connection-seam.png`: straight/curve connection at road height.
- `item-box-on-track.png`, `boost-pads-on-track.png`: replaced/new prop visuals.
- `glide-ramp-gap.png`: exact original launch and landing geometry.
- `tunnel-and-props.png`: enclosed tunnel and nearby dressing.
- `mid-launch.png`, `mid-glide.png`, `after-landing.png`: physical traversal.
- `track-art-report.json`, `boost-pad-race-report.json`: checks, results and events.
- `physics-after.json`, `blender-kit-audit.json`: geometry and asset evidence.

```sh
godot --headless --editor --path . --import --quit
godot --headless --fixed-fps 60 --path . res://scenes/test/TrackArtVerification.tscn -- --phase5c-check
godot --headless --fixed-fps 60 --path . res://scenes/test/BoostPadVerification.tscn -- --phase5c-pads-check
```

Omit `--headless` and `--fixed-fps 60` for rendered screenshots. The tested Mac
executable is `/Applications/Godot.app/Contents/MacOS/Godot`.
To rebuild the library, execute `tools/phase_5c/build_track_kit.py` through the
connected Blender MCP. It replaces only tagged kit output, exports all fourteen
GLBs and synchronizes the master/snapshot. `assemble_loop.py` writes placement
data only; all mesh modeling stays in Blender. Reimport after rebuilding.
