extends SceneTree
const OUT='res://../output/sword-banner-reference/volley/runtime/'
var failures=0
func _initialize():call_deferred('run')
func key(code: Key):
	var e=InputEventKey.new();e.physical_keycode=code;e.pressed=true;root.push_input(e,true)
func click(p: Vector2):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;root.push_input(e,true)
func snapshot(name: String):root.get_texture().get_image().save_png(OUT+name+'.png')
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-volley-capture.cfg';root.add_child(app)
	await RenderingServer.frame_post_draw
	app.menu_view.get_node('%TacticalTrial').pressed.emit();var t=app.active_trial;t.set_process(false);app.sound.enabled=false
	var r=t.rules
	for frame in 30:await RenderingServer.frame_post_draw
	click(t.archer_variant_button.get_global_rect().get_center());t.refresh()
	await RenderingServer.frame_post_draw
	snapshot('loadout')
	click(t.combined_button.get_global_rect().get_center())
	# Controlled ability fixture uses the normal deployed loadout and the real HUD/input path.
	r.units=r.units.filter(func(u):return u.side=='ally' and u.kind=='archer')
	var a=r.units[0]
	r.spawn('guard','enemy',Vector2(1050,1240))
	for u in r.units:
		u.order='hold'
		for i in u.soldiers.size():r.Charges.detach(r,u,i);u.soldiers[i].cooldown=999.
	t.set_camera(r.projection*Vector2(1050,1530)-Vector2(960,540)/t.zoom)
	t.refresh();click(t.start_button.get_global_rect().get_center());t.refresh()
	var hit_frames=[];var max_arrows=0;var launched=0;var hp: float=r.units[1].hp
	for frame in 420:
		if frame==30:click(t.roster[0].get_global_rect().get_center())
		if frame==60:
			key(KEY_V)
			t.pointer=Vector2(1050,1240)
		if frame==120:
			click((r.projection*Vector2(1050,1240)-t.camera_offset)*t.zoom)
			launched=r.volleys.size()
			if launched!=30:failures+=1;push_error('Real V input did not emit thirty arrows')
		if frame==121:
			root.gui_disable_input=true;t.set_process_input(false);t.set_process_unhandled_input(false)
		t._process(1./60)
		max_arrows=maxi(max_arrows,r.volleys.size())
		if r.units[1].hp<hp:hit_frames.append({'frame':frame,'damage':hp-r.units[1].hp});hp=r.units[1].hp
		await RenderingServer.frame_post_draw
		if frame in [90,140,170,210,300]:snapshot('frame-%04d'%frame)
	if hit_frames.is_empty():failures+=1;push_error('No volley impact in native capture')
	t.retry();t.refresh()
	for frame in 30:await RenderingServer.frame_post_draw
	var clean: bool=t.rules.volleys.is_empty() and t.rules.ability_sounds.is_empty() and t.rules.archer_variant==''
	if not clean:failures+=1
	snapshot('retry')
	var report={'failures':failures,'fixture':'Normal menu and loadout, controlled ten longbow versus ten stationary guard formation; no ordinary attacks',
		'launch_frame':120,'arrows':launched,'max_arrows':max_arrows,'hits':hit_frames,'retry_clean':clean,'normal_speed':true,'quiet':true,'zoom':t.zoom,
		'expected_movie_frames':484,'source_damage':18.,'final_enemy_hp':hp}
	FileAccess.open(OUT+'report.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
	print('Longbow native capture: ',JSON.stringify(report))
	t.closed.emit();app.queue_free();await RenderingServer.frame_post_draw;quit(1 if failures else 0)
