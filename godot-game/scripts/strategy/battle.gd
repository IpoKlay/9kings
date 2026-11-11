extends 'res://scripts/tactical/whiteboard_battle.gd'
const Layout=preload('res://scripts/strategy/formation.gd')
const StaticArt=preload('res://scripts/strategy/static_art.gd')
const ApprovedArt=preload('res://scripts/tactical/approved_unit_art.gd')
var strategy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://data/balance/strategy.json'))
var stock: Dictionary=strategy.starting_resources.duplicate()
var town_level=1
var world=preload('res://scripts/strategy/world.gd').new()
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
var next_wave=180.
var ai_food=100.
var ai_training=0.
var ai_serial=0
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
	config.individual_charge.speed*=.5
	config.individual_charge.damage_multiplier=1.
	config.individual_charge.trample_decay=1.
	terrain=PassTerrain.new(projection,bounds,config.types,{'rocks':cliffs,'SidePass':Rect2(-10000,-10000,1,1),'MainPass':Rect2(-10000,-10000,1,1)},true)
	world.setup(self)
	charges=0
	start()

func spawn_person(type: String,side: String,point: Vector2) -> Dictionary:
	var data: Dictionary=strategy.units[type]
	super.spawn(data.kind,side,point)
	var u: Dictionary=units.back()
	u.unit_type=type;u.art=data.art;u.archetype='';u.order='auto' if side=='enemy' else 'hold'
	u.approved_art=StaticArt.unit_id(type,level if side=='ally' else 1)
	var stats: Dictionary=config.types[data.kind].duplicate(true)
	stats.merge({'hp':data.hp,'damage':data.damage,'range':data.range,'speed':data.speed,'interval':data.interval,'files':1},true)
	stats.individual=config.types.legion.individual.duplicate(true)
	stats.individual.unit_size=strategy.collision_radius
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

func start() -> bool:
	if phase!='deploy' or alive('ally').is_empty():return false
	phase='battle';enemy_director.active=false
	return true

func deploy_combined() -> bool:return false
func deploy_vanguard() -> bool:return false
func camera_focus() -> Vector2:return world.CENTER
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
	if town_level>1:b.max_hp*=1.+.2*mini(town_level-1,3);b.hp=b.max_hp
	buildings.append(b)
	if complete and kind=='farm':resources.append({'kind':'farm','pos':point,'remaining':2500.,'building':b.id})
	rebuild_obstacles()
	return b
func rebuild_obstacles():
	var obstacles: Array=cliffs.duplicate()
	for b in buildings:
		if b.hp<=0 or b.kind=='farm' or b.kind=='gate' and b.open:continue
		var size: float=strategy.buildings[b.kind].size
		var dimensions: Vector2=b.get('wall_bounds',Vector2.ONE*size)
		obstacles.append(Rect2(b.pos-dimensions*.5,dimensions))
	terrain.replace_rocks(obstacles)
func build(kind: String,point: Vector2,ids: Array) -> bool:
	if phase!='battle' or not strategy.buildings.has(kind):return false
	var workers=Soldiers.members(self,ids).filter(func(row):return row.unit.unit_type=='villager')
	if workers.is_empty():report='请选择村民';return false
	var cost={'wood':building_cost(kind)}
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
	if not Soldiers.command(self,[Vector2i(worker.id,0)],'move',approach):report='村民无法到达';return false
	spend(cost)
	var b=add_building(kind,point)
	worker.soldiers[0].job={'kind':'build','id':b.id}
	report='已安排建造：'+strategy.buildings[kind].name
	return true
func train(type: String,building_id: int=-1) -> bool:
	if phase!='battle':return false
	if not strategy.units.has(type):return false
	var data: Dictionary=strategy.units[type]
	if type=='elite_cavalry' and town_level<5:report='精锐骑兵需要城镇五级';return false
	var available=buildings.filter(func(b):return b.id==building_id and b.side=='ally' and b.kind==data.producer and b.hp>0 and b.remaining<=0 and b.queue.size()<5)
	if available.is_empty():report='请选中对应的已完工建筑；每座建筑最多排队5人';return false
	var cost=unit_cost(type)
	if not affordable(cost):report='生产资源不足';return false
	if data.train_seconds==0:
		if population()>=population_cap():report='人口已满';return false
		if not produce(available[0],type):report='建筑出口被堵住';return false
		spend(cost);report='已生产：'+data.name;return true
	spend(cost)
	available[0].queue.append({'type':type,'remaining':float(data.train_seconds)})
	report='已加入生产队列：'+data.name
	return true
func promotion_cost() -> Dictionary:
	var cost=strategy.promotion_base_cost.duplicate()
	for key in cost:cost[key]*=pow(2,level-1)
	return cost
func research(id: String,building_id: int=-1) -> bool:
	if phase!='battle' or not research_queue.is_empty():report='已有科技研究中';return false
	var producer='barracks' if id=='promotion' else 'house' if id=='economy' else 'factory' if id=='military' else 'town' if id in ['towncraft','town_upgrade'] else 'academy'
	if building_id<0 or building_id>=buildings.size() or buildings[building_id].kind!=producer or buildings[building_id].side!='ally' or buildings[building_id].hp<=0 or buildings[building_id].remaining>0:report='缺少研究建筑：'+strategy.buildings[producer].name;return false
	if id=='town_upgrade' and town_level>=5 or id=='promotion' and level>=5 or id not in ['promotion','town_upgrade'] and researches.has(id):report='已完成该研究';return false
	if id.begins_with('direction_') and direction!='':report='发展方向已选择';return false
	var cost=town_cost() if id=='town_upgrade' else promotion_cost() if id=='promotion' else {'food':60.,'wood':40.,'iron':40.}
	if not affordable(cost):report='研究资源不足';return false
	spend(cost);research_queue={'id':id,'remaining':20.,'producer':producer,'building_id':building_id}
	report='研究中，20秒完成'
	return true
func apply_level(u: Dictionary):
	u.approved_art=StaticArt.unit_id(u.unit_type,level)
	var data: Dictionary=strategy.units[u.unit_type]
	var factor=1.+.1*(level-1)
	if u.unit_type=='villager':factor*=1.+.3*mini(town_level-1,3)
	elif town_level>=5:factor*=1.1
	var actor: Dictionary=u.soldiers[0]
	var ratio: float=actor.hp/maxf(1.,actor.max_hp)
	actor.max_hp=data.hp*factor;actor.hp=actor.max_hp*ratio
	u.max_hp=actor.max_hp;u.soldier_max_hp=actor.max_hp
	u.combat_stats.damage=data.damage*(1.+.1*(level-1))+(5. if u.unit_type=='villager' and town_level>=3 else 0.)
	if u.unit_type=='villager' and town_level>=3:
		u.combat_stats.range=32.;u.individual_stats.range=32.;u.individual_stats.aggro_range=300.
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
var formation_revision=0
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
	var paths=Layout.plan(self,planned,center+heading*.01,[],false)
	if paths.is_empty():report='附近空间不足以构建阵型';return false
	formation_revision+=1
	# Commit only after every member has a valid route.
	for i in people.size():
		var row=people[i]
		Soldiers.command(self,[Vector2i(row.unit.id,row.slot)],'hold',row.unit.pos)
		row.actor.personal_order='move';row.actor.path=paths[i].path;row.actor.move_goal=paths[i].path.back();row.actor.route_stops=paths[i].stops
		row.actor.formation=form;row.actor.formation_ready=false;row.actor.form_left=5.;row.actor.formation_revision=formation_revision
		row.actor.form_heading=paths[i].heading;row.actor.form_goal=paths[i].path.back()
	report='构建阵型中：5秒；枪兵在丘陵为15秒'
	return true
func formation_data(u: Dictionary) -> Dictionary:
	var actor: Dictionary=u.soldiers[0]
	return strategy.formations[actor.get('formation','default')] if actor.get('formation_ready',false) else {'speed':1.,'attack':0.,'armor':0.}
func on_hill(point: Vector2) -> bool:
	return hills.any(func(h):return h.has_point(point))
func personal_speed(u: Dictionary) -> float:
	return (1.1 if u.side=='ally' and u.unit_type!='villager' and town_level>=4 else 1.)*float(formation_data(u).speed)*(0.8 if u.soldiers[0].get('weakened',0.)>elapsed else 1.)
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
		if source.unit_type=='spear' and u.unit_type in ['light_cavalry','elite_cavalry']:damage+=strategy.units.spear.bonus_damage
		if source.unit_type in ['light_cavalry','elite_cavalry'] and u.unit_type=='archer':damage+=strategy.units[source.unit_type].bonus_damage
		if source.side=='ally' and town_level>=5 and source.unit_type!='villager' and source.hp>=source.max_hp:bonuses.append(.05)
		if source.soldiers[0].get('weakened',0.)>elapsed:bonuses.append(-.25)
		if source.soldiers[0].has('charge_run'):
			bonuses.append(f.get('charge',0.))
			if source.kind=='cavalry':bonuses.append(1.)
			if source.soldiers[0].get('formation','default')=='wedge':u.soldiers[0].weakened=elapsed+4.
			if source.kind=='cavalry' and u.soldiers[0].get('formation','')=='testudo':u.soldiers[0].formation_ready=false
		if source.soldiers[0].get('shield_raised',false):bonuses.append(-.4)
		source.soldiers[0].last_combat=elapsed
	var target_form=formation_data(u)
	var ranged=source_kind in ['archer','volley','siege']
	var data: Dictionary=strategy.units[u.unit_type]
	var armor: float=data.armor_ranged if ranged else data.armor_melee
	armor+=level-1 if u.side=='ally' else 0
	if u.side=='ally' and u.unit_type=='villager' and town_level>=3:armor+=2
	armor+=target_form.armor+u.get('armor_bonus',0)
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
	var hit=super.deal_blow(a,b,damage,contact,strike)
	if hit.has('origin') and a.get('unit_type','')=='archer' and strike.has('attacker_slot'):
		var slot: int=strike.attacker_slot
		var actor: Dictionary=a.soldiers[slot]
		var bearing=ApprovedArt.bearing_for(ground_basis.basis_xform(actor.get('heading',a.heading)))
		var clip=ApprovedArt.clip(a.approved_art,'attack',bearing)
		var offset=clip.release_offset*ApprovedArt.scale_for(a.kind)+Contact.body_shift(a,slot,elapsed)
		hit.sprite_origin=Soldiers.ground_position(self,a,slot)+ground_inverse.basis_xform(offset)
	return hit
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
	if not world.visible(point):return {}
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
		if row.unit.unit_type in ['villager','engineer']:
			var goal: Vector2=b.pos+b.pos.direction_to(row.unit.pos)*(strategy.buildings[b.kind].size*.5+40)
			if Soldiers.command(self,[Vector2i(row.unit.id,0)],'move',goal):row.actor.job={'kind':'build' if b.remaining>0 else 'repair_building','id':b.id}
	return true
func step(dt: float):
	if phase!='battle' or dt<=0:return
	advance_economy(dt)
	advance_siege(dt)
	for u in alive('ally')+alive('enemy'):
		var a: Dictionary=u.soldiers[0]
		# A settled soldier can be pushed off its slot by passing friends. Recover without a new command.
		if a.has('form_goal') and not a.has('job') and a.get('path',[]).is_empty() and a.personal_order in ['idle','move'] and not in_combat(u) and a.position.distance_to(a.form_goal)>8. and elapsed>=a.get('slot_retry',0.):
			a.slot_retry=elapsed+.5
			var path=terrain.leg(Soldiers.navigator(self,u.kind,u),a.position,a.form_goal)
			if not path.is_empty():a.path=path;a.move_goal=a.form_goal;a.personal_order='move'
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
		if u.unit_type in ['engineer','ram','tower'] or u.unit_type=='villager' and town_level<3:
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
	advance_ai(dt)
	world.step(self,dt)
func mark_work(actor: Dictionary,point: Vector2):
	if elapsed-actor.get('work_at',-1.)>.1:actor.work_start=elapsed
	actor.work_point=point
	actor.work_at=elapsed

func advance_economy(dt: float):
	for b in buildings:
		if b.hp<=0:
			b.queue.clear()
			if research_queue.get('building_id',-1)==b.id:research_queue={};report='研究建筑已被摧毁，研究中止'
			continue
		if b.remaining>0:continue
		if b.side=='enemy':
			if b.kind in ['outpost','fortress','wall_tower']:
				b.timer+=dt
				if b.timer>=1.5:
					for defender in alive('ally'):
						if not defender.escaped and defender.pos.distance_to(b.pos)<450.:
							hurt(defender,25.,'archer',0.,0);b.timer=0.;events.append({'kind':'hit','pos':defender.pos,'from':b.pos});break
			continue
		if not b.queue.is_empty() and population()<population_cap():
			b.queue[0].remaining-=dt*(1.+.3*mini(town_level-1,3)+(.35 if researches.has('towncraft') else 0.) if b.kind=='town' else 1.)
			if b.queue[0].remaining<=0:
				var spawn_point=find_exit(b)
				if spawn_point!=Vector2.INF and produce(b,b.queue[0].type):b.queue.pop_front()
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
			var amount=minf(resource.remaining,dt*gather_rate(resource.kind)*(1.5 if researches.has('economy') else 1.)*(1.25 if direction=='economy' else 1.))
			resource.remaining-=amount
			mark_work(a,resource.pos)
			if resource.kind in ['tree','fruit']:stock.wood+=amount
			if resource.kind in ['iron','large_iron']:stock.iron+=amount
			elif resource.kind!='tree':stock.food+=amount
		elif job.kind in ['build','repair_building']:
			var b: Dictionary=buildings[job.id]
			if b.hp<=0:a.erase('job');continue
			if u.pos.distance_to(b.pos)>strategy.buildings[b.kind].size*.5+70:continue
			if job.kind=='build':
				# Only the worker finishing the shared progress creates the farm resource.
				if b.remaining<=0:a.erase('job');continue
				b.remaining=maxf(0,b.remaining-dt)
				mark_work(a,b.pos)
				if b.remaining<=0:
					if b.kind=='farm':resources.append({'kind':'farm','pos':b.pos,'remaining':2500.,'building':b.id})
					a.erase('job')
			elif affordable({'wood':dt}):
				if b.hp<b.max_hp:mark_work(a,b.pos)
				spend({'wood':dt});b.hp=minf(b.max_hp,b.hp+dt*20)
	if not research_queue.is_empty() and buildings[research_queue.building_id].hp>0:
		research_queue.remaining-=dt*(1.3 if town_level>=4 else 1.)
		if research_queue.remaining<=0:
			var id: String=research_queue.id
			if id=='town_upgrade':upgrade_town()
			elif id=='promotion':
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
	if u.has('camp') or u.get('wild',false):return u.home
	if u.side=='enemy':return buildings[0].pos+Vector2(0,-120)
	return super.autonomous_destination(u,actor)
func resolve_battle(_dt: float):
	if not buildings.any(func(b):return b.side=='ally' and b.kind=='town' and b.hp>0):outcome='defenders_routed';phase='defeat'
	elif not buildings.any(func(b):return b.side=='enemy' and b.kind=='town' and b.hp>0):outcome='enemy_routed';phase='victory'

func strategy_paths(selected: Array,destination: Vector2,via: Array[Vector2]) -> Array:
	return Layout.plan(self,selected,destination,via)
func strategy_command(row: Dictionary,path: Dictionary):
	row.actor.erase('form_goal')
	row.actor.erase('formation_revision')
	row.actor.erase('job')
	row.actor.erase('form_left')
	if path.has('team'):
		row.actor.team=team_serial+path.team
		row.actor.form_goal=path.path.back()
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
				if affordable({'wood':dt}):
					spend({'wood':dt});heal(target,dt*25.)
					mark_work(a,target.pos)
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
	var key='wall_top_'+str(u.id)+'_'+str(u.soldiers[0].wall_top)
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

func find_exit(b: Dictionary) -> Vector2:
	for offset in [Vector2(0,110),Vector2(-110,0),Vector2(110,0),Vector2(0,-110),Vector2(-110,110),Vector2(110,110)]:
		var point: Vector2=b.pos+offset
		if terrain.clear_segment('legion',point,point) and not units.any(func(u):return u.hp>0 and u.pos.distance_to(point)<22.):return point
	return Vector2.INF

func cancel_training(building_id: int,index: int) -> bool:
	if phase!='battle' or building_id<0 or building_id>=buildings.size():return false
	var b: Dictionary=buildings[building_id]
	if b.side!='ally' or b.hp<=0 or index<0 or index>=b.queue.size():return false
	for key in unit_cost(b.queue[index].type):stock[key]+=unit_cost(b.queue[index].type)[key]
	b.queue.remove_at(index);report='已取消生产，退还食物'
	return true

func advance_ai(dt: float):
	if phase!='battle':return
	# Bounded AI recruitment budget; no fixed three-wave win condition.
	if not buildings.any(func(b):return b.side=='enemy' and b.kind=='town' and b.hp>0):return
	ai_food+=dt*2.
	ai_training+=dt
	var bases=buildings.filter(func(b):return b.side=='enemy' and b.kind=='barracks' and b.hp>0)
	if not bases.is_empty() and ai_training>=20. and alive('enemy').filter(func(u):return not u.has('camp') and not u.get('wild',false)).size()<30:
		var type=['spear','shield','archer','light_cavalry'][ai_serial%4]
		var cost: float=strategy.units[type].food
		var point=find_exit(bases[0])
		if ai_food>=cost and point!=Vector2.INF:
			ai_food-=cost;ai_training=0.;ai_serial+=1
			var u=spawn_person(type,'enemy',point)
			u.order='hold';u.soldiers[0].personal_order='hold';u.soldiers[0].reserve_ai=true
			# Move recruits to separate reserve slots without releasing an attack.
			var ids=[Vector2i(u.id,0)]
			Soldiers.command(self,ids,'move',Vector2(1100+(ai_serial%7)*40,650+(ai_serial%3)*45),-1,-1,[],true,'enemy')
	if elapsed>=next_wave:
		waves_sent+=1
		next_wave=elapsed+[95.,120.,105.][waves_sent%3]
		var reserves=alive('enemy').filter(func(u):return u.soldiers[0].get('reserve_ai',false))
		for u in reserves.slice(0,mini(reserves.size(),3+waves_sent)):
			u.soldiers[0].erase('reserve_ai');u.order='auto';Soldiers.automate(self,u,true)
		if not reserves.is_empty():report='斥候报告：敌军开始向城镇进军'

func building_cost(kind: String) -> float:return strategy.buildings[kind].wood*(.9 if town_level>=4 else 1.)
func unit_cost(type: String) -> Dictionary:
	var d: Dictionary=strategy.units[type]
	return {'food':d.food,'wood':d.get('wood',0),'iron':d.get('iron',0)}
func town_cost() -> Dictionary:return {'food':0,'wood':200*(town_level+1),'iron':200*(town_level+1)}
func upgrade_town():
	town_level=mini(5,town_level+1)
	for u in alive('ally'):apply_level(u)
	for b in buildings:
		if b.side!='ally':continue
		var ratio: float=b.hp/b.max_hp
		b.max_hp=strategy.buildings[b.kind].hp*(1.+.2*mini(town_level-1,3));b.hp=b.max_hp*ratio
func gather_rate(kind: String) -> float:
	return {'fruit':.6,'berries':1.1,'sheep':1.3,'wolf':1.3,'deer':1.5,'boar':1.8,'large_iron':1.5}.get(kind,1.)
func set_rally(b: Dictionary,point: Vector2) -> bool:
	if b.side!='ally' or b.hp<=0 or not strategy.units.values().any(func(d):return d.producer==b.kind):return false
	var start=find_exit(b)
	if start==Vector2.INF or terrain.leg('legion',start,point).is_empty():report='无法到达集结点';return false
	b.rally=point;report='集结点已设置';return true
func produce(b: Dictionary,type: String) -> bool:
	var point=find_exit(b)
	if point==Vector2.INF:return false
	var u=spawn_person(type,'ally',point)
	if b.has('rally'):Soldiers.command(self,[Vector2i(u.id,0)],'move',b.rally)
	return true
func unit_visible(u: Dictionary) -> bool:return u.side=='ally' or world.visible(u.pos)
func can_detect(observer: Dictionary,target: Dictionary) -> bool:
	return unit_visible(target) if observer.side=='ally' else observer.pos.distance_to(target.pos)<=600.
func current_order(u: Dictionary) -> Dictionary:
	var a: Dictionary=u.soldiers[0]
	if a.has('job'):
		var job: Dictionary=a.job
		var names={'gather':'采集','build':'建造','repair_building':'修复建筑','repair_siege':'修复攻城器','siege':'攻击建筑','embark':'登上攻城塔'}
		var point: Vector2=resources[job.id].pos if job.kind=='gather' else buildings[job.id].pos if job.kind in ['build','repair_building','siege'] else u.pos
		return {'name':names.get(job.kind,job.kind),'point':point,'attack':job.kind=='siege'}
	if a.has('charge_run'):return {'name':'冲锋','point':a.charge_run.goal,'attack':true}
	if a.has('form_left') and a.has('formation_revision'):return {'name':'切换阵型','point':a.form_goal,'attack':false}
	var order: String=a.get('personal_order','idle')
	var target=units.filter(func(other):return other.id==a.get('target_id',-1) and other.hp>0 and can_detect(u,other))
	if not target.is_empty():return {'name':'攻击','point':target[0].pos,'attack':true}
	if order in ['move','attack_move'] and not a.get('path',[]).is_empty():return {'name':'攻击移动' if order=='attack_move' else '移动','point':a.path.back(),'attack':order=='attack_move'}
	return {'name':'待命' if order in ['idle','hold'] else '自动作战','point':u.pos,'attack':false}
func unit_numbers(u: Dictionary) -> Dictionary:
	var d: Dictionary=strategy.units[u.unit_type]
	var armor=level-1 if u.side=='ally' else 0
	if u.unit_type=='villager' and u.side=='ally' and town_level>=3:armor+=2
	return {'hp':u.hp,'max_hp':u.max_hp,'damage':u.combat_stats.damage,'melee':d.armor_melee+armor,'ranged':d.armor_ranged+armor,'interval':u.combat_stats.interval}

func town_upgrade_description() -> String:
	return {1:'二级：村民生产速度与生命 +30%；所有建筑生命 +20%。',2:'三级：村民生产速度与生命再 +30%；村民攻击 +5、近远程护甲 +2；建筑生命再 +20%。',3:'四级：村民生产速度与生命再 +30%；建筑生命再 +20%；建筑木材成本 -10%；研发速度 +30%；军队移速 +10%。',4:'五级：解锁精锐骑兵；军队生命 +10%；脱战回复 2生命/秒；满血军队伤害 +5%。'}.get(town_level,'城镇已达最高等级')
