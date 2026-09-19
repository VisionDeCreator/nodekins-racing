# Phase 1 — Core kart movement

Implemented and verified in Godot 4.7.2 on macOS, 2026-09-19. Desktop only, GDScript,
no plugins, no production art. Open the project and press F5 to drive the test plane.

## Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Accelerate | W / Up | Right trigger |
| Brake | S / Down | Left trigger |
| Steer | A/D / Left/Right | Left stick X |
| Drift | Hold Space while steering; release for turbo | Hold south face button (A / cross); release for turbo |
| Reset to spawn | R | North face button (Y / triangle) |

Braking stops without reversing. Reset is available if stuck; reverse driving is not
part of this phase. All pad bindings accept any connected device. Steering has a 0.15
deadzone; triggers 0.10. Both keyboard and pad go through the same exponential steering
response (10/s), normalized throttle/brake, and shared controller.

## Architecture

`scenes/kart/Kart.tscn` is the reusable CharacterBody3D, box collider, and primitive kart.
`scenes/test/TestPlane.tscn` is the manual main scene: a 240 m square flat pad, 5 m grid,
collision boundaries, and a diagnostic HUD. Primitive meshes are gray-box placeholders.

CharacterBody3D permits explicit speed curves, yaw rate, grip, and collision sliding.
VehicleBody3D would introduce wheel contact, suspension, and traction tuning into this
arcade feel experiment. The tradeoff is that slopes, ramps, airtime, and richer vehicle
responses must be deliberately implemented and tested in later phases.
See [Godot's CharacterBody3D reference](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html).

The two integration boundaries are:

1. **`kart.stats`**: an exported `KartHandling` Resource, defaulting to
   `resources/handling/default_handling.tres`. Acceleration/steering curves, braking,
   grip, drift thresholds, turbo tiers/durations, and camera values are editable here.
   Replacing the Resource propagates to drift and camera; this is verified in-engine.
2. **`kart.controls`**: the `KartInput` component. Human input reads InputMap actions.
   Future drivers may call `set_command(throttle, brake, steering, drift, reset)` with
   normalized values; `use_player_input()` returns control to InputMap. Both routes
   pass through the same smoothing and movement implementation.

`kart_controller.gd` handles translation, yaw, gravity, and collision response.
`kart_drift.gd` owns charge, the latched drift direction, and boost lifetime.
`chase_camera.gd` independently observes pose/boost state; `kart_visuals.gd` and
`driving_hud.gd` provide feedback. The movement script never manipulates the camera.
Read-only telemetry and signals support observers; future movement drivers need only
the Resource and input boundary. This is not a networking implementation.

## Drift and boost behavior

- Full normalized steering maps to 35 virtual degrees. Entry requires strictly more
  than 15 degrees (about 0.429 normalized), drift held, ground contact, and at least 6 m/s.
- Drift side latches. Countersteer opens the arc instead of instantly swapping sides.
  Reduced grip creates real lateral slip; an additional 12-degree visual yaw emphasizes it.
- Color and meter progress show cyan / amber / violet tiers at 1 / 2 / 3 seconds.
- Release a charged drift to boost to 1.30 / 1.45 / 1.60 times top speed for
  1.00 / 1.25 / 1.50 seconds. Throttle drives the burst; brake cancels it.
- Brake, insufficient speed, or lost ground cancels unspent charge. Releasing before
  tier 1 grants no boost. At expiration, excess speed decays smoothly to normal.

The acceleration Curve maps normalized time to normalized speed. It is inverted from
current speed when resuming throttle, so lifting/braking does not restart acceleration
from an unrelated stored timer. Curve edits should remain monotonic with endpoints (0,0)
and (1,1). Wall-clipped velocity feeds back into the next simulation tick.

## Camera

SpringArm3D carries the Camera3D and sweeps a small sphere against the environment,
excluding the kart. The nominal camera is 4.5 m back and 2 m up, aiming 1.4 m ahead
at height 0.6 m. Exponential damping is 12/s for position and 7/s for rotation.
Horizontal velocity compensation preserves the chase distance during sustained movement.
Physics interpolation is enabled; the camera samples interpolated pose in render frames.
FOV eases from 70 to 79 degrees at 12/s while boosting, then back to 70.

## Verification and observations

Run `scenes/test/Verification.tscn` through Godot MCP or the editor to replay the
acceptance drive. It uses the public input component plus synthesized InputMap events;
it does not set the kart's speed or bypass movement. It writes measurements and PNGs
under `artifacts/phase_1/`, then stays open so MCP can retrieve the log.
With `-- --phase1-check`, it exits with a meaningful success/failure code. Headless
runs skip screenshots. Normal F5 starts the manual driving scene, not the automated drive.

The MCP acceptance run completed **36 checks**, with **zero errors and zero warnings**.
Coverage includes actual keyboard/pad event mappings, analog strengths/deadzone, no idle
spin, acceleration, braking/coasting, speed-sensitive steering, drift entry/countersteer,
short-release rejection, every turbo tier/expiration, FOV recovery, boundary collision,
input reset, and Resource replacement across components.

| Observation | Measured result |
| --- | --- |
| Speed at 0.25 / 0.75 / 1.50 seconds | 5.61 / 14.11 / 20.00 m/s |
| Speed after 0.5 seconds coasting from 20 | 16.50 m/s |
| Full-input turn ceiling at 4 / 20 m/s | 160.2 / 81.0 degrees/s |
| Tier 1 / 2 / 3 burst speeds | 26 / 29 / 32 m/s |
| FOV after about 0.25 seconds of boost | 78.45 degrees |
| Camera horizontal gap after acceleration | 4.90 m |
| Drift slip at 65% right steering | 12.43 degrees, plus 12 degrees visual yaw |

Evidence: `artifacts/phase_1/mcp-verification.json`, `measurements.json`,
`mid-drift.png`, and `mid-boost.png`. Both captured game frames were visually inspected.
These are local generated artifacts and are ignored by Git.

The acceleration has a strong launch and a clear taper. Drift reads distinctly, and
the tier-3 60% speed increase plus FOV change is pronounced. Braking is deliberately
strong: 42 m/s² gives a roughly half-second stop from normal top speed. Low-speed steering
may be too sharp on a keyboard. At 65% steering, a tier-3 charge implies approximately
a half-turn, so the three-second hold may feel long on short corners. Those are the
first human tuning questions; no supplied speed, charge threshold, or multiplier was
silently reduced to make the checks pass.

These impressions come from automated movement, measured telemetry, and visual inspection,
not a human gamepad session. Physical controller feel, native Windows/Linux runtime,
and hills/ramps remain unverified. Phase 0's old exported binaries are historical;
re-export for a packaged Phase 1 build.
