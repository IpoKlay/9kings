extends SceneTree
const Battle=preload('res://scripts/strategy/battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _init():
	var r=Battle.new(false);r.start();r.stock={'food':10000.,'wood':10000.,'iron':10000.}
	for row in [['gate',1500,650],['wall',1700,650],['fortress',1300,380]]:
		var structure=r.add_building(row[0],Vector2(row[1],row[2]),true);structure.side='enemy'
	var a=r.spawn_person('shield','ally',Vector2(1500,1500))
	var b=r.spawn_person('shield','enemy',Vector2(1550,1500))
	b.max_hp=1000.;b.hp=1000.;b.soldier_max_hp=1000.;b.soldier_hp=1000.;b.soldiers[0].max_hp=1000.;b.soldiers[0].hp=1000.
	a.soldiers[0].formation='default';b.soldiers[0].formation='default'
	r.researches.military=true;r.direction='military'
	var dealt=r.hurt(b,100.,'sword',0.,0,a.id,0)
	check(is_equal_approx(dealt,130.),'Military bonuses are additive before flat armor')
	b.hp=b.max_hp;b.soldier_hp=b.hp;b.soldiers[0].hp=b.max_hp;b.soldiers[0].shield_raised=true
	dealt=r.hurt(b,100.,'sword',0.,0,a.id,0)
	check(is_equal_approx(dealt,49.),'Shield reduction follows attack bonus, before armor')
	var cavalry=r.spawn_person('light_cavalry','ally',Vector2(900,1000))
	b.soldiers[0].shield_raised=false;b.hp=b.max_hp;b.soldier_hp=b.hp;b.soldiers[0].hp=b.max_hp
	dealt=r.hurt(b,100.,'sword',0.,0,cavalry.id,0)
	check(is_equal_approx(dealt,100.),'Hill cavalry penalty is additive with buffs')
	cavalry.soldiers[0].formation='wedge';cavalry.soldiers[0].heading=Vector2.LEFT
	check(not r.Charges.issue(r,[Vector2i(cavalry.id,0)],cavalry.pos+Vector2(200,0)),'Cavalry wedge needs facing alignment')
	var archer=r.spawn_person('archer','ally',Vector2(1600,1200))
	archer.soldiers[0].formation='dense'
	check(r.arrow_rain([Vector2i(archer.id,0)],Vector2(1700,1200)),'Arrow rain fires')
	check(not r.arrow_rain([Vector2i(archer.id,0)],Vector2(1700,1200)),'Arrow rain cooldown enforced')
	check(not r.train('elite_cavalry'),'Elite cavalry locked before town level five')
	var gate=r.buildings.filter(func(item):return item.side=='enemy' and item.kind=='gate')[0]
	var ram=r.spawn_person('ram','ally',gate.pos+Vector2(0,100))
	check(r.assault_building([Vector2i(ram.id,0)],gate),'Ram accepts enemy gate')
	var before: float=gate.hp
	r.advance_siege(1.)
	check(gate.hp<before,'Ram damages gate')
	var fort=r.buildings.filter(func(item):return item.kind=='fortress')[0]
	check(not r.assault_building([Vector2i(ram.id,0)],fort),'Ram rejects non-gate')
	gate.hp=1.;ram.soldiers[0].cooldown=0.;r.advance_siege(1.)
	check(gate.hp==0. and not r.terrain.ROCKS.any(func(rect):return rect.has_point(gate.pos)),'Destroyed gate removes obstruction')
	var engineer=r.spawn_person('engineer','ally',ram.pos+Vector2(40,0))
	r.hurt(ram,100.,'sword',0.,0)
	check(r.interact_unit([Vector2i(engineer.id,0)],ram.pos),'Engineer can repair siege machine')
	before=ram.hp;r.advance_siege(1.)
	check(ram.hp>before,'Siege repair restores real health')
	var wall=r.buildings.filter(func(item):return item.side=='enemy' and item.kind=='wall')[0]
	var tower=r.spawn_person('tower','ally',wall.pos+Vector2(0,100))
	var passenger=r.spawn_person('spear','ally',tower.pos+Vector2(40,0))
	check(r.interact_unit([Vector2i(passenger.id,0)],tower.pos),'Infantry can board tower')
	r.advance_siege(1.)
	check(passenger.escaped and passenger.soldiers[0].get('aboard',-1)==tower.id,'Boarded infantry is carried')
	check(r.assault_building([Vector2i(tower.id,0)],wall),'Tower approaches wall')
	r.advance_siege(1.)
	check(not passenger.escaped and passenger.soldiers[0].get('wall_top',-1)==wall.id,'Tower unloads onto wall')
	var nav=r.Soldiers.navigator(r,passenger.kind,passenger)
	check(r.terrain.clear_segment(nav,wall.pos,wall.pos),'Personal wall navigation layer')
	check(not r.terrain.clear_segment('legion',wall.pos,wall.pos),'Other troops still cannot walk through wall')
	r.waves_sent=3
	for enemy in r.alive('enemy'):
		enemy.hp=0.;enemy.soldier_hp=0.;enemy.soldiers[0].hp=0.;enemy.soldiers[0].death_state=2
	for building in r.buildings:
		if building.side=='enemy' and building.kind=='town':building.hp=0.
	r.resolve_battle(0.)
	check(r.phase=='victory','Enemy town destruction resolves victory')
	print('STRATEGY COMBAT CHECKS=',checks,' FAILURES=',failures)
	quit(1 if failures else 0)
