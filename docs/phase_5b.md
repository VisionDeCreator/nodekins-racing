# Phase 5b — modular characters

Completed in Blender 5.2 through Blender MCP and imported/run through Godot MCP in
Godot 4.7.2. All geometry, weights, colors and animation are original. No downloaded
assets, textures or Godot plugins are used.

## Deliverables

| Export | Contents |
| --- | --- |
| `assets/characters/char_body_male.glb` | Male body, 24-bone rig, eight animation clips |
| `assets/characters/char_body_female.glb` | Female body, identical joints and attachment layout, same clips |
| `assets/characters/char_appearance_parts.glb` | Nine separate, named, skinned appearance meshes; exported once for both bodies |

Editable master: `/Users/shane/Gaming/Assets/nodekins-racing/phase_5b/characters_01.blend`.
The byte-identical versioned copy is `source_assets/phase_5b/characters_01.blend`.
The file preserves the earlier kart and pipeline scenes. `Nodekins_Characters` is
the character studio, initially showing the male body and Outfit 01 in idle.

| Part | Triangles | Starter appearance |
| --- | ---: | --- |
| Each body | 1,424 | Shared head/joint envelope, different shoulder/hip/jaw shapes |
| `char_hair_01` / `02` | 286 / 286 | Cropped quiff / parted bob |
| `char_shirt_01` / `02` | 216 / 368 | Blue striped tee / orange zip jacket |
| `char_pants_01` / `02` | 260 / 356 | Navy shorts / olive trousers |
| `char_shoes_01` / `02` | 200 / 232 | Trainers / boots |
| `char_eyes_01` | 136 | Eye whites, irises, pupils, highlights and simple facial accents |

Complete dressed characters range from **2,522 to 2,802 triangles** across all 32
body/outfit combinations. Eyes are separate head-weighted geometry for crisp,
texture-free facial features at race distance. An eye appearance can later be
replaced through the same ID lookup as other parts.

The body uses neutral grayscale vertex colors and `skin_tint.gdshader`; each rider
gets its own material instance and a palette ID. Clothing uses flat vertex colors.
The import hook enables vertex colors and toon shading. There are no normal maps.

## Rig and attachment contract

One unit is one metre. Blender **+Y forward, +Z up** exports to Godot **−Z forward,
+Y up**, matching Phase 5a. Armatures and mesh objects have identity object
transforms. The common root is at the feet/ground center; the dressed shoe soles
meet ground level in the rest pose. Character scale is authored for the existing
cockpit; neither the kart nor its collider was rescaled.

Both body rigs and the appearance library have identical bone names, parent order,
joint locations, rest matrices and named skin bindings. They contain root, hips,
spine, chest, neck, head; paired upper arms, forearms, hands, thighs, shins and feet;
and six attachment bones. Hands are simple mitten shapes, without finger bones.

Socket rest positions, in Godot metres:

| Socket | Parent | Position |
| --- | --- | --- |
| `socket_hair` | head | (0, 1.43, 0) |
| `socket_eyes` | head | (0, 1.23, −0.21) |
| `socket_shirt` | chest | (0, 0.83, 0) |
| `socket_pants` | hips | (0, 0.60, 0) |
| `socket_shoes.L` / `.R` | corresponding foot | (−0.10 / +0.10, 0.09, 0) |

Skinned appearance parts attach at identity transform under the body's Skeleton3D
and reuse their exported named skin bindings. **Do not additionally parent these
skinned meshes to a moving BoneAttachment3D**: that would transform them twice.
BoneAttachment3D nodes expose the six sockets for future rigid accessories.
There are no body-specific part offsets or separate clothing exports.

Clips: `Idle`, `Drive`, `SteerLeft`, `SteerRight`, `Hit`, `Victory`, `GlideLeft`,
`GlideRight`. Idle and victory include subtle looping motion. Drive and steering
are seated poses with wheel grips; victory is a standing gallery pose and is not
automatically played inside the kart. The first second of each glide clip samples
neutral to full bank. It follows the existing wing bank, with a small seat lift and
arm compensation to clear its supports while retaining the grips.

## Godot integration

`scenes/characters/Character.tscn` assembles a body and five selected appearance
meshes from a `CharacterLook` Resource. `version`, body/part IDs and skin-tone ID
are compact values; asset paths live only in the local resolver. This establishes
the data convention for Phase 6.5, without adding a customization menu or networking.

`scenes/characters/KartRider.tscn` attaches under the existing kart `Visuals` node.
Its script only observes steering, hit suppression and glide telemetry to select
animations. It does not write to any of those systems. The player and CPU 2 use
the male/Outfit 01 default; CPU 1 and CPU 3 use female/Outfit 02. Every outfit can
be used on either body.

The only existing scene/code integration edits are the rider instance in
`Kart.tscn` and default appearance assignment in the track's CPU spawning loop.
Movement, input, stats, camera, glide, AI and RaceManager implementations remain
unchanged, as does the original collision shape.

## Verification

- Blender export: no warnings. Every mesh has identity transforms and fully
  assigned skin weights. The master and repository `.blend` snapshot match.
- Godot import and final MCP runtime logs: no errors or warnings. A temporary QA
  variable-shadowing warning was corrected before the final run.
- Imported-asset audit: all 32 combinations pass; rigs, sockets, skin bindings,
  animations, triangle budgets and seated joint positions survive the round-trip.
- Rendered four-kart, three-lap race: **51 checks passed**, all racers pass all
  24 ordered gates, three launches/landings each, and zero race recoveries.
- Finish: CPU 2 **45.32 s**, Player **47.97 s**, CPU 3 **48.53 s**, CPU 1 **54.68 s**.
  These match the previous kart-art baseline. Items and isolated glide/recovery
  checks also pass.
- Original Phase 1 movement acceptance test passes unchanged: 20 m/s at 1.5 s,
  turbo speeds 26/29/32 m/s, and boost FOV 78.45°.
- Original chase camera stayed at least **4.49 m** from the rider head joint during
  the race. Driving, drift, boost, launch, glide and landing screenshots were
  inspected for visible clipping.
- Blender triangle-intersection audit covers both bodies, every part variant and
  12 seated/steering/hit/glide-bank samples. The only overlaps are intentional
  bare-hand/rim contacts. Initial heel/seat and wing-support overlaps were resolved
  in character poses without changing the kart. This is sampled validation, not
  a claim about every possible future animation or new part.

Evidence under `artifacts/phase_5b/` (local, ignored by Git):
`default-outfits-idle.png`, `idle-and-victory.png`, `rider-driving-front.png`,
`rider-driving-side.png`, `mid-drift.png`, `mid-boost.png`, `mid-launch.png`,
`mid-glide.png`, `after-landing.png`, plus asset/race/clearance reports and logs.

Run `scenes/test/CharacterGallery.tscn` for defaults, poses and imported-asset checks.
Run `scenes/test/CharacterVerification.tscn` for the rendered race and screenshots.
The QA scene pilots the player; the normal main scene retains human control.

```sh
godot --headless --editor --path . --import --quit
godot --headless --fixed-fps 60 --path . res://scenes/test/CharacterVerification.tscn -- --phase5b-check
```

Headless runs cannot capture screenshots. To rebuild authored assets, execute
`tools/phase_5b/build_characters.py` through the connected Blender MCP. It replaces
only its tagged character studio output. Then reimport in Godot; keep both source
copies and all three exports in sync. `audit_blender_clearance.py` runs through
Blender MCP and restores the previous pose after its geometric inspection.
