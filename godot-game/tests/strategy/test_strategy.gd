extends SceneTree
const Battle=preload('res://scripts/strategy/battle.gd')
var failures=0
var checks=0
func check(ok: bool,text: String):
	checks+=1
	if not ok:failures+=1;push_error(text)
func _init():
	var r=Battle.new(false)
	check(r.stock=={'food':100.,'wood':100.,'iron':100.},'Starting resources')
	check(r.building_ready('town') and r.building_ready('barracks'),'Starting buildings')
	check(r.units.all(func(u):return u.soldiers.size()==1),'Independent selectable bodies')
	check(r.Layout.rows(6)==[3,3] and r.Layout.rows(7)==[4,3] and r.Layout.rows(8)==[4,4] and r.Layout.rows(9)==[5,4] and r.Layout.rows(10)==[5,5],'Balanced team rows')
	check(r.Layout.rows(11)==[4,4,3],'More than ten teams')
	check(r.damage_amount(100,[.2,.3],[.2,.1],5)==100.,'Additive modifiers and flat armor')
	check(r.damage_amount(10,[],[],20)==0.,'No negative healing damage')
	r.start()
	var spear=r.alive('ally').filter(func(u):return u.unit_type=='spear')[0]
	var chosen=[Vector2i(spear.id,0)]
	check(r.Soldiers.command(r,chosen,'move',Vector2(1600,1800)),'Individual move')
	for i in 120:r.step(1./60)
	check(spear.pos.distance_to(Vector2(1250,2260))>20.,'Actual soldier walks')
	var team=[]
	for i in 43:
		var u=r.spawn_person('shield','ally',Vector2(800+i*12,1800))
		u.soldiers[0].formation='wedge' if i<24 else 'default'
		team.append(Vector2i(u.id,0))
	var selected=r.Soldiers.members(r,team)
	var plan=r.Layout.plan(r,selected,Vector2(1600,1650),[])
	check(plan.size()==43,'43 people have paths')
	if plan.size()==43:
		var counts={}
		for path in plan:counts[path.team]=counts.get(path.team,0)+1
		check(counts.values()==[21,21,1],'21 person cap and overflow')
		check(plan.all(func(path):return path.formation=='wedge'),'Majority formation by people')
	check(not r.Soldiers.command(r,chosen,'move',r.cliffs[0].get_center()),'Cliffs reject orders')
	var villager=r.alive('ally').filter(func(u):return u.unit_type=='villager')[0]
	villager.pos=r.resources[1].pos+Vector2(60,0);villager.soldiers[0].position=villager.pos
	check(r.gathering([Vector2i(villager.id,0)],1),'Fruit gathering accepted')
	var food: float=r.stock.food;var wood: float=r.stock.wood
	r.advance_economy(1.)
	check(r.stock.food>food and r.stock.wood>wood,'Fruit yields food and wood')
	r.stock={'food':10000.,'wood':10000.,'iron':10000.}
	var engineer=r.alive('ally').filter(func(u):return u.unit_type=='engineer')[0]
	var workers=[Vector2i(engineer.id,0)]
	check(not r.build('range',Vector2(400,2400),workers),'Range requires barracks influence')
	check(r.build('range',Vector2(2030,2520),workers),'Range within barracks influence')
	var building: Dictionary=r.buildings.back()
	engineer.pos=building.pos+Vector2(80,0);engineer.soldiers[0].position=engineer.pos
	r.advance_economy(15.)
	check(building.remaining==0 and r.building_ready('range'),'Engineer completes construction')
	check(r.train('archer'),'Training queue accepts ranged unit')
	var count=r.units.size()
	# Housing needed because the layout fixture deliberately exceeded the starting cap.
	for i in 5:r.add_building('house',Vector2(100+i*100,3000),true)
	r.advance_economy(10.)
	check(r.units.size()>count,'Production spawns actual units')
	check(r.research('promotion'),'Promotion research starts')
	var base_hp: float=spear.max_hp
	r.advance_economy(21.)
	check(r.level==2 and is_equal_approx(spear.max_hp,base_hp*1.1),'Promotion raises base HP ten percent')
	check(r.promotion_cost().food==100,'Promotion cost doubles')
	var fresh=r.spawn_person('spear','ally',Vector2(1800,1800))
	check(fresh.max_hp==spear.max_hp and fresh.combat_stats.damage==spear.combat_stats.damage,'Existing and new units share upgraded stats')
	spear.soldiers[0].attack_age=10.;spear.soldiers[0].last_combat=-100.
	spear.pos=Vector2(1000,1000);spear.soldiers[0].position=spear.pos
	check(r.set_formation(chosen,'ring'),'Out of combat formation starts')
	check(not spear.soldiers[0].formation_ready,'No construction buff')
	for i in 6:r.step(1./60)
	check(spear.soldiers[0].get('form_left',0.)>4.9,'Hills slow spear formation')
	r.hurt(spear,5.,'sword',0.,0)
	check(not spear.soldiers[0].has('form_left') and not spear.soldiers[0].formation_ready,'Combat interrupts construction')
	check(not r.set_formation(chosen,'wedge'),'Cannot switch while fighting')
	var town=r.buildings[0];town.hp=0;r.resolve_battle(0)
	check(r.phase=='defeat','Town destruction loses battle')
	print('STRATEGY CHECKS=',checks,' FAILURES=',failures)
	quit(1 if failures else 0)
