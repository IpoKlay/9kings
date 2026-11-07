extends SceneTree
const Pass=preload('res://scripts/tactical/pass_battle.gd')
var checks=0
var failures=0
func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func run():
	var r=Pass.new();r.deploy_defenders();r.start()
	var horse=r.alive('enemy').filter(func(u):return u.kind=='cavalry')[0]
	var original=r.Contact.feet(r,horse);var start: Vector2=horse.pos
	for tick in 60:r.step(1./60);r.events.clear()
	check(horse.pos.distance_to(start)<.01,'Reserve cavalry waits for the pass signal under individual control')
	check(horse.soldiers.all(func(actor):return actor.has('position')),'Pass enemies own physical soldier positions')
	var blocked=0;var entered=0;var burned=false;var costs=[]
	for tick in 10800:
		if r.phase!='battle':break
		if not burned:
			for barrel in r.barrels:
				if barrel.state=='ready' and r.alive('enemy').any(func(u):return u.pos.distance_to(barrel.pos)<140.):burned=r.ignite(barrel) or burned
		var begin=Time.get_ticks_usec()
		r.step(1./60);r.events.clear();costs.append(Time.get_ticks_usec()-begin)
		if tick%30==0:
			for u in r.units:
				if u.hp<=0 or u.get('escaped',false):continue
				for slot in u.soldiers.size():
					if u.soldiers[slot].hp<=0:continue
					var foot=r.Soldiers.point(r,u,slot)
					for rock: Rect2 in r.terrain.ROCKS:
						if rock.has_point(foot):blocked+=1
					if u.side=='enemy' and u.soldiers[slot].get('lane_stage',0)>=2:entered+=1
	check(r.phase in ['victory','defeat'],'Authored pass still reaches a normal result')
	check(blocked==0,'Autonomous live feet never occupy an authored rock')
	check(r.units.any(func(u):return u.side=='enemy' and u.pos.distance_to(u.get('deployment_pos',u.pos))>0.) or entered>0 or r.units.any(func(u):return u.hp<u.max_hp),'Pass enemies actually advance into contact or through a gate')
	check(burned,'Existing archer-to-oil interaction remains usable against the advancing attackers')
	costs.sort();var total=0.
	for cost in costs:total+=cost
	print('Pass simulation CPU ms mean=',total/costs.size()/1000.,' p95=',costs[int(costs.size()*.95)]/1000.)
	print('Autonomous pass: ',checks,' checks, ',failures,' failures; phase=',r.phase,' time=',r.elapsed,' rock_samples=',blocked,' gate_samples=',entered)
	quit(1 if failures else 0)
