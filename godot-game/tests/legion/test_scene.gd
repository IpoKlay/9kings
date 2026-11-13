extends SceneTree
var checks = 0
var failures = 0

func check(value: bool, message: String):
	checks += 1
	if not value: failures += 1; printerr('FAIL: '+message)

func _initialize(): call_deferred('run')

func key(code: Key, ctrl: bool = false):
	var event = InputEventKey.new(); event.physical_keycode = code; event.pressed = true; event.ctrl_pressed = ctrl
	root.push_input(event)
	var release = event.duplicate(); release.pressed = false; root.push_input(release)

func field_click(t, world: Vector2, mouse_button: MouseButton = MOUSE_BUTTON_LEFT):
	var event = InputEventMouseButton.new(); event.position = t.world_to_screen(world); event.button_index = mouse_button; event.pressed = true
	t._unhandled_input(event); event.pressed = false; t._unhandled_input(event)

func capture(name: String, t):
	if DisplayServer.get_name() == 'headless': return
	t.field.queue_redraw(); t.update_ui(); t.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var folder = ProjectSettings.globalize_path('res://../output/legion-battle')
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder+'/'+name+'.png')

func run():
	var app = load('res://scenes/main.tscn').instantiate()
	app.settings_path = 'user://legion-scene-test.cfg'
	root.add_child(app)
	await process_frame
	app.sound.enabled = false
	app.menu_view.get_node('%TacticalTrial').pressed.emit()
	await process_frame
	var t = app.active_trial
	check(t != null and t.get_script().resource_path == 'res://scripts/legion/screen.gd','normal menu connects to new battle scene')
	check(not app.visible and t.rules.phase == 'deploy','normal menu pauses and scene begins in deployment')
	check(t.rules.strength('ally') == 140 and t.rules.strength('enemy') == 120,'normal entry has configured actual troops')
	t.set_process(false)
	key(KEY_3)
	check(t.selected == [2],'physical number key selects cavalry through viewport input')
	t.form_buttons.wedge.pressed.emit()
	check(t.rules.regiments[2].form == 'wedge','formation UI deploys cavalry wedge')
	key(KEY_1)
	t.select_regiment(1,true)
	check(t.selected == [0,1],'multi-selection owns regiment IDs')
	for code in [KEY_5,KEY_6,KEY_7]:
		key(code,true); t.selected = [3]; key(code)
		check(t.selected == [0,1],'Ctrl plus number binds and recalls groups five through seven')
	key(KEY_KP_4)
	check(t.selected == [3],'numeric keypad also selects groups')
	t.select_regiment(0); t.update_ui()
	check(t.form_buttons.wedge.disabled,'infantry wedge button disabled')
	t.form_buttons.ring.pressed.emit(); t.update_ui()
	check(t.rules.report == '选择组合的军团' and t.combination_candidates() == [3],'ring button prompts and highlights eligible partner')
	check(t.card_buttons[3].modulate != Color.WHITE,'eligible partner card is visibly highlighted')
	t.card_buttons[2].pressed.emit()
	check(t.combine_outer == 0 and t.rules.regiments[0].pair == -1,'ineligible cavalry cannot complete ring selection')
	key(KEY_4)
	check(t.rules.regiments[0].pair == 3 and t.selected == [0,3] and t.combine_outer == -1,'number shortcut completes linked ring')
	t.update_ui(); check(t.form_buttons.ring.text == '解除组合','ring button offers prebattle unlink')
	await capture('v2-ring-deployment',t)
	t.form_buttons.ring.pressed.emit()
	check(t.rules.regiments[0].pair == -1 and t.rules.regiments[3].form == 'default','unlink restores partner formation')
	t.select_regiment(1,true)
	t.update_ui()
	check(t.form_buttons.dense.disabled,'mixed selection only permits shared formations')
	var before = t.rules.soldiers.duplicate(true)
	t._process(0.1)
	check(t.rules.soldiers == before,'real scene process cannot start combat before start button')
	key(KEY_3); key(KEY_Q)
	check(t.aim_order == 'charge','Q arms a charge destination before battle')
	field_click(t,Vector2(1970,650))
	check(t.rules.regiments[2].charge_queued and t.rules.regiments[2].charge_cd == 0,'prebattle destination queues charge without starting cooldown')
	key(KEY_H); check(not t.rules.regiments[2].charge_queued,'H cancels planned charge through real keyboard input')
	key(KEY_Q); field_click(t,Vector2(1970,650))
	t.select_regiment(0); t.form_buttons.ring.pressed.emit(); key(KEY_4)
	await capture('deployment',t)
	t.start_button.pressed.emit()
	check(t.rules.phase == 'battle','start button triggers combat')
	check(t.rules.regiments[2].charge_state == 'forming','start button executes planned charge')
	t.select_regiment(1); t.update_ui()
	check(t.form_buttons.ring.disabled and t.form_buttons.wedge.disabled,'new ring and wedge formations disabled in combat')
	t.toggle_pause(); before = t.rules.soldiers.duplicate(true)
	t._process(0.1)
	check(t.rules.soldiers == before,'scene pause freezes soldiers and cooldowns')
	check(t.rules.set_formation([1],'testudo'),'formation can be queued while paused')
	check(t.rules.regiments[1].form_time == 3,'paused formation timer has not elapsed')
	key(KEY_1); t.update_ui()
	check(not t.form_buttons.ring.disabled and t.form_buttons.ring.text == '解除组合','linked ring can be dissolved in combat from the UI')
	t.selected = [2,0,3]; t.update_ui()
	t.form_buttons.ring.pressed.emit(); t.update_ui()
	check(t.rules.regiments[0].form == 'free' and t.rules.regiments[3].form == 'free','combat ring button frees both armies')
	t.selected = [0,3]; t.update_ui()
	check(t.form_buttons.default.disabled,'free armies cannot directly choose a formation')
	await capture('v3-free-attack',t)
	key(KEY_G); check(t.rules.regiments[0].form == 'free','G also issues free attack mode')
	key(KEY_1); key(KEY_A)
	check(t.aim_order == 'attack_move','A arms destination-based attack move')
	field_click(t,Vector2(1000,900))
	check(t.rules.regiments[0].order == 'attack_move' and t.aim_order == '' and t.selected == [0],'attack move click issues order without clearing selection')
	check(t.rules.regiments[0].form == 'default' and t.rules.regiments[0].regrouping,'move attack regroups a free army into default formation')
	key(KEY_M); field_click(t,Vector2(850,1050))
	check(t.rules.regiments[0].order == 'move','M and click issues distinct forced move')
	key(KEY_A); field_click(t,Vector2(900,900),MOUSE_BUTTON_RIGHT)
	check(t.aim_order == '' and t.rules.regiments[0].order == 'move','right click cancels aim without issuing another order')
	t.rules.command([0],'auto')
	t.toggle_pause()
	for i in 250: t._process(1.0/30)
	check(t.rules.regiments[1].form == 'testudo','formation finishes via actual scene update')
	check(t.rules.soldiers.any(func(s): return s.hp < s.max_hp),'scene combat causes individual injuries')
	t.selected = [1]; t.update_ui()
	await capture('combat',t)
	for i in 5000:
		t._process(1.0/30)
		if t.rules.phase != 'battle': break
	check(t.rules.phase in ['victory','defeat'] and t.result_panel.visible,'natural result panel appears')
	await capture('result',t)
	t.retry()
	check(t.rules.phase == 'deploy' and t.rules.strength('ally') == 140 and not t.result_panel.visible,'retry resets troops, phase and result UI')
	check(t.rules.projectiles.is_empty() and t.rules.effects.is_empty(),'retry clears projectiles and hit effects')
	check(t.rules.selected_group(7).is_empty() and t.aim_order == '' and t.combine_outer == -1,'retry clears rebound groups and targeting modes')
	check(t.rules.regiments[2].charge_state == '' and not t.rules.regiments[2].charge_queued and t.rules.regiments[2].charge_cd == 0,'retry clears active and queued charges')
	t.start_button.pressed.emit(); t.toggle_pause(); key(KEY_3)
	t.charge_button.pressed.emit(); field_click(t,Vector2(1900,750))
	check(t.rules.regiments[2].charge_state == 'forming' and not t.rules.regiments[2].charge_queued,'active charge button works after battle starts')
	await capture('v3-charge-order',t)
	t.closed.emit()
	await process_frame
	check(app.visible and app.active_trial == null,'return to main menu restores the app')
	app.open_tactical_trial()
	await process_frame
	check(app.active_trial.rules.phase == 'deploy','re-entering from menu gets a fresh match')
	app.active_trial.closed.emit()
	await process_frame
	app.queue_free()
	await process_frame
	await create_timer(0.35).timeout
	print('LEGION SCENE CHECKS=',checks,' FAILURES=',failures)
	quit(1 if failures else 0)
