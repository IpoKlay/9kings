extends SceneTree
var checks=0
var failures=0
func check(ok:bool,note:String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func run():
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-projectile-input.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	var baseline={};var results=[];var direct:Array[Vector2]=[]
	for fps in [30,60,120]:
		t.retry();var r=t.rules;r.units.clear()
		for kind in ['archer','cavalry','siege']:
			r.config.types[kind].files=1;r.config.types[kind].hp=r.config.types[kind].individual.hp;r.contact_profiles[kind]=r.Contact.profile(kind,r.config.types[kind],true)
		r.spawn('archer','ally',Vector2(650,550));r.spawn('cavalry','enemy',Vector2(950,550))
		r.spawn('siege','ally',Vector2(650,1700));r.spawn('cavalry','enemy',Vector2(1050,1700))
		for u in r.units:u.order='hold'
		t.refresh();t.start_button.pressed.emit();r.enemy_director.active=false
		var paused_state={};var saw_arrow=false;var saw_stone=false
		for frame in fps*10:
			if frame==fps/5:r.Soldiers.command(r,[Vector2i(r.units[1].id,0)],'move',Vector2(1400,300),-1,-1,direct,true,'enemy')
			if frame==fps*4/5:r.Soldiers.command(r,[Vector2i(r.units[3].id,0)],'move',Vector2(1800,1700),-1,-1,direct,true,'enemy')
			if frame==fps:
				check(not r.volleys.is_empty(),'Pause fixture has an arrow in flight')
				paused_state={'time':r.elapsed,'arrows':r.volleys.duplicate(true),'stones':r.stones.duplicate(true)};t.get_node('BattleHUD/TopActions/PauseButton').pressed.emit()
			if frame==fps*3/2:
				check(paused_state=={'time':r.elapsed,'arrows':r.volleys,'stones':r.stones},'Actual pause button freezes both projectile families')
				t.get_node('BattleHUD/TopActions/PauseButton').pressed.emit()
			if frame in [fps*2,fps*4]:t.pace_button.pressed.emit()
			t._process(1./fps);saw_arrow=saw_arrow or not r.volleys.is_empty();saw_stone=saw_stone or not r.stones.is_empty()
		check(saw_arrow and saw_stone,'Actual firing produces both projectile families')
		check(is_equal_approx(r.elapsed,8.5),'Pause and half-speed buttons preserve expected simulation time')
		var state={'time':snappedf(r.elapsed,.001),'soldiers':r.units.map(func(u):return range(u.soldiers.size()).map(func(i):return [snappedf(u.soldiers[i].hp,.001),r.Soldiers.ground_position(r,u,i).snapped(Vector2(.001,.001))])),'arrows':r.volleys.map(func(p):return [p.point.snapped(Vector2(.001,.001)),p.pos.snapped(Vector2(.001,.001))]),'stones':r.stones.map(func(s):return [snappedf(s.age,.001),s.pos])}
		if baseline.is_empty():baseline=state
		else:check(state==baseline,'Moving-target projectile state and personal outcomes agree at '+str(fps)+'FPS')
		results.append({'fps':fps,'elapsed':r.elapsed,'hp':r.units.map(func(u):return u.hp),'arrows':r.volleys.size(),'stones':r.stones.size()})
		t.retry();check(t.rules.volleys.is_empty() and t.rules.stones.is_empty() and t.rules.config.types.archer.files==10,'Retry restores counts and clears projectiles')
	var output_directory_error=DirAccess.make_dir_recursive_absolute('res://../output/sword-banner-reference/projectile-motion')
	assert(output_directory_error==OK)
	FileAccess.open('res://../output/sword-banner-reference/projectile-motion/fps.json',FileAccess.WRITE).store_string(JSON.stringify(results,'\t'))
	t.closed.emit();app.queue_free();await process_frame
	print('Projectile input: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
