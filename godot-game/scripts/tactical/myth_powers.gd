extends RefCounted
## Transient trial-only skill state. All tunable values live in myth_skills.json.
var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://data/balance/myth_skills.json'))
var bounds: Rect2
var pending: Array=[]
var charges: Array=[]
var zones: Array=[]
var decoys: Array=[]

func area(id: String, pos: Vector2) -> Dictionary:
	var c: Dictionary=config[id]
	if id in ['achilles','minotaur']:
		var origin=Vector2(clampf(pos.x-c.length/2,bounds.position.x,bounds.end.x-c.length),clampf(pos.y,bounds.position.y+c.width/2,bounds.end.y-c.width/2))
		return {'shape':'lane','origin':origin,'length':c.length,'width':c.width}
	if id=='medusa':
		return {'shape':'cone','origin':Vector2(clampf(pos.x-c.origin_offset,bounds.position.x,bounds.end.x-c.range),clampf(pos.y,bounds.position.y,bounds.end.y)), 'radius':c.range,'angle':c.half_angle}
	return {'shape':'circle','origin':pos,'radius':c.radius}

func contains(a: Dictionary, pos: Vector2) -> bool:
	var local: Vector2=pos-a.origin
	match a.shape:
		'lane':return local.x>=0 and local.x<=a.length and absf(local.y)<=a.width/2
		'cone':return local.length()<=a.radius and (local.length()<.001 or local.normalized().x>=cos(a.angle))
	return local.length()<=a.radius

func cast(id: String, pos: Vector2):
	pending.append({'character':id,'pos':pos,'age':0.0})

func hit(r, u: Dictionary, c: Dictionary, origin: Vector2, direction: Vector2=Vector2.ZERO):
	r.hurt(u,float(c.get('damage',0)))
	u.stun=maxf(u.stun,float(c.get('stun',0)))
	var force: float=c.get('push',0)
	if force>0:
		if direction==Vector2.ZERO:direction=origin.direction_to(u.pos)
		if direction==Vector2.ZERO:direction=Vector2.RIGHT
		u.push=(u.push+direction*force).limit_length(240)

func resolve(r, cast_data: Dictionary):
	var id: String=cast_data.character
	var c: Dictionary=config[id]
	var pos: Vector2=cast_data.pos
	var a=area(id,pos)
	var enemies=r.alive('enemy').filter(func(u):return contains(a,u.pos))
	match id:
		'athena':
			for u in r.alive('ally'):
				if contains(a,u.pos):u.shield=c.duration
		'artemis':
			for u in r.units:u.marked=0.0
			if not enemies.is_empty():
				enemies.sort_custom(func(u,v):return u.max_hp>v.max_hp if u.max_hp!=v.max_hp else u.id<v.id)
				var target: Dictionary=enemies[0]
				target.marked=c.duration
				for u in r.alive('ally'):
					if u.kind=='archer' and u.pos.distance_to(target.pos)<=c.rally_radius:u.cooldown=0.0
		'hephaestus':
			# One fire field at a time: unlimited casting relocates it instead of multiplying DPS.
			zones.clear()
			zones.append({'pos':pos,'remaining':c.duration,'age':0.0})
			for u in enemies:hit(r,u,c,pos)
		'demeter':
			for u in enemies:u.rooted=c.duration
		'achilles','minotaur':
			charges.append({'character':id,'area':a,'age':0.0,'hit':[]})
		'odysseus':
			decoys.clear()
			for i in int(c.count):
				var place=(pos+Vector2(0,(i-(c.count-1)/2)*c.spacing)).clamp(bounds.position,bounds.end)
				decoys.append({'id':-1-i,'kind':'decoy','side':'ally','pos':place,'hp':float(c.hp),'max_hp':float(c.hp),'remaining':float(c.duration),'hit_age':10.0})
		'medusa':
			for u in enemies:u.petrified=c.duration
		'hydra':
			# A castable power has no permanent Hydra body; regeneration supports nearby living allies.
			enemies.sort_custom(func(u,v):return u.pos.distance_squared_to(pos)<v.pos.distance_squared_to(pos))
			for i in mini(enemies.size(),int(c.max_targets)):
				var u: Dictionary=enemies[i]
				hit(r,u,c,pos)
				u.poison=c.duration
			for u in r.alive('ally'):
				if u.pos.distance_to(pos)<=c.regen_radius:u.regen=c.duration
		'heracles','cyclops','harpy':
			for u in enemies:hit(r,u,c,pos)
	r.events.append({'kind':'power_contact','power':id,'pos':pos})

func advance(r, dt: float):
	for u in r.units:
		if u.hp<=0:continue
		if u.poison>0:r.hurt(u,float(config.hydra.dps)*minf(dt,u.poison))
		if u.hp>0 and u.regen>0:u.hp=minf(u.max_hp,u.hp+float(config.hydra.regen_per_second)*minf(dt,u.regen))
		for status in ['shield','rooted','petrified','marked','poison','regen']:u[status]=maxf(0,u[status]-dt)
	for d in decoys:
		d.remaining-=dt
		d.hit_age+=dt
	decoys=decoys.filter(func(d):return d.remaining>0 and d.hp>0)
	for zone in zones:
		var c: Dictionary=config.hephaestus
		var active=minf(dt,zone.remaining)
		for u in r.alive('enemy'):
			if u.pos.distance_to(zone.pos)<=c.radius:r.hurt(u,float(c.dps)*active)
		zone.remaining-=dt
		zone.age+=dt
	zones=zones.filter(func(z):return z.remaining>0)
	for charge in charges:
		var c: Dictionary=config[charge.character]
		charge.age+=dt
		var reach=minf(1,charge.age/float(c.travel_seconds))*float(c.length)
		for u in r.alive('enemy'):
			if u.id not in charge.hit and contains(charge.area,u.pos) and u.pos.x-charge.area.origin.x<=reach:
				if charge.hit.is_empty():r.events.append({'kind':'power_impact','power':charge.character,'pos':u.pos})
				charge.hit.append(u.id)
				hit(r,u,c,charge.area.origin,Vector2.RIGHT)
	charges=charges.filter(func(c):return c.age<float(config[c.character].travel_seconds))
	# Resolve after ticking existing states so a newly applied duration is not spent immediately.
	var ready: Array=[]
	for p in pending:
		p.age+=dt
		if p.age+0.000001>=float(config[p.character].windup):ready.append(p)
	for p in ready:
		pending.erase(p)
		resolve(r,p)

func speed_multiplier(u: Dictionary) -> float:
	if u.side!='enemy':return 1.0
	for zone in zones:
		if u.pos.distance_to(zone.pos)<=config.hephaestus.radius:return config.hephaestus.slow
	return 1.0

func select_target(r, u: Dictionary) -> Dictionary:
	var candidates: Array=r.alive('enemy' if u.side=='ally' else 'ally')
	if u.side=='enemy':
		for d in decoys:
			if d.hp>0 and d.remaining>0 and d.pos.distance_to(u.pos)<=config.odysseus.radius:candidates.append(d)
	var target: Dictionary={}
	var best=INF
	for candidate in candidates:
		var distance: float=u.pos.distance_to(candidate.pos)
		if u.get('order','auto')=='hold' and distance>r.attack_reach(u,candidate):continue
		var score=distance
		if u.kind=='cavalry' and candidate.kind=='archer':score*=.65
		if candidate.kind=='decoy':score-=10000
		if u.side=='ally' and u.kind=='archer' and candidate.get('marked',0)>0 and distance<=config.artemis.rally_radius:score-=10000
		if score<best:
			best=score
			target=candidate
	return target

func clear(r):
	pending.clear()
	charges.clear()
	zones.clear()
	decoys.clear()
	for u in r.units:
		for status in ['shield','rooted','petrified','marked','poison','regen']:u[status]=0.0
