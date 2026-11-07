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
			var s=u.soldiers[i];s.hp=s.max_hp if i==0 else 0.
			r.Charges.detach(r,u,i);s.position=u.pos;s.personal_order='hold';s.cooldown=60.;s.aggro_timer=.1
		r.Soldiers.total(u)
	var a=r.units[0].soldiers[0];a.personal_order='idle';a.cooldown=0.;a.scan_slot=1
	return r
func tick(r,n=1):
	for i in n:r.step(1./60.)
func run():
	var r=fixture('legion',200.);var u=r.units[0];var s=u.soldiers[0]
	for i in 6:
		var a=u.soldiers[i];a.hp=a.max_hp;a.position=u.pos+Vector2(i*25,0);a.personal_order='idle';a.scan_slot=i;a.aggro_timer=.1;a.cooldown=0.
	r.Soldiers.total(u);tick(r)
	check(u.soldiers.filter(func(a):return a.target_id>=0).size()==1 and u.soldiers[1].target_id>=0,'Only slot congruent to current physics group acquires on a shared due step')
	check(u.soldiers.slice(0,6).all(func(a):return a.aggro_timer<=0. and a.aggro_timer>=-.06),'Every due scanner resets to negative0..0.06 jitter even when its group is skipped')
	check(u.soldiers[1].get('velocity',Vector2.ZERO).is_zero_approx(),'Acquisition does not also execute pursuit movement')
	tick(r)
	check(u.soldiers[1].velocity.y<0.,'Acquired target is pursued on the following simulation step')
	r=fixture();s=r.units[0].soldiers[0];tick(r)
	check(s.target_id>=0 and not s.has('attack_engaged') and not s.get('attack_pending',false),'Idle melee acquires into pursuit even when already in attack range')
	tick(r)
	check(s.has('attack_engaged') and not s.get('attack_pending',false),'Next step changes pursuit into attack state')
	tick(r)
	check(s.attack_age==0. and s.get('attack_pending',false),'Third step starts melee windup')
	r=fixture('archer',300.);s=r.units[0].soldiers[0];tick(r)
	check(s.has('attack_engaged') and not s.get('attack_pending',false),'Player ranged acquisition enters attack state directly')
	tick(r)
	check(s.attack_age==0.,'Player ranged starts windup one step after acquisition')
	r=fixture();s=r.units[0].soldiers[0];s.personal_order='hold';s.aggro_timer=0.;s.scan_slot=5
	tick(r,5)
	check(not s.get('attack_pending',false),'H does not swing before its own0.1-second scan interval')
	tick(r)
	check(s.attack_age==0.,'H can swing on interval without the six-group acquisition gate')
	s.attack_pending=false;s.cooldown=.01;s.aggro_timer=0.;tick(r)
	check(not s.get('attack_pending',false),'Cooldown expiry alone cannot start a new H swing between scans')
	r=fixture();u=r.units[0];s=u.soldiers[0];tick(r,3)
	var b=r.units[1];r.hurt(b,b.hp,'test',0.,0)
	# Keep the battle alive so the dead-target state transition can execute.
	r.spawn('legion','enemy',Vector2(1100,1200));r.units.back().order='hold'
	var old_clock: float=s.aggro_timer;tick(r)
	check(s.target_id==-1 and not s.has('attack_engaged') and s.aggro_timer==old_clock,'Dead target consumes one transition step without immediately scanning a replacement')
	var snap=s.duplicate(true);var step=r.simulation_step;var random_state=r.targeting_random.state;r.step(0.)
	check(s==snap and r.simulation_step==step and r.targeting_random.state==random_state,'Pause freezes scan clock, group phase and random stream')
	r=fixture('legion',200.);u=r.units[0];s=u.soldiers[0];s.aggro_timer=-.05
	r.Soldiers.command(r,[Vector2i(u.id,0)],'attack_move',u.pos+Vector2(200,0))
	check(s.aggro_timer==.1,'Attack-move makes acquisition eligible immediately, still respecting scan group')
	r=fixture('legion',200.);u=r.units[0];s=u.soldiers[0];s.aggro_timer=-.05;s.scan_slot=5
	r.Soldiers.command(r,[Vector2i(u.id,0)],'attack',r.units[1].pos,r.units[1].id,0);tick(r)
	check(s.target_id==r.units[1].id and s.velocity.y<0.,'Explicit attack bypasses acquisition timer and group gate')
	var first=Battle.new();var second=Battle.new()
	var phases=first.units[0].soldiers.map(func(a):return a.aggro_timer)
	check(phases==second.units[0].soldiers.map(func(a):return a.aggro_timer) and phases.min()!=phases.max() and phases.min()>=0. and phases.max()<=.2,'Fresh battle instances use reproducible but staggered initial0..0.2-second phases')
	print('Acquisition states: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
