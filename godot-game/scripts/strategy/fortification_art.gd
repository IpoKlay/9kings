extends RefCounted
## Blender-authored modules, rendered at one source pixel per game-ground unit.
const ATLAS=preload('res://assets/strategy/fortifications/roman-fortifications.png')
var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://data/generated/fortifications.json'))
var textures={}
func frame_key(b: Dictionary) -> String:
	var direction=posmod(roundi(b.get('wall_angle',0.)/(PI/4.)),8)
	var kind: String=b.kind
	if kind=='gate':kind='gate_open' if b.open else 'gate_closed'
	elif kind=='wall':
		var length: float=b.get('wall_length',64.)
		kind='wall_short' if length<56. else 'wall_long' if length<63. else 'wall'
	return kind+'_'+str(direction)
func texture(key: String) -> Texture2D:
	if not textures.has(key):
		var frame: Array=manifest.frames[key].region
		var image=AtlasTexture.new();image.atlas=ATLAS
		image.region=Rect2(frame[0],frame[1],frame[2],frame[3]);image.filter_clip=true
		textures[key]=image
	return textures[key]
func draw(canvas: CanvasItem,b: Dictionary):
	var key=frame_key(b)
	var origin: Array=manifest.frames[key].anchor
	var alpha=.5 if b.get('remaining',0.)>0 else 1.
	canvas.draw_texture(texture(key),(b.pos-Vector2(origin[0],origin[1])).round(),Color(1,1,1,alpha))
func structures_with_joints(r) -> Array:
	var structures: Array=r.world.displayed_buildings(r)
	var endpoints={}
	for b in structures:
		if not b.get('initial_wall',false) or b.hp<=0:continue
		var axis=Vector2.from_angle(b.wall_angle)*b.wall_length*.5
		for point in [b.pos-axis,b.pos+axis]:
			var key=Vector2i(point.round())
			endpoints[key]=endpoints.get(key,0)+1
	var corners=r.world.wall_vertices()
	for i in corners.size():
		# Never cover a destroyed wall with a surviving decorative joint.
		if endpoints.get(Vector2i(corners[i].round()),0)==2:
			structures.append({'kind':'corner','pos':corners[i],'wall_angle':i*PI/4.})
	structures.sort_custom(func(a,b):return a.pos.y<b.pos.y)
	return structures
