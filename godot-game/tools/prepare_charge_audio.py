"""Derive short charge hits and a dull landing from the project's CC0 clips.
No new downloads; preserves the original recordings and their attribution.
"""
from pathlib import Path
import hashlib, json, wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/combat_audio/charge'
OUT.mkdir(exist_ok=True)
records = []
for i in range(4):
    source = ROOT / f'assets/combat_audio/impact{i if i < 3 else 0}.wav'
    with wave.open(str(source)) as f:
        rate = f.getframerate()
        x = np.frombuffer(f.readframes(f.getnframes()), dtype='<i2').astype(float)
        x = x.reshape(-1, f.getnchannels()).mean(axis=1) / 32768.
    peak = int(np.argmax(abs(x)))
    start = max(0, peak - int(.018 * rate))
    duration = .20 if i < 3 else .13
    y = x[start:start + round(duration * rate)].copy()
    if i == 3:
        # Remove the ringing metal frequencies for a brief body/ground thud.
        a = 1 - np.exp(-2 * np.pi * 550 / rate)
        for _ in range(2):
            prev = 0.
            for j in range(len(y)):
                prev += a * (y[j] - prev)
                y[j] = prev
    y *= (.60 if i < 3 else .48) / max(float(abs(y).max()), .0001)
    attack, release = round(.003 * rate), round(.035 * rate)
    y[:attack] *= np.linspace(0, 1, attack)
    y[-release:] *= np.linspace(1, 0, release)
    name = f'charge-hit-{i}.wav' if i < 3 else 'charge-land.wav'
    with wave.open(str(OUT / name), 'wb') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(rate)
        f.writeframes((np.clip(y, -1, 1) * 32767).astype('<i2').tobytes())
    records.append({'file': name, 'source': str(source.relative_to(ROOT)),
                    'start_seconds': start/rate, 'duration_seconds': len(y)/rate,
                    'processing': 'short metal transient' if i < 3 else 'two-pole 550Hz low-pass thud',
                    'sha256': hashlib.sha256((OUT/name).read_bytes()).hexdigest()})
(OUT/'manifest.json').write_text(json.dumps({'license': 'CC0-1.0', 'files': records}, indent=2)+'\n')
print(json.dumps(records, indent=2))
