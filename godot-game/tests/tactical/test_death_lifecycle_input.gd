extends SceneTree
var checks=0
var failures=0
func check(ok:bool,note:String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func run():
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-death-input.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	var baseline={};var results=[]
	for fps in [30,60,120]:
		t.retry();var r=t.rules;r.units.clear()
		for kind in ['archer','legion']:
			r.config.types[kind].files=1;r.config.types[kind].hp=r.config.types[kind].individual.hp;r.contact_profiles[kind]=r.Contact.profile(kind,r.config.types[kind],true)
		r.spawn('archer','ally',Vector2(1000,1000));r.spawn('legion','enemy',Vector2(1029,1000));r.spawn('legion','enemy',Vector2(1200,1000));r.spawn('legion','ally',Vector2(1200,1050))
		for u in r.units:
			u.order='hold';r.Charges.detach(r,u,0);u.soldiers[0].position=u.pos;u.soldiers[0].personal_order='hold';u.soldiers[0].cooldown=999.
		t.refresh();t.start_button.pressed.emit();r.enemy_director.active=false
		var a=r.units[0];var killer=r.units[1];var b=r.units[2];r.hurt(a,a.hp-1.,'',0.,0)
		killer.soldiers[0].target_id=a.id;killer.soldiers[0].target_slot=0;killer.soldiers[0].attack_age=.43;killer.soldiers[0].attack_pending=true
		b.soldiers[0].shield_wall=true;b.soldiers[0].wall_heading=Vector2.LEFT
		for distance in [2.,12.,22.]:
			var p=r.deal_blow(a,b,20.,{}, {'attacker_slot':0,'target_slot':0,'release_delay':0.});p.point=b.pos+Vector2(-distance,0);p.speed=600.
		for frame in fps/10:t._process(1./fps)
		check(b.hp==68. and a.soldiers[0].death_state==2,'Actual trial processes4/8/20 damage across death phases at '+str(fps))
		check(r.volleys.is_empty() and r.projectile_serial==3,'All three source handles resolve exactly once')
		var snapshot=r.units.duplicate(true);var elapsed=r.elapsed
		t.get_node('BattleHUD/TopActions/PauseButton').pressed.emit()
		for frame in fps/5:t._process(1./fps)
		check(snapshot==r.units and elapsed==r.elapsed,'Pause preserves all actor lifecycle fields')
		t.get_node('BattleHUD/TopActions/PauseButton').pressed.emit();t.pace_button.pressed.emit()
		for frame in fps/5:t._process(1./fps)
		check(is_equal_approx(r.elapsed,.2),'Half speed preserves fixed simulation death order')
		var state={'hp':r.units.map(func(u):return u.hp),'lifetime':r.units.map(func(u):return u.soldiers[0].death_state),'serial':r.projectile_serial,'time':snappedf(r.elapsed,.001)}
		if baseline.is_empty():baseline=state
		else:check(state==baseline,'Death and projectile outcomes identical across render rates')
		results.append({'fps':fps,'state':state})
		t.retry();check(t.rules.projectile_serial==0 and t.rules.volleys.is_empty() and t.rules.stones.is_empty() and t.rules.units.all(func(u):return u.soldiers.all(func(actor):return actor.death_state==0)),'Retry creates fresh registered actors without delayed destruction or shot serials')
	var output_directory_error=DirAccess.make_dir_recursive_absolute('res://../output/sword-banner-reference/death-lifecycle')
	assert(output_directory_error==OK)
	FileAccess.open('res://../output/sword-banner-reference/death-lifecycle/fps.json',FileAccess.WRITE).store_string(JSON.stringify(results,'\t'))
	t.closed.emit();app.queue_free();await process_frame
	print('Death lifecycle input: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
