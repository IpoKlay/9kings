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
		# Native image operations whiten RGB while leaving source alpha intact.
		source.adjust_bcs(1.,0.,1.);source.adjust_bcs(2.1,1.,1.)
		masks[key]=ImageTexture.create_from_image(source)
		texture_bytes+=source.get_data_size()

func observe(event: Dictionary,rules,regiments: Dictionary):
	if not enabled or event.get('damage',0.)<=0. or not event.has('attacker_slot') or not event.has('target_slot'):return
	var attacker={};var target={}
	for u in rules.units:
		if u.id==event.get('attacker',-1):attacker=u
		if u.id==event.get('target',-1):target=u
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
