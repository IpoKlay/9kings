extends SceneTree
const OUT='res://../output/sword-banner-reference/individual/'
func _initialize():call_deferred('run')
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/tmp/eagle-individual-capture.cfg'
	root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit()
	var t=app.active_trial;t.set_process(false)
	app.sound.enabled=false;t.field.clean_capture=true
	var r=t.rules;r.units.clear()
	r.spawn('legion','ally',Vector2(950,900))
	r.spawn('legion','enemy',Vector2(1195,920))
	for u in r.units:u.heading=Vector2.UP;u.formation_heading=u.heading;u.order='hold'
	t.reset_camera();t.set_camera(r.projection*Vector2(1075,900)-Vector2(960,540)/t.zoom)
	t.refresh();t.start_button.pressed.emit()
	var trace=FileAccess.open(OUT+'actors.jsonl',FileAccess.WRITE)
	for frame in 420:
		t._process(1./60)
		t.field.effects.clear()
		trace.store_line(JSON.stringify({'frame':frame,'time':r.elapsed,'a':r.units[0].soldiers,'b':r.units[1].soldiers,'bodies':r.casualties.size()}))
		await process_frame
		if frame in [8,55,148,220,400]:
			RenderingServer.force_draw()
			root.get_texture().get_image().save_png(OUT+'frame-%03d.png'%frame)
	trace.close()
	print('Individual capture: ally HP=',r.units[0].hp,' enemy HP=',r.units[1].hp,' bodies=',r.casualties.size())
	t.closed.emit();app.queue_free()
	await process_frame
	quit()
