from pathlib import Path
import json,numpy as np
from PIL import Image
base=Path(__file__).resolve().parents[3];source=base/'output/sword-banner-reference/corpse-motion/art';target=base/'godot-game/assets/rts-corpses';target.mkdir(parents=True,exist_ok=True)
manifest=json.loads((source/'parts.json').read_text());meta={};report=[]
colors='2b2523 344957 879da6 dce0d5 401f25 872e2a b34f36 75572e c3a15a edcb81 70523d a97456 dbad7b'.split()
enemy='2b2523 344957 879da6 dce0d5 203346 315773 5993a4 75572e c3a15a edcb81 70523d a97456 dbad7b'.split()
for kind,row in manifest.items():
 extra=['293c2b','526844','869864'] if kind.startswith('goblin_') or kind=='dragon' else []
 pal=np.array([list(bytes.fromhex(c)) for c in colors+extra],dtype=np.int32);epal=np.array([list(bytes.fromhex(c)) for c in enemy+extra]);n=len(pal)
 count=len(row['bearings'][0]);atlas=np.full((1024,count*128),n,dtype=np.uint8);visible=0
 for bearing,parts in enumerate(row['bearings']):
  for index,part in enumerate(parts):
   a=np.asarray(Image.open(source/kind/f'{bearing:02}-{index:02}.png').convert('RGBA'))
   ys,xs=np.where(a[:,:,3]>=128)
   cell=np.full((128,128),n,dtype=np.uint8);solid=np.zeros((128,128),dtype=bool)
   if len(xs):
    x0=int(xs.min())//4*4;y0=int(ys.min())//4*4;x1=(int(xs.max())//4+1)*4;y1=(int(ys.max())//4+1)*4
    pixels=a[y0:y1,x0:x1];hh,ww=pixels.shape[:2]
    unique,idx=np.unique(pixels[:,:,:3].copy().view('V3').reshape(-1),return_inverse=True);rgb=unique.view('uint8').reshape(-1,3).astype(int)
    ids=((rgb[:,None,:]-pal)**2).sum(2).argmin(1)[idx].reshape(hh,ww);ids[pixels[:,:,3]<128]=n
    samples=ids.reshape(hh//4,4,ww//4,4).transpose(0,2,1,3).reshape(hh//4,ww//4,16);local_solid=(samples!=n).sum(2)>=8
    votes=np.stack([(samples==c).sum(2) for c in range(n)])
    cell[y0//4:y1//4,x0//4:x1//4]=np.where(local_solid,votes.argmax(0),n)
    solid[y0//4:y1//4,x0//4:x1//4]=local_solid
   edge=(np.roll(solid,1,0)|np.roll(solid,-1,0)|np.roll(solid,1,1)|np.roll(solid,-1,1))&~solid;cell[edge]=0
   assert not solid[[0,-1]].any() and not solid[:,[0,-1]].any(),(kind,bearing,part['name'])
   visible+=bool(solid.any());atlas[bearing*128:(bearing+1)*128,index*128:(index+1)*128]=cell
   part['cell']=index
  parts.sort(key=lambda p:-p['depth'])
 for side,lookup in [('ally',pal),('enemy',epal)]:
  rgba=np.zeros((n+1,4),dtype=np.uint8);rgba[:-1,:3]=lookup;rgba[:-1,3]=255
  Image.fromarray(rgba[atlas]).save(target/f'{kind}_{side}.png')
 meta[kind]=row['bearings'];report.append({'kind':kind,'parts':count,'visible_frames':visible,'frames':8*count,'colors':n,'alpha':'0 or255','frame_size':[128,128]})
(base/'godot-game/data/presentation/corpse_parts.json').write_text(json.dumps(meta,separators=(',',':'))+'\n')
(source.parent/'art-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('Packed',len(meta),'actors;',sum(x['frames'] for x in report),'rigid piece frames')
