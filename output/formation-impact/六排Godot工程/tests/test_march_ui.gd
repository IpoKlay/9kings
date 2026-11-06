extends SceneTree
const OUT='res://../output/route-branches-v1/'
var app
var checks=0
var failures=0
func _init():call_deferred('run')
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;printerr('FAIL: '+message)
func capture(name):
	for i in 4:await process_frame;RenderingServer.force_draw()
	root.get_texture().get_image().save_png(OUT+name+'.png')
func click(control):
	var p=control.get_global_rect().get_center()
	Input.warp_mouse(root.get_final_transform()*p);await process_frame
	var motion=InputEventMouseMotion.new();motion.position=p;motion.global_position=p;root.push_input(motion,true)
	for down in [true,false]:
		var event=InputEventMouseButton.new();event.position=p;event.global_position=p;event.pressed=down;event.button_index=MOUSE_BUTTON_LEFT;root.push_input(event,true)
	await process_frame
func setup_fork(source: String):
	app.campaign.reset(23);app.expedition.reset(1)
	app.main_menu=false;app.has_run=true
	app.expedition.state.current=source;app.expedition.state.visited=[app.expedition.data.start,source]
	app.expedition.state.opening='done';app.expedition.state.mode='map'
	app.expedition_map.selected='';app.expedition_map.last_current='';app.render_ui()
	app.expedition_map.atlas.focus_frontier()
func run():
	if DisplayServer.get_name()=='headless':printerr('Native renderer required');quit(1);return
	root.size=Vector2i(1280,720)
	app=load('res://scenes/main.tscn').instantiate();app.settings_path='/private/tmp/eagle-route-branches.cfg';root.add_child(app)
	app.set_process(false);app.prefs.enabled=false;app.prefs.music_volume=0;app.apply_prefs()
	app.starting_theaters.assign([1]);app.start_game();app.expedition_map.settle_entry()
	await capture('01-first-destination')
	for lang in ['zh','en']:
		app.language=lang;app.world.language=lang
		for source in app.expedition.march_choices:
			setup_fork(source);await process_frame
			var map=app.expedition_map;var atlas=map.atlas
			var choices=app.expedition.destinations();var visible_names=[]
			for nameplate in atlas.names:
				if nameplate.visible:visible_names.append(String(nameplate.name).trim_prefix('Name_'))
			check(choices.all(func(id):return id in visible_names),'Both branch names readable '+source+' '+lang)
			check(atlas.draw_routes.filter(func(r):return r.priority==2).size()==2,'Both next branches receive gold paths')
			check(map.content.get_node('RouteHint').text.contains(app.expedition.node_text(app.expedition.march_choices[source].merge)),'Merge city named in route hint')
			await capture(source+'-fork-'+lang)
			await click(map.city_buttons[choices[1]])
			check(map.selected==choices[1] and not map.travel_button.disabled,'Actual city click opens the chosen branch')
			check(map.atlas.draw_routes.filter(func(r):return r.priority==3).size()==2,'Choice preview reaches merge')
			check(map.info.get_node('CitySubtitle').text.contains(app.expedition.choice_text(choices[1])),'Intel names the local approach')
			await capture(source+'-selected-'+lang)
			await click(map.travel_button)
			preload('res://tests/expedition_test_support.gd').finish_departure(app)
			check(app.campaign.g.phase=='battle' and app.expedition.state.target==choices[1],'Branch selection enters native combat')
			app.campaign.finish(true);app.advance();app.skip_supply();app.continue_expedition();map.atlas.focus_frontier()
			check(not app.expedition.can_travel(choices[0]),'Sibling cannot be revisited')
			var key=choices[0]+'>'+app.expedition.march_choices[source].merge
			var abandoned=map.atlas.draw_routes.filter(func(r):return r.key==key)[0]
			check(abandoned.color.a<.2,'Abandoned path stays dim even when its merge is reachable')
			await capture(source+'-chosen-'+lang)
	# Looking at another theater never moves the army or bypasses geography.
	var before=app.expedition.state.duplicate(true)
	app.expedition_map.show_act(1)
	check(app.expedition.state==before,'Theater preview is camera-only')
	check(app.expedition_map.content.get_node('RouteHint').text.contains('preview'),'Future theater explains preview-only navigation')
	app.expedition_map.atlas.overview();await capture('overview-en')
	# All sixteen outer plots are visible options, including corners.
	app.campaign.reset(23);app.expedition.reset(1);app.expedition.state.opening='done';app.expedition.state.mode='camp'
	app.campaign.g.expansion_credits=1;app.language='zh';app.world.language='zh';app.render_ui();app.begin_camp_expansion()
	check(app.campaign.expansion_candidates().size()==16,'All sixteen border choices present')
	await capture('16-outer-plots')
	var corner=app.world.center(0);var pointer=app.world.project(corner.x,corner.y)
	Input.warp_mouse(root.get_final_transform()*pointer);await process_frame
	for down in [true,false]:
		var event=InputEventMouseButton.new();event.position=pointer;event.global_position=pointer;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;root.push_input(event,true)
	await process_frame
	check(app.campaign.is_unlocked(0) and app.campaign.g.expansion_credits==0,'Corner plot is immediately selectable')
	app.sound.stop();app.music.set_process(false)
	for i in 2:app.music.retire_slot(i)
	await create_timer(.1).timeout;app.queue_free();await process_frame;await process_frame
	print('%d native branch UI checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
