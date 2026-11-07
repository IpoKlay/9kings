extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func fixture():
	var r=Battle.new();r.units.clear()
	r.spawn('legion','ally',Vector2(1000,1200));r.spawn('legion','enemy',Vector2(650,850));r.spawn('legion','enemy',Vector2(1350,850))
	for u in r.units:u.order='hold'
	r.start();return r
func tick(r,n):
	for i in n:r.step(1./60)
func run():
	var r=fixture();var u=r.units[0]
	var before=[]
	for slot in u.soldiers.size():before.append(r.Soldiers.point(r,u,slot))
	# Isolate divergent steering from randomized scan latency and enemy strategic movement.
	r.enemy_director.until_review=999.
	for actor in u.soldiers:actor.aggro_timer=.1;actor.scan_slot=1
	r.command([u.id],'auto',Vector2.ZERO)
	check(u.soldiers.all(func(actor):return actor.has('position') and actor.personal_order=='auto'),'All-attack creates actual individual positions for every living soldier')
	check(u.pos==Vector2(1000,1200),'Activating autonomy does not teleport the formation')
	tick(r,60)
	var targets={};var directions=[]
	for actor in u.soldiers:targets[actor.target_id]=true;directions.append(actor.heading)
	check(targets.has(r.units[1].id) and targets.has(r.units[2].id),'Opposite ends independently choose enemies from different regiments')
	check(directions[0].x*directions[9].x<0,'The two ends physically diverge instead of following one command-centre path')
	var mean=Vector2.ZERO
	for actor in u.soldiers:mean+=actor.position
	mean/=u.soldiers.size()
	check(u.pos.distance_to(mean)<.01,'Regiment centre reports the mean of real soldiers')
	var held=u.soldiers[0].position
	r.Soldiers.command(r,[Vector2i(u.id,0)],'hold',Vector2.ZERO);tick(r,20)
	check(u.soldiers[0].personal_order=='hold' and u.soldiers[0].velocity==Vector2.ZERO and u.soldiers[1].personal_order=='auto','Personal hold stops active locomotion while allowing physical crowd displacement')
	var frozen=u.soldiers.duplicate(true);r.step(0.)
	check(u.soldiers==frozen,'Pause freezes autonomous movement and target timers')
	r.command([u.id],'hold',Vector2.ZERO)
	check(not u.get('individual_auto',false) and u.soldiers.all(func(actor):return actor.personal_order=='hold'),'Whole-group hold stops each actual individual without reforming the old line')
	var rock=fixture();var a=rock.units[0]
	var origin: Vector2=rock.projection.affine_inverse()*rock.Soldiers.point(rock,a,5)
	var obstacle=Rect2(rock.projection*(origin+Vector2(0,-100))-Vector2(18,18),Vector2(36,36))
	rock.terrain.ROCKS.append(obstacle);rock.command([a.id],'auto',Vector2.ZERO)
	var crossed=false
	for frame in 180:
		rock.step(1./60)
		for actor in a.soldiers:crossed=crossed or obstacle.has_point(rock.projection*actor.position)
	check(not crossed,'Autonomous feet route around authored rock geometry')
	check(a.soldiers.any(func(actor):return actor.position.y<origin.y-150.),'One blocked lane does not stop the entire row')
	var enemy=fixture();enemy.units[1].order='auto';tick(enemy,1)
	check(enemy.units[1].soldiers.all(func(actor):return actor.has('position') and actor.personal_order=='idle' and actor.director_owned),'Enemy director owns actual individuals and waits for its first strategic evaluation')
	check(not enemy.units[1].charge and not enemy.units[1].has('penetration'),'Individual control does not run the legacy regiment charge path')
	var hunt=fixture();var hunter=hunt.units[0]
	hunt.Soldiers.command(hunt,[Vector2i(hunter.id,0)],'auto',Vector2.ZERO)
	var s=hunter.soldiers[0]
	var first=hunt.Soldiers.personal_target(hunt,hunter,0,s)
	check(not first.is_empty() and s.target_id>=0,'Individual idle acquisition uses the resource aggro range')
	if not first.is_empty():
		hunt.hurt(first.unit,first.unit.soldiers[first.near.slot].hp,'test',0.,first.near.slot)
		tick(hunt,10)
		check(s.target_slot!=first.near.slot or s.target_id!=first.unit.id,'Dead target is replaced by a living soldier')
	var flee=fixture();var fleeing=flee.units[0]
	flee.command([fleeing.id],'auto',Vector2.ZERO)
	for actor in fleeing.soldiers:actor.position.y=2050.
	fleeing.pos.y=2050.;fleeing.routing=true;tick(flee,45)
	check(fleeing.escaped and flee.Soldiers.personal_fled(flee,fleeing),'An autonomous routed unit leaves only after its individual survivors reach the boundary')
	var lure=fixture();var enemy_unit=lure.units[1];enemy_unit.order='auto'
	var lure_point: Vector2=lure.projection.affine_inverse()*lure.Soldiers.point(lure,enemy_unit,0)+Vector2(10,0)
	var decoy={'id':-99,'kind':'decoy','side':'ally','pos':lure_point,'hp':300.,'max_hp':300.,'remaining':10.,'hit_age':10.}
	lure.powers.decoys.append(decoy);tick(lure,10)
	check(decoy.hp<300.,'Autonomous soldiers can acquire and damage the existing divine decoy at its actual position')
	print('Autonomous soldiers: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
