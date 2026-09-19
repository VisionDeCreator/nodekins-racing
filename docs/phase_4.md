# Phase 4 — Items and power-ups

Godot 4.7.2 / macOS, 2026-09-19. The normal `Track.tscn` now starts a four-kart,
three-lap race with items enabled. Press **E** or the **gamepad west face button
(X on Xbox / Square on PlayStation)** to use the held item. All other controls are
unchanged. Enter / Start resets the race and its items.

## Pickups and inventory

Twelve rotating cyan gray-box ItemBox instances are placed in four rows around the
track, at route distances 28, 145, 201, and 317 metres. Each row spans lanes −3.2,
0, and +3.2 m. A valid racer overlapping a box receives one position-weighted item.
The box disappears immediately and becomes available again after **4 seconds**.
A kart with a full slot leaves the box available to others. A shared availability
flag prevents two racers collecting the same box in one physics tick.

The item slot shows the held Resource's name, description, and color. CPU inventories
have the same capacity, pickups, effects, and input locks as the player. CPU logic waits
briefly, prefers a straight/turn exit for Boost, drops Banana, and fires Shell when a
target is ahead or after a five-second maximum hold. It does not hoard indefinitely.
The player in the normal scene has no automatic item-use or steering driver.

## Resource-driven items

`ItemDefinition` holds a stable ID, display name, description, duration, color,
front/back roll weights, CPU delay, and an effect Resource. The catalog automatically
loads `.tres` definitions under `resources/items/`, including remapped export paths.
Creating another Resource with an existing effect adds a variant without inventory,
HUD, pickup, or CPU code changes. A fundamentally new behavior can supply an `ItemEffect`
strategy implementing `activate` and optionally `cpu_should_use`; there is no central
item-name switch to expand.

| Resource | Starting parameters | Behavior |
| --- | --- | --- |
| `boost.tres` | 1.5×, 2 s | Existing turbo acceleration, visual trail, and FOV kick |
| `shell.tres` | 36 m/s, 4 s lifetime, 55°/s maximum homing | Fires forward, lightly follows a target initially within 38 m / 35°, stops at first collision |
| `banana.tres` | 18 s lifetime, 0.45 s arming | Drops 2.8 m behind; catches the first kart crossing it |

Shell and Banana use the same configurable deployment strategy and actor script, with
different scenes and parameters. Shell has a swept spherical collider, so its travel
between physics ticks is checked; walls also stop it. Shell excludes its firing kart.
Banana can hit its owner on a later pass once armed. Both disappear after the first
collision, including an immune target, or their configured timeout. Shapes are Godot
placeholders; no production Blender art was introduced in this phase.

Hits cancel boost/drift charge and apply **0.95 s** of ordinary braking/input suppression.
The mesh spins and flashes pink, while the existing CharacterBody3D controller continues
to handle collision, gravity, and movement. Hit immunity lasts through the spin plus
**2 seconds** afterward to prevent consecutive traps from indefinitely disabling input.
Race time and lap validation continue normally.

## Position weighting

Weights interpolate linearly across the current RaceManager position, then a random
weighted draw chooses the item. Production races randomize the seed; QA uses seed 404.

| Item | First place | Last place |
| --- | --- | --- |
| Boost | 1 / 9 = 11.1% | 5 / 10 = 50% |
| Shell | 2 / 9 = 22.2% | 4 / 10 = 40% |
| Banana | 6 / 9 = 66.7% | 1 / 10 = 10% |

Every item remains possible in every position. In a 6,000-roll check per position,
first place rolled 686 Boost / 1,370 Shell / 3,944 Banana; last place rolled
3,101 Boost / 2,318 Shell / 581 Banana. These rolls were separate from the race.

## Flagged additive APIs and composition

The following additions were flagged before implementation. Existing signatures remain
compatible. `ArcadeKart` movement code, `KartAI` rubber-banding, and RaceManager are unchanged.

- `KartInput.request_item_use()` queues one item-use command; `item_use_requested` emits
  only when input is permitted. Keyboard, gamepad, and CPU inventories share this path.
- `KartInput.suppress_for(seconds)` / `clear_suppression()` and the read-only-by-convention
  `suppression_remaining` field expose timed disabling. `is_locked()` now reports either
  the existing race lock or timed suppression. Suppression expiry cannot clear a race lock.
- `KartDrift.activate_boost(multiplier, duration, tier_hint)` is shared by mini-turbo
  releases and Boost items. Overlap takes the strongest multiplier and longest remaining
  duration, rather than multiplying or adding boosts. Existing boost signals, trail,
  camera, and movement acceleration observe the same state.

Items never overwrite velocity, kart pose, or CPU top-speed stats. The ordinary movement
controller applies braking for hits and turbo acceleration for Boost. Rubber-banding
continues to adjust the CPU's base speed, and the shared turbo multiplier applies on top.
A recovery/finish clears inventory and suppression; a race restart also resets boxes and
removes all live projectiles/traps. Countdown, recovery, finish, and hit locks prevent use.
No race progress or checkpoint API was changed.

## Verification

`scenes/test/ItemVerification.tscn` first runs all four karts through a full physical race,
with seed 404 and real box overlaps, real deployed-object collisions, and real checkpoint
crossings. A QA-only driver pilots the player slot and uses its normal item command API.
Every racer picks up and uses all three item types in that seeded race. The normal scene
leaves the player under human control.

The clean rendered Godot MCP run passed **52 checks, zero errors, zero warnings**.
The player slot's QA pilot finished at **47.80 s**, CPU 2 at **48.52 s**, CPU 3 at
**50.62 s**, and CPU 1 at **51.18 s**.

| Item moment | Pickup → use | Observed effect |
| --- | --- | --- |
| Player Banana | 7.48 → 8.58 s | Hit CPU 3 at 9.22 s; 32.0 → 8.9 m/s, still visibly spinning at the sample |
| CPU 1 Shell | 7.82 → 8.52 s | Hit player at 9.55 s; 20.0 → 0.0 m/s |
| CPU 3 Boost | 11.25 → 12.05 s | 20.0 → 30.0 m/s |

The full race finished with 24 accepted gate crossings per racer and no checkpoint
violations or recoveries. Race positions were checked on every sampled physics tick.
Measurements 0.55 seconds after hits/boosts confirm speed effects through the kart controller.
Individual item uses can be interrupted by traffic or another hit; not every Boost reaches
its maximum speed in a crowded race.

Separate post-race fixtures verify all three effects for a player and CPU owner, shell
first-hit-only behavior with a second kart behind the target, shell owner exclusion,
trap arming, real trap hits, immunity, input restoration, inventory capacity, trap timeout,
box disappearance/respawn, boost overlap, race-lock precedence, restart cleanup, and
synthetic keyboard/gamepad input events. Fixture teleports and an accelerated trap-lifetime
check are explicitly outside the full race; they are not used as race evidence.

The Phase 1 headless movement suite and all 28 Phase 3 non-screenshot checks also passed
with items disabled in the retained fixtures. This verifies the new input/boost paths
preserve prior handling and CPU behavior. Phase 2's fixture also explicitly disables items.
Human balance/feel, native Windows/Linux runtime, and packaged exports remain unverified.

Local, Git-ignored evidence lives in `artifacts/phase_4/`:

- `race-report.json`: results, full-race item events, measured speed effects, positions,
  weighted-roll distribution, isolated checks, and failures.
- `mcp-verification.json`: clean rendered Godot MCP output.
- `item-hud.png`: player holding a Shell after a real pickup.
- `banana-on-track.png`: deployed yellow trap behind CPU 1, with the field racing past.
- `phase1-regression.log` and `phase3-regression.log`: prior-phase checks.

```sh
godot --headless --path . --import
godot --path . res://scenes/test/ItemVerification.tscn -- --phase4-check
# Faster repeat without screenshots:
godot --headless --fixed-fps 60 --path . res://scenes/test/ItemVerification.tscn -- --phase4-check
```

Omit `--phase4-check` for MCP log retrieval after the suite. The playable main scene
never pilots the player or generates QA reports. Every production pickup, use, boost,
hit, ignored hit, and actor removal logs an `[Items]` record with race time and racer IDs.
