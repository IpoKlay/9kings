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
			r.Charges.detach(r,u,i);u.soldiers[i].position=u.pos;u.soldiers[i].personal_order='hold'
		r.Soldiers.total(u)
	# Isolate action timing from random initial acquisition phase.
	r.units[0].soldiers[0].aggro_timer=.1
	r.units[1].soldiers[0].cooldown=60.;r.units[1].soldiers[0].heading=Vector2.DOWN
	return r
func tick(r,n):
	for i in n:r.step(1./60.)
func run():
	var r=fixture();var a=r.units[0];var b=r.units[1]
	tick(r,1)
	check(a.soldiers[0].attack_age==0. and b.hp==100.,'Melee begins a visible windup without instant damage')
	tick(r,26)
	check(b.hp==100.,'No melee damage through0.4333 seconds after windup starts')
	tick(r,1)
	check(is_equal_approx(b.hp,75.),'First60Hz release at0.45 seconds applies one25-damage hit; H alone is not F shield wall hp='+str(b.hp))
	var hp=b.hp;tick(r,10)
	check(b.hp==hp,'The recovery cannot deliver the same attack twice')
	var age=a.soldiers[0].attack_age;r.step(0.)
	check(a.soldiers[0].attack_age==age and b.hp==hp,'Paused time preserves windup/recovery exactly')
	r=fixture('archer',300.);a=r.units[0];b=r.units[1];tick(r,1);tick(r,35)
	check(r.volleys.is_empty(),'Bow draws for0.5833 seconds without a projectile')
	tick(r,1)
	check(r.volleys.size()==1 and r.volleys[0].age==0. and r.volleys[0].release_delay==0.,'Arrow leaves at0.60 seconds with no second hidden release delay')
	check(r.events.any(func(e):return e.kind=='arrow'),'Bow sound event occurs on release')
	var flight:float=r.volleys[0].flight
	var damage_before=b.hp;r.advance_volleys(flight-.01)
	check(b.hp==damage_before,'Weapon-to-target travel remains incomplete before actual distance/speed')
	r.advance_volleys(.011)
	check(b.hp<damage_before and r.volleys.is_empty(),'Impact follows actual weapon-to-target flight, not feet distance')
	r=fixture('siege',400.);tick(r,1);tick(r,33)
	check(r.stones.is_empty(),'Catapult remains loaded through0.55 seconds')
	tick(r,1)
	check(r.stones.size()==1 and r.stones[0].age==0.,'Catapult releases at first tick after0.56 seconds, without the old0.20 delay')
	r=fixture();a=r.units[0];b=r.units[1];tick(r,1);r.hurt(b,1000.,'',0.,0);b.soldiers[0].death_state=1;r.Soldiers.advance(a,.5);r.Soldiers.fire_attacks(r)
	check(not a.soldiers[0].get('attack_pending',false) and not r.events.any(func(e):return e.get('attacker',-1)==a.id),'A target unregistered during windup consumes release without attacking a replacement')
	r=fixture();a=r.units[0];b=r.units[1];tick(r,1)
	r.Soldiers.command(r,[Vector2i(a.id,0)],'move',a.pos+Vector2(200,0));tick(r,35)
	check(b.hp==100.,'Accepted move clears the target and prevents a stored-target ghost hit')
	r=fixture();a=r.units[0];b=r.units[1];a.soldiers[0].personal_order='attack';a.soldiers[0].focus_id=b.id;a.soldiers[0].focus_slot=0
	a.soldiers[0].velocity=Vector2(0,-80.);tick(r,1)
	check(a.soldiers[0].has('attack_engaged') and a.soldiers[0].attack_age>1.,'Pursuit reaches attack state before windup')
	tick(r,1)
	check(a.soldiers[0].attack_age>1. and is_equal_approx(a.soldiers[0].velocity.y,-60.),'Melee pursuit decelerates at1200 per axis before starting a swing')
	tick(r,3)
	check(a.soldiers[0].attack_age==0.,'Melee begins only when normal speed falls below5')
	r=fixture();a=r.units[0];b=r.units[1];a.soldiers[0].personal_order='attack';a.soldiers[0].focus_id=b.id;a.soldiers[0].focus_slot=0;tick(r,1)
	b.soldiers[0].position=a.soldiers[0].position+Vector2(0,-38.);tick(r,28)
	check(b.hp<100. and a.soldiers[0].personal_order=='attack','Engaged target at38 stays within30×1.3 attack leash')
	b.soldiers[0].position=a.soldiers[0].position+Vector2(0,-70.);tick(r,1)
	check(not a.soldiers[0].has('attack_engaged') and a.soldiers[0].velocity.is_zero_approx(),'Leaving the attack leash transitions before movement')
	tick(r,1)
	check(a.soldiers[0].velocity.length()>0.,'Melee resumes pursuit on the following state step')
	r=fixture('archer',400.);a=r.units[0];b=r.units[1];a.soldiers[0].personal_order='attack';a.soldiers[0].focus_id=b.id;a.soldiers[0].focus_slot=0;tick(r,1)
	b.soldiers[0].position=a.soldiers[0].position+Vector2(0,-600.);tick(r,1)
	check(a.soldiers[0].personal_order=='idle' and a.soldiers[0].target_id==-1,'Player archer drops an engaged target beyond1.3 range instead of pursuing forever')
	tick(r,40);check(r.volleys.is_empty(),'A lost ranged target cannot receive the pending shot')
	print('Attack timing: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
