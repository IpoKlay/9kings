extends SceneTree
var failures=0
var checks=0
func check(ok: bool,note: String):
	checks+=1
	if not ok:failures+=1;push_error(note)
func _initialize():call_deferred('run')
func click(p: Vector2,button=MOUSE_BUTTON_LEFT):
	for down in [true,false]:
		var e=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=button;e.pressed=down;root.push_input(e,true)
func key(code: int):
	var e=InputEventKey.new();e.physical_keycode=code;e.keycode=code;e.pressed=true;root.push_input(e,true)
func point(t,p: Vector2) -> Vector2:return (t.field.project(p)-t.camera_offset)*t.zoom
func snap(name: String,t):
	if DisplayServer.get_name()=='headless':return
	t.field.queue_redraw();t.field.pass_layout.queue_redraw()
	for i in 2:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png('/tmp/contextual-'+name+'.png')
func run():
	var main=load('res://scenes/main.tscn').instantiate();main.settings_path='/tmp/contextual-ui.cfg'
	root.add_child(main);main.sound.enabled=false
	for i in 4:await process_frame
	click(main.menu_view.get_node('%TacticalTrial').get_global_rect().get_center())
	for i in 4:await process_frame
	var t=main.active_trial;t.set_process(false)
	var r=t.rules;var ui=t.get_meta('strategy_interface')
	check(r.phase=='battle','Game starts immediately')
	check(r.alive('ally').size()==9 and r.alive('ally').filter(func(u):return u.unit_type=='villager').size()==5,'Walled test opening')
	check(not t.get_node('BattleHUD').is_visible_in_tree(),'All old battle controls hidden')
	check(not ui.panel.visible and t.selected_people().is_empty(),'Opening has no command panel or selection')
	await snap('opening',t)
	var villager=r.alive('ally')[0]
	click(point(t,villager.pos)-Vector2(0,20))
	await process_frame
	check(t.soldier_ids==[Vector2i(villager.id,0)],'Real mouse selects one villager')
	check(ui.panel.visible and ui.actions.has('build:barracks') and not ui.actions.has('train:spear'),'Villager exposes build icons only')
	await snap('villager',t)
	var fruit=r.resources[0]
	click(point(t,fruit.pos),MOUSE_BUTTON_RIGHT)
	check(villager.soldiers[0].get('job',{}).get('kind','')=='gather','Right click dispatches gathering')
	var before: float=r.stock.iron
	for i in 1800:r.step(1./60)
	check(r.stock.iron>before,'Villager travels and gathers iron')
	key(KEY_ESCAPE);await process_frame
	check(not ui.panel.visible and t.selected_people().is_empty() and ui.mode=='','Esc clears every command surface')
	check(not t.paused and villager.soldiers[0].has('job'),'Esc does not pause or cancel committed work')
	key(KEY_ESCAPE);check(not t.paused,'Repeated Esc does not toggle pause')
	var town=r.buildings[0]
	click(point(t,town.pos));await process_frame
	check(ui.selected_building==town.id and ui.actions.has('train:villager'),'Town click shows villager production')
	check(not ui.actions.has('build:house') and not ui.actions.has('train:spear'),'Town does not expose global construction or other production')
	click(ui.actions['train:villager'].get_global_rect().get_center())
	check(town.queue.size()==1,'Mouse icon queues villager in selected town')
	key(KEY_ESCAPE);await process_frame
	check(town.queue.size()==1 and not ui.panel.visible,'Esc leaves queued production running')
	var n=r.units.size()
	for i in 600:r.step(1./60)
	check(r.units.size()>n,'Queued villager actually appears')
	var barracks=r.buildings[1]
	click(point(t,barracks.pos));await process_frame
	check(ui.selected_building==barracks.id and ui.actions.has('train:spear'),'Barracks shows military production')
	check(not ui.actions.has('train:villager') and not ui.actions.has('build:house'),'Barracks replaces build bar')
	r.stock.food=200
	click(ui.actions['train:spear'].get_global_rect().get_center())
	check(barracks.queue.is_empty() and town.queue.is_empty() and r.units.back().unit_type=='spear','Instant production stays in clicked building')
	await process_frame;await snap('barracks',t)
	key(KEY_ESCAPE)
	click(point(t,villager.pos)-Vector2(0,20));await process_frame
	check(ui.actions.has('build:house'),'Re-select villager restores build bar')
	click(ui.actions['build:house'].get_global_rect().get_center())
	check(ui.mode=='build','Building icon enters placement mode')
	var wood: float=r.stock.wood;var count=r.buildings.size()
	key(KEY_ESCAPE);click(point(t,Vector2(1330,2750)))
	check(r.buildings.size()==count and r.stock.wood==wood,'Escape cancels placement without spending resources')
	click(point(t,villager.pos)-Vector2(0,20));await process_frame
	click(ui.actions['build:house'].get_global_rect().get_center())
	click(point(t,Vector2(1330,2750)))
	check(r.buildings.size()==count+1 and is_equal_approx(r.stock.wood,wood-35),'Villager places house and pays once')
	var house=r.buildings.back()
	for i in 1800:r.step(1./60)
	check(house.remaining==0. and r.population_cap()==70,'Villager travels and completes house')
	click(point(t,barracks.pos));await process_frame
	barracks.hp=0;await process_frame
	check(not ui.panel.visible and ui.selected_building==-1,'Destroyed selection closes stale production bar')
	t.retry();await process_frame
	check(t.rules.phase=='battle' and t.rules.population()==9 and not ui.panel.visible,'Retry resets into immediate economy opening')
	check(t.rules.stock.food==10000 and t.rules.stock.wood==10000,'Retry resets economy')
	await snap('cleared',t)
	print('CONTEXTUAL UI CHECKS=',checks,' FAILURES=',failures)
	await main.prepare_shutdown()
	t.queue_free();main.queue_free();await process_frame;quit(1 if failures else 0)
