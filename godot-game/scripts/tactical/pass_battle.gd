extends "res://scripts/tactical/trial_rules.gd"
## Shared battle rules for manual deployment and all formation presets.
var barrels: Array=[]
var routed={'ally':0,'enemy':0}

func _init():
	super()
	terrain=preload('res://scripts/tactical/pass_terrain.gd').new(projection,bounds,config.types)
	enemy_wait=0
	for p in [Vector2(1130,513),Vector2(1170,910)]:
		barrels.append({'pos':p,'state':'ready','age':0.0,'from':Vector2.ZERO})

func deploy_defenders() -> bool:
	if phase!='deploy' or not alive('ally').is_empty():return false
	combined_arms=false
	units.clear()
	next_id=0
	deployment=Rect2(320,300,780,1000)
	var front=['guard','legion','spear','legion']
	for i in front.size():deploy(front[i],Vector2(920,405+207*i))
	for i in 2:deploy('archer',Vector2(673,550+355*i))
	deploy('cavalry',Vector2(575,1180))
	for i in 5:spawn('legion','enemy',Vector2(1840,395+184*i))
	for i in 2:spawn('archer','enemy',Vector2(2090,540+420*i))
	spawn('cavalry','enemy',Vector2(1980,1210))
	for u in alive('ally'):u.order='hold'
	return true

func spawn(kind: String,side: String,pos: Vector2):
	super(kind,side,pos)
	var u: Dictionary=units.back()
	u.morale=100.0
	u.routing=false
	u.escaped=false
	u.general=kind=='legion' and not units.any(func(other):return other.id!=u.id and other.side==side and other.general)

func alive(side: String) -> Array:
	return units.filter(func(u):return u.side==side and u.hp>0 and not u.routing)

func hurt(u: Dictionary, damage: float, source_kind: String='') -> float:
	var dealt=super(u,damage,source_kind)
	if dealt>0 and u.has('morale') and not u.routing:
		u.morale-=dealt/u.max_hp*(106 if u.general else 125)
		if u.hp<=0 or u.morale<=0:
			u.routing=true
			if u.hp>0:routed[u.side]+=1
			if u.general:
				for other in alive(u.side):
					other.morale=maxf(1,other.morale-18)
	return dealt

func deal_blow(attacker: Dictionary,target: Dictionary,damage: float):
	# A mounted blow from behind an engaged line increases the shock.
	if target.kind=='decoy':
		super.deal_blow(attacker,target,damage)
		return
	var rear=(attacker.pos.x-target.pos.x)*target.facing < -30
	if not rear and target.order=='hold' and target.kind=='legion':damage*=.72
	if rear and attacker.kind=='cavalry':
		damage*=1.4
		target.morale-=5
	hurt(target,damage,attacker.kind)

func barrel_at(pos: Vector2) -> Dictionary:
	for b in barrels:
		var local=ground_basis.basis_xform(pos-b.pos)
		if b.state=='ready' and Rect2(-24,-34,49,50).has_point(local):return b
	return {}

func move_oil(index: int,pos: Vector2) -> bool:
	if phase!='deploy' or index<0 or index>=barrels.size():return false
	if not Rect2(980,325,380,900).has_point(pos):return false
	for other in barrels:
		if other!=barrels[index] and other.pos.distance_to(pos)<115:return false
	barrels[index].pos=pos
	return true

func ignite(b: Dictionary) -> bool:
	if phase!='battle' or b.is_empty() or b.state!='ready':return false
	for archer in alive('ally'):
		if archer.kind=='archer' and archer.pos.distance_to(b.pos)<=640:
			b.state='arrow'
			b.age=0
			b.from=archer.pos
			archer.attack_age=0
			archer.heading=archer.pos.direction_to(b.pos)
			events.append({'kind':'arrow','pos':b.pos,'from':archer.pos})
			return true
	return false

func step(dt: float):
	if phase!='battle':return
	for b in barrels:
		b.age+=dt
		if b.state=='arrow' and b.age>=.4:
			b.state='burn'
			b.age=0
			events.append({'kind':'charge','pos':b.pos})
			for u in units:
				if u.hp>0 and not u.routing and u.pos.distance_to(b.pos)<=161:
					hurt(u,285)
					u.stun=maxf(u.stun,.8)
		elif b.state=='burn':
			if b.age>=4:b.state='ash'
			else:
				for u in units:
					if u.hp>0 and not u.routing and u.pos.distance_to(b.pos)<=161:hurt(u,60*dt)
	for u in units:
		if u.routing and u.hp>0 and not u.escaped:
			var sign_x=-1 if u.side=='ally' else 1
			u.facing=sign_x
			u.heading=Vector2(sign_x,0)
			var distance=float(config.types[u.kind].speed)*1.35*dt
			var exit_point=Vector2(bounds.position.x+1 if sign_x<0 else bounds.end.x-1,u.pos.y)
			var retreat=travel_target(u,exit_point)
			var next: Vector2=u.pos.move_toward(retreat,distance)
			if u.pos.distance_to(exit_point)<2:next=u.pos+Vector2(sign_x*distance,0)
			if not may_advance(u,next,false):continue
			u.pos=next
			u.march_distance+=distance
			u.moving=true
			u.attack_age=10
			if not bounds.has_point(u.pos):u.escaped=true
	super(dt)
	if phase=='timeout' and not alive('ally').is_empty():phase='victory'

func strength(side: String) -> float:
	var value=0.0
	for u in alive(side):value+=u.hp/u.max_hp*float(config.types[u.kind].soldiers)
	return value
