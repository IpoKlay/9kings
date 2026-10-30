extends RefCounted
## Native simulation. All authored values are read-only catalog data.
const Catalog=preload('res://scripts/data/catalog.gd')
const Formation=preload('res://scripts/formation.gd')
var rules=Catalog.rules()
var camp: Dictionary=Catalog.data('balance/camp')
var effects: Dictionary=Catalog.data('balance/effects')
var combat: Dictionary=Catalog.data('balance/combat')
var legacy: Dictionary=Catalog.data('balance/legacy_encounters')
var contracts: Dictionary=Catalog.data('schema/contracts')
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
	g=Catalog.new_state('campaign')
	# JSON numbers are floats; tile membership must use the same integer IDs as input.
	g.unlocked_cells=g.unlocked_cells.map(func(cell):return int(cell))
	g.rng=(randi() if seed_value<0 else seed_value) & int(contracts.random_mask)

func encounter(year: int) -> Dictionary:
	var y = maxi(int(legacy.minimum_year), year)
	var count = mini(int(legacy.max_count), int(legacy.base_count) + int(maxi(0,y-int(legacy.count_growth_start))/float(legacy.count_growth_divisor)))
	var roster: Array = []
	roster.resize(count)
	roster.fill('enemy')
	if y >= legacy.unlock_years.archer: roster[count-1] = 'archer'
	if y >= legacy.unlock_years.guard: roster[0] = 'guard'
	if y >= legacy.unlock_years.cavalry: roster[1] = 'cavalry'
	if y >= legacy.unlock_years.siege: roster[count-2] = 'siege'
	for i in range(3,count-2):
		if i%4 == 3: roster[i] = legacy.rotating_roster[y%legacy.rotating_roster.size()]
	var wave_name = legacy.wave_names[0]
	if y >= legacy.unlock_years.archer: wave_name = legacy.wave_names[1]
	if y >= legacy.unlock_years.guard: wave_name = legacy.wave_names[2]
	if y >= legacy.unlock_years.cavalry: wave_name = legacy.wave_names[3]
	if y >= legacy.unlock_years.siege: wave_name = legacy.wave_names[4]
	return {'year':y,'roster':roster,'health':1+legacy.health_growth*(y-1)+legacy.health_late_growth*maxi(0,y-int(legacy.late_growth_start)),
		'attack':1+legacy.attack_growth*(y-1)+legacy.attack_late_growth*maxi(0,y-int(legacy.late_growth_start)),'name':wave_name}

func current_encounter() -> Dictionary:
	return g.get('expedition_wave',encounter(int(g.round)))

func rank(id: String) -> int:
	return int(g.upgrades.get(id,0))

func is_troop(id: String) -> bool:
	return cards.get(id,{}).get('kind','')=='Troop'

func order_rank(id: String) -> int:
	if g.get('temporary_orders',{}).has(id): return maxi(1,int(g.upgrades.get(id,0)) if g.orders.get(id,false) else 1)
	var active=g.orders.get(id,false) or (id=='shield' and g.armyShield) or (id=='testudo' and g.armyTestudo)
	return maxi(1,rank(id)) if active else 0

func offered_level(id: String) -> int:
	if g.reward_context=='recovery':return 1
	return 1 if types.has(id) else mini(3,rank(id)+1)

func card_copy(id: String,language: String,level: int=-1) -> Dictionary:
	var value=offered_level(id) if level<0 else clampi(level,1,3)
	var source=Catalog.data('localization/cards')[id]
	var copy=source.en.duplicate()
	if language=='zh': copy.merge(source.zh,true)
	var tokens={}
	var multiplied={
		'legionTrain':['training_pct'],'archerTrain':['training_pct'],'siegeTrain':['training_pct'],
		'shieldDrill':['shield_rank'],'crossfire':['crossfire_pct'],'fireArrows':['burn_damage'],
		'oilShots':['oil_pct'],'fieldMedicine':['healing_pct'],'warhorn':['haste_pct'],
		'combinedArms':['diversity_pct','diversity_max_pct'],'pinning':['pinning_pct'],
		'shield':['army_shield'],'rally':['rally_pct'],'volley':['volley_pct']}
	for key in multiplied.get(id,[]): tokens[key]=str(roundi(float(Catalog.binding_value(key))*value))
	if id=='charge': tokens.charge_upgraded_pct=str(roundi((effects.charge.base_multiplier+effects.charge.bonus_per_rank*value-1)*100))
	if id=='testudo': tokens.testudo_damage_pct=str(roundi((1-testudo_damage(value))*100))
	for key in copy:
		for token in tokens: copy[key]=copy[key].replace('{'+token+'}',tokens[token])
		copy[key]=Catalog.format_text(copy[key])
	return copy

func testudo_damage(level: int) -> float:
	return maxf(.4,float(effects.testudo.damage_multiplier)-.1*(maxi(1,level)-1))

func adjacent(a: int,b: int) -> bool:
	return absi(a%int(camp.columns)-b%int(camp.columns))+absi(int(a/float(camp.columns))-int(b/float(camp.columns))) == 1

func is_unlocked(cell: int) -> bool:
	return cell in g.unlocked_cells

func expansion_candidates() -> Array:
	var result=[]
	for cell in int(camp.max_buildings):
		if not is_unlocked(cell): result.append(cell)
	return result

func expand(cell: int) -> bool:
	if g.phase not in ['reward','prepare'] or g.battle!=null or g.expansion_credits<=0 or cell not in expansion_candidates(): return false
	g.unlocked_cells.append(cell)
	g.unlocked_cells.sort()
	g.expansion_credits-=1
	return true

func record_capture():
	g.cities_captured+=1
	if int(g.cities_captured)%int(camp.expansion_every_victories)==0:
		g.expansion_credits=mini(int(g.expansion_credits)+1,int(camp.max_buildings)-g.unlocked_cells.size())

func relocate(id: int, cell: int) -> bool:
	if g.phase not in ['reward','prepare'] or g.battle!=null or not is_unlocked(cell): return false
	var selected=g.buildings.filter(func(b):return b.id==id)
	if selected.is_empty(): return false
	var b=selected[0]
	var occupant=building_at(cell)
	if occupant!=null: occupant.cell=b.cell
	b.cell=cell
	return true

func site_bonuses(b: Dictionary, from_cell: int = -1) -> Dictionary:
	var result={'attack':0.0,'health':0.0}
	for support in g.buildings:
		if from_cell>=0 and support.cell==from_cell: continue
		var cell=from_cell if from_cell>=0 and support.cell==b.cell else int(support.cell)
		if not adjacent(cell,int(b.cell)): continue
		if support.type=='training' and types[b.type].get('attack',0)>0: result.attack=maxf(result.attack,support.level*camp.training_adjacency_per_level)
		if support.type=='medic' and is_troop(b.type): result.health=maxf(result.health,support.level*camp.medic_adjacency_health_per_level)
	return result

func bonus(b: Dictionary) -> float:
	return site_bonuses(b).attack

func stats(b: Dictionary) -> Dictionary:
	if b.type == 'training': return {'bonus':b.level*camp.training_adjacency_per_level}
	var t = types[b.type]
	var placement=site_bonuses(b)
	var m = float(Formation.count(b.type,int(b.level)))/Formation.count(b.type,1) if is_troop(b.type) else 1+(b.level-1)*camp.level_growth
	var diversity = {}
	for v in g.buildings:
		if v.type != 'training': diversity[v.type] = true
	return {'hp':t.hp*m*(1+placement.health),'attack':t.attack*m*(1+g.boosts.get(b.type,0)*camp.training_boost_per_rank+placement.attack+rank('combinedArms')*mini(int(effects.combinedArms.max_types),diversity.size())*effects.combinedArms.per_type_per_rank+effects.rally.attack_bonus*order_rank('rally')),
		'heal':t.get('heal',0)*m*(1+rank('fieldMedicine')*effects.fieldMedicine.heal_bonus_per_rank),'range':t.range,'speed':t.speed,
		'interval':t.interval/(1+(effects.volley.attack_rate_multiplier-1)*order_rank('volley') if b.type in ['archer','siege'] else 1.0)}

func has_type(type: String) -> bool:
	for b in g.buildings:
		if b.type == type: return true
	return false

func available(id: String) -> bool:
	if not cards.has(id): return false
	var c = cards[id]
	if c.get('retired',false): return false
	if types.has(id):
		if g.buildings.size() < g.unlocked_cells.size(): return true
		for b in g.buildings:
			if b.type == id and b.level < camp.max_building_level: return true
		return false
	if c.kind!='Battle order' and c.has('max') and rank(id) >= c.max: return false
	for type in c.get('requires',[]):
		if not has_type(type): return false
	if c.has('needs') and rank(c.needs) == 0: return false
	return true

func random_value() -> float:
	g.rng = (int(g.rng)*int(contracts.random_multiplier)+int(contracts.random_increment)) & int(contracts.random_mask)
	return float(g.rng)/float(contracts.random_divisor)

func offers() -> Array:
	if g.reward_context=='recovery': return g.offered.duplicate()
	if g.offerYear == g.round: return g.offered.duplicate()
	var fresh: Array = []
	var repeated: Array = []
	for id in cards:
		if available(id):
			if id in g.offered: repeated.append(id)
			else: fresh.append(id)
	var out: Array = []
	# The first rewards always offer recruitment, while keeping the other choices optional.
	if g.buildings.filter(func(b):return is_troop(b.type)).size()<int(camp.guaranteed_troop_until):
		var troops=fresh.filter(func(id):return is_troop(id))
		if troops.is_empty(): troops=repeated.filter(func(id):return is_troop(id))
		if not troops.is_empty():
			var id=troops[int(floor(random_value()*troops.size()))]
			out.append(id);fresh.erase(id);repeated.erase(id)
	while out.size() < camp.reward_choices:
		var bag = fresh if not fresh.is_empty() else repeated
		if bag.is_empty(): break
		var i = int(floor(random_value()*bag.size()))
		out.append(bag[i])
		bag.remove_at(i)
	if g.reward_context=='elite':
		var suitable=cards.keys().filter(func(id):return cards[id].kind=='Permanent' and available(id))
		if not suitable.is_empty() and not out.any(func(id):return id in suitable):
			out[-1]=suitable[int(floor(random_value()*suitable.size()))]
	g.offered = out
	g.offerYear = g.round
	return out.duplicate()

func choose(id: String) -> bool:
	if g.phase != 'reward' or id not in offers() or not available(id): return false
	g.chosen = id
	if g.reward_context=='recovery':
		g.temporary_orders[id]=true
		g.phase='prepare';g.reward_context='';g.reward_rerolls=0
		return true
	g.reward_rerolls=0
	if types.has(id):
		g.pending = id
		g.phase = 'place'
	else:
		if cards[id].kind == 'Battle order':
			g.upgrades[id] = mini(3,rank(id)+1)
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
	g.reward_context='';g.reward_rerolls=0
	g.phase = 'prepare'
	return true

func building_at(cell: int):
	for b in g.buildings:
		if b.cell == cell: return b
	return null

func place(cell: int) -> bool:
	if g.phase != 'place' or not is_unlocked(cell): return false
	var b = building_at(cell)
	if b != null:
		if b.type != g.pending or b.level >= camp.max_building_level: return false
		b.level += 1
	else:
		g.buildings.append({'id':g.nextId,'type':g.pending,'cell':cell,'level':1})
		g.nextId += 1
	g.pending = null
	g.phase = 'prepare'
	return true

func muster(wave_override: Dictionary = {}) -> Array:
	var units: Array = []
	var allies=g.buildings.filter(func(b):return types[b.type].has('role'))
	allies.sort_custom(func(a,b):return a.cell<b.cell)
	for b in allies:
		var s=stats(b)
		var role=types[b.type].role
		var col=int(b.cell)%int(camp.columns)
		var row=int(b.cell)/int(camp.columns)
		var shield=effects.shield.amount*order_rank('shield')+(rank('shieldDrill')*effects.shieldDrill.per_rank if role=='front' else 0)+(effects.guard.base_shield if b.type=='guard' else 0)
		var origin=Formation.battle_position(int(b.cell))
		var destination=Vector2(combat.ally_spawn.start_x+col*combat.deployment_column_spacing,(row-(camp.rows-1)*.5)*combat.deployment_row_spacing)
		units.append({'id':units.size(),'buildingId':b.id,'cell':b.cell,'level':int(b.level),'soldierCount':Formation.count(b.type,int(b.level)),
			'side':'ally','type':b.type,'x':origin.x,'y':origin.y,'deployFrom':origin,'deployTo':destination,'hp':s.hp,'maxHp':s.hp,'attack':s.attack,'heal':s.heal,
			'range':s.range,'speed':s.speed*(effects.testudo.speed_multiplier if order_rank('testudo')>0 and b.type=='legion' else 1),
			'testudo':order_rank('testudo')>0 and b.type=='legion','testudoRank':order_rank('testudo'),'interval':s.interval,'shield':float(shield),
			'maxShield':float(shield),'cooldown':combat.ally_spawn.cooldown+col*combat.ally_spawn.cooldown_per_column,'moving':false,'flash':0.0,'charged':false})
	var wave = current_encounter() if wave_override.is_empty() else wave_override
	for role in ['front','middle','rear']:
		var group: Array = []
		for type in wave.roster:
			if enemies[type].role == role: group.append(type)
		for i in group.size():
			var type = group[i]
			var t = enemies[type]
			var col = int(i/float(combat.enemy_spawn.rows))
			var count = mini(int(combat.enemy_spawn.rows),group.size()-col*int(combat.enemy_spawn.rows))
			var hp = t.hp*wave.health
			var shield = t.get('shield',0)*wave.health
			units.append({'id':units.size(),'side':'enemy','type':type,'x':combat.enemy_spawn.start_x[role]+col*combat.enemy_spawn.column_spacing,
				'y':(i%int(combat.enemy_spawn.rows)-(count-1)/2.0)*combat.enemy_spawn.row_spacing,'hp':hp,'maxHp':hp,'attack':t.attack*wave.attack,'range':t.range,
				'speed':t.speed,'interval':t.interval,'shield':shield,'maxShield':shield,'cooldown':combat.enemy_spawn.cooldown+col*combat.enemy_spawn.cooldown_per_column,
				'moving':false,'flash':0.0,'charged':false})
	return units

func start() -> bool:
	if g.phase != 'prepare': return false
	var units = muster()
	g.battle = {'time':0.0,'units':units,'projectiles':[],'events':[],'serial':0,'report':null,
		'deploy_elapsed':0.0,
		'initialAllies':units.filter(func(u):return u.side=='ally').size(),
		'initialEnemies':units.filter(func(u):return u.side=='enemy').size()}
	var waves = current_encounter().get('waves',[])
	if not waves.is_empty():
		g.battle.merge({'waves':waves.duplicate(true),'wave_index':0,'waves_cleared':0,
			'wave_time':0.0,'rest_remaining':0.0})
	g.phase = 'battle'
	return true

# A city is one battle/reward transaction. Units are rebuilt only at a wave boundary,
# preserving building identity and restoring ID == array index for projectile lookup.
func begin_next_wave():
	var b = g.battle
	var previous = {}
	for u in b.units:
		if u.side == 'ally': previous[u.buildingId] = u
	b.wave_index += 1
	var fresh = muster(b.waves[b.wave_index])
	for u in fresh:
		if u.side != 'ally': continue
		var old = previous[u.buildingId]
		# Surviving squads recover; routed squads receive partial camp reinforcements.
		u.hp = minf(u.maxHp,maxf(old.hp+u.maxHp*combat.survivor_heal_fraction,u.maxHp*combat.reinforcement_fraction)) if old.hp>0 else u.maxHp*combat.reinforcement_fraction
		u.shield = minf(u.maxShield,old.shield+u.maxShield*combat.shield_recovery_fraction)
		# The existing wave rest regroups reinforcements at the battle line.
		# Leaving the camp happens once per city, not again between its waves.
		u.x=u.deployTo.x;u.y=u.deployTo.y
		u.deployFrom=u.deployTo
	b.units = fresh
	b.initialEnemies += fresh.filter(func(u):return u.side=='enemy').size()
	b.projectiles.clear()
	b.wave_time = 0.0
	b.rest_remaining = 0.0
	b.deploy_elapsed=combat.deployment_seconds
	b.events.append({'kind':'wave_start','x':0,'y':0})

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
	if target.get('slowUntil',0) > g.battle.time: amount += rank('pinning')*effects.pinning.damage_bonus_per_rank
	if siege and target.get('burnUntil',0) > g.battle.time: amount += rank('oilShots')*effects.oilShots.damage_bonus_per_rank
	if not siege:
		for v in alive:
			if v.side == 'ally' and types.get(v.type,{}).get('role','') == 'front' and distance(v,target) <= v.range+effects.crossfire.engagement_margin:
				amount += rank('crossfire')*effects.crossfire.damage_bonus_per_rank
				break
	return amount

func hurt(damage: Dictionary,id: int,amount: float):
	damage[id] = damage.get(id,0.0)+amount

func step(delta: float):
	if g.phase != 'battle' or delta <= 0: return
	var dt = minf(delta,float(contracts.maximum_delta_seconds))
	var b = g.battle
	b.time += dt
	b.events = []
	if b.deploy_elapsed<combat.deployment_seconds and b.units.any(func(u):return u.side=='ally' and u.hp>0) and b.units.any(func(u):return u.side=='enemy' and u.hp>0):
		b.deploy_elapsed=minf(combat.deployment_seconds,b.deploy_elapsed+dt)
		var progress=b.deploy_elapsed/combat.deployment_seconds
		for u in b.units:
			if u.side!='ally' or u.hp<=0:continue
			var p: Vector2=u.deployFrom.lerp(u.deployTo,progress)
			u.x=p.x;u.y=p.y
			u.moving=progress<1 and u.deployFrom!=u.deployTo
		return
	if b.has('waves'):
		if b.rest_remaining>0:
			b.rest_remaining = maxf(0,b.rest_remaining-dt)
			if b.rest_remaining<=0: begin_next_wave()
			return
		b.wave_time += dt
	var alive = b.units.filter(func(u):return u.hp>0)
	var damage = {}
	for u in alive:
		if u.get('burnUntil',0) > b.time: hurt(damage,int(u.id),u.get('burnDamage',effects.burn.damage_per_second)*dt)
	for p in b.projectiles:
		p.life -= dt
		if p.life > 0: continue
		if p.siege:
			for v in alive:
				if v.side == p.side: continue
				var d = distance(v,{'x':p.to,'y':p.toY})
				if d < combat.blast_radius: hurt(damage,int(v.id),p.damage*(1-combat.blast_edge_falloff*d/combat.blast_radius)*(ranged_bonus(v,true,alive) if p.side=='ally' else 1))
			b.events.append({'kind':'blast','x':p.to,'y':p.toY,'side':p.side})
		else:
			for t in alive:
				if t.id != p.target: continue
				hurt(damage,int(t.id),p.damage*(ranged_bonus(t,false,alive) if p.side=='ally' else 1))
				if p.fire:
					t.burnUntil = b.time+effects.burn.duration
					t.burnDamage=p.get('burnDamage',effects.burn.damage_per_second)
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
			var move = minf(u.speed*(effects.slow.speed_multiplier if u.get('slowUntil',0)>b.time else 1)*dt,d-u.range)
			moves.append({'u':u,'x':u.x+(target.x-u.x)/d*move,'y':u.y+(target.y-u.y)/d*move})
			u.moving = true
		elif u.cooldown <= 0:
			u.cooldown = u.interval/(1+(effects.haste.attack_rate_multiplier-1)*maxi(1,rank('warhorn')) if u.get('hasteUntil',0)>b.time else 1)
			if healer:
				var healed = minf(u.get('heal',12),target.maxHp-target.hp)
				target.hp += healed
				target.healUntil = b.time+combat.heal_flash_seconds
				b.events.append({'kind':'heal','id':target.id,'x':target.x,'y':target.y,'amount':healed,'side':u.side})
				continue
			b.events.append({'kind':'attack','id':u.id,'target':target.id,'x':u.x,'y':u.y,'ranged':ranged,'siege':u.type=='siege','side':u.side})
			if ranged:
				b.serial += 1
				var duration = combat.siege_flight_seconds if u.type=='siege' else combat.arrow_flight_seconds
				b.projectiles.append({'id':b.serial,'attacker':u.id,'target':target.id,'from':u.x,'fromY':u.y,
					'to':target.x,'toY':target.y,'life':duration,'duration':duration,'siege':u.type=='siege',
					'side':u.side,'damage':u.attack,'fire':u.side=='ally' and u.type=='archer' and rank('fireArrows')>0,'burnDamage':effects.burn.damage_per_second*rank('fireArrows')})
			else:
				var charge = 1.0
				if u.type=='cavalry' and not u.charged: charge = effects.charge.base_multiplier+(rank('charge')*effects.charge.bonus_per_rank if u.side=='ally' else 0)
				hurt(damage,int(target.id),u.attack*charge)
				if u.type=='cavalry': u.charged = true
				if u.type=='spear': target.slowUntil = b.time+effects.slow.duration
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
			if d >= combat.separation_radius: continue
			if d < combat.separation_epsilon:
				dy = -1.0 if a.id<v.id else 1.0
				dx = 0.0
				d = 1.0
			var push = minf((combat.separation_radius-d)*combat.separation_fraction,combat.separation_speed*dt)
			a.x += dx/d*push
			a.y += dy/d*push
			v.x -= dx/d*push
			v.y -= dy/d*push
	for u in alive:
		u.x = clampf(u.x,combat.bounds_x[0],combat.bounds_x[1])
		u.y = clampf(u.y,combat.bounds_y[0],combat.bounds_y[1])
	for id in damage:
		var u = b.units[id]
		var amount = damage[id]*(testudo_damage(int(u.get('testudoRank',1))) if u.get('testudo',false) else 1)
		var absorbed = minf(u.shield,amount)
		var before = u.hp
		u.shield -= absorbed
		u.hp = maxf(0,u.hp-amount+absorbed)
		u.flash = combat.hit_flash_seconds
		if amount > combat.hit_event_threshold: b.events.append({'kind':'hit','id':id,'x':u.x,'y':u.y,'side':u.side,'damage':before-u.hp,'absorbed':absorbed,'broken':absorbed>0 and u.shield==0})
		if u.hp == 0:
			b.events.append({'kind':'death','id':id,'x':u.x,'y':u.y,'side':u.side})
			if u.side=='enemy' and rank('warhorn')>0:
				for ally in alive:
					if ally.side=='ally' and distance(ally,u)<=effects.haste.radius: ally.hasteUntil=b.time+effects.haste.duration
	var has_enemies = b.units.any(func(u):return u.side=='enemy' and u.hp>0)
	var has_allies = b.units.any(func(u):return u.side=='ally' and u.hp>0)
	if b.has('waves'):
		if not has_allies and not b.projectiles.any(func(p):return p.side=='ally'):
			finish(false)
		elif not has_enemies and not b.projectiles.any(func(p):return p.side=='enemy'):
			if not has_allies:
				finish(false)
			else:
				b.waves_cleared += 1
				if b.wave_index+1>=b.waves.size(): finish(true)
				else:
					b.rest_remaining = combat.wave_rest_seconds
					b.projectiles.clear()
					for u in b.units: u.moving = false
		elif b.wave_time>=combat.wave_timeout_seconds: finish(false)
	else:
		if not has_enemies and not b.projectiles.any(func(p):return p.side=='enemy'): finish(true)
		elif (not has_allies and not b.projectiles.any(func(p):return p.side=='ally')) or b.time>=combat.wave_timeout_seconds: finish(false)

func finish(won: bool):
	var b = g.battle
	if b.report != null: return
	var surviving = b.units.filter(func(u):return u.hp>0 and u.side=='ally').size()
	var remaining = b.units.filter(func(u):return u.hp>0 and u.side=='enemy').size()
	var loss = 0 if won else int(camp.loss_lives)
	g.defense = maxi(0,g.defense-loss)
	b.report = {'won':won,'surviving':surviving,'deployed':b.initialAllies,'enemyLosses':b.initialEnemies-remaining,'enemyCount':b.initialEnemies,'defenseLost':loss}
	if b.has('waves'):
		b.report.merge({'wavesCleared':b.waves_cleared,'waveCount':b.waves.size()})
	g.history.append({'round':g.round,'defense':g.defense,'report':b.report.duplicate(),'card':g.chosen,'duration':b.time})
	if g.history.size()>camp.history_limit: g.history.pop_front()
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
		{'name':'Burn & Bombard','active':rank('fireArrows')>0 and rank('oilShots')>0 and has_type('archer') and has_type('siege'),'text':Catalog.format_text('Fire Arrows → Pitch Stones: +{oil_pct}% siege damage.')},
		{'name':'Pin & Pierce','active':has_type('spear') and rank('pinning')>0 and (has_type('archer') or has_type('siege')),'text':Catalog.format_text('Spears slow → ranged attacks deal +{pinning_pct}% damage.')},
		{'name':'Shield & Mend','active':has_type('medic') and (has_type('guard') or rank('shieldDrill')>0),'text':'Frontline shields absorb hits while medics restore health.'},
		{'name':'Charge & Glory','active':has_type('cavalry') and rank('warhorn')>0,'text':'Cavalry strikes → enemy defeats grant nearby attack haste.'},
		{'name':'Hold & Crossfire','active':rank('crossfire')>0 and has_type('archer') and melee,'text':Catalog.format_text('Melee engagement → archers deal +{crossfire_pct}% damage per rank.')}]

func reroll_reward() -> bool:
	if g.phase!='reward' or g.reward_context!='elite' or g.reward_rerolls<=0:return false
	g.reward_rerolls-=1;g.offerYear=0
	offers()
	return true
