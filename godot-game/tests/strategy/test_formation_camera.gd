extends 'res://tests/strategy/test_contextual_ui.gd'
const Pan=preload('res://scripts/strategy/camera_pan.gd')
const Layout=preload('res://scripts/strategy/formation.gd')
func run():
	var pan=Pan.new()
	var first=pan.advance(Vector2.RIGHT,1./60).x
	var last=0.
	for i in 30:last=pan.advance(Vector2.RIGHT,1./60).x
	check(first>0 and first<last*.2 and last<920./60,'Smooth acceleration rather than instant full speed')
	var speed=pan.velocity.x
	pan.advance(Vector2.ZERO,1./60)
	check(pan.velocity.x>0 and pan.velocity.x<speed,'Smooth release deceleration')
	for i in 90:pan.advance(Vector2.ZERO,1./60)
	check(pan.velocity==Vector2.ZERO,'Camera settles to rest')
	var a=Pan.new();var b=Pan.new();var da=Vector2.ZERO;var db=Vector2.ZERO
	for i in 30:da+=a.advance(Vector2.RIGHT,1./30)
	for i in 120:db+=b.advance(Vector2.RIGHT,1./120)
	check(da.distance_to(db)<.01,'Frame rate independent camera displacement')
	check(Pan.edge_direction(Vector2(-1,500),Vector2(1920,1080))==Vector2.ZERO,'Outside window does not pan')
	check(is_equal_approx(Pan.edge_direction(Vector2(1,1),Vector2(1920,1080)).length(),1.),'Corners do not accelerate diagonal speed')
	var wedge=Layout.offsets(21,'wedge',30.)
	var ranks={}
	for p in wedge:ranks[p.y]=ranks.get(p.y,0)+1
	check(ranks.values()==[1,2,3,4,5,6],'Filled triangle ranks, not hollow V')
	check(wedge[0]==Vector2.ZERO and wedge.back().y==150,'Apex forward, ranks behind')
	var spread=Layout.offsets(21,'scatter',30.)
	var min_gap=INF
	for i in spread.size():
		for j in range(i+1,spread.size()):min_gap=minf(min_gap,spread[i].distance_to(spread[j]))
	check(min_gap>=54.,'Scatter visibly separates all soldiers')
	var main=load('res://scenes/main.tscn').instantiate();main.settings_path='/tmp/formation-camera.cfg'
	root.add_child(main);main.sound.enabled=false
	for i in 4:await process_frame
	click(main.menu_view.get_node('%TacticalTrial').get_global_rect().get_center())
	for i in 4:await process_frame
	var t=main.active_trial;t.set_process(false)
	var r=t.rules;var ui=t.get_meta('strategy_interface');ui.set_process(false)
	var camera_before=t.camera_offset
	t.set_camera(camera_before+Vector2(.25,.25))
	check(t.camera_offset.distance_to(camera_before+Vector2(.25,.25))<.01,'Fractional camera movement survives low-speed acceleration')
	for camp in r.world.camps:camp.claimed=true
	for u in r.alive('enemy'):u.hp=0;u.soldiers[0].hp=0
	for building in r.buildings:
		if building.side=='enemy' and building.kind=='outpost':building.hp=0
	var ids=[]
	for i in 21:
		var u=r.spawn_person('shield','ally',Vector2(1300+(i%7)*36,1600+(i/7)*36))
		ids.append(Vector2i(u.id,0))
	t.soldier_ids=ids;t.selected='personal_route'
	ui.request_formation('wedge',Vector2.UP)
	check(ui.formation_panel.visible and ui.formation_label.text.begins_with('切换至楔形阵'),'Top notice shows requested formation')
	check(ui.formation_bar.value==0,'Progress starts at zero')
	for i in 150:r.step(1./60)
	ui.update_formation_notice(0.)
	check(absf(ui.formation_bar.value-50.)<.1,'Actual simulation progress reaches half at 2.5 seconds')
	t.paused=true;ui.update_formation_notice(1.)
	check(absf(ui.formation_bar.value-50.)<.1 and '暂停' in ui.formation_label.text,'Paused display does not invent progress')
	t.paused=false
	for i in 151:r.step(1./60)
	ui.update_formation_notice(0.)
	check(ui.formation_bar.value==100,'Five-second construction timer finishes')
	for i in 300:r.step(1./60)
	var members=r.Soldiers.members(r,ids)
	check(members.all(func(row):return row.actor.formation_ready and row.actor.position.distance_to(row.actor.form_goal)<21.),'All 21 live soldiers reach triangular slots')
	t.set_camera(r.projection*Vector2(1400,1750)-Vector2(960,530)/t.zoom)
	ui.update_formation_notice(0.);ui.show_commands()
	await snap('wedge',t)
	ui.request_formation('scatter',Vector2.UP)
	for i in 900:r.step(1./60)
	ui.update_formation_notice(0.)
	check(members.all(func(row):return row.actor.position.distance_to(row.actor.form_goal)<21.),'Soldiers physically spread out')
	await snap('scatter',t)
	var center=Vector2.ZERO
	for row in members:center+=row.unit.pos
	center/=members.size()
	for row in members:
		row.unit.pos+=Vector2(1350,1750)-center;row.actor.position=row.unit.pos
	ui.request_formation('ring',Vector2.UP)
	for i in 100:r.step(1./60)
	ui.update_formation_notice(0.)
	await snap('progress',t)
	var ring_plan=r.Layout.plan(r,members,Vector2(1350,1750),[],false)
	check(ring_plan.size()==21 and ring_plan[0].heading.dot(ring_plan[10].heading)<-.9,'Ring slots face outwards on opposite sides')
	r.Soldiers.command(r,ids,'hold',Vector2.ZERO)
	ui.update_formation_notice(0.)
	check(ui.formation_label.text=='阵型切换已中断','New order cancels the tracked transition')
	main.queue_free();await process_frame
	print('FORMATION CAMERA CHECKS=',checks,' FAILURES=',failures)
	quit(1 if failures else 0)
