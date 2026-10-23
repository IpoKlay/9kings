extends SceneTree
## Native pointer regression: no direct button signals or campaign.choose/place calls.
var app
var checks = 0
var failures = 0
func _init(): call_deferred('run')
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		printerr('FAIL: ' + message)
func click(p: Vector2):
	# OS mouse coordinates are physical pixels; the stretched viewport is logical.
	Input.warp_mouse(root.get_final_transform() * p)
	await process_frame
	var motion = InputEventMouseMotion.new()
	motion.position = p
	motion.global_position = p
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = p
		event.global_position = p
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame
func press(control: Control):
	await click(control.get_global_rect().get_center())
func supply():
	var chosen = app.card_hand.slots[0].id
	await click(app.card_hand.slots[0].origin + Vector2(120,130))
	await create_timer(.3).timeout
	check(app.campaign.g.chosen == chosen and not app.input_locked, 'Mouse chooses card and unlocks input')
	if app.campaign.g.phase == 'place':
		check(not app.ui.has_node('ContinueButton'), 'Must finish placing building before continuing')
		var cell = -1
		for b in app.campaign.g.buildings:
			if b.type == chosen and b.level < 3: cell = int(b.cell); break
		if cell < 0:
			for i in 12:
				if app.campaign.building_at(i) == null: cell = i; break
		var location = app.world.center(cell)
		await click(app.world.project(location.x,location.y))
	check(app.campaign.g.phase == 'prepare', 'Mouse placement/supply reaches preparation')
	check(app.ui.has_node('ContinueButton'), 'Visible next-step action after supply')
	check(not app.ui.has_node('ReportButton'), 'No premature report')
func capture(id: String):
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png('res://tests/' + id + '.png')
func run():
	if DisplayServer.get_name() == 'headless':
		printerr('This pointer test requires the native renderer.'); quit(1); return
	app = load('res://scenes/main.tscn').instantiate()
	root.add_child(app)
	current_scene = app
	app.set_process(false)
	app.sound.enabled = false
	for lang in ['zh','en']:
		app.language = lang
		for first_card in ['legion','training','shieldDrill','shield']:
			app.restart_expedition()
			app.campaign.reset(23)
			# Deterministic offered hand covers upgrade, new building, doctrine and order.
			app.campaign.g.offered = [first_card,'archer','siege']
			app.campaign.g.offerYear = app.campaign.g.round
			app.render_ui()
			await create_timer(.4).timeout
			await supply()
			if app.campaign.g.phase != 'prepare': quit(1); return
			if first_card == 'legion': await capture('supply-ready-' + lang)
			await press(app.ui.get_node('ContinueButton'))
			check(app.expedition_map.visible and app.expedition_map.selected == '148127', 'Continue opens map and reveals sole next stop')
			await press(app.expedition_map.travel_button)
			check(app.expedition.state.current == '148127' and app.campaign.g.phase == 'reward', 'Pointer enters friendly port')
			await create_timer(.4).timeout
			await supply()
			await press(app.ui.get_node('ContinueButton'))
			check(app.expedition_map.selected == '', 'A branch leaves route choice to player')
			await press(app.expedition_map.city_buttons['246349'])
			check(not app.expedition_map.travel_button.disabled, 'Battle action is available after supplies')
			await press(app.expedition_map.travel_button)
			check(app.campaign.g.phase == 'battle' and not app.expedition_map.visible, 'Mouse action starts real battle')
			for i in 120: app._process(1.0/60)
			check(app.campaign.g.battle.time > 1, 'Combat simulation advances after entering')
			if first_card == 'legion': await capture('supply-battle-' + lang)
	app.sound.stop()
	print('%d supply-to-battle pointer checks, %d failures' % [checks,failures])
	quit(1 if failures else 0)
