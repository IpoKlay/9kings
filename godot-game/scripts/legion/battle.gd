extends RefCounted
## A regiment owns orders and stats. HP, targets, attacks and projectiles remain individual.
const Formation = preload('res://scripts/legion/formations.gd')
const KINDS = ['spear','shield','cavalry','archer']
const BOUNDS = Rect2(240,210,2120,1280)
const DEPLOYMENT = Rect2(390,970,1840,480)
const OBSTACLES = [Rect2(1515,250,170,125)]
var stats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string('res://data/balance/legion_battle.json'))
var regiments: Array[Dictionary] = []
var soldiers: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var phase = 'deploy'
var elapsed = 0.0
var report = '先布阵，再开战。右键安排位置，右键拖动指定朝向。'
var losses = {'ally':0, 'enemy':0}
var navigation = AStarGrid2D.new()
var tick = 0

func _init():
	navigation.region = Rect2i(0,0,66,43)
	navigation.cell_size = Vector2(40,40)
	navigation.offset = Vector2(20,20)
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.update()
	for x in 66:
		for y in 43: navigation.set_point_solid(Vector2i(x,y), not legal_point(Vector2(x*40+20,y*40+20),16))
	var positions = [Vector2(800,1140),Vector2(1170,1140),Vector2(1970,1190),Vector2(1535,1260)]
	var enemy_positions = [Vector2(850,540),Vector2(1210,550),Vector2(1960,530),Vector2(1570,480)]
	for i in 4: add_regiment(KINDS[i],'ally',positions[i],35)
	for i in 4: add_regiment(KINDS[i],'enemy',enemy_positions[i],30)

func legal_point(point: Vector2, radius: float = 11.0) -> bool:
	if not BOUNDS.grow(-radius).has_point(point): return false
	for obstacle in OBSTACLES:
		if obstacle.grow(radius).has_point(point): return false
	return true

func add_regiment(kind: String, side: String, position: Vector2, count: int):
	var r = {'id':regiments.size(), 'kind':kind, 'side':side, 'pos':position, 'goal':position,
		'heading':Vector2.UP if side == 'ally' else Vector2.DOWN, 'form':'default', 'pending':'',
		'form_time':0.0, 'form_cd':0.0, 'rain_cd':0.0, 'debuff':0.0, 'broken':0.0,
		'order':'hold', 'target':-1, 'path':[], 'members':[], 'offsets':[], 'initial':count}
	regiments.append(r)
	for i in count:
		var s = {'id':soldiers.size(), 'regiment':r.id, 'slot':i, 'pos':position, 'heading':r.heading,
			'hp':float(stats[kind].hp), 'max_hp':float(stats[kind].hp), 'cooldown':float(i%7)*0.07,
			'target':-1, 'attack_age':10.0, 'hit_time':-100.0, 'death_time':0.0,
			'walk':0.0, 'moving':false, 'charge_distance':0.0, 'charge_ready':false}
		r.members.append(s.id)
		soldiers.append(s)
	reform(r,true)

func members(r: Dictionary) -> Array:
	return r.members.filter(func(id): return soldiers[id].hp > 0)

func alive(side: String) -> Array:
	return soldiers.filter(func(s): return s.hp > 0 and regiments[s.regiment].side == side)

func strength(side: String) -> int: return alive(side).size()

func hp(r: Dictionary) -> float:
	var total = 0.0
	for id in r.members: total += maxf(0,soldiers[id].hp)
	return total

func reform(r: Dictionary, instant: bool = false):
	var living = members(r)
	r.offsets = Formation.offsets(living.size(),r.form)
	for i in living.size():
		var s: Dictionary = soldiers[living[i]]
		s.slot = i
		if instant:
			s.pos = slot_position(r,s)
			s.heading = (s.pos-r.pos).normalized() if r.form == 'ring' else r.heading

func slot_position(r: Dictionary, s: Dictionary) -> Vector2:
	if s.slot >= r.offsets.size(): return r.pos
	if r.form_time > 0 and r.pending != '':
		var pending_offsets = Formation.offsets(r.offsets.size(),r.pending)
		return r.pos + Formation.world_offset(pending_offsets[s.slot],r.heading)
	return r.pos + Formation.world_offset(r.offsets[s.slot],r.heading)

func placement_valid(r: Dictionary, point: Vector2, heading: Vector2, form: String, moving_ids: Array = []) -> bool:
	var points = Formation.offsets(members(r).size(),form)
	for offset in points:
		var p = point + Formation.world_offset(offset,heading)
		if not DEPLOYMENT.grow(-10).has_point(p) or not legal_point(p): return false
		for other in soldiers:
			if other.hp > 0 and other.regiment != r.id and other.regiment not in moving_ids and other.pos.distance_squared_to(p) < 22*22: return false
	return true

func deploy(ids: Array, point: Vector2, heading: Vector2 = Vector2.ZERO) -> bool:
	if phase != 'deploy' or ids.is_empty(): return false
	var center = Vector2.ZERO
	for id in ids: center += regiments[id].pos
	center /= ids.size()
	var plans = []
	for id in ids:
		var r: Dictionary = regiments[id]
		if r.side != 'ally': return false
		var p: Vector2 = point + r.pos - center
		var h: Vector2 = r.heading if heading.is_zero_approx() else heading.normalized()
		if not placement_valid(r,p,h,r.form,ids):
			report = '布阵失败：整队必须在部署区内，且不能与其他士兵重叠。'
			return false
		plans.append([r,p,h])
	# Validate the final arrangement, not the old positions of other selected legions.
	var occupied = []
	for row in plans:
		for offset in row[0].offsets:
			var p: Vector2 = row[1]+Formation.world_offset(offset,row[2])
			for prior in occupied:
				if prior.regiment != row[0].id and p.distance_squared_to(prior.pos) < 22*22:
					report = '部署后的军团会相互重叠。'; return false
			occupied.append({'regiment':row[0].id,'pos':p})
	for row in plans:
		row[0].pos = row[1]; row[0].goal = row[1]; row[0].heading = row[2]
		reform(row[0],true)
	report = '已部署。右键拖动可调整朝向。'
	return true

func set_formation(ids: Array, form: String) -> bool:
	if phase not in ['deploy','battle'] or ids.is_empty(): return false
	for id in ids:
		var r: Dictionary = regiments[id]
		if r.side != 'ally' or members(r).is_empty() or form not in Formation.OPTIONS[r.kind]: return false
		if phase == 'battle' and (r.form_time > 0 or r.form_cd > 0):
			report = '换阵尚未完成或仍在冷却。'; return false
		if phase == 'deploy' and not placement_valid(r,r.pos,r.heading,form):
			report = '这个阵型需要更多空间，请先把军团移到空旷处。'; return false
	for id in ids:
		var r: Dictionary = regiments[id]
		if r.form == form: continue
		if phase == 'deploy': r.form = form; reform(r,true)
		else: r.pending = form; r.form_time = 3.0; r.form_cd = 13.0
	report = '已切换至'+Formation.NAMES[form] if phase == 'deploy' else '正在换阵：3 秒内无法攻击；完成后冷却 10 秒。'
	return true

func start() -> bool:
	if phase != 'deploy': return false
	phase = 'battle'
	for r in regiments: r.order = 'auto'
	report = '战斗开始。右键敌军集火，右键地面移动，H 坚守，R 撤退。'
	return true

func route(start_point: Vector2, end_point: Vector2, clearance: float = 16.0) -> Array:
	for x in 66:
		for y in 43: navigation.set_point_solid(Vector2i(x,y), not legal_point(Vector2(x*40+20,y*40+20),clearance))
	var a = Vector2i((start_point / 40).floor())
	var b = Vector2i((end_point / 40).floor())
	if not navigation.is_in_boundsv(a) or not navigation.is_in_boundsv(b) or navigation.is_point_solid(b): return []
	# A retreat can begin in contact or near an obstacle; allow its existing start cell.
	navigation.set_point_solid(a,false)
	var points: Array = Array(navigation.get_point_path(a,b))
	if not points.is_empty(): points[points.size()-1] = end_point
	return points

func command(ids: Array, order: String, point: Vector2 = Vector2.ZERO, target: int = -1) -> bool:
	ids = ids.filter(func(id): return regiments[id].side == 'ally' and not members(regiments[id]).is_empty())
	if phase != 'battle' or ids.is_empty(): return false
	var plans = []
	var center = Vector2.ZERO
	for id in ids: center += regiments[id].pos
	center /= ids.size()
	for id in ids:
		var r: Dictionary = regiments[id]
		if r.side != 'ally' or members(r).is_empty(): continue
		var radius = 20.0
		for offset in r.offsets: radius = maxf(radius,offset.length()+15)
		var goal: Vector2 = point+r.pos-center if order == 'move' else Vector2(clampf(r.pos.x,450,2200),1380) if order == 'retreat' else r.pos
		goal = goal.clamp(BOUNDS.position+Vector2.ONE*(radius+20),BOUNDS.end-Vector2.ONE*(radius+20))
		var path = route(r.pos,goal,radius) if order in ['move','retreat'] else []
		if order in ['move','retreat'] and path.is_empty(): report = '目标无法到达。'; return false
		plans.append([r,goal,path])
	for row in plans:
		var r: Dictionary = row[0]
		r.order = order; r.goal = row[1]; r.path = row[2]; r.target = target
		for id in r.members: soldiers[id].target = -1
	report = {'move':'行军中，到达后坚守。','hold':'原地坚守。','auto':'自由接敌。','attack':'集中攻击目标军团。','retreat':'撤往后方；安全脱战 6 秒后恢复存活士兵的生命。'}.get(order,'已下令')
	return not plans.is_empty()

func mods(r: Dictionary) -> Dictionary:
	var m = Formation.modifiers('default' if r.form == 'testudo' and r.broken > 0 else r.form)
	if r.debuff > 0: m.attack -= 0.25; m.speed *= 0.75; m.rate *= 0.75
	return m

static func damage_value(base: float, attack_bonuses: Array, reduction_bonuses: Array, armor: float, armor_bonuses: Array) -> float:
	var attack_bonus = 0.0; var reduction = 0.0; var armor_bonus = 0.0
	for b in attack_bonuses: attack_bonus += float(b)
	for b in reduction_bonuses: reduction += float(b)
	for b in armor_bonuses: armor_bonus += float(b)
	return maxf(0, base*maxf(0,1+attack_bonus)*(1-clampf(reduction,0,1))-armor*maxf(0,1+armor_bonus))

func target_for(s: Dictionary, enemies: Array) -> int:
	var r: Dictionary = regiments[s.regiment]
	var best = -1; var score = INF
	for other in enemies:
		if other.hp <= 0: continue
		var value: float = s.pos.distance_squared_to(other.pos)
		if r.order == 'attack' and other.regiment != r.target: value *= 4.0
		if value < score: score = value; best = other.id
	return best

func regiment_target(r: Dictionary) -> Dictionary:
	if r.order == 'attack' and r.target >= 0 and not members(regiments[r.target]).is_empty(): return regiments[r.target]
	var best: Dictionary = {}; var distance = INF
	for other in regiments:
		if other.side == r.side or members(other).is_empty(): continue
		var d: float = r.pos.distance_squared_to(other.pos)
		if d < distance: distance = d; best = other
	return best

func move_soldier(s: Dictionary, destination: Vector2, speed: float, dt: float):
	var old: Vector2 = s.pos
	var next: Vector2 = old.move_toward(destination,speed*dt)
	if legal_point(next): s.pos = next
	elif legal_point(Vector2(next.x,old.y)): s.pos = Vector2(next.x,old.y)
	elif legal_point(Vector2(old.x,next.y)): s.pos = Vector2(old.x,next.y)
	var distance: float = old.distance_to(s.pos)
	s.moving = distance > 0.01
	if s.moving:
		s.heading = old.direction_to(s.pos); s.walk += distance/60.0
		if elapsed-s.hit_time > 2.0:
			s.charge_distance += distance
			if s.charge_distance >= 150: s.charge_ready = true

func update(dt: float):
	if phase != 'battle': return
	elapsed += dt; tick += 1
	var sides = {'ally':alive('ally'),'enemy':alive('enemy')}
	for r in regiments:
		for key in ['form_cd','rain_cd','debuff','broken']: r[key] = maxf(0,r[key]-dt)
		if r.form_time > 0:
			r.form_time = maxf(0,r.form_time-dt)
			if r.form_time <= 0:
				r.form = r.pending; r.pending = ''; reform(r)
				if r.side == 'ally': report = stats[r.kind].name+'已完成换阵：'+Formation.NAMES[r.form]
		if members(r).is_empty(): continue
		var velocity: float = stats[r.kind].speed * mods(r).speed
		if r.order in ['auto','attack']:
			var target = regiment_target(r)
			if not target.is_empty():
				var direction: Vector2 = r.pos.direction_to(target.pos)
				var desired = 280.0 if r.kind == 'archer' else 110.0
				if r.pos.distance_to(target.pos) > desired:
					var next: Vector2 = r.pos + direction*velocity*dt
					if legal_point(next,70): r.pos = next
				if r.form != 'ring': r.heading = direction
		elif r.order in ['move','retreat'] and not r.path.is_empty():
			var point: Vector2 = r.path[0]
			if r.pos.distance_to(point) <= velocity*dt+1: r.pos = point; r.path.pop_front()
			else: r.heading = r.pos.direction_to(point); r.pos = r.pos.move_toward(point,velocity*dt)
			if r.path.is_empty() and r.order == 'move': r.order = 'hold'
	for s in soldiers:
		if s.hp <= 0: continue
		var r: Dictionary = regiments[s.regiment]
		var data: Dictionary = stats[r.kind]
		var m = mods(r)
		s.cooldown -= dt; s.attack_age += dt; s.moving = false
		var enemies: Array = sides['enemy' if r.side == 'ally' else 'ally']
		if s.target < 0 or soldiers[s.target].hp <= 0 or (tick+s.id)%9 == 0: s.target = target_for(s,enemies)
		var target: Dictionary = soldiers[s.target] if s.target >= 0 else {}
		var slot = slot_position(r,s)
		var distance: float = s.pos.distance_to(target.pos) if not target.is_empty() else INF
		var marching: bool = r.order in ['move','retreat']
		var contact: bool = not marching and r.form_time <= 0 and distance <= data.range
		if contact:
			s.heading = s.pos.direction_to(target.pos)
			if s.cooldown <= 0:
				s.cooldown = data.interval / m.rate; s.attack_age = 0.0
				var ranged: bool = r.kind == 'archer' and distance > 65
				var charge: bool = r.kind in ['cavalry','spear','shield'] and s.charge_ready
				var amount = attack_damage(s,target,ranged,charge)
				if ranged:
					projectiles.append({'from':s.pos,'to':target.pos,'age':0.0,'duration':maxf(0.15,distance/620.0),'target':target.id,'damage':amount,'rain':false})
				else: hit(target,amount,charge)
				if charge:
					s.charge_ready = false; s.charge_distance = 0.0
					var enemy_reg: Dictionary = regiments[target.regiment]
					if r.kind == 'cavalry' and enemy_reg.form == 'testudo': enemy_reg.broken = 4.0
					if r.form == 'wedge': enemy_reg.debuff = 4.0
		else:
			var destination: Vector2 = slot
			if not marching and r.form_time <= 0 and not target.is_empty() and distance < (230 if r.order != 'hold' else 110) and r.kind != 'archer': destination = target.pos
			var speed: float = data.speed*m.speed*(1.12 if marching else 1.0)
			if r.form_time > 0: speed = maxf(speed,s.pos.distance_to(destination)/maxf(dt,r.form_time))
			move_soldier(s,destination,speed,dt)
		if not contact and not s.moving: s.heading = (s.pos-r.pos).normalized() if r.form == 'ring' else r.heading
		var rear: bool = s.pos.y > 1120 if r.side == 'ally' else s.pos.y < 580
		if rear and distance > 430 and elapsed-s.hit_time >= 6 and r.order in ['retreat','hold']:
			s.hp = minf(s.max_hp,s.hp+s.max_hp*0.035*dt)
	separate()
	for shot in projectiles:
		shot.age += dt
		if shot.age >= shot.duration:
			if shot.rain:
				for s in soldiers:
					if s.hp > 0 and regiments[s.regiment].side != shot.side and s.pos.distance_to(shot.to) <= 92:
						var r: Dictionary = regiments[s.regiment]
						var amount = damage_value(shot.damage,[],[],stats[r.kind].ranged_armor,[mods(r).armor])
						hit(s,amount*mods(r).area,false)
				effects.append({'pos':shot.to,'age':0.0,'kind':'rain'})
			elif soldiers[shot.target].hp > 0: hit(soldiers[shot.target],shot.damage,false)
	projectiles = projectiles.filter(func(p): return p.age < p.duration)
	for e in effects: e.age += dt
	effects = effects.filter(func(e): return e.age < 0.5)
	if strength('enemy') == 0: finish('victory')
	elif strength('ally') == 0: finish('defeat')

func attack_damage(attacker: Dictionary, defender: Dictionary, ranged: bool, charge: bool) -> float:
	var a: Dictionary = regiments[attacker.regiment]; var b: Dictionary = regiments[defender.regiment]
	var am = mods(a); var bm = mods(b)
	var bonus: float = am.attack
	if a.kind == 'spear' and b.kind == 'cavalry': bonus += 0.8
	if a.kind == 'cavalry' and b.kind in ['shield','archer']: bonus += 0.35
	if charge:
		bonus += (1.0 if a.kind == 'cavalry' else 0.35) + am.charge
		if a.kind == 'cavalry' and b.heading.dot(defender.pos.direction_to(attacker.pos)) < 0.25: bonus += 0.6
	var armor: float = stats[b.kind].ranged_armor if ranged else stats[b.kind].melee_armor
	return damage_value(stats[a.kind].attack,[bonus],[],armor,[bm.armor])

func hit(s: Dictionary, damage: float, charge: bool):
	if s.hp <= 0: return
	s.hp = maxf(0,s.hp-damage); s.hit_time = elapsed
	if effects.size() < 120: effects.append({'pos':s.pos,'age':0.0,'kind':'charge' if charge else 'hit'})
	if s.hp <= 0:
		s.death_time = elapsed
		var r: Dictionary = regiments[s.regiment]
		losses[r.side] += 1
		reform(r)

func separate():
	var grid = {}
	for s in soldiers:
		if s.hp <= 0: continue
		var key = Vector2i((s.pos/24.0).floor())
		if not grid.has(key): grid[key] = []
		grid[key].append(s)
	for s in soldiers:
		if s.hp <= 0: continue
		var key = Vector2i((s.pos/24.0).floor())
		for x in range(-1,2):
			for y in range(-1,2):
				for other in grid.get(key+Vector2i(x,y),[]):
					if other.id <= s.id: continue
					var delta: Vector2 = s.pos-other.pos
					var d = delta.length()
					if d >= 19: continue
					var shift: Vector2 = (delta/d if d > 0.01 else Vector2.RIGHT)*minf(3,(19-d)*0.5)
					if legal_point(s.pos+shift): s.pos += shift
					if legal_point(other.pos-shift): other.pos -= shift

func arrow_rain(ids: Array, point: Vector2) -> bool:
	if phase != 'battle' or not legal_point(point,0): return false
	var fired = false
	for id in ids:
		var r: Dictionary = regiments[id]
		if r.side != 'ally' or r.kind != 'archer' or r.rain_cd > 0 or r.form_time > 0 or members(r).is_empty(): continue
		if r.pos.distance_to(point) > 650: report = '箭雨射程为 650，目标太远。'; continue
		r.rain_cd = 18.0
		projectiles.append({'from':r.pos,'to':point,'age':0.0,'duration':1.25,'target':-1,'rain':true,'side':r.side,
			'damage':stats.archer.attack*(1+mods(r).rain)*2.2*members(r).size()/35.0})
		for soldier_id in members(r): soldiers[soldier_id].attack_age = 0.0
		fired = true
	if fired: report = '箭雨已发射。'
	return fired

func finish(result: String):
	phase = result
	for s in soldiers:
		if s.hp > 0: s.hp = s.max_hp
	report = '敌军已被击溃。幸存者恢复生命，阵亡士兵不复活。' if result == 'victory' else '我方四个军团全部阵亡。'
