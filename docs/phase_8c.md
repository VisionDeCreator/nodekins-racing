# Phase 8c — Server-driven matchmaking

The title screen now includes **Race Online → Find Match**. Online players do not
select a track, mode, host, room or server address. They see their saved customized
kart/driver, search status and elapsed time, and can cancel independently. The
existing Play/character/track selection flow is still single-player.

## Implemented service model

A separate headless matchmaking service owns a FIFO queue. It requires two human
requests by default, waits a short three-second grouping window, randomly selects
an available track from `GameSession.catalog.tracks`, and launches a dedicated
race process. There is **one active worker slot**. Additional players stay queued
with an explicit “waiting for the next available race server” message and elapsed
time. Completed/failed workers are retired and the slot can serve the next group.
The service persists across matches; the race process is fresh for each match.

The service is infrastructure-owned. Clients never create server processes or
choose the track, including in the automated tests. For local verification the
service, race worker and clients happen to run on the same development computer,
but remain separate OS processes and separate ENet connections.

The shared track catalog now has an `online_world` PackedScene field on each track
entry. Only entries with an online world are eligible. Selection uses the server's
RandomNumberGenerator over that list, including when its length is one. The current
entry is `loop_01` / **Skyline Loop**. Adding another online track means registering
its dedicated-world scene alongside its catalog entry; no matchmaking UI list or
client selection code needs changing. The world must implement the existing
OnlineRaceWorld contract and contain that track's gameplay geometry/art.

The only change to the 8b implementation is an overridable `_create_world()`
construction hook, whose default remains the original world. The matched-session
adapter selects the assigned catalog world through that hook. Its other changes
are admission, startup timeout and lifecycle handling. Kart movement, prediction,
reconciliation, race rules, items, checkpoint evaluation and authoritative event
replication are inherited from 8b, unchanged.

## Boundaries and request flow

`Matchmaking` is an autoload with its own SceneMultiplayer/ENet peer scoped to its
`Wire` child. The race still uses its independent default multiplayer peer. This
keeps queue messages and session assignment out of the race RPC namespace. Godot's
[SceneMultiplayer branch support](https://docs.godotengine.org/en/stable/classes/class_scenemultiplayer.html)
and [high-level multiplayer API](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html)
provide the transport separation.

1. Find Match sends a request generation and the existing **13-byte customization
   profile**. It sends no requested track or mode. The service validates every ID
   against the existing local registry and allows one outstanding request per peer.
2. The queue forms a group and chooses the track. The service writes a local worker
   reservation containing the chosen track ID, profiles and unique 24-byte random
   admission tickets. These files are local control-plane data, not asset transfers.
3. The service launches and health-checks the dedicated worker before assigning
   its endpoint, track ID and each player's ticket. A failed start or missing ready
   report returns both players to a retryable error state.
4. Each client resolves the server-selected track locally, loads the matched-race
   adapter and redeems its ticket on the separate race connection. The reserved
   profile is passed through the original 8b admission/grid validation. Clients
   cannot replace it with a second profile or enter by calling the old hello RPC.
5. The inherited grid/countdown/race runs. Clients display the server's track name
   and official race state. Profiles still resolve through local part registries.

The service only receives worker lifecycle status (`admitting`, `running`,
`finished`); it does not calculate or write laps, movement, item effects or results.
The normal race connection can continue if matchmaking goes down after admission.

## Cancel, disconnect and error behavior

- **Cancel while searching/preparing:** removes the request, invalidates its
  generation and reserved ticket, and immediately restores Find Match. Delayed
  replies for the old request are ignored. Retry can use the same connection.
- **Queued disconnect:** removes the peer's request. No other player's approval or
  action is needed, and no stale queue entry counts toward the minimum.
- **Assigned player missing before grid assembly:** admission is bounded to 12
  seconds from worker startup. The remaining admitted player starts with three
  original server-controlled CPUs. No new player is required to rescue the match.
- **Disconnect after grid assembly:** remove the departed kart and continue with
  the ready racers and existing CPUs. Unready peers cannot indefinitely block the
  countdown. The normal 8b mid-race removal behavior is retained.
- **Nobody joins:** the empty worker exits and the service frees its slot.
- **Service unavailable:** a bounded eight-second connection timeout gives a
  “Please try again” message. A lost connection while searching does the same.
- **Assignment fails / worker dies / race connection times out:** the menu returns
  to Race Online with the error and Try Again available. Back returns to the title.
- **Race completed:** Escape returns to the title; Race Online can request another
  automatic match. No operator restart or manual server address is needed.

Request generations also prevent cleanup of a previous match from deleting a
newly queued request on the same connection. The repeat-match test exercises that
case while the old worker is being retired.

## Running it

Defaults are in `resources/matchmaking/default_settings.tres`: queue port **29200**,
race port **29201**, minimum/maximum humans **2**, one worker, grouping window **3 s**,
startup deadline **15 s**, admission deadline **12 s**, service connect timeout
**8 s**, worker watchdog **300 s**. The extra reserved grid slots use existing AI.

From the project directory, launch the service independently:

```sh
godot --headless --path . res://scenes/matchmaking/Service.tscn -- --match-service
```

Launch the ordinary game twice, or run it on two configured client machines. Each
player uses **Race Online → Find Match** from the title. No special client scene
or verification flag is needed for manual play. Saved customization is used.

The local defaults bind loopback. For a service on infrastructure, configure the
client build's `service_address`, and launch the service with its real advertised
race address and network binding, for example:

```sh
godot --headless --path . res://scenes/matchmaking/Service.tscn -- \
  --match-service --mm-bind=0.0.0.0 --mm-advertise=YOUR_SERVER_ADDRESS
```

Permit UDP 29200 and 29201 on that server. The current allocator launches the same
installed Godot executable and project; `--mm-worker-executable=...` can select an
administrator-configured worker executable. `--mm-port`, `--mm-race-port`,
`--mm-address` and `--mm-output` are operator/test overrides, not player-facing UI.
Default status/reservation/log files live under `user://matchmaking`.

Multiple simultaneous races would require a worker pool/allocator with distinct
ports or hosts, capacity tracking and routing each group to a free worker. A remote
worker would also replace this local reservation/status-file handoff with an
authenticated control API. The current single-slot service is implemented and
verified locally; no internet backend deployment was performed in this phase.

## Verification

Godot MCP manages one process, so rendered verification used it for client A,
the Godot executable for client B, and a separate headless service which launched
the race worker itself. Tests press actual menu buttons through input events;
the inherited 8b QA pilot supplies ordinary driving input after admission.
Customization test profiles are temporary and are never saved over player data.

Repeatable headless tests (use a fresh output directory each time):

```sh
python3 tools/phase_8c/verify_matchmaking.py --output artifacts/phase8c/new_race
python3 tools/phase_8c/verify_matchmaking.py --output artifacts/phase8c/new_retry --scenario cancel_retry
python3 tools/phase_8c/verify_matchmaking.py --output artifacts/phase8c/new_drop --scenario transition_drop
python3 tools/phase_8c/verify_matchmaking.py --output artifacts/phase8c/new_queue_drop --scenario queue_drop
python3 tools/phase_8c/verify_matchmaking.py --output artifacts/phase8c/new_service_failure --scenario service_failure
python3 tools/phase_8c/verify_matchmaking.py --output artifacts/phase8c/new_assignment_failure --scenario assignment_failure
python3 tools/phase_8c/verify_matchmaking.py --output artifacts/phase8c/new_worker_drop --scenario worker_drop
python3 tools/phase_8c/verify_matchmaking.py --output artifacts/phase8c/new_repeat --scenario repeat

godot --headless --debug --path . res://scenes/network/OfflineRegression.tscn -- --phase7-check
```

`--port` changes the test service port; the race uses the following port. The
failure cases deliberately use an unavailable worker executable, absent service,
closed queued/assigned connection, or terminate the newly assigned worker. They
assert a retryable UI state without engine/script errors or warnings.

The final rendered run assigned both clients match `b2a710b7067ce041`, track
`loop_01`, race port 29201. Both actual “matched” screenshots show **server tick
147**, countdown **3**, and **Skyline Loop**. Both searches had Cancel available
and no track/mode selection. All four racers then completed three laps at 75 ms
added latency in each direction, with matching official client/server states and
critical events. Every racer completed three glide landings. Final order:
CPU 1 **43.550 s**, CPU 2 **46.683 s**, Player 2 **48.433 s**, Player 1 **50.617 s**.

Passing runs include cancel-and-retry through a full race, queued disconnect,
assignment failure, service unavailable, assigned-worker loss, and assigned-player
dropout. In the dropout run the remaining player and three CPUs all finished
(42.050 / 44.033 / 47.417 / 49.600 s). The existing single-player, menu, HUD,
customization and audio regression passed all **74 checks**. The repeat-match test also passed: the same clients requeued before the first
worker retired, received a second server-selected session, and completed another
three-lap race. Both groups used the single worker slot without an operator restart
or stale-request loss. Final service, worker and client logs were clean. Early timer-formatting warnings are retained only in
failed development-run folders and were fixed before these passing runs.

Open `artifacts/phase8c/rendered/verification.html` for side-by-side, untouched
searching and matched-client viewport captures. Service decision logs, client
transition reports and per-match race logs/JSON sit alongside them. Verification
was on macOS with Godot 4.7.2; a real remote-machine/WAN and human input check remain
separate from this automated local multi-process validation.
