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

func clear_masks():
	masks.clear()
	texture_bytes=0

func prepare(regiments: Dictionary,units: Array):
	for u in units:
		var texture: Texture2D=regiments[u.get('art',u.kind)][u.side]
		var key=texture.get_instance_id()
		atlas_sides[key]=u.side
		prepare_texture(texture)

func prepare_texture(texture: Texture2D):
	var key=texture.get_instance_id()
	if masks.has(key):return
	var source=texture.get_image()
	if source.is_compressed():source.decompress()
	source.convert(Image.FORMAT_RGBA8)
	var pixels=source.get_data()
	# Cache only sheets that are used; preserve the exact alpha and atlas region.
	for i in range(0,pixels.size(),4):
		pixels[i]=255;pixels[i+1]=255;pixels[i+2]=255
	var mask=Image.create_from_data(source.get_width(),source.get_height(),false,Image.FORMAT_RGBA8,pixels)
	masks[key]=ImageTexture.create_from_image(mask)
	texture_bytes+=pixels.size()

func observe(event: Dictionary,rules,regiments: Dictionary):
	if not enabled or event.get('damage',0.)<=0. or not event.has('attacker_slot') or not event.has('target_slot'):return
	var attacker: Dictionary=rules.unit_by_id(event.get('attacker',-1))
	var target: Dictionary=rules.unit_by_id(event.get('target',-1))
	if attacker.is_empty() or target.is_empty():return
	var a: int=event.attacker_slot;var b: int=event.target_slot
	if a<0 or b<0 or a>=attacker.soldiers.size() or b>=target.soldiers.size():return
	var heavy: bool=event.get('personal_charge',false)
	var victim: Dictionary=target.soldiers[b];var rider: Dictionary=attacker.soldiers[a]
	var now: float=rules.elapsed
	var previous: Dictionary=victim.get('preview_hit',{})
	if now-previous.get('start',-100.)>=.2 or heavy and not previous.get('heavy',false):
		var direction=rules.Soldiers.ground_position(rules,attacker,a).direction_to(rules.Soldiers.ground_position(rules,target,b))
		victim.preview_hit={'start':now,'heavy':heavy,'direction':direction}
	if heavy:rider.preview_strike={'start':now,'heavy':true}
	prepare(regiments,[target,attacker] if heavy else [target])

func apply(figure: Dictionary,actor: Dictionary,now: float):
	if not enabled:return
	var strike: Dictionary=actor.get('rider_contact',actor.get('preview_strike',{}))
	if not strike.is_empty() and now-strike.start<float(hold_frames)/60.:
		if not strike.has('cell'):
			strike.cell=figure.cell;strike.upper_cell=figure.upper_cell
		figure.cell=strike.cell;figure.upper_cell=strike.upper_cell
		if figure.kind=='cavalry' and figure.has('pixel_clip'):
			if not strike.has('pixel_clip'):
				strike.pixel_clip=figure.pixel_clip
				strike.pixel_frame=figure.pixel_frame
			if strike.pixel_clip==figure.pixel_clip:figure.pixel_frame=strike.pixel_frame
	if not strike.is_empty() and strike.get('heavy',true):
		var strike_frame=floori((now-float(strike.start))*60.+.00001)
		apply_flash(figure,strike_frame,true)
		if strike_frame>=0 and strike_frame<6:contact_flash_roles['attacker']=true
	if actor.has('charge_hit_start'):
		var charge_frame=floori((now-float(actor.charge_hit_start))*60.+.00001)
		apply_flash(figure,charge_frame,true)
		if charge_frame>=0 and charge_frame<6:contact_flash_roles['victim']=true
	var hit: Dictionary=actor.get('preview_hit',{})
	if hit.is_empty() and actor.has('charge_lift'):
		var lift: Dictionary=actor.charge_lift
		hit={'start':lift.start,'heavy':true,'direction':lift.dir}
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
	if heavy and frame<6:contact_flash_roles['victim']=true

func apply_flash(figure: Dictionary,frame: int,heavy: bool):
	var flash_frames=6 if heavy else 2
	if not enabled or frame<0 or frame>=flash_frames or flash_strength<=0.:return
	var texture: Texture2D=figure.get('pixel_page',figure.get('texture'))
	prepare_texture(texture)
	var key=texture.get_instance_id()
	figure.flash_texture=masks[key]
	var alpha=flash_strength*(1. if frame<3 else .8 if frame<5 else .45)
	figure.flash_alpha=maxf(figure.get('flash_alpha',0.),alpha)
	flashed_sides[figure.get('side',atlas_sides.get(key,'live'))]=true

static func camera_offset(age: float,strength: float) -> Vector2:
	if age<0. or age>=.24 or strength<=0.:return Vector2.ZERO
	var samples=[Vector2(1,.5),Vector2(-1,-.5),Vector2(.75,-.5),Vector2(-.65,.5),Vector2(.45,.25),Vector2(-.3,-.2),Vector2(.15,0),Vector2.ZERO]
	return (samples[mini(floori(age*30.),7)]*strength).round()
