extends RefCounted
## Ground-targeted longbow ability. Ordinary arrows keep their existing tracking path.
const RANGE=900.
const COOLDOWN=15.

static func capable(r,row: Dictionary) -> bool:
	return r.Soldiers.individual(r,row.unit).get('has_volley',false)

static func ready(r,ids: Array) -> Array:
	return r.Soldiers.members(r,ids).filter(func(row):return capable(r,row) and row.actor.get('volley_cooldown',0.)<=0.)

static func radius(count: int) -> float:
	return 50.+4.*sqrt(float(count))

static func center(r,people: Array) -> Vector2:
	var value=Vector2.ZERO
	for row in people:value+=r.Soldiers.ground_position(r,row.unit,row.slot)
	return value/maxi(1,people.size())

static func issue(r,ids: Array,target: Vector2) -> bool:
	if r.phase!='battle' or not target.is_finite() or not r.bounds.has_point(target):return false
	var people=ready(r,ids)
	if people.is_empty() or center(r,people).distance_to(target)>RANGE*1.2:return false
	var spread=radius(people.size())*.4
	var damage: float=people[0].unit.get('combat_stats',r.config.types[people[0].unit.kind]).damage
	for row in people:
		row.actor.volley_cooldown=COOLDOWN
		row.actor.attack_age=0.
		row.actor.erase('attack_pending')
		row.actor.heading=r.Soldiers.ground_position(r,row.unit,row.slot).direction_to(target)
		row.unit.attack_age=0.
	for i in people.size()*3:
		var row: Dictionary=people[i%people.size()]
		var origin: Vector2=r.Soldiers.ground_position(r,row.unit,row.slot)
		var landing=target+Vector2(r.volley_random.randf_range(-spread,spread),r.volley_random.randf_range(-spread,spread))
		var distance=origin.distance_to(landing)
		r.volleys.append(r.Projectiles.schedule(r,{'kind':'ability_volley','side':row.unit.side,'attacker':row.unit.id,'attacker_slot':row.slot,
			'from':origin,'pos':landing,'target':-1,'damage':damage,'age':-r.volley_random.randf_range(0.,.4),
			'release_delay':0.,'flight':clampf(distance/500.,.6,2.),'peak':clampf(distance*.2,60.,200.)}))
	for i in mini(people.size(),6):
		r.ability_sounds.append({'delay':float(i)*.07,'pos':r.Soldiers.ground_position(r,people[i].unit,people[i].slot)})
	return true

static func advance_sounds(r,dt: float):
	for sound in r.ability_sounds:
		sound.delay-=dt
		if sound.delay<=0:r.events.append({'kind':'arrow','volley':true,'ability':'volley','pos':sound.pos,'from':sound.pos})
	r.ability_sounds=r.ability_sounds.filter(func(sound):return sound.delay>0.)

static func land(r,arrow: Dictionary):
	var target={};var slot=-1;var distance=21.
	# Public build initializes the nearest-hit threshold to nominal radius 20 + 1.
	for u in r.alive('enemy' if arrow.side=='ally' else 'ally'):
		for i in u.soldiers.size():
			if u.soldiers[i].hp<=0:continue
			var current: float=arrow.pos.distance_to(r.Soldiers.ground_position(r,u,i))
			if current<distance:distance=current;target=u;slot=i
	if target.is_empty():return
	# This ability's public-build damage has no attacker; directional shield blocking does not apply.
	var dealt: float=r.hurt(target,arrow.damage,'archer',0.,slot)
	if dealt<=0:return
	var impact: Vector2=r.Soldiers.ground_position(r,target,slot)
	r.Contact.light_hit(r,target,r.ground_basis.basis_xform(impact-target.pos),r.ground_basis.basis_xform(impact-arrow.from).normalized(),slot)
	r.events.append({'kind':'hit','ability':'volley','pos':impact,'damage':dealt,'target':target.id,'target_slot':slot})
