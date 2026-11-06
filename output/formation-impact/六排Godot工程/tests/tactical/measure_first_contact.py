"""Independent pixel check of the filmed first hit, in the native 960x540 field."""
import csv
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

GAME = Path(__file__).resolve().parents[2]
OUT = GAME.parent / 'output/first-contact'
SHEETS = {k: np.asarray(Image.open(GAME/f'assets/rts-armies/{k}_{s}.png').convert('RGBA'))[:, :, 3]
          for k, s in [('cavalry', 'ally'), ('legion', 'enemy')]}


def raster(unit, horse, contact=None):
    kind = 'cavalry' if horse else 'legion'
    legacy = (8, 4, 33, 24, 1.83) if horse else (10, 6, 26, 16, 1.23)
    files, depth, dx, dy, scale = unit.get('formation', legacy)
    count = max(unit['shown'], math.ceil(files*depth*unit['hp']/unit['max']))
    mask = np.zeros((540, 960), dtype=bool)
    first = np.zeros_like(mask)
    for i in range(files*depth):
        if unit['priority'].get(str(i), i) >= count:
            continue
        row, col = divmod(i, files)
        r = row - (depth-1)/2
        phase = (col+3*row) % 4
        cell = (9+max(0,unit['frame']-phase%2) if unit['action'] else
                1+(unit['frame']+(0,1,0,-1)[phase])%8 if unit['walk'] else 0)
        bearing = unit['dir']
        key = 'rider' if horse else 'defender'
        tagged = contact and i == contact['rider' if horse else 'soldier']
        if tagged:
            cell, bearing = contact[key+'_cell'], contact[key+'_bearing']
        shift = unit['offsets'].get(str(i), (0,0))
        x = math.floor(unit['p'][0]+(col-(files-1)/2)*dx+r*5+shift[0]-32*scale+.5)/2
        y = math.floor(unit['p'][1]+r*dy+shift[1]-54*scale+.5)/2
        xs = np.arange(max(0,math.ceil(x-.5)), min(960,math.ceil(x+32*scale-.5)))
        ys = np.arange(max(0,math.ceil(y-.5)), min(540,math.ceil(y+32*scale-.5)))
        ix = np.clip(((xs+.5-x)*2/scale).astype(int),0,63)+cell*64
        iy = np.clip(((ys+.5-y)*2/scale).astype(int),0,63)+bearing*64
        opaque = SHEETS[kind][np.ix_(iy,ix)] >= 128
        mask[np.ix_(ys,xs)] |= opaque
        if tagged:first[np.ix_(ys,xs)] |= opaque
    return mask, first


def distance(mask, point):
    y,x = np.nonzero(mask)
    return np.sqrt(np.min((x+.5-point[0])**2+(y+.5-point[1])**2))


def read(name):
    return [json.loads(line) for line in (OUT/(name+'.jsonl')).read_text().splitlines()]


def measure(name):
    rows=read(name)
    hit_index, = [i for i,r in enumerate(rows) if 'hit' in r]
    hit=rows[hit_index]['hit']
    slow_hit, = [r['hit'] for r in read(name+'-15') if 'hit' in r]
    assert hit==slow_hit, '15 and 60 Hz produced different contacts'
    p=np.array(hit['p'])/2
    touch=None
    for i in range(max(0,hit_index-12),hit_index+1):
        r=rows[i]
        a,first_a=raster(r['a'],True,r.get('hit'))
        b,first_b=raster(r['b'],False,r.get('hit'))
        if touch is None and (a & b).any():
            touch=i
    assert touch is not None, f'{name}: no shared visible texel at reaction'
    local=[distance(m,p) for m in (first_a,first_b)]
    assert max(local)<=1.5, f'{name}: contact outside the marked pair {local}'
    assert abs(hit_index-touch)<=1, f'{name}: visible edge frame {touch}, response {hit_index}'
    assert abs(rows[hit_index-1]['b']['hp']-rows[hit_index]['b']['hp']-hit['damage'])<.001
    # The center and opposite files keep their original positions; the actual
    # struck soldier is kept on screen, flashed, and then pushed locally.
    files, depth = rows[hit_index]['b'].get('formation', (10, 6))[:2]
    assert rows[hit_index]['b']['shown']==files*depth
    assert not any(abs(x)+abs(y)>.01 for x,y in rows[hit_index]['b']['offsets'].values())
    next_offsets=rows[hit_index+1]['b']['offsets']
    assert np.linalg.norm(next_offsets[str(hit['soldier'])])>1
    opposite=files-1 if hit['soldier']%files<files/2 else 0
    assert all(np.linalg.norm(next_offsets.get(str(row*files+opposite),(0,0)))<.01 for row in range(depth))
    return [name,touch,hit_index,hit_index-touch,hit['rider'],hit['soldier'],
            *[round(d,2) for d in local],round(hit['speed'],2),hit['damage'],hit['audio']]


if __name__=='__main__':
    with (OUT/'frames.csv').open('w') as f:
        writer=csv.writer(f)
        writer.writerow(['approach','visible_edges','first_reaction','steps_apart','rider_slot','infantry_slot',
                         'point_to_rider_px','point_to_infantry_px','world_speed','damage','main_audio'])
        for direction in ('east','west','north_east','north_west'):
            result=measure(direction)
            writer.writerow(result)
            print(*result)
