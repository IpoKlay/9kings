"""Blender --background --python render_armies.py -- SHIELD.blend OUTPUT_DIR
Build seven editable actors. Each animation timeline has eight bearings and 17 poses per bearing.
Columns are idle, eight march frames, eight action frames. The art uses local -Y forward.
"""
import sys
from math import pi, sin, cos
from pathlib import Path
import bpy
from mathutils import Vector

source, output = (Path(v).resolve() for v in sys.argv[sys.argv.index('--') + 1:])
actors = ['legion', 'archer', 'cavalry', 'spear', 'guard', 'medic', 'siege']

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

for kind in actors:
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
    if kind not in ('legion','guard','cavalry'): remove(shield)
    if kind not in ('legion','guard'): remove(sword)
    if kind in ('archer','medic'): 
        remove(O['Short crest'])
        for o in hips.children:
            if o.name.startswith(('Segmented','Linen and')):o.data.materials[0]=red if kind=='archer' else steel
    if kind=='guard':
        shield.scale=(1.23,1.1,1.14)
        box('Transverse brass bar',(0,-.125,.27),(.52,.035,.06),shield,gold)
        box('Transverse brass bar',(0,-.125,-.27),(.52,.035,.06),shield,gold)
        O['Short crest'].scale.x=2.9
    if kind in ('spear','cavalry'):
        weapon=joint('Hasta', (0,0,0), hands[0])
        rod('Ash shaft',(0,0,-.54),(0,0,1.15),.032,weapon,leather)
        rod('Leaf point',(0,0,1.15),(0,0,1.42),.067,weapon,steel,.003)
        if kind=='spear':
            # Smaller round auxiliary shield keeps the projecting spear legible.
            buckler=oval('Clipeus',(.02,-.06,0),(.27,.075,.33),hands[1],red)
            buckler.rotation_euler.x=.94
        else: shield.scale=(.58,.75,.65)
    if kind=='archer':
        bow=joint('Bow grip',(0,0,0),hands[1])
        limbs=[(0,.14,-.65),(0,-.014,-.51),(0,-.11,-.29),(0,-.08,0),(0,-.11,.29),(0,-.014,.51),(0,.14,.65)]
        for i in range(len(limbs)-1):rod('Bow stave',limbs[i],limbs[i+1],.034,bow,leather)
        strings=[rod('Bowstring',limbs[idx],(0,.16,0),.011,bow,gold) for idx in (0,-1)]
        quiver=rod('Quiver',(-.13,.18,.09),(.16,.21,.56),.075,hips,leather)
        for i in range(3):
            rod('Fletched shaft',(.12+i*.026,.2,.44),(.22+i*.026,.21,.68),.02,hips,gold)
    if kind=='medic':
        bag=box('Linen satchel',(.16,-.15,-.01),(.25,.17,.25),hips,leather)
        box('Linen flap',(0,-.51,.26),(.98,.10,.35),bag,steel)
        rod('Cross-body strap',(-.16,-.12,.49),(.18,-.16,.06),.026,hips,leather)
        box('Rolled bandage',(0,-.025,-.02),(.11,.11,.17),hands[0],steel)
        box('Linen cap',(0,0,.20),(.19,.19,.085),head,steel)
    horse_legs=[]; wheels=[]
    if kind=='cavalry':
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
    if kind in ('spear','cavalry','siege'):
        size={'spear':4.0,'cavalry':4.05,'siege':3.12}[kind]
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
                if kind in ('legion','guard'):
                    arms[0].rotation_euler.x-=1.22*action; elbows[0].rotation_euler.x+=.55*action
                    sword.rotation_euler.x=2.21-.51*action
                elif kind in ('spear','cavalry'):
                    arms[0].rotation_euler.x-=.98*action
                    weapon.rotation_euler.x=1.30+.84*action
                elif kind=='archer':
                    draw=[0,.35,.72,1,1,.05,.03,0][(col-9)%8] if attack else 0
                    arms[1].rotation_euler.x-=1.02*draw
                    arms[0].rotation_euler.x-=.76*draw; elbows[0].rotation_euler.x-=1.10*draw
                    bow.rotation_euler.x=.94-arms[1].rotation_euler.x
                    for string,idx in zip(strings,(0,-1)):
                        a=Vector(limbs[idx]); b=Vector((0,.15+.48*draw,0))
                        string.location=(a+b)*.5; string.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
                        string.scale.z=(b-a).length/.65
                elif kind=='medic':
                    arms[0].rotation_euler.x-=.98*action;arms[1].rotation_euler.x-=.69*action
                    hips.rotation_euler.x=.16*action
                if kind=='cavalry':
                    hips.location=(0,.15,1.44+.038*cos(phase*pi/2) if walk else 1.44)
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
                moving += pose_nodes+elbows
                if kind in ('legion','guard'):moving+=[sword]
                if kind in ('spear','cavalry'):moving+=[weapon]
                if kind=='archer':moving += [bow]+strings
                if kind=='cavalry':moving += [o for pair in horse_legs for o in pair]
            else:moving += [beam,rock]+wheels
            for o in moving:
                for prop in ('location','rotation_euler','scale'):o.keyframe_insert(data_path=prop,frame=frame)
    scene.frame_set(1);scene.render.fps=10
    out=output/kind;out.mkdir(parents=True,exist_ok=True)
    scene.render.filepath='//frames/'+kind+'-'
    bpy.ops.wm.save_as_mainfile(filepath=str(out.parent/(kind+'.blend')))
    scene.render.filepath=str(out/'pose-')
    bpy.ops.render.render(animation=True)
