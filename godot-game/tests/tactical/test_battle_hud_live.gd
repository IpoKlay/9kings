extends SceneTree
## Requires the complete native project. Terminal outcomes below are explicit
## UI fixtures, not evidence of victory or balance in a full simulated battle.
var failures=0
var checks=0
var output='res://../output/battle-hud/'

func _initialize():call_deferred('run')

func check(ok: bool, description: String):
	checks+=1
	if not ok:
		failures+=1
		push_error(description)

func click(point: Vector2):
	for down in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=point
		event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=down
		root.push_input(event,true)
	await process_frame

func screenshot(name: String):
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output+name+'.png')==OK,'Save '+name)

func run():
	create_timer(100).timeout.connect(func():push_error('HUD live test timeout');quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1920,1080)
	var main=load('res://scenes/main.tscn').instantiate()
	main.run_path_override='user://battle-hud-test-no-campaign.cfg'
	root.add_child(main)
	await process_frame
	main.language='zh'
	main.menu_view.render()
	var campaign=main.campaign.g.duplicate(true)
	await click(main.menu_view.options[0].get_global_rect().get_center())
	var trial=root.get_child(-1)
	check(trial.has_node('BattleHUD/BattleActions/StartButton'),'Main-menu entry instantiates the authored HUD')
	check(trial.start_button.pressed.get_connections().size()==1,'Start has one permanent action connection')
	check(trial.start_button.disabled,'Empty deployment cannot begin')
	await screenshot('deployment-zh')
	await click(trial.combined_button.get_global_rect().get_center())
	check(trial.rules.alive('ally').size()==7,'Seven-arm formation through its real button')
	check(not trial.deployment_actions.visible and trial.regiment_roster.visible,'Deployment actions switch to regiment roster')
	await click(trial.start_button.get_global_rect().get_center())
	check(trial.rules.phase=='battle','Start button begins battle')
	await click(trial.pause_button.get_global_rect().get_center())
	var elapsed=trial.rules.elapsed
	await process_frame
	check(trial.paused and trial.rules.elapsed==elapsed,'Pause button freezes battle')
	await click(trial.roster[0].get_global_rect().get_center())
	check(trial.squad_ids.size()==1,'Roster selects a living regiment')
	await click(trial.start_button.get_global_rect().get_center())
	check(trial.squad_at_id().order=='hold','Reused Start button commands Hold')
	await click(trial.hud.get_node('TopActions/HelpButton').get_global_rect().get_center())
	check(trial.controls.visible and trial.power_note.visible,'Help and actual power description open together')
	await screenshot('battle-zh')
	await click(trial.pause_button.get_global_rect().get_center())
	await click(trial.buttons.lightning.get_global_rect().get_center())
	check(trial.selected=='lightning','Power button enters existing targeting mode')
	var target=trial.rules.alive('enemy')[0].pos
	var screen: Vector2=(trial.field.project(target)-trial.camera_offset)*trial.zoom
	await click(screen)
	check(trial.notice==trial.words('神力已施放','Power released'),'Target click executes actual divine power')
	await screenshot('power-zh')
	for phase in ['victory','defeat','timeout']:
		trial.rules.phase=phase
		trial.refresh()
		check(trial.result.visible and trial.start_button.text=='重新试战','Terminal UI fixture '+phase)
		await screenshot('result-'+phase)
		await click(trial.start_button.get_global_rect().get_center())
		check(trial.rules.phase=='deploy' and trial.rules.alive('ally').is_empty(),'One retry click returns only to deployment: '+phase)
		check(not trial.result.visible and trial.field.effects.is_empty(),'Retry clears result and effects')
		check(trial.start_button.pressed.get_connections().size()==1,'No additional connection after retry')
		if phase!='timeout':
			await click(trial.defender_button.get_global_rect().get_center())
			check(trial.rules.alive('ally').size()==7,'Defensive-line button remains connected after retry')
			await click(trial.start_button.get_global_rect().get_center())
			check(trial.rules.phase=='battle','Start remains connected after retry')
	# Repeated refresh must never add a callback or move the independent button.
	var position: Vector2=trial.start_button.position
	for i in 30:trial.refresh()
	check(trial.start_button.position==position,'Refresh preserves scene-owned geometry')
	check(trial.start_button.pressed.get_connections().size()==1,'Refresh never reconnects Start')
	await click(trial.menu_button.get_global_rect().get_center())
	await process_frame
	check(main.visible and main.is_processing(),'Menu button restores main menu')
	check(main.campaign.g==campaign,'HUD actions preserve expedition progress')
	main.language='en'
	main.menu_view.render()
	await click(main.menu_view.options[0].get_global_rect().get_center())
	trial=root.get_child(-1)
	check(trial.start_button.text=='Begin' and trial.buttons.legion.text.contains('Infantry'),'English deployment data')
	await screenshot('deployment-en')
	await click(trial.setup_button.get_global_rect().get_center())
	check(trial.rules.alive('ally').size()==4,'Vanguard button uses existing formation rules')
	await click(trial.start_button.get_global_rect().get_center())
	check(trial.start_button.text.begins_with('Hold'),'English battle action')
	await screenshot('battle-en')
	await click(trial.menu_button.get_global_rect().get_center())
	await process_frame
	# Simulate an editor save to a separate scene; leave production files untouched.
	var source=FileAccess.get_file_as_string('res://scenes/ui/battle_hud.tscn')
	var marker=source.find('[node name="StartButton"')
	check(marker>=0,'Find StartButton in authored scene')
	var tail=source.substr(marker)
	var next=tail.find('[node ',1)
	var block=tail.substr(0,next)
	var moved_block=block.replace('offset_left = -182.0','offset_left = -278.0').replace('offset_right = -18.0','offset_right = -114.0')
	var file=FileAccess.open('user://battle-hud-moved.tscn',FileAccess.WRITE)
	file.store_string(source.substr(0,marker)+moved_block+tail.substr(next))
	file.close()
	file=FileAccess.open('user://battle-trial-moved.tscn',FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string('res://scenes/tactical_trial.tscn').replace('res://scenes/ui/battle_hud.tscn','user://battle-hud-moved.tscn'))
	file.close()
	var moved=load('user://battle-trial-moved.tscn').instantiate()
	moved.app=main
	main.hide()
	main.set_process(false)
	root.add_child(moved)
	await process_frame
	check(moved.start_button.position==position-Vector2(96,0),'Saved scene movement reaches the live controller')
	await click(moved.defender_button.get_global_rect().get_center())
	await click(moved.start_button.get_global_rect().get_center())
	check(moved.rules.phase=='battle','Moved button remains clickable')
	check(moved.start_button.position==position-Vector2(96,0),'Battle refresh does not reset moved StartButton')
	await screenshot('moved-start-button')
	moved.queue_free()
	main.queue_free()
	await process_frame
	for path in ['user://battle-hud-moved.tscn','user://battle-trial-moved.tscn']:DirAccess.remove_absolute(path)
	print('BATTLE HUD LIVE: %d checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
