extends SceneTree
const EnvironmentArt=preload('res://scripts/battle_environment.gd')
var app
var checks=0
var failures=0
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1;printerr('FAIL: '+message)
func _init(): call_deferred('run')
func capture(name: String):
	if DisplayServer.get_name()=='headless': return
	await process_frame
	RenderingServer.force_draw() # Deterministic capture even when the OS occludes this test window.
	root.get_texture().get_image().save_png('res://tests/wind-'+name+'.png')
func run():
	var env=EnvironmentArt.new()
	for act in [1,2,3]:
		var moved={}
		var opposite=false
		var bounded=true
		var visible_sway=false
		var rooted=true
		for step in 600:
			var left=0
			var right=0
			for tree in env.TREE_LAYOUTS[act-1].size():
				var sway=env.tree_sway(act,tree,.125,step*.2)
				if absf(sway)>=4.0: visible_sway=true
				bounded=bounded and absf(sway)<=4.0
				rooted=rooted and env.tree_sway(act,tree,.85,step*.2)==0
				if sway<0: left+=1
				if sway>0: right+=1
				if sway!=0: moved[tree]=true
			if left>0 and right>0: opposite=true
		check(moved.size()==12,'All twelve tree canopies move over time, theater '+str(act))
		check(visible_sway,'Canopy reaches a perceptible two-pixel sway')
		check(opposite,'Trees can move in opposite directions at the same time')
		check(bounded and rooted,'Sway stays within two native pixels and trunk stays fixed')
	app=load('res://scenes/main.tscn').instantiate()
	root.add_child(app);current_scene=app;app.set_process(false)
	app.sound.enabled=false;app.language='zh';app.start_rng.seed=62
	var rolls={1:0,2:0,3:0}
	for batch in 20:
		var set_seen={}
		for i in 3:
			var act=app.draw_starting_theater()
			set_seen[act]=true;rolls[act]+=1
		check(set_seen.size()==3,'Each batch contains all three starting maps')
	check(rolls[1]==20 and rolls[2]==20 and rolls[3]==20,'The third map is not starved by repeated draws')
	var seen={}
	var hashes={}
	for i in 3:
		app.start_game()
		var act=app.expedition.stage_order[0]
		seen[act]=true
		check(app.world.environment_act==act,'Start Game activates drawn background')
		var texture=app.world.tex(EnvironmentArt.BACKGROUNDS[act-1])
		check(texture!=null and texture.get_width()>0,'Theater texture loads')
		hashes[hash(texture.get_image().get_data())]=true
		check(app.ui.get_node('TheaterName').text==app.theater_name(act),'Camp identifies its theater')
		app.travel_to(app.expedition.destinations()[0])
		app.world.environment.clock=2.0
		app.world.queue_redraw()
		await capture('camp-'+str(act))
		preload('res://tests/expedition_test_support.gd').deploy(app)
		check(app.campaign.g.phase=='battle' and app.world.environment_act==act,'Native battle keeps correct theater')
		for step in 240: app._process(1.0/60)
		await capture('battle-'+str(act))
		app.world.environment.clock+=7.0;app.world.queue_redraw()
		await capture('wind-later-'+str(act))
		var state=app.campaign.g.duplicate(true)
		app.world.tick_environment(.1)
		check(app.campaign.g==state,'Scenery never changes combat or card state')
		app.return_to_menu()
	check(seen.size()==3 and hashes.size()==3,'Three successive starts render three distinct backgrounds')
	app.language='en';app.render_ui()
	await capture('menu-en')
	app.sound.stop()
	print('%d theater/wind checks, %d failures'%[checks,failures])
	quit(1 if failures else 0)
