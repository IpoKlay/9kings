extends 'res://tests/strategy/test_contextual_ui.gd'
func run():
	var main=load('res://scenes/main.tscn').instantiate();main.settings_path='/tmp/octagon-ui.cfg';root.add_child(main);main.sound.enabled=false
	for i in 4:await process_frame
	click(main.menu_view.get_node('%TacticalTrial').get_global_rect().get_center())
	for i in 4:await process_frame
	var t=main.active_trial;t.set_process(false);var r=t.rules;var ui=t.get_meta('strategy_interface')
	var vertices=r.world.wall_vertices();var side: float=vertices[0].distance_to(vertices[1])
	check(vertices.size()==8,'Eight wall vertices')
	for i in 8:
		check(is_equal_approx(vertices[i].distance_to(vertices[(i+1)%8]),side),'Octagon has equal edge lengths')
		var tangent: Vector2=vertices[i].direction_to(vertices[(i+1)%8])
		var next: Vector2=vertices[(i+1)%8].direction_to(vertices[(i+2)%8])
		check(is_equal_approx(tangent.dot(next),sqrt(.5)),'Octagon turns by 45 degrees')
	var worker=r.alive('ally')[0];var nav=r.Soldiers.navigator(r,worker.kind,worker)
	var gates=r.buildings.filter(func(b):return b.get('initial_wall',false) and b.kind=='gate')
	check(gates.size()==4 and gates.all(func(b):return b.open),'Four cardinal gates open at start')
	for gate in gates:
		var normal: Vector2=r.world.CENTER.direction_to(gate.pos)
		check(r.terrain.clear_segment(nav,gate.pos-normal*80,gate.pos+normal*80),'Gate corridor is open')
		gate.open=false;r.rebuild_obstacles()
		check(not r.terrain.clear_segment(nav,gate.pos-normal*80,gate.pos+normal*80),'Closed gate blocks the same corridor')
		gate.open=true;r.rebuild_obstacles()
	for i in [1,3,5,7]:
		var middle: Vector2=(vertices[i]+vertices[(i+1)%8])*.5
		var normal: Vector2=r.world.CENTER.direction_to(middle)
		check(not r.terrain.clear_segment(nav,middle-normal*80,middle+normal*80),'Diagonal walls block crossings')
		check(r.world.ring(middle-normal*50)==1 and r.world.ring(middle+normal*50)==2,'Inner resource ring matches diagonal wall')
	check(r.resources.filter(func(v):return v.kind=='tree' and v.ring==1).size()==9,'Opening forest stays inside octagon')
	# Cross-type and lateral team gaps are both halved without changing soldier spacing.
	var army=[]
	for i in 42:
		var u=r.spawn_person('shield','ally',Vector2(1500+(i%7)*36,1300+(i/7)*36));army.append(Vector2i(u.id,0))
	for i in 21:
		var u=r.spawn_person('spear','ally',Vector2(1500+(i%7)*36,1560+(i/7)*36));army.append(Vector2i(u.id,0))
	var selection=r.Soldiers.members(r,army);var plans=r.Layout.plan(r,selection,Vector2(1500,750),[],false)
	check(plans.size()==63,'Mixed army receives exact formation slots')
	if plans.size()==63:
		var forward: Vector2=plans[0].heading;var lateral=forward.orthogonal();var origin: Vector2=plans[0].path.back()
		check(is_equal_approx(absf((plans[21].path.back()-origin).dot(lateral)),6.*36.+45.),'Side-by-side teams have 45 gap')
		check(is_equal_approx(absf((plans[42].path.back()-origin).dot(forward)),2.*36.+45.),'Different unit types have 45 gap')
	for id in army:r.units[id.x].hp=0;r.units[id.x].soldiers[0].hp=0
	t.toggle_overview();await snap('octagon-overview',t);t.toggle_overview()
	var soldier=r.alive('ally').filter(func(u):return u.unit_type=='shield')[0]
	soldier.pos=Vector2(1600,2180);soldier.soldiers[0].position=soldier.pos
	soldier.soldiers[0].hp=50.;r.Soldiers.total(soldier)
	click(point(t,soldier.pos)-Vector2(0,20));await process_frame;await process_frame
	check(ui.health_label.text=='生命 50 / 100' and ui.health_bar.value==50. and ui.health_bar.max_value==100.,'Health meter beside numeric label tracks wounded soldier')
	await snap('health-meter',t)
	soldier.soldiers[0].hp=75.;r.Soldiers.total(soldier);await process_frame;await process_frame
	check(ui.health_bar.value==75.,'Health meter updates without reselecting')
	key(KEY_ESCAPE);click(point(t,worker.pos)-Vector2(0,20));await process_frame;await process_frame
	for i in 3:await process_frame
	click(ui.actions['build:house'].get_global_rect().get_center());await process_frame;await process_frame
	click(point(t,Vector2(1330,2750)))
	var house=r.buildings.back()
	if house.kind!='house' or house.remaining<=0:quit(1);return
	check(house.kind=='house' and house.remaining>0,'Real build icon places unfinished house')
	var workers=r.alive('ally').filter(func(u):return u.unit_type=='villager').slice(0,2)
	for i in 2:
		var u=workers[i];u.pos=house.pos+Vector2(-65+i*130,0);u.soldiers[0].position=u.pos;u.soldiers[0].path=[];u.soldiers[0].job={'kind':'build','id':house.id}
	var total: float=house.remaining
	r.advance_economy(total/4.)
	click(point(t,house.pos));await process_frame;await process_frame
	check(ui.construction_bar!=null and is_equal_approx(ui.construction_bar.value,50.),'Two workers advance shared construction to half')
	check('秒' not in ui.detail.text and '施工中' in ui.detail.text,'Construction shows progress without misleading countdown')
	await snap('construction-meter',t)
	r.advance_economy(total/4.);await process_frame;await process_frame
	check(house.remaining==0 and ui.construction_bar==null and r.population_cap()==70,'Completion removes construction meter and enables building')
	await snap('construction-complete',t)
	var farm=r.add_building('farm',Vector2(1400,2870))
	for u in workers:u.pos=farm.pos+Vector2(60,0);u.soldiers[0].job={'kind':'build','id':farm.id}
	r.advance_economy(20.)
	check(r.resources.filter(func(v):return v.get('building',-1)==farm.id).size()==1,'Multiple builders create only one farm harvest node')
	var fog=ui.fog_texture.get_image();var light=0.;var dark=1.
	for x in range(0,256,8):
		for y in range(0,256,8):
			var color=fog.get_pixel(x,y);light=maxf(light,color.r);dark=minf(dark,color.r)
	check(dark>.1 and light-dark>.03,'Unknown fog uses dark gray cloud variation, not black')
	check(fog.get_pixel(10,10).a==1.,'Unexplored fog remains opaque')
	key(KEY_ESCAPE);worker.pos=Vector2(700,1500);worker.soldiers[0].position=worker.pos;r.world.refresh_sight(r)
	worker.pos=r.world.CENTER;worker.soldiers[0].position=worker.pos;r.world.refresh_sight(r)
	t.toggle_overview();await snap('cloud-fog',t)
	print('OCTAGON PRESENTATION CHECKS=',checks,' FAILURES=',failures)
	main.queue_free();await process_frame;await process_frame;quit(1 if failures else 0)
