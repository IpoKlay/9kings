"""Run with Blender --background --python this_file -- <repository root>.

Author real limestone/wood geometry and render one orthographic pixel atlas.
Game-ground coordinates are compensated before projection, so the camera does
not compress the existing top-down navigation plane. No source PNG is warped.
"""
import bpy
import math
import json
import sys
from pathlib import Path
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

ROOT = Path(sys.argv[sys.argv.index('--') + 1])
ASSETS = ROOT / 'godot-game/assets/strategy/fortifications'
SOURCE = ROOT / 'art-source/blender'
EVIDENCE = ROOT / 'output/pixellab-art-integration-2026-11-10/blender'
for p in (ASSETS, SOURCE, EVIDENCE):
    p.mkdir(parents=True, exist_ok=True)
ELEVATION = math.radians(60)
SIN = math.sin(ELEVATION)
CELL = 192
ANCHOR = (96, 128)
WIDTH, HEIGHT = CELL * 8, CELL * 6
SHORT = (2 * 448 * (math.sqrt(2) - 1) - 64) / 6
LONG = 2 * 448 * (math.sqrt(2) - 1) / 6

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.name = 'Pixel atlas - all eight directions'
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 1
scene.cycles.use_denoising = False
scene.render.film_transparent = True
scene.render.filter_size = .01
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.image_settings.color_depth = '8'
scene.render.dither_intensity = 0
scene.view_settings.view_transform = 'Standard'
scene.view_settings.look = 'None'
scene.view_settings.exposure = 0
scene.view_settings.gamma = 1

PALETTE = {
    'stone': '#b4aa8c', 'stone_light': '#c6bc9c', 'stone_dark': '#9e967d',
    'mortar': '#706b5c', 'wood': '#695039', 'wood_light': '#937452',
    'iron': '#413e35', 'red': '#81382f', 'gold': '#bb934b',
}
materials = []
material_ids = {}
def linear(v):
    return v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4
for name, color in PALETTE.items():
    rgb = [int(color[i:i+2], 16) / 255 for i in (1, 3, 5)]
    for band, factor in enumerate((.72, .86, 1.0)):
        mat = bpy.data.materials.new(name + '_' + str(band))
        mat.diffuse_color = (*[c * factor for c in rgb], 1)
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        nodes.clear()
        emission = nodes.new('ShaderNodeEmission')
        emission.inputs['Color'].default_value = (*[linear(c * factor) for c in rgb], 1)
        output = nodes.new('ShaderNodeOutputMaterial')
        mat.node_tree.links.new(emission.outputs[0], output.inputs['Surface'])
        material_ids[name, band] = len(materials)
        materials.append(mat)

class Builder:
    def __init__(self, angle=0):
        self.angle = angle
        self.vertices, self.faces, self.colors = [], [], []

    def vertex(self, xyz):
        x, y, z = xyz
        c, s = math.cos(self.angle), math.sin(self.angle)
        return (x * c - y * s, -(x * s + y * c) / SIN, z)

    def solid(self, vertices, faces, color):
        start = len(self.vertices)
        v = [self.vertex(p) for p in vertices]
        self.vertices.extend(v)
        for f in faces:
            a, b, c = [Vector(v[i]) for i in f[:3]]
            normal = (b-a).cross(c-a).normalized()
            light = normal.dot(Vector((-.5, -.4, 1)).normalized())
            band = 2 if light > .38 else 1 if light > -.3 else 0
            self.faces.append(tuple(start + i for i in f))
            self.colors.append(material_ids[color, band])

    def box(self, center, dimensions, color='stone', rotation=0):
        x, y, z = center
        w, d, h = (a / 2 for a in dimensions)
        c, s = math.cos(rotation), math.sin(rotation)
        verts = []
        for dx, dy, dz in [(-w,-d,-h),(w,-d,-h),(w,d,-h),(-w,d,-h),(-w,-d,h),(w,-d,h),(w,d,h),(-w,d,h)]:
            verts.append((x+dx*c-dy*s, y+dx*s+dy*c, z+dz))
        self.solid(verts, [(0,3,2,1),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)], color)

    def object(self, name):
        mesh = bpy.data.meshes.new(name + '_editable_mesh')
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        scene.collection.objects.link(obj)
        for material in materials:
            mesh.materials.append(material)
        for face, color in zip(mesh.polygons, self.colors):
            face.material_index = color
        return obj

def masonry(builder, x, y, width, depth, height, seed=0):
    builder.box((x, y, height/2), (width, depth, height), 'mortar')
    rows = max(1, round(height/7))
    row_height = height/rows
    for row in range(rows):
        z = (row+.5)*row_height
        offset = -6 if row % 2 else 0
        for face in (-1, 1):
            for step in range(-1, math.ceil(width/12)+1):
                left = max(-width/2, -width/2+step*12+offset)
                right = min(width/2, -width/2+(step+1)*12+offset)
                if right-left < .8:
                    continue
                color = ('stone', 'stone_light', 'stone_dark')[(row*7+step*3+seed+face)%3]
                builder.box((x+(left+right)/2, y+face*depth/2, z), (right-left-.5, 1, row_height-.5), color)
    # End faces must be solid too; adjacent modules meet without transparent gaps.
    for face in (-1, 1):
        builder.box((x+face*width/2, y, height/2), (.5,depth,height), 'stone_dark')

def wall(builder, length):
    # One source-pixel overlap absorbs independent pixel rounding at shared sockets.
    length += 1.5
    masonry(builder, 0, 0, length, 34, 44)
    builder.box((0,0,45), (length,34,3), 'stone_light')
    # Walkway, transverse supports and crenellations share endpoint dimensions.
    builder.box((0,0,47), (length,20,2), 'wood')
    count = max(3, round(length/12))
    for i in range(count):
        x = -length/2+(i+.5)*length/count
        for y in (-14,14):
            builder.box((x,y,52), (6,6,10), 'stone_light')
        builder.box((x,0,48), (1,20,1), 'wood_light')
    # Small fittings follow the reference; keep the joining end faces bare.
    builder.box((0,-17.7,29), (9,1,19), 'red')
    builder.box((0,-18.3,32), (6,.5,2), 'gold')
    builder.box((0,-18.3,28), (2,.5,7), 'gold')

def tower(builder, x, width=20, depth=42, height=72):
    masonry(builder,x,0,width,depth,height,seed=2)
    builder.box((x,0,height+1), (width+2,depth+2,3), 'stone_light')
    for side in (-1,1):
        for y in (-depth/2+4,0,depth/2-4):
            builder.box((x+side*(width/2-2),y,height+6), (5,6,10), 'stone_light')
    for y in (-depth/2,depth/2):
        builder.box((x,y,height*.7), (4,1,10), 'iron')

def gate(builder, opened):
    # Towers sit outside +/-32; the 64-unit opening matches the navigation gap.
    tower(builder,-42)
    tower(builder,42)
    for i in range(12):
        a=i*math.pi/12; b=(i+1)*math.pi/12
        verts=[]
        for y in (-8,8):
            for radius, angle in [(32,a),(40,a),(40,b),(32,b)]:
                verts.append((radius*math.cos(angle),y,32+radius*math.sin(angle)))
        builder.solid(verts,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],'stone_light' if i%3 else 'stone')
    for side in (-1,1):
        hinge=side*32
        angle=side*math.pi/2 if opened else 0
        cx=hinge-side*16*math.cos(angle)
        cy=-side*16*math.sin(angle)
        builder.box((cx,cy,18), (32,3,36), 'wood', angle)
        for z in (8,28):
            builder.box((cx,cy-2, z), (32,1,3), 'iron', angle)
        for i in range(4):
            local=-12+i*8
            builder.box((cx+local*math.cos(angle),cy+local*math.sin(angle),18), (1,4,34), 'wood_light',angle)
        builder.box((side*42,-22,42), (10,1,24), 'red')
        builder.box((side*42,-23,44), (7,1,3), 'gold')
        builder.box((side*42,-23,40), (3,1,9), 'gold')

def corner(builder):
    # A compact octagonal joint closes the outer wedge of a 45-degree turn.
    verts=[]
    for z in (0,48):
        for i in range(8):
            a=(i+.5)*math.pi/4
            verts.append((19*math.cos(a),19*math.sin(a),z))
    faces=[tuple(range(7,-1,-1)),tuple(range(8,16))]
    faces += [(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)]
    builder.solid(verts,faces,'stone')
    for i in range(8):
        a=i*math.pi/4
        builder.box((16*math.cos(a),16*math.sin(a),52), (7,6,9), 'stone_light',a)

def camera_for(target_scene, width, height, center):
    camera_data=bpy.data.cameras.new(target_scene.name+'_orthographic_camera')
    camera=bpy.data.objects.new(camera_data.name,camera_data)
    target_scene.collection.objects.link(camera)
    cx,cy=center
    target=Vector((cx,-cy/SIN,0))
    camera.location=target+Vector((0,-1200*math.cos(ELEVATION),1200*SIN))
    camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
    camera_data.type='ORTHO';camera_data.ortho_scale=width;camera_data.sensor_fit='HORIZONTAL'
    camera_data.clip_end=5000
    target_scene.camera=camera
    target_scene.render.resolution_x=width;target_scene.render.resolution_y=height
    target_scene.render.resolution_percentage=100
    bpy.context.view_layer.update()
    return camera

camera=camera_for(scene,WIDTH,HEIGHT,(WIDTH/2,HEIGHT/2))
frames={};objects={};index=0
for kind in ('wall_short','wall_long','wall','gate_open','gate_closed','corner'):
    for direction in range(8):
        angle=direction*math.pi/4
        builder=Builder(angle)
        length=SHORT if kind=='wall_short' else LONG if kind=='wall_long' else 64.
        if kind.startswith('wall'):wall(builder,length)
        elif kind.startswith('gate'):gate(builder,kind=='gate_open')
        else:corner(builder)
        key=kind+'_'+str(direction)
        obj=builder.object(key)
        col,row=index%8,index//8
        origin=(col*CELL+ANCHOR[0],row*CELL+ANCHOR[1])
        obj.location=(origin[0],-origin[1]/SIN,0)
        obj['module_type']=kind;obj['direction_degrees']=direction*45
        obj['socket_left_game']=(-length/2,0,0);obj['socket_right_game']=(length/2,0,0)
        objects[key]=obj
        frames[key]={'region':[col*CELL,row*CELL,CELL,CELL],'anchor':list(ANCHOR),'length':length,'angle':angle}
        index+=1
bpy.context.view_layer.update()
errors=[]
for key,obj in objects.items():
    pixel=world_to_camera_view(scene,camera,obj.location)
    expected=frames[key]['region'][:2]
    error=max(abs(pixel.x*WIDTH-expected[0]-ANCHOR[0]),abs((1-pixel.y)*HEIGHT-expected[1]-ANCHOR[1]))
    errors.append(error)
assert max(errors)<.002, max(errors)
scene.render.filepath=str(ASSETS/'roman-fortifications.png')
bpy.ops.render.render(write_still=True)
manifest={'canvas':[WIDTH,HEIGHT],'cell':CELL,'anchor':list(ANCHOR),'ground_projection':'identity','camera_elevation_degrees':60,'wall_width':34,'wall_height':57,'gate_clearance':64,'source':'art-source/blender/roman-fortifications.blend','frames':frames}
data=ROOT/'godot-game/data/generated/fortifications.json';data.parent.mkdir(parents=True,exist_ok=True)
data.write_text(json.dumps(manifest,indent=2))

# An editable, correctly assembled eight-sided fort in a second Blender scene.
assembly=bpy.data.scenes.new('Assembled octagonal fort - socket validation')
assembly.render.engine='CYCLES';assembly.cycles.samples=1
assembly.render.film_transparent=True;assembly.render.filter_size=.01
assembly.view_settings.view_transform='Standard';assembly.view_settings.look='None'
radius=448;corner_distance=radius*(math.sqrt(2)-1)
points=[(-corner_distance,-radius),(corner_distance,-radius),(radius,-corner_distance),(radius,corner_distance),(corner_distance,radius),(-corner_distance,radius),(-radius,corner_distance),(-radius,-corner_distance)]
sockets=[]
def instance(key,point,name):
    obj=bpy.data.objects.new(name,objects[key].data);assembly.collection.objects.link(obj)
    obj.location=(point[0],-point[1]/SIN,0)
    return obj
for edge in range(8):
    a=Vector(points[edge]);b=Vector(points[(edge+1)%8]);axis=(b-a).normalized()
    count=7 if edge%2==0 else 6;cursor=0.
    for slot in range(count):
        is_gate=edge%2==0 and slot==3
        length=64 if is_gate else SHORT if edge%2==0 else LONG
        key=('gate_open' if is_gate else 'wall_short' if edge%2==0 else 'wall_long')+'_'+str(edge)
        pos=a+axis*(cursor+length/2)
        instance(key,pos,'Edge_%d_slot_%d_%s'%(edge,slot,key))
        sockets.append({'edge':edge,'slot':slot,'start':list(a+axis*cursor),'end':list(a+axis*(cursor+length))})
        cursor+=length
    assert abs(cursor-(b-a).length)<.001
    instance('corner_'+str(edge),a,'Corner_'+str(edge))
assembly_camera=camera_for(assembly,1152,1152,(0,-35))
assembly_camera.data.ortho_scale=1100
assembly.render.image_settings.file_format='PNG';assembly.render.image_settings.color_mode='RGBA'
assembly.render.filepath=str(EVIDENCE/'blender-assembly.png')
bpy.context.window.scene=assembly
bpy.ops.render.render(write_still=True)
for obj in assembly.objects:
    obj.select_set(False)
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'roman-fortifications.blend'))
(EVIDENCE/'model-validation.json').write_text(json.dumps({'blender':bpy.app.version_string,'frames':len(frames),'maximum_projection_error_pixels':max(errors),'sockets':sockets,'expected_gate_clearance':64,'render':'Cycles CPU, one sample, emission palette, transparent PNG, no denoising'},indent=2))
print('FORTIFICATIONS COMPLETE: 48 renders, editable Blender assembly and identity ground projection')
