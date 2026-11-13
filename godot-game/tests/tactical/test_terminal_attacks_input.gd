extends SceneTree
var checks=0
var failures=0
func check(ok:bool,note:String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func run():
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-terminal-input.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	var baseline={};var results=[]
	for fps in [30,60,120]:
		t.retry();var r=t.rules;r.units.clear()
		for kind in ['archer','legion']:
			r.config.types[kind].files=1;r.config.types[kind].hp=r.config.types[kind].individual.hp;r.contact_profiles[kind]=r.Contact.profile(kind,r.config.types[kind],true)
		r.spawn('legion','enemy',Vector2(971,1000));r.spawn('archer','ally',Vector2(1000,1000));r.spawn('legion','enemy',Vector2(1200,1000));r.spawn('legion','ally',Vector2(1600,1600))
		for u in r.units:
			u.order='hold';r.Charges.detach(r,u,0);var a=u.soldiers[0];a.position=u.pos;a.personal_order='hold';a.cooldown=999.
		t.refresh();t.start_button.pressed.emit();r.enemy_director.active=false
		var killer=r.units[0];var source=r.units[1];var target=r.units[2];r.hurt(source,source.hp-1.,'',0.,0)
		for pair in [[killer,source,.43],[source,target,.59]]:
			var a=pair[0].soldiers[0];a.target_id=pair[1].id;a.target_slot=0;a.attack_pending=true;a.attack_age=pair[2]
		var snapshot=r.units.duplicate(true);t.get_node('BattleHUD/TopActions/PauseButton').pressed.emit()
		for frame in fps/5:t._process(1./fps)
		check(r.units==snapshot and r.projectile_serial==0,'Pause before terminal release changes neither windup nor shot count')
		t.get_node('BattleHUD/TopActions/PauseButton').pressed.emit();t.pace_button.pressed.emit()
		for frame in fps*2:t._process(1./fps)
		check(is_equal_approx(r.elapsed,1.),'Half speed reaches one simulated second')
		check(source.hp==0 and source.soldiers[0].death_state==2,'Earlier attacker kills source and its registration is collected')
		check(target.hp==85. and r.projectile_serial==1 and r.volleys.is_empty(),'One terminal arrow hits15 after source removal at '+str(fps)+'FPS')
		var state={'hp':r.units.map(func(u):return u.hp),'lifetime':r.units.map(func(u):return u.soldiers[0].death_state),'serial':r.projectile_serial,'time':snappedf(r.elapsed,.001)}
		if baseline.is_empty():baseline=state
		else:check(state==baseline,'Terminal attack outcomes agree across render rates')
		results.append({'fps':fps,'state':state})
		t.retry();check(t.rules.projectile_serial==0 and t.rules.volleys.is_empty() and t.rules.units.all(func(u):return u.soldiers.all(func(a):return a.death_state==0 and not a.get('attack_pending',false))),'Retry clears terminal attack and death state')
	var output_directory_error=DirAccess.make_dir_recursive_absolute('res://../output/sword-banner-reference/terminal-attacks')
	assert(output_directory_error==OK)
	FileAccess.open('res://../output/sword-banner-reference/terminal-attacks/fps.json',FileAccess.WRITE).store_string(JSON.stringify(results,'\t'))
	t.closed.emit();app.queue_free();await process_frame
	print('Terminal input: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
