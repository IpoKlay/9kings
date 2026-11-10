extends 'res://tests/strategy/test_contextual_ui.gd'
func run():
	var main=load('res://scenes/main.tscn').instantiate();main.settings_path='/tmp/expansion-ui.cfg';root.add_child(main);main.sound.enabled=false
	for i in 4:await process_frame
	click(main.menu_view.get_node('%TacticalTrial').get_global_rect().get_center())
	for i in 4:await process_frame
	var t=main.active_trial;t.set_process(false)
	var r=t.rules;var ui=t.get_meta('strategy_interface')
	check(r.population()==9,'Normal menu starts expanded opening')
	await snap('new-opening',t)
	var b=r.buildings[1]
	click(point(t,b.pos));await process_frame
	check(ui.selected_building==b.id and ui.actions.has('train:shield'),'Building selection produces appropriate units')
	var rally=Vector2(1600,2250)
	click(point(t,rally),MOUSE_BUTTON_RIGHT);await process_frame
	check(b.has('rally') and b.rally.distance_to(rally)<2.,'Real right click sets rally')
	await snap('rally',t)
	var count=r.units.size()
	click(ui.actions['train:shield'].get_global_rect().get_center());await process_frame
	check(r.units.size()==count+1,'Real icon click produces immediately')
	var unit=r.units.back()
	check(unit.soldiers[0].personal_order=='move','Recruited soldier follows rally')
	click(point(t,unit.pos)-Vector2(0,20));await process_frame
	check('伤害' in ui.detail.text and '近甲' in ui.detail.text and '攻击间隔' in ui.detail.text and '指令' in ui.detail.text,'Individual numeric and order panel')
	await snap('unit-stats',t)
	var ids=r.alive('ally').filter(func(u):return u.unit_type in ['shield','spear']).map(func(u):return Vector2i(u.id,0))
	t.soldier_ids=ids;t.squad_ids.clear()
	check(r.Soldiers.command(r,ids,'move',Vector2(1580,2250)),'Multi-unit move creates teams')
	check(ui.order_representatives().size()==2,'One order marker per selected same-type team')
	var actor=unit.soldiers[0];actor.velocity=Vector2.ZERO
	r.step(1./60)
	var first: float=actor.velocity.length()
	for i in 15:r.step(1./60)
	check(first>0 and actor.velocity.length()>first*2,'Soldier accelerates over multiple frames')
	await process_frame;await snap('orders',t)
	check(r.Soldiers.command(r,ids,'attack_move',Vector2(1570,2300)),'Attack move accepted')
	check(ui.order_representatives().all(func(row):return r.current_order(row.unit).attack),'Attack movement uses red markers')
	await process_frame;await snap('attack-orders',t)
	key(KEY_ESCAPE);await process_frame
	check(not ui.panel.visible and ui.order_representatives().is_empty(),'Escape removes selection and instruction markers')
	# The remembered building remains a snapshot, while live enemies disappear from targeting.
	var enemy=r.alive('enemy')[0]
	var scout=r.alive('ally')[0];var old: Vector2=scout.pos
	scout.pos=enemy.pos+Vector2(40,0);scout.soldiers[0].position=scout.pos;r.world.refresh_sight(r)
	check(r.unit_visible(enemy),'Enemy visible when scouted')
	scout.pos=old;scout.soldiers[0].position=old;r.world.refresh_sight(r)
	check(not r.unit_visible(enemy) and not r.can_detect(scout,enemy),'Enemy hidden and untargetable after sight lost')
	t.toggle_overview();await snap('fog-overview',t)
	# Normal simulation advances with neutral camps and hostile wolves, without legacy director orders.
	for i in 180:r.step(1./60)
	check(not r.enemy_director.active and r.phase=='battle','Neutral encounters coexist with economy AI')
	t.toggle_overview()
	click(point(t,r.buildings[0].pos));await process_frame
	check(ui.actions.has('research:town_upgrade'),'Town selection exposes upgrade technology')
	click(ui.actions['research:town_upgrade'].get_global_rect().get_center())
	r.advance_economy(20.);await process_frame
	check(r.town_level==2 and '城镇 2 级' in ui.detail.text,'Actual town upgrade button completes level 2')
	await snap('town-upgrade',t)
	main.queue_free();await process_frame
	print('EXPANSION UI CHECKS=',checks,' FAILURES=',failures)
	quit(1 if failures else 0)
