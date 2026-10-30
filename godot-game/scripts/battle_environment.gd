extends RefCounted
const Catalog=preload('res://scripts/data/catalog.gd')
static var preset: Dictionary=Catalog.presentation('environment')
## Independent scenery layers: alpha trees sway, standards ripple, leaves/dust drift.
## None of these effects alter terrain, targeting, units or collision.
static var BACKGROUNDS = preset.backgrounds
# Biome-specific edge planting: the arena, camp grid and shoreline stay clear.
static var TREE_LAYOUTS = preset.tree_layouts
const WATER_SHADER = preload('res://shaders/water_surface.gdshader')
static var WATER_POLYGONS = preset.water_polygons
static var WATER_SPEEDS = preset.water_speeds
var surface: Sprite2D
var surface_act = -1
static var FLAG_ROOTS = preset.flag_roots
var clock = 0.0
var wind_profiles: Array = []
func _init():
	# Separate, stable scenery randomness never consumes the campaign/card RNG.
	var rng=RandomNumberGenerator.new()
	rng.seed=int(preset.wind_seed)
	for act in TREE_LAYOUTS.size():
		var profiles: Array = []
		for i in TREE_LAYOUTS[act].size():
			profiles.append({'phase':rng.randf_range(0,TAU),'detail_phase':rng.randf_range(0,TAU),
				'speed':rng.randf_range(preset.wind_speed[0],preset.wind_speed[1]),'detail_speed':rng.randf_range(preset.detail_speed[0],preset.detail_speed[1]),
				'gust_speed':rng.randf_range(preset.gust_speed[0],preset.gust_speed[1]),'gust_phase':rng.randf_range(0,TAU),
				'amplitude':rng.randf_range(preset.amplitude[0],preset.amplitude[1]),'direction':-1.0 if rng.randf()<.5 else 1.0})
		wind_profiles.append(profiles)

func tick(delta: float): clock+=clampf(delta,0,.1)

func tree_sway(act: int, tree_index: int, fraction: float, at_time: float) -> float:
	var w=wind_profiles[clampi(act-1,0,2)][tree_index]
	# Local gust envelopes create quiet spells; different periods and phase offsets
	# prevent a row of synchronized pendulums. The bottom quarter remains rooted.
	var bend=pow(clampf((preset.root_fraction-fraction)/preset.root_fraction,0,1),preset.bend_exponent)
	var gust=.50+.50*(.5+.5*sin(at_time*w.gust_speed+w.gust_phase))
	var motion=preset.main_motion_weight*sin(at_time*w.speed+w.phase)+preset.detail_motion_weight*sin(at_time*w.detail_speed+w.detail_phase)
	return roundf(motion*w.direction*w.amplitude*gust*bend/preset.pixel_step)*preset.pixel_step

func attach(canvas: Node2D):
	surface=Sprite2D.new()
	surface.name='WaterLandscape'
	surface.centered=false
	surface.z_index=-1
	surface.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var shader_material=ShaderMaterial.new()
	shader_material.shader=WATER_SHADER
	surface.material=shader_material
	canvas.add_child(surface)

func update_surface(canvas: Node2D, index: int, offset: Vector2):
	if surface_act!=index:
		surface.texture=canvas.tex(BACKGROUNDS[index])
		surface.scale=Vector2(1920,1080)/surface.texture.get_size()
		var points=PackedVector2Array(WATER_POLYGONS[index])
		points.resize(24)
		surface.material.set_shader_parameter('water_points',points)
		surface.material.set_shader_parameter('water_count',WATER_POLYGONS[index].size())
		surface.material.set_shader_parameter('flow_speed',WATER_SPEEDS[index])
		surface.material.set_shader_parameter('ripple_strength',preset.ripple_strengths[index])
		surface_act=index
	surface.position=offset
	surface.material.set_shader_parameter('flow_time',clock)

func draw(canvas: Node2D, act: int, offset: Vector2 = Vector2.ZERO):
	var index=clampi(act-1,0,2)
	update_surface(canvas,index,offset)
	if not preset.ground_overlays[index].is_empty():
		# The caller's draw transform already includes the camera punch.
		canvas.draw_texture_rect(canvas.tex(preset.ground_overlays[index]),Rect2(Vector2.ZERO,Vector2(1920,1080)),false)
	var trees: Texture2D=canvas.tex('environments/oak' if index==0 else 'environments/trees')
	var cell=trees.get_size().x if index==0 else trees.get_size().x/3.0
	var layout=TREE_LAYOUTS[index]
	for i in layout.size():
		var planting=layout[i]
		var root=Vector2(planting.x,planting.y)
		var size=Vector2(planting.z,planting.z)
		# Alpha sprites are sliced horizontally on the existing pixel grid. Only
		# foliage moves; no baked terrain or entire background image is distorted.
		for strip in int(preset.tree_strips):
			var fraction=strip/float(preset.tree_strips)
			var sway=tree_sway(index+1,i,fraction,clock)
			var src=Rect2(0 if index==0 else index*cell,trees.get_height()*fraction,cell,trees.get_height()/float(preset.tree_strips))
			var dest=Rect2(root-Vector2(size.x*.5,size.y)+Vector2(sway,size.y*fraction),Vector2(size.x,size.y/float(preset.tree_strips)+.5))
			canvas.draw_texture_rect_region(trees,dest,src)
	for i in FLAG_ROOTS.size(): draw_flag(canvas,FLAG_ROOTS[i],i)
	# Sparse drift at the boundaries. The center remains visually quiet.
	for i in int(preset.drift_count):
		var speed=preset.drift_speeds[index]
		var x=fmod(i*137+clock*speed,1920.0)
		var y=150+float(i%3)*23 if i%2==0 else 920+float(i%4)*25
		y+=sin(clock*.7+i)*9
		var color=Color('#cfc28b70') if index==1 else Color('#a4bd7375')
		canvas.draw_rect(Rect2(Vector2(x,y).snapped(Vector2(2,2)),Vector2(6 if index==1 else 4,2)),color)

func draw_flag(canvas: Node2D,root: Vector2,phase: int):
	canvas.draw_rect(Rect2(root-Vector2(2,80),Vector2(4,80)),Color('#ae9060'))
	canvas.draw_rect(Rect2(root-Vector2(5,84),Vector2(10,6)),Color('#e9c878'))
	canvas.draw_rect(Rect2(root-Vector2(9,3),Vector2(21,4)),Color('#203c3b80'))
	for column in 12:
		var dy=roundf(sin(clock*2.2-column*.43+phase)*float(column)/8)*2
		var pos=root+Vector2(column*2,-76+dy)
		canvas.draw_rect(Rect2(pos,Vector2(2,29)),Color('#ac503b') if column%3 else Color('#bc6545'))
		canvas.draw_rect(Rect2(pos+Vector2(0,27),Vector2(2,2)),Color('#ddbd79'))
		if column in [4,5,6,7]: canvas.draw_rect(Rect2(pos+Vector2(0,8),Vector2(2,9)),Color('#e6cd87'))
