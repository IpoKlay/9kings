extends RefCounted
## Presentation only: no hit points, physical feet, timers or orders are changed.
var enabled=true
var flash_strength=1.0
var local_shake=1.0
var hold_frames=3
var masks: Dictionary={}
var texture_bytes=0

func prepare(regiments: Dictionary,units: Array):
	for u in units:
		var texture: Texture2D=regiments[u.get('art',u.kind)][u.side]
		var key=texture.get_instance_id()
		if masks.has(key):continue
		var source=texture.get_image()
		if source.is_compressed():source.decompress()
		source.convert(Image.FORMAT_RGBA8)
		var pixels=source.get_data()
		# Preserve alpha exactly, including transparent pixels and the source edge.
		for i in range(0,pixels.size(),4):
			pixels[i]=255;pixels[i+1]=255;pixels[i+2]=255
		var mask=Image.create_from_data(source.get_width(),source.get_height(),false,Image.FORMAT_RGBA8,pixels)
		masks[key]=ImageTexture.create_from_image(mask)
		texture_bytes+=pixels.size()

func apply(figure: Dictionary,actor: Dictionary,now: float):
	if not enabled:return
	var strike: Dictionary=actor.get('preview_strike',{})
	if not strike.is_empty() and now-strike.start<float(hold_frames)/60.:
		if not strike.has('cell'):
			strike.cell=figure.cell;strike.upper_cell=figure.upper_cell
		figure.cell=strike.cell;figure.upper_cell=strike.upper_cell
	var hit: Dictionary=actor.get('preview_hit',{})
	if hit.is_empty():return
	var age: float=now-hit.start
	if age<0. or age>=.28:return
	var frame=floori(age*60.+.00001)
	if not hit.has('cell'):
		hit.cell=figure.cell;hit.bearing=figure.bearing
	var heavy: bool=hit.heavy
	var strength=1. if heavy else .45
	if frame<hold_frames:
		figure.cell=hit.cell;figure.bearing=hit.bearing;figure.upper_cell=-1
	# Rigid sprite displacement only; the shadow stays on the real collision foot.
	var shakes=[-3.,2.,-2.,1.,0.]
	var pulse: float=shakes[mini(frame/2,4)]*local_shake*strength
	figure.body_offset=(hit.direction*pulse).round()
	var pose: Dictionary=figure.pose.duplicate()
	if heavy and frame>=hold_frames and frame<14:
		var angle=.32 if frame<7 else .18 if frame<10 else .07
		pose.angle=angle*(signf(hit.direction.x) if absf(hit.direction.x)>.1 else 1.)
		pose.drop=2. if frame<7 else 0.
	figure.pose=pose
	var flash_frames=5 if heavy else 3
	if frame<flash_frames and flash_strength>0.:
		figure.flash_texture=masks.get(figure.texture.get_instance_id())
		figure.flash_alpha=flash_strength*(1. if frame<2 else .65 if frame<4 else .3)

static func camera_offset(age: float,strength: float) -> Vector2:
	if age<0. or age>=.15 or strength<=0.:return Vector2.ZERO
	var samples=[Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2.ZERO,Vector2.ZERO]
	return (samples[mini(floori(age*30.),4)]*strength).round()
