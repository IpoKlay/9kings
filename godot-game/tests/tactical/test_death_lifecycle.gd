extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok:bool,note:String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture(killer_first=false):
	var r=Battle.new();r.units.clear()
	if killer_first:r.spawn('legion','enemy',Vector2(1029,1000))
	r.spawn('archer','ally',Vector2(1000,1000))
	if not killer_first:r.spawn('legion','enemy',Vector2(1029,1000))
	r.spawn('legion','enemy',Vector2(1200,1000));r.spawn('legion','ally',Vector2(1200,1050))
	for u in r.units:
		u.order='hold'
		for i in u.soldiers.size():
			r.Charges.detach(r,u,i);var s=u.soldiers[i];s.hp=s.max_hp if i==0 else 0.;s.position=u.pos;s.personal_order='hold';s.cooldown=999.
		r.Soldiers.total(u)
	r.start();r.enemy_director.active=false
	return r
func source(r):return r.units.filter(func(u):return u.kind=='archer')[0]
func victim(r):return r.units[2]
func arrow(r,distance=2.):
	var a=source(r);var b=victim(r)
	var shot=r.deal_blow(a,b,20.,{}, {'attacker_slot':0,'target_slot':0,'release_delay':0.})
	shot.point=b.soldiers[0].position+Vector2(-distance,0);shot.speed=600.
	return shot
func shield(r):
	victim(r).soldiers[0].shield_wall=true;victim(r).soldiers[0].wall_heading=Vector2.LEFT
func run():
	for phase in [0,1,2]:
		var r=fixture();shield(r);var shot=arrow(r);var a=source(r);r.hurt(a,1000.,'',0.,0)
		if phase>=1:r.Soldiers.advance_personal(r,1./60)
		if phase==2:r.Soldiers.finish_deaths(r)
		var handle=r.Projectiles.source(r,shot)
		check(handle.is_empty() if phase==2 else handle.registered==(phase==0),'Object validity and slot registration are separate: phase'+str(phase))
		r.advance_volleys(1./60)
		check(is_equal_approx(victim(r).hp,[96.,92.,80.][phase]),'Shield damage is4/8/20 for registered/queued/freed source')
		check(victim(r).soldiers[0].has('last_attacker')==(phase==0),'Only registered source keeps attacker identity')
		if phase==1:
			var state=a.soldiers[0].duplicate(true);r.step(0.);check(a.soldiers[0]==state,'Pause cannot finish queued destruction')
	for killer_first in [false,true]:
		var r=fixture(killer_first);var a=source(r);var b=victim(r);shield(r)
		r.hurt(a,a.hp-1.,'',0.,0)
		var killer=r.units[0] if killer_first else r.units[1];var k=killer.soldiers[0]
		k.target_id=a.id;k.target_slot=0;k.attack_age=.43;k.attack_pending=true
		for distance in [2.,12.,22.]:arrow(r,distance)
		r.step(1./60)
		check(a.hp==0. and a.soldiers[0].death_state==(2 if killer_first else 0),'Death collection respects whether attacker visited before or after lethal hit')
		check(is_equal_approx(b.hp,92. if killer_first else 96.),'Existing arrow sees registered-dead or queued-dead source on lethal step')
		r.step(1./60)
		check(a.soldiers[0].death_state==2 and is_equal_approx(b.hp,72. if killer_first else 88.),'Following tick queues late death then finishes object destruction')
		r.step(1./60)
		check(is_equal_approx(b.hp,52. if killer_first else 68.) and r.volleys.is_empty(),'Later airborne arrow has null source and still hits once')
	stone_sources();retaliation();projectile_order();release_order()
	print('Death lifecycle: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
func stone(r):
	var a=source(r);var b=victim(r)
	var shot=r.Projectiles.schedule(r,{'side':'ally','from':a.pos,'pos':b.pos,'attacker':a.id,'attacker_slot':0,'damage':20.,'age':0.,'flight':.001})
	r.stones.append(shot);return shot
func stone_sources():
	for phase in [0,1,2]:
		var r=fixture();var a=source(r);var friend=r.units[3];stone(r);r.hurt(a,1000.,'',0.,0)
		if phase>=1:r.Soldiers.advance_personal(r,1./60)
		if phase==2:r.Soldiers.finish_deaths(r)
		r.advance_stones(.01)
		check(victim(r).hp==80.,'Stone still hits enemy after lethal source damage')
		check(friend.hp==(80. if phase==2 else 100.),'Stone includes friend only after actual source destruction')
func retaliation():
	var r=fixture();var a=source(r);var b=victim(r);b.soldiers[0].personal_order='idle';arrow(r);r.hurt(a,1000.,'',0.,0);r.advance_volleys(.01)
	check(b.soldiers[0].personal_order=='attack' and b.soldiers[0].last_attacker==Vector2i(a.id,0),'Dead but still registered source can trigger retaliation callback')
	for phase in [1,2]:
		r=fixture();a=source(r);b=victim(r);b.soldiers[0].personal_order='idle';arrow(r);r.hurt(a,1000.,'',0.,0)
		r.Soldiers.advance_personal(r,.001)
		if phase==2:r.Soldiers.finish_deaths(r)
		r.advance_volleys(.01)
		check(not b.soldiers[0].has('last_attacker'),'Queued/freed source cannot register retaliation')
func projectile_order():
	for stone_first in [false,true]:
		var r=fixture();var b=victim(r);r.hurt(b,90.,'',0.,0)
		if stone_first:stone(r);arrow(r)
		else:arrow(r);stone(r)
		r.step(1./60)
		check(b.hp==0 and r.stones.is_empty() and r.volleys.is_empty(),'Mixed projectile arrivals resolve once')
		check(r.events.filter(func(e):return e.kind=='arrow_impact').size()==(0 if stone_first else 1),'Arrow/stone resolution follows spawn order, not separate array order')
func release_order():
	var r=fixture();var a=source(r);var b=victim(r);var actor=a.soldiers[0]
	actor.target_id=b.id;actor.target_slot=0;actor.attack_pending=true;actor.attack_age=.59
	r.step(1./60)
	check(r.volleys.size()==1 and r.volleys[0].age==0 and r.volleys[0].point==r.volleys[0].origin,'New shot waits until next physics frame, as measured with native engine nodes')
	var p=r.volleys[0];var before:Vector2=p.point
	r.step(1./60)
	check(is_equal_approx(before.distance_to(p.point),400./60),'Existing shot first moves one normal step on next frame')
	r=fixture();a=source(r);b=victim(r);p=arrow(r);b.soldiers[0].velocity=Vector2(0,60);b.soldiers[0].personal_order='move';b.soldiers[0].path=[b.pos+Vector2(0,500)];p.point=b.pos+Vector2(-100,0)
	r.step(1./60)
	check(p.pos.y>1000 and p.pos==b.soldiers[0].position,'Existing shot tracks post-integration target position')
