extends SceneTree
var poseidon=false
var evidence_dir='res://../output/tactical-trial/'
func _initialize():call_deferred('run')
func run():
	poseidon='--poseidon' in OS.get_cmdline_user_args()
	if poseidon:evidence_dir='res://../output/poseidon/'
	var main=load('res://scenes/main.tscn').instantiate()
	main.run_path_override='user://tactical-verification-absent.json'
	root.add_child(main)
	await process_frame
	main.language='zh'
	main.render_ui()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence_dir+'menu.png')
	var before=main.campaign.g.duplicate(true)
	main.language='zh'
	main.open_tactical_trial(true)
	await process_frame
	var trial=root.get_child(root.get_child_count()-1)
	assert(trial.rules.phase=='deploy')
	assert(trial.field.apparition_alpha(0)==0)
	assert(trial.field.apparition_alpha(.12)==1)
	assert(trial.field.apparition_alpha(.5)==1)
	assert(trial.field.apparition_alpha(.88)>0 and trial.field.apparition_alpha(.88)<1)
	assert(trial.field.apparition_alpha(2.2)==0)
	for point in [Vector2(350,300),Vector2(700,780),Vector2(1160,545),Vector2(1640,820)]:
		assert(trial.field.unproject(trial.field.project(point)).distance_to(point)<.001)
	assert(trial.field.project(Vector2(1000,500)).y>trial.field.project(Vector2(900,500)).y)
	if poseidon:
		trial.character_picker.item_selected.emit(trial.character_ids.find('poseidon'))
		assert(trial.rules.deity=='poseidon')
		await mouse(trial.buttons.lightning.get_global_rect().get_center())
		assert(trial.rules.charges==2 and trial.notice!='')
	await mouse(trial.field.project(Vector2(650,420)))
	assert(trial.rules.reserve.legion==1)
	trial.rules.deploy('legion',Vector2(650,650))
	trial.rules.deploy('archer',Vector2(380,420))
	trial.rules.deploy('archer',Vector2(380,650))
	trial.refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence_dir+'deployment.png')
	await mouse(trial.start_button.get_global_rect().get_center())
	assert(trial.rules.phase=='battle')
	trial.rules.deploy('cavalry',Vector2(530,310))
	trial.rules.deploy('cavalry',Vector2(530,770))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence_dir+'cavalry-deployed.png')
	for i in 3600:
		trial.rules.step(1.0/60)
		trial.rules.events.clear()
	if poseidon:
		trial.character_picker.item_selected.emit(trial.character_ids.find('poseidon'))
	else:
		await mouse(trial.buttons.lightning.get_global_rect().get_center())
	assert(trial.selected=='lightning')
	trial.selected=''
	var hotkey=InputEventKey.new()
	hotkey.physical_keycode=KEY_Q
	hotkey.pressed=true
	root.push_input(hotkey,true)
	await process_frame
	assert(trial.selected=='lightning')
	await mouse(trial.field.project(trial.rules.alive('enemy')[0].pos))
	assert(trial.rules.charges==2 and trial.rules.cooldown==0)
	await mouse(trial.buttons.lightning.get_global_rect().get_center())
	assert(trial.rules.charges==2 and trial.rules.cooldown==0 and trial.selected=='lightning')
	if poseidon:
		trial.paused=true
		var windup=trial.field.effects.filter(func(e):return e.kind=='sea_wave')[0]
		windup.age=.12
		trial.field.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(evidence_dir+'poseidon-windup.png')
		trial.paused=false
		await create_timer(.55).timeout
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence_dir+('sea_wave.png' if poseidon else 'lightning.png'))
	if poseidon:
		var quake=trial.field.effects.filter(func(e):return e.kind=='sea_wave')[0]
		trial.paused=true
		var age=quake.age
		await process_frame
		assert(quake.age==age)
		trial.paused=false
		while quake.age<.7:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(evidence_dir+'poseidon-recovery.png')
		while quake.age<.88:await process_frame
		assert(trial.field.apparition_alpha(quake.age)<1 and trial.field.apparition_alpha(quake.age)>0)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(evidence_dir+'apparition-fading.png')
		while quake.age<2.3:await process_frame
		assert(trial.field.apparition_alpha(quake.age)==0)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(evidence_dir+'apparition-gone.png')
	trial.paused=true
	var time=trial.rules.elapsed
	await process_frame
	assert(trial.rules.elapsed==time)
	trial.rules.phase='victory'
	trial.refresh()
	trial.start_button.pressed.emit()
	assert(trial.rules.phase=='deploy')
	assert(trial.rules.units.size()==6)
	assert(trial.field.effects.is_empty())
	if poseidon:assert(trial.rules.deity=='poseidon' and trial.rules.charges==2 and trial.rules.waves.is_empty())
	trial.closed.emit()
	await process_frame
	assert(main.visible and main.is_processing())
	assert(main.campaign.g==before)
	main.language='en'
	main.open_tactical_trial()
	await process_frame
	trial=root.get_child(root.get_child_count()-1)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence_dir+'deployment-en.png')
	assert(trial.buttons.legion.text.contains('Infantry'))
	trial.closed.emit()
	await process_frame
	print('TACTICAL SCENE: pause, retry, exit, campaign isolation PASS')
	main.queue_free()
	for i in 3:await process_frame
	quit()

func mouse(pos: Vector2):
	for pressed in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=pos
		event.global_position=pos
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		root.push_input(event,true)
	await process_frame
