#!/usr/bin/env python3
"""Real dedicated race plus two input-generating clients; no client teleports or lap injection."""
import argparse
import json
import pathlib
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser()
p.add_argument('--godot', default='/Applications/Godot.app/Contents/MacOS/Godot')
p.add_argument('--output', type=pathlib.Path, default=ROOT/'artifacts/phase8b/headless')
p.add_argument('--port', type=int, default=29189)
p.add_argument('--latency', type=int, default=75)
p.add_argument('--loss', type=float, default=0)
p.add_argument('--jitter', type=float, default=0)
p.add_argument('--check-only', action='store_true')
p.add_argument('--disconnect', action='store_true')
a = p.parse_args()
a.output = a.output.resolve()
a.output.mkdir(parents=True, exist_ok=True)


def read(role):
    return json.loads((a.output/f'{role}.json').read_text())


def validate():
    for path in [a.output/f'{role}.log' for role in ('server','client_A','client_B')]:
        data = path.read_text()
        assert not any(s in data for s in ('ERROR:', 'WARNING:', 'SCRIPT ERROR:')), path
    server = read('server')
    assert server['headless']
    assert server['rejected_inputs'] == 0
    assert server['maximum_snapshot_payload'] <= 900
    assert server['race']['phase'] == 3, server['race']
    assert all(r['finished'] and r['completed_laps'] == 3 for r in server['race']['rows'])
    if a.disconnect:
        assert len(server['race']['rows']) == 3
        assert any(e['kind'] == 'disconnect' for e in server['events'])
        assert read('client_A')['race'] == server['race']
        assert read('client_A')['race_mismatches'] == 0
        print('PASS: disconnected racer removed; remaining human + two server CPUs finish.', flush=True)
        return
    assert len(server['race']['rows']) == 4
    assert len(server['profiles']) == 4
    critical = {e['serial']:e for e in server['events'] if e['kind'] in ('checkpoint','lap','finish','race_end','recovery','item','glide_launch','glide_end')}
    assert sum(e['kind'] == 'lap' for e in critical.values()) == 12
    for tag in ('A','B'):
        client = read('client_'+tag)
        assert client['race_mismatches'] == 0
        assert client['snapshots'] > 200
        assert client['race'] == server['race'], (tag, client['race'], server['race'])
        assert len(client['profiles']) == 4
        assert all(v['visual_match'] and v['rider_match'] for v in client['profiles'].values())
        assert {k:v['wire'] for k,v in client['profiles'].items()} == server['profiles']
        seen = {e['serial']:e for e in client['events']}
        assert all(seen.get(i) == event for i,event in critical.items()), (tag, 'Missing authoritative events')
        assert client['max_pending'] < 120
        owned = next(v for v in client['presentation'].values() if v['max_correction_rate'] > 0)
        assert owned['max_rebase_jump'] < .001, owned
        assert owned['max_correction_rate'] < 8.02, owned
        print(tag, 'RTT',client['rtt_median'],'ms; p95 prediction disagreement',round(client['prediction_error_p95'],3),'m; max pending',client['max_pending'],flush=True)
    item_events = [e['data'] for e in server['events'] if e['kind'] == 'item']
    for kind in ('boost','shell','banana'):
        assert any(e['kind'] == 'use' and e['item'] == kind for e in item_events), kind
    assert any(e['kind'] == 'hit' for e in item_events)
    assert any(m['kind'] == 'hit' and m['suppression'] > 0 and m['speed_after'] < m['speed_before'] for m in server['measured_effects'])
    assert any(m['kind'] == 'boost' and m['boost_remaining'] > 0 and m['speed_after'] > m['speed_before'] + 1 for m in server['measured_effects'])
    assert all(server['glide_landings'].get(r['id'],0) >= 3 for r in server['race']['rows']), server['glide_landings']
    moments = [read('client_'+tag+'_moment') for tag in ('A','B')]
    assert moments[0]['tick'] == moments[1]['tick']
    assert moments[0]['race'] == moments[1]['race']
    assert moments[0]['items'] == moments[1]['items']
    print('PASS: complete authoritative 3-lap race; matching standings/events/items/profile IDs; glide on every kart; shared evidence tick.',flush=True)
    print('Results:', [(r['id'],r['finish_order'],round(r['finish_time'],3)) for r in server['race']['rows']],flush=True)


if not a.check_only:
    assert not any((a.output/f'{r}.json').exists() for r in ('server','client_A','client_B')), 'Use a fresh output directory to avoid stale results'
    processes=[]
    streams=[]
    common=[a.godot,'--headless','--debug','--path',str(ROOT)]
    flags=['--verify',f'--port={a.port}',f'--latency={a.latency}',f'--loss={a.loss}',f'--jitter={a.jitter}',f'--output={a.output}','--quit-after=170']
    try:
        for role,scene,extra in (
            ('server','DedicatedRace',[]),
            ('client_A','OnlineClient',['--tag=A']),
            ('client_B','OnlineClient',['--tag=B']+(['--disconnect-at=10'] if a.disconnect else [])),
        ):
            stream=(a.output/f'{role}.log').open('w'); streams.append(stream)
            processes.append(subprocess.Popen(common+[f'res://scenes/network/{scene}.tscn','--']+flags+extra,stdout=stream,stderr=subprocess.STDOUT))
            time.sleep(.8)
        deadline=time.monotonic()+180
        while not all((a.output/f'{r}.json').exists() for r in ('server','client_A','client_B')):
            assert time.monotonic()<deadline,'Race did not finish; inspect logs'
            for process in processes:
                assert process.poll() in (None,0), f'Process exit {process.returncode}'
            for path in a.output.glob('*.log'):
                assert 'SCRIPT ERROR:' not in path.read_text(), f'Script failure: {path}'
            time.sleep(1)
        validate()
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=8)
        for stream in streams: stream.close()
else:
    validate()
