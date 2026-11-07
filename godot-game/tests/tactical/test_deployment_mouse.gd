extends SceneTree
var checks=0
var failures=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func click(button: Control):
	var at=button.get_global_rect().get_center()
	for pressed in [true,false]:
		var e=InputEventMouseButton.new();e.position=at;e.global_position=at;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed
		root.push_input(e,true)
	await process_frame
func run():
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='user://deployment-mouse-test.cfg'
	root.add_child(app);app.sound.enabled=false
	for language in ['zh','en']:
		app.language=language;app.render_ui();await process_frame
		await click(app.menu_view.get_node('%TacticalTrial'))
		var t=app.active_trial;t.set_process(false)
		await click(t.combined_button)
		t.refresh();await process_frame
		check(t.rules.alive('ally').size()==7,'Actual mouse reaches seven-arm preset in '+language)
		check(t.get_node('BattleHUD/RegimentRoster').visible,'Roster appears after real deployment in '+language)
		if not t.rules.alive('ally').is_empty():
			await click(t.roster[0]);check(not t.squad_ids.is_empty(),'Roster child button remains clickable in '+language)
			await click(t.start_button);check(t.rules.phase=='battle','Begin mouse click starts one battle in '+language)
			t.rules.phase='victory';t.refresh();await click(t.start_button)
			check(t.rules.phase=='deploy' and t.rules.alive('ally').is_empty(),'One result click creates a fresh deployment in '+language)
		t.retry();await process_frame
		await click(t.siege_button)
		check(t.rules.structures.size()==7,'Actual mouse reaches siege preset after retry in '+language)
		t.closed.emit();await process_frame
		await click(app.menu_view.get_node('%TacticalTrial'));t=app.active_trial;t.set_process(false)
		await click(t.defender_button)
		check(not t.rules.square_battle,'Actual mouse reaches pass preset in '+language)
		t.closed.emit();await process_frame
		await click(app.menu_view.get_node('%TacticalTrial'));t=app.active_trial;t.set_process(false)
		# A transparent part of the empty roster footprint must still start a ground gesture.
		var e=InputEventMouseButton.new();e.position=Vector2(1100,997);e.global_position=e.position;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=true
		root.push_input(e,true);check(t.gesture,'Empty roster area passes ground input in '+language)
		e.pressed=false;root.push_input(e,true)
		t.closed.emit();await process_frame
	app.queue_free();await process_frame
	print('Deployment mouse: ',checks,' checks, ',failures,' failures');quit(1 if failures else 0)
