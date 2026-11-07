extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
const Physics=preload('res://scripts/tactical/soldier_physics.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture(kind='legion',other='legion',distance=29.):
	var r=Battle.new();r.units.clear();r.spawn(kind,'ally',Vector2(1000,1200));r.spawn(other,'enemy',Vector2(1000,1200-distance))
	for u in r.units:u.order='hold'
	r.start()
	for u in r.units:
		for i in u.soldiers.size():
			u.soldiers[i].hp=u.soldiers[i].max_hp if i==0 else 0.
			r.Charges.detach(r,u,i);u.soldiers[i].position=u.pos;u.soldiers[i].personal_order='hold';u.soldiers[i].cooldown=60.
		r.Soldiers.total(u)
	return r
func row(u):return {'unit':u,'slot':0,'radius':9.,'point':u.soldiers[0].position}
func run():
	var r=fixture();var a=r.units[0];var s=a.soldiers[0];var start: Vector2=s.position
	s.velocity=Vector2(50,0);s.impulse=Vector2(-50,100);var rows=[row(a)]
	Physics.integrate(r,rows,.01)
	check(s.position.is_equal_approx(start+Vector2(0,1)),'Opposing normal and knockback X velocities cancel before one displacement')
	check(s.velocity==Vector2(50,0) and s.impulse.is_equal_approx(Vector2(-50,100)*pow(.85,.6)),'Normal velocity persists while only knockback decays')
	check(rows[0].point==s.position,'Collision rows see the newly integrated actual foot')
	s.velocity=Vector2(1000,0);s.erase('impulse');start=s.position;Physics.integrate(r,rows,.01)
	check(s.position.is_equal_approx(start+Vector2(1.4,0)),'Ordinary speed cap is base80 plus60 before integration')
	s.shield_wall=true;s.velocity=Vector2(1000,0);start=s.position;Physics.integrate(r,rows,.01)
	check(s.position.is_equal_approx(start+Vector2(1.1,0)),'Shield speed cap is110')
	a.stun=1.;s.impulse=Vector2(100,0);start=s.position;Physics.integrate(r,rows,.01)
	check(s.position==start and s.impulse==Vector2(100,0),'Frozen units neither integrate nor decay knockback')
	r=fixture();a=r.units[0];var b=r.units[1];s=a.soldiers[0]
	r.hurt(b,b.hp-10.,'',0.,0);r.hurt(a,a.hp-10.,'',0.,0)
	s.target_id=b.id;s.target_slot=0;s.attack_age=.43;s.attack_pending=true
	b.soldiers[0].charge_run={'goal':b.pos+Vector2(0,400),'age':0.,'duration':3.,'velocity':Vector2(0,240),'penalty':0.,'hits':[],'speed':240.}
	b.soldiers[0].velocity=Vector2(0,240);b.soldiers[0].personal_order='charge'
	r.step(1./60)
	check(b.hp==0. and a.hp==0.,'Earlier lethal hit does not skip the later registered actors charge visit')
	check(r.events.filter(func(e):return e.get('personal_charge',false)).size()==1,'Terminal charge is delivered once before source registration is collected')
	r=fixture('archer','legion',300.);a=r.units[0];s=a.soldiers[0];b=r.units[1];start=s.position
	s.target_id=b.id;s.target_slot=0;s.attack_age=.59;s.attack_pending=true;s.velocity=Vector2(60,0)
	r.step(1./60)
	check(r.volleys.size()==1 and r.volleys[0].from==start,'Projectile is released at pre-integration position')
	check(s.position.x>start.x,'Shooter braking movement occurs after its release')
	r=fixture('cavalry','legion',30.);a=r.units[0];b=r.units[1];start=b.soldiers[0].position
	r.Charges.issue(r,[Vector2i(a.id,0)],a.pos+Vector2(0,-300));a.soldiers[0].charge_run.velocity=Vector2(0,-240);a.soldiers[0].velocity=Vector2(0,-240)
	r.step(1./60)
	check(b.soldiers[0].position.y<start.y-10.,'Fresh charge knockback moves its victim in this same simulation step')
	check(b.soldiers[0].impulse.is_equal_approx(Vector2(0,-663)),'Fresh780 impulse is integrated then multiplied by0.85 once')
	r=fixture('legion','legion',300.);a=r.units[0];s=a.soldiers[0];s.velocity=Vector2(80,0);start=s.position
	r.step(1./60)
	check(s.velocity==Vector2(60,0) and s.position.is_equal_approx(start+Vector2(1,0)),'H decelerates existing movement instead of instantly deleting it')
	var frozen=s.duplicate(true);r.step(0.)
	check(s==frozen,'Pause leaves combined movement and impulse state untouched')
	print('Integration order: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
