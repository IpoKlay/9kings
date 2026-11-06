extends SceneTree
## Run against the unchanged base checkout to record genuine baseline frames.
func _initialize():call_deferred('run')
func capture(name: String):
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png('res://../output/battle-hud-baseline/'+name+'.png')
func run():
	create_timer(45).timeout.connect(func():quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://../output/battle-hud-baseline/'))
	root.size=Vector2i(1920,1080)
	var main=load('res://scenes/main.tscn').instantiate()
	main.run_path_override='user://battle-hud-baseline-no-save.cfg'
	root.add_child(main)
	await process_frame
	main.open_tactical_trial()
	await process_frame
	var trial=root.get_child(-1)
	await capture('deployment')
	trial.combined_button.pressed.emit()
	await process_frame
	trial.start_button.pressed.emit()
	await process_frame
	await capture('battle')
	trial.queue_free()
	main.queue_free()
	await process_frame
	print('BASELINE CAPTURE: deployment and battle')
	quit()
