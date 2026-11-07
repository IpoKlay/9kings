extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture(kind='legion',distance=29.):
	var r=Battle.new();r.units.clear();r.spawn(kind,'ally',Vector2(1000,1200));r.spawn('legion','enemy',Vector2(1000,1200-distance))
	for u in r.units:u.order='hold'
	r.start()
	for u in r.units:
		for i in u.soldiers.size():
			u.soldiers[i].hp=u.soldiers[i].max_hp if i==0 else 0.
			r.Charges.detach(r,u,i);u.soldiers[i].position=u.pos;u.soldiers[i].personal_order='hold';u.soldiers[i].cooldown=60.
		r.Soldiers.total(u)
	var a=r.units[0];a.soldiers[0].cooldown=0.
	r.Soldiers.command(r,[Vector2i(a.id,0)],'attack',r.units[1].pos,r.units[1].id,0)
	return r
func tick(r,n=1):
	for i in n:r.step(1./60.)
func run():
	var r=fixture();var a=r.units[0];var b=r.units[1];var s=a.soldiers[0]
	s.velocity=Vector2(0,-80.);var origin: Vector2=s.position
	tick(r)
	check(s.has('attack_engaged') and not s.get('attack_pending',false),'Arrival enters attack state without starting windup')
	check(s.velocity==Vector2(0,-80.) and s.position.y<origin.y-1.,'Entry tick preserves velocity through unified integration')
	tick(r)
	check(s.velocity==Vector2(0,-60.) and not s.get('attack_pending',false),'Following attack-state tick begins per-axis braking')
	tick(r,3)
	check(s.attack_age==0. and s.get('attack_pending',false),'Swing begins after actual braking reaches speed below5')
	var snapshot=s.duplicate(true);r.step(0.)
	check(s==snapshot,'Paused entry/recovery does not consume a state step')
	s.velocity=Vector2(0,-30.);b.soldiers[0].position=s.position+Vector2(0,-80.)
	tick(r)
	check(not s.has('attack_engaged') and s.velocity==Vector2(0,-30.),'Leash exit changes to pursuit without same-tick acceleration')
	tick(r)
	check(s.velocity.y < -30.,'Pursuit accelerates on the next simulation step')
	r=fixture('archer',300.);s=r.units[0].soldiers[0];tick(r)
	check(s.has('attack_engaged') and not s.get('attack_pending',false),'Directed archer attack also enters before windup')
	tick(r)
	check(s.attack_age==0.,'Ranged attack starts on the next state step')
	r=fixture();a=r.units[0];s=a.soldiers[0];tick(r)
	r.Soldiers.command(r,[Vector2i(a.id,0)],'hold',a.pos);s.aggro_timer=.1;tick(r)
	check(s.attack_age==0.,'H still attacks in place without the pursuit transition')
	r=fixture('cavalry');a=r.units[0];s=a.soldiers[0];tick(r)
	r.Charges.issue(r,[Vector2i(a.id,0)],a.pos+Vector2(300,0))
	check(not s.has('attack_engaged'),'Starting C clears the previous attack phase')
	s.attack_engaged=Vector2i(r.units[1].id,0);r.Charges.finish(r,a,s,'goal')
	check(not s.has('attack_engaged'),'Finishing C returns through pursuit instead of inheriting attack phase')
	print('Attack entry: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
