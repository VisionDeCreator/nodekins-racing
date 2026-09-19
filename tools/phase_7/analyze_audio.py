"""Inspect actual Godot mixer recordings and generated loop boundaries; no perceptual claims."""
import json,wave
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'artifacts/phase_7'
def read(path):
 with wave.open(str(path),'rb') as w:return np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').astype(float).reshape(-1,w.getnchannels())/32768,w.getframerate()
report={}
for name in ['full-flow-mix','mechanic-audition']:
 x,sr=read(OUT/(name+'.wav'))
 report[name]={'seconds':len(x)/sr,'sample_rate':sr,'peak_dbfs':float(20*np.log10(max(1e-9,np.max(np.abs(x))))),'rms_dbfs':float(20*np.log10(max(1e-9,np.sqrt(np.mean(x*x))))),'clipped_samples':int(np.sum(np.abs(x)>=.9999))}
 assert np.max(np.abs(x))>.01 and report[name]['clipped_samples']==0
loops={}
for name in ['menu_loop','race_loop','engine_loop','drift_loop']:
 x,sr=read(ROOT/'assets/audio'/f'{name}.wav');assert np.array_equal(x[0],x[-1]);x=x[:-1];edge=float(np.max(np.abs(x[0]-x[-1])));limit=float(np.quantile(np.abs(np.diff(x,axis=0)),.9999))
 loops[name]={'boundary_step':edge,'normal_step_99_99_percentile':limit,'has_boundary_spike':bool(edge>max(.001,limit*1.1))}
 assert not loops[name]['has_boundary_spike']
report['loops']=loops
# Trim a real race excerpt, with no remixing, for the human listen-through.
r=json.loads((OUT/'audio-report.json').read_text());cue=next(e for e in r['cues'] if e['cue']=='go')
x,sr=read(OUT/'full-flow-mix.wav');start=round(cue['recording_seconds']*sr);pcm=np.round(x[start:start+round(18*sr)]*32768).astype('<i2')
with wave.open(str(OUT/'race-excerpt.wav'),'wb') as w:w.setnchannels(x.shape[1]);w.setsampwidth(2);w.setframerate(sr);w.writeframes(pcm.tobytes())
(OUT/'pcm-report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
