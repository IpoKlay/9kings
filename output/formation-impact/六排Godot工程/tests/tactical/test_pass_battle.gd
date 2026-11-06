extends SceneTree
var failed=0
var t
func _initialize():call_deferred('run')
func check(ok: bool,message: String):
	if not ok:
		failed+=1
		push_error(message)
func click(p: Vector2,index=MOUSE_BUTTON_LEFT):
	for down in [true,false]:
		var e=InputEventMouseButton.new()
		e.position=p
		e.global_position=p
		e.button_index=index
		e.pressed=down
		root.push_input(e,true)
	await process_frame
	await process_frame
func screen(p: Vector2) -> Vector2:
	return (t.field.project(p)-t.camera_offset)*t.zoom
func snap(name: String):
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png('res://../output/pass-battle/'+name+'.png')
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path('res://../output/pass-battle'))
	create_timer(40).timeout.connect(func():push_error('TIMEOUT');quit(1))
	var main=load('res://scenes/main.tscn').instantiate()
	main.run_path_override='user://pass-test-absent.cfg'
	root.add_child(main)
	await process_frame
	main.language='zh'
	await click(main.menu_view.get_node('TacticalTrial').get_global_rect().get_center())
	t=root.get_child(-1)
	var r=t.rules
	await click(t.defender_button.get_global_rect().get_center())
	check(r.alive('ally').size()==7 and r.alive('enemy').size()==8,'Asymmetric deployment')
	await click(t.roster[1].get_global_rect().get_center())
	check(t.squad_ids==[1],'Roster selects commander')
	var barrel=r.barrels[0]
	await click(screen(barrel.pos),MOUSE_BUTTON_RIGHT)
	await click(screen(Vector2(1110,505)))
	check(barrel.pos.distance_to(Vector2(1110,505))<2,'Place oil before battle')
	await snap('deployment')
	await click(t.start_button.get_global_rect().get_center())
	check(r.phase=='battle','Start')
	await click(t.pace_button.get_global_rect().get_center())
	check(t.slow,'Tactical speed')
	for i in 1000:
		r.step(1./60)
		r.events.clear()
		if r.alive('enemy').any(func(u):return u.pos.distance_to(barrel.pos)<130):break
	await click(screen(barrel.pos),MOUSE_BUTTON_RIGHT)
	check(barrel.state=='arrow','Archers fire at oil')
	var attackers=r.alive('enemy')
	attackers.sort_custom(func(a,b):return a.pos.distance_to(barrel.pos)<b.pos.distance_to(barrel.pos))
	var victim=attackers[0]
	var hp: float=victim.hp
	for i in 60:
		r.step(1./60)
		r.events.clear()
	check(barrel.state=='burn' and victim.hp<hp,'Burn causes damage')
	await snap('engagement')
	await click(t.assault_button.get_global_rect().get_center())
	check(r.alive('ally').all(func(u):return u.order=='auto'),'General attack')
	for i in 10805:
		if r.phase!='battle':break
		r.step(1./60)
		r.events.clear()
	check(r.phase in ['victory','defeat','timeout'] and int(r.routed.ally+r.routed.enemy)>0,'Terminal state and morale')
	t.refresh()
	await click(t.start_button.get_global_rect().get_center())
	check(t.rules.phase=='deploy' and t.rules.barrels[0].state=='ready' and not t.slow,'Replay resets scenario')
	await click(t.combined_button.get_global_rect().get_center())
	check(t.rules.alive('ally').size()==7 and t.rules.barrels.size()==2,'Seven arms share the pass battlefield')
	await click(t.start_button.get_global_rect().get_center())
	await click(t.buttons.lightning.get_global_rect().get_center())
	await click(screen(t.rules.alive('enemy')[0].pos))
	check(t.selected=='lightning' and t.rules.alive('enemy')[0].hp<t.rules.alive('enemy')[0].max_hp,'Power cast in unified battle')
	await click(screen(Vector2(700,600)),MOUSE_BUTTON_RIGHT)
	t.paused=true
	var squad=t.rules.alive('ally')[0]
	await click(screen(squad.pos)-Vector2(0,35)*t.zoom)
	check(t.selected=='route' and t.squad_ids==[squad.id],'Select a regiment at pass camera zoom')
	var goal=Vector2(420,560)
	await click(screen(goal))
	check(squad.order=='move' and squad.destination.distance_to(goal)<1,'Left click sets pass regiment destination')
	t.paused=false
	t.closed.emit()
	await process_frame
	check(main.visible,'Return to menu')
	main.queue_free()
	await create_timer(.3).timeout
	print('PASS BATTLE native input and complete combat: ',failed,' failures')
	quit(1 if failed else 0)
