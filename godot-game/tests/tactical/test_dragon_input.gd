extends SceneTree
var checks=0
var failures=0
func check(ok:bool,note:String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func run():
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-dragon-input.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	for language in ['zh','en']:
		app.language=language;t.retry();t.refresh();var button=t.loadout_buttons.guard;var position=button.position
		for i in t.rules.config.loadouts.guard.size():
			if t.rules.guard_variant=='dragon':break
			button.pressed.emit()
		check(t.rules.guard_variant=='dragon' and button.position==position and button.pressed.get_connections().size()==1,'Persistent '+language+' dragon selector')
		await process_frame
		check(t.buttons.guard.get_combined_minimum_size().x<=148. and t.buttons.guard.text.begins_with('巨龙' if language=='zh' else 'Dragon'),'Localized reserve fits authored width')
		t.combined_button.pressed.emit();t.refresh();var dragon=t.rules.alive('ally').filter(func(u):return u.get('archetype','')=='dragon')[0]
		check(t.field.regiments.dragon.values().all(func(texture):return texture!=null),'Actual ally/enemy/petrification art loaded')
		var person=t.rules.Soldiers.point(t.rules,dragon,0)
		check(t.field.regiment_contains(dragon,person-t.rules.projection*dragon.pos-Vector2(0,30)),'Dragon remains mouse-selectable at actual art')
		t.start_button.pressed.emit();t.refresh();check(not button.visible,'Variant selector hidden during battle')
		t.select_regiment(t.rules.alive('ally').find(dragon));t.refresh()
		var event=InputEventKey.new();event.physical_keycode=KEY_C;event.pressed=true;root.push_input(event,true)
		check(t.selected=='charge','Real C key enters dragon aim')
		var screen=(t.rules.projection*(dragon.pos+Vector2(0,-600))-t.camera_offset)*t.zoom
		for down in [true,false]:
			var mouse=InputEventMouseButton.new();mouse.position=screen;mouse.global_position=screen;mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=down;root.push_input(mouse,true)
		check(dragon.soldiers.all(func(a):return a.has('charge_run')),'Real click issues charge to all selected dragons')
		t.retry();check(t.rules.guard_variant=='' and t.field.effects.is_empty(),'Retry clears selection and effects')
	var baseline={};var results=[]
	for fps in [30,60,120]:
		t.retry();var r=t.rules;r.units.clear();r.spawn('guard','ally',Vector2(1000,1400),'dragon');r.spawn('guard','enemy',Vector2(1000,700),'dragon')
		for kind in r.reserve:r.reserve[kind]=0
		r.start();r.command(r.alive('ally').map(func(u):return u.id),'auto',Vector2.ZERO)
		check(r.Charges.issue(r,r.Soldiers.group_members(r.alive('ally')),Vector2(1000,700)),'Mirror starts with real charged actors')
		for frame in fps*150:
			t._process(1./fps)
			if r.phase!='battle':break
		check(r.phase in ['victory','defeat'],'Dragon mirror reaches result at '+str(fps)+'fps')
		var state={'time':snappedf(r.elapsed,.001),'phase':r.phase,'soldiers':r.units.map(func(u):return u.soldiers.map(func(a):return [snappedf(a.hp,.001),a.position.snapped(Vector2(.001,.001))]))}
		if baseline.is_empty():baseline=state
		else:check(state==baseline,'Dragon mirror health/positions/outcome same at '+str(fps)+'fps')
		results.append({'fps':fps,'time':r.elapsed,'phase':r.phase,'allies':r.strength('ally'),'enemies':r.strength('enemy')})
	var output_directory_error=DirAccess.make_dir_recursive_absolute('res://../output/sword-banner-reference/dragon')
	assert(output_directory_error==OK)
	FileAccess.open('res://../output/sword-banner-reference/dragon/full-battle.json',FileAccess.WRITE).store_string(JSON.stringify(results,'\t'))
	t.closed.emit();app.queue_free();await process_frame
	print('Dragon input: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
