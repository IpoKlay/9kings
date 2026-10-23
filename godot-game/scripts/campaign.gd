extends RefCounted
## Native rules port of dist/engine.js. Coordinates and fixed-step order are preserved.
var rules = JSON.parse_string(FileAccess.get_file_as_string('res://data/rules.json'))
var types: Dictionary
var cards: Dictionary
var enemies: Dictionary
var g: Dictionary

func _init(seed_value: int = -1):
	types = rules.types
	cards = rules.cards
	enemies = rules.enemies
	reset(seed_value)

func reset(seed_value: int = -1):
	g = {'round':1, 'defense':3, 'phase':'reward', 'buildings':[
		{'id':1,'type':'legion','cell':0,'level':1}, {'id':2,'type':'archer','cell':2,'level':1},
		{'id':3,'type':'siege','cell':8,'level':1}], 'nextId':4,
		'boosts':{'legion':0,'archer':0,'siege':0}, 'upgrades':{}, 'orders':{},
		'rng':(randi() if seed_value < 0 else seed_value) & 0xffffffff, 'offered':[], 'offerYear':0,
		'armyShield':false,'armyTestudo':false,'pending':null,'chosen':null,'history':[],'battle':null}

func encounter(year: int) -> Dictionary:
	var y = maxi(1, year)
	var count = mini(20, 3 + int(maxi(0,y-2)/2.0))
	var roster: Array = []
	roster.resize(count)
	roster.fill('enemy')
	if y >= 4: roster[count-1] = 'archer'
	if y >= 6: roster[0] = 'guard'
	if y >= 8: roster[1] = 'cavalry'
	if y >= 10: roster[count-2] = 'siege'
	for i in range(3,count-2):
		if i%4 == 3: roster[i] = ['archer','guard','cavalry'][y%3]
	var wave_name = 'Early patrol'
	if y >= 4: wave_name = 'Skirmish line'
	if y >= 6: wave_name = 'Shield advance'
	if y >= 8: wave_name = 'Flanking riders'
	if y >= 10: wave_name = 'Siege host'
	return {'year':y,'roster':roster,'health':1+.025*(y-1)+.012*maxi(0,y-8),
		'attack':1+.018*(y-1)+.008*maxi(0,y-8),'name':wave_name}

func rank(id: String) -> int:
	return int(g.upgrades.get(id,0))

func adjacent(a: int,b: int) -> bool:
	return absi(a%4-b%4)+absi(int(a/4.0)-int(b/4.0)) == 1

func bonus(b: Dictionary) -> float:
	var value = 0.0
	for t in g.buildings:
		if t.type == 'training' and adjacent(int(t.cell),int(b.cell)): value = maxf(value,t.level*.25)
	return value

func stats(b: Dictionary) -> Dictionary:
	if b.type == 'training': return {'bonus':b.level*.25}
	var t = types[b.type]
	var m = 1+(b.level-1)*.5
	var diversity = {}
	for v in g.buildings:
		if v.type != 'training': diversity[v.type] = true
	return {'hp':t.hp*m,'attack':t.attack*m*(1+g.boosts.get(b.type,0)*.25+bonus(b)+rank('combinedArms')*mini(7,diversity.size())*.05+(.25 if g.orders.get('rally',false) else 0)),
		'heal':t.get('heal',0)*m*(1+rank('fieldMedicine')*.5),'range':t.range,'speed':t.speed,
		'interval':t.interval/(1.4 if g.orders.get('volley',false) and b.type in ['archer','siege'] else 1.0)}

func has_type(type: String) -> bool:
	for b in g.buildings:
		if b.type == type: return true
	return false

func available(id: String) -> bool:
	if not cards.has(id): return false
	var c = cards[id]
	if types.has(id):
		if g.buildings.size() < 12: return true
		for b in g.buildings:
			if b.type == id and b.level < 3: return true
		return false
	if c.has('max') and rank(id) >= c.max: return false
	for type in c.get('requires',[]):
		if not has_type(type): return false
	if c.has('needs') and rank(c.needs) == 0: return false
	return true

func random_value() -> float:
	g.rng = (int(g.rng)*1664525+1013904223) & 0xffffffff
	return float(g.rng)/4294967296.0

func offers() -> Array:
	if g.offerYear == g.round: return g.offered.duplicate()
	var fresh: Array = []
	var repeated: Array = []
	for id in cards:
		if available(id):
			if id in g.offered: repeated.append(id)
			else: fresh.append(id)
	var out: Array = []
	while out.size() < 3:
		var bag = fresh if not fresh.is_empty() else repeated
		if bag.is_empty(): break
		var i = int(floor(random_value()*bag.size()))
		out.append(bag[i])
		bag.remove_at(i)
	g.offered = out
	g.offerYear = g.round
	return out.duplicate()

func choose(id: String) -> bool:
	if g.phase != 'reward' or id not in offers() or not available(id): return false
	g.chosen = id
	if types.has(id):
		g.pending = id
		g.phase = 'place'
	else:
		if cards[id].kind == 'Battle order':
			g.orders[id] = true
			if id == 'shield': g.armyShield = true
			if id == 'testudo': g.armyTestudo = true
		else:
			g.upgrades[id] = rank(id)+1
			if id.ends_with('Train'): g.boosts[id.trim_suffix('Train')] = rank(id)
		g.phase = 'prepare'
	return true

func skip() -> bool:
	if g.phase not in ['reward','place']: return false
	g.pending = null
	g.chosen = null
	g.phase = 'prepare'
	return true

func building_at(cell: int):
	for b in g.buildings:
		if b.cell == cell: return b
	return null

func place(cell: int) -> bool:
	if g.phase != 'place' or cell < 0 or cell >= 12: return false
	var b = building_at(cell)
	if b != null:
		if b.type != g.pending or b.level >= 3: return false
		b.level += 1
	else:
		g.buildings.append({'id':g.nextId,'type':g.pending,'cell':cell,'level':1})
		g.nextId += 1
	g.pending = null
	g.phase = 'prepare'
	return true

func muster() -> Array:
	var units: Array = []
	var base = 40.0
	for role in ['rear','middle','front']:
		var group: Array = []
		for b in g.buildings:
			if types[b.type].get('role','') == role: group.append(b)
		group.sort_custom(func(a,b):return a.id < b.id)
		for i in group.size():
			var b = group[i]
			var s = stats(b)
			var col = int(i/4.0)
			var count = mini(4,group.size()-col*4)
			var shield = (40 if g.armyShield else 0)+(rank('shieldDrill')*20 if role == 'front' else 0)+(30 if b.type == 'guard' else 0)
			units.append({'id':units.size(),'buildingId':b.id,'side':'ally','type':b.type,'x':base+col*75,
				'y':(i%4-(count-1)/2.0)*120,'hp':s.hp,'maxHp':s.hp,'attack':s.attack,'heal':s.heal,
				'range':s.range,'speed':s.speed*(.75 if g.armyTestudo and b.type == 'legion' else 1),
				'testudo':g.armyTestudo and b.type == 'legion','interval':s.interval,'shield':float(shield),
				'maxShield':float(shield),'cooldown':.3+col*.1,'moving':false,'flash':0.0,'charged':false})
		base += maxi(1,int(ceil(group.size()/4.0)))*75+75
	var wave = encounter(int(g.round))
	for role in ['front','middle','rear']:
		var group: Array = []
		for type in wave.roster:
			if enemies[type].role == role: group.append(type)
		for i in group.size():
			var type = group[i]
			var t = enemies[type]
			var col = int(i/5.0)
			var count = mini(5,group.size()-col*5)
			var hp = t.hp*wave.health
			var shield = t.get('shield',0)*wave.health
			units.append({'id':units.size(),'side':'enemy','type':type,'x':{'front':820,'middle':950,'rear':1035}[role]+col*55.0,
				'y':(i%5-(count-1)/2.0)*105,'hp':hp,'maxHp':hp,'attack':t.attack*wave.attack,'range':t.range,
				'speed':t.speed,'interval':t.interval,'shield':shield,'maxShield':shield,'cooldown':.4+col*.1,
				'moving':false,'flash':0.0,'charged':false})
	return units

func start() -> bool:
	if g.phase != 'prepare': return false
	var units = muster()
	g.battle = {'time':0.0,'units':units,'projectiles':[],'events':[],'serial':0,'report':null,
		'initialAllies':units.filter(func(u):return u.side=='ally').size(),
		'initialEnemies':units.filter(func(u):return u.side=='enemy').size()}
	g.phase = 'battle'
	return true

func distance(a: Dictionary,b: Dictionary) -> float:
	# Use double precision arithmetic, matching the JS simulation rather than Vector2's float32.
	return hypot(a.x-b.x,a.y-b.y)

func hypot(x: float,y: float) -> float:
	var largest = maxf(absf(x),absf(y))
	if largest == 0: return 0.0
	x = absf(x)/largest
	y = absf(y)/largest
	return sqrt(x*x+y*y)*largest

func ranged_bonus(target: Dictionary,siege: bool,alive: Array) -> float:
	var amount = 1.0
	if target.get('slowUntil',0) > g.battle.time: amount += rank('pinning')*.3
	if siege and target.get('burnUntil',0) > g.battle.time: amount += rank('oilShots')*.5
	if not siege:
		for v in alive:
			if v.side == 'ally' and types.get(v.type,{}).get('role','') == 'front' and distance(v,target) <= v.range+10:
				amount += rank('crossfire')*.25
				break
	return amount

func hurt(damage: Dictionary,id: int,amount: float):
	damage[id] = damage.get(id,0.0)+amount

func step(delta: float):
	if g.phase != 'battle' or delta <= 0: return
	var dt = minf(delta,.1)
	var b = g.battle
	b.time += dt
	b.events = []
	var alive = b.units.filter(func(u):return u.hp>0)
	var damage = {}
	for u in alive:
		if u.get('burnUntil',0) > b.time: hurt(damage,int(u.id),3*dt)
	for p in b.projectiles:
		p.life -= dt
		if p.life > 0: continue
		if p.siege:
			for v in alive:
				if v.side == p.side: continue
				var d = distance(v,{'x':p.to,'y':p.toY})
				if d < 125: hurt(damage,int(v.id),p.damage*(1-.5*d/125)*(ranged_bonus(v,true,alive) if p.side=='ally' else 1))
			b.events.append({'kind':'blast','x':p.to,'y':p.toY,'side':p.side})
		else:
			for t in alive:
				if t.id != p.target: continue
				hurt(damage,int(t.id),p.damage*(ranged_bonus(t,false,alive) if p.side=='ally' else 1))
				if p.fire: t.burnUntil = b.time+3
				break
	b.projectiles = b.projectiles.filter(func(p):return p.life>0)
	var moves: Array = []
	for u in alive:
		u.moving = false
		u.flash = maxf(0,u.flash-dt)
		u.cooldown -= dt
		var healer = u.type == 'medic'
		var target = null
		for v in alive:
			if healer:
				if v.side != u.side or v.hp >= v.maxHp: continue
			else:
				if v.side == u.side: continue
			if target == null:
				target = v
				continue
			var d = distance(v,u)
			var td = distance(target,u)
			if healer:
				if v.hp/v.maxHp < target.hp/target.maxHp or (v.hp/v.maxHp == target.hp/target.maxHp and d < td): target = v
			elif d < td or (d == td and v.id < target.id): target = v
		if target == null: continue
		u.targetId = target.id
		var d = distance(u,target)
		var ranged = u.type in ['archer','siege']
		if d > u.range:
			var move = minf(u.speed*(.75 if u.get('slowUntil',0)>b.time else 1)*dt,d-u.range)
			moves.append({'u':u,'x':u.x+(target.x-u.x)/d*move,'y':u.y+(target.y-u.y)/d*move})
			u.moving = true
		elif u.cooldown <= 0:
			u.cooldown = u.interval/(1.3 if u.get('hasteUntil',0)>b.time else 1)
			if healer:
				var healed = minf(u.get('heal',12),target.maxHp-target.hp)
				target.hp += healed
				target.healUntil = b.time+.45
				b.events.append({'kind':'heal','id':target.id,'x':target.x,'y':target.y,'amount':healed,'side':u.side})
				continue
			b.events.append({'kind':'attack','id':u.id,'target':target.id,'x':u.x,'y':u.y,'ranged':ranged,'siege':u.type=='siege','side':u.side})
			if ranged:
				b.serial += 1
				var duration = .7 if u.type=='siege' else .24
				b.projectiles.append({'id':b.serial,'attacker':u.id,'target':target.id,'from':u.x,'fromY':u.y,
					'to':target.x,'toY':target.y,'life':duration,'duration':duration,'siege':u.type=='siege',
					'side':u.side,'damage':u.attack,'fire':u.side=='ally' and u.type=='archer' and rank('fireArrows')>0})
			else:
				var charge = 1.0
				if u.type=='cavalry' and not u.charged: charge = 1.6+(rank('charge')*.6 if u.side=='ally' else 0)
				hurt(damage,int(target.id),u.attack*charge)
				if u.type=='cavalry': u.charged = true
				if u.type=='spear': target.slowUntil = b.time+2
	for m in moves:
		m.u.x = m.x
		m.u.y = m.y
	for i in alive.size():
		for j in range(i+1,alive.size()):
			var a = alive[i]
			var v = alive[j]
			if a.side != v.side: continue
			var dx = a.x-v.x
			var dy = a.y-v.y
			var d = hypot(dx,dy)
			if d >= 75: continue
			if d < .01:
				dy = -1.0 if a.id<v.id else 1.0
				dx = 0.0
				d = 1.0
			var push = minf((75-d)*.5,24*dt)
			a.x += dx/d*push
			a.y += dy/d*push
			v.x -= dx/d*push
			v.y -= dy/d*push
	for u in alive:
		u.x = clampf(u.x,0,1050)
		u.y = clampf(u.y,-290,290)
	for id in damage:
		var u = b.units[id]
		var amount = damage[id]*(.6 if u.get('testudo',false) else 1)
		var absorbed = minf(u.shield,amount)
		var before = u.hp
		u.shield -= absorbed
		u.hp = maxf(0,u.hp-amount+absorbed)
		u.flash = .13
		if amount > .5: b.events.append({'kind':'hit','id':id,'x':u.x,'y':u.y,'side':u.side,'damage':before-u.hp,'absorbed':absorbed,'broken':absorbed>0 and u.shield==0})
		if u.hp == 0:
			b.events.append({'kind':'death','id':id,'x':u.x,'y':u.y,'side':u.side})
			if u.side=='enemy' and rank('warhorn')>0:
				for ally in alive:
					if ally.side=='ally' and distance(ally,u)<=240: ally.hasteUntil=b.time+3
	var has_enemies = b.units.any(func(u):return u.side=='enemy' and u.hp>0)
	var has_allies = b.units.any(func(u):return u.side=='ally' and u.hp>0)
	if not has_enemies and not b.projectiles.any(func(p):return p.side=='enemy'): finish(true)
	elif (not has_allies and not b.projectiles.any(func(p):return p.side=='ally')) or b.time>=75: finish(false)

func finish(won: bool):
	var b = g.battle
	if b.report != null: return
	var surviving = b.units.filter(func(u):return u.hp>0 and u.side=='ally').size()
	var remaining = b.units.filter(func(u):return u.hp>0 and u.side=='enemy').size()
	var loss = 0 if won else 1
	g.defense = maxi(0,g.defense-loss)
	b.report = {'won':won,'surviving':surviving,'deployed':b.initialAllies,'enemyLosses':b.initialEnemies-remaining,'enemyCount':b.initialEnemies,'defenseLost':loss}
	g.history.append({'round':g.round,'defense':g.defense,'report':b.report.duplicate(),'card':g.chosen,'duration':b.time})
	if g.history.size()>100: g.history.pop_front()
	g.phase = 'defeat' if g.defense<=0 else 'result'
	if loss: b.events.append({'kind':'breach','x':60,'y':0,'damage':loss})

func next_year() -> bool:
	if g.phase != 'result': return false
	g.round += 1
	g.phase = 'reward'
	g.pending = null
	g.chosen = null
	g.armyShield = false
	g.armyTestudo = false
	g.orders = {}
	g.battle = null
	return true

func synergies() -> Array:
	var melee = has_type('legion') or has_type('guard') or has_type('spear') or has_type('cavalry')
	return [
		{'name':'Burn & Bombard','active':rank('fireArrows')>0 and rank('oilShots')>0 and has_type('archer') and has_type('siege'),'text':'Fire Arrows → Pitch Stones: +50% siege damage.'},
		{'name':'Pin & Pierce','active':has_type('spear') and rank('pinning')>0 and (has_type('archer') or has_type('siege')),'text':'Spears slow → ranged attacks deal +30% damage.'},
		{'name':'Shield & Mend','active':has_type('medic') and (has_type('guard') or rank('shieldDrill')>0),'text':'Frontline shields absorb hits while medics restore health.'},
		{'name':'Charge & Glory','active':has_type('cavalry') and rank('warhorn')>0,'text':'Cavalry strikes → enemy defeats grant nearby attack haste.'},
		{'name':'Hold & Crossfire','active':rank('crossfire')>0 and has_type('archer') and melee,'text':'Melee engagement → archers deal +25% damage per rank.'}]
