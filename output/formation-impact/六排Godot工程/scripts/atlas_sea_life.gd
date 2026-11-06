extends Node2D
## Decorative atlas sprites; use the map's clock and world transform, never GUI input.
const Catalog=preload('res://scripts/data/catalog.gd')
const Kraken=preload('res://assets/expedition/sea_life/kraken.png')
const KrakenSway=preload('res://shaders/kraken_sway.gdshader')
const DIRECTIONS=['East','SouthEast','South','SouthWest','West','NorthWest','North','NorthEast']
var preset: Dictionary=Catalog.presentation('atlas').sea_life
var ships: Array[Dictionary]=[]
var clock=0.0
var last_frame=-1
var kraken: Sprite2D

func _ready():
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	show_behind_parent=true
	kraken=Sprite2D.new()
	kraken.name='Kraken'
	kraken.texture=Kraken
	kraken.position=preset.kraken_position
	kraken.scale=Vector2.ONE*preset.world_pixel_scale
	kraken.material=ShaderMaterial.new()
	kraken.material.shader=KrakenSway
	kraken.material.set_shader_parameter('sway_period',preset.kraken_sway_period)
	kraken.material.set_shader_parameter('sway_pixels',preset.kraken_sway_pixels)
	add_child(kraken)
	for definition in preset.ships:
		var curve=Curve2D.new()
		for point in definition.route: curve.add_point(point)
		ships.append({'curve':curve,'frames':load(definition.frames),'speed':definition.speed,'phase':definition.phase})
	queue_redraw()

func update_time(map_clock: float,reduced_motion: bool=false):
	# Five authored sail frames per second; no independent animation keeps running behind dialogs.
	var frame=0 if reduced_motion else int(map_clock*5.0)
	if frame==last_frame: return
	last_frame=frame
	clock=frame/5.0
	kraken.material.set_shader_parameter('sway_time',clock)
	queue_redraw()

func ship_pose(index: int,at_time: float) -> Dictionary:
	var ship=ships[index]
	var curve: Curve2D=ship.curve
	var length=curve.get_baked_length()
	var distance=fposmod(at_time*ship.speed+ship.phase*length,length*2.0)
	var direction=1.0
	if distance>length:
		distance=length*2.0-distance
		direction=-1.0
	var p=curve.sample_baked(distance)
	var tangent=(curve.sample_baked(minf(length,distance+1.0))-curve.sample_baked(maxf(0,distance-1.0)))*direction
	var facing=posmod(roundi(tangent.angle()/(PI/4.0)),8)
	return {'position':p.snapped(Vector2(2,2)),'animation':DIRECTIONS[facing]}

func _draw():
	var pixel_scale: float=preset.world_pixel_scale
	for i in ships.size():
		var pose=ship_pose(i,clock)
		var frames: SpriteFrames=ships[i].frames
		var frame=int(clock*5.0)%frames.get_frame_count(pose.animation)
		var texture=frames.get_frame_texture(pose.animation,frame)
		var dimensions=texture.get_size()*pixel_scale
		draw_texture_rect(texture,Rect2(pose.position-dimensions*.5,dimensions),false)
