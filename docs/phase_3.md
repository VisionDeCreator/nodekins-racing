# Phase 3 — AI racers

Built and verified on Godot 4.7.2 / macOS, 2026-09-19. Open the main scene
`scenes/track/Track.tscn` and press F5. Enter / gamepad Start resets the full grid.
The player remains under keyboard/gamepad control; three CPUs race automatically.

## Driver and grid

`KartAI` is a component attached to ordinary `Kart.tscn` instances. The movement,
input, drift, camera scripts, and source handling Resource from Phase 1 are unchanged.
There is no alternate AI kart scene or AI physics implementation. The driver calls
`KartInput.set_command(throttle, brake, steering, drift)` before the kart's physics tick.
Countdown, finish, and recovery locks still apply after those commands are sampled.

The ordered `TrackRoute` is the driving path. Its checkpoint-sector projection gives
validated progress and its sampled centerline gives a look-ahead steering target. A
navigation mesh would add complexity without improving this single closed course and
could suggest routes that skip required gates. This implementation is intended for a
continuous authored race route, not arbitrary off-road navigation.

Pure-pursuit steering follows the route with a speed-dependent look-ahead. Each CPU
has a preferred lateral offset; nearby traffic adjusts that offset within the road
margin and close traffic reduces throttle. All four participants collide with road,
walls, and each other in the grid scene. These remain kinematic collisions, not a new
ramming or knockback system. CPU cameras are inactive; the player's chase camera stays current.

Bend anticipation presses the normal drift input beyond the shared handling threshold.
While drifting, the driver countersteers using the existing drift steering response.
It releases on bend exit or at tier three, earning the same mini-turbo as the player.
It never directly awards boost, writes velocity, teleports to make progress, or advances
checkpoints. Recovery goes through RaceManager's existing request API.

Persistent nose colors and labels identify CPU 1 (coral), CPU 2 (green), and CPU 3
(gold), even when drift feedback changes their body colors. The HUD now shows the
live four-racer order, laps/checkpoints, and finish times. `cpu_count = 0` preserves
the single-player fixture used by the Phase 2 verification scene.

## Tunable rubber-banding

`resources/ai/default_ai.tres`, using `AITuning`, contains the driving decisions and
rubber-band settings. These are provisional values for the human feel-check:

| Setting | Default |
| --- | --- |
| Neutral gap | One average checkpoint segment, 43.11 m on Loop 01 |
| Gap for full effect | 2.5 segments, 107.79 m |
| Catch-up cap | +6% top speed |
| Ahead-of-pack penalty cap | −4% top speed |
| Maximum multiplier change | 0.02 per second |
| Telemetry interval | 2 seconds per active CPU |
| No-forward-progress timeout | 3 seconds |
| Recovery delay | Existing RaceManager delay, 0.9 seconds |

A CPU trailing the leader beyond the neutral gap receives a linear, capped adjustment.
A CPU ahead of the median of the other racers receives a capped penalty. The median
prevents one parked player from slowing a closely grouped CPU pack. Validated total
race distance drives the calculation, including laps. There are no forced overtakes,
finish-time targets, player-speed edits, or last-lap exceptions.

Each driver creates a private runtime copy of the **same source KartHandling Resource**
and changes only its `top_speed`, through the existing exported stats boundary. The
base file and all other karts remain unchanged; curves and other handling values retain
the shared defaults. Normal mini-turbos can still raise speed beyond this adjusted base.
The CPU owns this runtime speed adjustment; a future items/stat-modifier system should
compose effects at this boundary rather than having two systems overwrite top speed.
Godot's [Resource duplication API](https://docs.godotengine.org/en/4.3/classes/class_resource.html#class-resource-method-duplicate)
is used to isolate scalar changes without duplicating the movement implementation.

The active and target multipliers, race time, racer ID, and total progress are printed
as `[CPU band]` records. Disabling `rubber_band_enabled` in the Resource returns the
target to 1.0 through the same slew limit.

## Recovery

The inherited low-speed detector covers throttle against obstacles. The AI also watches
validated forward progress, so circling or stale positive speed cannot hide a stall.
Less than one metre of new progress over three seconds requests checkpoint recovery.
Countdown, finish, and recovery do not accumulate watchdog time. Respawn clears its
progress anchor, drift entry cooldown, and lane target before driving resumes.
A watchdog event prints the racer, elapsed stall duration, and last checkpoint.

Recovery cannot guarantee escape from a permanently blocked checkpoint. The current
track has sufficient clearance; more complex layouts may need alternate recovery lanes.

## Verification and evidence

`scenes/test/AIGridVerification.tscn` attaches a QA-only driver to the **player slot**;
that driver receives no rubber-banding. The three production CPU components drive the
other slots. The full race uses actual physics and real Area3D crossings throughout,
with no teleporting, injected checkpoint events, or patched race progress.

The rendered Godot MCP run checks all four registrations and countdown locks, standings
on every physics tick, 24 valid crossings per racer, real drift boosts, Resource isolation,
multiplier bounds and slew, screenshot framing, and recovery. It contains 30 checks.
The clean rendered run passed **30 checks with zero errors or warnings**. Every racer
crossed exactly 24 gates, every CPU earned six mini-turbos, and the full race had no
skipped gates or recoveries.

| Finish | Racer | Time | Active rubber-band range |
| --- | --- | --- | --- |
| 1 | Player slot (QA pilot) | 45.82 s | Disabled |
| 2 | CPU 2 | 45.98 s | 0.99790–1.00000 |
| 3 | CPU 3 | 47.62 s | 1.00000–1.00595 |
| 4 | CPU 1 | 49.50 s | 1.00000–1.03702 |

There were no unexpected multiplier spikes. The greatest one-tick change was 0.0003333
at 60 Hz, matching the 0.02-per-second limit. The injected stall requested recovery
2.98 seconds after motion was suspended and the CPU resumed through CP1.
The local JSON report and MCP log retain full snapshots and evidence.

A separate post-race fault test suspends one CPU body's physics while leaving its AI
and positive speed telemetry active. The progress watchdog requests recovery in about
three seconds; physics resumes, the 0.9-second checkpoint reset completes, and the CPU
passes the next real checkpoint. This deliberate fault is labeled separately from the
full race in the report. Policy boundary checks cover both multiplier caps and the
neutral range. The retained Phase 2 headless suite passed all 33 non-screenshot checks.

An otherwise identical headless comparison with rubber-banding disabled finished in:
Player 45.82 s, CPU 2 45.98 s, CPU 3 47.62 s, CPU 1 49.93 s. The enabled headless run
reduced the last racer's deficit from 4.12 s to 3.68 s, preserving finishing order.
This is evidence of a mild effect on this oval, not a broad skill/balance conclusion.
Preferred lanes differ in travel distance; human driving and future track layouts still
need tuning. Windows/Linux runtime and packaged exports were not exercised in this phase.

Generated, Git-ignored evidence is in `artifacts/phase_3/`:

- `race-report.json`: finishing order/times, checkpoint counts, boosts, multiplier ranges,
  10-second standings snapshots, and isolated recovery test.
- `mcp-verification.json`: complete clean rendered-run log.
- `four-karts-mid-race.png`: all four moving karts, captured at about 9 seconds.
- `no-band/race-report.json`: the comparison race.
- `phase2-regression.log`: retained race-system checks.

```sh
godot --headless --path . --import
godot --path . res://scenes/test/AIGridVerification.tscn -- --phase3-check
# Fast non-rendered repeat; optional --no-band writes to a separate evidence directory.
godot --headless --fixed-fps 60 --path . res://scenes/test/AIGridVerification.tscn -- --phase3-check --no-band
```

Omit `--phase3-check` when running via MCP to keep the process alive for log retrieval.
The normal main scene has no QA player pilot and does not generate verification artifacts.
