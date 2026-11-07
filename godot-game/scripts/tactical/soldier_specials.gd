extends RefCounted
## Source-derived old-build attacks; both still require a live main target at release.
const SLAM_RADIUS=80.
const HEAL_RADIUS=120.

static func slam(r,u: Dictionary,slot: int):
	var origin: Vector2=r.Soldiers.ground_position(r,u,slot)
	var damage: float=u.get('combat_stats',r.config.types[u.kind]).damage
	for enemy in r.alive('enemy' if u.side=='ally' else 'ally'):
		for i in enemy.soldiers.size():
			var victim: Dictionary=enemy.soldiers[i]
			if victim.hp<=0:continue
			var delta: Vector2=r.Soldiers.ground_position(r,enemy,i)-origin
			var distance: float=delta.length()
			if distance>SLAM_RADIUS:continue
			var strength: float=1.-.6*distance/SLAM_RADIUS
			r.deal_blow(u,enemy,damage*strength,{}, {'attacker_slot':slot,'target_slot':i})
			if distance>.1:
				r.Charges.detach(r,enemy,i)
				victim.impulse=victim.get('impulse',Vector2.ZERO)+delta/distance*300.*strength
	r.events.append({'kind':'troll_slam','pos':origin,'radius':SLAM_RADIUS,'attacker':u.id,'attacker_slot':slot})

static func heal_nearby(r,u: Dictionary,slot: int):
	var origin: Vector2=r.Soldiers.ground_position(r,u,slot)
	for ally in r.alive(u.side):
		for i in ally.soldiers.size():
			var patient: Dictionary=ally.soldiers[i]
			if patient.hp<=0 or patient.hp>=patient.max_hp or (ally.id==u.id and i==slot):continue
			var point: Vector2=r.Soldiers.ground_position(r,ally,i)
			if origin.distance_squared_to(point)>HEAL_RADIUS*HEAL_RADIUS:continue
			var amount: float=minf(15.,patient.max_hp-patient.hp)
			patient.hp+=amount
			r.events.append({'kind':'shaman_heal','pos':point,'from':origin,'amount':amount,'target':ally.id,'target_slot':i,'attacker':u.id,'attacker_slot':slot})
		r.Soldiers.total(ally)
	# The cast sound exists even when no nearby ally needs healing.
	r.events.append({'kind':'shaman_cast','pos':origin,'attacker':u.id,'attacker_slot':slot})
