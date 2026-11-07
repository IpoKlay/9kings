extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok:bool,note:String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture(first='legion',second='legion',distance=29.):
	var r=Battle.new();r.units.clear()
	for kind in r.config.types:
		r.config.types[kind].files=1;r.config.types[kind].hp=r.config.types[kind].get('individual',{}).get('hp',100.);r.contact_profiles[kind]=r.Contact.profile(kind,r.config.types[kind],true)
	r.spawn(first,'enemy',Vector2(1000,1000));r.spawn(second,'ally',Vector2(1000+distance,1000))
	for u in r.units:
		u.order='hold';r.Charges.detach(r,u,0);var s=u.soldiers[0];s.position=u.pos;s.personal_order='hold';s.cooldown=999.
	for k in r.reserve:r.reserve[k]=0
	r.start();r.enemy_director.active=false;return r
func row(u):return {'unit':u,'slot':0,'point':u.soldiers[0].position,'radius':9.}
func arm(u,target):
	var s=u.soldiers[0];s.attack_pending=true;s.attack_age=.43;s.target_id=target.id;s.target_slot=0
func run():
	var r=fixture();var u=r.units[0];var s=u.soldiers[0];r.hurt(u,1000.,'',0.,0)
	s.velocity=Vector2(80,0);s.impulse=Vector2(0,120);var start:Vector2=s.position
	r.Soldiers.Physics.integrate(r,[row(u)],1./60)
	check(s.position.is_equal_approx(start+Vector2(80,120)/60),'Zero-HP registration still integrates normal and knockback velocities')
	check(s.impulse==Vector2(0,102),'Lethal-step knockback still decays once')
	s.death_state=1;start=s.position;r.Soldiers.Physics.integrate(r,[row(u)],1./60)
	check(s.position==start,'Released registration cannot integrate again')
	r=fixture('legion','legion',18.);u=r.units[0];s=u.soldiers[0];r.hurt(u,1000.,'',0.,0);start=s.position
	r.Soldiers.Physics.repel(r,[row(u),row(r.units[1])],1./30)
	check(s.position.x<start.x and r.units[1].soldiers[0].position.x>1018.,'Registered zero-HP person participates in this physics-pair response')
	s.death_state=2;var other_start:Vector2=r.units[1].soldiers[0].position;start=s.position
	r.Soldiers.Physics.repel(r,[row(u),row(r.units[1])],1./30)
	check(s.position==start and r.units[1].soldiers[0].position==other_start,'Removed person cannot repel a living neighbour')
	# A late-slot cavalry hit is collected on the victim's next visit.
	r=fixture('legion','cavalry',30.);u=r.units[0];s=u.soldiers[0];var horse=r.units[1];r.hurt(u,u.hp-1.,'',0.,0)
	start=s.position;r.Charges.issue(r,[Vector2i(horse.id,0)],horse.pos+Vector2(-300,0));horse.soldiers[0].charge_run.velocity=Vector2(-240,0);horse.soldiers[0].velocity=Vector2(-240,0)
	r.step(1./60)
	check(s.hp==0 and s.death_state==0 and r.phase=='battle','Late lethal hit retains registration and defers elimination result')
	check(s.position.x<start.x-12. and s.get('impulse',Vector2.ZERO).x<0.,'Lethal charge pushes the victim in its actual hit step')
	check(r.casualties.is_empty() and r.Contact.drawable(u,0),'No premature corpse or invisible pending registration')
	check(r.Soldiers.identified_target(r,horse,0,u.id,0).is_empty(),'Visible dying actor is not a new living combat target')
	var lethal_foot:Vector2=s.position;r.step(1./60)
	check(s.death_state==2 and not r.Contact.drawable(u,0) and r.phase=='victory','Next death visit removes live drawing and permits elimination result')
	check(r.casualties.size()==1,'Actual death visit emits one corpse')
	var body=r.casualties[0]
	check(s.position.x<lethal_foot.x and body.ground_point==s.position and body.foot==r.projection*s.position,'Corpse starts at post-integration ground foot, not the initial hit position')
	check(body.step==2 and is_equal_approx(body.time,2./60),'Corpse age begins at actual death collection')
	check(body.attacker_point==horse.soldiers[0].position,'Death record reads still-registered attacker after movement')
	var saved=r.casualties.duplicate(true);r.step(0.);r.Soldiers.advance_personal(r,1./60);r.collect_casualties()
	check(r.casualties==saved,'Pause and repeated death passes do not duplicate corpse')
	horse.soldiers[0].position+=Vector2(100,100);check(r.casualties[0].foot==body.foot,'Corpse remains independent of survivor movement')
	# Earlier-slot lethal hit is collected after the victim's final state and integration.
	r=fixture();var killer=r.units[0];u=r.units[1];s=u.soldiers[0];r.hurt(u,u.hp-1.,'',0.,0);arm(killer,u)
	s.velocity=Vector2(80,0);s.impulse=Vector2(0,120);start=s.position;r.step(1./60)
	check(s.death_state==2 and r.casualties.size()==1,'Earlier lethal hit emits corpse in the same simulation step')
	check(s.position.is_equal_approx(start+Vector2(1,2)) and r.casualties[0].ground_point==s.position,'Final held state brakes first, then combined displacement occurs before death')
	check(r.casualties[0].velocity==Vector2(60,0),'Corpse saves normal velocity separately from already integrated knockback')
	for status in ['stun','petrified']:
		r=fixture();u=r.units[0];s=u.soldiers[0];u[status]=.05;r.hurt(u,1000.,'',0.,0);r.step(1./60)
		check(r.phase=='battle' and r.casualties.is_empty() and s.death_state==0,status+' skips death collection while frozen')
		for i in 4:r.step(1./60)
		check(s.death_state==2 and r.casualties.size()==1 and r.phase=='victory',status+' expires after lethal damage and cannot leave battle stuck')
	# Death signals release registrations sequentially, so the second body loses its dead attacker.
	r=fixture();for unit in r.units:r.hurt(unit,1000.,'',0.,0)
	r.units[0].soldiers[0].last_attacker=Vector2i(r.units[1].id,0);r.units[1].soldiers[0].last_attacker=Vector2i(r.units[0].id,0)
	r.step(1./60)
	check(r.casualties.size()==2 and r.casualties[0].attacker_point!=null and r.casualties[1].attacker_point==null,'Corpse source identity follows sequential death registration release')
	r=fixture('archer');u=r.units[1];s=u.soldiers[0];s.velocity=Vector2(80,0)
	var arrow=r.deal_blow(r.units[0],u,200.,{}, {'attacker_slot':0,'target_slot':0,'release_delay':0.});arrow.point=s.position-Vector2(1,0);arrow.speed=600.
	r.step(1./60)
	check(s.hp==0 and s.death_state==0 and r.casualties.is_empty() and r.phase=='battle','Projectile death after unit visits waits for next death collection')
	start=s.position;r.step(1./60)
	check(s.death_state==2 and r.casualties.size()==1 and r.casualties[0].ground_point==s.position and s.position.x>start.x,'Projectile casualty completes its next physical step before leaving a body')
	r=fixture();u=r.units[0];s=u.soldiers[0];start=s.position;r.hurt(u,1000.,'',0.,0)
	s.impulse=Vector2(780,0);r.terrain.ROCKS=[r.projection*Rect2(start+Vector2(12,-50),Vector2(25,100))]
	var nav=r.Soldiers.navigator(r,u.kind,u);r.terrain.clearances.erase(nav);r.terrain.extents.erase(nav)
	r.Soldiers.Physics.integrate(r,[row(u)],.2)
	check(s.position.x<start.x+12,'Lethal displacement still sweeps thin rocks instead of tunnelling')
	print('Death motion: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
