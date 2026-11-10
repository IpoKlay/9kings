"""Offline, deterministic UI atlas build. Run from the current project checkout.
No source assets are modified. Requires Pillow (already available on this machine).
"""
from pathlib import Path
from PIL import Image
import hashlib, json, math
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'godot-game/assets/ui_rpg/atlas'
CUTS={
    'scroll':([254,69,104,145],3,[26,18,22,16]),
    'paper':([396,31,86,99],3,[14,14,14,14]),
    'strip':([632,204,128,36],3,[10,5,10,5]),
    'button':([636,246,67,37],3,[8,6,8,6]),
    'book':([125,332,266,152],4,None),
    'arrow_left':([808,592,32,16],2,None),
    'arrow_right':([856,592,32,16],2,None),
}

def main():
    sources=[]
    for key,(region,scale,margins) in CUTS.items():
        sources.append(dict(id='ui.'+key,source='godot-game/assets/ui_rpg/ui.png',crop=region,scale=scale,nine_patch=[n*scale for n in margins] if margins else None))
    sources.append(dict(id='hud.toolbar',source='godot-game/assets/ui_rpg/battle_hud/toolbar.png',scale=1,nine_patch=[24,18,24,18]))
    for name in ('banner','gear','helmet','laurels','legion_flag','scroll'):
        sources.append(dict(id='icon.'+name,source=f'godot-game/assets/ui_roman/{name}.png',scale=1,nine_patch=None))
    images={};originals={};metadata={}
    for row in sources:
        with Image.open(ROOT/row['source']) as f:im=f.convert('RGBA')
        if 'crop' in row:
            x,y,w,h=row['crop'];assert 0<=x and 0<=y and x+w<=im.width and y+h<=im.height
            im=im.crop((x,y,x+w,y+h))
        scale=row['scale'];im=im.resize((im.width*scale,im.height*scale),Image.Resampling.NEAREST)
        digest=hashlib.sha256(str(im.size).encode()+im.tobytes()).hexdigest()
        images[digest]=im;originals[row['id']]=im
        metadata[row['id']]={**row,'pixel_key':digest,'source_size':list(im.size),'trim_offset':[0,0],'rotation':False}
    # Shelf packing, 2-pixel transparent gutters. Pixel-art nearest filtering only.
    width=2048;pad=2;x=y=pad;row_h=0;regions={};used_w=0
    for key in sorted(images,key=lambda k:(-images[k].height,-images[k].width,k)):
        im=images[key];assert im.width+pad*2<=width
        if x+im.width+pad>width:x=pad;y+=row_h+pad*2;row_h=0
        regions[key]=[x,y,im.width,im.height]
        x+=im.width+pad*2;row_h=max(row_h,im.height);used_w=max(used_w,x)
    height=2**math.ceil(math.log2(y+row_h+pad));assert height<=4096
    atlas=Image.new('RGBA',(width,height))
    for key,im in images.items():atlas.paste(im,regions[key][:2])
    for key,row in metadata.items():
        x,y,w,h=regions[row.pop('pixel_key')];row['region']=[x,y,w,h];row['page']='ui-atlas.png'
        assert atlas.crop((x,y,x+w,y+h)).tobytes()==originals[key].tobytes(),key
    # Distinct image regions must not overlap; aliases deliberately share a region.
    boxes=list(regions.values())
    for i,(x,y,w,h) in enumerate(boxes):
        assert x>=pad and y>=pad and x+w+pad<=width and y+h+pad<=height
        for a,b,c,d in boxes[i+1:]:assert x+w<=a or a+c<=x or y+h<=b or b+d<=y
    atlas.save(OUT/'ui-atlas.png')
    manifest={'canvas':[width,height],'filter':'nearest','mipmaps':False,'padding':pad,'extrusion':0,'rotation':False,'trim':False,'rgba8_MiB':width*height*4/1048576,'assets':metadata}
    (OUT/'ui-atlas.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/'ui-asset-inputs.json').write_text(json.dumps(sources,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/'packing-validation.json').write_text(json.dumps({'asset_count':len(metadata),'unique_images':len(images),'overlap_check':True,'rgba_roundtrip_exact':True,'source_assets_modified':False},indent=2))
    print(f'Built {width}x{height}, {len(metadata)} named assets, {len(images)} unique pixel images, all regions verified.')

if __name__=='__main__':main()
