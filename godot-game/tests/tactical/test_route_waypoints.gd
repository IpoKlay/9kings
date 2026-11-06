extends SceneTree
const Shutdown=preload('res://tests/tactical/helpers/native_shutdown.gd')

const OUTPUT="res://../output/rts-waypoints/"
var failures=0
var trial
var main

func _initialize():call_deferred('run')

func check(ok: bool,message: String):
	if not ok:
		failures+=1
		push_error(message)

func screen(p: Vector2) -> Vector2:
	return (trial.field.project(p)-trial.camera_offset)*trial.zoom

func mouse(pos: Vector2,button: MouseButton,down: bool,shift: bool=false):
	var event=InputEventMouseButton.new()
	event.position=pos
	event.global_position=pos
	event.button_index=button
	event.pressed=down
	event.shift_pressed=shift
	root.push_input(event,true)

func click(pos: Vector2,shift: bool=false,button: MouseButton=MOUSE_BUTTON_LEFT):
	mouse(pos,button,true,shift)
	mouse(pos,button,false,shift)

func drag(start: Vector2,end: Vector2,shift: bool):
	mouse(start,MOUSE_BUTTON_LEFT,true,shift)
	var motion=InputEventMouseMotion.new()
	motion.position=end
	motion.global_position=end
	motion.relative=end-start
	motion.shift_pressed=shift
	motion.button_mask=MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion,true)
	mouse(end,MOUSE_BUTTON_LEFT,false,shift)

func key(code: Key):
	var event=InputEventKey.new()
	event.physical_keycode=code
	event.pressed=true
	root.push_input(event,true)

func select_cavalry(unit: Dictionary):
	click(screen(unit.pos)-Vector2(0,35)*trial.zoom)
	check(trial.selected=='route' and trial.squad_ids==[unit.id],'Click selects cavalry and opens arrow')

func exercise(mode: String):
	var pass_mode=mode=='pass'
	var entry=main.menu_view.get_node('TacticalTrial')
	click(entry.get_global_rect().get_center())
	await process_frame
	trial=root.get_child(-1)
	var preset=trial.defender_button if pass_mode else trial.setup_button
	click(preset.get_global_rect().get_center())
	await process_frame
	click(trial.start_button.get_global_rect().get_center())
	await process_frame
	key(KEY_SPACE)
	check(trial.paused,'Paused through input')
	var rider: Dictionary=trial.rules.alive('ally').filter(func(u):return u.kind=='cavalry')[0]
	var points=[Vector2(390,1080),Vector2(330,810),Vector2(800,1150)]
	var previous_goal=Vector2(735,1170)
	select_cavalry(rider)
	click(screen(previous_goal))
	key(KEY_SPACE)
	for i in 14:await process_frame
	key(KEY_SPACE)
	var before: Vector2=rider.pos

	select_cavalry(rider)
	click(screen(points[0]),true)
	key(KEY_ESCAPE)
	check(trial.draft_waypoints.is_empty() and rider.destination.distance_to(previous_goal)<1 and rider.order=='move','Esc preserves the existing march')
	select_cavalry(rider)
	click(screen(points[0]),true)
	var camera_before: Vector2=trial.camera_offset
	drag(Vector2(1000,710),Vector2(937,676),false)
	click(screen(points[1]),false,MOUSE_BUTTON_WHEEL_UP)
	check(camera_before!=trial.camera_offset and trial.draft_waypoints.size()==1,'Camera gestures preserve draft')
	click(screen(Vector2(185,750)),true)
	click(screen(Vector2(185,750)))
	check(trial.draft_waypoints.size()==1 and trial.selected=='route' and rider.destination.distance_to(previous_goal)<1,'Invalid waypoint and invalid endpoint preserve old order and draft')
	click(screen(points[1]),true)
	check(trial.draft_waypoints.size()==2 and rider.destination.distance_to(previous_goal)<1,'Shift taps add points without dispatch')
	root.warp_mouse(screen(points[2]))
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(OUTPUT+mode+'-preview.png')
	click(screen(points[2]))
	check(trial.selected=='' and rider.destination.distance_to(points[0])<1 and rider.waypoints.size()==2,'Confirm replaces the previous march')
	select_cavalry(rider)
	click(screen(points[2]),true)
	key(KEY_ESCAPE)
	check(rider.waypoints.size()==2 and rider.destination.distance_to(points[0])<1,'Cancel preserves the committed queue')
	select_cavalry(rider)
	click(screen(points[1]),true)
	var center=screen(rider.pos)-Vector2(0,35)*trial.zoom
	drag(center-Vector2(40,40),center+Vector2(40,40),true)
	check(trial.selected=='' and trial.draft_waypoints.is_empty() and rider.id in trial.squad_ids and rider.waypoints.size()==2,'Shift drag box-selects without adding a waypoint')
	await process_frame
	check(rider.pos==before,'No movement during planning pause')
	var trace=FileAccess.open(OUTPUT+mode+'-track.csv',FileAccess.WRITE)
	trace.store_line('battle_seconds,x,y,waypoint_reached')
	key(KEY_SPACE)
	var reached=0
	for frame in 650:
		await process_frame
		var mark=''
		if reached<points.size() and rider.pos.distance_to(points[reached])<.1:
			reached+=1
			mark=str(reached)
			print(mode,' reached ',reached,' at ',rider.pos)
		trace.store_line('%.4f,%.4f,%.4f,%s'%[trial.rules.elapsed,rider.pos.x,rider.pos.y,mark])
		if rider.order=='hold':break
	trace.close()
	check(reached==3 and rider.order=='hold' and rider.waypoints.is_empty(),mode+' crossed both turns and stopped at goal')
	trial.closed.emit()
	await process_frame

func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	main=load('res://scenes/main.tscn').instantiate()
	main.run_path_override='user://waypoints-absent.cfg'
	root.add_child(main)
	await process_frame
	main.language='zh'
	await exercise('rts')
	await exercise('pass')
	main.queue_free()
	await process_frame
	print('Waypoint native input failures: ',failures)
	await Shutdown.settle(self)
	quit(1 if failures else 0)
