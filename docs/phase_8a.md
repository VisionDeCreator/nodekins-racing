# Phase 8a — Dedicated-server movement prototype

This is a separate Godot project at `prototypes/networking/project.godot`. The normal
Nodekins title/menu/race project remains unchanged. The parent `.gdignore` keeps the
prototype out of the main project's asset imports. The server project has no race,
audio, customization, input-device or rendering dependencies at runtime.

## Run three independent processes

Run these in three terminals from the repository root. Replace `godot` with the
engine executable (`/Applications/Godot.app/Contents/MacOS/Godot` on this Mac).

```sh
# Once on a fresh checkout (opening this project in the editor also imports it).
godot --headless --editor --path prototypes/networking --import --quit

# Server: no player, camera, meshes, or local input. Defaults to loopback only.
godot --headless --debug --path prototypes/networking res://scenes/DedicatedServer.tscn

# Two purely client instances. Neither can automatically become a server.
godot --debug --path prototypes/networking -- --client --tag=A --address=127.0.0.1
godot --debug --path prototypes/networking -- --client --tag=B --address=127.0.0.1
```

Use `-- --server` with the main scene as an alternative to the dedicated scene.
A server started without `--headless` refuses to run. A failed client connection
exits; it does not create a local match. Closing clients leaves the server running.
For a server on a separate machine, explicitly set `--bind=0.0.0.0`, choose a UDP
`--port=29088`, and point each client at that machine with `--address=...`.
Internet deployment, authentication, encryption, discovery and orchestration are
outside this phase. This is a direct-address prototype.

Controls: W/up accelerates, S/down brakes, A/D or arrows steer. Gamepad left stick
steers, right trigger accelerates and left trigger brakes. Both produce the same
normalized `(throttle, brake, steer)` command. F8 injects a local two-metre state
fault for manual reconciliation inspection. There is no drift, glide, item, race,
collision-between-karts or production camera implementation here.

## Network simulation and reproducible verification

For manual latency testing, add the same flags to the server and both clients:

```sh
--latency=150 --loss=0.05 --jitter=20
```

Latency is **added one-way latency**, applied independently to outgoing inputs and
snapshots. Thus 150 ms tests about **300 ms RTT**, plus engine/network scheduling.
Loss is a fraction (0.05 = 5%) per datagram per direction. Jitter is uniformly
sampled ±20 ms. Setup/roster and benchmark control messages are reliable and bypass
this artificial link; this test measures movement, not impaired connection setup.

Add `--benchmark` to all three processes for four 12-second stages: 0, 75, 150 ms,
then 150 ms with 5% loss and ±20 ms jitter. The server starts three seconds after two clients
join, allowing the client windows to finish initializing. The first two seconds of each stage are excluded from steady-state metrics.
The server introduces an unannounced two-metre position disagreement six seconds
into each stage. Both clients must replay and visually blend to the corrected path.
After the drive, both brake; screenshots and reports are recorded after settling.
Press F5 in a benchmark client to switch to manual controls after the test.

A repeatable headless acceptance check launches three separate OS processes in
debug mode, validates reports/logs and stops them cleanly:

```sh
python3 tools/phase_8a/verify_networking.py --godot /path/to/godot
```

It uses port 29089 and `artifacts/phase8a/headless/` by default. `--port` and `--output`
override those. `--check-only --output=artifacts/phase8a` checks a separately captured
visible run. Do not use `--fixed-fps`: these tests must use real wall-clock time.
`--quit-after=SECONDS` is available for bounded standalone test runs.

Godot MCP can track one run and does not expose headless/argument options. The
visible verification therefore uses MCP to launch `res://scenes/ClientA.tscn`, the
CLI for the independent headless server and client B, and MCP's output reader for
client A. That scene enables the benchmark without needing CLI arguments.

## What is implemented

- `kart_motor.gd`: one shared 60 Hz, replayable planar motor. Speed-sensitive
  steering and non-linear acceleration, 20 m/s maximum. Primitive box karts start
  at (-4, 0, 14) and (4, 0, 14). A 240 m plane leaves room for repeated circles;
  a deterministic boundary clamp exists at ±114 m. No external physics solver is
  involved in replay. This deliberately does not prove prediction of the real
  CharacterBody3D's collisions, suspension, drifting or gliding.
- `network_lab.gd`: dedicated authority, client prediction/reconciliation,
  snapshot buffers, connection lifecycle, direct-address startup and benchmark.
- `impaired_link.gd`: bounded outgoing datagram delay, loss and jitter queue.
- `kart_view.gd`: presentation interpolation and a separate correction offset.
  Simulation state corrects immediately; the visible offset decays exponentially,
  capped at 4 m/s and 180 degrees/s. Ordinary reconciliation preserves the current
  rendered pose at the correction boundary; it never teleports the view.

The high-level ENet transport uses three channels: reliable setup on 0, unreliable
input on 1, and unreliable snapshots on 2. The server always has authority ID 1.
`SceneMultiplayer.server_relay` is disabled; clients never forward state to one
another. All RPC paths are `/root/NetworkLab` in every entry scene. API conventions
follow the [Godot high-level multiplayer documentation](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html)
and [dedicated-server guidance](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html).

Clients generate commands at 60 Hz and send at 30 Hz, including up to 48 commands
starting at the oldest unacknowledged sequence. Retaining the oldest commands
recovers both isolated packet loss and longer process scheduling stalls without
throwing away unsimulated input. Ownership comes from the RPC sender,
not an ID supplied inside the packet. The server validates finite normalized input,
sequence bounds, packet sizes and a per-tick packet cap. It normally advances one fixed command per tick. A queue above six commands can
consume two steps per tick while catching up, constrained by a 60 Hz wall-clock
budget with at most one second of saved credit. This recovers from scheduling stalls
without permanently increasing input delay. It bounds burst execution; production
anti-cheat and a stricter client-clock discipline remain future work.

Each server snapshot (20 Hz) carries a server tick, peer IDs, last consumed input
sequence per kart, and five floats per state: x, z, yaw, speed, smoothed steering.
The client replaces its state at the acknowledged command and replays remaining
commands through the same motor. Stale snapshots are discarded. Unacknowledged
history is bounded to 512 commands; exhaustion disconnects with a visible reason
instead of silently freezing or growing memory without bound.

The server initially buffers three commands. Queue depth, catch-up steps, missing
command substitutions and boundary contacts are included in the server report. Short delivery gaps wait for redundant
inputs. If later commands arrive while a sequence remains missing, a bounded wait
is followed by a neutral/braking substitute. It never simulates extra unacknowledged
steps under the same sequence number, which would invalidate client replay. Complete
input silence stops that kart's progression; disconnect removes its record and view.

Remote karts render 100 ms behind the estimated received server timeline, interpolate
positions and wrapped angles, and apply render smoothing. Extrapolation is limited
to 100 ms, then holds until fresh state arrives. This is additional presentation
latency, not a promise that both clients display the same real-time pose while moving.
The final side-by-side captures are taken after braking, when all views should agree.

## Carrying this into the full kart

1. Extract a replayable movement step and complete snapshot/restore state from the
   existing controller while preserving its public input/stats interfaces. Include
   ground contact, vertical velocity, drift timers/tier, boost duration, glide state,
   steering smoothing and all other state that affects subsequent motion.
2. Define authoritative collision resolution and a replay strategy for static track
   geometry and moving karts. This planar prototype avoids non-deterministic physics
   contacts; identical floating-point output across platforms is not assumed.
3. Feed input commands through the existing analog input interface. Buffer/replay
   input for the owning client, render delayed authoritative snapshots for other
   clients, and keep camera/art/audio outside replay. Give one-shot effects event IDs
   so replay cannot duplicate sound, items or launch/landing effects.
4. Move RaceManager, checkpoints, item rolls/hits and finish decisions to the dedicated
   authority. Replicate reliable outcomes separately from movement snapshots.
5. Replicate the existing compact customization IDs with a version/revision, resolve
   them using local registries, and keep asset paths off the wire. No customization
   or content replication is part of this prototype.

The intended next step is that controlled integration, not matchmaking or a lobby.

## Verified results — 20 September 2026

Tested on Godot 4.7.2/macOS: one independent headless server, client A through Godot
MCP, and client B through the CLI, both rendering real windows. All three final
output logs contain **zero errors and zero warnings**. The full debug-mode headless
regression also passed. Only macOS has been exercised; Windows/Linux and real WAN
conditions still require cross-platform testing.

| Added one-way delay | Median RTT A / B | Two-metre correction settles A / B | Maximum pending commands A / B |
| --- | --- | --- | --- |
| 0ms | 15 / 14 ms | 0.72 / 0.73 s | 9 / 9 |
| 75ms | 164 / 164 ms | 0.73 / 0.73 s | 17 / 16 |
| 150ms | 317 / 314 ms | 0.73 / 0.72 s | 24 / 24 |
| 150ms_loss_jitter | 314 / 314 ms | 0.73 / 0.73 s | 30 / 30 |

Each stage applies local input during the same 60 Hz prediction step, with no wait
for a server response. The reported 16.67 ms input value is the **fixed-step response
bound**, not a measured hardware-to-display latency. This was a scripted drive,
not a hands-on gamepad feel check.

At 0 ms the remote presentation already includes the intentional 100 ms buffer.
At 75 ms, the local response has the same immediate code path while remote state is
older. At 150 ms, remote delay is more noticeable by design, but the buffer never
ran dry beyond the 100 ms extrapolation allowance in this run. With loss and jitter,
brief extrapolation occurred; neither client entered the beyond-limit hold state.
The same snapshot/replay path corrected all eight forced two-metre disagreements
without a rendered position jump. The corrections produce a short visible lateral
blend, rather than hiding an authoritative discrepancy indefinitely. A human
should judge that blend speed and remote delay before full-controller integration.

The largest measured discontinuity at a local reconciliation boundary was below
0.001 m (zero in these captures). Visual correction speed remained capped at 4 m/s.
Normal acknowledgement error at the 95th percentile was below 0.000001 m on both
clients; each deliberate fault still correctly registered an approximately 2 m
maximum error/correction. This same-machine planar result is not a claim of
cross-platform physics determinism.

Final authoritative coordinates: A `(13.537042, 13.302711)`, B
`(-13.537042, 13.302711)` in x/z, both stopped. Both clients' rendered coordinates
agree with the server within 0.03 m and headings within 0.001 radians (actual errors
are much smaller). Neither kart touched the artificial boundary.

Window-startup scheduling stalls also occurred. The final server recovered all
input through bounded catch-up, with **zero missing-command substitutions**, and
steady-state pending histories remained bounded as shown above. The disconnect
check separately observed two clients → one client → zero clients, with the server
continuing to tick after both had left (`artifacts/phase8a/lifecycle.log`).

Evidence (generated artifacts are intentionally not versioned):

- `artifacts/phase8a/server.log`, `client_A.log`, `client_B.log`: actual process/MCP output.
- `artifacts/phase8a/server.json`, `client_A.json`, `client_B.json`: full metrics and poses.
- `artifacts/phase8a/clients_side_by_side.html`: unmodified viewport captures arranged
  for comparison, explicitly labeled as separate captures rather than a desktop screenshot.
- `artifacts/phase8a/client_A.png`, `client_B.png`: original 640×560 captures.
- `artifacts/phase8a/headless_current/`: independent headless debug regression.

The prototype clients are left open after the benchmark. F5 enables manual driving
in each focused client; WASD/arrows or a gamepad control it. The dedicated server
remains a separate process with the final 150 ms/loss/jitter preset active. Restart
using the commands above for a clean manual 0/75/150 ms comparison.

| Client A | Client B |
| --- | --- |
| ![Client A](../artifacts/phase8a/client_A.png) | ![Client B](../artifacts/phase8a/client_B.png) |
