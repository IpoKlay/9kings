extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
const Physics=preload('res://scripts/tactical/soldier_physics.gd')
const Before=preload('res://tests/tactical/fixtures/repulsion_before_packed.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func run():
	for scenario in 8:
		var fast=Battle.new();fast.units.clear();fast.next_id=0
		var rng=RandomNumberGenerator.new();rng.seed=74011+scenario
		for group in 12:
			fast.spawn('legion','ally' if group%2 else 'enemy',Vector2(1000,1000))
			var u=fast.units.back()
			u.stun=.2 if group==10 else 0.;u.petrified=.2 if group==11 else 0.
			for slot in u.soldiers.size():
				fast.Charges.detach(fast,u,slot)
				var actor: Dictionary=u.soldiers[slot]
				actor.position=Vector2(1000+rng.randf_range(-70,70),1000+rng.randf_range(-70,70))
				if slot<2 and group<4:actor.position=Vector2(1000,1000)
				actor.heading=Vector2.from_angle(rng.randf_range(-PI,PI))
				actor.shield_wall=slot%5==0;actor.wall_heading=-actor.heading
				if slot%5==1:actor.wall_slot=actor.position;actor.personal_order='move'
				actor.death_state=1 if slot==8 else 0
				if slot==7:actor.hp=0.
				# Include feet still owned by a formation, testing detachment at actual pressure.
				if slot==9:actor.erase('position')
		var slow=Battle.new();slow.units=fast.units.duplicate(true)
		if scenario%2:
			var rocks=[Rect2(fast.projection*Vector2(1015,945),Vector2(12,82))]
			fast.terrain.replace_rocks(rocks);slow.terrain.replace_rocks(rocks.duplicate())
		fast.repulsion_seed=12345+scenario;slow.repulsion_seed=fast.repulsion_seed
		var exact=true;var cleaned=true;var seed_same=true;var moved=false
		for frame in 90:
			var a=[];var b=[]
			for index in fast.units.size():
				for slot in fast.units[index].soldiers.size():
					var radius=9.+float((index+slot)%5)*.1000000001
					a.append({'unit':fast.units[index],'slot':slot,'radius':radius,'point':fast.Soldiers.ground_position(fast,fast.units[index],slot)})
					b.append({'unit':slow.units[index],'slot':slot,'radius':radius,'point':slow.Soldiers.ground_position(slow,slow.units[index],slot)})
			var original: Vector2=a[2].point
			var dt=[1./120.,1./60.,1./30.,.1][scenario%4]
			Physics.repel(fast,a,dt);Before.repel(slow,b,dt)
			moved=moved or a[2].point!=original
			for index in a.size():
				exact=exact and a[index].point==b[index].point
				cleaned=cleaned and not a[index].has('physics_index') and not a[index].has('neighbours')
			exact=exact and fast.units==slow.units and fast.repulsion_time==slow.repulsion_time
			seed_same=seed_same and fast.repulsion_seed==slow.repulsion_seed
		check(exact,'Exact Vector2/actor/cadence equality against frozen kernel, scenario '+str(scenario))
		check(seed_same,'Coincident-pair RNG call order unchanged, scenario '+str(scenario))
		check(fast.repulsion_seed!=12345+scenario,'Fixture actually exercises coincident-foot separation, scenario '+str(scenario))
		check(cleaned,'Temporary neighbour and packed indexes released, scenario '+str(scenario))
		check(moved,'Fixture produces real displacement, scenario '+str(scenario))
	print('Packed repulsion: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
