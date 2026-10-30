extends SceneTree
var app
var view: SubViewport
var checks=0
var failures=0
func _init(): call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)
func click(control: Control):
	var pos=control.get_global_rect().get_center()
	for down in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=pos;event.global_position=pos
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
		view.push_input(event,true)
	await process_frame
func capture(id: String):
	if DisplayServer.get_name()=='headless': return
	await process_frame;RenderingServer.force_draw()
	view.get_texture().get_image().save_png('res://../output/map-pin-entry/'+id+'.png')
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://../output/map-pin-entry'))
	# A private viewport keeps the user's OS mouse/focus out of scripted input.
	var host=Window.new();root.add_child(host)
	view=SubViewport.new();view.size=Vector2i(1280,720)
	view.size_2d_override=Vector2i(1920,1080);view.size_2d_override_stretch=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	host.add_child(view)
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/private/tmp/eagle-paper-motion-test.cfg'
	view.add_child(app);app.sound.enabled=false
	var game_fps=Engine.max_fps
	app.starting_theaters.assign([1])
	await click(app.menu_view.get_node('StartGame'))
	var map=app.expedition_map
	map.settle_entry()
	var state=app.expedition.state.duplicate(true)
	map.atlas.focus_city('246349')
	await click(map.city_buttons['246349'])
	check(map.selected=='246349','Map clicks work before opening the archive')
	var camera=map.atlas.center
	await click(map.info.get_node('HistoryButton'))
	var old=app.documents.archive_city
	await click(app.modal.get_child(1).get_node('ArchiveNext'))
	check(app.documents.archive_city!=old and is_instance_valid(app.documents.page_turn),'Next commits once and starts a page turn')
	var turn=app.documents.page_turn
	turn.motion.pause()
	turn.set_progress(.2)
	var held_pose=turn.pose_index
	turn.set_progress(.21)
	check(turn.pose_index==held_pose,'Book holds discrete poses between animation ticks')
	for progress in [0.0,.25,.5,.75,1.0]:
		turn.set_progress(progress)
		await capture('page-'+str(progress))
	app.documents.cancel_turn()
	for i in 3: app.documents.turn_page(1)
	for i in 4: app.documents.turn_page(-1)
	check(app.documents.archive_city==old,'Rapid forward/backward presses preserve exactly one step per press')
	app.documents.turn_page(1)
	await create_timer(8.0/app.ui_preset.book_turn_fps+.15).timeout
	check(app.dialog_kind=='archive' and not is_instance_valid(app.documents.page_turn) and not app.has_node('BookPageTurn'),'A natural page turn finishes and frees its snapshots without closing the book')
	check(Engine.max_fps==game_fps,'Low frame-rate paper animation does not change the game frame cap')
	app.documents.select_region(3)
	check(app.documents.archive_region==3,'Region selection can interrupt a page turn')
	app.close_dialog()
	await create_timer(.4).timeout
	check(app.dialog_kind=='' and not is_instance_valid(app.documents.page_turn) and not app.has_node('BookPageTurn'),'Closing cancels snapshots and cannot reopen the book later')
	check(map.atlas.center==camera and app.expedition.state==state,'Turning pages preserves camera and campaign')
	app.return_to_menu();app.start_game();map.settle_entry()
	app.open_dialog('settings');app.close_dialog()
	check(preload('res://tests/expedition_test_support.gd').deploy(app),'Destination and first-card combat flow still works')
	app.sound.stop()
	print('%d paper animation checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
