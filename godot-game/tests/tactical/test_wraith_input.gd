extends SceneTree
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func key(code):
	var e=InputEventKey.new();e.physical_keycode=code;e.pressed=true;root.push_input(e,true)
func click(point):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;root.push_input(e,true)
func run():
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-wraith-input.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	for language in ['zh','en']:
		app.language=language;t.retry();t.refresh()
		for i in 3:t.legion_variant_button.pressed.emit()
		check(t.rules.selected_variant('legion')=='wraith','Wraith reachable from normal deployment selector')
		check(t.buttons.legion.text.begins_with('怨灵' if language=='zh' else 'Wraiths'),'Reserve short name identifies wraith rather than inherited base variant')
		t.combined_button.pressed.emit();t.start_button.pressed.emit();var r=t.rules
		var u=r.alive('ally').filter(func(u):return u.get('archetype','')=='wraith')[0]
		t.squad_ids=[u.id];t.soldier_ids=[];t.refresh()
		check(t.blink_button.visible and not t.blink_button.disabled and t.blink_button.pressed.get_connections().size()==1,'Persistent blink control binds exactly once')
		check(t.blink_button.text.begins_with('B '+('闪现' if language=='zh' else 'Blink')),'Blink label follows language')
		var position=t.blink_button.position;t.refresh();check(t.blink_button.position==position,'Refresh preserves authored blink position')
		check(not t.volley_button.visible,'Wraith does not expose volley')
		check(t.field.regiments.has('wraith') and t.field.regiments.wraith.ally!=null,'Real wraith texture is imported')
		key(KEY_B);check(t.selected=='blink','B enters ability mode')
		key(KEY_ESCAPE);check(t.selected=='','Esc cancels without firing')
		t.blink_button.pressed.emit();check(t.selected=='blink','Button uses same targeting mode')
		var origin=r.Blink.center(r,r.Blink.ready(r,t.selected_people()));var goal=origin+Vector2(0,-180)
		t.set_camera(r.projection*origin-Vector2(960,540)/t.zoom)
		t.paused=true;click((r.projection*goal-t.camera_offset)*t.zoom)
		check(r.Blink.ready(r,t.selected_people()).size()==10,'Pause prevents instant cast')
		t._process(1.);check(r.Blink.ready(r,t.selected_people()).size()==10,'Pause consumes no cooldown')
		t.paused=false;click((r.projection*goal-t.camera_offset)*t.zoom);t.refresh()
		check(t.selected=='' and u.soldiers.all(func(a):return a.blink_cooldown==8.),'Mouse target casts all selected ready wraiths once')
		check(t.blink_button.disabled and t.blink_button.text.ends_with('8s'),'Cooldown shown and button disabled')
		var saved=u.soldiers.map(func(a):return a.position);key(KEY_B);check(t.selected=='' and saved==u.soldiers.map(func(a):return a.position),'B cannot repeat while cooling')
		t.soldier_ids=[Vector2i(u.id,0),Vector2i(r.alive('ally')[0].id,0)];t.squad_ids=[];t.refresh()
		check(not t.blink_button.visible,'Mixed incapable selection hides blink button, as reference HUD')
		t.retry();check(t.rules.selected_variant('legion')=='' and not t.rules.units.any(func(u):return u.soldiers.any(func(a):return a.get('blink_cooldown',0.)>0.)),'Retry clears variant and individual blink cooldown')
	var baseline={};var records=[]
	for fps in [30,60,120]:
		t.retry();var r=t.rules;r.units.clear()
		r.spawn('legion','ally',Vector2(1050,1200),'wraith');r.spawn('guard','enemy',Vector2(1050,900));r.spawn('legion','enemy',Vector2(1900,200))
		for unit in r.units:unit.order='hold'
		r.start();r.enemy_director.active=false;var w=r.units[0];var ids=r.Soldiers.group_members([w])
		var first=[];var second=[]
		for frame in fps*12:
			if frame==fps:
				check(r.Blink.issue(r,ids,Vector2(1050,970)),'Initial blink accepted at '+str(fps)+' FPS')
				first=w.soldiers.map(func(a):return a.position.snapped(Vector2(.001,.001)))
			if frame==fps*10:
				var origin=r.Blink.center(r,r.Blink.ready(r,ids))
				check(r.Blink.issue(r,ids,origin+Vector2(0,180)),'Second blink accepted after cooldown at '+str(fps)+' FPS')
				second=w.soldiers.map(func(a):return a.position.snapped(Vector2(.001,.001)))
			t._process(1./fps)
		var state={'first':first,'second':second,'phase':r.phase,'soldiers':r.units.map(func(unit):return range(unit.soldiers.size()).map(func(i):return [snappedf(unit.soldiers[i].hp,.001),r.Soldiers.ground_position(r,unit,i).snapped(Vector2(.001,.001)),snappedf(unit.soldiers[i].get('blink_cooldown',0.),.001)]))}
		if baseline.is_empty():baseline=state
		else:check(state==baseline,'Blink endpoints, melee wounds, cooldown and final positions match at '+str(fps)+' FPS')
		check(r.units[1].hp<r.units[1].max_hp,'Wraiths actually cleave opponents at '+str(fps)+' FPS')
		records.append({'fps':fps,'time':r.elapsed,'phase':r.phase,'wraith_hp':w.hp,'enemy_hp':r.units[1].hp,'first':first,'second':second})
	var output_directory_error=DirAccess.make_dir_recursive_absolute('res://../output/sword-banner-reference/wraith')
	assert(output_directory_error==OK)
	FileAccess.open('res://../output/sword-banner-reference/wraith/fps.json',FileAccess.WRITE).store_string(JSON.stringify(records,'\t'))
	t.closed.emit();app.queue_free();await process_frame
	print('Wraith input: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
