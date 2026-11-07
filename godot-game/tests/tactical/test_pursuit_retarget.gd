extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture(kind='legion',variant=''):
	var r=Battle.new();r.units.clear();r.spawn(kind,'ally',Vector2(1000,1200),variant);r.spawn('legion','enemy',Vector2(1000,800));r.spawn('legion','enemy',Vector2(1070,1200))
	for u in r.units:
		u.order='hold'
		for i in u.soldiers.size():
			r.Charges.detach(r,u,i);var s=u.soldiers[i];s.position=u.pos;s.hp=s.max_hp if i==0 else 0.;s.personal_order='hold';s.cooldown=999.
		r.Soldiers.total(u)
	r.start();var a=r.units[0];r.Soldiers.command(r,[Vector2i(a.id,0)],'attack',Vector2.ZERO,r.units[1].id,0)
	a.soldiers[0].target_id=r.units[1].id;a.soldiers[0].target_slot=0
	return r
func choose(r,dt=.01):
	var u=r.units[0];var a=u.soldiers[0];var old=r.Soldiers.identified_target(r,u,0,a.target_id,a.target_slot)
	return r.Soldiers.retarget_pursuit(r,u,0,a,old,r.Soldiers.ranged_target_counts(r),dt)
func decision(r,dt=.01):r.Soldiers.step_personal(r,{'unit':r.units[0],'slot':0},[],r.Soldiers.ranged_target_counts(r),dt)
func run():
	var r=fixture();var u=r.units[0];var a=u.soldiers[0];var far=r.units[1];var close=r.units[2]
	check(u.soldiers.all(func(s):return s.retarget_timer>=0. and s.retarget_timer<=.15),'Spawn assigns bounded 0..0.15 personal phase')
	check(u.soldiers[0].retarget_timer!=u.soldiers[1].retarget_timer,'Spawn phases are distributed among soldiers')
	a.retarget_timer=.1
	for i in 5:choose(r)
	check(a.target_id==far.id and is_equal_approx(a.retarget_timer,.05),'Only elapsed pursuit steps consume countdown')
	choose(r,.051)
	check(a.target_id==close.id and a.focus_id==close.id and a.focus_slot==0,'Explicit player focus can switch to a nearby opponent')
	check(is_equal_approx(a.retarget_timer,.15),'Eligible scan resets countdown to0.15')
	r=fixture();a=r.units[0].soldiers[0];r.units[2].soldiers[0].position=Vector2(1073,1200);a.retarget_timer=0.;choose(r)
	check(a.target_id==r.units[1].id and a.retarget_timer==.15,'An empty72-radius scan still restarts the interval')
	r.units[2].soldiers[0].position=Vector2(1072,1200);a.retarget_timer=0.;choose(r)
	check(a.target_id==r.units[2].id,'Boundary at eight body radii is included')
	r=fixture();a=r.units[0].soldiers[0];var reach=r.Soldiers.effective_range(r,r.units[0],r.units[1]);a.retarget_timer=0.;r.units[1].soldiers[0].position=Vector2(1000,1200-reach*2.);choose(r)
	check(a.target_id==r.units[1].id and a.retarget_timer<0.,'Exactly twice effective range cannot trigger scan; timer remains overdue')
	r.units[1].soldiers[0].position.y-=.1;choose(r)
	check(a.retarget_timer==.15,'Crossing the strict twice-range boundary triggers immediately when overdue')
	r=fixture();a=r.units[0].soldiers[0];reach=r.Soldiers.effective_range(r,r.units[0],r.units[1]);r.units[1].soldiers[0].position=Vector2(1000,1200-reach*1.5);a.retarget_timer=.02
	for i in 5:choose(r)
	check(a.retarget_timer<0. and a.target_id==r.units[1].id,'Approaching between one and two ranges consumes timer without scanning')
	r.units[1].soldiers[0].position=Vector2(1000,800);choose(r)
	check(a.target_id==r.units[2].id,'Overdue approach timer is not replaced by a wall-clock deadline')
	r=fixture();a=r.units[0].soldiers[0];r.units[1].soldiers[0].position=Vector2(1000,1190);a.retarget_timer=.08;choose(r)
	check(a.retarget_timer==.08,'Entering melee attack range returns before timer decrement')
	r=fixture();a=r.units[0].soldiers[0]
	for order in ['hold','move','charge']:
		a.personal_order=order;a.retarget_timer=.08;choose(r,.1)
		check(a.retarget_timer==.08,order+' does not spend pursuit countdown')
	a.personal_order='attack';a.attack_engaged=Vector2i(r.units[1].id,0);choose(r,.1)
	check(a.retarget_timer==.08,'An ongoing attack does not run pursuit scan')
	a.erase('attack_engaged');a.shield_wall=true;choose(r,.1)
	check(a.retarget_timer==.08,'Shield stance does not run pursuit scan')
	r=fixture();a=r.units[0].soldiers[0];a.retarget_timer=0.;decision(r)
	check(a.target_id==r.units[2].id and a.velocity.y<0. and is_zero_approx(a.velocity.x),'Switch step still navigates toward the cached old target')
	decision(r)
	check(a.velocity.x>0.,'Following step starts turning toward the new target')
	a.retarget_timer=.117;r.Soldiers.command(r,[Vector2i(r.units[0].id,0)],'attack',Vector2.ZERO,r.units[1].id,0)
	check(a.retarget_timer==.117 and a.target_id==-1,'New explicit order changes target but preserves personal timer phase')
	decision(r);check(a.target_id==r.units[1].id,'New explicit focus is honored before a later eligible scan')
	r=fixture();a=r.units[0].soldiers[0];r.units[1].soldiers[0].position=Vector2(1000,1130);a.retarget_timer=0.;choose(r)
	check(a.target_id==r.units[1].id,'Equal squared distance keeps current target without arbitrary switching')
	r.units[2].soldiers[0].hp=0.;r.Soldiers.total(r.units[2]);a.retarget_timer=0.;choose(r)
	check(a.target_id==r.units[1].id,'Dead nearby candidates cannot replace pursuit target')
	r=fixture('cavalry','mounted_archer');a=r.units[0].soldiers[0];r.units[1].soldiers[0].position=Vector2(1000,1000);a.retarget_timer=.08;choose(r)
	check(is_equal_approx(a.retarget_timer,.07),'Mounted ranged pursuit still consumes timer inside weapon range')
	r.units[1].soldiers[0].position=Vector2(1000,500);a.cooldown=0.;a.retarget_timer=.08;decision(r)
	check(a.target_id==r.units[2].id and a.velocity.y<0. and is_zero_approx(a.velocity.x),'Mounted fire may change aim but current pursuit step keeps pre-fire navigation target')
	var saved=a.duplicate(true);r.step(0.)
	check(a==saved,'Pause freezes all pursuit timing and target state')
	print('Pursuit retarget: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
