extends RefCounted
## Five catapult impacts per stone wall: official Demo0.4.0 announcement.
## Wall dimensions and Roman appearance are authored locally, not measured from that build.
static func at(r,ground: Vector2) -> Dictionary:
	for section in r.structures:
		if section.hits<section.limit and section.rect.has_point(r.projection*ground):return section
	return {}

static func pick(r,ground: Vector2) -> Dictionary:
	for section in r.structures:
		var visible=Rect2(section.rect.position-Vector2(0,70),section.rect.size+Vector2(0,70))
		if section.hits<section.limit and visible.has_point(r.projection*ground):return section
	return {}

static func find(r,id: String) -> Dictionary:
	for section in r.structures:
		if section.id==id and section.hits<section.limit:return section
	return {}

static func order(r,ids: Array,section: Dictionary) -> bool:
	if r.phase!='battle' or section.is_empty():return false
	var selected=r.Soldiers.members(r,ids).filter(func(row):return row.unit.kind=='siege' and row.unit.side!=section.side)
	if selected.is_empty():return false
	for row in selected:
		r.Soldiers.command(r,[Vector2i(row.unit.id,row.slot)],'hold',Vector2.ZERO)
		row.actor.erase('attack_pending')
		row.actor.personal_order='bombard';row.actor.structure_target=section.id
	return true

static func approach(r,row: Dictionary) -> Vector2:
	var actor: Dictionary=row.unit.soldiers[row.slot];var here: Vector2=actor.position
	var section=find(r,actor.get('structure_target',''))
	if section.is_empty():
		actor.personal_order='hold';actor.erase('attack_pending');return here
	var goal: Vector2=r.projection.affine_inverse()*section.rect.get_center()
	var distance=here.distance_to(goal)
	var reach: float=r.Soldiers.individual(r,row.unit).range
	if distance<150. or distance>reach:
		var away=goal.direction_to(here)
		if away.is_zero_approx():away=Vector2.DOWN
		return goal+away*(180. if distance<150. else reach*.8)
	actor.heading=here.direction_to(goal)
	if actor.cooldown<=0.:
		actor.cooldown=row.unit.get('combat_stats',r.config.types[row.unit.kind]).interval
		actor.attack_age=0.;actor.attack_pending=true
	return here

static func release(r,u: Dictionary,slot: int):
	var actor: Dictionary=u.soldiers[slot]
	var section=find(r,actor.get('structure_target',''))
	if section.is_empty():return
	var goal: Vector2=r.projection.affine_inverse()*section.rect.get_center()
	var foot: Vector2=r.Soldiers.ground_position(r,u,slot)
	if foot.distance_to(goal)<150.:return
	var from: Vector2=r.Projectiles.origin(r,u,slot);var distance=from.distance_to(goal)
	r.stones.append(r.Projectiles.schedule(r,{'side':u.side,'from':from,'pos':goal,'target':-1,'target_slot':-1,
		'attacker':u.id,'attacker_slot':slot,'age':0.,'damage':u.get('combat_stats',r.config.types[u.kind]).damage,
		'flight':clampf(distance/350.,.8,2.5),'peak':clampf(distance*.25,80.,250.),'structure':section.id}))
	r.events.append({'kind':'launch','pos':from})

static func impact(r,shot: Dictionary):
	if shot.has('wall_hit'):return
	var section=at(r,shot.pos)
	if section.is_empty() or section.side==shot.side:return
	shot.wall_hit=section.id
	section.hits+=1;section.last_hit=r.elapsed
	if section.hits<section.limit:return
	section.breached_at=r.elapsed
	var obstacles: Array=r.structure_base_rocks.duplicate()
	for wall in r.structures:
		if wall.hits<wall.limit:obstacles.append(wall.rect)
	r.terrain.replace_rocks(obstacles)
	for u in r.units:
		for actor in u.soldiers:
			actor.erase('steer_path');actor.erase('steer_goal');actor.erase('steer_retry')
