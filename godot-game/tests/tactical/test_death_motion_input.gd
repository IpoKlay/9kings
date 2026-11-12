extends SceneTree
var checks=0
var failures=0
func check(ok:bool,note:String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func click(p:Vector2,double=false):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.double_click=double;root.push_input(e,true)
func key(code:Key):
	var e=InputEventKey.new();e.physical_keycode=code;e.pressed=true;root.push_input(e,true)
func run():
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-death-motion-input.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	var baseline={};var results=[]
	for fps in [30,60,120]:
		t.retry();var r=t.rules;r.units.clear()
		for kind in ['legion','cavalry']:
			r.config.types[kind].files=1;r.config.types[kind].hp=r.config.types[kind].individual.hp;r.contact_profiles[kind]=r.Contact.profile(kind,r.config.types[kind],true)
		r.spawn('legion','enemy',Vector2(1000,1000));r.spawn('cavalry','ally',Vector2(1030,1000));r.spawn('legion','enemy',Vector2(1700,1700))
		for u in r.units:
			u.order='hold';r.Charges.detach(r,u,0);var a=u.soldiers[0];a.position=u.pos;a.personal_order='hold';a.cooldown=999.
		var victim=r.units[0];var horse=r.units[1];r.hurt(victim,victim.hp-1.,'',0.,0)
		t.set_camera(r.projection*Vector2(1200,1000)-Vector2(960,540)/t.zoom);t.refresh();t.start_button.pressed.emit();r.enemy_director.active=false
		click((r.Soldiers.point(r,horse,0)-t.camera_offset)*t.zoom-Vector2(0,20),true);key(KEY_C)
		click((r.projection*Vector2(700,1000)-t.camera_offset)*t.zoom)
		check(horse.soldiers[0].has('charge_run'),'Actual selection and C issue lethal probe charge at '+str(fps))
		horse.soldiers[0].charge_run.velocity=Vector2(-240,0);horse.soldiers[0].velocity=Vector2(-240,0)
		t.get_node('BattleHUD/TopActions/PauseButton').pressed.emit();var frozen=r.units.duplicate(true)
		for frame in fps/5:t._process(1./fps)
		check(r.units==frozen and r.casualties.is_empty(),'Pause preserves pre-contact actors and creates no bodies')
		t.get_node('BattleHUD/TopActions/PauseButton').pressed.emit();t.pace_button.pressed.emit()
		for frame in fps/5:t._process(1./fps)
		check(is_equal_approx(r.elapsed,.1),'Half speed still advances the same six physical steps')
		check(victim.hp==0. and victim.soldiers[0].death_state==2 and r.casualties.size()==1 and r.casualties[0].step==2,'Actual trial emits exactly one corpse on the second simulation step')
		check(r.casualties[0].foot==r.projection*victim.soldiers[0].position and r.casualties[0].ground_point.x<980.,'Runtime corpse follows final lethal impulse position')
		var state={'hp':r.units.map(func(u):return u.hp),'time':snappedf(r.elapsed,.001),'body_point':r.casualties[0].ground_point.snapped(Vector2(.001,.001)),'body_step':r.casualties[0].step,'body_time':snappedf(r.casualties[0].time,.000001),'visible':r.Contact.drawable(victim,0)}
		if baseline.is_empty():baseline=state
		else:check(state==baseline,'Death foot and emission tick agree across render rates')
		results.append({'fps':fps,'state':state});t.retry()
		check(t.rules.casualties.is_empty() and t.rules.casualty_serial==0 and t.rules.units.all(func(u):return u.soldiers.all(func(a):return a.death_state==0)),'Retry clears corpse records and registration states')
	var output_directory_error=DirAccess.make_dir_recursive_absolute('res://../output/sword-banner-reference/death-motion')
	assert(output_directory_error==OK)
	FileAccess.open('res://../output/sword-banner-reference/death-motion/fps.json',FileAccess.WRITE).store_string(JSON.stringify(results,'\t'))
	t.closed.emit();app.queue_free();await process_frame
	print('Death motion input: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
