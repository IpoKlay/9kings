extends SceneTree
const OUT='res://../output/sword-banner-reference/attack-timing/'
func _initialize():call_deferred('run')
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-timing-capture.cfg';root.add_child(app)
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false;t.field.clean_capture=true
	var r=t.rules;r.units.clear()
	for k in 3:
		var x=760.+k*345.;var kind=['legion','archer','siege'][k]
		r.spawn(kind,'ally',Vector2(x,1300));r.spawn('legion','enemy',Vector2(x,1300-[40.,300.,400.][k]))
	for u in r.units:u.order='hold'
	t.set_camera(r.projection*Vector2(1110,1140)-Vector2(960,540)/t.zoom)
	t.refresh();t.start_button.pressed.emit()
	for u in r.units:
		for i in u.soldiers.size():
			u.soldiers[i].position=u.pos+Vector2((i-(u.soldiers.size()-1)*.5)*25.,0.)
			u.soldiers[i].cooldown=60.
	var report={'first_start':{},'first_release':{}};var trace=FileAccess.open(OUT+'attacks-frames.jsonl',FileAccess.WRITE)
	for frame in 480:
		if frame==60:
			for k in 3:
				for actor in r.units[k*2].soldiers:actor.cooldown=0.
				r.command([r.units[k*2].id],'attack',r.units[k*2+1].pos,r.units[k*2+1].id)
			root.gui_disable_input=true;t.set_process_input(false);t.set_process_unhandled_input(false)
		t._process(1./60)
		for u in r.units:
			if u.side!='ally':continue
			if not report.first_start.has(u.kind) and u.soldiers.any(func(s):return s.attack_age==0.):report.first_start[u.kind]=frame
		for e in t.field.effects:
			if e.age==0.:
				for u in r.units:
					if u.side=='ally' and u.id==e.get('attacker',-1) and not report.first_release.has(u.kind):report.first_release[u.kind]=frame
		if not r.volleys.is_empty() and not report.first_release.has('archer'):report.first_release.archer=frame
		if not r.stones.is_empty() and not report.first_release.has('siege'):report.first_release.siege=frame
		trace.store_line(JSON.stringify({'frame':frame,'units':r.units.map(func(u):return {'kind':u.kind,'side':u.side,'soldiers':u.soldiers}),'arrows':r.volleys,'stones':r.stones}))
		await process_frame
		if frame in [59,75,100,120,180,479]:RenderingServer.force_draw();root.get_texture().get_image().save_png(OUT+'attacks-%04d.png'%frame)
	trace.close()
	FileAccess.open(OUT+'attacks-report.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
	print('Attack timing capture ',JSON.stringify(report))
	t.closed.emit();app.queue_free();await process_frame;quit()
