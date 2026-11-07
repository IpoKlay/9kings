extends SceneTree
const OUT='res://../output/sword-banner-reference/individual-battle/'
func _initialize():call_deferred('run')
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/tmp/eagle-individual-battle-capture.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit()
	var t=app.active_trial;t.set_process(false)
	t.combined_button.pressed.emit();t.start_button.pressed.emit()
	t.assault_button.pressed.emit()
	t.set_camera(t.rules.projection*Vector2(1050,1100)-Vector2(960,540)/t.zoom)
	var report={'events':{},'result':'','time':0.}
	var result_frame=-1
	for frame in 3000:
		if frame==240:
			t.paused=true
			t.squad_ids=[t.rules.alive('ally').filter(func(u):return u.kind=='spear')[0].id]
			t.start_button.pressed.emit()
		if frame==300:t.paused=false;t.assault_button.pressed.emit()
		t._process(1./60)
		var r=t.rules
		for u in r.units:
			if not u.get('last_contact',{}).is_empty() and not report.events.has('cavalry'):report.events.cavalry=frame/60.
		for effect in t.field.effects:
			if effect.kind=='stone_impact' and not report.events.has('stone'):report.events.stone=frame/60.
		if r.phase!='battle' and result_frame<0:
			result_frame=frame;report.result=r.phase;report.time=r.elapsed
		await process_frame
		if frame in [30,900] or frame==result_frame:
			RenderingServer.force_draw();root.get_texture().get_image().save_png(OUT+'frame-%04d.png'%frame)
		if result_frame>=0 and frame>result_frame+90:break
	t.start_button.pressed.emit();t.refresh()
	report.retry=t.rules.phase=='deploy' and t.rules.casualties.is_empty() and t.rules.stones.is_empty()
	for frame in 30:await process_frame
	FileAccess.open(OUT+'report.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
	print('Full battle capture ',JSON.stringify(report))
	t.closed.emit();app.queue_free();await process_frame;quit()
