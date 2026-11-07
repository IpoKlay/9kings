"""Bake weapon anchors from our existing Blender sheets, in64px cell coordinates."""
from pathlib import Path
import bpy,json,sys,hashlib
from bpy_extras.object_utils import world_to_camera_view
base=Path(sys.argv[sys.argv.index('--')+1]).resolve()
models={'archer':('output/rts-armies/source/archer.blend','Bow grip'), 'mounted_archer':('output/sword-banner-reference/mounted-archer/art/mounted_archer.blend','Bow grip'),'crossbow':('output/sword-banner-reference/human-roster/art/crossbow.blend','Crossbow'),'skeleton_archer':('output/sword-banner-reference/undead-roster/art/skeleton_archer.blend','Bow grip'),'goblin_archer':('output/sword-banner-reference/goblin-roster/art/goblin_archer.blend','Bow grip'),'goblin_slinger':('output/sword-banner-reference/goblin-roster/art/goblin_slinger.blend','Sling stone'),'goblin_wolf_skirmisher':('output/sword-banner-reference/goblin-roster/art/goblin_wolf_skirmisher.blend','Bow grip'),'siege':('output/rts-armies/source/siege.blend','Shot')}
anchors={};manifest={}
for name,(file,node) in models.items():
 bpy.ops.wm.open_mainfile(filepath=str(base/file));scene=bpy.context.scene;obj=bpy.data.objects[node];rows=[]
 for bearing in range(8):
  row=[]
  for col in range(9,17):
   scene.frame_set(bearing*17+col+1);bpy.context.view_layer.update()
   point=world_to_camera_view(scene,scene.camera,obj.matrix_world.translation)
   row.append([round(point.x*64-32,4),round((1-point.y)*64-54,4)])
  rows.append(row)
 anchors[name]=rows;manifest[name]={'source':file,'sha256':hashlib.sha256((base/file).read_bytes()).hexdigest(),'anchor_node':node}
(base/'godot-game/data/presentation/projectile_anchors.json').write_text(json.dumps(anchors,indent=2)+'\n')
(base/'output/sword-banner-reference/projectile-motion/anchor-sources.json').write_text(json.dumps(manifest,indent=2)+'\n')
