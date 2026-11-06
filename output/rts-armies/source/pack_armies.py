"""python pack_armies.py RENDER_DIR GODOT_ASSET_DIR. Requires Pillow and NumPy."""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

source, target = map(Path, sys.argv[1:3])
target.mkdir(parents=True, exist_ok=True)
colors = '2b2523 344957 879da6 dce0d5 401f25 872e2a b34f36 75572e c3a15a edcb81 70523d a97456 dbad7b'.split()
enemy_colors = '2b2523 344957 879da6 dce0d5 203346 315773 5993a4 75572e c3a15a edcb81 70523d a97456 dbad7b'.split()
pal = np.array([list(bytes.fromhex(c)) for c in colors], dtype=np.int32)
enemy_pal = np.array([list(bytes.fromhex(c)) for c in enemy_colors])
gray = np.array([list(bytes.fromhex(c)) for c in '333f3e 515d57 737e70 929b87 b2b8a0 d4d7ba'.split()])
stone_pal = gray[np.minimum(5, (pal @ np.array([.2126,.7152,.0722])*6/256).astype(int))]
for folder in sorted(p for p in source.iterdir() if p.is_dir() and (p/'pose-0001.png').exists()):
    frames = sorted(folder.glob('pose-*.png'))
    assert len(frames)==136,folder
    atlas = np.full((512,1088),len(pal),dtype=np.uint8)
    for i,path in enumerate(frames):
        pixels=np.array(Image.open(path).convert('RGBA'))
        # Flat emission materials allow nearest-colour voting on the 4x4 samples.
        packed=pixels[:,:,:3].copy().view('V3').reshape(-1)
        unique,idx=np.unique(packed,return_inverse=True)
        rgb=unique.view('uint8').reshape(-1,3).astype(int)
        ids=((rgb[:,None,:]-pal)**2).sum(2).argmin(1)[idx].reshape(256,256)
        ids[pixels[:,:,3]<128]=len(pal)
        samples=ids.reshape(64,4,64,4).transpose(0,2,1,3).reshape(64,64,16)
        solid=(samples!=len(pal)).sum(2)>=8
        votes=np.stack([(samples==color).sum(2) for color in range(len(pal))])
        cell=np.where(solid,votes.argmax(0),len(pal))
        edge=(np.roll(solid,1,0)|np.roll(solid,-1,0)|np.roll(solid,1,1)|np.roll(solid,-1,1))&~solid
        cell[edge]=0
        assert solid.any() and not solid[[0,-1]].any() and not solid[:,[0,-1]].any(),path
        y,x=divmod(i,17);atlas[y*64:y*64+64,x*64:x*64+64]=cell
    for side,lookup in [('ally',pal),('enemy',enemy_pal),('stone',stone_pal)]:
        bitmap=atlas[:,:64] if side=='stone' else atlas
        rgba=np.zeros((len(pal)+1,4),dtype=np.uint8);rgba[:-1,:3]=lookup;rgba[:-1,3]=255
        Image.fromarray(rgba[bitmap]).save(target/f'{folder.name}_{side}.png')
    print(folder.name,flush=True)
