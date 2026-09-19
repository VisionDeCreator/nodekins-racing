"""Original synthesized placeholder audio. No samples, recordings, external music or downloads."""
from pathlib import Path
import math, wave, json
import numpy as np
ROOT=Path(__file__).resolve().parents[2]; OUT=ROOT/'assets/audio'; SR=44100
rng=np.random.default_rng(7001); manifest={}
def hz(m):return 440*2**((m-69)/12)
def save(name,x,loop=False):
    x=np.asarray(x,dtype=float);x-=x.mean(axis=0)
    peak=np.max(np.abs(x));x=x/max(1,peak/.79)
    pcm=np.round(x*32767).astype('<i2')
    # Godot 4.7 PCM mixer may decode loop_end itself: guard it with the first frame.
    if loop:pcm=np.concatenate([pcm,pcm[:1]],axis=0)
    with wave.open(str(OUT/(name+'.wav')),'wb') as w:
        w.setnchannels(1 if x.ndim==1 else 2);w.setsampwidth(2);w.setframerate(SR);w.writeframes(pcm.tobytes())
    manifest[name]={'file':name+'.wav','frames':len(x),'file_frames':len(pcm),'seconds':len(x)/SR,'loop':loop,'channels':1 if x.ndim==1 else 2,'peak':float(np.max(np.abs(x))),'rms':float(np.sqrt(np.mean(x*x))),'boundary_step':float(np.max(np.abs(x[0]-x[-1]))),'status':'original synthesized placeholder'}
def note(m,d,kind='bell'):
    t=np.arange(round(d*SR))/SR;f=hz(m)
    if kind=='bass':y=np.sin(2*np.pi*f*t)+.22*np.sin(4*np.pi*f*t);decay=3
    elif kind=='pluck':y=sum(np.sin(2*np.pi*f*k*t)/(k*k) for k in range(1,7));decay=8
    else:y=np.sin(2*np.pi*f*t)+.35*np.sin(2*np.pi*f*2*t)*np.exp(-t*12)+.10*np.sin(2*np.pi*f*3*t);decay=5
    env=(1-np.exp(-t*180))*np.exp(-t*decay)*np.minimum(1,(d-t)/.015)
    return y*env

def sequence(notes,step=.085,duration=.2):
    y=np.zeros(round((step*(len(notes)-1)+duration)*SR))
    for i,m in enumerate(notes):
        a=note(m,duration);j=round(i*step*SR);y[j:j+len(a)]+=a*.48
    return y
for name,ns,step,d in [('ui_move',[81],.05,.08),('ui_select',[72,79],.06,.17),('ui_back',[74,67],.06,.15),('countdown',[72],.05,.22),('go',[72,76,79,84],.035,.4),('lap',[76,79,84],.09,.36),('pickup',[79,84,88],.045,.23),('boost_use',[60,72,84],.055,.25),('victory',[60,64,67,72,76,79,84],.18,1.0),('results',[67,71,74,72],.18,.85),('drift_tier',[79,84],.06,.28)]:save(name,sequence(ns,step,d))
for name,d,high,low in [('boost',.8,350,70),('glide_deploy',.65,180,420),('glide_land',.28,105,40),('impact',.22,130,42),('shell_fire',.28,700,160),('banana_drop',.24,310,75),('spinout',.75,500,85),('drift_start',.18,500,180)]:
    t=np.arange(round(d*SR))/SR;phase=2*np.pi*(high*t+(low-high)*t*t/(2*d));noise=rng.normal(0,.22,len(t));noise=np.convolve(noise,np.ones(5)/5,'same')
    env=np.sin(np.pi*np.minimum(1,t/.012)/2)*np.exp(-t*(4/d))*np.minimum(1,(d-t)/.02)
    y=(np.sin(phase)*.5+noise*(2 if name in ['boost','drift_start','glide_deploy','impact'] else .5))*env
    if name=='spinout':y*=.6+.4*np.cos(2*np.pi*12*t)
    save(name,y)
# Integral cycles at both ends guarantee continuous engine/charge loops.
t=np.arange(SR*2)/SR
engine=sum(np.sin(2*np.pi*70*k*t+.15*np.sin(2*np.pi*4*t))/(k**1.35) for k in range(1,9))
engine*=.48*(.86+.14*np.cos(2*np.pi*35*t));save('engine_loop',engine,True)
t=np.arange(SR)/SR
charge=sum(np.sin(2*np.pi*f*t+float(rng.uniform(0,6.28)))*.018 for f in range(430,2100,31))
charge+=.12*np.sin(2*np.pi*330*t);charge*=.78+.22*np.cos(2*np.pi*8*t);save('drift_loop',charge,True)

def music(name,bpm,race=False):
    beat=60/bpm;N=round(32*beat*SR);mix=np.zeros((N,2))
    def add(a,when,gain,pan=0):
        ids=(np.arange(len(a))+round(when*SR))%N
        np.add.at(mix[:,0],ids,a*gain*math.sqrt((1-pan)/2));np.add.at(mix[:,1],ids,a*gain*math.sqrt((1+pan)/2))
    roots=[48,53,57,55,48,53,50,55]; melody=[[72,76,79,76],[74,77,81,79],[76,81,84,81],[74,79,83,79],[79,76,72,74],[77,81,84,81],[74,77,81,77],[79,83,86,79]]
    for bar,root in enumerate(roots):
        for b in range(4):
            time=(bar*4+b)*beat
            add(note(root if b%2==0 else root+7,beat*.85,'bass'),time,.3)
            n=melody[bar][b];a=note(n,.42 if race else .58,'pluck' if race else 'bell');add(a,time+(.5*beat if b%2 else 0),.30,-.22 if b%2 else .22)
            add(a,time+beat*.75,.06,.55) # circular echo includes tail from last bar in first bar
            if race:
                add(note(root+24+[0,4,7,4][b],.18,'pluck'),time+beat*.5,.14,-.5)
            t=np.arange(round(.16*SR))/SR
            kick=np.sin(2*np.pi*(43*t+70*.025*(1-np.exp(-t/.025))))*np.exp(-t*26)*(1-np.exp(-t*600))
            if race or b%2==0:add(kick,time,.4 if race else .24)
            if b%2:
                snare=rng.normal(0,.45,len(t))*np.exp(-t*33)*(1-np.exp(-t*700));add(snare,time,.19 if race else .09)
            for off in [0,.5]:
                t=np.arange(round(.07*SR))/SR;hat=rng.normal(0,.15,len(t))*np.exp(-t*65)*np.minimum(1,t/.003)
                add(hat,time+off*beat,.22 if race else .13,.4)
        for interval in [0,4 if bar not in [2,6] else 3,7]:
            add(note(root+12+interval,beat*3.6,'bell'),bar*4*beat,.095,-.35)
    # Release tails and echoes wrap circularly into the beginning of the musical period.
    save(name,mix,True)
music('menu_loop',120);music('race_loop',144,True)
(OUT/'manifest.json').write_text(json.dumps({'sample_rate':SR,'authorship':'Original procedural synthesis for Nodekins Racing; no third-party samples. All sounds are placeholders pending human listening and mix approval.','assets':manifest},indent=2)+'\n')
print(json.dumps({'assets':len(manifest),'seconds':sum(v['seconds'] for v in manifest.values()),'loops':{k:v['boundary_step'] for k,v in manifest.items() if v['loop']}}))
