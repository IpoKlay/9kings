extends RefCounted
## Self-contained trial state; never reads or writes expedition progress.
var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string('res://data/balance/tactical_trial.json'))
const Projectiles=preload('res://scripts/tactical/soldier_projectile.gd')
const MythPowers=preload('res://scripts/tactical/myth_powers.gd')
var powers=MythPowers.new()
var pass_layout_data: Dictionary
var bounds: Rect2
var deployment: Rect2
var units: Array = []
var reserve: Dictionary
var phase = 'deploy'
var elapsed = 0.0
var simulation_step=0
var personal_unit_lookup={}
var personal_target_bounds={}
## Per-step soldier feet per unit, gathered by begin_target_lookup for the target scans.
var personal_feet: Dictionary={}
var projectile_serial=0
var next_soldier_slot=0
var target_reservations: Dictionary={}
var targeting_random=RandomNumberGenerator.new()
const EnemyDirector=preload('res://scripts/tactical/enemy_director.gd')
var enemy_director=EnemyDirector.new()
var enemy_wait=50.0
var charges: int
var cooldown = 0.0
var events: Array = []
var next_id = 0
var deity='zeus'
var characters: Array=JSON.parse_string(FileAccess.get_file_as_string('res://data/content/myth_vfx.json')).characters
var waves: Array=[]
var stones: Array=[]
var volleys: Array=[]
var ability_sounds: Array=[]
var archer_variant=''
var cavalry_variant=''
var legion_variant=''
var guard_variant=''
var spear_variant=''
const Volley=preload('res://scripts/tactical/soldier_volley.gd')
var volley_random=RandomNumberGenerator.new()
var unlimited_powers=false
var combined_arms := false
var square_battle=false
const PassTerrain=preload("res://scripts/tactical/pass_terrain.gd")
const Sweep=preload('res://scripts/tactical/legion_sweep.gd')
const Contact=preload('res://scripts/tactical/regiment_contact.gd')
const Charges=preload('res://scripts/tactical/soldier_charge.gd')
const Blink=preload('res://scripts/tactical/soldier_blink.gd')
const Specials=preload('res://scripts/tactical/soldier_specials.gd')
const Soldiers=preload('res://scripts/tactical/regiment_soldiers.gd')
const Walls=preload('res://scripts/tactical/shield_wall.gd')
const Structures=preload('res://scripts/tactical/siege_structures.gd')
var structures: Array=[]
var structure_base_rocks: Array=[]
var shield_walls: Array=[]
var wall_serial=0
var move_batch_serial=0
var repulsion_time=0.
var repulsion_seed=12345
var contact_profiles={}
var casualties: Array[Dictionary]=[]
var casualty_serial=0
const CorpseMotion=preload('res://scripts/tactical/corpse_motion.gd')
var terrain: PassTerrain
## Soldier-facing maths asks for the ground/projection inverse on nearly every lookup while
## the ground basis is fixed once per battle, so the inverse is derived at assignment instead.
var ground_basis: Transform2D:
	set(value):
		ground_basis=value
		ground_inverse=value.affine_inverse()
var ground_inverse: Transform2D
var projection: Transform2D
## Per-kind config lookups (individual stats, individual support) repeated for every soldier.
var individual_kinds: Dictionary={}
## Per-step membership snapshots: the scan lists are rebuilt once per step instead of once per
## soldier. Liveness inside a snapshot is still read per soldier, so a death mid-step is not
## counted twice and never revives.
var step_alive: Dictionary={}
var step_alive_stamp=-1
var step_alive_count=-1
var unit_index: Dictionary={}
var unit_index_stamp=-1
var unit_index_count=-1
## Simulation step budget switch. With the cadence table on, a person that is not mid-attack
## or charging runs its target/path decision every other step while physics, cooldowns and
## attack release stay at 60 Hz. Clear it to compare against the exact per-step cadence.
var simulation_lod: bool=false
## Reused per-step row list (see Soldiers.advance_personal); keeps capacity between steps.
var personal_occupied: Array=[]
## Broad-phase scratch for Soldiers.prepare_neighbours, reused every step.
var neighbour_cells: Dictionary={}
var neighbour_keys: Array=[]
static var no_units: Array=[]

func _init(use_testing_rules: bool=true):
	targeting_random.seed=20260409
	volley_random.seed=20260409
	var field: Dictionary=preload('res://scripts/data/catalog.gd').presentation('field')
	ground_basis=Transform2D(Vector2(field.projection_x[0],field.projection_y[0]),Vector2(field.projection_x[1],field.projection_y[1]),Vector2.ZERO)
	projection=ground_basis
	projection.origin=Vector2(960,560)-ground_basis*Vector2(930,550)
	var authored=preload('res://scenes/battlefields/roman_pass.tscn').instantiate()
	pass_layout_data=authored.settings(projection)
	authored.free()
	bounds=pass_layout_data.BattleBounds
	deployment=pass_layout_data.Deployment
	powers.bounds=bounds
	unlimited_powers=use_testing_rules and bool(config.get("testing",{}).get("unlimited_powers",false))
	for kind in config.types:contact_profiles[kind]=Contact.profile(kind,config.types[kind])
	reserve = config.reserve.duplicate()
	charges = int(config.lightning.charges)
	for row in pass_layout_data.InitialEnemy: spawn(row[0], 'enemy', row[1])

func spawn(kind: String, side: String, pos: Vector2,variant: String=''):
	powers.invalidate_target_batch()
	var stats: Dictionary = config.types[kind].duplicate(true)
	if config.get('unit_variants',{}).get(variant,{}).get('kind','')==kind:
		stats.merge(config.unit_variants[variant],true)
	else:variant=''
	units.append({'id':next_id, 'kind':kind, 'side':side, 'pos':pos, 'home':pos,
		'hp':float(stats.hp), 'max_hp':float(stats.hp), 'cooldown':0.0, 'stun':0.0,
		'engaged':false, 'obstruction':'', 'order':'auto', 'destination':pos, 'waypoints':[], 'target_id':-1,
		'visible_slots':range(int(stats.files)),
		'heading':Vector2.RIGHT if side=='ally' else Vector2.LEFT, 'march_distance':0.0, 'moving':false, 'attack_age':10.0, 'hit_age':10.0, 'facing':1.0 if side=='ally' else -1.0,
		'shield':0.0,'rooted':0.0,'petrified':0.0,'marked':0.0,'poison':0.0,'regen':0.0,
		'push':Vector2.ZERO, 'charge':false,'clear_run':0.0, 'dead_age':0.0})
	if kind=='cavalry':
		units.back().merge({'pace':0.0,'run_axis':Vector2.ZERO,'charge_target':-1,'recover_until':0.0,'impact_until':0.0,'charge_id':0,'gait':'ride'})
	if variant!='':
		units.back().archetype=variant
		units.back().art=stats.get('art',kind)
		units.back().visual_scale=float(stats.get('visual_scale',1.))
		units.back().individual_stats=stats.individual
		units.back().combat_stats=stats
	Soldiers.initialize(units.back(),stats)
	for actor in units.back().soldiers:
		actor.scan_slot=next_soldier_slot;next_soldier_slot+=1
		actor.aggro_timer=targeting_random.randf_range(0.,.2)
		actor.retarget_timer=targeting_random.randf_range(0.,.15)
	next_id += 1

func deployment_valid(pos: Vector2, kind: String='legion') -> bool:
	if not deployment.has_point(pos) or (terrain and not terrain.clear_segment(kind,pos,pos)):return false
	for u in units:
		if u.hp>0 and u.pos.distance_to(pos)<100: return false
	return true

func selected_variant(kind: String) -> String:
	return str(get(kind+'_variant')) if config.loadouts.has(kind) else ''

func cycle_variant(kind: String):
	if phase!='deploy' or not config.loadouts.has(kind):return
	var options: Array=config.loadouts[kind]
	set(kind+'_variant',options[(options.find(selected_variant(kind))+1)%options.size()])

func deploy(kind: String, pos: Vector2) -> bool:
	if phase not in ['deploy','battle'] or not reserve.has(kind) or reserve[kind]<=0 or not deployment_valid(pos,kind): return false
	reserve[kind] -= 1
	spawn(kind,'ally',pos,selected_variant(kind))
	return true

func deploy_vanguard() -> bool:
	if phase!='deploy' or not alive('ally').is_empty():return false
	for slot in pass_layout_data.Vanguard:
		deploy(slot[0],slot[1])
	return true

func deploy_combined() -> bool:
	if phase!='deploy' or not alive('ally').is_empty():return false
	combined_arms=true
	deployment=pass_layout_data.CombinedDeployment
	units.clear()
	for slot in pass_layout_data.CombinedEnemies:
		spawn(slot[0],'enemy',slot[1])
	for slot in pass_layout_data.CombinedAllies:
		deploy(slot[0],slot[1])
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
	if square_battle:enemy_director.begin(self)
	return true

func alive(side: String) -> Array:
	var result: Array=[]
	for unit in units:
		if unit.hp>0 and unit.side==side:result.append(unit)
	return result

## Snapshot for the per-soldier target scans. Same membership rule as `alive()`; a unit that
## dies mid-step is merely skipped by its zero-HP soldiers, which the scans already test.
func step_units(side: String) -> Array:
	if step_alive_stamp!=simulation_step or step_alive_count!=units.size():
		rebuild_step_alive()
	var bucket: Variant=step_alive.get(side)
	return bucket if bucket!=null else no_units

func rebuild_step_alive() -> void:
	step_alive_stamp=simulation_step
	step_alive_count=units.size()
	step_alive.clear()
	for unit in units:
		if unit.hp<=0:continue
		var bucket: Variant=step_alive.get(unit.side)
		if bucket==null:
			bucket=[]
			step_alive[unit.side]=bucket
		bucket.append(unit)

## Id lookup shared by projectiles, retaliation and casualty reporting (was a linear scan).
func unit_by_id(id: int) -> Dictionary:
	if unit_index_stamp!=simulation_step or unit_index_count!=units.size():
		unit_index_stamp=simulation_step
		unit_index_count=units.size()
		unit_index.clear()
		for unit in units:unit_index[unit.id]=unit
	var found: Variant=unit_index.get(id)
	return found if found!=null else {}

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

func hurt(u: Dictionary, damage: float, source_kind: String='', _morale_shock: float=0.0,slot: int=-1,attacker_id: int=-1,attacker_slot: int=-1) -> float:
	powers.invalidate_target_batch()
	if u.hp<=0:return 0.0
	if u.get('shield',0)>0:damage*=1.0-float(powers.config.athena.reduction)
	if source_kind=='archer' and u.get('marked',0)>0:damage*=float(powers.config.artemis.archer_bonus)
	var dealt=minf(u.hp,maxf(0,damage))
	if u.has('soldiers'):dealt=Soldiers.hurt(u,dealt,slot)
	else:u.hp-=dealt
	if dealt>0:u.hit_age=0.0
	if attacker_id>=0:Soldiers.retaliate(self,u,slot,attacker_id,attacker_slot)
	return dealt

func heal(u: Dictionary,amount: float) -> float:
	powers.invalidate_target_batch()
	return Soldiers.heal(u,amount)

func command(ids: Array, order: String, destination: Vector2, target_id: int=-1) -> bool:
	if phase!='battle' or order not in ['move','attack_move','attack','hold','auto']:return false
	var squads=alive('ally').filter(func(unit):return unit.id in ids)
	if squads.is_empty():return false
	var center=Vector2.ZERO
	var formation=Rect2(squads[0].pos,Vector2.ZERO)
	for squad in squads:
		center+=squad.pos
		formation=formation.expand(squad.pos)
	center/=squads.size()
	var shift=(destination-center).clamp(bounds.position-formation.position,bounds.end-formation.end)
	var people=Soldiers.group_members(squads.filter(func(u):return config.types[u.kind].has('individual')))
	var personal_destination=destination
	if not people.is_empty() and squads.any(func(u):return not config.types[u.kind].has('individual')):
		var all_center=Vector2.ZERO;var person_center=Vector2.ZERO
		var all_people=Soldiers.members(self,Soldiers.group_members(squads))
		for row in all_people:
			var foot: Vector2=Soldiers.ground_position(self,row.unit,row.slot)
			all_center+=foot
			if config.types[row.unit.kind].has('individual'):person_center+=foot
		all_center/=all_people.size();person_center/=people.size()
		personal_destination+=person_center-all_center
		shift=destination-all_center
	if not people.is_empty() and not Soldiers.command(self,people,order,personal_destination,target_id,-1,[],false):return false
	var paths={}
	if order in ['move','attack_move']:
		if not bounds.has_point(destination):return false
		for squad in squads:
			if config.types[squad.kind].has('individual'):continue
			var goal: Vector2=squad.pos+shift
			var plan=plan_route(squad,[],goal.clamp(bounds.position,bounds.end-Vector2(.001,.001)))
			if not plan.ok:return false
			paths[squad.id]=plan.points
	if not people.is_empty():Soldiers.command(self,people,order,personal_destination,target_id)
	for squad in squads:
		if config.types[squad.kind].has('individual'):
			group_order(squad,order,destination,target_id)
			continue
		Soldiers.regroup(self,squad)
		if order not in ['move','attack_move']:interrupt_charge(squad)
		squad.erase('shield_wall')
		squad.erase('wall_heading')
		if squad.kind=='cavalry' and order=='hold':squad.pace=0.0
		squad.erase('penetration')
		squad.erase('follow_goal')
		squad.erase('brace_until')
		squad.engaged=false
		squad.obstruction=''
		squad.target_id=target_id
		squad.order=order
		squad.waypoints.clear()
		squad.erase('next_command_scan')
		if order in ['move','attack_move']:
			set_march(squad,paths[squad.id])
			squad.order=order
		else:squad.destination=squad.pos+shift
		if order=='auto':Soldiers.automate(self,squad,true)
	return true

func group_order(squad: Dictionary,order: String,destination: Vector2,target_id: int=-1):
	interrupt_charge(squad)
	for key in ['shield_wall','wall_heading','penetration','follow_goal','brace_until','next_command_scan','route_progress']:squad.erase(key)
	squad.individual_auto=order=='auto'
	squad.order=order;squad.target_id=target_id;squad.engaged=false;squad.obstruction=''
	squad.leg_start=squad.pos;squad.waypoints.clear()
	var goal=Vector2.ZERO;var count=0
	for actor in squad.soldiers:
		if actor.hp<=0:continue
		goal+=actor.path.back() if not actor.path.is_empty() else actor.position;count+=1
	squad.destination=goal/maxi(count,1) if order in ['move','attack_move'] else destination
	if squad.soldiers.all(func(actor):return actor.hp<=0 or actor.get('shield_wall',false)):
		squad.shield_wall=true
		for actor in squad.soldiers:
			if actor.hp>0:squad.wall_heading=actor.wall_heading;break

func plan_route(squad: Dictionary, via: Array[Vector2], goal: Vector2) -> Dictionary:
	if phase=='battle' and config.types[squad.kind].has('individual'):
		var people=Soldiers.members(self,Soldiers.group_members([squad]))
		var paths=Soldiers.movement_paths(self,people,goal,via)
		var valid=not paths.is_empty()
		var route: Array[Vector2]=[]
		var from: Vector2=squad.pos
		for stop in via+[goal]:
			route.append_array(terrain.leg(Soldiers.navigator(self,squad.kind,squad),from,stop));from=stop
		return {'ok':valid,'points':route,'blocked':goal,'people':people,'paths':paths}
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
	Soldiers.regroup(self,squad)
	interrupt_charge(squad)
	squad.erase('shield_wall')
	squad.erase('wall_heading')
	squad.erase('penetration')
	squad.erase('follow_goal')
	squad.erase('brace_until')
	squad.order='move'
	squad.engaged=false
	squad.obstruction=''
	squad.target_id=-1
	squad.leg_start=squad.pos
	squad.destination=points[0]
	squad.waypoints=points.slice(1)

func march_route(id: int, via: Array[Vector2], goal: Vector2) -> bool:
	if phase!='battle':return false
	for squad in alive('ally'):
		if squad.id!=id:continue
		if config.types[squad.kind].has('individual'):
			if not Soldiers.command(self,Soldiers.group_members([squad]),'move',goal,-1,-1,via):return false
			group_order(squad,'move',goal)
			squad.route_progress=0
			if not via.is_empty():squad.destination=via[0];squad.waypoints=via.slice(1);squad.waypoints.append(goal)
			return true
		var plan=plan_route(squad,via,goal)
		if not plan.ok:return false
		set_march(squad,plan.points)
		return true
	return false

# Only the single-file side gate imposes a queue. A unit moving away can always leave.
func may_advance(u: Dictionary, next: Vector2, traffic: bool=true, gate_approach: bool=false) -> bool:
	if not terrain:return true
	if not terrain.clear_segment(u.kind,u.pos,next):return false
	for wall in alive(u.side):
		if wall.id==u.id or not wall.get('shield_wall',false):continue
		if (wall.pos-u.pos).dot(next-u.pos)<=0:continue
		if Contact.touching(self,u,wall,next-u.pos):
			u.obstruction='queue'
			return false
	var approaching=u.order in ['move','attack_move'] and terrain.crosses(terrain.SIDE_GATE,projection*u.leg_start,projection*u.destination)
	if traffic and (approaching or gate_approach or terrain.touches_gate(u.kind,next)):
		var motion=projection.basis_xform(next-u.pos)
		for other in units:
			if other.id==u.id or other.side!=u.side or other.hp<=0 or other.get('routing',false):continue
			var gap=projection.basis_xform(other.pos-next)
			var clearance: Vector2=terrain.extents[u.kind]+terrain.extents[other.kind]
			if absf(gap.x)<clearance.x and absf(gap.y)<clearance.y and gap.dot(motion)>0:
				u.obstruction='queue'
				return false
	return true

func shield_layout(ids: Array,start: Vector2,finish: Vector2) -> Dictionary:
	var squads=alive('ally').filter(func(u):return u.id in ids)
	return Soldiers.shield_line(self,Soldiers.group_members(squads),start,finish,false) if phase=='battle' else {}

func command_shield_line(ids: Array,start: Vector2,finish: Vector2) -> bool:
	var squads=alive('ally').filter(func(u):return u.id in ids and Soldiers.individual(self,u).get('can_shield_wall',false))
	var layout=Soldiers.shield_line(self,Soldiers.group_members(squads),start,finish)
	if layout.is_empty():return false
	for u in squads:
		group_order(u,'move',(start+finish)*.5)
		u.shield_wall=true;u.wall_heading=start.direction_to(finish).orthogonal()
	return true

func travel_target(u: Dictionary, goal: Vector2) -> Vector2:
	if not terrain or terrain.clear_segment(u.kind,u.pos,goal):return goal
	var corner: Vector2=u.get('steer_corner',u.pos)
	if u.pos.distance_to(corner)>3 and terrain.clear_segment(u.kind,u.pos,corner):return corner
	var path=terrain.leg(u.kind,u.pos,goal)
	corner=u.pos if path.is_empty() else path[0]
	u.steer_corner=corner
	return corner

func reset_run(u: Dictionary):
	u.clear_run=0.0
	u.run_axis=Vector2.ZERO
	u.charge=false
	u.charge_target=-1

# Accepted replacement commands spend a committed charge, including route edits.
# Invalid routes return before this point and leave the current order intact.
func interrupt_charge(u: Dictionary):
	if u.kind!='cavalry':return
	if u.charge or u.charge_target>=0 or u.has('penetration'):
		u.recover_until=maxf(u.recover_until,elapsed+float(config.regiment_impact.recovery_seconds))
		u.gait='recover'
	reset_run(u)
	u.pace=minf(u.pace,1.)

# Look only one sprint ahead, on the current straight leg. The projected files are
# the same contact shapes used by the hit itself; a wide formation meets earlier.
func mounted_target(u: Dictionary, direction: Vector2, lead: float, focus: Dictionary) -> int:
	if terrain:
		var end: Vector2=u.pos+direction*lead
		if not terrain.clear_segment(u.kind,u.pos,end) or terrain.crosses(terrain.SIDE_GATE,projection*u.pos,projection*end):return -1
	var candidates=[focus] if not focus.is_empty() else alive('enemy' if u.side=='ally' else 'ally')
	var nearest=INF
	var id=-1
	for enemy in candidates:
		if enemy.kind=='decoy':continue
		var gap: Vector2=enemy.pos-u.pos
		var distance=gap.length()
		if distance>lead+680 or distance>=nearest:continue
		# A passing waypoint can skim an enemy corner. Only sprint into the chosen line.
		if gap.normalized().dot(direction)<cos(deg_to_rad(config.regiment_impact.approach_degrees)):continue
		if terrain and not terrain.clear_segment(u.kind,u.pos,enemy.pos):continue
		var offset=direction*minf(lead,distance)
		var meets: bool=Contact.touching(self,u,enemy,offset) if terrain else (gap-offset).length()<=config.types.cavalry.range
		if meets:
			nearest=distance
			id=enemy.id
	return id

# Commit one voluntary step. A rejected step adds neither distance nor animation.
func ride(u: Dictionary, goal: Vector2, speed: float, dt: float, focus: Dictionary={}, gate_approach: bool=false) -> bool:
	var direction: Vector2=u.pos.direction_to(goal)
	if direction==Vector2.ZERO:
		reset_run(u)
		u.pace=0.0
		return false
	var cfg: Dictionary=config.regiment_impact
	var tolerance=deg_to_rad(cfg.alignment_degrees)
	var turn: float=u.heading.angle_to(direction)
	var sharp=absf(turn)>tolerance or absf(u.get('formation_heading',u.heading).angle_to(direction))>tolerance
	if sharp or (u.run_axis!=Vector2.ZERO and absf(u.run_axis.angle_to(direction))>tolerance):
		reset_run(u)
		u.pace=minf(u.pace,.42)
	u.heading=u.heading.rotated(clampf(turn,-cfg.turn_rate*dt,cfg.turn_rate*dt)).normalized()
	var gate: bool=terrain!=null and terrain.touches_gate(u.kind,u.pos)
	var recovering: bool=elapsed<u.recover_until
	var clear_lane=not gate and not sharp and not recovering
	if clear_lane:
		for enemy in alive('enemy' if u.side=='ally' else 'ally'):
			var gap: float=u.pos.distance_to(enemy.pos)
			if gap<700 and gap<=attack_reach(u,enemy):
				clear_lane=false
				break
	var minimum: float=config.directional_combat.rearm_distance
	var sprint_length: float=speed*cfg.sprint_seconds*(1+cfg.top_speed)*.5
	var target=-1
	if clear_lane and u.clear_run>=minimum-sprint_length*.75:
		var lead=minf(u.pos.distance_to(goal),sprint_length+speed*.12)
		target=mounted_target(u,direction,lead,focus)
	if u.charge_target>=0 and u.charge_target!=target:
		reset_run(u)
		u.pace=minf(u.pace,1.0)
		target=-1
	u.charge_target=target
	var aim=cfg.top_speed if target>=0 else .42 if sharp else 1.0
	var rate: float=(cfg.top_speed-1)/cfg.sprint_seconds if target>=0 else 1/cfg.ride_start_seconds
	var pace=move_toward(u.pace,aim,rate*dt)
	var previous: Vector2=u.pos
	var next: Vector2=previous.move_toward(goal,speed*pace*maxf(0,u.heading.dot(direction))*dt)
	if not may_advance(u,next,true,gate_approach):
		reset_run(u)
		u.pace=0.0
		u.gait='ride'
		return false
	u.pos=next
	record_march(u,previous)
	var distance=previous.distance_to(next)
	u.pace=distance/maxf(.00001,speed*dt)
	if not clear_lane or (terrain and terrain.touches_gate(u.kind,next)):
		reset_run(u)
	elif distance>0:
		if u.run_axis==Vector2.ZERO:u.run_axis=direction
		u.clear_run+=distance
	if clear_lane and not focus.is_empty() and previous.distance_to(focus.pos)<780 and distance>0:
		var hoof=int(u.march_distance/32.)
		if hoof!=u.get('hoof_index',-1):
			u.hoof_index=hoof
			var rear: Vector2=Contact.feet(self,u)[(hoof*7)%contact_profiles.cavalry.feet.size()]
			var foot: Vector2=u.pos+ground_inverse.basis_xform(rear)
			events.append({'kind':'hoof_dust','pos':foot,'axis':ground_basis.basis_xform(u.heading).normalized(),'pace':pace})
	var was_ready: bool=u.charge
	u.charge=not u.get('personalized',false) and u.charge_target>=0 and u.clear_run>=minimum and distance/dt>=float(config.types.cavalry.speed)*cfg.minimum_impact_speed
	if u.charge and not was_ready:u.charge_id+=1
	u.gait='impact' if elapsed<u.impact_until else 'recover' if recovering else 'align' if sharp else 'sprint' if u.charge_target>=0 else 'ride'
	return true

func record_march(u: Dictionary, previous: Vector2):
	u.moving=previous!=u.pos
	if not u.moving:return
	u.march_distance+=previous.distance_to(u.pos)
	u.last_stride=elapsed
	if u.kind!='cavalry':u.heading=previous.direction_to(u.pos)

func impact_side(attacker: Dictionary, target: Dictionary,incoming: Vector2=Vector2.ZERO) -> String:
	if not target.has('heading'):return 'front'
	if incoming.is_zero_approx():incoming=target.pos.direction_to(attacker.pos)
	if incoming.is_zero_approx():return 'front'
	var alignment: float=target.heading.normalized().dot(incoming)
	if alignment>.5 or is_equal_approx(alignment,.5):return 'front'
	if alignment<-.5 or is_equal_approx(alignment,-.5):return 'rear'
	return 'side'

func soldier_sector(origin: Vector2,target: Dictionary,slot: int) -> String:
	if slot<0:return impact_side({'pos':origin},target)
	var actor: Dictionary=target.soldiers[slot]
	var point: Vector2=Soldiers.ground_position(self,target,slot)
	return impact_side({'pos':origin},{'pos':point,'heading':actor.heading if actor.has('personal_order') else target.heading})

func shield_active(target: Dictionary,slot: int=-1) -> bool:
	if slot>=0 and target.soldiers[slot].has('personal_order'):return target.soldiers[slot].get('shield_wall',false)
	return target.get('shield_wall',false)

func soldier_holding(target: Dictionary,slot: int=-1) -> bool:
	if slot>=0 and target.soldiers[slot].has('personal_order'):return target.soldiers[slot].personal_order=='hold'
	return target.order=='hold'

func deal_blow(attacker: Dictionary,target: Dictionary,damage: float,contact: Dictionary={},strike: Dictionary={}) -> Dictionary:
	var sector=impact_side(attacker,target) if contact.is_empty() else str(contact.sector)
	if not strike.is_empty():sector=soldier_sector(Soldiers.ground_position(self,attacker,strike.attacker_slot),target,strike.target_slot)
	var tactics: Dictionary=config.directional_combat
	var kind='arrow' if Soldiers.ranged(attacker) and attacker.kind!='siege' else 'hit'
	var shock=0.0
	var personal_charge: bool=strike.get('personal_charge',false)
	if personal_charge:kind='charge'
	var shielding=shield_active(target,strike.get('target_slot',contact.get('defender_slot',-1)))
	var shield_front=sector=='front'
	if not strike.is_empty():
		var victim: Dictionary=target.soldiers[strike.target_slot]
		var incoming: Vector2=(Soldiers.ground_position(self,attacker,strike.attacker_slot)-Soldiers.ground_position(self,target,strike.target_slot)).normalized()
		var facing: Vector2=victim.heading if victim.has('personal_order') else target.heading
		shield_front=facing.dot(incoming)>.34
	if kind!='arrow' and shielding and shield_front:
		damage*=1.-config.battle_commands.shield_melee_reduction
	elif not square_battle and not personal_charge and kind!='arrow' and sector=='front' and target.kind in ['legion','guard'] and soldier_holding(target,strike.get('target_slot',-1)) and not shielding:
		damage*=tactics.shield_front
	var charging: bool=strike.is_empty() and attacker.kind=='cavalry' and attacker.charge and attacker.charge_target==target.id
	if not contact.is_empty():
		if not charging or contact.attacker!=attacker.id or contact.target!=target.id or contact.charge_id!=attacker.charge_id:return {}
		if attacker.get('last_contact',{}).get('charge_id',-1)==contact.charge_id:return {}
		attacker.last_contact=contact
	elif charging and terrain and target.kind in ['legion','guard','spear']:return {}
	var mounted: bool=charging and target.kind!='decoy'
	var previous_count=Contact.count(target,config.types[target.kind]) if mounted else 0
	if charging:
		attacker.charge=false
		attacker.clear_run=0.0
		if not (Contact.braced_pikes(target,elapsed) and sector=='front'):damage*=tactics.charge
		kind='charge'
		if sector!='front':
			kind='flanking_charge'
			damage*=tactics[sector].damage
			shock=tactics[sector].morale
	if terrain and kind=='arrow' and target.kind!='decoy':
		var feet: PackedVector2Array=Contact.feet(self,target)
		var slot: int=strike.get('target_slot',posmod(attacker.id*7+roundi(elapsed*2),feet.size()))
		var visible=Contact.count(target,config.types[target.kind])
		if not strike.has('target_slot'):
			while not Contact.present(target,slot,visible):slot=(slot+1)%feet.size()
		var local: Vector2=feet[slot]+Contact.body_shift(target,slot,elapsed)
		var volley={'kind':'arrow','attacker':attacker.id,'target':target.id,'damage':damage,
			'from':attacker.pos,'aim_center':target.pos,'pos':target.pos+ground_inverse.basis_xform(local),'offset':local,'age':0.}
		if not strike.is_empty():
			volley.target_slot=slot
			volley.attacker_slot=strike.attacker_slot
			volley.pos=Soldiers.ground_position(self,target,slot)
			volley.offset=ground_basis.basis_xform(volley.pos-target.pos)
			volley.from=Soldiers.ground_position(self,attacker,strike.attacker_slot)
		volley.target_slot=slot
		volley.origin=Projectiles.origin(self,attacker,strike.attacker_slot) if strike.has('attacker_slot') else attacker.pos
		volley.point=volley.origin
		volley.speed=float(Soldiers.individual(self,attacker).projectile_speed)
		volley.direction=volley.point.direction_to(volley.pos)
		volley.projectile_art=Soldiers.individual(self,attacker).get('projectile_art','arrow')
		volley.flight=volley.origin.distance_to(volley.pos)/volley.speed
		volley.release_delay=strike.get('release_delay',.23)
		volleys.append(Projectiles.schedule(self,volley))
		if volley.release_delay==0.:events.append({'kind':'arrow','volley':true,'pos':volley.aim_center,'landing':volley.pos,'from':volley.from,'attacker':attacker.id,'target':target.id})
		return volley
	var struck_slot: int=strike.get('target_slot',contact.get('defender_slot',-1))
	var dealt=hurt(target,damage,attacker.kind,shock,struck_slot,attacker.id,strike.get('attacker_slot',-1))
	var hit={'kind':kind,'pos':target.pos,'from':attacker.pos,'sector':sector,'attacker':attacker.id,'target':target.id,'damage':dealt}
	if not strike.is_empty():
		hit.merge(strike)
		hit.pos=Soldiers.ground_position(self,target,struck_slot)
		hit.from=Soldiers.ground_position(self,attacker,strike.attacker_slot)
	if not contact.is_empty():
		hit.contact=contact
		hit.pos=contact.pos
	if terrain and mounted and dealt>0:
		Contact.apply(self,attacker,target,hit,previous_count)
	elif terrain and kind=='hit' and target.kind!='decoy' and dealt>0 and (not strike.is_empty() or attacker.order in ['attack','attack_move'] or target.order in ['attack','attack_move']):
		var ordinary=Contact.locate(self,attacker,target,Contact.count(target,config.types[target.kind])) if strike.is_empty() else {
			'pos':hit.pos,'entry':Soldiers.point(self,target,struck_slot)-projection*target.pos,
			'dir':ground_basis.basis_xform(hit.pos-hit.from).normalized()}
		hit.pos=ordinary.pos
		Contact.light_hit(self,target,ordinary.entry,ordinary.dir,struck_slot)
	if attacker.kind=='cavalry' and strike.is_empty():
		reset_run(attacker)
		attacker.recover_until=elapsed+config.regiment_impact.recovery_seconds
		attacker.impact_until=elapsed+.18 if charging else elapsed
		attacker.gait='impact' if charging else 'recover'
	events.append(hit)
	return hit

# In the large deployment, melee lines engage at their facing edges.
func attack_reach(u: Dictionary, target: Dictionary) -> float:
	var reach:=float(config.types[u.kind].range)
	if u.kind in ['archer','siege'] and target.has('soldiers'):
		return u.pos.distance_to(target.pos)+.01 if Soldiers.in_reach(self,u,target) else 0.
	if u.kind not in ['legion','guard','spear','cavalry'] or target.kind=='decoy':return reach
	if terrain and u.kind=='cavalry' and target.kind in ['legion','guard','spear'] and u.charge and u.charge_target==target.id and u.cooldown<=0:
		return -1.0 # The sweep owns this first strike, including its stopping point.
	if terrain and u.kind in ['legion','guard','spear'] and target.kind=='cavalry' and target.charge and target.charge_target==u.id and u.order=='hold':
		return -1.0
	if u.has('soldiers') and target.has('soldiers') and config.types[u.kind].has('individual'):
		return u.pos.distance_to(target.pos)+.01 if Soldiers.in_reach(self,u,target) else 0.
	var axis:=ground_basis.basis_xform(u.pos.direction_to(target.pos))
	if terrain and (square_battle or u.order=='attack' or (target.get('order','')=='attack' and target.target_id==u.id) or u.kind=='cavalry'):
		var distance: float=u.pos.distance_to(target.pos)
		if distance<780 and Contact.touching(self,u,target) and terrain.clear_segment(u.kind,u.pos,target.pos):
			return distance+.01
		return 0
	var v:=axis.abs()
	if v.is_zero_approx():return reach
	if terrain and (u.obstruction=='contact' or (target.get('obstruction','')=='contact' and target.target_id==u.id)):
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
				var clearance: Vector2=terrain.extents[a.kind]+terrain.extents[b.kind] if square_battle else Vector2(280,115)
				var normalized:=separation/clearance
				if normalized.length_squared()>=1:continue
				var movable_a: bool=not Soldiers.independent(a) and a.order in ['auto','attack','attack_move'] and a.rooted<=0 and a.stun<=0 and a.petrified<=0
				var movable_b: bool=not Soldiers.independent(b) and b.order in ['auto','attack','attack_move'] and b.rooted<=0 and b.stun<=0 and b.petrified<=0
				if not movable_a and not movable_b:continue
				var axis:=normalized.normalized() if not normalized.is_zero_approx() else Vector2.DOWN
				var offset:=ground_inverse.basis_xform(axis*clearance-separation)*minf(dt*3,1)/(int(movable_a)+int(movable_b))
				if movable_a and may_advance(a,a.pos-offset,false):a.pos=(a.pos-offset).clamp(bounds.position,bounds.end)
				if movable_b and may_advance(b,b.pos+offset,false):b.pos=(b.pos+offset).clamp(bounds.position,bounds.end)

func wounded_ally(medic: Dictionary) -> Dictionary:
	var best: Dictionary={}
	for candidate in alive(medic.side):
		if not Soldiers.wounded(candidate):continue
		var distance: float=medic.pos.distance_to(candidate.pos)
		if medic.order=='hold' and distance>float(config.types.medic.range):continue
		if best.is_empty() or candidate.hp/candidate.max_hp<best.hp/best.max_hp or (is_equal_approx(candidate.hp/candidate.max_hp,best.hp/best.max_hp) and distance<medic.pos.distance_to(best.pos)):
			best=candidate
	return best

func advance_volleys(dt: float):
	if dt<=0:return
	Volley.advance_sounds(self,dt)
	for volley in volleys:advance_volley(volley,dt)
	prune_projectiles()

func advance_volley(volley: Dictionary,dt: float):
	var previous: float=volley.age
	volley.age+=dt
	if volley.kind=='ability_volley':
		if volley.age>=volley.flight:Volley.land(self,volley)
	else:Projectiles.advance(self,volley,previous,dt)

func advance_stones(dt: float):
	if dt<=0:return
	for shot in stones:advance_stone(shot,dt)
	prune_projectiles()

func advance_stone(shot: Dictionary,dt: float):
	var stats: Dictionary=config.types.siege
	shot.age+=dt
	if shot.age<shot.get('flight',stats.flight):return
	Structures.impact(self,shot)
	var source=Projectiles.source(self,shot)
	var enemies=alive('enemy' if source.unit.side=='ally' else 'ally') if not source.is_empty() else alive('ally')+alive('enemy')
	for victim in enemies:
		for slot in victim.soldiers.size():
			if victim.soldiers[slot].hp<=0:continue
			var foot: Vector2=Soldiers.ground_position(self,victim,slot)
			if foot.distance_to(shot.pos)>stats.splash_radius:continue
			Projectiles.impact(self,shot,victim,slot,'siege')
	for decoy in powers.decoys:
		if shot.side=='enemy' and decoy.hp>0 and decoy.pos.distance_to(shot.pos)<=stats.splash_radius:
			hurt(decoy,shot.damage,'siege')
	events.append({'kind':'stone_impact','pos':shot.pos})

func prune_projectiles():
	volleys=volleys.filter(func(v):return v.age<v.flight if v.kind=='ability_volley' else not v.get('done',false))
	stones=stones.filter(func(shot):return shot.age<shot.get('flight',config.types.siege.flight))

func projectile_frame() -> Array:
	var shots=[]
	for shot in volleys:shots.append({'shot':shot,'stone':false,'serial':shot.get('serial',projectile_serial+shots.size()+1)})
	for shot in stones:shots.append({'shot':shot,'stone':true,'serial':shot.get('serial',projectile_serial+shots.size()+1)})
	shots.sort_custom(func(a,b):return a.serial<b.serial)
	return shots

func advance_projectiles(shots: Array,dt: float):
	if dt<=0:return
	Volley.advance_sounds(self,dt)
	for row in shots:
		if row.stone:advance_stone(row.shot,dt)
		else:advance_volley(row.shot,dt)
	prune_projectiles()

# Resolve after both sides moved so target motion is independent of iteration order.
func sweep_legion_charges(previous: Dictionary,dt: float):
	for a in units:
		if a.kind!='cavalry' or not a.charge or not a.moving or a.cooldown>0 or a.hp<=0 or a.get('routing',false):continue
		if a.get('last_contact',{}).get('charge_id',-1)==a.charge_id:continue
		var pa: Dictionary=previous[a.id]
		for b in alive('enemy' if a.side=='ally' else 'ally'):
			if b.kind not in ['legion','guard','spear'] or b.id!=a.charge_target:continue
			var pb: Dictionary=previous[b.id]
			var travel: Vector2=a.pos-pa.pos
			var distance=travel.length()
			if distance==0:continue
			# A long simulation step may earn eligibility only partway through its path.
			var minimum=clampf(1-(a.clear_run-config.directional_combat.rearm_distance)/distance,0,1)
			var contact=Sweep.earliest(self,a,b,pa,pb,dt,minimum)
			if contact.is_empty():
				# A discrete stride or attack frame can expose a new pixel at the endpoint.
				var now_a=Sweep.pose(self,a)
				var now_b=Sweep.pose(self,b)
				contact=Sweep.earliest(self,a,b,now_a,now_b,0)
				if contact.is_empty():continue
				contact.fraction=1.
			var t: float=contact.fraction
			# Allow at most one native texel of compression beyond first contact.
			var stop=minf(1,t+2/maxf(.001,ground_basis.basis_xform(travel).length()))
			a.pos=pa.pos.lerp(a.pos,stop)
			a.march_distance-=distance*(1-stop)
			var direction=travel/distance
			contact.merge({'attacker':a.id,'target':b.id,'charge_id':a.charge_id,'speed':distance/dt,
				'direction':direction,'dir':ground_basis.basis_xform(direction).normalized(),'sector':impact_side(a,b,-direction),'time':elapsed-dt+t*dt})
			contact.make_read_only()
			a.heading=direction
			if a.order!='attack_move':a.order='attack'
			a.target_id=b.id
			a.obstruction='contact'
			a.waypoints.clear()
			a.engaged=true
			a.attack_age=0.
			var stats: Dictionary=a.get('combat_stats',config.types.cavalry)
			a.cooldown=stats.interval
			deal_blow(a,b,stats.damage,contact)
			b.hit_age=0.
			break

func step(dt: float):
	if phase!='battle' or dt<=0: return
	simulation_step+=1
	# Scene physics runs existing projectile nodes after unit systems; new nodes wait one tick.
	var flying=projectile_frame()
	for unit in units:
		if unit.hp>0 and unit.order=='auto':Soldiers.automate(self,unit)
	var start_poses={}
	for unit in units:
		Soldiers.advance(unit,dt)
		if not unit.has('slot_distances'):Contact.track_slots(self,unit,0.)
	if terrain:
		for unit in units:
			if unit.kind in ['legion','guard','spear','cavalry']:start_poses[unit.id]=Sweep.pose(self,unit)
	elapsed+=dt
	enemy_director.advance(self,dt)
	cooldown=maxf(0,cooldown-dt)
	advance_waves(dt)
	powers.advance(self,dt)
	for u in units:
		Contact.advance_recovery(self,u,dt)
		if u.has('slot_states'):Contact.prune(u,elapsed)
		if u.hp<=0 or u.get('routing',false) or u.petrified>0:
			u.erase('penetration')
			u.erase('follow_goal')
		if u.get('routing',false) and u.hp>0:continue
		if u.kind=='cavalry':
			if not u.moving or u.stun>0 or u.rooted>0 or u.petrified>0 or u.push!=Vector2.ZERO:
				reset_run(u)
				u.pace=0.0
			if u.impact_until>elapsed or u.has('follow_goal'):u.gait='impact'
			elif u.recover_until>elapsed:u.gait='recover'
			elif u.gait in ['impact','recover'] or not u.moving:u.gait='ride'
		if u.has('contact_motion') and elapsed-u.contact_motion.start>u.contact_motion.hold+u.contact_motion.recover+.45:u.erase('contact_motion')
		u.moving=false
		u.engaged=false
		if u.obstruction=='queue':u.obstruction=''
		u.attack_age+=dt
		u.hit_age+=dt
		u.stun=maxf(0,u.stun-dt)
		if u.hp<=0:
			u.dead_age+=dt
			continue
		u.cooldown=maxf(0,u.cooldown-dt)
		if u.petrified>0:
			u.push=Vector2.ZERO
			continue
		var displaced: Vector2=u.push*minf(1,dt*12)
		if displaced!=Vector2.ZERO and may_advance(u,u.pos+displaced,false):
			u.pos=(u.pos+displaced).clamp(bounds.position,bounds.end)
		u.push-=displaced
		if u.has('penetration'):
			var defender: Dictionary={}
			for unit in units:
				if unit.id==u.penetration.target:
					defender=unit
					break
			if not defender.is_empty() and defender.hp>0 and not defender.get('routing',false) and u.rooted<=0 and u.stun<=0:
				if Contact.advance_passage(self,u,defender,dt):continue
			u.erase('penetration')
			u.erase('follow_goal')
			u.pace=0.
		if u.stun>0 or elapsed<u.get('brace_until',0): continue
		if Soldiers.independent(u):continue
		var stats: Dictionary=u.get('combat_stats',config.types[u.kind])
		var march_enemy: Dictionary={}
		if u.order=='attack_move':
			if elapsed>=u.get('next_command_scan',0.):
				march_enemy=attack_move_target(u)
				u.target_id=march_enemy.get('id',-1)
				u.next_command_scan=elapsed+config.battle_commands.scan_seconds
			else:
				for candidate in alive('enemy' if u.side=='ally' else 'ally'):
					if candidate.id==u.target_id:march_enemy=candidate;break
		elif u.order=='move' and u.get('shield_wall',false):
			for candidate in alive('enemy' if u.side=='ally' else 'ally'):
				if u.pos.distance_to(candidate.pos)<600 and Soldiers.in_reach(self,u,candidate):march_enemy=candidate;break
		# A march can go around a line, but cannot pass through a defending squad.
		if u.order=='move' and u.rooted<=0 and u.kind!='medic' and not u.get('shield_wall',false):
			var heading: Vector2=u.pos.direction_to(u.destination)
			for enemy in alive('enemy'):
				var gap: Vector2=enemy.pos-u.pos
				var committed: bool=u.kind=='cavalry' and u.charge_target==enemy.id
				var touches: bool=gap.length()<=attack_reach(u,enemy) if committed else in_formation_contact(u,enemy)
				if touches and heading.dot(gap.normalized())>.35:
					u.order='attack'
					u.obstruction='contact'
					u.waypoints.clear()
					u.target_id=enemy.id
					break
		if u.order in ['move','attack_move'] and march_enemy.is_empty():
			if u.rooted>0:continue
			var previous: Vector2=u.pos
			var goal=travel_target(u,u.destination)
			var speed: float=stats.speed*powers.speed_multiplier(u)
			if u.get('shield_wall',false):speed=minf(speed,config.battle_commands.shield_march_speed)
			if u.kind=='cavalry':
				if not ride(u,goal,speed,dt):continue
			else:
				var next: Vector2=u.pos.move_toward(goal,speed*dt)
				if not may_advance(u,next):continue
				u.pos=next
				record_march(u,previous)
				if u.get('shield_wall',false):u.heading=u.wall_heading
			if absf(u.pos.x-previous.x)>.001:u.facing=signf(u.pos.x-previous.x)
			if u.pos.is_equal_approx(u.destination):
				if u.waypoints.is_empty():
					u.order='hold'
					if u.get('shield_wall',false):u.heading=u.wall_heading
				else:
					u.leg_start=u.pos
					u.destination=u.waypoints.pop_front()
			continue
		var target: Dictionary=march_enemy
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
		if target.is_empty():target=combat_target(u)
		if advance_objective(u,target,dt):continue
		if target.is_empty(): continue
		var distance: float=u.pos.distance_to(target.pos)
		var lock_front: bool=(u.order=='hold' or u.get('shield_wall',false)) and u.kind in ['legion','guard','spear']
		if not lock_front and absf(target.pos.x-u.pos.x)>2: u.facing=signf(target.pos.x-u.pos.x)
		# Defenders hold their line until the player approaches; cavalry is a reserve.
		if u.kind!='medic' and u.side=='enemy' and target.kind!='decoy' and distance>float(stats.range)+220 and elapsed<enemy_wait: continue
		if distance>attack_reach(u,target):
			if u.rooted>0 or u.order=='hold':continue
			var chase: Vector2=Soldiers.approach(self,u,target) if u.kind in ['legion','guard','spear'] and target.has('soldiers') else target.pos
			var steer=travel_target(u,chase)
			var motion: Vector2=u.pos.direction_to(steer)
			# Local squad separation keeps readable fronts without per-soldier pathfinding.
			for other in units:
				if other.id==u.id or other.hp<=0 or other.get('routing',false): continue
				var gap: float=u.pos.distance_to(other.pos)
				if gap>1 and gap<85: motion+=other.pos.direction_to(u.pos)*(85-gap)/65.0
			var previous: Vector2=u.pos
			var speed: float=stats.speed*powers.speed_multiplier(u)
			if u.kind=='cavalry':
				var goal: Vector2=u.pos+motion.normalized()*u.pos.distance_to(steer)
				ride(u,goal.clamp(bounds.position,bounds.end),speed,dt,target)
				continue
			var stride: Vector2=motion.limit_length()*speed*dt
			var next: Vector2=u.pos+stride
			next=next.clamp(bounds.position,bounds.end)
			if not may_advance(u,next):
				if u.obstruction=='queue':continue
				next=u.pos.move_toward(steer,float(stats.speed)*powers.speed_multiplier(u)*dt)
				if not may_advance(u,next):continue
			u.pos=next
			record_march(u,previous)
		else:
			u.engaged=true
			if terrain and u.kind in ['legion','guard'] and target.kind in ['legion','guard']:
				Contact.press_wall(self,u,target)
			if u.kind in ['legion','guard','spear','cavalry','archer','siege'] and target.has('soldiers'):
				Soldiers.attack(self,u,target)
				continue
			if u.cooldown>0:continue
			if not lock_front and distance>.01:u.heading=u.pos.direction_to(target.pos)
			u.cooldown=float(stats.interval)
			u.attack_age=0.0
			if u.kind=='medic':
				heal(target,float(stats.heal))
				events.append({'kind':'heal','pos':target.pos,'from':u.pos})
				continue
			if u.kind=='siege':
				stones.append(Projectiles.schedule(self,{'side':u.side,'from':u.pos,'pos':target.pos,'target':target.id,'age':-.20 if terrain else 0.,'damage':stats.damage}))
				events.append({'kind':'launch','pos':u.pos})
				continue
			var damage: float=stats.damage
			if target.kind=='legion' and u.kind=='archer': damage*=.65
			if target.kind=='guard' and u.kind=='archer':damage*=1.0-float(config.types.guard.missile_reduction)
			if target.kind=='cavalry' and u.kind=='spear':damage*=float(stats.mounted_bonus)
			deal_blow(u,target,damage)
	for unit in units:Contact.turn(self,unit,dt)
	Soldiers.advance_personal(self,dt)
	if terrain:sweep_legion_charges(start_poses,dt)
	if combined_arms:separate_lines(dt)
	advance_projectiles(flying,dt)
	Soldiers.finish_deaths(self)
	collect_casualties()
	for unit in units:Contact.track_slots(self,unit,dt)
	resolve_battle(dt)

	if phase!='battle':
		for u in units:
			for actor in u.soldiers:
				if actor.has('charge_run'):Charges.finish(self,u,actor,'battle_ended')
				actor.erase('impulse')
		powers.clear(self)
		waves.clear()
		stones.clear()
		volleys.clear()
		ability_sounds.clear()

func record_casualty(u: Dictionary,slot: int):
	var actor: Dictionary=u.soldiers[slot]
	var point: Vector2=Soldiers.ground_position(self,u,slot)
	# Captured at the moment of death instead of every step for everyone; only in-flight
	# projectiles fired by this person read it during the dying window.
	actor.source_point=point
	var axis: Vector2=ground_basis.basis_xform(actor.get('heading',u.heading))
	var velocity: Vector2=actor.get('velocity',Vector2.ZERO)
	# Carry a cavalry launch into the existing corpse rig instead of dropping it
	# back onto its original foot. Ordinary death motion remains unchanged.
	var launched: bool=actor.has('charge_lift') and elapsed-actor.charge_lift.start<.46
	if launched:velocity+=actor.get('impulse',Vector2.ZERO)
	var attacker_point=null
	var attacker: Vector2i=actor.get('last_attacker',Vector2i(-1,-1))
	if attacker.y>=0 and attacker.x>=0:
		var source: Dictionary=unit_by_id(attacker.x)
		if not source.is_empty() and attacker.y<source.soldiers.size() and source.soldiers[attacker.y].get('death_state',0)==0:
			attacker_point=Soldiers.ground_position(self,source,attacker.y)
	# Legacy row reactions have no physical actor position; retain their displayed displacement.
	var foot: Vector2=projection*point+(Contact.body_shift(u,slot,elapsed) if not actor.has('position') else Vector2.ZERO)
	casualty_serial+=1
	var stats=Soldiers.individual(self,u)
	var motion=CorpseMotion.new()
	var source_delta=point-attacker_point if attacker_point!=null else null
	motion.setup(str(stats.get('reference_type','')),actor.get('heading',u.heading),velocity,source_delta,18. if int(CorpseMotion.definitions.types.get(stats.get('reference_type',''),-1)) in [6,12,13,26,27,45] else 12.,20260409+casualty_serial)
	casualties.append({'id':casualty_serial,'unit_id':u.id,'kind':u.kind,'art':u.get('art',u.kind),'side':u.side,
		'slot':slot,'foot':foot,'ground_point':point,'velocity':velocity,'attacker_point':attacker_point,
		'bearing':posmod(roundi(atan2(axis.x,axis.y)/(PI/4)),8),'scale':contact_profiles[u.kind].scale*u.get('visual_scale',1.),
		'time':elapsed,'step':simulation_step,'dir':ground_basis.basis_xform(motion.direction).normalized(),'motion':motion})
	if launched:casualties.back().charge_lift=actor.charge_lift.duplicate()
	if u.has('slot_states'):u.slot_states.erase(slot)

func advance_casualties(dt:float):
	if dt<=0:return
	for body in casualties:body.motion.advance(dt)
	casualties=casualties.filter(func(body):return body.motion.age<CorpseMotion.DURATION)

func collect_casualties():
	for u in units:
		u.visible_slots=[]
		for slot in u.soldiers.size():
			if Contact.drawable(u,slot):u.visible_slots.append(slot)

func in_formation_contact(u: Dictionary, enemy: Dictionary) -> bool:
	var gap: Vector2=enemy.pos-u.pos
	if terrain and terrain.clear_segment(u.kind,u.pos,enemy.pos):
		var separation=ground_basis.basis_xform(gap).abs()
		var edges: Vector2=terrain.extents[u.kind]+terrain.extents[enemy.kind]
		return separation.x<=edges.x and separation.y<=edges.y and Contact.touching(self,u,enemy)
	return gap.length_squared()<68*68

func combat_target(u: Dictionary) -> Dictionary:
	return powers.select_target(self,u)

func autonomous_destination(u: Dictionary,actor: Dictionary) -> Vector2:
	var target=combat_target(u)
	return actor.position if target.is_empty() else target.pos

func autonomous_engagement(_u: Dictionary,_actor: Dictionary,_target: Dictionary) -> bool:
	return true

# Keep the march itinerary while fighting nearby enemies; never turn this into auto.
func attack_move_target(u: Dictionary) -> Dictionary:
	if u.kind=='medic':return {}
	var reach=maxf(float(config.battle_commands.attack_move_acquire),float(config.types[u.kind].range))
	var best={}
	var distance=reach
	for enemy in alive('enemy' if u.side=='ally' else 'ally'):
		if u.pos.distance_to(enemy.pos)>reach+500.:continue
		for slot in u.soldiers.size():
			if u.soldiers[slot].hp<=0:continue
			var near=Soldiers.nearest(self,u,slot,enemy)
			if not near.is_empty() and near.distance<distance:
				distance=near.distance;best=enemy
	return best

func advance_objective(_u: Dictionary, _target: Dictionary, _dt: float) -> bool:
	return false

func resolve_battle(_dt: float):
	if alive('enemy').is_empty() and not Soldiers.pending_deaths(self,'enemy'): phase='victory'
	elif alive('ally').is_empty() and not Soldiers.pending_deaths(self,'ally') and not reserve.values().any(func(stock):return stock>0): phase='defeat'
	elif elapsed>=float(config.duration): phase='timeout'
