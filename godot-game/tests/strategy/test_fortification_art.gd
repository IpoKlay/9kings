extends 'res://tests/strategy/test_contextual_ui.gd'
const FortArt=preload('res://scripts/strategy/fortification_art.gd')
func run():
	var main=load('res://scenes/main.tscn').instantiate();main.settings_path='/tmp/fort-art-ui.cfg'
	root.add_child(main);main.sound.enabled=false
	for i in 4:await process_frame
	click(main.menu_view.get_node('%TacticalTrial').get_global_rect().get_center())
	for i in 4:await process_frame
	var t=main.active_trial;t.set_process(false);var r=t.rules
	var art=t.field.pass_layout.fortifications
	check(art.manifest.frames.size()==48,'All eight directions have three wall lengths, two door states and a corner joint')
	check(art.ATLAS.get_size()==Vector2(1536,1152),'Single bounded Blender sprite page is loaded')
	for direction in 8:
		var b={'kind':'wall','wall_angle':direction*PI/4.,'wall_length':64.}
		check(art.frame_key(b)=='wall_'+str(direction),'Wall uses its rendered direction without rotating a PNG')
	var walls=r.buildings.filter(func(b):return b.get('initial_wall',false))
	var corners=r.world.wall_vertices()
	var max_error=0.
	for i in 8:
		var edge=walls.filter(func(b):return posmod(roundi(b.wall_angle/(PI/4.)),8)==i)
		var total=0.
		for b in edge:
			total+=b.wall_length
			var frame=art.manifest.frames[art.frame_key(b)]
			max_error=maxf(max_error,absf(frame.length-b.wall_length))
		check(absf(total-corners[i].distance_to(corners[(i+1)%8]))<.001,'Every edge ends exactly at its next corner')
	check(max_error<.001,'Source model lengths match the actual game module lengths')
	check(art.structures_with_joints(r).filter(func(b):return b.kind=='corner').size()==8,'Eight intact junctions receive modelled corner pieces')
	var broken=walls[0];var health: float=broken.hp;broken.hp=0
	check(art.structures_with_joints(r).filter(func(b):return b.kind=='corner').size()==7,'Destroyed endpoint removes its decorative join instead of hiding the breach')
	broken.hp=health
	var gate=walls.filter(func(b):return b.kind=='gate' and b.pos.x<r.world.CENTER.x-400)[0]
	t.zoom=1.5;t.set_camera(gate.pos-Vector2(850,530)/t.zoom)
	await snap('fort-open-closeup',t)
	var worker=r.alive('ally')[0];var nav=r.Soldiers.navigator(r,worker.kind,worker)
	var normal=r.world.CENTER.direction_to(gate.pos)
	check(r.terrain.clear_segment(nav,gate.pos-normal*80,gate.pos+normal*80),'Open gate retains the real navigable passage')
	gate.open=false;r.rebuild_obstacles()
	check(art.frame_key(gate).begins_with('gate_closed'),'Closed door selects the separately rendered closed 3D model')
	check(not r.terrain.clear_segment(nav,gate.pos-normal*80,gate.pos+normal*80),'Closed gate blocks that same passage')
	await snap('fort-closed-closeup',t)
	gate.open=true;r.rebuild_obstacles();t.reset_camera()
	click(point(t,worker.pos)-Vector2(0,20));await process_frame;await process_frame
	var ui=t.get_meta('strategy_interface')
	ui.actions['build:gate'].pressed.emit();ui.mouse_world=r.world.CENTER+Vector2(200,150)
	check(ui.mode=='build' and ui.build_kind=='gate','Gate placement preview uses the same rendered model before construction')
	await snap('fort-gate-placement',t);key(KEY_ESCAPE)
	t.toggle_overview();await snap('fort-overview',t)
	print('FORTIFICATION ART CHECKS=',checks,' FAILURES=',failures)
	t.queue_free();main.queue_free();await process_frame;await create_timer(.2).timeout;quit(1 if failures else 0)
