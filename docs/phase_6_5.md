# Phase 6.5 — Customization

The driver-selection step now opens **Customize Character** and **Customize Kart**.
This keeps appearance choices in the normal pre-race flow. Both screens return to
driver selection, switch to each other, or continue to track selection. Keyboard,
gamepad and mouse work throughout. The existing `DriverPreview` supplies both live
3D views. Kart preview has a Show/Hide Glider button; changing the glider opens it.
Body changes preserve the rest of the outfit. Every successful edit saves immediately.

## Profile contract v1

`CustomizationProfile` contains precisely these thirteen unsigned-byte IDs, in order:

| Byte | Field | Current choices |
| --- | --- | --- |
| 0 | chassis_id | 0 Classic, 1 Sprint |
| 1 | wheel_id | 0 Faceted, 1 Six-spoke |
| 2 | spoiler_id | 0 Touring, 1 Split fin |
| 3 | glider_id | 0 Cloudwing, 1 Arrowwing |
| 4 | primary_color | Palette 0–9 |
| 5 | secondary_color | Palette 0–9 |
| 6 | body_type_id | 0 Male, 1 Female |
| 7 | hair_id | 0 Quiff, 1 Bob, 2 Mohawk |
| 8 | eye_id | 0 Sapphire, 1 Emerald, 2 Hazel |
| 9 | shirt_id | 0 Striped tee, 1 Zip jacket |
| 10 | pants_id | 0 Shorts, 1 Trousers |
| 11 | shoe_id | 0 Trainers, 1 Boots |
| 12 | skin_tone_id | Palette 0–5 |

`to_wire()` produces **13 bytes**. `from_values()` accepts a byte array or a decoded
JSON array, rejecting wrong lengths, strings, booleans, non-integral numbers,
non-finite numbers and values outside 0–255. `CustomizationLibrary.accepts()` also
requires every ID to exist in its category. Call it before applying received data.
There are no file paths, asset names, floating colors or gameplay stats in the profile.
The schema version belongs in the envelope, outside the thirteen appearance bytes.
No networking is implemented in this phase.

Paint IDs: 0 Lagoon, 1 Cherry, 2 Midnight, 3 Citrus, 4 Sunset, 5 Lime, 6 Violet,
7 Cloud, 8 Ocean, 9 Rose. Skin IDs: 0 Amber, 1 Warm, 2 Porcelain, 3 Bronze,
4 Umber, 5 Deep. The UI color pickers are palette swatches so colors remain IDs.
Primary paints the chassis; accent paints wheels, spoiler and glider. Eye color
changes the iris region while retaining whites, pupils and facial details.

Treat IDs and their meanings as stable. Append entries instead of renumbering them;
a breaking change needs a versioned migration/compatibility policy before online play.

## Registry and assembly

- `resources/customization/library.tres` joins `kart_registry.tres` and
  `character_registry.tres`. Both UI and runtime consume these resources.
- `PartsRegistry` contains slot definitions; each slot names its profile field,
  display label, palette behavior, sockets and entries. `CustomizationPart` maps
  a byte ID to a local PackedScene, mesh name, material template and tint source.
  These paths/names belong only to the local registry.
- Add a mesh to the matching Blender library, export/import it, then add a registry
  entry with an unused ID. No UI or assembler list needs editing. All new parts must
  obey the existing socket or skeleton contract.
- `KartPartsAssembler.apply()` replaces mesh children under the existing kart
  sockets. All four wheels share one mesh. In a race, the existing glider socket
  stays under `Glide/Canopy`; deployment, retraction and banking remain glide-owned.
- `CharacterAppearance.set_profile()` resolves bodies and appearance through the
  same library. Skinned parts attach to the shared Skeleton3D using the authored
  named skin bindings. Parenting them to a BoneAttachment as well would transform
  them twice. The six named bone sockets remain available for rigid accessories.
- Material templates are duplicated per assembly. Paint and skin retain the existing
  tint shaders. The paint shader adds an opt-in grayscale conversion for the original
  colored canopy; its default remains unchanged. The iris shader only recolors the
  original iris vertex-color region. No new textures were exported.
- Legacy `set_look(CharacterLook)` remains available for historical test scenes and
  CPU defaults. Registry legacy keys adapt it to the integer profile; those old
  string names never enter the saved or wire profile.

`GameSession` owns the local profile and loads it on startup. Menu previews, race
setup and the victory preview consume it. Only visual scripts and menu/session code
changed: controller, handling Resource, camera, glide, AI, items, track collision and
RaceManager logic remain unchanged. `KartVisuals.apply_profile()` is an additive
visual API, not a change to the controller's public interface.

## Persistence

The real player save is `user://customization/profile_v1.json`, containing only:

```json
{"version":1,"values":[1,1,1,1,1,7,1,2,1,1,1,1,4]}
```

The store writes and flushes a temporary file, backs up the last valid profile to
`.bak`, then renames the temporary file into place. It reports failures in the UI
and keeps the active profile unchanged if saving fails. Startup validates the file,
then tries the backup, then uses defaults. Corrupt player preferences do not produce
engine errors. The example above is the verified red/white alternate kart with a
female mohawk driver, emerald eyes, jacket, trousers, boots and Umber skin.

## Original Blender additions

There was one option per kart slot, so a second option for each was modeled/exported
through Blender MCP, along with the requested example's mohawk:

| Export | Separate meshes | Triangles |
| --- | --- | --- |
| `assets/customization/kart_variants.glb` | kart_chassis_02 / kart_wheel_02 / kart_spoiler_02 / kart_glider_02 | 980 / 272 shared wheel / 156 / 244 |
| `assets/customization/character_variants.glb` | char_hair_03 with matching named rig | 202 |

The chassis preserves the cockpit/seat/steering and floor dimensions; only the nose
narrows. The wheel keeps its original radius, and wing supports retain their original
locations. These are socket-local parts: meters, identity transforms, Blender +Y
exporting to Godot -Z. No collider or socket was resized. The 272-triangle alternate
wheel is intentionally richer than Phase 5a's original 96-triangle wheel; it remains
shared by all four instances and desktop scope has no mobile budget constraint.

Editable source: `/Users/shane/Gaming/Assets/nodekins-racing/phase_6_5/customization_01.blend`.
The identical versioned snapshot is `source_assets/phase_6_5/customization_01.blend`.
`tools/phase_6_5/build_variants.py` runs in the connected Blender process; it replaces
only its own tagged scene. `build_registries.py` regenerates the initial registry data.
The Godot import hook preserves flat/toon vertex colors. Original GLBs are unchanged.

## Verification

`CustomizationVerification.tscn` drives actual keyboard, gamepad and mouse events
through every profile field, both carousels' wrap directions, palette swatches,
glider preview, back navigation, track selection, a complete race and results.
Only the QA scene gives the player a standard KartAI pilot; normal play remains human.
The contract audit checks all registry IDs, all registered character parts on both
rigs, named rest bindings, socket preservation, shared wheels, tint isolation,
serialization, invalid input, backup recovery and write failure behavior.

The test uses `artifacts/phase_6_5/restart-profile.json`, leaving the real user's
save untouched. `CustomizationRestartVerification.tscn` runs in a **separate Godot
process**, reloads that persisted profile through the same GameSession store before
constructing the main screen, and verifies title and actual race appearance.

```sh
godot --headless --editor --path . --import --quit
godot --headless --fixed-fps 60 --path . res://scenes/test/CustomizationVerification.tscn -- --phase65-check
godot --headless --path . res://scenes/test/CustomizationRestartVerification.tscn -- --phase65-check
```

Run without `--headless` and `--fixed-fps` for visual evidence. Reports and screenshots
are in `artifacts/phase_6_5/` (generated, ignored by Git).

Final Godot MCP run (Godot 4.7.2, rendered Metal): **63 UI/race checks + 390
contract/assembly checks passed**. Separate-process restart: **11 checks passed**.
Final import, rendered race and restart output contain **zero errors or warnings**.
Blender export reported no warnings. The first rendered run exposed a QA-only
shadowed-variable warning; it was corrected before the final clean run.

All four racers finished, each with 24 ordered checkpoints and three glide landings.
No recoveries occurred. Seed 445 produced the same times as the Phase 6 baseline:

| Place | Racer | Time |
| --- | --- | --- |
| 1 | CPU 2 | 42.867 s |
| 2 | CPU 3 | 47.217 s |
| 3 | Player | 49.817 s |
| 4 | CPU 1 | 50.017 s |

HUD lap, position and held-item values matched their live sources throughout.
The selected thirteen IDs matched preview, player kart, rider and results; runtime
checks also confirmed actual alternate chassis/glider mesh names and paint uniforms.
Screenshots visually confirm the red/white kart, mohawk, outfit and skin match on
the road and in flight. Human preference tuning remains appropriate for the look;
no handling values were changed.

Evidence: `character-customization-final.png`, `kart-customization.png`,
`kart-customization-glider.png`, `customized-on-track.png`,
`customized-mid-glide.png`, `customized-results.png`, `restart-title.png`,
`customization-report.json`, `restart-report.json`, `mcp-race-log.json`,
`mcp-restart-log.json`, and `import-final.log` under `artifacts/phase_6_5/`.
