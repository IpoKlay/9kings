extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func run():
	var r=Battle.new();r.units.clear()
	r.spawn('siege','ally',Vector2(900,1200))
	r.spawn('legion','enemy',Vector2(900,800))
	var a=r.units[0];var b=r.units[1]
	strike(r,a,b)
	check(r.stones.size()==3,'Three living catapults launch three physical stones')
	check(r.stones.all(func(s):return s.flight>=.8 and s.flight<=2.5 and s.has('attacker_slot')),'Stone duration uses bounded .8–2.5 second flight from actual spoon')
	strike(r,a,b)
	check(r.stones.size()==3,'Each catapult spends its own five-second cooldown once')
	r.stones.clear()
	var impact: Vector2=r.projection.affine_inverse()*r.Soldiers.point(r,b,0)
	# This impact is outside the regiment-centre radius, but inside its end soldier.
	check(impact.distance_to(b.pos)>80.,'Fixture exercises end-of-line splash beyond regiment centre')
	var expected=[]
	for i in b.soldiers.size():
		var foot: Vector2=r.projection.affine_inverse()*r.Soldiers.point(r,b,i)
		if foot.distance_to(impact)<=80.:expected.append(i)
	r.stones.append({'side':'ally','from':a.pos,'pos':impact,'target':b.id,'damage':120.,'age':0.,'flight':.5})
	r.advance_stones(.49)
	check(b.hp==1000.,'Splash cannot apply before the visible landing')
	r.advance_stones(.01)
	var killed=[]
	for i in b.soldiers.size():
		if b.soldiers[i].hp<=0:killed.append(i)
	check(killed==expected and killed.size()<10,'Only living footpoints in the 80-unit footprint take damage')
	check(b.soldiers[9].hp==100.,'Distant end remains unhurt')
	var after: float=b.hp
	r.advance_stones(1.)
	check(b.hp==after and r.stones.is_empty(),'One stone lands exactly once')
	# Minimum range applies to each engine and its chosen target.
	for actor in a.soldiers:actor.cooldown=0.
	b.pos=a.pos
	strike(r,a,b)
	check(r.stones.is_empty(),'Catapults cannot fire inside 150 ground units')
	var q=Battle.new();q.units.clear()
	q.spawn('archer','ally',Vector2(1000,1100));q.spawn('legion','enemy',Vector2(1000,750))
	var bow=q.units[0];var victim=q.units[1]
	strike(q,bow,victim)
	var arrow=q.volleys[0]
	check(is_equal_approx(arrow.flight,arrow.origin.distance_to(arrow.pos)/400.),'Arrow flight uses official projectile speed')
	var slot: int=arrow.target_slot
	victim.formation_heading=Vector2.RIGHT
	q.advance_volleys(.3)
	var target_point: Vector2=q.projection.affine_inverse()*q.Soldiers.point(q,victim,slot)
	check(arrow.pos.is_equal_approx(target_point),'Rendered arrow follows the actual displaced target foot, not its old slot')
	check(victim.hp==victim.max_hp,'No damage while the arrow is visibly in flight')
	q.advance_volleys(2.)
	check(victim.hp<victim.max_hp and q.volleys.is_empty(),'Arrow arrivals resolve and clear their own projectiles')
	print('Individual projectiles: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)

func strike(r,a,b,only_slot=-1,target_slot=-1):
	r.Soldiers.attack(r,a,b,only_slot,target_slot)
	for actor in a.soldiers:actor.attack_age+=.61
	r.Soldiers.fire_attacks(r)
