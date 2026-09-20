#!/usr/bin/env python3
"""Three independent processes; fixed input benchmark, no production project dependencies."""
import argparse
import json
import math
import pathlib
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
PROJECT = ROOT / 'prototypes/networking'
parser = argparse.ArgumentParser()
parser.add_argument('--godot', default='/Applications/Godot.app/Contents/MacOS/Godot')
parser.add_argument('--port', type=int, default=29089)
parser.add_argument('--output', type=pathlib.Path, default=ROOT / 'artifacts/phase8a/headless')
parser.add_argument('--check-only', action='store_true')
args = parser.parse_args()
args.output = args.output.resolve()
args.output.mkdir(parents=True, exist_ok=True)


def check():
    reports = {tag: json.loads((args.output / f'{tag}.json').read_text())
               for tag in ('server', 'client_A', 'client_B')}
    for path in args.output.glob('*.log'):
        contents = path.read_text()
        assert not any(term in contents for term in ('ERROR:', 'WARNING:', 'SCRIPT ERROR:')), path
    assert reports['server']['headless']
    authoritative_rows = reports['server']['server_states']
    if len(authoritative_rows) != 2:
        # Clients can close before the server's final report. Compare against its
        # actual full-grid completion event, not its correctly empty post-disconnect roster.
        for line in (args.output / 'server.log').read_text().splitlines():
            if line.startswith('NETLAB '):
                event = json.loads(line[7:])
                if event['event'] == 'benchmark_drive_complete':
                    authoritative_rows = event['data']['states']
    assert len(authoritative_rows) == 2
    assert all(row['state']['speed'] == 0 for row in authoritative_rows)
    assert reports['server']['rejected_inputs'] == 0
    assert all(row['boundary_hits'] == 0 for row in authoritative_rows)
    for tag in ('client_A', 'client_B'):
        report = reports[tag]
        assert len(report['phases']) == 4, tag
        assert len(report['rendered']) == 2, tag
        assert report['max_visible_rebase_jump_m'] < .001, tag
        assert report['max_visual_correction_rate_mps'] < 4.01, tag
        for phase in report['phases']:
            assert phase['ack_error_p95_m'] < .05, (tag, phase)
            assert 1.9 < phase['max_replay_correction'] < 2.1, (tag, phase)
            assert 0 < phase['fault_settle_seconds'] < 2, (tag, phase)
            assert phase['max_pending'] < 120, (tag, phase)
            delay = phase['one_way_ms']
            assert max(0, delay * 2 - 40) <= phase['rtt_median_ms'] < delay * 2 + 120, (tag, phase)
        for rendered in report['rendered']:
            authoritative = next(row['state'] for row in authoritative_rows
                                 if row['slot'] == rendered['slot'])
            distance = math.hypot(rendered['x']-authoritative['x'], rendered['z']-authoritative['z'])
            assert distance < .03, (tag, rendered, authoritative, distance)
            yaw_delta = rendered['yaw']-authoritative['yaw']
            assert abs(math.atan2(math.sin(yaw_delta), math.cos(yaw_delta))) < .001
    print('PASS: independent headless authority; both clients replay, smoothly correct 2m faults, and settle to server positions.', flush=True)
    for tag in ('client_A', 'client_B'):
        for phase in reports[tag]['phases']:
            print(tag, phase['stage'], 'RTT', phase['rtt_median_ms'], 'ms;',
                  'p95 error', round(phase['ack_error_p95_m'], 6), 'm;',
                  'fault settle', round(phase['fault_settle_seconds'], 3), 's', flush=True)


if not args.check_only:
    # Populate Godot's script-class cache on a fresh checkout before running scenes.
    with (args.output / 'import.log').open('w') as import_log:
        subprocess.run([args.godot, '--headless', '--editor', '--path', str(PROJECT),
                        '--import', '--quit'], stdout=import_log, stderr=subprocess.STDOUT,
                       check=True, timeout=45)
    processes = []
    logs = []
    common = [args.godot, '--headless', '--debug', '--path', str(PROJECT)]
    user = ['--benchmark', f'--port={args.port}', f'--output={args.output}']
    try:
        for tag, scene, options in (
            ('server', 'res://scenes/DedicatedServer.tscn', ['--quit-after=66']),
            ('client_A', 'res://scenes/NetworkLab.tscn', ['--tag=A', '--quit-after=59']),
            ('client_B', 'res://scenes/NetworkLab.tscn', ['--tag=B', '--quit-after=59']),
        ):
            stream = (args.output / f'{tag}.log').open('w')
            logs.append(stream)
            processes.append(subprocess.Popen(common+[scene, '--']+user+options, stdout=stream, stderr=subprocess.STDOUT))
            time.sleep(.5)
        deadline = time.monotonic()+75
        while any(process.poll() is None for process in processes):
            assert time.monotonic() < deadline, 'Processes did not finish'
            for process in processes:
                assert process.poll() in (None, 0), f'Godot exited {process.returncode}; inspect logs'
            time.sleep(.5)
        print('All three processes exited cleanly.', flush=True)
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
        for stream in logs:
            stream.close()
check()
