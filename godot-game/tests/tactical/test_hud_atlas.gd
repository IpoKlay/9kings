extends SceneTree
## Real renderer, isolated input viewport: OS focus cannot cancel a held test click.
var out := "res://../output/ui-atlas-integration-2026-11-09/"
var failures: Array[String] = []
var evidence := {}
var viewport: SubViewport
var app
var trial
var hud
var optimized_theme: Theme
var original_theme: Theme

func _initialize():
	call_deferred("run")

func check(value: bool, label: String):
	if not value:
		failures.append(label)
		push_error(label)

func settle():
	for i in 3:
		await process_frame
		RenderingServer.force_draw()

func motion(point: Vector2, held := false):
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	viewport.push_input(event, true)

func mouse(point: Vector2, down: bool):
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	viewport.push_input(event, true)

func click(control: Control):
	var point := control.get_global_rect().get_center()
	motion(point)
	mouse(point, true)
	mouse(point, false)
	await settle()

func compare(label: String):
	var popup_open: bool = trial.character_picker.get_popup().visible
	hud.set_batching_enabled(false)
	hud.theme = original_theme
	await settle()
	if popup_open:
		trial.character_picker.show_popup()
		await settle()
	var before := viewport.get_texture().get_image()
	var rects := {}
	for item in hud._items:
		rects[str(item.control.get_path())] = item.control.get_global_rect()
	hud.theme = optimized_theme
	hud.set_batching_enabled(true)
	await settle()
	if popup_open:
		trial.character_picker.show_popup()
		await settle()
	var after := viewport.get_texture().get_image()
	var same := before.get_data() == after.get_data()
	check(same, label + " pixel equality")
	for item in hud._items:
		check(rects[str(item.control.get_path())] == item.control.get_global_rect(), label + " rect")
	before.save_png(out + label + "-before.png")
	after.save_png(out + label + "-after.png")
	evidence[label] = {"pixels_identical": same, "pause_mode": trial.get_node("BattleHUD/TopActions/PauseButton").get_draw_mode()}
	print("COMPARE ", label, " ", same)

func first_frame_hover():
	var frames: Array[Image] = []
	var pause: Button = hud.get_node("TopActions/PauseButton")
	for optimized in [false, true]:
		hud.set_batching_enabled(false)
		hud.theme = optimized_theme if optimized else original_theme
		hud.set_batching_enabled(optimized)
		motion(Vector2(800, 400))
		await settle()
		motion(pause.get_global_rect().get_center())
		await RenderingServer.frame_post_draw
		frames.append(viewport.get_texture().get_image())
	check(frames[0].get_data() == frames[1].get_data(), "hover background updates on first rendered frame")
	evidence["first_frame_hover"] = {"pixels_identical": frames[0].get_data() == frames[1].get_data()}

func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	create_timer(90).timeout.connect(func(): push_error("HUD TEST TIMEOUT"); quit(1))
	root.always_on_top = true
	AudioServer.set_bus_mute(0, true)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.gui_embed_subwindows = true
	root.add_child(viewport)
	app = load("res://scenes/main.tscn").instantiate()
	app.settings_path = out + "temporary-test-settings.cfg"
	app.run_path_override = out + "temporary-test-run.json"
	viewport.add_child(app)
	app.language = "zh"
	app.menu_view.get_node("%TacticalTrial").pressed.emit()
	trial = app.active_trial
	trial.reparent(viewport, false)
	viewport.notify_mouse_entered()
	check(trial.get_viewport() == viewport, "fixture owns actual trial viewport")
	trial.set_process(false)
	hud = trial.get_node("BattleHUD")
	optimized_theme = hud.theme
	original_theme = hud.theme.duplicate(true)
	for type in original_theme.get_type_list():
		for key in original_theme.get_stylebox_list(type):
			var style = original_theme.get_stylebox(key, type)
			if style is StyleBoxTexture:
				style.texture = load("res://assets/ui_rpg/battle_hud/toolbar.png")
				style.region_rect = Rect2()
	trial.field.hide()
	await settle()
	check(hud.batching_enabled, "batching enabled from normal scene")
	await compare("zh-empty-deployment")
	await click(trial.combined_button)
	trial.refresh()
	check(trial.rules.alive("ally").size() == 7, "Chinese combined deployment click")
	await compare("zh-deployed")
	await first_frame_hover()
	var pause: Button = hud.get_node("TopActions/PauseButton")
	var point := pause.get_global_rect().get_center()
	motion(point)
	await compare("zh-hover")
	check(pause.get_draw_mode() == BaseButton.DRAW_HOVER, "actual Chinese hover")
	mouse(point, true)
	await compare("zh-held")
	check(pause.get_draw_mode() in [BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED], "actual Chinese pressed")
	# Theme switching during the visual A/B may cancel an in-flight gesture.
	# Validate uninterrupted clicks separately, without changing styles mid-click.
	mouse(point, false)
	var paused: bool = trial.paused
	await click(pause)
	check(trial.paused != paused, "Chinese pause mouse release")
	await click(pause)
	check(trial.paused == paused, "Chinese resume click")
	# Cancel a held click outside the button, then exercise disabled input.
	mouse(point, true)
	motion(Vector2(800, 400), true)
	await compare("zh-drag-out")
	mouse(Vector2(800, 400), false)
	check(trial.paused == paused, "release outside does not click")
	pause.disabled = true
	motion(point)
	await compare("zh-disabled")
	await click(pause)
	check(trial.paused == paused, "disabled pause rejects mouse")
	pause.disabled = false
	pause.focus_mode = Control.FOCUS_ALL
	pause.grab_focus()
	await compare("zh-focus")
	pause.release_focus()
	await click(hud.get_node("TopActions/HelpButton"))
	check(trial.controls.visible, "Chinese help opened")
	motion(Vector2(800, 400))
	await compare("zh-help")
	await click(trial.character_picker)
	check(trial.character_picker.get_popup().visible, "Chinese character popup opened")
	await compare("zh-popup")
	trial.character_picker.get_popup().hide()
	trial.selected = "lightning"
	trial.rules.elapsed = 65.0
	trial.refresh()
	await compare("zh-selection-timer")
	# A clipped roster retains native backgrounds as new entries are duplicated.
	check(hud._items.all(func(item): return not str(item.control.get_path()).contains("RegimentRoster")), "roster not regrouped")
	await click(trial.roster[2])
	check(trial.squad_ids.size() == 1, "Chinese roster selection")
	trial.refresh()
	for button in trial.roster:
		button.text += " 这是用于检验裁切的长队伍名称"
	hud.get_node("RegimentRoster").scroll_horizontal = 160
	await compare("zh-roster-clipping")
	await click(trial.start_button)
	check(trial.rules.phase == "battle", "Chinese begin battle click")
	trial.refresh()
	await compare("zh-battle")
	trial.rules.flag_state = "capturing"
	trial.refresh()
	await compare("zh-tinted-alert")
	trial.rules.phase = "victory"
	trial.rules.outcome = "enemy_routed"
	trial.refresh()
	await compare("zh-result")
	await click(trial.start_button)
	trial.refresh()
	check(trial.rules.phase == "deploy", "Chinese retry click")
	await compare("zh-retry")
	app.language = "en"
	trial.refresh()
	await compare("en-refreshed")
	await click(hud.get_node("TopActions/MenuButton"))
	check(app.active_trial == null or not is_instance_valid(app.active_trial), "menu exit frees trial")
	evidence["failures"] = failures
	FileAccess.open(out + "visual-input-results.json", FileAccess.WRITE).store_string(JSON.stringify(evidence, "\t"))
	viewport.queue_free()
	await process_frame
	print("HUD ATLAS: ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
