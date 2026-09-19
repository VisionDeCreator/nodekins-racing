# Phase 0 verification

Verified on 2026-09-19 with Godot 4.7.2 and Blender 5.2 on an Apple M4 Pro Mac.
Scope was revised during setup to **Windows/macOS/Linux only**, keyboard and gamepad.
No mobile export or touch work remains in the current plan.

## Acceptance results

| Requirement | Result |
| --- | --- |
| Godot project setup | Main scene configured; desktop Forward+; existing Jolt setting retained |
| Local Git repository | Initialized on `main`; Phase 0 files form the initial commit |
| Godot MCP round-trip | `create_scene`, `run_project`, and `get_debug_output` succeeded |
| Blender MCP round-trip | New test mesh created and exported as GLB; editable `.blend` saved |
| Godot asset import | One surface, 12 triangles, material present, dimensions `(1, 0.5, 1.5)` metres after axis conversion |
| Handling Resource | Typed Resource and `.tres` load in both editor-launched and exported runs |
| Windows export | Debug export succeeded; PE x86_64 executable and PCK produced |
| Linux export | Debug export succeeded; ELF x86_64 executable and PCK produced |
| macOS export | Universal x86_64/arm64 debug export succeeded with ad-hoc signing |
| Packaged runtime | Exported macOS app ran with Forward+, passed all startup checks, and produced a screenshot |
| Visual verification | Rendered test mesh, ground, and PASS status inspected |

Final Godot MCP output reported an empty error list. Both the desktop source run and
the exported macOS diagnostic run exited with code 0. Startup diagnostics report:

```text
[Phase 0] Blender GLB: triangles=12, Godot size=(1.0, 0.5, 1.5), material=true
[Phase 0] Handling loaded: 20.0 m/s, 1.5 s to top speed, 180.0 deg/s, drift > 15.0 deg
[Phase 0] PASS: scene running; Blender import and handling resource verified. No gameplay implemented.
```

Windows and Linux binaries were exported and their formats checked on macOS. They have
not been launched on native Windows/Linux machines. Release signing, notarization,
installation, and store distribution are not verified in this phase.

The first import caught a diagnostic variable type error, which was fixed before the
successful runs. The first macOS export required ASTC texture imports; enabling them
fixed the universal export. This is an Apple Silicon desktop requirement.

Local evidence (ignored by Git): `artifacts/phase0-desktop.log`,
`artifacts/phase0-desktop.png`, `artifacts/export-{windows,linux,macos}.log`,
`artifacts/exported-macos-run.log`, and `artifacts/exported-macos.png`.
Earlier failed-attempt logs may also be present; the final macOS result is in
`artifacts/export-macos.log`.

## Handling handoff to Phase 1

`resources/handling/default_handling.tres` stores the supplied starting values:

| Parameter | Starting value |
| --- | --- |
| Top speed | 20 m/s |
| Time to top speed | 1.5 s |
| Low-speed turn rate | 180 degrees/s |
| Drift entry | Hold drift plus steering strictly beyond 15 degrees |
| Mini-turbo hold thresholds | 1 / 2 / 3 s |
| Mini-turbo speed multipliers | 1.3 / 1.45 / 1.6 |
| Mini-turbo durations | Provisional 1 / 1.25 / 1.5 s, within supplied range |

Acceleration is an editable normalized time-to-speed Curve with a provisional ease-out
shape. Steering uses a speed-to-turn-rate multiplier Curve, provisionally tapering from
1.0 to 0.45 (81 degrees/s at top speed). Neither curve shape was finalized by the design
specification. The future controller must define how normalized steering maps to the
15-degree drift threshold; degrees must not be confused with a 0–1 input axis.

Gamepad is the reference for tuning. Keyboard feeds the same analog-friendly controller;
no device-specific movement implementations. Input bindings and controller logic belong
to Phase 1 and are not implemented here.

The chase camera specification is retained for Phase 1: SpringArm3D; 4–5 m behind and
about 2 m above; aim slightly ahead of the kart; exponential position damping; more
rotation lag than position lag; base FOV about 70 degrees, quickly easing to 78–80 on boost.
The Phase 0 inspection camera is static and does not implement this chase camera.

## Asset provenance

Blender MCP created `Phase0TestMesh` in a separate `Phase0PipelineCheck` scene, using an
applied-scale cube and one Principled material. The original scene was left intact and
restored as the active scene. Export used selected objects, binary glTF, and Y-up.
The source dimensions in Blender are `(1, 1.5, 0.5)` metres (Z-up); Godot receives
`(1, 0.5, 1.5)` metres (Y-up). No texture files or external art were used.

The original source is in the connected Assets workspace, with a versioned snapshot
under `source_assets/phase_0`. The `.gdignore` excludes source files from automatic
Blender import; Godot consumes the explicit `.glb` export only.

Export reference: [Godot export documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html)
and [macOS export documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html).
