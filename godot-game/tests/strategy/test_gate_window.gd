extends 'res://tests/strategy/test_contextual_ui.gd'
func run():
	var main=load('res://scenes/main.tscn').instantiate();main.settings_path='/tmp/gate-window.cfg';root.add_child(main);main.sound.enabled=false
	for i in 4:await process_frame
	click(main.menu_view.get_node('%TacticalTrial').get_global_rect().get_center())
	for i in 4:await process_frame
	var t=main.active_trial;t.set_process(false);var r=t.rules
	for camp in r.world.camps:camp.claimed=true
	for u in r.units:u.hp=0;u.soldiers[0].hp=0
	for b in r.buildings:
		if b.side=='enemy' and b.kind=='outpost':b.hp=0
	r.ai_training=-10000.;r.next_wave=10000.
	var ids=[]
	for i in 63:
		var u=r.spawn_person('shield','ally',Vector2(1120+(i%9)*42,2200+(i/9)*38));ids.append(Vector2i(u.id,0))
	t.soldier_ids=ids;t.selected='';t.set_camera(Vector2(1450,2100)-Vector2(960,530)/t.zoom)
	click(point(t,Vector2(1450,2030)),MOUSE_BUTTON_RIGHT)
	check(r.alive('ally').all(func(u):return not u.soldiers[0].path.is_empty()),'Real mouse group order accepted')
	for i in 600:r.step(1./60);r.events.clear()
	await snap('gate-transit',t)
	for i in 3000:r.step(1./60);r.events.clear()
	check(r.alive('ally').all(func(u):return u.pos.y<2060 and u.soldiers[0].path.is_empty()),'All 63 visible soldiers finish outside city')
	await snap('gate-arrived',t)
	print('GATE WINDOW CHECKS=',checks,' FAILURES=',failures)
	main.queue_free();await process_frame;quit(1 if failures else 0)
