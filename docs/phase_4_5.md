# Phase 4.5 — Glide mechanic

Godot 4.7.2 / macOS, 2026-09-19. The normal `Track.tscn` now includes an automatic
glide section, using the same `Kart.tscn` for the player and three CPUs. Drive up the
orange ramp at speed; no deployment button is required. Keyboard/gamepad steering
allows limited course correction, and landing retracts the placeholder wing.

## Track and race integration

`resources/tracks/test_glide.tres` defines the gray-box section: a 12 m ramp from
route distance 20 to 32 m, rising 1.4 m, followed by a 16 m open gap. Road resumes
at 48 m. The replacement distances align with the current oval's road segments;
changing this geometry to another route requires aligning its segment boundaries.
There is no hidden floor under the gap.

CP1 sits at 40 m, inside the gap. Its trigger is 8 m tall so a gliding kart crosses
the real ordered gate. RaceManager continues using its existing route-distance,
checkpoint-order, lap, ranking, and recovery APIs without modification. CP1's
recovery anchor is at 51 m on the far bank, before CP2, so a failed landing cannot
create a repeated respawn over the gap. The track duplicates the route Resource
before supplying its recovery override; the original oval asset stays unchanged.

The first item row moves from 28 to 64 m to clear the ramp and landing. Other rows
retain their existing positions. Historical Phase 2–4 verification scenes explicitly
disable the glide section to retain their original fixtures.

## Shared state and flagged API additions

`KartGlide`, exposed as `kart.glide`, supplies `try_launch()`, `active`, `flight_time`,
`last_flight`, and `launched` / `ended(flight)` signals. `GlideLaunch` detects forward
center-plane crossings and requests launch only while racing. The component rejects
launches when locked, already gliding, not grounded, or below minimum launch speed.
Standing in the volume or crossing backward does not deploy it.

The existing controller still performs its shared acceleration, braking, turbo,
speed-sensitive turn-rate calculation, and collision-speed feedback. A flight-only
branch delegates heading, gravity, and `move_and_slide()` to the glide component.
The horizontal speed at launch carries over. The new component never implements a
second acceleration or boost system. `KartAI` and the shared input layer are unchanged.

While gliding, ground drift charge is ineligible; existing boosts can continue.
Ground acceleration and drift formulas retain their previous values and behavior.
One additional numerical guard was flagged during verification: nearly identical
ground direction vectors are made exactly equal before the existing spherical
interpolation. This avoids Godot's invalid rotation-axis error as a parked kart's
direction converges. It does not change ordinary steering or handling tuning.

Floor snapping is disabled on launch and restored on landing, recovery, or restart.
A descending floor contact immediately ends flight. A four-second timeout prevents
an indefinite glide away from the intended section; ordinary falls outside a launch
trigger retain normal gravity. Existing recovery handles falling and stuck racers.

The orange flat wing and two struts are visible only during the glide, with a small
visual bank when steering. They are Godot gray-box meshes; no Blender art was added.

## Starting tuning and observed behavior

All flight handling values live on the same exported `KartHandling` Resource used
by player and CPU karts, in `resources/handling/default_handling.tres`.

| Setting | Starting value |
| --- | --- |
| Gravity multiplier | 0.30 × normal 24 m/s² = 7.2 m/s² |
| Air steering authority | 0.22 × current ground turn rate |
| Upward launch velocity | 3.5 m/s |
| Minimum launch speed | 6 m/s |
| Heading deviation limit | ±25° from launch heading |
| Air direction damping | 3 /s |
| Maximum glide time | 4 s |

Observed at 20 m/s, flight lasts about **1.27 s**, covers **25.33 m** from the
launch plane to contact, and peaks **2.22 m above the flat road**. This gives a
forgiving margin across the 16 m gap. Landing preserves horizontal speed to within
floating-point rounding; no pause or stuck state occurred in the race.

Full steering through the normal input smoothing changes heading by **4.36° in
roughly one third of a second**. The trajectory makes a gentle correction instead
of a sharp turn. These are observations from the rendered run and telemetry, not
a hands-on gamepad feel assessment. The short flight looks controlled and forgiving;
longer hang time and steering responsiveness remain human feel-tuning decisions.
Heavy braking or an item hit can still jeopardize a crossing.

Boost and hit suppression continue through the existing movement pipeline in flight.
A Banana use during glide leaves it held until landing, for both player and CPU,
rather than creating a floating trap. Shell remains usable in flight.

## Verification

The rendered **Godot MCP run passed 39 checks with zero errors and zero warnings**.
`GlideVerification.tscn` pilots the player through the normal shared input interface
for a repeatable four-kart race with items enabled and seed 445. It does not teleport
or advance race progress during that race. The normal main scene has no player pilot.

| Finish | Racer | Three-lap time |
| --- | --- | --- |
| 1 | CPU 2 | 45.32 s |
| 2 | Player slot, QA pilot | 47.97 s |
| 3 | CPU 3 | 48.53 s |
| 4 | CPU 1 | 54.68 s |

All four racers passed 24 ordered gates, launched and landed on all three laps,
and crossed CP1 while airborne. There were **12 successful glides, no checkpoint
violations, and no recoveries** in the full race. Position order was checked every
sampled physics tick, and the canopy's visibility matched the glide state.

Examples from RaceManager at airborne CP1 crossings:

| Race time | Racer | Lap | Last → next checkpoint | Total progress | Position |
| --- | --- | --- | --- | --- | --- |
| 2.55 s | Player | 1 | 1 → 2 | 40.32 m | 1 / 4 |
| 16.87 s | CPU 3 | 2 | 1 → 2 | 385.28 m | 1 / 4 |

Both samples report gliding and not grounded. Their kart origins are at world
heights 6.21 m and 6.06 m respectively, above the road plane at 4 m.

Post-race fixtures separately measured gravity and air steering, continued ground
driving after landing, safe CP1 recovery, unchanged source route data, a held Banana,
airborne Boost reaching 30 m/s, a midair hit slowing the kart while its wing remains
deployed, recovery requested in the air, ordinary falls, restart locks, and a stable
parked grid after completion. These fixtures use controlled setup and direct item
effect calls where appropriate; they are separate from the physical race evidence.

Regression checks passed: Phase 1 movement, all 33 Phase 2 race checks, and all 50
Phase 4 non-screenshot item checks. Phase 1 and Phase 4 were rerun after the numerical
guard. Human gamepad feel remains to be checked.

Local evidence is Git-ignored under `artifacts/phase_4_5/`:

- `glide-report.json`: full-race flights, standings, airborne checkpoints, item events,
  recoveries, measured air control, and final check results.
- `mcp-verification.json`: clean rendered output and empty error list.
- `mid-launch.png`, `mid-glide.png`, `after-landing.png`: external QA camera views
  from the first physical race crossing, with HUD temporarily hidden for visibility.
- `phase1-regression.log`, `phase2-regression.log`, `phase4-regression.log`.

```sh
godot --headless --path . --import
godot --path . res://scenes/test/GlideVerification.tscn -- --phase45-check
# Faster repeat without the three screenshot checks:
godot --headless --fixed-fps 60 --path . res://scenes/test/GlideVerification.tscn -- --phase45-check
```

Omit `--phase45-check` for MCP log retrieval after completion. The playable main
scene uses its ordinary chase camera, never automates the player, and does not
generate QA reports. Press Enter / gamepad Start to restart a manual race.
