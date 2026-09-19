# Nodekins Racing — placeholder audio

All 23 WAV files are original procedural synthesis created for this project by
`tools/phase_7/generate_audio.py`. No external music, recordings, sample packs or
third-party audio were used. **Every asset is a placeholder**, including the two
music tracks; none is considered final sound design or an approved final mix.

Source: the generator script (Python + NumPy, generation only). Runtime: native
Godot AudioStreamWAV and AudioStreamPlayer/AudioStreamPlayer3D, no plugins.
Re-running the script deterministically regenerates the WAVs and `manifest.json`.

The WAVs are 44.1 kHz, 16-bit PCM. Music is stereo; object SFX/loops are mono for
spatial playback. The four looping files use uncompressed PCM imports, loop begin
0 and exact period frame counts from the manifest. Each file appends a duplicated
first-frame guard for Godot 4.7.2 PCM boundary decoding; the guard is outside the
configured period. The manifest distinguishes period frames and file frames. Music is eight bars, with note/echo
release tails wrapped into the start of the loop. Engine and drift loops are
periodic synthesis. The manifest records duration, level and boundary measurements.

- Menu: 120 BPM, bright bell/pluck melody, soft bass and light percussion.
- Race: 144 BPM, faster plucks, bass, kick/snare and eighth-note hats.
- Engine: a harmonic motor buzz, pitch/volume controlled by the kart's telemetry.
- Drift: a textured scrape/drone plus a short rising tier chime.
- Other SFX: short synthesized tones, filtered noise and frequency sweeps.

Mix settings live in native Godot buses and the object-owned player scenes, not
in baked, permanently normalized mix exports. See `docs/phase_7.md` for triggers
and verification; generated in-engine recordings are in `artifacts/phase_7/`.
