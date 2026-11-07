extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok:bool,note:String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture(kind='legion',killer_first=true):
	var r=Battle.new();r.units.clear()
	for key in r.config.types:
		r.config.types[key].files=1;r.config.types[key].hp=r.config.types[key].get('individual',{}).get('hp',100.)
		r.contact_profiles[key]=r.Contact.profile(key,r.config.types[key],true)
	if killer_first:r.spawn('legion','enemy',Vector2(971,1000))
	r.spawn(kind,'ally',Vector2(1000,1000))
	if not killer_first:r.spawn('legion','enemy',Vector2(971,1000))
	r.spawn('legion','enemy',Vector2(1025,1000));r.spawn('legion','ally',Vector2(1600,1600))
	for u in r.units:
		u.order='hold';r.Charges.detach(r,u,0);var actor=u.soldiers[0];actor.position=u.pos;actor.personal_order='hold';actor.cooldown=999.
	r.start();r.enemy_director.active=false
	var source=r.units[1] if killer_first else r.units[0]
	var killer=r.units[0] if killer_first else r.units[1]
	r.hurt(source,source.hp-1.,'',0.,0)
	arm(killer,source,.43);arm(source,r.units[2],.43 if kind=='legion' else .59)
	return {'r':r,'source':source,'killer':killer,'target':r.units[2]}
func arm(u,target,age):
	var s=u.soldiers[0];s.target_id=target.id;s.target_slot=0;s.attack_age=age;s.attack_pending=true
func hits(r,u):return r.events.filter(func(e):return e.get('attacker',-1)==u.id and e.get('damage',0.)>0)
func run():
	for first in [false,true]:
		var f=fixture('legion',first);var r=f.r;var source=f.source;var s=source.soldiers[0]
		r.step(1./60)
		check(source.hp==0. and f.target.hp==75.,'Lethal frame still releases the due25 damage melee, both visitation orders')
		check(hits(r,source).size()==1,'Terminal melee awards exactly one hit')
		check(s.death_state==(2 if first else 0),'Earlier/later visitation still controls registration lifetime')
		var hp=f.target.hp
		for tick in 5:r.step(1./60)
		check(f.target.hp==hp and s.death_state==2 and not s.get('attack_pending',false),'Collected source cannot attack again')
	for age in [.1,.79]:
		var f=fixture();f.source.soldiers[0].attack_age=age;f.r.step(1./60)
		check(f.target.hp==100. and f.source.soldiers[0].death_state==2,'Unreached/expired windup cannot invent a terminal strike')
	var f=fixture('archer');f.target.soldiers[0].position=Vector2(1200,1000);f.r.step(1./60)
	check(f.source.hp==0 and f.source.soldiers[0].death_state==2 and f.r.volleys.size()==1,'Archer killed before own visit still releases a due arrow')
	check(not f.r.volleys.is_empty() and f.r.volleys[0].age==0.,'Terminal arrow follows normal new-projectile scheduling')
	for tick in 40:f.r.step(1./60)
	check(f.target.hp==85. and f.r.projectile_serial==1 and f.r.volleys.is_empty(),'Terminal arrow continues after source destruction and hits exactly once')
	f=fixture();var s=f.source.soldiers[0];f.r.hurt(f.source,1.,'',0.,0);s.personal_order='move'
	f.r.hurt(f.source,0.,'',0.,0,f.killer.id,0)
	# Direct callback tests the source UnitShell state transition; aggregate hurt stops at zero.
	f.r.Soldiers.retaliate(f.r,f.source,0,f.killer.id,0)
	check(s.personal_order=='attack' and s.hp==0.,'Lethally wounded registered actor can change target without being healed')
	for phase in [1,2]:
		f=fixture();s=f.source.soldiers[0];s.death_state=phase
		f.r.Soldiers.fire_actor(f.r,f.source,0)
		check(f.target.hp==100.,'Released registration cannot emit another attack')
	f=fixture();s=f.source.soldiers[0];f.r.hurt(f.source,1.,'',0.,0);f.source.stun=1.
	f.r.Soldiers.advance_personal(f.r,1./60)
	check(s.death_state==0 and f.target.hp==100.,'Frozen actor skips both release and death visit')
	f.source.stun=0.;s.attack_age=.45;f.r.Soldiers.advance_personal(f.r,1./60)
	check(s.death_state==1 and f.target.hp==75.,'Unfreezing resumes release before collection')
	f=fixture('archer');s=f.source.soldiers[0];f.r.hurt(f.target,1000.,'',0.,0)
	s.attack_age=.61;f.r.Soldiers.fire_actor(f.r,f.source,0)
	check(f.r.volleys.size()==1 and f.r.volleys[0].target_slot==0,'Release keeps explicitly registered dead target rather than retargeting or looping')
	f.r.advance_volleys(1./60)
	check(f.r.volleys.is_empty(),'Arrow to dead target cancels on its first flight callback')
	f=fixture('archer');f.r.hurt(f.target,1000.,'',0.,0);f.r.step(1./60)
	check(f.r.projectile_serial==1 and f.r.volleys.size()==1,'Full held-state visit preserves registered aim through the terminal release')
	f.r.step(1./60);check(f.r.volleys.is_empty(),'Scheduled dead-target arrow cancels next tick')
	print('Terminal attacks: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
