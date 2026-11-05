"""Build licensed combat clips from the downloaded CC0 recordings.
Usage: python tools/prepare_trial_audio.py SOURCE_DIRECTORY (requires numpy, soundfile).
"""
from pathlib import Path
import sys
import numpy as np
import soundfile as sf

source = Path(sys.argv[1])
target = Path(__file__).resolve().parents[1] / 'assets/combat_audio'
target.mkdir(parents=True, exist_ok=True)

def read(name):
    x, rate = sf.read(source / name, always_2d=True)
    assert rate == 44100
    return x.mean(axis=1)

def save(name, x, peak=.65):
    active = np.flatnonzero(np.abs(x) > .003)
    if len(active):
        x = x[max(0, active[0]-220):min(len(x), active[-1]+881)].copy()
    x *= peak / max(.001, np.abs(x).max())
    attack, release = min(220,len(x)//4), min(2205,len(x)//4)
    x[:attack] *= np.linspace(0,1,attack)
    x[-release:] *= np.linspace(1,0,release)
    sf.write(target / (name+'.wav'), x, 44100, subtype='PCM_16')
    print(name, round(len(x)/44100,3), 'seconds, peak', round(np.abs(x).max(),3))

for i, n in enumerate([1,3,5]):
    save('impact'+str(i), read('sword_clash.'+str(n)+'.ogg'), .6)
bow = read('Bow.wav')
for i, speed in enumerate([1., .94, 1.06]):
    save('arrow'+str(i), np.interp(np.arange(0,len(bow)-1,speed), np.arange(len(bow)), bow), .55)

# Choose energetic, non-overlapping group-shout excerpts, not a perpetual battlefield loop.
crowd = read('crowd_shouting_0.ogg')
length = 2*44100
starts = range(0,len(crowd)-length,22050)
ranked = sorted(starts, key=lambda n:float(np.mean(crowd[n:n+length]**2)), reverse=True)
chosen = []
for start in ranked:
    if all(abs(start-other)>length for other in chosen): chosen.append(start)
    if len(chosen)==2:break
for i,start in enumerate(chosen):
    clip = crowd[start:start+length]
    clip = np.interp(np.arange(0,len(clip)-1,.88),np.arange(len(clip)),clip)
    save('cry'+str(i),clip,.55)
quake = read('shake.flac')
quake = np.interp(np.arange(0,len(quake)-1,1.8),np.arange(len(quake)),quake)
save('earthquake',quake,.8)
