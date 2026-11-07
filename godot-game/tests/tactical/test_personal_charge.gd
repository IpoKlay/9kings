extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func person(r,kind: String,side: String,pos: Vector2):
	r.spawn(kind,side,pos)
	var u=r.units.back();u.order='hold'
	for slot in u.soldiers.size():
		u.soldiers[slot].cooldown=999.
		if slot>0:u.soldiers[slot].hp=0.
	r.Soldiers.total(u);r.Charges.detach(r,u,0)
	u.soldiers[0].position=pos;u.soldiers[0].heading=Vector2.DOWN if side=='enemy' else Vector2.UP
	return u
func fixture(kind='legion',target_kind='legion'):
	var r=Battle.new();r.units.clear()
	person(r,kind,'ally',Vector2(1000,1200));person(r,target_kind,'enemy',Vector2(1000,900))
	r.start();return r
func hits(r):return r.events.filter(func(e):return e.get('personal_charge',false))
func tick(r,n: int):
	for i in n:r.step(1./60)
func run():
	var r=fixture();var a=r.units[0];var b=r.units[1];var actor=a.soldiers[0]
	check(r.Charges.issue(r,[Vector2i(a.id,0)],Vector2(1000,700)),'Melee C charge starts')
	var position: Vector2=actor.position;r.step(0.)
	check(actor.position==position and actor.charge_run.age==0.,'Pause freezes charge motion and timer')
	check(not r.Charges.issue(r,[Vector2i(a.id,0)],Vector2(1000,700)),'An active charge cannot restart its timer')
	tick(r,100)
	check(hits(r).size()==1,'Infantry awards exactly one charge hit')
	if not hits(r).is_empty():check(is_equal_approx(hits(r)[0].damage,62.5),'Full-speed swordsman hits for 25 × 2.5 without legacy side or hold multipliers')
	check(not actor.has('charge_run') and actor.charge_cooldown>9.,'Infantry stops charging on hit and begins its own ten-second cooldown')
	check(b.soldiers[0].position.y<900.,'The struck individual is physically displaced')
	check(not r.Charges.issue(r,[Vector2i(a.id,0)],Vector2(1000,700)),'Cooldown prevents another charge')
	var cd: float=actor.charge_cooldown;r.step(0.);check(cd==actor.charge_cooldown,'Pause does not consume cooldown')
	var shield=fixture();var sa=shield.units[0];var sb=shield.units[1]
	sb.soldiers[0].shield_wall=true
	shield.Charges.issue(shield,[Vector2i(sa.id,0)],Vector2(1000,700));tick(shield,100)
	check(hits(shield).size()==1 and is_equal_approx(hits(shield)[0].damage,25.),'Frontal shield wall reduces personal charge damage by sixty percent')
	var flank=fixture();var fa=flank.units[0];var fb=flank.units[1]
	fb.soldiers[0].shield_wall=true;fb.soldiers[0].heading=Vector2.LEFT
	flank.Charges.issue(flank,[Vector2i(fa.id,0)],Vector2(1000,700));tick(flank,100)
	check(hits(flank).size()==1 and is_equal_approx(hits(flank)[0].damage,62.5),'Exposed shield flank receives full charge damage')
	var cancel=fixture('cavalry');var ca=cancel.units[0]
	cancel.Charges.issue(cancel,[Vector2i(ca.id,0)],Vector2(1000,700));tick(cancel,12)
	check(cancel.Soldiers.command(cancel,[Vector2i(ca.id,0)],'hold',Vector2.ZERO),'A personal order cancels an active charge')
	check(not ca.soldiers[0].has('charge_run') and ca.soldiers[0].charge_cooldown==8.,'Cancelling cavalry starts the full eight-second cooldown')
	var invalid=fixture();var ia=invalid.units[0]
	invalid.Charges.issue(invalid,[Vector2i(ia.id,0)],Vector2(1000,700));tick(invalid,8)
	check(not invalid.Soldiers.command(invalid,[Vector2i(ia.id,0)],'move',Vector2(-1,-1)) and ia.soldiers[0].has('charge_run'),'Rejected move does not cancel a valid charge')
	invalid.command([ia.id],'hold',Vector2.ZERO)
	check(not ia.soldiers[0].has('charge_run') and ia.soldiers[0].charge_cooldown==10.,'Whole-regiment command also consumes charge cooldown')
	var ranged=fixture('archer')
	check(not ranged.Charges.issue(ranged,[Vector2i(ranged.units[0].id,0)],Vector2(1000,700)),'Archers cannot enter melee charge')
	var wall=fixture('cavalry');var wa=wall.units[0]
	var rock=Rect2(wall.projection*Vector2(970,1050),Vector2(60,24))
	wall.terrain.ROCKS.append(rock)
	wall.Charges.issue(wall,[Vector2i(wa.id,0)],Vector2(1000,700));tick(wall,100)
	check(hits(wall).is_empty() and wa.soldiers[0].charge_end.position.y>1050. and wa.soldiers[0].charge_end.reason=='blocked','Authored rock stops a charge before an enemy behind it')
	check(wa.soldiers[0].charge_cooldown>6.,'Terrain blockage starts cooldown')
	var trample=fixture('cavalry');var horse=trample.units[0]
	trample.units[1].soldiers[0].position.x=1015.
	person(trample,'legion','enemy',Vector2(1015,820));person(trample,'legion','enemy',Vector2(1015,740))
	trample.Charges.issue(trample,[Vector2i(horse.id,0)],Vector2(1000,580));tick(trample,190)
	var records=hits(trample);var victims=[]
	for record in records:
		check(record.target not in victims,'A mounted charge never charges the same victim twice')
		victims.append(record.target)
		var expected=30.*2.5*pow(.7,victims.size()-1)*record.speed_fraction
		check(is_equal_approx(record.damage,expected),'Mounted hit uses actual speed and per-victim trample decay')
	check(records.size()>=2,'Cavalry retains momentum into a second distinct target')
	check(horse.soldiers[0].charge_cooldown>0 and not horse.soldiers[0].has('charge_run'),'Mounted charge has a bounded duration and ends in cooldown')
	var push=fixture('cavalry');var pushed=push.units[1]
	var barrier=Rect2(push.projection*Vector2(970,850),Vector2(60,15))
	push.terrain.ROCKS.append(barrier)
	push.Charges.knock(push,pushed,0,Vector2(0,-780));tick(push,60)
	check(pushed.soldiers[0].position.y>850. and not barrier.has_point(push.projection*pushed.soldiers[0].position),'Knockback cannot teleport through an authored rock')
	var tandem=fixture('cavalry');var first=tandem.units[0];var victim=tandem.units[1]
	victim.soldiers[0].position.x=1020.
	var second=person(tandem,'cavalry','ally',Vector2(1040,1200))
	person(tandem,'legion','enemy',Vector2(1500,400))
	tandem.Charges.issue(tandem,[Vector2i(first.id,0),Vector2i(second.id,0)],Vector2(1020,700));tick(tandem,100)
	var shared=hits(tandem).filter(func(e):return e.target==victim.id)
	check(shared.size()==2,'Two riders keep separate hit ledgers against one victim')
	if shared.size()==2:check(is_equal_approx(shared[0].damage+shared[1].damage,100.),'Simultaneous charge damage stops at victim HP, without a second regiment damage grant')
	var removed=fixture('cavalry');var rider=removed.units[0];var gone=removed.units[1]
	person(removed,'legion','enemy',Vector2(1600,400))
	removed.Charges.issue(removed,[Vector2i(rider.id,0)],Vector2(1000,700));tick(removed,20)
	removed.hurt(gone,gone.hp,'test',0.,0);tick(removed,180)
	check(hits(removed).is_empty() and not rider.soldiers[0].has('charge_run'),'Target dying early leaves no ghost hit or endless charge')
	check(rider.soldiers[0].charge_end.reason in ['goal','duration'],'Charge to a ground point finishes after the target disappears')
	var close=fixture();var close_a=close.units[0];var close_b=close.units[1]
	close_b.soldiers[0].position=Vector2(1000,1175)
	close.Charges.issue(close,[Vector2i(close_a.id,0)],Vector2(1000,700));tick(close,1)
	check(hits(close).size()==1 and is_equal_approx(hits(close)[0].damage,6.25),'No run-up uses the original ten-percent speed floor, not full charge damage')
	var capped=fixture('cavalry');var cap_a=capped.units[0]
	capped.Charges.issue(capped,[Vector2i(cap_a.id,0)],Vector2(1000,100))
	check(is_equal_approx(cap_a.soldiers[0].position.distance_to(cap_a.soldiers[0].charge_run.goal),760.),'Ground target is capped at the confirmed maximum charge range')
	tick(capped,1)
	check(is_equal_approx(cap_a.soldiers[0].charge_run.velocity.length(),20.),'Charging accelerates from rest instead of jumping straight to peak speed')
	var moving=fixture();var moving_a=moving.units[0]
	moving.Soldiers.command(moving,[Vector2i(moving_a.id,0)],'move',Vector2(1000,1050));tick(moving,20)
	moving.Charges.issue(moving,[Vector2i(moving_a.id,0)],Vector2(1000,700))
	check(absf(moving_a.soldiers[0].charge_run.velocity.length()-80.)<.01,'C preserves an already marching soldier’s actual movement velocity')
	var ready_after=fixture();var waiting=ready_after.units[0]
	ready_after.Charges.issue(ready_after,[Vector2i(waiting.id,0)],Vector2(1000,700))
	ready_after.Soldiers.command(ready_after,[Vector2i(waiting.id,0)],'hold',Vector2.ZERO)
	tick(ready_after,599)
	check(not ready_after.Charges.ready(ready_after,waiting,waiting.soldiers[0]),'Infantry remains unavailable just before ten simulation seconds')
	tick(ready_after,1)
	check(ready_after.Charges.ready(ready_after,waiting,waiting.soldiers[0]),'Infantry becomes ready after the full cooldown')
	print('Personal charge: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
