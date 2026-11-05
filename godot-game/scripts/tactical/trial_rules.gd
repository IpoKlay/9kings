extends RefCounted
## Self-contained trial state; never reads or writes expedition progress.
var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string('res://data/balance/tactical_trial.json'))
const MythPowers=preload('res://scripts/tactical/myth_powers.gd')
var powers=MythPowers.new()
var bounds: Rect2
var deployment: Rect2
var units: Array = []
var reserve: Dictionary
var phase = 'deploy'
var elapsed = 0.0
var enemy_wait=50.0
var charges: int
var cooldown = 0.0
var events: Array = []
var next_id = 0
var deity='zeus'
var characters: Array=JSON.parse_string(FileAccess.get_file_as_string('res://data/content/myth_vfx.json')).characters
var waves: Array=[]
var stones: Array=[]
var unlimited_powers=false
var combined_arms := false
const PassTerrain=preload("res://scripts/tactical/pass_terrain.gd")
var terrain: PassTerrain
var ground_basis: Transform2D
var projection: Transform2D

func _init(use_testing_rules: bool=true):
	var field: Dictionary=preload('res://scripts/data/catalog.gd').presentation('field')
	ground_basis=Transform2D(Vector2(field.projection_x[0],field.projection_y[0]),Vector2(field.projection_x[1],field.projection_y[1]),Vector2.ZERO)
	projection=ground_basis
	projection.origin=Vector2(960,560)-ground_basis*Vector2(930,550)
	var dimensions: Array=config.battlefield.bounds
	bounds=Rect2(dimensions[0],dimensions[1],dimensions[2],dimensions[3])
	dimensions=config.battlefield.deployment
	deployment=Rect2(dimensions[0],dimensions[1],dimensions[2],dimensions[3])
	powers.bounds=bounds
	unlimited_powers=use_testing_rules and bool(config.get("testing",{}).get("unlimited_powers",false))
	reserve = config.reserve.duplicate()
	charges = int(config.lightning.charges)
	for row in config.enemies: spawn(row[0], 'enemy', Vector2(row[1], row[2]))

func spawn(kind: String, side: String, pos: Vector2):
	var stats: Dictionary = config.types[kind]
	units.append({'id':next_id, 'kind':kind, 'side':side, 'pos':pos, 'home':pos,
		'hp':float(stats.hp), 'max_hp':float(stats.hp), 'cooldown':0.0, 'stun':0.0,
		'obstruction':'', 'order':'auto', 'destination':pos, 'waypoints':[], 'target_id':-1,
		'heading':Vector2.RIGHT if side=='ally' else Vector2.LEFT, 'march_distance':0.0, 'moving':false, 'attack_age':10.0, 'hit_age':10.0, 'facing':1.0 if side=='ally' else -1.0,
		'shield':0.0,'rooted':0.0,'petrified':0.0,'marked':0.0,'poison':0.0,'regen':0.0,
		'push':Vector2.ZERO, 'charge':kind=='cavalry','clear_run':0.0, 'dead_age':0.0})
	next_id += 1

func deployment_valid(pos: Vector2, kind: String='legion') -> bool:
	if not deployment.has_point(pos) or (terrain and not terrain.clear_segment(kind,pos,pos)):return false
	for u in units:
		if u.hp>0 and u.pos.distance_to(pos)<100: return false
	return true

func deploy(kind: String, pos: Vector2) -> bool:
	if phase not in ['deploy','battle'] or not reserve.has(kind) or reserve[kind]<=0 or not deployment_valid(pos,kind): return false
	reserve[kind] -= 1
	spawn(kind,'ally',pos)
	return true

func deploy_vanguard() -> bool:
	if phase!='deploy' or not alive('ally').is_empty():return false
	for slot in config.battlefield.vanguard:
		deploy(slot[0],Vector2(slot[1],slot[2]))
	return true

func deploy_combined() -> bool:
	if phase!='deploy' or not alive('ally').is_empty():return false
	combined_arms=true
	var area: Array=config.battlefield.combined_deployment
	deployment=Rect2(area[0],area[1],area[2],area[3])
	units.clear()
	for slot in config.battlefield.combined_enemy:
		spawn(slot[0],'enemy',Vector2(slot[1],slot[2]))
	for slot in config.battlefield.combined:
		deploy(slot[0],Vector2(slot[1],slot[2]))
	return true

func reserve_squads(ids: Array):
	if phase!='deploy':return
	for squad in alive('ally'):
		if squad.id in ids:
			reserve[squad.kind]+=1
			units.erase(squad)

# A click shifts the complete formation; dragging specifies the two ends of a rank.
func layout_positions(ids: Array, anchor: Vector2, end: Vector2, line: bool) -> Dictionary:
	var squads=alive('ally').filter(func(u):return u.id in ids)
	var slots={}
	if squads.is_empty():return slots
	var center=Vector2.ZERO
	for u in squads:center+=u.pos
	center/=squads.size()
	if line:
		var axis=anchor.direction_to(end)
		squads.sort_custom(func(a,b):return a.pos.dot(axis)<b.pos.dot(axis))
	for i in squads.size():
		var u=squads[i]
		var slot: Vector2=u.pos+anchor-center
		if line:
			slot=end if squads.size()==1 else anchor.lerp(end,float(i)/(squads.size()-1))
		slots[u.id]=slot
	return slots

func layout_valid(slots: Dictionary) -> bool:
	if phase!='deploy' or slots.is_empty():return false
	var occupied: Array=[]
	for u in alive('ally'):
		if not slots.has(u.id):occupied.append(u.pos)
		elif terrain and not terrain.clear_segment(u.kind,slots[u.id],slots[u.id]):return false
	for pos in slots.values():
		if not deployment.has_point(pos):return false
		for other in occupied:
			if pos.distance_to(other)<100:return false
		occupied.append(pos)
	return true

func place_layout(slots: Dictionary) -> bool:
	if not layout_valid(slots):return false
	for u in alive('ally'):
		if slots.has(u.id):
			u.pos=slots[u.id]
			u.home=u.pos
			u.destination=u.pos
	return true

func start() -> bool:
	if phase!='deploy' or alive('ally').is_empty(): return false
	phase='battle'
	return true

func alive(side: String) -> Array:
	return units.filter(func(u): return u.hp>0 and u.side==side)

func select_deity(id: String) -> bool:
	if phase not in ['deploy','battle'] or (phase=='battle' and not unlimited_powers): return false
	if not characters.any(func(c):return c.id==id):return false
	deity=id
	if phase=='deploy':charges=int(power_config().charges)
	return true

func power_config() -> Dictionary:
	if deity=='poseidon':return config.sea_wave
	return powers.config[deity] if powers.config.has(deity) else config.lightning

func wave_start(pos: Vector2) -> Vector2:
	var length: float=config.sea_wave.length
	return Vector2(clampf(pos.x-length/2,bounds.position.x,bounds.end.x-length),clampf(pos.y,bounds.position.y+config.sea_wave.width/2,bounds.end.y-config.sea_wave.width/2))

func power_available() -> bool:
	return unlimited_powers or (charges>0 and cooldown<=0)

func strike(pos: Vector2) -> bool:
	if phase!='battle' or not power_available() or not bounds.has_point(pos): return false
	if not unlimited_powers:
		charges-=1
		cooldown=float(power_config().cooldown)
	if deity=='poseidon':
		var start_pos=wave_start(pos)
		waves.append({'start':start_pos,'age':0.0,'hit':[]})
		events.append({'kind':'sea_wave','character':deity,'pos':start_pos})
		return true
	if deity!='zeus':
		powers.cast(deity,pos)
		events.append({'kind':'myth_cast','character':deity,'pos':pos})
		return true
	for u in alive('enemy'):
		if u.pos.distance_to(pos)<=float(config.lightning.radius):
			hurt(u,float(config.lightning.damage))
			u.stun=float(config.lightning.stun)
			u.hit_age=0.0
	events.append({'kind':'lightning','character':deity,'pos':pos})
	return true

func advance_waves(dt: float):
	var q: Dictionary=config.sea_wave
	for wave in waves:
		wave.age+=dt
		var reach: float=minf(1,wave.age/float(q.travel_seconds))*float(q.length)
		for u in alive('enemy'):
			var local: Vector2=u.pos-wave.start
			if u.id not in wave.hit and local.x>=0 and local.x<=reach and absf(local.y)<=float(q.width)/2:
				wave.hit.append(u.id)
				hurt(u,float(q.damage))
				u.stun=float(q.stun)
				u.hit_age=0
				u.push=Vector2(float(q.push),0)
	waves=waves.filter(func(wave):return wave.age<float(q.travel_seconds))

func hurt(u: Dictionary, damage: float, source_kind: String='', _morale_shock: float=0.0) -> float:
	if u.hp<=0:return 0.0
	if u.get('shield',0)>0:damage*=1.0-float(powers.config.athena.reduction)
	if source_kind=='archer' and u.get('marked',0)>0:damage*=float(powers.config.artemis.archer_bonus)
	var dealt=minf(u.hp,maxf(0,damage))
	u.hp-=dealt
	if dealt>0:u.hit_age=0.0
	return dealt

func command(ids: Array, order: String, destination: Vector2, target_id: int=-1) -> bool:
	if phase!='battle' or order not in ['move','attack','hold','auto']:return false
	var squads=alive('ally').filter(func(unit):return unit.id in ids)
	if squads.is_empty():return false
	var center=Vector2.ZERO
	var formation=Rect2(squads[0].pos,Vector2.ZERO)
	for squad in squads:
		center+=squad.pos
		formation=formation.expand(squad.pos)
	center/=squads.size()
	var shift=(destination-center).clamp(bounds.position-formation.position,bounds.end-formation.end)
	var paths={}
	if order=='move':
		for squad in squads:
			var goal: Vector2=squad.pos+shift
			var plan=plan_route(squad,[],goal.clamp(bounds.position,bounds.end-Vector2(.001,.001)))
			if not plan.ok:return false
			paths[squad.id]=plan.points
	for squad in squads:
		squad.obstruction=''
		squad.target_id=target_id
		squad.order=order
		squad.waypoints.clear()
		if order=='move':set_march(squad,paths[squad.id])
		else:squad.destination=squad.pos+shift
	return true

func plan_route(squad: Dictionary, via: Array[Vector2], goal: Vector2) -> Dictionary:
	var points: Array[Vector2]=[]
	var start: Vector2=squad.pos
	var stops=via.duplicate()
	stops.append(goal)
	for stop in stops:
		if not bounds.has_point(stop):return {'ok':false,'points':points,'blocked':stop}
		if terrain:
			var leg=terrain.leg(squad.kind,start,stop)
			if leg.is_empty():
				var blocked=stop if not terrain.clear_segment(squad.kind,stop,stop) else terrain.first_blocker(squad.kind,start,stop)
				return {'ok':false,'points':points,'blocked':blocked}
			points.append_array(leg)
		else:points.append(stop)
		start=stop
	return {'ok':true,'points':points}

func set_march(squad: Dictionary, points: Array[Vector2]):
	squad.order='move'
	squad.obstruction=''
	squad.target_id=-1
	squad.leg_start=squad.pos
	squad.destination=points[0]
	squad.waypoints=points.slice(1)

func march_route(id: int, via: Array[Vector2], goal: Vector2) -> bool:
	if phase!='battle':return false
	for squad in alive('ally'):
		if squad.id!=id:continue
		var plan=plan_route(squad,via,goal)
		if not plan.ok:return false
		set_march(squad,plan.points)
		return true
	return false

# Only the single-file side gate imposes a queue. A unit moving away can always leave.
func may_advance(u: Dictionary, next: Vector2, traffic: bool=true) -> bool:
	if not terrain:return true
	if not terrain.clear_segment(u.kind,u.pos,next):return false
	var approaching=u.order=='move' and terrain.crosses(terrain.SIDE_GATE,projection*u.leg_start,projection*u.destination)
	if traffic and (approaching or terrain.touches_gate(u.kind,next)):
		var motion=projection.basis_xform(next-u.pos)
		for other in units:
			if other.id==u.id or other.side!=u.side or other.hp<=0 or other.get('routing',false):continue
			var gap=projection.basis_xform(other.pos-next)
			var clearance: Vector2=terrain.extents[u.kind]+terrain.extents[other.kind]
			if absf(gap.x)<clearance.x and absf(gap.y)<clearance.y and gap.dot(motion)>0:
				u.obstruction='queue'
				return false
	return true

func travel_target(u: Dictionary, goal: Vector2) -> Vector2:
	if not terrain or terrain.clear_segment(u.kind,u.pos,goal):return goal
	var corner: Vector2=u.get('steer_corner',u.pos)
	if u.pos.distance_to(corner)>3 and terrain.clear_segment(u.kind,u.pos,corner):return corner
	var path=terrain.leg(u.kind,u.pos,goal)
	corner=u.pos if path.is_empty() else path[0]
	u.steer_corner=corner
	return corner

func record_march(u: Dictionary, previous: Vector2):
	u.moving=previous!=u.pos
	if not u.moving:return
	var distance=previous.distance_to(u.pos)
	u.march_distance+=distance
	u.heading=previous.direction_to(u.pos)
	if u.kind!='cavalry' or u.charge:return
	# Accumulate a fresh run only on open ground, outside every live enemy formation.
	for other in alive('enemy' if u.side=='ally' else 'ally'):
		var gap: Vector2=other.pos-u.pos
		var reach=attack_reach(u,other)
		if terrain:
			var edges: Vector2=terrain.extents[u.kind]+terrain.extents[other.kind]
			var separation=ground_basis.basis_xform(gap).abs()
			if separation.x<=edges.x and separation.y<=edges.y:
				u.clear_run=0.0
				return
		if gap.length()<=reach:
			u.clear_run=0.0
			return
	if u.order!='move':return
	u.clear_run+=distance
	if u.clear_run>=float(config.directional_combat.rearm_distance):u.charge=true

func impact_side(attacker: Dictionary, target: Dictionary) -> String:
	if not target.has('heading'):return 'front'
	var incoming: Vector2=target.pos.direction_to(attacker.pos)
	if incoming.is_zero_approx():return 'front'
	var alignment: float=target.heading.normalized().dot(incoming)
	if alignment>.5 or is_equal_approx(alignment,.5):return 'front'
	if alignment<-.5 or is_equal_approx(alignment,-.5):return 'rear'
	return 'side'

func deal_blow(attacker: Dictionary,target: Dictionary,damage: float):
	var sector=impact_side(attacker,target)
	var tactics: Dictionary=config.directional_combat
	var kind='arrow' if attacker.kind=='archer' else 'hit'
	var shock=0.0
	if sector=='front' and target.kind in ['legion','guard'] and target.order=='hold':
		damage*=tactics.shield_front
	if attacker.charge:
		attacker.charge=false
		attacker.clear_run=0.0
		damage*=tactics.charge
		kind='charge'
		if sector!='front':
			kind='flanking_charge'
			damage*=tactics[sector].damage
			shock=tactics[sector].morale
	hurt(target,damage,attacker.kind,shock)
	events.append({'kind':kind,'pos':target.pos,'from':attacker.pos,'sector':sector})

# In the large deployment, melee lines engage at their facing edges.
func attack_reach(u: Dictionary, target: Dictionary) -> float:
	var reach:=float(config.types[u.kind].range)
	if u.kind not in ['legion','guard','spear','cavalry'] or target.kind=='decoy':return reach
	var v:=ground_basis.basis_xform(u.pos.direction_to(target.pos)).abs()
	if v.is_zero_approx():return reach
	if terrain and u.obstruction=='contact':
		var edges: Vector2=terrain.extents[u.kind]+terrain.extents[target.kind]
		return maxf(reach,minf(edges.x/maxf(.001,v.x),edges.y/maxf(.001,v.y)))
	if not combined_arms:return reach
	var contact:=minf(250/maxf(.001,v.x),95/maxf(.001,v.y))
	return maxf(reach,contact+(reach-90)*.45)

func separate_lines(dt: float):
	for side in ['ally','enemy']:
		var army:=alive(side)
		for i in army.size():
			var a: Dictionary=army[i]
			for j in range(i+1,army.size()):
				var b: Dictionary=army[j]
				var separation:=ground_basis.basis_xform(b.pos-a.pos)
				var normalized:=separation/Vector2(280,115)
				if normalized.length_squared()>=1:continue
				var movable_a: bool=a.order in ['auto','attack'] and a.rooted<=0 and a.stun<=0 and a.petrified<=0
				var movable_b: bool=b.order in ['auto','attack'] and b.rooted<=0 and b.stun<=0 and b.petrified<=0
				if not movable_a and not movable_b:continue
				var axis:=normalized.normalized() if not normalized.is_zero_approx() else Vector2.DOWN
				var offset:=ground_basis.affine_inverse().basis_xform(axis*Vector2(280,115)-separation)*minf(dt*3,1)/(int(movable_a)+int(movable_b))
				if movable_a and may_advance(a,a.pos-offset,false):a.pos=(a.pos-offset).clamp(bounds.position,bounds.end)
				if movable_b and may_advance(b,b.pos+offset,false):b.pos=(b.pos+offset).clamp(bounds.position,bounds.end)

func wounded_ally(medic: Dictionary) -> Dictionary:
	var best: Dictionary={}
	for candidate in alive(medic.side):
		if candidate.hp>=candidate.max_hp:continue
		var distance: float=medic.pos.distance_to(candidate.pos)
		if medic.order=='hold' and distance>float(config.types.medic.range):continue
		if best.is_empty() or candidate.hp/candidate.max_hp<best.hp/best.max_hp or (is_equal_approx(candidate.hp/candidate.max_hp,best.hp/best.max_hp) and distance<medic.pos.distance_to(best.pos)):
			best=candidate
	return best

func advance_stones(dt: float):
	var stats: Dictionary=config.types.siege
	for shot in stones:
		shot.age+=dt
		if shot.age<stats.flight:continue
		var enemies=alive('enemy' if shot.side=='ally' else 'ally')
		for victim in enemies:
			if victim.pos.distance_to(shot.pos)<=stats.splash_radius:
				hurt(victim,shot.damage if victim.id==shot.target else shot.damage*stats.splash_fraction,'siege')
		for decoy in powers.decoys:
			if shot.side=='enemy' and decoy.hp>0 and decoy.pos.distance_to(shot.pos)<=stats.splash_radius:
				hurt(decoy,shot.damage,'siege')
		events.append({'kind':'stone_impact','pos':shot.pos})
	stones=stones.filter(func(shot):return shot.age<stats.flight)

func step(dt: float):
	if phase!='battle': return
	elapsed+=dt
	cooldown=maxf(0,cooldown-dt)
	advance_waves(dt)
	advance_stones(dt)
	powers.advance(self,dt)
	for u in units:
		if u.get('routing',false) and u.hp>0:continue
		u.moving=false
		if u.obstruction=='queue':u.obstruction=''
		u.attack_age+=dt
		u.hit_age+=dt
		if u.hp<=0:
			u.dead_age+=dt
			continue
		u.cooldown=maxf(0,u.cooldown-dt)
		u.stun=maxf(0,u.stun-dt)
		if u.petrified>0:
			u.push=Vector2.ZERO
			continue
		var displaced: Vector2=u.push*minf(1,dt*12)
		if displaced!=Vector2.ZERO and may_advance(u,u.pos+displaced,false):
			u.pos=(u.pos+displaced).clamp(bounds.position,bounds.end)
		u.push-=displaced
		if u.stun>0: continue
		# A march can go around a line, but cannot pass through a defending squad.
		if u.order=='move' and u.rooted<=0 and u.kind!='medic':
			var heading: Vector2=u.pos.direction_to(u.destination)
			for enemy in alive('enemy'):
				var gap: Vector2=enemy.pos-u.pos
				var contact=gap.length_squared()<68*68
				if terrain and terrain.clear_segment(u.kind,u.pos,enemy.pos):
					var separation=ground_basis.basis_xform(gap).abs()
					var edges: Vector2=terrain.extents[u.kind]+terrain.extents[enemy.kind]
					contact=separation.x<=edges.x and separation.y<=edges.y
				if contact and heading.dot(gap.normalized())>.35:
					u.order='attack'
					u.obstruction='contact'
					u.waypoints.clear()
					u.target_id=enemy.id
					break
		if u.order=='move':
			if u.rooted>0:continue
			var previous: Vector2=u.pos
			var next: Vector2=u.pos.move_toward(travel_target(u,u.destination),float(config.types[u.kind].speed)*powers.speed_multiplier(u)*dt)
			if not may_advance(u,next):continue
			u.pos=next
			record_march(u,previous)
			if absf(u.pos.x-previous.x)>.001:u.facing=signf(u.pos.x-previous.x)
			if u.pos.is_equal_approx(u.destination):
				if u.waypoints.is_empty():u.order='hold'
				else:
					u.leg_start=u.pos
					u.destination=u.waypoints.pop_front()
			continue
		var target: Dictionary={}
		if u.kind=='medic':
			target=wounded_ally(u)
			if target.is_empty():continue
		elif u.order=='attack':
			for enemy in units:
				if enemy.id==u.target_id and enemy.side!=u.side and enemy.hp>0 and not enemy.get('routing',false):
					target=enemy
					break
			if target.is_empty():
				u.order='auto'
				u.obstruction=''
		if target.is_empty():target=powers.select_target(self,u)
		if advance_objective(u,target,dt):continue
		if target.is_empty(): continue
		var distance: float=u.pos.distance_to(target.pos)
		var stats: Dictionary=config.types[u.kind]
		var lock_front: bool=u.order=='hold' and u.kind in ['legion','guard']
		if not lock_front and absf(target.pos.x-u.pos.x)>2: u.facing=signf(target.pos.x-u.pos.x)
		# Defenders hold their line until the player approaches; cavalry is a reserve.
		if u.kind!='medic' and u.side=='enemy' and target.kind!='decoy' and distance>float(stats.range)+220 and elapsed<enemy_wait: continue
		if distance>attack_reach(u,target):
			if u.rooted>0 or u.order=='hold':continue
			var steer=travel_target(u,target.pos)
			var motion: Vector2=u.pos.direction_to(steer)
			# Local squad separation keeps readable fronts without per-soldier pathfinding.
			for other in units:
				if other.id==u.id or other.hp<=0 or other.get('routing',false): continue
				var gap: float=u.pos.distance_to(other.pos)
				if gap>1 and gap<85: motion+=other.pos.direction_to(u.pos)*(85-gap)/65.0
			var previous: Vector2=u.pos
			var next: Vector2=(u.pos+motion.limit_length()*float(stats.speed)*powers.speed_multiplier(u)*dt).clamp(bounds.position,bounds.end)
			if not may_advance(u,next):
				if u.obstruction=='queue':continue
				next=u.pos.move_toward(steer,float(stats.speed)*powers.speed_multiplier(u)*dt)
				if not may_advance(u,next):continue
			u.pos=next
			record_march(u,previous)
		elif u.cooldown<=0:
			if not lock_front and distance>.01:u.heading=u.pos.direction_to(target.pos)
			u.cooldown=float(stats.interval)
			u.attack_age=0.0
			if u.kind=='medic':
				target.hp=minf(target.max_hp,target.hp+float(stats.heal))
				events.append({'kind':'heal','pos':target.pos,'from':u.pos})
				continue
			if u.kind=='siege':
				stones.append({'side':u.side,'from':u.pos,'pos':target.pos,'target':target.id,'age':0.0,'damage':stats.damage})
				events.append({'kind':'launch','pos':u.pos})
				continue
			var damage: float=stats.damage
			if target.kind=='legion' and u.kind=='archer': damage*=.65
			if target.kind=='guard' and u.kind=='archer':damage*=1.0-float(config.types.guard.missile_reduction)
			if target.kind=='cavalry' and u.kind=='spear':damage*=float(stats.mounted_bonus)
			deal_blow(u,target,damage)
			target.hit_age=0.0
	if combined_arms:separate_lines(dt)
	resolve_battle(dt)

	if phase!='battle':
		powers.clear(self)
		waves.clear()
		stones.clear()

func advance_objective(_u: Dictionary, _target: Dictionary, _dt: float) -> bool:
	return false

func resolve_battle(_dt: float):
	if alive('enemy').is_empty(): phase='victory'
	elif alive('ally').is_empty() and not reserve.values().any(func(stock):return stock>0): phase='defeat'
	elif elapsed>=float(config.duration): phase='timeout'
