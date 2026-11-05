extends SceneTree

var failures=0
var output="res://../output/rts-battle/"
func _initialize():call_deferred('run')

func check(ok: bool, description: String):
	if not ok:
		failures+=1
		push_error(description)

func march_end(u: Dictionary) -> Vector2:
	return u.destination if u.waypoints.is_empty() else u.waypoints.back()

func mouse_button(pos: Vector2, index: MouseButton, down: bool, shift: bool=false):
	var event=InputEventMouseButton.new()
	event.shift_pressed=shift
	event.position=pos
	event.global_position=pos
	event.button_index=index
	event.pressed=down
	root.push_input(event,true)

func click(pos: Vector2, index: MouseButton=MOUSE_BUTTON_LEFT):
	mouse_button(pos,index,true)
	mouse_button(pos,index,false)
	await process_frame

func pan(start: Vector2, delta: Vector2):
	mouse_button(start,MOUSE_BUTTON_LEFT,true)
	var motion=InputEventMouseMotion.new()
	motion.position=start+delta
	motion.global_position=motion.position
	motion.button_mask=MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion,true)
	mouse_button(motion.position,MOUSE_BUTTON_LEFT,false)
	await process_frame

func screenshot(name: String):
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(output+name+'.png')

func run():
	create_timer(40).timeout.connect(func():push_error("RTS TEST TIMEOUT");quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var main=load("res://scenes/main.tscn").instantiate()
	main.run_path_override='user://rts-verification-absent.cfg'
	root.add_child(main)
	await process_frame
	main.language='zh'
	await click(main.menu_view.options[0].get_global_rect().get_center())
	var trial=root.get_child(-1)
	check(trial.has_method('field_point'),'Primary entry opens commander')
	var field=trial.field
	var r=trial.rules
	check(r.bounds.size==Vector2(2860,1060),'Larger manoeuvre area')
	var classic=field.tex(field.environment.BACKGROUNDS[0])
	var extended: Texture2D=field.environment.surface.texture
	check(extended.get_size()==classic.get_size()*2,'Four times as many source texels')
	check(field.environment.surface.scale.is_equal_approx(Vector2(1920,1080)/classic.get_size()),'Classic terrain texels per world unit')
	await click(trial.setup_button.get_global_rect().get_center())
	var front=r.alive('ally').filter(func(u):return u.kind=='legion')
	check(front.size()==2 and r.reserve.archer==1 and r.reserve.cavalry==1 and r.reserve.legion==0,'Vanguard leaves two reserves')
	for i in front.size():
		var feet: Vector2=field.project(front[i].pos)-Vector2(0,35)
		mouse_button(feet,MOUSE_BUTTON_LEFT,true,i>0)
		mouse_button(feet,MOUSE_BUTTON_LEFT,false,i>0)
	check(trial.squad_ids.size()==2,'Pre-battle additive selection')
	var first=Vector2(570,465)
	var last=Vector2(610,785)
	mouse_button(field.project(first),MOUSE_BUTTON_RIGHT,true)
	var rank_motion=InputEventMouseMotion.new()
	rank_motion.position=field.project(last)
	rank_motion.button_mask=MOUSE_BUTTON_MASK_RIGHT
	root.push_input(rank_motion,true)
	check(trial.placing_rank and trial.rank_dragged,'Live rank preview')
	await screenshot('deploy-line')
	mouse_button(field.project(last),MOUSE_BUTTON_RIGHT,false)
	check(front[0].pos.distance_to(first)<1 and front[1].pos.distance_to(last)<1,'Release places both ends of rank')
	var stock=r.reserve.duplicate()
	await click(field.project(Vector2(900,750)),MOUSE_BUTTON_RIGHT)
	check(front[0].pos.distance_to(first)<1 and front[1].pos.distance_to(last)<1 and r.reserve==stock,'Invalid layout preserves every squad and stock')
	var recall=InputEventKey.new()
	recall.physical_keycode=KEY_R
	recall.pressed=true
	root.push_input(recall,true)
	check(r.reserve.legion==2 and r.alive('ally').size()==2,'Recall selected squads')
	trial.retry()
	r=trial.rules
	var drop=field.project(Vector2(650,420))
	await pan(drop,Vector2(-180,-80))
	check(trial.camera_offset.distance_to(Vector2(180,80))<2 and r.alive('ally').is_empty(),'Dragging a deployment location pans without spawning')
	await pan(drop,Vector2(180,80))
	for p in [Vector2(650,420),Vector2(650,700)]:
		await click(field.project(p))
	check(r.alive('ally').size()==2,'Deployment via pointer')
	await click(trial.start_button.get_global_rect().get_center())
	check(r.phase=='battle','Start via button')
	trial.paused=true
	var units=r.alive('ally')
	var a: Vector2=field.project(units[0].pos)-Vector2(0,35)
	var b: Vector2=field.project(units[1].pos)-Vector2(0,35)
	var first_goal=Vector2(865,470)
	var second_goal=Vector2(475,650)
	await click(a)
	check(trial.selected=='route' and trial.squad_ids==[units[0].id],'Click squad to aim the route')
	await click(field.project(first_goal))
	check(trial.selected=='' and march_end(units[0]).distance_to(first_goal)<1,'Click terrain commits the arrow')
	trial.paused=false
	await create_timer(.22).timeout
	trial.paused=true
	var turn: Vector2=units[0].pos
	check(turn.distance_to(first_goal)<Vector2(650,420).distance_to(first_goal),'March along first route')
	a=field.project(turn)-Vector2(0,35)
	await click(a)
	root.warp_mouse(field.project(second_goal))
	await process_frame
	await screenshot('route-arrow')
	await click(field.project(second_goal))
	check(units[0].destination.distance_to(second_goal)<1 and units[1].order=='auto','Retarget only the chosen squad')
	trial.paused=false
	await create_timer(.22).timeout
	trial.paused=true
	check(units[0].pos.distance_to(second_goal)<turn.distance_to(second_goal),'Squad turns toward the new destination')
	a=field.project(units[0].pos)-Vector2(0,35)
	await click(a)
	var cancel=InputEventKey.new()
	cancel.physical_keycode=KEY_ESCAPE
	cancel.pressed=true
	root.push_input(cancel,true)
	check(trial.selected=='' and trial.paused and units[0].destination.distance_to(second_goal)<1,'Escape preserves the committed order and pause')
	b=field.project(units[1].pos)-Vector2(0,35)
	var box=Rect2(a,Vector2.ZERO).expand(b).grow(18)
	mouse_button(box.position,MOUSE_BUTTON_LEFT,true,true)
	var motion=InputEventMouseMotion.new()
	motion.position=box.end
	motion.global_position=box.end
	motion.button_mask=MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion,true)
	mouse_button(box.end,MOUSE_BUTTON_LEFT,false,true)
	check(trial.squad_ids.size()==2,'Box selects two live squads')
	await click(field.project(Vector2(940,850)),MOUSE_BUTTON_RIGHT)
	check(units.all(func(u):return u.order=='move'),'Group move while paused')
	var before: Vector2=units[0].pos
	await create_timer(.12).timeout
	check(units[0].pos==before,'Orders during pause do not move units')
	trial.paused=false
	await create_timer(.20).timeout
	check(units[0].pos.distance_to(before)>0,'Active movement')
	var enemy=r.alive('enemy')[1]
	await click(field.project(enemy.pos)-Vector2(0,35),MOUSE_BUTTON_RIGHT)
	check(units.all(func(u):return u.order=='attack' and u.target_id==enemy.id),'Right click focuses real target')
	await click(trial.start_button.get_global_rect().get_center())
	check(units.all(func(u):return u.order=='hold'),'Hold button')
	await screenshot('native-scale')
	var selection: Array=trial.squad_ids.duplicate()
	var old_orders=units.map(func(u):return u.order)
	await pan(Vector2(1100,720),Vector2(-540,-220))
	check(trial.squad_ids==selection and units.map(func(u):return u.order)==old_orders,'Camera drag preserves orders and selection')
	await screenshot('native-scale-panned')
	await pan(Vector2(480,410),Vector2(540,220))
	var anchor=Vector2(930,650)
	var original=trial.field_point(anchor)
	await click(anchor,MOUSE_BUTTON_WHEEL_UP)
	check(trial.zoom>1 and trial.field_point(anchor).distance_to(original)<3,'Zoom anchored at cursor')
	var old_offset=trial.camera_offset
	var pan=InputEventMouseMotion.new()
	pan.button_mask=MOUSE_BUTTON_MASK_MIDDLE
	pan.position=anchor
	pan.relative=Vector2(-120,-70)
	root.push_input(pan,true)
	check(trial.camera_offset.distance_to(old_offset)>80,'Middle drag pans actual view')
	for i in 3:await click(anchor,MOUSE_BUTTON_WHEEL_DOWN)
	check(trial.zoom==.5,'Wheel reaches full overview')
	check(field.unproject(trial.field_point((field.project(Vector2(2300,1150))-trial.camera_offset)*trial.zoom)).distance_to(Vector2(2300,1150))<.01,'Expanded coordinates round trip')
	var far_point=Vector2(2400,1100)
	await click((field.project(far_point)-trial.camera_offset)*trial.zoom,MOUSE_BUTTON_RIGHT)
	check(units.all(func(u):return u.order=='move' and march_end(u).x>1640),'Orders reach new flank')
	trial.choose_deity('poseidon')
	await pan(Vector2(940,600),Vector2(-130,-80))
	check(r.waves.is_empty() and trial.selected=='lightning','Dragging while targeting never casts')
	var target=Vector2(2240,1100)
	await click((field.project(target)-trial.camera_offset)*trial.zoom)
	check(not r.waves.is_empty() and r.waves.back().start.x>1640,'Sea travels beyond old field')
	trial.selected=''
	trial.field.queue_redraw()
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(output+'overview.png')
	trial.retry()
	check(trial.squad_ids.is_empty() and trial.zoom==1 and trial.rules.phase=='deploy','Retry resets orders and view')
	trial.closed.emit()
	await process_frame
	check(main.visible,'Menu return')
	main.queue_free()
	await create_timer(.3).timeout
	print('RTS native input: ',failures,' failures')
	quit(1 if failures else 0)
