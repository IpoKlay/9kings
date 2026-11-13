extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
const Visuals=preload('res://scripts/tactical/charge_visuals.gd')
var failures=0
var checks=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred('run')
func fixture(kind='legion'):
	var r=Battle.new();r.units.clear()
	for row in [['cavalry','ally',Vector2(1000,1200)],[kind,'enemy',Vector2(1000,900)],['legion','enemy',Vector2(1600,400)]]:
		r.spawn(row[0],row[1],row[2]);var u=r.units.back();u.order='hold'
		for slot in u.soldiers.size():
			u.soldiers[slot].hp=10000. if slot==0 else 0.;u.soldiers[slot].cooldown=999.
		r.Soldiers.total(u);r.Charges.detach(r,u,0)
		u.soldiers[0].position=row[2];u.soldiers[0].heading=Vector2.RIGHT
	r.start();return r
func run():
	var summaries=[]
	for mode in ['open','shield','pike','lethal','mounted','ballista']:
		var r=fixture('spear' if mode=='pike' else 'cavalry' if mode=='mounted' else 'legion')
		var a=r.units[0];var b=r.units[1];var victim=b.soldiers[0]
		if mode=='ballista':b.kind='archer';b.art='siege'
		if mode in ['shield','pike']:victim.heading=Vector2.DOWN;victim.shield_wall=mode=='shield'
		if mode=='lethal':victim.hp=1.;r.Soldiers.total(b)
		var origin: Vector2=victim.position;var hit_time=-1.;var distance=0.;var peak=0.;var hits=0;var corpse_carries=false;var corpse_distance=0.
		var corpse_flashes=false
		check(r.Charges.issue(r,[Vector2i(a.id,0)],Vector2(1000,650)),mode+': charge accepted')
		check(is_equal_approx(a.soldiers[0].charge_run.speed,348.),mode+': cavalry gets the shared 45 percent speed increase')
		for frame in 180:
			r.step(1./60);r.advance_casualties(1./60)
			for event in r.events:
				if event.get('personal_charge',false) and event.target==b.id:
					hits+=1
					if hit_time<0:hit_time=r.elapsed
			r.events.clear()
			if hit_time>=0 and r.elapsed-hit_time<.55:distance=maxf(distance,origin.distance_to(victim.position))
			peak=maxf(peak,Visuals.height(victim.get('charge_lift',{}),r.elapsed))
			for body in r.casualties:
				if body.unit_id!=b.id or body.slot!=0:continue
				corpse_carries=body.has('charge_lift') and body.velocity.length()>300.
				corpse_flashes=body.has('charge_hit_start') and is_equal_approx(body.charge_hit_start,hit_time)
				if body.motion.x.size()>0:corpse_distance=maxf(corpse_distance,(body.motion.point(0)-body.motion.rest[0]).length())
		check(hits==1,mode+': one damage grant per rider/victim')
		check(hit_time>=0. and is_equal_approx(victim.get('charge_hit_start',-1.),hit_time),mode+': damaged defender flashes at contact even without a launch')
		check(r.bounds.has_point(victim.position),mode+': stays inside battlefield')
		check(Visuals.height(victim.get('charge_lift',{}),r.elapsed)==0.,mode+': settles back on ground')
		if mode=='open':
			check(distance>55. and distance<80.,'Open infantry is physically knocked a substantial, bounded distance')
			check(origin.y-victim.position.y>40.,'Most displacement follows the incoming charge')
			check(peak>28. and peak<=30.,'Exaggerated lift peaks at thirty pixels above the real ground')
			check(a.soldiers[0].charge_end.reason=='through','Horse keeps moving through open infantry')
		elif mode in ['shield','pike']:
			check(peak==0. and not victim.has('charge_lift'),mode+': brace prevents flight')
			check(absf(distance-(9.945 if mode=='shield' else 2.613))<.1,mode+': retains previous knockback')
			check(a.soldiers[0].charge_end.reason==('resisted' if mode=='shield' else 'pike'),mode+': stops the horse')
		elif mode=='lethal':
			check(corpse_carries and corpse_distance>25.,'Lethal collision carries both height and horizontal momentum into corpse rig')
			check(corpse_flashes,'Lethal collision carries the flash into the death pose')
		elif mode in ['mounted','ballista']:check(peak==0. and distance<40.,mode+': retains old displacement and is not lifted')
		summaries.append({'mode':mode,'displacement':distance,'peak_height':peak,'corpse_distance':corpse_distance})
	var r=fixture();var horse=r.units[0].soldiers[0];var dust=Visuals.new()
	r.Charges.issue(r,[Vector2i(r.units[0].id,0)],Vector2(1000,650))
	for frame in 45:r.step(1./60);dust.advance(r,1./60)
	check(not dust.puffs.is_empty(),'Moving charging horse leaves dust at its actual feet')
	var saved=dust.puffs.duplicate(true)
	dust.advance(r,0.)
	check(dust.puffs==saved,'Pause freezes dust age and emission')
	for frame in 12:dust.advance(r,1./15)
	check(dust.puffs.is_empty(),'Blocked stationary horse stops emitting, old dust expires')
	r.Soldiers.command(r,[Vector2i(r.units[0].id,0)],'hold',Vector2.ZERO)
	for frame in 10:horse.position+=Vector2(0,-18);dust.advance(r,1./15)
	check(dust.puffs.is_empty(),'Movement without charging does not produce a charge trail')
	# Stress presentation directly, without involving collision or damage simulation.
	r.units.clear()
	for group in 30:
		r.spawn('cavalry','ally',Vector2(600+group*20,1200))
		var u=r.units.back()
		for slot in u.soldiers.size():
			r.Charges.detach(r,u,slot);u.soldiers[slot].charge_run={}
	for frame in 16:
		for u in r.units:
			for actor in u.soldiers:actor.position+=Vector2(0,-18)
		dust.advance(r,1./15)
	check(dust.peak_puffs==Visuals.MAX_PUFFS and dust.puffs.size()<=Visuals.MAX_PUFFS,'Dense cavalry emission obeys the particle cap')
	dust.clear()
	check(dust.puffs.is_empty() and dust.tracks.is_empty(),'Reset drops every old puff and rider track')
	var state={'start':0.,'height':22.,'dir':Vector2.RIGHT}
	check(Visuals.height(state,4./60.)==0. and Visuals.height(state,6./60.)>0.,'Five-frame contact plants the body before lifting')
	check(Visuals.body_pose(state,.3).angle>1.1,'Airborne body tips over instead of remaining upright')
	check(Visuals.height(state,.50)==0. and Visuals.body_pose(state,.50).angle>1.3,'Landing holds a grounded fallen pose')
	check(Visuals.body_pose(state,.95).is_empty(),'Recovery hands animation back to ordinary movement')
	var landing_actor={'position':Vector2(1000,1000),'charge_lift':state}
	dust.watch_landing(landing_actor,999,0);dust.watch_landing(landing_actor,999,0)
	check(dust.landings.size()==1,'Repeated event delivery cannot duplicate a landing')
	r.units.clear();r.elapsed=0.;dust.advance(r,.50)
	check(dust.puffs.size()==2 and dust.audio_events.any(func(e):return e.layer=='landing'),'Landing emits a bounded dust burst and timed thud')
	dust.advance(r,.01)
	check(not dust.audio_events.any(func(e):return e.layer=='landing'),'Landing thud occurs only once')
	dust.watch_landing(landing_actor,999,0);dust.clear()
	check(dust.landings.is_empty() and dust.audio_events.is_empty(),'Retry also clears queued landing and sound cues')
	dust.impact();var kick=dust.camera_offset()
	check(is_equal_approx(dust.shake_strength,7.5*.6) and kick==Vector2(5,2),'Collision uses the reduced camera amplitude')
	dust.advance(r,.05);dust.impact()
	check(is_equal_approx(dust.shock_age,.05),'Simultaneous crowd hits cannot continuously reset the shake')
	dust.advance(r,0.)
	check(is_equal_approx(dust.shock_age,.05) and dust.audio_events.is_empty(),'Pause holds shake and never replays stale sound cues')
	dust.advance(r,.25)
	check(dust.camera_offset()==Vector2.ZERO,'Camera settles exactly after impact')
	dust.impact();dust.clear()
	check(dust.camera_offset()==Vector2.ZERO,'Retry clears camera displacement')
	print(JSON.stringify(summaries));print('Charge feedback: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
