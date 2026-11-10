extends SceneTree
const Strategy=preload("res://scripts/strategy/battle.gd")
## Normal menu -> economy match; automated player orders, normal visible real-time loop.
var out='res://../output/combat-readability-20261109/normal-match/'
var failures=0
func _initialize():call_deferred('run')
func check(ok: bool,note: String):
	if not ok:failures+=1;push_error(note)
func shot(label: String):
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out+label+'.png')
func run():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	Engine.max_fps=60
	var app=load('res://scenes/main.tscn').instantiate();app.settings_path='/tmp/eagle-readability-match.cfg';root.add_child(app)
	await shot('menu')
	var launched=Time.get_ticks_usec()
	app.menu_view.get_node('%TacticalTrial').pressed.emit()
	var t=app.active_trial;var r=t.rules
	await shot('economy-opening')
	var load_seconds=(Time.get_ticks_usec()-launched)/1000000.
	check(r is Strategy and r.population()==6,'Normal menu preserves the six-villager economy opening')
	var panel=t.get_meta('strategy_interface')
	var feedback=[]
	for expected in [true,false]:
		var sent=Time.get_ticks_usec()
		for down in [true,false]:
			var event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
			event.position=panel.pause_button.get_global_rect().get_center();event.global_position=event.position
			root.push_input(event,true)
		await process_frame;await RenderingServer.frame_post_draw
		feedback.append((Time.get_ticks_usec()-sent)/1000.)
		check(t.paused==expected,'Pause/resume responds to mouse event through actual UI')
	check(feedback.max()<=100.,'Input-to-present feedback <=100ms')
	var next_order=0.;var snapshot=120.;var history=[];var peak=0;var start=Time.get_ticks_usec()
	var town=r.buildings.filter(func(b):return b.side=='enemy' and b.kind=='town')[0]
	while r.phase=='battle' and r.elapsed<600.:
		if r.elapsed>=next_order:
			next_order=r.elapsed+2.
			var villagers=r.alive('ally').filter(func(u):return u.unit_type=='villager')
			for u in villagers:
				if u.soldiers[0].has('job'):continue
				var resource=[1,0,8][u.id%3]
				if r.resources[resource].remaining<=0:resource=2 if resource==1 else 9 if resource==0 else 8
				r.gathering([Vector2i(u.id,0)],resource)
			if villagers.size()<9 and r.buildings[0].queue.is_empty():r.train('villager',0)
			if r.elapsed>45 and r.level<3 and r.research_queue.is_empty():r.research('promotion',1)
			if r.population()<80 and r.buildings[1].queue.size()<2:r.train('shield' if int(r.elapsed)%6 else 'spear',1)
			if r.population()>r.population_cap()-8 and not villagers.is_empty() and not r.buildings.any(func(b):return b.kind=='house' and b.remaining>0):
				r.build('house',Vector2(1800+(r.population_cap()-40)*5,2790),[Vector2i(villagers[0].id,0)])
			if r.elapsed>160:
				var ids=r.alive('ally').filter(func(u):return u.unit_type in ['shield','spear']).map(func(u):return Vector2i(u.id,0))
				if not ids.is_empty():r.assault_building(ids,town)
		peak=maxi(peak,r.alive('ally').size()+r.alive('enemy').size())
		if r.elapsed>=snapshot:
			history.append({'seconds':r.elapsed,'ally':r.population(),'enemy':r.alive('enemy').size(),'town_hp':town.hp})
			print('MATCH PROGRESS ',JSON.stringify(history.back()))
			await shot('match-'+str(int(snapshot)));snapshot+=120.
		await process_frame
	check(r.phase in ['victory','defeat'],'Normal game naturally reaches a result')
	await shot('result')
	var report={'phase':r.phase,'seconds':r.elapsed,'wall_seconds':(Time.get_ticks_usec()-start)/1000000.,'peak_soldiers':peak,'entry_seconds':load_seconds,'pause_feedback_ms':feedback,'history':history,'input':'Scripted normal menu button and player command APIs; no forced simulation stepping','siege':'No siege units created; only pre-existing infantry town attack used to reach existing victory condition'}
	var ui=t.get_meta('strategy_interface')
	var retry_button=ui.result_panel.get_child(0).get_child(1)
	retry_button.pressed.emit();await process_frame
	check(t.rules is Strategy and t.rules.population()==6 and t.rules.elapsed<.1,'Visible result retry rebuilds clean economy opening')
	check(t.rules.shield_walls.is_empty() and t.rules.casualties.is_empty() and t.field.effects.is_empty(),'No wall, casualty or impact feedback survives retry')
	check(t.rules.units.all(func(u):return u.soldiers.all(func(a):return not a.has('charge_run') and not a.has('gap_until'))),'No local charge state survives retry')
	await shot('retry')
	report.failures=failures
	FileAccess.open(out+'report.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
	print('NORMAL MATCH ',JSON.stringify(report))
	t.closed.emit();await process_frame;app.queue_free();await process_frame;await process_frame
	quit(1 if failures else 0)
