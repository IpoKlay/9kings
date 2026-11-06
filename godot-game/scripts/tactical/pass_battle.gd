extends "res://scripts/tactical/trial_rules.gd"
## Shared battle rules for manual deployment and all formation presets.
var flag_center: Vector2
var flag_radius: float
var capture_seconds: float
var capture_time=0.0
var flag_state='secure'
var outcome=''
var journal: Array[Dictionary]=[]
var capture_contested=false
var flank_captor=false
var defender_preset=false
var flank_state='reserve'
var signal_time=0.0
var assault: Dictionary=config.pass_assault
var barrels: Array=[]
var routed={'ally':0,'enemy':0}

func _init(test_powers: bool=false):
	super(test_powers)
	flag_center=pass_layout_data.flag
	flag_radius=config.pass_standard.radius
	capture_seconds=config.pass_standard.capture_seconds
	terrain=preload('res://scripts/tactical/pass_terrain.gd').new(projection,bounds,config.types,pass_layout_data)
	enemy_wait=0
	for p in pass_layout_data.OilBarrels:
		barrels.append({'pos':p,'state':'ready','age':0.0,'from':Vector2.ZERO})

func start() -> bool:
	if not super.start():return false
	record_event('deployed',{'count':alive('ally').size()})
	return true

func record_event(kind: String, facts: Dictionary={}):
	var entry=facts.duplicate()
	entry.kind=kind
	entry.time=elapsed
	journal.append(entry)

func key_event() -> Dictionary:
	# Prefer the decisive flag episode, then a rout or a witnessed flank maneuver.
	var tactical_highlight='rear_archers' if outcome=='enemy_routed' else 'flank_divert'
	for kind in ['captured','relieved','flag_contested',tactical_highlight,'general_rout','last_regiment','flank_through','flank_divert','flag_threat','held_line','flank_signal','deployed']:
		for i in range(journal.size()-1,-1,-1):
			if journal[i].kind==kind:return journal[i]
	return {}

func deploy_defenders() -> bool:
	if phase!='deploy' or not alive('ally').is_empty():return false
	combined_arms=false
	defender_preset=true
	units.clear()
	next_id=0
	deployment=pass_layout_data.DefenderDeployment
	for slot in pass_layout_data.PassAllies:deploy(slot[0],slot[1])
	for slot in pass_layout_data.PassEnemies:spawn(slot[0],'enemy',slot[1])
	for u in alive('ally'):u.order='hold'
	return true

func deploy_escort(campaign, building: Dictionary):
	if building.is_empty():return
	var kind: String=building.type
	var spot: Vector2=pass_layout_data.escort
	spawn(kind,'ally',spot)
	var u: Dictionary=units.back()
	u.order='hold'
	u.escort=true
	var derived: Dictionary=campaign.stats(building)
	var base: Dictionary=campaign.types[kind]
	u.max_hp*=float(derived.hp)/float(base.hp)
	u.hp=u.max_hp
	var stats: Dictionary=config.types[kind].duplicate()
	if base.attack>0:stats.damage*=float(derived.attack)/float(base.attack)
	if kind=='medic':stats.heal*=float(derived.heal)/float(base.heal)
	stats.interval*=float(derived.interval)/float(base.interval)
	u.camp_shield=campaign.starting_shield(building)*config.types[kind].hp/base.hp
	u.camp_damage_taken=1.0
	var testudo: int=campaign.order_rank('testudo') if kind=='legion' else 0
	if testudo>0:
		stats.speed*=campaign.effects.testudo.speed_multiplier
		u.camp_damage_taken=campaign.testudo_damage(testudo)
	u.combat_stats=stats

func reserve_squads(ids: Array):
	var recalled=alive('ally').filter(func(u):return u.id in ids and not u.get('escort',false))
	super(recalled.map(func(u):return u.id))

func spawn(kind: String,side: String,pos: Vector2):
	super(kind,side,pos)
	var u: Dictionary=units.back()
	u.morale=100.0
	u.routing=false
	u.escaped=false
	u.general=kind=='legion' and not units.any(func(other):return other.id!=u.id and other.side==side and other.general)

func alive(side: String) -> Array:
	return units.filter(func(u):return u.side==side and u.hp>0 and not u.routing)

func hurt(u: Dictionary, damage: float, source_kind: String='', morale_shock: float=0.0) -> float:
	if u.get('escort',false):
		damage*=u.camp_damage_taken
		var absorbed=minf(u.camp_shield,damage)
		u.camp_shield-=absorbed
		damage-=absorbed
	var dealt=super(u,damage,source_kind)
	if dealt>0 and u.has('morale') and not u.routing:
		u.morale-=dealt/u.max_hp*(106 if u.general else 125)+morale_shock
		if u.hp<=0 or u.morale<=0:
			u.routing=true
			if u.hp>0:routed[u.side]+=1
			if u.general:
				if u.hp>0:
					record_event('general_rout',{'side':u.side,'unit_id':u.id})
				for other in alive(u.side):
					other.morale=maxf(1,other.morale-18)
			if alive(u.side).is_empty():record_event('last_regiment',{'side':u.side,'unit_id':u.id,'regiment':u.kind,'routed':u.hp>0})
	return dealt

func deal_blow(attacker: Dictionary,target: Dictionary,damage: float,contact: Dictionary={}) -> Dictionary:
	var hit=super.deal_blow(attacker,target,damage,contact)
	if hit.is_empty():return hit
	if attacker.side=='ally' and target.kind=='archer' and hit.kind=='flanking_charge' and hit.sector=='rear' and hit.damage>0:
		record_event('rear_archers',{'damage':hit.damage,'attacker':attacker.id,'target':target.id})
	return hit

func barrel_at(pos: Vector2) -> Dictionary:
	for b in barrels:
		var local=ground_basis.basis_xform(pos-b.pos)
		if b.state=='ready' and Rect2(-24,-34,49,50).has_point(local):return b
	return {}

func move_oil(index: int,pos: Vector2) -> bool:
	if phase!='deploy' or index<0 or index>=barrels.size():return false
	if not pass_layout_data.OilPlacement.has_point(pos):return false
	for other in barrels:
		if other!=barrels[index] and other.pos.distance_to(pos)<115:return false
	barrels[index].pos=pos
	return true

func ignite(b: Dictionary) -> bool:
	if phase!='battle' or b.is_empty() or b.state!='ready':return false
	for archer in alive('ally'):
		if archer.kind=='archer' and archer.pos.distance_to(b.pos)<=640:
			b.state='arrow'
			b.age=0
			b.from=archer.pos
			archer.attack_age=0
			archer.heading=archer.pos.direction_to(b.pos)
			events.append({'kind':'arrow','pos':b.pos,'from':archer.pos})
			return true
	return false

func step(dt: float):
	if phase!='battle':return
	update_flank()
	for b in barrels:
		b.age+=dt
		if b.state=='arrow' and b.age>=.4:
			b.state='burn'
			b.age=0
			events.append({'kind':'charge','pos':b.pos})
			for u in units:
				if u.hp>0 and not u.routing and u.pos.distance_to(b.pos)<=161:
					hurt(u,285)
					u.stun=maxf(u.stun,.8)
		elif b.state=='burn':
			if b.age>=4:b.state='ash'
			else:
				for u in units:
					if u.hp>0 and not u.routing and u.pos.distance_to(b.pos)<=161:hurt(u,60*dt)
	for u in units:
		if u.routing and u.hp>0 and not u.escaped:
			var sign_x=-1 if u.side=='ally' else 1
			u.facing=sign_x
			u.heading=Vector2(sign_x,0)
			var distance=float(config.types[u.kind].speed)*1.35*dt
			var exit_point=Vector2(bounds.position.x+1 if sign_x<0 else bounds.end.x-1,u.pos.y)
			var retreat=travel_target(u,exit_point)
			var next: Vector2=u.pos.move_toward(retreat,distance)
			if u.pos.distance_to(exit_point)<2:next=u.pos+Vector2(sign_x*distance,0)
			if not may_advance(u,next,false):continue
			u.pos=next
			u.march_distance+=distance
			u.moving=true
			u.attack_age=10
			if not bounds.has_point(u.pos):u.escaped=true
	super(dt)

func inside_flag(unit: Dictionary) -> bool:
	return flag_center.distance_squared_to(unit.pos)<=flag_radius*flag_radius

# Lane gates are in the same projected plane as the terrain and the rank footprints.
func flank_entry() -> Vector2:
	return terrain.inverse*(Vector2(terrain.SIDE_GATE.end.x+18,terrain.SIDE_GATE.get_center().y))

func side_is_blocked() -> bool:
	for defender in alive('ally'):
		if terrain.touches_gate(defender.kind,defender.pos):return true
	return false

func update_flank():
	var riders=alive('enemy').filter(func(u):return u.kind=='cavalry' and u.order=='auto')
	if riders.is_empty():
		if flank_state!='reserve':flank_state='ended'
		return
	if flank_state=='reserve' and elapsed>=float(assault.signal_at):
		flank_state='warning'
		signal_time=elapsed
		record_event('flank_signal')
		events.append({'kind':'flank_signal','pos':flank_entry()})
	elif flank_state=='warning' and elapsed-signal_time>=float(assault.warning_seconds):
		var crossing=terrain.inverse*terrain.SIDE_GATE.get_center()
		flank_state='divert' if side_is_blocked() or terrain.leg('cavalry',riders[0].pos,crossing).is_empty() else 'crossing'
		if flank_state=='divert':record_event('flank_divert')
	elif flank_state=='crossing' and side_is_blocked():
		flank_state='divert'
		record_event('flank_divert')

func lane_goal(u: Dictionary, side_lane: bool) -> Vector2:
	var pos: Vector2=projection*u.pos
	var gate: Rect2=terrain.SIDE_GATE if side_lane else terrain.main_pass
	var y=gate.get_center().y if side_lane else gate.position.y+gate.size.y*(92.+80.*(u.id%3))/329.
	var entry=Vector2(gate.end.x+190,y)
	var exit_point=Vector2(gate.position.x-175,y)
	var lane='side' if side_lane else 'front'
	if u.get('lane','')!=lane:
		u.lane=lane
		u.lane_stage=0 if pos.x>entry.x else 1
		if pos.x<=exit_point.x:u.lane_stage=2
		u.erase('steer_corner')
	if u.lane_stage==0:
		if pos.distance_to(entry)>6:return terrain.inverse*entry
		u.lane_stage=1
	if u.lane_stage==1:
		if pos.distance_to(exit_point)>6:return terrain.inverse*exit_point
		u.lane_stage=2
		if side_lane:
			flank_state='through'
			u.cleared_side_gate=true
			record_event('flank_through',{'unit_id':u.id})
	return flag_center

func supporting_goal(u: Dictionary) -> Vector2:
	var leader: Dictionary={}
	var nearest=INF
	for unit in alive('enemy'):
		if unit.kind not in ['legion','spear','guard']:continue
		var distance: float=unit.pos.distance_to(flag_center)
		if distance<nearest:
			nearest=distance
			leader=unit
	if leader.is_empty():return lane_goal(u,false)
	var axis=flag_center.direction_to(leader.pos)
	var wing=1 if u.id%2==0 else -1
	var point: Vector2=leader.pos+axis*float(assault.archer_trail)+axis.orthogonal()*60*wing
	point=point.clamp(bounds.position,bounds.end-Vector2.ONE)
	return point if terrain.clear_segment(u.kind,point,point) else leader.pos

func combat_target(u: Dictionary) -> Dictionary:
	var preferred=super.combat_target(u)
	if u.side!='enemy' or u.order!='auto' or u.kind=='medic':return preferred
	if preferred.get('kind','')=='decoy':return preferred
	u.obstruction=''
	u.target_id=-1
	var nearest=INF
	var local: Dictionary={}
	var melee: bool=u.kind in ['legion','guard','spear','cavalry']
	for defender in alive('ally'):
		var distance: float=u.pos.distance_to(defender.pos)
		if distance>=nearest:continue
		if distance<=float(config.types[u.kind].range) or (melee and in_formation_contact(u,defender)):
			local=defender
			nearest=distance
	if not local.is_empty():
		if melee:
			u.obstruction='contact'
			u.target_id=local.id
		return local
	return preferred

func advance_objective(u: Dictionary, target: Dictionary, dt: float) -> bool:
	if u.side!='enemy' or u.order!='auto' or u.kind=='medic':return false
	if not target.is_empty() and u.pos.distance_to(target.pos)<=attack_reach(u,target):return false
	if u.rooted>0 or inside_flag(u):return true
	var goal: Vector2
	if u.kind=='cavalry':
		if flank_state in ['reserve','warning']:return true
		goal=lane_goal(u,flank_state in ['crossing','through'])
	elif u.kind in ['archer','siege']:
		goal=supporting_goal(u)
	else:
		goal=lane_goal(u,false)
	var previous: Vector2=u.pos
	var steer=travel_target(u,goal)
	var speed: float=config.types[u.kind].speed*powers.speed_multiplier(u)
	var approaching=terrain.crosses(terrain.SIDE_GATE,projection*u.pos,projection*goal)
	if u.kind=='cavalry':
		ride(u,steer,speed,dt,{},approaching)
		return true
	var next: Vector2=u.pos.move_toward(steer,speed*dt)
	if may_advance(u,next,true,approaching):
		u.pos=next
		record_march(u,previous)
	return true

func resolve_battle(dt: float):
	var attackers=alive('enemy')
	var defenders=alive('ally')
	var previous=flag_state
	if not attackers.any(inside_flag):
		if capture_time>0:record_event('relieved',{'seconds':capture_time})
		capture_contested=false
		flank_captor=false
		flag_state='secure'
		capture_time=0.0
	elif defenders.any(inside_flag):
		flag_state='contested'
	else:
		flag_state='capturing'
		capture_time=minf(capture_seconds,capture_time+dt)
	if flag_state!='secure':
		if previous=='secure':record_event('flag_threat')
		if flag_state=='contested' and previous=='capturing':
			capture_contested=true
			record_event('flag_contested',{'seconds':capture_time})
		if not flank_captor:
			flank_captor=attackers.any(func(u):return u.get('cleared_side_gate',false) and inside_flag(u))
	# Resolve once, after movement, damage and routs for this simulation step.
	if attackers.is_empty():
		outcome='enemy_routed'
		phase='victory'
	elif capture_time>=capture_seconds-1e-8:
		capture_time=capture_seconds
		record_event('captured',{'seconds':capture_time,'contested':capture_contested,'flank':flank_captor})
		outcome='flag_lost'
		phase='defeat'
	elif defenders.is_empty() and not reserve.values().any(func(stock):return stock>0):
		outcome='defenders_routed'
		phase='defeat'
	elif elapsed>=float(config.duration)-1e-8:
		if not defenders.is_empty():record_event('held_line',{'count':defenders.size()})
		outcome='defenders_routed' if defenders.is_empty() else 'time_held'
		phase='defeat' if defenders.is_empty() else 'victory'


func strength(side: String) -> float:
	var value=0.0
	for u in alive(side):value+=u.hp/u.max_hp*float(config.types[u.kind].soldiers)
	return value
