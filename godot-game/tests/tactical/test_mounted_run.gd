extends SceneTree
const DT=1./60
const Pass=preload('res://scripts/tactical/pass_battle.gd')
var failures=0
var checks=0
func _initialize():call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;push_error(message)

func setup(start: Vector2,end: Vector2):
	var r=Pass.new()
	r.units.clear()
	r.spawn('cavalry','ally',r.terrain.inverse*start)
	r.spawn('guard','enemy',r.terrain.inverse*end)
	r.units[0].heading=r.units[0].pos.direction_to(r.units[1].pos)
	r.units[1].order='hold'
	r.start()
	r.command([r.units[0].id],'attack',r.units[1].pos,r.units[1].id)
	return r

func first_hit(r,limit: int=1300) -> Dictionary:
	var horse=r.units[0]
	for tick in limit:
		r.step(DT)
		for e in r.events:
			if e.get('attacker',-1)==horse.id:
				r.events.clear()
				return e
		r.events.clear()
	return {}

func run():
	var r=setup(Vector2(1500,890),Vector2(1600,890))
	var horse=r.units[0]
	check(not horse.charge and horse.clear_run==0,'Fresh deployment starts at rest')
	check(first_hit(r).get('kind','')=='hit','Point-blank attack stays ordinary')
	r=setup(Vector2(1260,890),Vector2(1620,890))
	check(first_hit(r).get('kind','')=='hit','Insufficient clear ground before contact')
	r=setup(Vector2(540,890),Vector2(1540,890))
	horse=r.units[0]
	var entered=false
	var left=false
	var close_hit=''
	var run_at_exit=0.
	for tick in 1100:
		r.step(DT)
		if r.terrain.touches_gate('cavalry',horse.pos):entered=true
		elif entered and not left:
			left=true
			run_at_exit=horse.clear_run
		for e in r.events:
			if e.get('attacker',-1)==horse.id:close_hit=e.kind
		if close_hit!='':break
		r.events.clear()
	check(entered and left and run_at_exit<3 and close_hit=='hit','Close enemy just beyond gate admits only ordinary melee')
	r=setup(Vector2(1250,930),Vector2(2100,910))
	horse=r.units[0]
	var target=r.units[1]
	for i in 550:
		r.step(DT)
		if horse.charge:break
	check(horse.charge,'Continuous target approach pays for full-speed charge')
	var before: Vector2=horse.pos
	var dir: Vector2=horse.heading
	var diversion: Vector2=before+dir.orthogonal()*130
	check(r.command([horse.id],'move',diversion),'Accept sharp diversion')
	r.step(DT)
	check(not horse.charge and horse.clear_run==0 and before.distance_to(horse.pos)/DT<139*.5,'Turn brakes immediately and loses qualifying distance')
	r=setup(Vector2(1250,930),Vector2(2100,910))
	horse=r.units[0];target=r.units[1]
	var hit=first_hit(r)
	check(hit.get('mounted_contact',false) and horse.recover_until>r.elapsed,'Real run ends in one mounted impact and recovery')
	var recover_until: float=horse.recover_until
	for i in 12:r.command([horse.id],'attack',target.pos,target.id)
	check(horse.recover_until==recover_until and not horse.charge,'Repeated orders cannot clear recovery')
	check(first_hit(r).get('kind','')=='hit','Continued contact gets a normal blow')
	r=setup(Vector2(670,890),Vector2(1950,890))
	horse=r.units[0]
	var block=r.terrain.inverse*Vector2(950,890)
	r.spawn('guard','ally',block);r.units.back().order='hold'
	r.command([horse.id],'move',r.terrain.inverse*Vector2(1460,890))
	var stalled=0
	for i in 600:
		var pos: Vector2=horse.pos
		var feet: float=horse.march_distance
		r.step(DT)
		if horse.obstruction=='queue' and horse.pos==pos and horse.march_distance==feet and not horse.charge and horse.clear_run==0:stalled+=1
	check(stalled>60,'Waiting at the gate cannot cycle legs or bank distance')
	r=setup(Vector2(1260,890),Vector2(2100,890))
	horse=r.units[0]
	horse.combat_stats=r.config.types.cavalry.duplicate()
	horse.combat_stats.speed*=.65
	check(first_hit(r).get('kind','')=='hit','Long straight run below impact speed does ordinary damage')
	r=setup(Vector2(700,727),Vector2(1550,665))
	horse=r.units[0]
	var edge: Vector2=r.terrain.inverse*Vector2(1020,790)
	var clear_before=false
	var refused=false
	for i in 200:
		var feet: float=horse.march_distance
		var pos: Vector2=horse.pos
		if not r.ride(horse,edge,139,DT):
			refused=horse.pos==pos and horse.march_distance==feet and horse.clear_run==0 and not horse.charge
			break
		if horse.clear_run>40:clear_before=true
	check(clear_before and refused,'Rock clipping cancels prior run and never advances stride on a rejected step')
	# Drive the actual scene clock through pause and inspect the eight-direction renderer.
	var main=load('res://scenes/main.tscn').instantiate()
	main.settings_path='/tmp/eagle-gait-freeze.cfg'
	root.add_child(main)
	main.menu_view.get_node('%TacticalTrial').pressed.emit()
	var t=main.active_trial;t.set_process(false)
	t.rules=setup(Vector2(1250,930),Vector2(2100,910))
	horse=t.rules.units[0]
	for i in 550:
		t._process(DT)
		if horse.gait=='sprint':break
	t.paused=true
	var state=horse.duplicate(true)
	for i in 60:t._process(DT)
	check(horse==state and horse.gait=='sprint','Pause freezes sprint distance, location, cooldown and stride')
	t.paused=false
	for i in 160:
		t._process(DT)
		if horse.gait=='impact':break
	t.paused=true
	var clock: float=t.rules.elapsed
	state=horse.duplicate(true)
	for i in 60:t._process(DT)
	check(horse==state and clock==t.rules.elapsed and horse.recover_until>clock,'Pause freezes post-impact recovery')
	horse.erase('sprite_bearing')
	var sector=t.field.mounted_bearing(horse,0)
	for angle in [21,24,22,23,19,25]:check(t.field.mounted_bearing(horse,deg_to_rad(angle))==sector,'No flicker around 22.5 degrees')
	check(t.field.mounted_bearing(horse,deg_to_rad(32))==1 and t.field.mounted_bearing(horse,deg_to_rad(20))==1 and t.field.mounted_bearing(horse,deg_to_rad(14))==0,'Hysteresis changes direction in both directions')
	t.closed.emit()
	main.queue_free()
	await process_frame
	print('Mounted run: ',checks,' checks, ',failures,' failures')
	quit(1 if failures else 0)
