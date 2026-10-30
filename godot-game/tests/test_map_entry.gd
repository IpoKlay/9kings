extends SceneTree
var view: SubViewport
var app
var checks=0
var failures=0
func _init():call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;printerr('FAIL: '+message)
func mouse(point: Vector2,down: bool,button=MOUSE_BUTTON_LEFT):
	var event=InputEventMouseButton.new();event.position=point;event.global_position=point
	event.button_index=button;event.pressed=down;view.push_input(event,true)
func click(control):
	var point=control.get_global_rect().get_center()
	mouse(point,true);mouse(point,false)
func capture(id):
	await process_frame;RenderingServer.force_draw()
	view.get_texture().get_image().save_png('res://../output/map-pin-entry/'+id+'.png')
func run():
	if DisplayServer.get_name()=='headless':printerr('Native renderer required');quit(1);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://../output/map-pin-entry'))
	var host=Window.new();root.add_child(host)
	view=SubViewport.new();view.size=Vector2i(1920,1080)
	view.size_2d_override=Vector2i(1920,1080);view.size_2d_override_stretch=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;host.add_child(view)
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/private/tmp/eagle-map-entry.cfg';view.add_child(app)
	app.set_process(false);app.language='zh';app.sound.enabled=true;app.sound.volume=.35;app.sound.voices=0
	app.starting_theaters.assign([1]);app.render_ui()
	await process_frame
	var frame_cap=Engine.max_fps
	click(app.menu_view.get_node('StartGame'))
	var map=app.expedition_map;var pins=map.pins;var sound=app.sound
	pins.set_process(false);map.atlas.set_process(false)
	check(map.visible and map.content.get_parent()==map and map.content.visible,'Start immediately shows the full map with no offscreen wrapper')
	check(not map.has_node('MapUnroll') and not app.input_locked,'Entry has no scroll overlay or input lock')
	check(not pins.finished and pins.age==0,'Pins start on the same input event')
	check(sound.map_paper_player.playing and not sound.page_player.playing,'Map opening plays a separate paper sound')
	check(is_equal_approx(sound.map_paper_player.volume_linear,.35*sound.preset.map_paper.gain),'Map sound follows master volume while voice volume is zero')
	check(pins.mouse_filter==Control.MOUSE_FILTER_IGNORE and pins.get_parent()==map,'Nails are click-through and outside the map camera')
	check(pins.centers()==[Vector2(30,30),Vector2(1890,30),Vector2(30,1050),Vector2(1890,1050)],'Four nails occupy four paper corners')
	for center in pins.centers():
		check(not Rect2(Vector2(48,44),Vector2(1800,60)).has_point(center),'Corner nails avoid toolbar controls')
	check(is_equal_approx(pins.duration(),.28),'The full nail feedback lasts 0.28 seconds')
	var state=app.expedition.state.duplicate(true);var bag=app.starting_theaters.duplicate()
	app.start_game()
	check(app.expedition.state==state and app.starting_theaters==bag,'Repeated Start cannot reroll an active run')
	await capture('entry-00')
	for frame in range(1,8):
		pins.advance(1.0/24)
		await capture('entry-%02d'%frame)
	check(pins.finished and pins.landed==[true,true,true,true] and not pins.is_processing(),'All four nails settle and stop processing')
	await capture('map-1080p')
	check(sound.map_pin_player.max_polyphony==4,'Tap overlap is bounded to four voices')
	check(app.expedition.state==state and Engine.max_fps==frame_cap,'Entry leaves campaign and frame cap unchanged')
	# Freeze a fresh drop to send genuine input through it, without timing races.
	map.present();pins.set_process(false);pins.advance(.06)
	var age=pins.age;var p=Vector2(960,540);var zoom=map.atlas.zoom
	mouse(p,true,MOUSE_BUTTON_WHEEL_UP);mouse(p,false,MOUSE_BUTTON_WHEEL_UP)
	check(map.atlas.zoom>zoom and pins.age==age,'Wheel zoom works while the nails are falling')
	var id=app.expedition.destinations()[0]
	map.atlas.focus_city(id);click(map.city_buttons[id])
	check(map.selected==id and not map.travel_button.disabled,'First city click opens intel immediately, without skipping an animation')
	check(map.pins==pins and pins.age==age and not pins.finished,'City selection rebuild does not restart or cancel the nails')
	await create_timer(.12).timeout
	var playback=sound.map_paper_player.get_playback_position()
	map.render()
	check(sound.map_paper_player.get_playback_position()>=playback and pins.age==age,'UI rebuild does not replay the paper sound')
	click(map.content.get_node('SettingsButton'))
	check(app.dialog_kind=='settings' and pins.finished,'Settings can open immediately and settles entry motion')
	check(not sound.map_paper_player.playing and not sound.map_pin_player.playing,'Opening a modal clears entry audio tails')
	app.close_dialog();app.return_to_menu();app.resume_game()
	check(not pins.finished and sound.map_paper_player.playing,'Returning to the map plays one new entry')
	app.return_to_menu()
	await create_timer(.35).timeout
	check(app.main_menu and pins.finished and not pins.is_processing() and not sound.map_pin_player.playing and not sound.map_paper_player.playing,'Early exit cancels motion and cannot play delayed taps')
	app.resume_game()
	await create_timer(.4).timeout
	check(pins.finished and not pins.is_processing() and map.visible,'Normal entry finishes naturally')
	# Reduced motion keeps the sound and all fasteners, without a falling animation.
	pins.begin(sound,true)
	check(pins.finished and not pins.is_processing() and sound.map_paper_player.playing,'Reduced motion displays static nails with paper sound')
	sound.stop_map_entry();sound.enabled=false;map.present()
	pins.advance(1)
	check(not sound.map_paper_player.playing and not sound.map_pin_player.playing,'Mute silences paper and taps')
	sound.enabled=true;sound.volume=0;map.present();pins.advance(1)
	check(not sound.map_paper_player.playing and not sound.map_pin_player.playing,'Zero master volume silences entry')
	sound.volume=.35;sound.play_page_turn();map.present()
	check(sound.page_player.playing and sound.map_paper_player.playing,'Map paper and book turning use independent players')
	sound.stop();map.settle_entry()
	view.size=Vector2i(1280,720)
	await capture('map-720p')
	check(pins.size==Vector2(1920,1080),'Window scaling preserves logical corner placement')
	# Exhausted campaign restart must still work after removing the old intro guard.
	app.campaign.g.phase='defeat';app.start_game()
	check(app.campaign.g.phase=='prepare' and app.expedition.state.opening=='destination','Defeat can still start a new campaign')
	map.settle_entry();app.sound.stop()
	print('%d map entry checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
