# Phase 7 — Audio

Audio now follows the entire menu/race/results flow. **All 23 assets are original,
self-generated placeholders; none is final.** No external audio or plugins were
used. Their source generator and provenance manifest are committed with the WAVs.
Human listening is still required to judge tone, repetition and relative levels.

## Event ownership and triggers

| Owner / source | Cue | Trigger and behavior |
| --- | --- | --- |
| Main / MenuAudio | Menu music | Continues across title, selection, customization and Options; stops when entering a race |
| Main / MenuAudio | Navigation | Short tick for focus/hover, rising pair for select, descending pair for Back; auto-focus after a screen transition is quiet |
| Track / RaceAudio | Race music | Starts with the countdown, loops through the race, pauses with the race and stops at results |
| Track / RaceAudio | Countdown | Three progressively higher beeps for 3–2–1; bright four-note GO cue |
| Every Kart / Audio | Engine | Continuous spatial motor loop; pitch rises from idle with normalized speed and throttle, falls with braking/coasting |
| Every Kart / Audio | Drift start / charge | Short tire scrape starts a looping textured tone. At 1 / 2 / 3 s the loop gets louder and higher, with a rising two-note tier confirmation |
| Every Kart / Audio | Boost | Existing boost_started signal plays a low descending whoosh, including mini-turbo release, Boost items and track pads |
| Every Kart / Audio | Glide | Launch plays a soft rising air/wing sweep; ended(reason=landed) plays a short touchdown thud; respawn/timeout do not falsely play landing |
| Every Kart / Audio | Impact | Wall/kart contact plays a short knock proportional to normal closing speed; floor contacts and gentle pushes are ignored |
| ItemBox / PickupAudio | Pickup | Quick ascending sparkle only after the box successfully awards an item |
| Kart inventory → Kart / Audio | Boost use | Ascending activation chirp, layered with the shared boost whoosh |
| Kart inventory → Kart / Audio | Shell use | Short descending pew at confirmed firing |
| Kart inventory → Kart / Audio | Banana use | Low dropping plop at confirmed deployment |
| Kart inventory → Kart / Audio | Item hit | Wobbling downward spin-out cue only when take_hit succeeds; immunity blocks the cue along with the hit |
| Track / RaceAudio | Lap | Player-only three-note chime after laps 1 and 2, slightly higher on the second; CPUs do not announce their laps |
| Main / MenuAudio | Result | First place gets an ascending victory flourish; other placements get a shorter neutral cadence. Menu music resumes when it finishes |

The final lap does not overlap a lap chime with the results jingle. Results follow
Phase 6's existing rule: the results screen appears after the entire field finishes.
The music and stinger use the actual player's result from the authoritative results
snapshot. No race state is copied into an audio manager.

### Integration boundary

`KartAudio.tscn`, `RaceAudio.tscn` and `MenuAudio.tscn` are children of their existing
Kart, Track and Main scenes. PickupAudio is a child of ItemBox. Sound players are
native AudioStreamPlayer or spatial AudioStreamPlayer3D nodes on those owners.
A plain resource field (`ItemDefinition.use_sound`) selects each item's cue, so a
new item does not require another item-ID branch in audio code.

Existing boost/glide/countdown/lap/result signals were reused. The following
read-only notifications were added at the existing state transitions:

- Kart: `motion_updated(speed, throttle, brake)` and `collision_impact(normal_speed)`.
- Drift: `drift_started`, `drift_ended`, `charge_tier_changed(tier)`.
- Inventory: `item_used(item)`, `item_hit(item)` after confirmed effects.
- ItemBox: `picked_up` after a confirmed award.

Movement, drift, item and race calculations are unchanged. Contact notification
reads the existing slide contacts and relative velocity after move_and_slide; it
never changes motion. The only continuous feed is the kart's emitted motion sample,
needed for smoothly changing engine tone. Audio components do not poll gameplay in
_process or _physics_process. Drift/boost/glide/item cues are discrete signal hooks.
Impact threshold (2.5 units/s) and debounce (0.28 s) are exported audio values.

All racers use the same kart audio component. SFX attenuate with distance (6 m unit
size, 40–45 m maximum distance), and nearby sounds are capped at 0 dB spatial gain.
No audio node writes to controls, stats, race position or customization data.

## Mix and Options

`default_bus_layout.tres` defines **Music**, **SFX**, **Engine**, each routed to Master.
Master has a -1 dB ceiling limiter for coincident cues. The Options placeholder is
now a usable three-slider mixer, supporting mouse, keyboard and gamepad. Zero mutes
that bus. Changes affect playback immediately and persist to `user://audio.cfg`.
The defaults are 70% Music, 90% SFX, 70% Engine. Volume preferences are separate from
the thirteen-byte customization profile.

`AudioPreferences` is a settings-only autoload: bus levels, mute and config saving.
It never creates players or dispatches gameplay sounds. Saving is debounced during
dragging and flushed on exit. Scene pause suspends race-owned audio while menu/back
feedback remains active. Leaving a race frees its audio players with the track.

Quit and the window close request stop players, save volumes and allow 150 ms for
AudioServer to release stopped playback before exiting. This avoids a reproduced
Godot 4.7.2 shutdown warning about an active looping WAV. Music also explicitly
releases its stream during scene teardown. No navigation destination changed.

## Assets and loop construction

`tools/phase_7/generate_audio.py` deterministically synthesizes all files using
NumPy. This dependency is only for generation; the game uses native Godot playback.
WAVs are 44.1 kHz, 16-bit PCM: stereo music and mono object sounds. Four imported
loops use exact period boundaries and PCM compression disabled:

- `menu_loop.wav`: eight bars at 120 BPM, 16 seconds.
- `race_loop.wav`: eight bars at 144 BPM, 13⅓ seconds.
- `engine_loop.wav`: 2 seconds, harmonic motor pulse.
- `drift_loop.wav`: 1 second, periodic textured charge bed.

Music release/echo tails wrap into the first bar; engine/drift oscillators use
integral cycles. The WAV importer uses `edit/loop_mode=2` for Forward (the runtime
AudioStreamWAV enum is 1); see the [official importer source](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/editor/import/resource_importer_wav.cpp).
Each looping WAV has one extra frame duplicating its first frame, with loop_end set
to the original period length. This guards the boundary decoded by the
[Godot 4.7.2 PCM mixer](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/scene/resources/audio_stream_wav.cpp),
so the wrap reads the next periodic sample. The manifest distinguishes period
frames from file frames; tests validate both the loop region and the guard frame. `assets/audio/manifest.json` records every asset's source, length,
peak, RMS and loop status. `assets/audio/README.md` flags all assets as placeholders.
Loop-boundary measurements can catch clicks/gaps but do not replace human listening.

## Verification and recordings

`AudioVerification.tscn` uses real keyboard/gamepad/mouse events: Title → Options
(volume changes and disk reload) → Driver → Track → Countdown → paused/resumed race
→ three laps → Results → Title. The player uses the existing QA KartAI pilot; normal
play remains under human control. Cue signals log the emitting node, race time, bus,
pitch and actual playing state. Confirmed item-use events are compared against cue
counts, rather than just calling sound methods and assuming they work.

The test also runs a separate physical lab for a continuous three-tier drift,
release, a wall impact and a kart-to-kart impact. The victory branch is auditioned
explicitly there; the full race's actual player placement is third, so its real
results screen plays the neutral jingle. Lab events are labeled separately in the
report and are not presented as a first-place race result.

Godot AudioEffectRecord on Master captures actual mixed PCM:

- `artifacts/phase_7/full-flow-mix.wav`: title through real race results.
- `artifacts/phase_7/mechanic-audition.wav`: physical drift tiers, release, impacts and victory branch.
- `artifacts/phase_7/race-excerpt.wav`: an unremixed 18-second excerpt for a quick listen.
- `artifacts/phase_7/audio-report.json`: cue timings, mixer values, checks and results.
- `artifacts/phase_7/pcm-report.json`: measured levels, clipping and boundary checks.

`analyze_audio.py` checks non-silent recordings, digital clipping and loop-boundary
sample steps, and extracts the short race excerpt. Verification uses an isolated
volume config under artifacts, preserving the user's normal mix preferences.

```sh
godot --headless --editor --path . --import --quit
godot --headless --path . res://scenes/test/AudioVerification.tscn -- --phase7-check
godot --headless --path . res://scenes/test/AudioShutdownVerification.tscn
```

Run AudioVerification without `--headless` to record the actual mixer output.
Do not use `--fixed-fps` to speed up this test: the audio mixer runs on its own clock.
The shutdown smoke test exercises the normal audio-aware Quit path.

### Recorded results

Final rendered Godot MCP run: **78 checks passed**, no errors or warnings. All four
racers completed three laps: 24 ordered checkpoints and three glide landings each,
with no recoveries. Seed 445 reproduced the previous gameplay baseline exactly:
CPU 2 42.867 s, CPU 3 47.217 s, Player 49.817 s, CPU 1 50.017 s. HUD values matched
RaceManager/inventory through 6,321 rendered frames.

The real race produced 35 pickup cues; exactly 11 Boost, 9 Shell and 13 Banana use
cues matched successful inventory actions. There were 13 confirmed spin-out cues,
12 deployments and 12 landings. All four engine sources ranged from 0.78× to
2.052× pitch with speed/throttle. Every drift tier occurred naturally in the race.
The separate physical lab also confirmed wall and kart contact, sustained-push
suppression and the first-place stinger branch.

Concrete player moments (race-clock seconds):

| Time | Observed playback |
| --- | --- |
| 2.117 / 3.383 | Glide deployment sweep / touchdown thud |
| 4.783 | Banana plop on confirmed drop |
| 5.133 / 6.133 / 7.133 | Tier 1 / 2 / 3 drift confirmations, progressively higher/louder charge loop |
| 7.167 | Release stops charge loop and plays turbo whoosh |
| 8.600 | Item hit plays wobbling spin-out cue |
| 17.100 / 31.233 | Player's lap-complete chimes |
| 31.317 | Boost activation chirp plus shared acceleration whoosh |
| 40.850 | Shell firing pew |
| 50.017 | Neutral results cadence for actual third-place player; race music stops |

The actual mixer recording is 58.037 s at 48 kHz stereo, peak -1.00 dBFS, RMS
-20.43 dBFS, with **zero digitally clipped samples**. The physical audition is
11.36 s, peak -10.99 dBFS, also without clipping. These are signal measurements,
not a subjective listening verdict. The committed assets remain placeholders.

The test caught and fixed an initial WAV import-mode mismatch; the final run checks
both actual imported loop regions and playback across a loop boundary. The final
import log, MCP log and audio-aware shutdown smoke test contain no warnings/errors.

Final headless regression: **74 checks passed with exit code 0**, no warnings or
errors, including continuous engine playback while moving for all four karts and
the audio-aware shutdown path. `headless-report.json` records each engine
`stopped_while_moving=false`. The rendered report remains `audio-report.json`.
