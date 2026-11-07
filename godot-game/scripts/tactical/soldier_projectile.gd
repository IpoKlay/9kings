extends RefCounted
## Ordinary homing shots use actual positions; V volleys retain ground-targeted arcs.
static var anchors: Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://data/presentation/projectile_anchors.json'))

static func schedule(r,shot: Dictionary) -> Dictionary:
	r.projectile_serial+=1
	shot.serial=r.projectile_serial
	return shot

static func origin(r,u: Dictionary,slot: int) -> Vector2:
	var foot: Vector2=r.Soldiers.ground_position(r,u,slot)
	var art: String=u.get('art',u.kind)
	if not anchors.has(art):return foot
	var actor: Dictionary=u.soldiers[slot]
	var heading: Vector2=r.ground_basis.basis_xform(actor.get('heading',u.heading))
	var bearing=posmod(roundi(atan2(heading.x,heading.y)/(PI/4)),8)
	var frame=clampi(int(actor.attack_age/r.Soldiers.ATTACK_DURATION*8),0,7)
	var cell=r.Contact.cell_index(true,false,frame,slot%4)-9
	var xy: Array=anchors[art][bearing][cell]
	var scale: float=r.contact_profiles[u.kind].scale*u.get('visual_scale',1.)
	return foot+r.ground_basis.affine_inverse().basis_xform(Vector2(xy[0],xy[1])*scale)

static func source(r,shot: Dictionary) -> Dictionary:
	for u in r.units:
		if u.id!=shot.get('attacker',-1):continue
		if u.get('escaped',false):return {}
		var slot: int=shot.get('attacker_slot',-1)
		if slot>=0:
			if slot>=u.soldiers.size():return {}
			var actor: Dictionary=u.soldiers[slot]
			var state: int=actor.get('death_state',0)
			if state==2:return {}
			return {'unit':u,'slot':slot if state==0 else -1,'registered':state==0,
				'point':actor.source_point if state==1 else r.Soldiers.ground_position(r,u,slot)}
		if u.hp>0:return {'unit':u,'slot':-1,'registered':true,'point':u.pos}
	return {}

static func impact(r,shot: Dictionary,target: Dictionary,slot: int,kind: String) -> float:
	var from=source(r,shot);var damage: float=shot.damage;var blocked=false
	var point: Vector2=r.Soldiers.ground_position(r,target,slot)
	if not from.is_empty():
		var delta: Vector2=from.point-point
		var actor: Dictionary=target.soldiers[slot]
		var normal: Vector2=actor.get('wall_heading',actor.get('heading',target.heading))
		if r.shield_active(target,slot) and delta.length()>.1 and delta.normalized().dot(normal)>.34:
			blocked=true
			damage*=1.-(r.config.battle_commands.shield_ranged_reduction if from.registered and r.Soldiers.ranged(from.unit) else r.config.battle_commands.shield_melee_reduction)
		elif not r.square_battle and target.kind in ['legion','guard'] and r.soldier_holding(target,slot) and r.soldier_sector(from.point,target,slot)=='front':damage*=r.config.directional_combat.shield_front
	var dealt: float=r.hurt(target,damage,kind,0.,slot,from.unit.id if not from.is_empty() else -1,from.slot if not from.is_empty() else -1)
	if dealt>0:
		var axis: Vector2=point-shot.get('origin',shot.from)
		r.Contact.light_hit(r,target,r.ground_basis.basis_xform(point-target.pos),r.ground_basis.basis_xform(axis).normalized(),slot)
		if kind=='archer':r.events.append({'kind':'arrow_impact','pos':point,'blocked':blocked,'damage':dealt,'target':target.id,'target_slot':slot})
	return dealt

static func advance(r,shot: Dictionary,previous: float,dt: float):
	var target={};var slot: int=shot.get('target_slot',-1)
	for u in r.units:
		if u.id==shot.target:target=u;break
	if target.is_empty() or target.hp<=0 or target.get('escaped',false) or slot<0 or slot>=target.soldiers.size() or target.soldiers[slot].hp<=0:
		shot.done=true;return
	shot.pos=r.Soldiers.ground_position(r,target,slot)
	shot.offset=r.ground_basis.basis_xform(shot.pos-target.pos)
	var delay: float=shot.get('release_delay',0.)
	if previous<delay and shot.age>=delay:r.events.append({'kind':'arrow','volley':true,'pos':shot.aim_center,'landing':shot.pos,'from':shot.from,'attacker':shot.attacker,'target':shot.target})
	var movement=maxf(0.,shot.age-delay)-maxf(0.,previous-delay)
	if movement<=0:return
	var delta: Vector2=shot.pos-shot.point
	if delta.length()>.01:shot.direction=delta.normalized()
	var distance: float=shot.speed*movement
	if delta.length()<=distance:
		shot.point=shot.pos;impact(r,shot,target,slot,'archer');shot.done=true
	else:shot.point+=delta.normalized()*distance
