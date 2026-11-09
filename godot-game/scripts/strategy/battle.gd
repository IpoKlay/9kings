extends 'res://scripts/tactical/whiteboard_battle.gd'
const Layout=preload('res://scripts/strategy/formation.gd')
var strategy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://data/balance/strategy.json'))
var stock={'food':100.,'wood':100.,'iron':100.}
var buildings: Array=[]
var resources: Array=[]
var hills=[Rect2(700,850,600,400),Rect2(2000,1500,420,360)]
var river=Rect2(2700,300,100,2300)
var cliffs=[Rect2(450,1300,260,160),Rect2(2150,900,260,170)]
var level=1
var researches={}
var research_queue={}
var team_serial=0
var report=''
var waves_sent=0
var next_wave=100.
var direction=''
var rain: Array=[]

func _init(test_powers: bool=false):
	super(test_powers)
	units.clear();next_id=0
	for kind in config.types:
		config.types[kind].files=1
		contact_profiles[kind]=Contact.profile(kind,config.types[kind],true)
		reserve[kind]=0
	config.battle_commands.shield_melee_reduction=0.
	config.battle_commands.shield_ranged_reduction=0.
	config.directional_combat.charge=1.
	config.individual_charge.damage_multiplier=1.
	config.individual_charge.trample_decay=1.
	terrain=PassTerrain.new(projection,bounds,config.types,{'rocks':cliffs,'SidePass':Rect2(-10000,-10000,1,1),'MainPass':Rect2(-10000,-10000,1,1)},true)
	add_building('town',Vector2(1450,2540),true)
	add_building('barracks',Vector2(1830,2450),true)
	for i in 4:spawn_person('villager','ally',Vector2(1330+i*32,2410))
	spawn_person('engineer','ally',Vector2(1650,2400))
	for type in ['shield','spear','archer','light_cavalry']:
		for i in 7:spawn_person(type,'ally',Vector2(1250+i*32,2170+['shield','spear','archer','light_cavalry'].find(type)*90))
	for i in 12:spawn_person('spear' if i%2 else 'shield','enemy',Vector2(1200+i*40,480))
	for row in [['tree',950,2440],['fruit',1050,2260],['berries',1700,2700],['deer',900,1950],['sheep',1900,2720],['boar',2200,2050],['cattle',800,2700],['fish',2750,2330],['iron',2050,2280],['tree',1120,2720],['fruit',720,2230]]:
		resources.append({'kind':row[0],'pos':Vector2(row[1],row[2]),'remaining':1000.})
	var fort=add_building('fortress',Vector2(1600,370),true);fort.side='enemy'
	for x in [1472,1536,1600,1664]:
		var wall=add_building('gate' if x==1536 else 'wall',Vector2(x,650),true);wall.side='enemy'
	charges=0

func spawn_person(type: String,side: String,point: Vector2) -> Dictionary:
	var data: Dictionary=strategy.units[type]
	super.spawn(data.kind,side,point)
	var u: Dictionary=units.back()
	u.unit_type=type;u.art=data.art;u.archetype='';u.order='auto' if side=='enemy' else 'hold'
	var stats: Dictionary=config.types[data.kind].duplicate(true)
	stats.merge({'hp':data.hp,'damage':data.damage,'range':data.range,'speed':data.speed,'interval':data.interval,'files':1},true)
	stats.individual=config.types.legion.individual.duplicate(true)
	stats.individual.merge({'hp':data.hp,'damage':data.damage,'range':data.range,'speed':data.speed,'can_charge':type in ['spear','shield','light_cavalry','elite_cavalry'],'can_shield_wall':false,'has_volley':false,'role_bits':4 if type in ['archer','ballista','catapult'] else 1,'aggro_range':450. if data.damage>0 else 0.},true)
	u.combat_stats=stats;u.individual_stats=stats.individual
	u.hp=data.hp;u.max_hp=data.hp
	Soldiers.initialize(u,stats)
	var actor: Dictionary=u.soldiers[0]
	actor.scan_slot=next_soldier_slot;next_soldier_slot+=1
	actor.position=point;actor.personal_order='hold';actor.path=[];actor.formation='default';actor.formation_ready=true
	actor.heading=u.heading;actor.team=-1;actor.last_combat=-100.
	u.personalized=true
	if side=='ally':apply_level(u)
	return u

func deploy_combined() -> bool:return false
func deploy_vanguard() -> bool:return false
func camera_focus() -> Vector2:return Vector2(1550,2320)
func population() -> int:return alive('ally').size()
func population_cap() -> int:
	var count=40
	for b in buildings:
		if b.side=='ally' and b.hp>0 and b.remaining<=0 and b.kind=='house':count+=15
	return count
func building_ready(kind: String) -> bool:
	return buildings.any(func(b):return b.kind==kind and b.side=='ally' and b.hp>0 and b.remaining<=0)
func affordable(cost: Dictionary) -> bool:
	for key in cost:
		if stock[key]+.0001<cost[key]:return false
	return true
func spend(cost: Dictionary):
	for key in cost:stock[key]-=cost[key]
func add_building(kind: String,point: Vector2,complete: bool=false) -> Dictionary:
	var data: Dictionary=strategy.buildings[kind]
	var b={'id':buildings.size(),'kind':kind,'pos':point,'hp':float(data.hp),'max_hp':float(data.hp),'remaining':0. if complete else float(data.seconds),'timer':0.,'queue':[],'open':false,'side':'ally'}
	buildings.append(b)
	if complete and kind=='farm':resources.append({'kind':'farm','pos':point,'remaining':2500.,'building':b.id})
	rebuild_obstacles()
	return b
func rebuild_obstacles():
	var obstacles: Array=cliffs.duplicate()
	for b in buildings:
		if b.hp<=0 or b.kind=='farm' or b.kind=='gate' and b.open:continue
		var size: float=strategy.buildings[b.kind].size
		obstacles.append(Rect2(b.pos-Vector2.ONE*size*.5,Vector2.ONE*size))
	terrain.replace_rocks(obstacles)
func build(kind: String,point: Vector2,ids: Array) -> bool:
	if phase!='battle' or not strategy.buildings.has(kind):return false
	var workers=Soldiers.members(self,ids).filter(func(row):return row.unit.unit_type=='engineer')
	if workers.is_empty():report='请选择军事工程师';return false
	var cost={'wood':strategy.buildings[kind].wood}
	if not affordable(cost):report='木材不足';return false
	var size: float=strategy.buildings[kind].size
	var padding=0. if kind in ['wall','gate','wall_tower'] else 20.
	var rect=Rect2(point-Vector2.ONE*(size*.5+padding),Vector2.ONE*(size+padding*2))
	if not bounds.encloses(rect) or rect.intersects(river):report='无法在这里建造';return false
	for obstacle in terrain.ROCKS:
		if rect.intersects(obstacle):report='建筑不能重叠地形或其他建筑';return false
	for u in alive('ally')+alive('enemy'):
		if rect.has_point(u.pos):report='建造位置被单位占用';return false
	if kind in ['range','stable'] and not buildings.any(func(b):return b.side=='ally' and b.kind=='barracks' and b.hp>0 and b.remaining<=0 and b.pos.distance_to(point)<=360.):
		report='必须在军营的360范围影响力内';return false
	var worker: Dictionary=workers[0].unit
	var approach=point+point.direction_to(worker.pos)*(size*.5+40)
	if not Soldiers.command(self,[Vector2i(worker.id,0)],'move',approach):report='工程师无法到达';return false
	spend(cost)
	var b=add_building(kind,point)
	worker.soldiers[0].job={'kind':'build','id':b.id}
	report='已安排建造：'+strategy.buildings[kind].name
	return true
func train(type: String) -> bool:
	if phase!='battle':return false
	var data: Dictionary=strategy.units[type]
	if type=='elite_cavalry' and level<4:report='精锐骑兵需要晋升四级';return false
	var available=buildings.filter(func(b):return b.side=='ally' and b.kind==data.producer and b.hp>0 and b.remaining<=0 and b.queue.size()<5)
	if available.is_empty():report='缺少生产建筑或队列已满';return false
	if not affordable({'food':data.food}):report='食物不足';return false
	spend({'food':data.food})
	available[0].queue.append({'type':type,'remaining':float(data.train_seconds)})
	report='已加入生产队列：'+data.name
	return true
func promotion_cost() -> Dictionary:
	var cost=strategy.promotion_base_cost.duplicate()
	for key in cost:cost[key]*=pow(2,level-1)
	return cost
func research(id: String) -> bool:
	if phase!='battle' or not research_queue.is_empty():report='已有科技研究中';return false
	var producer='barracks' if id=='promotion' else 'house' if id=='economy' else 'factory' if id=='military' else 'town' if id=='towncraft' else 'academy'
	if not building_ready(producer):report='缺少研究建筑：'+strategy.buildings[producer].name;return false
	if id=='promotion' and level>=5 or id!='promotion' and researches.has(id):report='已完成该研究';return false
	if id.begins_with('direction_') and direction!='':report='发展方向已选择';return false
	var cost=promotion_cost() if id=='promotion' else {'food':60.,'wood':40.,'iron':40.}
	if not affordable(cost):report='研究资源不足';return false
	spend(cost);research_queue={'id':id,'remaining':20.,'producer':producer}
	report='研究中，20秒完成'
	return true
func apply_level(u: Dictionary):
	var data: Dictionary=strategy.units[u.unit_type]
	var factor=1.+.1*(level-1)
	var actor: Dictionary=u.soldiers[0]
	var ratio: float=actor.hp/maxf(1.,actor.max_hp)
	actor.max_hp=data.hp*factor;actor.hp=actor.max_hp*ratio
	u.max_hp=actor.max_hp;u.soldier_max_hp=actor.max_hp
	u.combat_stats.damage=data.damage*factor
	u.individual_stats.damage=u.combat_stats.damage
	Soldiers.total(u)
func gathering(ids: Array,index: int) -> bool:
	if phase!='battle' or index<0 or index>=resources.size() or resources[index].remaining<=0:return false
	var selected=Soldiers.members(self,ids).filter(func(row):return row.unit.unit_type=='villager')
	var success=false
	for row in selected:
		var point: Vector2=resources[index].pos+resources[index].pos.direction_to(row.unit.pos)*55
		if Soldiers.command(self,[Vector2i(row.unit.id,row.slot)],'move',point):
			row.actor.job={'kind':'gather','id':index};success=true
	report='村民正在前往采集' if success else '请选择村民；目标需可到达'
	return success
func permitted(type: String) -> Array:
	if type=='spear':return ['default','wedge','ring','scatter']
	if type=='shield':return ['default','testudo','ring','wedge','scatter']
	if type in ['light_cavalry','elite_cavalry']:return ['default','wedge']
	if type=='archer':return ['default','dense','scatter']
	return ['default']
func in_combat(u: Dictionary) -> bool:
	return elapsed-u.soldiers[0].get('last_combat',-100.)<3. or u.soldiers[0].attack_age<1.
func set_formation(ids: Array,form: String,heading: Vector2=Vector2.ZERO) -> bool:
	var people=Soldiers.members(self,ids)
	if phase!='battle' or people.is_empty():return false
	for row in people:
		if in_combat(row.unit) or form not in permitted(row.unit.unit_type):report='需要脱战，且所有所选兵种都支持此阵型';return false
	var center=Vector2.ZERO
	for row in people:center+=row.unit.pos
	center/=people.size()
	if heading.is_zero_approx():heading=people[0].actor.heading
	var planned=people.duplicate(true)
	for row in planned:row.actor.formation=form
	var paths=Layout.plan(self,planned,center+heading*.01,[])
	if paths.is_empty():report='附近空间不足以构建阵型';return false
	# Commit only after every member has a valid route.
	for i in people.size():
		var row=people[i]
		Soldiers.command(self,[Vector2i(row.unit.id,row.slot)],'hold',row.unit.pos)
		row.actor.personal_order='move';row.actor.path=paths[i].path;row.actor.move_goal=paths[i].path.back();row.actor.route_stops=paths[i].stops
		row.actor.formation=form;row.actor.formation_ready=false;row.actor.form_left=5.
		row.actor.form_heading=heading;row.actor.form_goal=paths[i].path.back()
	report='构建阵型中：5秒；枪兵在丘陵为15秒'
	return true
func formation_data(u: Dictionary) -> Dictionary:
	var actor: Dictionary=u.soldiers[0]
	return strategy.formations[actor.get('formation','default')] if actor.get('formation_ready',false) else {'speed':1.,'attack':0.,'armor':0.}
func on_hill(point: Vector2) -> bool:
	return hills.any(func(h):return h.has_point(point))
func personal_speed(u: Dictionary) -> float:
	return float(formation_data(u).speed)*(0.8 if u.soldiers[0].get('weakened',0.)>elapsed else 1.)
func damage_amount(base: float,bonuses: Array,reductions: Array,armor: float) -> float:
	var bonus=0.;var reduction=0.
	for value in bonuses:bonus+=value
	for value in reductions:reduction+=value
	return maxf(0.,base*maxf(0.,1.+bonus)*maxf(0.,1.-reduction)-armor)
func hurt(u: Dictionary,damage: float,source_kind: String='',shock: float=0.,slot: int=-1,attacker_id: int=-1,attacker_slot: int=-1) -> float:
	if not u.has('unit_type'):return super.hurt(u,damage,source_kind,shock,slot,attacker_id,attacker_slot)
	var source={}
	for other in units:
		if other.id==attacker_id:source=other;break
	var bonuses=[];var reductions=[]
	if not source.is_empty() and source.has('unit_type'):
		var f=formation_data(source)
		bonuses.append(f.get('volley',0.) if source_kind=='volley' else f.attack)
		if source.side=='ally' and researches.has('military'):bonuses.append(.2)
		if source.side=='ally' and direction=='military':bonuses.append(.15)
		if source.kind=='cavalry' and on_hill(source.pos):bonuses.append(-strategy.hill_cavalry_attack_penalty)
		if source.unit_type=='spear' and u.kind=='cavalry':bonuses.append(.6)
		if source.unit_type=='light_cavalry' and u.unit_type in ['archer','ballista','catapult']:bonuses.append(.35)
		if source.soldiers[0].get('weakened',0.)>elapsed:bonuses.append(-.25)
		if source.soldiers[0].has('charge_run'):
			bonuses.append(f.get('charge',0.))
			if source.soldiers[0].get('formation','default')=='wedge':u.soldiers[0].weakened=elapsed+4.
			if source.kind=='cavalry' and u.soldiers[0].get('formation','')=='testudo':u.soldiers[0].formation_ready=false
		if source.soldiers[0].get('shield_raised',false):bonuses.append(-.4)
		source.soldiers[0].last_combat=elapsed
	var target_form=formation_data(u)
	var ranged=source_kind in ['archer','volley','siege']
	var data: Dictionary=strategy.units[u.unit_type]
	var armor: float=data.armor_ranged if ranged else data.armor_melee
	armor+=level-1 if u.side=='ally' else 0
	armor+=target_form.armor
	if u.unit_type=='spear' and u.soldiers[0].get('formation_ready',false) and u.soldiers[0].get('formation','')=='default':armor+=2
	if u.soldiers[0].get('shield_raised',false):reductions.append(.6)
	if source_kind in ['volley','siege']:reductions.append(target_form.get('area_reduction',0.))
	var dealt=damage_amount(damage,bonuses,reductions,armor)
	u.soldiers[0].last_combat=elapsed
	if u.soldiers[0].has('form_left'):u.soldiers[0].erase('form_left');u.soldiers[0].formation_ready=false
	return super.hurt(u,dealt,source_kind,shock,slot,attacker_id,attacker_slot)
func deal_blow(a: Dictionary,b: Dictionary,damage: float,contact: Dictionary={},strike: Dictionary={}) -> Dictionary:
	if a.get('unit_type','')=='archer' and a.pos.distance_to(b.pos)<60.:
		var dealt=hurt(b,damage,'sword',0.,strike.get('target_slot',0),a.id,strike.get('attacker_slot',0))
		var event={'kind':'hit','pos':b.pos,'from':a.pos,'attacker':a.id,'target':b.id,'damage':dealt}
		events.append(event);return event
	return super.deal_blow(a,b,damage,contact,strike)
func arrow_rain(ids: Array,point: Vector2) -> bool:
	if phase!='battle' or not bounds.has_point(point):return false
	var fired=false
	for row in Soldiers.members(self,ids):
		if row.unit.unit_type!='archer' or row.actor.get('rain_until',0.)>elapsed or row.unit.pos.distance_to(point)>650.:continue
		row.actor.rain_until=elapsed+12.;row.actor.attack_age=0.
		rain.append({'point':point+Vector2(volley_random.randf_range(-80,80),volley_random.randf_range(-80,80)),'remaining':1.5,'attacker':row.unit.id,'damage':row.unit.combat_stats.damage})
		fired=true
	report='箭雨已发射（范围80，冷却12秒）' if fired else '需要650范围内、箭雨已冷却的弓箭手'
	return fired
func shield(ids: Array):
	for row in Soldiers.members(self,ids):
		if row.unit.unit_type=='shield':row.actor.shield_raised=not row.actor.get('shield_raised',false)
func entity_at(point: Vector2) -> Dictionary:
	for b in buildings:
		if b.hp>0 and point.distance_to(b.pos)<float(strategy.buildings[b.kind].size)*.7:return {'kind':'building','id':b.id}
	for i in resources.size():
		if resources[i].remaining>0 and point.distance_to(resources[i].pos)<55:return {'kind':'resource','id':i}
	return {}
func interact(ids: Array,point: Vector2) -> bool:
	var hit=entity_at(point)
	if hit.is_empty():return interact_unit(ids,point)
	if hit.kind=='resource':gathering(ids,hit.id);return true
	var b: Dictionary=buildings[hit.id]
	if b.side=='enemy':
		assault_building(ids,b);return true
	if b.kind=='farm':
		for i in resources.size():
			if resources[i].get('building',-1)==b.id:return gathering(ids,i)
	if b.kind=='gate':b.open=not b.open;rebuild_obstacles();report='城门已打开' if b.open else '城门已关闭';return true
	for row in Soldiers.members(self,ids):
		if row.unit.unit_type=='engineer':
			var goal: Vector2=b.pos+b.pos.direction_to(row.unit.pos)*(strategy.buildings[b.kind].size*.5+40)
			if Soldiers.command(self,[Vector2i(row.unit.id,0)],'move',goal):row.actor.job={'kind':'repair_building','id':b.id}
	return true
func step(dt: float):
	if phase!='battle' or dt<=0:return
	advance_economy(dt)
	advance_siege(dt)
	for u in alive('ally')+alive('enemy'):
		var a: Dictionary=u.soldiers[0]
		if a.has('form_left'):
			if in_combat(u):a.erase('form_left');a.formation_ready=false
			else:
				a.form_left-=dt/(strategy.hill_formation_multiplier if u.unit_type=='spear' and on_hill(u.pos) else 1.)
				a.form_left=maxf(0.,a.form_left)
				if a.form_left<=0 and a.position.distance_to(a.form_goal)<20.:
					var goal: Vector2=a.form_goal;var heading: Vector2=a.form_heading
					a.erase('form_left')
					var path=terrain.leg(Soldiers.navigator(self,u.kind,u),a.position,goal)
					if not path.is_empty():
						a.path=path;a.move_goal=goal;a.route_stops=[goal];a.personal_order='move';a.formation_ready=true;a.heading=heading
		if u.unit_type in ['villager','engineer','ram','tower']:
			a.target_id=-1;a.target_slot=-1;a.erase('attack_pending')
			if a.personal_order in ['auto','idle','attack','attack_move']:a.personal_order='hold'
		if a.get('weakened',0.)>elapsed:u.combat_stats.interval=strategy.units[u.unit_type].interval*1.3
		else:u.combat_stats.interval=strategy.units[u.unit_type].interval
	super.step(dt)
	for u in alive('ally')+alive('enemy'):
		var actor: Dictionary=u.soldiers[0]
		if actor.get('formation_ready',false) and actor.has('form_heading') and actor.get('path',[]).is_empty() and actor.get('target_id',-1)<0:
			actor.heading=actor.form_heading
	for shot in rain:
		shot.remaining-=dt
		if shot.remaining>0:continue
		for u in alive('enemy'):
			if u.pos.distance_to(shot.point)<80.:hurt(u,shot.damage,'volley',0.,0,shot.attacker,0)
		events.append({'kind':'hit','pos':shot.point,'from':shot.point-Vector2(0,120)})
	rain=rain.filter(func(s):return s.remaining>0)
	if elapsed>=next_wave and waves_sent<3:
		waves_sent+=1;next_wave+=90.
		for i in 10+waves_sent*3:
			var u=spawn_person('light_cavalry' if i%4==0 else 'archer' if i%3==0 else 'shield','enemy',Vector2(850+i*45,300))
			u.order='auto'
func advance_economy(dt: float):
	for b in buildings:
		if b.hp<=0 or b.remaining>0:continue
		if b.side=='enemy':
			if b.kind in ['outpost','fortress','wall_tower']:
				b.timer+=dt
				if b.timer>=1.5:
					for defender in alive('ally'):
						if not defender.escaped and defender.pos.distance_to(b.pos)<450.:
							hurt(defender,25.,'archer',0.,0);b.timer=0.;events.append({'kind':'hit','pos':defender.pos,'from':b.pos});break
			continue
		if b.kind=='town':
			b.timer+=dt
			if b.timer>=(15. if researches.has('towncraft') else 20.) and population()<population_cap() and affordable({'food':35.}):
				spend({'food':35.});spawn_person('villager','ally',b.pos+Vector2(-100,100));b.timer=0.
		if not b.queue.is_empty() and population()<population_cap():
			b.queue[0].remaining-=dt
			if b.queue[0].remaining<=0:spawn_person(b.queue.pop_front().type,'ally',b.pos+Vector2(0,110))
		if b.kind in ['outpost','fortress','wall_tower']:
			b.timer+=dt
			if b.timer>=1.5:
				for enemy in alive('enemy'):
					if enemy.pos.distance_to(b.pos)<450.:hurt(enemy,25.,'archer',0.,0);b.timer=0.;break
	for u in alive('ally'):
		var a: Dictionary=u.soldiers[0]
		if not a.has('job'):continue
		var job: Dictionary=a.job
		if job.kind=='gather':
			var resource: Dictionary=resources[job.id]
			if resource.remaining<=0:a.erase('job');continue
			if u.pos.distance_to(resource.pos)>85.:continue
			var amount=minf(resource.remaining,dt*(3. if researches.has('economy') else 2.)*(1.25 if direction=='economy' else 1.))
			resource.remaining-=amount
			if resource.kind in ['tree','fruit']:stock.wood+=amount
			if resource.kind=='iron':stock.iron+=amount
			elif resource.kind!='tree':stock.food+=amount
		elif job.kind in ['build','repair_building']:
			var b: Dictionary=buildings[job.id]
			if b.hp<=0:a.erase('job');continue
			if u.pos.distance_to(b.pos)>strategy.buildings[b.kind].size*.5+70:continue
			if job.kind=='build':
				b.remaining=maxf(0,b.remaining-dt)
				if b.remaining<=0:
					if b.kind=='farm':resources.append({'kind':'farm','pos':b.pos,'remaining':2500.,'building':b.id})
					a.erase('job')
			elif affordable({'wood':dt}):spend({'wood':dt});b.hp=minf(b.max_hp,b.hp+dt*20)
	if not research_queue.is_empty() and building_ready(research_queue.producer):
		research_queue.remaining-=dt
		if research_queue.remaining<=0:
			var id: String=research_queue.id
			if id=='promotion':
				level+=1
				for u in alive('ally'):apply_level(u)
			else:
				researches[id]=true
				if id.begins_with('direction_'):direction=id.trim_prefix('direction_')
			research_queue={};report='研究完成'
	# Enemy troops can destroy the town, so the economy has a real loss condition.
	for enemy in alive('enemy'):
		if enemy.soldiers[0].cooldown>0:continue
		for b in buildings:
			if b.side=='ally' and b.hp>0 and enemy.pos.distance_to(b.pos)<strategy.buildings[b.kind].size*.5+70:
				b.hp=maxf(0,b.hp-enemy.combat_stats.damage);enemy.soldiers[0].cooldown=enemy.combat_stats.interval
				if b.hp<=0:rebuild_obstacles()
				break
func autonomous_destination(u: Dictionary,actor: Dictionary) -> Vector2:
	if u.side=='enemy':return buildings[0].pos+Vector2(0,-120)
	return super.autonomous_destination(u,actor)
func resolve_battle(_dt: float):
	if buildings[0].hp<=0:outcome='defenders_routed';phase='defeat'
	elif waves_sent>=3 and not buildings.any(func(b):return b.side=='enemy' and b.kind=='fortress' and b.hp>0) and alive('enemy').is_empty() and not Soldiers.pending_deaths(self,'enemy'):outcome='enemy_routed';phase='victory'

func strategy_paths(selected: Array,destination: Vector2,via: Array[Vector2]) -> Array:
	return Layout.plan(self,selected,destination,via)
func strategy_command(row: Dictionary,path: Dictionary):
	row.actor.erase('job')
	row.actor.erase('form_left')
	if path.has('team'):
		row.actor.team=team_serial+path.team
		var previous: String=row.actor.get('formation','default')
		row.actor.formation=path.formation
		row.actor.form_heading=path.heading
		if previous!=path.formation or row.actor.heading.dot(path.heading)<.98:
			row.actor.formation_ready=false;row.actor.form_left=5.;row.actor.form_goal=path.path.back();row.actor.form_heading=path.heading
	# The command caller allocates one serial range for all members atomically.
func charge_allowed(people: Array,point: Vector2) -> bool:
	for row in people:
		if row.unit.kind=='cavalry' and row.actor.get('formation','')=='wedge' and row.actor.heading.dot(row.unit.pos.direction_to(point))<cos(deg_to_rad(20)):
			report='楔形骑兵需先面向目标（使用朝向按钮）';return false
	return true

func assault_building(ids: Array,b: Dictionary) -> bool:
	var issued=false
	for row in Soldiers.members(self,ids):
		var type: String=row.unit.unit_type
		if type in ['villager','engineer','archer']:continue
		if type=='ram' and b.kind!='gate':continue
		var distance=500. if type in ['ballista','catapult'] else strategy.buildings[b.kind].size*.5+50.
		var goal: Vector2=b.pos+b.pos.direction_to(row.unit.pos)*distance
		if Soldiers.command(self,[Vector2i(row.unit.id,0)],'move',goal):
			row.actor.job={'kind':'siege','id':b.id};issued=true
	report='已下令攻击工事；攻城锤只能攻击城门' if issued else '选择可攻城的单位（攻城锤只攻击城门）'
	return issued
func interact_unit(ids: Array,point: Vector2) -> bool:
	var targets=alive('ally').filter(func(u):return u.pos.distance_to(point)<30 and u.unit_type in ['ram','tower','ballista','catapult'])
	if targets.is_empty():return false
	var target: Dictionary=targets[0];var success=false
	for row in Soldiers.members(self,ids):
		if row.unit.unit_type=='engineer':
			if Soldiers.command(self,[Vector2i(row.unit.id,0)],'move',target.pos+Vector2(45,0)):
				row.actor.job={'kind':'repair_siege','id':target.id};success=true
		elif target.unit_type=='tower' and row.unit.unit_type in ['shield','spear','archer']:
			if Soldiers.command(self,[Vector2i(row.unit.id,0)],'move',target.pos+Vector2(0,40)):
				row.actor.job={'kind':'embark','id':target.id};success=true
	return success
func advance_siege(dt: float):
	for u in alive('ally'):
		var a: Dictionary=u.soldiers[0]
		if a.has('aboard'):
			var carriers=units.filter(func(other):return other.id==a.aboard and other.hp>0)
			if carriers.is_empty():
				u.escaped=false;u.stun=0.;a.erase('aboard');a.position+=Vector2(60,0)
			else:
				a.position=carriers[0].pos;u.pos=a.position;u.stun=1.
			continue
		if not a.has('job'):continue
		var job: Dictionary=a.job
		if job.kind in ['repair_siege','embark']:
			var targets=units.filter(func(other):return other.id==job.id and other.hp>0)
			if targets.is_empty():a.erase('job');continue
			var target: Dictionary=targets[0]
			if u.pos.distance_to(target.pos)>90.:continue
			if job.kind=='repair_siege':
				if target.hp>=target.max_hp:a.erase('job');continue
				if affordable({'wood':dt}):spend({'wood':dt});heal(target,dt*25.)
			elif units.filter(func(other):return other.soldiers[0].get('aboard',-1)==target.id).size()<21:
				a.aboard=target.id;u.escaped=true;a.erase('job');a.personal_order='hold';a.path=[]
		elif job.kind=='siege':
			var b: Dictionary=buildings[job.id]
			if b.hp<=0:a.erase('job');continue
			var reach=600. if u.unit_type in ['ballista','catapult'] else strategy.buildings[b.kind].size*.5+80.
			if u.pos.distance_to(b.pos)>reach:continue
			if u.unit_type=='tower':
				# Wall-top landing uses a personal navigation layer until dismounting.
				for passenger in units:
					var soldier: Dictionary=passenger.soldiers[0]
					if soldier.get('aboard',-1)!=u.id:continue
					passenger.escaped=false;passenger.stun=0.;soldier.erase('aboard')
					soldier.position=b.pos+Vector2((passenger.id%3-1)*18,0);passenger.pos=soldier.position
					soldier.wall_top=b.id;soldier.personal_order='hold';soldier.path=[]
				a.erase('job');a.personal_order='hold';a.path=[];report='攻城塔已让驻载军队登墙'
			elif a.cooldown<=0:
				b.hp=maxf(0,b.hp-u.combat_stats.damage);a.last_combat=elapsed;a.cooldown=u.combat_stats.interval;a.attack_age=0.
				events.append({'kind':'hit','pos':b.pos,'from':u.pos})
				if b.hp<=0:rebuild_obstacles();report='敌方工事已摧毁'
func wall_navigator(u: Dictionary) -> String:
	var key='wall_top_'+str(u.id)
	var b: Dictionary=buildings[u.soldiers[0].wall_top]
	if b.hp<=0 or u.pos.distance_to(b.pos)>strategy.buildings[b.kind].size*.5+30.:
		u.soldiers[0].erase('wall_top')
		return Soldiers.navigator(self,u.kind,u)
	var radius=Vector2.ONE*9.
	terrain.extents[key]=radius
	var walls: Array[Rect2]=[]
	for obstacle in terrain.ROCKS:
		if obstacle.has_point(b.pos):continue
		walls.append(obstacle.grow(9))
	terrain.clearances[key]=walls
	return key
