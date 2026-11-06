"""Measure the two filmed regiments in Godot's native 960x540 pixel viewport.
Run after capture_regiment_contact.gd. Requires Pillow and NumPy.
"""
import csv
import json
import math
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image

GAME = Path(__file__).resolve().parents[2]
OUTPUT = GAME.parent / 'output' / 'rts-impact'
TYPES = json.loads((GAME / 'data/balance/tactical_trial.json').read_text())['types']
LAYOUT = {'guard': (26, 16, 1.23), 'cavalry': (33, 24, 1.83), 'spear': (26, 16, 1.86)}


@lru_cache(None)
def atlas(kind, side):
    return np.asarray(Image.open(GAME / 'assets/rts-armies' / f'{kind}_{side}.png').convert('RGBA'))[:, :, 3]


def silhouette(unit, side):
    kind = unit['kind']
    stats = TYPES[kind]
    spacing, pitch, scale = LAYOUT[kind]
    files = stats['files']
    depth = math.ceil(stats['soldiers'] / files)
    files, depth, spacing, pitch, scale = unit.get('formation', (files, depth, spacing, pitch, scale))
    count = max(1, math.ceil(files * depth * unit['hp'] / unit['max']))
    mask = np.zeros((540, 960), dtype=bool)
    sheet = atlas(kind, side)
    for slot in range(files * depth):
        if unit.get('priority', {}).get(str(slot), slot) >= count:
            continue
        row, col = divmod(slot, files)
        phase = (col + row * 3) % 4
        frame = 0
        if unit['attack'] < .55:
            frame = 9 + max(0, min(7, int(unit['attack'] * 8 / .55)) - phase % 2)
        elif unit['walk']:
            frame = 1 + (int(8 * unit['march'] / stats['stride']) + [0, 1, 0, -1][phase]) % 8
        dx, dy = unit.get('offsets', {}).get(str(slot), (0, 0))
        r = row - (depth - 1) / 2
        x = math.floor(unit['p'][0] + (col - (files-1)/2)*spacing + r*5 + dx - 32*scale + .5) / 2
        y = math.floor(unit['p'][1] + r*pitch + dy - 54*scale + .5) / 2
        # Pixel centers, nearest-neighbor sampling, alpha >= 1/2. Ignore UI, shadows
        # painted by the field, and occlusion by the third formation pinning the front.
        xs = np.arange(max(0, math.ceil(x-.5)), min(960, math.ceil(x+32*scale-.5)))
        ys = np.arange(max(0, math.ceil(y-.5)), min(540, math.ceil(y+32*scale-.5)))
        ix = np.clip(((xs+.5-x)*2/scale).astype(int), 0, 63) + frame*64
        iy = np.clip(((ys+.5-y)*2/scale).astype(int), 0, 63) + unit['dir']*64
        mask[np.ix_(ys, xs)] |= sheet[np.ix_(iy, ix)] >= 128
    return mask


def measure(version, case):
    rows = [json.loads(line) for line in (OUTPUT/version/f'{case}.jsonl').read_text().splitlines()]
    impact = next(i for i, row in enumerate(rows) if row['events'])
    # Every filmed first contact occurs before any follow-through animation.
    touch = next(i for i, row in enumerate(rows[:impact+60])
                 if (silhouette(row['a'], 'ally') & silhouette(row['d'], 'enemy')).any())
    assert rows[impact]['d']['hp'] < rows[impact-1]['d']['hp']
    stop = next(i for i in range(31, len(rows)) if rows[i]['a']['march'] and not rows[i]['a']['walk'])
    end = stop
    if rows[stop+1]['a']['walk']:
        end = next(i for i in range(stop+2, len(rows)) if not rows[i]['a']['walk'])
    travel = math.dist(rows[stop]['a']['p'], rows[end]['a']['p'])
    return [version, case, touch, impact, impact-touch, stop, end, round(travel, 1)]


if __name__ == '__main__':
    fields = ['version','case','outline_frame','first_damage_frame','delay_frames',
              'first_halt','follow_through_end','projected_follow_px']
    with (OUTPUT / 'frames.csv').open('w') as file:
        writer = csv.writer(file)
        writer.writerow(fields)
        for version in ('before', 'after'):
            for case in ('shield','flank','pikes'):
                values = measure(version, case)
                print(*values)
                writer.writerow(values)
