extends RefCounted
const Catalog=preload('res://scripts/data/catalog.gd')
var preset: Dictionary=Catalog.presentation('atlas_sea')
var contracts: Dictionary=Catalog.data('schema/contracts')
## Flat pixel sea: pointer motion raises broad, short-lived wind patches.
## Patches strengthen the existing water pattern; no cursor-shaped outlines.
var WORLD = Vector2(contracts.map_world_size[0],contracts.map_world_size[1])
var LIFETIME = preset.lifetime_seconds
var MAX_WATER_SPEED = preset.max_water_speed
var POINTER_GAIN = preset.pointer_gain
var DRAG = preset.drag_per_second
var MAX_GUSTS = int(contracts.technical_gust_capacity)
var GUST_INTERVAL = preset.gust_interval_seconds
var GUST_SPACING = preset.gust_spacing
const SeaShader=preload('res://shaders/atlas_sea.gdshader')
var material: ShaderMaterial
var shore: Image
var clock=0.0
var pointer=Vector2.INF
var last_input_usec=0
var gusts: Array[Dictionary]=[]
var active_gust: Dictionary={}
var last_frame=-1
var next_gust_id=0
var revision=0

func setup(_atlas_texture: Texture2D):
	if material!=null: return
	var distance_texture=load('res://assets/expedition/shore_distance.png')
	shore=distance_texture.get_image()
	material=ShaderMaterial.new()
	material.shader=SeaShader
	material.set_shader_parameter('shore_distance',distance_texture)
	sync_gusts()

func is_water(p: Vector2) -> bool:
	if shore==null or not Rect2(Vector2.ZERO,WORLD).has_point(p): return false
	return shore.get_pixel(clampi(int(p.x/2),0,shore.get_width()-1),clampi(int(p.y/2),0,shore.get_height()-1)).g>.5

func break_stroke():
	pointer=Vector2.INF
	active_gust={}

# Optional elapsed time allows deterministic speed checks; live events use
# arrival timestamps rather than a delayed, filtered mouse velocity.
func move_pointer(p: Vector2,elapsed_seconds: float=-1.0) -> bool:
	var now=Time.get_ticks_usec()
	var dt=elapsed_seconds if elapsed_seconds>=0.0 else float(now-last_input_usec)/1000000.0
	last_input_usec=now
	if not is_water(p):
		break_stroke()
		return false
	if pointer==Vector2.INF:
		pointer=p
		return false
	var start=pointer
	pointer=p
	var distance=start.distance_to(p)
	if distance<.01: return false
	if distance>preset.pointer_break_distance:
		break_stroke()
		return false
	if dt>preset.pointer_break_seconds: active_gust={}
	var direction=start.direction_to(p)
	var speed=minf(MAX_WATER_SPEED,distance/maxf(dt,.0001)*POINTER_GAIN)
	# Large patches overlap along fast strokes, but individual wind sources never
	# chase the mouse or form a closed path. Existing patches keep their motion.
	var samples=maxi(1,ceili(distance/GUST_SPACING))
	for i in range(1,samples+1):
		var point=start.lerp(p,float(i)/samples)
		if not is_water(point): active_gust={};continue
		var emit=active_gust.is_empty()
		if not emit:
			emit=clock-float(active_gust.born)>=GUST_INTERVAL or point.distance_to(active_gust.origin)>=GUST_SPACING
		if emit:
			if gusts.size()>=MAX_GUSTS: continue
			var seed=fposmod(sin(next_gust_id*12.9898+7.233)*43758.5453,1.0)
			next_gust_id+=1
			active_gust={'origin':point,'position':point,'direction':direction,'speed':speed,
				'travel':0.0,'born':clock,'seed':seed,'radius':Vector2(preset.radius.x+seed*preset.radius_variation.x,preset.radius.y+seed*preset.radius_variation.y)}
			gusts.append(active_gust)
		else:
			active_gust.speed=speed
	sync_gusts() # The first pixel of a slow movement responds next render frame.
	return true

func gust_strength(gust: Dictionary) -> float:
	var age=maxf(0.0,clock-float(gust.born))
	# A short strong breeze, then a continuous fade of the entire patch. No pixel
	# dropout, resetting the underlying water, or seven-second residual rings.
	return 1.0-smoothstep(preset.fade_start_seconds,LIFETIME,age)

func sync_gusts():
	if material==null: return
	var patches=PackedVector4Array()
	var flows=PackedVector4Array()
	patches.resize(MAX_GUSTS);flows.resize(MAX_GUSTS)
	for i in gusts.size():
		var gust=gusts[i]
		var p: Vector2=gust.position
		var radius: Vector2=gust.radius
		var direction: Vector2=gust.direction
		patches[i]=Vector4(p.x*.5,p.y*.5,radius.x*.5,radius.y*.5)
		flows[i]=Vector4(direction.x,direction.y,gust_strength(gust),float(gust.seed))
	material.set_shader_parameter('gust_count',gusts.size())
	material.set_shader_parameter('gust_patches',patches)
	material.set_shader_parameter('gust_flows',flows)
	revision+=1

func advance(delta: float) -> bool:
	var dt=clampf(delta,0.0,.1)
	clock+=dt
	var had_gusts=not gusts.is_empty()
	var drag=exp(-DRAG*dt)
	for gust in gusts:
		var speed=clampf(float(gust.speed),0.0,MAX_WATER_SPEED)
		var travel=speed*(1.0-drag)/DRAG
		gust.travel+=travel
		gust.position+=Vector2(gust.direction)*travel
		gust.speed=speed*drag
	for i in range(gusts.size()-1,-1,-1):
		if clock-float(gusts[i].born)>=LIFETIME: gusts.remove_at(i)
	if not active_gust.is_empty() and clock-float(active_gust.born)>=LIFETIME: active_gust={}
	# Movement and fading update every frame. Only water texture animation is
	# stepped inside the shader, retaining deliberate hard-edged pixel motion.
	if had_gusts: sync_gusts()
	var frame=int(clock*preset.animation_fps)
	if frame==last_frame: return false
	last_frame=frame
	material.set_shader_parameter('sea_time',clock)
	revision+=1
	return true
