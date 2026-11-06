extends SceneTree
func _initialize():call_deferred('run')
func run():
	var app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/tmp/eagle-breach-perf.cfg'
	root.add_child(app)
	app.menu_view.get_node('TacticalTrial').pressed.emit()
	var t=app.active_trial
	t.set_process(false);t.combined_button.pressed.emit();t.start_button.pressed.emit()
	var r=t.rules
	var count=0
	for u in r.units:
		u.hp=1e6;u.max_hp=1e6
		count+=int(r.config.types[u.kind].soldiers)
	for i in 900:r.step(1./60);r.events.clear()
	t.set_camera(Vector2(200,100))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	var samples=[]
	for i in 360:
		var start=Time.get_ticks_usec()
		t._process(1./60)
		await RenderingServer.frame_post_draw
		# Readback fences this frame on the GPU, identical cost in both builds.
		var img=root.get_texture().get_image()
		if img==null:quit(1);return
		if i>=60:samples.append((Time.get_ticks_usec()-start)/1000.)
		await process_frame
	samples.sort()
	print('STRESS ',count,' figures, ',root.get_texture().get_size(),' 300 frames mean=',samples.reduce(func(a,b):return a+b)/samples.size(),' ms p95=',samples[284],' ms')
	t.closed.emit();app.queue_free();await process_frame
	quit()
