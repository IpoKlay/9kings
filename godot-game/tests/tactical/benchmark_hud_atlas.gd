extends SceneTree
## Paired native/atlas runs through the actual main-menu entry; no forced draws
## inside the timed interval. Fixed simulation steps keep battle work identical.
const OUT = "res://../output/ui-atlas-integration-2026-11-09/"
const FRAMES = 600
var app
var trial
var hud
var optimized_theme: Theme
var original_theme: Theme
var rows: Array = []

func _initialize():
	call_deferred("run")

func run():
	app = load("res://scenes/main.tscn").instantiate()
	app.settings_path = OUT + "temporary-benchmark.cfg"
	app.run_path_override = OUT + "temporary-benchmark.json"
	root.add_child(app)
	app.language = "zh"
	app.menu_view.get_node("%TacticalTrial").pressed.emit()
	trial = app.active_trial
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
	root.always_on_top = true
	OS.low_processor_usage_mode = false
	AudioServer.set_bus_mute(0, true)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_title("Eagle UI performance comparison")
	DisplayServer.window_move_to_foreground()
	for scenario in ["ui", "deployment", "battle", "deployment-capped", "battle-capped"]:
		for repetition in (1 if scenario.ends_with("-capped") else 3):
			var modes = [false, true] if repetition % 2 == 0 else [true, false]
			for optimized in modes:
				await measure(scenario, optimized, repetition)
	var data = {"engine": Engine.get_version_info().string, "window": DisplayServer.window_get_size(),
		"vsync": DisplayServer.window_get_vsync_mode(), "fps_limit": Engine.max_fps,
		"frames_per_run": FRAMES, "fixed_simulation_step": 1.0 / 60.0, "runs": rows}
	FileAccess.open(OUT + "performance.json", FileAccess.WRITE).store_string(JSON.stringify(data, "\t"))
	trial.closed.emit()
	app.queue_free()
	await process_frame
	quit()

func measure(scenario: String, optimized: bool, repetition: int):
	DisplayServer.window_move_to_foreground()
	Engine.max_fps = 60 if scenario.ends_with("-capped") else 0
	var base_scenario := scenario.trim_suffix("-capped")
	seed(20261109)
	trial.retry()
	trial.combined_button.pressed.emit()
	trial.refresh()
	trial.field.visible = base_scenario != "ui"
	if base_scenario == "battle":
		trial.start_or_hold()
		trial.rules.command(trial.rules.alive("ally").map(func(u): return u.id), "auto", Vector2.ZERO)
	hud.set_batching_enabled(false)
	hud.theme = optimized_theme if optimized else original_theme
	hud.set_batching_enabled(optimized)
	for i in 120:
		trial._process(1.0 / 60.0)
		await process_frame
	# Check the normal root viewport's appearance at this exact state.
	if repetition == 0 and base_scenario != "battle":
		root.get_texture().get_image().save_png(OUT + scenario + ("-after.png" if optimized else "-before.png"))
	var times: Array[float] = []
	var draws: Array[float] = []
	var begin := Time.get_ticks_usec()
	var previous := begin
	var rendered := Engine.get_frames_drawn()
	for i in FRAMES:
		trial._process(1.0 / 60.0)
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - previous) / 1000.0)
		previous = now
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var elapsed_ms := (Time.get_ticks_usec() - begin) / 1000.0
	var rendered_count := Engine.get_frames_drawn() - rendered
	if rendered_count < FRAMES - 2:
		push_error("Benchmark window stopped rendering; discard this run")
		quit(1)
		return
	times.sort()
	draws.sort()
	var row = {"scenario": scenario, "fps_limit": Engine.max_fps, "optimized": optimized, "repetition": repetition,
		"fps": rendered_count * 1000.0 / elapsed_ms, "median_ms": times[FRAMES / 2],
		"p95_ms": times[int(FRAMES * 0.95)], "elapsed_ms": elapsed_ms,
		"draw_calls_median": draws[FRAMES / 2], "draw_calls_min": draws[0], "draw_calls_max": draws[-1],
		"rendered_frames": rendered_count,
		"final_state": str(trial.rules.units.map(func(u): return [u.id, u.pos, u.hp, u.morale]))}
	rows.append(row)
	print("BENCH ", scenario, " optimized=", optimized, " repetition=", repetition,
		" FPS=", row.fps, " P95ms=", row.p95_ms, " draws=", row.draw_calls_median,
		" rendered=", rendered_count)
