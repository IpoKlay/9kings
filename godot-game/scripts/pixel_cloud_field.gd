extends Node2D
## Independent cloud clusters. This local generator never touches the campaign RNG.
const Catalog=preload('res://scripts/data/catalog.gd')
const CloudShader=preload('res://shaders/departure_clouds.gdshader')
var preset: Dictionary=Catalog.presentation('atlas').departure
var layout_seed=-1
var clouds: Array=[]
var bed: ColorRect
var gentle=false

func _ready():
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var rng=RandomNumberGenerator.new()
	if layout_seed<0: rng.randomize()
	else: rng.seed=layout_seed
	bed=ColorRect.new();bed.size=Vector2(preset.cloud_size);bed.color=preset.cloud_light
	bed.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(bed)
	for i in int(preset.cloud_count):
		# Random candidates spread coverage without rows or a tile grid.
		var center=Vector2.ZERO;var best=-1.0
		for attempt in 5:
			var candidate=Vector2(rng.randf_range(-16,preset.cloud_size.x+16),rng.randf_range(-12,preset.cloud_size.y+12))
			var nearest=INF
			for other in clouds: nearest=minf(nearest,candidate.distance_squared_to(other.center))
			if nearest>best: center=candidate;best=nearest
		var width=rng.randf_range(preset.cloud_width.x,preset.cloud_width.y)
		var dimensions=Vector2(width,width*rng.randf_range(.54,.78)).round()
		var drift=Vector2.from_angle(rng.randf_range(0,TAU))*rng.randf_range(preset.cloud_drift.x,preset.cloud_drift.y)
		var rect=ColorRect.new();rect.size=dimensions;rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var material=ShaderMaterial.new();material.shader=CloudShader
		for tone in ['shadow','mid','light','highlight']: material.set_shader_parameter(tone+'_ink',preset['cloud_'+tone])
		material.set_shader_parameter('lobes',Vector4(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1)))
		rect.material=material;add_child(rect)
		clouds.append({'rect':rect,'center':center,'size':dimensions,'drift':drift,'delay':rng.randf_range(0,.23),'fade_start':rng.randf_range(.25,.48),'end':rng.randf_range(.78,1.0)})
	set_progress(0,false,false)

func set_progress(coverage: float,revealing: bool,reduced: bool):
	gentle=reduced
	coverage=clampf(coverage,0,1)
	var scatter=1.0-coverage
	# Dense mist guarantees a hidden scene swap. It clears across the entire
	# screen early; the independent clouds linger afterwards.
	var mist=coverage if reduced else smoothstep(.78,1.0,coverage)
	bed.color=Color(preset.cloud_light,ceilf(mist*12)/12)
	for cloud in clouds:
		var position: Vector2=cloud.center
		var dimensions: Vector2=cloud.size
		var alpha=coverage
		if not reduced:
			var progress=clampf((scatter-cloud.delay)/(cloud.end-cloud.delay),0,1)
			position+=cloud.drift*smoothstep(0.0,1.0,progress)*(1.0 if revealing else -.35)
			dimensions*=1.0-.10*progress
			alpha=1.0-smoothstep(cloud.fade_start,1.0,progress)
		if coverage<=0: alpha=0
		cloud.rect.size=dimensions.round()
		cloud.rect.position=(position-cloud.rect.size*.5).round()
		cloud.rect.material.set_shader_parameter('opacity',ceilf(alpha*12)/12)
