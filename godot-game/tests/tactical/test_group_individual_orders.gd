extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture():
	var r=Battle.new();r.units.clear()
	r.spawn('legion','ally',Vector2(1000,1300));r.spawn('legion','enemy',Vector2(1800,300))
	for u in r.units:u.order='hold'
	r.start();return r
func feet(r,u):
	var result=[]
	for slot in u.soldiers.size():result.append(r.projection.affine_inverse()*r.Soldiers.point(r,u,slot))
	return result
func tick(r,n):
	for i in n:r.step(1./60)
func run():
	var r=fixture();var u=r.units[0];var before=feet(r,u)
	check(r.command([u.id],'move',Vector2(1000,1000)),'Regiment selection expands into personal move orders')
	check(feet(r,u)==before and u.soldiers.all(func(a):return a.personal_order=='move'),'Command changes neither current feet nor frontage')
	var frozen=u.soldiers.duplicate(true);r.step(0.)
	check(frozen==u.soldiers,'Paused group movement leaves every actor unchanged')
	tick(r,30);var stopped=feet(r,u)
	r.command([u.id],'hold',Vector2.ZERO);tick(r,60)
	check(feet(r,u)==stopped,'Group H stops people where they are without hidden regroup movement')
	check(r.march_route(u.id,[Vector2(1000,1100)],Vector2(1000,900)),'Group route accepts individual clearance and intermediate stops')
	var seen=true
	for i in u.soldiers.size():seen=seen and u.soldiers[i].path.size()>=2
	check(seen,'Each living person receives the intermediate route')
	tick(r,420)
	check(u.order=='idle' and u.pos.distance_to(Vector2(1000,900))<17.,'All people physically arrive and the summary centre follows them')
	var valid=u.soldiers.duplicate(true)
	check(not r.command([u.id],'move',Vector2(1,1)) and valid==u.soldiers,'A destination putting some feet out of bounds rejects the entire order')
	var q=fixture();var a=q.units[0];var start=feet(q,a)
	var rock=Rect2(q.projection*(start[0]+Vector2(0,-120))-Vector2(25,20),Vector2(50,40));q.terrain.ROCKS.append(rock)
	check(q.command([a.id],'move',Vector2(1000,1000)),'A rock in one lane produces per-person routes')
	var crossed=false;var separated=false
	for frame in 420:
		q.step(1./60)
		for p in feet(q,a):crossed=crossed or rock.has_point(q.projection*p)
		separated=separated or a.soldiers[0].position.x>start[0].x+10. or a.soldiers[0].position.x<start[0].x-10.
	check(not crossed and separated,'Blocked end detours while the far end advances; no foot crosses rock')
	check(a.order=='idle' and a.pos.distance_to(Vector2(1000,1000))<17.,'All detouring soldiers arrive without moving an invisible parent formation')
	var wall=fixture();var w=wall.units[0]
	check(wall.command_shield_line([w.id],Vector2(800,1100),Vector2(1200,1100)),'F lays out real individual shield slots')
	tick(wall,600)
	check(w.order=='hold' and w.soldiers.all(func(s):return s.shield_wall and s.heading.is_equal_approx(Vector2.UP) and absf(s.position.y-1100.)<3.),'Every shield reaches its slot and keeps the wall normal')
	var positions=feet(wall,w);var state=w.soldiers.duplicate(true)
	check(not wall.command_shield_line([w.id],Vector2(-200,1000),Vector2(100,1000)) and w.soldiers==state,'An out-of-bounds shield slot rejects F before changing any soldier')
	wall.command([w.id],'attack',wall.units[1].pos,wall.units[1].id)
	check(feet(wall,w)==positions and w.soldiers.all(func(s):return s.personal_order=='attack' and not s.shield_wall),'Group focus starts from actual wall positions and clears each shield stance')
	var mixed=fixture();mixed.spawn('medic','ally',Vector2(600,1300));var m=mixed.units.back();m.order='hold'
	check(mixed.command([mixed.units[0].id,m.id],'move',Vector2(800,1100)),'Mixed combat and local medic selection still accepts a move')
	tick(mixed,240)
	check(m.pos.y<1250 and mixed.units[0].soldiers[0].position.y<1250,'Medic extension and independent combat soldiers both execute the mixed command')
	print('Group individual orders: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
