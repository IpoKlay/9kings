"""Pack RTS sheets without changing horizontal UV normalization. Requires Pillow."""
from pathlib import Path
from PIL import Image
import hashlib,json,math
ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'assets/rts-armies'
OUT=SRC/'atlas'
CORE=['legion','guard','spear','archer','cavalry','medic','siege']
def main():
 OUT.mkdir(exist_ok=True)
 groups={};manifest={'sheets':{},'pages':{},'rotation':False,'trim':False}
 for p in SRC.glob('*.png'):
  with Image.open(p) as im:w,h=im.size
  assert h==512 and w in (64,1088),p
  groups.setdefault(w,[]).append(p)
 for width,paths in sorted(groups.items()):
  paths.sort(key=lambda p:(0 if p.stem.rsplit('_',1)[0] in CORE else 1,p.name))
  for start in range(0,len(paths),15):
   chunk=paths[start:start+15];height=2**math.ceil(math.log2((len(chunk)+1)*512))
   page=f'units-{width}-{start//15}.png';atlas=Image.new('RGBA',(width,height))
   for i,p in enumerate(chunk):
    im=Image.open(p).convert('RGBA');atlas.paste(im,(0,i*512))
    assert atlas.crop((0,i*512,width,(i+1)*512)).tobytes()==im.tobytes()
    manifest['sheets'][p.stem]={'page':page,'region':[0,i*512,width,512],'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
   atlas.putpixel((0,height-1),(255,255,255,255));atlas.save(OUT/page)
   manifest['pages'][page]={'size':[width,height],'white_pixel':[0,height-1,1,1]}
 (OUT/'units.json').write_text(json.dumps(manifest,indent=2))
 print('Verified',len(manifest['sheets']),'sheets in',len(manifest['pages']),'pages')
if __name__=='__main__':main()
