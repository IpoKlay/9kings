"""Original synthesized UI auditions, deliberately free of mouth/foley recordings.
Each preview: three hover cues, a pause, then a selection cue. Not installed in game.
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parents[2] / 'output' / 'card-audio-auditions'
OUT.mkdir(parents=True, exist_ok=True)

def tone(freq, decay, duration, level=1, harmonic=0):
    return [level * min(1, i / (RATE * .0008)) * math.exp(-i / RATE / decay)
            * (math.sin(2 * math.pi * freq * i / RATE)
               + harmonic * math.sin(2 * math.pi * freq * 3 * i / RATE))
            * min(1, (duration - i / RATE) / .008)
            for i in range(int(RATE * duration))]

def noise(duration, decay, level, seed, highpass=False):
    rng = random.Random(seed)
    result = []
    last = 0
    for i in range(int(RATE * duration)):
        n = rng.uniform(-1, 1)
        filtered = (n-last)*.5 if highpass else (n+last)*.5
        last = n
        t = i/RATE
        result.append(filtered * level * math.exp(-t/decay) * min(1,t/.001)
                      * min(1,(duration-t)/.006))
    return result

def mix(*layers):
    result = [0.] * max(int(offset * RATE) + len(data) for offset, data in layers)
    for offset, data in layers:
        start = round(offset * RATE)
        for i, v in enumerate(data):
            if start+i < len(result): result[start+i] += v
    return result

def cue(style, selected, variant=0):
    seed = 707+variant
    f = 1 + variant*.025
    if style == 'A':  # a short dry snap and separated paper-edge ticks
        layers = [(0, noise(.055,.012,.75,seed,True)),
                  (0, tone(1250*f,.009,.05,.22))]
        if selected: layers += [(.032, noise(.065,.016,.8,seed+13,True)),
                                (.032,tone(420,.018,.08,.3))]
    elif style == 'B':  # wooden tokens, no sweeping pitch
        layers = [(0,tone(680*f,.018,.11,.65)),(0,tone(1430*f,.009,.065,.27)),
                  (0,noise(.025,.004,.34,seed))]
        if selected: layers += [(.047,tone(440,.025,.14,.7)),(.047,noise(.025,.006,.3,seed+1))]
    elif style == 'C':  # metal clasp, controlled short resonance
        layers = [(0,tone(2100*f,.025,.14,.32)),(0,tone(3190*f,.017,.10,.18)),
                  (0,noise(.02,.005,.4,seed,True))]
        if selected: layers += [(0,tone(760,.035,.18,.38)),(.04,tone(2650,.038,.2,.29))]
    elif style == 'D':  # retro note clicks, no abrasive square wave
        layers = [(0,tone(880*f,.022,.065,.4,.2))]
        if selected: layers += [(.05,tone(1174.66,.027,.085,.4,.2)),
                                (.10,tone(1760,.033,.13,.34,.15))]
    elif style == 'E':  # heavier mechanical latch
        layers = [(0,tone(220*f,.023,.12,.58)),(0,tone(1050*f,.008,.055,.35)),
                  (0,noise(.032,.006,.55,seed,True))]
        if selected: layers += [(.055,tone(130,.035,.18,.66)),
                                (.055,noise(.04,.009,.6,seed+3,True))]
    else:  # dry physical click plus a restrained reward interval
        layers = [(0,noise(.027,.006,.5,seed,True)),(0,tone(980*f,.018,.085,.4))]
        if selected: layers += [(.035,tone(1470,.029,.14,.32)),
                                (.07,tone(1960,.036,.18,.25)),
                                (0,tone(330,.02,.1,.24))]
    return mix(*layers)

def save(path, data):
    with wave.open(str(path),'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', round(max(-1,min(1,x))*32767)) for x in data))

names = {'A':'dry-card-snap','B':'wooden-token','C':'metal-clasp',
         'D':'retro-pixel','E':'heavy-latch','F':'crisp-reward'}
for style, name in names.items():
    events = [cue(style,False,i) for i in range(3)] + [cue(style,True)]
    # Match hover energy across families, preserve a modestly louder selection.
    energy = math.sqrt(sum(x*x for x in events[0]) / (RATE*.10))
    gain = .075/max(.0001,energy)
    peak = max(abs(x)*gain for event in events for x in event)
    gain *= min(1,.72/max(.001,peak))
    events = [[x*gain for x in event] for event in events]
    preview = mix(*zip([.20,.70,1.20,2.05],events), (0,[0.] * int(RATE*2.85)))
    save(OUT / f'{style}-{name}.wav',preview)
    # Keep isolated sources for installing the user's chosen style later.
    save(OUT / f'{style}-hover.wav',events[0])
    save(OUT / f'{style}-select.wav',events[3])
    assert max(abs(x) for x in preview) <= .721
    print(f'{style}: {name}, 2.85s, peak {max(abs(x) for x in preview):.3f}')
