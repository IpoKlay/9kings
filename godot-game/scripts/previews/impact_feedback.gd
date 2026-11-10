extends RefCounted
## Presentation only: no hit points, physical feet, timers or orders are changed.
var enabled=true
var flash_strength=1.0
var local_shake=2.0
var hold_frames=5
var masks: Dictionary={}
var atlas_sides: Dictionary={}
var flashed_sides: Dictionary={}
var contact_flash_roles: Dictionary={}
var texture_bytes=0

func prepare(regiments: Dictionary,units: Array):
	for u in units:
		var texture: Texture2D=regiments[u.get('art',u.kind)][u.side]
		var key=texture.get_instance_id()
		atlas_sides[key]=u.side
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
	if not strike.is_empty() and strike.get('heavy',false):
		var strike_frame=floori((now-strike.start)*60.+.00001)
		if strike_frame>=0 and strike_frame<8:
			apply_flash(figure,strike_frame,true)
			contact_flash_roles['attacker']=true
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
	var strength=1. if heavy else .75
	if frame<hold_frames:
		figure.cell=hit.cell;figure.bearing=hit.bearing;figure.upper_cell=-1
	# Rigid sprite displacement only; the shadow stays on the real collision foot.
	var shakes=[-3.,2.,-2.,1.,0.]
	var pulse: float=shakes[mini(frame/2,4)]*local_shake*strength
	figure.body_offset=(hit.direction*pulse).round()
	var pose: Dictionary=figure.pose.duplicate()
	if frame>=hold_frames and frame<16:
		var angle=(.46 if frame<9 else .25 if frame<12 else .10)*strength
		pose.angle=angle*(signf(hit.direction.x) if absf(hit.direction.x)>.1 else 1.)
		pose.drop=3.*strength if frame<9 else 0.
	figure.pose=pose
	apply_flash(figure,frame,heavy)
	if heavy and frame<8:contact_flash_roles['victim']=true

func apply_flash(figure: Dictionary,frame: int,heavy: bool):
	var flash_frames=8 if heavy else 6
	if frame<flash_frames and flash_strength>0.:
		figure.flash_texture=masks.get(figure.texture.get_instance_id())
		var white_frames=4 if heavy else 3
		figure.flash_alpha=maxf(figure.get('flash_alpha',0.),flash_strength*(1. if frame<white_frames else .75 if frame<flash_frames-1 else .35))
		if figure.flash_texture!=null:flashed_sides[atlas_sides[figure.texture.get_instance_id()]]=true

static func camera_offset(age: float,strength: float) -> Vector2:
	if age<0. or age>=.18 or strength<=0.:return Vector2.ZERO
	var samples=[Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1),Vector2.ZERO,Vector2.ZERO]
	return (samples[mini(floori(age*30.),5)]*strength).round()
