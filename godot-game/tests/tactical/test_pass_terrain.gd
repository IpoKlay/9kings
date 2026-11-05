extends SceneTree

const OUTPUT='res://../output/pass-terrain/'
const Plain=preload('res://scripts/tactical/trial_rules.gd')
var t
var r
var errors=0
var direct: Array[Vector2]=[]
var trace: FileAccess

func _initialize():call_deferred('run')

func check(ok: bool, note: String):
	if not ok:
		errors+=1
		push_error(note)

func click(pos: Vector2):
	for down in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=pos
		event.global_position=pos
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=down
		root.push_input(event,true)

func world(p: Vector2) -> Vector2:return r.terrain.inverse*p

func spawn(kind: String, side: String, pos: Vector2) -> Dictionary:
	r.spawn(kind,side,world(pos))
	r.units.back().order='hold'
	return r.units.back()

func fixture():
	t.retry()
	r=t.rules
	r.units.clear()
	spawn('legion','enemy',Vector2(2100,1030))
	t.paused=true

func select(u: Dictionary):
	click(r.projection*u.pos-Vector2(0,35))
	check(t.squad_ids==[u.id] and t.selected=='route','Select regiment with mouse')

func step_and_record(label: String, frame: int, u: Dictionary):
	var pos: Vector2=r.projection*u.pos
	trace.store_line('%s,%d,%d,%.3f,%.3f,%s,%s'%[label,frame,u.id,pos.x,pos.y,u.order,u.obstruction])

func snap(label: String, cursor: Vector2):
	root.warp_mouse(cursor)
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(OUTPUT+label+'.png')

func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	trace=FileAccess.open(OUTPUT+'tracks.csv',FileAccess.WRITE)
	trace.store_line('case,tick,regiment,projected_x,projected_y,order,reason')
	var main=load('res://scenes/main.tscn').instantiate()
	main.run_path_override='user://terrain-verification-absent.cfg'
	root.add_child(main)
	await process_frame
	main.language='zh'
	click(main.menu_view.get_node('TacticalTrial').get_global_rect().get_center())
	await process_frame
	t=root.get_child(-1)
	fixture()
	var rider=spawn('cavalry','ally',Vector2(630,796))
	r.start()
	select(rider)
	var end=Vector2(1430,796)
	var shown: Dictionary=r.plan_route(rider,direct,world(end))
	check(shown.ok and shown.points.size()>1,'Detour has clearance corners')
	await snap('01-detour',end)
	click(end)
	var issued: Array=[rider.destination]
	issued.append_array(rider.waypoints)
	check(issued.size()==shown.points.size(),'Preview and command use the same number of legs')
	for i in mini(issued.size(),shown.points.size()):
		check(issued[i].distance_to(shown.points[i])<.02,'Preview and command agree')
	var hit=0
	var safe=true
	for tick in 1400:
		var old: Vector2=rider.pos
		r.step(1./60)
		safe=safe and r.terrain.clear_segment(rider.kind,old,rider.pos)
		var half: Vector2=r.terrain.extents[rider.kind]
		var footprint=Rect2(r.projection*rider.pos-half,half*2)
		for rock in r.terrain.ROCKS:
			if footprint.intersects(rock):safe=false
		step_and_record('detour',tick,rider)
		if hit<issued.size() and rider.pos.distance_to(issued[hit])<.02:hit+=1
		if rider.order=='hold':break
	check(safe and hit==issued.size() and rider.pos.distance_to(world(end))<.02,'Cross every preview vertex and arrive without clipping')
	select(rider)
	var bad=Vector2(1022,791)
	await snap('02-unreachable',bad)
	click(bad)
	check(t.selected=='route' and rider.order=='hold' and not r.plan_route(rider,direct,world(bad)).ok,'Invalid click preserves current order')
	var slot=world(Vector2(1022,859))
	check(r.terrain.clear_segment('medic',slot,slot) and not r.terrain.clear_segment('legion',slot,slot),'Passability depends on footprint')

	fixture()
	var lead=spawn('legion','ally',Vector2(790,890))
	var rear=spawn('cavalry','ally',Vector2(480,890))
	r.start()
	select(lead)
	click(Vector2(1540,890))
	select(rear)
	click(Vector2(1210,890))
	var waiting=0
	var overlap=false
	var captured=false
	for tick in 1800:
		r.step(1./60)
		var delta: Vector2=(r.projection.basis_xform(lead.pos-rear.pos)).abs()
		var clearance: Vector2=r.terrain.extents[lead.kind]+r.terrain.extents[rear.kind]
		if delta.x<clearance.x and delta.y<clearance.y:overlap=true
		step_and_record('gate',tick,lead)
		step_and_record('gate',tick,rear)
		if rear.obstruction=='queue':
			waiting+=1
			if not captured:
				await snap('03-queue',Vector2(1210,890))
				captured=true
		if rear.order=='hold' and lead.order=='hold':break
	check(waiting>0 and not overlap and rear.pos.distance_to(world(Vector2(1210,890)))<.02 and lead.pos.distance_to(world(Vector2(1540,890)))<.02,'Faster rear waits then clears single-file gate')
	print('Waiting simulation ticks: ',waiting)
	fixture()
	rider=spawn('cavalry','ally',Vector2(520,610))
	var enemy=spawn('legion','enemy',Vector2(1090,610))
	r.start()
	select(rider)
	click(Vector2(1440,610))
	for tick in 1000:
		r.step(1./60)
		step_and_record('contact',tick,rider)
		if rider.order=='attack':break
	check(rider.obstruction=='contact' and rider.target_id==enemy.id and rider.waypoints.is_empty(),'Defending line breaks march into existing attack order')
	await snap('04-intercept',Vector2(1440,610))
	select(rider)
	click(Vector2(450,600))
	r.step(1./60)
	check(rider.order=='move' and rider.obstruction=='','New order pulls squad back after interception')
	var plain=Plain.new()
	plain.deploy_vanguard()
	plain.start()
	var army=plain.alive('ally')
	var diff: Vector2=army[0].pos-army[1].pos
	plain.command([army[0].id,army[1].id],'move',Vector2(900,680))
	check((army[0].destination-army[1].destination).is_equal_approx(diff) and army[0].waypoints.is_empty(),'Open-field group keeps original slots and straight march')
	trace.close()
	t.closed.emit()
	await process_frame
	main.queue_free()
	await process_frame
	print('PASS TERRAIN failures: ',errors)
	quit(1 if errors else 0)
