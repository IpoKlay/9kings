extends SceneTree
## Real-time engine loop. No manual simulation stepping or forced rendering.
const OUT='res://../output/audited-sync/live/'
var app
var rows=[]
func _initialize():call_deferred('run')
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.always_on_top=true
	Engine.max_fps=60;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	AudioServer.set_bus_mute(0,true)
	app=load('res://scenes/main.tscn').instantiate();app.settings_path=OUT+'settings.cfg';root.add_child(app);app.hide();app.set_process(false)
	for optimized in [false,true]:
		seed(20261109)
		var t=load('res://scenes/tactical_trial.tscn').instantiate();t.rules=t.WhiteboardBattle.new(false);t.app=app
		root.add_child(t)
		t.field.set_unit_atlas_enabled(optimized)
		t.combined_button.pressed.emit();t.start_button.pressed.emit()
		t.rules.command(t.rules.alive('ally').map(func(u):return u.id),'auto',Vector2.ZERO)
		t.set_camera(t.rules.bounds.get_center()-Vector2(960,540))
		var people=0
		for u in t.rules.units:people+=u.soldiers.size()
		await create_timer(2.).timeout
		var times=[];var cpu=[];var draws=[];var first=Time.get_ticks_usec();var previous=first
		while Time.get_ticks_usec()-first<30000000:
			await RenderingServer.frame_post_draw
			var now=Time.get_ticks_usec();times.append((now-previous)/1000.);previous=now
			cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.)
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		times.sort();cpu.sort();draws.sort()
		var im=root.get_texture().get_image();im.save_png(OUT+('atlas' if optimized else 'native')+'.png')
		var row={'atlas':optimized,'people':people,'size':str(im.get_size()),'seconds':(previous-first)/1000000.,'frames':times.size(),
			'mean_ms':times.reduce(func(a,b):return a+b,0.)/times.size(),'p95_ms':times[int(times.size()*.95)],
			'over_50ms':times.filter(func(v):return v>50.).size(),'process_p95_ms':cpu[int(cpu.size()*.95)],'draws_median':draws[draws.size()/2],
			'texture_bytes':Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),'static_bytes':Performance.get_monitor(Performance.MEMORY_STATIC),
			'sim_seconds':t.rules.elapsed,'phase':t.rules.phase}
		t.queue_free();await process_frame;await create_timer(.3).timeout
		row.texture_bytes_after_exit=Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
		rows.append(row);print('LIVE ',row)
	FileAccess.open(OUT+'results.json',FileAccess.WRITE).store_string(JSON.stringify(rows,'\t'))
	app.queue_free();await process_frame;await create_timer(.15).timeout;quit()
