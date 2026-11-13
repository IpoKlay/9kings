extends RefCounted
## One swept contact area per rider; at most four distinct victims per charge.
static func begin(b, s: Dictionary, target: Dictionary) -> bool:
	var r: Dictionary = b.regiments[s.regiment]
	if r.kind != 'cavalry' or s.charge_cd > 0 or s.charging or r.form_time > 0 or r.order in ['move','retreat']: return false
	if target.is_empty() or target.hp <= 0 or s.pos.distance_to(target.pos) > b.tuning.charge_acquire_range: return false
	s.charging = true; s.charge_cd = b.tuning.charge_cooldown
	s.charge_left = b.tuning.charge_duration; s.charge_hits = []
	s.charge_heading = s.pos.direction_to(target.pos)
	if s.charge_heading.is_zero_approx(): s.charge_heading = r.heading
	s.charge_wedge = r.form == 'wedge'
	s.charge_control = s.charge_wedge and not s.first_charge_used
	s.first_charge_used = true
	return true

static func amount(b, rider: Dictionary, victim: Dictionary, index: int) -> float:
	var r: Dictionary = b.regiments[rider.regiment]
	var spear: bool = b.regiments[victim.regiment].kind == 'spear'
	var factors: Array = [1.0,1.0,0.5,0.25] if rider.charge_wedge else [2.0,1.0,0.5,0.25]
	if index >= 4: return 0.0
	var bonus = 0.0
	for value in r.charge_bonuses: bonus += float(value)
	return b.stats.cavalry.attack*(1.0 if spear else factors[index])*maxf(0,1+bonus)

static func stop(s: Dictionary):
	s.charging = false; s.charge_left = 0.0

static func advance(b, s: Dictionary, enemies: Array, dt: float):
	var start: Vector2 = s.pos
	var r: Dictionary = b.regiments[s.regiment]
	var speed: float = b.stats.cavalry.speed*b.tuning.charge_speed_multiplier*b.soldier_mods(s).speed
	var finish: Vector2 = start+s.charge_heading*speed*dt
	if not b.legal_point(finish): stop(s); return
	var hits = []
	var segment = finish-start
	for enemy in enemies:
		if enemy.hp <= 0 or enemy.id in s.charge_hits: continue
		var t = clampf((enemy.pos-start).dot(segment)/maxf(0.001,segment.length_squared()),0,1)
		if enemy.pos.distance_to(start+segment*t) <= b.tuning.charge_radius:
			hits.append({'soldier':enemy,'t':t})
	hits.sort_custom(func(a,c): return a.t < c.t if not is_equal_approx(a.t,c.t) else a.soldier.id < c.soldier.id)
	for row in hits:
		var enemy: Dictionary = row.soldier
		if s.charge_hits.size() >= 4: break
		var damage = amount(b,s,enemy,s.charge_hits.size())
		s.charge_hits.append(enemy.id)
		b.hit(enemy,damage,true)
		if s.charge_control: enemy.wedge_debuff = b.tuning.wedge_duration
		var enemy_reg: Dictionary = b.regiments[enemy.regiment]
		if enemy_reg.kind == 'shield': enemy_reg.broken = b.tuning.break_duration
		if enemy_reg.kind == 'spear' or s.charge_hits.size() == 4:
			finish = start+segment*row.t; stop(s); break
	s.pos = finish; s.moving = start.distance_to(finish) > 0.01
	s.walk += start.distance_to(finish)/60.0; s.heading = s.charge_heading
	s.charge_left -= dt
	if s.charge_left <= 0: stop(s)
