extends RefCounted
## Empty slots propagate rearwards. Engaged soldiers retain their current slot.
static func refill(b, r: Dictionary):
	if r.kind == 'cavalry' or r.form == 'free' or r.regrouping or r.form_time > 0: return
	var living = b.members(r)
	var occupied = {}
	for id in living: occupied[b.soldiers[id].slot] = id
	var slots = range(r.offsets.size())
	if r.form not in ['ring','ring_inner']:
		slots.sort_custom(func(a,c): return r.offsets[a].y < r.offsets[c].y)
	var reassigned = {}
	for vacancy in slots:
		if occupied.has(vacancy): continue
		var point: Vector2 = r.pos+b.Formation.world_offset(r.offsets[vacancy],r.heading)
		var nearest = -1; var distance = INF
		for id in living:
			var s: Dictionary = b.soldiers[id]
			if reassigned.has(id) or b.can_attack(s) or s.wedge_debuff > 0: continue
			if r.form not in ['ring','ring_inner'] and r.offsets[s.slot].y <= r.offsets[vacancy].y+0.1: continue
			if r.form in ['ring','ring_inner']:
				# A circle has no front: only leave an idle slot to gain an actual attack.
				# This also avoids circulating the same empty slot around the ring forever.
				if s.target < 0 or b.soldiers[s.target].hp <= 0: continue
				if point.distance_to(b.soldiers[s.target].pos) > b.stats[r.kind].range: continue
			var d: float = s.pos.distance_squared_to(point)
			if d < distance: distance = d; nearest = id
		if nearest < 0: continue
		var s: Dictionary = b.soldiers[nearest]
		occupied.erase(s.slot); s.slot = vacancy; occupied[vacancy] = nearest
		reassigned[nearest] = true

static func nearest_enemy_distance(b, r: Dictionary) -> float:
	var distance = INF
	for id in b.members(r):
		var s: Dictionary = b.soldiers[id]
		if s.target >= 0 and b.soldiers[s.target].hp > 0:
			distance = minf(distance,s.pos.distance_to(b.soldiers[s.target].pos))
	return distance

static func settled(b, r: Dictionary) -> bool:
	return b.members(r).all(func(id): return b.soldiers[id].pos.distance_to(b.slot_position(r,b.soldiers[id])) < 5)
