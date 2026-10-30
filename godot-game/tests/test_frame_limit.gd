extends SceneTree
const Store=preload('res://scripts/data/settings_store.gd')
const PATH='res://../output/frame-rate/test-settings.cfg'
var app
var checks=0
var failures=0
func _init(): call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)
func click(control: Control):
	for down in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=control.get_global_rect().get_center();event.global_position=event.position
		event.pressed=down;event.button_index=MOUSE_BUTTON_LEFT
		root.push_input(event,true)
	await process_frame
func capture(name: String):
	if DisplayServer.get_name()=='headless': return
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png('res://../output/frame-rate/'+name+'.png')
func boot():
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path=PATH
	root.add_child(app);current_scene=app;app.sound.enabled=false
func run():
	DirAccess.make_dir_recursive_absolute('res://../output/frame-rate')
	for suffix in ['','.bak','.tmp']:
		if FileAccess.file_exists(PATH+suffix): DirAccess.remove_absolute(PATH+suffix)
	var legacy=ConfigFile.new()
	legacy.set_value('settings','volume',.35);legacy.set_value('settings','language','zh');legacy.save(PATH)
	check(Store.read_settings(PATH).fps_limit==60 and Store.read_settings(PATH).volume==.35,'Old settings gain 60 FPS without losing sound settings')
	for invalid in [-1,15,59.9,144,'120',true,INF,NAN,null]:
		check(Store.normalized({'fps_limit':invalid}).fps_limit==60,'Invalid frame limit falls back safely: '+str(invalid))
	for valid in [30.0,60.0,120.0,0.0]:
		check(Store.normalized({'fps_limit':valid}).fps_limit==int(valid),'JSON numeric caps and integer config caps are both accepted')
	boot()
	check(Engine.max_fps==60,'Default frame cap applies at boot')
	app.open_dialog('settings')
	for limit in Store.FRAME_LIMITS:
		await click(app.modal.get_child(1).get_node('FrameLimit_'+str(limit)))
		check(Engine.max_fps==limit and app.prefs.fps_limit==limit,'Actual engine cap changes via pointer: '+str(limit))
		check(Store.read_settings(PATH).fps_limit==limit,'Selected cap is saved: '+str(limit))
		check(app.modal.get_child(1).get_node('FrameLimit_'+str(limit)).text.begins_with('✓ '),'Current cap visibly marked')
		for option in app.modal.get_child(1).get_children():
			if option is Button and String(option.name).begins_with('FrameLimit_'):
				var face=option.get_theme_stylebox('normal')
				var available=option.size.x-face.get_content_margin(SIDE_LEFT)-face.get_content_margin(SIDE_RIGHT)
				check(app.font.get_string_size(option.text,HORIZONTAL_ALIGNMENT_LEFT,-1,option.get_theme_font_size('font_size')).x<=available,'Frame option text fits: '+option.text)
				check(option.get_rect().end.x<=700,'Frame option stays inside settings panel')
		if DisplayServer.get_name()!='headless':
			check(DisplayServer.window_get_vsync_mode()==DisplayServer.VSYNC_DISABLED,'VSync does not impose a second cap')
			for i in 8: await process_frame
			var start=Time.get_ticks_usec();var frames=0
			while Time.get_ticks_usec()-start<800000:
				await process_frame
				frames+=1
			var actual=frames*1000000.0/(Time.get_ticks_usec()-start)
			print('FRAME CAP %d: %.1f measured FPS'%[limit,actual])
			if limit>0: check(actual<=limit*1.12 and actual>=limit*.75,'Native frame pacing follows selected cap')
	app.set_frame_limit(120)
	app.set_language('en')
	check(Engine.max_fps==120 and app.prefs.fps_limit==120,'Language change retains cap')
	app.set_frame_limit(0)
	var unlimited=app.modal.get_child(1).get_node('FrameLimit_0')
	check(unlimited.get_rect().end.x<=700,'Selected Unlimited label remains within the panel')
	check(unlimited.has_focus(),'Frame selection retains a visible keyboard focus')
	app.set_frame_limit(120)
	await capture('settings-en')
	app.set_language('zh')
	await capture('settings-zh')
	app.close_dialog();app.start_game()
	check(Engine.max_fps==120,'New expedition retains cap')
	app.open_dialog('settings')
	await click(app.modal.get_child(1).get_node('FrameLimit_60'))
	check(Engine.max_fps==60 and app.expedition.state.mode=='map','Map settings update the same preference')
	app.close_dialog()
	check(preload('res://tests/expedition_test_support.gd').deploy(app),'Existing destination/card flow still enters combat')
	app.open_map();app.open_dialog('settings')
	check(app.modal.get_child(1).has_node('MapContextAction'),'Return-to-battle action is retained')
	await capture('map-settings-zh')
	app.close_dialog();app.show_camp()
	var state=app.campaign.g.duplicate(true)
	app.open_dialog('settings');app.set_frame_limit(30)
	app._process(.1)
	check(app.campaign.g==state,'Changing frame cap in settings cannot advance battle')
	await click(app.modal.get_child(1).get_node('FrameLimit_120'))
	check(app.campaign.g==state,'High frame cap does not alter battle state or speed')
	app.sound.stop();root.remove_child(app);app.queue_free()
	await process_frame
	boot()
	check(Engine.max_fps==120 and app.prefs.fps_limit==120,'Restart restores selected cap')
	check(is_equal_approx(app.sound.volume,.35),'Other settings survive frame-limit changes')
	app.sound.stop()
	for suffix in ['','.bak','.tmp']:
		if FileAccess.file_exists(PATH+suffix): DirAccess.remove_absolute(PATH+suffix)
	print('%d frame-limit checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
