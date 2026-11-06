extends SceneTree

func _initialize():call_deferred('run')

func run():
	var out=ProjectSettings.globalize_path('res://../output/myth-roster/animation')
	DirAccess.make_dir_recursive_absolute(out)
	var main=load('res://scenes/main.tscn').instantiate()
	main.run_path_override='user://tactical-verification-absent.json'
	root.add_child(main)
	await process_frame
	main.language='zh'
	main.open_tactical_trial(true)
	await process_frame
	var trial=root.get_child(root.get_child_count()-1)
	trial.set_process(false)
	trial.choose_deity('poseidon')
	for p in [Vector2(650,420),Vector2(650,650)]:trial.rules.deploy('legion',p)
	for p in [Vector2(380,420),Vector2(380,650)]:trial.rules.deploy('archer',p)
	assert(trial.rules.start())
	trial.rules.deploy('cavalry',Vector2(530,310))
	trial.rules.deploy('cavalry',Vector2(530,770))
	for i in 3600:
		trial.rules.step(1.0/60)
		trial.rules.events.clear()
	trial.selected=''
	for frame in 120:
		if frame==15:assert(trial.rules.strike(trial.rules.alive('enemy')[0].pos))
		trial._process(1.0/30)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out+'/frame_%03d.png'%frame)
	print('POSEIDON CAPTURE: 120 frames of actual Godot trial at 30 FPS, one valid cast')
	main.queue_free()
	trial.queue_free()
	await process_frame
	quit()
