"""Original deterministic stone-rumble effect; no third-party samples."""
import math
import random
import struct
import wave
from pathlib import Path
rng = random.Random(1102)
low = 0.0
samples = []
rate = 22050
for i in range(int(rate * 2.4)):
    t = i / rate
    noise = rng.uniform(-1, 1)
    low = low * .97 + noise * .03
    envelope = min(1, t * 80) * math.exp(-t * 1.9)
    grit = noise * .06 * max(0, math.sin(t * 31))
    value = (low * 2.4 + math.sin(t * math.tau * 47) * .12 + grit) * envelope
    samples.append(struct.pack('<h', int(max(-.8, min(.8, value)) * 32767)))
with wave.open(str(Path(__file__).resolve().parents[1] / 'assets/poseidon_rumble.wav'), 'wb') as audio:
    audio.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
    audio.writeframes(b''.join(samples))
