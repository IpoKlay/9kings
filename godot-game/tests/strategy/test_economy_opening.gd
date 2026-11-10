extends SceneTree
const Battle=preload('res://scripts/strategy/battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _init():
	var r=Battle.new(false)
	check(r.phase=='battle','No deployment phase')
	check(r.alive('ally').size()==9 and r.alive('ally').filter(func(u):return u.unit_type=='villager').size()==5,'Only starting villagers')
	check(r.stock=={'food':10000.,'wood':10000.,'iron':10000.},'Starting resources preserved')
	var food: float=r.stock.food;r.advance_economy(30.)
	check(r.population()==9 and r.stock.food==food,'No invisible automatic villager purchases')
	check(not r.train('spear',0),'Town cannot train infantry')
	check(not r.train('villager',1),'Barracks cannot train villagers')
	check(not r.train('spear'),'Production requires a concrete selected building')
	var second=r.add_building('barracks',Vector2(2200,2600),true)
	check(r.train('spear',second.id),'Selected second barracks can train')
	check(r.buildings[1].queue.is_empty() and second.queue.is_empty() and r.units.back().pos.distance_to(second.pos)<170.,'No fallback to another barracks')
	var paid: float=r.stock.food
	r.train('villager',0)
	check(r.cancel_training(0,0) and r.stock.food==paid,'Cancel returns exact cost')
	check(r.train('villager',0),'Town queue accepts villager')
	r.advance_economy(9.)
	check(r.population()==11 and r.buildings[0].queue.is_empty(),'Town finishes production')
	check(not r.research('promotion',0),'Research requires correct selected building')
	r.stock={'food':1000.,'wood':1000.,'iron':1000.}
	check(r.research('promotion',second.id),'Research binds to selected barracks')
	second.hp=0;r.advance_economy(21.)
	check(r.level==1 and r.research_queue.is_empty(),'Destroyed research source cannot complete in another building')
	var villager=r.alive('ally')[0]
	check(r.build('house',Vector2(1330,2750),[Vector2i(villager.id,0)]),'Villager is a valid builder')
	var home=r.buildings[0];var hostile=r.buildings.filter(func(b):return b.side=='enemy' and b.kind=='town')[0]
	# AI recruits before raids, pays for units, and is not gated on a three-wave script.
	for i in 8:r.advance_ai(20.)
	check(r.alive('enemy').size()>0,'AI produces units over time')
	check(r.alive('enemy').filter(func(u):return not u.has('camp') and not u.get('wild',false)).all(func(u):return u.order=='hold'),'Recruits wait during opening grace')
	r.elapsed=180.;r.advance_ai(.1)
	check(r.waves_sent==1 and r.alive('enemy').any(func(u):return u.order=='auto'),'First raid releases recruited troops')
	for i in 4:
		r.elapsed=r.next_wave;r.advance_ai(60.)
	check(r.waves_sent==5 and r.phase=='battle','AI continues beyond three attacks')
	var count=r.units.size()
	for b in r.buildings:
		if b.side=='enemy' and b.kind=='barracks':b.hp=0
	r.advance_ai(120.)
	check(r.units.size()==count,'Destroying AI barracks stops recruitment')
	hostile.hp=0;r.resolve_battle(0.)
	check(r.phase=='victory','Destroying enemy town wins without fixed wave requirement')
	var lose=Battle.new(false);lose.buildings[0].hp=0;lose.resolve_battle(0)
	check(lose.phase=='defeat','Losing own town ends game')
	print('ECONOMY OPENING CHECKS=',checks,' FAILURES=',failures)
	quit(1 if failures else 0)
