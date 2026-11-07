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
	r.spawn('legion','ally',Vector2(1000,1200));r.spawn('legion','enemy',Vector2(1800,200));r.spawn('legion','enemy',Vector2(1800,100))
	for u in r.units:u.order='hold'
	r.start();return r
func tick(r,n):
	for i in n:r.step(1./60)
func run():
	var r=fixture();var u=r.units[0];var id=Vector2i(u.id,0)
	var start: Vector2=r.projection.affine_inverse()*r.Soldiers.point(r,u,0)
	r.Soldiers.command(r,[id],'move',start+Vector2(0,-16))
	tick(r,20)
	check(u.soldiers[0].personal_order=='move' and u.soldiers[0].position==start,'Inside17 waits in the arrival region rather than declaring immediate arrival')
	var paused=u.soldiers[0].duplicate(true);r.step(0.)
	check(paused==u.soldiers[0],'Pause freezes settlement timer')
	tick(r,12)
	check(u.soldiers[0].personal_order=='idle','Half-second arrival enters idle rather than H holding')
	tick(r,30)
	check(u.soldiers[0].position==start,'Idle with no nearby enemy does not seek a distant army')
	var held: Vector2=r.projection.affine_inverse()*r.Soldiers.point(r,u,9)
	r.Soldiers.command(r,[Vector2i(u.id,9)],'hold',Vector2.ZERO)
	r.units[1].pos=Vector2(1000,1000)
	tick(r,60)
	check(u.soldiers[0].position.y<start.y-40. and u.soldiers[0].target_id>=0,'Arrived idle soldier independently acquires and approaches a nearby enemy')
	check(u.soldiers[9].position==held,'Explicit H soldier does not join the pursuit')
	var q=fixture();var a=q.units[0];var s=a.soldiers[0];id=Vector2i(a.id,0)
	start=q.projection.affine_inverse()*q.Soldiers.point(q,a,0)
	q.Soldiers.command(q,[id],'move',start+Vector2(0,-16));tick(q,20)
	s.position+=Vector2(0,4.);var accumulated: float=s.move_settle;tick(q,1)
	check(is_equal_approx(s.move_settle,accumulated),'Leaving inner17 but staying inside34 preserves accumulated settlement')
	s.position+=Vector2(0,30);tick(q,1)
	check(s.move_settle==0.,'Leaving outer34 resets accumulated settlement')
	q.Soldiers.command(q,[id],'move',start+Vector2(0,-16));tick(q,1)
	check(s.personal_order=='move' and s.move_settle==0.,'Replacement move does not inherit a previous arrival timer')
	q.Soldiers.command(q,[id],'attack',q.units[1].pos,q.units[1].id,0)
	q.units[1].soldiers[0].hp=0.;q.Soldiers.total(q.units[1]);tick(q,1)
	check(s.personal_order=='idle','An explicitly focused soldier dying returns pursuer to idle')
	var route=fixture();var v=route.units[0];id=Vector2i(v.id,0)
	start=route.projection.affine_inverse()*route.Soldiers.point(route,v,0)
	var via: Array[Vector2]=[start+Vector2(0,-90),start+Vector2(90,-90)]
	route.Soldiers.command(route,[id],'move',start+Vector2(90,-180),-1,-1,via)
	var intermediate=0;var reached=[]
	for frame in 360:
		route.step(1./60)
		var actor=v.soldiers[0]
		if actor.route_progress>intermediate:
			intermediate=actor.route_progress;reached.append(actor.position)
		if actor.personal_order=='idle':break
	check(reached.size()==3 and reached[0].distance_to(via[0])<2. and reached[1].distance_to(via[1])<2.,'Intermediate authored waypoints are still crossed before final settlement')
	check(v.soldiers[0].position.distance_to(start+Vector2(90,-180))<17.,'Final route point uses the reference arrival radius')
	print('Idle arrival: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
