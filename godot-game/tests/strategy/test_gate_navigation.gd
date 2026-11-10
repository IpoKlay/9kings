extends SceneTree
const Battle=preload('res://scripts/strategy/battle.gd')
var failures=0
var checks=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _init():
	var r=Battle.new(false);var ids=[]
	# Isolate pathing from combat and wave recruitment.
	for u in r.units:u.hp=0;u.soldiers[0].hp=0
	for camp in r.world.camps:camp.claimed=true
	for b in r.buildings:
		if b.side=='enemy' and b.kind=='outpost':b.hp=0
	r.next_wave=10000.;r.ai_training=-10000.
	for i in 63:
		var u=r.spawn_person('shield','ally',Vector2(1240+(i%9)*42,2240+(i/9)*32));ids.append(Vector2i(u.id,0))
	var t=Time.get_ticks_usec()
	check(r.Soldiers.command(r,ids,'move',Vector2(1450,2030)),'63-person order near wall no longer rejected')
	var command_ms=(Time.get_ticks_usec()-t)/1000.
	var builds=r.terrain.graph_builds
	check(builds<=2,'Navigation graph shared across units')
	check(r.terrain.ROCKS.size()<r.buildings.size(),'Contiguous cardinal wall segments merged without closing gates')
	for i in 3600:r.step(1./60);r.events.clear()
	var crossed=r.alive('ally').filter(func(u):return u.pos.y<2060.).size()
	check(crossed==63,'All selected units physically cross north gate')
	var settled=r.alive('ally').filter(func(u):return u.soldiers[0].get('path',[]).is_empty()).size()
	check(settled==63,'All units complete their orders after passing gate')
	check(r.terrain.graph_builds==builds,'Moving units reuse static graph')
	var displaced=r.alive('ally')[0];var actor=displaced.soldiers[0];var goal: Vector2=actor.form_goal
	actor.position+=Vector2(0,-45);displaced.pos=actor.position
	for i in 180:r.step(1./60);r.events.clear()
	check(actor.position.distance_to(goal)<8.,'Soldier pushed away after arrival returns to its slot')
	r.Soldiers.command(r,[Vector2i(displaced.id,0)],'hold',displaced.pos)
	check(not actor.has('form_goal'),'New hold cancels previous slot recovery')
	var north=r.buildings.filter(func(b):return b.kind=='gate' and b.pos.y<r.world.CENTER.y)[0]
	north.open=false;r.rebuild_obstacles()
	check(not r.terrain.clear_segment(r.Soldiers.navigator(r,'guard',r.alive('ally')[0]),north.pos-Vector2(0,70),north.pos+Vector2(0,70)),'Closed gate remains physically blocked')
	north.open=true;r.rebuild_obstacles()
	check(r.terrain.clear_segment(r.Soldiers.navigator(r,'guard',r.alive('ally')[0]),north.pos-Vector2(0,70),north.pos+Vector2(0,70)),'Opening gate invalidates obstacle cache')
	check(is_equal_approx(r.strategy.units.villager.speed,47.5) and is_equal_approx(r.strategy.units.shield.speed,37.5) and is_equal_approx(r.strategy.units.light_cavalry.speed,77.5),'Movement speed halved across worker, infantry, cavalry')
	check(r.alive('ally')[0].individual_stats.unit_size==10.,'Body radius modestly enlarged from 9 to 10')
	print('GATE CHECKS=',checks,' FAILURES=',failures,' crossed=',crossed,' settled=',settled,' order_ms=',command_ms)
	quit(1 if failures else 0)
