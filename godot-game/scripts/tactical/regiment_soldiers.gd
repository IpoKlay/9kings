extends RefCounted
const Physics=preload('res://scripts/tactical/soldier_physics.gd')
const ATTACK_DURATION=.8
## Group orders coexist with individual orders and physical soldier positions.

static func individual(r,u: Dictionary) -> Dictionary:
	if u.has('individual_stats'):return u.individual_stats
	return r.config.types.get(u.kind,{}).get('individual',{})

static func ranged(u: Dictionary) -> bool:
	return bool(int(u.get('individual_stats',{}).get('role_bits',0))&4) or u.kind in ['archer','siege']

static func mounted_ranged(u: Dictionary) -> bool:
	return u.kind=='cavalry' and ranged(u)

static func initialize(u: Dictionary,stats: Dictionary):
	u.soldiers=[]
	var maximum: float=u.max_hp/int(stats.files)
	for slot in int(stats.files):
		u.soldiers.append({'hp':maximum,'max_hp':maximum,'death_state':0,'cooldown':0.,'attack_age':10.,
			'hit_age':10.,'target_id':-1,'target_slot':-1,'heading':u.heading})
	u.soldier_hp=u.hp
	u.soldier_max_hp=u.max_hp

# Campaign scaling and scripted setup can still assign the regiment's aggregate.
static func sync(u: Dictionary):
	if not u.has('soldiers'):return
	if not is_equal_approx(u.max_hp,u.soldier_max_hp):
		var scale: float=u.max_hp/u.soldier_max_hp
		for actor in u.soldiers:actor.max_hp*=scale;actor.hp*=scale
		u.soldier_hp*=scale
		u.soldier_max_hp=u.max_hp
	if not is_equal_approx(u.hp,u.soldier_hp):
		var factor: float=maxf(0,u.hp)/maxf(.000001,u.soldier_hp)
		for actor in u.soldiers:actor.hp=minf(actor.max_hp,actor.hp*factor)
		total(u)

static func total(u: Dictionary):
	u.hp=0.
	for actor in u.soldiers:u.hp+=actor.hp
	u.soldier_hp=u.hp

static func advance(u: Dictionary,dt: float):
	sync(u)
	for actor in u.get('soldiers',[]):
		if actor.get('death_state',0)!=0:continue
		actor.cooldown=maxf(0,actor.cooldown-dt)
		actor.blink_cooldown=maxf(0,actor.get('blink_cooldown',0.)-dt)
		actor.volley_cooldown=maxf(0,actor.get('volley_cooldown',0.)-dt)
		actor.charge_cooldown=maxf(0,actor.get('charge_cooldown',0.)-dt)
		actor.attack_age+=dt
		actor.hit_age+=dt

static func hurt(u: Dictionary,damage: float,slot: int=-1) -> float:
	sync(u)
	var before: float=u.hp
	if slot>=0:
		if slot>=u.soldiers.size():return 0.
		var actor: Dictionary=u.soldiers[slot]
		actor.hp=maxf(0,actor.hp-damage)
		if actor.hp>0:actor.hit_age=0.
	else:
		# shortcut: legacy divine powers supply aggregate damage; migrate their footprints separately.
		var factor:=maxf(0,1-damage/maxf(.000001,before))
		for actor in u.soldiers:
			if actor.hp>0:actor.hp*=factor;actor.hit_age=0.
	total(u)
	return before-u.hp

# A hit changes only eligible personal states; H, F and an existing pursuit keep their orders.
static func retaliate(r,u: Dictionary,slot: int,source_id: int,source_slot: int):
	if slot<0 or slot>=u.get('soldiers',[]).size() or source_slot<0:return
	var actor: Dictionary=u.soldiers[slot]
	var source=r.units.filter(func(other):return other.id==source_id)
	if source.is_empty() or source_slot>=source[0].soldiers.size():return
	# A lethal hit does not unregister the attacker until its death-system visit.
	if source[0].soldiers[source_slot].get('death_state',0)!=0:return
	actor.last_attacker=Vector2i(source_id,source_slot)
	if actor.get('death_state',0)!=0 or not actor.has('personal_order') or actor.get('shield_wall',false) or actor.has('charge_run'):return
	var order: String=actor.personal_order
	var pursuing: bool=actor.has('attack_engaged') or (actor.get('target_id',-1)>=0 and not mounted_ranged(u))
	if order not in ['idle','move','attack_move','auto'] or (order!='move' and pursuing):return
	actor.resume_attack_move=order=='attack_move'
	actor.personal_order='attack'
	actor.focus_id=source_id;actor.focus_slot=source_slot
	remember_target(u,actor,{'unit':source[0],'near':{'slot':source_slot}},r.target_reservations)
	actor.erase('attack_engaged');actor.erase('steer_path');actor.erase('steer_goal')
	if not actor.resume_attack_move:actor.path=[];actor.route_stops=[]

static func lost_pursuit_target(u: Dictionary,actor: Dictionary,counts: Dictionary):
	var resume: bool=actor.get('resume_attack_move',false) and not actor.has('attack_engaged')
	remember_target(u,actor,{},counts)
	actor.personal_order='attack_move' if resume else 'idle'
	actor.erase('resume_attack_move')
	if resume:actor.aggro_timer=.1

static func heal(u: Dictionary,amount: float) -> float:
	sync(u)
	var before: float=u.hp
	for actor in u.soldiers:
		if actor.hp<=0:continue
		var gain:=minf(amount,actor.max_hp-actor.hp)
		actor.hp+=gain;amount-=gain
		if amount<=0:break
	total(u)
	return u.hp-before

static func wounded(u: Dictionary) -> bool:
	return u.soldiers.any(func(actor):return actor.hp>0 and actor.hp<actor.max_hp-.001)

static func ground_position(r,u: Dictionary,slot: int) -> Vector2:
	if u.soldiers[slot].has('position'):return u.soldiers[slot].position
	return u.pos+r.ground_basis.affine_inverse().basis_xform(r.Contact.formation_feet(r,u)[slot])

static func point(r,u: Dictionary,slot: int) -> Vector2:
	return r.projection*ground_position(r,u,slot)+r.Contact.body_shift(u,slot,r.elapsed)

static func effective_range(r,a: Dictionary,b: Dictionary) -> float:
	var radius: float=individual(r,b).get('unit_size',9.)
	return float(individual(r,a).range)+maxf(0.,radius-9.)

static func nearest(r,a: Dictionary,slot: int,b: Dictionary) -> Dictionary:
	var origin=ground_position(r,a,slot)
	var best=INF
	var result={}
	for j in b.soldiers.size():
		if b.soldiers[j].hp<=0:continue
		var delta=ground_position(r,b,j)-origin
		var distance=delta.length_squared()
		if distance<best:
			best=distance
			result={'slot':j,'distance':sqrt(distance),'heading':delta.normalized()}
	return result

static func in_reach(r,a: Dictionary,b: Dictionary) -> bool:
	var stats: Dictionary=individual(r,a)
	for i in a.soldiers.size():
		if a.soldiers[i].hp<=0:continue
		if a.soldiers[i].has('personal_order'):continue
		var target:=nearest(r,a,i,b)
		if not target.is_empty() and target.distance<=effective_range(r,a,b) and target.distance>=stats.get('minimum_range',0.):return true
	return false

static func approach(r,a: Dictionary,b: Dictionary) -> Vector2:
	var shortest=INF
	var goal: Vector2=b.pos
	for slot in a.soldiers.size():
		if a.soldiers[slot].hp<=0:continue
		if a.soldiers[slot].has('personal_order'):continue
		var near=nearest(r,a,slot,b)
		if not near.is_empty() and near.distance<shortest:
			shortest=near.distance
			goal=a.pos+near.heading*near.distance
	return goal

static func attack(r,a: Dictionary,b: Dictionary,only_slot: int=-1,target_slot: int=-1):
	var stats: Dictionary=individual(r,a)
	var combat: Dictionary=(a.combat_stats if a.has('combat_stats') else r.config.types[a.kind])
	for i in a.soldiers.size():
		if only_slot>=0 and i!=only_slot:continue
		var actor: Dictionary=a.soldiers[i]
		if actor.get('death_state',0)!=0:continue
		if only_slot<0 and actor.has('personal_order'):continue
		var target={}
		if target_slot>=0:
			if target_slot>=b.soldiers.size() or b.soldiers[target_slot].hp<=0:continue
			var delta: Vector2=ground_position(r,b,target_slot)-ground_position(r,a,i)
			target={'slot':target_slot,'distance':delta.length(),'heading':delta.normalized()}
		else:target=nearest(r,a,i,b)
		if target.is_empty() or target.distance>engagement_range(r,a,actor,b,target.slot) or target.distance<stats.get('minimum_range',0.):continue
		actor.target_id=b.id;actor.target_slot=target.slot
		actor.heading=actor.get("wall_heading",actor.heading) if actor.get("shield_wall",false) else target.heading
		if actor.cooldown>.000001:continue
		actor.cooldown=combat.interval
		actor.attack_age=0.
		a.attack_age=0.
		actor.attack_pending=true
		actor.attack_engaged=Vector2i(b.id,target.slot)

static func engagement_range(r,u: Dictionary,actor: Dictionary,target: Dictionary,slot: int) -> float:
	var engaged: bool=actor.get('attack_engaged',Vector2i(-1,-1))==Vector2i(target.id,slot)
	return effective_range(r,u,target)*(1.3 if engaged else 1.)

# The countdown fraction describes time remaining, not elapsed windup.
static func fire_attacks(r):
	for a in r.units:
		for i in a.soldiers.size():fire_actor(r,a,i)

static func fire_actor(r,a: Dictionary,i: int):
	if not r.config.types[a.kind].has('individual'):return
	if a.get('escaped',false) or a.stun>0 or a.petrified>0:return
	var stats: Dictionary=individual(r,a)
	var actor: Dictionary=a.soldiers[i]
	# Source death is collected after this actor's state and release, not at zero HP.
	if actor.get('death_state',0)!=0 or not actor.get('attack_pending',false):return
	if actor.attack_age+0.000001<ATTACK_DURATION*(1.-stats.fire_fraction):return
	actor.erase('attack_pending')
	if actor.attack_age>=ATTACK_DURATION:return
	if actor.get('personal_order','')=='bombard':
		r.Structures.release(r,a,i);return
	var selected=identified_target(r,a,i,actor.target_id,actor.target_slot,false)
	if selected.is_empty():return
	var b: Dictionary=selected.unit;var target: Dictionary=selected.near
	var damage: float=(a.combat_stats if a.has('combat_stats') else r.config.types[a.kind]).damage
	if stats.get('special_attack','')=='troll':
		r.Specials.slam(r,a,i);return
	if stats.get('special_attack','')=='shaman':
		r.Specials.heal_nearby(r,a,i);return
	if stats.get('scythe_cleave',false):
		r.Blink.cleave(r,a,i,selected)
		return
	if a.kind=='siege':
		var impact=ground_position(r,b,target.slot)
		if ground_position(r,a,i).distance_to(impact)<150.:return
		var from=r.Projectiles.origin(r,a,i)
		var distance: float=from.distance_to(impact)
		r.stones.append(r.Projectiles.schedule(r,{'side':a.side,'from':from,'pos':impact,'target':b.id,'target_slot':target.slot,
			'attacker':a.id,'attacker_slot':i,'age':0.,'damage':damage,'flight':clampf(distance/350.,.8,2.5),'peak':clampf(distance*.25,80.,250.)}))
		r.events.append({'kind':'launch','pos':from})
		return
	if not r.square_battle and a.kind=='spear' and b.kind=='cavalry':damage*=float(r.config.types.spear.mounted_bonus)
	r.deal_blow(a,b,damage,{}, {'attacker_slot':i,'target_slot':target.slot,'release_delay':0.})

static func start_mounted_shot(r,u: Dictionary,actor: Dictionary,target: Dictionary,counts: Dictionary):
	remember_target(u,actor,target,counts)
	actor.cooldown=(u.combat_stats if u.has('combat_stats') else r.config.types[u.kind]).interval
	actor.attack_age=0.;u.attack_age=0.
	actor.attack_pending=true
	actor.erase('attack_engaged')

static func mounted_fire(r,u: Dictionary,slot: int,actor: Dictionary,counts: Dictionary):
	if actor.cooldown>0:return
	var reach: float=individual(r,u).range
	var chosen=identified_target(r,u,slot,actor.target_id,actor.target_slot)
	if chosen.is_empty() or chosen.near.distance>reach:
		chosen={};var distance=INF
		for enemy in r.alive('enemy' if u.side=='ally' else 'ally'):
			if r.has_method('can_detect') and not r.can_detect(u,enemy):continue
			var candidate=nearest(r,u,slot,enemy)
			if not candidate.is_empty() and candidate.distance<=reach and candidate.distance<distance:
				chosen={'unit':enemy,'near':candidate};distance=candidate.distance
	if not chosen.is_empty():start_mounted_shot(r,u,actor,chosen,counts)

static func brake_for_attack(r,row: Dictionary,velocity: Vector2,dt: float):
	var actor: Dictionary=row.unit.soldiers[row.slot]
	actor.velocity=Vector2(move_toward(velocity.x,0.,1200.*dt),move_toward(velocity.y,0.,1200.*dt))
	if row.unit.rooted>0:actor.velocity=Vector2.ZERO

static func navigator(r,kind: String,u: Dictionary={}) -> String:
	if r.has_method('wall_navigator') and not u.is_empty() and u.soldiers[0].has('wall_top'):return r.wall_navigator(u)
	var radius: float=individual(r,u).get('unit_size',9.) if not u.is_empty() else r.config.types[kind].get('individual',{}).get('unit_size',9.)
	var key='person_'+kind+'_'+str(radius)
	if r.terrain.extents.has(key):return key
	var extent=Vector2(Vector2(r.ground_basis.x.x,r.ground_basis.y.x).length(),Vector2(r.ground_basis.x.y,r.ground_basis.y.y).length())*radius
	r.terrain.extents[key]=extent
	var walls: Array[Rect2]=[]
	for rock: Rect2 in r.terrain.ROCKS:walls.append(Rect2(rock.position-extent,rock.size+extent*2))
	r.terrain.clearances[key]=walls
	return key

static func members(r,ids: Array,side: String='ally') -> Array:
	var result=[]
	for id: Vector2i in ids:
		for u in r.alive(side):
			if u.id!=id.x or id.y<0 or id.y>=u.soldiers.size() or u.soldiers[id.y].hp<=0:continue
			result.append({'unit':u,'slot':id.y,'actor':u.soldiers[id.y]})
	return result

static func group_members(squads: Array) -> Array:
	var ids=[]
	for u in squads:
		for slot in u.soldiers.size():
			if u.soldiers[slot].hp>0:ids.append(Vector2i(u.id,slot))
	return ids

static func movement_paths(r,selected: Array,destination: Vector2,via: Array[Vector2]=[]) -> Array:
	if r.has_method("strategy_paths"):return r.strategy_paths(selected,destination,via)
	var center=Vector2.ZERO
	var low=Vector2.INF;var high=-Vector2.INF;var total_radius=0.
	for row in selected:
		var foot: Vector2=ground_position(r,row.unit,row.slot)
		center+=foot;low=low.min(foot);high=high.max(foot)
		total_radius+=individual(r,row.unit).get('unit_size',9.)
	center/=maxi(1,selected.size())
	var outside=destination.x<low.x or destination.x>high.x or destination.y<low.y or destination.y>high.y
	var spread=0.
	for row in selected:spread=maxf(spread,(ground_position(r,row.unit,row.slot)).distance_to(center))
	var scale=minf(1.,19.*sqrt(float(selected.size()))*1.5/maxf(spread,.001))
	var batch={'center':destination,'radius':total_radius/maxi(1,selected.size())*sqrt(float(selected.size()))*2.5}
	var paths=[]
	for row in selected:
		var start: Vector2=ground_position(r,row.unit,row.slot)
		var offset=start-center
		if via.is_empty():
			if selected.size()==1:offset=Vector2.ZERO
			elif outside:offset*=scale
			else:offset=Vector2.from_angle(TAU*paths.size()/selected.size())*9.5
		var path: Array[Vector2]=[];var stops: Array[Vector2]=[]
		for stop in via+[destination]:
			var next: Vector2=stop+offset
			if not r.bounds.has_point(next):return []
			var leg: Array[Vector2]=r.terrain.leg(navigator(r,row.unit.kind,row.unit),start,next)
			if leg.is_empty():return []
			path.append_array(leg);stops.append(next);start=next
		paths.append({'path':path,'stops':stops,'batch':batch if via.is_empty() else {}})
	return paths

static func command(r,ids: Array,order: String,destination: Vector2,target_id: int=-1,target_slot: int=-1,via: Array[Vector2]=[],commit: bool=true,side: String='ally') -> bool:
	if r.phase!='battle' or order not in ['move','hold','auto','attack','attack_move']:return false
	var selected=members(r,ids,side)
	if selected.is_empty():return false
	if order=='move' and via.is_empty() and not r.has_method('strategy_paths'):
		var wall=r.Walls.march(r,ids,destination,commit)
		if not wall.is_empty():return wall.accepted
	var paths=movement_paths(r,selected,destination,via) if order in ['move','attack_move'] else []
	if order in ['move','attack_move'] and paths.is_empty():return false
	if not commit:return true
	if r.has_method('strategy_command'):r.team_serial+=10000
	var batch={}
	if not paths.is_empty() and not paths[0].batch.is_empty():
		batch=paths[0].batch.duplicate();batch.id=r.move_batch_serial;r.move_batch_serial+=1
	for i in selected.size():
		var row=selected[i];var actor=row.actor;var u=row.unit
		r.Charges.detach(r,u,row.slot)
		r.Charges.cancel(r,u,actor)
		actor.erase('contact_recovery')
		actor.personal_order=order
		if r.has_method('strategy_command'):r.strategy_command(row,paths[i] if not paths.is_empty() else {})
		actor.erase('resume_attack_move')
		actor.erase('attack_engaged')
		if order!='hold':actor.shield_wall=false
		# Holding keeps the shield stance, but cancels the old wall's march authority.
		actor.erase('wall_id')
		actor.erase('wall_slot')
		actor.path=paths[i].path if not paths.is_empty() else []
		if not actor.path.is_empty():actor.move_goal=actor.path.back()
		actor.route_stops=paths[i].stops if not paths.is_empty() else []
		actor.route_progress=0
		actor.move_settle=0.
		actor.erase('settled_by_sibling');actor.erase('settled_position')
		if not batch.is_empty():actor.move_batch=batch
		elif order!='hold':actor.erase('move_batch')
		actor.focus_id=target_id;actor.focus_slot=target_slot
		actor.target_id=-1;actor.target_slot=-1
		actor.next_scan=0.;actor.erase('steer_path');actor.erase('steer_goal')
		if order=='attack_move':actor.aggro_timer=.1
	return true

static func sibling_settled(row: Dictionary) -> bool:
	var actor: Dictionary=row.unit.soldiers[row.slot]
	var batch: Dictionary=actor.get('move_batch',{})
	if batch.is_empty() or actor.position.distance_squared_to(batch.center)>batch.radius*batch.radius:return false
	for neighbour in row.get('neighbours',[]):
		if neighbour.unit.id==row.unit.id and neighbour.slot==row.slot:continue
		if neighbour.unit.side!=row.unit.side:continue
		var other: Dictionary=neighbour.unit.soldiers[neighbour.slot]
		if other.hp<=0 or other.get('move_batch',{}).get('id',-1)!=batch.id:continue
		var state: String=other.get('personal_order','')
		if state!='hold' and not (state=='idle' and other.get('target_id',-1)<0):continue
		var reach: float=row.radius+neighbour.radius+.6*maxf(row.radius,neighbour.radius)
		if actor.position.distance_squared_to(neighbour.point)<reach*reach:return true
	return false

static func regroup(r,u: Dictionary):
	u.erase('individual_auto')
	for actor in u.get('soldiers',[]):
		if actor.has('position'):
			r.Charges.cancel(r,u,actor)
			actor.personal_order='regroup';actor.path=[];actor.shield_wall=false

static func automate(r,u: Dictionary,replace: bool=false):
	if not r.config.types[u.kind].has('individual') or u.get('individual_auto',false) and not replace:return
	u.individual_auto=true
	for slot in u.soldiers.size():
		var actor: Dictionary=u.soldiers[slot]
		if actor.hp<=0 or actor.has('personal_order') and actor.personal_order!='regroup' and not replace:continue
		r.Charges.cancel(r,u,actor)
		r.Charges.detach(r,u,slot)
		actor.personal_order='auto';actor.path=[];actor.shield_wall=false
		actor.focus_id=-1;actor.focus_slot=-1;actor.target_id=-1;actor.target_slot=-1
		actor.next_scan=0.
	u.charge=false;u.erase('penetration')

static func independent(u: Dictionary) -> bool:
	return u.soldiers.all(func(actor):return actor.hp<=0 or actor.has('personal_order') and actor.personal_order!='regroup')

static func update_center(r,u: Dictionary,dt: float):
	r.powers.invalidate_target_batch()
	if not independent(u):return
	var center=Vector2.ZERO;var heading=Vector2.ZERO;var count=0;var moving=false
	for actor in u.soldiers:
		if actor.hp<=0:continue
		center+=actor.position;heading+=actor.heading;count+=1
		moving=moving or actor.get('velocity',Vector2.ZERO).length_squared()>.04
	if count==0:return
	center/=count
	u.march_distance+=u.pos.distance_to(center);u.pos=center;u.moving=moving
	if not heading.is_zero_approx():u.heading=heading.normalized()
	if u.kind=='cavalry':u.gait='ride';u.pace=1. if moving else 0.
	u.engaged=u.soldiers.any(func(actor):return actor.hp>0 and actor.attack_age<.55)
	if u.has('route_progress'):
		var reached=100000
		for actor in u.soldiers:
			if actor.hp>0:reached=mini(reached,actor.get('route_progress',0))
		while u.route_progress<reached and not u.waypoints.is_empty():
			u.destination=u.waypoints.pop_front();u.route_progress+=1
	if u.order in ['move','attack_move','attack'] and u.soldiers.all(func(actor):return actor.hp<=0 or actor.personal_order in ['hold','idle']):
		u.order='idle' if u.soldiers.any(func(actor):return actor.hp>0 and actor.personal_order=='idle') else 'hold'
		u.waypoints.clear()

static func identified_target(r,u: Dictionary,slot: int,id: int,target_slot: int,living: bool=true) -> Dictionary:
	if id<0 or target_slot<0:return {}
	var candidates: Array=r.units if r.personal_unit_lookup.is_empty() else [r.personal_unit_lookup[id]] if r.personal_unit_lookup.has(id) else []
	for enemy in candidates:
		if enemy.id!=id or enemy.side==u.side or enemy.get('escaped',false) or target_slot<0 or target_slot>=enemy.soldiers.size():continue
		if r.has_method('can_detect') and not r.can_detect(u,enemy):return {}
		var target: Dictionary=enemy.soldiers[target_slot]
		if target.get('death_state',0)!=0 or (living and target.hp<=0):continue
		var delta: Vector2=ground_position(r,enemy,target_slot)-ground_position(r,u,slot)
		return {'unit':enemy,'near':{'slot':target_slot,'distance':delta.length(),'heading':delta.normalized()}}
	return {}

static func shield_line(r,ids: Array,start: Vector2,finish: Vector2,commit: bool=true) -> Dictionary:
	var plan=r.Walls.layout(r,ids,start,finish)
	if commit and not plan.is_empty():r.Walls.place(r,plan)
	return plan

static func ranged_target_counts(r) -> Dictionary:
	var counts={}
	for unit in r.units:
		if unit.hp<=0 or unit.get('escaped',false) or not ranged(unit):continue
		for actor in unit.soldiers:
			if actor.hp<=0 or actor.get('target_id',-1)<0 or actor.get('target_slot',-1)<0:continue
			var key=Vector2i(actor.target_id,actor.target_slot)
			counts[key]=counts.get(key,0)+1
	return counts

static func remember_target(u: Dictionary,actor: Dictionary,best: Dictionary,counts: Dictionary) -> Dictionary:
	var old=Vector2i(actor.get('target_id',-1),actor.get('target_slot',-1))
	var next=Vector2i(-1,-1) if best.is_empty() else Vector2i(best.unit.id,best.near.slot)
	if old!=next:actor.erase('attack_engaged')
	if old!=next and ranged(u):
		if old.x>=0 and old.y>=0:counts[old]=maxi(0,counts.get(old,0)-1)
		if next.x>=0 and next.y>=0:counts[next]=counts.get(next,0)+1
	actor.target_id=next.x;actor.target_slot=next.y
	return best

static func scan_due(r,actor: Dictionary,dt: float,holding: bool) -> bool:
	actor.aggro_timer=actor.get('aggro_timer',0.)+dt
	if actor.aggro_timer+.000001<.1:return false
	actor.aggro_timer=-r.targeting_random.randf_range(0.,.06)
	return holding or int(actor.scan_slot)%6==r.simulation_step%6

static func personal_target(r,u: Dictionary,slot: int,actor: Dictionary,shared_counts=null,acquire: bool=true,fresh: bool=false) -> Dictionary:
	var counts: Dictionary=ranged_target_counts(r) if shared_counts==null else shared_counts
	var best={};var best_score=-INF
	var stats: Dictionary=individual(r,u)
	if actor.personal_order=='attack':
		if actor.get('target_id',-1)>=0:return remember_target(u,actor,identified_target(r,u,slot,actor.target_id,actor.target_slot),counts)
		var alive_focus=r.alive('enemy' if u.side=='ally' else 'ally').filter(func(enemy):return enemy.id==actor.focus_id)
		if alive_focus.is_empty():return remember_target(u,actor,{},counts)
		var focused=identified_target(r,u,slot,actor.focus_id,actor.focus_slot) if actor.focus_slot>=0 else {'unit':alive_focus[0],'near':nearest(r,u,slot,alive_focus[0])}
		return remember_target(u,actor,focused,counts)
	if u.side=='enemy':
		for decoy in r.powers.decoys:
			var delta: Vector2=decoy.pos-ground_position(r,u,slot)
			if decoy.hp>0 and decoy.remaining>0 and delta.length()<=r.powers.config.odysseus.radius:
				return remember_target(u,actor,{'unit':decoy,'near':{'slot':-1,'distance':delta.length(),'heading':delta.normalized()}},counts)
	var current=identified_target(r,u,slot,actor.get('target_id',-1),actor.get('target_slot',-1))
	if not acquire:return remember_target(u,actor,current,counts)
	var reach: float=stats.range if u.side=='ally' and ranged(u) else stats.aggro_range
	if actor.personal_order=='attack_move':reach=minf(maxf(reach*4.,stats.range),800.)
	if actor.personal_order=='hold' or actor.get('shield_wall',false):reach=stats.range
	if (actor.personal_order=='hold' or actor.get('shield_wall',false)) and actor.cooldown>0:return remember_target(u,actor,current,counts)
	var is_ranged: bool=ranged(u)
	if not fresh and actor.personal_order in ['auto','idle','attack_move'] and not current.is_empty():return current
	var holding: bool=actor.personal_order=='hold' or actor.get('shield_wall',false)
	var origin=ground_position(r,u,slot)
	for enemy in r.alive('enemy' if u.side=='ally' else 'ally'):
		if r.has_method('can_detect') and not r.can_detect(u,enemy):continue
		if r.personal_target_bounds.has(enemy.id):
			var area: Rect2=r.personal_target_bounds[enemy.id]
			if origin.distance_squared_to(origin.clamp(area.position,area.end))>reach*reach:continue
		var enemy_roles: int=individual(r,enemy).get('role_bits',0)
		for j in enemy.soldiers.size():
			var victim: Dictionary=enemy.soldiers[j]
			if victim.hp<=0:continue
			var delta: Vector2=ground_position(r,enemy,j)-origin
			var distance_sq=delta.length_squared()
			if distance_sq>reach*reach:continue
			var score=-distance_sq
			var aimed: int=counts.get(Vector2i(enemy.id,j),0)
			if not holding:
				# Public physics score: proximity + wounds + anti-mounted role - ranged congestion.
				score=1.-distance_sq/(reach*reach)+.15*(1.-victim.hp/victim.max_hp)
				if int(stats.get('role_bits',0))&8 and enemy_roles&64:score+=.8
				if is_ranged:score-=.15*aimed
			if score>best_score:
				best_score=score;best={'unit':enemy,'near':{'slot':j,'distance':sqrt(distance_sq),'heading':delta.normalized()}}
	return remember_target(u,actor,best,counts)

# Return the new aim, but the caller finishes this movement step toward its cached old target.
static func retarget_pursuit(r,u: Dictionary,slot: int,actor: Dictionary,navigation_target: Dictionary,counts: Dictionary,dt: float) -> Dictionary:
	var current=identified_target(r,u,slot,actor.get('target_id',-1),actor.get('target_slot',-1))
	if navigation_target.is_empty() or current.is_empty() or actor.has('attack_engaged') or actor.get('shield_wall',false) or actor.has('charge_run'):return current
	if actor.personal_order not in ['attack','idle','auto','attack_move']:return current
	if mounted_ranged(u) and actor.personal_order!='attack':return current
	var reach=effective_range(r,u,navigation_target.unit)
	var distance_sq: float=navigation_target.near.distance*navigation_target.near.distance
	if not mounted_ranged(u) and distance_sq<=reach*reach:return current
	actor.retarget_timer=actor.get('retarget_timer',0.)-dt
	if actor.retarget_timer>0. or distance_sq<=reach*reach*4.:return current
	actor.retarget_timer=.15
	var radius: float=individual(r,u).unit_size*8.
	var origin=ground_position(r,u,slot)
	var is_ranged: bool=ranged(u)
	var best=current
	var best_cost: float=current.near.distance*current.near.distance
	if is_ranged:best_cost+=counts.get(Vector2i(current.unit.id,current.near.slot),0)*1500.
	for enemy in r.alive('enemy' if u.side=='ally' else 'ally'):
		if r.has_method('can_detect') and not r.can_detect(u,enemy):continue
		if r.personal_target_bounds.has(enemy.id):
			var area: Rect2=r.personal_target_bounds[enemy.id]
			if origin.distance_squared_to(origin.clamp(area.position,area.end))>radius*radius:continue
		for j in enemy.soldiers.size():
			if enemy.soldiers[j].hp<=0 or (enemy.id==current.unit.id and j==current.near.slot):continue
			var delta=ground_position(r,enemy,j)-origin
			var cost=delta.length_squared()
			if cost>radius*radius:continue
			var distance: float=sqrt(cost)
			if is_ranged:cost+=counts.get(Vector2i(enemy.id,j),0)*1500.
			if cost>=best_cost:continue
			best_cost=cost;best={'unit':enemy,'near':{'slot':j,'distance':distance,'heading':delta.normalized()}}
	remember_target(u,actor,best,counts)
	if actor.personal_order=='attack':actor.focus_id=best.unit.id;actor.focus_slot=best.near.slot
	return best

static func begin_target_lookup(r):
	# Regroup can settle feet during decisions; it erases that unit's bounds below.
	r.personal_unit_lookup.clear();r.personal_target_bounds.clear()
	for unit in r.units:
		r.personal_unit_lookup[unit.id]=unit
		if unit.hp<=0 or unit.soldiers.is_empty():continue
		var area=Rect2(ground_position(r,unit,0),Vector2.ZERO)
		for slot in range(1,unit.soldiers.size()):area=area.expand(ground_position(r,unit,slot))
		r.personal_target_bounds[unit.id]=area

static func advance_personal(r,dt: float):
	r.powers.end_target_batch()
	var registered=[]
	for unit in r.units:
		if unit.get('escaped',false):continue
		var radius: float=float(individual(r,unit).get('unit_size',9.))
		for slot in unit.soldiers.size():
			var actor: Dictionary=unit.soldiers[slot]
			if actor.get('death_state',0)!=0:continue
			actor.source_point=ground_position(r,unit,slot)
			registered.append({'unit':unit,'slot':slot,'radius':radius,'point':actor.source_point})
	if not r.units.any(func(u):return u.get('personalized',false)):
		fire_attacks(r)
		for row in registered:
			if row.unit.soldiers[row.slot].hp<=0 and row.unit.stun<=0 and row.unit.petrified<=0:
				r.record_casualty(row.unit,row.slot)
				row.unit.soldiers[row.slot].death_state=1
		return
	begin_target_lookup(r)
	r.Walls.advance(r)
	var occupied=registered
	prepare_neighbours(r,occupied,dt)
	var target_counts=ranged_target_counts(r)
	r.target_reservations=target_counts
	var dead=[]
	r.powers.begin_target_batch()
	for row in registered:
		if row.unit.stun>0 or row.unit.petrified>0:continue
		step_personal(r,row,occupied,target_counts,dt)
		fire_actor(r,row.unit,row.slot)
		if row.unit.soldiers[row.slot].hp<=0:dead.append(row)
	r.powers.end_target_batch()
	r.target_reservations={}
	r.personal_unit_lookup.clear();r.personal_target_bounds.clear()
	Physics.integrate(r,occupied,dt)
	Physics.repel(r,occupied,dt)
	# Free the combat registration now; queue_free keeps the source object until frame end.
	for row in dead:
		r.record_casualty(row.unit,row.slot)
		row.unit.soldiers[row.slot].death_state=1
	# Neighbour lists reference these same rows; release the temporary cycles each step.
	for row in occupied:row.erase('neighbours')
	for u in r.units:
		update_center(r,u,dt)
		if independent(u) and u.get('routing',false):u.escaped=personal_fled(r,u)
		if u.get('personalized',false) and not u.soldiers.any(func(actor):return actor.has('position')):u.erase('personalized')

static func pending_deaths(r,side: String) -> bool:
	return r.units.any(func(u):return u.side==side and not u.get('escaped',false) and u.soldiers.any(func(a):return a.hp<=0 and a.get('death_state',0)==0))

static func finish_deaths(r):
	for unit in r.units:
		for actor in unit.soldiers:
			if actor.get('death_state',0)==1:
				actor.death_state=2
				actor.erase('attack_pending');actor.erase('charge_run');actor.erase('impulse')

# Only displaced wall members check this, at 5 Hz. Reuse this step's soldiers.
static func return_occupied(row: Dictionary,occupied: Array) -> bool:
	var actor: Dictionary=row.unit.soldiers[row.slot]
	for other in occupied:
		if other.unit.side==row.unit.side or other.unit.soldiers[other.slot].hp<=0:continue
		var nearest=Geometry2D.get_closest_point_to_segment(other.point,actor.position,actor.wall_slot)
		if nearest.distance_squared_to(other.point)<pow(row.radius+other.radius+12.,2.):return true
	return false

static func step_personal(r,row: Dictionary,occupied: Array,target_counts: Dictionary,dt: float):
	var u=row.unit;var slot: int=row.slot;var actor=u.soldiers[slot]
	if actor.get('death_state',0)!=0 or not actor.has('personal_order'):return
	if u.get('routing',false):
		r.Charges.cancel(r,u,actor)
		actor.personal_order='flee'
	if u.stun>0 or u.petrified>0:return
	if r.elapsed<actor.get('contact_recovery',0.):actor.velocity=Vector2.ZERO;return
	if actor.has('charge_run'):
		r.Charges.step(r,row,occupied,dt);return
	var previous_velocity: Vector2=actor.get('velocity',Vector2.ZERO)
	brake_for_attack(r,row,previous_velocity,dt)
	var reaction: Dictionary=u.get('slot_states',{}).get(slot,{})
	if not reaction.is_empty() and r.elapsed<reaction.start+reaction.get('hold',0.)+reaction.get('recover',0.):actor.velocity=Vector2.ZERO;return
	if actor.get('shield_wall',false) and actor.personal_order=='hold' and actor.has('wall_slot'):
		actor.wall_off_slot=actor.get('wall_off_slot',0.)+dt if actor.position.distance_to(actor.wall_slot)>17. else 0.
		if actor.wall_off_slot>=.5 and r.elapsed>=actor.get('gap_until',0.) and r.elapsed>=actor.get('return_check',0.):
			actor.return_check=r.elapsed+.2
			var return_path=[] if return_occupied(row,occupied) else r.terrain.leg(navigator(r,u.kind,u),actor.position,actor.wall_slot)
			if not return_path.is_empty():r.Walls.assign(actor,actor.wall_slot,return_path)
			actor.wall_off_slot=0.
	var order: String=actor.personal_order
	var goal: Vector2=actor.position
	var wall_ready: bool=actor.get('shield_wall',false) and actor.position.distance_to(actor.get('wall_slot',actor.position))<3.
	if wall_ready and order=='move':
		actor.wall_settle=actor.get('wall_settle',0.)+dt
		if actor.wall_settle>=1.:actor.personal_order='hold';actor.path=[]
	elif actor.get('shield_wall',false):actor.wall_settle=0.
	var holding: bool=order=='hold' or actor.get('shield_wall',false)
	var target={}
	var mobile=mounted_ranged(u) and not holding
	if mobile:
		if order=='idle':
			if scan_due(r,actor,dt,false):
				var seen=personal_target(r,u,slot,actor,target_counts,true,true)
				if not seen.is_empty() and seen.near.distance<=effective_range(r,u,seen.unit):start_mounted_shot(r,u,actor,seen,target_counts)
			return
		if order=='attack':
			if actor.target_id<0:
				target=personal_target(r,u,slot,actor,target_counts)
			else:target=identified_target(r,u,slot,actor.target_id,actor.target_slot)
			if target.is_empty():
				lost_pursuit_target(u,actor,target_counts);return
		if order in ['move','attack_move','attack','auto']:mounted_fire(r,u,slot,actor,target_counts)
		if order=='attack':
			# Original pursuit caches its target before mounted fire may select a different shot target.
			if not target.is_empty():
				actor.heading=target.near.heading
				retarget_pursuit(r,u,slot,actor,target,target_counts,dt)
				goal=ground_position(r,target.unit,target.near.slot)
		elif order=='auto':goal=r.autonomous_destination(u,actor)
	else:
		var current=identified_target(r,u,slot,actor.get('target_id',-1),actor.get('target_slot',-1))
		if not holding and order in ['auto','idle','attack','attack_move'] and actor.get('target_id',-1)>=0 and current.is_empty():
			if order=='attack':lost_pursuit_target(u,actor,target_counts)
			else:remember_target(u,actor,{},target_counts)
			if order=='attack_move':actor.aggro_timer=.1
			actor.velocity=previous_velocity
			return
		var scan=true
		if (order in ['hold','auto','idle','attack_move'] or wall_ready) and (holding or current.is_empty()):scan=scan_due(r,actor,dt,holding)
		# Holding only replaces its aim on a ready acquisition visit; release uses that stored aim.
		if order=='hold' and (not scan or actor.cooldown>0.):return
		target=personal_target(r,u,slot,actor,target_counts,scan) if (order in ['hold','auto','idle','attack','attack_move'] or wall_ready) and r.config.types[u.kind].has('individual') else {}
		if order=='auto' and u.get('individual_auto',false) and not target.is_empty() and not r.autonomous_engagement(u,actor,target):target={}
		if order=='auto' and target.is_empty() and u.get('individual_auto',false):goal=r.autonomous_destination(u,actor)
		if not holding and order in ['auto','idle','attack_move'] and current.is_empty() and not target.is_empty() and target.unit.kind!='decoy':
			var ranged_ally: bool=u.side=='ally' and ranged(u)
			if ranged_ally and target.near.distance<=effective_range(r,u,target.unit):actor.attack_engaged=Vector2i(target.unit.id,target.near.slot)
			if not (ranged_ally and order=='attack_move'):
				actor.velocity=previous_velocity
				return
			# Ranged attack-move finishes its navigation step when acquisition changes state.
			target={}
		if not target.is_empty():
			actor.move_settle=0.
			var stats: Dictionary=individual(r,u)
			if not holding:actor.heading=target.near.heading
			if actor.has('attack_engaged') and target.near.distance>engagement_range(r,u,actor,target.unit,target.near.slot):
				actor.erase('attack_engaged')
				if u.side=='ally' and ranged(u) and order!='hold':
					remember_target(u,actor,{},target_counts)
					if order=='attack':actor.personal_order='idle'
					actor.next_scan=r.elapsed+.1
					actor.velocity=previous_velocity
					return
				if not holding:
					actor.velocity=previous_velocity
					return
			if target.near.distance<=engagement_range(r,u,actor,target.unit,target.near.slot) and target.near.distance>=stats.get('minimum_range',0.):
				if holding and not scan:return
				if target.unit.kind=='decoy':
					if actor.cooldown<=0:
						var combat: Dictionary=(u.combat_stats if u.has('combat_stats') else r.config.types[u.kind])
						actor.cooldown=combat.interval;actor.attack_age=0.;actor.heading=target.near.heading
						var dealt=r.hurt(target.unit,combat.damage,u.kind)
						r.events.append({'kind':'hit','attacker':u.id,'attacker_slot':slot,'target':target.unit.id,'damage':dealt,'pos':target.unit.pos,'from':actor.position})
					return
				# Enter attack state now; braking and windup belong to its next simulation step.
				if not holding and not actor.has('attack_engaged'):
					actor.attack_engaged=Vector2i(target.unit.id,target.near.slot)
					actor.velocity=previous_velocity
					return
				brake_for_attack(r,row,previous_velocity,dt)
				if order=='hold' or actor.get('shield_wall',false) or ranged(u) or actor.velocity.length_squared()<25.:
					attack(r,u,target.unit,slot,target.near.slot)
				return
			if order!='hold':
				retarget_pursuit(r,u,slot,actor,target,target_counts,dt)
				if target.near.distance<stats.get('minimum_range',0.):goal=actor.position-target.near.heading*(stats.minimum_range-target.near.distance+10.)
				else:goal=actor.position+target.near.heading*maxf(0,target.near.distance-effective_range(r,u,target.unit)*.85)
		elif order=='attack':actor.personal_order='idle';actor.next_scan=0.
	if wall_ready:return
	if target.is_empty() and order in ['move','attack_move']:
		var formation_slot=r.has_method('strategy_paths') and actor.has('form_goal')
		# Authored intermediate waypoints stay exact; only the final ordinary goal settles early.
		if not actor.get('shield_wall',false) and actor.path.size()==1:
			var distance: float=actor.position.distance_to(actor.path[0])
			if distance<(3. if formation_slot else 17.):
				actor.move_settle=actor.get('move_settle',0.)+dt
				if actor.move_settle>=.5:
					actor.personal_order='idle';actor.path=[];actor.next_scan=0.;actor.settled_position=actor.position
					actor.route_progress=actor.get('route_progress',0)+actor.get('route_stops',[]).size();actor.route_stops=[]
				return
			if distance>=34.:actor.move_settle=0.
		if not formation_slot and not actor.get('shield_wall',false) and sibling_settled(row):
			actor.personal_order='idle';actor.path=[];actor.next_scan=0.;actor.settled_position=actor.position;actor.settled_by_sibling=true
			actor.route_progress=actor.get('route_progress',0)+actor.get('route_stops',[]).size();actor.route_stops=[]
			return
		while not actor.path.is_empty() and actor.position.distance_to(actor.path[0])<.05:
			var reached: Vector2=actor.path.pop_front()
			var stops: Array=actor.get('route_stops',[])
			if not stops.is_empty() and reached.is_equal_approx(stops[0]):
				stops.pop_front();actor.route_progress=actor.get('route_progress',0)+1
		if actor.path.is_empty():actor.personal_order='hold' if actor.get('shield_wall',false) else 'idle'
		else:goal=actor.path[0]
	elif order=='bombard':
		goal=r.Structures.approach(r,row)
	elif order=='regroup':
		goal=u.pos+r.ground_basis.affine_inverse().basis_xform(r.Contact.formation_feet(r,u)[slot])
		if actor.position.distance_to(goal)<.05:
			r.personal_target_bounds.erase(u.id)
			actor.erase('position');actor.erase('personal_order');actor.erase('velocity');return
	elif order=='flee':
		goal=Vector2(actor.position.x,r.bounds.end.y-30. if u.side=='ally' else r.bounds.position.y+30.) if r.square_battle else Vector2(r.bounds.position.x+30. if u.side=='ally' else r.bounds.end.x-30.,actor.position.y)
	if u.rooted>0 or actor.position.is_equal_approx(goal):return
	var nav=navigator(r,u.kind,u)
	if not r.terrain.clear_segment(nav,actor.position,goal):
		var path: Array=actor.get('steer_path',[])
		while path.size()>1 and actor.position.distance_to(path[0])<3.:path.pop_front()
		var changed: bool=actor.get('steer_goal',Vector2.INF).distance_squared_to(goal)>2500.
		if path.is_empty() or changed or not r.terrain.clear_segment(nav,actor.position,path[0]):
			if not changed and path.is_empty() and r.elapsed<actor.get('steer_retry',0.):return
			path=r.terrain.leg(nav,actor.position,goal)
			actor.steer_path=path;actor.steer_goal=goal;actor.steer_retry=r.elapsed+.1
		if path.is_empty():return
		goal=path[0]
	else:actor.erase('steer_path')
	var speed: float=(u.combat_stats if u.has('combat_stats') else r.config.types[u.kind]).speed*r.powers.speed_multiplier(u)
	if r.has_method('personal_speed'):speed*=r.personal_speed(u)
	if not mobile and not target.is_empty() and target.near.distance>effective_range(r,u,target.unit):
		var reach: float=effective_range(r,u,target.unit)
		if target.near.distance<reach*1.2:speed*=clampf((target.near.distance-reach*.9)/(reach*.3),.35,1.)
		var braking=speed*(.85 if u.kind=='cavalry' else .4)
		if target.near.distance<braking:speed*=clampf(target.near.distance/braking,0.,1.)
	if order=='flee':speed*=1.35
	if actor.get('shield_wall',false):speed=minf(speed,r.config.battle_commands.shield_march_speed)
	var direction=actor.position.direction_to(goal)
	var wanted=direction*speed
	var acceleration=speed/0.45 if r.has_method('strategy_paths') else 1200.
	var velocity=previous_velocity.move_toward(wanted,acceleration*dt)
	velocity=velocity.limit_length(110. if actor.get('shield_wall',false) else (u.combat_stats if u.has('combat_stats') else r.config.types[u.kind]).speed+60.)
	var step=minf(velocity.length()*dt,actor.position.distance_to(goal))
	if not velocity.is_zero_approx():direction=velocity.normalized()
	actor.heading=actor.wall_heading if actor.get('shield_wall',false) else direction
	actor.velocity=direction*step/dt

static func prepare_neighbours(r,occupied: Array,dt: float):
	# Broad phase only. Exact collision still reads the live point of every nearby person.
	var cells={};var widest=0.;var fastest: float=r.config.individual_charge.speed*2.
	for u in r.units:
		fastest=maxf(fastest,(u.combat_stats if u.has('combat_stats') else r.config.types[u.kind]).speed*r.powers.speed_multiplier(u)*1.35)
	for row in occupied:
		var cell=Vector2i((row.point/64.).floor())
		if not cells.has(cell):cells[cell]=[]
		cells[cell].append(row);widest=maxf(widest,row.radius)
	for row in occupied:
		var padding=Vector2.ONE*(row.radius+widest+.6*maxf(row.radius,widest)+2.*fastest*dt)
		var low=Vector2i(((row.point-padding)/64.).floor());var high=Vector2i(((row.point+padding)/64.).floor())
		var neighbours=[]
		for y in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):neighbours.append_array(cells.get(Vector2i(x,y),[]))
		row.neighbours=neighbours

static func personal_fled(r,u: Dictionary) -> bool:
	for actor in u.soldiers:
		if actor.hp<=0 or not actor.has('position'):continue
		var coordinate: float=actor.position.y if r.square_battle else actor.position.x
		var boundary: float=(r.bounds.end.y if u.side=='ally' else r.bounds.position.y) if r.square_battle else (r.bounds.position.x if u.side=='ally' else r.bounds.end.x)
		if absf(coordinate-boundary)>31.:return false
	return true
