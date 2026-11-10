extends SceneTree
var failures=0
func _initialize():call_deferred('run')
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func run():
	var scene=load('res://scenes/previews/cavalry_depth.tscn').instantiate()
	root.add_child(scene);current_scene=scene
	await create_timer(2.6).timeout
	check(not scene.trial.rules.contact_log.is_empty(),'Rendered scene reaches actual contact')
	scene.get_node('Pause').pressed.emit()
	var stopped=scene.trial.rules.elapsed
	await create_timer(.15).timeout
	check(scene.trial.rules.elapsed==stopped,'Pause button stops simulation')
	scene.get_node('Pause').pressed.emit()
	await create_timer(.15).timeout
	check(scene.trial.rules.elapsed>stopped,'Pause button resumes simulation')
	var old_id=scene.get_instance_id()
	scene.get_node('Restart').pressed.emit()
	await process_frame;await process_frame;await process_frame
	check(current_scene.get_instance_id()!=old_id,'Restart reloads the actual preview scene')
	check(current_scene.trial.rules.contact_log.is_empty(),'Restart clears contact history')
	check(current_scene.trial.rules.exit_pending.is_empty(),'Restart clears follow-up orders')
	check(current_scene.trial.rules.rider_ids.size()==24 and current_scene.trial.rules.defender_ids.size()==40,'Restart restores 64 people')
	print('Cavalry preview UI: 7 checks, ',failures,' failures (engine signal input, not system mouse)')
	current_scene.queue_free();await process_frame;await create_timer(.15).timeout
	quit(1 if failures else 0)
