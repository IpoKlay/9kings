"""Render rigid, unoccluded death pieces from the project's own editable actors."""
import bpy,json,sys,hashlib
from math import pi
from mathutils import Vector
from pathlib import Path
from bpy_extras.object_utils import world_to_camera_view
base=Path(sys.argv[sys.argv.index('--')+1]).resolve()
out=base/'output/sword-banner-reference/corpse-motion/art';out.mkdir(parents=True,exist_ok=True)
models={p.stem:p for p in (base/'output/rts-armies/source').glob('*.blend')}
models.update({p.stem:p for p in (base/'output/sword-banner-reference').glob('*/art/*.blend')})
weapons={'Gladius / right','Hasta','Bow grip','Two handed axe','Pitchfork','Crossbow','Knotted club','Sling','Crooked staff','Scythe'}
# Bones identify the independently observed reference skeleton, not original artwork.
bones={'torso':[2,1],'head':[1,0],'right_arm':[2,5],'right_hand':[5,6],'left_arm':[2,3],'left_hand':[3,4], 'right_thigh':[2,8],'right_shin':[8,10],'left_thigh':[2,7],'left_shin':[7,9], 'mount':[13,12],'mount_head':[12,11],'mount_fl':[12,14],'mount_fr':[12,15],'mount_back':[13,16], 'hound':[3,2],'hound_head':[1,0],'hound_fl':[2,4],'hound_fr':[2,5],'hound_bl':[3,6],'hound_br':[3,7],'weapon':[6,6],'shield':[4,4]}
def names(o):
 result=[]
 while o:result.append(o.name);o=o.parent
 return result
def group(o,kind):
 ns=names(o)
 if kind in ('dragon','siege'):return 'torso'
 if any(n in weapons for n in ns):return 'weapon'
 if 'Scutum / left' in ns or 'Clipeus' in ns:return 'shield'
 if 'Mount' in ns:
  legs=[n for n in ns if n.startswith('Horse leg')]
  if legs:return {'Horse leg':'mount_fl','Horse leg.001':'mount_back','Horse leg.002':'mount_fr','Horse leg.003':'mount_back'}[legs[0]]
  if o.name.startswith(('Neck','Horse head','Muzzle','Ear','Bridle','Mane','Wolf neck','Wolf skull','Wolf snout','Wolf pointed','Wolf eye','Wolf fang','Horse chamfron')):return 'mount_head'
  return 'mount'
 if 'Hound body' in ns:
  legs=[n for n in ns if n.startswith('Hound leg')]
  if legs:return {'Hound leg':'hound_fl','Hound leg.001':'hound_bl','Hound leg.002':'hound_fr','Hound leg.003':'hound_br'}[legs[0]]
  return 'hound_head' if 'Hound neck' in ns else 'hound'
 for name,g in [('Head / chin','head'),('Elbow','right_hand'),('Elbow.001','left_hand'),('Shoulder','right_arm'),('Shoulder.001','left_arm'),('Knee','right_shin'),('Knee.001','left_shin'),('Hip joint','right_thigh'),('Hip joint.001','left_thigh')]:
  if name in ns:return g
 return 'torso'
manifest=json.loads((out/'parts.json').read_text()) if (out/'parts.json').exists() else {}
selected=sys.argv[sys.argv.index('--')+2:]
for kind,path in sorted(models.items()):
 if selected and kind not in selected:continue
 bpy.ops.wm.open_mainfile(filepath=str(path));s=bpy.context.scene
 s.frame_set(1);bpy.data.objects['Bearing'].animation_data_clear()
 old_size=s.camera.data.ortho_scale
 s.camera.location-=s.camera.matrix_world.to_quaternion()@Vector((0,old_size*.34375,0))
 s.camera.data.ortho_scale=old_size*2;s.render.resolution_x=512;s.render.resolution_y=512
 meshes=[o for o in bpy.data.objects if o.type=='MESH' and not o.hide_render]
 groups={}
 for o in meshes:groups.setdefault(group(o,kind),[]).append(o)
 if kind=='wraith':groups={k:v for k,v in groups.items() if k=='weapon'}
 rows=[]
 for bearing in range(8):
  s.frame_set(1+bearing*17);bpy.data.objects['Bearing'].rotation_euler=(pi/2,0,bearing*pi/4);bpy.context.view_layer.update();row=[]
  for index,(name,objects) in enumerate(sorted(groups.items())):
   for o in meshes:o.hide_render=o not in objects
   p=out/kind/f'{bearing:02}-{index:02}.png';p.parent.mkdir(parents=True,exist_ok=True)
   s.render.filepath=str(p);bpy.ops.render.render(write_still=True)
   assert abs(bpy.data.objects['Bearing'].rotation_euler.x-pi/2)<.0001,'Animation overwrote prone pose'
   centers=[world_to_camera_view(s,s.camera,o.matrix_world.translation) for o in objects]
   # Authored anchor is stored in128px death-cell pixels relative to the ground foot (64,64).
   cx=sum(c.x for c in centers)/len(centers);cy=sum(c.y for c in centers)/len(centers)
   row.append({'name':name,'bone':bones[name],'pivot':[cx*128-64,(1-cy)*128-64],'depth':sum(c.z for c in centers)/len(centers)})
  rows.append(row)
 for o in meshes:o.hide_render=False
 manifest[kind]={'source':str(path.relative_to(base)),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'pose':'Own model laid on ground by90 degree root rotation; live scale preserved in128px death canvas','bearings':rows}
 (out/'parts.json').write_text(json.dumps(manifest,indent=2)+'\n');print('CORPSE_PARTS',kind,len(groups)*8,flush=True)
