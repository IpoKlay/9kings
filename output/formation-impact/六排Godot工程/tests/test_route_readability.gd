extends SceneTree
const OUT='res://../output/route-readability-v2/'
var app
var checks=0
var failures=0
func _init():call_deferred('run')
func check(ok,message):
	checks+=1
	if not ok:failures+=1;printerr('FAIL: '+message)
func capture(name):
	for i in 3:await process_frame;RenderingServer.force_draw()
	root.get_texture().get_image().save_png(OUT+name+'.png')
func click(control):
	var p=control.get_global_rect().get_center()
	Input.warp_mouse(root.get_final_transform()*p);await process_frame
	for down in [true,false]:
		var event=InputEventMouseButton.new();event.position=p;event.global_position=p;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;root.push_input(event,true)
	await process_frame
func setup_city(id):
	app.campaign.reset(23);app.expedition.reset(1)
	app.main_menu=false;app.has_run=true
	app.expedition.state.current=id;app.expedition.state.visited=[app.expedition.data.start,id]
	app.expedition.state.opening='done';app.expedition.state.mode='map'
	app.expedition_map.selected='';app.expedition_map.last_current='';app.render_ui()
func inspect_labels(node):
	for child in node.get_children():
		if child is Label:
			check(child.get_minimum_size().y<=child.size.y+.1,'All text lines visible: '+child.text)
			check(child.get_line_count()*child.get_line_height()<=child.size.y+2,'Shaped lines fit reading area: '+child.text)
			check(Rect2(Vector2.ZERO,node.size).encloses(child.get_rect()),'Text within its panel: '+child.text)
		inspect_labels(child)
func run():
	if DisplayServer.get_name()=='headless':quit(1);return
	root.size=Vector2i(1280,720)
	app=load('res://scenes/main.tscn').instantiate();app.settings_path='/private/tmp/eagle-route-readability.cfg';root.add_child(app)
	app.set_process(false);app.prefs.enabled=false;app.prefs.music_volume=0;app.apply_prefs()
	for lang in ['zh','en']:
		app.language=lang;app.world.language=lang
		app.restart_expedition(1);app.expedition_map.settle_entry()
		await capture('opening-'+lang)
		for source in app.expedition.march_choices:
			setup_city(source);await process_frame
			var map=app.expedition_map
			var brief=map.briefing_view
			var choices=app.expedition.destinations()
			check(brief.choice_buttons.size()==2,'Two choices visible at fork '+source)
			inspect_labels(brief)
			for id in choices:
				check(map.atlas.buttons[id].get_rect().end.x<1440,'Actionable city left of the scout slips '+id)
				check(map.atlas.names.any(func(l):return l.visible and l.name=='Name_'+id),'Actionable city has visible name '+id)
				check(map.atlas.branch_badges.has(id),'A/B labels connect the map to scout slips '+id)
			var local_lines=map.atlas.draw_routes.filter(func(r):return r.priority>=2)
			var remote_lines=map.atlas.draw_routes.filter(func(r):return r.priority==0)
			check(local_lines.size()==2 and remote_lines.all(func(r):return r.color.a<=.24),'Foreground choices dominate remote routes')
			await capture(source+'-'+lang)
			var before=app.expedition.state.duplicate(true)
			await click(brief.choice_buttons[choices[1]])
			check(map.selected==choices[1] and app.expedition.state==before,'Scout slip inspects without committing')
			check(not map.travel_button.disabled,'Inspected current choice can depart')
			check(not map.briefing_view.get_global_rect().intersects(map.info.get_global_rect()),'Scout comparison does not cover city intel')
			inspect_labels(map.info)
			await capture(source+'-selected-'+lang)
			await click(map.travel_button)
			preload('res://tests/expedition_test_support.gd').finish_departure(app)
			check(app.campaign.g.phase=='battle' and app.expedition.state.target==choices[1],'Selected route enters real battle')
			var roster=app.expedition.encounter(choices[1]).roster
			var actual=app.campaign.g.battle.units.filter(func(u):return u.side=='enemy').map(func(u):return u.type)
			for type in roster:check(actual.count(type)==roster.count(type),'Combat matches scout troops '+type)
			app.campaign.finish(false);app.expedition.settle();app.render_ui()
			check(not app.expedition.distances().has(choices[0]),'Unchosen branch darkens after failed committed attack')
			check(app.expedition_map.briefing_view.choice_buttons.size()==1,'Retry only advertises the committed route')
		# At the preceding city, scouting helps decide which reward to keep.
		setup_city('246349');await process_frame
		check(app.expedition.briefing().ahead,'Preceding city previews the next decision')
		var choice=app.expedition.briefing().choices[0]
		await click(app.expedition_map.briefing_view.choice_buttons[choice])
		check(app.expedition_map.travel_button.disabled,'Future route preview cannot skip a city')
		await capture('planning-ahead-'+lang)
		setup_city('265849')
		app.campaign.g.buildings.append({'id':9,'type':'spear','cell':7,'level':1})
		app.campaign.g.buildings.append({'id':10,'type':'cavalry','cell':8,'level':1})
		app.expedition_map.render();await process_frame
		check(app.expedition.response_cards('265823').owned.has('spear'),'Existing spearmen alter the advice')
		await capture('with-build-'+lang)
		app.expedition_map.atlas.overview();await capture('overview-'+lang)
		check(app.expedition_map.atlas.full_network,'Overview restores the broader network')
		app.expedition_map.render()
		check(app.expedition_map.atlas.full_network,'Overview survives a UI refresh')
	root.size=Vector2i(1920,1080);setup_city('265849');await capture('branch-native-1080')
	# Stationary overlays do not rebuild routes or advance gameplay each frame.
	var atlas=app.expedition_map.atlas
	var redraws=[0]
	atlas.draw.connect(func():redraws[0]+=1)
	var children=app.expedition_map.content.get_child_count()
	var rng=app.campaign.g.rng
	for i in 30:await process_frame
	check(redraws[0]<=1,'Stationary routes are cached, not redrawn each frame')
	check(children==app.expedition_map.content.get_child_count() and rng==app.campaign.g.rng,'Idle briefing adds no nodes or random draws')
	# Native combat evidence uses an explicit representative force, not a saved run.
	for target in ['265823','265762']:
		setup_city('265849')
		app.campaign.g.buildings=[{'id':1,'type':'legion','cell':8,'level':2},{'id':2,'type':'spear','cell':13,'level':2},{'id':3,'type':'guard','cell':18,'level':2},{'id':4,'type':'archer','cell':7,'level':2},{'id':5,'type':'siege','cell':6,'level':2},{'id':6,'type':'medic','cell':12,'level':2}]
		app.travel_to(target,false)
		for i in 150:app.campaign.step(.05)
		app.render_ui()
		await capture('combat-'+target)
	app.sound.stop();app.music.set_process(false)
	for i in 2:app.music.retire_slot(i)
	app.queue_free();await process_frame;await process_frame
	print('%d native route readability checks, %d failures'%[checks,failures]);quit(1 if failures else 0)
