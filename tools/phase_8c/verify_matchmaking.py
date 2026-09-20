#!/usr/bin/env python3
"""Exercise real menus, separate matchmaking ENet service and supervised race processes."""
import argparse
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser()
p.add_argument('--godot', default='/Applications/Godot.app/Contents/MacOS/Godot')
p.add_argument('--output', type=Path, required=True)
p.add_argument('--scenario', choices=['race','repeat','cancel','cancel_retry','queue_drop','transition_drop','assignment_failure','service_failure','worker_drop'], default='race')
p.add_argument('--port', type=int, default=29210)
p.add_argument('--check-only', action='store_true')
a=p.parse_args();a.output=a.output.resolve();a.output.mkdir(parents=True,exist_ok=True)

def read(path):
    return json.loads(path.read_text())

def service_report():
    f=a.output/'service.json'
    return read(f) if f.exists() else {'events':[]}

def assignment():
    groups=[e['data'] for e in service_report()['events'] if e['event']=='grouped']
    return groups[-1] if groups else {}

def validate():
    for path in a.output.rglob('*.log'):
        log=path.read_text(errors='replace')
        assert not any(s in log for s in ('ERROR:','WARNING:','SCRIPT ERROR:')), path
    qas={f.stem[3:]:read(f) for f in (a.output/'clients').glob('qa_*.json')}
    for tag,q in qas.items():
        assert not q['failures'],(tag,q['failures'])
    events=service_report()['events']
    if a.scenario in ('cancel','queue_drop'):
        assert service_report()['queue_size']==0
        assert any(e['event']==('canceled' if a.scenario=='cancel' else 'queue_disconnect') for e in events)
    elif a.scenario in ('assignment_failure','service_failure','worker_drop'):
        assert all(q['state']=='error' for q in qas.values()),qas
    else:
        participants=['A'] if a.scenario=='transition_drop' else ['A','B']
        group=assignment()
        assert group['candidate_count']==1 and group['humans']==2
        server=read(Path(group['directory'])/'server.json')
        assert server['race']['phase']==3
        assert all(row['completed_laps']==3 and row['finished'] for row in server['race']['rows'])
        official={e['serial']:e for e in server['events'] if e['kind'] in ('checkpoint','lap','finish','item','glide_launch','glide_end')}
        for tag in participants:
            qa=qas[tag];client=read(a.output/'clients'/f'client_{tag}.json')
            assert qa['searching'] and qa['matched']
            assert qa['assignment']['match']==group['match'] and qa['assignment']['track']==group['track']
            assert client['race']==server['race'] and client['race_mismatches']==0
            assert {e['serial']:e for e in client['events'] if e['serial'] in official}==official
            assert all(x['visual_match'] and x['rider_match'] for x in client['profiles'].values())
        if a.scenario=='transition_drop':
            assert qas['B']['state']=='error'
            assert len(server['profiles'])==4 and 'cpu_3' in server['profiles']
        if a.scenario=='repeat':
            assert len([e for e in events if e['event']=='grouped'])==2
            assert any(e['event']=='session_released' and not e['data']['reason'] for e in events)
            assert all(len(q['completed_rounds'])==1 for q in qas.values())
        if a.scenario=='cancel_retry':
            assert any(e['event']=='canceled' for e in events)
        print('Race:',[(r['id'],round(r['finish_time'],3)) for r in server['race']['rows']],flush=True)
    print('PASS',a.scenario,'— states:',{t:[x['state'] for x in q['transitions']] for t,q in qas.items()},flush=True)

if a.check_only:
    validate()
else:
    assert not (a.output/'service.json').exists(), 'Use a fresh output directory'
    processes=[];streams=[];killed=False
    base=[a.godot,'--headless','--debug','--path',str(ROOT)]
    common=[f'--mm-port={a.port}',f'--mm-race-port={a.port+1}',f'--mm-output={a.output}','--mm-verify','--mm-latency=75']
    try:
        if a.scenario!='service_failure':
            log=(a.output/'service.log').open('w');streams.append(log)
            extra=['--mm-worker-executable=/missing/nodekins/server'] if a.scenario=='assignment_failure' else []
            processes.append(subprocess.Popen(base+['res://scenes/matchmaking/Service.tscn','--','--match-service']+common+extra,stdout=log,stderr=subprocess.STDOUT))
            time.sleep(.8)
        tags=['A'] if a.scenario in ('cancel','queue_drop','service_failure') else ['A','B']
        for tag in tags:
            scenario=(a.scenario if (tag=='A' and a.scenario in ('cancel','cancel_retry','queue_drop','repeat')) or (tag=='B' and a.scenario in ('transition_drop','repeat')) else 'race')
            delay=5 if tag=='B' and a.scenario=='cancel_retry' else 0
            log=(a.output/f'client_{tag}.log').open('w');streams.append(log)
            processes.append(subprocess.Popen(base+['res://scenes/ui/Main.tscn','--']+common+[f'--mm-tag={tag}',f'--mm-scenario={scenario}',f'--mm-delay={delay}'],stdout=log,stderr=subprocess.STDOUT))
            time.sleep(.7)
        deadline=time.monotonic()+230
        while not all((a.output/'clients'/f'qa_{t}.json').exists() for t in tags):
            assert time.monotonic()<deadline,'Flow timed out'
            for f in a.output.rglob('*.log'):
                assert 'SCRIPT ERROR:' not in f.read_text(errors='replace'),f
            if a.scenario=='worker_drop' and not killed and any(e['event']=='assigned' for e in service_report()['events']):
                subprocess.run(['kill',str(assignment()['pid'])],check=True);killed=True
            time.sleep(.5)
        if a.scenario in ('cancel','queue_drop'):time.sleep(1)
        validate()
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate();process.wait(timeout=8)
        group=assignment()
        if group.get('pid',0)>0:
            subprocess.run(['kill',str(group['pid'])],capture_output=True)
        for stream in streams:stream.close()
