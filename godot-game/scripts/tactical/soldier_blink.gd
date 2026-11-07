extends RefCounted
## The aim gate and each caster's actual displacement are different in the reference.
const RANGE=250.
const DISTANCE=200.
const COOLDOWN=8.

static func capable(r,row: Dictionary) -> bool:
	return r.Soldiers.individual(r,row.unit).get('has_blink',false)

static func ready(r,ids: Array) -> Array:
	return r.Soldiers.members(r,ids).filter(func(row):return capable(r,row) and row.actor.get('blink_cooldown',0.)<=0.)

static func center(r,people: Array) -> Vector2:
	var point=Vector2.ZERO
	for row in people:point+=r.Soldiers.ground_position(r,row.unit,row.slot)
	return point/maxi(1,people.size())

static func issue(r,ids: Array,target: Vector2) -> bool:
	if r.phase!='battle' or not target.is_finite():return false
	var people=ready(r,ids)
	if people.is_empty() or center(r,people).distance_to(target)>RANGE*1.2:return false
	var squads={}
	for row in people:
		if not row.unit.has('slot_distances'):r.Contact.track_slots(r,row.unit,0.)
		r.Charges.detach(r,row.unit,row.slot)
		var actor: Dictionary=row.actor
		var origin: Vector2=actor.position
		var offset=target-origin
		actor.position=origin+offset.limit_length(DISTANCE)
		actor.heading=Vector2.from_angle(offset.angle())
		actor.personal_order='idle'
		actor.target_id=-1;actor.target_slot=-1;actor.focus_id=-1;actor.focus_slot=-1
		actor.path=[];actor.erase('resume_attack_move');actor.erase('attack_engaged')
		actor.blink_cooldown=COOLDOWN
		# A blink is an instantaneous relocation, not gait distance or a terrain path.
		actor.settled_position=actor.position
		row.unit.slot_last_feet[row.slot]=r.projection*actor.position
		row.unit.slot_speeds[row.slot]=0.
		squads[row.unit.id]=row.unit
		r.events.append({'kind':'blink','pos':actor.position,'from':origin,'attacker':row.unit.id,'attacker_slot':row.slot})
	for u in squads.values():
		var distance: float=u.march_distance
		r.Soldiers.update_center(r,u,0.)
		u.march_distance=distance
		if u.soldiers.all(func(a):return a.hp<=0 or a.get('personal_order','')=='idle'):
			u.order='idle';u.waypoints.clear()
	return true

static func cleave(r,u: Dictionary,slot: int,target: Dictionary):
	var origin: Vector2=r.Soldiers.ground_position(r,u,slot)
	var heading: Vector2=u.soldiers[slot].heading
	var damage: float=u.get('combat_stats',r.config.types[u.kind]).damage
	r.deal_blow(u,target.unit,damage,{}, {'attacker_slot':slot,'target_slot':target.near.slot})
	for enemy in r.alive('enemy' if u.side=='ally' else 'ally'):
		for i in enemy.soldiers.size():
			if enemy.soldiers[i].hp<=0 or (enemy.id==target.unit.id and i==target.near.slot):continue
			var delta: Vector2=r.Soldiers.ground_position(r,enemy,i)-origin
			if delta.length_squared()>50.*50. or absf(heading.angle_to(delta.normalized()))>PI/4:continue
			r.deal_blow(u,enemy,damage*.6,{}, {'attacker_slot':slot,'target_slot':i})
	r.events.append({'kind':'scythe','pos':origin,'heading':heading,'attacker':u.id,'attacker_slot':slot})
