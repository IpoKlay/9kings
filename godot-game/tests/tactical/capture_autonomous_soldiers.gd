extends SceneTree
func _initialize():call_deferred('run')
func run():
	var out='res://../output/sword-banner-reference/autonomy/'
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-autonomy-capture.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false;t.field.clean_capture=true
	var r=t.rules;r.units.clear()
	r.spawn('legion','ally',Vector2(1000,1200));r.spawn('legion','enemy',Vector2(650,850));r.spawn('legion','enemy',Vector2(1350,850))
	for unit in r.units:unit.order='hold'
	var a=r.units[0]
	t.set_camera(r.projection*Vector2(1000,1020)-Vector2(960,540)/t.zoom)
	t.refresh();t.start_button.pressed.emit()
	var trace=FileAccess.open(out+'frames.jsonl',FileAccess.WRITE)
	for frame in 600:
		if frame==24:
			var p=(r.Soldiers.point(r,a,4)-t.camera_offset)*t.zoom-Vector2(0,20)
			for down in [true,false]:
				var e=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.double_click=true;root.push_input(e,true)
		if frame==48:
			var e=InputEventKey.new();e.physical_keycode=KEY_A;e.pressed=true;root.push_input(e,true)
		t._process(1./60);t.field.effects.clear()
		trace.store_line(JSON.stringify({'frame':frame,'time':r.elapsed,'center':a.pos,'actors':a.soldiers}))
		await process_frame
		if frame in [40,100,180,300,480]:
			RenderingServer.force_draw();root.get_texture().get_image().save_png(out+'frame-%04d.png'%frame)
	trace.close()
	FileAccess.open(out+'report.json',FileAccess.WRITE).store_string(JSON.stringify({'input':'Main menu → battle → double-click regiment → A','frames':600,'simulation_seconds':r.elapsed,'zoom':t.zoom,'phase':r.phase,'actors':a.soldiers},'\t'))
	print('Autonomy native capture complete, phase=',r.phase)
	t.closed.emit();app.queue_free();await process_frame;quit()
