extends SceneTree
func _initialize():call_deferred('run')
func run():
	var groups=int(OS.get_cmdline_user_args()[0])
	var app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/tmp/eagle-mix-qa.cfg'
	root.add_child(app)
	app.menu_view.get_node('TacticalTrial').pressed.emit()
	var t=app.active_trial;t.set_process(false)
	app.music.set_volume(0,0);app.sound.set_ambience('')
	app.sound.enabled=true;app.sound.volume=.75
	var r=t.rules;r.units.clear()
	var axis=Vector2(.85,-.52).normalized()
	var dir=r.ground_basis.affine_inverse().basis_xform(axis).normalized()
	var pairs=[]
	for i in groups:
		var delta:=Vector2((i-(groups-1)*.5)*470,0)
		var mid=Vector2(2360,800)+delta
		r.spawn('legion','enemy',mid+dir*395)
		var b=r.units.back();b.heading=dir.orthogonal();b.order='hold'
		r.spawn('cavalry','ally',mid-dir*395)
		var a=r.units.back();a.heading=dir;a.order='hold'
		pairs.append([a,b])
	t.start_button.pressed.emit()
	t.set_camera(r.projection*Vector2(2170,800)-Vector2(960,556))
	var impacts=[];var main_audio=[]
	t.contact_audio_started.connect(func(c):main_audio.append([c.time,c.attacker]))
	for i in 360:
		if i==24:
			for pair in pairs:r.command([pair[0].id],'attack',pair[1].pos,pair[1].id)
		t._process(1./60)
		for e in t.field.effects:
			if e.age==0 and e.get('mounted_contact',false):impacts.append([r.elapsed,e.attacker])
		if i%2==0:await process_frame
	print('MIX ',groups,' actual strikes ',impacts,' audible main onsets ',main_audio,' mixer ',t.voice_times)
	t.closed.emit();app.queue_free();await process_frame
	quit()
