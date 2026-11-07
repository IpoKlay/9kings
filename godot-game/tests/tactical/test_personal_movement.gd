extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture():
	var r=Battle.new();r.units.clear();r.spawn('legion','ally',Vector2(1000,1200));r.spawn('legion','enemy',Vector2(1800,400))
	for u in r.units:u.order='hold'
	r.start();return r
func ground(r,u,slot: int) -> Vector2:return r.projection.affine_inverse()*r.Soldiers.point(r,u,slot)
func run():
	var r=fixture();var u=r.units[0];var actor=u.soldiers[0]
	var before=[]
	for slot in u.soldiers.size():before.append(ground(r,u,slot))
	var goal: Vector2=before[0]+Vector2(0,-180)
	check(r.Soldiers.command(r,[Vector2i(u.id,0)],'move',goal),'One selected person accepts a ground move')
	var maximum_step=0.
	for tick in 180:
		var old=ground(r,u,0);r.step(1./60);maximum_step=maxf(maximum_step,old.distance_to(ground(r,u,0)))
	check(ground(r,u,0).distance_to(goal)<17. and actor.personal_order=='idle','Selected person arrives at the clicked point')
	check(maximum_step<=80./60+.01,'Individual motion is speed limited, without teleportation')
	check(u.pos==Vector2(1000,1200),'Moving one soldier does not move the command centre')
	var neighbours_still=true
	for slot in range(1,u.soldiers.size()):neighbours_still=neighbours_still and ground(r,u,slot).is_equal_approx(before[slot])
	check(neighbours_still,'Other soldiers keep their actual positions')
	check((r.projection*u.pos+r.Contact.feet(r,u)[0]).distance_to(r.projection*actor.position)<.01,'Drawing and contact feet use the same independent world position')
	var state=actor.duplicate(true)
	r.step(0.)
	check(actor==state,'Pause freezes personal movement and orders')
	check(not r.Soldiers.command(r,[Vector2i(u.id,0)],'move',Vector2(-100,-100)) and actor==state,'Invalid destination preserves the individual order')
	check(not r.command([u.id],'move',Vector2(-100,-100)) and actor==state,'Invalid regiment order cannot silently pull its detached soldier back')
	var arrived: Vector2=actor.position
	r.command([u.id],'hold',Vector2.ZERO)
	check(actor.position==arrived and actor.personal_order=='hold','A full-group hold stops the detached soldier at its actual position')
	for tick in 180:r.step(1./60)
	check(actor.personal_order=='hold' and ground(r,u,0).distance_to(arrived)<.05,'Hold never pulls a soldier back to its former slot')
	# An individual fits around a rock using personal clearance, not regiment width.
	var q=fixture();var v=q.units[0]
	var start=ground(q,v,0);var end=start+Vector2(0,-260)
	var rock=Rect2(q.projection*(start+Vector2(0,-130))-Vector2(35,25),Vector2(70,50))
	q.terrain.ROCKS.append(rock)
	check(q.Soldiers.command(q,[Vector2i(v.id,0)],'move',end),'Individual path plans around the authored rock')
	var crossed=false
	for tick in 600:
		q.step(1./60);crossed=crossed or rock.has_point(q.projection*ground(q,v,0))
	check(not crossed and ground(q,v,0).distance_to(end)<17.,'Actual foot follows the route around the rock and reaches its goal')
	var fight=fixture();var attacker=fight.units[0];var defender=fight.units[1]
	defender.pos=Vector2(1000,700)
	check(fight.Soldiers.command(fight,[Vector2i(attacker.id,0)],'attack',defender.pos,defender.id,9),'One soldier accepts a focused enemy soldier')
	for tick in 700:fight.step(1./60)
	check(defender.soldiers[9].hp<defender.soldiers[9].max_hp,'Detached attacker damages the chosen soldier using its real position')
	check(attacker.soldiers[0].hp<attacker.soldiers[0].max_hp,'Defending line can strike the detached soldier away from its owner centre')
	check(attacker.soldiers.slice(1).all(func(s):return s.hp==s.max_hp),'Counterattack does not damage the soldiers left at home')
	print('Personal movement: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
