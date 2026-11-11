extends RefCounted
## Explicit C orders. Positions, hit history and cooldown belong to each soldier.

static func ready(r,u: Dictionary,actor: Dictionary) -> bool:
	return actor.hp>0 and r.Soldiers.individual(r,u).get('can_charge',false) and actor.get('charge_cooldown',0.)<=.000001 and not actor.has('charge_run') and not u.get('routing',false)

static func detach(r,u: Dictionary,slot: int):
	var actor: Dictionary=u.soldiers[slot]
	if not actor.has('position'):
		actor.position=r.Soldiers.ground_position(r,u,slot)
	if u.has('slot_states'):u.slot_states.erase(slot)
	if u.has('contact_motion'):u.contact_motion.offsets.erase(slot)
	u.personalized=true
	if not actor.has('personal_order'):actor.personal_order='hold';actor.path=[]

static func issue(r,ids: Array,destination: Vector2,side: String='ally') -> bool:
	if r.phase!='battle' or not r.bounds.has_point(destination):return false
	var people=r.Soldiers.members(r,ids,side).filter(func(row):return ready(r,row.unit,row.actor))
	if people.is_empty():return false
	if r.has_method('charge_allowed') and not r.charge_allowed(people,destination):return false
	var center=Vector2.ZERO
	for row in people:center+=r.Soldiers.ground_position(r,row.unit,row.slot)
	center/=people.size()
	var delta=(destination-center).limit_length(r.config.individual_charge.max_range)
	if delta.length()<1.:return false
	for row in people:
		var u: Dictionary=row.unit;var actor: Dictionary=row.actor
		detach(r,u,row.slot)
		actor.personal_order='charge';actor.path=[];actor.shield_wall=false
		actor.erase('resume_attack_move')
		actor.erase('charge_end')
		actor.erase('attack_engaged')
		actor.erase('contact_recovery')
		var speed: float=maxf(u.get('combat_stats',r.config.types[u.kind]).speed,r.config.individual_charge.speed)
		var velocity: Vector2=actor.get('velocity',u.heading*u.get('slot_speeds',{}).get(row.slot,0.) if u.moving else Vector2.ZERO)
		actor.charge_run={'goal':actor.position+delta,'age':0.,'duration':r.config.individual_charge.max_range/speed,
			'velocity':velocity,'penalty':0.,'hits':[],'speed':speed}
		# The legacy regiment sweep must not also award a charge to this rider.
		u.charge=false;u.clear_run=0.;u.erase('penetration')
	return true

static func cancel(r,u: Dictionary,actor: Dictionary):
	if not actor.has('charge_run'):return
	actor.charge_cooldown=float(r.Soldiers.individual(r,u).charge_cooldown)
	actor.erase('charge_run')

static func finish(r,u: Dictionary,actor: Dictionary,reason: String):
	actor.charge_end={'time':r.elapsed,'reason':reason,'position':actor.position}
	actor.erase('attack_engaged')
	cancel(r,u,actor)
	actor.personal_order='attack' if actor.get('target_id',-1)>=0 else 'auto'
	actor.focus_id=actor.get('target_id',-1);actor.focus_slot=actor.get('target_slot',-1)

# Resistance is local to the actual victim, not a regiment-wide hit modifier.
static func brace(r,u: Dictionary,actor: Dictionary,incoming: Vector2) -> String:
	if u.kind not in ['legion','guard','spear'] or u.get('routing',false) or u.stun>0:return ''
	if actor.get('velocity',Vector2.ZERO).length()>20. or actor.has('form_left'):return ''
	if r.elapsed<actor.get('gap_until',0.):return ''
	var facing: Vector2=actor.get('wall_heading',actor.heading) if actor.get('shield_wall',false) else actor.heading
	if facing.dot(-incoming)<.65:return ''
	var holding: bool=actor.get('personal_order','')=='hold' or actor.get('shield_wall',false) or actor.get('formation_ready',false) and actor.get('path',[]).is_empty()
	if not holding:return ''
	if u.kind=='spear':return 'pike'
	if actor.get('shield_wall',false) or actor.get('shield_raised',false):return 'shield'
	return ''

static func step(r,row: Dictionary,occupied: Array,dt: float):
	var u: Dictionary=row.unit;var actor: Dictionary=u.soldiers[row.slot]
	var run: Dictionary=actor.charge_run
	var cfg: Dictionary=r.config.individual_charge
	run.age+=dt
	if run.age>=run.duration:finish(r,u,actor,'duration');return
	if u.rooted>0:finish(r,u,actor,'rooted');return
	var here: Vector2=actor.position
	var reach: float=r.Soldiers.individual(r,u).range
	var dragon: bool=r.Soldiers.individual(r,u).get('dragon',false)
	var dragon_hit=false
	var incoming: Vector2=run.velocity.normalized()
	if incoming.is_zero_approx():incoming=here.direction_to(run.goal)
	for other in occupied:
		if other.unit.side==u.side or other.unit.soldiers[other.slot].hp<=0:continue
		var id=Vector2i(other.unit.id,other.slot)
		if id in run.hits or here.distance_squared_to(other.point)>reach*reach:continue
		var victim: Dictionary=other.unit.soldiers[other.slot]
		var braced=brace(r,other.unit,victim,incoming) if u.kind=='cavalry' else ''
		var fraction=clampf(run.velocity.length()/run.speed,.1,1.)
		var damage: float=u.get('combat_stats',r.config.types[u.kind]).damage*cfg.damage_multiplier*fraction
		if u.kind=='cavalry':damage*=pow(cfg.trample_decay,run.hits.size())
		run.hits.append(id)
		actor.target_id=id.x;actor.target_slot=id.y
		actor.attack_age=0.
		var hit=r.deal_blow(u,other.unit,damage,{}, {'attacker_slot':row.slot,'target_slot':other.slot,'personal_charge':true,'speed_fraction':fraction})
		if hit.get('damage',0.)>0:
			var direction=here.direction_to(other.point)
			var side=signf(run.velocity.cross(other.point-here))
			# Stable scatter for reproducible recordings. Original uses a random 0.1–0.45 radian angle.
			var scatter=lerpf(.1,cfg.scatter_angle,float(posmod(u.id*73+row.slot*31+id.x*17+id.y,101))/100.)
			var impulse: Vector2=direction.rotated(side*scatter)*cfg.knockback*fraction*(cfg.cavalry_knockback if u.kind=='cavalry' else 1.)
			knock(r,other.unit,other.slot,impulse)
			if braced!='':victim.impact_pose.reaction='brace'
		if u.kind=='cavalry':
			actor.rider_contact={'start':r.elapsed,'dir':r.ground_basis.basis_xform(incoming),'braced':braced!=''}
			# Public 20260409 rules accumulate bounded slowdown, not a shield/pike stop.
			run.penalty=minf(cfg.slow_cap,run.penalty+cfg.slow_per_hit)
		if u.kind!='cavalry':
			if not dragon:finish(r,u,actor,'hit');return
			dragon_hit=true

	# The legacy dragon loop finishes all nearby hits before leaving its charging step.
	if dragon_hit:finish(r,u,actor,'hit')
	var to_goal: Vector2=run.goal-here
	if to_goal.length()<25.:finish(r,u,actor,'goal');return
	if run.age>.15 and run.velocity.length()<10.:finish(r,u,actor,'stalled');return
	var desired=to_goal.normalized()*run.speed*(1.-run.penalty)
	run.velocity=Vector2(move_toward(run.velocity.x,desired.x,cfg.acceleration*dt),move_toward(run.velocity.y,desired.y,cfg.acceleration*dt))
	actor.heading=run.velocity.normalized();actor.velocity=run.velocity

static func knock(r,u: Dictionary,slot: int,impulse: Vector2):
	if u.soldiers[slot].get('death_state',0)!=0:return
	var actor: Dictionary=u.soldiers[slot]
	detach(r,u,slot)
	actor.impulse=actor.get('impulse',Vector2.ZERO)+impulse
	actor.gap_until=r.elapsed+r.config.individual_charge.gap_hold
	actor.impact_pose={'reaction':'charge','start':r.elapsed,'dir':r.ground_basis.basis_xform(impulse).normalized()}

