extends SceneTree
# Controlled native counterpart to the observed original sandbox blink sequence.
# Selection and spawn points are fixtures; B and targeting use real input dispatch.
const OUT = 'res://../output/sword-banner-reference/original-wraith/local/'
var checks = 0
var failures = 0
func _initialize(): call_deferred('run')
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1; push_error(label)
func key(code):
	var e = InputEventKey.new(); e.physical_keycode = code; e.pressed = true; root.push_input(e, true)
func click(p):
	for down in [true, false]:
		var e = InputEventMouseButton.new(); e.position = p; e.global_position = p; e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down; root.push_input(e, true)
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var app = load('res://scenes/main.tscn').instantiate(); app.settings_path = '/tmp/eagle-blink-reference.cfg'; root.add_child(app)
	await RenderingServer.frame_post_draw
	app.menu_view.get_node('%TacticalTrial').pressed.emit()
	var t = app.active_trial; t.set_process(false); app.sound.enabled = false
	var r = t.rules; r.units.clear(); r.config.types.legion.files = 1; r.config.types.legion.hp = 100.; r.config.unit_variants.wraith.hp = 150.
	r.contact_profiles.legion = r.Contact.profile('legion', r.config.types.legion)
	r.spawn('legion', 'ally', Vector2(1000, 900), 'wraith')
	r.spawn('legion', 'ally', Vector2(1040, 880), 'wraith')
	r.spawn('legion', 'ally', Vector2(920, 840))
	r.spawn('legion', 'enemy', Vector2(1900, 200))
	t.refresh(); click(t.start_button.get_global_rect().get_center()); r.enemy_director.active = false
	for u in r.units:
		u.order = 'hold'; r.Charges.detach(r, u, 0); u.soldiers[0].personal_order = 'hold'; u.soldiers[0].position = u.pos
	t.squad_ids = []; t.soldier_ids = [Vector2i(r.units[0].id, 0), Vector2i(r.units[1].id, 0), Vector2i(r.units[2].id, 0)]
	t.set_camera(r.projection * Vector2(1050, 1050) - Vector2(960, 540) / t.zoom); t.refresh()
	var starts = r.units.slice(0, 3).map(func(u): return u.soldiers[0].position)
	var target = Vector2(1020, 1170); var records = []
	check(not t.blink_button.visible, 'Mixed selection hides all-capable HUD button')
	for frame in 660:
		if frame == 30:
			key(KEY_B); check(t.selected == 'blink', 'B targets eligible subset of mixed selection')
		if frame == 60:
			click((r.projection * target - t.camera_offset) * t.zoom)
			for i in 2:
				var a = r.units[i].soldiers[0]
				check(a.position.is_equal_approx(starts[i] + (target - starts[i]).normalized() * 200.), 'Independent 200-unit endpoint')
				check(a.blink_cooldown == 8., 'Each caster starts eight-second cooldown')
			check(r.units[2].soldiers[0].position == starts[2], 'Incapable ally stays in place')
		if frame in [194, 491, 613]:
			key(KEY_B)
			check((t.selected == 'blink') == (frame == 613), 'Cooldown retry at frame ' + str(frame))
			records.append({'frame':frame, 'seconds_after_cast':(frame - 60) / 60., 'targeting':t.selected == 'blink', 'cooldown':r.units[0].soldiers[0].blink_cooldown})
		t._process(1. / 60)
		await RenderingServer.frame_post_draw
		if frame in [30, 59, 60, 194, 491, 613, 659]: root.get_texture().get_image().save_png(OUT + 'frame-%04d.png' % frame)
	FileAccess.open(OUT + 'capture-report.json', FileAccess.WRITE).store_string(JSON.stringify({'checks':checks, 'failures':failures, 'fixture':'Normal menu then two one-person wraith units, one swordsman and distant enemy reserve. Fixed selected IDs; actual B and left-click input. Native simulation runs at normal speed; original sandbox tactical slowdown is not reproduced.', 'target':target, 'origins':starts, 'endpoints':r.units.slice(0, 3).map(func(u):return u.soldiers[0].position), 'retry':records, 'expected_frames':663, 'scope':'Behavioral counterpart, not identical map/projection/random seed or exact simulation-time comparison.'}, '\t'))
	print('Blink reference capture: ', checks, ' checks, ', failures, ' failures')
	t.closed.emit(); app.queue_free(); await RenderingServer.frame_post_draw; quit(1 if failures else 0)
