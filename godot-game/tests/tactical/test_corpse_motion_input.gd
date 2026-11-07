extends SceneTree
var checks=0
var failures=0
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred('run')
func run():
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-corpse-input.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	for fps in [30,60,120]:
		t.retry();var r=t.rules;r.units.clear()
		r.spawn('legion','enemy',Vector2(1050,1000));r.spawn('cavalry','ally',Vector2(1050,1400));t.refresh();t.start_button.pressed.emit()
		r.hurt(r.units[0],100000.);t._process(1./30)
		check(r.phase=='victory' and r.casualties.size()==10,'Terminal casualties are emitted through actual battle at '+str(fps))
		var m=r.casualties[0].motion;var initial_age:float=m.age;var initial_x:PackedFloat32Array=m.x.duplicate();var elapsed=r.elapsed
		t.get_node('BattleHUD/TopActions/PauseButton').pressed.emit()
		for frame in fps:t._process(1./fps)
		check(m.age==initial_age and m.x==initial_x,'Real pause freezes body rig, equipment and fading after result')
		t.get_node('BattleHUD/TopActions/PauseButton').pressed.emit();t.pace_button.pressed.emit()
		for frame in fps:t._process(1./fps)
		check(is_equal_approx(m.age-initial_age,.5) and r.elapsed==elapsed,'Real half-speed advances only cosmetic lifetime after result')
		t.pace_button.pressed.emit()
		for frame in fps*3:t._process(1./fps)
		check(r.casualties.is_empty() and r.phase=='victory' and r.elapsed==elapsed,'Bodies expire while battle result and elapsed combat time stay frozen')
		t.retry();check(t.rules.casualties.is_empty() and t.rules.casualty_serial==0,'Retry leaves no body motion or prior random seed index')
	t.closed.emit();app.queue_free();await process_frame
	print('Corpse motion input: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
