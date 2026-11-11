extends RefCounted
## Ground-anchored pixel dust and a presentation-only height above the real foot.
const MAX_PUFFS=192
const MAX_CHIPS=96
const SAMPLE_INTERVAL=1./15.
const PUFF_LIFE=.65
const LIFT_DURATION=.46
const RECOVERY_DURATION=.9
const IMPACT_HOLD=5./60.
const Feedback=preload('res://scripts/previews/impact_feedback.gd')
var shock_age=1.
var shake_strength=7.5
var landings: Array=[]
var audio_events: Array=[]
var puffs: Array=[]
var tracks: Dictionary={}
var sample_age=0.
var serial=0
var peak_puffs=0
var chips: Array=[]
var burst_cells: Dictionary={}
var fx_clock=0.
var peak_chips=0

func clear():
	puffs.clear();tracks.clear();sample_age=0.;serial=0;peak_puffs=0
	landings.clear();audio_events.clear()
	shock_age=1.
	chips.clear();burst_cells.clear();fx_clock=0.;peak_chips=0

func emit_impact(point: Vector2,axis: Vector2,strength: float=1.):
	var cell=Vector2i(floori(point.x/32.),floori(point.y/24.))
	if fx_clock-float(burst_cells.get(cell,-10.))<.10:return
	burst_cells[cell]=fx_clock
	axis=axis.normalized() if not axis.is_zero_approx() else Vector2.RIGHT
	for side in [-1.,1.]:
		add_puff(point+axis.orthogonal()*side*5.,-axis*.35+axis.orthogonal()*side*.65,.85*strength,true)
	for i in 6:
		var spark=i>=4
		var direction=axis.rotated((float(i)-2.5)*.28)
		chips.append({'point':point,'velocity':direction*(48.+i*13.)*strength,'age':0.,
			'life':.10 if spark else .32+float(i%2)*.06,'rise':38.+i*8.,'spark':spark,'variant':i%3})
	while chips.size()>MAX_CHIPS:chips.pop_front()
	peak_chips=maxi(peak_chips,chips.size())

func impact():
	# Dense contacts cannot reset the shake every frame or accumulate amplitude.
	if shock_age>=.12:shock_age=0.

func camera_offset() -> Vector2:
	return Feedback.camera_offset(shock_age,shake_strength)

static func height(state: Dictionary,now: float) -> float:
	if state.is_empty():return 0.
	var progress=(now-float(state.start)-IMPACT_HOLD)/(LIFT_DURATION-IMPACT_HOLD)
	if progress<=0. or progress>=1.:return 0.
	return 4.*progress*(1.-progress)*float(state.height)

static func body_pose(state: Dictionary,now: float) -> Dictionary:
	if state.is_empty():return {}
	var age=now-float(state.start)
	if age<0. or age>=RECOVERY_DURATION:return {}
	var direction: Vector2=state.get('dir',Vector2.RIGHT)
	var hand=signf(direction.x) if absf(direction.x)>.1 else 1.
	var angle=0.
	var drop=0.
	if age<IMPACT_HOLD:angle=.12
	elif age<LIFT_DURATION:
		angle=lerpf(.12,1.32,smoothstep(IMPACT_HOLD,.32,age))
	elif age<.60:angle=1.4;drop=3.
	else:angle=lerpf(1.4,0.,smoothstep(.60,RECOVERY_DURATION,age));drop=2.
	return {'angle':angle*hand,'drop':drop,'frame':10 if age<.16 else 1,'flash':age<IMPACT_HOLD}

static func apply_figure(figure: Dictionary,actor: Dictionary,now: float):
	var pose=body_pose(actor.get('charge_lift',{}),now)
	if not pose.is_empty():
		figure.pose=pose;figure.cell=pose.frame;figure.upper_cell=-1;figure.body_offset=Vector2.ZERO
	if figure.kind!='cavalry':return
	var contact: Dictionary=actor.get('rider_contact',{})
	if contact.is_empty():return
	var age=now-float(contact.start)
	if age<0. or age>.28:return
	var pulse=sin(PI*clampf(age/.28,0.,1.))
	figure.pose={'angle':.12*signf(contact.dir.x)*pulse,'drop':roundf(5.*pulse),'frame':figure.cell,'flash':false}
	figure.upper_cell=11
	figure.rider_offset=Vector2(roundf(contact.dir.x*5.*pulse),roundf(2.*pulse))

func watch_landing(actor: Dictionary,unit_id: int,slot: int):
	if not actor.has('charge_lift'):return
	var state: Dictionary=actor.charge_lift
	if landings.any(func(e):return e.unit_id==unit_id and e.slot==slot and e.start==state.start):return
	landings=landings.filter(func(e):return e.unit_id!=unit_id or e.slot!=slot)
	landings.append({'actor':actor,'unit_id':unit_id,'slot':slot,'start':state.start,'age':0.})

func add_puff(point: Vector2,axis: Vector2,strength: float,landing: bool=false):
	serial+=1
	puffs.append({'point':point,'axis':axis,'age':0.,'variant':serial%3,'strength':strength,'landing':landing})
	if puffs.size()>MAX_PUFFS:puffs.pop_front()

func advance(r,dt: float):
	audio_events.clear()
	if dt<=0:return
	shock_age+=dt
	fx_clock+=dt
	for chip in chips:chip.age+=dt
	chips=chips.filter(func(chip):return chip.age<chip.life)
	for cell in burst_cells.keys():
		if fx_clock-burst_cells[cell]>.2:burst_cells.erase(cell)
	for puff in puffs:puff.age+=dt
	puffs=puffs.filter(func(puff):return puff.age<PUFF_LIFE)
	for landing in landings:
		landing.age+=dt
		if landing.age<LIFT_DURATION:continue
		var ground: Vector2=landing.actor.get('position',Vector2.ZERO)
		var point: Vector2=r.projection*ground
		for body in r.casualties:
			if body.unit_id==landing.unit_id and body.slot==landing.slot and body.motion.x.size()>0:
				point=body.foot+r.projection.basis_xform(body.motion.point(0)-body.motion.rest[0]);break
		for side in [-1.,1.]:add_puff(point,Vector2(side,0),1.1,true)
		audio_events.append({'sample':'impact0','pos':ground,'gain':.42,'layer':'landing'})
	landings=landings.filter(func(e):return e.age<LIFT_DURATION)
	sample_age+=dt
	if sample_age<SAMPLE_INTERVAL:return
	var sample_dt=sample_age;sample_age=0.
	var next_tracks={}
	for u in r.units:
		if u.kind!='cavalry' or u.hp<=0 or u.get('escaped',false) or u.petrified>0:continue
		if r.has_method('unit_visible') and not r.unit_visible(u):continue
		for slot in u.soldiers.size():
			var actor: Dictionary=u.soldiers[slot]
			if actor.hp<=0:continue
			if not actor.has('charge_run') and u.get('gait','')!='sprint':continue
			var id=Vector2i(u.id,slot)
			var point: Vector2=r.Soldiers.ground_position(r,u,slot)
			var old: Dictionary=tracks.get(id,{'point':point,'distance':0.})
			var delta: Vector2=point-old.point
			var distance=delta.length()
			var covered: float=old.distance+distance
			next_tracks[id]={'point':point,'distance':covered}
			# Actual displacement prevents dust from a blocked horse or a teleport.
			if distance/sample_dt<70. or distance>80.:
				next_tracks[id].distance=0.;continue
			var spacing=20.+float(posmod(u.id*7+slot*11,9))
			if covered<spacing:continue
			next_tracks[id].distance=fmod(covered,spacing)
			var axis: Vector2=r.projection.basis_xform(delta.normalized()).normalized()
			var foot: Vector2=r.projection*point
			var strength=clampf(distance/sample_dt/210.,.65,1.65)
			add_puff(foot-axis*12.+axis.orthogonal()*(-5. if serial%2 else 5.),axis,strength)
			if audio_events.size()<16:audio_events.append({'sample':'foot'+str(serial%3),'pos':point,'gain':.28*strength,'layer':'hoof'})
	tracks=next_tracks
	peak_puffs=maxi(peak_puffs,puffs.size())

func draw(field: Node2D):
	for puff in puffs:
		var progress: float=puff.age/PUFF_LIFE
		var fade: float=1.-smoothstep(.15,1.,progress)
		var strength: float=puff.get('strength',1.)
		var size=maxf(6.,2.*floorf((2.+progress*3.+puff.variant*.5)*strength))
		var tick=floorf(progress*8.)/8.
		var drift=24. if puff.landing else 14.
		var point: Vector2=(puff.point-puff.axis*tick*drift+Vector2(0,-tick*5.)).snapped(Vector2(2,2))
		# Stepped, low clouds instead of rectangular white plates or soft circles.
		var shape=PackedVector2Array([Vector2(-size,0),Vector2(-size,-2),Vector2(-size+2,-2),
			Vector2(-size+2,-size*.5),Vector2(-2,-size*.5),Vector2(-2,-size*.5-2),
			Vector2(size-2,-size*.5-2),Vector2(size-2,-2),Vector2(size,-2),Vector2(size,2),Vector2(-size,2)])
		for i in shape.size():shape[i]=(shape[i]+point).snapped(Vector2(2,2))
		field.draw_colored_polygon(shape,Color(.77,.75,.67,.38*fade))
		field.draw_rect(Rect2(point+Vector2(-size+2,-size*.5),Vector2(size,4)),Color(.93,.92,.85,.42*fade))
		field.draw_rect(Rect2(point+Vector2(0,-size*.5-2),Vector2(maxf(2.,size-4.),2)),Color(.99,.98,.93,.45*fade))

func draw_air(field: Node2D):
	for chip in chips:
		var t: float=chip.age
		var h=maxf(0.,chip.rise*t-120.*t*t)
		var point: Vector2=(chip.point+chip.velocity*t-Vector2(0,20.+t*24. if chip.spark else h)).snapped(Vector2(2,2))
		var color=Color('#fff0bc') if chip.spark else [Color('#8d7952'),Color('#bca47b'),Color('#d7c4a0')][chip.variant]
		color.a=1.-smoothstep(chip.life*.45,chip.life,t)
		field.draw_rect(Rect2(point,Vector2(4,2) if chip.spark else Vector2(2,2)),color)
		if chip.spark and t<.045:field.draw_rect(Rect2(point+Vector2(2,-2),Vector2(2,6)),color)
