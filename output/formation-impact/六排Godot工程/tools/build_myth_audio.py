"""Rebuild myth skill cues from the project's credited CC0 foley and original synthesis.
Requires numpy; no network, voice model, or proprietary audio library.
"""
from pathlib import Path
import hashlib, json, wave
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/myth_audio'
OUT.mkdir(exist_ok=True)
SR=24000
rng=np.random.default_rng(1411)
used={}

def band(x, lo=0, hi=10000):
    f=np.fft.rfftfreq(len(x),1/SR)
    gain=1/(1+(f/max(hi,1))**8)
    if lo: gain*=1-1/(1+(f/lo)**6)
    return np.fft.irfft(np.fft.rfft(x)*gain,n=len(x))

def source(path, speed=1., duration=None, start=0.):
    file=ROOT/'assets'/path
    used[path]=hashlib.sha256(file.read_bytes()).hexdigest()
    with wave.open(str(file),'rb') as w:
        assert w.getsampwidth()==2
        rate=w.getframerate()
        x=np.frombuffer(w.readframes(w.getnframes()),'<i2').astype(float).reshape(-1,w.getnchannels()).mean(axis=1)/32768
    x=np.interp(np.arange(0,len(x),rate/SR*speed),np.arange(len(x)),x)
    x=x[int(start*SR):int((start+duration)*SR) if duration else None].copy()
    return x

def fade(x, attack=.008, release=.07):
    x=x.copy()
    a=min(int(attack*SR),len(x)//2); b=min(int(release*SR),len(x)//2)
    if a:x[:a]*=np.linspace(0,1,a)
    if b:x[-b:]*=np.linspace(1,0,b)
    return x

def air(seconds, lo=140, hi=4000, swell=False):
    t=np.linspace(0,1,int(seconds*SR),endpoint=False)
    env=np.sin(np.pi*t)**(1.2 if swell else .45) if swell else (1-t)**2
    return fade(band(rng.normal(0,1,len(t)),lo,hi)*env,.015,.1)

def bell(seconds, freq, bright=.45):
    t=np.arange(int(seconds*SR))/SR
    out=np.zeros(len(t))
    for ratio,gain in [(1,1),(2.76,bright),(4.1,bright*.3)]:
        out+=gain*np.sin(2*np.pi*freq*ratio*t)*np.exp(-t*(4+ratio))
    return fade(out,.008,.12)

def body(seconds=.42,freq=76):
    t=np.arange(int(seconds*SR))/SR
    return fade(np.sin(2*np.pi*(freq*t-18*t*t))*np.exp(-t*9),.004,.1)

def mix(seconds,*layers):
    out=np.zeros(int(seconds*SR))
    for sample,at,gain in layers:
        start=int(at*SR); count=min(len(sample),len(out)-start)
        if count>0:out[start:start+count]+=sample[:count]*gain
    return fade(out,.005,min(.18,seconds/4))

def bubbles():
    result=np.zeros(int(1.05*SR))
    for i in range(12):
        seconds=rng.uniform(.045,.11);t=np.arange(int(seconds*SR))/SR
        freq=rng.uniform(220,700)
        bubble=np.sin(2*np.pi*(freq*t-freq*.5/seconds*t*t))*np.exp(-t*35)
        start=int((i*.055+rng.uniform(0,.025))*SR)
        result[start:start+len(t)]+=fade(bubble,.003,.02)*.2
    return result

sea=source('selected_audio/sea.wav',duration=2.1,start=3.1)
fire=source('selected_audio/fire.wav',duration=1.5)
steel=source('selected_audio/shield-0.wav')
equip=source('selected_audio/equip-0.wav')
bow=source('combat_audio/arrow0.wav')
wood=source('break0.wav')
thud=source('impact0.wav')
stone=source('combat_audio/earthquake.wav',duration=1.1)
grunts=source('kill0.wav',speed=.8)
swish=source('swing0.wav',speed=.7)
cloth=source('selected_audio/equip-1.wav')
thunder=source('tactical_thunder.wav')
slow_wood=source('break0.wav',speed=.7)
low_steel=source('selected_audio/shield-1.wav',speed=.75)

cues={
'zeus':(
 mix(.26,(air(.22,1800,9000),0,.3),(bell(.2,700),0,.06)),
 mix(1.65,(thunder,0,1),(air(.15,1000,8000),0,.14))),
'poseidon':(
 mix(.85,(sea,0,1.0),(air(.8,120,2400,True),0,.22)),
 mix(1.7,(sea,0,1.8),(air(1.3,80,3400),0,.3),(body(.45,60),0,.05))),
'athena':(
 mix(.42,(fade(steel[::-1],.08,.03),0,.6),(bell(.4,440),0,.05)),
 mix(1.0,(steel,0,.8),(bell(.9,740),.012,.09),(bell(.7,1100),.045,.04))),
'artemis':(
 mix(.32,(equip,0,.6),(air(.25,600,3400,True),0,.05)),
 mix(.62,(bow,0,.8),(bow,.04,.4),(bow,.085,.2),(swish,.02,.15))),
'hephaestus':(
 mix(.45,(equip,0,.8),(swish,.15,.4),(low_steel,0,.15)),
 mix(1.5,(low_steel,0,.7),(fire,.03,1),(air(.7,90,3000),0,.3),(body(),0,.2))),
'demeter':(
 mix(.45,(fade(slow_wood[::-1],.05,.04),0,.5),(cloth,0,.5)),
 mix(.95,(wood,0,.8),(slow_wood,.1,.5),(wood,.28,.3),(air(.7,400,2000),0,.035))),
'achilles':(
 mix(.35,(swish,0,.7),(equip,.02,.35),(air(.28,220,4500,True),0,.12)),
 mix(.6,(source('combat_audio/impact1.wav'),0,.7),(bow,.015,.3),(body(.25,110),0,.08))),
'odysseus':(
 mix(.52,(air(.5,250,2200,True),0,.16),(fade(cloth[::-1],.08,.06),0,.45)),
 mix(1.15,(air(1.,250,3000),0,.1),(bell(.8,330),0,.05),(steel,.09,.12),(steel,.22,.08),(steel,.38,.04))),
'heracles':(
 mix(.48,(slow_wood,0,.3),(air(.44,90,2200,True),0,.18),(grunts,.08,.3)),
 mix(1.15,(thud,0,.8),(slow_wood,.01,.7),(band(stone,30,850),.05,.35),(body(.5,62),0,.16))),
'minotaur':(
 mix(.62,(grunts,0,.65),(thud,.13,.15),(thud,.29,.2),(air(.55,90,1600,True),0,.12)),
 mix(1.2,(thud,0,.85),(stone,.02,.4),(wood,.025,.25),(body(.45,56),0,.14))),
'medusa':(
 mix(.5,(air(.48,1400,6000,True),0,.2),(band(fire,1600,7000),0,.3)),
 mix(1.05,(band(stone,350,4000),0,.65),(wood,.02,.3),(band(low_steel,500,2500),.06,.15),(air(.7,1200,4500),0,.08))),
'cyclops':(
 mix(.5,(band(stone,180,2200),0,.45),(grunts,.02,.25),(air(.4,160,1600,True),0,.1)),
 mix(1.3,(stone,0,.7),(thud,0,.6),(wood,.05,.35),(wood,.18,.2),(body(.5,53),0,.15))),
'hydra':(
 mix(.5,(air(.45,500,4200,True),0,.16),(sea,0,.7),(bubbles(),0,.25)),
 mix(1.45,(sea,0,.7),(bubbles(),0,.6),(air(.65,450,2700),0,.1),(bell(.8,310),.4,.035))),
'harpy':(
 mix(.56,(cloth,0,.55),(cloth,.12,.45),(cloth,.24,.3),(air(.5,400,4800,True),0,.12)),
 mix(.85,(air(.45,220,4800),0,.16),(swish,0,.6),(thud,.03,.35),(cloth,.1,.4)))
}
files=[]
for name,(cast,impact) in cues.items():
    for stage,x in [('cast',cast),('impact',impact)]:
        x-=np.mean(x)
        x=fade(x,.005,.08)
        rms=np.sqrt(np.mean(x*x)); peak=np.max(np.abs(x))
        x*=min(.12/max(rms,1e-6),.58/max(peak,1e-6))
        path=OUT/f'{name}-{stage}.wav'
        pcm=np.round(x*32767).astype('<i2')
        with wave.open(str(path),'wb') as w:
            w.setnchannels(1);w.setsampwidth(2);w.setframerate(SR);w.writeframes(pcm.tobytes())
        files.append(dict(file=path.name,duration=len(x)/SR,peak=float(np.max(np.abs(x))),rms=float(np.sqrt(np.mean(x*x))),sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
manifest={'date':'2026-11-01','method':'Deterministic edits of existing CC0 foley plus original noise/resonant synthesis; no generated voices.','sample_rate':SR,'format':'mono PCM16','seed':1411,'sources':used,'files':files,'credit_files':['../AUDIO-CREDITS.txt','../selected_audio/CREDITS.txt','../combat_audio/CREDITS.txt']}
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(OUT/'CREDITS.txt').write_text('''Myth skill audio — 2026-11-01
28 short cast/impact cues, derived from the project's existing CC0 recordings, plus original procedural noise, resonances and bubbles. No third-party voice model or new recording download.
See ../AUDIO-CREDITS.txt, ../selected_audio/CREDITS.txt and ../combat_audio/CREDITS.txt for full source URLs and attribution.
Contributors used: Ben Jaszczak & Brian Nelson (metal); Vehicle (equipment/cloth); artisticdude (bow/swish); Kenney (wood/body impacts); HaelDB (vocal effort); StarNinjas (weapon clashes); mieki256 (stone); jasinski / qubodup (sea); AntumDeluge (fire).
CC0 1.0 https://creativecommons.org/publicdomain/zero/1.0/
Original synthesis: thunder, band-limited air, short resonances and bubbles.
Poseidon uses sea/water layers only, not the earthquake recording.
Edits: mono downmix, pitch/tempo edits, spectral filtering, short layered foley, deterministic envelopes, DC removal, level matching and fades. File/source hashes are in manifest.json.
Rebuild: tools/build_myth_audio.py (numpy).
''')
config={'voice_limit':6,'per_character_limit':2,'min_gap':.12,'mix_gain':.6,'characters':{}}
for name in cues:
    config['characters'][name]={'cast':{'file':f'res://assets/myth_audio/{name}-cast.wav','gain':.65},'impact':{'file':f'res://assets/myth_audio/{name}-impact.wav','gain':1.0}}
config['characters']['poseidon']['impact_delay']=1.1
(ROOT/'data/presentation/myth_audio.json').write_text(json.dumps(config,indent=2)+'\n')
print(f'Built {len(files)} distinct cues; max peak {max(f["peak"] for f in files):.3f}')
