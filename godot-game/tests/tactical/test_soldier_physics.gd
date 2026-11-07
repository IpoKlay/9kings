extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
const Physics=preload('res://scripts/tactical/soldier_physics.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func row(id: int,position: Vector2,side='ally'):
	return {'unit':{'id':id,'side':side,'kind':'legion','stun':0.,'petrified':0.,'soldiers':[{'hp':100.,'heading':Vector2.RIGHT}]},'slot':0,'radius':9.,'point':position}
func run():
	var r=Battle.new();var a=row(0,Vector2.ZERO);var b=row(1,Vector2(18,0))
	check(Physics.pair_shift(r,a,b,1./30).is_equal_approx(Vector2(-1.0185185185,0)),'Friendly contact at18 produces the public-kernel1.0185185 displacement per person')
	b.unit.side='enemy'
	check(Physics.pair_shift(r,a,b,1./30).is_equal_approx(Vector2(-.3155522164,0)),'Ordinary opposing contact is weaker at the same distance')
	b.point=Vector2(20,0)
	check(Physics.pair_shift(r,a,b,1./30)==Vector2.ZERO,'Opposing contact stops outside1.1 times the combined body radius')
	b.unit.side='ally'
	check(Physics.pair_shift(r,a,b,1./30).length()>0.,'Friendly spacing still acts at20 within the1.2 radius')
	b.unit.side='enemy';b.point=Vector2(24,0);a.unit.soldiers[0].shield_wall=true
	check(Physics.pair_shift(r,a,b,1./30).is_equal_approx(Vector2(-1.6975308642,0)),'A forward-facing shield extends pressure to1.6 radii with strength200')
	b.point=Vector2(-24,0)
	check(Physics.pair_shift(r,a,b,1./30)==Vector2.ZERO,'Shield rear does not acquire the frontal pressure bonus')
	b.point=Vector2(24,0)
	var expected=Physics.pair_shift(r,a,b,1./30)
	a.point=a.point.rotated(.7);b.point=b.point.rotated(.7);a.unit.soldiers[0].heading=Vector2.RIGHT.rotated(.7)
	check(Physics.pair_shift(r,a,b,1./30).distance_to(expected.rotated(.7))<.00001,'Rotating both positions and the shield normal rotates the same pressure')
	b.unit.side='ally';b.unit.soldiers[0].shield_wall=true;b.point=Vector2(1,0)
	check(Physics.pair_shift(r,a,b,1./30)==Vector2.ZERO,'Friendly shield formations do not repel each other, even across wall IDs')
	a.unit.soldiers[0].shield_wall=false;b.unit.soldiers[0].shield_wall=false
	check(absf(Physics.pair_shift(r,a,b,1./30).length()-1.0963525709)<.00001,'Deep compression uses the additional inner-radius multiplier')
	check(Physics.pair_shift(r,a,b,10.).length()<=16.00001,'Large-time non-shield pair displacement is capped at16')
	b.point=Vector2.ZERO;r.repulsion_seed=12345
	var jitter=Physics.pair_shift(r,a,b,1./30);r.repulsion_seed=12345
	check(jitter!=Vector2.ZERO and jitter==Physics.pair_shift(r,a,b,1./30),'Coincident feet separate with the public two-step random generator and repeatable initial seed')
	var rows=[]
	for i in 48:rows.append(row(i,Vector2(63.+(i%8)*32.,63.+(i/8)*32.)))
	r.Soldiers.prepare_neighbours(r,rows,1./30)
	var covered=true
	for x in rows:
		for y in rows:
			if x!=y and x.point.distance_to(y.point)<(x.radius+y.radius)*1.6:covered=covered and y in x.neighbours
	for x in rows:x.erase('neighbours')
	check(covered,'Spatial broad phase includes every potentially active shield-pressure pair at cell boundaries')
	r.units.clear();r.spawn('legion','ally',Vector2(1000,1200));r.spawn('legion','enemy',Vector2(1800,200))
	for u in r.units:u.order='hold'
	r.start();var u=r.units[0];r.Charges.detach(r,u,0);var s=u.soldiers[0]
	s.impulse=Vector2(.51,100.);var start: Vector2=s.position
	rows=[{'unit':u,'slot':0,'radius':9.,'point':s.position}]
	Physics.integrate(r,rows,1./60)
	check(s.position.distance_to(start+Vector2(.51,100.)/60.)<.001 and s.impulse==Vector2(0,85),'Knockback integrates before0.85 decay and clears each sub0.5 component separately')
	s.erase('impulse');s.shield_wall=true;s.wall_heading=Vector2.UP;s.personal_order='hold'
	start=s.position
	u.contact_motion={'start':r.elapsed-.1,'rise':.05,'hold':1.,'recover':.5,'offsets':{0:Vector3(10,0,0)}}
	for frame in 10:r.step(1./60)
	check(s.position==start and r.Contact.body_shift(u,0,r.elapsed).x>9.,'Visible hit recoil stays visible without accumulating into the anchored physical foot')
	var frozen=r.repulsion_time;r.step(0.)
	check(r.repulsion_time==frozen,'Pause does not advance repulsion cadence')
	var fresh=Battle.new()
	check(fresh.repulsion_time==0. and fresh.repulsion_seed==12345,'New battle resets cadence and random seed')
	print('Soldier physics: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
