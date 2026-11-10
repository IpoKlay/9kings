extends SceneTree
const Battle=preload('res://scripts/strategy/battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _init():
	var r=Battle.new(false)
	check(r.stock=={'food':10000.,'wood':10000.,'iron':10000.},'Test stock 10000 each')
	check(r.alive('ally').size()==9,'Nine opening units')
	for pair in [['villager',5],['shield',2],['spear',2]]:check(r.alive('ally').filter(func(u):return u.unit_type==pair[0]).size()==pair[1],'Opening '+pair[0])
	check(r.buildings.filter(func(b):return b.side=='ally' and b.kind=='gate').size()==4,'Four gates')
	check(r.buildings.any(func(b):return b.side=='ally' and b.kind=='house') and r.population_cap()==55,'Initial house increases population')
	check(r.buildings.filter(func(b):return b.side=='ally' and b.kind=='farm').size()==3,'Three adjacent farms')
	var inner=r.resources.filter(func(v):return r.world.ring(v.pos)==1)
	check(inner.filter(func(v):return v.kind=='iron').size()==1,'Exactly one inner mine')
	check(inner.all(func(v):return v.kind in ['tree','iron','farm']),'Inner region contains only specified resources')
	for resource in r.resources:
		var zone=r.world.ring(resource.pos)
		check((zone==1 and resource.kind in ['tree','iron','farm']) or (zone==2 and resource.kind in ['berries','sheep','tree','iron']) or (zone==3 and resource.kind in ['deer','fruit','iron']) or (zone==4 and resource.kind in ['boar','large_iron']),'Resource assigned to correct ring')
	check(r.world.camps.size()==4,'Both camp types spawn twice')
	for c in r.world.camps:
		check(c.units.size()>=20 and c.units.size()<=25 and c.towers.size()==2 if c.strong else c.units.size()>=3 and c.units.size()<=8,'Camp defenders and towers')
	check(not r.world.visible(r.world.enemy_city) and not r.world.discovered(r.world.enemy_city),'Known enemy city starts without vision')
	check(r.world.visible(r.buildings[0].pos),'Own base visible')
	var scout=r.alive('ally')[0];var old: Vector2=scout.pos
	scout.pos=Vector2(500,500);scout.soldiers[0].position=scout.pos;r.world.refresh_sight(r)
	check(r.world.visible(scout.pos),'Scouting reveals new area')
	scout.pos=old;scout.soldiers[0].position=old;r.world.refresh_sight(r)
	check(r.world.discovered(Vector2(500,500)) and not r.world.visible(Vector2(500,500)),'Explored area becomes fogged')
	var b=r.buildings[1]
	check(r.set_rally(b,Vector2(1600,2250)),'Building accepts rally')
	var n=r.units.size();var food: float=r.stock.food;var wood: float=r.stock.wood;var iron: float=r.stock.iron
	check(r.train('shield',b.id) and r.units.size()==n+1 and b.queue.is_empty(),'Military production is immediate')
	check(r.stock.food==food-200 and r.stock.wood==wood-50 and r.stock.iron==iron-50,'All three unit costs charged')
	var recruit=r.units.back()
	check(recruit.soldiers[0].personal_order=='move' and not recruit.soldiers[0].path.is_empty(),'New recruit receives rally move order')
	var numbers=r.unit_numbers(recruit)
	check(numbers.max_hp==100 and numbers.damage==11 and numbers.melee==5 and numbers.ranged==7 and is_equal_approx(numbers.interval,1.1),'Shield numeric profile')
	check(r.train('villager',0) and r.buildings[0].queue.size()==1,'Villagers still use timed production')
	for pair in [['farm',1.],['tree',1.],['iron',1.],['berries',1.1],['sheep',1.3],['wolf',1.3],['deer',1.5],['boar',1.8],['fruit',.6]]:check(is_equal_approx(r.gather_rate(pair[0]),pair[1]),'Gather rate '+pair[0])
	check(r.gather_rate('large_iron')>r.gather_rate('iron'),'Large mine faster')
	var stable=r.add_building('stable',Vector2(1650,2650),true)
	check(not r.train('elite_cavalry',stable.id),'Elite locked before town 5')
	check(r.research('town_upgrade',0),'Town upgrade can be researched')
	r.advance_economy(20.)
	check(r.town_level==2 and is_equal_approx(scout.max_hp,78.) and r.buildings[0].max_hp==1440,'Town level 2 health bonuses')
	r.upgrade_town()
	check(scout.combat_stats.damage==5 and r.unit_numbers(scout).melee==2,'Town level 3 villagers armed')
	r.upgrade_town()
	check(is_equal_approx(r.building_cost('barracks'),90.) and is_equal_approx(r.personal_speed(recruit),1.1),'Town level 4 costs and army speed')
	r.upgrade_town()
	check(is_equal_approx(recruit.max_hp,110.) and r.train('elite_cavalry',stable.id),'Town level 5 army health and elite unlock')
	var wounded=recruit.soldiers[0];wounded.hp=50.;r.Soldiers.total(recruit);wounded.last_combat=-100.;wounded.attack_age=10.
	r.world.step(r,1.)
	check(is_equal_approx(wounded.hp,52.),'Out of combat regeneration 2/s')
	var camp=r.world.camps.filter(func(c):return c.strong)[0]
	for u in r.units:
		if u.id in camp.units:u.hp=0;u.soldiers[0].hp=0
	for id in camp.towers:r.buildings[id].hp=0
	var before: float=r.stock.food;var count=r.units.size()
	r.world.step(r,.1)
	check(camp.claimed and r.stock.food==before+600 and camp.reward_count>=5 and camp.reward_count<=8,'Strong camp grants resources and 5–8 allies')
	check(r.units.slice(count).all(func(u):return u.side=='ally' and u.unit_type in ['shield','spear','archer','light_cavalry']),'Rewards exclude elite cavalry')
	r.world.step(r,.1);check(r.stock.food==before+600,'Camp loot cannot repeat')
	var combat=Battle.new(false)
	var cavalry=combat.spawn_person('light_cavalry','ally',Vector2(1400,2300))
	var archer=combat.spawn_person('archer','enemy',Vector2(1440,2300))
	check(is_equal_approx(combat.hurt(archer,10.,'cavalry',0.,0,cavalry.id,0),15.),'Cavalry has flat +5 versus archers')
	archer.soldiers[0].hp=60.;combat.Soldiers.total(archer)
	cavalry.soldiers[0].charge_run={}
	check(is_equal_approx(combat.hurt(archer,10.,'cavalry',0.,0,cavalry.id,0),30.),'Cavalry charge is additive +100 percent damage')
	cavalry.soldiers[0].erase('charge_run')
	var spear=combat.spawn_person('spear','ally',Vector2(1500,2300))
	var horse=combat.spawn_person('light_cavalry','enemy',Vector2(1540,2300))
	check(is_equal_approx(combat.hurt(horse,15.,'spear',0.,0,spear.id,0),23.),'Spear +10 against cavalry before armor')
	var town=r.buildings.filter(func(v):return v.side=='enemy' and v.kind=='town')[0]
	scout.pos=town.pos+Vector2(90,0);r.world.refresh_sight(r)
	check(r.world.remembered_buildings.has(town.id),'Scouted buildings enter memory')
	scout.pos=old;r.world.refresh_sight(r);town.hp=0;r.world.refresh_sight(r)
	check(r.world.displayed_buildings(r).any(func(v):return v.id==town.id and v.hp>0),'Unseen destruction does not leak through fog')
	var gatherer=combat.alive('ally')[0]
	var fruit=combat.resources.filter(func(v):return v.kind=='fruit')[0]
	gatherer.pos=fruit.pos;gatherer.soldiers[0].position=fruit.pos
	gatherer.soldiers[0].job={'kind':'gather','id':combat.resources.find(fruit)}
	var start_food: float=combat.stock.food;var start_wood: float=combat.stock.wood
	combat.advance_economy(1.)
	check(is_equal_approx(combat.stock.food-start_food,.6) and is_equal_approx(combat.stock.wood-start_wood,.6),'Fruit grants 0.6 food and wood each simulated second')
	var before_queue: float=r.stock.food
	check(r.research('economy',2),'House research available after town upgrades')
	r.advance_economy(1.)
	check(is_equal_approx(r.research_queue.remaining,18.7),'Town 4 research speed is 30 percent faster')
	var new_house=r.add_building('house',Vector2(1500,2850),true)
	check(new_house.max_hp==800.,'New buildings inherit town health upgrades')
	print('EXPANSION CHECKS=',checks,' FAILURES=',failures)
	quit(1 if failures else 0)
