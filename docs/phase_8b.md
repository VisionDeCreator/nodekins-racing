# Phase 8b — Full dedicated-server race

The real `Kart.tscn`, Loop 01, ordered checkpoints, three laps, drift/mini-turbo,
glide gap, items, boost pads and ID-based appearance now run in a separate online
mode. `Main.tscn` remains the single-player entry point. There is no lobby or
matchmaking, and no client ever becomes the server.

## Run a direct-connected race

Use the same project/content and Godot 4.7.2 on each process. Commands assume
`godot` is on PATH; on the development Mac it is
`/Applications/Godot.app/Contents/MacOS/Godot`.

```sh
# Independent headless authority; waits for two human connections.
godot --headless --path . res://scenes/network/DedicatedRace.tscn -- --players=2 --port=29188

# Separate client processes, or run one on each player's computer.
godot --path . res://scenes/network/OnlineClient.tscn -- --address=127.0.0.1 --port=29188 --tag=A
godot --path . res://scenes/network/OnlineClient.tscn -- --address=127.0.0.1 --port=29188 --tag=B
```

The default server binds loopback. For other computers use `--bind=0.0.0.0` on
the server, its actual address on clients, and permit UDP 29188 on the server.
The headless process is the only authority, including when all three processes
run on the same development machine. Keyboard/gamepad actions are unchanged.
Escape returns a client to the existing title screen. Start a fresh server for
the next race; online rematch/lobby flow is deferred to 8c.

`--players=2`, `3` or `4` sets required human connections. Existing server-run
KartAI drivers fill the remaining places to four. This keeps the race populated
and exercises the original AI, rubber banding and item logic on the authority.
The ordinary client loads the existing locally saved profile; it never sends
asset names or paths. `--verify` instead uses a repeatable input-generating QA
pilot and temporary red/female/Mohawk and cyan/male/Quiff profiles. It neither
teleports racers nor injects checkpoint/lap results, and never saves those profiles.

## Ownership and protocol

| State | Owner / delivery |
| --- | --- |
| Input | Client sends sequenced normalized throttle/brake/steer/drift/reset/item commands; server validates sender, shape, bounds, finite values and rate |
| Movement | Same full controller step on server and owner; 60 Hz inputs, 30 Hz redundant command batches, 20 Hz authoritative snapshots |
| Local correction | Restore acknowledged state, replay remaining commands against the real static track, then decay visual/camera offsets without a correction-boundary position jump |
| Remote karts | Buffered server transforms, approximately 100 ms interpolation delay, bounded 100 ms extrapolation then hold |
| Laps/checkpoints/positions/finish | Only server RaceManager evaluates rules; clients expose its received rows through a read-only replica mode |
| Boxes, rolls, inventory, pads, shell/banana collision and lifetime | Original item systems run only on server; clients receive box cooldowns, inventory IDs and mesh-only actor replicas |
| Appearance | Protocol version plus existing 13-byte profile, validated through the existing registry; relayed IDs resolve to each client's local parts/materials |
| Discrete presentation | Serial-numbered reliable server events for drift/boost/glide/item/race audio; prediction replay cannot emit duplicate gameplay events |

ENet server relay is disabled. Client RPCs cannot submit transforms, hits, lap
counts or finish order. Command credit is bounded by elapsed server time, with
at most two input steps per physics tick for catch-up. Missing input is retained
and resent from the oldest unacknowledged command. Movement snapshots are compressed
and split into at most 900-byte payloads, avoiding ENet's unreliable-packet MTU
warning; incomplete/stale snapshot fragments are discarded. Object deserialization
is not enabled.

The impairment queue applies outgoing one-way delay, optional jitter and random
loss to movement datagrams. Reliable events get the delay/jitter but are not
randomly discarded by the simulator; this is not a full emulation of TCP/ENet
retransmission behavior or real WAN congestion. Setup RPCs are unimpaired.

## Full-controller migration details and public additions

The ground acceleration, steering, drift equations, handling Resource and glide
physics remain shared with single-player. New opt-in hooks are `network_driven`,
`simulate_step`, `network_snapshot`, `network_restore`, `network_mute_signals` and
`has_ground_contact` on ArcadeKart, with snapshot/restore helpers on its components.
The original `_physics_process` invokes the same step when not network-driven.
RaceManager adds explicit replica/snapshot methods; inventory adds read-only
replica updates. Track gains `external_race_management` to reuse its geometry
without spawning a second race. All these switches default to offline behavior.
RaceAudio's configurable local racer ID defaults to the original `player`.

Three differences from the simplified 8a prototype required special handling:

- **State beyond transforms:** travel direction, input smoothing/locks/spin-out
  suppression, recovery, drift charge/tier, boost duration/multiplier, glide launch
  heading/entry state/bank and floor-snap length must survive restore and replay.
- **Engine-owned floor contact and Areas:** restoration refreshes the internal
  CharacterBody contact cache and supplies the saved ground-contact result for the
  first replay decision. The online glide launcher checks swept crossings against
  the original authored launch volume, so replay does not depend on stale Area
  overlap notifications. Server checkpoint/item Areas remain the real existing
  systems.
- **Repeated side effects:** replay mutes component signals. Server events are
  ordered and deduplicated for presentation, while item results arrive in full
  snapshots. Drift/boost timers advance only through the shared movement step.

The chase camera reads an optional corrected render transform online. Remote
snapshot refresh preserves the current interpolated pose instead of briefly
moving the visible body to the newest server pose. Current-camera selection happens
after the entire grid has been instantiated.

Dynamic kart contacts are authoritative on the server. Owner replay predicts
static-track collisions and receives corrections for other karts and item hits.
This avoids replaying contacts against other racers at mismatched times, but
contact-heavy human races still need a feel-check. Local correction displacement
is limited to 8 m/s and yaw correction to pi rad/s; deliberate recovery teleports
use an authoritative epoch and camera reset. No claim of cross-machine deterministic
physics or a human gamepad feel assessment is made.

## Disconnects

Mid-race disconnect removes the kart, inventory and its active deployed items,
unregisters the racer and relays removal. Other racers continue with authoritative
standings. Mid-race join/reconnect is explicitly rejected; there is no attempt to
restore a departed player's slot. No permanent collidable abandoned kart remains.

## Verification

The MCP runner owns one game process, so rendered verification uses MCP for client
A, the Godot executable for client B, and a third independent headless Godot process
for the authority. Test reports and actual viewport PNGs are in `artifacts/phase8b/`.
The repeatable headless harness launches all three processes itself:

```sh
python3 tools/phase_8b/verify_online.py --output artifacts/phase8b/new_latency_run --latency 75
python3 tools/phase_8b/verify_online.py --output artifacts/phase8b/new_loss_run --port 29189 --latency 75 --loss .02 --jitter 10
python3 tools/phase_8b/verify_online.py --output artifacts/phase8b/new_disconnect_run --port 29190 --latency 75 --disconnect

godot --headless --debug --path . res://scenes/network/OfflineRegression.tscn -- --phase7-check
```

Use a fresh output directory per run; the harness rejects stale reports. The
headless pilots generate real input. Assertions compare complete final race rows,
all critical server events, applied appearance IDs, matching authoritative item
and race evidence, successful glide landings, measurable hit/boost effects and
bounded correction presentation. Logs are checked for errors and warnings.

The offline wrapper reuses the Phase 7 suite with an isolated customization save.
It passed all 74 checks, including the menu-to-results physical race, customization,
HUD state, audio cues and volume controls, with no errors or warnings. The older
Phase 6.5 test's direct quit was updated to use the existing audio shutdown drain;
that test-only cleanup avoids exit-time resource leaks.

The `loss_03` run passed with 75 ms added per direction (159/166 ms median RTT),
2% datagram loss and +/-10 ms jitter. All four racers completed three laps and
three glide landings, with no recoveries. Player 1 completed lap one at 13.783 s.
At 9.167 s its banana hit CPU 1; 0.35 s later CPU 1 had slowed from 32 to 18 units/s
and retained 0.617 s of input suppression. At 5.083 s Player 1 used Boost, increasing
20 to 30 units/s. Both clients received the same event serials and data. Results:
Player 1 43.783 s, Player 2 46.533 s, CPU 1 48.083 s, CPU 2 48.733 s.

`disconnect_03` disconnected Player 2 at 10 s. Player 1 and both CPUs finished;
the surviving client's complete official standings matched the server. Both tests
had zero reported engine/script errors or warnings. The final rendered run also passed after correcting current-camera selection
and preserving the remote interpolation pose during snapshot refresh.

| Position | Racer | Official time |
| --- | --- | --- |
| 1 | CPU 1 | 44.033 s |
| 2 | CPU 2 | 48.517 s |
| 3 | Player 2 | 48.700 s |
| 4 | Player 1 | 51.850 s |

Both clients had 166 ms median RTT, zero official race-state mismatches and three
successful glides for every kart. All 493 server events were delivered in order;
checked checkpoint/lap/finish/item/glide events had identical serials and data.
Client A applied 1,200 snapshots; B applied 1,196. Maximum acknowledged-state
position disagreement was 0.150 m on each client; p95 was 0.000 m. Item/contact
corrections produced transient visual offsets up to 2.67 m (A) and 2.36 m (B),
which decayed at the configured limit rather than jumping at the correction
boundary. These are presentation offsets, not discrepancies in official race state.
They should receive particular attention in a human listen/drive check.

Concrete checks in that rendered run:

- At 9.650 s, CPU 2's shell hit Player 1 (serial 89). At 10.000 s the target had
  slowed from 32 to 18 units/s with 0.617 s suppression remaining. Both clients
  received the exact same authoritative hit event.
- Player 2 completed lap one at 15.133 s (serial 135), with the same checkpoint,
  lap and position report on both clients.
- Client B applied Player 1's thirteen IDs to both the kart assembly and rider:
  red alternate chassis, female body, Mohawk. Client A similarly applied the cyan
  male/Quiff profile for Player 2, with no asset transfer.
- The live screenshots both display server tick 1059 with matching standings and
  inventories. Additional diagnostic views render tick 1062 (4.05 s) with all four
  customized karts from the same authoritative snapshot.

Open `artifacts/phase8b/verification.html` for the two live viewport PNGs and the
side-by-side synchronized diagnostic views. The latter are explicitly labeled:
they temporarily render received authoritative poses using each client's loaded
meshes, and are not presented as ordinary chase-camera or desktop screenshots.
The JSON reports, moment data and three process logs sit beside the page. Failed
intermediate checks are retained in their earlier artifact folders; they are not
used as the final passing evidence.

Verification was automated on macOS/Godot 4.7.2. It validates actual physical races
and state agreement under simulated impairment, not a production WAN soak or a
subjective human handling assessment. The 8a prototype remains unchanged.
