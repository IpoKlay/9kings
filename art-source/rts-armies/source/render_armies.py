"""Blender --background --python render_armies.py -- SHIELD.blend OUTPUT_DIR
Build seven editable actors. Each animation timeline has eight bearings and 17 poses per bearing.
Columns are idle, eight march frames, eight action frames. The art uses local -Y forward.
"""
import sys
from math import pi, sin, cos
from pathlib import Path
import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index('--') + 1:]
source, output = (Path(v).resolve() for v in args[:2])
actors = args[2:] or ['legion', 'archer', 'cavalry', 'spear', 'guard', 'medic', 'siege']

def mount(obj, name, position, parent, mat):
    obj.name = name
    obj.parent = parent
    obj.location = position
    obj.data.materials.append(mat)
    return obj

def box(name, pos, size, parent, mat):
    bpy.ops.mesh.primitive_cube_add(size=1)
    obj = mount(bpy.context.object, name, pos, parent, mat)
    obj.scale = size
    return obj

def oval(name, pos, size, parent, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6)
    obj = mount(bpy.context.object, name, pos, parent, mat)
    obj.scale = size
    return obj

def joint(name, pos, parent):
    obj = bpy.data.objects.new(name, None)
    scene.collection.objects.link(obj)
    obj.parent = parent
    obj.location = pos
    obj.empty_display_size = .06
    return obj

def rod(name, a, b, radius, parent, mat, tip=None):
    a, b = Vector(a), Vector(b)
    bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=radius, radius2=radius if tip is None else tip, depth=(b-a).length)
    obj = mount(bpy.context.object, name, (a+b)*.5, parent, mat)
    obj.rotation_euler = (b-a).to_track_quat('Z','Y').to_euler()
    return obj

def remove(obj):
    for child in list(obj.children):
        remove(child)
    bpy.data.objects.remove(obj, do_unlink=True)

def wheel(pos, radius, parent):
    hub = joint('Wheel axle', pos, parent)
    ring = [(0, radius*cos(i*pi/6), radius*sin(i*pi/6)) for i in range(12)]
    for i, point in enumerate(ring):
        rod('Wooden felloe', point, ring[(i+1)%12], .043, hub, leather)
        if i%2==0:
            rod('Spoke', (0,0,0), point, .028, hub, gold)
    rod('Axle cap',(-.07,0,0),(.07,0,0),.087,hub,steel)
    return hub

for actor_name in actors:
    goblin=actor_name.startswith('goblin_')
    kind={'goblin_runt':'goblin_club','goblin_brat':'legion','goblin_spiker':'spear','goblin_stabber':'legion','goblin_archer':'archer','goblin_wolf_rider':'cavalry','goblin_wolf_skirmisher':'mounted_archer','goblin_troll':'goblin_club'}.get(actor_name,actor_name)
    bpy.ops.wm.open_mainfile(filepath=str(source))
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    O=bpy.data.objects
    root=O['Bearing']; hips=O['Pelvis']; head=O['Head / chin']
    arms=[O['Shoulder'],O['Shoulder.001']]
    elbows=[O['Elbow'], O['Elbow.001']]
    hands=[O['Grip'],O['Grip.001']]
    shield=O['Scutum / left']; sword=O['Gladius / right']
    red,steel,leather,gold,skin=(bpy.data.materials[x] for x in ['Madder • scutum','Iron • cool','Oiled leather','Old brass','Skin'])
    # Read the approved march before replacing the timeline. All equipment follows its grip.
    pose_nodes=[o for o in O if o.animation_data and o!=root]
    poses=[]
    for f in range(1,9):
        scene.frame_set(f)
        poses.append([(o, o.location.copy(),o.rotation_euler.copy()) for o in pose_nodes])
    for o in list(O):
        if o.animation_data: o.animation_data_clear()
    if kind not in ('legion','guard','cavalry','noble_son','knight','draugr','death_rider'): remove(shield)
    if kind not in ('legion','guard','noble_son','draugr'): remove(sword)
    if kind in ('archer','mounted_archer','medic'):
        if O.get('Short crest'):remove(O['Short crest'])
        for o in hips.children:
            if o.name.startswith(('Segmented','Linen and')):o.data.materials[0]=red if kind in ('archer','mounted_archer','skeleton_archer') else steel
    if goblin:
        skin=skin.copy();skin.name='Goblin green'
        def linear_hex(h):
            values=[int(h[i:i+2],16)/255 for i in (0,2,4)]
            return tuple(((x+.055)/1.055)**2.4 if x>.04045 else x/12.92 for x in values)+(1,)
        for node in skin.node_tree.nodes:
            if node.type=='VALTORGB':
                for stop,h in zip(node.color_ramp.elements,['293c2b','526844','869864']):stop.color=linear_hex(h)
        for obj in list(O):
            if obj.type=='MESH' and obj.data.materials and obj.data.materials[0].name=='Skin':obj.data.materials[0]=skin
        for name in ['Short crest','Galea bowl','Brow ridge','Nape guard','Cheek plate','Cheek plate.001']:
            if O.get(name):remove(O[name])
        if actor_name not in ('goblin_stabber','goblin_troll'):
            for obj in list(O):
                if obj.name.startswith(('Segmented','Shoulder lames','Apron','Strap tip')):obj.hide_render=True
            O['Linen and mail'].data.materials[0]=leather
        head.scale=(1.22,1.2,1.12)
        for x in [-1,1]:rod('Goblin ear',(x*.12,0,.08),(x*.34,.02,.13),.075,head,skin,.002)
        box('Long goblin nose',(0,-.19,.005),(.09,.13,.08),head,skin)
        for x in [-.07,.07]:box('Goblin eye',(x,-.16,.06),(.035,.025,.025),head,gold)
        if kind not in ('cavalry','mounted_archer'):
            body_scale=1. if actor_name=='goblin_troll' else .65 if actor_name in ('goblin_runt','goblin_brat') else .72
            root.scale=(body_scale,)*3
        if actor_name=='goblin_troll':
            hips.scale=(1.3,1.2,1.)
            for obj in list(O):
                if obj.name.startswith(('Upper arm','Forearm','Thigh','Calf')):obj.scale.x*=1.4;obj.scale.y*=1.4
        if kind=='goblin_club':
            weapon=joint('Knotted club',(0,0,0),hands[0])
            if actor_name=='goblin_troll':weapon.scale=(.65,.65,.65)
            rod('Club handle',(0,0,-.18),(0,0,.45),.05,weapon,leather)
            oval('Club head',(0,0,.50),(.12,.11,.25),weapon,leather)
            for z in [.38,.54]:rod('Club knot',(-.13,0,z),(.13,0,z),.04,weapon,gold)
        elif kind=='goblin_slinger':
            weapon=joint('Sling',(0,0,0),hands[0])
            for x in [-.055,.055]:rod('Sling thong',(x,0,0),(x,-.32,.30),.018,weapon,leather)
            oval('Sling pouch',(0,-.32,.30),(.075,.04,.035),weapon,leather)
            oval('Sling stone',(0,-.32,.33),(.05,.05,.045),weapon,steel)
        elif kind=='goblin_shaman':
            weapon=joint('Crooked staff',(0,0,0),hands[0])
            rod('Staff',(0,0,-.5),(0,0,.8),.045,weapon,leather)
            rod('Staff bend',(0,0,.8),(.16,0,.95),.05,weapon,leather)
            oval('Staff charm',(.16,0,.98),(.11,.08,.12),weapon,skin)
            box('Shaman sash',(0,-.15,.20),(.10,.04,.48),hips,red)
    if kind in ('draugr','gravewalker','skeleton_archer','skeleton_spearman','death_rider'):
        remove(O['Short crest'])
        # An independently built bony rig and ragged team cloth keep the existing palette.
        bone=steel.copy();bone.name='Old bone'
        for node in bone.node_tree.nodes:
            if node.type=='VALTORGB':
                for stop,color in zip(node.color_ramp.elements,[(.16,.10,.055,1),(.55,.47,.28,1),(.72,.75,.67,1)]):stop.color=color
        for obj in list(O):
            if obj.type=='MESH' and obj.data.materials and obj.data.materials[0]==skin:obj.data.materials[0]=bone
        if kind in ('skeleton_archer','skeleton_spearman','death_rider'):
            for obj in list(O):
                if obj.name.startswith(('Segmented','Linen and','Tunic hem','Apron','Strap tip','Shoulder lames','Sandal straps','Wrist wrap','Cingulum','Belt plate')):obj.hide_render=True
                if obj.name.startswith(('Upper arm','Forearm','Thigh','Calf')):obj.scale.x*=.48;obj.scale.y*=.48
            rod('Spine',(0,0,.02),(0,0,.51),.035,hips,bone)
            for z in [.17,.27,.37,.47]:
                oval('Rib left',(-.09,-.02,z),(.13,.11,.027),hips,bone)
                oval('Rib right',(.09,-.02,z),(.13,.11,.027),hips,bone)
            for x in [-.06,.06]:box('Empty eye socket',(x,-.151,.035),(.055,.035,.05),head,leather)
            box('Jaw',(0,-.125,-.09),(.16,.045,.045),head,bone)
            box('Team tabard front',(0,-.145,.16),(.14,.035,.46),hips,red)
            box('Team tabard back',(0,.15,.16),(.14,.035,.46),hips,red)
        if kind=='gravewalker':
            for name in ['Galea bowl','Brow ridge','Nape guard','Cheek plate','Cheek plate.001','Shoulder lames','Shoulder lames.001']:remove(O[name])
            for obj in list(O):
                if obj.name.startswith(('Segmented','Apron','Strap tip')):obj.hide_render=True
            O['Linen and mail'].data.materials[0]=leather
            O['Tunic hem'].data.materials[0]=red
    if kind=='wraith':
        # Own low-poly hood and ragged robe, animated on the existing actor rig.
        for obj in list(O):
            if obj.type=='MESH':obj.hide_render=True
        bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=.31, radius2=.20, depth=1.10)
        mount(bpy.context.object,'Spectral robe',(0,0,-.23),hips,steel)
        dark=bpy.data.materials.new('Wraith hood charcoal');dark.use_nodes=True
        dark.node_tree.nodes.clear()
        emission=dark.node_tree.nodes.new('ShaderNodeEmission');emission.inputs['Color'].default_value=(.024,.019,.017,1)
        material_out=dark.node_tree.nodes.new('ShaderNodeOutputMaterial')
        dark.node_tree.links.new(emission.outputs[0],material_out.inputs['Surface'])
        oval('Hood',(0,0,0),(.19,.17,.23),head,dark)
        oval('Hood shadow',(0,-.14,0),(.12,.05,.15),head,dark)
        box('Mask',(0,-.185,-.03),(.12,.025,.10),head,steel)
        for x in [-.045,.045]:box('Eye',(x,-.205,.025),(.025,.02,.022),head,gold)
        box('Team sash front',(0,-.29,-.20),(.075,.035,.72),hips,red)
        box('Team sash back',(0,.29,-.20),(.075,.035,.72),hips,red)
        for x in [-.29,.29]:box('Team sash side',(x,0,-.20),(.035,.075,.72),hips,red)
        for hand in hands:oval('Bone hand',(0,0,0),(.055,.055,.075),hand,steel)
        weapon=joint('Scythe',(0,0,0),hands[0])
        rod('Scythe shaft',(0,0,-.55),(0,0,.95),.035,weapon,leather)
        rod('Scythe heel',(0,0,.95),(0,-.22,1.0),.06,weapon,steel,.04)
        rod('Scythe blade',(0,-.22,1.0),(0,-.58,.78),.05,weapon,steel,.002)
        weapon.scale=(.72,.72,.72)
    if kind=='guard':
        shield.scale=(1.23,1.1,1.14)
        box('Transverse brass bar',(0,-.125,.27),(.52,.035,.06),shield,gold)
        box('Transverse brass bar',(0,-.125,-.27),(.52,.035,.06),shield,gold)
        O['Short crest'].scale.x=2.9
    if kind in ('spear','cavalry','veteran_spearman','knight','skeleton_spearman','death_rider'):
        weapon=joint('Hasta', (0,0,0), hands[0])
        rod('Ash shaft',(0,0,-.54),(0,0,1.15),.032,weapon,leather)
        rod('Leaf point',(0,0,1.15),(0,0,1.42),.067,weapon,steel,.003)
        if kind in ('spear','veteran_spearman','skeleton_spearman'):
            # Smaller round auxiliary shield keeps the projecting spear legible.
            buckler=oval('Clipeus',(.02,-.06,0),(.27,.075,.33),hands[1],red)
            buckler.rotation_euler.x=.94
        else: shield.scale=(.58,.75,.65)
    if kind in ('archer','mounted_archer','skeleton_archer'):
        bow=joint('Bow grip',(0,0,0),hands[1])
        limbs=[(0,.14,-.65),(0,-.014,-.51),(0,-.11,-.29),(0,-.08,0),(0,-.11,.29),(0,-.014,.51),(0,.14,.65)]
        for i in range(len(limbs)-1):rod('Bow stave',limbs[i],limbs[i+1],.034,bow,leather)
        strings=[rod('Bowstring',limbs[idx],(0,.16,0),.011,bow,gold) for idx in (0,-1)]
        quiver=rod('Quiver',(-.13,.18,.09),(.16,.21,.56),.075,hips,leather)
        for i in range(3):
            rod('Fletched shaft',(.12+i*.026,.2,.44),(.22+i*.026,.21,.68),.02,hips,gold)
    if kind=='noble_son':
        shield.scale=(.83,.9,.9)
        O['Short crest'].scale.x=1.65
        box('Officer shield stripe',(0,-.13,0),(.075,.03,.62),shield,gold)
    if kind=='veteran_spearman':
        box('Veteran shoulder clasp',(.19,-.08,.40),(.12,.055,.08),hips,gold)
        O['Short crest'].scale.x=1.65
    if kind=='heavy':
        weapon=joint('Two handed axe',(0,0,0),hands[0]);weapon.scale=(.88,.88,.72)
        rod('Axe haft',(0,0,-.42),(0,0,.68),.042,weapon,leather)
        box('Axe head',(.09,0,.61),(.39,.11,.24),weapon,steel)
        box('Axe cutting edge',(.29,0,.61),(.055,.12,.30),weapon,steel)
        O['Shoulder lames'].scale*=1.16
        O['Shoulder lames.001'].scale*=1.16
    if kind=='peasant':
        for name in ['Short crest','Galea bowl','Brow ridge','Nape guard','Cheek plate','Cheek plate.001','Shoulder lames','Shoulder lames.001']:
            remove(O[name])
        for o in list(hips.children):
            if o.name.startswith('Segmented'):remove(o)
        O['Linen and mail'].data.materials[0]=red
        weapon=joint('Pitchfork',(0,0,0),hands[0]);weapon.scale=(.95,.95,.72)
        rod('Fork handle',(0,0,-.50),(0,0,.46),.035,weapon,leather)
        rod('Fork crosspiece',(-.16,0,.46),(.16,0,.46),.027,weapon,steel)
        for x in [-.16,0,.16]:rod('Fork tine',(x,0,.46),(x,0,.73),.023,weapon,steel,.005)
    if kind=='crossbow':
        remove(O['Short crest'])
        weapon=joint('Crossbow',(0,0,0),hands[1])
        box('Crossbow stock',(0,-.12,0),(.085,.67,.09),weapon,leather)
        rod('Steel prod',(-.36,-.33,0),(.36,-.33,0),.035,weapon,steel)
        for x in [-.36,.36]:rod('Crossbow string',(x,-.33,0),(0,-.04,.015),.012,weapon,gold)
        rod('Bolt',(0,-.05,.065),(0,-.58,.065),.018,weapon,gold)
    if kind=='medic':
        bag=box('Linen satchel',(.16,-.15,-.01),(.25,.17,.25),hips,leather)
        box('Linen flap',(0,-.51,.26),(.98,.10,.35),bag,steel)
        rod('Cross-body strap',(-.16,-.12,.49),(.18,-.16,.06),.026,hips,leather)
        box('Rolled bandage',(0,-.025,-.02),(.11,.11,.17),hands[0],steel)
        box('Linen cap',(0,0,.20),(.19,.19,.085),head,steel)
    horse_legs=[]; wheels=[]
    if kind in ('cavalry','mounted_archer','knight','death_rider'):
        horse=joint('Mount',(0,0,0),root)
        oval('Barrel',(0,.05,1.12),(.34,.76,.34),horse,leather)
        oval('Rump',(0,.56,1.17),(.33,.40,.33),horse,leather)
        neck=oval('Neck',(0,-.56,1.43),(.21,.27,.50),horse,leather);neck.rotation_euler.x=.55
        skull=oval('Horse head',(0,-.93,1.67),(.17,.31,.21),horse,leather);skull.rotation_euler.x=.25
        oval('Muzzle',(0,-1.16,1.54),(.137,.19,.12),horse,leather)
        for sign in (-1,1):
            rod('Ear',(sign*.09,-.83,1.80),(sign*.12,-.79,2.02),.05,horse,leather,.012)
            oval('Bridle stud',(sign*.158,-1.00,1.72),(.019,.035,.032),horse,gold)
        rod('Mane',(0,-.42,1.43),(0,-.78,1.87),.105,horse,leather,.055)
        rod('Tail',(0,.84,1.26),(0,1.06,.49),.105,horse,leather,.06)
        oval('Saddle cloth',(0,.10,1.38),(.37,.37,.14),horse,red)
        for sign in (-1,1):
            for y in (-.47,.50):
                hip=joint('Horse leg',(sign*.215,y,1.10),horse)
                rod('Upper leg',(0,0,0),(0,.045,-.54),.112,hip,leather,.07)
                hock=joint('Pastern',(0,.045,-.54),hip)
                rod('Shin',(0,0,0),(0,-.04,-.45),.069,hock,leather,.045)
                box('Hoof',(0,-.062,-.47),(.116,.16,.09),hock,steel)
                horse_legs.append((hip,hock))
    if goblin and kind in ('cavalry','mounted_archer'):
        horse.scale=(.82,.90,.78)
        fur=leather.copy();fur.name='Wolf grey'
        for node in fur.node_tree.nodes:
            if node.type=='VALTORGB':
                for stop,h in zip(node.color_ramp.elements,['2b2523','344957','879da6']):stop.color=linear_hex(h)
        for obj in list(horse.children_recursive):
            if obj.type=='MESH' and obj.data.materials and obj.data.materials[0]==leather:obj.data.materials[0]=fur
            if obj.name.startswith(('Neck','Horse head','Muzzle','Ear','Bridle stud','Mane','Tail')):obj.hide_render=True
        oval('Wolf neck',(0,-.56,1.20),(.23,.30,.27),horse,fur)
        oval('Wolf skull',(0,-.88,1.28),(.18,.26,.19),horse,fur)
        oval('Wolf snout',(0,-1.13,1.20),(.12,.22,.11),horse,fur)
        rod('Wolf tail',(0,.74,1.19),(0,1.14,1.45),.11,horse,fur,.035)
        for x in [-1,1]:
            rod('Wolf pointed ear',(x*.12,-.72,1.38),(x*.15,-.69,1.66),.08,horse,fur,.003)
            box('Wolf eye',(x*.167,-.94,1.35),(.025,.05,.035),horse,gold)
            rod('Wolf fang',(x*.08,-1.19,1.14),(x*.08,-1.19,1.02),.025,horse,steel,.002)
        hips.scale=(.65,.65,.65)
    if kind=='death_rider':
        for obj in list(horse.children_recursive):
            if obj.type=='MESH' and obj.data.materials and obj.data.materials[0]==leather:obj.data.materials[0]=bone
            if obj.name.startswith(('Upper leg','Shin')):obj.scale.x*=.6;obj.scale.y*=.6
        for name in ['Barrel','Rump','Mane']:O[name].hide_render=True
        rod('Horse spine',(0,-.45,1.25),(0,.76,1.25),.055,horse,bone)
        for y in [-.38,-.16,.06,.28,.50]:
            for x in [-1,1]:rod('Horse rib',(0,y,1.3),(x*.27,y,1.0),.04,horse,bone)
        for x in [-1,1]:rod('Pelvis bone',(0,.62,1.25),(x*.26,.62,1.08),.055,horse,bone)
    if kind=='knight':
        oval('Horse chamfron',(0,-.99,1.79),(.18,.23,.055),horse,steel)
        box('Armored saddle trim',(0,.10,1.49),(.62,.50,.045),horse,gold)
        O['Short crest'].scale.x=1.65
    hound_parts=[]
    if kind=='fell_hound':
        for obj in list(O):
            if obj.type=='MESH':obj.hide_render=True
        hound=joint('Hound body',(0,0,.49),root)
        oval('Lean torso',(0,.07,0),(.18,.49,.19),hound,leather)
        oval('Haunch',(0,.36,.01),(.20,.23,.20),hound,leather)
        hound_head=joint('Hound neck',(0,-.44,.13),hound)
        oval('Hound skull',(0,-.08,.02),(.13,.21,.14),hound_head,leather)
        oval('Snout',(0,-.27,-.045),(.09,.15,.085),hound_head,leather)
        for x in [-1,1]:
            rod('Pointed ear',(x*.095,0,.08),(x*.12,.04,.26),.065,hound_head,leather,.005)
            box('Pale eye',(x*.114,-.16,.065),(.035,.055,.035),hound_head,steel)
            rod('Fang',(x*.065,-.29,-.075),(x*.065,-.29,-.16),.024,hound_head,steel,.002)
        box('Team collar',(0,-.39,.03),(.39,.12,.14),hound,red)
        tail=rod('Raised tail',(0,.45,.08),(0,.78,.28),.07,hound,leather,.015)
        hound_legs=[]
        for x in [-1,1]:
            for y in [-.28,.32]:
                leg=joint('Hound leg',(x*.14,y,-.03),hound)
                rod('Hound thigh',(0,0,0),(0,.07,-.21),.055,leg,leather,.035)
                paw=joint('Hound ankle',(0,.07,-.21),leg)
                rod('Hound shin',(0,0,0),(0,-.07,-.20),.032,paw,leather,.025)
                box('Paw',(0,-.09,-.20),(.09,.15,.07),paw,leather)
                hound_legs.append((leg,paw))
        hound_parts=[hound,hound_head,tail]+[o for pair in hound_legs for o in pair]
    dragon_parts=[]
    if kind=='dragon':
        for obj in list(O):
            if obj.type=='MESH':obj.hide_render=True
        scales=skin.copy();scales.name='Dragon scales'
        for node in scales.node_tree.nodes:
            if node.type=='VALTORGB':
                for stop,h in zip(node.color_ramp.elements,['293c2b','526844','869864']):
                    rgb=[int(h[i:i+2],16)/255 for i in (0,2,4)]
                    stop.color=tuple(((v+.055)/1.055)**2.4 if v>.04045 else v/12.92 for v in rgb)+(1,)
        dragon=joint('Dragon torso',(0,0,1.15),root)
        oval('Scaled chest',(0,-.08,0),(.39,.76,.35),dragon,scales)
        oval('Belly plates',(0,-.10,-.21),(.27,.60,.18),dragon,gold)
        neck=joint('Dragon neck',(0,-.66,.16),dragon)
        oval('Raised neck',(0,-.15,.11),(.20,.31,.25),neck,scales)
        oval('Dragon skull',(0,-.40,.20),(.22,.27,.19),neck,scales)
        oval('Long muzzle',(0,-.63,.13),(.16,.24,.12),neck,scales)
        jaw=joint('Jaw hinge',(0,-.36,.06),neck)
        oval('Lower jaw',(0,-.24,-.035),(.14,.30,.055),jaw,gold)
        for x in [-1,1]:
            rod('Swept horn',(x*.15,-.29,.31),(x*.26,-.02,.60),.07,neck,gold,.008)
            box('Amber eye',(x*.195,-.49,.25),(.04,.09,.055),neck,gold)
            rod('Tooth',(x*.13,-.66,.07),(x*.13,-.66,-.045),.024,neck,steel,.002)
        tail=joint('Tail root',(0,.53,.04),dragon)
        points=[(0,0,0),(0,.39,-.05),(.08,.75,-.11),(.22,1.08,.02),(.30,1.36,.18)]
        for i in range(len(points)-1):rod('Tapered tail',points[i],points[i+1],.18-i*.04,tail,scales,max(.012,.14-i*.04))
        for y in [-.35,-.05,.25,.55]:rod('Back spine',(0,y,.28),(0,y+.08,.52),.075,dragon,gold,.003)
        dragon_wings=[]
        for sign in [-1,1]:
            wing=joint('Wing shoulder',(sign*.27,-.15,.22),dragon)
            verts=[(0,0,0),(sign*.70,-.35,.30),(sign*1.66,-.15,.12),(sign*1.22,.35,0),(sign*.90,.69,-.06),(sign*.34,.61,-.12)]
            mesh=bpy.data.meshes.new('Wing membrane');mesh.from_pydata(verts,[],[(0,1,2),(0,2,3),(0,3,4),(0,4,5)]);mesh.update()
            membrane=bpy.data.objects.new('Team wing membrane',mesh);scene.collection.objects.link(membrane);mount(membrane,membrane.name,(0,0,0),wing,red)
            for i in [1,2,3,4,5]:rod('Wing finger',verts[0],verts[i],.028,wing,scales,.014)
            dragon_wings.append(wing)
        dragon_legs=[]
        for x in [-1,1]:
            for y in [-.42,.43]:
                leg=joint('Dragon leg',(x*.29,y,-.10),dragon)
                rod('Upper leg',(0,0,0),(x*.09,.10,-.36),.10,leg,scales,.07)
                rod('Lower leg',(x*.09,.10,-.36),(x*.09,-.03,-.78),.065,leg,scales,.045)
                for claw in [-1,0,1]:rod('Claw',(x*.09+claw*.045,-.03,-.78),(x*.09+claw*.055,-.20,-.82),.024,leg,gold,.002)
                dragon_legs.append(leg)
        dragon_parts=[dragon,neck,jaw,tail]+dragon_wings+dragon_legs
        size=5.2;scene.camera.data.ortho_scale=size;scene.camera.location.z+=(size/2.60-1)*.917
    if kind=='siege':
        remove(hips); pose_nodes=[]; poses=[[]]*8
        chassis=joint('Onager chassis',(0,0,0),root)
        for x in (-.43,.43):
            box('Side beam',(x,0,.44),(.16,1.7,.20),chassis,leather)
            rod('A-frame',(x,-.68,.5),(x,-.08,1.37),.078,chassis,leather)
            rod('A-frame',(x,.57,.50),(x,-.08,1.37),.078,chassis,leather)
            for y in (-.58,.58):wheels.append(wheel((x*1.38,y,.32),.28,chassis))
        for y in (-.65,0,.62):box('Cross member',(0,y,.48),(.99,.14,.16),chassis,leather)
        box('Padded stop',(0,-.08,1.34),(1.05,.17,.15),chassis,red)
        spindle=rod('Torsion skein',(-.52,.04,.57),(.52,.04,.57),.147,chassis,gold)
        beam=joint('Throwing arm',(0,.04,.57),chassis)
        rod('Arm',(0,0,0),(0,0,1.19),.083,beam,leather,.061)
        oval('Spoon',(0,0,1.23),(.19,.21,.12),beam,gold)
        rock=oval('Shot',(0,0,1.34),(.14,.14,.14),beam,steel)
    if kind in ('spear','cavalry','mounted_archer','siege','veteran_spearman','knight','skeleton_spearman','death_rider'):
        size={'spear':4.0,'cavalry':4.05,'mounted_archer':4.05,'siege':3.12,'veteran_spearman':4.0,'knight':4.05,'skeleton_spearman':4.0,'death_rider':4.05}[kind]
        scene.camera.data.ortho_scale=size
        scene.camera.location.z+=(size/2.60-1)*.917
    scene.frame_end=136
    for direction in range(8):
        for col in range(17):
            frame=direction*17+col+1; walk=1<=col<=8; attack=col>=9
            phase=(col-1)%8 if walk else 0
            for o,loc,rot in poses[phase]:
                o.location=loc; o.rotation_euler=rot
            root.rotation_euler.z=direction*pi/4
            if kind!='siege':
                if not walk:
                    for name in ('Hip joint','Knee','Ankle','Hip joint.001','Knee.001','Ankle.001'):
                        O[name].rotation_euler.x=0
                    hips.location.z=.94; arms[0].rotation_euler.x=arms[1].rotation_euler.x=0
                action=[0,.16,.50,1,.86,.48,.16,0][(col-9)%8] if attack else 0
                elbows[0].rotation_euler.x=-.85
                if kind in ('legion','guard','noble_son','draugr'):
                    arms[0].rotation_euler.x-=1.22*action; elbows[0].rotation_euler.x+=.55*action
                    sword.rotation_euler.x=2.21-.51*action
                elif kind in ('spear','cavalry','veteran_spearman','knight','skeleton_spearman','death_rider'):
                    arms[0].rotation_euler.x-=.98*action
                    weapon.rotation_euler.x=1.30+.84*action
                elif kind in ('archer','mounted_archer','skeleton_archer'):
                    draw=[0,.35,.72,1,1,.05,.03,0][(col-9)%8] if attack else 0
                    arms[1].rotation_euler.x-=1.02*draw
                    arms[0].rotation_euler.x-=.76*draw; elbows[0].rotation_euler.x-=1.10*draw
                    bow.rotation_euler.x=.94-arms[1].rotation_euler.x
                    for string,idx in zip(strings,(0,-1)):
                        a=Vector(limbs[idx]); b=Vector((0,.15+.48*draw,0))
                        string.location=(a+b)*.5; string.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
                        string.scale.z=(b-a).length/.65
                elif kind=='goblin_club':
                    arms[0].rotation_euler.x-=1.1*action
                    weapon.rotation_euler.x=.4+1.5*action
                elif kind=='goblin_slinger':
                    arms[0].rotation_euler.x=-.9-.7*action
                    weapon.rotation_euler.z=(col-9)*pi/3 if attack else 0
                    weapon.rotation_euler.x=.4
                elif kind=='goblin_shaman':
                    arms[0].rotation_euler.x=-.3-.6*action
                    arms[1].rotation_euler.x=-.9*action
                    weapon.rotation_euler.x=.4
                elif kind=='gravewalker':
                    for i in range(2):
                        arms[i].rotation_euler.x=-1.10-.5*action
                        elbows[i].rotation_euler.x=-.25
                    hips.rotation_euler.x=.14
                elif kind=='fell_hound':
                    hound.location.z=.49+(.025*cos(phase*pi/2) if walk else 0)
                    hound_head.rotation_euler.x=-.30*action
                    hound.location.y=-.09*action
                    for j,(leg,paw) in enumerate(hound_legs):
                        a=(phase/8+[0,.5,.5,0][j])*2*pi
                        leg.rotation_euler.x=.65*sin(a) if walk else -.08
                        paw.rotation_euler.x=.4*max(0,cos(a)) if walk else 0
                elif kind=='dragon':
                    t=phase*pi/4
                    dragon.location.z=1.15+(.06*cos(2*t) if walk else 0)
                    neck.location.y=-.66-.20*action;neck.rotation_euler.x=-.25*action
                    jaw.rotation_euler.x=.65*action
                    tail.rotation_euler.z=.14*sin(t) if walk else .05*action
                    for j,wing in enumerate(dragon_wings):wing.rotation_euler.y=(-1 if j==0 else 1)*(.18+(.43*sin(t) if walk else .25*action))
                    for j,leg in enumerate(dragon_legs):leg.rotation_euler.x=.35*sin(t+(j%2)*pi) if walk else 0
                elif kind=='wraith':
                    arms[0].rotation_euler.x-=.60*action
                    weapon.rotation_euler.x=1.15+.50*action
                elif kind in ('heavy','peasant'):
                    arms[0].rotation_euler.x-=1.05*action
                    arms[1].rotation_euler.x-=.72*action
                    elbows[1].rotation_euler.x=-.8
                    weapon.rotation_euler.x=.60+1.12*action
                elif kind=='crossbow':
                    aim=[0,.4,.85,1,1,.8,.35,0][(col-9)%8] if attack else .2
                    arms[1].rotation_euler.x-=1.0*aim
                    arms[0].rotation_euler.x-=.8*aim
                    elbows[0].rotation_euler.x=-1.1
                    bpy.context.view_layer.update()
                    weapon.rotation_euler=(weapon.parent.matrix_world.to_quaternion().inverted() @ root.matrix_world.to_quaternion()).to_euler()
                elif kind=='medic':
                    arms[0].rotation_euler.x-=.98*action;arms[1].rotation_euler.x-=.69*action
                    hips.rotation_euler.x=.16*action
                if kind in ('cavalry','mounted_archer','knight','death_rider'):
                    hips.location=(0,.15,1.44+.038*cos(phase*pi/2) if walk else 1.44)
                    if goblin:hips.location.z=1.08+(.025*cos(phase*pi/2) if walk else 0)
                    for i in range(2):
                        suffix='' if i==0 else '.001'
                        O['Hip joint'+suffix].rotation_euler=(-.82,(-1 if i==0 else 1)*-.37,0)
                        O['Knee'+suffix].rotation_euler.x=1.04
                        O['Ankle'+suffix].rotation_euler.x=-.21
                    for j,(leg,hock) in enumerate(horse_legs):
                        t=(phase/8+([0,.5,.5,0][j]))*2*pi
                        leg.rotation_euler.x=.51*sin(t) if walk else 0
                        hock.rotation_euler.x=.46*max(0,cos(t)) if walk else 0
            else:
                beam.rotation_euler.x=([-1.03,-1.15,-1.22,-.54,.24,.27,-.20,-.76][col-9] if attack else -.76)
                # Aft at rest, forward at release.
                rock.scale=(.14,.14,.14) if not attack or col<12 or col>=16 else (.001,)*3
                for w in wheels:w.rotation_euler.x=-phase*pi/12
            # Key only parts whose pose changes. Mesh materials and camera are static.
            moving=[root]
            if kind!='siege':
                moving += pose_nodes+elbows+hound_parts+dragon_parts
                if kind in ('legion','guard','noble_son','draugr'):moving+=[sword]
                if kind in ('spear','cavalry','veteran_spearman','knight','heavy','peasant','crossbow','wraith','skeleton_spearman','death_rider','goblin_club','goblin_slinger','goblin_shaman'):moving+=[weapon]
                if kind in ('archer','mounted_archer','skeleton_archer'):moving += [bow]+strings
                if kind in ('cavalry','mounted_archer','knight','death_rider'):moving += [o for pair in horse_legs for o in pair]
            else:moving += [beam,rock]+wheels
            for o in moving:
                for prop in ('location','rotation_euler','scale'):o.keyframe_insert(data_path=prop,frame=frame)
    scene.frame_set(1);scene.render.fps=10
    out=output/actor_name;out.mkdir(parents=True,exist_ok=True)
    scene.render.filepath='//frames/'+actor_name+'-'
    bpy.ops.wm.save_as_mainfile(filepath=str(out.parent/(actor_name+'.blend')))
    scene.render.filepath=str(out/'pose-')
    bpy.ops.render.render(animation=True)
