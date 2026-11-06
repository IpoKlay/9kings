extends SceneTree
var app
var checks=0
var failures=0
func _init(): call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)
func click(control: Control):
	var position=control.get_global_rect().get_center()
	for down in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=position;event.global_position=position
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
		root.push_input(event,true)
	await process_frame
func run():
	if DisplayServer.get_name()=='headless':
		printerr('Book playback validation requires a native window');quit(1);return
	root.size=Vector2i(1920,1080)
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/private/tmp/eagle-book-audio-test.cfg'
	root.add_child(app);current_scene=app
	app.restart_expedition(1);app.expedition_map.settle_entry()
	var sound=app.sound
	sound.enabled=true;sound.volume=.35;sound.stop()
	var docs=app.documents
	var first=docs.archive_ids()[0]
	docs.open_archive(first)
	await process_frame
	check(sound.page_player.stream is AudioStreamWAV,'The trimmed recording loads as native audio')
	check(absf(sound.page_player.stream.get_length()-.7)<.002,'The 1.2x result lasts 0.7 seconds')
	check(sound.page_player.max_polyphony==1,'Page turns use one voice')
	check(not sound.page_player.playing,'Opening the book does not play a page turn')
	docs.turn_page(-1)
	check(not sound.page_player.playing,'The first-page boundary stays silent')
	await click(app.modal.get_child(1).get_node('ArchiveNext'))
	check(sound.page_player.playing,'A mouse page turn starts the recording')
	check(sound.page_player.pitch_scale==1.0,'The baked 1.2x speed is not applied twice')
	check(is_equal_approx(sound.page_player.volume_db,linear_to_db(.35*.8)),'Page sound follows master volume')
	await create_timer(.12).timeout
	var key=InputEventKey.new();key.keycode=KEY_RIGHT;key.pressed=true
	root.push_input(key,true)
	await process_frame
	check(sound.page_player.playing and sound.page_player.get_playback_position()<.10,'Keyboard page turn restarts the same voice')
	app.close_dialog()
	check(not sound.page_player.playing,'Closing mid-turn stops the sound')
	docs.open_archive(first)
	docs.select_region(1)
	check(sound.page_player.playing,'A changed region plays its page-turn animation sound')
	sound.stop_page_turn();docs.select_region(1)
	check(not sound.page_player.playing,'Selecting the current region stays silent')
	var ids=docs.archive_ids()
	docs.archive_city=ids.back()
	docs.archive_page=docs.pages_for(app.expedition.node_text(docs.archive_city,'history')).size()-1
	docs.turn_page(1)
	check(not sound.page_player.playing,'The last-page boundary stays silent')
	sound.enabled=false;sound.play_page_turn()
	check(not sound.page_player.playing,'Mute prevents new page sound')
	sound.enabled=true;sound.volume=0;sound.play_page_turn()
	check(not sound.page_player.playing,'Zero volume prevents new page sound')
	sound.volume=.35;sound.play_page_turn()
	check(sound.page_player.playing,'Sound resumes when enabled')
	sound.stop()
	check(not sound.page_player.playing,'Global stop clears page sound')
	sound.play_page_turn()
	await create_timer(.8).timeout
	check(not sound.page_player.playing,'The clip ends naturally without looping')
	app.close_dialog();sound.stop()
	print('%d book audio checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
