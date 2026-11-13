extends RefCounted
## An explicitly ordered, rigid regiment sweep. The center soldier lands on the marker.
static func center_soldier(b, r: Dictionary) -> int:
	var best = -1; var distance = INF
	for id in b.members(r):
		var s: Dictionary = b.soldiers[id]
		var d: float = r.offsets[s.slot].length_squared()
		if d < distance: distance = d; best = id
	return best

static func plan(b, r: Dictionary, point: Vector2) -> Dictionary:
	if r.kind != 'cavalry' or r.form == 'free' or r.regrouping or r.form_time > 0 or r.charge_cd > 0 or r.charge_state != '' or b.members(r).is_empty(): return {}
	var anchor = center_soldier(b,r)
	var center: Vector2 = b.centroid(r) if b.phase == 'battle' else r.pos
	var heading: Vector2 = center.direction_to(point)
	if heading.is_zero_approx(): return {}
	var goal: Vector2 = point-b.Formation.world_offset(r.offsets[b.soldiers[anchor].slot],heading)
	# Validate every lane, not only the center, before accepting the order.
	for id in b.members(r):
		var offset: Vector2 = b.Formation.world_offset(r.offsets[b.soldiers[id].slot],heading)
		var start: Vector2 = center+offset
		var finish: Vector2 = goal+offset
		for i in range(ceili(start.distance_to(finish)/10.0)+1):
			if not b.legal_point(start.move_toward(finish,i*10.0)): return {}
		if not b.legal_point(finish): return {}
	return {'center':center,'heading':heading,'goal':goal,'point':point,'anchor':anchor}

static func order(b, ids: Array, point: Vector2) -> bool:
	if b.phase not in ['deploy','battle'] or ids.is_empty(): return false
	var plans = []
	for id in ids:
		var r: Dictionary = b.regiments[id]
		if r.side != 'ally': return false
		var p = plan(b,r,point)
		if p.is_empty(): b.report = '冲锋需要已成阵且冷却完成的骑兵，整队路径不能穿过地形。'; return false
		plans.append({'r':r,'plan':p})
	for row in plans:
		var r: Dictionary = row.r
		r.charge_point = point; r.charge_queued = b.phase == 'deploy'
		if b.phase == 'battle': prepare(b,r,row.plan)
	b.report = '已预设冲锋：开战后整队朝标记前进，H 取消预令。' if b.phase == 'deploy' else '正在整队；完成后一起朝冲锋目标前进。'
	return true

static func prepare(b, r: Dictionary, p: Dictionary):
	r.pos = p.center; r.heading = p.heading; r.goal = p.goal
	r.charge_point = p.point; r.charge_anchor = p.anchor; r.charge_queued = false
	r.charge_state = 'forming'; r.order = 'charge'; r.path = []
	for id in b.members(r):
		var s: Dictionary = b.soldiers[id]
		s.charging = false; s.charge_hits = []; s.target = -1

static func stop(b, r: Dictionary):
	r.charge_state = ''; r.charge_queued = false
	if r.order == 'charge': r.order = 'hold'
	for id in r.members: b.soldiers[id].charging = false

static func advance(b, r: Dictionary, enemies: Array, dt: float):
	if r.charge_state == 'forming':
		if not b.members(r).all(func(id): return b.soldiers[id].pos.distance_to(b.slot_position(r,b.soldiers[id])) < 0.1): return
		r.charge_state = 'running'; r.charge_cd = b.tuning.charge_cooldown
		for id in b.members(r):
			var s: Dictionary = b.soldiers[id]
			s.charging = true; s.charge_control = r.form == 'wedge' and not s.first_charge_used
			s.first_charge_used = true
	if r.charge_state != 'running': return
	var delta: Vector2 = r.pos.move_toward(r.goal,b.formation_speed(r)*b.tuning.charge_speed_multiplier*dt)-r.pos
	if delta.is_zero_approx():
		if r.pos.distance_to(r.goal) < 0.1: stop(b,r)
		return
	for id in b.members(r):
		if not b.legal_point(b.soldiers[id].pos+delta): stop(b,r); return
	for id in b.members(r):
		var s: Dictionary = b.soldiers[id]; var start: Vector2 = s.pos
		for enemy in enemies:
			if enemy.hp <= 0 or enemy.id in s.charge_hits: continue
			var t = clampf((enemy.pos-start).dot(delta)/delta.length_squared(),0,1)
			if enemy.pos.distance_to(start+delta*t) > b.tuning.charge_radius: continue
			s.charge_hits.append(enemy.id)
			b.hit(enemy,b.stats[r.kind].attack*b.tuning.charge_damage_factor,true)
			if s.charge_control: enemy.wedge_debuff = b.tuning.wedge_duration
			var victim: Dictionary = b.regiments[enemy.regiment]
			if victim.kind == 'shield': victim.broken = b.tuning.break_duration
		s.pos += delta; s.moving = true; s.walk += delta.length()/60.0; s.heading = r.heading
	r.pos += delta
	if r.pos.distance_to(r.goal) < 0.1: stop(b,r)
