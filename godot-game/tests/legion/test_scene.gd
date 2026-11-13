extends SceneTree
var checks = 0
var failures = 0

func check(value: bool, message: String):
	checks += 1
	if not value: failures += 1; printerr('FAIL: '+message)

func _initialize(): call_deferred('run')

func capture(name: String):
	if DisplayServer.get_name() == 'headless': return
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
	t.select_regiment(0)
	t.form_buttons.wedge.pressed.emit()
	check(t.rules.regiments[0].form == 'wedge','formation UI changes the actual regiment')
	t.select_regiment(1,true)
	check(t.selected == [0,1],'multi-selection owns regiment IDs')
	t.update_ui()
	check(t.form_buttons.dense.disabled,'mixed selection only permits shared formations')
	var before = t.rules.soldiers.duplicate(true)
	t._process(0.1)
	check(t.rules.soldiers == before,'real scene process cannot start combat before start button')
	await capture('deployment')
	t.start_button.pressed.emit()
	check(t.rules.phase == 'battle','start button triggers combat')
	t.toggle_pause(); before = t.rules.soldiers.duplicate(true)
	t._process(0.1)
	check(t.rules.soldiers == before,'scene pause freezes soldiers and cooldowns')
	check(t.rules.set_formation([1],'testudo'),'formation can be queued while paused')
	check(t.rules.regiments[1].form_time == 3,'paused formation timer has not elapsed')
	t.toggle_pause()
	for i in 250: t._process(1.0/30)
	check(t.rules.regiments[1].form == 'testudo','formation finishes via actual scene update')
	check(t.rules.soldiers.any(func(s): return s.hp < s.max_hp),'scene combat causes individual injuries')
	t.selected = [1]; t.update_ui()
	await capture('combat')
	for i in 5000:
		t._process(1.0/30)
		if t.rules.phase != 'battle': break
	check(t.rules.phase in ['victory','defeat'] and t.result_panel.visible,'natural result panel appears')
	await capture('result')
	t.retry()
	check(t.rules.phase == 'deploy' and t.rules.strength('ally') == 140 and not t.result_panel.visible,'retry resets troops, phase and result UI')
	check(t.rules.projectiles.is_empty() and t.rules.effects.is_empty(),'retry clears projectiles and hit effects')
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
