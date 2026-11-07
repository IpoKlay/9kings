extends SceneTree
const Battle=preload('res://scripts/tactical/square_battle.gd')
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func key(value: Dictionary) -> Array:
	return [] if value.is_empty() else [value.unit.id,value.near.slot,value.near.distance,value.near.heading]
func _initialize():call_deferred('run')
func run():
	var r=Battle.new();r.units.clear();r.next_id=0
	r.spawn('archer','ally',Vector2(1050,1050));var archer=r.units[0]
	var rng=RandomNumberGenerator.new();rng.seed=47591
	for i in 40:
		r.spawn('legion' if i%2 else 'cavalry','enemy',Vector2(100+(i%5)*400,100+(i/5)*240))
		var u=r.units.back()
		for j in u.soldiers.size():
			r.Charges.detach(r,u,j)
			u.soldiers[j].position+=Vector2(rng.randf_range(-180,180),rng.randf_range(-120,120))
			if j%4==0:u.soldiers[j].hp*=.25
	r.start();r.enemy_director.active=false
	r.Soldiers.command(r,[Vector2i(archer.id,0)],'hold',Vector2.ZERO)
	var counts={}
	for u in r.alive('enemy'):
		for j in u.soldiers.size():counts[Vector2i(u.id,j)]=rng.randi_range(0,5)
	for i in 240:
		archer.soldiers[0].position=Vector2(rng.randf_range(0,2100),rng.randf_range(0,2100))
		var actor=archer.soldiers[0].duplicate(true)
		actor.personal_order=['hold','auto','attack_move','attack'][i%4]
		actor.cooldown=0.;actor.focus_id=r.units[1+i%40].id;actor.focus_slot=0
		actor.target_id=-1;actor.target_slot=-1
		r.Soldiers.begin_target_lookup(r)
		var fast=r.Soldiers.personal_target(r,archer,0,actor.duplicate(true),counts.duplicate(),true,true)
		r.personal_unit_lookup.clear();r.personal_target_bounds.clear()
		var slow=r.Soldiers.personal_target(r,archer,0,actor.duplicate(true),counts.duplicate(),true,true)
		check(key(fast)==key(slow),'Cached search preserves exact target/score tie order at sample '+str(i))
	var retargets=0
	for i in 120:
		archer.soldiers[0].position=Vector2(rng.randf_range(0,2100),rng.randf_range(0,2100))
		var actor=archer.soldiers[0].duplicate(true)
		actor.personal_order='attack';actor.target_id=r.units[1+i%40].id;actor.target_slot=0
		actor.focus_id=actor.target_id;actor.focus_slot=0;actor.retarget_timer=0.;actor.erase('attack_engaged')
		var target=r.Soldiers.identified_target(r,archer,0,actor.target_id,0)
		var fast_actor=actor.duplicate(true);var fast_counts=counts.duplicate()
		r.Soldiers.begin_target_lookup(r)
		var fast=r.Soldiers.retarget_pursuit(r,archer,0,fast_actor,target,fast_counts,1./60.)
		r.personal_unit_lookup.clear();r.personal_target_bounds.clear()
		var slow_actor=actor.duplicate(true);var slow_counts=counts.duplicate()
		var slow=r.Soldiers.retarget_pursuit(r,archer,0,slow_actor,target,slow_counts,1./60.)
		check(key(fast)==key(slow),'Pursuit bounding rejection preserves exact target at sample '+str(i))
		check(fast_actor==slow_actor and fast_counts==slow_counts,'Pursuit keeps focus, timers and ranged reservations unchanged at sample '+str(i))
		if not fast.is_empty() and (fast.unit.id!=actor.target_id or fast.near.slot!=actor.target_slot):retargets+=1
	check(retargets>0,'Pursuit fixture actually switches to a nearby replacement target')
	var near=r.units[1]
	near.soldiers[0].position=Vector2(1050,1050);archer.soldiers[0].position=Vector2(1050,1100)
	r.Soldiers.begin_target_lookup(r)
	check(r.Soldiers.identified_target(r,archer,0,near.id,0).near.distance==50.,'Lookup reads individual feet even when far from regiment center')
	near.soldiers[0].hp=0.
	check(r.Soldiers.identified_target(r,archer,0,near.id,0).is_empty(),'Lookup reads deaths occurring after cache construction')
	check(not r.Soldiers.identified_target(r,archer,0,near.id,0,false).is_empty(),'Pending lethal target remains available to release rules')
	near.soldiers[0].death_state=1
	check(r.Soldiers.identified_target(r,archer,0,near.id,0,false).is_empty(),'Collected death is absent even from release lookup')
	near.soldiers[1].hp=1.;near.escaped=true
	check(r.Soldiers.identified_target(r,archer,0,near.id,1).is_empty(),'Escaped unit stays excluded')
	check(r.Soldiers.identified_target(r,archer,0,-1,0).is_empty() and r.Soldiers.identified_target(r,archer,0,near.id,-1).is_empty(),'Absent target and slot return empty')
	r.units.erase(near);r.Soldiers.begin_target_lookup(r)
	check(not r.personal_unit_lookup.has(near.id),'Rebuild removes deleted units')
	r.step(1./60.)
	check(r.personal_unit_lookup.is_empty() and r.personal_target_bounds.is_empty(),'Simulation discards caches before physical motion and later projectile visits')
	var regroup=Battle.new();regroup.units.clear();regroup.next_id=0
	regroup.spawn('legion','enemy',Vector2(1000,1000));regroup.spawn('archer','ally',Vector2(1200,1000))
	var soldier=regroup.units[0];var bow=regroup.units[1]
	var home=regroup.Soldiers.ground_position(regroup,soldier,0)
	regroup.Charges.detach(regroup,soldier,0)
	soldier.soldiers[0].position=home-Vector2(.02,0);soldier.soldiers[0].personal_order='regroup'
	for slot in range(1,soldier.soldiers.size()):soldier.soldiers[slot].hp=0.
	regroup.Soldiers.total(soldier)
	regroup.Charges.detach(regroup,bow,0);bow.soldiers[0].personal_order='hold'
	bow.soldiers[0].position=home+Vector2(regroup.Soldiers.individual(regroup,bow).range,0)
	regroup.Soldiers.begin_target_lookup(regroup)
	regroup.Soldiers.step_personal(regroup,{'unit':soldier,'slot':0},[],{},1./60.)
	check(not soldier.soldiers[0].has('position') and not regroup.personal_target_bounds.has(soldier.id),'Regroup settling invalidates bounds when position changes inside the decision pass')
	var at_edge=regroup.Soldiers.personal_target(regroup,bow,0,bow.soldiers[0],{},true,true)
	check(not at_edge.is_empty() and at_edge.unit.id==soldier.id and at_edge.near.slot==0,'Later bowman can acquire the settled soldier exactly on the range boundary')
	print('Target lookup: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
