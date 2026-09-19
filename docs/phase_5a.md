# Phase 5a — Modular kart and glider art

Created entirely in the connected Blender 5.2 instance through Blender MCP on
2026-09-19. Imported and verified in Godot 4.7.2 on macOS. No external art,
textures, normal maps, or Godot plugins were used.

## Deliverables and geometry

- Runtime export: `assets/karts/kart_01.glb` — one glTF 2.0 binary containing all parts.
- Editable source: `/Users/shane/Gaming/Assets/nodekins-racing/phase_5a/kart_01.blend`.
- Matching versioned source snapshot: `source_assets/phase_5a/kart_01.blend`.
- Blender construction script: `tools/phase_5a/build_kart.py`; execute inside Blender
  via MCP from the Phase 0 baseline. It creates a separate `Nodekins_Kart_01` scene
  and preserves the original scene. The source includes a studio camera and lighting;
  these are excluded from the selected-object, active-scene-only GLB export.

The silhouette uses a tapered nose, beveled side pods, open cockpit, bucket seat,
steering rim, chunky faceted tires, rear spoiler, and swept amber glider. Chassis
details form a single chassis mesh with one material. Wheels, spoiler, and glider
remain independent meshes on named attachment nodes.

| Part | Exported mesh-node name | Triangles |
| --- | --- | --- |
| Chassis | `kart_chassis_01` | 980 |
| Front-left wheel | `kart_wheel_01` | 96 |
| Other wheel instances | `kart_wheel_01_fr`, `_rl`, `_rr` | 96 each |
| Spoiler | `kart_spoiler_01` | 156 |
| Glider, deployed | `kart_glider_01` | 244 |

There are **four unique mesh datablocks**, seven mesh instances, and **1,764 rendered
triangles** with the glider deployed; **1,520** with it hidden. All four wheel nodes
reference the same mesh in both the GLB and Godot. All requested part budgets are met.
Faces use flat normals; Godot materials use toon diffuse lighting.

## Scale, orientation, and attachment rig

One Blender unit is one metre. The assembly origin is at ground center, with
**Blender +Y forward / +Z up → Godot −Z forward / +Y up** through the standard
glTF Y-up conversion. This is the asset convention for subsequent parts. There is
no corrective rotation or scale on the Godot instance.

Mesh objects have identity transforms: zero local location/rotation and unit scale.
Geometry is already authored in its final dimensions. Empty attachment nodes carry
intentional positional offsets; their translations must remain as the part rig.
This rigid modular asset uses attachment nodes rather than a deformation skeleton.

Godot-space offsets from the ground-center root:

| Attachment | Position (x, y, z), metres |
| --- | --- |
| `socket_chassis` | (0, 0, 0) |
| `socket_wheel_fl` | (−0.68, 0.29, −0.57) |
| `socket_wheel_fr` | (0.68, 0.29, −0.57) |
| `socket_wheel_rl` | (−0.68, 0.29, 0.60) |
| `socket_wheel_rr` | (0.68, 0.29, 0.60) |
| `socket_spoiler` | (0, 0.62, 0.73) |
| `socket_glider` | (0, 0.78, 0.40) |

Replacement parts should place their mount at local zero, retain the axis convention,
and replace only the mesh child of the corresponding socket. The chassis is 1.16 m
wide and 1.84 m long. The wheel envelope is 1.62 m wide with bottoms at y = 0.
The glider span is 3.8 m; its deployed top is approximately 1.89 m above the root.

The original collider remains **1.2 × 0.7 × 1.9 m**, centered at (0, 0.35, 0).
No collider resizing or visual rescaling was required. As before, wheels extend
slightly outside the body collider and the seat/accessories extend above it. Art
adds no physics bodies or collision shapes.

## Materials and visual integration

The chassis uses one portable Principled material in Blender. Vertex `Color` exports
as `COLOR_0`: RGB stores neutral grayscale shading, and alpha is a binary paint mask
(1 = paint, 0 = neutral trim). Alpha is **not opacity**. There is no baked final paint
color and no texture to rebake. The glider has its own amber/cream vertex-color livery
and material; glider customization is deferred.

`assets/karts/kart_paint.gdshader` uses this mask for per-kart paint and the existing
drift/boost/hit feedback. Neutral tires, seat, bumper, and steering rim stay readable.
`KartVisuals.paint_color` and `set_livery(color)` control the art tint. The player starts
cyan, with coral, green, and gold CPUs. The spoiler retains identity color while the
chassis displays charge/hit feedback. This is a visual API addition only.

`Kart.tscn` instances the complete GLB under `Visuals/Model`. The visual adapter moves
its authored glider socket under the existing `Glide/Canopy` node without changing its
local offset. The original glide component still owns deployment, retraction, and bank.
Driving hides the glider entirely; the source mesh is modeled in the deployed pose,
with no fold animation. Recovery/restart also hide it through the existing state.

Ground movement, input, drift/boost logic, the handling Resource, glide logic, camera
logic, and RaceManager are unchanged. Only model attachment, material feedback, and
the track's visual identity assignment were updated. The existing boost trail effect
is retained. No physics or handling adjustments accompany this art swap.

## Import corrections and warnings

The final Blender export and final Godot import reported **no warnings or errors**.
Two integration issues were caught and corrected before delivery:

- Godot's automatic node-name suffix processing interpreted `kart_wheel_01` as a
  vehicle-wheel node. Both suffix-conversion options are disabled in the committed
  `.glb.import` settings, preserving the required names and mesh-only hierarchy.
- Imported StandardMaterials initially ignored the authored vertex colors, making
  tires and gliders white. The small built-in `EditorScenePostImport` script enables
  vertex colors and toon diffuse lighting. It is referenced by the committed import
  settings, so a fresh checkout reproduces the correct materials.

The initial diagnostic was started before editor import finished and failed to load
the GLB; rerunning after import resolved it. A diagnostic integer-division warning
was fixed. The final clean logs are saved separately from these early attempts.

## In-engine verification

The rendered Godot MCP acceptance run passed **59 checks, zero errors, zero warnings**.
It inspects named parts, shared wheel resources, triangle counts, one chassis material,
grayscale/mask data, metre scale/orientation, unchanged collider, per-kart tint, and the
glider's actual parent/visibility. External QA cameras capture close views; the game's
chase camera and its logic are unchanged. HUD and 3D labels are hidden only while taking
the art screenshots.

The existing physical four-kart, three-lap glide race runs with all new models and items.
A QA-only input driver pilots the player slot. All four finish with **12 successful
glides, 12 airborne CP1 crossings, 24 ordered gates per kart, no checkpoint violations,
and no recoveries**. Times: CPU 2 **45.32 s**, player **47.97 s**, CPU 3 **48.53 s**,
CPU 1 **54.68 s**. Separate fixtures verify landing, recovery, restart, and item effects
while airborne. The normal scene leaves the player under human control.

The unchanged Phase 1 movement suite also passes: 20 m/s at 1.5 s, mini-turbos at
26 / 29 / 32 m/s, collision clipping, reset behavior, and camera/FOV checks. These
measurements match the previous phase. Visual inspection confirmed the new model on
the track from front and rear, visible charged drift, deployed glider in flight, and
the glider hidden again after landing.

Local evidence in `artifacts/phase_5a/` is Git-ignored:

- `kart-art-report.json`, `mcp-verification.json`, `blender-audit.json`,
  `blender-export.json`, `import.log`, `phase1-regression.log`.
- `track-front.png`, `track-rear.png`, `mid-drift.png`, `mid-boost.png`,
  `mid-launch.png`, `mid-glide.png`, `after-landing.png`, `blender-deployed.png`.

```sh
godot --headless --editor --path . --import --quit
godot --path . res://scenes/test/KartArtVerification.tscn -- --phase5a-check
# Without screenshots:
godot --headless --fixed-fps 60 --path . res://scenes/test/KartArtVerification.tscn -- --phase5a-check
```

Omit `--phase5a-check` for MCP output retrieval after completion. Open the normal
main scene for a human check; Enter / gamepad Start restarts the race.
