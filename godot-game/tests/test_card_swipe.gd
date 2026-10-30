extends SceneTree
## Native input regressions: no press, hover, canceled drag or duplicate release can award a card.
var app
var view: SubViewport
var host: Window
var checks=0
var failures=0
var pick_sounds=0
func _init(): call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok:
		failures+=1;printerr('FAIL: '+message)
		if is_instance_valid(app.card_hand): printerr('Gesture context: dragging=',app.card_hand.dragging,' active=',app.card_hand.active)
func motion(point: Vector2):
	var event=InputEventMouseMotion.new();event.position=point;event.global_position=point
	view.push_input(event,true)
	await process_frame
func mouse(point: Vector2,down: bool,button: MouseButton=MOUSE_BUTTON_LEFT):
	var event=InputEventMouseButton.new();event.position=point;event.global_position=point
	event.button_index=button;event.pressed=down
	view.push_input(event,true)
	await process_frame
func key(code: Key):
	var event=InputEventKey.new();event.keycode=code;event.pressed=true
	view.push_input(event,true)
	await process_frame
func capture(name: String):
	await process_frame
	if DisplayServer.get_name()=='headless': return
	RenderingServer.force_draw()
	view.get_texture().get_image().save_png('res://../output/camp-expansion-v1/'+name+'.png')
func unchanged(before: Dictionary,message: String):
	check(app.campaign.g==before,message)
	check(not app.input_locked and not app.card_hand.locked,'Canceled gesture leaves selection unlocked')
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://../output/camp-expansion-v1'))
	# Isolate scripted gestures from other native tests or the user's OS cursor.
	host=Window.new()
	root.add_child(host)
	view=SubViewport.new()
	view.size=Vector2i(1280,720)
	view.size_2d_override=Vector2i(1920,1080)
	view.size_2d_override_stretch=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	host.add_child(view)
	app=load('res://scenes/main.tscn').instantiate()
	app.settings_path='/private/tmp/eagle-card-swipe-test.cfg'
	view.add_child(app)
	app.set_process(false);app.prefs.music_volume=0;app.apply_prefs();app.sound.enabled=false;app.language='zh'
	for window_size in [Vector2i(1280,720),Vector2i(1920,1080)]:
		view.size=window_size
		app.restart_expedition(1)
		app.travel_to(app.expedition.destinations()[0])
		app.campaign.finish(true);app.advance()
		app.campaign.g.offered=['legion','archer','medic'];app.render_ui()
		await create_timer(.5).timeout
		var hand=app.card_hand
		hand.cue.connect(func(cue):
			if cue=='pick': pick_sounds+=1)
		var before=app.campaign.g.duplicate(true)
		var start=hand.slots[0].origin+Vector2(120,150)
		var up=Vector2(0,-hand.preset.drag_threshold-12)
		await motion(start)
		for i in 2:
			await mouse(start,true);unchanged(before,'Press alone never uses a card')
			await mouse(start,false);unchanged(before,'Click/double-click does not use a card')
		for code in [KEY_1,KEY_2,KEY_3,KEY_ENTER,KEY_SPACE]:
			await key(code);unchanged(before,'Keyboard cannot bypass upward confirmation')
		for delta in [Vector2(0,-8),Vector2(0,-hand.preset.drag_threshold+1),Vector2(150,0),Vector2(0,120),Vector2(220,-110)]:
			await motion(start);await mouse(start,true);await motion(start+delta)
			check(hand.dragging==0,'Dragging over neighbouring cards keeps original ownership')
			await mouse(start+delta,false);unchanged(before,'Wrong direction or insufficient travel cancels')
		# Hovering upward or pressing outside the hand never arms it.
		await motion(start+Vector2(0,100));await motion(start+up)
		await mouse(start+up,false);unchanged(before,'Movement without a press cannot use a card')
		await motion(Vector2(300,950));await mouse(Vector2(300,950),true)
		await motion(start);await motion(start+up);await mouse(start+up,false)
		unchanged(before,'Pressing outside and moving into a card cannot use it')
		await motion(start);await mouse(start,true)
		var origin=hand.slots[0].card.position
		await motion(start+up)
		check(hand.ready_to_play and hand.slots[0].card.get_node('CardFrame').armed,'Threshold visibly arms the original card')
		check(hand.slots[0].card.position==origin+up,'Dragged card follows the pointer without easing delay')
		unchanged(before,'Crossing the threshold still waits for release')
		if window_size.x==1280: await capture('ready-to-release')
		await motion(start+Vector2(0,-12))
		check(not hand.ready_to_play,'Dragging back disarms the card')
		await mouse(start+Vector2(0,-12),false);unchanged(before,'Dragging back then releasing cancels')
		for cancel_mode in ['escape','right','focus','window_exit','modal']:
			await motion(start);await mouse(start,true);await motion(start+up)
			match cancel_mode:
				'escape': await key(KEY_ESCAPE)
				'right': await mouse(start+up,true,MOUSE_BUTTON_RIGHT)
				'focus': host.focus_exited.emit()
				'window_exit': host.mouse_exited.emit()
				'modal': app.open_dialog('settings')
			check(hand.dragging==-1 and not hand.ready_to_play,'Interruption cancels pending drag: '+cancel_mode)
			await mouse(start+up,false)
			if cancel_mode=='modal': app.close_dialog()
			check(app.dialog_kind=='','Escape/right-click cancel drag without opening another UI')
			unchanged(before,'Canceled release never selects: '+cancel_mode)
		await motion(Vector2(1600,600)) # No fresh hover should lift a card during the settling check.
		await create_timer(.3).timeout
		for slot in hand.slots: check(slot.card.position.is_equal_approx(slot.origin),'Canceled cards settle back into original hand')
		if window_size.x==1280: await capture('canceled')
		var sounds_before=pick_sounds
		await motion(start);await mouse(start,true)
		# A fast movement can reach release without a delivered motion event.
		await mouse(start+up,false)
		check(app.input_locked,'Valid upward release starts one commit')
		await mouse(start+up,false)
		await create_timer(.3).timeout
		check(app.campaign.g.chosen=='legion' and app.campaign.g.phase=='place','Valid release uses exactly the original card')
		check(pick_sounds==sounds_before+1,'Pick recording plays once, only for confirmation')
		check(app.campaign.place(6),'Chosen building is still placed normally')
		app.render_ui()
		check(app.campaign.g.phase=='prepare','First victory card finishes in camp')
		app.continue_expedition();app.travel_to(app.expedition.destinations()[0])
		check(app.campaign.g.phase=='battle','Next destination enters battle without another card')
		app.campaign.finish(true);app.render_ui();app.advance()
		check(app.campaign.g.phase=='reward','Victory still awards a new hand')
		await create_timer(.5).timeout
		hand=app.card_hand
		before=app.campaign.g.duplicate(true)
		start=hand.slots[1].origin+Vector2(120,150)
		await motion(start);await mouse(start,true);await mouse(start,false)
		unchanged(before,'Post-victory reward also rejects a plain click')
		var id=hand.slots[1].id
		await motion(start);await mouse(start,true);await motion(start+up);await mouse(start+up,false)
		await create_timer(.3).timeout
		check(app.campaign.g.chosen==id and app.campaign.g.phase!='reward','Post-victory reward uses the same upward gesture')
	app.sound.stop();app.music.set_process(false)
	for i in 2:app.music.retire_slot(i)
	await create_timer(.1).timeout;app.queue_free();await process_frame;await process_frame
	print('%d upward card gesture checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
