# Phase 2 — Track systems

Verified on 2026-09-19 in Godot 4.7.2 on macOS. Main scene:
`scenes/track/Track.tscn`. F5 starts the race; Enter / gamepad Start restarts the countdown.
WASD/arrows, Space drift, and gamepad driving controls are unchanged. R / north face
button now requests recovery to the last accepted checkpoint during a race.

## Track and lap rules

Loop 01 is a raised, 14 m wide oval with 32 m bend radii and 72 m straights. Its sampled
centerline is **344.92 m** long. `resources/tracks/oval.tres` supplies 84 centerline points
and eight gate indices. `graybox_track.gd` builds road boxes, walls, center dashes, and
gate markers at runtime from this Resource. The track root stays at the world origin;
the route positions are world-space. These are Godot gray-box primitives, not production art.

CP0 is start/finish; the valid order is **CP1 → CP2 → … → CP7 → CP0**, repeated three times.
The kart starts on CP0 with CP0 already considered its initial recovery anchor. Touching
or rocking across the start line cannot award a lap. Each Area3D records passage across
its oriented center plane, rather than merely awarding progress on body entry.

- Forward crossing of the next expected gate accepts it.
- Re-crossing the last accepted gate grants nothing.
- Backward crossing shows WRONG WAY and grants no checkpoint or lap.
- Crossing a later gate without its predecessors shows the missed checkpoint, increments
  `invalid_crossings`, and requests recovery. It is not silently ignored.
- Movement outside the current valid route sector for over two seconds requests recovery.
- The first fully validated finish crossing completes lap 1. The third finishes the racer.

A **12 m opening in the first straight's outer wall** deliberately provides a physical
fall test. The road itself remains continuous. Other walls keep the loop readable and
forgiving. The body has to actually drive over an edge and fall to trigger fall recovery.

## RaceManager autoload

`scripts/race/race_manager.gd` is registered as `RaceManager` in `project.godot`.
It holds per-kart records independently of the track scene and has no hardcoded track
node paths. Register competitors before starting; the playable scene registers one player.

| Public operation | Purpose |
| --- | --- |
| `configure(route, laps = 3)` | Clear previous race and supply route/race length |
| `register_kart(kart, racer_id, display_name)` | Register a unique kart and stable ID while idle; returns success |
| `unregister_kart(racer_id)` | Remove a racer and release its input/recovery ownership |
| `start_race()` | Reset racers to their grids and start 3–2–1–GO |
| `report_checkpoint(kart, index, forward_crossing)` | Entry point for trusted local checkpoint volumes |
| `request_recovery(racer_id, reason)` | Request delayed recovery without accessing movement internals |
| `get_racer_state(racer_id)` | Obtain an independent serializable state snapshot; unknown ID returns `{}` |
| `get_standings()` | Obtain ordered snapshots for every registered kart |
| `clear_race()` | Release registrations when leaving the scene |

Snapshots include displayed lap, completed laps, last/next checkpoint, lap distance,
total distance progress, position, racer count, elapsed time, lap times, wrong-way flag,
invalid-crossing count, recovery reason/count/delay, finished flag, finish order, and finish time.
`lap` is one-based and capped at three; `completed_laps` runs from zero to three.
`next_checkpoint` remains the cyclic successor after finishing, but `finished` prevents
further progression. The current geometric lap-distance cursor wraps at CP0.

Position is based on completed laps plus projection onto **only the currently validated
checkpoint sector**, not the nearest point anywhere on the oval. Going backward can
decrease progress within that sector. Projection is capped at the next required gate.
Finished racers rank by immutable finish order. Other racers rank by distance, using
millimetre buckets and stable registration-order ties. A single finisher does not end a
multi-kart race; the race ends when every remaining registered racer has finished.

Signals: `countdown_changed`, `race_started`, `checkpoint_passed`, `lap_completed`,
`racer_finished`, `race_finished`, `route_violation`, `recovery_started`, `recovery_completed`.
The HUD polls snapshots; future items/AI/UI can use these queries and signals.
This is local race authority; network validation remains a later phase.

## Additive Phase 1 interface changes

These additions were flagged before implementation. Existing stats, input command, and
camera interfaces retain their signatures; the RaceManager never writes private kart fields.

- `ArcadeKart.respawn_at(Transform3D)` resets position, direction, speed, velocity, drift,
  interpolation, and steering smoothing, then emits the existing `respawned` signal.
- `ArcadeKart.recovery_requested(reason)` delegates recovery to a connected recovery owner.
  RaceManager subscribes for registered racers. With no subscriber, Phase 1's local
  start-position reset and fall behavior remain intact.
- `KartInput.set_locked(bool)` / `is_locked()` apply an authoritative input lock after
  either human input or injected commands are sampled. Held input and future AI commands
  cannot bypass the countdown, recovery, or finish lock.

Recoveries wait **0.9 s**, preserve completed laps and the last accepted gate, and place
the kart 3 m beyond that gate, facing forward. The extra offset avoids re-triggering the
gate on spawn. Race time continues during recovery. Falls below Y = −2, manual reset,
missed gates, and sustained throttle with speed below 0.7 m/s for 2.5 s request recovery.
An idle kart does not count as stuck. Countdown time is excluded from race time.

## Verification

`scenes/test/RaceVerification.tscn` runs a QA-only input driver through the entire course.
The full race uses the public normalized input boundary and **real Area3D crossings**;
it does not teleport the racer or inject progress. The clean Godot MCP run completed
**36 checks, zero failures, zero errors, and zero warnings**.

The full race finished in **52.43 s**, with exactly **24 accepted crossings**, no invalid
crossings, and no recoveries. Lap times were **17.83 / 17.30 / 17.30 s**.

| Race snapshot | Displayed lap | Completed laps | Last → next CP | Total progress | Position |
| --- | --- | --- | --- | --- | --- |
| 9.18 s | 1 | 0 | 4 → 5 | 172.73 m | 1 / 1 |
| 24.17 s | 2 | 1 | 3 → 4 | 471.54 m | 1 / 1 |
| Finish, 52.43 s | 3 | 3 | 0 → 1 (inactive) | 1,034.76 m | 1 / 1 |

Additional checks physically cross a skipped gate and a backward gate, drive off the
open edge, and hold throttle against a wall. Fall detection occurred at Y = −2.15 m
and recovered to **CP1**, retaining **CP2** as the next target. Managed manual reset,
countdown/finish locks, stopped timers, and idle-vs-stuck behavior were checked.

Separate stationary multi-kart fixtures test sector-distance ranking, equal-distance ties,
independent query snapshots, lap precedence, partial finish behavior, and cleanup on removal.
Only those isolated ranking fixtures inject checkpoint events; their times are not race
performance measurements. They are not AI racers in the playable scene.

The Phase 1 headless controller regression suite also passed (34 non-screenshot checks).
Local evidence is in `artifacts/phase_2/`: `mcp-verification.json`, `race-report.json`,
`track-layout.png`, `countdown.png`, `race-finished.png`, and `phase1-regression.log`.
All three captured frames were visually inspected. Generated evidence is ignored by Git.

Run the verification scene through Godot MCP/editor, or run:

```sh
godot --headless --path . --import
godot --path . res://scenes/test/RaceVerification.tscn -- --phase2-check
```

`--phase2-check` exits with success/failure after the tests. Without it, the verification
scene stays alive so MCP can retrieve the complete log. Native Windows/Linux execution,
AI racing, kart-to-kart collision behavior, and new packaged desktop exports are not
part of this verification. The Phase 0 build binaries are historical; use F5 or re-export.
